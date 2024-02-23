extends JamClientUI

@onready var pages: JamPageStack = $CC/M/M/PageStack
@onready var home_page: Control = $CC/M/M/PageStack/Home
@onready var host_page: Control = $CC/M/M/PageStack/HostGame
@onready var join_code_page: Control = $CC/M/M/PageStack/JoinGameCode
@onready var session_page: Control = $CC/M/M/PageStack/Session

@onready var errors: Control = $Bottom/ErrorArea/Errors
@onready var version_info: Label = $Bottom/M/VersionInfo

@onready var start_join: Button = $CC/M/M/PageStack/Home/VB/StartJoin
@onready var start_host: Button = $CC/M/M/PageStack/Home/VB/StartHost
@onready var no_deploy_lbl: Label = $CC/M/M/PageStack/Home/NoDeployment
@onready var dev_tools: MenuButton = $CC/M/M/PageStack/Home/VB/DevTools

@onready var join_busy: Control = $CC/M/M/PageStack/JoinGameCode/Busy
@onready var join_busy_lock: ScopeLocker = $CC/M/M/PageStack/JoinGameCode/JoinBusy
@onready var join_code_edit: LineEdit = $CC/M/M/PageStack/JoinGameCode/Entry/EnterCode/JoinCode
@onready var join_btn: Button = $CC/M/M/PageStack/JoinGameCode/Entry/EnterCode/JoinWithCode

@onready var host_busy: Control = $CC/M/M/PageStack/HostGame/Busy
@onready var host_busy_lock: ScopeLocker = $CC/M/M/PageStack/HostGame/HostBusy
@onready var host_region_select: OptionButton = $CC/M/M/PageStack/HostGame/G/RegionSelect
@onready var host_btn: Button = $CC/M/M/PageStack/HostGame/HB/Host

const REFRESH_NORMAL = 4.0
const REFRESH_FAST = 2.0
const REFRESH_SLOW = 5.0
@onready var session_refresh_timer: Timer = $CC/M/M/PageStack/Session/SessionRefresh
@onready var join_code_btn: Button = $CC/M/M/PageStack/Session/M/VB/JoinInfo/JoinCodeCopy
@onready var start_game_btn: Button = $CC/M/M/PageStack/Session/M/VB/StartBox/StartGame
@onready var session_server_progress: Control = $CC/M/M/PageStack/Session/M/VB/StartBox/Busy/ProgressBar
@onready var player_grid: GridContainer = $CC/M/M/PageStack/Session/M/VB/Players/M/VB/Grid

var session_token: String = ""
var session_result: JamClientApi.GameSessionResult = null:
	set(val):
		session_result = val
		session_server_progress.get_parent().visible = false
		start_game_btn.visible = false
		
		if session_result == null:
			return
		elif session_result.has_unusable_status():
			show_error("server in unusable status - quitting session")
			pages.show_page_node(home_page, false)
		else:
			while player_grid.get_child_count() > 0:
				var c := player_grid.get_child(0)
				player_grid.remove_child(c)
				c.queue_free()
			
			for p in session_result.players:
				var plbl := Label.new()
				plbl.text = p.user_id
				player_grid.add_child(plbl)
			
			if session_result.busy_progress() < 1.0:
				session_server_progress.value = 100 * session_result.busy_progress()
				session_server_progress.get_parent().visible = true
			else:
				start_game_btn.visible = true

func _ready():
	var gid_parts = game_id.split("-")
	var version_number = gid_parts[len(gid_parts) - 1]
	version_info.text = "version %s" % version_number
	version_info.text += " - jam launch %s" % client_api.addon_version
	if OS.is_debug_build():
		dev_tools.get_popup().id_pressed.connect(_on_devtools_pressed)
		version_info.text += " (debug)"
	else:
		dev_tools.visible = false
	
	pages.show_page_node(home_page, false)
	
	if not jam_connect.has_deployment:
		set_enable_deployments(false)
	
	jam_connect.local_player_joining.connect(_on_joining_game)
	jam_connect.local_player_left.connect(_on_leaving_game)

func _on_joining_game():
	start_game_btn.disabled = true

func _on_leaving_game():
	start_game_btn.disabled = false
	session_result = null
	session_token = ""
	pages.show_page_node(home_page, false)

func _on_devtools_pressed(id: int):
	if id == 0:
		jam_connect.start_as_dev_server.call_deferred()
	elif id == 1:
		jam_client.client_session_request("127.0.0.1", 7437, "localdev", "localhost")
	elif id >= 3 and id <= 7:
		var client_num = id - 2
		jam_client.test_client_number = client_num
		
		var pop = dev_tools.get_popup()
		for x in range(3, 8):
			pop.set_item_checked(pop.get_item_index(x), x == id)

