@tool
extends JamEditorPluginPage

var jwt: JamJwt = JamJwt.new()
var cache: KeyValCache = KeyValCache.new()
const jwt_cache_idx = "editor_jwt_dev_key"

func _ready():
	jwt.token_changed.connect(_on_token_changed)

func _page_init():
	var key = cache.get_val(jwt_cache_idx)
	if key == null or key == "":
		return
	var res = jwt.set_token(key)
	if res.errored:
		_err("Error with cached key: %s" % res.error)

func show_init():
	dashboard.toolbar.visible = false

func _on_paste_button_pressed():
	var clipped = DisplayServer.clipboard_get()
	if not clipped or len(clipped) < 1:
		_err("No string available to paste")
		return
	
	var res = jwt.set_token(clipped)
	if res.errored:
		_err(res.error)
		return

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
