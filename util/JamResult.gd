@tool
class_name JamResult
extends RefCounted

## A utility class for storing return values along with descriptive errors. 

var errored: bool = false
var error_msg: String = ""
var value: Variant = null

static func ok(value: Variant = null) -> JamResult:
	var r = JamResult.new()
	r.value = value
	return r

static func err(msg: String, value: Variant = null) -> JamResult:
	var e = JamResult.new()
	e.errored = true
	e.error_msg = msg
	e.value = value
	return e
