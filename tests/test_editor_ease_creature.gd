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
const Effects := preload("res://game/ui/editor_ease/creature_effects.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")
const Stats := preload("res://game/domain/creature/creature_stats.gd")
const PlacementHint := preload("res://game/ui/editor_ease/placement_hint.gd")

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
	check(hud.editor_ease != null and hud.editor_ease.get_script() == Ease, "the HUD made its editor-ease node")
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
	var panel: Control = hud.editor_ease.stats
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
	var panel: Control = editor.hud.editor_ease.stats
	for key in ["length", "mass", "speed", "health", "bite", "sight", "legs", "limbs", "parts", "bones"]:
		check(not panel.row(key).is_empty(), "the %s stat is shown" % key)
	for word in ["legs", "limbs", "parts", "bones"]:
		check(panel.counts_label.text.contains(word), "the counts line names the %s" % word)
	check_eq(panel.grid.get_child_count(), 3 * 7, "a header and a row each for length, mass, speed, health, bite and sight")
	for t in panel.row_texts():
		check(not t.contains("▲") and not t.contains("▼") and not t.contains("+"), "no change marks on arrival (%s)" % t)
	editor.insert_after_selected()
	var length: Dictionary = panel.row("length")
	check_eq(length["value"], "%.2f m" % float(editor.session.preview()["phenotype"]["length_m"]),
			"the Length row shows the editor's length")
	check(length["change"].begins_with("+"), "a vertebra more makes it longer (%s)" % length["change"])
	check(not length["change"].contains("▲") and not length["change"].contains("▼"), "length is a plain change")
	check(panel.counts_label.text.contains("bones (+1)"), "the counts lines show the bone more (%s)" % panel.counts_label.text)
	check_eq(panel.counts_label.text.split("\n").size(), 2, "legs and limbs on one line, parts and bones on the next")
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
	var label: Label = editor.hud.editor_ease.stats.selected_label
	var eye: Dictionary = editor.working_body().parts.filter(func(p): return p["id"] == editor.selected["id"])[0]
	check_eq(label.text, "Selected: eye" + (" (a pair)" if eye["mirror"] else ""), "the new eye by its name")
	editor.choose_tool("")
	var v_id := String(desc.vertebrae[2]["id"])
	editor.press(editor.handle_screen("vertebra", v_id))
	editor.release()
	check(editor.selected.get("id", "") == v_id, "the third vertebra's handle picked")
	check_eq(label.text, "Selected: vertebra 3 of %d from the head" % desc.vertebrae.size(), "a vertebra by its place")


func _card_has(card_texts: PackedStringArray, piece: String) -> bool:
	for t in card_texts:
		if t.contains(piece):
			return true
	return false


func test_hovering_a_tool_opens_the_part_card_in_place_of_the_engine_tooltip() -> void:
	open_hud()
	var eye := hud.tool_button("eye")
	eye.tooltip_text = "Eye, 10 points"   # as set_tool_icon writes it
	eye.mouse_entered.emit()
	var card: Control = hud.editor_ease.card
	check(card.visible, "the card opens on hover")
	var price := int((CreatureData.editor_costs()["part"] as Dictionary).get("eye", CreatureData.editor_costs()["part_default"]))
	var texts: PackedStringArray = card.texts()
	check_eq(texts[0], "Eye · %d points" % price, "its title names the part and its price")
	check(_card_has(texts, "a mirrored pair %d" % (2 * price)), "and the price of a mirrored pair (%s)" % ", ".join(texts))
	check(_card_has(texts, "Sight"), "an eye's card shows the sight it adds")
	check_eq(eye.tooltip_text, "", "the engine's tooltip, which covered the tool's name, is not shown")
	check_eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the card never takes the mouse")
	eye.mouse_exited.emit()
	check(not card.visible, "and closes when the pointer leaves")
	hud.tool_button("").mouse_entered.emit()
	check(card.visible and card.texts()[0] == "Select", "Select has a card too")
	hud.tool_button("limb").mouse_entered.emit()
	check(card.texts()[0].begins_with("Limb · %d" % int(hud.tool_button("limb").get_meta("price"))), "and the limb tool")


