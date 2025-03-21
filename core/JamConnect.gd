class_name JamConnect
extends Node
## A [Node] that simplifies integration with the Jam Launch API.
##
## The JamConnect Node serves as an all-in-one Jam Launch integration that
## handles client and server initialization, and provides a session
## establishment GUI for clients. It is designed to be placed in a multiplayer
## game's main scene and connected to the player joining/leaving functions via
## the [signal JamConnect.player_connected] and
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
@warning_ignore("unused_signal")
signal log_event(msg: String)

## Emitted in the server whenever a player connects and authenticates with the server
@warning_ignore("unused_signal")
signal player_connected(pid: int, username: String)
## Emitted in the server whenever a player disconnects from the server
@warning_ignore("unused_signal")
signal player_disconnected(pid: int, username: String)

## Emitted in the server immediately before a "READY" notification is provided
## to Jam Launch - this can be used for configuring things before players join.
@warning_ignore("unused_signal")
signal server_pre_ready()
## Emitted in the server immediately after a "READY" notification is provided
## to Jam Launch
@warning_ignore("unused_signal")
signal server_post_ready()
## Emitted in the server before shutting down - this can be used for last minute
## logging or Data API interactions.
@warning_ignore("unused_signal")
signal server_shutting_down()

## Emitted in the client when it starts trying to connect to the server
@warning_ignore("unused_signal")
signal local_player_joining()
## Emitted in the client when it has been verified
@warning_ignore("unused_signal")
signal local_player_joined()
## Emitted in the client when it has been disconnected or fails to connect
@warning_ignore("unused_signal")
signal local_player_left()

## Emitted in clients when a player joins
@warning_ignore("unused_signal")
signal player_joined(pid: int, username: String)
## Emitted in clients when a player leaves
@warning_ignore("unused_signal")
signal player_left(pid: int, username: String)

## Emitted in clients and server when the game has finished a standard
## initialization step. By default, this implies that all pending players have
## connected as peers of the host/server
@warning_ignore("unused_signal")
signal game_init_finalized()

## Emitted in clients when they have acquired their Jam Launch API credentials
## (e.g. via embedded file, test client API, or user entry)
@warning_ignore("unused_signal")
signal gjwt_acquired()

## The amount of time in minutes that the server will wait for players to join.
## If no players join before the timeout is reached, the server will shut down.
## [br]
## A value of [code]0[/code] means that no timeout will be enforced.
@export_range(0, 120) var pre_join_timeout_minutes: int = 15

## The maximum time that a server is allowed to run before it should shut itself
## down. This is primarily meant as a convenience/backup in case the server
## fails to end itself appropriately.
## [br]
## A value of [code]0[/code] means that no automatic uptime shutdown will be
## performed.
@export_range(0, 60 * 24) var maximum_uptime_minutes: int = 0

## If true, shuts down the server when all players have disconnected.
@export var shutdown_when_empty: bool = true

## The maximum number of players that can be connected before auth checks will
## auto-fail for all players trying to connect.
##
## A value less than 1 means that no limit is imposed.
@export var maximum_player_count: int = 0

## A reference to the child [JamClient] node that will be instantiated when
## running as a client
var client: JamClient = null
## A reference to the child [JamServer] node that will be instantiated when
## running as a server
var server: JamServer = null

## The Jam Launch Game ID of this game (a hyphen-separated concatenation of the
## project ID and release ID, e.g. "projectId-releaseId"). Usually derived from
## the [code]deployment.cfg[/code] file located a directory above this file
## which is generated by the Jam Launch editor plugin when a deployment is
## pushed or loaded. If it is not present in your copy of a deployed game, you
## may need to navigate to the project page in the editor plugin to sync it (the
## sync happens automatically when the project page is loaded)
var game_id: String


## Whether or not guests are allowed to play this release. This does not need to
## be enforced by the game in any way - it is mostly provided for UI awareness.
var allow_guests: bool = false


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

## Convenience reference to the MultiplayerAPI for full SceneMultiplayer API
## auto-completion
var m: SceneMultiplayer

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
		if game_id == null:
			printerr("FATAL: deployment.cfg does not contain a game id value")
			get_tree().quit(1)
			return
		allow_guests = deployment_info.get_value("game", "allow_guests", false)
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
	
	m = multiplayer
	start_up.call_deferred()

