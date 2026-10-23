class_name InputPrompts
extends RefCounted
## Which device the player used last (keyboard and mouse, or a controller) and the names of the
## inputs bound to an action for that device (UI pass). Hints and menus show the controller's
## buttons while a controller is in use and the keys otherwise, read from the bindings (Bible 19).
## Main reports every input event with note(); `device` is static so any hint can read it.

## "keys" or "pad".
static var device := "keys"
## Goes up by one each time the device changes, so a hint can tell it must redraw.
static var generation := 0


## Updates `device` from an event: a button or a stick pushed past half way means "pad"; a key, a
## click or a real mouse move means "keys".
static func note(event: InputEvent) -> void:
	var seen := ""
	if event is InputEventJoypadButton:
		seen = "pad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		seen = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		seen = "keys"
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 4.0:
		seen = "keys"
	if not seen.is_empty() and seen != device:
		device = seen
		generation += 1


## The name of one code: a key in the player's layout, a mouse button or a controller input.
static func code_name(code: String) -> String:
	if InputCodes.device_of(code) == "pad":
		return InputCodes.pad_name(code)
	var event := InputCodes.to_event(code)
	if event is InputEventKey:
		return KeyLabel.key_name(event)
	if event is InputEventMouseButton:
		return KeyLabel.mouse_button_name((event as InputEventMouseButton).button_index)
	return code


## The inputs bound to an action for a device ("keys" or "pad"; default: the one in use).
static func names_for(action: StringName, for_device: String = "") -> PackedStringArray:
	var want := for_device if not for_device.is_empty() else device
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_NONE:
			# The engine's ui_* actions bind some keys by key code (Enter, Escape).
			if want == "keys":
				out.append(KeyLabel.key_name(event))
			continue
		var code := InputCodes.from_event(event)
		if not code.is_empty() and InputCodes.device_of(code) == want:
			out.append(code_name(code))
	return out


## "A Select · B Back" style hint text for the device in use: pairs of [action, words].
static func hint_line(pairs: Array) -> String:
	var parts := PackedStringArray()
	for pair in pairs:
		var names := names_for(pair[0])
		if names.is_empty():
			continue
		parts.append("%s  %s" % [names[0], pair[1]])
	return "   ·   ".join(parts)
