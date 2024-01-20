extends Node
class_name ClientUI

@onready var session_text: LineEdit = $CC/Sessions/VB/HB/Session
@onready var page_root: Control = $CC
@onready var sessions: Control = $CC/Sessions
@onready var region_select: OptionButton = $CC/Sessions/VB/RegionSelect

@onready var lobby = $CC/Lobby
@onready var join_id_label = $CC/Lobby/VB/JoinId
@onready var session_refresh = $CC/Lobby/SessionRefresh
@onready var player_list = $CC/Lobby/VB/Players
@onready var server_status = $CC/Lobby/VB/ServerStatus

@onready var errors = $Bottom/Errors
@onready var loading_splash = $CC/LoadingSplash

@onready var version_info = $Bottom/M/VersionInfo

class LoadingHandle:
	extends RefCounted
	
	var _base
	var target_page
	
	func _init(base: ClientUI):
		_base = base
		var was_visible = _base.show_child(_base.loading_splash)
		if len(was_visible) < 1:
			push_error("no previously visible children available to target by loading handle")
			target_page = _base.sessions
		else:
			target_page = was_visible[0]
		
	func _notification(what):
		if what == NOTIFICATION_PREDELETE:
			_base.show_child(target_page)

var game_id: String :
	get:
		return client_api.game_id

var msg_scn = preload("res://addons/jam_launch/ui/MessagePanel.tscn")

var jam_client:
	get:
		return get_parent()
		
var jc:
	get:
		return jam_client.get_parent()

var id_token: String
var client_api: ClientApi
var active_session = null
var session_token
var active_session_data :
	set(val):
		active_session_data = val
		player_list.clear()
		if val == null:
			server_status.text = "Server status: Unknown"
			return
		
		server_status.text = "Server status: %s" % active_session_data["status"]
		for p in active_session_data["players"]:
			player_list.add_item(p["user_id"])

signal connect_to_session(ip: String, port: int, token: String, domain: Variant)


func _ready():
	
	var gid_parts = game_id.split("-")
	var version_number = gid_parts[len(gid_parts) - 1]
	version_info.text = "version %s" % version_number
	version_info.text += " - jam launch %s" % client_api.addon_version
	if OS.is_debug_build():
		$Menu/DevTools.get_popup().id_pressed.connect(_on_devtools_pressed)
		version_info.text += " (debug)"
	else:
		$Menu/DevTools.visible = false
	
	show_child(sessions)
	
	if not jc.has_deployment:
		set_enable_deployments(false)

func set_enable_deployments(enable: bool):
	$CC/Sessions/VB/HB/Join.disabled = !enable
	$CC/Sessions/VB/HB/Session.editable = enable
	$CC/Sessions/VB/Create.disabled = !enable
	$CC/Sessions/VB/RegionSelect.disabled = !enable
	
	$CC/Sessions/VB/Message.visible = !enable
	if !enable:
		$CC/Sessions/VB/Message.text = "No deployable configuration was found for this project - features will be limited to local hosting. Jam Launch developer access is required to make deployable projects."

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("got quit notification")
		if active_session != null:
			var res = await client_api.leave_game_session(active_session as String)
			if res.errored:
				push_error(res.error_msg)
			else:
				print("left game session")
		get_tree().quit()

func show_child(c):
	var was_visible = []
	for child in page_root.get_children():
		if "visible" in child:
			if child.visible:
				was_visible.append(child)
			child.visible = false
	c.visible = true
	return was_visible

func enter_lobby(session_id: String, join_token: String, loading_handle: LoadingHandle) -> bool:
	var res := await client_api.get_game_session(session_id)
	if res.errored:
		show_error(res.error_msg)
		return false
	
	join_id_label.text = res.data["join_id"]
	active_session_data = res.data
	active_session = session_id
	session_token = join_token
	loading_handle.target_page = lobby
	session_refresh.start(4)
	return true

