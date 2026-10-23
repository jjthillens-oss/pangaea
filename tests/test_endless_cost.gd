extends TestCase
## The endless world's cost gates (S1 spine T0.7, core 10.2; G17). A straight swim from home on the
## content tests/test_endless_gates.gd picks (the real tiles once T4.3 lands, the fixture world
## before), with RACER, the fastest legal body, hidden from the creatures so a chase or a death does
## not change what is timed. The slow gates swim overdriven (SwimBot.overdrive before every step: the
## 6 tm/s cap the plan names, which no legal body reaches; S1 build plan B-12); the soak case repeats
## them with RACER as it is (4.41 tm/s). Every timed step is followed on the same thread by the
## yardstick (tests/cost_yardstick.gd), as #28 does, and the flake policy of docs/DECISIONS.md ("M1
## step 3 review fixes") applies: only a pass on a quiet machine or on CI rules a regression out.
##  - #28E: 3 runs of 1,800 ticks after 600 warm-up ticks; the fastest run's median tick is at most
##    1,500 us and the median run's median at most 8 yardsticks. awake_overflow and chunk_waits stay
##    0 on every run (G17).
##  - P99.9: the 99.9th percentile tick is at most 16 yardsticks. The 3 runs time the same ticks
##    (their end hashes are equal), and each tick counts at its fastest of the 3, as #29's windows do,
##    so one burst of load from another process does not fail the gate; the median run's own
##    percentile is printed beside it. RACER as it is gets the same 3-run set: one run's own
##    percentile is load, not cost.
##  - Sleeper: after a swim the left-behind sleepers are timed against a twin sim with them removed,
##    tick by tick in turn, 200 ticks each, 3 rounds: the difference of the two sims' median ticks
##    per sleeper is at most 2 us. Each round builds the twins afresh, so the 3 rounds time the same
##    ticks (their end hashes are equal), and each tick of each sim counts at its fastest of the 3,
##    as P99.9's do; every round's own difference is printed beside it. The limit is in microseconds,
##    so load that slows every tick alike still moves it. Debug creatures never sleep (core CC-6), so
##    the sleepers are the world's own: the swim goes east at least SLEEPER_SWIM_TICKS and on until
##    SLEEPER_STOP of them sleep, since how many sleep where it stops depends on the tiles there (on
##    the real content 6 or 7 after 1,200 ticks). On the fixture world there may be too few to time,
##    and the gate then waits for the real content.
##  - Rebase: 20 ticks with debug_rebase of 3 chunks against the plain tick just before each; the
##    median excess is at most 2 yardsticks. The 3 runs time the same rebases (their end hashes are
##    equal), and each tick, the rebase tick and the plain one, counts at its fastest of the 3, as
##    P99.9's do, so one burst of load on either tick does not move the excess; the median run's own
##    median is printed beside it. The rebase goes against the cell's side of the origin, so the
##    tick holds one rebase, not two.
##  - Saturated (B-7): on DenseGen, T2's FakeWorldGen with 3 zones and 9 rammer sites a chunk, RACER
##    swims overdriven east for 1,200 ticks and then 600 timed ticks, 3 runs, with the awake cap
##    (12, at least 6 in view), the sleeper cap (30) and the food cap (120, less one zone's worth
##    being eaten) full. The slow case checks that and prints the rows; the soak case holds B-7's
##    limits, the median run's median tick at most 10 yardsticks and every tick that loads a chunk at
##    most 16 at its fastest of 3. The saturated case needs no invariant, so it waits on
##    Gates.missing(Gates.WORLD) and FakeWorldGen only.
## While the endless world has not landed each prints what it waits on (Gates.missing()).

