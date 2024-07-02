extends MarginContainer
class_name ChatConsole

@onready var chat_log = $VB/P/ChatLog
@onready var msg_line = $VB/MsgHB/Msg

var jam_connect: JamConnect:
	set(val):
		val.log_event.connect(append_status_message)
		jam_connect = val

func append_status_message(msg: String):
	print(msg)
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
		_send_chat_msg.rpc(msg)

@rpc("any_peer", "call_local")
func _send_chat_msg(msg: String):
	msg = sanitize(msg)
	
	var peer_id := multiplayer.get_remote_sender_id()
	var username: String = "<>"
	if jam_connect.server:
		username = jam_connect.server.peer_usernames.get(peer_id, "<>")
	elif jam_connect.client:
		username = jam_connect.client.peer_usernames.get(peer_id, "<>")
	
	_print_chat_msg(username, msg)

func sanitize(msg: String) -> String:
	msg = msg.substr(0, 500)
	# prevent bbcode tags from clients
	msg = msg.replace("[", "(")
	msg = msg.replace("]", ")")
	return msg

func _print_chat_msg(username: String, msg: String):
	
	append_chat_message(username, msg)
