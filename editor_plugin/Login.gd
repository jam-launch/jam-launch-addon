@tool
extends Control

var jwt: Jwt = Jwt.new()
var cache: KeyValCache = KeyValCache.new()
const jwt_cache_idx = "editor_jwt_dev_key"

@onready var ui_error = $VB/ErrorMsg

func _ready():
	jwt.token_changed.connect(_on_token_changed)

func initialize():
	ui_error.text = ""
	
	var key = cache.get_val(jwt_cache_idx)
	if key == null or key == "":
		return
	var res = jwt.set_token(key)
	if res.errored:
		_err("Error with cached key: %s" % res.error)

func _on_paste_button_pressed():
	ui_error.text = ""
	
	var clipped = DisplayServer.clipboard_get()
	
	if not clipped or len(clipped) < 1:
		_err("No string available to paste")
		return
	
	var res = jwt.set_token(clipped)
	if res.errored:
		_err(res.error)
		return
	
	print(res.data.header)
	print(res.data.claims)

func _on_token_changed(tkn: String):
	cache.store(jwt_cache_idx, tkn)

func _err(msg: String):
	ui_error.text = msg
	printerr(msg)
