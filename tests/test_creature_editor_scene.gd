extends TestCase
## The creature editor scene (game/scenes/creature/creature_editor.tscn), driven headless through its method twins
## only, as the smoke drives it: a part tool and a click on the skin add a part and the points fall; a vertebra drag
## is one undo step that gives back the byte-identical body; a refused op shows its reason; the test drive walks the
## quadruped and refuses a legless body; Done emits the body as a dictionary the codec reloads.

const EDITOR_SCENE := preload("res://game/scenes/creature/creature_editor.tscn")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")

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


func test_the_skin_covering_rides_in_the_body_and_reaches_the_shader() -> void:
	open()
	var Look = load("res://game/scenes/creature/creature_look.gd")
	(editor.hud.covering_row.get_child(1) as Button).pressed.emit()
	check_eq(editor.skin_covering, 1, "the Fur toggle sets the covering")
	check(editor.working_body().extra.get(Look.COVERING_KEY) is float
			and int(editor.working_body().extra[Look.COVERING_KEY]) == 1, "the working body carries skin_covering")
	var mat := editor.rig.mesh_instance.material_override as ShaderMaterial if editor.rig else null
	if mat != null:
		check_eq(int(mat.get_shader_parameter("covering")), 1, "the preview's shader gets it")
	editor.set_skin_covering(9)
	check_eq(editor.skin_covering, 0, "an unknown covering is smooth")
	check((editor.hud.covering_row.get_child(0) as Button).button_pressed, "and the HUD follows")
	editor.set_skin_covering(3)
	check(editor.undo() == false, "a covering is not an undo step")
	var got := {}   # filled in place: a lambda captures a local by value
	editor.done_requested.connect(func(body: Dictionary, _p: int): got.merge(body))
	var done := editor.finish()
	check(done["ok"], "Done commits it: %s" % done.get("reason", ""))
	check_eq(int(got.get(Look.COVERING_KEY, -1)), 3, "the body Done hands on carries the wet covering")


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


## Owner playtest, 2026-10-24: right-drag turns the creature, the zoom reaches in to a part and out to a big body,
## and every part can be resized.
func test_a_right_drag_orbits_the_camera() -> void:
	open()
	var before: Vector3 = editor.camera.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	editor._unhandled_input(press)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(80.0, 0.0)
	editor._unhandled_input(move)
	check(editor.camera.position.distance_to(before) > 0.01, "the camera moved round the body")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	editor._unhandled_input(release)
	var after: Vector3 = editor.camera.position
	editor._unhandled_input(move)
	check(editor.camera.position.is_equal_approx(after), "and stops when the button is up")


func test_the_zoom_stays_between_a_close_look_and_the_whole_body() -> void:
	open()
	var framed: float = editor._frame_distance
	check(framed > 0.0, "the body was framed")
	for i in 60:
		editor.zoom(1)
	check(is_equal_approx(editor._distance, framed * CreatureEditor.ZOOM_MIN), "zoomed in to %.2f of the framing" % (editor._distance / framed))
	for i in 60:
		editor.zoom(-1)
	check(is_equal_approx(editor._distance, framed * CreatureEditor.ZOOM_MAX), "zoomed out to %.2f of the framing" % (editor._distance / framed))


func test_a_selected_part_grows_and_shrinks_within_the_rules() -> void:
	open()
	var desc = editor.working_body()
	var part: Dictionary = desc.parts[0]
	check(editor.select("part", part["id"]), "a part selected")
	var start := int(part["scale"])
	var r: Dictionary = editor.resize_selected(1)
	check(r["ok"], "grows: %s" % r["reason"])
	var grown: int = editor.working_body().parts[0]["scale"]
	check_eq(grown, int(round(start * CreatureEditor.PART_SCALE_STEP)), "by one step")
	check(editor.undo(), "as one undo step")
	check_eq(int(editor.working_body().parts[0]["scale"]), start, "undo gives the size back")
	editor.select("part", part["id"])
	var hi := int(editor.rules["part_scale_max"])
	for i in 40:
		editor.resize_selected(1)
	check_eq(int(editor.working_body().parts[0]["scale"]), hi, "up to the rules' largest")
	check(not editor.resize_selected(1)["ok"], "and no further")
	var key := InputEventKey.new()
	key.keycode = KEY_MINUS
	key.pressed = true
	editor._unhandled_input(key)
	check(int(editor.working_body().parts[0]["scale"]) < hi, "the - key shrinks it")


func test_new_parts_are_sized_to_the_body() -> void:
	open()
	var desc = editor.working_body()
	var rules: Dictionary = editor.rules
	var size: float = (desc.bounds_m() as AABB).get_longest_axis_size()
	check_eq(Picking.fit_scale(desc, size, rules), 1000, "on a body the reference size, scale 1000")
	check_eq(Picking.fit_scale(desc, size / 2.0, rules), 2000, "on a body twice the size, twice as big")
	check_eq(Picking.fit_scale(desc, size * 100.0, rules), int(rules["part_scale_min"]), "never under the rules' smallest")
	check_eq(Picking.fit_scale(desc, size / 100.0, rules), int(rules["part_scale_max"]), "never over the largest")


