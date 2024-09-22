extends Node
class_name ClientKeys

var dev_mode_api: JamDevModeApi

var dev_jwt: JamJwt

func _init():
	if OS.is_debug_build():
		dev_mode_api = JamDevModeApi.new()
		add_child(dev_mode_api)

func _get_web_gjwt() -> Variant:
	var js_return = JavaScriptBridge.eval("window.getJamLaunchGJWT?.() ?? null;")
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

func get_test_gjwt(gameId: String) -> Variant:
	if not OS.is_debug_build():
		push_error("can't get test gjwt if not in dev mode")
		return null
	
	var peer = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", 17343)
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to connect to local auth proxy for test creds")
			return null
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
	
	var parts = gameId.split("-")
	peer.put_string("key/%s/%s" % [parts[0], parts[1]])
	
	while true:
		await get_tree().create_timer(0.1).timeout
		var err := peer.poll()
		if err != OK:
			push_error("failed to get response from local auth proxy for test creds")
			return null
		if peer.get_available_bytes() > 0:
			break
	
	var jwt_response = peer.get_string()
	
	if jwt_response.begins_with("Error:"):
		push_error("failed to get test creds - %s" % jwt_response)
		return null
	
	peer.disconnect_from_host()
	return jwt_response
