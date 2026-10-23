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


func test_a_cell_pressed_against_any_layout_rock_is_at_a_clear_point() -> void:
	# Pushing out lands the cell within float32 rounding of the rock's surface, a few micrometres
	# either side at pool distances. Continue only restores a clear point, so those must count.
	var arena := PoolLayout.load_from().build_arena()
	var contacts := 0
	for rock in arena.rocks:
		for k in 72:
			var out := Vector2.from_angle(k * TAU / 72.0)
			var m := Locomotion.MotionState.new(rock.center + out * (rock.radius + BODY_R + 0.01))
			for i in 3:
				m.velocity = -out * 3.0
				arena.move(m, BODY_R, DT)
			if m.position.length() > arena.soft_start - BODY_R:
				continue   # resting in the soft band, which is never a clear point
			contacts += 1
			if not arena.is_clear(m.position, BODY_R):
				var gap: float = m.position.distance_to(rock.center) - rock.radius - BODY_R
				check(false, "pressed against %s from %d deg: %s is %.7f m off the surface and not clear"
					% [rock.id, k * 5, m.position, gap])
				return
	check(contacts > 1000, "the cell rested against the rocks %d times" % contacts)


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


# --- Geometry creatures share (M1 step 3) ---

func test_settling_after_random_pushes_never_leaves_a_body_in_a_rock_or_outside_the_pool() -> void:
	var arena := _crowded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3031
	var m := Locomotion.MotionState.new(Vector2(-2.0, 2.5))
	var pushed_into := 0
	for i in 10000:
		# Separation pushes a body sideways by up to a body radius, into rocks and the wall.
		m.velocity = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 6.0)
		m.position += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.5)
		if _deepest_rock_overlap(arena, m.position) > 0.001 or m.position.length() > arena.hard_radius - BODY_R:
			pushed_into += 1
		arena.settle(m, BODY_R)
		var overlap := _deepest_rock_overlap(arena, m.position)
		if overlap > 0.001 or m.position.length() > arena.hard_radius - BODY_R + 1e-6 or not m.position.is_finite():
			check(false, "push %d: overlap %.4f m, r %.3f" % [i, overlap, m.position.length()])
			return
	check(pushed_into > 300, "the fuzz actually pushed the body into rocks or the wall (%d times)" % pushed_into)


func test_settling_removes_only_the_velocity_into_the_rock() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2.ZERO, 1.0)
	var m := Locomotion.MotionState.new(Vector2(1.2, 0.0))
	m.velocity = Vector2(-2.0, 1.5)
	arena.settle(m, BODY_R)
	check_near(m.position.x, 1.5, 1e-5, "out to the surface")
	check_near(m.velocity.x, 0.0, 1e-6, "no velocity into the rock")
	check_near(m.velocity.y, 1.5, 1e-6, "the sliding velocity is kept")
	var away := Locomotion.MotionState.new(Vector2(0.0, 1.3))
	away.velocity = Vector2(0.0, 2.0)
	arena.settle(away, BODY_R)
	check_eq(away.velocity, Vector2(0.0, 2.0), "a body already swimming away keeps its velocity")


func test_line_of_sight_is_blocked_only_well_inside_a_rock() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2(5.0, 0.0), 1.0)
	check(arena.segment_clear(Vector2.ZERO, Vector2(4.0, 0.0)), "the segment ends before the rock")
	check(not arena.segment_clear(Vector2.ZERO, Vector2(10.0, 0.0)), "straight through the center")
	check(not arena.segment_clear(Vector2(0.0, 0.85), Vector2(10.0, 0.85)), "within 0.9 of the radius")
	check(arena.segment_clear(Vector2(0.0, 0.95), Vector2(10.0, 0.95)), "grazing the edge still sees")
	check(not arena.segment_clear(Vector2(0.0, 0.95), Vector2(10.0, 0.95), 1.0), "unless the whole rock blocks")
	check(arena.segment_clear(Vector2(0.0, 3.0), Vector2(10.0, 3.0)), "passing beside it")
	check(not arena.segment_clear(Vector2(5.0, 0.2), Vector2(5.0, 0.2)), "a point inside the rock")
	check(arena.segment_clear(Vector2(2.0, 2.0), Vector2(2.0, 2.0)), "a point in open water")
	check(arena.segment_clear(Vector2(10.0, 0.0), Vector2(10.0, 0.0) + Vector2(3.0, 0.0)), "the rock behind the start")


