@tool
extends MarginContainer

var plugin: EditorPlugin = null
@onready var project_api: ProjectApi = $ProjectApi

func jwt() -> Jwt:
		return $Login.jwt
		
func show_page(p: Control):
	$Login.visible = false
	$ProjectSelect.visible = false
	$Project.visible = false
	$NewProject.visible = false
	$Sessions.visible = false
	
	p.visible = true

func _ready() -> void:
	if plugin == null:
		return
		
	jwt().token_changed.connect(_on_jwt_changed)
	project_api.jwt = jwt()
	
	show_page($Login)
	$Project.initialize()
	$NewProject.initialize()
	$ProjectSelect.initialize()
	$Login.initialize()
	$Sessions.initialize()

func _plugin() -> EditorPlugin:
	return plugin

func _on_jwt_changed(token):
	if len(token) > 0:
		show_page($ProjectSelect)
		$ProjectSelect.get_projects()
	else:
		show_page($Login)

func _on_project_select_open_project(project_id: String, project_name: String) -> void:
	show_page($Project)
	$Project.show_project(project_id, project_name)
	_plugin().get_editor_interface().get_resource_filesystem().get_filesystem()

func _on_project_go_back() -> void:
	show_page($ProjectSelect)
	$ProjectSelect.get_projects()

func _on_project_select_new_project() -> void:
	show_page($NewProject)

func _on_new_project_cancel() -> void:
	show_page($ProjectSelect)

func _on_new_project_create_done(project_id: String, project_name: String) -> void:
	show_page($Project)
	$Project.show_project(project_id, project_name)

func _on_sessions_go_back():
	show_page($Project)

func _on_project_session_page_selected(project_id: String, project_name: String):
	show_page($Sessions)
	$Sessions.show_game(project_id, project_name)
