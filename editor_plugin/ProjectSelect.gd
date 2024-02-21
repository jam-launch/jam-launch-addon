@tool
extends JamEditorPluginPage

@onready var projects: ItemList = $VB/Projects
@onready var no_projects: Label = $VB/NoProjects

signal open_project(project_id: String, project_name: String)
signal new_project()

var project_map = {}

var loading: bool = false:
	set(v):
		loading = v
		$Loading.visible = v
		$VB.visible = not v

func _page_init():
	$VB/TopBar/NewBtn.icon = dashboard.editor_icon("Add")

func show_init():
	dashboard.toolbar_title.text = "Projects"
	get_projects()

func refresh_page():
	get_projects()

func get_projects():
	if dashboard.load_locker.is_locked():
		return
	var lock = dashboard.load_locker.get_lock()
	
	projects.clear()
	loading = true
	var res = await project_api.list_projects()
	loading = false
	
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
	
	for p in res.data["projects"]:
		projects.add_item(p["project_name"])
		project_map[p["project_name"]] = p
	
	projects.visible = projects.item_count > 0
	no_projects.visible = not projects.visible

func _on_projects_item_activated(index: int) -> void:
	var pname = projects.get_item_text(index)
	open_project.emit(project_map[pname]["id"], pname)

func _on_new_btn_pressed() -> void:
	new_project.emit()