func test_route_point_goes_straight_in_open_water_and_round_a_rock_in_the_way() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2(5.0, 0.0), 1.0)
	var target := Vector2(10.0, 0.0)
	check_eq(arena.route_point(Vector2.ZERO, Vector2(0.0, 8.0), BODY_R), Vector2(0.0, 8.0), "nothing in the way")
	check_eq(arena.route_point(Vector2.ZERO, Vector2(3.0, 0.0), BODY_R), Vector2(3.0, 0.0), "the target is short of the rock")
	check_eq(arena.route_point(Vector2(12.0, 0.0), Vector2(20.0, 0.0), BODY_R), Vector2(20.0, 0.0), "the rock is behind")
	var above := arena.route_point(Vector2(0.0, -0.4), Vector2(10.0, -0.4), BODY_R)
	check_near(above.distance_to(Vector2(5.0, 0.0)), 1.0 + BODY_R + PoolArena.ROUTE_MARGIN, 1e-5, "the detour keeps the margin")
	check(above.y < 0.0 and absf(above.x - 5.0) < 1e-5, "it goes round on the side the line passes: %s" % above)
	var below := arena.route_point(Vector2(0.0, 0.4), Vector2(10.0, 0.4), BODY_R)
	check(below.y > 0.0, "and the other side from the other side: %s" % below)
	var dead_on := arena.route_point(Vector2.ZERO, target, BODY_R)
	check(dead_on.distance_to(Vector2(5.0, 0.0) + Vector2.RIGHT.orthogonal() * 2.1) < 1e-5, "dead on: dir.orthogonal()'s side, %s" % dead_on)
	check(arena.route_point(Vector2(0.0, 1.55), Vector2(10.0, 1.55), BODY_R).y > 1.55, "within the clearance counts as in the way")
	check_eq(arena.route_point(Vector2(0.0, 1.65), Vector2(10.0, 1.65), BODY_R), Vector2(10.0, 1.65), "beyond it does not")


func test_route_point_can_be_told_which_side_to_take() -> void:
	var arena := _pool()
	arena.add_rock("r", Vector2(5.0, 0.0), 1.0)
	var from := Vector2(0.0, -0.4)
	var to := Vector2(10.0, -0.4)
	var dir := (to - from).normalized()
	var plus := arena.route_point(from, to, BODY_R, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, 1)
	var minus := arena.route_point(from, to, BODY_R, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, -1)
	check(plus.distance_to(Vector2(5.0, 0.0) + dir.orthogonal() * 2.1) < 1e-5, "+1 is dir.orthogonal()'s side: %s" % plus)
	check(minus.distance_to(Vector2(5.0, 0.0) - dir.orthogonal() * 2.1) < 1e-5, "-1 is the other side: %s" % minus)
	check_eq(arena.route_point(from, from + Vector2(0.0, 5.0), BODY_R, 0.1, 0.6, 1), from + Vector2(0.0, 5.0), "a side changes nothing in open water")


func test_steering_at_the_route_point_gets_round_a_rock_to_a_target_behind_it() -> void:
	var arena := _crowded()
	var p := _body("grazer")
	for case in [[Vector2(-1.5, -6.6), Vector2(-1.5, 6.6)], [Vector2(-6.0, 0.0), Vector2(6.0, 0.0)], [Vector2(5.5, 7.0), Vector2(-3.0, -7.0)]]:
		var m := Locomotion.MotionState.new(case[0])
		var arrived := false
		for i in 60 * 30:
			var aim := arena.route_point(m.position, case[1], BODY_R)
			_step(arena, m, (aim - m.position).normalized(), p)
			if m.position.distance_to(case[1]) < 0.5:
				arrived = true
				break
		check(arrived, "from %s to %s: stopped at %s" % [case[0], case[1], m.position])


