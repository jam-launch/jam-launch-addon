class_name JamConnect
extends Node
## A [Node] that simplifies integration with the Jam Launch API.
##
## The JamConnect Node serves as an all-in-one Jam Launch integration that
## handles client and server initialization, and provides a session
## establishment GUI for clients. It is designed to be placed in a multiplayer
## game's main scene and connected to the player joining/leaving functions via
## the [signal JamConnect.player_verified] and
## [signal JamConnect.player_disconnected] signals.
## [br][br]
## When a JamConnect node determines that a game is being started as a server
## (e.g. by checking a feature tag), it will add a [JamServer] child node which
## configures the Godot multiplayer peer in server mode and spins up things like
## the Jam Launch Data API (which is only accessible from the server).
## [br][br]
## When a JamConnect node determines that a game is being started as a client,
## it will add a [JamClient] child node which configures the Godot multiplayer
## peer in client mode, and overlays a GUI for establishing the connection to
## the server via the Jam Launch API.
## [br][br]
## The JamConnect Node is not strictly necessary for integrating a game with Jam
## Launch - it is just a reasonable all-in-one default. The various low-level
## clients and utilities being used by JamConnect could be recomposed by an
## advanced user into a highly customized solution.
##

## Emitted in clients whenever the server sends a notification message
signal log_event(msg: String)

## Emitted in the server whenever the server finishes verifying a connected
## client - [code]pid[/code] is the Godot multiplayer peer ID of the player, and
## the [code]pinfo[/code] dictionary will include the unique Jam Launch username
## of the player in the [code]"name"[/code] key
signal player_verified(pid: int, pinfo: Dictionary)
## Emitted in the server whenever a player disconnects from the server - see
## [signal JamConnect.player_verified] for argument details.
signal player_disconnected(pid: int, pinfo: Dictionary)

## Emitted in the server immediately before a "READY" notification is provided
## to Jam Launch - this can be used for configuring things before players join.
signal server_pre_ready()
## Emitted in the server immediately after a "READY" notification is provided
## to Jam Launch
signal server_post_ready()
## Emitted in the server before shutting down - this can be used for last minute
## logging or Data API interactions.
signal server_shutting_down()

## Emitted in the client when it starts trying to connect to the server
signal local_player_joining()
## Emitted in the client when it has been verified
signal local_player_joined(pinfo: Dictionary)
## Emitted in the client when it has been disconnected or fails to connect
signal local_player_left()

## Emitted in clients when a player joins
signal player_joined(user_id: String)
## Emitted in clients when a player leaves
signal player_left(user_id: String)

## Emitted in clients and server when the game has finished a standard
## initialization step. By default, this implies that all pending players have
## connected as peers of the host/server
signal game_init_finalized()

## Emitted in the server when an asynchronous DB operation has completed or
## errored out
signal game_db_async_result(result, error)
## Emitted in the server when an asynchronous Files operation has completed or
## errored out
signal game_files_async_result(key, error)

## Emitted in the client when a configuration request response is received from
## the server
signal config_request_result(key: String, value: String, error: Variant)

## Emitted in the client when a configuration set request response is received
## from the server
signal config_set_request_result(key: String, error: Variant)

## A reference to the child [JamClient] node that will be instantiated when
## running as a client
var client: JamClient
## A reference to the child [JamServer] node that will be instantiated when
## running as a server
var server: JamServer

## The Jam Launch Game ID of this game (a hyphen-separated concatenation of the
## project ID and release ID, e.g. "projectId-releaseId"). Usually derived from
## the [code]deployment.cfg[/code] file located a directory above this file
## which is generated by the Jam Launch editor plugin when a deployment is
## pushed or loaded. If it is not present in your copy of a deployed game, you
## may need to navigate to the project page in the editor plugin to sync it (the
## sync happens automatically when the project page is loaded)
var game_id: String

