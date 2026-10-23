extends SceneTree
## Editor core tests (domain/creature_editor_session.gd, domain/editor_picking.gd), headless.
## Run: godot --headless --path prototypes/creature-lab --script res://tests/run_editor_tests.gd

const Lab := preload("res://lab_spine.gd")
const BodyCodec := preload("res://domain/body_codec.gd")
const BodyField := preload("res://domain/body_field.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const AnchorResolver := preload("res://domain/anchor_resolver.gd")
const Session := preload("res://domain/creature_editor_session.gd")
const Picking := preload("res://domain/editor_picking.gd")

## Picking round trip: a skin point -> anchor -> resolver must land this close, as a fraction of body length, for
## this share of the skin's vertices. The rest are in the fillets where a limb meets the trunk: the click picks the
## limb, and the resolver's ray from the limb axis finds the skin a little way off.
const ROUND_TRIP_MAX := 0.01
const ROUND_TRIP_SHARE := 0.95

var failures := 0
var rules := {}
var part_rules := {}
var costs := {}


func _init() -> void:
	rules = Lab.rules()
	part_rules = Lab.part_rules()
	costs = Lab.editor_costs()
	test_fresh_session()
	test_spine_edits_and_undo()
	test_refused_ops_change_nothing()
	test_gesture_is_one_undo_step()
	test_limb_edits()
	test_part_edits()
	test_cost()
	test_commit()
	test_deterministic()
	test_ray_to_skin()
	test_pick_round_trip()
	test_anchor_for_part()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func session(body_name := "s1_quadruped", points := 100) -> RefCounted:
	return Session.new(Lab.body(body_name), rules, part_rules, costs, points)


func text(s: RefCounted) -> String:
	return BodyCodec.encode(s.working)


func test_fresh_session() -> void:
	for body_name in Lab.stage1_names():
		var s := session(body_name)
		var pv: Dictionary = s.preview()
		check(s.cost() == 0 and pv["errors"].is_empty() and pv["phenotype"] == pv["current"],
				"%s: a fresh session costs nothing, has no problems, before = after" % body_name)
	var stats: Dictionary = session().preview()["phenotype"]
	check(stats["legs"] == 4 and stats["limbs"] == 4 and stats["bones"] == 25 and stats["mass_kg"] > 0.0,
			"quadruped stats: %s" % str(stats))


func test_spine_edits_and_undo() -> void:
	var s := session()
	var start := text(s)
	var r: Dictionary = s.move_vertebra("v_3", Vector3i(0, 30, -260))
	var limb: Dictionary = s.working.limbs[0]
	check(r["ok"] and limb["joints"][0]["p"] == [90, -10, -260] and limb["joints"][3]["p"] == [110, -490, -320],
			"moving a vertebra moves the limbs on it %s" % r["reason"])
	r = s.insert_vertebra(9)
	# A longer body has a coarser skin grid (cell = longest extent / divisions), so the thin toes fall under it.
	check(not r["ok"] and r["reason"].contains("too thin"), "refused: a tail vertebra that would make the toes too thin for the grid (%s)" % r["reason"])
	r = s.insert_vertebra(3)
	check(r["ok"] and s.working.vertebrae[3]["p"] == [0, 15, -190], "a vertebra added halfway %s" % r["reason"])
	r = s.set_vertebra_radius("v_5", 140)
	check(r["ok"], "a vertebra made thicker %s" % r["reason"])
	var edited := text(s)
	var undone: bool = s.undo() and s.undo() and s.undo()
	check(undone and text(s) == start and not s.undo(), "three undos give back the exact starting body")
	var redone: bool = s.redo() and s.redo() and s.redo()
	check(redone and text(s) == edited and not s.redo(), "three redos give back the exact edited body")
	var fish := session("fish")
	r = fish.insert_vertebra(fish.working.vertebrae.size())
	check(r["ok"] and fish.working.vertebrae[-1]["id"] == r["vertebra_id"], "a vertebra added at the fish's tail %s" % r["reason"])
	r = s.remove_vertebra("v_6")
	check(r["ok"] and r["removed"]["limbs"] == ["l_2"] and r["removed"]["parts"] == ["p_6"]
			and s.working.limb_index("l_2") < 0, "removing a vertebra removes its limbs and their parts %s" % str(r))


func test_refused_ops_change_nothing() -> void:
	var cases := {
		"vertebra past the position limit": func(s): return s.move_vertebra("v_5", Vector3i(0, 0, 4000)),
		"vertebra radius past the limit": func(s): return s.set_vertebra_radius("v_5", 900),
		"vertebra folded back on itself": func(s): return s.move_vertebra("v_5", Vector3i(0, 0, -250)),
		"missing vertebra": func(s): return s.move_vertebra("v_99", Vector3i.ZERO),
		"knee pulled off so joint 0 leaves the spine": func(s): return s.move_joint("l_1", "j_1", Vector3i(400, -40, -260)),
		"first joint removed": func(s): return s.remove_joint("l_1", "j_1"),
		"limb on a missing vertebra": func(s): return s.add_limb("v_99", [[Vector3i.ZERO, 50], [Vector3i(0, -100, 0), 40]]),
		"unknown part": func(s): return s.add_part("tentacle", {}),
		"eye on a leg": func(s): return s.add_part("eye", {"host": "l_1", "u": 500, "ring": 250}),
		"eye turned past its limit": func(s): return s.orient_part("p_1", {"turn": 90}),
		"part at 3x": func(s): return s.scale_part("p_1", 3000),
		"beak moved off the middle": func(s): return s.move_part("p_2", {"ring": 250}),
		"part host set through orient": func(s): return s.orient_part("p_1", {"host": "l_1"}),
	}
	for what in cases:
		var s := session()
		var before := text(s)
		var r: Dictionary = cases[what].call(s)
		check(not r["ok"] and r["reason"] != "" and text(s) == before and not s.undo(),
				"refused, nothing changed: %s (%s)" % [what, r["reason"]])
	var tiny := session("s1_tiny")
	var r: Dictionary = tiny.remove_vertebra(String(tiny.working.vertebrae[1]["id"]))
	check(not r["ok"], "refused: the tiny body's third-to-last vertebra (%s)" % r["reason"])


func test_gesture_is_one_undo_step() -> void:
	var s := session()
	var start := text(s)
	s.begin_gesture()
	for k in 6:
		s.move_vertebra("v_9", Vector3i(0, 50 + 10 * k, 500))
	s.move_vertebra("v_9", Vector3i(0, 50, 9000))  # refused mid-drag: the drag stays at its last valid point
	s.end_gesture()
	var dragged := text(s)
	check(s.working.vertebrae[8]["p"] == [0, 100, 500] and s.undo() and text(s) == start and not s.undo(),
			"a six-step drag is one undo step")
	check(s.redo() and text(s) == dragged, "and one redo")


func test_limb_edits() -> void:
	var s := session()
	var r: Dictionary = s.move_joint("l_1", "j_2", Vector3i(130, -260, -200))
	var j: Array = s.working.limbs[0]["joints"]
	check(r["ok"] and j[1]["p"] == [130, -260, -200] and j[3]["p"] == [130, -520, -280],
			"dragging a knee brings the foot along %s" % r["reason"])
	r = s.move_joint("l_1", "j_3", Vector3i(110, -460, -260), false)
	check(r["ok"] and j.size() == 4 and s.working.limbs[0]["joints"][3]["p"] == [130, -520, -280],
			"a joint moved alone leaves the next joint where it was %s" % r["reason"])
	r = s.insert_joint("l_2", "j_6")
	check(r["ok"] and s.working.limbs[1]["joints"].size() == 5, "a joint inserted in a leg %s" % r["reason"])
	r = s.insert_joint("l_2", "j_8")
	check(not r["ok"], "refused: a sixth joint (%s)" % r["reason"])
	r = s.add_limb("v_2", [[Vector3i(60, 0, -380), 50], [Vector3i(200, 40, -380), 45], [Vector3i(300, 60, -400), 42]])
	check(r["ok"] and s.working.limb_chains().size() == 6, "a mirrored arm added on the neck %s" % r["reason"])
	r = s.remove_limb("l_1")
	check(r["ok"] and r["removed"]["parts"] == ["p_5"], "removing a leg removes the foot on it %s" % str(r))
	r = s.set_limb_mirror("l_2", false)
	check(not r["ok"], "refused: a leg pair made single while its foot has a twin (%s)" % r["reason"])
	s.set_part_mirror("p_6", false)
	r = s.set_limb_mirror("l_2", false)
	check(r["ok"], "with the foot's twin gone, the leg pair made single %s" % r["reason"])


func test_part_edits() -> void:
	var s := session()
	var r: Dictionary = s.add_part("eye", {"host": "spine", "u": 120, "ring": 250, "mirror": true})
	var id := String(r.get("part_id", ""))
	check(r["ok"] and s._part(s.working, id)["handles"] == [0, 0], "an eye added, with the record's default handles")
	r = s.move_part(id, {"u": 150, "ring": 300})
	check(r["ok"] and s._part(s.working, id)["u"] == 150, "the eye moved %s" % r["reason"])
	r = s.orient_part(id, {"turn": 30, "tilt": -20, "height": 5})
	check(r["ok"], "the eye turned and lifted %s" % r["reason"])
	r = s.set_part_handles(id, [500, 1000])
	check(r["ok"] and s._part(s.working, id)["handles"] == [500, 1000], "the eye's handles set %s" % r["reason"])
	r = s.set_part_handles(id, [500])
	check(not r["ok"], "refused: wrong number of handles (%s)" % r["reason"])
	r = s.set_part_mirror(id, false)
	check(r["ok"] and not s._part(s.working, id)["mirror"], "the eye's twin taken away %s" % r["reason"])
	r = s.remove_part(id)
	check(r["ok"] and s._part(s.working, id).is_empty(), "the eye removed %s" % r["reason"])


func test_cost() -> void:
	var s := session()
	s.insert_vertebra(3)
	check(s.cost() == 5, "a vertebra costs 5 (%d)" % s.cost())
	s.add_part("eye", {"host": "spine", "u": 120, "ring": 250, "mirror": true})
	check(s.cost() == 25, "a mirrored eye costs two eyes (%d)" % s.cost())
	s.undo()
	s.undo()
	check(s.cost() == 0, "undone, it costs nothing (%d)" % s.cost())
	s.remove_part("p_3")
	check(s.cost() == -15, "removing a mirrored horn refunds half of two horns (%d)" % s.cost())
	s.undo()
	s.set_part_mirror("p_3", false)
	check(s.cost() == -7, "taking a horn's twin away refunds half a horn, rounded down (%d)" % s.cost())
	s.undo()
	s.add_limb("v_2", [[Vector3i(60, 0, -380), 50], [Vector3i(200, 40, -380), 45], [Vector3i(300, 60, -400), 42]])
	check(s.cost() == 24, "a mirrored three-joint arm costs six joints (%d)" % s.cost())
	s.undo()
	s.move_vertebra("v_9", Vector3i(0, 80, 500))
	s.scale_part("p_1", 1200)
	s.orient_part("p_3", {"turn": 10})
	check(s.cost() == 0, "moving, resizing and turning are free (%d)" % s.cost())


func test_commit() -> void:
	var s := session("s1_quadruped", 10)
	var original_text := BodyCodec.encode(s.original)
	s.insert_vertebra(3)
	s.add_part("eye", {"host": "spine", "u": 120, "ring": 250, "mirror": true})
	var poor: Dictionary = s.commit()
	check(not poor["ok"] and poor["body"] == null and poor["points_left"] == 10
			and BodyCodec.encode(s.original) == original_text, "a commit over the points is refused: %s" % str(poor["errors"]))
	s.undo()
	var done: Dictionary = s.commit()
	check(done["ok"] and done["points_left"] == 5 and BodyCodec.encode(done["body"]) == text(s)
			and done["body"] != s.working, "a commit within the points returns a new body and the points left")
	check(BodyCodec.encode(s.original) == original_text, "the original body is untouched")


func edit_sequence() -> String:
	var s := session()
	s.insert_vertebra(0)
	s.move_joint("l_2", "j_6", Vector3i(120, -250, 210))
	s.add_part("fin", {"host": "spine", "u": 700, "ring": 0})
	s.undo()
	s.add_part("eye", {"host": "spine", "u": 140, "ring": 220, "mirror": true})
	return BodyCodec.hash_text(s.working)


func test_deterministic() -> void:
	check(edit_sequence() == edit_sequence(), "the same edits give the same body (SHA-256)")


func test_ray_to_skin() -> void:
	var desc = Lab.body("s1_quadruped")
	var field = BodyField.from_description(desc)
	var hit: Dictionary = Picking.ray_to_skin(field, Vector3(0, 0.0, 3.0), Vector3.FORWARD)
	var head: Dictionary = Picking.ray_to_skin(field, Vector3(0, 0.048, -3.0), Vector3.BACK)
	var miss: Dictionary = Picking.ray_to_skin(field, Vector3(0, 3.0, 0.0), Vector3.RIGHT)
	var leg: Dictionary = Picking.ray_to_skin(field, Vector3(3.0, -0.4, -0.31), Vector3.LEFT)
	check(hit["hit"] and absf(field.sample(hit["point"]) - BodyField.ISO) < 1e-4 and hit["point"].z > 0.5
			and head["hit"] and head["point"].z < -0.6 and not miss["hit"],
			"rays from behind and ahead hit the skin at the tail and the snout; a ray past the body misses")
	var on_leg: Dictionary = Picking.anchor_at(desc, field, leg["point"])
	check(leg["hit"] and on_leg["host"] == "l_1" and not on_leg["on_copy"],
			"a ray from the right hits the right front leg: %s" % str(on_leg))
	var copy_ray: Dictionary = Picking.ray_to_skin(field, Vector3(-3.0, -0.4, -0.31), Vector3.RIGHT)
	var on_copy: Dictionary = Picking.anchor_at(desc, field, copy_ray["point"])
	check(on_copy["host"] == "l_1" and on_copy["on_copy"] and on_copy["ring"] == on_leg["ring"],
			"the same ray from the left hits the leg's copy, at the same anchor: %s" % str(on_copy))


func test_pick_round_trip() -> void:
	for body_name in Lab.stage1_names():
		var desc = Lab.body(body_name)
		var field = BodyField.from_description(desc)
		var verts: PackedVector3Array = SkinCpu.build(desc, 32)["vertices"]
		var length: float = desc.bounds_m().get_longest_axis_size()
		var errs := PackedFloat32Array()
		for k in range(0, verts.size(), maxi(1, verts.size() / 400)):
			var a: Dictionary = Picking.anchor_at(desc, field, verts[k])
			var part := {"id": "p_x", "type": "x", "host": a["host"], "u": a["u"], "ring": a["ring"], "elev": a["elev"],
					"height": 0, "turn": 0, "tilt": 0, "roll": 0, "scale": 1000, "handles": [], "mirror": false}
			var t: Transform3D = AnchorResolver.resolve(desc, field, part)["transform"]
			if a["on_copy"]:
				t = AnchorResolver.mirrored(t)
			errs.append(t.origin.distance_to(verts[k]) / length)
		var sorted := errs.duplicate()
		sorted.sort()
		var share := float(sorted.bsearch(ROUND_TRIP_MAX)) / sorted.size()
		check(share >= ROUND_TRIP_SHARE, "%s: click -> anchor -> resolver lands within %.0f%% of body length for %.1f%% of %d skin points (median %.2f%%, worst %.1f%%)"
				% [body_name, 100.0 * ROUND_TRIP_MAX, 100.0 * share, sorted.size(), 100.0 * sorted[sorted.size() / 2],
				100.0 * sorted[sorted.size() - 1]])


func test_anchor_for_part() -> void:
	var desc = Lab.body("s1_quadruped")
	var field = BodyField.from_description(desc)
	var side := {"host": "spine", "u": 100, "ring": 230, "elev": 0, "on_copy": false}
	var beak: Dictionary = Picking.anchor_for_part(desc, part_rules["beak"], side)
	var horn: Dictionary = Picking.anchor_for_part(desc, part_rules["horn"], {"host": "spine", "u": 100, "ring": 0, "elev": 0})
	var eye: Dictionary = Picking.anchor_for_part(desc, part_rules["eye"], side)
	check(beak["ring"] == 0 and not beak["mirror"] and horn["ring"] != 0 and horn["mirror"] and eye["ring"] == 230
			and eye["mirror"], "a beak snaps to the middle line, a horn leaves it with a twin, an eye stays put with a twin")
	var tip := {"host": "l_1", "u": 950, "ring": 500, "elev": 0, "on_copy": false}
	var foot: Dictionary = Picking.anchor_for_part(desc, part_rules["foot"], tip)
	var eye_leg: Dictionary = Picking.anchor_for_part(desc, part_rules["eye"], tip)
	check(foot["host"] == "l_1:end" and foot["mirror"] and eye_leg.has("reason"),
			"a foot clicked near a leg tip goes on the leg's end with a twin; an eye there is refused (%s)" % eye_leg.get("reason", ""))
	var s := session()
	var copy_ray: Dictionary = Picking.ray_to_skin(field, Vector3(-3.0, -0.2, -0.31), Vector3.RIGHT)
	var picked: Dictionary = Picking.anchor_at(desc, field, copy_ray["point"])
	var a: Dictionary = Picking.anchor_for_part(desc, part_rules["fin"], picked)
	var r: Dictionary = s.add_part("fin", a)
	var placed := AnchorResolver.resolve_all(s.working, BodyField.from_description(s.working),
			Lab.part_orientations(part_rules)).filter(func(e): return e["part"] == r.get("part_id", ""))
	var length: float = desc.bounds_m().get_longest_axis_size()
	check(r["ok"] and placed.size() == 2 and placed[1]["transform"].origin.distance_to(copy_ray["point"]) < 0.02 * length,
			"a fin clicked on a leg's mirror copy is added to the leg, and its twin lands where the click was %s" % r["reason"])
