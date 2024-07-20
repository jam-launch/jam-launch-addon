@tool
extends JamHttpBase
class_name JamCallbackApi

var session_id := OS.get_environment("SESSION_ID")

func _ready():
	super()
	api_url = OS.get_environment("CALLBACK_URL")
	jwt.set_token(OS.get_environment("CALLBACK_KEY"))

func send_ready() -> Result:
	print("Sending ready to %s" % api_url)
	return await _json_http(
		"",
		HTTPClient.METHOD_POST,
		{
			"sessionId": session_id,
			"state": "READY"
		}
	)

func check_token(username: String, token: String) -> Result:
	return await _json_http(
		"",
		HTTPClient.METHOD_POST,
		{
			"sessionId": session_id,
			"authenticate": {
				"username": username,
				"token": token
			}
		}
	)

func get_vars(var_names: Array[String]) -> Result:
	return await _json_http(
		"",
		HTTPClient.METHOD_POST,
		{
			"sessionId": session_id,
			"getVars": var_names
		}
	)
