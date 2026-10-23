extends TestCase
## File-level regression checks for every persisted setting, using a private per-process path.

const SaveFolder := preload("res://tests/save_folder.gd")


func before_each() -> void:
	SaveFolder.clear()


func after_each() -> void:
	SaveFolder.clear()


func _roundtrip(id: String, value: Variant) -> void:
	var path := SaveFolder.path("settings.cfg")
	var writer := SettingsService.new(path)
	check(writer.settings.set_value(id, value), "%s accepts a valid non-default value" % id)
	check_eq(writer.save_file(), OK, "%s writes settings.cfg" % id)
	var cfg := ConfigFile.new()
	check_eq(cfg.load(path), OK, "%s file is readable" % id)
	if value is float:
		check_near(float(cfg.get_value("values", id)), value, 0.000001, "%s stored in its named key" % id)
	else:
		check_eq(cfg.get_value("values", id), value, "%s stored in its named key" % id)
	var reader := SettingsService.new(path)
	check(reader.load_file().is_empty(), "%s reload has no warnings" % id)
	check_eq(reader.load_source, "file", "%s came from disk" % id)
	if value is float:
		check_near(float(reader.get_value(id)), value, 0.000001, "%s survived reload" % id)
	else:
		check_eq(reader.get_value(id), value, "%s survived reload" % id)
	check_eq(reader.settings.to_dict().values.size(), GameSettings.SPEC.size(), "all settings persisted")


func test_graphics_window_mode_roundtrips() -> void:
	_roundtrip("graphics/window_mode", "fullscreen")


func test_graphics_vsync_roundtrips() -> void:
	_roundtrip("graphics/vsync", false)


func test_graphics_frame_cap_roundtrips() -> void:
	_roundtrip("graphics/max_fps", 120)


func test_graphics_render_scale_roundtrips() -> void:
	_roundtrip("graphics/render_scale", 0.75)


func test_graphics_msaa_roundtrips() -> void:
	_roundtrip("graphics/msaa", "4x")


func test_master_volume_roundtrips() -> void:
	_roundtrip("audio/master", 35)


func test_music_volume_roundtrips() -> void:
	_roundtrip("audio/music", 25)


func test_sfx_volume_roundtrips() -> void:
	_roundtrip("audio/sfx", 45)


func test_ambience_volume_roundtrips() -> void:
	_roundtrip("audio/ambience", 55)


func test_mute_unfocused_roundtrips() -> void:
	_roundtrip("audio/mute_unfocused", true)


func test_zoom_speed_roundtrips() -> void:
	_roundtrip("controls/zoom_speed", 1.5)


func test_invert_zoom_roundtrips() -> void:
	_roundtrip("controls/invert_zoom", true)


func test_stick_deadzone_roundtrips() -> void:
	_roundtrip("controls/stick_deadzone", 0.35)


func test_text_scale_roundtrips() -> void:
	_roundtrip("accessibility/text_scale", 130)


func test_reduce_camera_motion_roundtrips() -> void:
	_roundtrip("accessibility/reduce_camera_motion", true)


func test_reduce_flashing_roundtrips() -> void:
	_roundtrip("accessibility/reduce_flashing", true)


func test_growth_trigger_roundtrips() -> void:
	_roundtrip("gameplay/growth_trigger", "press")


func test_pause_on_focus_loss_roundtrips() -> void:
	_roundtrip("gameplay/pause_on_focus_loss", false)


func test_chosen_slot_roundtrips() -> void:
	_roundtrip("game/slot", 3)


func test_invalid_choice_preserves_the_previous_saved_value() -> void:
	var path := SaveFolder.path("settings.cfg")
	var service := SettingsService.new(path)
	check(service.settings.set_value("graphics/window_mode", "fullscreen"), "valid choice")
	check_eq(service.save_file(), OK, "saved first choice")
	var before := FileAccess.get_file_as_string(path)
	check(not service.settings.set_value("graphics/window_mode", "giant"), "unknown choice refused")
	check_eq(service.settings.get_value("graphics/window_mode"), "fullscreen", "keeps previous choice")
	check_eq(service.save_file(), OK, "writes after refusal")
	check_eq(FileAccess.get_file_as_string(path), before, "refusal does not change file")


func test_wrong_kind_preserves_previous_numeric_setting() -> void:
	var service := SettingsService.new(SaveFolder.path("settings.cfg"))
	check(service.settings.set_value("audio/master", 35), "valid volume")
	check(not service.settings.set_value("audio/master", "loud"), "wrong kind refused")
	check_eq(service.settings.get_value("audio/master"), 35, "volume not reset")
	check_eq(service.save_file(), OK, "saved after refusal")
	var reader := SettingsService.new(service.path)
	check(reader.load_file().is_empty(), "reload valid")
	check_eq(reader.get_value("audio/master"), 35, "previous volume persists")


func test_numeric_out_of_range_values_use_documented_clamps() -> void:
	var service := SettingsService.new(SaveFolder.path("settings.cfg"))
	check(service.settings.set_value("audio/master", 101), "int is safely clamped")
	check(service.settings.set_value("graphics/render_scale", 0.12), "float is safely clamped")
	check_eq(service.settings.get_value("audio/master"), 100, "upper bound")
	check_eq(service.settings.get_value("graphics/render_scale"), 0.5, "lower bound")
	check_eq(service.save_file(), OK, "clamped values saved")
	var reader := SettingsService.new(service.path)
	check(reader.load_file().is_empty(), "clamped settings load cleanly")
	check_eq(reader.get_value("audio/master"), 100, "upper bound persists")
	check_eq(reader.get_value("graphics/render_scale"), 0.5, "lower bound persists")
