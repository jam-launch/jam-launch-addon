@tool
extends JamEditorPluginPage

@onready var load_locker: ScopeLocker = $LoadLocker

@onready var log_popup: Popup = $LogPopup
@onready var log_display: TextEdit = $LogPopup/Logs

@onready var no_sessions_lbl: Label = $M/HB/VB/SC/VB/NoSessions
@onready var session_list: ItemList = $M/HB/VB/SC/VB/SessionList
@onready var session_details_layout = $M/HB/Details
@onready var session_title: Label = $M/HB/Details/Session
@onready var session_data: TextEdit = $M/HB/Details/SessionData

@onready var terminate_btn: Button = $M/HB/Details/HB/BtnDelete
var disable_terminate := false

var project_data = []

var refresh_retries = 0

var project_name: String
var project_id: String
var sessions: Array = []

var filter_active_sessions := true

var session_details: Dictionary = {}:
	set(val):
		session_details = val
		var sid = session_details.get("id")
		if sid == null:
			session_details_layout.visible = false
		else:
			session_title.text = "Session " + session_details.get("join_code", sid)
			session_details_layout.visible = true

func _page_init():
	$M/HB/Details/HB/BtnLogs.icon = dashboard.editor_icon("Script")
	session_details_layout.visible = false
	log_popup.visible = false

func show_init():
	if len(project_name) > 0:
		dashboard.toolbar_title.text = "Sessions: %s" % project_name

func refresh_page():
	refresh_sessions()

func show_game(proj_id: String, proj_name: String):
	project_id = proj_id
	project_name = proj_name
	dashboard.toolbar_title.text = "Sessions: %s" % project_name
	refresh_sessions()

func refresh_sessions():
	if len(project_id) < 1:
		return
	
	if load_locker.is_locked():
		show_error("cannot refresh sessions while loading...", 5.0)
		return
	
	var _lock = load_locker.get_lock()
	session_details = {}
	session_list.clear()
	session_list.visible = false
	no_sessions_lbl.visible = false
		
	var res = await project_api.get_sessions(project_id, filter_active_sessions)
	
	if res.errored:
		show_error(res.error_msg)
		return
	
	sessions = res.data["sessions"]
	
	for s in sessions:
		var rt = Time.get_datetime_dict_from_datetime_string(s["created_at"], false)
		var now_utc = Time.get_datetime_dict_from_system(true)
		var time_text = "%s-%02d-%02d %02d:%02d" % [
			rt["year"],
			rt["month"],
			rt["day"],
			rt["hour"],
			rt["minute"],
		]
		if rt["year"] == now_utc["year"]:
			if rt["month"] == now_utc["month"]:
				if rt["day"] == now_utc["day"]:
					time_text = "%02d:%02d" % [
						rt["hour"],
						rt["minute"],
					]
				else:
					time_text = "%02d %02d:%02d" % [
						rt["day"],
						rt["hour"],
						rt["minute"],
					]
			else:
				time_text = "%02d-%02d %02d:%02d" % [
					rt["month"],
					rt["day"],
					rt["hour"],
					rt["minute"],
				]
		session_list.add_item(time_text)
	
	if len(sessions) < 1:
		no_sessions_lbl.visible = true
	else:
		session_list.visible = true

func _get_session_details(p, r, s):
	if load_locker.is_locked():
		show_error("cannot get session details while loading...", 5.0)
		return
	session_data.text = ""
	var lock = load_locker.get_lock()
	var res = await project_api.get_session(p, r, s)
	
	if res.errored:
		show_error("Failed to get session %s: %s" % [s, res.error_msg])
		return
	
	session_details = res.data
	session_data.text = JSON.stringify(res.data, "  ")
	
	disable_terminate = session_details.get("force_terminated", false)
	terminate_btn.disabled = disable_terminate

func _show_logs(p, r, s) -> void:
	log_popup.popup_centered_ratio(0.8)
	log_display.text = "loading logs..."
	var res = await project_api.get_session_logs(p, r, s)
	if res.errored:
		log_display.text = "Error fetching logs: %s" % res.error_msg
	else:
		print("got %d log events..." % len(res.data["events"]))
		var log_text = ""
		for e in res.data["events"]:
			log_text += Time.get_datetime_string_from_unix_time(e["t"] / 1000.0)
			log_text += " " + e["msg"] + "\n"
		log_display.text = log_text

func show_error(msg: String, auto_dismiss: float=0.0):
	dashboard.show_error(msg, auto_dismiss)

func _on_load_locker_lock_changed(locked: bool):
	$M/HB/Details/HB/BtnLogs.disabled = locked
	terminate_btn.disabled = locked or disable_terminate

func _on_btn_logs_pressed():
	var session_id = session_details.get("id")
	var release_id = session_details.get("release_id")
	if session_id == null or release_id == null:
		show_error("Cannot get logs - session details are not correctly loaded")
		return
	_show_logs(project_id, release_id, session_id)

func _on_btn_delete_pressed():
	$ConfirmDelete.popup()

func _on_confirm_delete_confirmed():
	var session_id = session_details.get("id")
	var release_id = session_details.get("release_id")
	if session_id == null or release_id == null:
		show_error("Cannot delete session - session details are not correctly loaded")
		return
	
	var res = await project_api.terminate_session(project_id, release_id, session_id)
	if res.errored:
		show_error(res.error_msg)
		return
	
	session_details = {}
	_get_session_details(project_id, release_id, session_id)

func _on_session_list_item_selected(index):
	if len(sessions) <= index or index < 0:
		return
	
	var s = sessions[index]
	_get_session_details(project_id, s["release_id"], s["id"])

func _on_filter_item_selected(index):
	if index == 0:
		filter_active_sessions = true
		terminate_btn.visible = true
		refresh_sessions()
	elif index == 1:
		filter_active_sessions = false
		terminate_btn.visible = false
		refresh_sessions()
