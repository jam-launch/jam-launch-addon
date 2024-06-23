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
		if OS.is_debug_build() and OS.get_name() != "Android":
			_setup_test_gjwt()
		else:
			push_error("Failed to load GJWT")
	else:
		set_gjwt(gjwt as String)

func _setup_test_gjwt():
	gjwt_fetch_busy = true
	var gjwt = await keys.get_test_gjwt(_jc.game_id)
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
	
	multiplayer.connected_to_server.connect(_on_client_connect)
	multiplayer.connection_failed.connect(_on_client_connect_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnect)
	client_ui.client_ui_initialization(_jc)
	add_child(client_ui)

## Initiates a connection to a provisioned server
func client_session_request(host: String, port: int, token: String):
	current_client_token = token
	client_ui.visible = false
	
	_jc.log_event.emit("Attempting to connect to %s:%d..." % [host, port])
	print("Attempting to connect to %s:%d..." % [host, port])
	
	var peer
	var err
	if _jc.network_mode == "websocket":
		peer = WebSocketMultiplayerPeer.new()
		err = peer.create_client("wss://%s:%d" % [host, port], TLSOptions.client_unsafe())
	else:
		peer = ENetMultiplayerPeer.new()
		err = peer.create_client(host, port)
	if err != OK:
		printerr("Server connection error: ", err)
		_jc.log_event.emit("Error: %d" % err)
		client_ui.visible = true
		client_ui.show_error(("Server connection error: %d" % err) as String)
		return
	multiplayer.multiplayer_peer = peer
	_jc.local_player_joining.emit()

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
		_jc.verify_identity(jwt.claims["username"] as String, current_client_token)

func _on_server_disconnect():
	_jc.log_event.emit("Server disconnected")
	_jc.local_player_left.emit()
	client_ui.visible = true

func _on_game_init_finalized():
	client_ui.visible = false
