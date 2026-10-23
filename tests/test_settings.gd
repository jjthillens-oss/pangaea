extends TestCase
## Player settings (UI pass): GameSettings checks values, InputCodes round-trips inputs, and
## SettingsService saves, reloads and applies them (bindings, deadzone, buses, text size) without
## touching the player's own settings file.

const PATH := "user://test_settings/settings.cfg"

var _service: SettingsService


func before_each() -> void:
	_clear()
	_service = SettingsService.new(PATH)


func after_each() -> void:
	_service.reset_bindings()
	_service.settings = GameSettings.defaults()
	_service.apply_bindings()
	_service.apply_text_scale()
	_clear()


func _clear() -> void:
	for file in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func test_defaults_match_the_spec() -> void:
	var s := GameSettings.defaults()
	for id in GameSettings.SPEC:
		check_eq(s.get_value(id), GameSettings.SPEC[id].default, id)
	check(s.problems.is_empty(), "no problems")
	check(s.bindings.is_empty(), "no rebinds")


func test_values_are_checked_against_the_spec() -> void:
	var s := GameSettings.defaults()
	check(s.set_value("audio/music", 140), "a number out of range is clamped")
	check_eq(s.get_value("audio/music"), 100, "clamped to 100")
	check(not s.set_value("audio/music", "loud"), "text refused for a number")
	check_eq(s.get_value("audio/music"), 100, "unchanged after a refusal")
	check(s.set_value("graphics/render_scale", 0.73), "a float is snapped")
	check_near(s.get_value("graphics/render_scale"), 0.75, 0.0001, "snapped to the 0.05 step")
	check(not s.set_value("graphics/window_mode", "huge"), "an unknown option refused")
	check(s.set_value("accessibility/text_scale", 115.0), "a float that is a whole option is fine")
	check_eq(s.get_value("accessibility/text_scale"), 115, "kept as the option")
	check(not s.set_value("nope/nothing", 1), "an unknown setting refused")
	check(not s.set_value("graphics/vsync", 1), "a number is not a bool")


func test_choices_cycle_both_ways() -> void:
	var s := GameSettings.defaults()
	check_eq(s.cycle("gameplay/growth_trigger", 1), "press", "next")
	check_eq(s.cycle("gameplay/growth_trigger", 1), "auto", "wraps")
	check_eq(s.cycle("graphics/window_mode", -1), "fullscreen", "previous wraps to the end")


func test_bad_data_falls_back_to_defaults_and_says_why() -> void:
	var s := GameSettings.from_dict({"values": {"audio/master": "x", "audio/sfx": 30, "bogus/key": 2},
		"bindings": {"pause": ["key:80", "nonsense"], "grow": ["pad:3"], "zoom_in": 5}})
	check_eq(s.get_value("audio/master"), 80, "bad value -> default")
	check_eq(s.get_value("audio/sfx"), 30, "good value kept")
	check(not s.bindings.has("pause"), "a list with a bad code is dropped whole")
	check(not s.bindings.has("zoom_in"), "a non-list is dropped")
	check_eq(s.bindings.get("grow"), PackedStringArray(["pad:3"]), "good bindings kept")
	check_eq(s.problems.size(), 4, "each problem named: %s" % [s.problems])


func test_input_codes_round_trip() -> void:
	for code in ["key:87", "mouse:1", "mouse:4", "pad:0", "pad:14", "axis:1:-1", "axis:5:1"]:
		var event := InputCodes.to_event(code)
		check(event != null, "%s makes an event" % code)
		check_eq(InputCodes.from_event(event), code, "%s round trip" % code)
	for bad in ["", "key", "key:0", "key:x", "mouse:42", "pad:-1", "axis:1", "axis:1:2", "joy:1", "key:1:2"]:
		check(InputCodes.to_event(bad) == null, "'%s' refused" % bad)
	var resting := InputEventJoypadMotion.new()
	resting.axis = JOY_AXIS_LEFT_X
	resting.axis_value = 0.1
	check_eq(InputCodes.from_event(resting), "", "a stick at rest is no input")
	check_eq(InputCodes.pad_name("pad:0"), "A", "A")
	check_eq(InputCodes.pad_name("axis:1:-1"), "Left stick up", "stick name")
	check_eq(InputCodes.device_of("axis:0:1"), "pad", "stick is the pad")
	check_eq(InputCodes.device_of("mouse:1"), "keys", "mouse is keys")


