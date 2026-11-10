extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): the inputs bound to an action as words with their modifiers
## ("Ctrl+Z", "Ctrl+Shift+Z / Ctrl+Y"), for the editors' tooltips and key lines (Bible 19: show the bindings,
## not hardcoded text). KeyLabel.key_name names the key alone, so an undo bound to Ctrl+Z would read "Z"; this
## adds the modifiers and leaves the key's name to KeyLabel (the player's layout in a window, the physical key
## headless, where a layout lookup would log an engine error). No class_name: preload it by path.

## Between two bindings of one action.
const JOIN := " / "
## Between two entries of a key line, as InputPrompts.hint_line does.
const LINE_JOIN := "   ·   "


## One key with its modifiers: "Ctrl+Shift+Z". A binding made with command_or_control_autoremap (the engine's
## ui_undo and ui_redo) reads "Ctrl" off a Mac and "Cmd" on one.
static func key_text(e: InputEventKey) -> String:
	var mac := OS.has_feature("macos")
	var parts := PackedStringArray()
	if e.command_or_control_autoremap:
		parts.append("Cmd" if mac else "Ctrl")
	elif e.ctrl_pressed:
		parts.append("Ctrl")
	if e.alt_pressed:
		parts.append("Option" if mac else "Alt")
	if e.shift_pressed:
		parts.append("Shift")
	if e.meta_pressed and not e.command_or_control_autoremap:
		parts.append("Cmd" if mac else "Meta")
	# The key alone: a bare copy, so KeyLabel never adds its own modifier text (as_text_physical_keycode does).
	var bare := InputEventKey.new()
	bare.keycode = e.keycode
	bare.physical_keycode = e.physical_keycode
	bare.key_label = e.key_label
	parts.append(KeyLabel.key_name(bare))
	return "+".join(parts)


## Every input bound to `action` for a device ("keys" or "pad"; "" for the one in use, InputPrompts.device), in
## binding order: keys with their modifiers and mouse buttons, or the controller's buttons.
static func for_action(action: StringName, device := "") -> PackedStringArray:
	var want := device if not device.is_empty() else InputPrompts.device
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	if want == "pad":
		return InputPrompts.names_for(action, "pad")
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			out.append(key_text(event))
		elif event is InputEventMouseButton:
			out.append(KeyLabel.mouse_button_name((event as InputEventMouseButton).button_index))
	return out


## The bindings of `action` in one string, "Ctrl+Shift+Z / Ctrl+Y"; "" when nothing is bound for the device.
static func label(action: StringName, device := "") -> String:
	return JOIN.join(for_action(action, device))


## "Ctrl+Z  undo   ·   Escape  back" for the device in use: pairs of [action, words], each with its first
## binding; an action with nothing bound for the device is left out.
static func hint_line(pairs: Array, device := "") -> String:
	var parts := PackedStringArray()
	for pair: Array in pairs:
		var names := for_action(pair[0], device)
		if not names.is_empty():
			parts.append("%s  %s" % [names[0], pair[1]])
	return LINE_JOIN.join(parts)


## A button's tooltip: "Undo the last change (Ctrl+Z)", or just the words when nothing is bound.
static func with_binding(words: String, action: StringName, device := "") -> String:
	var keys := label(action, device)
	return words if keys.is_empty() else "%s (%s)" % [words, keys]
