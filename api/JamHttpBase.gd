@tool
class_name JamHttpBase
extends Node

var addon_version: String = "unknown"
var api_url: String
var jwt: JamJwt = JamJwt.new()
var pool: JamHttpRequestPool

func _ready() -> void:
	var dir: String = (self.get_script() as Script).get_path().get_base_dir()
	
	var settings: ConfigFile = ConfigFile.new()
	var err: Error = settings.load(dir + "/../settings.cfg")
	if not err == OK:
		printerr("Failed to load api settings")
		return
	api_url = "https://%s" % settings.get_value("api", "domain")
	
	addon_version = settings.get_value("info", "version", "unknown")
	
	pool = JamHttpRequestPool.new()
	add_child(pool)


func _auth_headers() -> Array:
	if not jwt.has_token():
		return []
	else:
		return ["Authorization: Bearer %s" % jwt.get_token()]


func _json_auth_headers() -> Array:
	return _auth_headers() + ["Content-type: application/json"]


func get_string_data(url: String) -> JamResult:
	var h: JamHttpRequestPool.ScopedClient = pool.get_client()
	var err: Error = h.http.request(url)
	if not err == OK:
		return JamResult.err("HTTP request error")
	
	var resp: Variant = await h.http.request_completed
	if resp[1] > 299:
		return JamResult.err("HTTP error code %d" % [resp[1]])
	
	var s: String = resp[3].get_string_from_utf8()
	if len(s) < 1:
		return JamResult.err("Empty of invalid HTTP response")

	return JamResult.ok(s)


func _json_http(route: String, method: HTTPClient.Method=HTTPClient.METHOD_GET, body: Variant=null) -> Result:
	var result: Result = Result.new()
	var err: Error
	var h: JamHttpRequestPool.ScopedClient = pool.get_client()
	if not body == null:
		err = h.http.request(
			api_url + route,
			_json_auth_headers(),
			HTTPClient.METHOD_POST,
			JSON.stringify(body)
		)
	else:
		err = h.http.request(
			api_url + route,
			_json_auth_headers(),
			method
		)
	if not err == OK:
		result.errored = true
		result.error_msg = "HTTP request error"
		return result
		
	var resp: Variant = await h.http.request_completed
	var response_code: Variant = resp[1]
	var response_body: String = resp[3].get_string_from_utf8()
	var data: Dictionary = {}
	if not response_body.is_empty():
		data = JSON.parse_string(response_body)
	if response_code > 299:
		result.errored = true
		result.error_msg = "HTTP error %d" % response_code
		if data and "message" in data:
			result.error_msg += ": %s" % data["message"]
		return result
	
	if data == null:
		result.errored = true
		result.error_msg = "Failed to parse result body"
		return result
	
	result.data = data
	return result


class Result:
	var data: Dictionary = {}
	var errored: bool = false
	var error_msg: String = ""

	static func err(msg: String) -> Result:
		var r: Result = Result.new()
		r.errored = true
		r.error_msg = msg
		return r


	static func ok(d: Dictionary) -> Result:
		var r: Result = Result.new()
		r.data = d
		return r