func test_settings_survive_a_save_and_reload() -> void:
	_service.set_value("audio/music", 35)
	_service.set_value("gameplay/growth_trigger", "press")
	_service.set_value("accessibility/reduce_camera_motion", true)
	_service.rebind("pause", "key:%d" % KEY_O)
	check_eq(_service.save_file(), OK, "saved")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file left")
	var again := SettingsService.new(PATH)
	check(again.load_file().is_empty(), "reads back cleanly")
	check_eq(again.load_source, "file", "from the file")
	check_eq(again.get_value("audio/music"), 35, "music")
	check_eq(again.growth_trigger(), "press", "growth trigger")
	check(again.reduce_camera_motion(), "reduce camera motion")
	check_eq(again.codes_for("pause")[0], "key:%d" % KEY_O, "rebind kept")


func test_a_missing_or_damaged_file_means_defaults() -> void:
	check(_service.load_file().is_empty(), "missing file is fine")
	check_eq(_service.load_source, "defaults", "defaults")
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[values\nthis is not a config file = = =")
	f.close()
	check(not _service.load_file().is_empty(), "damage is reported")
	check_eq(_service.load_source, "damaged", "damaged")
	check_eq(_service.get_value("audio/master"), 80, "defaults used")
	check(FileAccess.file_exists(PATH), "the damaged file is left in place")


func test_rebinding_swaps_an_input_another_action_used() -> void:
	var w := "key:%d" % KEY_W
	var g := "key:%d" % KEY_G
	_service.rebind("grow", w)
	check_eq(_service.first_code("grow", "keys"), w, "grow takes W")
	check_eq(_service.first_code("move_up", "keys"), g, "swim up gets grow's old key")
	check(InputMap.action_has_event("grow", InputCodes.to_event(w)), "applied to the input map")
	check(not InputMap.action_has_event("move_up", InputCodes.to_event(w)), "W left swim up")
	check_eq(_service.first_code("grow", "pad"), "pad:3", "the controller input is untouched")
	_service.rebind("grow", "pad:0")
	check_eq(_service.first_code("grow", "pad"), "pad:0", "controller rebind")
	_service.reset_bindings()
	check_eq(_service.codes_for("move_up"), SettingsService.default_codes("move_up"), "reset to the project's")
	check(InputMap.action_has_event("move_up", InputCodes.to_event(w)), "W back on swim up")


func test_every_rebindable_action_exists_and_has_a_keyboard_input() -> void:
	for pair in SettingsService.REBINDABLE:
		check(InputMap.has_action(pair[0]), "%s exists" % pair[0])
		check(not _service.first_code(pair[0], "keys").is_empty(), "%s has a key or mouse input" % pair[0])


func test_the_deadzone_and_the_menu_stick_are_applied() -> void:
	_service.set_value("controls/stick_deadzone", 0.35)
	check_near(InputMap.action_get_deadzone("move_left"), 0.35, 0.001, "deadzone")
	var up := InputCodes.to_event("axis:1:-1")
	check(InputMap.action_has_event("ui_up", up), "the menus take the left stick")
	check(InputMap.action_has_event("ui_accept", InputCodes.to_event("pad:0")), "A chooses in menus")
	check(InputMap.action_has_event("ui_cancel", InputCodes.to_event("pad:1")), "B goes back in menus")
	_service.set_value("controls/stick_deadzone", 0.2)


func test_text_scale_scales_the_theme_and_back() -> void:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_font_size("font_size", "Label", 30)
	_service.set_value("accessibility/text_scale", 130)
	_service.apply_text_scale(theme)
	check_eq(theme.default_font_size, 26, "default size scaled")
	check_eq(theme.get_font_size("font_size", "Label"), 39, "type size scaled")
	_service.set_value("accessibility/text_scale", 100)
	_service.apply_text_scale(theme)
	check_eq(theme.get_font_size("font_size", "Label"), 30, "back to the base, not compounded")


func test_audio_volumes_skip_missing_buses() -> void:
	# The bus layout belongs to the sound work; with or without it this must not error.
	_service.set_value("audio/master", 0)
	check(AudioServer.is_bus_mute(0), "master muted at 0")
	_service.set_value("audio/master", 50)
	check(not AudioServer.is_bus_mute(0), "unmuted")
	check_near(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01, "half volume")
	_service.set_value("audio/master", 80)


func test_slot_paths() -> void:
	check_eq(SaveSlots.path(1), GameSession.DEFAULT_SLOT, "slot 1 is the old default slot")
	check_eq(SaveSlots.path(3), "user://saves/slot_3.json", "slot 3")
	check_eq(SaveSlots.path(9), "user://saves/slot_3.json", "clamped")
	check_eq(SaveSlots.number_of("user://saves/slot_2.json"), 2, "number of a slot path")
	check_eq(SaveSlots.number_of("user://smoke/slot_1.json"), 0, "a smoke slot is no numbered slot")
	_service.set_value("game/slot", 2)
	check_eq(_service.current_slot_path(), "user://saves/slot_2.json", "the chosen slot")
