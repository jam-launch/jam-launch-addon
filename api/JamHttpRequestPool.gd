@tool
class_name JamHttpRequestPool
extends Node

func get_client() -> ScopedClient:
	for c in get_children():
		if not c.in_use:
			return ScopedClient.new(c as HttpHolder)
	
	var hh := HttpHolder.new()
	add_child(hh)
	return ScopedClient.new(hh)


class HttpHolder:
	extends HTTPRequest
	var in_use: bool = false


class ScopedClient:
	extends RefCounted
	var http: HttpHolder

	func _init(holder: HttpHolder) -> void:
		http = holder
		http.in_use = true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			http.in_use = false


	


