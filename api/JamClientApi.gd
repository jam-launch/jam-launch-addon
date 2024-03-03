@tool
extends JamHttpBase
class_name JamClientApi

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

class GameSessionResult:
	extends JamHttpBase.Result
	var session_id: String = ""
	var status: SessionStatus = SessionStatus.UNKNOWN
	var region: String = ""
	var addresses: Array[GameSessionAddress] = []
	var players: Array[PlayerInfo] = []
	var join_id: String = ""
	
	static func from_result(res: Result) -> GameSessionResult:
		var gres = GameSessionResult.new()
		gres.data = res.data
		gres.errored = res.errored
		gres.error_msg = res.error_msg
		
		if res.errored:
			return gres
		
		gres.status = SessionStatus.get(res.data["status"], SessionStatus.UNKNOWN)
		gres.session_id = res.data["id"]
		gres.region = res.data["region"]
		for p in res.data["players"]:
			var pinfo = PlayerInfo.new()
			pinfo.user_id = p["user_id"]
			gres.players.push_back(pinfo)
		
		for a in res.data["addresses"]:
			var addr = GameSessionAddress.new()
			addr.ip = a["ip"]
			addr.port = a["port"]
			addr.domain = a["domain"]
			gres.addresses.push_back(addr)
		
		if "join_id" in res.data:
			gres.join_id = res.data["join_id"]
		
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

class P2pGameSessionResult:
	extends JamHttpBase.Result
	var session_id: String = ""
	var join_id: String = ""
	var created_at: String = ""
	var sealed: bool = false
	var players: Array[PlayerInfo] = []

	static func from_result(res: Result) -> P2pGameSessionResult:
		var gres = P2pGameSessionResult.new()
		gres.data = res.data
		gres.errored = res.errored
		gres.error_msg = res.error_msg
		
		if res.errored:
			return gres
		
		gres.session_id = res.data["id"]
		gres.join_id = res.data["join_id"]
		gres.created_at = res.data["created_at"]
		gres.sealed = res.data["sealed"]
		for p in res.data["players"]:
			var pinfo = PlayerInfo.new()
			pinfo.user_id = p["user_id"]
			gres.players.push_back(pinfo)
		
		return gres

class P2pJoinResult:
	extends JamHttpBase.Result
	var session_id: String = ""
	var join_id: String = ""
	var join_token: String = ""

	static func from_result(res: Result) -> P2pJoinResult:
		var jres = P2pJoinResult.new()
		jres.data = res.data
		jres.errored = res.errored
		jres.error_msg = res.error_msg
		
		if res.errored:
			return jres
		
		jres.session_id = res.data["session_id"]
		jres.join_id = res.data.get("join_id", "")
		jres.join_token = res.data["join_token"]
		
		return jres

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
		"/sessions/%s/%s/join" % [game_id, join_id],
		HTTPClient.METHOD_POST,
		{}
	)

func get_game_session(session_id: String) -> GameSessionResult:
	return GameSessionResult.from_result(
		await _json_http("/sessions/%s/%s" % [game_id, session_id])
	)

func leave_game_session(session_id: String) -> Result:
	return await _json_http(
		"/sessions/%s/%s/leave" % [game_id, session_id],
		HTTPClient.METHOD_POST,
		{}
	)

func create_p2p_game_session() -> P2pJoinResult:
	return P2pJoinResult.from_result(await _json_http(
		"/p2p/%s" % game_id,
		HTTPClient.METHOD_POST,
		{
		}
	))

func join_p2p_game_session(join_id: String) -> P2pJoinResult:
	return P2pJoinResult.from_result(await _json_http(
		"/p2p/%s/%s/join" % [game_id, join_id],
		HTTPClient.METHOD_POST,
		{}
	))

func get_p2p_game_session(session_id: String) -> P2pGameSessionResult:
	return P2pGameSessionResult.from_result(
		await _json_http("/p2p/%s/%s" % [game_id, session_id])
	)

func leave_p2p_game_session(session_id: String) -> Result:
	return await _json_http(
		"/p2p/%s/%s/leave" % [game_id, session_id],
		HTTPClient.METHOD_POST,
		{}
	)
