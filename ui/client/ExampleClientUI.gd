extends JamClientUI

@onready var pages: JamPageStack = $CC/M/M/PageStack
@onready var gjwt_page: Control = $CC/M/M/PageStack/GjwtEntry
@onready var home_page: Control = $CC/M/M/PageStack/Home
@onready var host_page: Control = $CC/M/M/PageStack/HostGame
@onready var join_code_page: Control = $CC/M/M/PageStack/JoinGameCode
@onready var session_page: Control = $CC/M/M/PageStack/Session

@onready var errors: Control = $Bottom/ErrorArea/Errors
@onready var version_info: Label = $Bottom/M/VersionInfo

@onready var device_auth: DeviceAuthUI = $CC/M/M/PageStack/GjwtEntry/Entry/DeviceAuth
@onready var manual_auth: Control = $CC/M/M/PageStack/GjwtEntry/Entry/Manual
@onready var gjwt_entry: Control = $CC/M/M/PageStack/GjwtEntry/Entry
@onready var gjwt_busy: Control = $CC/M/M/PageStack/GjwtEntry/Busy

@onready var start_join: Button = $CC/M/M/PageStack/Home/VB/StartJoin
@onready var start_host: Button = $CC/M/M/PageStack/Home/VB/StartHost
@onready var no_deploy_lbl: Label = $CC/M/M/PageStack/Home/NoDeployment
@onready var dev_tools: MenuButton = $CC/M/M/PageStack/Home/VB/DevTools
@onready var logged_in: Label = $CC/M/M/PageStack/Home/VB/LoggedIn

@onready var join_busy: Control = $CC/M/M/PageStack/JoinGameCode/Busy
@onready var join_busy_lock: ScopeLocker = $CC/M/M/PageStack/JoinGameCode/JoinBusy
@onready var join_code_edit: LineEdit = $CC/M/M/PageStack/JoinGameCode/Entry/EnterCode/JoinCode
@onready var join_btn: Button = $CC/M/M/PageStack/JoinGameCode/Entry/EnterCode/JoinWithCode

@onready var host_busy: Control = $CC/M/M/PageStack/HostGame/Busy
@onready var host_busy_lock: ScopeLocker = $CC/M/M/PageStack/HostGame/HostBusy
@onready var host_region_select: OptionButton = $CC/M/M/PageStack/HostGame/G/RegionSelect
@onready var host_btn: Button = $CC/M/M/PageStack/HostGame/HB/Host

@onready var guest_auth_ui: VBoxContainer = $CC/M/M/PageStack/GjwtEntry/Entry/Manual/Guest
@onready var local_launch_ui: VBoxContainer = $CC/M/M/PageStack/GjwtEntry/Entry/Manual/Local

const REFRESH_NORMAL = 4.0
const REFRESH_FAST = 2.0
const REFRESH_SLOW = 5.0
@onready var session_refresh_timer: Timer = $CC/M/M/PageStack/Session/SessionRefresh
@onready var join_code_btn: Button = $CC/M/M/PageStack/Session/M/VB/JoinInfo/JoinCodeCopy
@onready var start_game_btn: Button = $CC/M/M/PageStack/Session/M/VB/StartBox/StartGame
@onready var session_server_progress: Control = $CC/M/M/PageStack/Session/M/VB/StartBox/Busy/ProgressBar
@onready var player_grid: GridContainer = $CC/M/M/PageStack/Session/M/VB/Players/M/VB/Grid

var JOIN_ID_MIN_LEN: int = 4

var did_join_game: bool = false

var session_token: String = ""
var session_result: JamClientApi.GameSessionResult = null:
	set(val):
		session_result = val
		session_server_progress.get_parent().visible = false
		start_game_btn.visible = false
		
		if session_result == null:
			while player_grid.get_child_count() > 0:
				var c := player_grid.get_child(0)
				player_grid.remove_child(c)
				c.queue_free()
			session_server_progress.value = 0
			session_server_progress.get_parent().visible = true
			start_game_btn.visible = false
			pages.show_page_node(home_page, false)
			return
		elif session_result.has_unusable_status():
			show_error("server in unusable status - quitting session")
			session_result = null
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
	if OS.is_debug_build() and OS.get_name() != "Android":
		dev_tools.get_popup().id_pressed.connect(_on_devtools_pressed)
		version_info.text += " (debug)"
		local_launch_ui.visible = true
	else:
		dev_tools.visible = false
		local_launch_ui.visible = false
	
	var allow_guests = await client_api.check_guests_allowed(jam_connect.game_id)
	jam_connect.allow_guests = not allow_guests.errored
	guest_auth_ui.visible = jam_connect.allow_guests
	
	device_auth.active_auth.connect(_on_active_device_auth)
	device_auth.has_token.connect(_set_gjwt)
	jam_connect.gjwt_acquired.connect(_on_gjwt_acquired)
	jam_client.fetching_test_gjwt.connect(_on_gjwt_fetch_busy)
	_on_gjwt_fetch_busy(jam_client.gjwt_fetch_busy)
	
	if jam_client.jwt.has_token():
		_on_gjwt_acquired()
	else:
		pages.show_page_node(gjwt_page, false)
	
	if not jam_connect.has_deployment:
		set_enable_deployments(false)
	
	jam_connect.local_player_joining.connect(_on_joining_game)
	jam_connect.local_player_left.connect(_on_leaving_game)

