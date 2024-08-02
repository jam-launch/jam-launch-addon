@tool
class_name JamDataApi
extends JamHttpBase

var project_id: String = ""

func _ready():
	super()
	api_url = OS.get_environment("DATA_URL")
	jwt.set_token(OS.get_environment("DATA_KEY"))

func put_object(key: String, object: Dictionary) -> Result:
	var path := "/proj/%s/data/%s" % [project_id, key]
	return await _json_http(
		path,
		HTTPClient.METHOD_POST,
		object
	)
	
func get_object(key: String) -> Result:
	return await _json_http(
		"/proj/%s/data/%s" % [project_id, key],
		HTTPClient.METHOD_GET
	)
