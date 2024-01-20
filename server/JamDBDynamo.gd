extends JamDB
class_name JamDBDynamo

var ddb

func _init(jam_connect: JamConnect, ddb_client):
	super(jam_connect)
	ddb = ddb_client
	ddb.async_result.connect(_relay_result)

func _relay_result(result, err):
	_jc.game_db_async_result.emit(result, err)

func get_db_data(key_1: String, key_2: String):
	return ddb.get_item(
		OS.get_environment("GAME_DATA_TABLE"),
		key_1,
		key_2
	)

func put_db_data(key_1: String, key_2: String, data: Dictionary):
	data["session_id"] = key_1
	data["record_type"] = key_2
	return ddb.put_item(
		OS.get_environment("GAME_DATA_TABLE"),
		data
	)

func query_db_data(
		key_condition_expression: String,
		filter_expression: String,
		expression_attribute_names: Dictionary,
		expression_attribute_values: Dictionary) -> Array:
	return ddb.query(
		OS.get_environment("GAME_DATA_TABLE"),
		key_condition_expression,
		filter_expression,
		expression_attribute_names,
		expression_attribute_values
	)

func get_db_data_async(key_1: String, key_2: String):
	ddb.get_item_async(
		OS.get_environment("GAME_DATA_TABLE"),
		key_1,
		key_2
	)

func put_db_data_async(key_1: String, key_2: String, data: Dictionary):
	data["session_id"] = key_1
	data["record_type"] = key_2
	ddb.put_item_async(
		OS.get_environment("GAME_DATA_TABLE"),
		data
	)

func query_db_data_async(
		key_condition_expression: String,
		filter_expression: String,
		expression_attribute_names: Dictionary,
		expression_attribute_values: Dictionary):
	ddb.query_async(
		OS.get_environment("GAME_DATA_TABLE"),
		key_condition_expression,
		filter_expression,
		expression_attribute_names,
		expression_attribute_values
	)

func get_last_error():
	return ddb.last_error()
