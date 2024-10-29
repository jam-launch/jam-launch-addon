class_name JamDBDynamo
extends JamDB

var ddb: Variant

func _init(jam_connect: JamConnect, ddb_client: Variant) -> void:
	super(jam_connect)
	ddb = ddb_client
	ddb.async_result.connect(_relay_result)


func _relay_result(result: Variant, err: Variant) -> void:
	_jc.game_db_async_result.emit(result, err)


func get_db_data(key_1: String, key_2: String) -> Variant:
	return ddb.get_item(
		OS.get_environment("GAME_DATA_TABLE"),
		key_1,
		key_2
	)


func put_db_data(key_1: String, key_2: String, data: Dictionary) -> Variant:
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


func get_db_data_async(key_1: String, key_2: String) -> void:
	ddb.get_item_async(
		OS.get_environment("GAME_DATA_TABLE"),
		key_1,
		key_2
	)


func put_db_data_async(key_1: String, key_2: String, data: Dictionary) -> void:
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
		expression_attribute_values: Dictionary) -> void:
	ddb.query_async(
		OS.get_environment("GAME_DATA_TABLE"),
		key_condition_expression,
		filter_expression,
		expression_attribute_names,
		expression_attribute_values
	)


func get_last_error() -> String:
	return ddb.last_error()
