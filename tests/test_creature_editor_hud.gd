extends TestCase
## The creature editor's HUD (game/ui/creature_editor_hud.tscn): one palette button per part type with its cost,
## plus Select and Limb; buttons emit the signals the editor binds to its method twins; the points line reads the
## cost; the refusal line shows and hides; the tool and swatch states follow the editor without emitting.

const HUD_SCENE := preload("res://game/ui/creature_editor_hud.tscn")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")

var hud: CreatureEditorHud


func before_each() -> void:
	hud = HUD_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.wire()


func after_each() -> void:
	hud.free()


func palette(tools: Array = ["eye", "horn", "maw"]) -> void:
	hud.setup(tools, CreatureData.editor_costs(), [Color.RED, Color.GREEN])


func test_the_palette_has_select_limb_and_a_priced_button_per_tool() -> void:
	palette()
	var labels := PackedStringArray()
	for b in hud.tools_grid.get_children():
		labels.append((b as Button).text)
	check_eq(labels, PackedStringArray(["Select", "Limb  24", "Eye  10", "Horn  15", "Maw  10"]), "palette labels and costs")
	check_eq(hud.swatch_row.get_child_count(), 2, "one swatch per colour")
	for b in hud.tools_grid.get_children():
		check((b as Button).focus_mode == Control.FOCUS_NONE, "%s takes no focus, so Enter and Escape reach the editor" % b.text)


func test_buttons_emit_the_signals_the_editor_binds() -> void:
	palette()
	var got := []
	hud.tool_chosen.connect(func(t: String): got.append("tool:" + t))
	hud.action.connect(func(a: String): got.append("action:" + a))
	hud.test_drive_toggled.connect(func(on: bool): got.append("drive:%s" % on))
	hud.color_chosen.connect(func(c: Color): got.append("color:" + c.to_html(false)))
	(hud.tools_grid.get_child(2) as Button).pressed.emit()
	(hud.tools_grid.get_child(0) as Button).pressed.emit()
	for name in ["Undo", "Redo", "Delete", "Insert", "Mirror", "Done", "Back"]:
		(hud.get_node("%" + name) as Button).pressed.emit()
	hud.test_drive_button.toggled.emit(true)
	(hud.swatch_row.get_child(1) as Button).pressed.emit()
	check_eq(got, ["tool:eye", "tool:", "action:undo", "action:redo", "action:delete", "action:insert", "action:mirror",
			"action:done", "action:back", "drive:true", "color:00ff00"], "signals in order")


func test_tool_and_colour_states_follow_without_emitting() -> void:
	palette()
	var emitted := [0]
	hud.tool_chosen.connect(func(_t: String): emitted[0] += 1)
	hud.color_chosen.connect(func(_c: Color): emitted[0] += 1)
	hud.set_tool("horn")
	check((hud.tools_grid.get_child(3) as Button).button_pressed and not (hud.tools_grid.get_child(2) as Button).button_pressed,
			"the horn button is down, the eye button up")
	check(hud.title_text.text.contains("horn"), "the title names the tool (%s)" % hud.title_text.text)
	hud.set_tool("")
	check(not (hud.tools_grid.get_child(3) as Button).button_pressed and hud.title_text.text == "Creature editor", "no tool")
	hud.set_color(Color.GREEN)
	check((hud.swatch_row.get_child(1) as Button).button_pressed and not (hud.swatch_row.get_child(0) as Button).button_pressed,
			"the green swatch is down")
	check_eq(emitted[0], 0, "state setters emit nothing")


func test_points_refusal_and_test_drive_lines() -> void:
	palette()
	hud.set_points(150, 0, true)
	check(hud.points_text.text.contains("150") and hud.cost_text.text == "No changes to pay for", "no cost")
	hud.set_points(150, 25, true)
	check(hud.cost_text.text.contains("25") and hud.cost_text.text.contains("125"), "cost and points left (%s)" % hud.cost_text.text)
	hud.set_points(150, -7, true)
	check(hud.cost_text.text.begins_with("Refund 7"), "a refund (%s)" % hud.cost_text.text)
	hud.set_points(10, 25, false)
	check(hud.cost_text.text.contains("15 more"), "too dear by 15 (%s)" % hud.cost_text.text)
	check(not hud.refusal_panel.visible, "no refusal at first")
	hud.set_refusal("missed the body")
	check(hud.refusal_panel.visible and hud.refusal_text.text == "missed the body", "the refusal shows")
	hud.set_refusal("")
	check(not hud.refusal_panel.visible, "and hides")
	hud.set_test_drive(true)
	check(hud.test_drive_button.button_pressed and hud.test_drive_button.text == "Stop test drive", "driving")
	hud.set_test_drive(false)
	check(not hud.test_drive_button.button_pressed and hud.test_drive_button.text == "Test drive", "editing")
	hud.set_undo_redo(false, true)
	check(hud.undo_button.disabled and not hud.redo_button.disabled, "undo off, redo on")