func exit_lobby():
	var h = LoadingHandle.new(self)
	loading_splash.set_operation_text("leaving game...")
	h.target_page = sessions
	session_refresh.stop()
	var res := await client_api.leave_game_session(active_session as String)
	active_session = null
	if res.errored:
		show_error(res.error_msg)
		return false
	else:
		return true

func _on_create_pressed():
	var h := LoadingHandle.new(self)
	loading_splash.set_operation_text("creating game session...")
	var region := "us-east-2"
	var region_id = region_select.get_item_id(region_select.selected)
	print("region ID: ", region_id)
	if region_id == 0:
		region = "us-east-2"
	elif region_id == 1:
		region = "eu-west-2"
	print("Attempting to start game session in '%s'..." % region)
	var res := await client_api.create_game_session(region)
	if res.errored:
		show_error(res.error_msg)
		return
	
	print("result: ", res.data)
	
	loading_splash.set_operation_text("entering lobby...")
	if not await enter_lobby(res.data["id"] as String, res.data["join_token"] as String, h):
		res = await client_api.leave_game_session(res.data["id"] as String)
		if res.errored:
			show_error("failed to leave game session after failing to enter lobby: %s" % res.error_msg)

func _on_start_pressed():
	if active_session_data == null:
		show_error("session information no longer available!")
		await exit_lobby()
		return
	
	if len(active_session_data["addresses"]) < 1:
		show_error("session not yet initialized", 4.0)
		return
		
	if active_session_data["status"] != "READY":
		show_error("session not yet ready", 4.0)
		return
	
	var address = active_session_data["addresses"][0]
	
	connect_to_session.emit(address["ip"], address["port"], session_token, address.get("domain", null))

func join_session(join_id: String) -> bool:
	var h := LoadingHandle.new(self)
	loading_splash.set_operation_text("joining %s..." % join_id)
	var res := await client_api.join_game_session(join_id)
	if res.errored:
		show_error(res.error_msg)
		return false
	
	loading_splash.set_operation_text("entering %s lobby..." % join_id)
	await enter_lobby(res.data["session_id"] as String, res.data["join_token"] as String, h)
	clear_errors()
	return true

func _on_session_refresh_timeout():
	if active_session == null:
		session_refresh.stop()
		return
	elif not self.visible:
		session_refresh.stop()
		return
	var res := await client_api.get_game_session(active_session as String)
	if res.errored:
		show_error("session refresh error: " + res.error_msg, 5.0)
		session_refresh.start(5)
		return
	session_refresh.start(2)
	active_session_data = res.data

func _on_leave_pressed():
	await exit_lobby()

func _on_session_text_changed(new_text: String):
	var upper = new_text.to_upper()
	if upper != new_text:
		session_text.text = upper
		session_text.caret_column = len(upper)

func _on_join_pressed():
	_join()

func _on_session_text_submitted(_new_text):
	_join()

func _join():
	await join_session(session_text.text)

func show_error(msg: String, auto_dismiss_delay: float = 0.0):
	printerr(msg)
	
	var msg_panel: MessagePanel = msg_scn.instantiate()
	errors.add_child(msg_panel)
	errors.move_child(msg_panel, 0)
	
	msg_panel.set_error_text(msg)
	if auto_dismiss_delay > 0.0:
		msg_panel.set_auto_dismiss(auto_dismiss_delay)

func clear_errors():
	for msg in errors.get_children():
		msg.dismiss()

func _on_devtools_pressed(id: int):
	if id == 0:
		jc.start_as_dev_server.call_deferred()
	elif id == 1:
		jam_client.client_session_request("127.0.0.1", 7437, "localdev", "localhost")
	elif id >= 3 and id <= 7:
		var client_num = id - 2
		jam_client.test_client_number = client_num
		
		var pop = $Menu/DevTools.get_popup()
		for x in range(3, 8):
			pop.set_item_checked(pop.get_item_index(x), x == id)
