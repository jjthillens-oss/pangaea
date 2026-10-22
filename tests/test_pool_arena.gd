extends TestCase

const DT := 1.0 / 60.0
const BODY_R := 0.5

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _body(body_name: String) -> Phenotype:
	var r := Lineage.found(1, "test+dev", catalog, body_name)
	return Phenotype.derive(r.save.genome, catalog)


## A swimmer at the catalog's speed cap: the hardest case for rocks.
func _fastest() -> Phenotype:
	var p := Phenotype.new()
	p.speed = float(catalog.caps.speed)
	p.acceleration = float(catalog.caps.acceleration)
	p.turn_rate = float(catalog.caps.turn_rate)
	return p


func _pool() -> PoolArena:
	return PoolArena.create(40.0, 36.0, 39.5)


## Rocks packed closely in a small pool, so random swimming hits them and the wall all the time.
## The narrowest gap (1.2 m) still fits the cell, as in the real layout.
func _crowded() -> PoolArena:
	var arena := PoolArena.create(12.0, 9.0, 11.0)
	var rocks := [[Vector2(0.0, 0.0), 1.5], [Vector2(3.7, 0.0), 1.0], [Vector2(-3.4, 1.0), 0.8], [Vector2(1.0, 4.2), 1.3],
		[Vector2(-1.5, -4.0), 1.2], [Vector2(5.5, 4.5), 0.9], [Vector2(-6.0, -3.0), 1.1], [Vector2(4.0, -5.0), 0.8]]
	for i in rocks.size():
		arena.add_rock("rock_%d" % i, rocks[i][0], rocks[i][1])
	return arena


func _deepest_rock_overlap(arena: PoolArena, p: Vector2) -> float:
	var worst := 0.0
	for rock in arena.rocks:
		worst = maxf(worst, rock.radius + BODY_R - p.distance_to(rock.center))
	return worst


func _step(arena: PoolArena, m: Locomotion.MotionState, move: Vector2, p: Phenotype) -> float:
	Locomotion.steer(m, move, p, 1.0, DT)
	return arena.move(m, BODY_R, DT)


func test_random_swimming_never_enters_a_rock_or_leaves_the_pool() -> void:
	var arena := _crowded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	for p in [_fastest(), _body("grazer")]:
		var m := Locomotion.MotionState.new(Vector2(-2.0, 2.5))
		var move := Vector2.ZERO
		var hits := 0
		for i in 10000:
			if i % 40 == 0:
				move = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0)
			_step(arena, m, move, p)
			var overlap := _deepest_rock_overlap(arena, m.position)
			if overlap > -0.01:
				hits += 1
			if overlap > 0.001 or m.position.length() > arena.hard_radius - BODY_R + 1e-6:
				check(false, "tick %d: overlap %.4f m, r %.3f" % [i, overlap, m.position.length()])
				return
		check(hits > 100, "the fuzz actually touched rocks (%d ticks)" % hits)


func test_a_glancing_contact_slides_past_the_rock() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2(5.0, 0.0), 1.0)
	var p := _body("grazer")
	var m := Locomotion.MotionState.new(Vector2(0.0, -0.8))
	var touched_at := -1
	for i in 600:
		_step(arena, m, Vector2.RIGHT, p)
		var dist := m.position.distance_to(Vector2(5.0, 0.0))
		if touched_at < 0 and dist <= 1.5 + 1e-4:
			touched_at = i
		if touched_at >= 0 and m.position.x > 5.0 and dist > 1.5 + 0.01:
			check((i - touched_at) * DT <= 3.0, "cleared %.2f s after first contact" % ((i - touched_at) * DT))
			return
	check(touched_at >= 0, "touched the rock")
	check(false, "never cleared the rock")


func test_steering_away_from_a_touching_rock_separates_quickly() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2.ZERO, 1.0)
	var p := _body("hunter")
	# Resting against the rock's north side, heading along it; then asked to swim straight away.
	var m := Locomotion.MotionState.new(Vector2(0.0, -1.5), 0.0)
	for i in 30:
		_step(arena, m, Vector2.UP, p)
	check(m.position.length() > 1.5 + 0.05, "separated within 0.5 s: %.3f m from the centre" % m.position.length())


