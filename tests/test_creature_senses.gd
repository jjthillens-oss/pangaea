extends TestCase
## CreatureSenses (M1 step 3): a creature perceives a body by touch (near) or by sight (range, field
## of view and a line of sight past rocks), and food by range and field of view. Percepts are fresh
## copies sorted by (distance, id).

const SIGHT := 6.0
const NEAR := 1.0
const VIEWER_R := 0.75
const BODY_R := 0.5


## An ambush-hunter-like viewer at `at`, facing `heading`, with a 200 degree field of view.
func _viewer(at := Vector2(20.0, -11.0), heading := 0.0, fov_deg := 200.0) -> Dictionary:
	return {"id": "c_1", "species": "ambush_hunter", "position": at, "heading": heading,
		"radius": VIEWER_R, "sight": SIGHT, "fov": deg_to_rad(fov_deg), "near": NEAR}


func _body(id: String, at: Vector2, extra := {}) -> Dictionary:
	var b := {"id": id, "species": "lineage", "position": at, "velocity": Vector2(0.3, -0.2), "radius": BODY_R,
		"alive": true, "concealed": false, "engageable": true, "bite": false, "spikes": 0}
	b.merge(extra, true)
	return b


## The body's position at `distance` from the viewer and `bearing` from its heading.
func _at(viewer: Dictionary, distance: float, bearing: float) -> Vector2:
	return viewer.position + Vector2.from_angle(viewer.heading + bearing) * distance


