class_name KeyLabel
extends RefCounted
## Names of the inputs bound to an action, for hints and menus (Bible 19: show the bindings, not
## hardcoded text). Keys are bound by physical position; in a window the name follows the
## player's keyboard layout (on AZERTY the "W" position shows as "Z").
##
## Never uses InputEvent.as_text(), which says "W - Physical". The headless display server cannot
## look up layout labels (it logs an engine error), so headless runs name the physical key.


## The first key bound to `action`, or "" when it has no key.
static func for_action(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return key_name(event)
	return ""


## Every key and mouse button bound to `action`, in binding order.
static func all_for_action(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append(key_name(event))
		elif event is InputEventMouseButton:
			out.append(mouse_button_name(event.button_index))
	return out


static func key_name(event: InputEventKey) -> String:
	if event.physical_keycode == KEY_NONE:
		return OS.get_keycode_string(event.keycode)
	if DisplayServer.get_name() == "headless":
		return event.as_text_physical_keycode()
	return OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(event.physical_keycode))


static func mouse_button_name(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "Left mouse"
		MOUSE_BUTTON_RIGHT:
			return "Right mouse"
		MOUSE_BUTTON_MIDDLE:
			return "Middle mouse"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel down"
	return "Mouse button %d" % button