func test_no_tunneling_through_the_smallest_rock_at_top_speed() -> void:
	var arena := _pool()
	arena.add_rock("small", Vector2(3.0, 0.0), 0.8)
	var m := Locomotion.MotionState.new()
	for i in 120:
		m.velocity = Vector2(6.0, 0.0)
		arena.move(m, BODY_R, DT)
		if m.position.x > 3.0 - 1.3 + 0.001:
			check(false, "tick %d: at x %.3f, past the rock's near side" % [i, m.position.x])
			return


func test_full_thrust_into_the_wall_settles_inside_the_soft_band() -> void:
	var arena := _pool()
	for body_name in ["grazer", "hunter"]:
		var p := _body(body_name)
		var m := Locomotion.MotionState.new(Vector2(30.0, 0.0))
		var furthest := 0.0
		for i in 20 * 60:
			_step(arena, m, Vector2.RIGHT, p)
			furthest = maxf(furthest, m.position.length())
		var settled := m.position.length()
		check(settled >= 37.5 and settled <= 39.0, "%s settles at %.2f m" % [body_name, settled])
		# The failsafe clamps at 39.0 m, so stopping short of it shows the soft band did the holding.
		var failsafe := arena.hard_radius - BODY_R
		check(furthest <= failsafe - 0.1, "%s is held by the soft band, short of the %.1f m failsafe (%.3f)"
			% [body_name, failsafe, furthest])
		var back := -1.0
		for i in 10 * 60:
			_step(arena, m, Vector2.ZERO, p)
			if m.position.length() < 36.5:
				back = (i + 1) * DT
				break
		check(back > 0.0, "%s drifts back inside 36.5 m within 10 s" % body_name)


func test_the_hard_limit_holds_even_at_top_speed() -> void:
	# With no return current the soft band alone only slows the cell toward the hard radius, so
	# only the failsafe can stop it at 39 m.
	var arena := PoolArena.create(40.0, 36.0, 39.5, 0.0)
	var m := Locomotion.MotionState.new(Vector2(38.0, 0.0))
	for i in 120:
		m.velocity = Vector2(6.0, 0.0)
		arena.move(m, BODY_R, DT)
	check(m.position.length() <= 39.0 + 1e-6, "clamped at hard - body radius: %.3f" % m.position.length())
	check(m.position.length() >= 39.0 - 1e-4, "pressed against the limit: %.4f" % m.position.length())
	check(m.velocity.dot(m.position.normalized()) <= 1e-6, "the clamp removes the outward velocity: %s" % m.velocity)


func test_the_returned_distance_is_the_actual_displacement() -> void:
	var arena := _crowded()
	var p := _fastest()
	var m := Locomotion.MotionState.new(Vector2(-2.0, 2.5))
	for i in 600:
		var before := m.position
		var d := _step(arena, m, Vector2.from_angle(i * 0.01), p)
		if absf(d - m.position.distance_to(before)) > 1e-9 or m.prev_position != before:
			check(false, "tick %d: returned %.5f, moved %.5f" % [i, d, m.position.distance_to(before)])
			return


func test_clear_points_avoid_rocks_and_the_soft_wall() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2(10.0, 0.0), 1.0)
	check(arena.is_clear(Vector2.ZERO, 0.5), "open water")
	check(not arena.is_clear(Vector2(10.0, 1.2), 0.5), "touching a rock")
	check(arena.is_clear(Vector2(10.0, 1.6), 0.5), "beside a rock")
	check(not arena.is_clear(Vector2(35.8, 0.0), 0.5), "in the soft band")
	check(not arena.is_clear(Vector2(NAN, 0.0), 0.5), "not a place")
	check_eq(arena.wall_depth(Vector2(36.0, 0.0)), 0.0, "depth at soft start")
	check_eq(arena.wall_depth(Vector2(0.0, 39.5)), 1.0, "depth at the hard radius")
