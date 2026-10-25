extends TestCase
## Editor-ease in the cell editor (game/ui/cell_editor.gd, game/ui/editor_ease/; docs/proposals/editor-ease.md):
## one Undo takes back one action, a whole drag round the rim included, and Undo, Redo and Back name the keys
## bound to them (Bible 12 undo and redo; Bible 19 inputs shown from the bindings).

const UndoSteps := preload("res://game/ui/editor_ease/undo_steps.gd")
const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")

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
