@tool
extends CenterContainer

@export var speed: float = 1.0
@export var padding_ratio: float = 0.1:
	set(p):
		padding_ratio = p
		_on_resized()

@onready var circle: Sprite2D = $C/Circle

func _ready() -> void:
	_on_resized()

func _process(delta: float) -> void:
	var amount: float = delta * speed * 2.0 * PI
	circle.rotate(amount)

func _on_resized() -> void:
	if not circle:
		return
	var bounds: float = min(size.x, size.y)
	bounds -= bounds * padding_ratio
	
	if bounds > 48:
		circle.texture = preload("res://addons/jam_launch/assets/icons/progress_96x96.svg")
	elif bounds > 24:
		circle.texture = preload("res://addons/jam_launch/assets/icons/progress_48x48.svg")
	elif bounds > 16:
		circle.texture = preload("res://addons/jam_launch/assets/icons/progress_24x24.svg")
	else:
		circle.texture = preload("res://addons/jam_launch/assets/icons/progress_16x16.svg")
	
	var circle_bounds: int = circle.texture.get_height()
	if bounds > circle_bounds:
		circle.scale = Vector2(1.0, 1.0)
	else:
		var ratio: float = bounds / circle_bounds
		circle.scale = Vector2(ratio, ratio)
