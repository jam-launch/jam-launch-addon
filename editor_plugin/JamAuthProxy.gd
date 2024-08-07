@tool
extends Node
class_name JamAuthProxy

var server := TCPServer.new()
var connections: Array[StreamPeerTCP]
var req_counter := 0
var api: JamProjectApi

var localhostKey: String
var localhostCert: String

class RequestHandler:
	extends Node
	
	var peer: StreamPeerTCP
	var request: String
	var request_num: int
	var api: JamProjectApi
	var is_done: bool = false
	var is_started: bool = false
	var localhostKey: String = ""
	var localhostCert: String = ""
	
	func _process(_delta):
		if is_started:
			return
		is_started = true
		
		var req_parts := request.split("/")
		if req_parts[0] == "key":
			_get_testclient_key(req_parts)
		elif req_parts[0] == "serverkeys":
			_get_server_keys(req_parts)
		elif req_parts[0] == "localhostkey":
			_get_localhost_key(req_parts)
		elif req_parts[0] == "localhostcert":
			_get_localhost_cert(req_parts)
		else:
			await _err("Unexpected auth proxy request: %s" % req_parts[0])
			return
	
	func _err(msg: String):
		printerr(msg)
		peer.put_string("Error: %s" % msg)
		await get_tree().create_timer(1.0).timeout
		is_done = true
	
	func _get_testclient_key(req_parts: PackedStringArray):
		if len(req_parts) != 3:
			await _err("Expected 3 parts in key request, got %d" % len(req_parts))
			return
		
		var test_num = (request_num % 9) + 1
		var res := await api.get_test_key(req_parts[1], req_parts[2], test_num)
		if res.errored:
			await _err(res.error_msg)
			return
		peer.put_string(res.data["test_jwt"])
		await get_tree().create_timer(1.0).timeout
		is_done = true
	
	func _get_server_keys(req_parts: PackedStringArray):
		if len(req_parts) != 3:
			await _err("Expected 3 parts in server keys request, got %d" % len(req_parts))
			return
		
		var res := await api.get_local_server_keys(req_parts[1], req_parts[2])
		if res.errored:
			await _err(res.error_msg)
			return
		peer.put_string(JSON.stringify(res.data))
		await get_tree().create_timer(1.0).timeout
		is_done = true
	
	func _get_localhost_key(req_parts: PackedStringArray):
		if len(req_parts) != 1:
			await _err("Expected 1 part in localhost key request, got %d" % len(req_parts))
			return
		peer.put_string(localhostKey)
		await get_tree().create_timer(1.0).timeout
		is_done = true
	
	func _get_localhost_cert(req_parts: PackedStringArray):
		if len(req_parts) != 1:
			await _err("Expected 1 parts in localhost cert request, got %d" % len(req_parts))
			return
		peer.put_string(localhostCert)
		await get_tree().create_timer(1.0).timeout
		is_done = true
		

# Called when the node enters the scene tree for the first time.
func _ready():
	pass


func start():
	if server.is_listening():
		return
	print_debug("starting Jam Launch auth proxy server...")
	
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	localhostKey = key.save_to_string()
	localhostCert = crypto.generate_self_signed_certificate(key, "CN=localhost").save_to_string()
	
	var port := 17343
	var err := server.listen(port, "127.0.0.1")
	if err != OK:
		printerr("failed to start auth proxy server - code %d" % err)

func _exit_tree():
	if server.is_listening():
		print_debug("stopping Jam Launch auth proxy server...")
		server.stop()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if server.is_listening():
			print_debug("stopping Jam Launch auth proxy server...")
			server.stop()

func get_port():
	return server.get_local_port()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not server.is_listening():
		return
	
	var to_remove = []
	for c in connections:
		var err = c.poll()
		if err != OK:
			to_remove.push_back(c)
			continue
		var status = c.get_status()
		if status == StreamPeerTCP.STATUS_ERROR:
			to_remove.push_back(c)
		if status != StreamPeerTCP.STATUS_CONNECTED:
			continue
		
		if c.get_available_bytes() < 1:
			continue
		
		var req_string = c.get_string()
		var req = RequestHandler.new()
		req.localhostKey = localhostKey
		req.localhostCert = localhostCert
		req.request = req_string
		req.request_num = req_counter
		req.api = api
		req.peer = c
		add_child(req)
		
		req_counter += 1
	
	for c in to_remove:
		connections.erase(c)
	
	for r in get_children():
		if r.is_done:
			r.queue_free()
	
	while true:
		if not server.is_connection_available():
			return
		connections.append(server.take_connection())
