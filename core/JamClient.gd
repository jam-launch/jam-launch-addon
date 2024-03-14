class_name JamClient
extends CanvasLayer
## A [CanvasLayer] that provides client-specific multiplayer capabilities as the
## child of a [JamConnect] Node

## The client UI used to configure and initiate sessions
var client_ui: JamClientUI
## The client token for the active session. The token is used to verify
## identity with the server.
var current_client_token: String

var test_client_number: int = 1:
	set(val):
		if val != test_client_number and OS.is_debug_build():
			test_client_number = val
			await _setup_test_gjwt()

var session_id: String = ""

signal fetching_test_gjwt(busy: bool)
var gjwt_fetch_busy: bool = false:
	set(val):
		gjwt_fetch_busy = val
		fetching_test_gjwt.emit(val)

## The Game JWT for this client - used to authenticate with the Jam Launch API
var jwt: JamJwt = JamJwt.new()
## Interface for calling the Jam Launch session API
var api: JamClientApi
## Helper object for acquiring a Game JWT for authentication
var keys: ClientKeys

## The WebRTC client helper (available if network mode is WebRTC peer-to-peer)
var webrtc_helper: JamWebRTCHelper

var _jc: JamConnect:
	get:
		return get_parent()

func _init():
	layer = 512
	
	keys = ClientKeys.new()
	add_child(keys)

func _ready():
	api = JamClientApi.new()
	api.game_id = _jc.game_id
	api.jwt = jwt
	add_child(api)
	
	_jc.game_init_finalized.connect(_on_game_init_finalized)
	
	var gjwt = keys.get_included_gjwt(_jc.get_game_id())
	if gjwt == null:
		if OS.is_debug_build():
			_setup_test_gjwt()
		else:
			push_error("Failed to load GJWT")
	else:
		set_gjwt(gjwt as String)

func _setup_test_gjwt():
	gjwt_fetch_busy = true
	var gjwt = await keys.get_test_gjwt(_jc.game_id, test_client_number)
	gjwt_fetch_busy = false
	if gjwt != null:
		set_gjwt(gjwt as String)
	else:
		push_error("Failed to load GJWT")

func set_gjwt(gjwt: String):
	var gjwtRes = jwt.set_token(gjwt)
	if gjwtRes.errored:
		push_error(gjwtRes.error)
	else:
		_jc.gjwt_acquired.emit()

## Persists the GJWT so that it can be retrieved in the next run. Should only be
## used when the GJWT was not embedded in the game package (e.g. on mobile)
func persist_gjwt() -> bool:
	if not jwt.has_token():
		return false
	var gjwt_file = FileAccess.open("user://gjwt-%s" % _jc.get_game_id(), FileAccess.WRITE)
	if gjwt_file == null:
		return false
	gjwt_file.store_string(jwt.get_token())
	gjwt_file.close()
	return true

## Configures and starts client functionality
func client_start():
	print("Starting as client...")
	if _jc.network_mode == "webrtc" or OS.has_feature("webrtc"):
		webrtc_init()
	
	multiplayer.connected_to_server.connect(_on_client_connect)
	multiplayer.connection_failed.connect(_on_client_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnect)
	client_ui.client_ui_initialization(_jc)
	add_child(client_ui)

## Initiates a connection to a provisioned server
func client_session_request(ip: String, port: int, token: String, domain: Variant):
	current_client_token = token
	client_ui.visible = false
	
	var dev_ws = _jc.network_mode == "websocket" and OS.is_debug_build()
	
	if OS.has_feature("websocket") or dev_ws:
		if domain == null:
			domain = "jamserve.net"
		ip = "wss://%s" % domain
	
	_jc.log_event.emit("Attempting to connect to %s:%d..." % [ip, port])
	print("Attempting to connect to %s:%d..." % [ip, port])
	
	var peer
	var err
	if OS.has_feature("websocket") or dev_ws:
		peer = WebSocketMultiplayerPeer.new()
		err = peer.create_client("%s:%d" % [ip, port], TLSOptions.client_unsafe())
	else:
		peer = ENetMultiplayerPeer.new()
		err = peer.create_client(ip, port)
	if err != OK:
		printerr("Server connection error: ", err)
		_jc.log_event.emit("Error: %d" % err)
		client_ui.visible = true
		client_ui.show_error(("Server connection error: %d" % err) as String)
		return
	multiplayer.multiplayer_peer = peer
	_jc.local_player_joining.emit()

