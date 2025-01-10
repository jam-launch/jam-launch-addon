@tool
extends Tree

# Some of this is copied from:
# https://github.com/ImTani/godot-property-selection-window

const EXCLUDED_PROPERTIES: Array[String] = [
	"owner", "multiplayer", "script"
]

const FILTER_PROPERTY_USAGE_MASK: int = PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_INTERNAL

const SYNC_TYPE_MAP: Dictionary = {
	TYPE_BOOL: "bool",
	TYPE_INT: "int",
	TYPE_FLOAT: "float",
	TYPE_STRING: "String",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR2I: "Vector2i",
	TYPE_VECTOR3: "Vector3",
	TYPE_VECTOR3I: "Vector3i",
	TYPE_VECTOR4: "Vector4",
	TYPE_VECTOR4I: "Vector4i",
	TYPE_QUATERNION: "Quaternion",
	TYPE_BASIS: "Basis",
	TYPE_PACKED_BYTE_ARRAY: "PackedByteArray",
	TYPE_COLOR: "Color"
}

func populate_for_target(target: Object):
	clear()
	var root = create_item()
	hide_root = true
	
	var _already_done = {}
	var classes = []
	var c = target.get_class()
	while c:
		classes.append(c)
		c = ClassDB.get_parent_class(c)
	
	for base_class in classes:
		var class_item = create_item(root)
		class_item.set_selectable(0, false)
		class_item.set_text(0, base_class)
		var f = SystemFont.new()
		f.font_names = ["Open Sans", "Sans"]
		f.font_weight = 800
		class_item.set_custom_font(0, f)
		var icon = get_editor_icon(base_class)
		if icon:
			class_item.set_icon(0, icon)
		
		for p in ClassDB.class_get_property_list(base_class, true):
			if p["usage"] & FILTER_PROPERTY_USAGE_MASK:
				continue
			if p["name"] in EXCLUDED_PROPERTIES:
				continue
			if p["type"] not in SYNC_TYPE_MAP:
				continue
			
			var item = create_item(class_item)
			item.set_text(0, p["name"])
			icon = get_editor_icon(SYNC_TYPE_MAP[p["type"]])
			if icon:
				item.set_icon(0, icon)


func get_editor_icon(name: String) -> Variant:
	if EditorInterface.get_editor_theme().has_icon(name, &"EditorIcons"):
		return EditorInterface.get_editor_theme().get_icon(name, &"EditorIcons")
	else:
		return null