func set_enable_deployments(enable: bool):
	start_host.disabled = !enable
	start_join.disabled = !enable
	no_deploy_lbl.visible = !enable

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("got quit notification")
		if session_result != null:
			var res = await client_api.leave_game_session(session_result.session_id)
			if res.errored:
				push_error(res.error_msg)
			else:
				print("left game session")
		get_tree().quit()
#
func enter_session(session_id: String, token: String) -> bool:
	session_result = await client_api.get_game_session(session_id)
	if session_result.errored:
		show_error(session_result.error_msg)
		return false
	
	if len(session_result.join_id):
		join_code_btn.text = session_result.join_id
		join_code_btn.get_parent().visible = true
	else:
		join_code_btn.get_parent().visible = false
	
	session_token = token
	session_refresh_timer.start(REFRESH_NORMAL)
	pages.show_page_node(session_page)
	return true

func exit_session() -> bool:
	session_refresh_timer.stop()
	session_token = ""
	if session_result == null:
		return false
	var res := await client_api.leave_game_session(session_result.session_id)
	session_result = null
	if res.errored:
		show_error(res.error_msg)
		return false
	else:
		return true

func leave_game_session():
	exit_session()


func _on_page_stack_tab_changed(_tab):
	if not pages:
		return
	if pages.get_current_tab_control() != session_page:
		exit_session()

func _on_start_join_pressed():
	pages.show_page_node(join_code_page)

func _on_start_host_pressed():
	pages.show_page_node(host_page)

func _on_host_pressed():
	var region := "us-east-2"
	var region_id = host_region_select.get_item_id(host_region_select.selected)
	if region_id == 0:
		region = "us-east-2"
	elif region_id == 1:
		region = "eu-west-2"
	
	var _lock = host_busy_lock.get_lock()
	
	var res := await client_api.create_game_session(region)
	if res.errored:
		show_error(res.error_msg)
		return
	
	if not await enter_session(res.data["id"] as String, res.data["join_token"] as String):
		print("fail")
		res = await client_api.leave_game_session(res.data["id"] as String)
		if res.errored:
			show_error("failed to leave game session after failing to enter: %s" % res.error_msg)

func _on_host_busy_lock_changed(locked):
	host_btn.get_parent().visible = not locked
	host_region_select.get_parent().visible = not locked
	host_busy.visible = locked

func _on_join_with_code_pressed():
	if join_busy_lock.is_locked():
		show_error("cannot trigger join while join is already in progress")
		return
	var _lock = join_busy_lock.get_lock()
	var res := await client_api.join_game_session(join_code_edit.text)
	if res.errored:
		show_error(res.error_msg)
		return
	if not await enter_session(res.data["session_id"] as String, res.data["join_token"] as String):
		return
	join_code_edit.clear()

func _on_paste_code_pressed():
	join_code_edit.text = DisplayServer.clipboard_get()
	_on_join_with_code_pressed()

func _on_join_code_text_submitted(_new_text):
	_on_join_with_code_pressed()

func _on_join_code_text_changed(new_text):
	var upper = new_text.to_upper()
	if upper != new_text:
		join_code_edit.text = upper
		join_code_edit.caret_column = len(upper)
	join_btn.disabled = len(upper) != 4

func _on_join_busy_lock_changed(locked):
	join_btn.get_parent().get_parent().visible = not locked
	join_busy.visible = locked

func _on_session_refresh_timeout():
	if session_result == null or session_result.has_unusable_status():
		return
		
	var res := await client_api.get_game_session(session_result.session_id)
	if res.errored:
		show_error("session refresh error: " + res.error_msg, REFRESH_SLOW)
		session_refresh_timer.start(REFRESH_SLOW)
		return
	
	if res.busy_progress() == 1.0:
		session_refresh_timer.start(REFRESH_NORMAL)
	else:
		session_refresh_timer.start(REFRESH_FAST)
	session_result = res

func show_error(msg: String, auto_dismiss_delay: float = 0.0):
	printerr(msg)
	var msg_panel: MessagePanel = preload("../MessagePanel.tscn").instantiate()
	errors.add_child(msg_panel)
	errors.move_child(msg_panel, 0)
	msg_panel.set_error_text(msg)
	if auto_dismiss_delay > 0.0:
		msg_panel.set_auto_dismiss(auto_dismiss_delay)

func clear_errors():
	for msg in errors.get_children():
		msg.dismiss()

func _on_join_code_copy_pressed():
	DisplayServer.clipboard_set(join_code_btn.text)

func _on_leave_session_pressed():
	pages.go_back()

func _on_host_back_pressed():
	pages.go_back()

func _on_join_code_back_pressed():
	pages.go_back()

func _on_start_game_pressed():
	if session_result == null or session_result.busy_progress() < 1.0:
		show_error("cannot start game without a session that is ready", 5.0)
		return
	session_refresh_timer.stop()
	var addr := session_result.addresses[0]
	jam_client.client_session_request(addr.ip, addr.port, session_token, addr.domain)

