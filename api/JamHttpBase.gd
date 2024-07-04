@tool
extends Node
class_name JamHttpBase

var addon_version: String = "unknown"
var api_url: String
var jwt: JamJwt = JamJwt.new()

var pool: JamHttpRequestPool

class Result:
	var data: Dictionary = {}
	var errored: bool = false
	var error_msg: String = ""
	
	static func err(msg: String):
		var r = Result.new()
		r.errored = true
		r.error_msg = msg
		return r
	
	static func ok(d: Dictionary):
		var r = Result.new()
		r.data = d
		return r

func _ready():
	var dir := (self.get_script() as Script).get_path().get_base_dir()
	
	var settings = ConfigFile.new()
	var err = settings.load(dir + "/../settings.cfg")
	if err != OK:
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
	var h = pool.get_client()
	var err = h.http.request(url)
	if err != OK:
		return JamResult.err("HTTP request error")
	
	var resp = await h.http.request_completed
	if resp[1] > 299:
		return JamResult.err("HTTP error code %d" % [resp[1]])
	
	var s = resp[3].get_string_from_utf8()
	if len(s) < 1:
		return JamResult.err("Empty of invalid HTTP response")
	
	return JamResult.ok(s)

func _json_http(route: String, method: HTTPClient.Method=HTTPClient.METHOD_GET, body: Variant=null) -> Result:
	var result = Result.new()
	var err
	var h = pool.get_client()
	if body != null:
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
	if err != OK:
		result.errored = true
		result.error_msg = "HTTP request error"
		return result
		
	var resp = await h.http.request_completed
	var response_code = resp[1]
	var response_body: String = resp[3].get_string_from_utf8()
	var data = {}
	if len(response_body) > 0:
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
