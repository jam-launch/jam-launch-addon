@tool
extends JamEditorPluginPage

signal cancel()
signal create_done(project_id: String, project_name: String)

@onready var name_edit = $VB/ProjectName

func _page_init():
	$VB/Options/Create.icon = dashboard.editor_icon("Add")

func show_init():
	dashboard.toolbar_title.text = "Create a new Project"
	
var waiting = false:
	set(v):
		waiting = v
		$VB/Options/Create.disabled = v
		name_edit.editable = not v

func initialize():
	project_api = get_parent().project_api

func _on_cancel_pressed() -> void:
	name_edit.clear()
	cancel.emit()

func _on_create_pressed() -> void:
	if name_edit.text == "":
		dashboard.show_error("project name must be non-empty", 5.0)
		return
	
	var pending_name = name_edit.text
	waiting = true
	var res = await project_api.create_project(pending_name)
	waiting = false
	if res.errored:
		dashboard.show_error(res.error_msg)
		return
	name_edit.clear()
	create_done.emit(res.data["id"], pending_name)

func _on_project_name_text_submitted(_new_text):
	_on_create_pressed()