func _on_active_device_auth(active: bool):
	manual_auth.visible = !active
	
func _on_gjwt_fetch_busy(busy: bool):
	gjwt_entry.visible = not busy
	gjwt_busy.visible = busy
	if busy:
		pages.show_page_node(gjwt_page, false)

func _on_gjwt_acquired():
	pages.show_page_node(home_page, false)
	logged_in.text = "Logged in as\n%s" % jam_client.jwt.username

var joined_players = {}

func update_player_grid():
	while player_grid.get_child_count() > 0:
		var c := player_grid.get_child(0)
		player_grid.remove_child(c)
		c.queue_free()

func _on_joining_game():
	start_game_btn.disabled = true
	did_join_game = true

func _on_leaving_game():
	if did_join_game:
		start_game_btn.disabled = false
		session_result = null
		session_token = ""
		did_join_game = false

func _on_devtools_pressed(id: int):
	if id == 0:
		jam_connect.start_as_dev_server.call_deferred()
	elif id == 1:
		jam_client.client_session_request("localhost", 7437, "localdev")
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

func enter_session(session_id: String, token: String) -> bool:
	var res := await client_api.get_game_session(session_id)
	if res.errored:
		show_error(res.error_msg)
		return false
	session_result = res
	
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

	if session_result != null:
		var res := await client_api.leave_game_session(session_result.session_id)
		session_result = null
		
		if res.errored:
			show_error(res.error_msg)
			return false
		else:
			return true
	else:
		return false

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
	
	if not await enter_session(res.data["id"] as String, res.data["token"] as String):
		res = await client_api.leave_game_session(res.data["id"] as String)
		if res.errored:
			show_error("failed to leave game session after failing to enter: %s" % res.error_msg)

func _on_host_busy_lock_changed(locked):
	host_btn.get_parent().visible = not locked
	host_region_select.get_parent().visible = not locked
	host_busy.visible = locked
	
	start_host.get_parent().visible = not locked

func _on_join_with_code_pressed():
	if join_busy_lock.is_locked():
		show_error("cannot trigger join while join is already in progress")
		return
	var _lock = join_busy_lock.get_lock()
	var res := await client_api.join_game_session(join_code_edit.text)
	if res.errored:
		show_error(res.error_msg)
		return
	if not await enter_session(res.data["id"] as String, res.data["token"] as String):
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
	join_btn.disabled = len(upper) < JOIN_ID_MIN_LEN

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

func show_error(msg: String, auto_dismiss_delay: float=0.0):
	printerr(msg)
	var msg_panel: MessagePanel = preload ("../MessagePanel.tscn").instantiate()
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
	if session_result and session_result.busy_progress() == 1.0:
		session_refresh_timer.stop()
		var addr := session_result.address
		var addrParts := addr.rsplit(":", false, 1)
		if len(addrParts) < 2:
			show_error("cannot start game without a valid session address", 5.0)
			return
		jam_client.client_session_request(addrParts[0], addrParts[1].to_int(), session_token)
	else:
		show_error("cannot start game without a session that is ready", 5.0)
		return

func _set_gjwt(gjwt: String):
	jam_client.set_gjwt(gjwt)
	if !OS.is_debug_build() or OS.get_name() == "Android":
		jam_client.persist_gjwt()

func _on_client_pressed():
	jam_client.client_session_request("localhost", 7437, "localdev")

func _on_server_pressed():
	jam_connect.start_as_dev_server.call_deferred()

func _on_device_auth_errored(msg: String):
	show_error(msg)

func _on_guest_auth_pressed() -> void:
	_on_gjwt_fetch_busy(true)
	
	var res = await jam_client.api.get_guest_jwt(jam_connect.game_id)
	if res.errored:
		show_error(res.error_msg)
	else:
		jam_client.set_gjwt(res.data["token"])
	
	_on_gjwt_fetch_busy.call_deferred(false)
