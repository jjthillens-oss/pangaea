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
const StatsRows := preload("res://game/ui/editor_ease/stats_rows.gd")

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


## A body point inside the back between the fifth and sixth vertebrae, as tests/test_creature_editor_scene.gd aims.
static func back_point(desc: RefCounted, up := 0.7) -> Vector3:
	return (desc.position_m(4) + desc.position_m(5)) * 0.5 + Vector3(0.0, up * desc.radius_m(4), 0.0)


func test_stat_lines_parse_into_rows_and_compare_with_a_shape_and_a_sign() -> void:
	var lines := PackedStringArray(["Length  1.31 m", "Legs  4   ·   limbs  4", "Speed  3.7 m/s   ·   health  132",
			"a line the editor may add", "Selected  part p3"])
	var parsed := StatsRows.parse(lines)
	var names := PackedStringArray()
	for row: Dictionary in parsed["rows"]:
		names.append(row["name"])
	check_eq(names, PackedStringArray(["Length", "Legs", "Limbs", "Speed", "Health", "a line the editor may add"]),
			"one row per stat, two on a line split apart, an unknown line kept raw")
	check_eq(parsed["selected"], "part p3", "the selection is split off")
	check(bool(parsed["rows"][5].get("raw", false)), "the unknown line is a raw row")
	var later := StatsRows.parse(PackedStringArray(["Length  1.45 m", "Legs  4   ·   limbs  4",
			"Speed  3.4 m/s   ·   health  140"]))
	var rows := StatsRows.compare(later["rows"], parsed["rows"])
	var changes := {}
	for row: Dictionary in rows:
		changes[row["key"]] = row["change"]
	check_eq(changes["length"], "+0.14 m", "a longer body is a plain change: a sign, no better/worse mark")
	check_eq(changes["legs"], "", "an unchanged stat shows nothing")
	check_eq(changes["speed"], "▼ -0.3 m/s", "slower is worse: a down triangle and the sign")
	check_eq(changes["health"], "▲ +8", "more health is better: an up triangle")


func test_the_stats_panel_replaces_the_text_block_and_unknown_lines_stay_readable() -> void:
	open_hud()
	hud.set_stats(PackedStringArray(["Length  1.31 m", "Mass  73.9 kg", "Selected  -"]))
	var panel: Control = hud.ease.stats
	check(panel.visible and not hud.stats_text.visible, "the table shows and the old text block hides")
	check(panel.get_index() < hud.stats_text.get_index(), "the table sits where the text was, before it")
	check_eq(panel.row_texts(), PackedStringArray(["Length 1.31 m", "Mass 73.9 kg"]), "a row per stat")
	check_eq(panel.selected_label.text, "Selected: nothing", "no selection in words")
	hud.set_stats(PackedStringArray(["Length  1.40 m", "Mass  73.9 kg", "Selected  -"]))
	check_eq(panel.row("length")["change"], "+0.09 m", "the change since the first stats of the visit")
	hud.set_stats(PackedStringArray(["something new"]))
	check(not panel.visible and hud.stats_text.visible and hud.stats_text.text == "something new",
			"lines it cannot read leave the editor's own text showing")


func test_the_editor_stats_show_changes_since_the_visit_began() -> void:
	open_editor()
	var panel: Control = editor.hud.ease.stats
	for key in ["length", "mass", "speed", "bite", "sight"]:
		check(not panel.row(key).is_empty(), "a %s row" % key)
	check(panel.row_texts().size() >= 10, "every stat on its own row (%d)" % panel.row_texts().size())
	for t in panel.row_texts():
		check(not t.contains("▲") and not t.contains("▼") and not t.contains("+"), "no change marks on arrival (%s)" % t)
	editor.insert_after_selected()
	var length: Dictionary = panel.row("length")
	check_eq(length["value"], "%.2f m" % float(editor.session.preview()["phenotype"]["length_m"]),
			"the Length row shows the editor's length")
	check(length["change"].begins_with("+"), "a vertebra more makes it longer (%s)" % length["change"])
	check(not length["change"].contains("▲") and not length["change"].contains("▼"), "length is a plain change")
	editor.undo()
	for t in panel.row_texts():
		check(not t.contains("▲") and not t.contains("▼") and not t.contains("+"), "no change marks after the undo (%s)" % t)
	editor.offer_presets(true)
	editor.start_from_preset(CreatureData.preset_names()[0])
	for t in panel.row_texts():
		check(not t.contains("▲") and not t.contains("▼") and not t.contains("+"), "a preset starts the count afresh (%s)" % t)


func test_the_selection_is_named_in_words() -> void:
	open_editor()
	var desc = editor.working_body()
	editor.choose_tool("eye")
	var r: Dictionary = editor.click_skin(editor.screen_of(back_point(desc)))
	check(r["ok"], "an eye added: %s" % r.get("reason", ""))
	var label: Label = editor.hud.ease.stats.selected_label
	var eye: Dictionary = editor.working_body().parts.filter(func(p): return p["id"] == editor.selected["id"])[0]
	check_eq(label.text, "Selected: eye" + (" (a mirrored pair)" if eye["mirror"] else ""), "the new eye by its name")
	editor.choose_tool("")
	var v_id := String(desc.vertebrae[2]["id"])
	editor.press(editor.handle_screen("vertebra", v_id))
	editor.release()
	check(editor.selected.get("id", "") == v_id, "the third vertebra's handle picked")
	check_eq(label.text, "Selected: vertebra 3 of %d from the head" % desc.vertebrae.size(), "a vertebra by its place")