func _ids(percepts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p in percepts:
		out.append(p.id)
	return out


func _open() -> PoolArena:
	return PoolArena.create(40.0, 36.0, 39.5)


func test_sight_reaches_exactly_its_range_plus_the_body_radius() -> void:
	for heading in [0.0, 2.0, -2.6]:
		var v := _viewer(Vector2(20.0, -11.0), heading)
		var inside := CreatureSenses.perceive(v, [_body("a", _at(v, SIGHT + BODY_R - 1e-3, 0.3))], _open())
		check_eq(_ids(inside), PackedStringArray(["a"]), "heading %.1f: just inside the range" % heading)
		if not inside.is_empty():
			check_eq(inside[0].by, "sight", "seen, not touched")
		var outside := CreatureSenses.perceive(v, [_body("a", _at(v, SIGHT + BODY_R + 1e-3, 0.3))], _open())
		check(outside.is_empty(), "heading %.1f: just outside the range" % heading)
	var big := CreatureSenses.perceive(_viewer(), [_body("big", _at(_viewer(), SIGHT + 0.75 - 1e-3, 0.0), {"radius": 0.75})], _open())
	check_eq(big.size(), 1, "a bigger body is seen from farther away")


func test_the_field_of_view_includes_its_edges_and_nothing_past_them() -> void:
	for fov_deg in [200.0, 270.0, 90.0]:
		for heading in [0.0, 1.0472, -2.9258]:
			var v := _viewer(Vector2(-9.4, -16.3), heading, fov_deg)
			var half := deg_to_rad(fov_deg) / 2.0
			for side in [1.0, -1.0]:
				var on_edge := CreatureSenses.perceive(v, [_body("a", _at(v, 4.0, side * half))], _open())
				check_eq(on_edge.size(), 1, "fov %d heading %.2f: on the %s edge" % [fov_deg, heading, "right" if side > 0 else "left"])
				var past := CreatureSenses.perceive(v, [_body("a", _at(v, 4.0, side * (half + 0.01)))], _open())
				check(past.is_empty(), "fov %d heading %.2f: 0.01 rad past the %s edge" % [fov_deg, heading, "right" if side > 0 else "left"])


func test_a_rock_in_the_line_hides_a_body_but_grazing_its_edge_does_not() -> void:
	var arena := _open()
	arena.add_rock("rock", Vector2(3.5, 0.0), 1.0)
	for y in [0.0, 0.5, 0.85]:
		var v := _viewer(Vector2(0.0, y), 0.0)
		var hidden := _body("a", Vector2(6.2, y))
		check_eq(CreatureSenses.perceive(v, [hidden], _open()).size(), 1, "%.2f m off: in range and view without the rock" % y)
		check(CreatureSenses.perceive(v, [hidden], arena).is_empty(), "%.2f m from the rock's center: hidden" % y)
	for y in [0.95, -0.95, 1.2]:
		var v := _viewer(Vector2(0.0, y), 0.0)
		check_eq(CreatureSenses.perceive(v, [_body("a", Vector2(6.2, y))], arena).size(), 1, "%.2f m from the rock's center: seen" % y)
	var past_it := _viewer(Vector2(5.0, 0.0), 0.0)
	check_eq(CreatureSenses.perceive(past_it, [_body("a", Vector2(9.0, 0.0))], arena).size(), 1, "a rock behind the viewer hides nothing")


func test_touch_ignores_the_field_of_view_and_rocks() -> void:
	var v := _viewer(Vector2.ZERO, 0.0)
	var reach := VIEWER_R + BODY_R + NEAR
	var behind := CreatureSenses.perceive(v, [_body("a", Vector2(-(reach - 1e-3), 0.0))], _open())
	check_eq(_ids(behind), PackedStringArray(["a"]), "touched from straight behind")
	if not behind.is_empty():
		check_eq(behind[0].by, "near", "by touch")
	check(CreatureSenses.perceive(v, [_body("a", Vector2(-(reach + 1e-3), 0.0))], _open()).is_empty(), "just out of touch, behind")
	var arena := _open()
	arena.add_rock("pebble", Vector2(1.0, 0.0), 0.2)
	var through := CreatureSenses.perceive(v, [_body("a", Vector2(2.0, 0.0))], arena)
	check_eq(_ids(through), PackedStringArray(["a"]), "touched through a pebble that blocks the line")
	if not through.is_empty():
		check_eq(through[0].by, "near", "touch wins over sight in front too")


func test_concealed_dead_and_the_viewer_itself_are_never_perceived() -> void:
	var v := _viewer(Vector2.ZERO, 0.0)
	var bodies := [
		_body("c_1", Vector2.ZERO),
		_body("hidden", Vector2(1.0, 0.0), {"concealed": true}),
		_body("dead", Vector2(0.0, 1.0), {"alive": false}),
		_body("seen", Vector2(3.0, 0.0)),
	]
	check_eq(_ids(CreatureSenses.perceive(v, bodies, _open())), PackedStringArray(["seen"]), "only the live, visible other body")


func test_percepts_come_nearest_first_with_ties_broken_by_id() -> void:
	var v := _viewer(Vector2(3.0, -4.0), 0.5, 360.0)
	# Four rings of eight: every sign and order of one offset, exact in float32, so each ring's
	# distances are exactly equal and only the id can order them.
	var offsets := []
	for base in [Vector2(0.75, 1.0), Vector2(1.5, 2.0), Vector2(2.25, 3.0), Vector2(3.0, 4.0)]:
		for swap in [false, true]:
			for sx in [1.0, -1.0]:
				for sy in [1.0, -1.0]:
					var o: Vector2 = Vector2(base.y, base.x) if swap else base
					offsets.append(Vector2(o.x * sx, o.y * sy))
	# Ids shuffled with a fixed seed, so neither the input order nor the ring order matches id order.
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var ids := []
	for i in offsets.size():
		ids.insert(rng.randi_range(0, i), "b_%02d" % i)
	var bodies := []
	for i in offsets.size():
		bodies.append(_body(ids[i], v.position + offsets[i]))
	var got := CreatureSenses.perceive(v, bodies, _open())
	check_eq(got.size(), 32, "every body perceived")
	var ties := 0
	for i in range(1, got.size()):
		var a: Dictionary = got[i - 1]
		var b: Dictionary = got[i]
		if a.distance == b.distance:
			ties += 1
			check(a.id < b.id, "equal distances: %s before %s" % [a.id, b.id])
		else:
			check(a.distance < b.distance, "%s (%.6f) before %s (%.6f)" % [a.id, a.distance, b.id, b.distance])
	check_eq(ties, 28, "seven exact ties in each ring")


func test_percepts_are_copies_that_carry_the_body_flags() -> void:
	var v := _viewer(Vector2.ZERO, 0.0)
	var body := _body("r", Vector2(3.0, 1.0), {"species": "rammer", "engageable": false, "bite": true, "spikes": 4, "radius": 0.625})
	var got := CreatureSenses.perceive(v, [body], _open())
	check_eq(got.size(), 1, "seen")
	if got.is_empty():
		return
	var p: Dictionary = got[0]
	check_eq(p.species, "rammer", "species")
	check_eq(p.engageable, false, "engageable passes through")
	check_eq(p.bite, true, "bite")
	check_eq(p.spikes, 4, "spikes")
	check_near(p.radius, 0.625, 1e-9, "radius")
	check_near(p.distance, Vector2(3.0, 1.0).length(), 1e-5, "distance")
	check_near(p.bearing, atan2(1.0, 3.0), 1e-5, "bearing")
	check_eq(p.velocity, Vector2(0.3, -0.2), "velocity")
	p.position = Vector2(99.0, 99.0)
	p.velocity = Vector2.ZERO
	check_eq(body.position, Vector2(3.0, 1.0), "changing the percept leaves the body alone")
	check_eq(body.velocity, Vector2(0.3, -0.2), "and its velocity")
	body.position = Vector2(-5.0, 0.0)
	check_eq(got[0].position, Vector2(99.0, 99.0), "and moving the body later leaves the percept alone")
	check(not is_same(got[0], body), "a new dictionary")
	var again := CreatureSenses.perceive(v, [_body("e", Vector2(3.0, 0.0))], _open())
	check_eq(again[0].engageable, true, "engageable true passes through too")


func test_the_bearing_is_positive_on_the_viewers_right() -> void:
	# Plane +y is south (screen down), so with heading 0 (east) a point at +y is on the right.
	var v := _viewer(Vector2(1.0, 1.0), 0.0)
	check_near(CreatureSenses.bearing(v, Vector2(1.0, 3.0)), PI / 2.0, 1e-6, "right")
	check_near(CreatureSenses.bearing(v, Vector2(1.0, -1.0)), -PI / 2.0, 1e-6, "left")
	check_near(absf(CreatureSenses.bearing(v, Vector2(-1.0, 1.0))), PI, 1e-6, "behind")
	var north := _viewer(Vector2.ZERO, -PI / 2.0)
	check_near(CreatureSenses.bearing(north, Vector2(2.0, 0.0)), PI / 2.0, 1e-6, "facing north, east is on the right")


## Food sense takes no arena, so rocks never hide food; and it has no touch, so food behind is missed.
func test_food_is_found_by_range_and_field_of_view_only() -> void:
	var v := _viewer(Vector2.ZERO, 0.0)
	var items := [
		{"id": "cr_2", "kind": "meat", "position": Vector2(5.0, 0.0), "radius": 0.3},
		{"id": "cr_1", "kind": "meat", "position": Vector2(0.0, 5.0), "radius": 0.3},
		{"id": "pk_1", "kind": "plant", "position": Vector2(2.0, 0.0), "radius": 0.18},
		{"id": "cr_3", "kind": "meat", "position": Vector2(-1.5, 0.0), "radius": 0.3},
		{"id": "cr_4", "kind": "meat", "position": Vector2(SIGHT + 0.3 + 1e-3, 0.0), "radius": 0.3},
		{"id": "cr_5", "kind": "meat", "position": Vector2(SIGHT + 0.3 - 1e-3, 0.5).normalized() * (SIGHT + 0.3 - 1e-3), "radius": 0.3},
	]
	var got := CreatureSenses.perceive_food(v, items, PackedStringArray(["meat"]))
	check_eq(_ids(got), PackedStringArray(["cr_1", "cr_2", "cr_5"]), "meat in range and view, ties by id")
	check_eq(_ids(CreatureSenses.perceive_food(v, items, PackedStringArray(["plant"]))), PackedStringArray(["pk_1"]), "only the asked kinds")
	check(CreatureSenses.perceive_food(v, items, PackedStringArray()).is_empty(), "no diet, no food")
	var narrow := _viewer(Vector2.ZERO, 0.0, 90.0)
	check_eq(_ids(CreatureSenses.perceive_food(narrow, items, PackedStringArray(["meat"]))), PackedStringArray(["cr_2", "cr_5"]), "a narrower view misses the one to the side")
	if got.size() == 3:
		check_eq(got[0].kind, "meat", "kind")
		check_near(got[0].distance, 5.0, 1e-6, "distance")
		check(got[0].has("bearing") and got[0].has("radius") and got[0].has("position"), "the food percept's fields")
