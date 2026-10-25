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
##
## S3 (T0.4; s3-sim 8.1, S3G17 (K), S3G17d, S3G25; X3-16 keeps invariant 14 in test_threat_fuzz):
##  - the S3 growth fuzz: the same cycles on the band-1 fixture world (world_b1_min.json, top 4),
##    from size 2, the size set back to 2 at size 4, so the forced growths go 2 to 3 and 3 to 4; fast
##    on one seed run twice (the hashes alike), slow on four;
##  - the size-4 tours on the shipped world at its size-4 top (WorldChecks, until I-3 flips the
##    shipped file): the cell swims (SwimBot.Unjam) to the landmark anchors round home, nearest
##    first, and holds by each until the landmark pass moves the checkpoint there or TOUR_HOLD_TICKS
##    pass; a dev feed keeps it from starving on the way, since the tour never stops to eat.
##    S3G25: one tour past TOUR_ANCHORS anchors, invariant 3 on every tick across the landmark
##    moves; S3G17 (K): four tours of 5 minutes, invariant 12 with the morsel sites they load. The
##    tours' creatures eat each morsel item soon after it spawns, so none is live when its chunk
##    unloads: the unload clause's cases are test_morsel_sites' and test_fuzz_invariants'.
## FuzzInvariants checks S3G17d (morsel_claims) on every tick of every run.

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
const GROWTH_NEEDS: PackedStringArray = ["set_size", "force_growth", "fuzz_growth"]
const GROWTH_CYCLE := 1200
const GROWTH_FAST_SEED := 531
const GROWTH_FAST_TICKS := 2520
const GROWTH_SLOW_SEEDS: Array[int] = [531, 532, 533, 534]
const GROWTH_SLOW_TICKS := 6000
const GROWTH_SOAK_SEEDS: Array[int] = [535, 536]
const GROWTH_SOAK_TICKS := 36000
const WorldChecks := preload("res://tests/world_checks.gd")
const S3_WORLD := "res://tests/fixtures/world/world_b1_min.json"
const S3_PERIOD := 4                    ## FakeWorldGen's site period on the fixture world
const S3_GROWTH_FAST_SEED := 541
const S3_GROWTH_SLOW_SEEDS: Array[int] = [541, 542, 543, 544]
const TOUR_SEED := 551
const TOUR_ANCHORS := 20
const TOUR_MAX_TICKS := 15 * 60 * 60    ## the S3G25 tour's bound (it passes 20 anchors in about 8 min)
const TOUR_SEEDS: Array[int] = [561, 562, 563, 564]
const TOUR_TICKS := 5 * 60 * 60
const TOUR_CHUNKS := 8                  ## the anchors toured lie within this many chunks of home
const TOUR_NEAR_TM := 3.0               ## by an anchor: within this of it (landmark_find_tm is 6)
const TOUR_HOLD_TICKS := 240            ## how long the cell holds by an anchor that does not take it
const TOUR_FEED_SHARE := 0.5            ## the dev feed fills the cell below this share of its energy
const TOUR_MIN_LANDMARK_MOVES := 5

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog
var _top4: WorldContent


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


## S3 T0.4: the growth fuzz through 2 to 3 and 3 to 4 on the band-1 fixture world, one seed run
## twice: every invariant on every tick through both growths, and the two runs hash alike.
func test_s3_growth_fuzz_grows_two_to_three_to_four_and_two_runs_hash_alike() -> void:
	var fz := FuzzInvariants.new(species, layout)
	var a := _growth_fuzz(fz, S3_GROWTH_FAST_SEED, GROWTH_FAST_TICKS, true)
	var b := _growth_fuzz(null, S3_GROWTH_FAST_SEED, GROWTH_FAST_TICKS, true)
	_print_growth(S3_GROWTH_FAST_SEED, a)
	check_eq(fz.report(), "", "every invariant on every tick through 2 to 3 and 3 to 4")
	_check_growth_run(S3_GROWTH_FAST_SEED, GROWTH_FAST_TICKS, a, true)
	check_eq(a.hashes, b.hashes, "two runs hash alike after every growth and at the end")


