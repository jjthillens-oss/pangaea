extends TestCase
## Editor-ease in the cell editor (game/ui/cell_editor.gd, game/ui/editor_ease/; docs/proposals/editor-ease.md):
## one Undo takes back one action, a whole drag round the rim included; Undo, Redo and Back name the keys bound to
## them; with Symmetry on a part and its twin are added, changed and removed as one; a drag snaps; and the part card
## shows what a part does by the game's own rules (Bible 12 undo, redo, mirroring and one stats rule; Bible 14
## previews; Bible 19 inputs shown from the bindings, states in words and shapes).

const UndoSteps := preload("res://game/ui/editor_ease/undo_steps.gd")
const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")
const Sym := preload("res://game/ui/editor_ease/cell_symmetry.gd")
const PartCard := preload("res://game/ui/editor_ease/part_card.gd")

var catalog: PartCatalog
var save: SaveGame
var editor: CellEditor


func before_each() -> void:
	catalog = PartCatalog.load_from()
	save = SaveGame.new_run(99, "test+dev")
	save.genome.add_part("mouth_filter", 0.0)
	save.genome.add_part("flagellum", PI)
	save.adaptation_points = 100
	editor = CellEditor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)


func after_each() -> void:
	editor.free()


func _state() -> ActorState:
	var s := ActorState.fresh(Phenotype.derive(save.genome, catalog))
	s.energy = s.energy_capacity
	return s


func _rim() -> CellEditor.RimView:
	var rim: CellEditor.RimView = editor.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is CellEditor.RimView)[0]
	rim.set_anchors_preset(Control.PRESET_TOP_LEFT)   # out of a live tree it has no laid-out size
	rim.size = Vector2(400, 400)
	return rim


