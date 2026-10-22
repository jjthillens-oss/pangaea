extends TestCase

const DT := 1.0 / 60.0
const VECTOR_EPSILON := 1e-5   ## Vector2 holds 32-bit floats

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _body(body_name: String) -> Phenotype:
	var r := Lineage.found(1, "test+dev", catalog, body_name)
	return Phenotype.derive(r.save.genome, catalog)


func _bodies() -> Dictionary:
	var out := {}
	for body_name in catalog.starting_bodies:
		out[body_name] = _body(body_name)
	return out


## One tick in open water: steer, then move by the velocity.
func _tick(m: Locomotion.MotionState, move: Vector2, p: Phenotype, mul: float = 1.0) -> void:
	Locomotion.steer(m, move, p, mul, DT)
	m.prev_position = m.position
	m.position += m.velocity * DT


func _forward_speed(m: Locomotion.MotionState) -> float:
	return m.velocity.dot(Vector2.from_angle(m.heading))


func test_each_body_reaches_its_top_speed_and_never_exceeds_it() -> void:
	var bodies := _bodies()
	for body_name in bodies:
		var p: Phenotype = bodies[body_name]
		var m := Locomotion.MotionState.new()
		var fastest := 0.0
		var t90 := -1.0
		for i in 300:
			_tick(m, Vector2.RIGHT, p)
			fastest = maxf(fastest, m.velocity.length())
			if t90 < 0.0 and m.velocity.length() >= 0.9 * p.speed:
				t90 = (i + 1) * DT
		check(m.velocity.length() >= 0.99 * p.speed, "%s reaches top speed: %.3f of %.3f" % [body_name, m.velocity.length(), p.speed])
		check(fastest <= p.speed + VECTOR_EPSILON, "%s never exceeds top speed" % body_name)
		check(t90 >= 0.5 and t90 <= 1.5, "%s: 90%% speed after %.2f s, wanted 0.5..1.5" % [body_name, t90])


func test_turning_never_pushes_the_total_speed_past_the_top_speed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for mul in [1.0, ActorState.STARVING_SPEED]:
		for body_name in ["grazer", "hunter"]:
			var p := _body(body_name)
			var m := Locomotion.MotionState.new()
			var move := Vector2.RIGHT
			for i in 3000:
				if i % 30 == 0:
					move = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 1.0)
				_tick(m, move, p, mul)
				if m.velocity.length() > p.speed * mul + VECTOR_EPSILON:
					check(false, "%s x%.1f tick %d: %.4f m/s, top %.4f" % [body_name, mul, i, m.velocity.length(), p.speed * mul])
					return


func test_starving_halves_top_speed() -> void:
	var p := _body("grazer")
	var m := Locomotion.MotionState.new()
	var fastest := 0.0
	for i in 300:
		_tick(m, Vector2.RIGHT, p, ActorState.STARVING_SPEED)
		fastest = maxf(fastest, m.velocity.length())
	check_near(m.velocity.length(), p.speed * 0.5, p.speed * 0.005, "half speed")
	check(fastest <= p.speed * 0.5 + VECTOR_EPSILON, "never above half")


func test_heading_never_turns_faster_than_the_turn_rate() -> void:
	var p := _body("hunter")
	var m := Locomotion.MotionState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var move := Vector2.ZERO
	for i in 2000:
		if i % 25 == 0:
			move = Vector2.from_angle(rng.randf() * TAU) * rng.randf()
		_tick(m, move, p)
		var turned := absf(angle_difference(m.prev_heading, m.heading))
		if turned > p.turn_rate * DT + 1e-9:
			check(false, "tick %d turned %.4f rad, limit %.4f" % [i, turned, p.turn_rate * DT])
			return


func test_a_reversal_reaches_ninety_percent_of_top_speed_within_two_seconds() -> void:
	var bodies := _bodies()
	for body_name in bodies:
		var p: Phenotype = bodies[body_name]
		var m := Locomotion.MotionState.new()
		for i in 300:
			_tick(m, Vector2.RIGHT, p)
		var took := -1.0
		for i in 300:
			_tick(m, Vector2.LEFT, p)
			if m.velocity.dot(Vector2.LEFT) >= 0.9 * p.speed:
				took = (i + 1) * DT
				break
		check(took > 0.0 and took <= 2.0, "%s reversal took %.2f s" % [body_name, took])


func test_letting_go_coasts_to_a_stop_over_a_short_distance() -> void:
	var bodies := _bodies()
	for body_name in bodies:
		var p: Phenotype = bodies[body_name]
		var m := Locomotion.MotionState.new()
		for i in 300:
			_tick(m, Vector2.RIGHT, p)
		var from := m.position
		for i in 300:
			_tick(m, Vector2.ZERO, p)
		check(m.velocity.length() < 1e-6, "%s stops" % body_name)
		var coast := m.position.distance_to(from)
		check(coast >= 0.8 and coast <= 2.5, "%s coasts %.2f m, wanted 0.8..2.5" % [body_name, coast])


