@tool
extends RefCounted
class_name JamConfig

static var default_path: String:
	get:
		return OS.get_data_dir().path_join("jam-launch/jam-config.cfg")

static func set_value(key: String, value: Variant, section: String="core") -> bool:
	var c := get_cache()
	if c.errored:
		printerr("error storing key in Jam Config: %s" % c.error_msg)
		return false
	c.cache.set_value(section, key, value)
	return not write_cache(c.cache).errored

static func clear(key: String, section: String="core") -> bool:
	var c := get_cache()
	if c.errored:
		printerr("error clearing key in Jam Config: %s" % c.error_msg)
		return false
	if not c.exists:
		return false
	if not c.cache.has_section_key(section, key):
		return false
	c.cache.erase_section_key(section, key)
	return not write_cache(c.cache).errored

static func get_value(key: String, section: String="core", default: Variant=null) -> Variant:
	var c := get_cache()
	if c.errored:
		printerr("error getting key from Jam Config: %s" % c.error_msg)
		return default
	elif not c.exists:
		return default
	return c.cache.get_value(section, key, default)

class CacheResult:
	var cache: ConfigFile
	var errored: bool = false
	var error_msg: String = ""
	var exists: bool = true
	var path: String = ""
	
	var _dirty: bool = false
	
	static func err(msg: String) -> CacheResult:
		var r := CacheResult.new()
		r.errored = true
		r.error_msg = msg
		return r
	
	static func not_found(value_path: String) -> CacheResult:
		var r := CacheResult.new()
		r.cache = ConfigFile.new()
		r.exists = false
		r.path = value_path
		return r
	
	static func result(cfg: ConfigFile, value_path: String) -> CacheResult:
		var r := CacheResult.new()
		r.cache = cfg
		r.path = value_path
		return r
	
	func set_value(key: String, value: Variant, section: String="core") -> bool:
		if errored:
			return false
		cache.set_value(section, key, value)
		_dirty = true
		return true
	
	func _notification(what):
		if what == NOTIFICATION_PREDELETE:
			if _dirty:
				var r := JamConfig.write_cache(cache, path)
				if r.errored:
					printerr("error writing back Jam Config: %s" % r.error_msg)

static func get_cache(path_override: String="") -> CacheResult:
	var path := default_path
	if not path_override.is_empty():
		path = path_override
	
	if !FileAccess.file_exists(path):
		return CacheResult.not_found(path)
	var cfg := ConfigFile.new()
	var result = cfg.load(path)
	if result != OK:
		return CacheResult.err("failed to parse Jam Config file '%s'" % path)
	return CacheResult.result(cfg, path)

static func write_cache(cache: ConfigFile, path_override: String="") -> CacheResult:
	var path := default_path
	if not path_override.is_empty():
		path = path_override
	
	var base_dir := path.get_base_dir()
	if not FileAccess.file_exists(base_dir):
		var err = DirAccess.make_dir_recursive_absolute(base_dir)
		if err != OK:
			return CacheResult.err("failed to create directories for Jam Config file '%s' - err %d" % [path, err])
	
	var result := cache.save(path)
	if result != OK:
		return CacheResult.err("failed to write Jam Config file to path '%s' - error code %d" % [path, result])
	
	return CacheResult.result(cache, path)