func test_slow_s3_growth_fuzz_on_four_seeds() -> void:
	var fz := FuzzInvariants.new(species, layout)
	for seed_value in S3_GROWTH_SLOW_SEEDS:
		var run := _growth_fuzz(fz, seed_value, GROWTH_SLOW_TICKS, true)
		_print_growth(seed_value, run)
		_check_growth_run(seed_value, GROWTH_SLOW_TICKS, run, true)
	check_eq(fz.report(), "", "every invariant on every tick of every seed")


## S3G25: a size-4 swim past TOUR_ANCHORS landmark anchors keeps invariant 3 on every tick across
## the checkpoint's landmark moves (at a landmark checkpoint only the q == 1 creatures count).
func test_slow_a_size_four_swim_past_20_anchors_keeps_invariant_3_across_landmark_moves() -> void:
	var fz := FuzzInvariants.new(species, layout)
	var run := _tour(fz, TOUR_SEED, TOUR_MAX_TICKS, TOUR_ANCHORS)
	_print_tour(TOUR_SEED, run)
	check(int(run.passed) >= TOUR_ANCHORS, "past %d anchors (%d) in %d ticks" % [TOUR_ANCHORS, int(run.passed), int(run.ticks)])
	check(int(run.landmark_moves) >= TOUR_MIN_LANDMARK_MOVES, "the checkpoint moved to a landmark %d times (at least %d)" % [
		int(run.landmark_moves), TOUR_MIN_LANDMARK_MOVES])
	check_eq(fz.report(), "", "every invariant on every tick of the tour")


## S3G17 (K): four size-4 tours of 5 minutes keep invariant 12 with the morsel sites they load (and
## every other invariant, S3G17d among them, on every tick); each spawns morsel items.
func test_slow_size_four_tours_keep_invariant_12_with_morsel_sites_on_four_seeds() -> void:
	var fz := FuzzInvariants.new(species, layout)
	for seed_value in TOUR_SEEDS:
		var run := _tour(fz, seed_value, TOUR_TICKS)
		_print_tour(seed_value, run)
		check(int(run.morsel_spawns) > 0, "seed %d: morsel items spawned (%d)" % [seed_value, int(run.morsel_spawns)])
	check_eq(fz.report(), "", "every invariant on every tick of every tour")


func _growth_waits(what: String) -> bool:
	var waits := Gates.s2_missing(GROWTH_NEEDS)
	if waits.is_empty():
		return false
	print("test-endless-fuzz: %s waits on: %s" % [what, "; ".join(waits)])
	return true


## The S3 growth fuzz's sim: FakeWorldGen on the band-1 fixture world (top 4), growth on, at size 2.
func _s3_growth_sim(seed_value: int) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(seed_value, catalog, layout, species, FakeWorldGen.fixture_content(S3_WORLD),
		PackedFloat64Array(), S3_PERIOD, true)
	check(sim.debug_set_size(2), "seed %d: size 2" % seed_value)
	return sim


## A sim with growth on for the growth fuzz: the real content once it holds size-2 sites, else the
## size-2 fake world.
func _growth_sim(seed_value: int) -> PoolSim:
	if Gates.s2_has("size_two_content"):
		return Gates.make_sim("omnivore", seed_value, true)
	return FakeWorldGen.endless_sim(seed_value, catalog, layout, FakeWorldGen.s2_species(), null, PackedFloat64Array(), 4, true)


