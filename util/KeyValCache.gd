extends RefCounted
class_name KeyValCache

var cache_path: String = "user://jamlaunchcache.json"

func store(key: String, val: String):
	var c := get_cache()
	if c.errored:
		return false
	c.cache[key] = val
	return write_cache(c.cache)

func clear(key: String):
	var c := get_cache()
	if c.errored:
		return false
	if c.cache.erase(key):
		return write_cache(c.cache)
	else:
		return false

func get_val(key: String):
	var c := get_cache()
	if c.errored:
		return null
	return c.cache.get(key)

class CacheResult:
	var cache: Dictionary = {}
	var errored: bool = false
	var error_msg: String = ""
	
	static func err(msg: String) -> CacheResult:
		var r := CacheResult.new()
		r.errored = true
		r.error_msg = msg
		return r
	
	static func result(data: Dictionary) -> CacheResult:
		var r := CacheResult.new()
		r.cache = data
		return r

func get_cache() -> CacheResult:
	if !FileAccess.file_exists(cache_path):
		return CacheResult.err("cache file '%s' does not exist" % cache_path)
	var cache_string := FileAccess.get_file_as_string(cache_path)
	var data = JSON.parse_string(cache_string)
	if data == null:
		return CacheResult.err("failed to parse cache file '%s' as JSON" % cache_path)
	return CacheResult.result(data as Dictionary)

func write_cache(cache: Dictionary):
	var s := JSON.stringify(cache)
	
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f == null:
		printerr("Failed to open jam launch cache for writing")
		return false
	f.store_string(s)
	f.close()
	
	return true
