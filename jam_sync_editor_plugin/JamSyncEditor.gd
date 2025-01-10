@tool
extends Control

var jam_sync: Variant = null:
	set(val):
		if jam_sync:
			jam_sync.sync_config.changed.disconnect(refresh)
		jam_sync = val
		if jam_sync:
			jam_sync.sync_config.changed.connect(refresh)
		refresh()

func _ready():
	%AddProp.icon = EditorInterface.get_base_control().get_theme_icon("Add", "EditorIcons")
	%AddPropPath.icon = EditorInterface.get_base_control().get_theme_icon("Add", "EditorIcons")

func refresh():
	var to_remove = []
	for idx in range(%SyncProps.get_child_count()):
		if idx >= %SyncProps.columns:
			to_remove.append(%SyncProps.get_child(idx))
	for node in to_remove:
		node.queue_free()
	
	if jam_sync == null:
		return
	
	var cfg: JamSyncConfig = jam_sync.sync_config
	for p in cfg.sync_properties:
		var property = Label.new()
		property.text = p.path
		%SyncProps.add_child(property)
		
		var interval = SpinBox.new()
		interval.min_value = 1
		interval.max_value = 6000
		interval.prefix = "x"
		interval.value = p.interval_mult
		interval.value_changed.connect(func(v: float): cfg.set_property_interval_mult(p.path, v))
		%SyncProps.add_child(interval)
		
		var mode = OptionButton.new()
		mode.add_item("Simple", JamSync.SyncMode.SIMPLE)
		mode.add_item("Spawn Only", JamSync.SyncMode.SPAWN_ONLY)
		mode.add_item("Interpolate", JamSync.SyncMode.INTERPOLATE)
		mode.add_item("Interpolate Angle", JamSync.SyncMode.INTERPOLATE_ANGLE)
		mode.select(mode.get_item_index(p.sync_mode))
		mode.item_selected.connect(func(idx: int): cfg.set_property_sync_mode(p.path, mode.get_item_id(idx)))
		%SyncProps.add_child(mode)
		
		var del = Button.new()
		del.icon = EditorInterface.get_base_control().get_theme_icon("Remove", "EditorIcons")
		del.pressed.connect(func(): cfg.remove_property(p.path))
		%SyncProps.add_child(del)

func _add_prop(prop_path: String) -> bool:
	var res = JamSyncProperty.create(prop_path)
	if res.errored:
		printerr("failed to add property - %s" % res.error_msg)
		return false
	jam_sync.sync_props.append(res.value as JamSyncProperty)
	refresh()
	return true

func _on_add_prop_path_pressed() -> void:
	if _add_prop(%PropPath.text):
		%PropPath.clear()

func _on_prop_path_text_submitted(_new_text: String) -> void:
	_on_add_prop_path_pressed()

var curr_node_path := ""
func _on_add_prop_pressed() -> void:
	%NodeTree.clear()
	curr_node_path = ""
	var root_item = %NodeTree.create_item()
	_populate_tree(root_item, jam_sync.get_parent())
	%NodeSelectPopup.popup_centered()

func _populate_tree(parent_item: TreeItem, node: Node):
	var tree_item: TreeItem = %NodeTree.create_item(parent_item)
	tree_item.set_text(0, node.name)
	if EditorInterface.get_editor_theme().has_icon(node.get_class(), &"EditorIcons"):
		tree_item.set_icon(0, EditorInterface.get_base_control().get_theme_icon(node.get_class(), &"EditorIcons"))
	else:
		tree_item.set_icon(0, EditorInterface.get_base_control().get_theme_icon(node.get_class().get_basename(), &"EditorIcons"))
	tree_item.set_metadata(0, node)
	for child in node.get_children():
			_populate_tree(tree_item, child)

func _on_node_tree_item_selected() -> void:
	%SelectNode.disabled = false

func _on_node_tree_nothing_selected() -> void:
	%SelectNode.disabled = true

func _on_node_tree_item_activated() -> void:
	_on_select_node_pressed()

func _on_select_node_pressed() -> void:
	var item: TreeItem = %NodeTree.get_selected()
	if item == null:
		return
	
	%NodeSelectPopup.hide()
	
	var selected_node: Node = item.get_metadata(0)
	var node_path = jam_sync.get_parent().get_path_to(selected_node)
	curr_node_path = node_path
	if curr_node_path == ".":
		curr_node_path = ""

	%PropList.populate_for_target(selected_node)

	%PropertySelectPopup.popup_centered()

func _on_prop_list_item_selected() -> void:
	%SelectProp.disabled = %PropList.get_selected() == null

func _on_prop_list_nothing_selected() -> void:
	%SelectProp.disabled = true

func _on_select_prop_pressed() -> void:
	_on_prop_list_item_activated()

func _on_prop_list_item_activated() -> void:
	var prop_item: TreeItem = %PropList.get_selected()
	if prop_item == null:
		return
	
	var prop = prop_item.get_text(0)
	var np = NodePath("%s:%s" % [curr_node_path, prop])
	_add_prop("%s" % np)
	
	%PropertySelectPopup.hide()
