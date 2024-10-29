class_name KeyValCache
extends RefCounted

var old_default_cache_path: String = "user://jamlaunchcache.json"
var cache_path: String = OS.get_data_dir().path_join("jam-launch/data.json")

func store(key: String, val: String) -> bool:
	var c: CacheResult = get_cache()
	if c.errored:
		if not c.no_file:
			printerr("error storing key in cache: %s" % c.error_msg)
			return false
		c = CacheResult.result({})
	c.cache[key] = val
	return write_cache(c.cache)


func clear(key: String) -> bool:
	var c: CacheResult = get_cache()
	if c.errored:
		if not c.no_file:
			printerr("error clearing key in cache: %s" % c.error_msg)
		return false
	if c.cache.erase(key):
		return write_cache(c.cache)
	else:
		return false


func get_val(key: String) -> Variant:
	var c: CacheResult = get_cache()
	if c.errored:
		return null
	return c.cache.get(key)


func get_cache(path_override: String = "") -> CacheResult:
	var path: String = cache_path
	if not path_override.is_empty():
		path = path_override
	if !FileAccess.file_exists(path):
		if FileAccess.file_exists(old_default_cache_path) and path_override.is_empty():
			var res: CacheResult = get_cache(old_default_cache_path)
			if not res.errored:
				write_cache(res.cache, cache_path)
				return res
		var e: CacheResult = CacheResult.err("cache file '%s' does not exist" % path)
		e.no_file = true
		return e
	var cache_string: String = FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(cache_string)
	if data == null:
		return CacheResult.err("failed to parse cache file '%s' as JSON" % path)
	return CacheResult.result(data as Dictionary)


func write_cache(cache: Dictionary, path_override: String = "") -> bool:
	if path_override.is_empty():
		path_override = cache_path

	var s: String = JSON.stringify(cache)
	var base_dir: String = path_override.get_base_dir()
	if not FileAccess.file_exists(base_dir):
		var err: Error = DirAccess.make_dir_recursive_absolute(base_dir)
		if not err == OK:
			printerr("failed to create directories for cache file '%s' - err %d" % [path_override, err])
			return false

	var f: FileAccess = FileAccess.open(path_override, FileAccess.WRITE)
	if f == null:
		printerr("failed to open cache for writing at '%s'" % path_override)
		return false
	f.store_string(s)
	f.close()
	return true


class CacheResult:
	var cache: Dictionary = {}
	var errored: bool = false
	var error_msg: String = ""
	var no_file: bool = false

	static func err(msg: String) -> CacheResult:
		var r: CacheResult = CacheResult.new()
		r.errored = true
		r.error_msg = msg
		return r

	static func result(data: Dictionary) -> CacheResult:
		var r: CacheResult = CacheResult.new()
		r.cache = data
		return r