extends TestCase
## The creature body description, codec and capsule field (game/domain/creature/), ported from the creature lab's
## tests/run_spine_tests.gd and tests/run_stage1_tests.gd: validation limits, byte-identical round trips, ids,
## the size budget, part placement rules and the field around the capsules.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const BodyDescription := preload("res://game/domain/creature/body_description.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")

var rules := {}


func before_each() -> void:
	rules = CreatureData.rules()


func straight(count: int, r: int, ref_mm := 1000) -> RefCounted:
	var d = BodyDescription.create()
	d.reference_length_mm = ref_mm
	for i in count:
		d.add_vertebra(Vector3i(0, 0, -500 + i * 1000 / maxi(1, count - 1)), r)
	return d


func quad() -> RefCounted:
	return Fixtures.body("s1_quadruped")


func test_spine_and_starter_bodies_are_valid() -> void:
	for body_name in Fixtures.SPINE_BODY_NAMES:
		var problems: PackedStringArray = Fixtures.body(body_name).validate(rules)
		check(problems.is_empty(), "%s is valid %s" % [body_name, "" if problems.is_empty() else str(problems)])
	for body_name in Fixtures.starter_names():
		var problems: PackedStringArray = Fixtures.body(body_name).validate(rules)
		check(problems.is_empty(), "%s is valid %s" % [body_name, "" if problems.is_empty() else str(problems)])


func test_validation_refuses_each_spine_limit() -> void:
	check(straight(3, 120).validate(rules).is_empty(), "boundary: 3 vertebrae accepted")
	check(straight(24, 120).validate(rules).is_empty(), "boundary: 24 vertebrae accepted")
	var cases := {
		"2 vertebrae": straight(2, 120),
		"25 vertebrae": straight(25, 120),
		"radius above 400": straight(5, 401),
		"radius below 20": straight(5, 19),
	}
	var thin = straight(8, 20)  # 20/1000 of a 1 m body is under 1.5 cells of the finest preview grid, length/72
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


func test_validation_refuses_limb_limits() -> void:
	var cases := {}
	var missing = quad()
	missing.limbs[0]["attach"] = "v_99"
	cases["limb on a missing vertebra"] = missing
	var away = quad()
	away.limbs[0]["joints"][0]["p"] = [400, -40, -260]
	cases["limb starting away from its vertebra"] = away
	var crossing = quad()
	crossing.limbs[0]["joints"][2]["p"] = [10, -480, -260]
	cases["mirrored limb reaching its copy"] = crossing
	var middle = quad()
	middle.limbs[1]["joints"][0]["p"] = [0, -30, 160]
	cases["mirrored limb starting on the middle plane"] = middle
	var one_joint = quad()
	one_joint.limbs[0]["joints"] = [one_joint.limbs[0]["joints"][0]]
	cases["limb with one joint"] = one_joint
	var six = quad()
	for k in 2:
		var extra: Dictionary = (six.limbs[0]["joints"][-1] as Dictionary).duplicate(true)
		extra["id"] = "j_%d" % int(six.next_ids["j"])
		six.next_ids["j"] = int(six.next_ids["j"]) + 1
		extra["p"] = [110, -520, -340 - 40 * k]
		six.limbs[0]["joints"].append(extra)
	cases["limb with six joints"] = six
	var folded = quad()
	folded.limbs[0]["joints"][2]["p"] = [110, -40, -230]
	cases["limb folding back"] = folded
	var thin = quad()
	thin.limbs[0]["joints"][3]["r"] = 20
	cases["joint too thin for the grid"] = thin
	var too_many = quad()
	for k in 11:
		too_many.add_limb("v_5", [[Vector3i(90, 0, 20), 50], [Vector3i(200, -100, 20), 40]])
	cases["13 limbs"] = too_many
	var dup = quad()
	dup.limbs[1]["joints"][0]["id"] = dup.limbs[0]["joints"][0]["id"]
	cases["duplicate joint id"] = dup
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
	for body_name in Fixtures.SPINE_BODY_NAMES:
		var text := BodyCodec.encode(Fixtures.body(body_name))
		ok = ok and BodyCodec.encode(BodyCodec.decode(text)) == text
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 1000:
		var text := BodyCodec.encode(random_body(rng))
		ok = ok and BodyCodec.encode(BodyCodec.decode(text)) == text
	check(ok, "encode -> decode -> encode is byte-identical for the 7 spine bodies and 1000 random bodies")


