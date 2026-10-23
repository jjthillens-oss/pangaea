extends TestCase
## The endless fuzz (S1 T2.8, G8), on the real WorldGen with the fixture world: a cell swimming at
## random with a death, a forced rebase and a dev teleport, every tick checked against FuzzInvariants
## (1 to 11 restated for the endless world, 12, 13 and 16). The fast case runs one seed with
## caps.food_items lowered to FOOD_CAP in a config copy, so the trim runs too; the slow case four
## seeds. A third case lets a home rammer engage and then flees straight at 6 tm/s (SwimBot.overdrive,
## B-12) for 3,600 ticks: the chaser is let go and every local stays under 256 tm (B-6).
## Each case prints its non-vacuity counts and fails when loads, unloads, sleeps, wakes or spawns is 0.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const FAST_SEED := 501
const SLOW_SEEDS: Array[int] = [501, 502, 503, 504]
const FAST_TICKS := 1800
const SLOW_TICKS := 3600
const FLIGHT_TICKS := 3600
## A config copy's food cap for the fast seed: low enough that the trim runs round home.
const FOOD_CAP := 40
const NOTICE := 90                     ## ticks a dead cell lies before the respawn is asked for
const TURN := 0.04                     ## rad: the most the swim turns in a tick
const NON_VACUOUS: PackedStringArray = ["loads", "unloads", "sleeps", "wakes", "spawns"]

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func test_endless_fuzz_keeps_every_invariant_on_one_seed() -> void:
	var fz := FuzzInvariants.new(species, layout)
	var run := _fuzz(fz, FAST_SEED, FAST_TICKS, FOOD_CAP)
	_print(FAST_SEED, run)
	check_eq(fz.report(), "", "every invariant on every tick")
	for key in NON_VACUOUS:
		check(int(run[key]) > 0, "%s happened (%d)" % [key, int(run[key])])
	check(int(run.food_trimmed) > 0, "the trim ran (%d)" % int(run.food_trimmed))
	check(int(run.respawns) >= 1 and int(run.debug_rebases) == 1 and int(run.teleports) == 1, "a death, a rebase and a teleport (%s)" % run)


func test_slow_endless_fuzz_keeps_every_invariant_on_four_seeds() -> void:
	var fz := FuzzInvariants.new(species, layout)
	for seed_value in SLOW_SEEDS:
		var run := _fuzz(fz, seed_value, SLOW_TICKS)
		_print(seed_value, run)
		for key in NON_VACUOUS:
			check(int(run[key]) > 0, "seed %d: %s happened (%d)" % [seed_value, key, int(run[key])])
	check_eq(fz.report(), "", "every invariant on every tick of every seed")


