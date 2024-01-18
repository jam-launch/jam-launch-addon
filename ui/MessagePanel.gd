@tool
extends MarginContainer
class_name MessagePanel

@onready var dismiss_progress = $PC/MC/HB/VB/ProgressBar
@onready var msg_txt = $PC/MC/HB/Message

var message: String:
	get:
		return $PC/MC/HB/Message.text
	set(val):
		$PC/MC/HB/Message.text = val

var _auto_dismissed: bool = false
var _auto_dismiss_delay: float = 10.0
var elapsed: float = 0.0

func _ready():
	$PC/MC/HB/VB/ProgressBar.visible = false

func _process(delta):
	if not _auto_dismissed:
		return
	
	elapsed += delta
	dismiss_progress.value = int(elapsed * 100.0 / _auto_dismiss_delay)

func set_auto_dismiss(delay: float):
	_auto_dismissed = true
	_auto_dismiss_delay = delay
	dismiss_progress.visible = true
	$DismissTimer.stop()
	$DismissTimer.start(_auto_dismiss_delay)
	dismiss_progress.value = 0

func _on_dismiss_timer_timeout():
	dismiss()

func _on_dismiss_pressed():
	dismiss()

func dismiss():
	queue_free()

func set_error_text(text: String):
	msg_txt.text = "[color=#f99]%s[/color]" % text
