extends Node
class_name ClientKeys

const jwt_cache_idx = "editor_jwt_dev_key"
var cache = KeyValCache.new()
var dev_mode_api: JamDevModeApi

var dev_jwt: JamJwt

func _init():
	if OS.is_debug_build():
		dev_mode_api = JamDevModeApi.new()
		add_child(dev_mode_api)

func _get_web_gjwt() -> Variant:
	var js_return = JavaScriptBridge.eval("getJamLaunchGJWT();")
	if !js_return:
		printerr("failed to retrieve GJWT in browser context")
	return js_return

func get_included_gjwt(game_id: String) -> Variant:
	if OS.get_name() == "Web":
		return _get_web_gjwt()
	
	var gjwt_path := OS.get_executable_path().get_base_dir()
	if OS.get_name() == "macOS":
		gjwt_path += "/../Resources"
	gjwt_path += "/gjwt"
	
	if FileAccess.file_exists(gjwt_path):
		return FileAccess.get_file_as_string(gjwt_path)
	else:
		if FileAccess.file_exists("user://gjwt-%s" % game_id):
			return FileAccess.get_file_as_string("user://gjwt-%s" % game_id)
		else:
			print("Cannot locate included GJWT")
	
	return null

func _load_dev_jwt() -> Variant:
	if dev_jwt:
		return dev_jwt
		
	var dev_key = cache.get_val(jwt_cache_idx)
	
	if dev_key == null:
		push_error("no developer key available for fetching test keys")
		return null
		
	var jwt = JamJwt.new()
	var jwt_res = jwt.set_token(dev_key as String)
	if jwt_res.errored:
		push_error("invalid developer key in cache: %s" % jwt_res.error)
		return null
	
	dev_jwt = jwt
	return dev_jwt

func get_test_gjwt(gameId: String, n: int = 1) -> Variant:
	if not OS.is_debug_build():
		push_error("can't get test gjwt if not in dev mode")
		return null
	
	_load_dev_jwt()
	if dev_jwt == null:
		return null
	dev_mode_api.jwt = dev_jwt
	
	var gameIdParts := gameId.split("-")
	var test_res = await dev_mode_api.get_test_key(gameIdParts[0], gameIdParts[1], n)
	if test_res.errored:
		push_error("failed to fetch test key: %s" % test_res.error_msg)
		return null
	
	return test_res.data["test_jwt"]

