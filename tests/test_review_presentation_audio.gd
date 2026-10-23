extends TestCase
## Headless checks for presentation routing and controls, with no audio device required.


func test_menu_cancel_uses_back_cue() -> void:
	var button := Button.new()
	button.text = "Cancel deletion"
	check_eq(UiSounds.press_sound(button), "back", "cancel sounds distinct")
	button.free()


func test_menu_explicit_sound_overrides_caption() -> void:
	var button := Button.new()
	button.text = "Cancel"
	button.set_meta("ui_sound", "press")
	check_eq(UiSounds.press_sound(button), "press", "explicit action wins")
	button.free()


func test_menu_regular_action_uses_press_cue() -> void:
	var button := Button.new()
	button.text = "New lineage"
	check_eq(UiSounds.press_sound(button), "press", "regular action")
	button.free()


func test_every_settings_row_names_a_persisted_key() -> void:
	var shown := {}
	for tab in SettingsMenu.ROWS:
		for row in SettingsMenu.ROWS[tab]:
			shown[row[0]] = true
	for key in shown:
		check(GameSettings.SPEC.has(key), "%s has a saved settings specification" % key)
	for key in GameSettings.SPEC:
		check(shown.has(key) or key == "game/slot", "%s is reachable or is the dedicated slot" % key)


func test_default_menu_bindings_decode_for_both_devices() -> void:
	var service := SettingsService.new("user://test_review_presentation_audio.cfg")
	for pair in SettingsService.REBINDABLE:
		var action: String = pair[0]
		for code in service.codes_for(action):
			check(InputCodes.to_event(code) != null, "%s %s decodes" % [action, code])
	for action in SettingsService.UI_PAD:
		var code: String = SettingsService.UI_PAD[action]
		check(InputCodes.to_event(code) != null, "%s menu gamepad input decodes" % action)
		check_eq(InputCodes.device_of(code), "pad", "%s is a gamepad control" % action)


func test_slot_lines_do_not_show_payload_fields() -> void:
	var header := {"body": "grazer", "lineage_tag": "A1", "generation": 2,
		"adaptation_points": 7, "saved_at_unix": 1000}
	var peek := {"exists": true, "ok": true, "summary": header, "secret_payload": "DO_NOT_SHOW"}
	var lines := "\n".join(SlotPicker.slot_lines(peek))
	check(lines.contains("A1") and lines.contains("Generation 2"), "header appears")
	check(not lines.contains("DO_NOT_SHOW"), "unknown full-save data is not displayed")


func test_settings_tab_first_focus_is_an_enabled_visible_row() -> void:
	var menu := SettingsMenu.new()
	menu.open(SettingsService.new("user://test_review_presentation_audio.cfg"))
	for i in SettingsMenu.TABS.size():
		menu.show_tab(i)
		var first: Control = menu._first_focus()
		check(first != null and first.visible, "%s has a visible first control" % SettingsMenu.TABS[i])
		if first is BaseButton:
			check(not (first as BaseButton).disabled, "%s starts on an enabled control" % SettingsMenu.TABS[i])
	menu.free()


func test_positional_effect_flat_fallback_routes_to_sfx() -> void:
	var node := CellAudio.new()
	var player := node._flat_for_positional("tell_lunge")
	check_eq(player.bus, &"SFX", "fallback cue uses the effects bus")
	check_eq(player.max_polyphony, CellAudio.FLAT_POLYPHONY, "polyphony stays bounded")
	node.free()


func test_ambience_loop_routes_to_ambience_bus() -> void:
	var node := CellAudio.new()
	var player := node._loop_player("ambience_probe", "amb_bed", CellAudio.BED_DB)
	check_eq(player.bus, &"Ambience", "bed uses independently mutable ambience bus")
	check(player.stream != null, "bed has a loadable stream")
	node.free()


func test_music_creates_no_players_during_600_ticks() -> void:
	var node := Soundtrack.new()
	node._ready()
	var before := node.get_child_count()
	check_eq(before, Soundtrack.LAYERS.size(), "one fixed player per layer")
	for tick in 600:
		node._process(1.0 / 60.0)
	check_eq(node.get_child_count(), before, "no tick-driven allocation")
	node.free()


func test_music_bus_mute_covers_all_soundtrack_layers() -> void:
	var bus := AudioServer.get_bus_index("Music")
	check(bus >= 0, "Music bus exists")
	if bus < 0:
		return
	var node := Soundtrack.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	if node._players.is_empty():
		node._ready()
	check_eq(node._players.size(), Soundtrack.LAYERS.size(), "every layer exists")
	var old := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, true)
	for player in node._players.values():
		check_eq((player as AudioStreamPlayer).bus, &"Music", "layer is behind the muted bus")
	check(AudioServer.is_bus_mute(bus), "bus stays muted while routed layers exist")
	AudioServer.set_bus_mute(bus, old)
	node.free()
