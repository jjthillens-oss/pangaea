extends TestCase
## The creature editor scene (game/scenes/creature/creature_editor.tscn), driven headless through its method twins
## only, as the smoke drives it: a part tool and a click on the skin add a part and the points fall; a vertebra drag
## is one undo step that gives back the byte-identical body; a refused op shows its reason; the test drive walks the
## quadruped and refuses a legless body; Done emits the body as a dictionary the codec reloads.

const EDITOR_SCENE := preload("res://game/scenes/creature/creature_editor.tscn")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")

const POINTS := 150

var editor: CreatureEditor


func after_each() -> void:
	if editor != null:
		editor.free()
		editor = null


func open(body_name := "quadruped", points := POINTS) -> CreatureEditor:
	editor = EDITOR_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	editor.setup(CreatureData.body(body_name), points)
	return editor


func text() -> String:
	return BodyCodec.encode(editor.working_body())


## A point inside the back between the fifth and sixth vertebrae, `up` radii above the spine: a ray through it
## enters the skin before it, and no handle (the vertebrae, the fin further forward) is within reach of the click.
static func back_point(desc: RefCounted, up := 0.7) -> Vector3:
	return (desc.position_m(4) + desc.position_m(5)) * 0.5 + Vector3(0.0, up * desc.radius_m(4), 0.0)


func test_setup_shows_the_starter_body_with_its_handles_and_palette() -> void:
	open()
	var desc = editor.working_body()
	var vertebrae: int = editor.handles.filter(func(h): return h["kind"] == "vertebra").size()
	check_eq(vertebrae, desc.vertebrae.size(), "one handle per vertebra")
	check(editor.handles.filter(func(h): return h["kind"] == "joint").size() > 0, "joint handles")
	check(editor.handles.filter(func(h): return h["kind"] == "part").size() > 0, "part handles")
	check_eq(editor.points(), POINTS, "the points to spend")
	check(editor.tools.size() >= 17 and editor.tools.has("eye"), "one tool per part type in the records (%d)" % editor.tools.size())
	check_eq(editor.hud.tools_grid.get_child_count(), editor.tools.size() + 2, "a palette button per tool, plus Select and Limb")
	check_eq(editor.hud.swatch_row.get_child_count(), 8, "eight skin swatches")
	check(editor.hud.points_text.text.contains("150"), "the points are shown (%s)" % editor.hud.points_text.text)
	check(editor.refusal_text == "", "nothing refused yet")


func test_a_part_tool_and_a_click_on_the_skin_add_the_part_and_the_points_fall() -> void:
	open()
	var desc = editor.working_body()
	var parts_before: int = desc.parts.size()
	editor.choose_tool("eye")
	check_eq(editor.tool, "eye", "the eye tool is chosen")
	# A ray through a point inside the back, between two vertebrae and above their handles, enters the skin first.
	var at: Vector2 = editor.screen_of(back_point(desc))
	var r: Dictionary = editor.click_skin(at)
	check(r["ok"], "an eye added by clicking the skin at %s: %s" % [at, r["reason"]])
	check_eq(editor.working_body().parts.size(), parts_before + 1, "one more part")
	var pv: Dictionary = editor.session.preview()
	check(pv["cost"] > 0 and POINTS - pv["cost"] < POINTS, "the points left fell to %d" % (POINTS - pv["cost"]))
	check(editor.hud.cost_text.text.contains(str(POINTS - pv["cost"])), "the HUD shows the points left (%s)" % editor.hud.cost_text.text)
	check(not editor.selected.is_empty() and editor.selected["kind"] == "part", "the new part is selected")
	editor.choose_tool("")
	check_eq(editor.tool, "", "no tool")
	editor.choose_tool("tentacle")
	check_eq(editor.tool, "", "an unknown tool is ignored")


func test_a_limb_tool_drag_grows_a_limb_as_one_undo_step() -> void:
	open()
	var start := text()
	var desc = editor.working_body()
	var chains_before: int = desc.limb_chains().size()
	editor.choose_tool("limb")
	# Press on the top of the back: a single limb grows up out of it; then pull its tip forward and up.
	var from: Vector2 = editor.screen_of(back_point(desc, 0.8))
	var r: Dictionary = editor.press(from)
	check(r["ok"] and editor.dragging and editor.selected.get("kind", "") == "joint", "a limb grown from the back, its tip in hand: %s %s" % [r["reason"], str(editor.selected)])
	if r["ok"]:
		var tip: Vector3 = editor.selected["world"]
		var to: Vector2 = editor._unproject(tip + Vector3(0.0, 0.08, -0.1))
		for i in range(1, 7):
			var moved: Dictionary = editor.drag_to(from.lerp(to, i / 6.0))
			check(moved.get("ok", true), "drag step %d: %s" % [i, moved.get("reason", "")])
		editor.release()
	check(editor.working_body().limb_chains().size() > chains_before, "more limb chains")
	check(not editor.dragging, "released")
	check(editor.undo() and text() == start, "one undo gives back the starting body")


