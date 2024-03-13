class_name JamWebRTCHelper
extends Node

var signalling: JamWebRTCSignalling
var rtc_mp: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()
var sealed := false

var peers: Dictionary = {}
var local_pid: int = -1

signal errored(msg: String)
signal multiplayer_initialized(pid: int, pinfo: Dictionary)
signal multiplayer_terminating()

signal peer_added(pid: int)
signal peer_removed(pid: int)

signal session_sealed()

func _init():
	signalling = JamWebRTCSignalling.new()
	add_child(signalling)
	
	signalling.connected.connect(self._connected)
	signalling.disconnected.connect(self._disconnected)

	signalling.offer_received.connect(self._offer_received)
	signalling.answer_received.connect(self._answer_received)
	signalling.candidate_received.connect(self._candidate_received)

	signalling.session_sealed.connect(self._session_sealed)
	signalling.peer_connected.connect(self._peer_connected)
	signalling.peer_disconnected.connect(self._peer_disconnected)

func start(url: String) -> JamError:
	await stop()
	sealed = false
	return await signalling.connect_to_url(url)

func stop():
	if multiplayer.has_multiplayer_peer():
		multiplayer_terminating.emit()
		multiplayer.multiplayer_peer = null
	
	peers = {}
	rtc_mp.close()
	await signalling.close()

func _add_webrtc_peer(id: int) -> Variant:
	var peer: WebRTCPeerConnection = WebRTCPeerConnection.new()
	var err = peer.initialize({
		"iceServers": [ {"urls": [
			"stun:stun1.jamlaunch.com:13478",
			"stun:stun.l.google.com:19302"
		] } ]
	})
	if err != OK:
		_err("Failed to initialize peer %d (possibly due to missing WebRTC GDExtension)" % [id], err)
		return null
	peer.session_description_created.connect(self._offer_created.bind(id))
	peer.ice_candidate_created.connect(self._new_ice_candidate.bind(id))
	err = rtc_mp.add_peer(peer, id)
	if err != OK:
		_err("Failed to add peer %d (possibly due to missing WebRTC GDExtension)" % [id], err)
		return null
	return peer

func _new_ice_candidate(mid_name: String, index_name: int, sdp_name: String, id: int):
	#print("new ice candidate: %d %s %d %s" % [id, mid_name, index_name, sdp_name])
	signalling.send_candidate(id, mid_name, index_name, sdp_name)

func _offer_created(type: String, data: String, id: int):
	if not rtc_mp.has_peer(id):
		printerr("offer created by unknown peer %d" % id)
		printerr(rtc_mp.get_peers())
		return
	rtc_mp.get_peer(id).connection.set_local_description(type, data)
	if type == "offer":
		signalling.send_offer(id, data)
	else:
		signalling.send_answer(id, data)

func _connected(pid: int, pinfo: Dictionary):
	if pid == 1:
		var err = rtc_mp.create_server()
		if err != OK:
			_err("Failed to create WebRTC server peer", err)
			await signalling.close()
			return
		peers[pid] = pinfo
	else:
		var err = rtc_mp.create_client(pid)
		if err != OK:
			_err("Failed to create WebRTC client peer", err)
			await signalling.close()
			return
		
	multiplayer.multiplayer_peer = rtc_mp
	local_pid = pid
	multiplayer_initialized.emit(pid, pinfo)

func _disconnected():
	if not sealed:
		await stop()

func _peer_connected(pid: int, pinfo: Dictionary):
	#print("Peer connected %d (in %d)" % [pid, multiplayer.get_unique_id()])
	#print(pinfo)
	if multiplayer.is_server():
		if _add_webrtc_peer(pid) != null:
			peers[pid] = pinfo
			peer_added.emit(pid)
	elif pid == 1:
		var p = _add_webrtc_peer(pid)
		if p != null:
			peers[pid] = pinfo
			peer_added.emit(pid)
			p.create_offer()
	else:
		printerr("Unexpected client-to-client peer connection message %d - %d" % [pid, multiplayer.get_unique_id()])

func _peer_disconnected(id: int):
	if rtc_mp.has_peer(id):
		rtc_mp.remove_peer(id)
		peer_removed.emit(id)
	else:
		printerr("disconnect of unknown peer %d" % id)
		printerr(rtc_mp.get_peers())
	peers.erase(id)

func _session_sealed():
	sealed = true
	session_sealed.emit()

func _offer_received(id: int, offer: String):
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)
	else:
		printerr("offer received from unknown peer %d" % id)
		printerr(rtc_mp.get_peers())

func _answer_received(id: int, answer: String):
	#print("Got answer: %d" % id)
	if rtc_mp.has_peer(id):
		rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)
	else:
		printerr("answer received from unknown peer %d" % id)
		printerr(rtc_mp.get_peers())

func _candidate_received(id: int, mid: String, index: int, sdp: String):
	if rtc_mp.has_peer(id):
		#push_warning("%s -- %d -- %s" % [mid, index, sdp])
		# TODO: figure out why this can produce spurrious error messages
		rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)
	else:
		printerr("candidate received from unknown peer %d" % id)
		printerr(rtc_mp.get_peers())

func _err(msg: String, code: Error = OK):
	if code != OK:
		msg += " - error code: %d" % code
	printerr(msg)
	errored.emit(msg)
