class_name JamServer
extends Node
## A [Node] that provides server-specific multiplayer capabilities as the child
## of a [JamConnect] Node

const MAX_CLIENTS: int = 100
const DEFAULT_PORT: int = 7437

## A dictionary mapping peer id [code]int[/code]s to username [code]String[/code]s
var peer_usernames := {}

## True if the server is in developer mode. In developer mode, the clients are
## not verified and dummy API implementations are used instead of the AWS-driven
## implementations.
var dev_mode: bool = false

## True if the local dev mode server has keys for accessing server APIs like
## Data and Callback 
var has_dev_keys: bool = false

## A callback API client for communicating back to Jam Launch
var callback_api: JamCallbackApi

## A data API client for persisting project information
var data_api: JamDataApi
var session_id: String = "unset":
	set(v):
		session_id = v
		if callback_api:
			callback_api.session_id = v

var _jc: JamConnect:
	get:
		return get_parent()

func _ready() -> void:
	session_id = OS.get_environment("SESSION_ID")
	callback_api = JamCallbackApi.new()
	add_child(callback_api)
	
	data_api = JamDataApi.new()
	add_child(data_api)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		printerr("server got quit notification")
		shut_down()


## Configures and starts server functionality
func server_start(args: Dictionary) -> void:
	print("Starting as server...")
	
	data_api.project_id = _jc.get_project_id()
	
	_jc.m.auth_callback = _auth_callback
	
	var listen_port: int = DEFAULT_PORT
	if "port" in args:
		listen_port = (args["port"] as String).to_int()
	
	dev_mode = "dev" in args and args["dev"]
	
	var peer: MultiplayerPeer
	var err: Error
	if _jc.network_mode == "websocket":
		peer = WebSocketMultiplayerPeer.new()
		var key: CryptoKey
		var cert: X509Certificate
		if OS.is_debug_build() or dev_mode:
			var crypto: Crypto = Crypto.new()
			var localkey: Variant = await _jc.fetch_dev_localhost_key()
			if not localkey == null:
				key = CryptoKey.new()
				key.load_from_string(localkey as String)
			else:
				key = crypto.generate_rsa(2048)

			var localcert: Variant = await _jc.fetch_dev_localhost_cert()
			if not localcert == null:
				cert = X509Certificate.new()
				cert.load_from_string(localcert as String)
			else:
				cert = crypto.generate_self_signed_certificate(key, "CN=localhost")
		else:
			print("Setting up certificates for secure websockets...")
			var extra_downloads: String = OS.get_environment("EXTRA_DOWNLOAD_URLS")
			if len(extra_downloads) < 0:
				push_error("FATAL: Missing EXTRA_DOWNLOAD_URLS environment variable for cert and key downloads")
				get_tree().quit(1)
				return
			var extras: Variant = JSON.parse_string(extra_downloads)
			if extras == null:
				push_error("FATAL: EXTRA_DOWNLOAD_URLS environment variable failed to parse as valid JSON")
				get_tree().quit(1)
				return
			if not "server.key" in extras or not "server.crt" in extras:
				push_error("FATAL: Missing cert and key downloads")
				get_tree().quit(1)
				return
			var key_res: JamResult = await callback_api.get_string_data(extras["server.key"] as String)
			if key_res.errored:
				push_error("FATAL: server key download failed - %s" % key_res.error_msg)
				get_tree().quit(1)
				return
			var cert_res: JamResult = await callback_api.get_string_data(extras["server.crt"] as String)
			if cert_res.errored:
				push_error("FATAL: server cert download failed - %s" % cert_res.error_msg)
				get_tree().quit(1)
				return
			key = CryptoKey.new()
			err = key.load_from_string(key_res.value as String)
			if not err == OK:
				push_error("FATAL: Failed to load server key %s" % key_res.value)
				get_tree().quit(1)
				return
			cert = X509Certificate.new()
			err = cert.load_from_string(cert_res.value as String)
			if not err == OK:
				push_error("FATAL: Failed to load server cert %s" % cert_res.value)
				get_tree().quit(1)
				return
		err = peer.create_server(listen_port, "*", TLSOptions.server(key, cert))
	else:
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(listen_port, MAX_CLIENTS)
	if not err == OK:
		push_error("FATAL: Failed to start server on port %d - err code %d" % [listen_port, err])
		get_tree().quit(1)
		return
	
	multiplayer.multiplayer_peer = peer
	peer.peer_disconnected.connect(_on_peer_disconnect)
	_jc.m.peer_connected.connect(_on_peer_connect)
	
	print("Server listening on port %d" % listen_port)
	
	if dev_mode:
		_jc.server_pre_ready.emit()
		await _setup_local_dev_keys()
		_jc.server_post_ready.emit()
	else:
		# TODO: new file/DB system
		_jc.server_pre_ready.emit()
		var res: JamHttpBase.Result = await callback_api.send_ready()
		if res.errored:
			printerr("FATAL: Failed to set READY status in database - %s - aborting..." % res.error_msg)
			get_tree().quit()
		_jc.server_post_ready.emit()


