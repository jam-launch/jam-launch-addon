extends Control

var load_dots = 1
var max_load_dots = 6
var dot_rate = 0.2
var _elapsed = 0.0

func set_operation_text(text: String):
	$Operation.text = text
	
func _process(delta):
	if not self.visible:
		return
	
	_elapsed += delta
	if _elapsed > dot_rate:
		while _elapsed > dot_rate:
			load_dots = (load_dots + 1) % (max_load_dots + 1)
			_elapsed -= dot_rate
		
		var dots = ""
		for i in range(load_dots):
			dots += "."
		$Loading.text = dots + "Loading" + dots
