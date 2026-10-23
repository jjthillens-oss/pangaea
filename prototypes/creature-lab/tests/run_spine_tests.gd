extends SceneTree
## Spine Lab (0b) tests, headless, GDScript skin only (the bench compares the GPU path).
## Run: godot --headless --path prototypes/creature-lab --script res://tests/run_spine_tests.gd

const Lab := preload("res://lab_spine.gd")
const BodyCodec := preload("res://domain/body_codec.gd")
const BodyDescription := preload("res://domain/body_description.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const MeshChecks := preload("res://skin/mesh_checks.gd")

var failures := 0
var rules := {}


func _init() -> void:
	rules = Lab.rules()
	test_test_bodies_are_valid()
	test_validation_refuses_each_limit()
	test_codec_round_trip()
	test_codec_survives_save_json()
	test_codec_keeps_unknown_and_reports_bad()
	test_ids_never_reused()
	test_size_budget()
	test_skin_watertight_and_wound()
	test_random_bodies_watertight()
	test_skin_deterministic()
	test_weights()
	test_paint_coordinates()
	test_triangle_budget_large_body()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func straight(count: int, r: int, ref_mm := 1000) -> RefCounted:
	var d = BodyDescription.create()
	d.reference_length_mm = ref_mm
	for i in count:
		d.add_vertebra(Vector3i(0, 0, -500 + i * 1000 / maxi(1, count - 1)), r)
	return d


func test_test_bodies_are_valid() -> void:
	for body_name in Lab.BODY_NAMES:
		var problems: PackedStringArray = Lab.body(body_name).validate(rules)
		check(problems.is_empty(), "%s is valid %s" % [body_name, "" if problems.is_empty() else str(problems)])


func test_validation_refuses_each_limit() -> void:
	check(straight(3, 120).validate(rules).is_empty(), "boundary: 3 vertebrae accepted")
	check(straight(24, 120).validate(rules).is_empty(), "boundary: 24 vertebrae accepted")
	var cases := {
		"2 vertebrae": straight(2, 120),
		"25 vertebrae": straight(25, 120),
		"radius above 400": straight(5, 401),
		"radius below 20": straight(5, 19),
	}
	var thin = straight(8, 30)  # 30/1000 of a 1 m body is under 1.5 cells of length/48
	cases["thin feature"] = thin
	var ratio = straight(5, 120)
	ratio.vertebrae[2]["r"] = 361
	cases["neighbour ratio over 3:1"] = ratio
	var outside = straight(5, 120)
	outside.vertebrae[0]["p"] = [0, 0, -1501]
	cases["outside the body box"] = outside
	var folded = straight(5, 60)
	folded.vertebrae[3]["p"] = [40, 0, -100]
	cases["folded spine"] = folded
	# A hairpin: down one side, round a bend, back up the other side 150 units away (radii 100 each).
	var u_turn = BodyDescription.create()
	for z in [-500, -300, -100, 100, 300]:
		u_turn.add_vertebra(Vector3i(0, 0, z), 100)
	u_turn.add_vertebra(Vector3i(75, 0, 420), 100)
	for z in [300, 100, -100, -300, -500]:
		u_turn.add_vertebra(Vector3i(150, 0, z), 100)
	cases["spine touching itself"] = u_turn
	var dup = straight(4, 120)
	dup.vertebrae[1]["id"] = dup.vertebrae[0]["id"]
	cases["duplicate id"] = dup
	for what in cases:
		var problems: PackedStringArray = cases[what].validate(rules)
		check(not problems.is_empty(), "refused: %s (%s)" % [what, problems[0] if not problems.is_empty() else "accepted!"])


func random_body(rng: RandomNumberGenerator) -> RefCounted:
	var d = BodyDescription.create()
	d.reference_length_mm = rng.randi_range(100, 8000)
	var count := rng.randi_range(3, 24)
	for i in count:
		d.add_vertebra(Vector3i(rng.randi_range(-1500, 1500), rng.randi_range(-1500, 1500),
				rng.randi_range(-1500, 1500)), rng.randi_range(20, 400))
	# Some edits remove vertebrae, so ids have gaps.
	if count > 4 and rng.randf() < 0.5:
		d.remove_vertebra(rng.randi_range(0, count - 1))
	return d


func test_codec_round_trip() -> void:
	var ok := true
	for body_name in Lab.BODY_NAMES:
		var text := BodyCodec.encode(Lab.body(body_name))
		ok = ok and BodyCodec.encode(BodyCodec.decode(text)) == text
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 1000:
		var text := BodyCodec.encode(random_body(rng))
		ok = ok and BodyCodec.encode(BodyCodec.decode(text)) == text
	check(ok, "encode -> decode -> encode is byte-identical for the 7 test bodies and 1000 random bodies")


func test_codec_survives_save_json() -> void:
	# A save writes the description as part of a bigger JSON document with Godot's default writer.
	var ok := true
	for body_name in Lab.BODY_NAMES:
		var desc = Lab.body(body_name)
		var save_text := JSON.stringify({"save_version": 2, "body": desc.to_dict()})
		var back: Dictionary = JSON.parse_string(save_text)
		ok = ok and BodyCodec.encode(BodyCodec.from_dict(back["body"])) == BodyCodec.encode(desc)
	check(ok, "a body written into a save with Godot's default JSON and read back encodes to the same text")


func test_codec_keeps_unknown_and_reports_bad() -> void:
	var text := BodyCodec.encode(Lab.body("bean"))
	var d: Dictionary = JSON.parse_string(text)
	d["future_field"] = {"x": 1}
	d["vertebrae"][0]["r"] = 120.5
	var desc = BodyCodec.from_dict(d)
	check(desc.extra.has("future_field") and BodyCodec.encode(desc).contains("future_field"),
			"unknown fields are kept and written back")
	check(not desc.load_problems.is_empty() and not desc.validate(rules).is_empty(),
			"a non-whole radius is reported, not silently accepted (%s)" % str(desc.load_problems))
	var newer: Dictionary = JSON.parse_string(text)
	newer["body_version"] = 99
	check(not BodyCodec.from_dict(newer).validate(rules).is_empty(), "a newer body_version is refused with a reason")


func test_ids_never_reused() -> void:
	var d = straight(5, 120)
	var seen := {}
	for v in d.vertebrae:
		seen[v["id"]] = true
	var reused := false
	for round_i in 20:
		d.remove_vertebra(round_i % d.vertebrae.size())
		var id: String = d.add_vertebra(Vector3i(0, 10, round_i * 10), 120, 1)
		reused = reused or seen.has(id)
		seen[id] = true
	check(not reused and int(d.next_ids["v"]) == 26, "ids are never reused; the counter only grows")


func test_size_budget() -> void:
	var d = BodyDescription.create()
	d.reference_length_mm = 8000
	for i in 24:
		d.add_vertebra(Vector3i(-1500, -1500, -1500 + i * 125), 400)
	var size := BodyCodec.encode(d).to_utf8_buffer().size()
	check(size <= int(rules["size_budget_bytes"]), "largest spine body encodes in %d bytes (budget %d)"
			% [size, int(rules["size_budget_bytes"])])


func test_skin_watertight_and_wound() -> void:
	for body_name in Lab.BODY_NAMES:
		var desc = Lab.body(body_name)
		var skin := SkinCpu.build(desc, int(rules["preview_divisions"]))
		check(MeshChecks.watertight(skin["indices"]), "%s skin is closed and one piece (%d triangles)"
				% [body_name, skin["indices"].size() / 3])
		check(MeshChecks.wrong_winding_fraction(skin) == 0.0, "%s skin winds clockwise seen from outside" % body_name)


## A random but valid spine: a wandering walk with smoothly varying thickness.
func random_valid_spine(rng: RandomNumberGenerator) -> RefCounted:
	while true:
		var d = BodyDescription.create()
		d.reference_length_mm = rng.randi_range(200, 4000)
		var count := rng.randi_range(3, 24)
		var step := 1100.0 / count
		var p := Vector3(0.0, 0.0, -550.0)
		var dir := Vector3(0.0, 0.0, 1.0)
		var r := rng.randf_range(60.0, 300.0)
		for i in count:
			d.add_vertebra(Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)), roundi(r))
			dir = dir.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7)).rotated(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
			p += dir * step
			r = clampf(r * rng.randf_range(0.7, 1.35), 40.0, 380.0)
		if d.validate(rules).is_empty():
			return d
	return null


func test_random_bodies_watertight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var closed := 0
	var fixes := 0
	var total := 25
	for i in total:
		var skin := SkinCpu.build(random_valid_spine(rng), int(rules["preview_divisions"]))
		fixes += int(skin["topology_fixes"])
		if MeshChecks.watertight(skin["indices"]) and MeshChecks.wrong_winding_fraction(skin) == 0.0:
			closed += 1
	check(closed == total, "%d of %d random valid spines give a closed, correctly wound skin (%d topology fixes)"
			% [closed, total, fixes])


func test_skin_deterministic() -> void:
	var desc = Lab.body("fish")
	var a := MeshChecks.mesh_hash(SkinCpu.build(desc, 48))
	var b := MeshChecks.mesh_hash(SkinCpu.build(desc, 48))
	check(a == b, "two builds of the same body give the same SHA-256")


func test_weights() -> void:
	var desc = Lab.body("snake")
	var skin := SkinCpu.build(desc, 48)
	var ok := true
	var w: PackedFloat32Array = skin["weights"]
	var bones: PackedInt32Array = skin["bones"]
	for v in w.size() / 4:
		var s := w[4 * v] + w[4 * v + 1] + w[4 * v + 2] + w[4 * v + 3]
		ok = ok and absf(s - 1.0) < 1e-5
		for k in 4:
			ok = ok and bones[4 * v + k] >= 0 and bones[4 * v + k] < desc.vertebrae.size()
	check(ok, "every vertex has four bone weights summing to 1 on real bones")


func test_paint_coordinates() -> void:
	var desc = straight(8, 150)  # head at -Z, tail at +Z
	var skin := SkinCpu.build(desc, 48)
	var v: PackedVector3Array = skin["vertices"]
	var c: PackedFloat32Array = skin["custom0"]
	var top := 0
	var right := 0
	var head := 0
	for i in v.size():
		if v[i].y > v[top].y:
			top = i
		if v[i].x > v[right].x:
			right = i
		if v[i].z < v[head].z:
			head = i
	var ring_top := minf(c[4 * top + 1], 1.0 - c[4 * top + 1])
	check(c.size() == 4 * v.size() and ring_top < 0.02 and absf(c[4 * right + 1] - 0.25) < 0.02
			and c[4 * head] < 0.02, "paint coordinates: back 0, right side 0.25, head end 0 (got %.3f, %.3f, %.3f)"
			% [ring_top, c[4 * right + 1], c[4 * head]])


func test_triangle_budget_large_body() -> void:
	var skin := SkinCpu.build(Lab.body("large"), int(rules["gameplay_divisions"]))
	var tris: int = skin["indices"].size() / 3
	check(tris < int(rules["gameplay_triangle_budget"]), "large body at the gameplay grid (length/%d) has %d triangles (budget %d)"
			% [int(rules["gameplay_divisions"]), tris, int(rules["gameplay_triangle_budget"])])
