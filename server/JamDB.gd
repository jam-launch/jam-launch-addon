extends RefCounted
class_name JamDB

var jc: JamConnect

func _init(jam_connect):
	jc = jam_connect

@warning_ignore("unused_parameter")
func get_db_data(key_1: String, key_2: String):
	return null

func get_game_data(key_2: String):
	return get_db_data(jc.get_game_id(), key_2)
	
func get_release_data(key_2: String):
	return get_db_data(jc.get_release_id(), key_2)

func get_session_data(key_2: String):
	return get_db_data(jc.get_session_id(), key_2)

@warning_ignore("unused_parameter")
func put_db_data(key_1: String, key_2: String, data: Dictionary):
	return false

func put_game_data(key_2: String, data: Dictionary):
	return put_db_data(jc.get_game_id(), key_2, data)

func put_release_data(key_2: String, data: Dictionary):
	return put_db_data(jc.get_release_id(), key_2, data)

func put_session_data(key_2: String, data: Dictionary):
	return put_db_data(jc.get_session_id(), key_2, data)

@warning_ignore("unused_parameter")
func query_db_data(
		key_condition_expression: String,
		filter_expression: String,
		expression_attribute_names: Dictionary,
		expression_attribute_values: Dictionary) -> Array:
	return []

@warning_ignore("unused_parameter")
func get_db_data_async(key_1: String, key_2: String):
	jc.game_db_async_result.emit(null, "No DB available in dev mode")

func get_game_data_async(key_2: String):
	return get_db_data_async(jc.get_game_id(), key_2)
	
func get_release_data_async(key_2: String):
	return get_db_data_async(jc.get_release_id(), key_2)

func get_session_data_async(key_2: String):
	return get_db_data_async(jc.get_session_id(), key_2)

@warning_ignore("unused_parameter")
func put_db_data_async(key_1: String, key_2: String, data: Dictionary):
	jc.game_db_async_result.emit(null, "No DB available in dev mode")

func put_game_data_async(key_2: String, data: Dictionary):
	return put_db_data_async(jc.get_game_id(), key_2, data)

func put_release_data_async(key_2: String, data: Dictionary):
	return put_db_data_async(jc.get_release_id(), key_2, data)

func put_session_data_async(key_2: String, data: Dictionary):
	return put_db_data_async(jc.get_session_id(), key_2, data)

@warning_ignore("unused_parameter")
func query_db_data_async(
		key_condition_expression: String,
		filter_expression: String,
		expression_attribute_names: Dictionary,
		expression_attribute_values: Dictionary):
	jc.game_db_async_result.emit(null, "No DB available in dev mode")

func get_last_error():
	return "server is in dev mode - no DB available"
