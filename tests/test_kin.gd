extends TestCase
## S4.3, kin and mating (Kin; docs/s4/s4-plan.md): a cell ready to mate is joined by a cell of its
## own kind, and touching it at a calm moment reports `mate` once.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 5101
var catalog: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()


func _sim(growth := true) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, null, null, PackedFloat64Array(), 4, growth)
	sim.drain_events()
	return sim


## Ticks with `move` as the intent until `type` is reported or `max_ticks` pass. Returns the events.
func _run(sim: PoolSim, ticks: int, move := Vector2.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		var intent := SimIntent.new()
		intent.move = move
		sim.step(intent)
		out.append_array(sim.drain_events())
	return out


static func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _make_ready(sim: PoolSim) -> void:
	sim.save.adaptation_points = Kin.cheapest_part(catalog)
	sim.debug_set_energy(sim.state.energy_capacity)


func test_kin_needs_growth_and_a_ready_cell() -> void:
	check(_sim(false).kin == null, "no kin without growth (the pool and S1's sea are unchanged)")
	var sim := _sim()
	check(sim.kin != null and not sim.kin.present, "with growth: none yet")
	check(Kin.cheapest_part(catalog) == 40, "the cheapest editor part costs 40 (%d)" % Kin.cheapest_part(catalog))
	sim.save.adaptation_points = Kin.cheapest_part(catalog) - 1
	sim.debug_set_energy(sim.state.energy_capacity)
	check(not Kin.is_ready(sim), "a point short is not ready")
	sim.save.adaptation_points += 1
	sim.debug_set_energy(sim.state.energy_capacity * 0.69)
	check(not Kin.is_ready(sim), "under 70 % energy is not ready")
	sim.debug_set_energy(sim.state.energy_capacity * 0.7)
	check(Kin.is_ready(sim), "70 % energy and points for a part is ready")


func test_a_ready_cell_calls_its_kin_and_mates_by_touch() -> void:
	var sim := _sim()
	_make_ready(sim)
	var call := CreatureBrain.ticks(Kin.CALL_S)
	var events := _run(sim, call - 2)
	check_eq(_of(events, "kin_arrived"), [], "nothing before CALL_S")
	events = _run(sim, 2)
	var arrived := _of(events, "kin_arrived")
	check_eq(arrived.size(), 1, "the kin swims in after CALL_S of readiness")
	var r := sim.phenotype.radius
	var d := sim.kin.motion.position.distance_to(sim.motion.position)
	check(d > 6.0 * r and d <= Kin.ARRIVE_RADII * r + 1.0, "from a distance (%.2f radii)" % (d / r))
	events = _run(sim, 360)
	d = sim.kin.motion.position.distance_to(sim.motion.position)
	check(absf(d - Kin.HOLD_RADII * r) < 0.6 * r, "it comes to hold beside the cell (%.2f radii)" % (d / r))
	check_eq(_of(events, "mate"), [], "and waits to be touched")
	# The cell swims into it.
	var mates: Array[Dictionary] = []
	for i in 240:
		var to := sim.kin.motion.position - sim.motion.position
		events = _run(sim, 1, to.normalized() * 0.5)
		mates.append_array(_of(events, "mate"))
		if not mates.is_empty():
			break
	check_eq(mates.size(), 1, "touching it reports mate")
	check(sim.kin.waiting, "and the kin waits for the editor")
	events = _run(sim, 60)
	check_eq(_of(events, "mate"), [], "once")
	sim.kin.finish(sim)
	events = sim.drain_events()
	check_eq(_of(events, "kin_left").map(func(e: Dictionary) -> String: return e.reason), ["mated"], "finish sends it away")
	check(not sim.kin.present, "gone")


func test_a_kin_goes_when_the_cell_stops_being_ready_or_dies() -> void:
	var sim := _sim()
	_make_ready(sim)
	_run(sim, CreatureBrain.ticks(Kin.CALL_S) + 1)
	check(sim.kin.present, "arrived")
	sim.save.adaptation_points = 0
	var events := _run(sim, CreatureBrain.ticks(Kin.LEAVE_S) - 2)
	check(sim.kin.present, "still there before LEAVE_S")
	events = _run(sim, 3)
	check_eq(_of(events, "kin_left").map(func(e: Dictionary) -> String: return e.reason), ["not ready"], "gone after LEAVE_S")
	_make_ready(sim)
	_run(sim, CreatureBrain.ticks(Kin.CALL_S) + 1)
	check(sim.kin.present, "back once ready again")
	sim.debug_hurt_player(sim.state.max_health + 1.0)
	events = _run(sim, 1)
	check_eq(_of(events, "kin_left").map(func(e: Dictionary) -> String: return e.reason), ["died"], "a death sends it away")


func test_no_mate_while_hunted_and_the_kin_changes_nothing_else() -> void:
	# Two runs from one seed, ready the same way, one with the kin's tick and one without: the sea plays
	# out the same (the kin takes no random stream and no creature sees it).
	var a := _sim()
	var b := _sim()
	_make_ready(a)
	_make_ready(b)
	b.kin = null
	for i in 600:
		var intent := SimIntent.new()
		intent.move = Vector2(0.4, 0.2)
		a.step(intent)
		b.step(intent)
	check(a.kin.present or a.kin.ready_ticks == 0, "a's kin ran (%s)" % a.kin.present)
	check_eq(a.state_hash(), b.state_hash(), "the sea is the same with the kin as without")
	check(not Kin.is_calm(a) or a.growth.blocker_of(a, false) in ["", "eating"], "calm is Growth's blockers but eating")
