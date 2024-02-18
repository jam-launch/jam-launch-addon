@tool
extends TabContainer
class_name JamPageStack

var stack: Array[int] = []

signal go_back_enabled(enabled: bool)

func _ready():
	tabs_visible = false

func go_back():
	if len(stack) < 2:
		return
	stack.pop_back()
	current_tab = stack[-1]
	if len(stack) < 2:
		go_back_enabled.emit(false)

func show_page_node(page_node: Node, push_to_stack: bool = true) -> bool:
	for idx in range(get_tab_count()):
		if get_tab_control(idx) == page_node:
			show_page(idx, push_to_stack)
			return true
	printerr("Failed to show page node ", page_node)
	return false

func show_page(idx: int, push_to_stack: bool = true):
	current_tab = idx
	if push_to_stack:
		stack.push_back(idx)
		go_back_enabled.emit(true)
	else:
		stack = [ current_tab ]
		go_back_enabled.emit(false)
