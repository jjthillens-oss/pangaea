extends Node
## Debug builds only (M1 step 2): F3 shows or hides the debug panel; F5 fills energy, F6 drains
## it, F7 empties the nearest plankton zone and F8 drops carrion 4 m ahead. Each command goes
## through the debug panel's run(), so keys and buttons do the same thing. Main loads it by path.

const COMMANDS := {
	&"dev_fill": "fill",
	&"dev_drain": "drain",
	&"dev_empty_zone": "empty_zone",
	&"dev_spawn_carrion": "spawn_carrion",
}

var main: Node


func attach(p_main: Node) -> void:
	main = p_main


func _unhandled_input(event: InputEvent) -> void:
	if main == null or main.debug_panel == null:
		return
	if event.is_action_pressed(&"toggle_debug"):
		get_viewport().set_input_as_handled()
		main.debug_panel.toggle()
		return
	for action: StringName in COMMANDS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			main.debug_panel.run(COMMANDS[action])
			return
