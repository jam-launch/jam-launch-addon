@tool
class_name JamEditorPluginPage
extends Control

var dashboard: JamEditorPluginDashboard
var project_api: JamProjectApi
var plugin: EditorPlugin

func page_init() -> void:
	var d: Node = get_parent()
	while not d.is_in_group("jam_launch_dashboard"):
		d = d.get_parent()
		if not d:
			printerr("failed to find the Jam Launch Editor Dashboard in page parents")
			return
	dashboard = d
	project_api = dashboard.project_api
	plugin = dashboard.plugin
	_page_init()


func _page_init() -> void:
	pass


func show_init() -> void:
	pass


func _ready() -> void:
	add_to_group("jam_editor_plugin_page")