func test_a_first_design_can_start_from_a_preset_at_no_cost() -> void:
	open()
	check(not editor.start_from_preset("raptor")["ok"], "refused while presets are not offered")
	editor.offer_presets(true)
	var names := CreatureData.preset_names()
	check_eq(editor.hud.preset_count(), names.size(), "a button per preset")
	var r: Dictionary = editor.start_from_preset("raptor")
	check(r["ok"], "starts from the raptor: %s" % r.get("reason", ""))
	var want: Dictionary = CreatureData.preset("raptor")["body"]
	var got: Dictionary = editor.working_body().to_dict()
	for key in ["vertebrae", "limbs", "parts", "reference_length_mm"]:
		check_eq(JSON.stringify(got[key]), JSON.stringify(BodyCodec.from_dict(want).to_dict()[key]), "the raptor's %s" % key)
	check_eq(editor.skin_color.to_html(false), Color(want["skin_color"]).to_html(false), "and its colour")
	check_eq(editor.points(), POINTS, "the points are untouched")
	check_eq(int(editor.session.preview()["cost"]), 0, "it costs nothing")
	check_eq(editor.back(), "asked", "Back asks before leaving the preset")
	var done := editor.finish()
	check(done["ok"], "Done commits it: %s" % done.get("reason", ""))
	editor.offer_presets(false)
	check(not editor.start_from_preset("dragon")["ok"], "refused once presets are withdrawn")


## Owner playtest, 2026-10-24: the palette shows the parts as pictures. Headless runs render none, so the HUD's seam
## is driven with a stand-in picture.
func test_a_part_picture_turns_its_tool_into_a_picture_button() -> void:
	open()
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	editor.hud.set_tool_icon("eye", tex)
	check(editor.hud.tool_icon("eye") == tex, "the eye tool shows its picture")
	check_eq(editor.hud.tools_grid.columns, editor.hud.ICON_COLUMNS, "the palette goes to picture columns")
	check(editor.hud.tool_icon("maw") == null, "a part without a picture keeps its text")
	editor.hud.set_tool_icon("tentacle", tex)
	check(editor.hud.tool_icon("tentacle") == null, "an unknown part is ignored")


## Owner ask, 2026-10-24: a Random button for a surprise first design.
func test_a_first_design_can_start_from_a_random_creature() -> void:
	open()
	check(not editor.start_random(5)["ok"], "refused while presets are not offered")
	editor.offer_presets(true)
	var bases := {}
	for s in 6:
		var r: Dictionary = editor.start_random(s)
		check(r["ok"], "seed %d starts: %s" % [s, r.get("reason", "")])
		check(CreatureData.preset_names().has(r["base"]), "from a preset (%s)" % r["base"])
		check_eq(editor.points(), POINTS, "the points are untouched")
		check_eq(int(editor.session.preview()["cost"]), 0, "it costs nothing")
		bases[r["base"]] = true
	check(bases.size() >= 2, "different seeds give different creatures (%d bases)" % bases.size())
	var a := JSON.stringify(_random_body(11))
	check_eq(JSON.stringify(_random_body(11)), a, "the same seed gives the same creature")
	var pressed := [0]
	editor.hud.random_requested.connect(func(): pressed[0] += 1)
	(editor.hud.find_child("Random", true, false) as Button).pressed.emit()
	check_eq(pressed[0], 1, "the Random button asks for one")
	var done := editor.finish()
	check(done["ok"], "Done commits it: %s" % done.get("reason", ""))


func _random_body(seed_value: int) -> Dictionary:
	editor.start_random(seed_value)
	var out: Dictionary = editor.working_body().to_dict()
	out["color"] = editor.skin_color.to_html(false)
	return out


func test_the_head_shape_sliders_edit_the_body_as_one_undo_step_at_no_cost() -> void:
	open()
	var start := text()
	var hud := editor.hud
	check(hud.head_slider("snout") != null and hud.head_slider("snout").value == 1000.0, "the sliders show the body")
	hud.head_slider("snout").drag_started.emit()
	for v in [1200, 1400, 1600]:
		hud.head_slider("snout").value_changed.emit(float(v))   # as the slider does when dragged
	hud.head_slider("snout").drag_ended.emit(true)
	check_eq(int(editor.working_body().extra["head_shape"]["snout"]), 1600, "the drag sets the snout")
	check_eq(editor.session.cost(), 0, "the head costs nothing")
	var r: Dictionary = editor.set_head_shape("width", 1700)
	check(not r["ok"] and editor.refusal_text != "" and hud.head_slider("width").value == 1000.0,
			"a width past 1.6x is refused and the slider goes back")
	check(editor.undo() and text() == start, "one undo takes the whole drag back")
	check_eq(hud.head_slider("snout").value, 1000.0, "and the slider follows")
	editor.set_head_shape("height", 1400)
	var got := []
	editor.done_requested.connect(func(body: Dictionary, _p: int): got.append(body))
	editor.finish()
	check(got.size() == 1 and int(BodyCodec.from_dict(got[0]).extra["head_shape"]["height"]) == 1400,
			"Done hands the head shape on in the body")
