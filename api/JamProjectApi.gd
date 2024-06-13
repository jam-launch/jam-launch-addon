@tool
extends JamHttpBase
class_name JamProjectApi

var auto_export: JamAutoExport

func _ready():
	super()
	auto_export = JamAutoExport.new()
	add_child(auto_export)

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
			"is_web": b.get("is_web", false)
		})
	}
	return await _json_http(
		"/projects/%s/releases" % project_id,
		HTTPClient.METHOD_POST,
		req
	)

func do_auto_export(project_id: String, config: Dictionary, prepare_result: Dictionary) -> JamError:
	var export_config = JamAutoExport.ExportConfig.new()
	export_config.network_mode = config["network_mode"]
	export_config.export_timeout = config["export_timeout"]
	export_config.parallel = config["parallel"]
	
	export_config.game_id = "%s-%s" % [project_id, prepare_result["id"]]
	
	export_config.build_configs = ([] as Array[JamAutoExport.BuildConfig])
	
	for b in config["builds"]:
		var c := JamAutoExport.BuildConfig.new()
		c.output_target = b["export_name"]
		c.template_name = b["template_name"]
		
		var mapped := false
		for t in prepare_result["builds"]:
			if t["build_name"] == b["name"]:
				c.presigned_post = t["upload_target"]
				c.log_presigned_post = t["log_upload_target"]
				mapped = true
				break
		if not mapped:
			return Result.err("Failed to get upload target for '%s' build" % b["name"])
		
		export_config.build_configs.append(c)
	
	return await auto_export.auto_export(export_config, pool)

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