## Start the JamConnect functionality including client/server determination and 
## multiplayer peer creation and configuration.
func start_up():
	print("Running JamConnect start-up...")
	get_tree().set_auto_accept_quit(false)
	JamRoot.get_jam_root(get_tree()).jam_connect = self
	
	var args := {}
	for a in OS.get_cmdline_args():
		if a.find("=") > -1:
			var key_value = a.split("=")
			args[key_value[0].lstrip("--")] = key_value[1]
		elif a.begins_with("--"):
			args[a.lstrip("--")] = true
	
	if "window-c" in args:
		get_window().move_to_center()
	
	if "window-x" in args:
		get_window().position.x += int(args["window-x"] as String)
		
	if "window-y" in args:
		get_window().position.y += int(args["window-y"] as String)
	
	if OS.has_feature("server") or "--server" in OS.get_cmdline_args():
		server = JamServer.new()
		add_child(server)
		await server.server_start(args)
	elif "local-dev-server" in args:
		start_as_dev_server()
	else:
		client = JamClient.new()
		client.client_ui = client_ui_scene.instantiate()
		add_child(client)
		client.client_start()
		
		if "local-dev-client" in args:
			var delay := float(args.get("local-dev-client-delay", "0.75") as String)
			await get_tree().create_timer(delay).timeout
			client.client_session_request("localhost", 7437, "localdev")

## Converts this JamConnect node from being configured as a client to being
## being configured as a server in "dev" mode. Used for simplified local hosting
## in debug instances launched from the Godot editor.
func start_as_dev_server():
	if client != null:
		client.queue_free()
		client = null

	server = JamServer.new()
	add_child(server)
	await server.server_start({"dev": true})

## Gets the project ID (the game ID without the release string)
func get_project_id() -> String:
	return game_id.split("-")[0]

## Gets the game ID (a.k.a. release ID - the project ID concatenated with the
## release string
func get_game_id() -> String:
	return game_id

## Gets the session ID
func get_session_id() -> String:
	if server:
		return server.session_id
	elif client:
		return client.session_id
	else:
		return ""

func is_webrtc_mode() -> bool:
	return network_mode == "webrtc"

func is_websocket_mode():
	return network_mode == "websocket"
	
func is_dedicated_server() -> bool:
	return multiplayer.is_server() and not is_webrtc_mode()

func is_player_server() -> bool:
	return multiplayer.is_server() and is_webrtc_mode()

func is_player() -> bool:
	return not multiplayer.is_server() or is_player_server()

#
# ----- Server methods -----
#

@rpc("reliable")
func _send_player_joined(pid: int, username: String):
	player_joined.emit(pid, username)

@rpc("reliable")
func _send_player_left(pid: int, username: String):
	player_left.emit(pid, username)

@rpc("reliable", "call_local")
func _send_game_init_finalized():
	game_init_finalized.emit()

## A server-callable RPC method for broadcasting informational server messages
## to clients
@rpc("reliable")
func notify_players(msg: String):
	log_event.emit(msg)


func fetch_dev_localhost_key() -> Variant:
	var peer = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", 17343)
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to connect to local auth proxy for localhost cert key info - this might result in TLS handshake errors")
			peer.disconnect_from_host()
			return null
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
	
	peer.put_string("localhostkey")
	
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to get response from local auth proxy for localhost cert key")
			peer.disconnect_from_host()
			return null
		if peer.get_available_bytes() > 0:
			break
	
	var response := peer.get_string()
	
	if response.begins_with("Error:"):
		push_error("failed to get localhost cert key - %s" % response)
		return null
	
	return response

func fetch_dev_localhost_cert() -> Variant:
	var peer = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", 17343)
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to connect to local auth proxy for localhost cert - this might result in TLS handshake errors")
			peer.disconnect_from_host()
			return null
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
	
	peer.put_string("localhostcert")
	
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to get response from local auth proxy for localhost cert")
			peer.disconnect_from_host()
			return null
		if peer.get_available_bytes() > 0:
			break
	
	var response := peer.get_string()
	
	if response.begins_with("Error:"):
		push_error("failed to get localhost cert - %s" % response)
		return null
	
	return response