const Gates := preload("res://tests/test_endless_gates.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const Yardstick := preload("res://tests/cost_yardstick.gd")

const COST_SEED := 2801
const RUNS := 3
const WARM_TICKS := 600
const TIMED_TICKS := 1800
const LIMIT_US := 1500.0
const LIMIT_YARDSTICKS := 8.0
const P999_YARDSTICKS := 16.0
const P999 := 0.999
const SLEEPER_SWIM_TICKS := 1200      ## at least about 120 tm east overdriven (88 as it is), leaving the home block's creatures behind,
const SLEEPER_STOP := 10              ## then on east until this many of the world's own creatures sleep (SLEEPER_MIN and two)
const SLEEPER_SWIM_MAX_TICKS := 4800  ## or until this many ticks in all
const SLEEPER_REST_TICKS := 60
const SLEEPER_TICKS := 200
const SLEEPER_ROUNDS := 3
const SLEEPER_MIN := 8                ## fewer cannot be told from noise
const SLEEPER_LIMIT_US := 2.0
const REBASES := 20
const REBASE_GAP_TICKS := 30
const REBASE_CHUNKS := 3
const REBASE_LIMIT_YARDSTICKS := 2.0
## The saturated case (B-7): a dense FakeWorldGen world (DenseGen), RACER overdriven east along the
## lane y = DENSE_LANE_Y from x = 0 for DENSE_WARM_TICKS, then DENSE_TICKS timed ticks, 3 runs.
const FAKE_GEN := "res://tests/fakes/fake_world_gen.gd"   ## T2's permanent test generator
const DENSE_SEED := 2802
const DENSE_LANE_Y := 16.0             ## tm: between the zone rows at 8 and 24 of every chunk
const DENSE_WARM_TICKS := 1200         ## 120 tm: the cell is among creatures that spawned out of its view
const DENSE_TICKS := 600
const DENSE_MIN_IN_VIEW := 6           ## at least half the awake cap in the cell's view
const DENSE_LIMIT_YARDSTICKS := 10.0   ## the median run's median tick
const DENSE_LOAD_LIMIT_YARDSTICKS := 16.0   ## every tick that loads a chunk, at its fastest of 3

static var _runs := {}                ## overdriven (bool) -> the timed swim runs
static var _dense: Array[Dictionary] = []   ## the saturated case's 3 runs


func _waits(gate: String) -> bool:
	var what := Gates.missing()
	if what.is_empty():
		return false
	print("test-endless-cost: %s waits on: %s" % [gate, "; ".join(what)])
	return true


static func _mode(overdriven: bool) -> String:
	return "overdriven" if overdriven else "racer"


## A racer at home, hidden, about to swim east.
static func _swimmer() -> Variant:
	var sim: Variant = Gates.make_sim(Gates.RACER, COST_SEED)
	sim.debug_set_hidden(true)
	sim.drain_events()
	return sim


## One untimed swim step: overdriven or as it is (Gates.drive), then the bot's move.
static func _swim_step(sim: Variant, bot: Variant, overdriven: bool) -> void:
	Gates.drive(sim, overdriven)
	sim.step(bot.next_intent(sim))
	sim.drain_events()


## Steps `sim` once, timed, then runs the yardstick: {"us", "yard_us", "ratio", "events"}. The caller
## drives the sim before it (outside the timing).
static func _timed_step(sim: Variant, intent: SimIntent, rebase_by := Vector2i.ZERO) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	if rebase_by != Vector2i.ZERO:
		sim.debug_rebase(rebase_by)
	sim.step(intent)
	var us := Time.get_ticks_usec() - t0
	var yard := Yardstick.time_once()
	return {"us": float(us), "yard_us": float(yard), "ratio": us / float(maxi(yard, 1)), "events": sim.drain_events()}


## The three timed runs of the straight swim (shared by #28E and P99.9): per run, every tick's us
## and yardsticks, the end hash and the counters.
func _swim_runs(overdriven: bool) -> Array[Dictionary]:
	if _runs.has(overdriven):
		return _runs[overdriven]
	var out: Array[Dictionary] = []
	for run in RUNS:
		var sim: Variant = _swimmer()
		var bot = SwimBot.new(Vector2.RIGHT)
		var start: PackedFloat64Array = sim.absolute_position_am()
		for i in WARM_TICKS:
			_swim_step(sim, bot, overdriven)
		var us: Array[float] = []
		var ratios: Array[float] = []
		for i in TIMED_TICKS:
			Gates.drive(sim, overdriven)
			var t := _timed_step(sim, bot.next_intent(sim))
			us.append(t.us)
			ratios.append(t.ratio)
		out.append({"us": us, "ratios": ratios, "hash": sim.state_hash(), "chunks": sim.world.loaded_keys().size(),
			"awake": sim.creatures.awake().size(), "sleeping": sim.world.sleeping_ids().size(),
			"awake_overflow": int(sim.world.counters.awake_overflow), "chunk_waits": int(sim.world.counters.chunk_waits),
			"speed": Gates.abs_distance(start, sim.absolute_position_am()) / ((WARM_TICKS + TIMED_TICKS) / 60.0)})
	_runs[overdriven] = out
	return out


## Each tick's yardsticks (or the run's `key` array) at its fastest of `runs` (which timed the same
## ticks).
static func _fastest_per_tick(runs: Array[Dictionary], key := "ratios") -> Array[float]:
	var out: Array[float] = []
	for i in (runs[0][key] as Array).size():
		var best := INF
		for r in runs:
			best = minf(best, r[key][i])
		out.append(best)
	return out


## The value at quantile `q` of `values`: the ceil(q n)-th smallest.
static func _percentile(values: Array[float], q: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(q * sorted.size()) - 1, 0, sorted.size() - 1)]


