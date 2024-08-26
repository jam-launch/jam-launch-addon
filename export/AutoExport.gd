@tool
extends Node
class_name JamAutoExport

class BuildConfig:
	extends RefCounted
	var template_name: String
	var output_target: String
	var no_zip: bool
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

func auto_export(export_config: ExportConfig, staging_dir: String = "user://jam-auto-export") -> JamError:
	# set up staging directory where exports will be placed
	print(export_config.game_id)
	if DirAccess.dir_exists_absolute(staging_dir) or FileAccess.file_exists(staging_dir):
		var deleteRes := JamAutoExport.recursive_delete(staging_dir)
		if deleteRes.errored:
			return JamError.err("Failed to remove old staging directory at %s - %s" % [staging_dir, deleteRes.error_msg])
	var err = DirAccess.make_dir_recursive_absolute(staging_dir)
	if err != OK:
		return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
	
	# set the export presets if they are not already there
	var res := JamAutoExport.merge_presets("res://addons/jam_launch/export/preset_base.cfg")
	if res.errored:
		return res
	
	# prepare the export tasks
	var tasks: Array[Callable] = []
	for build_config in export_config.build_configs:
		print("adding task for ", build_config.template_name)
		# template export
		var out_base := staging_dir.path_join(build_config.template_name)
		err = DirAccess.make_dir_recursive_absolute(out_base)
		if err != OK:
			return JamError.err("Failed to create staging directory at %s - code %d" % [staging_dir, err])
		tasks.append(perform_export.bind(out_base, build_config, export_config.export_timeout))
	
	# run the export tasks
	var results: Array[JamThreadHelper.ThreadProduct] = []
	if export_config.parallel:
		results = await thread_helper.run_multiple_producers(tasks)
	else:
		for t in tasks:
			results.append(await thread_helper.run_threaded_producer(t))
	
	# handle the export results
	var errors: PackedStringArray = []
	for task_result in results:
		if task_result.errored:
			errors.append(task_result.error_msg)
			continue
		
		var export_result := task_result.value as JamError
		if export_result.errored:
			errors.append(export_result.error_msg)

	if len(errors) > 0:
		return JamError.err(("%d export errors: " % [len(errors)]) + "\n".join(errors))
	else:
		return JamError.ok()

func perform_export(output_base: String, config: BuildConfig, timeout: int) -> JamError:
	# Prepare the godot export
	var output := []
	var err := JamAutoExport.perform_godot_export(output_base, config, timeout, output)
	if not err.errored:
		err = JamAutoExport.upload_export(output_base, config)
	
	var reader := StreamingUpload.StringReader.new()
	if len(output) > 0:
		reader.data = output[0]
		reader.data_length = len(output[0])
	else:
		reader.data = "No export output log was available"
		reader.data_length = len(reader.data)
	reader.filename = "%s-build.log" % config.template_name
	var log_err := StreamingUpload.streaming_upload(config.log_presigned_post["url"] as String, config.log_presigned_post["fields"] as Dictionary, reader)
	
	if err.errored:
		if log_err.errored:
			printerr("log upload failed after export failure - release may be stuck in 'pending' state")
			printerr(log_err.error_msg)
		return err
	elif log_err.errored:
		return log_err
	
	return JamError.ok()

