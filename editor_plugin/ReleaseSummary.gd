@tool
extends MarginContainer

@onready var title: RichTextLabel = $M/HB/VB/Title
@onready var link_nav: Button = $M/HB/VB/Config/MC/VB/HB/PageLink
@onready var link_copy: Button = $M/HB/VB/Config/MC/VB/HB/Copy
@onready var check_public: CheckButton = $M/HB/VB/Config/MC/VB/Access/CheckPublic
@onready var access_icon: TextureRect = $M/HB/VB/Config/MC/VB/Access/AccessIcon
@onready var jobs: GridContainer = $M/HB/M/PC/MC/VB/Jobs

@onready var check_guests: CheckButton = $M/HB/VB/Config/MC/VB/Guests/CheckGuests

@onready var channel_menu: MenuButton = $M/HB/VB/Config/MC/VB/SetChannel
@onready var current_channel: Control = $M/HB/VB/Config/MC/VB/CurrentChannel
@onready var current_channel_lbl: Label = $M/HB/VB/Config/MC/VB/CurrentChannel/Channel

var dashboard: JamEditorPluginDashboard:
	set(d):
		dashboard = d
		link_copy.icon = dashboard.editor_icon("ActionCopy")
		link_nav.icon = dashboard.editor_icon("ExternalLink")
		dashboard.load_locker.lock_changed.connect(_load_lock_changed)

var project_id: String = ""
var release_id: String = ""
var release_data

var local_export_active: bool = false

func _load_lock_changed(locked: bool):
	check_public.disabled = locked
	check_guests.disabled = locked
	channel_menu.disabled = locked

signal update_release(release_id: String, data: Dictionary)
signal show_logs(log_url: String)
signal build_busy()

var dashboard_url = "https://app.jamlaunch.com"

func _ready():
	var dir := (self.get_script() as Script).get_path().get_base_dir()
	var settings = ConfigFile.new()
	var err = settings.load(dir + "/../settings.cfg")
	if err != OK:
		printerr("Failed to load settings for dashboard address")
		return
	dashboard_url = "https://%s" % settings.get_value("api", "dashboard_domain")
	
	channel_menu.get_popup().index_pressed.connect(_on_channel_selected)

func set_channels(channels: Array):
	var popup = channel_menu.get_popup()
	popup.clear()
	for c in channels:
		popup.add_item(c)

func set_release(proj_id: String, r: Dictionary):
	
	project_id = proj_id
	release_id = r["id"]
	release_data = r
	
	title.clear()
	
	title.push_color(Color(1, 1, 1, 0.4))
	title.add_text("Release ")
	title.pop_all()
	
	title.push_font_size(18)
	title.push_bold()
	title.add_text(r["id"])
	title.pop_all()
	
	title.push_context()
	title.push_color(Color(1, 1, 1, 0.4))
	var rt = Time.get_datetime_dict_from_datetime_string(r["created_at"], false)
	title.add_text("\n%s-%02d-%02d\n%02d:%02d:%02d" % [
		rt["year"],
		int(rt["month"]),
		int(rt["day"]),
		int(rt["hour"]),
		int(rt["minute"]),
		int(rt["second"]),
	])
	title.pop_context()
	
	if r["public"]:
		check_public.text = "Public"
		check_public.button_pressed = true
		access_icon.texture = preload("res://addons/jam_launch/assets/icons/public.svg")
		access_icon.modulate = Color(0.7, 1.0, 0.8)
	else:
		check_public.text = "Private"
		check_public.button_pressed = false
		access_icon.texture = preload("res://addons/jam_launch/assets/icons/lock.svg")
		access_icon.modulate = Color("white")
	
	if r.get("allow_guests"):
		check_guests.button_pressed = true
	else:
		check_guests.button_pressed = false
	
	if r.get("channel"):
		current_channel.visible = true
		channel_menu.visible = false
		current_channel_lbl.text = "Channel: " + r["channel"]
	else:
		current_channel.visible = false
		channel_menu.visible = true
		current_channel_lbl.text = ""
	
	for child in jobs.get_children():
		child.queue_free()
	
	var sorted_job_names: Array = []
	var builds_by_name = {}
	for b in r["builds"]:
		sorted_job_names.append(b["name"])
		builds_by_name[b["name"]] = b
	sorted_job_names.sort()
	if sorted_job_names.has("Server"):
		sorted_job_names.erase("Server")
		sorted_job_names.push_front("Server")
	
	var is_busy = false
	for bname in sorted_job_names:
		var b = builds_by_name[bname]
		if b["has_build"]:
			jobs.add_child(preload("res://addons/jam_launch/ui/SuccessBadge.tscn").instantiate())
		elif b["has_log"]:
			jobs.add_child(preload("res://addons/jam_launch/ui/FailBadge.tscn").instantiate())
		else:
			if local_export_active:
				is_busy = true
				jobs.add_child(preload("res://addons/jam_launch/ui/BusyBadge.tscn").instantiate())
			else:
				jobs.add_child(preload("res://addons/jam_launch/ui/ErrorBadge.tscn").instantiate())
		
		var name_lbl = Label.new()
		name_lbl.text = bname
		jobs.add_child(name_lbl)
		
		if b["has_log"]:
			var log_btn = Button.new()
			log_btn.icon = dashboard.editor_icon("Script")
			log_btn.pressed.connect(_show_logs.bind(b["log_url"]))
			log_btn.flat = true
			log_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			jobs.add_child(log_btn)
		else:
			var blank = Label.new()
			jobs.add_child(blank)
	
	if is_busy:
		build_busy.emit()

func release_page_uri() -> String:
	return "%s/g/%s-%s" % [dashboard_url, project_id, release_id]

func _on_copy_pressed():
	DisplayServer.clipboard_set(release_page_uri())

func _on_check_public_toggled(toggled_on: bool):
	if check_public.disabled:
		# ignore check state changes that happen during an update
		return
	update_release.emit(release_id, {"public": toggled_on})

func _show_logs(log_url: String):
	show_logs.emit(log_url)

func _on_page_link_pressed():
	OS.shell_open(release_page_uri())

func on_export_active_changed(export_active: bool):
	local_export_active = export_active

func _on_check_guests_toggled(toggled_on: bool) -> void:
	if check_guests.disabled:
		# ignore check state changes that happen during an update
		return
	update_release.emit(release_id, {"allow_guests": toggled_on})


func _on_clear_channel_pressed() -> void:
	if not release_data or not release_data.get("channel"):
		return
	update_release.emit(release_id, {"channel": null})

func _on_channel_selected(idx: int) -> void:
	var channel = channel_menu.get_popup().get_item_text(idx)
	update_release.emit(release_id, {"channel": channel})