## The helpers the gates read their numbers with (fast; the gates themselves are slow and soak).
func test_the_percentile_and_fastest_tick_helpers() -> void:
	var values: Array[float] = []
	for i in 1800:
		values.append(float(1799 - i))
	check_eq(_percentile(values, P999), 1798.0, "P99.9 of 1,800 ticks is the second slowest")
	check_eq(_percentile(values, 0.5), 899.0, "the 900th smallest")
	var one: Array[float] = [7.0]
	check_eq(_percentile(one, P999), 7.0, "a single value")
	var a: Array[float] = [5.0, 1.0, 9.0]
	var b: Array[float] = [4.0, 3.0, 9.5]
	var runs: Array[Dictionary] = [{"ratios": a}, {"ratios": b}]
	check_eq(_fastest_per_tick(runs), [4.0, 1.0, 9.0] as Array[float], "each tick at its fastest run")
	var plain_a: Array[float] = [2.0, 3.0]
	var plain_b: Array[float] = [9.0, 2.5]
	var at_a: Array[float] = [4.0, 6.0]
	var at_b: Array[float] = [3.5, 30.0]
	var pairs: Array[Dictionary] = [{"before": plain_a, "at": at_a}, {"before": plain_b, "at": at_b}]
	check_eq(_fastest_excess(pairs), [1.5, 3.5] as Array[float], "a rebase tick at its fastest less the plain tick at its fastest")
	check_eq(_rebases([{"type": "debug"}, {"type": "rebased"}, {"type": "rebased"}]), 2, "rebased events counted")


func test_slow_a_size_1_swim_costs_at_most_8_yardsticks_a_tick() -> void:
	if _waits("#28E"):
		return
	_check_swim_cost(true)


func test_slow_the_slowest_tick_in_a_thousand_stays_under_16_yardsticks() -> void:
	if _waits("P99.9"):
		return
	_check_p999(true)


func test_slow_a_sleeper_costs_at_most_2_us() -> void:
	if _waits("sleeper"):
		return
	_check_sleeper_cost(true)


func test_slow_a_rebase_tick_costs_at_most_2_yardsticks_more() -> void:
	if _waits("rebase"):
		return
	_check_rebase_cost(true)


