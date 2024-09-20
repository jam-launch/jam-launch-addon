@tool
class_name JamClientApi
extends JamHttpBase

var game_id: String

enum SessionStatus {
	INIT, UNKNOWN, PROVISIONING, PENDING, ACTIVATING, RUNNING, READY, DEACTIVATING, STOPPING, DEPROVISIONING, STOPPED
}

class GameSessionAddress:
	extends RefCounted
	var ip: String
	var port: int
	var domain: String

class PlayerInfo:
	extends RefCounted
	var user_id: String
	var token: String

class GameSessionResult:
	extends JamHttpBase.Result
	var session_id: String = ""
	var status: SessionStatus = SessionStatus.UNKNOWN
	var region: String = ""
	var address: String = ""
	var players: Array[PlayerInfo] = []
	var join_id: String = ""
	
	static func from_result(res: Result) -> GameSessionResult:
		
		#print(res.data)
		
		var gres = GameSessionResult.new()
		gres.data = res.data
		gres.errored = res.errored
		gres.error_msg = res.error_msg
		
		if res.errored:
			return gres
		
		gres.status = SessionStatus.get(res.data["state"], SessionStatus.UNKNOWN)
		gres.session_id = res.data["id"]
		gres.region = res.data["region"]
		for p in res.data["players"]:
			var pinfo = PlayerInfo.new()
			pinfo.user_id = p["username"]
			gres.players.push_back(pinfo)
			if "joinToken" in p:
				pinfo.token = p["joinToken"]
		
		if "address" in res.data:
			gres.address = res.data["address"]
			
		if "joinCode" in res.data:
			gres.join_id = res.data["joinCode"]
		
		return gres
	
	func has_unusable_status() -> bool:
		return errored or [
				SessionStatus.UNKNOWN,
				SessionStatus.DEACTIVATING,
				SessionStatus.STOPPING,
				SessionStatus.DEPROVISIONING,
				SessionStatus.STOPPED
			].has(status)
	
	func busy_progress() -> float:
		if status == SessionStatus.INIT:
			return 1.0 / 6.0
		elif status == SessionStatus.PROVISIONING:
			return 2.0 / 6.0
		elif status == SessionStatus.PENDING:
			return 3.0 / 6.0
		elif status == SessionStatus.ACTIVATING:
			return 4.0 / 6.0
		elif status == SessionStatus.RUNNING:
			return 5.0 / 6.0
		elif status == SessionStatus.READY:
			return 1.0
		else:
			return 0.0

func create_game_session(region: String="us-east-2") -> Result:
	return await _json_http(
		"/sessions/%s" % game_id,
		HTTPClient.METHOD_POST,
		{
			"region": region
		}
	)

func join_game_session(join_id: String) -> Result:
	return await _json_http(
		"/sessions/%s/join/%s" % [game_id, join_id],
		HTTPClient.METHOD_POST,
		{}
	)

func get_game_session(session_id: String) -> GameSessionResult:
	return GameSessionResult.from_result(
		await _json_http("/sessions/%s/check/%s" % [game_id, session_id])
	)

func leave_game_session(session_id: String) -> Result:
	return await _json_http(
		"/sessions/%s/leave/%s" % [game_id, session_id],
		HTTPClient.METHOD_POST,
		{}
	)

func get_guest_jwt(game_id: String) -> Result:
	return await _json_http("/guest-auth/%s" % [game_id])

func check_guests_allowed(game_id: String) -> Result:
	return await _json_http("/guest-auth/%s/allowed" % [game_id])
