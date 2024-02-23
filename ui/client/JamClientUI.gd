extends Control
class_name JamClientUI

var jam_connect: JamConnect
var jam_client: JamClient
var client_api: JamClientApi
var game_id: String

func client_ui_initialization(jc: JamConnect):
	jam_connect = jc
	jam_client = jc.client
	client_api = jam_client.api
	game_id = client_api.game_id

func leave_game_session():
	pass

func show_error(msg: String, _auto_dismiss_delay: float = 0.0):
	printerr(msg)
