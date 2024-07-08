@tool
extends Object
class_name StreamingUpload

class StringReader:
	extends RefCounted
	var filename: String
	var data_length: int
	var data: String
	var idx: int = 0
		
	func get_data(max_bytes: int) -> PackedByteArray:
		var toTake := min(max_bytes, len(data)) as int
		var buf = data.substr(idx, toTake).to_utf8_buffer()
		idx += toTake
		return buf

class FileReader:
	extends RefCounted
	var filename: String
	var data_length: int
	var data_reader: FileAccess
	
	static func from_path(path: String) -> JamResult:
		var r = FileReader.new()
		r.filename = path.get_file()
		r.data_reader = FileAccess.open(path, FileAccess.READ)
		if r.data_reader == null:
			return JamResult.err("failed to open file '%s' - error code %d" % [path, FileAccess.get_open_error()])
		r.data_length = r.data_reader.get_length()
		return JamResult.ok(r)
		
	func get_data(max_bytes: int) -> PackedByteArray:
		return data_reader.get_buffer(max_bytes)
	
	func _notification(what):
		if what == NOTIFICATION_PREDELETE:
			if data_reader != null:
				data_reader.close()

static func streaming_upload(url: String, fields: Dictionary, reader) -> JamError:
	var url_no_proto = url.substr(7)
	var split_url = url_no_proto.split("/", false, 1)
	var host: String = split_url[0]
	var path = "/"
	if len(split_url) > 1:
		path += split_url[1]
	var host_ip := IP.resolve_hostname(host)
	
	# prepare request data
	var bound = "----BodyBoundary%d" % (randi() % 100000)
	
	var upload_body_start := PackedByteArray()
	upload_body_start.append_array("--{0}\r\n".format([bound]).to_utf8_buffer())
	for key in fields:
		upload_body_start.append_array(("Content-Disposition: form-data; name=\"{0}\"\r\n\r\n".format([key])).to_utf8_buffer())
		upload_body_start.append_array(("{0}".format([fields[key]])).to_utf8_buffer())
		upload_body_start.append_array("\r\n--{0}\r\n".format([bound]).to_utf8_buffer())
	upload_body_start.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"{0}\"\r\n").format([reader.filename]).to_utf8_buffer())
	upload_body_start.append_array(("Content-Type: application/zip\r\n\r\n").to_utf8_buffer())
	
	var last_chunk := PackedByteArray()
	last_chunk.append_array("\r\n--{0}--\r\n".format([bound]).to_utf8_buffer())
	
	var first_chunk := PackedByteArray()
	first_chunk.append_array("POST {0} HTTP/1.1\r\n".format([path]).to_utf8_buffer())
	first_chunk.append_array("Host: {0}\r\n".format([host]).to_utf8_buffer())
	first_chunk.append_array("Connection: keep-alive\r\n".to_utf8_buffer())
	first_chunk.append_array("Content-Type: multipart/form-data; boundary={0}\r\n".format([bound]).to_utf8_buffer())
	first_chunk.append_array("Content-Length: {0}\r\n\r\n".format([upload_body_start.size() + last_chunk.size() + reader.data_length]).to_utf8_buffer())
	first_chunk.append_array(upload_body_start)
	
	# Set up StreamPeers
	var tcp_peer := StreamPeerTCP.new()
	var err := tcp_peer.connect_to_host(host_ip, 443)
	if err != OK:
		return JamError.err("Failed to connect to upload host for {0} upload".format([reader.filename]))
	while true:
		tcp_peer.poll()
		if tcp_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		elif tcp_peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			return JamError.err("Bad TCP peer status %d for %s export" % [tcp_peer.get_status(), reader.filename])
		OS.delay_msec(50)
	var tls_peer := StreamPeerTLS.new()
	err = tls_peer.connect_to_stream(tcp_peer, host)
	if err != OK:
		return JamError.err("Failed TLS to upload host for %s export" % [reader.filename])
	while true:
		tls_peer.poll()
		if tls_peer.get_status() == StreamPeerTLS.STATUS_CONNECTED:
			break
		elif tls_peer.get_status() != StreamPeerTLS.STATUS_HANDSHAKING:
			return JamError.err("Bad TLS peer status %d for %s export" % [tls_peer.get_status(), reader.filename])
		OS.delay_msec(50)
	
	# Send data
	err = tls_peer.put_data(first_chunk)
	if err != OK:
		return JamError.err("Failed to put first chunk of data for %s export upload" % [reader.filename])
	
	var to_write = reader.data_length
	while to_write > 0:
		tls_peer.poll()
		if tls_peer.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			return JamError.err("Bad TLS peer status %d for %s export (mid-upload)" % [tls_peer.get_status(), reader.filename])
		var maxBytes = min(to_write, 16384)
		var buf: PackedByteArray = reader.get_data(maxBytes)
		if buf.size() < 1:
			printerr("unexpected empty read %d (supposedly %d left...)" % [buf.size(), to_write])
			return JamError.err("Bad export read with %d bytes left for %s export (mid-upload)" % [to_write, reader.filename])
		to_write -= buf.size()
		err = tls_peer.put_data(buf)
		if err != OK:
			return JamError.err("Failed to write archive data for %s export upload - code: %d" % [reader.filename, err])
	
	err = tls_peer.put_data(last_chunk)
	if err != OK:
		return JamError.err("Failed to put last chunk of data for %s export upload" % [reader.filename])
	
	# Get and parse response
	var http_resp_re := RegEx.new()
	http_resp_re.compile("HTTP/1.1 ([0-9]+) (.*)")
	var full_resp := PackedByteArray()
	for x in range(200 * 60 * 3):
		OS.delay_msec(50)
		tls_peer.poll()
		if tls_peer.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			return JamError.err("Failed to get response for %s export upload before connection closed" % [reader.filename])
		if tls_peer.get_available_bytes() > 0:
			var resp = tls_peer.get_data(tls_peer.get_available_bytes())
			if resp[0] != 0:
				return JamError.err("Failure receiving HTTP response bytes from %s export upload" % [reader.filename])
			
			full_resp.append_array(resp[1] as PackedByteArray)
			var resp_string := full_resp.get_string_from_utf8()
			var m := http_resp_re.search(resp_string)
			if m != null:
				var code = int(m.get_string(1))
				var reason = m.get_string(2)
				if code < 200 or code > 299:
					return JamError.err("Received HTTP error during %s upload - %d: %s" % [reader.filename, code, reason])
				else:
					return JamError.ok()
	
	return JamError.err("HTTP response for %s upload timed out" % [reader.filename])
