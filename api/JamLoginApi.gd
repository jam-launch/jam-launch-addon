@tool
extends JamHttpBase
class_name JamLoginApi

const DEV_SCOPE: String = "developer"
const USER_SCOPE: String = "user"

func _ready():
	super()
	var dir := (self.get_script() as Script).get_path().get_base_dir()

func request_auth(client_id: String, scope: String) -> Result:
	return await _json_http(
		"/device-auth/request",
		HTTPClient.METHOD_POST,
		{
			"clientId": client_id,
			"scope": scope
		}
	)

func check_auth(user_code: String, device_code: String) -> Result:
	return await _json_http("/device-auth/request/%s/%s" % [user_code, device_code])
