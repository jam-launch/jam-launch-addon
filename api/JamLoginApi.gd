@tool
extends JamHttpBase
class_name JamLoginApi

const DEV_SCOPE: String = "developer"
const USER_SCOPE: String = "user"

func _ready():
	super()

func request_developer_auth() -> Result:
	return await _json_http(
		"/device-auth/request",
		HTTPClient.METHOD_POST,
		{
			"clientId": "jamlaunch-addon",
			"scope": "developer"
		}
	)
	
func request_user_auth(gameId: String) -> Result:
	return await _json_http(
		"/device-auth/request",
		HTTPClient.METHOD_POST,
		{
			"clientId": "jam-play",
			"scope": "user",
			"game": gameId
		}
	)

func check_auth(user_code: String, device_code: String) -> Result:
	return await _json_http("/device-auth/request/%s/%s" % [user_code, device_code])
