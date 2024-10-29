class_name JamFilesS3
extends JamFiles

var s3: Variant

func _init(jam_connect: JamConnect, s3_client: Variant) -> void:
	super(jam_connect)
	s3 = s3_client
	s3.async_result.connect(_relay_result)


func _relay_result(key: Variant, err: Variant) -> void:
	_jc.game_files_async_result.emit(key, err)


func get_file(key: String, file_name: String) -> bool:
	return s3.get_file(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)


func put_file(key: String, file_name: String) -> bool:
	return s3.put_file(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)


func get_file_async(key: String, file_name: String) -> void:
	s3.get_file_async(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)


func put_file_async(key: String, file_name: String) -> void:
	s3.put_file_async(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)


func get_last_error() -> String:
	return s3.last_error()
