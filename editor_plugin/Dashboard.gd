@tool
class_name JamEditorPluginDashboard
extends MarginContainer

@onready var project_api: JamProjectApi = $ProjectApi
@onready var load_locker: ScopeLocker = $LoadLocker
@onready var pages: JamPageStack = $VB/PageStack
@onready var login_page: JamEditorPluginPage = $VB/PageStack/Login
@onready var project_select_page: JamEditorPluginPage = $VB/PageStack/ProjectSelect
@onready var project_page: JamEditorPluginPage = $VB/PageStack/Project
@onready var new_project_page: JamEditorPluginPage = $VB/PageStack/NewProject
@onready var sessions_page: JamEditorPluginPage = $VB/PageStack/Sessions
@onready var errors: VBoxContainer = $Errors
@onready var toolbar: HBoxContainer = $VB/ToolBar
@onready var toolbar_refresh: Button = $VB/ToolBar/Refresh
@onready var toolbar_back: Button = $VB/ToolBar/Back
@onready var toolbar_title: Label = $VB/ToolBar/Title
@onready var auth_proxy: JamAuthProxy = $JamAuthProxy

var msg_scn: Resource = preload("res://addons/jam_launch/ui/MessagePanel.tscn")
var plugin: EditorPlugin

func _ready() -> void:
	if not plugin:
		return

	if not Engine.is_editor_hint():
		return

	toolbar_refresh.icon = editor_icon("Reload")
	toolbar_back.icon = editor_icon("Back")
	toolbar_back.visible = false
	pages.go_back_enabled.connect(func(enabled: bool) -> void: toolbar_back.visible = enabled)
	for page in pages.get_children():
		if is_instance_of(page, JamEditorPluginPage):
			page.page_init()
	
	auth_proxy.api = project_api
	auth_proxy.start()
	login_page.jwt.token_changed.connect(_on_jwt_changed)
	project_api.jwt = login_page.jwt
	_on_jwt_changed(login_page.jwt.get_token() as String)
	_on_page_stack_tab_changed(pages.current_tab)


func editor_icon(iconName: StringName) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(iconName, "EditorIcons")


func _on_page_stack_tab_changed(_tab: Variant) -> void:
	var active_page: Control = pages.get_current_tab_control()
	toolbar_refresh.visible = active_page.has_method("refresh_page")
	toolbar.visible = true
	toolbar_title.text = ""
	active_page.show_init()


func show_page(page: JamEditorPluginPage, push_to_stack: bool = true) -> void:
	pages.show_page_node(page, push_to_stack)


func _on_jwt_changed(token: String) -> void:
	if not token.is_empty():
		show_page(project_select_page, false)
	else:
		show_page(login_page, false)


func _on_project_select_open_project(project_id: String, project_name: String) -> void:
	show_page(project_page)
	project_page.show_project(project_id, project_name)


func _on_project_select_new_project() -> void:
	show_page(new_project_page)


func _on_new_project_cancel() -> void:
	pages.go_back()


func _on_new_project_create_done(project_id: String, project_name: String) -> void:
	pages.go_back()
	show_page(project_page)
	project_page.show_project.call_deferred(project_id, project_name)


func _on_project_session_page_selected(project_id: String, project_name: String) -> void:
	show_page(sessions_page)
	sessions_page.show_game(project_id, project_name)


func show_error(msg: String, auto_dismiss_delay: float = 0.0) -> void:
	printerr(msg)
	var msg_panel: MessagePanel = msg_scn.instantiate()
	errors.add_child(msg_panel)
	errors.move_child(msg_panel, 0)
	msg_panel.set_error_text(msg)
	if auto_dismiss_delay > 0.0:
		msg_panel.set_auto_dismiss(auto_dismiss_delay)


func show_message(msg: String, auto_dismiss: float = 0.0) -> void:
	print(msg)
	var msg_box: MessagePanel = msg_scn.instantiate()
	errors.add_child(msg_box)
	errors.move_child(msg_box, 0)
	msg_box.message = msg
	if auto_dismiss > 0.0:
		msg_box.set_auto_dismiss(auto_dismiss)


func _on_log_out_pressed() -> void:
	login_page.jwt.clear()


func _on_refresh_pressed() -> void:
	var active_page: Control = pages.get_current_tab_control()
	if active_page.has_method("refresh_page"):
		active_page.call("refresh_page")


func _on_back_pressed() -> void:
	pages.go_back()


func _on_load_locker_lock_changed(locked: bool) -> void:
	toolbar_refresh.disabled = locked
