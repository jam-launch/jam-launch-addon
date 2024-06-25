@tool
extends JamEditorPluginPage

@onready var login_api: JamLoginApi = $JamLoginApi
@onready var notes: RichTextLabel = $Waiting/Notes
@onready var user_code_label: Label = $Waiting/PC/M/UserCode

@onready var busy_scope: ScopeLocker = $BusyScope
@onready var waiting_scope: ScopeLocker = $WaitingScope

var jwt: JamJwt = JamJwt.new()
var cache: KeyValCache = KeyValCache.new()
const jwt_cache_idx = "addon_jwt_dev_key"

var cancel_auth: bool = false
var device_auth_url: String
var client_id: String

func _ready():
	$Base.visible = true
	$Busy.visible = false
	$Waiting.visible = false
	jwt.token_changed.connect(_on_token_changed)
	
	var dir := (self.get_script() as Script).get_path().get_base_dir()
	var settings = ConfigFile.new()
	var err = settings.load(dir + "/../settings.cfg")
	if err != OK:
		printerr("Failed to load auth settings")
		return
	device_auth_url = settings.get_value("auth", "url")
	client_id = settings.get_value("auth", "client_id")

func _page_init():
	var key = cache.get_val(jwt_cache_idx)
	if key == null or key == "":
		return
	var res = jwt.set_token(key)
	if res.errored:
		_err("Error with cached key: %s" % res.error)

func show_init():
	dashboard.toolbar.visible = false

func _on_token_changed(tkn: String):
	cache.store(jwt_cache_idx, tkn)

func _err(msg: String):
	dashboard.show_error(msg)

func _on_notes_meta_hover_started(meta):
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _on_notes_meta_hover_ended(meta):
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_notes_meta_clicked(meta):
	OS.shell_open(meta)


func _on_login_button_pressed():
	
	var lock = busy_scope.get_lock()
	var res = await login_api.request_developer_auth()
	if res.errored:
		_err(res.error_msg)
		return
	
	var userCode = res.data["userCode"]
	var deviceCode = res.data["deviceCode"]
	var authUrl = "%s?user_code=%s" % [device_auth_url, userCode]
	
	OS.shell_open(authUrl)
	user_code_label.text = userCode
	notes.parse_bbcode("[center][color=#eeeeee][bgcolor=#00000000]Confirm the following code at
[url]%s[/url][/bgcolor][/color][/center]" % device_auth_url)
	
	lock = waiting_scope.get_lock()
	while true:
		if cancel_auth:
			cancel_auth = false
			return
		await get_tree().create_timer(1).timeout
		var authRes = await login_api.check_auth(userCode, deviceCode)
		if authRes.errored:
			_err(authRes.error_msg)
		elif authRes.data["state"] == "pending":
			continue
		elif authRes.data["state"] == "allowed":
			jwt.set_token(authRes.data["accessKey"])
		else:
			_err("Access was not granted")
		break

func _on_busy_scope_lock_changed(locked):
	$Busy.visible = locked
	$Base.visible = not (locked || waiting_scope.is_locked())

func _on_waiting_scope_lock_changed(locked):
	$Waiting.visible = locked
	$Base.visible = not (locked || busy_scope.is_locked())

func _on_cancel_auth_pressed():
	cancel_auth = true