## One seed of the growth fuzz: the wandering swim of _fuzz with growth on, the size set back at
## half of each cycle and a growth forced at its end, deaths continued after NOTICE. S2's runs on
## _growth_sim set size 2 back to 1; with `s3` the run is on the band-1 fixture world from size 2 and
## sets size 4 back to 2. Returns the counts of FuzzInvariants plus {"grew", "grew_to" (per size),
## "forced", "set_backs", "respawns", "size", "hashes"}: the state hash after each grew and at the
## end. With `fz` null nothing is checked (a hash run).
func _growth_fuzz(fz: Variant, seed_value: int, ticks: int, s3 := false) -> Dictionary:
	var sim := _s3_growth_sim(seed_value) if s3 else _growth_sim(seed_value)
	var top := 4 if s3 else 2
	var floor_size := 2 if s3 else 1
	sim.grace_until = sim.tick
	sim.drain_events()
	if fz != null:
		fz.start_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var heading := rng.randf_range(-PI, PI)
	var run := {"grew": 0, "grew_to": {}, "forced": 0, "set_backs": 0, "respawns": 0, "size": 0, "hashes": PackedStringArray()}
	var dead_since := -1
	for t in ticks:
		var was: Dictionary = fz.before(sim) if fz != null else {}
		var c := t % GROWTH_CYCLE
		var alive := not sim.dead and not sim.respawn_pending
		if c == GROWTH_CYCLE / 2 and alive and sim.size() == top and sim.debug_set_size(floor_size):
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
				run.grew_to[sim.size()] = int(run.grew_to.get(sim.size(), 0)) + 1
				run.hashes.append(str(sim.state_hash()))
	run.hashes.append(str(sim.state_hash()))
	run.size = sim.size()
	if fz != null:
		run.merge(fz.counts)
	return run


## Non-vacuity of one growth run: a forced growth at the end of every whole cycle grew (the last
## cycle's may still be in its beat), and every growth but the last was set back (with `s3`, every
## other one, at size 4, and the run grew both to 3 and to 4).
func _check_growth_run(seed_value: int, ticks: int, run: Dictionary, s3 := false) -> void:
	var cycles := ticks / GROWTH_CYCLE
	check(int(run.forced) >= cycles, "seed %d: %d growths forced over %d cycles" % [seed_value, int(run.forced), cycles])
	check(int(run.grew) >= cycles, "seed %d: %d grew over %d cycles" % [seed_value, int(run.grew), cycles])
	var backs := (cycles - 1) / 2 if s3 else cycles - 1
	check(int(run.set_backs) >= backs, "seed %d: set back %d times" % [seed_value, int(run.set_backs)])
	if s3:
		check(int(run.grew_to.get(3, 0)) >= 1 and int(run.grew_to.get(4, 0)) >= 1, "seed %d: grew to 3 and to 4 (%s)" % [
			seed_value, run.grew_to])
	check(int(run.get("set_sizes", 0)) >= int(run.set_backs), "seed %d: the checker saw %d set_size cuts" % [seed_value, int(run.get("set_sizes", 0))])
	check(int(run.get("growths", 0)) >= cycles, "seed %d: the checker saw %d growth ticks" % [seed_value, int(run.get("growths", 0))])
	for key in ["loads", "unloads", "spawns"]:
		check(int(run[key]) > 0, "seed %d: %s happened (%d)" % [seed_value, key, int(run[key])])


