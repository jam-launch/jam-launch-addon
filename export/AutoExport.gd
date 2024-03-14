@tool
extends Node
class_name JamAutoExport

class TemplateConfig:
	extends RefCounted
	var template_name: String
	var output_target: String
	var presigned_post: Dictionary

class ExportConfig:
	extends RefCounted
	var game_id: String
	var network_mode: String
	var template_configs: Array[TemplateConfig]

var thread_helper: JamThreadHelper
var extension_ignore_lock: ScopeLocker

var zip_pack_mutex = Mutex.new()

func _init():
	thread_helper = JamThreadHelper.new()
	extension_ignore_lock = ScopeLocker.new()
	extension_ignore_lock.lock_changed.connect(_handle_extension_ignore_locker)
	add_child(thread_helper)

func auto_export(export_config: ExportConfig, http_pool: JamHttpRequestPool, staging_dir: String = "user://jam-auto-export") -> JamError:
	if DirAccess.dir_exists_absolute(staging_dir) or FileAccess.file_exists(staging_dir):
		var res = recursive_delete(staging_dir)
		if res.errored:
			return JamError.err("Failed to remove old staging directory at %s - %s" % [staging_dir, res.error_msg])
	var err = DirAccess.make_dir_recursive_absolute(staging_dir)
	if err != OK:
		return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
	
	var deployment_path = ProjectSettings.globalize_path("res://addons/jam_launch/deployment.cfg")
	var deployment_config = ConfigFile.new()
	deployment_config.set_value("game", "id", export_config.game_id)
	deployment_config.set_value("game", "network_mode", export_config.network_mode)
	deployment_config.save(deployment_path)
	
	# set the export presets if they are not already there
	# TODO: need a better way of playing nice with custom or existing export presets
	if not FileAccess.file_exists("res://export_presets.cfg"):
		print("applying base export_presets.cfg...")
		err = DirAccess.copy_absolute("res://addons/jam_launch/export/preset_base.cfg", "res://export_presets.cfg")
		if err != OK:
			return JamError.err("Failed to initialize export_presets.cfg from base copy")
	
	# get the GDExtension for the server if it's not already there
	var extension_path = "res://addons/jam_launch/extension"
	if not DirAccess.dir_exists_absolute(extension_path):
		print("fetching GDExtension for server export...")
		var c = http_pool.get_client()
		# TODO: maybe stream the download into the file vs buffering the whole thing into a single PackedByteArray response body
		# TODO: Godot-version-sensitive gdx downloads
		err = c.http.request("https://cdn.jamlaunch.com/gdx/4.2/34/gdx.zip")
		if err != OK:
			return JamError.err("Failed to initialize HTTP request for GDExtension download")
		var http_resp: Array = await c.http.request_completed
		if http_resp[1] > 299 or http_resp[1] < 200:
			return JamError.err("Failed HTTP request for GDExtension download with code %d" % http_resp[1])
		
		var gdx_path = staging_dir.path_join("gdx.zip")
		var gdx_writer = FileAccess.open(gdx_path, FileAccess.WRITE)
		if gdx_writer == null:
			return JamError.err("Failed to open file for staging GDExtension download - code %d" % FileAccess.get_open_error())
		gdx_writer.store_buffer(http_resp[3])
		gdx_writer.close()
		
		var gdx_reader = ZIPReader.new()
		err = gdx_reader.open(gdx_path)
		if err != OK:
			return JamError.err("Failed to open GDExtension download for unzipping")
		
		err = DirAccess.make_dir_recursive_absolute(extension_path)
		if err != OK:
			return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
		for f in gdx_reader.get_files():
			var f_path = extension_path.path_join(f)
			var f_writer = FileAccess.open(f_path, FileAccess.WRITE)
			if f_writer == null:
				recursive_delete(extension_path)
				return JamError.err("Failed to open gdx file '%s' for writing - code %d" % [f, FileAccess.get_open_error()])
			f_writer.store_buffer(gdx_reader.read_file(f))
			f_writer.close()
	
	var gdx_ignore_lock = extension_ignore_lock.get_lock()
	
	var tasks: Array[Callable] = []
	for template_config in export_config.template_configs:
		print("adding task for ", template_config.template_name)
		# template export
		var out_base = staging_dir.path_join(template_config.template_name)
		err = DirAccess.make_dir_recursive_absolute(out_base)
		if err != OK:
			return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
		tasks.append(perform_export.bind(out_base, template_config))
	
	var results = await thread_helper.run_multiple_producers(tasks)
	
	var errors = []
	
	for task_result in results:
		if task_result.errored:
			errors.append(task_result.error_msg)
			continue
		var export_result: JamResult = task_result.value
		if export_result.errored:
			errors.append(export_result.error_msg)
	
	if len(errors) > 0:
		return JamError.err(("%d export errors: " % len(errors)) + "\n".join(errors))
	else:
		return JamError.ok()

