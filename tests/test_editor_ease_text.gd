extends TestCase
## Editor-ease's binding text (game/ui/editor_ease/shortcut_text.gd; Bible 19, inputs shown from the bindings):
## every key bound to undo and redo is named with its modifiers, read from the InputMap, not from constants.

const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")


func test_undo_and_redo_name_every_bound_key_with_its_modifiers() -> void:
	for action: StringName in [&"ui_undo", &"ui_redo"]:
		var text := ShortcutText.label(action, "keys")
		var keys := InputMap.action_get_events(action).filter(func(e: InputEvent) -> bool: return e is InputEventKey)
		check(not keys.is_empty(), "%s has a key bound" % action)
		var names := ShortcutText.for_action(action, "keys")
		check_eq(names.size(), keys.size(), "%s: one name per bound key (%s)" % [action, text])
		for i in keys.size():
			var e: InputEventKey = keys[i]
			var key := OS.get_keycode_string(e.keycode if e.physical_keycode == KEY_NONE else e.physical_keycode)
			check(names[i].ends_with("+" + key) or names[i] == key, "%s names %s (%s)" % [action, key, names[i]])
			var ctrl := e.command_or_control_autoremap or e.ctrl_pressed
			var mod := "Cmd" if e.command_or_control_autoremap and OS.has_feature("macos") else "Ctrl"
			check_eq(names[i].contains(mod + "+"), ctrl, "%s: %s shows its control modifier" % [action, names[i]])
			check_eq(names[i].contains("Shift+"), e.shift_pressed, "%s: %s shows Shift as bound" % [action, names[i]])
			check(text.contains(names[i]), "%s's label holds %s" % [action, names[i]])


func test_a_physical_key_is_named_once_without_doubled_modifiers() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_D
	e.ctrl_pressed = true
	e.shift_pressed = true
	check_eq(ShortcutText.key_text(e), "Ctrl+Shift+D", "modifiers once, then the key")


func test_a_hint_line_skips_what_the_device_has_not_bound_and_tooltips_carry_the_keys() -> void:
	var line := ShortcutText.hint_line([[&"ui_undo", "undo"], [&"no_such_action", "nothing"]], "keys")
	check(line.begins_with(ShortcutText.for_action(&"ui_undo", "keys")[0] + "  undo"), "undo first: " + line)
	check(not line.contains("nothing"), "an unbound action is left out")
	check_eq(ShortcutText.label(&"no_such_action"), "", "no action, no label")
	check_eq(ShortcutText.with_binding("Undo", &"no_such_action"), "Undo", "no binding, the words alone")
	var tip := ShortcutText.with_binding("Undo the last change", &"ui_undo", "keys")
	check(tip.contains("(" + ShortcutText.label(&"ui_undo", "keys") + ")"), "the tooltip names the keys: " + tip)
