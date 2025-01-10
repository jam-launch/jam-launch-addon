@tool
extends EditorPlugin

var jam_sync_editor: Control = null

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
	
	add_custom_type("ScopeLocker", "Node", preload("../util/ScopeLocker.gd"), editor_interface.get_base_control().get_theme_icon("Lock", "EditorIcons"))
	add_custom_type("JamConnect", "Node", preload("../core/JamConnect.gd"), preload("../assets/star-jar-outlined_16x16.png"))
	add_custom_type("JamSyncProperty", "Resource", preload("../core/JamSyncProperty.gd"), preload("../assets/icons/JamSync.png"))
	add_custom_type("JamSyncConfig", "Resource", preload("../core/JamSyncConfig.gd"), preload("../assets/icons/JamSync.png"))
	add_custom_type("JamSync", "Node", preload("../core/JamSync.gd"), preload("../assets/icons/JamSync.png"))

func _exit_tree():
	if jam_sync_editor:
		remove_control_from_bottom_panel(jam_sync_editor)
		jam_sync_editor.queue_free()
		jam_sync_editor = null
	
	remove_custom_type("JamSync")
	remove_custom_type("JamSyncConfig")
	remove_custom_type("JamSyncProperty")
	remove_custom_type("JamConnect")
	remove_custom_type("ScopeLocker")

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
