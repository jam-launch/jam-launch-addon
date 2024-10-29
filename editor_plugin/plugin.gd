@tool
extends EditorPlugin

# A class member to hold the dock during the plugin life cycle.
var dashboard: JamEditorPluginDashboard = null

func _enter_tree() -> void:
	var editor_interface: EditorInterface = get_editor_interface()
	if !editor_interface:
		return
	var main_screen: VBoxContainer = EditorInterface.get_editor_main_screen()
	if !main_screen:
		return
	var dashboard_scn: Resource = preload("res://addons/jam_launch/editor_plugin/Dashboard.tscn")
	dashboard = dashboard_scn.instantiate()
	dashboard.plugin = self
	main_screen.add_child(dashboard)
	dashboard.hide()
	
	add_custom_type("JamConnect", "Node", preload("../core/JamConnect.gd"), preload("../assets/star-jar-outlined_16x16.png"))
	add_custom_type("ScopeLocker", "Node", preload("../util/ScopeLocker.gd"), EditorInterface.get_base_control().get_theme_icon("Lock", "EditorIcons"))
	add_custom_type("JamSync", "Node", preload("../core/JamSync.gd"), preload("../assets/icons/JamSync.png"))


func _exit_tree() -> void:
	remove_custom_type("JamConnect")
	remove_custom_type("ScopeLocker")
	remove_custom_type("JamSync")

	if dashboard:
		dashboard.free()
		dashboard = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if dashboard:
		dashboard.visible = visible


func _get_plugin_name() -> String:
	return "Jam Launch"


func _get_plugin_icon() -> Texture2D:
	return load("res://addons/jam_launch/assets/star-jar-outlined_16x16.png")
