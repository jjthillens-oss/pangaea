extends TestCase
## The menus of the UI pass: the settings screen, the save slots screen and the slots service, and
## the device-aware input names. Each test uses its own settings file and slot folder, never the
## player's. The screens' widgets and flows driven by real key and controller presses are checked
## in tests/smoke/menus_smoke.gd, where the screens are in a running scene tree.

const ROOT := "user://test_menus"

var _service: SettingsService
var _old_folder := ""
var _nodes: Array[Node] = []


func before_each() -> void:
	_wipe(ROOT)
	_old_folder = SaveSlots.folder
	SaveSlots.folder = ROOT.path_join("saves")
	_service = SettingsService.new(ROOT.path_join("settings.cfg"))


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	_service.reset_bindings()
	SaveSlots.folder = _old_folder
	InputPrompts.device = "keys"
	_wipe(ROOT)


func _add(node: Node) -> Node:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_nodes.append(node)
	return node


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _found_in_slot(n: int, body: String) -> Dictionary:
	var session := GameSession.new(SaveSlots.path(n), PoolLayout.DEFAULT_PATH, "")
	return session.start_new(body, 77)


func test_every_settings_tab_builds_a_row_for_each_of_its_settings() -> void:
	var menu: SettingsMenu = _add(SettingsMenu.new())
	menu.open(_service)
	for i in SettingsMenu.TABS.size():
		menu.show_tab(i)
		var tab: String = SettingsMenu.TABS[i]
		for row in SettingsMenu.ROWS[tab]:
			check(menu._controls.has(row[0]), "%s has a row for %s" % [tab, row[0]])
			check(GameSettings.SPEC.has(row[0]), "%s is a real setting" % row[0])
	menu.show_tab(2)
	for pair in SettingsService.REBINDABLE:
		check(menu._bind_buttons.has([pair[0], "keys"]) and menu._bind_buttons.has([pair[0], "pad"]),
			"Controls lists %s for both devices" % pair[0])
	check_eq(menu.tab, 2, "on Controls")
	menu.show_tab(-1)
	check_eq(menu.tab, SettingsMenu.TABS.size() - 1, "tabs wrap around")


func test_every_setting_is_on_some_tab_except_the_slot() -> void:
	var shown := []
	for tab in SettingsMenu.ROWS:
		for row in SettingsMenu.ROWS[tab]:
			shown.append(row[0])
	for id in GameSettings.SPEC:
		check(id in shown or id == "game/slot", "%s is on a tab" % id)


func test_choice_rows_step_both_ways() -> void:
	var menu: SettingsMenu = _add(SettingsMenu.new())
	menu.open(_service)
	menu.show_tab(4)
	var choice: SettingsMenu.ChoiceButton = menu._controls["gameplay/growth_trigger"]
	choice.step(1)
	check_eq(_service.growth_trigger(), "press", "right picks the next option")
	check(choice.text.contains("When I press Grow"), "the row shows it (%s)" % choice.text)
	choice.step(-1)
	check_eq(_service.growth_trigger(), "auto", "left goes back")


func test_rebinding_waits_for_an_input_of_the_right_device() -> void:
	var menu: SettingsMenu = _add(SettingsMenu.new())
	menu.open(_service)
	menu.show_tab(2)
	menu.begin_capture("grow", "keys")
	check_eq(menu.binding_text("grow", "keys"), str(TranslationServer.translate(SettingsMenu.WAIT_TEXT)), "the button says it is waiting")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	check(not menu.capture(pad), "a controller button is not a keyboard input")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	key.pressed = true
	check(menu.capture(key), "a key is taken")
	check_eq(_service.first_code("grow", "keys"), "key:%d" % KEY_H, "grow is now H")
	check_eq(menu.capture_action, "", "no longer waiting")
	menu.begin_capture("grow", "pad")
	check(menu.capture(pad), "a controller button is taken for the controller column")
	check_eq(_service.first_code("grow", "pad"), "pad:%d" % JOY_BUTTON_X, "grow is now X")
	check_eq(menu.binding_text("grow", "pad"), "X", "and the button names it")


func test_closing_the_settings_writes_the_file() -> void:
	var menu: SettingsMenu = _add(SettingsMenu.new())
	menu.open(_service)
	_service.set_value("audio/sfx", 10)
	menu.close()
	check(not menu.is_open(), "closed")
	var again := SettingsService.new(_service.path)
	again.load_file()
	check_eq(again.get_value("audio/sfx"), 10, "the change is in the file")


func test_value_text_reads_plainly() -> void:
	check_eq(SettingsMenu.value_text("graphics/vsync", true), "On", "bool")
	check_eq(SettingsMenu.value_text("audio/master", 80), "80%", "volume")
	check_eq(SettingsMenu.value_text("graphics/render_scale", 0.75), "75%", "resolution")
	check_eq(SettingsMenu.value_text("controls/zoom_speed", 1.5), "1.50x", "zoom speed")
	check_eq(SettingsMenu.value_text("graphics/max_fps", 0, {0: "No limit"}), "No limit", "words win")


