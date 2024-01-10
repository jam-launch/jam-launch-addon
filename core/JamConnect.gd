extends Node
class_name JamConnect

signal log_event(msg: String)
signal player_verified(pid: int, pinfo: Dictionary)
signal player_disconnected(pid: int, pinfo: Dictionary)

signal server_pre_ready()
signal server_post_ready()
signal server_shutting_down()
signal game_db_async_result(result, error)
signal game_files_async_result(key, error)

var client: JamClient
var server: JamServer

func _init():
	print("Creating game node...")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# force quit after a timeout in case graceful shutdown blocks up
		await get_tree().create_timer(4.0).timeout
		get_tree().quit(1)

func _ready():
	print("JamConnect node ready, deferring auto start-up...")
	start_up.call_deferred()

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
		add_child(client)
		client.client_start()

@rpc("any_peer", "call_remote", "reliable")
func verify_player(join_token: String):
	if multiplayer.is_server():
		server.verify_player(join_token)

@rpc("reliable")
func notify_players(msg: String):
	log_event.emit(msg)

func server_relay(callable: Callable, args: Array = []):
	if not multiplayer.is_server():
		return
	server.rpc_relay(callable, multiplayer.get_remote_sender_id(), args)

func start_as_dev_server():
	client.queue_free()
	client = null

	server = JamServer.new()
	add_child(server)
	server.server_start({"dev": true})

func get_game_id() -> String:
	if server:
		return get_session_id().split("-")[0]
	elif client:
		return client.game_id.split("-")[0]
	else:
		return ""

func get_release_id() -> String:
	if server:
		var parts = get_session_id().split("-")
		return parts[0] + "-" + parts[1]
	elif client:
		return client.game_id
	else:
		return ""
	
func get_session_id() -> String:
	if server:
		return OS.get_environment("SESSION_ID")
	elif client:
		return client.session_id
	else:
		return ""