func test_the_card_tells_what_each_kind_of_part_does() -> void:
	open_hud()
	var rules := CreatureData.part_rules()
	var body: RefCounted = CreatureData.body("s1_quadruped")
	var mouthless: RefCounted = BodyCodec.from_dict(body.to_dict())
	mouthless.parts = mouthless.parts.filter(func(p): return String(rules.get(p["type"], {}).get("role", "")) != "mouth")
	var tuning := CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")
	var gait := CreatureData.gait_table()
	var size: float = (body.bounds_m() as AABB).get_longest_axis_size()
	for type in rules:
		var role := String(rules[type].get("role", ""))
		var fx := Effects.effects(mouthless, type, rules, gait, tuning, CreatureData.rules(), size)
		var c := Effects.card(type, rules[type], fx, {"price": 10})
		var texts := PackedStringArray()
		for line: Array in c["lines"]:
			texts.append(" ".join(line.map(func(x): return str(x))))
		check(not texts.is_empty() and not texts[0].is_empty(), "%s has a card" % type)
		match role:
			"weapon":
				check(_card_has(texts, Effects.NEEDS_MOUTH), "a %s on a mouthless body says it needs a mouth" % type)
			"foot", "hand":
				check(_card_has(texts, Effects.NO_STAT_CHANGE), "a %s changes the look only" % type)
			"mouth":
				check(_card_has(texts, "Bite"), "a %s adds bite" % type)
			"detail":
				check(_card_has(texts, "Charm"), "a %s adds charm" % type)
			"eye":
				check(_card_has(texts, "Sight"), "a %s adds sight" % type)
	hud.set_locked({"eye": true})
	hud.tool_button("eye").mouse_entered.emit()
	check(_card_has(hud.editor_ease.card.texts(), Effects.LOCKED), "a locked part says where to find it")


## Bible 14: the card's preview asks the same rules as the action. An eye added by a real click, and a mirrored pair
## of eyes added with the editor's own picking rules, give exactly the sight the card predicted.
func test_the_card_predicts_the_sight_an_eye_really_gives() -> void:
	open_editor()
	var tuning := CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")
	var rules := CreatureData.part_rules()
	var size: float = (CreatureData.body("s1_quadruped").bounds_m() as AABB).get_longest_axis_size()
	var fx := Effects.effects(editor.working_body(), "eye", rules, CreatureData.gait_table(), tuning, CreatureData.rules(), size)
	editor.hud.tool_button("eye").mouse_entered.emit()
	var predicted := PackedStringArray()
	for t in editor.hud.editor_ease.card.texts():
		if t.begins_with("Sight") or t.begins_with(Effects.PAIR_LABEL):
			predicted.append(t)
	check_eq(predicted.size(), 2, "the card shows one eye's and a pair's sight (%s)" % ", ".join(editor.hud.editor_ease.card.texts()))
	check(predicted[0].contains("%.0f m" % float(fx["one"]["sight_m"])) and predicted[1].contains("%.0f m" % float(fx["pair"]["sight_m"])),
			"the card's numbers are the effects' (%s)" % ", ".join(predicted))
	editor.choose_tool("eye")
	var r: Dictionary = editor.click_skin(editor.screen_of(back_point(editor.working_body())))
	check(r["ok"], "an eye added by a click: %s" % r.get("reason", ""))
	var eye: Dictionary = editor.working_body().parts.filter(func(p): return p["id"] == editor.selected["id"])[0]
	var got := Stats.of(editor.working_body(), rules, CreatureData.gait_table(), tuning)
	check_eq(got["sight_m"], fx["pair" if eye["mirror"] else "one"]["sight_m"], "the clicked eye gives the predicted sight")
	editor.undo()
	var desc = editor.working_body()
	var a: Dictionary = Picking.anchor_for_part(desc, rules["eye"], {"host": "spine", "u": 200, "ring": 250, "elev": 0})
	check(bool(a.get("mirror", false)), "a side spot gives a pair")
	a["scale"] = Picking.fit_scale(desc, size, CreatureData.rules())
	check(editor.session.add_part("eye", a)["ok"], "a pair of eyes added the editor's way")
	got = Stats.of(editor.working_body(), rules, CreatureData.gait_table(), tuning)
	check_eq(got["sight_m"], fx["pair"]["sight_m"], "the pair gives the predicted sight")


