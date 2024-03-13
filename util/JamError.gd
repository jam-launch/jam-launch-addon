@tool
class_name JamError
extends RefCounted

## A utility class for storing error states with descriptive strings. Useful as
## a function return value.

var errored: bool = false
var error_msg: String = ""

static func ok() -> JamError:
	return JamError.new()

static func err(msg: String) -> JamError:
	var e = JamError.new()
	e.errored = true
	e.error_msg = msg
	return e
