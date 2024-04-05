@tool
class_name JamEditorPluginPage
extends Control

var dashboard: JamEditorPluginDashboard
var project_api: JamProjectApi
var plugin: EditorPlugin

func page_init():
	var d = get_parent()
	while not d.is_in_group("jam_launch_dashboard"):
		d = d.get_parent()
		if not d:
			printerr("failed to find the Jam Launch Editor Dashboard in page parents")
			return
	dashboard = d
	project_api = dashboard.project_api
	plugin = dashboard.plugin
	_page_init()

func _page_init():
	pass

func show_init():
	pass

func _ready():
	add_to_group("jam_editor_plugin_page")
