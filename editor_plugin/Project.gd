@tool
extends JamEditorPluginPage

@onready var net_mode_box: OptionButton = $HB/Config/NetworkMode

@onready var log_popup: Popup = $LogPopup
@onready var log_display: TextEdit = $LogPopup/Logs

@onready var btn_deploy: Button = $HB/Config/BtnDeploy
@onready var btn_delete: Button = $HB/Config/BtnDelete
@onready var btn_sessions: Button = $HB/Config/BtnSessions

@onready var deploy_busy: Control = $HB/Releases/VB/PreparingBusy

@onready var platform_options: MenuButton = $HB/Config/PlatformOptions

@onready var no_deployments: Control = $HB/Releases/VB/NoDeployments

@onready var channels_root: VBoxContainer = $HB/Channels/VB/VB
@onready var releases_root: VBoxContainer = $HB/Releases/VB/VB

@onready var export_busy: ScopeLocker = $ExportBusy
@onready var export_prep_busy: ScopeLocker = $ExportPrepBusy
@onready var export_timeout: SpinBox = $HB/Config/Timeout/Minutes
@onready var export_parallel: CheckBox = $HB/Config/Parallel

@onready var log_request: HTTPRequest = $LogRequest

signal request_projects_update()
signal go_back()
signal session_page_selected(project_id: String, project_name: String)

var project_data = []

var refresh_retries = 0

var active_project
var active_id = ""

var waiting_for_export: bool = false
var auto_export: JamAutoExport

func _ready():
	auto_export = JamAutoExport.new()
	add_child(auto_export)

func _page_init():
	log_popup.visible = false
	btn_deploy.icon = dashboard.editor_icon("ArrowUp")
	btn_sessions.icon = dashboard.editor_icon("GuiVisibilityVisible")
	
	dashboard.load_locker.lock_changed.connect(_load_lock_changed)
	
	platform_options.get_popup().id_pressed.connect(_on_platform_option_selected)
	

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
	releases_root.visible = false
	if not await refresh_project():
		$AutoRefreshTimer.start(1.0)

func refresh_project(repeat: float = 0.0) -> bool:
	no_deployments.visible = false
	
	if len(active_id) < 1:
		dashboard.show_error("invalid project ID")
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
	
	var plat_menu = platform_options.get_popup()
	
	var available_channels = []
	while channels_root.get_child_count() > 0:
		var c = channels_root.get_child(0)
		channels_root.remove_child(c)
		c.queue_free()
	var sorted_channels = active_project.get("channels", [])
	sorted_channels.sort_custom(func (a, _b): return a.get("default_release", false))
	for channel in sorted_channels:
		available_channels.append(channel.get("name"))
		var channel_release = "No Release"
		for rel in active_project.get("releases", []):
			if rel.get("channel") == channel.get("name"):
				channel_release = "Release: %s" % [rel.get("id", "")]
		var summary = preload("res://addons/jam_launch/editor_plugin/ChannelSummary.tscn").instantiate()
		channels_root.add_child(summary)
		summary.set_channel(channel, channel_release)
		summary.update_channel.connect(_update_channel)
		
	while releases_root.get_child_count() > 0:
		var rel = releases_root.get_child(0)
		releases_root.remove_child(rel)
		rel.queue_free()
	var sorted_releases = active_project.get("releases", [])
	sorted_releases.reverse()
	for r in sorted_releases:
		var rel_summary = preload("res://addons/jam_launch/editor_plugin/ReleaseSummary.tscn").instantiate()
		releases_root.add_child(rel_summary)
		rel_summary.dashboard = dashboard
		rel_summary.build_busy.connect(_on_build_busy)
		export_busy.lock_changed.connect(rel_summary.on_export_active_changed)
		rel_summary.set_channels(available_channels)
		rel_summary.set_release(active_id, r)
		
		rel_summary.update_release.connect(_update_release)
		rel_summary.show_logs.connect(_show_logs)
	
	if len(sorted_releases) > 0:
		releases_root.visible = true
		var r = sorted_releases[0]
		var net_mode = r["network_mode"]
		net_mode_box.disabled = false
		if net_mode == "enet":
			net_mode_box.select(0)
		elif net_mode == "websocket":
			net_mode_box.select(1)
		#elif net_mode == "webrtc":
			#net_mode_box.select(2)
		else:
			net_mode = "enet"
			net_mode_box.select(-1)
		plat_menu.set_item_disabled(3, net_mode == "enet")
		
		for idx in range(plat_menu.item_count):
			plat_menu.set_item_checked(idx, false)
		for b in r["builds"]:
			var bname: String = b["name"]
			if "Linux" == bname:
				plat_menu.set_item_checked(0, true)
			elif "Windows" == bname:
				plat_menu.set_item_checked(1, true)
			elif "MacOS" == bname:
				plat_menu.set_item_checked(2, true)
			elif "Web" == bname:
				plat_menu.set_item_checked(3, true)
			elif "Android" == bname:
				plat_menu.set_item_checked(4, true)
	
		if r["id"] != null:
			var dir = self.get_script().get_path().get_base_dir()
			var deployment_cfg = ConfigFile.new()
			deployment_cfg.set_value("game", "id", "%s-%s" % [active_id, r["id"]])
			deployment_cfg.set_value("game", "network_mode", net_mode)
			deployment_cfg.set_value("game", "allow_guests", r.get("allow_guests", false))
			var err = deployment_cfg.save(dir + "/../deployment.cfg")
			if err != OK:
				dashboard.show_error("Failed to save current deployment configuration")
				return
	else:
		no_deployments.visible = true
		plat_menu.set_item_checked(0, true)
		plat_menu.set_item_checked(1, true)
		plat_menu.set_item_checked(2, true)
		plat_menu.set_item_checked(3, false)
		plat_menu.set_item_checked(4, false)

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
	
	refresh_project.call_deferred()

