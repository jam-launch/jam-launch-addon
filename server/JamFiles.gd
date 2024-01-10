extends RefCounted
class_name JamFiles

var jc: JamConnect

func _init(jam_connect):
	jc = jam_connect

@warning_ignore("unused_parameter")
func get_file(key: String, file_name: String) -> bool:
	return false

func get_game_file(key: String, file_name: String):
	return get_file(jc.get_game_id() + "/" + key, file_name)
	
func get_release_file(key: String, file_name: String):
	return get_file(jc.get_release_id() + "/" + key, file_name)

func get_session_file(key: String, file_name: String):
	return get_file(jc.get_session_id() + "/" + key, file_name)

@warning_ignore("unused_parameter")
func put_file(key: String, file_name: String) -> bool:
	return false

func put_game_file(key: String, file_name: String):
	return put_file(jc.get_game_id() + "/" + key, file_name)
	
func put_release_file(key: String, file_name: String):
	return put_file(jc.get_release_id() + "/" + key, file_name)

func put_session_file(key: String, file_name: String):
	return put_file(jc.get_session_id() + "/" + key, file_name)

@warning_ignore("unused_parameter")
func get_file_async(key: String, file_name: String):
	jc.game_files_async_result.emit(null, "No DB available in dev mode")

func get_game_file_async(key: String, file_name: String):
	get_file_async(jc.get_game_id() + "/" + key, file_name)
	
func get_release_file_async(key: String, file_name: String):
	get_file_async(jc.get_release_id() + "/" + key, file_name)

func get_session_file_async(key: String, file_name: String):
	get_file_async(jc.get_session_id() + "/" + key, file_name)

@warning_ignore("unused_parameter")
func put_file_async(key: String, file_name: String):
	jc.game_files_async_result.emit(null, "No DB available in dev mode")

func put_game_file_async(key: String, file_name: String):
	put_file_async(jc.get_game_id() + "/" + key, file_name)
	
func put_release_file_async(key: String, file_name: String):
	put_file_async(jc.get_release_id() + "/" + key, file_name)

func put_session_file_async(key: String, file_name: String):
	put_file_async(jc.get_session_id() + "/" + key, file_name)

func get_last_error():
	return "server is in dev mode - no DB available"
