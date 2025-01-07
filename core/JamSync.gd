class_name JamSync
extends Node

var jam_root: JamRoot
var replicator: JamReplicator
var sync_id: int

@export var spawn_properties: Array[String] = []
@export var sync_properties: Array[String] = []

func _ready():
	jam_root = JamRoot.get_jam_root(get_tree())
	replicator = JamReplicator.get_replicator(get_tree())
	
	get_parent().ready.connect(_target_ready)

func _target_ready():
	if not multiplayer.has_multiplayer_peer() or not jam_root.jam_connect:
		return
	
	if multiplayer.is_server():
		sync_id = get_instance_id()
		replicator.sync_refs[sync_id] = self
		replicator.scene_spawn(self)
		replicator.sync_step_start.connect(_push_server_state)
	else:
		replicator.sync_refs[sync_id] = self
		replicator.sync_step_end.connect(_pull_client_state)

func _exit_tree():
	if multiplayer.is_server():
		replicator.scene_despawn(self)
	else:
		replicator.clear_sync_ref(sync_id)

func _push_server_state(_delta: float):
	var target = get_parent()
	var server_state = {}
	for p in sync_properties:
		server_state[p] = target.get(p)
	replicator.amend_server_state(sync_id, server_state)

const LERP_TYPES = [TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, TYPE_BASIS]

func _pull_client_state(_delta: float):
	var target = get_parent()
	var s = replicator.get_state(sync_id)
	if not s.valid:
		return
	for p in s.start_state:
		var val: Variant = s.start_state[p]
		if typeof(val) in LERP_TYPES:
			val = lerp(val, s.end_state[p], s.progress)
		target.set(p as String, val)
