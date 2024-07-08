class_name JamReplicator
extends Node

const sync_interval = 1.0 / 30.0
var sync_seq = 0
var sync_clock: float = 0.0
var sync_stable: bool = false

var state_buffer: Array[StateFrame] = []
var state_interp: float = 0.0
var got_initial_state = false
var target_state_buffer_len = 4
var target_state_buffer_len_min = 4

# for dynamic client state buffer limiting
var segment_time: float = 0.0
var segment_length: float = 5.0
var drops_in_segment: int = 0
var drops_threshold: int = 3
var dropless_segments: int = 0
var dropless_threshold: int = 5
var buffer_increases: int = 0

var server_state = {}

var sync_refs = {}

class StateFrame:
	extends RefCounted
	var seq: int
	var data: Dictionary
	
	static func from(s: int, d: Dictionary) -> StateFrame:
		var f = StateFrame.new()
		f.seq = s
		f.data = d
		return f

class StateInterp:
	extends RefCounted
	var start_state: Variant
	var end_state: Variant
	var progress: float
	var valid: bool
	
	static func invalid():
		var s = StateInterp.new()
		s.valid = false
		return s
	
	static func create(sbuf: Array[StateFrame], sync_id: int, interp: float):
		if len(sbuf) < 1:
			return StateInterp.invalid()
		
		var s = StateInterp.new()
		s.valid = true
		if sync_id not in sbuf[0].data:
			return StateInterp.invalid()
		s.start_state = sbuf[0].data[sync_id]
		
		if len(sbuf) == 1:
			s.end_state = s.start_state
			s.progress = 0.0
		else:
			if sync_id not in sbuf[1].data:
				return StateInterp.invalid()
			s.end_state = sbuf[1].data[sync_id]
			s.progress = interp
			
		return s

static func get_replicator(tree: SceneTree) -> JamReplicator:
	return JamRoot.get_jam_root(tree).jam_replicator

func _ready():
	if get_parent().jam_connect:
		_jam_connect_init(get_parent().jam_connect as JamConnect)
	get_parent().has_jam_connect.connect(_jam_connect_init)

func _jam_connect_init(jc: JamConnect):
	if not jc.m.is_server():
		return
	jc.m.peer_connected.connect(_on_peer_connected)
	jc.m.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(pid: int):
	if not multiplayer.is_server():
		return
	for sync_id in sync_refs:
		scene_spawn(sync_refs[sync_id] as JamSync, pid)

func _on_peer_disconnected(_pid: int):
	if not multiplayer.is_server():
		return

func _process(delta):
	if not multiplayer.has_multiplayer_peer():
		return
	
	if multiplayer.is_server():
		sync_clock += delta
		if sync_clock > sync_interval:
			sync_seq += 1
			sync_clock -= sync_interval
			if sync_clock > sync_interval:
				if sync_stable:
					push_warning("sync interval lagging due to large _process delta - resetting sync clock")
				sync_clock = 0.0
			else:
				sync_stable = true
			
			sync_state.rpc(sync_seq, server_state)
			server_state = {}
	else:
		state_interp += delta
		
		# adjust state buffer max based on quality of network
		segment_time += delta
		if segment_time >= segment_length:
			if drops_in_segment == 0:
				dropless_segments += 1
				if dropless_segments > dropless_threshold:
					if target_state_buffer_len > target_state_buffer_len_min:
						target_state_buffer_len -= 1
						print("decreasing state buffer to %d" % target_state_buffer_len)
					dropless_segments = 0
			elif drops_in_segment > drops_threshold:
				dropless_segments = 0
				dropless_threshold += 1
				target_state_buffer_len += 1
				buffer_increases += 1
				print("increasing state buffer to %d" % target_state_buffer_len)
				if buffer_increases > 3:
					buffer_increases = 0
					target_state_buffer_len_min += 1
			
			drops_in_segment = 0
			segment_time = 0.0
		
		# remove expired states
		while state_interp > sync_interval:
			state_interp -= sync_interval
			if len(state_buffer) > 1:
				state_buffer.pop_front()
			else:
				if got_initial_state:
					push_warning("state buffer depleted")
				state_interp = 0.0
				return StateInterp.invalid()
		
		# remove over-buffered states
		var overbuffered: int = len(state_buffer) - target_state_buffer_len
		if overbuffered > 0:
			push_warning("dropping %d over-buffered states" % overbuffered)
			drops_in_segment += 1
			state_interp = sync_interval
			state_buffer = state_buffer.slice(overbuffered)
		elif len(state_buffer) == 1:
			state_interp = 0.0

