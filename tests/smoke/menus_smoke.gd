extends SceneTree
## Menus smoke (UI pass): the title screen, the settings screen and the save slots screen driven
## the way a player drives them, mostly with controller buttons (Input.parse_input_event), plus
## keyboard rebinding and the pause menu over a run. tools/check.sh runs it. It prints one PASS or
## FAIL line per check; the exit code is 0 when every check passes, 1 otherwise.
##
## It uses its own settings file and slot folder under user://smoke/, never the player's.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const ROOT := "user://smoke/menus"

var main: Main
var service: SettingsService
var _failures := 0
var _checks := 0
var _finished := false


func _initialize() -> void:
	print("Menus smoke, build %s" % BuildInfo.build_id())
	_wipe(ROOT)
	SaveSlots.folder = ROOT.path_join("saves")
	service = SettingsService.new(ROOT.path_join("settings.cfg"))
	service.load_file()
	SettingsService.set_shared(service)
	var founded := GameSession.new(SaveSlots.path(1), PoolLayout.DEFAULT_PATH, "").start_new("hunter", 4242)
	_check(founded.ok and founded.saved, "a hunter lineage is saved in slot 1")

	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	await _title()
	await _settings_with_a_controller()
	await _slots_with_a_controller()
	await _rebind_with_the_keyboard()
	await _text_size()
	await _pause_menu_with_a_controller()

	main.queue_free()
	await _frames(2)
	SettingsService.set_shared(null)
	_wipe(ROOT)
	_finished = true
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _finalize() -> void:
	if not _finished:
		print("FAIL the game quit before the smoke finished")
		quit(1)


func _title() -> void:
	var start := main.start_screen
	_check(start != null and start.slot_number == 1, "the title shows slot 1")
	_check(start.continue_lines().has("Hunter"), "its card names the hunter (%s)" % start.continue_lines())
	_check(_focus() == start.continue_button, "Continue has focus (%s)" % _focus_name())
	var ids := []
	for b in start.find_children("*", "Button", true, false):
		if b.get_parent().name == "Buttons" and b.is_visible_in_tree():
			ids.append(str(b.name))
	_check(ids == ["ContinueButton", "NewButton", "SlotsButton", "SettingsButton", "QuitButton"],
		"the menu is Continue, New lineage, Save slots, Settings, Quit (%s)" % [ids])
	var world := start.world
	_check(world != null and world.camera.current, "the live world is behind the title, its camera on")
	_check(world.hero_genome != null and Lineage.starting_body_of(world.hero_genome, main.session.catalog) == "hunter",
		"the saved hunter swims in it")
	var start_at := world.hero.position
	await _frames(30)
	_check(world.hero.position.distance_to(start_at) > 0.01, "and it swims (%.3f m)" % world.hero.position.distance_to(start_at))
	_check(start.continue_button.scale.x > 1.01, "the focused button has swelled (%.3f)" % start.continue_button.scale.x)
	_check(is_equal_approx(start.new_button.scale.x, 1.0), "the others have not")
	start.open_picker()
	start.select("omnivore")
	await _frames(2)
	_check(world.hero_genome == start._genomes["omnivore"], "picking the omnivore puts it in the world")
	start.show_main()
	await _frames(2)
	_check(Lineage.starting_body_of(world.hero_genome, main.session.catalog) == "hunter", "Back brings the saved hunter back")
	_check(_focus() == start.continue_button, "with Continue focused again")


func _settings_with_a_controller() -> void:
	var start := main.start_screen
	for i in 3:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	_check(_focus() == start.settings_button, "three d-pad presses reach Settings (%s)" % _focus_name())
	_check(InputPrompts.device == "pad", "the game knows a controller is in use")
	_check(start.hint.text.contains("A  Select") and start.hint.text.contains("B  Back"),
		"the hint names A and B (%s)" % start.hint.text)
	await _pad(JOY_BUTTON_A)
	var menu := main.settings_menu
	_check(menu != null and menu.is_open(), "A opens the settings")
	if menu == null:
		return
	_check(menu.tab == 0 and _focus() == menu._controls["graphics/window_mode"], "on Graphics, the first row focused (%s)" % _focus_name())
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(menu.tab == 1, "RB goes to Audio")
	_check(_focus() == menu._controls["audio/master"], "the master volume has focus (%s)" % _focus_name())
	await _pad(JOY_BUTTON_DPAD_LEFT)
	_check(service.get_value("audio/master") == 79, "d-pad left turns it down (%s)" % service.get_value("audio/master"))
	_check(menu._value_labels["audio/master"].text == "79%", "and the row shows 79%")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(menu.tab == 4, "LB twice wraps round to Gameplay")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	_check(service.growth_trigger() == "press", "d-pad right switches growing to the Grow button")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	_check(not service.pause_on_focus_loss(), "A flips the focus-loss switch off")
	await _pad(JOY_BUTTON_B)
	_check(main.settings_menu == null, "B closes the settings")
	_check(_focus() == start.settings_button, "and focus is back on Settings (%s)" % _focus_name())
	var saved := SettingsService.new(service.path)
	saved.load_file()
	_check(saved.get_value("audio/master") == 79 and saved.growth_trigger() == "press" and not saved.pause_on_focus_loss(),
		"closing wrote the changes to the settings file")