## The network mode for the client/server interaction as determined by the 
## [code]deployment.cfg[/code] file.
## [br][br]
## [code]"enet"[/code] - uses the [ENetMultiplayerPeer] for connections. This
## provides low-overhead UDP communication, but is not supported by web clients.
## [br]
## [code]"websocket"[/code] - uses the [WebSocketMultiplayerPeer] for
## connections. This enables web browser-based clients.
## [br]
## [code]"webrtc"[/code] - uses the [WebRTCMultiplayerPeer] for
## connections. This allows games to be run in a peer-to-peer configuration
## without a dedicated server. The hosting player acts as the game
## authority/server.
var network_mode: String = "enet"

## True if a Jam Launch cloud deployment for this project is known to exist via
## the presence of a [code]deployment.cfg[/code] file. When this value is false,
## only local testing functionality can be provided.
var has_deployment: bool = false

## A [JamThreadHelper] instance for assisting with threading
var thread_helper: JamThreadHelper

@export var client_ui_scene: PackedScene


#
# ----- Core Methods -----
#

func _init():
	print("Creating game node...")
	
	thread_helper = JamThreadHelper.new()
	add_child(thread_helper)
	
	var dir := (self.get_script() as Script).get_path().get_base_dir()
	var deployment_info = ConfigFile.new()
	var err = deployment_info.load(dir + "/../deployment.cfg")
	if err != OK:
		print("Game deployment settings could not be located - only the local hosting features will be available...")
		game_id = "init-undeployed"
	else:
		game_id = deployment_info.get_value("game", "id")
		network_mode = deployment_info.get_value("game", "network_mode", "enet")
		has_deployment = true

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# force quit after a timeout in case graceful shutdown blocks up
		await get_tree().create_timer(4.0).timeout
		get_tree().quit(1)

func _ready():
	print("JamConnect node ready, deferring auto start-up...")
	if not client_ui_scene:
		client_ui_scene = preload("../ui/client/ExampleClientUI.tscn")
	start_up.call_deferred()

## Start the JamConnect functionality including client/server determination and 
## multiplayer peer creation and configuration.
func start_up():
	print("Running JamConnect start-up...")
	get_tree().set_auto_accept_quit(false)
	
	var args := {}
	for a in OS.get_cmdline_args():
		if a.find("=") > -1:
			var key_value = a.split("=")
			args[key_value[0].lstrip("--")] = key_value[1]
		elif a.begins_with("--"):
			args[a.lstrip("--")] = true
	
	if OS.has_feature("server") or "--server" in OS.get_cmdline_args():
		server = JamServer.new()
		add_child(server)
		server.server_start(args)
	else:
		client = JamClient.new()
		client.client_ui = client_ui_scene.instantiate()
		add_child(client)
		client.client_start()

## Converts this JamConnect node from being configured as a client to being
## being configured as a server in "dev" mode. Used for simplified local hosting
## in debug instances launched from the Godot editor.
func start_as_dev_server():
	client.queue_free()
	client = null

	server = JamServer.new()
	add_child(server)
	server.server_start({"dev": true})

## Gets the project ID (the game ID without the release string)
func get_project_id() -> String:
	return game_id.split("-")[0]

## Gets the game ID (a.k.a. release ID - the project ID concatenated with the
## release string
func get_game_id() -> String:
	return game_id

## Gets the session ID (the game ID concatenated with a unique session string)
func get_session_id() -> String:
	if is_dedicated_server():
		return OS.get_environment("SESSION_ID")
	elif client:
		return client.session_id
	else:
		return ""

func is_webrtc_mode() -> bool:
	return network_mode == "webrtc" or OS.has_feature("webrtc")

func is_websocket_mode():
	return network_mode == "websocket" or OS.has_feature("webrtc")
	
func is_dedicated_server() -> bool:
	return multiplayer.is_server() and not is_webrtc_mode()

func is_player_server() -> bool:
	return multiplayer.is_server() and is_webrtc_mode()


#
# ----- Client methods -----
#

## A client-callable method used by connected clients to verify their
## identity with the server.
func verify_identity(join_token: String):
	if not is_webrtc_mode():
		_verify_player.rpc_id(1, join_token)

