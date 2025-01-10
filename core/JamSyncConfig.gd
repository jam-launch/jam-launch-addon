@tool
extends Resource
class_name JamSyncConfig

@export var sync_properties: Array[JamSyncProperty] = []

func add_property(cfg: JamSyncProperty) -> Variant:
	for p in sync_properties:
		if p.path == cfg.path:
			return "property path already configured"
	sync_properties.append(cfg)
	emit_changed()
	return null

func remove_property(property_path: String) -> bool:
	for idx in range(len(sync_properties)):
		if sync_properties[idx].path == property_path:
			sync_properties.remove_at(idx)
			emit_changed()
			return true
	return false

func set_property_interval_mult(property_path: String, interval_mult: int) -> bool:
	for p in sync_properties:
		if p.path == property_path:
			p.interval_mult = interval_mult
			emit_changed()
			return true
	return false

func set_property_sync_mode(property_path: String, sync_mode: JamSync.SyncMode) -> bool:
	for p in sync_properties:
		if p.path == property_path:
			p.sync_mode = sync_mode
			emit_changed()
			return true
	return false
