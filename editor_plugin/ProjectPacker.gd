@tool
extends Object
class_name ProjectPacker

static func pack(project_dir: EditorFileSystemDirectory):
	var dir = DirAccess.open("user://")
	if dir.file_exists("jamlaunchexport.zip"):
		dir.remove("jamlaunchexport.zip")
	dir.remove("project.godot")
	var writer := ZIPPacker.new()
	var err := writer.open("user://jamlaunchexport.zip")
	if err != OK:
		return "failed to stage local project archive"
	
	if dir.file_exists("jamlaunchexportproject.godot"):
		dir.remove("jamlaunchexportproject.godot")
	err = ProjectSettings.save_custom("user://jamlaunchexportproject.godot")
	if err != OK:
		return "failed to stage project settings"
		
	writer.start_file("project.godot")
	writer.write_file(FileAccess.get_file_as_bytes("user://jamlaunchexportproject.godot"))
	writer.close_file()
	
	_pack_dir(project_dir, writer)

	writer.close()
	
	return FileAccess.get_file_as_bytes("user://jamlaunchexport.zip")


static func _pack_full_dir(dir: DirAccess, writer: ZIPPacker):
	dir.include_hidden = true
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var abs_file = dir.get_current_dir() + "/" + file_name
		if dir.current_is_dir():
			_pack_full_dir(DirAccess.open(abs_file), writer)
		else:
			writer.start_file(abs_file.right(-6).lstrip("/"))
			writer.write_file(FileAccess.get_file_as_bytes(abs_file))
			writer.close_file()
		file_name = dir.get_next()

static func _pack_dir(dir: EditorFileSystemDirectory, writer: ZIPPacker):
	var base_path = dir.get_path()
	
	var extension_base = false
	
	for idx in range(dir.get_file_count()):
		var file_path = base_path + "/" + dir.get_file(idx)
		if file_path.ends_with(".gdextension"):
			# if there is an extension spec, assume the subdirectories should be fully packed
			extension_base = true
		writer.start_file(file_path.right(-6).lstrip("/"))
		writer.write_file(FileAccess.get_file_as_bytes(file_path))
		writer.close_file()
	
	for idx in range(dir.get_subdir_count()):
		var subdir = dir.get_subdir(idx)
		if extension_base:
			_pack_full_dir(DirAccess.open(base_path + "/" + subdir.get_name()), writer)
		else:
			_pack_dir(subdir, writer)