## B-6 and B-12: a home rammer engages the cell, which then flees due south at 6 tm/s for 3,600
## ticks (360 tm). The chaser is let go ("unloaded": by the hold ring while awake, or with its chunks
## once it gives up and sleeps; on the fixture world it sleeps first, and the hold ring's own test is
## test_world_stream's); invariant 13 (every stored position under 256 tm) holds on every tick, with
## the rest.
func test_slow_a_chaser_then_a_6_tms_flight_keeps_every_local_under_256() -> void:
	var sim := FakeWorldGen.real_sim(FAST_SEED, catalog, layout, species)
	sim.grace_until = sim.tick
	var engaged := ""
	for t in 1800:
		var to := sim.world.local_of_abs(0.0, -15.0) - sim.motion.position   # into the northern territories
		sim.step(SimIntent.new(to.normalized() if to.length() > 1.0 else Vector2.ZERO))
		if not sim.creatures.engaged_on_player.is_empty():
			engaged = sim.creatures.engaged_on_player[0]
			break
	check(not engaged.is_empty(), "a creature engaged the cell")
	sim.drain_events()
	var fz := FuzzInvariants.new(species, layout)
	var flee = SwimBot.new(Vector2.DOWN)
	var let_go := -1
	var slept := -1
	var far := 0.0
	var speed_ticks := 0
	for t in FLIGHT_TICKS:
		var was := fz.before(sim)
		var tick := sim.tick
		if sim.dead:
			break
		SwimBot.overdrive(sim)
		sim.step(flee.next_intent(sim))
		var events := sim.drain_events()
		fz.after(sim, events, tick, "flight tick %d" % t, was)
		far = maxf(far, sim.motion.position.length())
		if sim.motion.velocity.length() > 5.9:
			speed_ticks += 1
		for e in events:
			if e.type == "creature_removed" and e.id == engaged and e.reason == "unloaded" and let_go < 0:
				let_go = t
			if e.type == "creature_slept" and e.id == engaged and slept < 0:
				slept = t
	print("test-endless-fuzz: flight: %s engaged; let go at %d, slept at %d; %d ticks above 5.9 tm/s; cell up to %.1f tm; %s" % [
		engaged, let_go, slept, speed_ticks, far, fz.counts])
	check(not sim.dead, "the cell outswam it")
	check(speed_ticks >= FLIGHT_TICKS / 2, "at 6 tm/s (%d ticks above 5.9)" % speed_ticks)
	check(let_go >= 0, "the chaser was let go (%d; slept at %d)" % [let_go, slept])
	check(sim.creatures.find(engaged) == null, "and is gone at the end")
	check_eq(fz.report(), "", "every invariant on every tick")
	check(int(fz.counts.rebases) >= 3, "the origin moved with the flight (%d)" % int(fz.counts.rebases))


## One seed: a swim whose heading wanders, a forced rebase at a third of the run, a death at a half
## (the respawn asked for NOTICE ticks later; any other death the same way), a dev teleport at three
## quarters. Returns FuzzInvariants' counts plus the run's own.
func _fuzz(fz: FuzzInvariants, seed_value: int, ticks: int, food_cap := -1) -> Dictionary:
	var sim := FakeWorldGen.real_sim(seed_value, catalog, layout, species)
	if food_cap > 0:
		sim.world.caps.food_items = food_cap   # a config copy
	sim.grace_until = sim.tick
	sim.drain_events()
	fz.start_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var heading := rng.randf_range(-PI, PI)
	var run := {"respawns": 0, "debug_rebases": 0, "teleports": 0}
	var dead_since := -1
	for t in ticks:
		var was := fz.before(sim)
		if t == ticks / 3:
			sim.debug_rebase(Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2)))
			run.debug_rebases += 1
		if t == ticks / 2 and not sim.dead:
			sim.debug_hurt_player(1.0e9)
		if t == ticks * 3 / 4 and not sim.dead and not sim.respawn_pending:
			sim.debug_teleport_abs(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
			run.teleports += 1
		if sim.dead and not sim.respawn_pending:
			if dead_since < 0:
				dead_since = t
			elif t - dead_since >= NOTICE:
				sim.respawn_player()
				dead_since = -1
				run.respawns += 1
		heading += rng.randf_range(-TURN, TURN)
		var tick := sim.tick
		sim.step(SimIntent.new(Vector2.from_angle(heading) * rng.randf_range(0.7, 1.0)))
		fz.after(sim, sim.drain_events(), tick, "seed %d tick %d" % [seed_value, t], was)
	run.merge(fz.counts)
	run["food_trimmed"] = int(sim.world.counters.food_trimmed)
	return run


func _print(seed_value: int, run: Dictionary) -> void:
	print("test-endless-fuzz: seed %d: %d spawns, %d sleeps, %d wakes, %d loads, %d unloads, %d evictions, %d zone changes, %d rebases, %d cuts, %d respawns, %d food trims; %d tells, %d strikes, %d hits on the cell, %d give-ups, %d memory checks" % [
		seed_value, run.spawns, run.sleeps, run.wakes, run.loads, run.unloads, run.evictions, run.zone_changes, run.rebases,
		run.cuts, run.respawns, run.food_trimmed, run.tells, run.strikes, run.hits_on_cell, run.give_ups, run.memory_checks])