func test_a_stat_name_explains_itself_on_the_card() -> void:
	open_editor()
	var panel: Control = editor.hud.editor_ease.stats
	var tuning := CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")
	panel.stat_entered.emit("sight", panel)
	var texts: PackedStringArray = editor.hud.editor_ease.card.texts()
	check(editor.hud.editor_ease.card.visible and texts[0] == "Sight", "the card names the stat")
	check(_card_has(texts, "%d m at most" % int(tuning["sight"]["max_m"])), "with the stage's own numbers (%s)" % ", ".join(texts))
	panel.stat_exited.emit("sight")
	check(not editor.hud.editor_ease.card.visible, "and closes")
	panel.stat_entered.emit(panel.COUNTS_KEY, panel.counts_label)
	check_eq(editor.hud.editor_ease.card.texts()[0], "Legs, limbs, parts, bones", "the counts line explains itself too")
	panel.stat_entered.emit(panel.CHANGE_KEY, panel)
	check(_card_has(editor.hud.editor_ease.card.texts(), "since you came into the editor"), "and the CHANGE header says what it counts from")


func test_every_part_has_a_placement_hint() -> void:
	var rules := CreatureData.part_rules()
	check(rules.size() > 0, "part rules to check")
	for type in rules:
		check(not PlacementHint.creature(rules[type]).is_empty(), "%s has a hint" % type)
	check(not PlacementHint.limb_tool().is_empty(), "the limb tool has a hint")
	check_eq(PlacementHint.snap_degrees(), roundi(Picking.MIDDLE_SNAP * 0.36), "the snap angle is the editor's own")


## The hint's words about one or a pair are what EditorPicking does with a click at the side and near the middle.
func test_the_hint_says_what_a_click_will_do_about_pairs() -> void:
	var rules := CreatureData.part_rules()
	var desc: RefCounted = CreatureData.body("s1_quadruped")
	var side := {"host": "spine", "u": 200, "ring": 250, "elev": 0}
	var near_middle := {"host": "spine", "u": 200, "ring": Picking.MIDDLE_SNAP - 5, "elev": 0}
	var seen := {}
	for type in rules:
		var rule: Dictionary = rules[type]
		var centerline := String(rule.get("centerline", ""))
		if not (rule["hosts"] as Array).has("spine") or seen.has(centerline):
			continue
		seen[centerline] = true
		var hint := PlacementHint.creature(rule)
		var at_side: bool = Picking.anchor_for_part(desc, rule, side)["mirror"]
		var at_middle: bool = Picking.anchor_for_part(desc, rule, near_middle)["mirror"]
		match centerline:
			"required":
				check(hint.contains("never a pair") and not at_side and not at_middle, "%s: one, never a pair" % type)
			"forbidden":
				check(hint.contains("mirrored pair") and at_side and at_middle, "%s: always a pair" % type)
			"allowed":
				check(hint.contains("%d°" % PlacementHint.snap_degrees()) and at_side and not at_middle,
						"%s: a pair at the side, one near the middle line" % type)
	check_eq(seen.size(), 3, "a part of each middle-line rule was checked (%s)" % str(seen.keys()))


