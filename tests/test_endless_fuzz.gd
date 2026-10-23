extends TestCase
## The endless fuzz (S1 T2.8, G8), on the real WorldGen with the fixture world: a cell swimming at
## random with a death, a forced rebase and a dev teleport, every tick checked against FuzzInvariants
## (1 to 11 restated for the endless world, 12, 13 and 16). The fast case runs one seed with
## caps.food_items lowered to FOOD_CAP in a config copy, so the trim runs too; the slow case four
## seeds. A third case lets a home rammer engage and then flees straight at 6 tm/s (SwimBot.overdrive,
## B-12) for 3,600 ticks: the chaser is let go and every local stays under 256 tm (B-6).
## Each case prints its non-vacuity counts and fails when loads, unloads, sleeps, wakes or spawns is 0.
##
## The growth fuzz (S2 T0.4, gate S2G21; S2 build plan BP-5): the same wandering swim with growth on,
## in cycles of GROWTH_CYCLE ticks: at tick GROWTH_CYCLE / 2 of a cycle a cell at size 2 is set back
## to size 1 (debug_set_size, a cut for the checker), and at a cycle's last tick a growth is forced
## (debug_force_growth: the meter full and due, past the calm window), so each cycle after the first
## grows again. Every tick runs FuzzInvariants, 12, 13 and 16 through the growth tick (BP-2). There
## is no max_in_build 3 config (BP-5). It runs on the size-2 fake world (FakeWorldGen with its
## size-2 rammer sites and the two size-2 species) until the real content holds size-2 sites (T3.5),
## then on the real content.
##  - fast: 1 seed x 2,520 ticks (two growths), run twice: the two runs' hashes are equal after
##    every growth and at the end;
##  - slow: 4 seeds x 6,000 ticks;
##  - soak: 2 seeds x 36,000 ticks.
## Each run must grow at least once a cycle after the first and set the size back between.

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
## The growth fuzz (S2G21).
const Gates := preload("res://tests/test_endless_gates.gd")
const GROWTH_NEEDS: PackedStringArray = ["set_size", "fuzz_growth"]
const GROWTH_CYCLE := 1200
const GROWTH_FAST_SEED := 531
const GROWTH_FAST_TICKS := 2520
const GROWTH_SLOW_SEEDS: Array[int] = [531, 532, 533, 534]
const GROWTH_SLOW_TICKS := 6000
const GROWTH_SOAK_SEEDS: Array[int] = [535, 536]
const GROWTH_SOAK_TICKS := 36000

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


func test_growth_fuzz_grows_twice_cleanly_and_two_runs_hash_alike() -> void:
	if _growth_waits("the fast growth fuzz"):
		return
	var fz := FuzzInvariants.new(species, layout)
	var a := _growth_fuzz(fz, GROWTH_FAST_SEED, GROWTH_FAST_TICKS)
	var b := _growth_fuzz(null, GROWTH_FAST_SEED, GROWTH_FAST_TICKS)   # the hash only: no checker
	_print_growth(GROWTH_FAST_SEED, a)
	check_eq(fz.report(), "", "every invariant on every tick through two growths")
	_check_growth_run(GROWTH_FAST_SEED, GROWTH_FAST_TICKS, a)
	check_eq(a.hashes, b.hashes, "two runs hash alike after every growth and at the end")


func test_slow_growth_fuzz_on_four_seeds() -> void:
	if _growth_waits("the slow growth fuzz"):
		return
	var fz := FuzzInvariants.new(species, layout)
	for seed_value in GROWTH_SLOW_SEEDS:
		var run := _growth_fuzz(fz, seed_value, GROWTH_SLOW_TICKS)
		_print_growth(seed_value, run)
		_check_growth_run(seed_value, GROWTH_SLOW_TICKS, run)
	check_eq(fz.report(), "", "every invariant on every tick of every seed")


func test_soak_growth_fuzz_for_ten_minutes_on_two_seeds() -> void:
	if _growth_waits("the soak growth fuzz"):
		return
	var fz := FuzzInvariants.new(species, layout)
	for seed_value in GROWTH_SOAK_SEEDS:
		var run := _growth_fuzz(fz, seed_value, GROWTH_SOAK_TICKS)
		_print_growth(seed_value, run)
		_check_growth_run(seed_value, GROWTH_SOAK_TICKS, run)
	check_eq(fz.report(), "", "every invariant on every tick of every seed")


