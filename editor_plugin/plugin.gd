@tool
extends EditorPlugin

# A class member to hold the dock during the plugin life cycle.
var dashboard = null

func _enter_tree():
	var editor_interface = get_editor_interface()
	if !editor_interface:
		return
	var main_screen = editor_interface.get_editor_main_screen()
	if !main_screen:
		return
	var dashboard_scn = preload("res://addons/jam_launch/editor_plugin/Dashboard.tscn")
	dashboard = dashboard_scn.instantiate()
	dashboard.plugin = self
	main_screen.add_child(dashboard)
	dashboard.hide()
	
	add_custom_type("JamConnect", "Node", preload("../core/JamConnect.gd"), preload("../assets/star-jar-outlined_16x16.png"))

func _exit_tree():
	if dashboard:
		dashboard.free()
		dashboard = null

func _has_main_screen():
	return true

func _make_visible(visible):
	if dashboard:
		dashboard.visible = visible

func _get_plugin_name():
	return "Jam Launch"

func _get_plugin_icon():
	return load("res://addons/jam_launch/assets/star-jar-outlined_16x16.png")
