@tool
extends MarginContainer
class_name MessagePanel

@onready var dismiss_progress: ProgressBar = $MC/HB/VB/ProgressBar
@onready var msg_txt: RichTextLabel = $MC/HB/Message
@onready var show_all: Button = $MC/HB/ShowAll
@onready var full_message: RichTextLabel = $Full/M/FullMessage
@onready var full_popup: Popup = $Full

var message: String:
	set(val):
		full_message.text = val
		var preview: String = val
		if len(val) > 130:
			preview = val.substr(0, 127) + "..."
			show_all.visible = true
		else:
			show_all.visible = false
		msg_txt.text = preview
		message = val

var _auto_dismissed: bool = false
var _auto_dismiss_delay: float = 10.0
var elapsed: float = 0.0

func _ready() -> void:
	$MC/HB/VB/ProgressBar.visible = false

func _process(delta: float) -> void:
	if not _auto_dismissed:
		return
	
	elapsed += delta
	dismiss_progress.value = int(elapsed * 100.0 / _auto_dismiss_delay)

func set_auto_dismiss(delay: float) -> void:
	_auto_dismissed = true
	_auto_dismiss_delay = delay
	dismiss_progress.visible = true
	$DismissTimer.stop()
	$DismissTimer.start(_auto_dismiss_delay)
	dismiss_progress.value = 0

func _on_dismiss_timer_timeout() -> void:
	dismiss()

func _on_dismiss_pressed() -> void:
	dismiss()

func dismiss() -> void:
	queue_free()

func set_error_text(text: String) -> void:
	message = text
	msg_txt.text = "[color=#f99]%s[/color]" % msg_txt.text

func _on_show_all_pressed() -> void:
	$DismissTimer.stop()
	dismiss_progress.visible = false
	full_popup.popup_centered_ratio(0.7)
