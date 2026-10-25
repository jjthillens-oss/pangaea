extends TestCase
## A scene control must resolve its key through the imported English catalog.


func test_pause_title_resolves_to_english_in_scene_tree() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var menu := load("res://game/ui/pause_menu.tscn").instantiate() as PauseMenu
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	var title := menu.get_node("Center/Panel/Box/Title") as Label
	var resume := menu.get_node("Center/Panel/Box/Buttons/Resume") as Button
	check(title.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED, "title auto translation is enabled")
	check(resume.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED, "button auto translation is enabled")
	check_eq(title.tr(title.text), "Paused", "scene label must not display a raw key")
	check_eq(resume.tr(resume.text), "Resume", "button must not display a raw key")
	menu.free()
	TranslationServer.set_locale(previous)


func test_dynamic_messages_resolve_through_the_catalog() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	check_eq(KeyLabel.mouse_button_name(MOUSE_BUTTON_LEFT), "Left mouse", "input label resolves")
	check_eq(str(Main.quit_prompt(false, false).title), "Save first?", "dialog title resolves")
	var arrow := StarvingArrow.new()
	check_eq(arrow.label_text(), "Food 0 m", "drawn distance resolves")
	arrow.free()
	TranslationServer.set_locale(previous)
