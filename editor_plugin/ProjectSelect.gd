@tool
extends MarginContainer

@onready var projects: ItemList = $VB/Projects
@onready var err_label: Label = $VB/ErrMsg
@onready var load_bar: ProgressBar = $Loading/Bar

signal open_project(project_id: String, project_name: String)
signal new_project()

var project_map = {}
var project_api: ProjectApi

var api_url
var error_msg = null :
	set(value):
		if value == null:
			err_label.visible = false
		else:
			err_label.text = value
			err_label.visible = true

var loading: bool = false:
	set(v):
		load_bar.value = 0
		loading = v
		$Loading.visible = v
		$VB.visible = not v

func _dashboard():
	return get_parent()

func _plugin() -> EditorPlugin:
	return _dashboard().plugin

func _ready():
	error_msg = null

func initialize():
	project_api = _dashboard().project_api
	$VB/TopBar/NewBtn.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Add", "EditorIcons")
	$VB/TopBar/RefreshBtn.icon = _plugin().get_editor_interface().get_base_control().get_theme_icon("Reload", "EditorIcons")

func _process(delta: float) -> void:
	if loading:
		load_bar.value += delta * 50
		if load_bar.value > 100:
			load_bar.value -= 100

func get_projects():
	projects.clear()
	error_msg = null
	loading = true
	var res = await project_api.list_projects()
	loading = false
	
	if res.errored:
		error_msg = res.error_msg
		return
		
	for p in res.data["projects"]:
		projects.add_item(p["project_name"])
		project_map[p["project_name"]] = p

func _on_projects_item_activated(index: int) -> void:
	var pname = projects.get_item_text(index)
	open_project.emit(project_map[pname]["id"], pname)

func _on_log_out_btn_pressed() -> void:
	_dashboard().jwt().clear()

func _on_new_btn_pressed() -> void:
	new_project.emit()

func _on_refresh_btn_pressed() -> void:
	get_projects()