func _update_channel(channel: String, props: Dictionary):
	if len(active_id) < 1:
		return false
	
	if dashboard.load_locker.is_locked():
		dashboard.show_error("cannot update channel while handling another request")
		return
	var lock = dashboard.load_locker.get_lock()
	
	var res = await project_api.update_channel(active_id, channel, props)
	
	if res.errored:
		dashboard.show_error(res.error_msg)
	
	refresh_project.call_deferred()

func _on_build_busy():
	pass
	#print("setting auto-refresh")
	#$AutoRefreshTimer.start(3.0)

func _show_logs(log_url: String) -> void:
	log_display.text = "fetching logs..."
	log_popup.popup_centered()
	
	var err := log_request.request(log_url)
	if err != OK:
		log_display.text = "failed to fetch logs - error code %d" % err
		return
	
	var resp = await log_request.request_completed
	var code: int = resp[1]
	if code > 299:
		log_display.text = "failed to fetch logs - HTTP status %d" % code
		return
	
	var response_body: String = resp[3].get_string_from_utf8()
	log_display.text = response_body

func _on_btn_deploy_pressed() -> void:
	if not active_project:
		dashboard.show_error("Project is not correctly loaded")
		return
	
	if export_busy.is_locked() or export_prep_busy.is_locked():
		dashboard.show_error("Cannot release while release tasks are still active")
		return
	
	var net_mode
	if net_mode_box.get_selected_id() == 0:
		net_mode = "enet"
	elif net_mode_box.get_selected_id() == 1:
		net_mode = "websocket"
	#elif net_mode_box.get_selected_id() == 2:
		#net_mode = "webrtc"
	else:
		dashboard.show_error("Invalid network mode selection")
		return
	
	var builds = []
	var plat_menu = platform_options.get_popup()
	if plat_menu.is_item_checked(0):
		builds.append({
			"name": "Linux",
			"template_name": "jam-linux",
			"export_name": "%s.x86_64" % active_project.project_name
		})
	if plat_menu.is_item_checked(1):
		builds.append({
			"name": "Windows",
			"template_name": "jam-windows",
			"export_name": "%s.exe" % active_project.project_name
		})
	if plat_menu.is_item_checked(2):
		builds.append({
			"name": "MacOS",
			"template_name": "jam-macos",
			"export_name": "%s.app" % active_project.project_name
		})
	if plat_menu.is_item_checked(3):
		builds.append({
			"name": "Web",
			"template_name": "jam-web",
			"export_name": "index.html",
			"is_web": true
		})
	if plat_menu.is_item_checked(4):
		builds.append({
			"name": "Android",
			"template_name": "jam-android",
			"export_name": "%s.apk" % active_project.project_name,
			"no_zip": true
		})
	
	if net_mode in ["enet", "websocket"]:
		builds.append({
			"name": "Server",
			"template_name": "jam-linux-server",
			"export_name": "linux-server.x86_64",
			"is_server": true
		})
	
	var cfg = {
		"network_mode": net_mode,
		"export_timeout": export_timeout.value * 60,
		"parallel": export_parallel.button_pressed,
		"builds": builds
	}
	var prep_res := await _export_prep(cfg)
	if prep_res.errored:
		dashboard.show_error(prep_res.error_msg)
		return
	refresh_project.call_deferred()
	
	var export_res := await _do_export(cfg, prep_res.value)
	if export_res.errored:
		dashboard.show_error(export_res.error_msg)
	
	refresh_project.call_deferred(3.0)