static func perform_godot_export(output_base: String, config: BuildConfig, timeout: int, output: Array) -> JamError:
	var godot := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output_target := ProjectSettings.globalize_path(output_base.path_join(config.output_target))
	var export_arg := "--export-release"
	if config.template_name.to_lower().contains("android"):
		export_arg = "--export-debug"
	var exit_code
	if OS.get_name() == "Windows":
		var ps_check_out := []
		var ps_check = OS.execute("powershell.exe", ["Get-ExecutionPolicy"], ps_check_out, true)
		if ps_check == 0 and ps_check_out[0].strip_edges() == "Unrestricted":
			var timeout_script = ProjectSettings.globalize_path("res://addons/jam_launch/export/run-with-timeout.ps1")
			exit_code = OS.execute("powershell.exe", ["-file", timeout_script, timeout, godot, "--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
		else:
			if ps_check != 0:
				push_warning("powershell.exe failed to execute - export timeout will be ignored")
			else:
				push_warning("cannot execute timeout script due to '%s' powershell script execution policy - set 'Set-ExecutionPolicy -Scope CurrentUser unrestricted' in an admin powershell to enable the timeout functionality" % [ps_check_out[0].strip_edges()])
			exit_code = OS.execute(godot, ["--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
	else:
		var timeout_check = OS.execute("command", ["-v", "timeout"])
		var gtimeout_check = OS.execute("command", ["-v", "gtimeout"])
		if timeout_check == 0:
			exit_code = OS.execute("timeout", [timeout * 60, godot, "--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
		elif gtimeout_check == 0:
			exit_code = OS.execute("gtimeout", [timeout * 60, godot, "--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
		else:
			push_warning("Neither the 'timeout' or 'gtimeout' command could be found on this system - ignoring export timout")
			exit_code = OS.execute(godot, ["--headless", export_arg, config.template_name, "--path", project_path, output_target], output, true)
	if exit_code != 0:
		if exit_code == 124:
			return JamError.err("Export timed out")
		else:
			if (output[0].contains("No export template found at the expected path")):
				printerr("Make sure you have installed the export templates for this version of Godot - you can check for and download the export templates at 'Editor -> Manage Export Templates...' in the editor menu")
			return JamError.err("Non-zero exit code from export command - %d" % [exit_code])
	if not (FileAccess.file_exists(output_target) or DirAccess.dir_exists_absolute(output_target)):
		if (output[0].contains("No export template found at the expected path")):
			printerr("Make sure you have installed the export templates for this version of Godot - you can check for and download the export templates at 'Editor -> Manage Export Templates...' in the editor menu")
		return JamError.err("Export failed to produce desired output target")
	return JamError.ok()

static func upload_export(output_base: String, config: BuildConfig) -> JamError:
	var staging_dir = output_base.path_join("..").simplify_path()
	var artifact_path: String
	if config.no_zip:
		artifact_path = ProjectSettings.globalize_path(output_base.path_join(config.output_target))
	else:
		# Archive the export output in a zip file
		var zip_name := "%s.zip" % config.template_name
		artifact_path = staging_dir.path_join(zip_name)
		var zip_err := zip_folder(output_base, artifact_path)
		if zip_err.errored:
			return JamError.err("Failed to create zip for %s export - %s" % [config.template_name, zip_err.error_msg])
	
	# Perform streaming upload of the zip file
	var stream_reader_res := StreamingUpload.FileReader.from_path(artifact_path)
	if stream_reader_res.errored:
		return JamError.err(stream_reader_res.error_msg)
	
	var upload_res := StreamingUpload.streaming_upload(
		config.presigned_post["url"] as String,
		config.presigned_post["fields"] as Dictionary,
		stream_reader_res.value as StreamingUpload.FileReader
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
	var output := []
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

	# TODO: maybe this can still be used as a fallback if the required system utilities are not available
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
	var file_name := dir.get_next()
	while file_name != "":
		var abs_file := dir.get_current_dir() + "/" + file_name
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

static func merge_presets(additions_path: String, base_path: String = "res://export_presets.cfg") -> JamError:
	
	if not FileAccess.file_exists(base_path):
		var err = DirAccess.copy_absolute(additions_path, base_path)
		if err != OK:
			return JamError.err("Failed to initialize export_presets.cfg from base copy")
	else:
		var export_cfg = ConfigFile.new()
		var err = export_cfg.load(base_path)
		if err != OK:
			return JamError.err("Failed to load existing export presets at '%s'" % base_path)
		
		var jam_export_cfg = ConfigFile.new()
		err = jam_export_cfg.load(additions_path)
		if err != OK:
			return JamError.err("Failed to load additional export presets at '%s'" % additions_path)
		
		var jam_preset_map: Dictionary = {}
		var jam_preset_options_map: Dictionary = {}
		var preset_regex = RegEx.create_from_string("^preset\\.(\\d+)$")
		for section in jam_export_cfg.get_sections():
			if preset_regex.search(section) == null:
				continue
			# determine name and get values
			var vals = {}
			var preset_name = ""
			for key in jam_export_cfg.get_section_keys(section):
				vals[key] = jam_export_cfg.get_value(section, key)
				if key == "name":
					preset_name = vals[key]
			jam_preset_map[preset_name] = vals
			# get options section
			vals = {}
			var opt_section := section + ".options"
			for key in jam_export_cfg.get_section_keys(opt_section):
				vals[key] = jam_export_cfg.get_value(opt_section, key)
			jam_preset_options_map[preset_name] = vals
		
		var highest_section_num := -1
		for section in export_cfg.get_sections():
			var preset_match = preset_regex.search(section)
			if preset_match == null:
				continue
			highest_section_num = maxi(preset_match.get_string(1).to_int(), highest_section_num)
			for key in export_cfg.get_section_keys(section):
				if key == "name":
					jam_preset_map.erase(export_cfg.get_value(section, key))
					break
		
		var insert_index = highest_section_num + 1
		for preset_name in jam_preset_map:
			var section := "preset.%d" % [insert_index]
			insert_index += 1
			for key in jam_preset_map[preset_name]:
				export_cfg.set_value(section, key as String, jam_preset_map[preset_name][key])
			
			var opt_section := "%s.options" % [section]
			for key in jam_preset_options_map[preset_name]:
				export_cfg.set_value(opt_section, key as String, jam_preset_options_map[preset_name][key])
		
		if len(jam_preset_map.keys()) > 0:
			err = export_cfg.save(base_path)
			if err != OK:
				return JamError.err("Failed to save updated export presets at '%s'" % base_path)
	
	return JamError.ok()
