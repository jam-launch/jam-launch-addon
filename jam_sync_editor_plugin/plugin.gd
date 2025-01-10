@tool
extends EditorPlugin

var jam_sync_editor_scn := preload("./JamSyncEditor.tscn")
var jam_sync_editor: Control = null
var bottom_panel_button: Button = null

func _enter_tree():
	bottom_panel_button = null
	jam_sync_editor = jam_sync_editor_scn.instantiate()
	jam_sync_editor.jam_sync = null

func _exit_tree():
	_remove_panel()
	if jam_sync_editor:
		jam_sync_editor.queue_free()
		jam_sync_editor = null

func _handles(object: Object) -> bool:
	return object is JamSync

func _make_visible(visible):
	if visible:
		_show_panel(null)
	else:
		_remove_panel()

func _get_plugin_name():
	return "Jam Sync Editor"

func _get_plugin_icon():
	return load("../assets/icons/JamSync.png")

func _edit(object: Object) -> void:
	if object is JamSync:
		_show_panel(object)
	else:
		_remove_panel()

func _show_panel(target: JamSync):
	if not jam_sync_editor:
		jam_sync_editor = jam_sync_editor_scn.instantiate()
		jam_sync_editor.jam_sync = target
	if target != null:
		jam_sync_editor.jam_sync = target
	if not bottom_panel_button:
		bottom_panel_button = add_control_to_bottom_panel(jam_sync_editor, "Jam Sync")
	make_bottom_panel_item_visible(jam_sync_editor)

func _remove_panel():
	if jam_sync_editor:
		if bottom_panel_button:
			if bottom_panel_button.button_pressed:
				hide_bottom_panel()
			remove_control_from_bottom_panel(jam_sync_editor)
			bottom_panel_button = null
		jam_sync_editor.jam_sync = null
