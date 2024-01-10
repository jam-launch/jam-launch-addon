extends Node
class_name JamServer

const MAX_CLIENTS = 100
const DEFAULT_PORT = 7437

# APIs for saving and loading game data
var db: JamDB
var files: JamFiles

# Reusable clients for AWS services (only available when deployed)
var ddb
var s3

var pending_peers = []
var accepted_peers = {}
var dev_mode = false

var jc: JamConnect:
	get:
		return get_parent()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		printerr("server got quit notification")
		shut_down()

func server_start(args: Dictionary):
	print("Starting as server...")
	
	var listen_port: int = DEFAULT_PORT
	if "port" in args:
		listen_port = (args["port"] as String).to_int()
	
	dev_mode = "dev" in args and args["dev"]
	
	var peer
	var err
	if OS.has_feature("websocket"):
		peer = WebSocketMultiplayerPeer.new()
		var cert_base = "certs"
		var key_path = cert_base.path_join("private.key")
		var crt_path = cert_base.path_join("certificate.crt")
		printerr("cert base files: ", DirAccess.get_files_at(cert_base))
		var key = CryptoKey.new()
		err = key.load(key_path)
		if err != OK:
			push_error("FATAL: Failed to load server key at %s" % key_path)
			get_tree().quit(1)
			return
		var cert = X509Certificate.new()
		err = cert.load(crt_path)
		if err != OK:
			push_error("FATAL: Failed to load server cert at %s" % crt_path)
			get_tree().quit(1)
			return
		err = peer.create_server(listen_port, "*", TLSOptions.server(key, cert))
	else:
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(listen_port, MAX_CLIENTS)
	if err != OK:
		push_error("FATAL: Failed to start server on port %d - err code %d" % [listen_port, err])
		get_tree().quit(1)
		return
	
	multiplayer.multiplayer_peer = peer
	peer.peer_connected.connect(
		func(new_peer_id):
			print("pending peer %d..." % new_peer_id)
			pending_peers.append(new_peer_id)
	)
	
	peer.peer_disconnected.connect(_on_peer_disconnect)
	
	print("Server listening on port %d" % listen_port)
	
	if dev_mode:
		# TODO: mock/local DB and file API using files in user://... ?
		db = JamDB.new(jc)
		files = JamFiles.new(jc)
		jc.server_pre_ready.emit()
		jc.server_post_ready.emit()
	else:
		if not ClassDB.can_instantiate("DynamoDbClient"):
			printerr("FATAL: Cannot instantiate DynamoDbClient. Is the Jam Launch extension missing?")
			get_tree().quit()
			
		if not ClassDB.can_instantiate("S3Client"):
			printerr("FATAL: Cannot instantiate S3Client. Is the Jam Launch extension missing?")
			get_tree().quit()
			
		ddb = ClassDB.instantiate("DynamoDbClient")
		@warning_ignore("unsafe_call_argument")
		db = JamDBDynamo.new(jc, ddb)
		s3 = ClassDB.instantiate("S3Client")
		@warning_ignore("unsafe_call_argument")
		files = JamFilesS3.new(jc, s3)
		
		jc.server_pre_ready.emit()
		var res = db.put_session_data("status", {
			"status": "READY"
		})
		if not res:
			printerr("FATAL: Failed to set READY status in database - aborting...")
			get_tree().quit()
		jc.server_post_ready.emit()

func verify_player(join_token: String):	
	var pid: int = multiplayer.get_remote_sender_id()
	if pid not in pending_peers:
		print("Ignoring verification request from non-pending peer %d" % pid)
		return
	
	var pinfo
	if dev_mode:
		if join_token != "localdev":
			push_error("failed verification request from localdev peer %d" % pid)
			return
		pinfo = {"name": "dev-%d" % pid}
	
	else:
		print("Verifying join token from %d" % pid)
		pinfo = db.get_session_data("JGT-"+join_token)
		if pinfo == null or "name" not in pinfo:
			print("Failed verification of join token (%s), booting %d..." % [join_token, pid])
			multiplayer.multiplayer_peer.disconnect_peer(pid, true)
			pending_peers.erase(pid)
			return
		
		for already_here in accepted_peers.values():
			if already_here["name"] == pinfo["name"]:
				print("Player '%s' is already joined, booting duplicate pid %d..." % [pinfo["name"], pid])
				multiplayer.multiplayer_peer.disconnect_peer(pid, true)
				pending_peers.erase(pid)
				return
		
		pinfo.erase("key_1")
		pinfo.erase("key_2")
		
	pending_peers.erase(pid)
	accepted_peers[pid] = pinfo
	
	print("Accepted player %d as %s!" % [pid, pinfo["name"]])
	jc.notify_players.rpc("'%s' has joined" % pinfo["name"])
	jc.player_verified.emit(pid, pinfo)

func rpc_relay(rpc_call: Callable, origin_pid: int, args: Array):
	var pinfo = accepted_peers.get(origin_pid)
	if pinfo == null:
		print("Ignoring relay call from non-accepted peer %d" % origin_pid)
		return
	var call_args := [origin_pid, pinfo.get("name", "<>")]
	call_args.append_array(args)
	var bound_rpc_call = rpc_call.bindv(call_args)
	for pid in accepted_peers:
		bound_rpc_call.rpc_id(pid as int)

func _on_peer_disconnect(pid: int):
	if pid in accepted_peers:
		var pinfo = accepted_peers[pid]
		accepted_peers.erase(pid)
		jc.notify_players.rpc("Player '%s' has disconnected" % pinfo.get("name", "<>"))
		jc.player_disconnected.emit(pid, pinfo)
	pending_peers.erase(pid)
	
	if pending_peers.is_empty() and accepted_peers.is_empty():
		print("All peers disconnected - shutting down...")
		shut_down(false)

func shut_down(do_disconnect: bool = true):
	if do_disconnect:
		var all_pids = pending_peers + accepted_peers.keys()
		for pid in all_pids:
			multiplayer.multiplayer_peer.disconnect_peer(pid as int, true)
	jc.server_shutting_down.emit()
	get_tree().quit()
