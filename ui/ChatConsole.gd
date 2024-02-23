extends MarginContainer
class_name ChatConsole

@onready var chat_log = $VB/P/ChatLog
@onready var msg_line = $VB/MsgHB/Msg

var jam_connect: JamConnect:
	set(val):
		val.log_event.connect(append_status_message)
		jam_connect = val

func append_status_message(msg: String):
	chat_log.text += "[color=#aaa][i]" + msg + "[/i][/color]\n"
	
func append_chat_message(sender: String, msg: String):
	chat_log.text += "[color=#bbb][b]%s:[/b][/color] %s\n" % [sender, msg]

func is_chat_focused():
	return msg_line.has_focus()

func give_chat_focus():
	msg_line.grab_focus()

func _on_text_submit():
	var msg := sanitize(msg_line.text as String)
	msg_line.clear()
	msg_line.release_focus()
	if len(msg) > 0:
		_send_chat_msg.rpc_id(1, msg)

@rpc("any_peer")
func _send_chat_msg(msg: String):
	msg = sanitize(msg)
	jam_connect.server_relay(_print_chat_msg, [msg])

func sanitize(msg: String) -> String:
	msg = msg.substr(0, 500)
	# prevent bbcode tags from clients
	msg = msg.replace("[", "(")
	msg = msg.replace("]", ")")
	return msg

@rpc
func _print_chat_msg(_sender_pid: int, sender_name: String, msg: String):
	append_chat_message(sender_name, msg)
