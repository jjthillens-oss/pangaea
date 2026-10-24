extends TestCase
## Part anchors on the skin (game/domain/creature/anchor_resolver.gd, editor_picking.gd), ported from the creature
## lab's tests/run_stage1_tests.gd and tests/run_editor_tests.gd: every part sits on the skin, twins are exact mirror
## images, parts ride along when the body changes, and a skin point -> anchor -> resolver round trip lands back.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")

## Picking round trip: a skin point -> anchor -> resolver must land this close, as a fraction of body length, for
## this share of the skin's vertices. The rest are in the fillets where a limb meets the trunk: the click picks the
## limb, and the resolver's ray from the limb axis finds the skin a little way off.
const ROUND_TRIP_MAX := 0.01
const ROUND_TRIP_SHARE := 0.95

var rules := {}
var orient := {}


func before_each() -> void:
	rules = CreatureData.rules()
	orient = CreatureData.part_orientations()


## Distance from p to the skin, to first order (field offset over gradient length).
func skin_distance(field: RefCounted, p: Vector3, h: float) -> float:
	var g := Vector3(field.sample(p + Vector3(h, 0, 0)) - field.sample(p - Vector3(h, 0, 0)),
			field.sample(p + Vector3(0, h, 0)) - field.sample(p - Vector3(0, h, 0)),
			field.sample(p + Vector3(0, 0, h)) - field.sample(p - Vector3(0, 0, h))) / (2.0 * h)
	return absf(field.sample(p) - BodyField.ISO) / maxf(g.length(), 1e-9)


func test_parts_sit_on_skin() -> void:
	for body_name in Fixtures.starter_names():
		var desc = Fixtures.body(body_name)
		if desc.parts.is_empty():
			continue
		var field = BodyField.from_description(desc)
		var placed := AnchorResolver.resolve_all(desc, field, orient)
		var length: float = desc.bounds_m().get_longest_axis_size()
		var worst := 0.0
		var twins_exact := true
		var expected := 0
		for p in desc.parts:
			expected += 2 if p["mirror"] else 1
		for k in placed.size():
			var e: Dictionary = placed[k]
			var part: Dictionary = desc.parts.filter(func(x): return x["id"] == e["part"])[0]
			if orient.get(part["type"], "normal") != "ground" and int(part["height"]) == 0:
				worst = maxf(worst, skin_distance(field, e["transform"].origin, 0.002 * length) / length)
			if e["twin"]:
				var o: Transform3D = placed[k - 1]["transform"]
				var t: Transform3D = e["transform"]
				twins_exact = twins_exact and t.origin.is_equal_approx(Vector3(-o.origin.x, o.origin.y, o.origin.z)) \
						and t.basis.determinant() < 0.0
		check(placed.size() == expected and worst < 0.002 and twins_exact,
				"%s: %d placements, each on the skin (worst %.3f%% of body length off), twins are exact mirror images"
				% [body_name, placed.size(), 100.0 * worst])


func test_parts_ride_along() -> void:
	# Thicken the quadruped's head and neck by half: the eyes and horns must move out and stay on the skin.
	var desc = Fixtures.body("s1_quadruped")
	var before := AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orient)
	for i in 3:
		desc.vertebrae[i]["r"] = int(desc.vertebrae[i]["r"] * 1.5)
	var field = BodyField.from_description(desc)
	var after := AnchorResolver.resolve_all(desc, field, orient)
	var ok: bool = desc.validate(rules).is_empty()
	var length: float = desc.bounds_m().get_longest_axis_size()
	for k in 2:
		ok = ok and after[k]["transform"].origin.distance_to(before[k]["transform"].origin) > 0.01 \
				and skin_distance(field, after[k]["transform"].origin, 0.002 * length) / length < 0.002
	check(ok, "after the head is thickened by half, the eyes move with the skin and stay on it")


func test_mirrored_transform_is_the_reflection_across_x() -> void:
	var t := Transform3D(Basis(Vector3(0.3, 1.2, -0.4).normalized(), 0.7), Vector3(0.25, 0.1, -0.5))
	var m: Transform3D = AnchorResolver.mirrored(t)
	check(m.origin.is_equal_approx(Vector3(-0.25, 0.1, -0.5)), "the origin is reflected across X = 0")
	check(m.basis.determinant() < 0.0, "the basis is a reflection")
	check(AnchorResolver.mirrored(m).is_equal_approx(t), "mirroring twice gives the transform back")


func test_pick_round_trip() -> void:
	for body_name in Fixtures.starter_names():
		var desc = Fixtures.body(body_name)
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
