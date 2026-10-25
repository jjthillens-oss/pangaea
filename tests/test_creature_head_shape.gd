extends TestCase
## The head shape dials (game/domain/creature/head_shape.gd): the block in the body's extra dictionary, its ranges
## from body_rules.json, the capsules BodyField adds around the head end (the skin changes, the vertebrae do not),
## parts on the head still land on the skin, the codec round trip through a save's JSON, and the editor session's
## set_head_shape with its refusals, undo, redo and gesture, at no cost, and that the dials stay cosmetic: they do not
## change mass or any creature stat built on it.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const HeadShape := preload("res://game/domain/creature/head_shape.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const Session := preload("res://game/domain/creature/creature_editor_session.gd")
const Sim := preload("res://game/systems/creature/creature_world_sim.gd")

var rules := {}


func before_each() -> void:
	rules = CreatureData.rules()


## A preset's body with its own head shape taken off, so the dials start from neutral.
func plain_body(preset: String) -> RefCounted:
	var desc = CreatureData.preset_body(preset)
	desc.extra.erase(HeadShape.KEY)
	return desc


func shaped(shape: Dictionary, preset := "prowler") -> RefCounted:
	var desc = plain_body(preset)
	HeadShape.store(desc.extra, shape)
	return desc


## Distance from the head centre to the skin along `dir` (body space), by the anchor resolver's march.
static func reach(desc: RefCounted, dir: Vector3) -> float:
	var field = BodyField.from_description(desc)
	var c: Vector3 = desc.position_m(0)
	return AnchorResolver._march(field, c, dir.normalized(), desc.radius_m(0)).distance_to(c)


func test_the_ranges_come_from_the_body_rules() -> void:
	var r: Dictionary = HeadShape.ranges(rules)
	check_eq(r["width"], [600, 1600], "skull width 0.6x to 1.6x")
	check_eq(r["height"], [600, 1600], "skull height 0.6x to 1.6x")
	check_eq(r["snout"], [1000, 2000], "snout 1.0x to 2.0x")
	check_eq(r["jaw"], [0, 1000], "jaw 0 to 100%")
	check_eq(r["brow"], [0, 1000], "brow 0 to 100%")


func test_a_neutral_shape_stores_nothing_and_changes_nothing() -> void:
	var desc = plain_body("prowler")
	var before := BodyCodec.encode(desc)
	var field_before = BodyField.from_description(desc)
	HeadShape.store(desc.extra, HeadShape.DEFAULTS)
	check(not desc.extra.has(HeadShape.KEY) and BodyCodec.encode(desc) == before, "the neutral shape leaves no block")
	var field_after = BodyField.from_description(desc)
	check_eq(field_after.capsule_count(), field_before.capsule_count(), "no extra capsules")
	check_eq(field_after.shape_from, field_after.capsule_count(), "the chains end at the last capsule")


func test_the_block_is_whole_number_floats_and_reads_back_as_ints() -> void:
	var desc := shaped({"snout": 1500, "width": 800})
	var block: Dictionary = desc.extra[HeadShape.KEY]
	check(block["snout"] is float and block["snout"] == 1500.0 and block["brow"] == 0.0, "floats, all five keys")
	var shape := HeadShape.of(desc.extra)
	check(shape["snout"] is int and shape["snout"] == 1500 and shape["width"] == 800 and shape["height"] == 1000,
			"read back as ints with the defaults (%s)" % str(shape))
	check(HeadShape.of({HeadShape.KEY: {"snout": 1500.5, "width": "x"}}) == HeadShape.DEFAULTS,
			"a non-whole or non-number value reads as the default")


func test_validation_refuses_values_outside_the_ranges() -> void:
	check(shaped({"snout": 2000, "width": 600, "height": 1600, "jaw": 1000, "brow": 1000}).validate(rules).is_empty(),
			"the range ends are valid")
	for bad in [{"snout": 900}, {"snout": 2050}, {"width": 550}, {"height": 1650}, {"jaw": -50}, {"brow": 1050}]:
		var desc := shaped({})
		desc.extra[HeadShape.KEY] = {"snout": 1000.0, "width": 1000.0, "height": 1000.0, "jaw": 0.0, "brow": 0.0}
		for k in bad:
			desc.extra[HeadShape.KEY][k] = float(bad[k])
		var problems: PackedStringArray = desc.validate(rules)
		check(problems.size() == 1 and problems[0].begins_with("head "), "%s is refused (%s)" % [str(bad), str(problems)])
	var odd := shaped({})
	odd.extra[HeadShape.KEY] = {"snout": 1000.0, "tusks": 3.0}
	check(not odd.validate(rules).is_empty(), "an unknown dial is reported")
	odd.extra[HeadShape.KEY] = "round"
	check(not odd.validate(rules).is_empty(), "a block that is not an object is reported")


