@tool
extends CenterContainer

signal cancel()
signal create_done(project_id: String, project_name: String)

@onready var name_edit = $VB/ProjectName
@onready var err_label = $VB/ErrMsg

var project_api: ProjectApi
	
var waiting = false:
	set(v):
		waiting = v
		$VB/Options/Create.disabled = v
		name_edit.editable = not v

var error_msg = null :
	set(value):
		if value == null:
			err_label.visible = false
		else:
			err_label.text = value
			err_label.visible = false
			waiting = false

func initialize():
	project_api = get_parent().project_api

func _on_cancel_pressed() -> void:
	name_edit.clear()
	error_msg = null
	cancel.emit()

func _on_create_pressed() -> void:
	error_msg = null
	if name_edit.text == "":
		error_msg = "project name must be non-empty"
		return
	
	var pending_name = name_edit.text
	waiting = true
	var res = await project_api.create_project(pending_name)
	waiting = false
	if res.errored:
		error_msg = res.error_msg
		return
	name_edit.clear()
	create_done.emit(res.data["id"], pending_name)