func test_codec_round_trip_and_size_for_starter_bodies() -> void:
	var ok := true
	var largest := 0
	for body_name in Fixtures.starter_names():
		var desc = Fixtures.body(body_name)
		var text := BodyCodec.encode(desc)
		ok = ok and BodyCodec.encode(BodyCodec.decode(text)) == text
		var save_text := JSON.stringify({"save_version": 2, "body": desc.to_dict()})
		ok = ok and BodyCodec.encode(BodyCodec.from_dict(JSON.parse_string(save_text)["body"])) == text
		largest = maxi(largest, text.length())
	check(ok, "the ten starter bodies round-trip byte-identically, directly and through a save's JSON")
	check(largest <= int(rules["size_budget_bytes"]), "starter bodies encode in at most %d bytes (budget %d)"
			% [largest, int(rules["size_budget_bytes"])])


func test_codec_survives_save_json() -> void:
	# A save writes the description as part of a bigger JSON document with Godot's default writer.
	var ok := true
	for body_name in Fixtures.SPINE_BODY_NAMES:
		var desc = Fixtures.body(body_name)
		var save_text := JSON.stringify({"save_version": 2, "body": desc.to_dict()})
		var back: Dictionary = JSON.parse_string(save_text)
		ok = ok and BodyCodec.encode(BodyCodec.from_dict(back["body"])) == BodyCodec.encode(desc)
	check(ok, "a body written into a save with Godot's default JSON and read back encodes to the same text")


func test_codec_keeps_unknown_and_reports_bad() -> void:
	var text := BodyCodec.encode(Fixtures.body("bean"))
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


func test_version_1_body_loads() -> void:
	var desc = Fixtures.body("bean")
	check(desc.limbs.is_empty() and desc.validate(rules).is_empty() and int(desc.next_ids["l"]) == 1,
			"a version 1 spine body still loads, with no limbs")


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


func test_parts_valid_and_refused() -> void:
	var pr := CreatureData.part_rules()
	check(pr.size() >= 5, "part rules read from the art records (%s)" % ", ".join(pr.keys()))
	for body_name in Fixtures.starter_names():
		var problems: PackedStringArray = Fixtures.body(body_name).validate_parts(rules, pr)
		if not Fixtures.body(body_name).parts.is_empty():
			check(problems.is_empty(), "%s parts are allowed where they are %s" % [body_name, "" if problems.is_empty() else str(problems)])
	var cases := {}
	var beak = quad()
	beak.parts[1]["ring"] = 250
	beak.parts[1]["elev"] = 30
	cases["beak off the middle line"] = beak
	var horn = quad()
	horn.parts[2]["ring"] = 0
	cases["chiral horn on the middle line"] = horn
	var eye_on_leg = quad()
	eye_on_leg.parts[0]["host"] = "l_1"
	cases["eye on a leg"] = eye_on_leg
	var foot_on_spine = quad()
	foot_on_spine.parts[4]["host"] = "spine"
	cases["foot on the spine"] = foot_on_spine
	var turned = quad()
	turned.parts[0]["turn"] = 90
	cases["eye turned past its limit"] = turned
	var scaled = quad()
	scaled.parts[0]["scale"] = 3000
	cases["part at 3x scale"] = scaled
	var missing = quad()
	missing.parts[4]["host"] = "l_9:end"
	cases["part on a missing limb"] = missing
	var giant = Fixtures.body("s1_giant_limb")
	giant.add_part("fin", {"host": "l_1", "u": 500, "ring": 250, "mirror": true})
	cases["twin on a limb with no mirror copy"] = giant
	for what in cases:
		var problems: PackedStringArray = cases[what].validate_parts(rules, pr)
		check(not problems.is_empty(), "refused: %s (%s)" % [what, problems[0] if not problems.is_empty() else "accepted!"])


## The capsule field: one capsule per spine segment and limb segment, inside the body under the iso value and
## outside above it, with the skin found between.
func test_field_is_inside_below_iso_and_outside_above() -> void:
	var desc = quad()
	var field = BodyField.from_description(desc)
	var segments: int = desc.vertebrae.size() - 1
	for c in desc.limb_chains():
		segments += (c["points"] as PackedVector3Array).size() - 1
	check_eq(field.capsule_count(), segments, "one capsule per spine and limb segment")
	var centre: Vector3 = desc.position_m(desc.vertebrae.size() / 2)
	check(field.sample(centre) > BodyField.ISO, "the field at a vertebra centre is above the iso value (inside)")
	check(field.sample(centre + Vector3(0, 5.0, 0)) < BodyField.ISO, "five metres above the body is outside")
	var r: float = desc.radius_m(desc.vertebrae.size() / 2)
	var inside: float = field.sample(centre + Vector3(0, 0.5 * r, 0))
	var outside: float = field.sample(centre + Vector3(0, 1.5 * r, 0))
	check(inside > BodyField.ISO and outside < BodyField.ISO, "the skin lies between half and one and a half radii out")
	check(field.normal(centre + Vector3(0, r, 0), 0.001).dot(Vector3.UP) > 0.9, "the field normal on top points up")
