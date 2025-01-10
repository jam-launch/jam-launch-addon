@tool
class_name JamSync
extends Node

enum SyncMode {
	SIMPLE = 0,
	SPAWN_ONLY = 1,
	INTERPOLATE = 2,
	INTERPOLATE_ANGLE = 3
}

var jam_root: JamRoot
var replicator: JamReplicator
var sync_id: int

@export_range(1, 600, 1) var max_frames_per_sync: int = 3:
	set(val):
		max_frames_per_sync = val
		if replicator:
			replicator.request_max_frames_per_sync(max_frames_per_sync)

@export_storage var sync_config: JamSyncConfig = JamSyncConfig.new()
var sync_props: Array[JamSyncProperty]:
	get:
		return sync_config.sync_properties

class JamSyncPropertyCache:
	extends JamSyncProperty
	
	var prev_value: Variant = null
	var last_value: Variant = null
	var last_seq: int = 0
	
	static func from_property(p: JamSyncProperty) -> JamSyncPropertyCache:
		var c = JamSyncPropertyCache.new()
		c.path = p.path
		c.interval_mult = p.interval_mult
		c.sync_mode = p.sync_mode
		return c

var sync_prop_map = {}

func _ready():
	jam_root = JamRoot.get_jam_root(get_tree())
	replicator = JamReplicator.get_replicator(get_tree())
	replicator.request_max_frames_per_sync(max_frames_per_sync)
	
	get_parent().ready.connect(_target_ready)

func _target_ready():
	if not multiplayer.has_multiplayer_peer() or not jam_root.jam_connect:
		return
	
	if multiplayer.is_server():
		sync_id = get_instance_id()
		replicator.sync_refs[sync_id] = self
		replicator.scene_spawn(self)
		replicator.server_sync_step.connect(_push_server_state)
	else:
		for prop in sync_props:
			sync_prop_map[prop.path] = JamSyncPropertyCache.from_property(prop)
		replicator.sync_refs[sync_id] = self
		replicator.client_sync_step.connect(_pull_client_state)

func _exit_tree():
	if multiplayer.is_server():
		replicator.scene_despawn(self)
	else:
		replicator.clear_sync_ref(sync_id)

@warning_ignore("integer_division")
func _push_server_state():
	var target := get_parent()
	var server_state = {}
	var local_sync_interval = max_frames_per_sync / replicator.min_frames_per_sync
	if replicator.sync_seq % local_sync_interval != 0:
		return
	for p in sync_props:
		if p.sync_mode == SyncMode.SPAWN_ONLY:
			continue
		if replicator.sync_seq % p.interval_mult != 0:
			continue
		server_state[p.path] = p.get_from(target)
	replicator.amend_server_state(sync_id, server_state)

func _pull_client_state(is_sequence_step: bool):
	var frame = replicator.get_state(sync_id)
	if frame == null:
		return
	for property in sync_prop_map.values():
		if property.sync_mode in [SyncMode.INTERPOLATE, SyncMode.INTERPOLATE_ANGLE]:
			apply_interpolation(frame as Dictionary, property as JamSyncPropertyCache, is_sequence_step)
		elif not is_sequence_step:
			continue
		elif property.path in frame:
			property.apply_to(get_parent(), frame[property.path])

const LERP_TYPES = [TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, TYPE_BASIS]

@warning_ignore("integer_division")
func apply_interpolation(frame: Dictionary, property: JamSyncPropertyCache, is_sequence_step: bool):
	var local_sync_interval = max_frames_per_sync / replicator.min_frames_per_sync
	var property_sync_interval = local_sync_interval * property.interval_mult
	
	var start_value: Variant
	var end_value: Variant
	var progress: float = replicator.state_interp / replicator.sync_interval
	if property_sync_interval == 1: # can interpolate with replicator step buffer
		if property.path not in frame:
			return
		
		var next_frame = replicator.get_state(sync_id, 1)
		if next_frame == null or property.path not in next_frame:
			property.apply_to(get_parent(), frame[property.path])
			return
		
		start_value = frame[property.path]
		end_value = next_frame[property.path]
	else: # interval too big - must delay and maintain its own step buffer
		if property.path in frame and is_sequence_step:
			if property.last_value == null:
				property.last_value = property.get_from(get_parent())
			property.prev_value = property.last_value
			property.last_value = frame[property.path]
			
			start_value = property.prev_value
			end_value = property.last_value
			
			property.last_seq = replicator.sync_seq
		else:
			if property.last_value == null or property.prev_value == null:
				return
			start_value = property.prev_value
			end_value = property.last_value
			progress += replicator.sync_seq - property.last_seq
		
		progress /= property_sync_interval
	
	var val = start_value
	if property.sync_mode == SyncMode.INTERPOLATE and typeof(val) in LERP_TYPES and typeof(end_value) in LERP_TYPES:
		val = lerp(val, end_value, progress)
	elif property.sync_mode == SyncMode.INTERPOLATE_ANGLE:
		if val is float and end_value is float:
			val = lerp_angle(val as float, end_value as float, progress)
	property.apply_to(get_parent(), val)