## The saturated case (B-7), measured: on a dense world with the awake, sleeper and food caps full,
## the 3 runs time the same ticks, chunks load during them, and the case prints its rows (each
## run's median tick, the load ticks at their fastest, the counts). B-7's limits are the soak gate
## below: this case read about twice them, and B-7's remedy (caps.awake 10) as much (docs/DECISIONS.md,
## S1 build decisions), so asserting them here would stop every check.sh until that is settled.
func test_slow_a_saturated_world_fills_its_caps_and_prints_its_cost() -> void:
	if _dense_waits("the saturated case"):
		return
	var runs := _dense_runs()
	var r0: Dictionary = runs[0]
	var caps: Dictionary = r0.caps
	for r in runs:
		check_eq(r.hash, r0.hash, "every run timed the same ticks")
		check_eq(r.load_ticks, r0.load_ticks, "every run loaded on the same ticks")
	var medians: Array[float] = []
	for r in runs:
		medians.append(Yardstick.median(r.ratios))
	var loads := _dense_load_ticks(runs)
	var verdict := "within" if Yardstick.median(medians) <= DENSE_LIMIT_YARDSTICKS and (loads.is_empty() or loads.max() <= DENSE_LOAD_LIMIT_YARDSTICKS) else "OVER"
	print("test-endless-cost: saturated: over %d ticks after %d the median awake %d (%d in view), asleep %d, food %d (caps %d, %d, %d), %d chunks, %d sites, %d loads; median tick %.2f yardsticks in the median run (%s), %.1f us; load ticks at their fastest %s; awake_overflow %d, evictions %d, food_trimmed %d; %s B-7's limits (%.0f, %.0f)" % [
		DENSE_TICKS, DENSE_WARM_TICKS, r0.awake, r0.in_view, r0.asleep, r0.food, int(caps.awake), int(caps.sleepers),
		int(caps.food_items), r0.chunks, r0.sites, loads.size(), Yardstick.median(medians), _joined(medians, "%.2f"),
		Yardstick.median(r0.us), _joined(loads, "%.2f"), r0.awake_overflow, r0.evictions, r0.food_trimmed, verdict,
		DENSE_LIMIT_YARDSTICKS, DENSE_LOAD_LIMIT_YARDSTICKS])
	check_eq(int(r0.awake), int(caps.awake), "the median tick has the awake cap full")
	check(int(r0.in_view) >= DENSE_MIN_IN_VIEW, "and at least %d of them in view (%d)" % [DENSE_MIN_IN_VIEW, r0.in_view])
	check_eq(int(r0.asleep), int(caps.sleepers), "the median tick has the sleeper cap full")
	check(int(r0.food) <= int(caps.food_items) and int(r0.food) >= int(caps.food_items) - int(caps.food_per_zone),
		"the median tick has the food cap full but for one zone's worth eaten and regrowing (%d of %d)" % [r0.food, caps.food_items])
	check(not loads.is_empty(), "chunks loaded during the timing")


## B-7's gate on the saturated case: the median run's median tick at most 10 yardsticks and every
## tick that loads a chunk at most 16 at its fastest of 3. If it fails, T1 lowers caps.awake to 10
## and nothing else changes first.
func test_soak_a_saturated_world_costs_at_most_10_yardsticks_a_tick() -> void:
	if _dense_waits("B-7's saturated gate"):
		return
	var runs := _dense_runs()
	var medians: Array[float] = []
	for r in runs:
		medians.append(Yardstick.median(r.ratios))
	var median := Yardstick.median(medians)
	var loads := _dense_load_ticks(runs)
	print("test-endless-cost: B-7: median tick %.2f yardsticks in the median run (%s); load ticks at their fastest %s" % [
		median, _joined(medians, "%.2f"), _joined(loads, "%.2f")])
	check(not loads.is_empty(), "chunks loaded during the timing")
	check(median <= DENSE_LIMIT_YARDSTICKS, "median tick %.2f yardsticks in the median run (limit %.1f)" % [median, DENSE_LIMIT_YARDSTICKS])
	for i in loads.size():
		check(loads[i] <= DENSE_LOAD_LIMIT_YARDSTICKS, "load tick %d: %.2f yardsticks at its fastest (limit %.1f)" % [
			runs[0].load_ticks[i], loads[i], DENSE_LOAD_LIMIT_YARDSTICKS])


## The saturated case reads the endless world's counters and fields, not the invariants, and swims on
## T2's FakeWorldGen, so it waits on Gates.WORLD and that file only.
func _dense_waits(gate: String) -> bool:
	var what := Gates.missing(Gates.WORLD)
	if not FileAccess.file_exists(FAKE_GEN):
		what.append("tests/fakes/fake_world_gen.gd (T2.1)")
	if what.is_empty():
		return false
	print("test-endless-cost: %s waits on: %s" % [gate, "; ".join(what)])
	return true


## The 3 runs of the saturated case, run once per process.
func _dense_runs() -> Array[Dictionary]:
	if _dense.is_empty():
		for run in RUNS:
			_dense.append(_dense_run())
	return _dense


## The yardsticks of each timed tick that loaded a chunk, at its fastest of the runs.
static func _dense_load_ticks(runs: Array[Dictionary]) -> Array[float]:
	var fastest := _fastest_per_tick(runs)
	var out: Array[float] = []
	for i in runs[0].load_ticks:
		out.append(fastest[i])
	return out