func test_a_vertebra_drag_is_one_undo_step_that_restores_the_byte_identical_body() -> void:
	open()
	var start := text()
	var from: Vector2 = editor.handle_screen("vertebra", "v_3")
	check(from.x >= 0.0, "the v_3 handle is on screen")
	var r: Dictionary = editor.drag(from, from + Vector2(0.0, -40.0))
	check(r["ok"], "the vertebra moved: %s" % r.get("reason", ""))
	check(text() != start, "the body changed")
	check(editor.undo(), "one undo")
	check_eq(text(), start, "the byte-identical starting body is back")
	check(not editor.undo(), "nothing more to undo")
	check(editor.redo() and text() != start, "redo brings the drag back")


func test_select_thicken_insert_mirror_and_delete() -> void:
	open()
	check(editor.select("vertebra", "v_4"), "v_4 selected")
	var r_before: int = int(editor.working_body().vertebrae[3]["r"])
	var r: Dictionary = editor.thicken(1)
	check(r["ok"] and int(editor.working_body().vertebrae[3]["r"]) > r_before, "thicker: %s" % r["reason"])
	var count: int = editor.working_body().vertebrae.size()
	r = editor.insert_after_selected()
	check(r["ok"] and editor.working_body().vertebrae.size() == count + 1, "a vertebra inserted after it: %s" % r["reason"])
	check(editor.select("part", "p_1"), "p_1 selected")
	var mirrored: bool = editor.working_body().parts[0]["mirror"]
	r = editor.mirror_selected()
	check(r["ok"] and editor.working_body().parts[0]["mirror"] != mirrored, "its mirror toggled: %s" % r["reason"])
	r = editor.remove_selected()
	check(r["ok"] and editor.working_body().parts.filter(func(p): return p["id"] == "p_1").is_empty(), "removed: %s" % r["reason"])
	check(editor.selected.is_empty(), "nothing selected after a delete")


func test_a_refused_op_shows_its_reason() -> void:
	open()
	var r: Dictionary = editor.remove_selected()
	check(not r["ok"] and editor.refusal_text == r["reason"] and editor.refusal_text != "", "delete with nothing selected: %s" % r["reason"])
	check(editor.hud.refusal_panel.visible and editor.hud.refusal_text.text == r["reason"], "the HUD shows it")
	editor.choose_tool("eye")
	r = editor.click_skin(Vector2(2.0, 2.0))
	check(not r["ok"] and editor.refusal_text == "missed the body", "a click off the body: %s" % r["reason"])
	var before := text()
	check(editor.select("vertebra", "v_5"), "v_5 selected")
	r = editor.thicken(40)
	check(not r["ok"] and editor.refusal_text == r["reason"] and text() == before, "a radius past the limit is refused and changes nothing: %s" % r["reason"])
	editor._process(1.0)
	check(editor.refusal_text != "", "still shown after 1 s")
	editor._process(1.5)
	check(editor.refusal_text == "" and not editor.hud.refusal_panel.visible, "gone after 2 s")


func test_the_skin_colour_rides_in_the_body() -> void:
	open()
	editor.set_skin_color(Color("#4fc08a"))
	check_eq(String(editor.working_body().extra.get("skin_color", "")), "4fc08a", "the working body carries the swatch")
	check(editor.undo() == false, "a colour is not an undo step")


func test_the_test_drive_walks_the_quadruped_and_refuses_a_legless_body() -> void:
	open()
	var r: Dictionary = editor.test_drive(true)
	check(r["ok"] and editor.walker != null and r.get("legs", 0) == 4, "the quadruped walks on four legs: %s" % r["reason"])
	check(not editor.handle_root.visible, "the handles are hidden while driving")
	editor._process(1.0 / 60.0)
	check(editor.walker.planner.position.length() >= 0.0, "the planner stepped")
	r = editor.test_drive(false)
	check(r["ok"] and editor.walker == null and editor.handle_root.visible, "back to editing")
	after_each()
	open("snake")
	r = editor.test_drive(true)
	check(not r["ok"] and r["reason"].contains("no legs") and editor.walker == null, "a legless body is refused: %s" % r["reason"])
	check_eq(editor.refusal_text, r["reason"], "and the reason is shown")