func test_the_placement_line_follows_the_tool_and_hides_for_none_and_the_test_drive() -> void:
	open_hud()
	var row: Control = hud.editor_ease.snap_hint
	check(row.get_parent() == hud.get_node("Bottom") and row.get_index() < hud.get_node("Bottom/DockCenter").get_index(),
			"the line sits just above the dock")
	var pill_bg := (row.get_child(0) as Control).get_theme_stylebox(&"panel") as StyleBoxFlat
	check(pill_bg != null and pill_bg.bg_color.a >= 0.95, "the pill is opaque enough to read over the creature")
	check(not row.visible, "hidden with no tool")
	hud.set_tool("eye")
	check(row.visible and hud.editor_ease.snap_label.text.begins_with("Eye  ·  Click the head or body"), "the eye's line (%s)" % hud.editor_ease.snap_label.text)
	hud.set_tool("limb")
	check_eq(hud.editor_ease.snap_label.text, "Limb  ·  " + PlacementHint.limb_tool(), "the limb tool's line")
	hud.set_test_drive(true)
	hud.editor_ease._process(0.0)
	check(not row.visible, "hidden during the test drive")
	hud.set_test_drive(false)
	hud.editor_ease._process(0.0)
	check(row.visible, "back after it")
	hud.set_tool("")
	check(not row.visible, "hidden again with no tool")
	hud.tool_button("eye").mouse_entered.emit()
	check(_card_has(hud.editor_ease.card.texts(), PlacementHint.creature(CreatureData.part_rules()["eye"])), "the card says where it goes too")


func test_the_symmetry_toggle_shows_only_when_the_editor_listens() -> void:
	hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.wire()
	var button: Button = hud.editor_ease.symmetry_button
	check(button.get_parent() == hud.get_node("%Mirror").get_parent() and button.get_index() == hud.get_node("%Mirror").get_index() + 1,
			"the toggle sits after Mirror in the dock")
	hud.setup(["eye"], CreatureData.editor_costs(), [Color.RED])
	check(not button.visible, "hidden while nothing listens: no dead control ships")
	var got := []
	hud.symmetry_toggled.connect(func(on: bool): got.append(on))
	hud.setup(["eye"], CreatureData.editor_costs(), [Color.RED])
	check(button.visible, "shown once the editor connects symmetry_toggled before setup")
	check_eq(button.focus_mode, Control.FOCUS_NONE, "it takes no focus, so Enter and Escape reach the editor")
	button.button_pressed = true
	check_eq(button.text, "Symmetry: on", "its state in words")
	button.button_pressed = false
	check_eq(got, [true, false], "a press emits the new state")
	hud.set_symmetry(true)
	check(button.button_pressed and button.text == "Symmetry: on", "set_symmetry shows the state")
	check_eq(got, [true, false], "without emitting")


func test_the_editor_does_not_listen_to_symmetry_yet_so_the_toggle_stays_hidden() -> void:
	open_editor()
	check_eq(editor.hud.editor_ease.symmetry_button.visible, not editor.hud.symmetry_toggled.get_connections().is_empty(),
			"the toggle shows exactly when the editor connects it (GitHub issue #204)")


## While the editor listens to the Symmetry toggle, the placement line and the card follow it: off, a part off the
## middle line comes alone and the card shows no pair.
func test_the_placement_line_and_the_card_follow_the_symmetry_switch() -> void:
	hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.wire()
	hud.symmetry_toggled.connect(func(_on: bool): pass)
	hud.setup(["eye", "antenna"], CreatureData.editor_costs(), [Color.RED])
	var rules := CreatureData.part_rules()
	hud.set_symmetry(true)
	hud.set_tool("eye")
	check(hud.editor_ease.snap_label.text.contains("mirrored pair"), "on: a pair further out (%s)" % hud.editor_ease.snap_label.text)
	hud.set_symmetry(false)
	check_eq(hud.editor_ease.snap_label.text, "Eye  ·  " + PlacementHint.creature(rules["eye"], false), "off: the line changes at once")
	check(hud.editor_ease.snap_label.text.contains("alone") and not hud.editor_ease.snap_label.text.contains("mirrored pair"), "off: alone")
	hud.tool_button("eye").mouse_entered.emit()
	check(not _card_has(hud.editor_ease.card.texts(), Effects.PAIR_LABEL), "off: the card shows no pair (%s)" % ", ".join(hud.editor_ease.card.texts()))
	hud.set_tool("limb")
	check_eq(hud.editor_ease.snap_label.text, "Limb  ·  " + PlacementHint.limb_tool(false), "off: a limb comes alone")
	hud.editor_ease.symmetry_button.button_pressed = true
	check_eq(hud.editor_ease.snap_label.text, "Limb  ·  " + PlacementHint.limb_tool(true), "pressing the toggle switches the line back")