func test_slot_lines_for_empty_unreadable_and_saved_slots() -> void:
	check_eq(SlotPicker.slot_lines({"exists": false})[0], "Empty", "empty")
	check_eq(SlotPicker.slot_lines({"exists": true, "ok": false})[0], "Unreadable", "unreadable")
	var founded := _found_in_slot(2, "grazer")
	check(founded.ok and founded.saved, "a lineage saved in slot 2")
	var peeks := SaveSlots.peek_all()
	check_eq(peeks.size(), SaveSlots.COUNT, "one summary per slot")
	check(not peeks[0].exists and peeks[1].ok and not peeks[2].exists, "only slot 2 holds a lineage")
	check_eq(peeks[1].slot, 2, "numbered")
	var lines := SlotPicker.slot_lines(peeks[1])
	check_eq(lines[0], "Grazer", "the body first")
	check(lines[1].begins_with("Lineage "), "then the lineage tag (%s)" % lines[1])


func test_deleting_a_slot_removes_its_save_and_backup_only() -> void:
	_found_in_slot(2, "omnivore")
	var path := SaveSlots.path(2)
	var session := GameSession.new(path, PoolLayout.DEFAULT_PATH, "")
	session.continue_run()
	session.save_now()   # a second save makes the backup
	check(FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"), "a save and its backup")
	var corrupt := path + ".corrupt-1"
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	check_eq(SaveSlots.delete(path), OK, "deleted")
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"), "both gone")
	check(FileAccess.file_exists(corrupt), "a set-aside unreadable file is kept")
	check(not SaveSlots.peek(2).exists, "the slot reads as empty")


func test_input_prompts_follow_the_device_in_use() -> void:
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 0.1
	InputPrompts.note(stick)
	check_eq(InputPrompts.device, "keys", "a stick at rest changes nothing")
	stick.axis_value = -0.9
	var before := InputPrompts.generation
	InputPrompts.note(stick)
	check_eq(InputPrompts.device, "pad", "a pushed stick means the controller")
	check(InputPrompts.generation > before, "and hints know to redraw")
	check_eq(InputPrompts.names_for(&"move_up"), PackedStringArray(["Left stick up", "D-pad up"]), "pad names")
	check_eq(InputPrompts.names_for(&"pause"), PackedStringArray(["Menu"]), "Menu pauses")
	var lines := PauseMenu.pad_controls_lines()
	check(lines.has("Swim: Left stick or D-pad"), "the pause menu names the stick (%s)" % lines)
	check(lines.has("Grow: Y"), "and Y grows")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputPrompts.note(key)
	check_eq(InputPrompts.device, "keys", "a key brings the keys back")
	check(InputPrompts.names_for(&"move_up").has("W") or DisplayServer.get_name() == "headless", "key names")


func test_hit_flashes_swell_gently_when_flashing_is_reduced() -> void:
	check_eq(PlayerCellView.hit_flash(0.0, 0.15), 1.0, "a hit starts at full strength")
	check_eq(PlayerCellView.hit_flash(-1.0, 0.15), 0.0, "no hit, no flash")
	check_eq(PlayerCellView.hit_flash(0.15, 0.15), 0.0, "over after its length")
	check_eq(PlayerCellView.hit_flash(0.0, 0.15, true), 0.0, "reduced: it does not jump on")
	var peak := 0.0
	for i in 16:
		peak = maxf(peak, PlayerCellView.hit_flash(0.01 * i, 0.15, true))
	check(peak > 0.3 and peak <= PlayerCellView.REDUCED_FLASH_PEAK + 0.0001, "reduced: it peaks at %.2f" % peak)


func test_the_starving_arrow_label_follows_text_size() -> void:
	var old := SettingsService.shared()
	SettingsService.set_shared(_service)
	check_eq(StarvingArrow.font_size(), StarvingArrow.FONT_SIZE, "100%")
	_service.set_value("accessibility/text_scale", 130)
	check_eq(StarvingArrow.font_size(), roundi(StarvingArrow.FONT_SIZE * 1.3), "130%")
	_service.set_value("accessibility/text_scale", 100)
	SettingsService.set_shared(old)


func test_the_settings_footer_names_the_inputs_of_the_device_in_use() -> void:
	_service.apply_bindings()
	InputPrompts.device = "pad"
	var pad := SettingsMenu.hint_text()
	check(pad.begins_with("LB / RB  Tabs"), "the controller's tab buttons (%s)" % pad)
	check(pad.contains("A  Select") and pad.contains("B  Back"), "A and B from the input map (%s)" % pad)
	check(pad.contains("D-pad  Change"), "the d-pad changes values (%s)" % pad)
	InputPrompts.device = "keys"
	var keys := SettingsMenu.hint_text()
	check(keys.begins_with("Q / E  Tabs") and not keys.contains("A  Select"), "the keyboard's (%s)" % keys)
	check_eq(SettingsMenu.pair_name("Left", "Right"), "Left / Right", "two keys")
	check_eq(SettingsMenu.pair_name("D-pad left", "D-pad right"), "D-pad", "one pad")
