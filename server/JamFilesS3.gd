extends JamFiles
class_name JamFilesS3

var s3

func _init(jam_connect: JamConnect, s3_client):
	super(jam_connect)
	s3 = s3_client
	s3.async_result.connect(_relay_result)

func _relay_result(key, err):
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
	
func get_file_async(key: String, file_name: String):
	s3.get_file_async(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)

func put_file_async(key: String, file_name: String):
	s3.put_file_async(
		OS.get_environment("GAME_DATA_BUCKET"),
		key,
		file_name
	)

func get_last_error():
	return s3.last_error()
