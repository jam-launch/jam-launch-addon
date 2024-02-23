extends JamHttpBase
class_name JamDevModeApi

func get_test_key(project_id: String, release: String, test_num: int) -> Result:
	return await _json_http(
		"/projects/%s/testkey" % [project_id],
		HTTPClient.METHOD_POST,
		{
			"num": test_num,
			"release": release
		}
	) 