func test_separating_two_bodies_moves_positions_only_and_the_heavier_one_less() -> void:
	var a := Locomotion.MotionState.new(Vector2(10.0, 3.0))
	var b := Locomotion.MotionState.new(Vector2(10.6, 3.2))
	a.velocity = Vector2(1.0, 0.5)
	b.velocity = Vector2(-2.0, 0.0)
	var a0 := a.position
	var b0 := b.position
	check(PoolArena.separate(a, 0.5, 1.0, b, 0.75, 3.0), "they overlapped")
	check(a.position.distance_to(b.position) >= 1.25 - 1e-4, "they end touching: %.6f" % a.position.distance_to(b.position))
	check(a.position.distance_to(b.position) <= 1.25 + 1e-4, "and no farther apart")
	check_near(a.position.distance_to(a0) / b.position.distance_to(b0), 3.0, 1e-3, "the push splits by inverse mass")
	check_eq(a.velocity, Vector2(1.0, 0.5), "a's velocity unchanged")
	check_eq(b.velocity, Vector2(-2.0, 0.0), "b's velocity unchanged")
	var line := (b0 - a0).normalized()
	check(absf((a.position - a0).normalized().dot(line) + 1.0) < 1e-4, "a moves back along the line between centers")
	var c := Locomotion.MotionState.new(Vector2(0.0, 0.0))
	var d := Locomotion.MotionState.new(Vector2(1.01, 0.0))
	check(not PoolArena.separate(c, 0.5, 1.0, d, 0.5, 1.0), "apart already")
	check_eq(d.position, Vector2(1.01, 0.0), "nothing moves")


func test_separating_coincident_bodies_is_deterministic() -> void:
	var a := Locomotion.MotionState.new(Vector2(2.0, 2.0))
	var b := Locomotion.MotionState.new(Vector2(2.0, 2.0))
	check(PoolArena.separate(a, 0.5, 1.0, b, 0.5, 1.0), "they overlapped")
	check_eq(a.position, Vector2(1.5, 2.0), "a goes -X")
	check_eq(b.position, Vector2(2.5, 2.0), "b goes +X")
	var e := Locomotion.MotionState.new(Vector2(0.0, 0.0))
	var f := Locomotion.MotionState.new(Vector2(0.5, 0.0))
	PoolArena.separate(e, 0.5, 0.0, f, 0.5, 0.0)
	check_near(e.position.distance_to(f.position), 1.0, 1e-5, "massless bodies split the push evenly")
	check_near(e.position.x, -0.25, 1e-6, "half each")


func test_rock_contact_names_the_rock_a_body_touches() -> void:
	var arena := _pool()
	arena.add_rock("rock_b", Vector2(5.0, 0.0), 1.0)
	arena.add_rock("rock_a", Vector2(5.0, 3.0), 1.0)
	check_eq(arena.rock_contact(Vector2(3.5, 0.0), BODY_R), "rock_b", "touching")
	check_eq(arena.rock_contact(Vector2(3.45, 0.0), BODY_R), "rock_b", "within the slack")
	check_eq(arena.rock_contact(Vector2(3.4, 0.0), BODY_R), "", "beyond the slack")
	check_eq(arena.rock_contact(Vector2(3.4, 0.0), BODY_R, 0.2), "rock_b", "a wider slack")
	check_eq(arena.rock_contact(Vector2(5.0, 1.5), BODY_R), "rock_a", "between two, equal gaps: the lower id")
	check_eq(arena.rock_contact(Vector2(5.0, 1.49), BODY_R), "rock_b", "between two: the nearer surface")
	check_eq(arena.rock_contact(Vector2(3.5, 0.0), BODY_R, 0.05, 0.0, deg_to_rad(60.0)), "rock_b", "ahead")
	check_eq(arena.rock_contact(Vector2(3.5, 0.0), BODY_R, 0.05, PI, deg_to_rad(60.0)), "", "behind does not count when facing away")
	check_eq(arena.rock_contact(Vector2(5.0, 1.5), BODY_R, 0.05, -PI / 2.0, deg_to_rad(60.0)), "rock_b", "only the rock ahead counts")