@rpc("any_peer", "call_remote", "reliable")
func _verify_player(join_token: String):
	if is_dedicated_server():
		server.verify_player(join_token)

## A client-callable RPC method used to fetch configuration information. Results
## will be returned with the [JamConnect.config_request_result] signal
@rpc("any_peer", "reliable")
func request_config(key: String):
	if not multiplayer.is_server() or not server:
		resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", "Invalid request")
		return
	if multiplayer.get_remote_sender_id() not in server.accepted_peers:
		return
	if len(key) > 255:
		resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", "Config key too large")
		return
	
	var p = await thread_helper.run_threaded_producer(server.db.get_session_data.bind("CFG"))
	if p.errored:
		printerr("Failed to get session config info: ", p.error_msg)
		resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", p.error_msg)
	else:
		if p.value is Dictionary:
			if key in p.value:
				resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, p.value[key], null)
			else:
				resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", "Requested key '%s' was not found in config" % key)
		else:
			printerr("Unexpected session config result: ", p.value)
			resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", "Unexpected config query result")

## A client-callable RPC method used to patch configuration information. Results
## will be returned with the [JamConnect.config_request_result] signal
@rpc("any_peer", "reliable")
func edit_config(key: String, value: String):
	# TODO: maybe add some sort of assignable conditional to restrict usage (right now just restricted to host)
	if not multiplayer.is_server() or not server:
		resolve_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "", "Invalid request")
		return
	if multiplayer.get_remote_sender_id() not in server.accepted_peers:
		return
	if len(key) > 255:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "Config key too large")
	if len(value) > 20000:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "Config value too large")
	
	var pinfo = server.accepted_peers[multiplayer.get_remote_sender_id()]
	
	# check if caller is host
	var cfg = await thread_helper.run_threaded_producer(server.db.get_session_data.bind("CFG"))
	if cfg.errored:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, cfg.error_msg)
		return
	if not (cfg.value is Dictionary):
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "Unexpected config query result")
		return
	var cfg_data: Dictionary = cfg.value
	if not cfg_data.get("host", "").split(",").has(pinfo["name"]):
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "Player %s cannot edit the config" % pinfo["name"])
		return
	
	cfg_data.erase("key_1")
	cfg_data.erase("key_2")
	cfg_data[key] = value
	var set_result = await thread_helper.run_threaded_producer(server.db.put_session_data.bind("CFG", cfg_data))
	if set_result.errored:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, set_result.error_msg)
	elif not set_result.value:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, "set config failed")
	else:
		resolve_set_config_request.rpc_id(multiplayer.get_remote_sender_id(), key, null)

#
# ----- Server methods -----
#

## called from the server to notify clients that they have been verified
@rpc("reliable")
func _verification_notification(pinfo: Dictionary):
	local_player_joined.emit(pinfo)

@rpc("reliable")
func _send_player_joined(user_id: String):
	player_joined.emit(user_id)

@rpc("reliable")
func _send_player_left(user_id: String):
	player_left.emit(user_id)

@rpc("reliable", "call_local")
func _send_game_init_finalized():
	game_init_finalized.emit()

## A server-callable RPC method for broadcasting informational server messages
## to clients
@rpc("reliable")
func notify_players(msg: String):
	log_event.emit(msg)

## A server-callable RPC method for resolving configuration requests from the
## client
@rpc("reliable")
func resolve_config_request(key: String, value: String, error: Variant):
	config_request_result.emit(key, value, error)

## A server-callable RPC method for resolving configuration requests from the
## client
@rpc("reliable")
func resolve_set_config_request(key: String, error: Variant):
	config_set_request_result.emit(key, error)

## A method that can be called on the server in order to make sure the client
## is verified before relaying to other clients.
func server_relay(callable: Callable, args: Array = []):
	if not multiplayer.is_server() or not server:
		return
	server.rpc_relay(callable, multiplayer.get_remote_sender_id(), args)
