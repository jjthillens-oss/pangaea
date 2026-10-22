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