## One run of the saturated case: RACER overdriven east from (0, DENSE_LANE_Y) on DenseGen, hidden,
## DENSE_WARM_TICKS untimed, then DENSE_TICKS timed. Returns each tick's us and yardsticks, the timed
## ticks that loaded a chunk (indices), the end hash and the median count of each capped thing.
func _dense_run() -> Dictionary:
	var catalog := PartCatalog.load_from()
	var layout := PoolLayout.load_from()
	var species := SpeciesCatalog.load_from()
	var Fake: GDScript = load(FAKE_GEN)
	var content: Variant = Fake.call("fixture_content")
	var r := Lineage.found(DENSE_SEED, Gates.BUILD_ID, catalog, "hunter")
	Gates.make_racer(r.save.genome, catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, DENSE_LANE_Y)
	var sim: Variant = (load(Gates.POOL_SIM_PATH) as GDScript).callv("_create_endless",
		[r.save, catalog, layout, species, content, DenseGen.new(content, species, DENSE_SEED)])
	sim.debug_set_hidden(true)
	sim.drain_events()
	var caps: Dictionary = sim.world.caps
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in DENSE_WARM_TICKS:
		_swim_step(sim, bot, true)
	var us: Array[float] = []
	var ratios: Array[float] = []
	var load_ticks: Array[int] = []
	var counts := {"awake": [] as Array[float], "in_view": [] as Array[float], "asleep": [] as Array[float], "food": [] as Array[float]}
	for i in DENSE_TICKS:
		Gates.drive(sim, true)
		var t := _timed_step(sim, bot.next_intent(sim))
		us.append(t.us)
		ratios.append(t.ratio)
		for e in t.events:
			if e.type == "chunk_loaded":
				load_ticks.append(i)
				break
		counts.awake.append(float(sim.creatures.awake().size()))
		counts.in_view.append(float(_awake_in_view(sim)))
		counts.asleep.append(float(sim.world.sleeping_ids().size()))
		counts.food.append(float(sim.plankton.items.size()))
	var c: Dictionary = sim.world.counters
	return {"us": us, "ratios": ratios, "load_ticks": load_ticks, "hash": sim.state_hash(), "caps": caps,
		"awake": int(Yardstick.median(counts.awake)), "in_view": int(Yardstick.median(counts.in_view)),
		"asleep": int(Yardstick.median(counts.asleep)), "food": int(Yardstick.median(counts.food)),
		"chunks": sim.world.loaded_keys().size(), "sites": sim.world.sites.size(), "awake_overflow": int(c.awake_overflow), "evictions": int(c.evictions),
		"food_trimmed": int(c.food_trimmed)}


## The awake creatures in the cell's widest view, as the stream keeps them awake: within its view
## margin plus their radius of the view's footprint.
static func _awake_in_view(sim: Variant) -> int:
	var w: Variant = sim.world
	var quad := ViewFootprint.corners(sim.motion.position, w.camera, float(w.camera.zoom_max), float(w.view_aspect))
	var n := 0
	for c in sim.creatures.awake():
		if ViewFootprint.distance_outside(quad, c.motion.position) <= float(w.view_margin) + c.phenotype.radius:
			n += 1
	return n


## The four gates again with RACER as it is (B-12: each overdriven swim keeps one racer run).
func test_soak_the_racer_as_it_is_meets_the_same_cost_gates() -> void:
	if _waits("the racer's cost gates"):
		return
	_check_swim_cost(false)
	_check_p999(false)
	_check_sleeper_cost(false)
	_check_rebase_cost(false)