func _handle_extension_ignore_locker(locked: bool):
	var gdignore_path = "res://addons/jam_launch/extension/.gdignore"
	if locked:
		if FileAccess.file_exists(gdignore_path):
			var err = DirAccess.remove_absolute(gdignore_path)
			if err != OK:
				printerr("Failed to remove extension .gdignore - code %d" % err)
	else:
		if DirAccess.dir_exists_absolute("res://addons/jam_launch/extension"):
			var gdignore_file = FileAccess.open(gdignore_path, FileAccess.WRITE)
			if gdignore_file == null:
				printerr("Failed to create extension .gdignore - code %d" % FileAccess.get_open_error())
			gdignore_file.close()

func perform_export(output_base: String, config: TemplateConfig) -> JamResult:
	# Run the godot export
	var godot = OS.get_executable_path()
	var project_path = ProjectSettings.globalize_path("res://")
	var staging_dir = output_base.path_join("..").simplify_path()
	
	var output_target = ProjectSettings.globalize_path(output_base.path_join(config.output_target))
	
	var export_arg = "--export-release"
	if config.template_name.begins_with("android"):
		export_arg = "--export-debug"
	
	var output = []
	var exit_code = OS.execute(godot, ["--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
	if exit_code != 0:
		return JamResult.err("Non-zero exit code from", output)
	if not (FileAccess.file_exists(output_target) or DirAccess.dir_exists_absolute(output_target)):
		return JamResult.err("Export failed to produce desired output target", output)
	
	# Archive the export output in a zip file
	var zip_name := "%s.zip" % config.template_name
	var zip_path := staging_dir.path_join(zip_name)
	var zip_err := zip_folder(output_base, zip_path)
	if zip_err.errored:
		return JamResult.err("Failed to create zip for %s export - %s" % [config.template_name, zip_err.error_msg], output)
	var zip_reader := FileAccess.open(zip_path, FileAccess.READ)
		
	if zip_reader == null:
		return JamResult.err("Failed to open export zip for upload in %s export - error code %d" % [config.template_name, FileAccess.get_open_error()], output)
	
	var url: String = config.presigned_post["url"]
	var url_no_proto = url.substr(7)
	var split_url = url_no_proto.split("/", false, 1)
	var host: String = split_url[0]
	var path = "/"
	if len(split_url) > 1:
		path += split_url[1]
	var host_ip = IP.resolve_hostname(host)
	
	# prepare request data
	var bound = "----BodyBoundary%d" % (randi() % 100000)
	
	var upload_body_start = PackedByteArray()
	upload_body_start.append_array("--{0}\r\n".format([bound]).to_utf8_buffer())
	var fields = config.presigned_post["fields"]
	for key in fields:
		upload_body_start.append_array(("Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % key).to_utf8_buffer())
		upload_body_start.append_array(("%s" % fields[key]).to_utf8_buffer())
		upload_body_start.append_array("\r\n--{0}\r\n".format([bound]).to_utf8_buffer())
	upload_body_start.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"{0}\"\r\n").format([zip_name]).to_utf8_buffer())
	upload_body_start.append_array(("Content-Type: application/zip\r\n\r\n").to_utf8_buffer())
	
	var last_chunk = PackedByteArray()
	last_chunk.append_array("\r\n--{0}--\r\n".format([bound]).to_utf8_buffer())
	
	var first_chunk = PackedByteArray()
	first_chunk.append_array("POST {0} HTTP/1.1\r\n".format([path]).to_utf8_buffer())
	first_chunk.append_array("Host: {0}\r\n".format([host]).to_utf8_buffer())
	first_chunk.append_array("Connection: keep-alive\r\n".to_utf8_buffer())
	first_chunk.append_array("Content-Type: multipart/form-data; boundary={0}\r\n".format([bound]).to_utf8_buffer())
	first_chunk.append_array("Content-Length: {0}\r\n\r\n".format([upload_body_start.size() + last_chunk.size() + zip_reader.get_length()]).to_utf8_buffer())
	first_chunk.append_array(upload_body_start)
	
	print("uploading %s export..." % config.template_name)
	
	# Set up StreamPeers
	var tcp_peer := StreamPeerTCP.new()
	var err := tcp_peer.connect_to_host(host_ip, 443)
	if err != OK:
		return JamResult.err("Failed to connect to upload host for %s export" % config.template_name, output)
	while true:
		tcp_peer.poll()
		if tcp_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		elif tcp_peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			return JamResult.err("Bad TCP peer status %d for %s export" % [tcp_peer.get_status(), config.template_name], output)
		OS.delay_msec(50)
	var tls_peer := StreamPeerTLS.new()
	err = tls_peer.connect_to_stream(tcp_peer, host)
	if err != OK:
		return JamResult.err("Failed TLS to upload host for %s export" % config.template_name, output)
	while true:
		tls_peer.poll()
		if tls_peer.get_status() == StreamPeerTLS.STATUS_CONNECTED:
			break
		elif tls_peer.get_status() != StreamPeerTLS.STATUS_HANDSHAKING:
			return JamResult.err("Bad TLS peer status %d for %s export" % [tls_peer.get_status(), config.template_name], output)
		OS.delay_msec(50)
	
	# Send data
	err = tls_peer.put_data(first_chunk)
	if err != OK:
		return JamResult.err("Failed to put first chunk of data for %s export upload" % config.template_name, output)
	
	var to_write = zip_reader.get_length()
	while to_write > 0:
		tls_peer.poll()
		if tls_peer.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			zip_reader.close()
			return JamResult.err("Bad TLS peer status %d for %s export (mid-upload)" % [tls_peer.get_status(), config.template_name], output)
		var buf := zip_reader.get_buffer(min(to_write, 16384))
		if buf.size() < 1:
			printerr("unexpected empty read %d (supposedly %d left...)" % [buf.size(), to_write])
			zip_reader.close()
			return JamResult.err("Bad export read with %d bytes left for %s export (mid-upload)" % [to_write, config.template_name], output)
			break
		to_write -= buf.size()
		err = tls_peer.put_data(buf)
		if err != OK:
			zip_reader.close()
			return JamResult.err("Failed to write archive data for %s export upload - code: %d" % [config.template_name, err], output)
	zip_reader.close()
	
	err = tls_peer.put_data(last_chunk)
	if err != OK:
		return JamResult.err("Failed to put last chunk of data for %s export upload" % config.template_name, output)
	
	# Get and parse response
	var http_resp_re := RegEx.new()
	http_resp_re.compile("HTTP/1.1 ([0-9]+) (.*)")
	var full_resp := PackedByteArray()
	for x in range(30000):
		OS.delay_msec(50)
		tls_peer.poll()
		if tls_peer.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			return JamResult.err("Failed to get response for %s export upload before connection closed" % config.template_name, output)
		if tls_peer.get_available_bytes() > 0:
			var resp = tls_peer.get_data(tls_peer.get_available_bytes())
			if resp[0] != 0:
				return JamResult.err("Failure receiving HTTP response bytes from %s export upload" % config.template_name, output)
			
			full_resp.append_array(resp[1])
			var resp_string = full_resp.get_string_from_utf8()
			#print(resp_string)
			var m := http_resp_re.search(resp_string)
			if m != null:
				var code = int(m.get_string(1))
				var reason = m.get_string(2)
				if code < 200 or code > 299:
					return JamResult.err("Received HTTP error during %s upload - %d: %s" % [config.template_name, code, reason], output)
				else:
					return JamResult.ok(output)
	
	return JamResult.err("Unexpectedly long upload during %s export" % config.template_name, output)


static func recursive_delete(directory: String) -> JamError:
	if FileAccess.file_exists(directory):
		var err = DirAccess.remove_absolute(directory)
		if err != OK:
			return JamError.err("Failed to remove file %s: %d" % [directory, err])
		return JamError.ok()
	var dir = DirAccess.open(directory)
	if dir == null:
		return JamError.err("Directory open error: %d" % DirAccess.get_open_error())
	for f in dir.get_files():
		var err = dir.remove(f)
		if err != OK:
			return JamError.err("Failed to remove file %s: %d" % [f, err])
	for d in dir.get_directories():
		var res = recursive_delete(directory.path_join(d))
		if res.errored:
			return res
	
	DirAccess.remove_absolute(directory)
	return JamError.ok()


static func zip_folder(source_root: String, zip_path: String) -> JamError:
	var output = []
	var exit_code: int = 0
	
	if OS.get_name() == "Windows":
		exit_code = OS.execute("powershell.exe", ["-Command", "Compress-Archive -Path '%s' -DestinationPath '%s'" % [ProjectSettings.globalize_path(source_root.path_join("*")), ProjectSettings.globalize_path(zip_path)]], output, true)
	elif OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		exit_code = OS.execute("sh", ["-c", "cd '%s' && zip -r '%s' ." % [ProjectSettings.globalize_path(source_root), ProjectSettings.globalize_path(zip_path)]], output, true)
	else:
		return JamError.err("Failed zip step - unsupported editor platform '%s'" % OS.get_name())
	
	if exit_code != 0:
		return JamError.err("Failed zip file command:\n%s" % "\n".join(output))
	return JamError.ok()
	#var zip := ZIPPacker.new()
	#var err := zip.open(zip_path)
	#if err != OK:
		#return JamError.err("Failed to open zip file '%s' (error code %d)" % [zip_path, err])
	#var out_dir = DirAccess.open(source_root)
	#if out_dir == null:
		#return JamError.err("Failed to open zip target directory '%s' (error code %d)" % [out_dir, err])
	#recursive_zip(out_dir, zip)
	#err = zip.close()
	#if err != OK:
		#return JamError.err("Failed to close zip file (error code %d)" % err)
	#return JamError.ok()

static func recursive_zip(dir: DirAccess, writer: ZIPPacker, root_folder: String = ""):
	dir.include_hidden = true
	
	if len(root_folder) == 0:
		root_folder = dir.get_current_dir()
	
	var err: int
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var abs_file = dir.get_current_dir() + "/" + file_name
		if dir.current_is_dir():
			recursive_zip(DirAccess.open(abs_file), writer, root_folder)
		else:
			err = writer.start_file(abs_file.right(-1 * len(root_folder)).lstrip("/"))
			if err != OK:
				printerr("Unexpected error when starting file write: %d" % err)
			err = writer.write_file(FileAccess.get_file_as_bytes(abs_file))
			if err != OK:
				printerr("Unexpected error when performing file write: %d" % err)
			err = writer.close_file()
			if err != OK:
				printerr("Unexpected error when closing file write: %d" % err)
		file_name = dir.get_next()