func test_tiny_input_is_ignored() -> void:
	var p := _body("grazer")
	var m := Locomotion.MotionState.new(Vector2.ZERO, 1.0)
	for i in 60:
		_tick(m, Vector2(0.01, -0.02), p)
	check_eq(m.heading, 1.0, "no turn inside the deadzone")
	check_eq(m.velocity, Vector2.ZERO, "no thrust inside the deadzone")


func test_adding_spikes_makes_the_same_body_slower() -> void:
	var r := Lineage.found(1, "test+dev", catalog, "grazer")
	var plain := Phenotype.derive(r.save.genome, catalog)
	r.save.genome.add_part("spike", 0.5)
	r.save.genome.add_part("spike", -0.5)
	var spiked := Phenotype.derive(r.save.genome, catalog)
	var a := Locomotion.MotionState.new()
	var b := Locomotion.MotionState.new()
	for i in 120:
		_tick(a, Vector2.RIGHT, plain)
		_tick(b, Vector2.RIGHT, spiked)
	check(b.velocity.length() < a.velocity.length(), "spiked %.3f vs plain %.3f m/s" % [b.velocity.length(), a.velocity.length()])
	check(b.position.x < a.position.x, "and covers less ground")


func test_asking_straight_behind_gives_no_forward_thrust_until_past_ninety_degrees() -> void:
	var p := _body("omnivore")
	var m := Locomotion.MotionState.new()
	var past_ninety := false
	for i in 120:
		_tick(m, Vector2.LEFT, p)
		var error := absf(angle_difference(m.heading, PI))
		if error >= PI / 2.0:
			check(m.velocity.length() < 1e-9, "tick %d: still turning (error %.2f rad) yet moving %s" % [i, error, m.velocity])
		else:
			past_ninety = true
	check(past_ninety, "turned past 90 degrees within 2 s")
	check(_forward_speed(m) > 0.0, "then swims")
	check(m.position.x < 0.0, "toward where it was asked to go")


# --- Strikes (M1 step 3) ---

func test_a_burst_sets_the_heading_and_the_whole_velocity_along_it() -> void:
	var p := _body("grazer")
	for heading in [0.0, 1.0472, -2.9258, PI - 0.001, -PI + 0.001]:
		var m := Locomotion.MotionState.new(Vector2.ZERO, 0.5)
		for i in 30:
			_tick(m, Vector2.from_angle(2.0), p)   # moving and turning another way first
		Locomotion.burst(m, heading, 4.5)
		check_eq(m.heading, heading, "heading snaps to the lock")
		check_near(m.velocity.length(), 4.5, VECTOR_EPSILON, "speed is the burst speed, not the body's %.2f" % p.speed)
		check_near(absf(angle_difference(m.velocity.angle(), heading)), 0.0, VECTOR_EPSILON, "no sideways drift left")
	var wrapped := Locomotion.MotionState.new()
	Locomotion.burst(wrapped, 3.0 * PI / 2.0, 1.0)
	check_near(wrapped.heading, -PI / 2.0, 1e-12, "the heading wraps into -PI..PI")


func test_a_glide_decays_exponentially_and_holds_the_heading() -> void:
	for case in [[4.5, 6.0, 15], [4.0, 5.0, 18], [6.0, 6.0, 60]]:
		var m := Locomotion.MotionState.new(Vector2.ZERO, 0.0)
		Locomotion.burst(m, -2.0, case[0])
		var direction := m.velocity.normalized()
		for n in range(1, case[2] + 1):
			Locomotion.glide(m, case[1], DT)
			var expected: float = case[0] * exp(-case[1] * n / 60.0)
			# Vector2 holds 32-bit floats, so the match is to float32 rounding, not 1e-9.
			if absf(m.velocity.length() - expected) > VECTOR_EPSILON:
				check(false, "drag %.1f tick %d: %.7f, expected %.7f" % [case[1], n, m.velocity.length(), expected])
				return
			check_eq(m.heading, -2.0, "heading holds")
		check(m.velocity.normalized().distance_to(direction) < VECTOR_EPSILON, "direction holds")


func test_strike_travel_is_the_per_tick_sum_of_the_burst_and_the_glide() -> void:
	for case in [[4.5, 21, 6.0, 15], [4.0, 54, 5.0, 18], [3.0, 0, 4.0, 10], [2.0, 10, 1.0, 0]]:
		var m := Locomotion.MotionState.new()
		Locomotion.burst(m, 0.7, case[0])   # the glide starts from the burst speed even with no burst ticks
		for i in case[1]:
			Locomotion.burst(m, 0.7, case[0])
			m.position += m.velocity * DT
		for i in case[3]:
			Locomotion.glide(m, case[2], DT)
			m.position += m.velocity * DT
		var travel := Locomotion.strike_travel(case[0], case[1], case[2], case[3], DT)
		check_near(m.position.length(), travel, 1e-4, "burst %.1f m/s x %d, glide drag %.1f x %d" % case)
	# The probed strikes: the lunge and the charge, a few centimetres short of the integrals 2.16 and 4.22.
	check_near(Locomotion.strike_travel(4.5, 21, 6.0, 15, DT), 2.129, 0.001, "lunge travel")
	check_near(Locomotion.strike_travel(4.0, 54, 5.0, 18, DT), 4.196, 0.001, "charge travel")