func _slots_with_a_controller() -> void:
	await _pad(JOY_BUTTON_DPAD_UP)
	_check(_focus() == main.start_screen.slots_button, "d-pad up reaches Save slots (%s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	var picker := main.slot_picker
	_check(picker != null and picker.is_open(), "A opens the slots")
	if picker == null:
		return
	_check(picker.play_button(1).disabled and picker.card_lines(1).has("Hunter"), "slot 1 is in use and holds the hunter")
	_check(_focus() == picker.play_button(2), "the first free slot has focus (%s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check(main.session.slot == SaveSlots.path(2), "A plays slot 2 (%s)" % main.session.slot)
	var reread := SettingsService.new(service.path)
	reread.load_file()
	_check(int(reread.get_value("game/slot")) == 2, "the choice of slot is remembered")
	var start := main.start_screen
	_check(start.slot_number == 2 and start.continue_button.disabled, "the title shows the empty slot 2")
	_check(_focus() == start.new_button, "with New lineage focused (%s)" % _focus_name())

	picker = main.open_slots()
	await _frames(2)
	picker.request_delete(1)
	await _frames(1)
	_check(_focus() != null and _focus().name == "cancel", "deleting asks with Cancel focused (%s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	_check(SaveSlots.peek(1).exists, "Cancel keeps slot 1")
	picker.request_delete(1)
	await _frames(1)
	await _pad(JOY_BUTTON_DPAD_LEFT)
	_check(_focus() != null and _focus().name == "delete", "d-pad left reaches Delete (%s)" % _focus_name())
	await _pad(JOY_BUTTON_A)
	await _frames(2)
	_check(not SaveSlots.peek(1).exists, "Delete empties slot 1")
	_check(picker.card_lines(1).has("Empty"), "and its card says so")
	await _pad(JOY_BUTTON_B)
	_check(main.slot_picker == null and _focus() == main.start_screen.slots_button, "B closes the slots, focus on Save slots")


func _rebind_with_the_keyboard() -> void:
	var menu := main.open_settings()
	await _frames(2)
	menu.show_tab(2)
	var button: Button = menu._bind_buttons[["grow", "keys"]]
	button.grab_focus()
	await _key(KEY_ENTER)
	_check(menu.capture_action == "grow", "Enter on Grow's key waits for a key (%s)" % button.text)
	await _key(KEY_H)
	_check(InputMap.action_has_event(&"grow", InputCodes.to_event("key:%d" % KEY_H)), "H now grows")
	_check(button.text == "H" and _focus() == button, "the button names H and keeps focus (%s)" % button.text)
	button.grab_focus()
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	_check(menu.capture_action == "" and menu.is_open(), "Esc while waiting cancels the wait, not the screen")
	_check(InputMap.action_has_event(&"grow", InputCodes.to_event("key:%d" % KEY_H)), "and H still grows")
	await _key(KEY_ESCAPE)
	_check(main.settings_menu == null, "a second Esc closes the settings")
	service.reset_bindings()
	service.save_file()


func _text_size() -> void:
	var theme: Theme = load(SettingsService.THEME_PATH)
	var before := theme.get_font_size(&"font_size", &"Button")
	service.set_value("accessibility/text_scale", 130)
	_check(theme.get_font_size(&"font_size", &"Button") == roundi(before * 1.3), "text size 130% scales the buttons' text")
	service.set_value("accessibility/text_scale", 100)
	_check(theme.get_font_size(&"font_size", &"Button") == before, "and 100% puts it back")


func _pause_menu_with_a_controller() -> void:
	var result := main.start_new("grazer", 4242)
	await _frames(3)
	_check(result.ok and main.pool != null, "a new grazer lineage starts in slot 2")
	if main.pool == null:
		return
	main.pool.pause_on_focus_loss = false
	await _pad(JOY_BUTTON_START)
	_check(main.pause_menu.is_open() and main.pool.paused, "Menu pauses")
	_check(_focus() == main.pause_menu.resume_button, "Resume has focus (%s)" % _focus_name())
	var controls: Label = main.pause_menu.get_node("%ControlsText")
	_check(controls.text.contains("Swim: Left stick or D-pad"), "the controls name the controller's inputs (%s)" % controls.text.replace("\n", " | "))
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	_check(_focus() == main.pause_menu.settings_button, "Settings is two presses down (%s)" % _focus_name())
	_check(MenuBounce.rest_scale(main.pause_menu.settings_button) > 1.0 and MenuBounce.rest_scale(main.pause_menu.resume_button) == 1.0,
		"the focused pause button swells, the others rest")
	await _pad(JOY_BUTTON_A)
	_check(main.settings_menu != null and main.settings_menu.is_open(), "A opens the settings over the run")
	await _pad(JOY_BUTTON_B)
	_check(main.settings_menu == null and main.pause_menu.is_open() and main.pool.paused, "B closes them; still paused")
	_check(_focus() == main.pause_menu.settings_button, "focus back on Settings (%s)" % _focus_name())
	await _pad(JOY_BUTTON_B)
	_check(not main.pause_menu.is_open() and not main.pool.paused, "B again resumes")
	service.set_value("controls/invert_zoom", true)
	_check(main.pool.camera.zoom_step < 0.0, "inverting the zoom applies to the running camera")
	service.set_value("controls/invert_zoom", false)
	main.session.save_now()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		event.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(1)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(1)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _focus_name() -> String:
	return str(_focus().name) if _focus() != null else "nothing"


func _check(ok: bool, what: String) -> void:
	if what.is_empty():
		return
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
