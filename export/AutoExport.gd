@tool
extends Node
class_name JamAutoExport

class BuildConfig:
	extends RefCounted
	var template_name: String
	var output_target: Variant
	var presigned_post: Dictionary
	var log_presigned_post: Dictionary

class ExportConfig:
	extends RefCounted
	var game_id: String
	var network_mode: String
	var build_configs: Array[BuildConfig]
	var parallel: bool
	var export_timeout: int

var thread_helper: JamThreadHelper

func _init():
	thread_helper = JamThreadHelper.new()
	add_child(thread_helper)

func auto_export(export_config: ExportConfig, http_pool: JamHttpRequestPool, staging_dir: String = "user://jam-auto-export") -> JamError:
	# set up staging directory where exports will be placed
	if DirAccess.dir_exists_absolute(staging_dir) or FileAccess.file_exists(staging_dir):
		var res = recursive_delete(staging_dir)
		if res.errored:
			return JamError.err("Failed to remove old staging directory at %s - %s" % [staging_dir, res.error_msg])
	var err = DirAccess.make_dir_recursive_absolute(staging_dir)
	if err != OK:
		return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
	
	# update the deployment.cfg file
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
	
	# prepare the export tasks
	var tasks: Array[Callable] = []
	for build_config in export_config.build_configs:
		print("adding task for ", build_config.template_name)
		# template export
		var out_base = staging_dir.path_join(build_config.template_name)
		err = DirAccess.make_dir_recursive_absolute(out_base)
		if err != OK:
			return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
		tasks.append(perform_export.bind(out_base, build_config, export_config.export_timeout))
	
	# run the export tasks
	var results = []
	if export_config.parallel:
		results = await thread_helper.run_multiple_producers(tasks)
	else:
		for t in tasks:
			results.append(await thread_helper.run_threaded_producer(t))
	
	# handle the export results
	var errors = []
	var idx = -1
	for task_result in results:
		idx += 1
		if task_result.errored:
			errors.append(task_result.error_msg)
			continue
		
		var export_result = task_result.value
		if export_result.errored:
			errors.append(export_result.error_msg)

	if len(errors) > 0:
		return JamError.err(("%d export errors: " % len(errors)) + "\n".join(errors))
	else:
		return JamError.ok()

func perform_export(output_base: String, config: BuildConfig, timeout: int) -> JamError:
	# Prepare the godot export
	var output = []
	var err := perform_godot_export(output_base, config, timeout, output)
	if not err.errored:
		err = upload_export(output_base, config)
	
	var log_err = JamError.ok()
	if len(output) > 0:
		var reader = StreamingUpload.StringReader.new()
		reader.data = output[0]
		reader.data_length = len(output[0])
		reader.filename = "%s-build.log" % config.template_name
		log_err = StreamingUpload.streaming_upload(config.log_presigned_post["url"], config.log_presigned_post["fields"], reader)
	
	if err.errored:
		return err
	elif log_err.errored:
		return log_err
	
	return JamError.ok()

static func perform_godot_export(output_base: String, config: BuildConfig, timeout: int, output: Array) -> JamError:
	var godot = OS.get_executable_path()
	var project_path = ProjectSettings.globalize_path("res://")
	var staging_dir = output_base.path_join("..").simplify_path()
	var output_target = ProjectSettings.globalize_path(output_base.path_join(config.output_target))
	var export_arg = "--export-release"
	if config.template_name.begins_with("android"):
		export_arg = "--export-debug"
	var exit_code
	if OS.get_name() == "Windows":
		var timeout_script = ProjectSettings.globalize_path("res://addons/jam_launch/export/run-with-timeout.ps1")
		exit_code = OS.execute("powershell.exe", ["-file", timeout_script, timeout, godot, "--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
	else:
		exit_code = OS.execute(godot, ["--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
	if exit_code != 0:
		return JamError.err("Non-zero exit code from")
	if not (FileAccess.file_exists(output_target) or DirAccess.dir_exists_absolute(output_target)):
		return JamError.err("Export failed to produce desired output target")
	return JamError.ok()

static func upload_export(output_base: String, config: BuildConfig) -> JamError:
	# Archive the export output in a zip file
	var staging_dir = output_base.path_join("..").simplify_path()
	var zip_name := "%s.zip" % config.template_name
	var zip_path := staging_dir.path_join(zip_name)
	var zip_err := zip_folder(output_base, zip_path)
	if zip_err.errored:
		return JamError.err("Failed to create zip for %s export - %s" % [config.template_name, zip_err.error_msg])
	
	# Perform streaming upload of the zip file
	var stream_reader_res = StreamingUpload.FileReader.from_path(zip_path)
	if stream_reader_res.errored:
		return JamError.err(stream_reader_res.error_msg)
	
	var upload_res = StreamingUpload.streaming_upload(
		config.presigned_post["url"],
		config.presigned_post["fields"],
		stream_reader_res.value
	)
	if upload_res.errored:
		return JamError.err("export upload failed: %s" % upload_res.error_msg)
	return JamError.ok()

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
