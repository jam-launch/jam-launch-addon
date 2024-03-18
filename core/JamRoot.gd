class_name JamRoot
extends Node

const JAM_ROOT_NAME = "JamRoot"

signal has_jam_connect(jam_connect: JamConnect)

var jam_connect: JamConnect:
	set(val):
		jam_connect = val
		has_jam_connect.emit(val)
		
var jam_replicator: JamReplicator

static func get_jam_root(tree: SceneTree) -> JamRoot:
	var r: JamRoot = tree.root.get_node_or_null(JAM_ROOT_NAME)
	if r == null:
		r = JamRoot.new()
		r.name = JAM_ROOT_NAME
		tree.root.add_child(r)
		
		r.jam_replicator = JamReplicator.new()
		r.add_child(r.jam_replicator, true)
		
	return r
