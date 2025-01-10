@tool
extends Resource
class_name JamSyncProperty

@export var path: String = ""
@export var interval_mult: int = 1
@export var sync_mode: JamSync.SyncMode = JamSync.SyncMode.SIMPLE:
	set(val):
		if val == JamSync.SyncMode.SPAWN_ONLY:
			interval_mult = 1
		sync_mode = val

static func create(property_path: String) -> JamResult:
	var node_path = NodePath(property_path)
	if node_path.is_empty():
		return JamResult.err("invalid NodePath")
	if len(node_path.get_concatenated_subnames()) < 1:
		return JamResult.err("empty property")
	
	var cfg = JamSyncProperty.new()
	cfg.path = property_path
	return JamResult.ok(cfg)

func get_from(node: Node) -> Variant:
	var np := NodePath(path)
	if np.get_concatenated_names().is_empty():
		return node.get_indexed(np)
	else:
		var base: Node = node.get_node_or_null(NodePath(np.get_concatenated_names()))
		if not base:
			return null
		return base.get_indexed(NodePath(np.get_concatenated_subnames()))

func apply_to(node: Node, value: Variant):
	var np := NodePath(path)
	if np.get_concatenated_names().is_empty():
		node.set_indexed(np, value)
	else:
		var base: Node = node.get_node_or_null(NodePath(np.get_concatenated_names()))
		if not base:
			return
		base.set_indexed(NodePath(np.get_concatenated_subnames()), value)