## initiates the P2P signalling connection
func p2p_session_connect(sess_id: String, user_id: String, token: String) -> JamError:
	current_client_token = token
	return await webrtc_helper.start("wss://p2p.jamlaunch.com/?session=%s&user=%s&token=%s" % [sess_id, user_id, token])

func p2p_game_start():
	if _jc.is_player_server():
		webrtc_helper.signalling.seal_lobby()
		_jc._send_game_init_finalized.rpc()

## Elegantly leaves the game by disconnecting from the server and notifying the
## Jam Launch API
func leave_game():
	client_ui.visible = true
	await client_ui.leave_game_session()
	multiplayer.multiplayer_peer.close()

func _on_client_connect_fail():
	_jc.log_event.emit("Connection to server failed")
	_jc.local_player_left.emit()
	client_ui.visible = true

func _on_client_connect():
	if not _jc.is_webrtc_mode():
		_jc.log_event.emit("Connected, verifying...")
		_jc.verify_identity(current_client_token)

func _on_server_disconnect():
	_jc.log_event.emit("Server disconnected")
	_jc.local_player_left.emit()
	client_ui.visible = true

func webrtc_init():
	webrtc_helper = JamWebRTCHelper.new()
	add_child(webrtc_helper)
	
	webrtc_helper.session_sealed.connect(self._webtrc_session_sealed)
	webrtc_helper.multiplayer_initialized.connect(self._p2p_multiplayer_initialized)
	webrtc_helper.multiplayer_terminating.connect(self._p2p_multiplayer_terminating)

	multiplayer.peer_connected.connect(self._p2p_peer_connected)
	multiplayer.peer_disconnected.connect(self._p2p_peer_disconnected)

func _p2p_peer_connected(pid: int):
	#print("P2P peer connected: %d (to %d)" % [pid, multiplayer.get_unique_id()])
	if _jc.is_player_server():
		if not webrtc_helper.peers.has(pid):
			printerr("Unexpected client connection from peer '%d'" % pid)
			return
		var p: Dictionary = webrtc_helper.peers[pid]
		_jc.notify_players.rpc("'%s' has joined" % p["name"])
		_jc.player_verified.emit(pid, p)
		_jc._verification_notification.rpc_id(pid, p)
		
		for other in webrtc_helper.peers.values():
			if other["name"] != p["name"]:
				_jc._send_player_joined.rpc_id(pid, other["name"])
				_jc.notify_players.rpc_id(pid, "'%s' is here" % other["name"])
		_jc.notify_players.rpc("'%s' has joined" % p["name"])
		_jc._send_player_joined.rpc(p["name"])
		_jc.player_joined.emit(p["name"])

func _p2p_peer_disconnected(pid: int):
	#print("P2P peer disconnected: %d" % pid)
	if _jc.is_player_server():
		if pid in webrtc_helper.peers:
			var pinfo = webrtc_helper.peers[pid]
			
			_jc.notify_players.rpc("Player '%s' has disconnected" % pinfo.get("name", "<>"))
			_jc.player_disconnected.emit(pid, pinfo)
			_jc._send_player_left.rpc(pinfo["name"])
			_jc.player_left.emit(pinfo["name"])
			
			webrtc_helper.peers.erase(pid)
	
func _p2p_multiplayer_initialized(pid: int, pinfo: Dictionary):
	if _jc.is_player_server():
		_jc.log_event.emit("'%s' has joined" % pinfo["name"])
		_jc.player_verified.emit(pinfo["pid"], pinfo)
		_jc.local_player_joining.emit()
		_jc.local_player_joined.emit(pinfo)
		_jc.player_joined.emit(pinfo["name"])
		print("server player joined")

func _p2p_multiplayer_terminating():
	_jc.local_player_left.emit()

func _webtrc_session_sealed():
	pass
	#print("WebRTC Client Session Sealed!")

func _on_game_init_finalized():
	client_ui.visible = false
