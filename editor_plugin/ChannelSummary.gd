@tool
extends MarginContainer

@onready var title: RichTextLabel = $M/VB/Title

@onready var link_nav: Button = $M/VB/Config/MC/VB/HB/PageLink
@onready var link_copy: Button = $M/VB/Config/MC/VB/HB/Copy

@onready var access_icon: TextureRect = $M/VB/Config/MC/VB/Access/AccessIcon
@onready var check_public: CheckButton = $M/VB/Config/MC/VB/Access/CheckPublic
@onready var check_guests: CheckButton = $M/VB/Config/MC/VB/CheckGuests
@onready var check_default: CheckButton = $M/VB/Config/MC/VB/CheckDefault

signal update_channel(channel: String, data: Dictionary)

var c: Dictionary = {}


func _load_lock_changed(locked: bool):
	check_public.disabled = locked
	check_guests.disabled = locked
	check_default.disabled = locked

func set_channel(channel_data: Dictionary, release_name: String = ""):
	c = channel_data
	
	if len(release_name) < 1:
		release_name = "No Release"
	title.clear()
	title.push_font_size(18)
	title.push_bold()
	title.add_text(channel_data.get("name"))
	title.pop_all()
	title.push_context()
	title.push_color(Color(1, 1, 1, 0.4))
	title.add_text("\n%s" % [release_name])
	title.pop_context()
	
	if channel_data.get("public_release", false):
		check_public.text = "Public"
		access_icon.texture = preload("res://addons/jam_launch/assets/icons/public.svg")
		access_icon.modulate = Color(0.7, 1.0, 0.8)
	else:
		check_public.text = "Private"
		access_icon.texture = preload("res://addons/jam_launch/assets/icons/lock.svg")
		access_icon.modulate = Color("white")
	
	check_default.set_pressed_no_signal(channel_data.get("default_release", false))
	check_public.set_pressed_no_signal(channel_data.get("public_release", false))
	check_guests.set_pressed_no_signal(channel_data.get("allow_guests", false))

func _on_config_change(_toggled_on: bool):
	if not c.get("name"):
		return
	
	update_channel.emit(c.get("name"), {
		"default_release": check_default.button_pressed,
		"public_release": check_public.button_pressed,
		"allow_guests": check_guests.button_pressed,
	})
