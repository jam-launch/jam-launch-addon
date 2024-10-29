@tool
class_name DeviceAuthUI
extends MarginContainer

signal errored(msg: String)
signal active_auth(active: bool)
signal has_token(token: String)

@onready var login_api: JamLoginApi = $JamLoginApi
@onready var notes: RichTextLabel = $Waiting/Notes
@onready var user_code_label: Label = $Waiting/PC/M/UserCode
@onready var busy_scope: ScopeLocker = $BusyScope
@onready var waiting_scope: ScopeLocker = $WaitingScope
@onready var active_scope: ScopeLocker = $ActiveScope
@export var auth_mode: AUTH_MODE = AUTH_MODE.DEVELOPER

var cancel_auth: bool = false
var device_auth_url: String
var game_id: String = ""

enum AUTH_MODE {
	USER,
	DEVELOPER
}

func _ready() -> void:
	$Base.visible = true
	$Busy.visible = false
	$Waiting.visible = false
	active_scope.lock_changed.connect(func(x:bool)->void: active_auth.emit(x))
	var dir: String = (self.get_script() as Script).get_path().get_base_dir()
	var settings: ConfigFile = ConfigFile.new()
	var err: Error = settings.load(dir + "/../../settings.cfg")
	if not err == OK:
		printerr("Failed to load auth settings")
		return

	device_auth_url = settings.get_value("auth", "url")
	var deployment: ConfigFile = ConfigFile.new()
	err = deployment.load(dir + "/../../deployment.cfg")
	if not err == OK:
		printerr("Failed to load deployment settings")
		return

	game_id = deployment.get_value("game", "id")


func _err(msg: String) -> void:
	errored.emit(msg)


func _on_notes_meta_hover_started(_meta: String) -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _on_notes_meta_hover_ended(_meta: String) -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _on_notes_meta_clicked(meta: String) -> void:
	OS.shell_open(meta)


func _on_login_button_pressed() -> void:
	var _active_lock: ScopeLocker.ScopeLock = active_scope.get_lock()
	var _lock: ScopeLocker.ScopeLock = busy_scope.get_lock()
	var res: JamLoginApi.Result
	if auth_mode == AUTH_MODE.USER:
		if not game_id.is_empty():
			res = await login_api.request_user_auth(game_id)
		elif OS.is_debug_build():
			res = await login_api.request_developer_auth()
		else:
			res = JamLoginApi.Result.err("missing Game ID from deployment settings - can't log in")
	else:
		res = await login_api.request_developer_auth()
	if res.errored:
		_err(res.error_msg)
		return
	
	var userCode: String = res.data["userCode"] as String
	var deviceCode: String = res.data["deviceCode"] as String
	var authUrl: String = "%s?user_code=%s" % [device_auth_url, userCode]
	OS.shell_open(authUrl)
	user_code_label.text = userCode
	notes.parse_bbcode("[center][color=#eeeeee][bgcolor=#00000000]Confirm the following code at 
[url]%s[/url][/bgcolor][/color][/center]" % device_auth_url)
	
	_lock = waiting_scope.get_lock()
	while true:
		if cancel_auth:
			cancel_auth = false
			return
		await get_tree().create_timer(1).timeout
		var authRes: JamHttpBase.Result = await login_api.check_auth(userCode, deviceCode)
		if authRes.errored:
			_err(authRes.error_msg)
		elif authRes.data["state"] == "pending":
			continue
		elif authRes.data["state"] == "allowed":
			has_token.emit(authRes.data["accessKey"])
		else:
			_err("Access was not granted")
		break


func _on_busy_scope_lock_changed(locked: bool) -> void:
	$Busy.visible = locked
	$Base.visible = not (locked||waiting_scope.is_locked())


func _on_waiting_scope_lock_changed(locked: bool) -> void:
	$Waiting.visible = locked
	$Base.visible = not (locked||busy_scope.is_locked())


func _on_cancel_auth_pressed() -> void:
	cancel_auth = true