func _growth_waits(what: String) -> bool:
	var waits := Gates.s2_missing(GROWTH_NEEDS)
	if waits.is_empty():
		return false
	print("test-endless-fuzz: %s waits on: %s" % [what, "; ".join(waits)])
	return true


## A sim with growth on for the growth fuzz: the real content once it holds size-2 sites, else the
## size-2 fake world.
func _growth_sim(seed_value: int) -> PoolSim:
	if Gates.s2_has("size_two_content"):
		return Gates.make_sim("omnivore", seed_value, true)
	return FakeWorldGen.endless_sim(seed_value, catalog, layout, FakeWorldGen.s2_species(), null, PackedFloat64Array(), 4, true)


## One seed of the growth fuzz: the wandering swim of _fuzz with growth on, the size set back at
## half of each cycle and a growth forced at its end, deaths continued after NOTICE. Returns the
## counts of FuzzInvariants plus {"grew", "forced", "set_backs", "respawns", "size", "hashes"}: the
## state hash after each grew and at the end. With `fz` null nothing is checked (a hash run).
func _growth_fuzz(fz: Variant, seed_value: int, ticks: int) -> Dictionary:
	var sim := _growth_sim(seed_value)
	sim.grace_until = sim.tick
	sim.drain_events()
	if fz != null:
		fz.start_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var heading := rng.randf_range(-PI, PI)
	var run := {"grew": 0, "forced": 0, "set_backs": 0, "respawns": 0, "size": 0, "hashes": PackedStringArray()}
	var dead_since := -1
	for t in ticks:
		var was: Dictionary = fz.before(sim) if fz != null else {}
		var c := t % GROWTH_CYCLE
		var alive := not sim.dead and not sim.respawn_pending
		if c == GROWTH_CYCLE / 2 and alive and sim.size() == 2 and sim.debug_set_size(1):
			run.set_backs += 1
		if c == GROWTH_CYCLE - 1 and alive and sim.debug_force_growth():
			run.forced += 1
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
		var events := sim.drain_events()
		if fz != null:
			fz.after(sim, events, tick, "growth seed %d tick %d" % [seed_value, t], was)
		for e in events:
			if e.type == "grew":
				run.grew += 1
				run.hashes.append(str(sim.state_hash()))
	run.hashes.append(str(sim.state_hash()))
	run.size = sim.size()
	if fz != null:
		run.merge(fz.counts)
	return run


## Non-vacuity of one growth run: a forced growth at the end of every whole cycle grew (the last
## cycle's may still be in its beat), and every growth but the last was set back.
func _check_growth_run(seed_value: int, ticks: int, run: Dictionary) -> void:
	var cycles := ticks / GROWTH_CYCLE
	check(int(run.forced) >= cycles, "seed %d: %d growths forced over %d cycles" % [seed_value, int(run.forced), cycles])
	check(int(run.grew) >= cycles, "seed %d: %d grew over %d cycles" % [seed_value, int(run.grew), cycles])
	check(int(run.set_backs) >= cycles - 1, "seed %d: set back to size 1 %d times" % [seed_value, int(run.set_backs)])
	check(int(run.get("set_sizes", 0)) >= int(run.set_backs), "seed %d: the checker saw %d set_size cuts" % [seed_value, int(run.get("set_sizes", 0))])
	check(int(run.get("growths", 0)) >= cycles, "seed %d: the checker saw %d growth ticks" % [seed_value, int(run.get("growths", 0))])
	for key in ["loads", "unloads", "spawns"]:
		check(int(run[key]) > 0, "seed %d: %s happened (%d)" % [seed_value, key, int(run[key])])


func _print_growth(seed_value: int, run: Dictionary) -> void:
	print("test-endless-fuzz: growth seed %d: %d forced, %d grew, %d set back, %d respawns, size %d at the end; %d growth ticks and %d set_size cuts checked; %d spawns, %d sleeps, %d wakes, %d loads, %d unloads, %d rebases" % [
		seed_value, run.forced, run.grew, run.set_backs, run.respawns, run.size, int(run.get("growths", 0)),
		int(run.get("set_sizes", 0)), run.spawns, run.sleeps, run.wakes, run.loads, run.unloads, run.rebases])


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