func _check_swim_cost(overdriven: bool) -> void:
	var mode := _mode(overdriven)
	var runs := _swim_runs(overdriven)
	var medians: Array[float] = []
	var ratios: Array[float] = []
	for r in runs:
		medians.append(Yardstick.median(r.us))
		ratios.append(Yardstick.median(r.ratios))
		check_eq(r.hash, runs[0].hash, "%s: every run timed the same ticks" % mode)
		check_eq(int(r.awake_overflow) + int(r.chunk_waits), 0, "%s: no awake overflow and no chunk waits on the swim (G17)" % mode)
	var fastest: float = medians.min()
	var ratio := Yardstick.median(ratios)
	print("test-endless-cost: #28E %s on %s at %.2f tm/s: median tick %.1f us in the fastest of %d runs (%s); %.2f yardsticks in the median run (%s); %d chunks, %d awake, %d asleep at the end; awake_overflow %d, chunk_waits %d" % [
		mode, Gates.content_path(), runs[0].speed, fastest, RUNS, _joined(medians, "%.1f"), ratio, _joined(ratios, "%.2f"),
		runs[0].chunks, runs[0].awake, runs[0].sleeping, runs[0].awake_overflow, runs[0].chunk_waits])
	check(fastest <= LIMIT_US, "%s: median tick %.1f us in the fastest run (limit %.0f)" % [mode, fastest, LIMIT_US])
	check(ratio <= LIMIT_YARDSTICKS, "%s: %.2f yardsticks in the median run (limit %.1f)" % [mode, ratio, LIMIT_YARDSTICKS])


func _check_p999(overdriven: bool) -> void:
	var mode := _mode(overdriven)
	var runs := _swim_runs(overdriven)
	var fastest := _fastest_per_tick(runs)
	var p := _percentile(fastest, P999)
	var by_median: Array[float] = []
	for r in runs:
		by_median.append(Yardstick.median(r.ratios))
	var median_run: Dictionary = runs[by_median.find(Yardstick.median(by_median))]
	print("test-endless-cost: P99.9 %s %.2f yardsticks over each tick's fastest run; the median run's own %.2f; worst tick %.2f" % [
		mode, p, _percentile(median_run.ratios, P999), fastest.max()])
	check(p <= P999_YARDSTICKS, "%s: P99.9 tick %.2f yardsticks (limit %.1f)" % [mode, p, P999_YARDSTICKS])


func _check_sleeper_cost(overdriven: bool) -> void:
	var mode := _mode(overdriven)
	var rounds: Array[Dictionary] = []
	for k in SLEEPER_ROUNDS:
		var r := _sleeper_round(overdriven)
		rounds.append(r)
		var n: int = r.n
		check_eq(int(r.twin_asleep), n, "%s: the twin sims are the same" % mode)
		if n < SLEEPER_MIN:
			if Gates.content_path() != Gates.REAL_WORLD:
				print("test-endless-cost: sleeper %s waits on the real content: %d sleepers on %s (need %d)" % [
					mode, n, Gates.content_path(), SLEEPER_MIN])
				return
			check(false, "%s: only %d sleepers after the swim on the real content (need %d)" % [mode, n, SLEEPER_MIN])
			return
		check_eq(int(r.twin_left), 0, "%s: the twin has no sleepers" % mode)
		check(int(r.asleep_end) == n, "%s: they slept through the timing" % mode)
	var r0: Dictionary = rounds[0]
	var n0: int = r0.n
	for r in rounds:
		check_eq(r.hash, r0.hash, "%s: every round timed the same ticks" % mode)
	var per: Array[float] = []
	for r in rounds:
		per.append((Yardstick.median(r.with_us) - Yardstick.median(r.without_us)) / n0)
	var cost := (Yardstick.median(_fastest_per_tick(rounds, "with_us")) - Yardstick.median(_fastest_per_tick(rounds, "without_us"))) / n0
	print("test-endless-cost: %s: %d sleepers after %d ticks east (%.0f tm) cost %.2f us each, each tick at its fastest of %d rounds (rounds %s); %d still asleep at the end" % [
		mode, n0, r0.swum, r0.east, cost, SLEEPER_ROUNDS, _joined(per, "%.2f"), r0.asleep_end])
	check(cost <= SLEEPER_LIMIT_US, "%s: a sleeper costs %.2f us (limit %.1f)" % [mode, cost, SLEEPER_LIMIT_US])


