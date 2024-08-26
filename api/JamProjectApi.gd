@tool
extends JamHttpBase
class_name JamProjectApi


func _ready():
	super()

func create_project(project_name: String) -> Result:
	return await _json_http(
		"/projects",
		HTTPClient.METHOD_POST,
		{"project_name": project_name}
	)

func list_projects() -> Result:
	return await _json_http("/projects")

func get_project(project_id: String) -> Result:
	return await _json_http("/projects/%s" % project_id)

func delete_project(project_id: String) -> Result:
	return await _json_http(
		"/projects/%s" % project_id,
		HTTPClient.METHOD_DELETE
	)

func prepare_release(project_id: String, config: Dictionary) -> Result:
	var req = {
		"network_mode": config["network_mode"],
		"builds": config["builds"].map(func(b): return {
			"name": b["name"],
			"export_name": b["export_name"],
			"is_server": b.get("is_server", false),
			"is_web": b.get("is_web", false),
			"no_zip": b.get("no_zip", false)
		})
	}
	return await _json_http(
		"/projects/%s/releases" % project_id,
		HTTPClient.METHOD_POST,
		req
	)

func update_release(project_id: String, release_id: String, props: Dictionary) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s" % [project_id, release_id],
		HTTPClient.METHOD_POST,
		props
	)

func post_config(project_id: String, cfg: Dictionary) -> Result:
	return await _json_http(
		"/projects/%s/config" % project_id,
		HTTPClient.METHOD_POST,
		cfg
	)

func get_build_logs(project_id: String, release_id: String, log_id: String) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s/buildlogs/%s" % [
			project_id,
			release_id,
			log_id,
		])

func get_sessions(project_id: String, active: bool) -> Result:
	var state = "up"
	if not active:
		state = "down"
	return await _json_http(
		"/projects/%s/sessions/%s" % [
			project_id,
			state,
		])

func get_session(project_id: String, release_id: String, session_id: String) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s/sessions/%s" % [
			project_id,
			release_id,
			session_id,
		])

func get_session_logs(project_id: String, release_id: String, session_id: String) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s/sessions/%s/logs" % [
			project_id,
			release_id,
			session_id,
		])

func terminate_session(project_id: String, release_id: String, session_id: String) -> Result:
	return await _json_http(
		"/projects/%s/releases/%s/sessions/%s/terminate" % [
			project_id,
			release_id,
			session_id,
		],
		HTTPClient.METHOD_POST,
		{}
	)

func get_test_key(project_id: String, release: String, test_num: int) -> Result:
	return await _json_http(
		"/projects/%s/testkey" % [project_id],
		HTTPClient.METHOD_POST,
		{
			"test_num": test_num,
			"release": release
		}
	) 

func get_local_server_keys(project_id: String, release: String) -> Result:
	return await _json_http(
		"/projects/%s/localserverkeys" % [project_id],
		HTTPClient.METHOD_POST,
		{
			"release": release
		}
	) 



func create_channel(project_id: String, channel: String) -> Result:
	return await _json_http(
		"/projects/%s/channels" % [project_id],
		HTTPClient.METHOD_POST,
		{
			"name": channel
		}
	)

func update_channel(project_id: String, channel: String, props: Dictionary) -> Result:
	return await _json_http(
		"/projects/%s/channels/%s" % [project_id, channel],
		HTTPClient.METHOD_POST,
		props
	)

func get_channels(project_id: String, release: String) -> Result:
	return await _json_http(
		"/projects/%s/channels" % [project_id],
		HTTPClient.METHOD_GET
	) 
