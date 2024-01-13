@tool
extends HttpBase
class_name ClientApi

var game_id: String

func create_game_session(region: String = "us-east-2") -> Result:
	return await _json_http(
		"/sessions/%s" % game_id,
		HTTPClient.METHOD_POST,
		{
			"region": region
		}
	)

func join_game_session(join_id: String) -> Result:
	return await _json_http(
		"/sessions/%s/%s/join" % [game_id, join_id],
		HTTPClient.METHOD_POST,
		{}
	)

func get_game_session(session_id: String) -> Result:
	return await _json_http("/sessions/%s/%s" % [game_id, session_id])

func leave_game_session(session_id: String) -> Result:
	return await _json_http(
		"/sessions/%s/%s/leave" % [game_id, session_id],
		HTTPClient.METHOD_POST,
		{}
	)