## One round of the sleeper gate: the twin sims built afresh (_sleeper_scene twice, the twin's
## sleepers removed), then SLEEPER_TICKS still ticks of each, timed in turn. The sims are
## deterministic, so every round times the same ticks. Returns the sleepers' count ("n") and the
## twin's before the removal ("twin_asleep"), and, with at least SLEEPER_MIN of them, each sim's
## timed ticks in us ("with_us", "without_us"), the twin's sleepers left ("twin_left"), the
## sleepers still asleep at the end ("asleep_end") and both sims' end hashes.
static func _sleeper_round(overdriven: bool) -> Dictionary:
	var with_them: Variant = _sleeper_scene(overdriven)
	var without: Variant = _sleeper_scene(overdriven)
	var sleepers: Array = []
	for c in without.creatures.creatures:
		if c.asleep:
			sleepers.append(c)
	var out := {"n": sleepers.size(), "twin_asleep": with_them.world.sleeping_ids().size(),
		"swum": with_them.tick - SLEEPER_REST_TICKS, "east": with_them.absolute_position_am()[0]}
	if sleepers.size() < SLEEPER_MIN:
		return out
	for c in sleepers:
		without.creatures.remove(c, "evicted", without.tick, false)
	without.drain_events()
	out.twin_left = without.world.sleeping_ids().size()
	var still := SimIntent.new()
	var a: Array[float] = []
	var b: Array[float] = []
	for i in SLEEPER_TICKS:
		a.append(_timed_step(with_them, still).us)
		b.append(_timed_step(without, still).us)
	out.with_us = a
	out.without_us = b
	out.asleep_end = with_them.world.sleeping_ids().size()
	out.hash = [with_them.state_hash(), without.state_hash()]
	return out


## A racer that swam east (overdriven or as it is) and stopped, leaving the creatures it passed
## asleep behind it: at least SLEEPER_SWIM_TICKS, then on until SLEEPER_STOP sleep (or
## SLEEPER_SWIM_MAX_TICKS in all).
static func _sleeper_scene(overdriven: bool) -> Variant:
	var sim: Variant = _swimmer()
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in SLEEPER_SWIM_MAX_TICKS:
		if i >= SLEEPER_SWIM_TICKS and sim.world.sleeping_ids().size() >= SLEEPER_STOP:
			break
		_swim_step(sim, bot, overdriven)
	for i in SLEEPER_REST_TICKS:
		sim.step(SimIntent.new())
		sim.drain_events()
	return sim


func _check_rebase_cost(overdriven: bool) -> void:
	var mode := _mode(overdriven)
	var runs: Array[Dictionary] = []
	for run in RUNS:
		runs.append(_rebase_run(overdriven))
	var r0: Dictionary = runs[0]
	var same := true
	for r in runs:
		check_eq(r.hash, r0.hash, "%s: every run timed the same rebases" % mode)
		same = same and r.kept == r0.kept
	check(same, "%s: every run kept the same tries" % mode)
	check_eq(r0.kept.size(), REBASES, "%s: %d rebase ticks timed in %d tries" % [mode, r0.kept.size(), r0.tries])
	if not same or r0.kept.is_empty():
		return
	var excess := _fastest_excess(runs)
	var m := Yardstick.median(excess)
	var own: Array[float] = []
	for r in runs:
		own.append(Yardstick.median(_excess(r.at, r.before)))
	print("test-endless-cost: %s: a rebase tick costs %.2f yardsticks more than the tick before it, each at its fastest of %d runs (median of %d: %s); the median run's own %.2f (runs %s)" % [
		mode, m, RUNS, excess.size(), _joined(excess, "%.2f"), Yardstick.median(own), _joined(own, "%.2f")])
	check(m <= REBASE_LIMIT_YARDSTICKS, "%s: a rebase tick costs %.2f yardsticks more (limit %.1f)" % [mode, m, REBASE_LIMIT_YARDSTICKS])


## One run of the rebase gate: RACER swims east WARM_TICKS untimed, then up to REBASES * 3 tries of
## REBASE_GAP_TICKS untimed, a timed plain tick and a timed tick with debug_rebase. A try is kept when
## the plain tick held no rebase and the other exactly one. Returns each kept try's yardsticks (the
## plain tick "before", the rebase tick "at"), the kept tries' numbers, the tries and the end hash.
static func _rebase_run(overdriven: bool) -> Dictionary:
	var sim: Variant = _swimmer()
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in WARM_TICKS:
		_swim_step(sim, bot, overdriven)
	var before: Array[float] = []
	var at: Array[float] = []
	var kept: Array[int] = []
	var tries := 0
	while kept.size() < REBASES and tries < REBASES * 3:
		tries += 1
		for i in REBASE_GAP_TICKS:
			_swim_step(sim, bot, overdriven)
		Gates.drive(sim, overdriven)
		var plain := _timed_step(sim, bot.next_intent(sim))
		if _rebases(plain.events) != 0:
			continue
		var by := Vector2i(REBASE_CHUNKS if sim.motion.position.x >= 0.0 else -REBASE_CHUNKS, 0)
		Gates.drive(sim, overdriven)
		var rebased := _timed_step(sim, bot.next_intent(sim), by)
		if _rebases(rebased.events) != 1:
			continue
		before.append(float(plain.ratio))
		at.append(float(rebased.ratio))
		kept.append(tries)
	return {"before": before, "at": at, "kept": kept, "tries": tries, "hash": sim.state_hash()}


