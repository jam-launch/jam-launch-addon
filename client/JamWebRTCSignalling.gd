class_name JamWebRTCSignalling
extends Node

signal session_joined()
signal connected(id: int, pinfo: Dictionary)
signal disconnected()
signal peer_connected(id: int, pinfo: Dictionary)
signal peer_disconnected(id: int)
signal offer_received(id: int, offer: String)
signal answer_received(id: int, answer: String)
signal candidate_received(id: int, mid: String, index: int, sdp: String)
signal session_sealed()
signal ws_connecting()
signal ws_opened()
signal ws_closing()
signal ws_closed()
signal ws_opened_or_closed(state: WebSocketPeer.State)

enum Message {
	JOIN,
	ID,
	PEER_CONNECT,
	PEER_DISCONNECT,
	OFFER,
	ANSWER,
	CANDIDATE,
	SEAL,
	PING
}

var ws: WebSocketPeer = WebSocketPeer.new()
var code: int = 1000
var reason: String = "Unknown"
var state: int = WebSocketPeer.STATE_CLOSED

func _process(_delta: float) -> void:
	_update_ws_state()
	while state == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count():
		var err: JamError = _parse_msg()
		if err.errored:
			print("Error parsing message from server: %s" % err.error_msg)


func connect_to_url(url: String) -> JamError:
	await close()
	var err: Error = ws.connect_to_url(url)
	if not err == OK:
		return JamError.err("Failed to connect WebSocket to provided URL. Error code: %d" % err)
	
	await ws_opened_or_closed
	if state == WebSocketPeer.STATE_OPEN:
		return JamError.ok()
	else:
		return JamError.err("WebSocket not in opened state at end of connection request (%d)" % state)


func close() -> void:
	if state < WebSocketPeer.STATE_CLOSING:
		ws.close()
		code = 1000
		reason = "Unknown"
	if not state == WebSocketPeer.STATE_CLOSED:
		await ws_closed


func _update_ws_state() -> void:
	ws.poll()
	var new_state: int = ws.get_ready_state()
	if new_state == state:
		return
	
	var x: int = (state + 1) % 4
	state = new_state
	while true:
		if x == WebSocketPeer.STATE_CONNECTING:
			ws_connecting.emit()
		elif x == WebSocketPeer.STATE_OPEN:
			_on_ws_opened()
		elif x == WebSocketPeer.STATE_CLOSING:
			ws_closing.emit()
		elif x == WebSocketPeer.STATE_CLOSED:
			_on_ws_closed()
		if x == new_state:
			break
		x = (x + 1) % 4


func _on_ws_opened() -> void:
	print("joining session via websocket...")
	join_session()
	ws_opened.emit()
	ws_opened_or_closed.emit(WebSocketPeer.STATE_OPEN)


func _on_ws_closed() -> void:
	code = ws.get_close_code()
	reason = ws.get_close_reason()
	print("websocket closed... %d - %s" % [code, reason])
	disconnected.emit()
	ws_closed.emit()
	ws_opened_or_closed.emit(WebSocketPeer.STATE_CLOSED)


func _parse_msg() -> JamError:
	var parsed: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
	if not typeof(parsed) == TYPE_DICTIONARY \
			or not parsed.has("type") \
			or not parsed.has("id") \
			or not typeof(parsed.get("data")) == TYPE_STRING:
		return JamError.err("Message format incorrect: %s" % parsed as String)

	var msg: Dictionary = parsed as Dictionary
	if not str(msg.type).is_valid_int() or not str(msg.id).is_valid_int():
		return JamError.err("Message type and id are not both integers: %s" % msg)

	var type: int = str(msg.type).to_int()
	var src_id: int = str(msg.id).to_int()

	if type == Message.ID:
		var pinfo: Dictionary = JSON.parse_string(msg.data as String)
		if not typeof(pinfo) == TYPE_DICTIONARY:
			return JamError.err("ID message data is not a parseable JSON dictionary: %s" % msg.data as String)
		connected.emit(src_id, pinfo)
	elif type == Message.JOIN:
		session_joined.emit()
	elif type == Message.SEAL:
		session_sealed.emit()
	elif type == Message.PEER_CONNECT:
		var pinfo: Dictionary = JSON.parse_string(msg.data as String)
		if not typeof(pinfo) == TYPE_DICTIONARY:
			return JamError.err("PEER_CONNECT message data is not a parseable JSON dictionary: %s" % msg.data as String)
		peer_connected.emit(src_id, pinfo)
	elif type == Message.PEER_DISCONNECT:
		peer_disconnected.emit(src_id)
	elif type == Message.OFFER:
		offer_received.emit(src_id, msg.data)
	elif type == Message.ANSWER:
		answer_received.emit(src_id, msg.data)
	elif type == Message.CANDIDATE:
		var candidate: PackedStringArray = msg.data.split("\n", false)
		if not candidate.size() == 3:
			return JamError.err("CANDIDATE data is not exactly 3 lines: %s" % msg.data as String)
		if not candidate[1].is_valid_int():
			return JamError.err("CANDIDATE index is not a valid integer: %s" % msg.data as String)
		candidate_received.emit(src_id, candidate[0], candidate[1].to_int(), candidate[2])
	elif type == Message.PING:
		print("got ping from signalling system")
	else:
		return JamError.err("Message has unrecognized type '%d'" % type)
		
	return JamError.ok()


func join_session() -> int:
	return _send_msg(Message.JOIN, 0, "")


func seal_lobby() -> int:
	return _send_msg(Message.SEAL, 0)


func send_candidate(id: int, mid: String, index: int, sdp: String) -> int:
	return _send_msg(Message.CANDIDATE, id, "\n%s\n%d\n%s" % [mid, index, sdp])


func send_offer(id: int, offer: String) -> int:
	return _send_msg(Message.OFFER, id, offer)


func send_answer(id: int, answer: String) -> int:
	return _send_msg(Message.ANSWER, id, answer)


func _send_msg(type: int, id: int, data: Variant="") -> int:
	return ws.send_text(JSON.stringify({
		"type": type,
		"id": id,
		"data": data
	}))