func amend_server_state(sync_id: int, value: Variant):
	server_state[sync_id] = value

@rpc("authority", "call_remote", "unreliable")
func sync_state(seq: int, data: Dictionary):
	if len(state_buffer) < 1:
		got_initial_state = true
		state_interp = 0.0
		state_buffer.append(StateFrame.from(seq, data))
	elif seq > state_buffer[- 1].seq:
		data.merge(state_buffer[ - 1].data)
		state_buffer.append(StateFrame.from(seq, data))
		if seq > state_buffer[- 1].seq + 1:
			push_warning("state seq skipped %d" % (seq - state_buffer[ - 1].seq))
	elif seq < state_buffer[0].seq:
		push_warning("state drop %d" % seq)
	else:
		var idx = 1
		while idx < len(state_buffer):
			if seq == state_buffer[idx].seq:
				push_warning("state dupe %d" % seq)
				break
			elif seq < state_buffer[idx].seq:
				push_warning("state OOO %d" % seq)
				break
			idx += 1

func get_state(sync_id: int) -> StateInterp:
	return StateInterp.create(state_buffer, sync_id, state_interp / sync_interval)

var spawn_scene_cache = {}

func _instantiate_spawn_scene(scene_path: String) -> Node:
	if scene_path not in spawn_scene_cache:
		var scene = load(scene_path)
		spawn_scene_cache[scene_path] = scene
	return spawn_scene_cache[scene_path].instantiate()

func scene_spawn(sync_node: JamSync, peer_id: int=-1):
	var target = sync_node.get_parent()
	var target_node_path = "/" + target.get_path().get_concatenated_names()
	
	var sprops = {}
	for p in sync_node.spawn_properties:
		sprops[p] = target.get(p)
	
	if peer_id == -1:
		_scene_spawn.rpc(target_node_path, target.scene_file_path, sprops, sync_node.sync_id)
	else:
		_scene_spawn.rpc_id(peer_id, target_node_path, target.scene_file_path, sprops, sync_node.sync_id)

func scene_despawn(sync_node: JamSync):
	_scene_despawn.rpc(sync_node.sync_id)

@rpc("authority", "call_remote", "reliable")
func _scene_spawn(node_path: String, scene_path: String, spawn_properties: Dictionary, sync_id: int):
	if sync_id in sync_refs:
		push_warning("sync id already in refs, no need to spawn: %d - %s" % [sync_id, node_path])
		return
	var parent_path := node_path.rsplit("/", true, 1)[0]
	var parent_node = get_node_or_null(parent_path)
	if parent_node == null:
		push_warning("received scene spawn sync for '%s' on missing parent node '%s'" % [scene_path, parent_path])
		return
	var spawned_node := _instantiate_spawn_scene(scene_path)
	for k in spawn_properties:
		spawned_node.set(k as String, spawn_properties[k])
	spawned_node.name = node_path.rsplit("/", true, 1)[1]
	for child in spawned_node.get_children():
		if is_instance_of(child, JamSync):
			child.sync_id = sync_id
			break
	parent_node.add_child(spawned_node)

@rpc("authority", "call_local", "reliable")
func _scene_despawn(sync_id: int):
	if sync_id in sync_refs:
		sync_refs[sync_id].get_parent().queue_free()
		clear_sync_ref(sync_id)

func clear_sync_ref(sync_id: int):
	sync_refs.erase(sync_id)