func test_each_dial_moves_the_skin_and_leaves_the_vertebrae() -> void:
	var plain := plain_body("prowler")
	var fwd: Vector3 = (plain.position_m(0) - plain.position_m(1)).normalized()
	var side := Vector3.RIGHT
	var up := Vector3.UP
	var base := {"fwd": reach(plain, fwd), "side": reach(plain, side), "up": reach(plain, up), "down": reach(plain, -up),
			"brow": reach(plain, fwd + up)}
	var cases := [
		[{"snout": 2000}, "fwd", 1.6], [{"width": 1600}, "side", 1.4], [{"width": 600}, "side", -0.75],
		[{"height": 1600}, "up", 1.4], [{"height": 600}, "up", -0.75], [{"jaw": 1000}, "down", 1.3],
		[{"brow": 1000}, "brow", 1.15],
	]
	for c in cases:
		var desc := shaped(c[0])
		var d := reach(desc, {"fwd": fwd, "side": side, "up": up, "down": -up, "brow": fwd + up}[c[1]])
		var ratio: float = d / float(base[c[1]])
		var want: float = c[2]
		var ok := ratio >= want if want > 0.0 else ratio <= -want
		check(ok, "%s: the skin %s is %.2fx the plain head's (want %s %.2f)" % [str(c[0]), c[1], ratio,
				">=" if want > 0.0 else "<=", absf(want)])
		check(desc.vertebrae == plain.vertebrae and desc.limbs == plain.limbs, "%s leaves the skeleton" % str(c[0]))
	var long := shaped({"snout": 2000, "height": 1600})
	check(long.bounds_m().position.z < plain.bounds_m().position.z - plain.radius_m(0)
			and long.bounds_m().end.y > plain.bounds_m().end.y, "the bounds grow with the head, so the skin grid holds it")


func test_head_capsules_ride_on_the_head_bone_and_paint_as_the_head_end() -> void:
	var desc := shaped({"snout": 1800, "width": 1300, "jaw": 600, "brow": 600})
	var field = BodyField.from_description(desc)
	check(field.capsule_count() - field.shape_from == 4, "a bar, a snout, a jaw and a brow (%d)"
			% (field.capsule_count() - field.shape_from))
	for k in range(field.shape_from, field.capsule_count()):
		check(field.bone_a[k] == 0 and field.bone_b[k] == 0 and field.limb[k] == 0.0, "capsule %d is on bone 0" % k)
	var tip: Vector3 = field.b[field.shape_from + 1]
	check(field.paint_coords(tip).x < 0.01, "the snout tip paints at the head end (%.3f)" % field.paint_coords(tip).x)


func test_head_parts_follow_the_skin() -> void:
	var plain := plain_body("prowler")
	var desc := shaped({"snout": 2000, "width": 1500, "height": 700})
	var orientations := CreatureData.part_orientations()
	var before := AnchorResolver.resolve_all(plain, BodyField.from_description(plain), orientations)
	var after := AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations)
	check_eq(after.size(), before.size(), "every part still resolves")
	var field = BodyField.from_description(desc)
	for i in after.size():
		var p: Vector3 = (after[i]["transform"] as Transform3D).origin
		var part: Dictionary = {}
		for q in desc.parts:
			if q["id"] == after[i]["part"]:
				part = q
		if int(part["height"]) != 0 or String(part["host"]) != "spine":
			continue
		check(absf(field.sample(p) - BodyField.ISO) < 0.01, "part %s sits on the shaped skin" % after[i]["part"])
	# A part straight off the head end rides out to the snout tip.
	plain.add_part("beak", {"host": "spine", "u": 0, "ring": 0, "elev": 0})
	desc.add_part("beak", {"host": "spine", "u": 0, "ring": 0, "elev": 0})
	var beak_before := _origin_of(plain, AnchorResolver.resolve_all(plain, BodyField.from_description(plain), orientations), "beak")
	var beak_after := _origin_of(desc, AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), "beak")
	check(beak_after.z < beak_before.z - 0.75 * desc.radius_m(0), "a beak on the head end moves out to the snout tip (%.3f -> %.3f)"
			% [beak_before.z, beak_after.z])


static func _origin_of(desc: RefCounted, placed: Array, type: String) -> Vector3:
	for e in placed:
		for q in desc.parts:
			if q["id"] == e["part"] and q["type"] == type and not e["twin"]:
				return (e["transform"] as Transform3D).origin
	return Vector3.INF