## Authenticates a player by verifying the provided [code]username[/code] and
## [code]token[/code] with the Jam Launch callback. In developer mode, a token
## with the value [code]"localdev"[/code] will always verify successfully. 
func _auth_callback(peer_id: int, data: PackedByteArray) -> void:
	var data_json: String = data.get_string_from_utf8()
	if data_json == "":
		printerr("Invalid UTF-8 auth data provided by peer %d" % peer_id)
	var data_obj: Variant = JSON.parse_string(data_json)
	if data_obj == null:
		printerr("Invalid JSON auth data provided by peer %d" % peer_id)
	print("peer ", peer_id, ", data: ", data_obj)

	var username: String = data_obj["username"] as String
	if peer_id in peer_usernames:
		printerr("Unexpected duplicate auth call for peer %d : %s : %s" % [peer_id, peer_usernames[peer_id], username])

	var res: JamError = await _check_auth(username, data_obj["token"] as String)
	if res.errored:
		push_error("Auth failure - peer id %d - %s" % [peer_id, res.error_msg])
		_jc.m.disconnect_peer(peer_id)
		return

	print("Correlating peer %d with username %s" % [peer_id, username])
	peer_usernames[peer_id] = username
	var err: Error = _jc.m.complete_auth(peer_id)
	if not err == OK:
		printerr("Unexpected error when completing %d auth - code %d" % [peer_id, err])
		peer_usernames.erase(peer_id)
		return

	print("Authenticated peer %d as %s!" % [peer_id, username])


func _check_auth(username: String, join_token: String) -> JamError:
	if dev_mode:
		if join_token == "localdev":
			return JamError.ok()
		else:
			return JamError.err("Failed local dev auth for %s - token %s" % [username, join_token])
		
	var res: JamHttpBase.Result = await callback_api.check_token(username, join_token)
	if res.errored:
		return JamError.err("Failed verification of join token for %s (%s) - %s" % [username, join_token, res.error_msg])
	else:
		return JamError.ok()


func _on_peer_connect(peer_id: int) -> void:
	if peer_id not in peer_usernames:
		printerr("Unexpected connect without username record - peer_id %d" % peer_id)
		return
	
	var username: String = peer_usernames[peer_id]
	for other: Variant in peer_usernames.keys():
		if not peer_usernames[other] == username:
			_jc._send_player_joined.rpc_id(peer_id, other, peer_usernames[other])
			_jc.notify_players.rpc_id(peer_id, "'%s' is here" % peer_usernames[other])
	_jc.notify_players.rpc("'%s' has connected" % username)
	_jc.player_connected.emit(peer_id, username)
	_jc._send_player_joined.rpc(peer_id, username)


func _on_peer_disconnect(pid: int) -> void:
	if pid in peer_usernames:
		var username: String = peer_usernames[pid]
		peer_usernames.erase(pid)
		_jc.notify_players.rpc("'%s' has disconnected" % username)
		_jc.player_disconnected.emit(pid, username)
		_jc._send_player_left.rpc(pid, username)
	
	if peer_usernames.is_empty():
		print("All peers disconnected - shutting down...")
		shut_down(false)


## Shuts down the server elegantly
func shut_down(do_disconnect: bool = true) -> void:
	if do_disconnect:
		for pid: int in _jc.m.get_authenticating_peers():
			multiplayer.multiplayer_peer.disconnect_peer(pid, true)
		for pid: int in peer_usernames.keys():
			multiplayer.multiplayer_peer.disconnect_peer(pid as int, true)
	_jc.server_shutting_down.emit()
	get_tree().quit()


func _setup_local_dev_keys() -> void:
	var local_keys: Variant = await _fetch_local_dev_keys()
	if local_keys == null:
		return

	session_id = local_keys["session_id"]
	callback_api.api_url = local_keys["callback_url"] as String
	var res: JamJwt.TokenParseResult = callback_api.jwt.set_token(local_keys["callback_key"] as String)
	if res.errored:
		printerr("failed to set dev key for callback API - %s" % [res.error])
		return
	data_api.api_url = local_keys["data_url"] as String
	res = data_api.jwt.set_token(local_keys["data_key"] as String)
	if res.errored:
		printerr("failed to set dev key for data API - %s" % [res.error])
		return

	print("Setup local server dev keys for data and callback access - session %s" % [session_id])
	has_dev_keys = true


func _fetch_local_dev_keys() -> Variant:
	var peer: StreamPeerTCP = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", 17343)
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to connect to local auth proxy for local server creds")
			return null
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break

	var parts: PackedStringArray = _jc.get_game_id().split("-")
	peer.put_string("serverkeys/%s/%s" % [parts[0], parts[1] + "dev"])
	while true:
		await get_tree().create_timer(0.1).timeout
		var err: Error = peer.poll()
		if not err == OK:
			push_error("failed to get response from local auth proxy for server creds")
			return null
		if peer.get_available_bytes() > 0:
			break

	var json_response: String = peer.get_string()
	if json_response.begins_with("Error:"):
		push_error("failed to get server creds - %s" % json_response)
		return null

	var result: Variant = JSON.parse_string(json_response)
	if result == null:
		push_error("failed to parse server creds result - %s" % json_response)
		return null

	peer.disconnect_from_host()
	return result
