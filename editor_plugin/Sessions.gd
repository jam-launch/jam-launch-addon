@tool
extends VBoxContainer

@onready var title: Label = $TopBar/Title

@onready var load_locker: ScopeLocker = $LoadLocker

@onready var log_popup: Popup = $LogPopup
@onready var log_display: TextEdit = $LogPopup/Logs

@onready var session_list = $M/HB/SC/Sessions
@onready var session_data: TextEdit = $M/HB/Details/SessionData

@onready var err_stack: VBoxContainer = $Errors
var msg_scn = preload("res://addons/jam_launch/ui/MessagePanel.tscn")

signal go_back()

var project_data = []
var project_api: ProjectApi

var refresh_retries = 0

var project_id: String
var release_id: String
var sessions: Array = []
var session_details: Dictionary = {}

func _dashboard():
	return get_parent()

func _plugin() -> EditorPlugin:
	return _dashboard().plugin

func initialize():
	log_popup.visible = false
	project_api = _dashboard().project_api

func show_game(proj_id: String, project_name: String, rel_id: String):
	project_id = proj_id
	release_id = rel_id
	$TopBar/BtnBack.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Back", "EditorIcons")
	$TopBar/BtnRefresh.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Reload", "EditorIcons")
	title.text = project_name
	refresh_sessions()

func refresh_sessions():
	if load_locker.is_locked():
		show_error("cannot refresh sessions while loading...", 5.0)
		return
		
	var lock = load_locker.get_lock()
	session_data.text = ""
	
	for c in session_list.get_children():
		c.queue_free()
		
	var res = await project_api.get_sessions(project_id, true)
	
	if res.errored:
		show_error(res.error_msg)
		return
	
	sessions = res.data["sessions"]
	
	for s in sessions:
		var hb = HBoxContainer.new()
		
		var id = Button.new()
		var rt = Time.get_datetime_dict_from_datetime_string(s["created_at"], false)
		var now_utc = Time.get_datetime_dict_from_system(true)
		var time_text = "%s-%s-%s %s:%s" % [
			rt["year"],
			rt["month"],
			rt["day"],
			rt["hour"],
			rt["minute"],
		]
		if rt["year"] == now_utc["year"]:
			if rt["month"] == now_utc["month"]:
				if rt["day"] == now_utc["day"]:
					time_text = "%s:%s" % [
						rt["hour"],
						rt["minute"],
					]
				else:
					time_text = "%s %s:%s" % [
						rt["day"],
						rt["hour"],
						rt["minute"],
					]
			else:
				time_text = "%s-%s %s:%s" % [
					rt["month"],
					rt["day"],
					rt["hour"],
					rt["minute"],
				]
		id.text = time_text
		id.pressed.connect(_get_session_details.bind(project_id, release_id, s["id"]))
		hb.add_child(id)
		
		var logs = Button.new()
		logs.text = "Logs"
		logs.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Script", "EditorIcons")
		logs.pressed.connect(_show_logs.bind(project_id, release_id, s.id))
		hb.add_child(logs)
		
		session_list.add_child(hb)
	
	if len(sessions) < 1:
		var no_sessions = Label.new()
		no_sessions.text = "No sessions to display"
		session_list.add_child(no_sessions)


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
	
	session_data.text = JSON.stringify(res.data, "  ")
	

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
			log_text += Time.get_datetime_string_from_unix_time(e["t"])
			log_text += " " + e["msg"] + "\n"
		log_display.text = log_text

func _on_btn_refresh_pressed() -> void:
	refresh_sessions()

func _on_btn_back_pressed() -> void:
	go_back.emit()

func _on_log_out_btn_pressed() -> void:
	_dashboard().jwt().clear()

func show_message(msg: String, auto_dismiss: float = 0.0):
	var msg_box := msg_scn.instantiate()
	err_stack.add_child(msg_box)
	msg_box.message = msg
	if auto_dismiss > 0.0:
		msg_box.set_auto_dismiss(auto_dismiss)

func show_error(msg: String, auto_dismiss: float = 0.0):
	var msg_box := msg_scn.instantiate()
	err_stack.add_child(msg_box)
	msg_box.set_error_text(msg)
	if auto_dismiss > 0.0:
		msg_box.set_auto_dismiss(auto_dismiss)


func _on_load_locker_lock_changed(locked: bool):
	$TopBar/BtnRefresh.disabled = locked