## Each kept try's rebase tick at its fastest of `runs` less its plain tick at its fastest (the runs
## timed the same ticks).
static func _fastest_excess(runs: Array[Dictionary]) -> Array[float]:
	return _excess(_fastest_per_tick(runs, "at"), _fastest_per_tick(runs, "before"))


## at[i] - before[i] for each i.
static func _excess(at: Array[float], before: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for i in at.size():
		out.append(at[i] - before[i])
	return out


static func _rebases(events: Array) -> int:
	var n := 0
	for e in events:
		n += 1 if e.type == "rebased" else 0
	return n


static func _joined(values: Array[float], format: String) -> String:
	return ", ".join(values.map(func(v: float) -> String: return format % v))


## The saturated case's world (B-7): T2's FakeWorldGen made dense. Every chunk keeps the fake's shell
## at its centre + (8, 8), the south-east quadrant's centre, and holds a zone of the fake's radius and
## capacity on each other quadrant's centre, with PER_ZONE rammer sites spread round it HOME_R from
## its centre (homes 4.3 tm apart; min_gap_m is 2), facing it: their territory the zone, their reach
## the species' own leash disc. That is 9 sites a chunk, against the fake's one per 16 chunks.
class DenseGen extends "res://tests/fakes/fake_world_gen.gd":
	const ZONE_CENTRES: Array[Vector2] = [Vector2(8.0, 8.0), Vector2(24.0, 8.0), Vector2(8.0, 24.0)]
	const PER_ZONE := 3
	const HOME_R := 2.5

	func chunk(n: int, cx: int, cy: int) -> WorldChunk:
		var c := WorldChunk.new()
		c.key = Vector2i(cx, cy)
		c.size = n
		var o := Vector2(32.0 * cx, 32.0 * cy)
		var tile := Vector2i(floori(cx / 2.0), floori(cy / 2.0))
		c.shells.append({"id": "s_d_%d_%d" % [cx, cy], "x": o.x + 16.0 + SHELL_OFFSET, "y": o.y + 16.0 + SHELL_OFFSET,
			"r": SHELL_R, "kind": "shell", "asset": "rock_a", "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
		for q in ZONE_CENTRES.size():
			var zc: Vector2 = o + ZONE_CENTRES[q]
			c.zones.append({"id": "z_d_%d_%d_%d" % [cx, cy, q], "x": zc.x, "y": zc.y, "radius": ZONE_R,
				"capacity": ZONE_CAPACITY, "growth_rate": ZONE_GROWTH, "tile": tile, "region": "sunlit"})
			for k in PER_ZONE:
				var a := TAU * k / PER_ZONE
				var home := Vector2.from_angle(a) * HOME_R
				var site := {"species": SITE_SPECIES, "home": home, "heading": a + PI}
				var reach: Dictionary = species.reach_disc_for(site, species.territory_from(site, {"center": Vector2.ZERO, "radius": ZONE_R}))
				var rx: float = zc.x + reach.center.x
				var ry: float = zc.y + reach.center.y
				c.sites.append({"id": "d_%d_%d_%d_%d" % [cx, cy, q, k], "species": SITE_SPECIES, "x": zc.x + home.x,
					"y": zc.y + home.y, "heading": a + PI, "territory": {"x": zc.x, "y": zc.y, "radius": ZONE_R},
					"reach": {"x": rx, "y": ry, "radius": float(reach.radius)}, "chunks": disc_chunks(rx, ry, float(reach.radius), 32.0),
					"sizes": [1] as Array[int], "tile": tile})
		return c