func test_clamping_to_a_disc_puts_the_body_on_the_circle_and_keeps_inward_velocity() -> void:
	var center := Vector2(-9.4, -16.3)
	var m := Locomotion.MotionState.new(center + Vector2(9.5, 0.3))
	m.velocity = Vector2(1.0, -0.7)
	check(PoolArena.clamp_to_disc(m, center, 9.0), "it was outside")
	check_near(m.position.distance_to(center), 9.0, 1e-5, "on the circle")
	var n := (m.position - center).normalized()
	check(m.velocity.dot(n) <= 1e-6, "no outward velocity left: %s" % m.velocity)
	check_near(m.velocity.dot(n.orthogonal()), Vector2(1.0, -0.7).dot(n.orthogonal()), 1e-5, "the sliding velocity is kept")
	var inward := Locomotion.MotionState.new(center + Vector2(0.0, 9.2))
	inward.velocity = Vector2(0.3, -2.0)
	PoolArena.clamp_to_disc(inward, center, 9.0)
	check_eq(inward.velocity, Vector2(0.3, -2.0), "inward velocity is kept whole")
	var inside := Locomotion.MotionState.new(center + Vector2(3.0, 4.0))
	inside.velocity = Vector2(5.0, 5.0)
	check(not PoolArena.clamp_to_disc(inside, center, 9.0), "inside the disc")
	check_eq(inside.position, center + Vector2(3.0, 4.0), "untouched")
	check_eq(inside.velocity, Vector2(5.0, 5.0), "velocity untouched")


func test_swimming_out_against_a_disc_clamp_slides_along_its_edge() -> void:
	var p := _body("hunter")
	var center := Vector2(3.0, -2.0)
	var m := Locomotion.MotionState.new(center)
	var arena := _pool()
	var worst := 0.0
	var travelled := 0.0
	for i in 600:
		Locomotion.steer(m, Vector2.from_angle(0.3 + i * 0.002), p, 1.0, DT)
		travelled += arena.move(m, BODY_R, DT)
		PoolArena.clamp_to_disc(m, center, 3.0)
		worst = maxf(worst, m.position.distance_to(center))
	check(worst <= 3.0 + 1e-3, "never past the disc: %.5f" % worst)
	check(travelled > 3.0 + 1.0, "it kept sliding along the edge (%.2f m)" % travelled)


# --- The rock grid (plan section 20) ---

func test_the_rock_grid_never_rules_out_a_rock_a_body_could_touch() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	var ruled_out := 0
	var kept := 0
	for arena: PoolArena in [PoolLayout.load_from().build_arena(), _crowded()]:
		# Random points across the pool and past its edge (beyond the grid), up to larger bodies
		# than the grid serves.
		var reach := arena.radius + 4.0
		for i in 20000:
			var p := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
			var r := rng.randf_range(0.0, PoolArena.GRID_BODY_R + 0.5)
			if arena.rocks_near(p, r):
				kept += 1
				continue
			ruled_out += 1
			for rock in arena.rocks:
				if p.distance_to(rock.center) < rock.radius + r:
					check(false, "a body of radius %.3f at %s touches %s, but the grid ruled it out" % [r, p, rock.id])
					return
		# Just inside touching distance, all round every rock, with the largest body the grid serves.
		for rock in arena.rocks:
			for k in 360:
				var p: Vector2 = rock.center + Vector2.from_angle(k * TAU / 360.0) * (rock.radius + PoolArena.GRID_BODY_R - 1e-3)
				if not arena.rocks_near(p, PoolArena.GRID_BODY_R):
					check(false, "%s at %d deg, just inside touching distance, was ruled out" % [rock.id, k])
					return
	check(ruled_out > 10000 and kept > 1000, "the grid ruled out %d points and kept %d" % [ruled_out, kept])


