extends TestCase
## Editor-ease in the creature editor (game/ui/creature_editor_hud.gd hooks, game/ui/editor_ease/;
## docs/proposals/editor-ease.md): Undo and Redo name the keys bound to them and the dock says what each button does
## (Bible 19 inputs shown from the bindings). The HUD is driven alone, as tests/test_creature_editor_hud.gd does, and
## inside the editor scene where a check needs the editor's own rules.

const HUD_SCENE := preload("res://game/ui/creature_editor_hud.tscn")
const EDITOR_SCENE := preload("res://game/scenes/creature/creature_editor.tscn")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")
const Ease := preload("res://game/ui/editor_ease/creature_hud_ease.gd")

const POINTS := 150

var hud: CreatureEditorHud
var editor: CreatureEditor


func after_each() -> void:
	if hud != null:
		hud.free()
		hud = null
	if editor != null:
		editor.free()
		editor = null


## The HUD alone, wired and given a palette.
func open_hud(tools: Array = ["eye", "horn", "maw", "foot", "crest"]) -> CreatureEditorHud:
	hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.wire()
	var roles := {}
	var rules := CreatureData.part_rules()
	for type in rules:
		roles[type] = String(rules[type].get("role", ""))
	hud.setup(tools, CreatureData.editor_costs(), [Color.RED, Color.GREEN], roles)
	return hud


func open_editor(body_name := "s1_quadruped", points := POINTS) -> CreatureEditor:
	editor = EDITOR_SCENE.instantiate()
	editor.threaded = false
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	editor.setup(CreatureData.body(body_name), points)
	return editor


func test_the_hud_has_one_ease_node_and_the_tools_are_reachable() -> void:
	open_hud()
	check(hud.ease != null and hud.ease.get_script() == Ease, "the HUD made its editor-ease node")
	check_eq(hud.find_children("EditorEase", "", false, false).size(), 1, "exactly one, as a child of the HUD")
	hud.wire()
	check_eq(hud.find_children("EditorEase", "", false, false).size(), 1, "a second wire() makes no second one")
	check(hud.tool_button("eye") != null and hud.tool_button("eye").text.begins_with("Eye"), "tool_button finds the Eye tool")
	check(hud.tool_button("limb") != null, "and the limb tool")
	check(hud.tool_button("tentacle") == null, "an unknown tool is null")


func test_undo_and_redo_name_their_bindings_and_say_when_there_is_nothing() -> void:
	open_hud()
	hud.set_undo_redo(false, false)
	check_eq(hud.undo_button.tooltip_text, Ease.NOTHING_TO_UNDO, "a disabled Undo says why")
	check_eq(hud.redo_button.tooltip_text, Ease.NOTHING_TO_REDO, "a disabled Redo says why")
	hud.set_undo_redo(true, true)
	var undo_keys := ShortcutText.label(&"ui_undo")
	var redo_keys := ShortcutText.label(&"ui_redo")
	check(not undo_keys.is_empty() and not redo_keys.is_empty(), "the engine binds ui_undo and ui_redo (%s, %s)" % [undo_keys, redo_keys])
	check_eq(hud.undo_button.tooltip_text, "%s (%s)" % [Ease.UNDO_WORDS, undo_keys], "Undo names its binding")
	check_eq(hud.redo_button.tooltip_text, "%s (%s)" % [Ease.REDO_WORDS, redo_keys], "Redo names its bindings")
	# Every key the tooltip names comes from InputMap, not from a constant.
	for e in InputMap.action_get_events(&"ui_undo"):
		if e is InputEventKey:
			check(hud.undo_button.tooltip_text.contains(ShortcutText.key_text(e)), "Undo names %s" % ShortcutText.key_text(e))


func test_the_dock_buttons_say_what_they_do_in_plain_words() -> void:
	open_hud()
	for button_name in Ease.DOCK_TIPS:
		var b: Control = hud.get_node("%" + button_name)
		check_eq(b.tooltip_text, Ease.DOCK_TIPS[button_name], "%s has its tooltip" % button_name)
		for key in ["Ctrl", "Esc", "Enter", "Del ", "Ins ", "M ", "T "]:
			check(not b.tooltip_text.contains(key), "%s names no hardcoded key (%s)" % [button_name, key])


func test_the_editor_drives_the_undo_tooltips() -> void:
	open_editor()
	check_eq(editor.hud.undo_button.tooltip_text, Ease.NOTHING_TO_UNDO, "nothing to undo on a fresh visit")
	editor.insert_after_selected()
	check(editor.hud.undo_button.tooltip_text.begins_with(Ease.UNDO_WORDS), "after an edit Undo is live (%s)" % editor.hud.undo_button.tooltip_text)
	editor.undo()
	check(editor.hud.redo_button.tooltip_text.begins_with(Ease.REDO_WORDS), "after an undo Redo is live")
	check_eq(editor.hud.undo_button.tooltip_text, Ease.NOTHING_TO_UNDO, "and Undo has nothing left")