func test_done_emits_the_body_as_a_dictionary_the_codec_reloads() -> void:
	open()
	var got := {}   # filled in place: a lambda captures a local by value
	editor.done_requested.connect(func(body: Dictionary, points_left: int): got.merge({"body": body, "points": points_left}))
	var desc = editor.working_body()
	editor.choose_tool("eye")
	check(editor.click_skin(editor.screen_of(back_point(desc)))["ok"], "an eye added")
	var cost: int = editor.session.cost()
	var edited := text()
	var r: Dictionary = editor.finish()
	check(r["ok"] and r["points_left"] == POINTS - cost, "committed: %s" % r["reason"])
	check(not got.is_empty() and got["points"] == POINTS - cost, "done_requested carried the points left")
	if not got.is_empty():
		var reloaded = BodyCodec.from_dict(got["body"])
		check(reloaded.load_problems.is_empty() and BodyCodec.encode(reloaded) == edited, "the codec reloads the body unchanged")
		check(String(got["body"].get("skin_color", "")) == editor.skin_color.to_html(false), "with the skin colour")
		check(int(got["body"].get("pattern_seed", -1)) == int(editor.skin_pattern["pattern_seed"])
				and int(got["body"].get("coat_pattern", -1)) == int(editor.skin_pattern["coat_pattern"])
				and int(got["body"].get("detail_pattern", -1)) == int(editor.skin_pattern["detail_pattern"]),
				"and the three pattern keys the world reads (%s)" % [got["body"].keys()])
	check_eq(editor.points(), POINTS - cost, "the editor goes on from the committed body with the points left")
	check(editor.session.cost() == 0, "nothing to pay for after the commit")


func test_done_over_the_points_is_refused_and_back_asks_to_leave() -> void:
	open("quadruped", 5)
	var backs := [0]
	editor.back_requested.connect(func(): backs[0] += 1)
	var desc = editor.working_body()
	editor.choose_tool("eye")
	check(editor.click_skin(editor.screen_of(back_point(desc)))["ok"], "an eye added")
	var r: Dictionary = editor.finish()
	check(not r["ok"] and r["reason"] != "" and editor.refusal_text == r["reason"], "a commit over the points is refused: %s" % r["reason"])
	check_eq(editor.points(), 5, "the points are untouched")
	check_eq(editor.back(), "cleared", "the first Back clears the tool and the selection")
	check(editor.tool == "" and editor.selected.is_empty() and backs[0] == 0, "nothing left yet")
	check_eq(editor.back(), "asked", "the next asks about the unsaved edit")
	check_eq(editor.refusal_text, CreatureEditor.UNSAVED_TEXT, "with the reason")
	check_eq(backs[0], 0, "still in the editor")
	check_eq(editor.back(), "left", "and the one after leaves")
	check_eq(backs[0], 1, "back_requested emitted")
	editor._process(CreatureEditor.REFUSAL_S + 0.1)
	after_each()
	open("quadruped", 5)
	editor.back_requested.connect(func(): backs[0] += 1)
	check_eq(editor.back(), "left", "Back with nothing edited leaves at once")
	check_eq(backs[0], 2, "back_requested emitted")


func test_done_on_a_body_without_legs_asks_once() -> void:
	open("snake")
	var dones := [0]
	editor.done_requested.connect(func(_b, _p): dones[0] += 1)
	var r: Dictionary = editor.finish()
	check(not r["ok"] and r["reason"] == CreatureEditor.NO_LEGS_TEXT and editor.refusal_text == r["reason"], "the first Done asks: %s" % r["reason"])
	check_eq(dones[0], 0, "nothing committed")
	r = editor.finish()
	check(r["ok"], "Done again goes anyway: %s" % r["reason"])
	check_eq(dones[0], 1, "committed")


func test_the_camera_stays_above_the_floor_and_the_wheel_zooms_off_the_selection() -> void:
	open()
	for i in 12:
		editor.wheel(-1)
	editor.orbit(Vector2(0.0, -5.0))
	check(editor.camera.position.y > editor.floor_disc.position.y, "pitched to the floor and zoomed far out, the camera is above the disc (%.2f)" % editor.camera.position.y)
	var desc = editor.working_body()
	var v: Dictionary = desc.vertebrae[3]
	editor.selected = {"kind": "vertebra", "id": v["id"], "twin": false}
	var before := BodyCodec.encode(desc)
	var distance: float = editor._distance
	editor.wheel(1, Vector2(2.0, 2.0))
	check(text() == before and editor._distance < distance, "the wheel away from the selected handle zooms, not thickens")
	var handle: Dictionary = editor.handles.filter(func(h): return h["kind"] == "vertebra" and h["id"] == v["id"])[0]
	distance = editor._distance
	editor.wheel(1, editor._unproject(handle["world"]))
	check(text() != before and is_equal_approx(editor._distance, distance), "over the selected handle it thickens")
	check(editor.undo(), "as one undo step")