func _print_growth(seed_value: int, run: Dictionary) -> void:
	print("test-endless-fuzz: growth seed %d: %d forced, %d grew %s, %d set back, %d respawns, size %d at the end; %d growth ticks and %d set_size cuts checked; %d spawns, %d sleeps, %d wakes, %d loads, %d unloads, %d rebases" % [
		seed_value, run.forced, run.grew, run.grew_to, run.set_backs, run.respawns, run.size, int(run.get("growths", 0)),
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


## A new omnivore lineage of `seed_value` at home on the shipped world at its size-4 top, growth on,
## set to size 4.
func _top4_sim(seed_value: int) -> PoolSim:
	if _top4 == null:
		_top4 = WorldContent.load_from(WorldChecks.shipped_world_at(4), layout, species)
	_top4.config.switches["growth"] = true
	var r := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save_abs(_top4.home.spawn[0], _top4.home.spawn[1])
	var sim := PoolSim.create(r.save, catalog, layout, species, _top4)
	sim.grace_until = sim.tick
	check(sim.debug_set_size(4), "seed %d: size 4" % seed_value)
	sim.drain_events()
	return sim


## The landmark anchors (tm at size 4) within TOUR_CHUNKS chunks of home, in the order of a greedy
## nearest-next swim from home.
static func _anchor_order(sim: PoolSim, home: Vector2) -> Array[Vector2]:
	var left: Array[Vector2] = []
	for cy in range(-TOUR_CHUNKS, TOUR_CHUNKS + 1):
		for cx in range(-TOUR_CHUNKS, TOUR_CHUNKS + 1):
			for a in sim.world.gen.chunk(4, cx, cy).anchors:
				left.append(Vector2(float(a.x), float(a.y)))
	var out: Array[Vector2] = []
	var at := home
	while not left.is_empty():
		var best := 0
		for i in left.size():
			if left[i].distance_to(at) < left[best].distance_to(at):
				best = i
		at = left[best]
		out.append(at)
		left.remove_at(best)
	return out


## One size-4 tour of `seed_value` for up to `ticks` (or until it has passed `anchors`, when above
## 0), every tick checked by `fz`; deaths continued. An anchor is passed when the cell has held by it
## TOUR_HOLD_TICKS or the checkpoint moves to a landmark. Returns FuzzInvariants' counts plus
## {"passed", "landmark_moves", "fed", "ticks"}.
func _tour(fz: FuzzInvariants, seed_value: int, ticks: int, anchors := 0) -> Dictionary:
	var sim := _top4_sim(seed_value)
	fz.start_run()
	var order := _anchor_order(sim, Vector2(_top4.home.spawn[0], _top4.home.spawn[1]))
	var unjam := SwimBot.Unjam.new()
	var run := {"passed": 0, "landmark_moves": 0, "fed": 0, "ticks": 0}
	var dead := {}
	var held := 0
	for t in ticks:
		if anchors > 0 and int(run.passed) >= anchors:
			break
		Gates.continue_after_death(sim, dead, fz)
		var was := fz.before(sim)
		if not sim.dead and sim.state.energy < TOUR_FEED_SHARE * sim.state.energy_capacity:
			sim.debug_set_energy(sim.state.energy_capacity)
			run.fed += 1
		var intent := SimIntent.new()
		if not sim.dead and int(run.passed) < order.size():
			var goal := sim.world.local_of_tm(order[run.passed].x, order[run.passed].y)
			if sim.motion.position.distance_to(goal) > TOUR_NEAR_TM:
				intent.move = (unjam.aim(sim, goal) - sim.motion.position).normalized()
				held = 0
			else:
				held += 1
				if held > TOUR_HOLD_TICKS:
					run.passed += 1
					held = 0
		var tick := sim.tick
		sim.step(intent)
		var events := sim.drain_events()
		fz.after(sim, events, tick, "tour seed %d tick %d" % [seed_value, t], was)
		for e in events:
			if e.type == "checkpoint_moved" and str(e.get("reason", "")) == "landmark":
				run.landmark_moves += 1
				run.passed += 1
				held = 0
		run.ticks = t + 1
	run.merge(fz.counts)
	return run


func _print_tour(seed_value: int, run: Dictionary) -> void:
	print("test-endless-fuzz: size-4 tour seed %d: %d ticks, %d anchors passed, %d landmark moves, %d feeds, %d deaths; %d morsel spawns, %d morsel unloads, %d loads, %d unloads, %d spawns, %d rebases, %d drift checks" % [
		seed_value, run.ticks, run.passed, run.landmark_moves, run.fed, run.deaths, run.morsel_spawns, run.morsel_unloads,
		run.loads, run.unloads, run.spawns, run.rebases, run.drift_checks])