func _export_prep(cfg: Dictionary) -> JamResult:
	if dashboard.load_locker.is_locked():
		return JamResult.err("cannot deploy while handling another request")
	var lock = dashboard.load_locker.get_lock()
	
	var busy_lock = export_prep_busy.get_lock()
	var res = await project_api.prepare_release(active_id, cfg)
	if !res:
		return JamResult.err("invalid result from local export attempt")
	if res.errored:
		return JamResult.err(res.error_msg)
	return JamResult.ok(res.data)

func _do_export(config: Dictionary, prepare_result: Dictionary) -> JamError:
	var busy_lock = export_busy.get_lock()
	var export_config = JamAutoExport.ExportConfig.new()
	export_config.network_mode = config["network_mode"]
	export_config.export_timeout = config["export_timeout"]
	export_config.parallel = config["parallel"]
	export_config.game_id = "%s-%s" % [active_id, prepare_result["id"]]
	export_config.build_configs = ([] as Array[JamAutoExport.BuildConfig])
	
	for b in config["builds"]:
		var c := JamAutoExport.BuildConfig.new()
		c.output_target = b["export_name"]
		c.template_name = b["template_name"]
		c.no_zip = b.get("no_zip", false)
		var mapped := false
		for t in prepare_result["builds"]:
			if t["build_name"] == b["name"]:
				c.presigned_post = t["upload_target"]
				c.log_presigned_post = t["log_upload_target"]
				mapped = true
				break
		if not mapped:
			return JamError.err("Failed to get upload target for '%s' build" % b["name"])
		
		export_config.build_configs.append(c)
	
	return await auto_export.auto_export(export_config)

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
	#elif net_mode_box.get_selected_id() == 2:
		#cfg["network_mode"] = "webrtc"
	else:
		dashboard.show_error("invalid network mode selected")
		return
	
	var plat_menu = platform_options.get_popup()
	if cfg["network_mode"] == "enet":
		plat_menu.set_item_disabled(3, true)
		plat_menu.set_item_checked(3, false)
	else:
		plat_menu.set_item_disabled(3, false)

func _on_platform_option_selected(idx: int):
	var menu = platform_options.get_popup()
	if menu.is_item_disabled(idx):
		return
	menu.set_item_checked(idx, not menu.is_item_checked(idx))
	menu.show.call_deferred()


func _on_export_busy_lock_changed(locked):
	waiting_for_export = locked

func _on_export_prep_busy_lock_changed(locked):
	deploy_busy.visible = locked
	releases_root.visible = not locked


func _on_add_channel_pressed() -> void:
	$CreateChannel/VB/NewChannelName.clear()
	$CreateChannel.popup_centered()
	

func _on_create_channel_confirmed() -> void:
	var lock = $ChannelUpdateBusy.get_lock()
	var res = await project_api.create_channel(active_id, $CreateChannel/VB/NewChannelName.text)
	if res.errored:
		dashboard.show_error(res.error_msg)
	
	refresh_project.call_deferred()


func _on_channel_update_busy_lock_changed(locked: bool) -> void:
	$HB/Channels/VB/ChangeBusy.visible = locked
	$HB/Channels/VB/VB.visible = not locked