func _press(rim: CellEditor.RimView, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	rim._gui_input(e)


func _move(rim: CellEditor.RimView, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	rim._gui_input(e)


func _angle(part_id: String) -> float:
	for p in editor.session.working.parts:
		if str(p.id) == part_id:
			return float(p.angle)
	return NAN


## Drags part `part_id` round the rim from where it is to `to`, in `motions` mouse moves.
func _drag(part_id: String, to: float, motions := 5) -> void:
	var rim := _rim()
	var from := _angle(part_id)
	_press(rim, rim.at(from), true)
	for i in motions:
		_move(rim, rim.at(lerp_angle(from, to, (i + 1.0) / motions)))
	_press(rim, rim.at(to), false)


func test_a_drag_round_the_rim_is_one_undo_step() -> void:
	editor.open(save, catalog, _state())
	editor.add("eye_spot")
	var eye := editor.selected
	var before := _angle(eye)
	_drag(eye, before - 1.0)
	var after := _angle(eye)
	check(absf(angle_difference(after, before - 1.0)) < 0.02, "dragged to the end (%.3f)" % after)
	check(editor.session.can_undo(), "the drag can be undone")
	editor.undo()
	check_near(_angle(eye), before, 1e-6, "one Undo puts it back where the drag began")
	check_eq(editor.session.working.parts.size(), 3, "and keeps the part that was added before the drag")
	editor.redo()
	check_near(_angle(eye), after, 1e-6, "one Redo puts it at the drag's end")
	editor.undo()
	editor.undo()
	check_eq(editor.session.working.parts.size(), 2, "a second Undo takes the added part off")
	check(not editor.session.can_undo(), "and nothing is left to undo")


func test_a_click_without_a_drag_leaves_nothing_to_undo_and_ops_stay_one_step_each() -> void:
	editor.open(save, catalog, _state())
	var rim := _rim()
	var mouth := str(editor.session.working.parts[0].id)
	_press(rim, rim.at(_angle(mouth)), true)
	_press(rim, rim.at(_angle(mouth)), false)
	check_eq(editor.selected, mouth, "the click picks the part")
	check(not editor.session.can_undo(), "a pick alone is no change")
	editor.add("cilia")
	check(editor.resize_selected(CellEditor.SCALE_STEP).ok, "bigger")
	check(editor.move_selected(1.0).ok, "moved")
	var cilia := editor.selected
	editor.undo()
	check(absf(_angle(cilia) - 1.0) > 1e-3, "the move is undone alone")
	check_eq(float(editor.session.working.parts[-1].scale), 1.0 + CellEditor.SCALE_STEP, "the resize stays")
	editor.undo()
	check_eq(float(editor.session.working.parts[-1].scale), 1.0, "then the resize")
	editor.undo()
	check_eq(editor.session.working.parts.size(), 2, "then the add")


func test_an_undo_in_mid_drag_ends_the_drag() -> void:
	editor.open(save, catalog, _state())
	editor.add("eye_spot")
	var eye := editor.selected
	var before := _angle(eye)
	var rim := _rim()
	_press(rim, rim.at(before), true)
	for i in 3:
		_move(rim, rim.at(before - 0.2 * (i + 1)))
	editor.undo()
	check_near(_angle(eye), before, 1e-6, "the drag so far is undone in one")
	_move(rim, rim.at(before - 1.0))
	check_near(_angle(eye), before, 1e-6, "and a later move does not drag the part on")
	_press(rim, rim.at(before - 1.0), false)


func test_undo_steps_group_and_drop_redo_like_the_session() -> void:
	var s := EditorSession.new(save.genome, catalog, 100)
	var steps := UndoSteps.new()
	var eye_ok: bool = s.add_part("eye_spot", 1.0).ok
	steps.note(eye_ok)
	var eye := str(s.working.parts[-1].id)
	steps.begin_group()
	for a in [1.1, 1.2, 1.3]:
		steps.note(s.move_part(eye, a).ok)
	steps.note(false)   # a refused op makes no step
	steps.end_group()
	check_eq(steps.undo_count(), 2, "the add and the drag")
	check(steps.undo(s), "undo")
	check_near(float(s.working.parts[-1].angle), 1.0, 1e-6, "the whole drag")
	check(steps.redo(s), "redo")
	check_near(float(s.working.parts[-1].angle), 1.3, 1e-6, "the whole drag again")
	steps.undo(s)
	steps.note(s.move_part(eye, 2.0).ok)
	check(not steps.redo(s) and not s.can_redo(), "a new step drops the redo, as the session does")


func test_undo_redo_and_back_name_their_bindings() -> void:
	editor.open(save, catalog, _state())
	var undo := editor.find_child("Undo", true, false) as Button
	var redo := editor.find_child("Redo", true, false) as Button
	check_eq(undo.text, "Undo", "the button keeps its name")
	check(undo.disabled and undo.tooltip_text == CellEditor.NO_UNDO_TIP, "nothing to undo: " + undo.tooltip_text)
	check(redo.disabled and redo.tooltip_text == CellEditor.NO_REDO_TIP, "nothing to redo: " + redo.tooltip_text)
	editor.add("cilia")
	var undo_keys := ShortcutText.label(&"ui_undo")
	check(not undo_keys.is_empty(), "undo has a binding")
	check(undo.tooltip_text.contains(undo_keys), "the Undo tooltip names %s: %s" % [undo_keys, undo.tooltip_text])
	editor.undo()
	var redo_keys := ShortcutText.label(&"ui_redo")
	check(redo.tooltip_text.contains(redo_keys), "the Redo tooltip names %s: %s" % [redo_keys, redo.tooltip_text])
	var line := (editor.find_child("KeyLine", true, false) as Label).text
	for pair: Array in CellEditor.KEY_LINE:
		var names := ShortcutText.for_action(pair[0])
		if not names.is_empty():
			check(line.contains("%s  %s" % [names[0], pair[1]]), "the key line has %s: %s" % [pair[1], line])


func _parts_of(type_id: String) -> Array:
	return editor.session.working.parts.filter(func(p: Dictionary) -> bool: return str(p.type) == type_id)


func test_symmetry_is_off_by_default_and_an_add_is_one_part() -> void:
	editor.open(save, catalog, _state())
	check(not editor.symmetry, "off by default (PROPOSED)")
	check_eq((editor.find_child("Symmetry", true, false) as Button).text, "Symmetry: off", "the toggle says so in words")
	editor.add("eye_spot")
	check_eq(_parts_of("eye_spot").size(), 1, "one eye spot")


func test_with_symmetry_a_part_and_its_twin_are_added_changed_and_removed_as_one() -> void:
	editor.open(save, catalog, _state())
	var toggle := editor.find_child("Symmetry", true, false) as Button
	toggle.button_pressed = true   # the player's toggle
	check(editor.symmetry and toggle.text == "Symmetry: on", "on: " + toggle.text)
	check(editor.add("eye_spot").ok, "added")
	var eyes := _parts_of("eye_spot")
	check_eq(eyes.size(), 2, "an eye spot and its twin")
	check(absf(sin(float(eyes[0].angle))) > 0.5, "off the middle line (%.2f)" % eyes[0].angle)
	check_near(float(eyes[1].angle), -float(eyes[0].angle), 1e-6, "at the mirrored angle")
	check_eq(editor.session.cost(), 2 * catalog.cost_of("eye_spot"), "the pair costs two eye spots")
	check_eq(str(editor.selected_twin().id), str(eyes[1].id), "the selected part knows its twin")
	editor.undo()
	check_eq(_parts_of("eye_spot").size(), 0, "one Undo takes both off")
	editor.redo()
	check_eq(_parts_of("eye_spot").size(), 2, "one Redo puts both back")
	editor.selected = str(_parts_of("eye_spot")[0].id)
	check(editor.move_selected(1.0).ok, "moved")
	check_near(_angle(editor.selected), 1.0, 1e-6, "to the angle")
	check_near(float(editor.selected_twin().angle), -1.0, 1e-6, "and the twin to its mirror")
	check(editor.resize_selected(CellEditor.SCALE_STEP).ok, "bigger")
	for p: Dictionary in _parts_of("eye_spot"):
		check_eq(float(p.scale), 1.0 + CellEditor.SCALE_STEP, "both bigger")
	var upgrade := editor.find_child("Upgrade", true, false) as Button
	var price := catalog.upgrade_cost("eye_spot", 1)
	check(upgrade.text.ends_with(str(2 * price)), "the Upgrade button shows the pair's price: " + upgrade.text)
	var cost_before := editor.session.cost()
	check(editor.upgrade_selected().ok, "upgraded")
	for p: Dictionary in _parts_of("eye_spot"):
		check_eq(Genome.level_of(p), 2, "both a level up")
	check_eq(editor.session.cost() - cost_before, 2 * price, "and both are paid for")
	editor.undo()
	check_eq(Genome.level_of(_parts_of("eye_spot")[1]), 1, "one Undo takes back both upgrades")
	editor.redo()
	check(not editor.mirror_selected().ok, "a part that has its twin is not mirrored again")
	check(editor.remove_selected().ok, "removed")
	check_eq(_parts_of("eye_spot").size(), 0, "with its twin")
	editor.undo()
	check_eq(_parts_of("eye_spot").size(), 2, "and one Undo brings both back")


func test_with_symmetry_a_mouth_stays_single_and_a_pair_keeps_off_the_middle_line() -> void:
	editor.open(save, catalog, _state())
	editor.set_symmetry(true)
	editor.add("mouth_jaw")
	check_eq(_parts_of("mouth_jaw").size(), 1, "a mouth on the middle line has no twin")
	check(editor.selected_twin().is_empty(), "and none is selected")
	editor.add("cilia")
	var cilia := editor.selected
	check_eq(_parts_of("cilia").size(), 2, "cilia off the middle line come as a pair")
	editor.move_selected(0.01)
	check_near(_angle(cilia), Sym.PAIR_EDGE, 1e-6, "a pair stops just off the front")
	check_near(float(editor.selected_twin().angle), -Sym.PAIR_EDGE, 1e-6, "and so does its twin")
	editor.move_selected(-1.2)
	check_near(_angle(cilia), -1.2, 1e-6, "across the line it goes to the other side")
	check_near(float(editor.selected_twin().angle), 1.2, 1e-6, "and the twin comes over to this one")


func test_with_symmetry_a_twin_that_does_not_fit_leaves_one_part_and_says_why() -> void:
	editor.open(save, catalog, _state())
	editor.set_symmetry(true)
	editor.add("eye_spot")
	var result := editor.add("eye_spot")
	check(result.ok, "the third eye spot fits")
	check_eq(_parts_of("eye_spot").size(), catalog.max_count_of("eye_spot"), "but not its twin")
	var status := (editor.find_child("Status", true, false) as Label).text
	check(status.begins_with("No room for its pair") and status.contains("limit"), "the status line says why: " + status)
	editor.undo()
	check_eq(_parts_of("eye_spot").size(), 2, "one Undo takes the single back")


func test_twins_are_found_by_type_size_level_and_mirrored_angle() -> void:
	var parts := [
		{"id": "p1", "type": "eye_spot", "angle": 1.0, "scale": 1.0},
		{"id": "p2", "type": "eye_spot", "angle": -1.0 + 0.01, "scale": 1.0},
		{"id": "p3", "type": "cilia", "angle": -1.0, "scale": 1.0},
		{"id": "p4", "type": "eye_spot", "angle": -1.0, "scale": 1.5},
		{"id": "p5", "type": "eye_spot", "angle": 0.02, "scale": 1.0},
		{"id": "p6", "type": "eye_spot", "angle": -0.02, "scale": 1.0},
	]
	check_eq(str(Sym.twin_of(parts, parts[0]).get("id", "")), "p2", "same type and size, near the mirror")
	check_eq(str(Sym.twin_of(parts, parts[2]).get("id", "")), "", "no other cilia")
	check(Sym.twin_of(parts, parts[4]).is_empty(), "a part on the middle line has no twin")
	parts[1].level = 2
	check(Sym.twin_of(parts, parts[0]).is_empty(), "nor does one at another level")
	check_near(Sym.off_line(0.01, 1.0), Sym.PAIR_EDGE, 1e-9, "front, right side")
	check_near(Sym.off_line(-0.01, -2.0), -Sym.PAIR_EDGE, 1e-9, "front, left side")
	check_near(Sym.off_line(PI - 0.01, 2.0), PI - Sym.PAIR_EDGE, 1e-9, "back, right side")
	check_near(Sym.off_line(1.0, -2.0), 1.0, 1e-9, "off the line it is left alone")


func test_a_drag_snaps_onto_the_middle_line_or_opposite_its_kind_and_says_so() -> void:
	var parts := [
		{"id": "p1", "type": "eye_spot", "angle": 1.0, "scale": 1.0},
		{"id": "p2", "type": "eye_spot", "angle": 2.0, "scale": 1.0},
		{"id": "p3", "type": "cilia", "angle": -2.5, "scale": 1.0},
	]
	var near_front := Sym.snap(0.03, parts, "p2")
	check(near_front.kind == "centre" and near_front.angle == 0.0, "near the front it snaps onto the line: %s" % near_front)
	var near_back := Sym.snap(-PI + 0.05, parts, "p2")
	check(near_back.kind == "centre" and absf(angle_difference(near_back.angle, PI)) < 1e-9, "and at the back: %s" % near_back)
	var opposite := Sym.snap(-1.0 + 0.05, parts, "p2")
	check(opposite.kind == "twin" and opposite.of == "p1", "opposite the other eye spot: %s" % opposite)
	check_eq(float(opposite.angle), -1.0, "exactly at its mirror")
	var far := Sym.snap(-1.5, parts, "p2")
	check(far.kind == "" and is_equal_approx(far.angle, -1.5), "far from both it stays put: %s" % far)
	check_eq(str(Sym.snap(2.5 + 0.03, parts, "p2").kind), "", "a part of another kind is no twin")
	check_eq(str(Sym.snap(-2.0, parts, "p2").kind), "", "nor is its own mirror")


func test_a_drag_round_the_rim_ends_snapped_with_a_guide_and_a_hint_line() -> void:
	editor.open(save, catalog, _state())
	editor.add("eye_spot")
	var eye := editor.selected
	var hint := editor.find_child("RimHint", true, false) as Label
	check_eq(hint.text, CellEditor.RIM_HINT, "at rest the line says how to move a part")
	var rim := _rim()
	_press(rim, rim.at(_angle(eye)), true)
	for i in 5:
		_move(rim, rim.at(lerp_angle(_angle(eye), 0.03, (i + 1) / 5.0)))
	check_eq(_angle(eye), 0.0, "the pointer near the front leaves the part on the middle line")
	check_eq(hint.text, CellEditor.SNAP_HINTS.centre, "the line says so")
	check_eq(str(rim._snap.get("kind", "")), "centre", "and the rim draws the snapped guide")
	_move(rim, rim.at(1.2))
	check_near(_angle(eye), 1.2, 1e-5, "away from the line it follows the pointer")
	check_eq(hint.text, CellEditor.DRAG_HINT, "and the line says where it would snap")
	_move(rim, rim.at(0.03))
	_press(rim, rim.at(0.03), false)
	check_eq(_angle(eye), 0.0, "released, it stays on the line")
	check_eq(hint.text, CellEditor.RIM_HINT, "and the line is back to how to move a part")
	editor.undo()
	check_near(absf(_angle(eye)), PI / 2.0, 0.01, "one Undo takes the whole snapped drag back")


func test_with_symmetry_a_dragged_pair_stops_off_the_middle_line() -> void:
	editor.open(save, catalog, _state())
	editor.set_symmetry(true)
	editor.add("eye_spot")
	var eye := editor.selected
	var rim := _rim()
	_press(rim, rim.at(_angle(eye)), true)
	for i in 5:
		_move(rim, rim.at(lerp_angle(_angle(eye), 0.03, (i + 1) / 5.0)))
	check_near(absf(_angle(eye)), Sym.PAIR_EDGE, 1e-6, "the pair stops just off the line")
	check_near(float(editor.selected_twin().angle), -_angle(eye), 1e-6, "mirrored")
	check_eq((editor.find_child("RimHint", true, false) as Label).text, CellEditor.SNAP_HINTS.pair_edge, "and says why")
	_press(rim, rim.at(0.03), false)
	editor.undo()
	check_eq(_parts_of("eye_spot").size(), 2, "one Undo takes the drag back and keeps the pair")
	check_near(absf(_angle(eye)), PI / 2.0, 0.01, "where it was")


func _card_texts() -> PackedStringArray:
	return editor.part_card().call("texts")


## The card's stat row for `label` ("Turning 2.5 → 4.0 ▲"), "" when it has none.
func _card_row(label: String) -> String:
	for t in _card_texts():
		if t.begins_with(label + " "):
			return t
	return ""


func test_the_part_card_shows_what_the_part_does_by_the_game_s_own_rules() -> void:
	editor.open(save, catalog, _state())
	check(not editor.part_card().visible, "opening the editor does not open a card")
	var tile := editor.find_child("Add_cilia", true, false) as Button
	check_eq(tile.tooltip_text, "", "no plain tooltip over the tile's name: the card says it")
	tile.mouse_entered.emit()
	check(editor.part_card().visible, "hovering a tile opens its card")
	var copy := Genome.from_dict(editor.session.working.to_dict())
	copy.add_part("cilia", editor.place_angle("cilia"))
	var now := Phenotype.derive(editor.session.working, catalog)
	var then := Phenotype.derive(copy, catalog)
	var turning := _card_row("Turning")
	check(turning.contains("%.1f → %.1f" % [now.turn_rate, then.turn_rate]), "turning before → after as derived: " + turning)
	check(turning.ends_with(PartCard.MARKS[true]), "marked better by shape: " + turning)
	var upkeep := _card_row("Energy use")
	check(upkeep.contains("→ %.2f/s" % then.upkeep) and upkeep.ends_with(PartCard.MARKS[false]), "energy use worse: " + upkeep)
	check_eq(_card_row("Health"), "", "a stat it leaves alone is not listed")
	check(_card_texts()[0].contains(str(catalog.cost_of("cilia"))), "the title has the price: " + _card_texts()[0])
	check(Array(_card_texts()).has("0 of %d on the body now" % catalog.max_count_of("cilia")), "and the count")
	tile.mouse_exited.emit()
	check(not editor.part_card().visible, "leaving the tile closes it")


func test_the_part_card_follows_the_body_and_says_when_the_limit_is_reached() -> void:
	editor.open(save, catalog, _state())
	var tile := editor.find_child("Add_cilia", true, false) as Button
	tile.mouse_entered.emit()
	editor.add("cilia")
	check(Array(_card_texts()).has("1 of 3 on the body now"), "an add updates the open card: %s" % [_card_texts()])
	check(Array(_card_texts()).any(func(t: String) -> bool: return t.begins_with("Copies add less: each extra one gives 60%")),
		"and says a second copy gives less (diminishing_factor %.1f)" % catalog.diminishing_factor)
	var copy := Genome.from_dict(editor.session.working.to_dict())
	copy.add_part("cilia", editor.place_angle("cilia"))
	var then := Phenotype.derive(copy, catalog)
	check(_card_row("Turning").contains("→ %.1f" % then.turn_rate), "the second copy's turning, diminished: " + _card_row("Turning"))
	editor.add("cilia")
	editor.add("cilia")
	var texts := _card_texts()
	check(Array(texts).any(func(t: String) -> bool: return t.contains("Limit reached: 3 of 3")), "at the limit it says so: %s" % [texts])
	check_eq(_card_row("Turning"), "", "and lists no numbers")


func test_with_symmetry_the_part_card_shows_the_pair() -> void:
	editor.open(save, catalog, _state())
	editor.set_symmetry(true)
	(editor.find_child("Add_eye_spot", true, false) as Button).focus_entered.emit()
	check(editor.part_card().visible, "focusing a tile opens its card too")
	var a := editor.place_angle("eye_spot")
	var copy := Genome.from_dict(editor.session.working.to_dict())
	copy.add_part("eye_spot", a)
	copy.add_part("eye_spot", -a)
	var then := Phenotype.derive(copy, catalog)
	check(_card_texts()[0].contains("pair") and _card_texts()[0].contains(str(2 * catalog.cost_of("eye_spot"))),
		"the title prices the pair: " + _card_texts()[0])
	check(_card_row("Sight").contains("→ %.1f" % then.sight), "sight with both eye spots: " + _card_row("Sight"))
	editor.add("eye_spot")
	check_eq(_parts_of("eye_spot").size(), 2, "and the add makes what the card showed")
	check_near(Phenotype.derive(editor.session.working, catalog).sight, then.sight, 1e-6, "with the sight it showed")