func test_swimming_settling_and_sight_come_out_the_same_to_the_bit_with_the_rock_grid_as_without_it() -> void:
	var grid := PoolLayout.load_from().build_arena()
	var plain := PoolLayout.load_from().build_arena()
	plain.rock_grid = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 2021
	var p := _fastest()
	var a := Locomotion.MotionState.new(Vector2(9.0, 2.0))
	var b := Locomotion.MotionState.new(Vector2(9.0, 2.0))
	var move := Vector2.ZERO
	var touching := 0
	var resting := 0
	var in_band := 0
	for i in 30000:
		if i % 40 == 0:
			move = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 1.0)
		Locomotion.steer(a, move, p, 1.0, DT)
		Locomotion.steer(b, move, p, 1.0, DT)
		if i % 300 < 30:
			a.velocity = Vector2.ZERO   # at rest, as a waiting creature is
			b.velocity = Vector2.ZERO
		if i % 97 == 0:
			# A push as separation gives, into rocks and the wall at times, then the settle after it.
			var push := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.5)
			a.position += push
			b.position += push
			grid.settle(a, BODY_R)
			plain.settle(b, BODY_R)
		var moved_a := grid.move(a, BODY_R, DT)
		var moved_b := plain.move(b, BODY_R, DT)
		if moved_a != moved_b or a.position != b.position or a.velocity != b.velocity or a.prev_position != b.prev_position:
			check(false, "tick %d: with the grid %s %s moved %.9f, without %s %s moved %.9f" % [
				i, a.position, a.velocity, moved_a, b.position, b.velocity, moved_b])
			return
		var contact := grid.rock_contact(a.position, BODY_R)
		if contact != plain.rock_contact(b.position, BODY_R) or grid.is_clear(a.position, BODY_R) != plain.is_clear(b.position, BODY_R):
			check(false, "tick %d: the rock contact or the clear test differs at %s" % [i, a.position])
			return
		if not contact.is_empty():
			touching += 1
		if moved_a == 0.0 and a.velocity == Vector2.ZERO:
			resting += 1
		if a.position.length() > grid.soft_start:
			in_band += 1
	check(touching > 200 and resting > 1000 and in_band > 100, "the swim touched rocks on %d ticks, rested on %d, was in the soft band on %d" % [
		touching, resting, in_band])
	# A body at rest that something left inside a rock (the leash clamp does not settle): its next
	# move still pushes it out, with the grid as without it.
	for rock in grid.rocks:
		var inside: Vector2 = rock.center + Vector2.from_angle(0.7) * (rock.radius + BODY_R - 0.2)
		var still_a := Locomotion.MotionState.new(inside)
		var still_b := Locomotion.MotionState.new(inside)
		grid.move(still_a, BODY_R, DT)
		plain.move(still_b, BODY_R, DT)
		if still_a.position != still_b.position or still_a.position.distance_to(rock.center) < rock.radius + BODY_R - 1e-3:
			check(false, "a resting body inside %s ended %.4f m from its surface at %s with the grid, at %s without" % [
				rock.id, still_a.position.distance_to(rock.center) - rock.radius - BODY_R, still_a.position, still_b.position])
			return
	# Lines of sight, which skip the rocks outside a segment's box.
	var blocked := 0
	for i in 20000:
		var from := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 38.0)
		var to := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 20.0)
		var seen := grid.segment_clear(from, to)
		if seen != plain.segment_clear(from, to):
			check(false, "the line of sight from %s to %s differs" % [from, to])
			return
		if not seen:
			blocked += 1
	check(blocked > 500, "rocks blocked %d of the lines of sight" % blocked)
