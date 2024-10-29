@tool
extends JamEditorPluginPage

signal open_project(project_id: String, project_name: String)
signal new_project()

@onready var projects: ItemList = $VB/Projects
@onready var no_projects: Label = $VB/NoProjects

var project_map: Dictionary = {}

var loading: bool = false:
	set(v):
		loading = v
		$Loading.visible = v
		$VB.visible = not v


func _page_init() -> void:
	$VB/TopBar/NewBtn.icon = dashboard.editor_icon("Add")


func show_init() -> void:
	dashboard.toolbar_title.text = "Projects"
	get_projects()


func refresh_page() -> void:
	get_projects()


func get_projects() -> void:
	if dashboard.load_locker.is_locked():
		return
	var _lock: ScopeLocker.ScopeLock = dashboard.load_locker.get_lock()
	projects.clear()
	loading = true
	var res: JamHttpBase.Result = await project_api.list_projects()
	loading = false
	
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
	
	for p: Dictionary in res.data["projects"]:
		projects.add_item(p["project_name"] as String)
		project_map[p["project_name"]] = p
	
	projects.visible = projects.item_count > 0
	no_projects.visible = not projects.visible

func _on_projects_item_activated(index: int) -> void:
	var pname: String = projects.get_item_text(index)
	open_project.emit(project_map[pname]["id"], pname)

func _on_new_btn_pressed() -> void:
	new_project.emit()