func test_the_codec_keeps_the_block_through_a_save() -> void:
	var desc := shaped({"snout": 1650, "width": 1250, "height": 900, "jaw": 400, "brow": 750})
	var text := BodyCodec.encode(desc)
	check(text.contains("\"head_shape\""), "the block is written")
	check_eq(BodyCodec.encode(BodyCodec.decode(text)), text, "encode -> decode -> encode is byte-identical")
	var save_text := JSON.stringify({"save_version": 2, "body": desc.to_dict()})
	var back = BodyCodec.from_dict(JSON.parse_string(save_text)["body"])
	check_eq(BodyCodec.encode(back), text, "and through a save's JSON")
	check_eq(HeadShape.of(back.extra), HeadShape.of(desc.extra), "the dials come back")
	check(back.validate(rules).is_empty(), "and validate")


func test_to_dict_does_not_share_the_block() -> void:
	var desc := shaped({"snout": 1500})
	var d: Dictionary = desc.to_dict()
	(desc.extra[HeadShape.KEY] as Dictionary)["snout"] = 1900.0
	check_eq(float(d[HeadShape.KEY]["snout"]), 1500.0, "a snapshot keeps its own copy")


func test_the_session_sets_dials_with_undo_and_refusals_at_no_cost() -> void:
	var s = Session.new(plain_body("monkey"), rules, CreatureData.part_rules(),
			CreatureData.editor_costs(), 10)
	var start := BodyCodec.encode(s.working)
	check_eq(s.head_shape(), HeadShape.DEFAULTS, "a preset starts neutral")
	var r: Dictionary = s.set_head_shape("snout", 1700)
	check(r["ok"] and s.head_shape()["snout"] == 1700, "snout set %s" % r["reason"])
	r = s.set_head_shape("width", 1400)
	check(r["ok"] and s.cost() == 0 and s.preview()["errors"].is_empty(), "the dials are free and valid")
	var edited := BodyCodec.encode(s.working)
	for bad in [["snout", 2100], ["width", 500], ["height", 1700], ["jaw", -1], ["brow", 1001], ["horns", 500]]:
		r = s.set_head_shape(bad[0], bad[1])
		check(not r["ok"] and BodyCodec.encode(s.working) == edited, "%s %d is refused (%s)" % [bad[0], bad[1], r["reason"]])
	check(s.undo() and s.undo() and BodyCodec.encode(s.working) == start, "two undos give back the preset")
	check(s.redo() and s.redo() and BodyCodec.encode(s.working) == edited, "two redos give back the edit")
	s.begin_gesture()
	for v in [1100, 1200, 1300, 1400, 1500]:
		s.set_head_shape("jaw", v - 1000)
	s.end_gesture()
	check(s.undo() and BodyCodec.encode(s.working) == edited, "a slider drag is one undo step")
	s.set_head_shape("height", 1300)
	var c: Dictionary = s.commit()
	check(c["ok"] and HeadShape.of(c["body"].extra)["height"] == 1300 and c["points_left"] == 10,
			"commit carries the head and spends nothing")


func test_the_dials_are_cosmetic_and_leave_mass_and_stats_alone() -> void:
	var tuning: Dictionary = Sim.load_tuning()
	var table = CreatureData.gait_table()
	var part_rules: Dictionary = CreatureData.part_rules()
	var maxed := {"snout": 2000, "width": 1600, "height": 600, "jaw": 1000, "brow": 1000}
	var tall := {"snout": 1000, "width": 600, "height": 1600, "jaw": 0, "brow": 0}
	for preset in ["monkey", "prowler"]:
		var plain = plain_body(preset)
		var base: Dictionary = CreatureStats.of(plain, part_rules, table, tuning)
		var base_editor: Dictionary = Session.stats(plain)
		for shape in [maxed, tall]:
			var desc := shaped(shape, preset)
			check(BodyField.from_description(desc).capsule_count() > BodyField.from_description(plain).capsule_count(),
					"%s: the shape adds capsules" % preset)
			var st: Dictionary = CreatureStats.of(desc, part_rules, table, tuning)
			for key in ["mass_kg", "max_health", "bite_power", "speed_mps", "speed_factor"]:
				check(is_equal_approx(float(st[key]), float(base[key])),
						"%s %s: %s stays %s with %s" % [preset, key, st[key], base[key], shape])
			check(is_equal_approx(float(Session.stats(desc)["mass_kg"]), float(base_editor["mass_kg"])),
					"%s: the editor panel's mass stays put" % preset)
