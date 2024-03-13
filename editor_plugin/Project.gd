@tool
extends JamEditorPluginPage

@onready var net_mode_box: OptionButton = $HB/Config/NetworkMode

@onready var log_popup: Popup = $LogPopup
@onready var log_display: TextEdit = $LogPopup/Logs

@onready var btn_deploy: Button = $HB/Config/BtnDeploy
@onready var btn_delete: Button = $HB/Config/BtnDelete
@onready var btn_sessions: Button = $HB/Config/BtnSessions

@onready var deploy_busy: Control = $HB/Releases/VB/PreparingBusy
@onready var latest_release: Control = $HB/Releases/VB/ReleaseSummary

@onready var no_deployments: Control = $HB/Releases/VB/NoDeployments

signal request_projects_update()
signal go_back()
signal session_page_selected(project_id: String, project_name: String)

var project_data = []

var refresh_retries = 0

var active_project
var active_id = ""


func _page_init():
	log_popup.visible = false
	btn_deploy.icon = dashboard.editor_icon("ArrowUp")
	btn_sessions.icon = dashboard.editor_icon("GuiVisibilityVisible")
	
	latest_release.dashboard = dashboard
	dashboard.load_locker.lock_changed.connect(_load_lock_changed)

func show_init():
	if active_project:
		dashboard.toolbar_title.text = active_project["project_name"]

func _load_lock_changed(locked: bool):
	btn_deploy.disabled = locked
	net_mode_box.disabled = locked
	btn_delete.disabled = locked

func refresh_page():
	refresh_project()

func show_project(project_id: String, project_name: String = "..."):
	active_id = project_id
	dashboard.toolbar_title.text = project_name
	latest_release.visible = false
	refresh_project()

func refresh_project(repeat: float = 0.0) -> bool:
	no_deployments.visible = false
	
	if len(active_id) < 1:
		return false
	
	if dashboard.load_locker.is_locked():
		return false
	var lock = dashboard.load_locker.get_lock()
	
	var res = await project_api.get_project(active_id)
	
	if res.errored:
		dashboard.show_error(res.error_msg)
		return false
		
	setup_project_data(res.data)
	if (repeat > 0.0):
		$AutoRefreshTimer.start(repeat)
	return true

func setup_project_data(p):
	
	active_project = p
	dashboard.toolbar_title.text = p["project_name"]
	
	var net_mode = active_project["configs"][0]["network_mode"]
	net_mode_box.disabled = false
	if net_mode == "enet":
		net_mode_box.select(0)
	elif net_mode == "websocket":
		net_mode_box.select(1)
	elif net_mode == "webrtc":
		net_mode_box.select(2)
	else:
		net_mode = "enet"
		net_mode_box.select(-1)

	if "releases" in active_project and len(active_project["releases"]) > 0:
		latest_release.visible = true
		var r = active_project["releases"][len(active_project["releases"]) - 1]
		
		latest_release.set_release(active_id, r)
		
		if r["game_id"] != null:
			var dir = self.get_script().get_path().get_base_dir()
			var deployment_cfg = ConfigFile.new()
			deployment_cfg.set_value("game", "id", r["game_id"])
			deployment_cfg.set_value("game", "network_mode", net_mode)
			var err = deployment_cfg.save(dir + "/../deployment.cfg")
			if err != OK:
				dashboard.show_error("Failed to save current deployment configuration")
				return
	else:
		no_deployments.visible = true

func _update_release(release_id: String, props: Dictionary):
	if len(active_id) < 1:
		return false
	
	if dashboard.load_locker.is_locked():
		dashboard.show_error("cannot update release while handling another request")
		return
	var lock = dashboard.load_locker.get_lock()
	
	var res = await project_api.update_release(active_id, release_id, props)
	
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
	
	refresh_project.call_deferred()

func _show_logs(p, r, log_id) -> void:
	log_popup.popup_centered_ratio(0.8)
	log_display.text = "loading logs..."
	print("loading %s logs for %s-%s" % [log_id, p, r])
	var res = await project_api.get_build_logs(p, r, log_id)
	if res.errored:
		log_display.text = "Error fetching logs: %s" % res.error_msg
	else:
		print("got %d log events..." % len(res.data["events"]))
		var log_text = ""
		for e in res.data["events"]:
			log_text += Time.get_datetime_string_from_unix_time(e["t"] / 1000.0)
			log_text += " " + e["msg"] + "\n"
		log_display.text = log_text

func _on_btn_deploy_pressed() -> void:
	if dashboard.load_locker.is_locked():
		dashboard.show_error("cannot deploy while handling another request")
		return
	var lock = dashboard.load_locker.get_lock()
	
	var net_mode
	if net_mode_box.get_selected_id() == 0:
		net_mode = "enet"
	elif net_mode_box.get_selected_id() == 1:
		net_mode = "websocket"
	elif net_mode_box.get_selected_id() == 2:
		net_mode = "webrtc"
	else:
		dashboard.show_error("Invalid network mode selection")
		return
	
	deploy_busy.visible = true
	var res = await project_api.local_build_project(active_id, {"network_mode": net_mode})
	if res.errored:
		dashboard.show_error(res.error_msg)
	await get_tree().create_timer(1.5)
	deploy_busy.visible = false
	refresh_project.call_deferred(2.0)
	

func _on_auto_refresh_timer_timeout():
	$AutoRefreshTimer.stop()
	await refresh_project()

func _on_btn_delete_pressed():
	$ConfirmDelete.popup()

func _on_confirm_delete_confirmed():
	if dashboard.load_locker.is_locked():
		dashboard.show_error("cannot delete while handling another request")
		return
	var lock = dashboard.load_locker.get_lock()
	
	var res = await project_api.delete_project(active_id)
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
	dashboard.pages.go_back()

func _on_btn_sessions_pressed():
	session_page_selected.emit(active_id, active_project["project_name"])

func _on_config_item_selected(_index):
	if not active_project:
		return
	
	if dashboard.load_locker.is_locked():
		dashboard.show_error("cannot submit config while handling another request")
		return
	var lock = dashboard.load_locker.get_lock()
	
	var cfg = {}
	if net_mode_box.get_selected_id() == 0:
		cfg["network_mode"] = "enet"
	elif net_mode_box.get_selected_id() == 1:
		cfg["network_mode"] = "websocket"
	elif net_mode_box.get_selected_id() == 2:
		cfg["network_mode"] = "webrtc"
	else:
		return
	
	var res = await project_api.post_config(active_id, cfg)
	
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
