extends TestCase
## The endless world's cost gates (S1 spine T0.7, core 10.2; G17), slow tier. A straight swim from
## home on the content tests/test_endless_gates.gd picks (the real tiles once T4.3 lands, the fixture
## world before), with RACER, the fastest legal body (4.41 tm/s; no body reaches the 6 tm/s the plan
## names), hidden from the creatures so a chase or a death does not change what is timed. Every timed
## step is followed on the same thread by the yardstick (tests/cost_yardstick.gd), as #28 does, and
## the flake policy of docs/DECISIONS.md ("M1 step 3 review fixes") applies: only a pass on a quiet
## machine or on CI rules a regression out.
##  - #28E: 3 runs of 1,800 ticks after 600 warm-up ticks; the fastest run's median tick is at most
##    1,500 us and the median run's median at most 8 yardsticks.
##  - P99.9: the 99.9th percentile tick is at most 16 yardsticks. The 3 runs time the same ticks
##    (their end hashes are equal), and each tick counts at its fastest of the 3, as #29's windows do,
##    so one burst of load from another process does not fail the gate; the median run's own
##    percentile is printed beside it.
##  - Sleeper: after a swim the left-behind sleepers are timed against a twin sim with them removed,
##    tick by tick in turn, 200 ticks each, 3 rounds: the median difference per sleeper is at most
##    2 us. Debug creatures never sleep (core C-6), so the sleepers are the world's own; on the fixture
##    world there may be too few to time, and the gate then waits for the real content.
##  - Rebase: 20 ticks with debug_rebase of 3 chunks against the plain tick just before each; the
##    median excess is at most 2 yardsticks. The rebase goes against the cell's side of the origin, so
##    the tick holds one rebase, not two.
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
const SLEEPER_SWIM_TICKS := 1200      ## about 88 tm east, leaving the home block's creatures behind
const SLEEPER_REST_TICKS := 60
const SLEEPER_TICKS := 200
const SLEEPER_ROUNDS := 3
const SLEEPER_MIN := 8                ## fewer cannot be told from noise
const SLEEPER_LIMIT_US := 2.0
const REBASES := 20
const REBASE_GAP_TICKS := 30
const REBASE_CHUNKS := 3
const REBASE_LIMIT_YARDSTICKS := 2.0

static var _runs: Array[Dictionary] = []


func _waits(gate: String) -> bool:
	var what := Gates.missing()
	if what.is_empty():
		return false
	print("test-endless-cost: %s waits on: %s" % [gate, "; ".join(what)])
	return true


## A racer at home, hidden, about to swim east.
static func _swimmer() -> Variant:
	var sim: Variant = Gates.make_sim(Gates.RACER, COST_SEED)
	sim.debug_set_hidden(true)
	sim.drain_events()
	return sim


## Steps `sim` once, timed, then runs the yardstick: {"us", "yard_us", "ratio", "events"}.
static func _timed_step(sim: Variant, intent: SimIntent, rebase_by := Vector2i.ZERO) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	if rebase_by != Vector2i.ZERO:
		sim.debug_rebase(rebase_by)
	sim.step(intent)
	var us := Time.get_ticks_usec() - t0
	var yard := Yardstick.time_once()
	return {"us": float(us), "yard_us": float(yard), "ratio": us / float(maxi(yard, 1)), "events": sim.drain_events()}


## The three timed runs of the straight swim (shared by #28E and P99.9): per run, every tick's us
## and yardsticks, and the end hash.
func _swim_runs() -> Array[Dictionary]:
	if not _runs.is_empty():
		return _runs
	for run in RUNS:
		var sim: Variant = _swimmer()
		var bot = SwimBot.new(Vector2.RIGHT)
		for i in WARM_TICKS:
			sim.step(bot.next_intent(sim))
			sim.drain_events()
		var us: Array[float] = []
		var ratios: Array[float] = []
		for i in TIMED_TICKS:
			var t := _timed_step(sim, bot.next_intent(sim))
			us.append(t.us)
			ratios.append(t.ratio)
		_runs.append({"us": us, "ratios": ratios, "hash": sim.state_hash(), "chunks": sim.world.loaded_keys().size(),
			"awake": sim.creatures.awake().size(), "sleeping": sim.world.sleeping_ids().size()})
	return _runs


## Each tick's yardsticks at its fastest of `runs` (which timed the same ticks).
static func _fastest_per_tick(runs: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for i in (runs[0].ratios as Array).size():
		var best := INF
		for r in runs:
			best = minf(best, r.ratios[i])
		out.append(best)
	return out


## The value at quantile `q` of `values`: the ceil(q n)-th smallest.
static func _percentile(values: Array[float], q: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(q * sorted.size()) - 1, 0, sorted.size() - 1)]


## The helpers the gates read their numbers with (fast; the gates themselves are slow).
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
	check_eq(_rebases([{"type": "debug"}, {"type": "rebased"}, {"type": "rebased"}]), 2, "rebased events counted")


func test_slow_a_size_1_swim_costs_at_most_8_yardsticks_a_tick() -> void:
	if _waits("#28E"):
		return
	var runs := _swim_runs()
	var medians: Array[float] = []
	var ratios: Array[float] = []
	for r in runs:
		medians.append(Yardstick.median(r.us))
		ratios.append(Yardstick.median(r.ratios))
		check_eq(r.hash, runs[0].hash, "every run timed the same ticks")
	var fastest: float = medians.min()
	var ratio := Yardstick.median(ratios)
	print("test-endless-cost: #28E on %s: median tick %.1f us in the fastest of %d runs (%s); %.2f yardsticks in the median run (%s); %d chunks, %d awake, %d asleep at the end" % [
		Gates.content_path(), fastest, RUNS, _joined(medians, "%.1f"), ratio, _joined(ratios, "%.2f"), runs[0].chunks, runs[0].awake,
		runs[0].sleeping])
	check(fastest <= LIMIT_US, "median tick %.1f us in the fastest run (limit %.0f)" % [fastest, LIMIT_US])
	check(ratio <= LIMIT_YARDSTICKS, "%.2f yardsticks in the median run (limit %.1f)" % [ratio, LIMIT_YARDSTICKS])


func test_slow_the_slowest_tick_in_a_thousand_stays_under_16_yardsticks() -> void:
	if _waits("P99.9"):
		return
	var runs := _swim_runs()
	var fastest := _fastest_per_tick(runs)
	var p := _percentile(fastest, P999)
	var by_median: Array[float] = []
	for r in runs:
		by_median.append(Yardstick.median(r.ratios))
	var median_run: Dictionary = runs[by_median.find(Yardstick.median(by_median))]
	print("test-endless-cost: P99.9 %.2f yardsticks over each tick's fastest run; the median run's own %.2f; worst tick %.2f" % [
		p, _percentile(median_run.ratios, P999), fastest.max()])
	check(p <= P999_YARDSTICKS, "P99.9 tick %.2f yardsticks (limit %.1f)" % [p, P999_YARDSTICKS])


func test_slow_a_sleeper_costs_at_most_2_us() -> void:
	if _waits("sleeper"):
		return
	var with_them: Variant = _sleeper_scene()
	var without: Variant = _sleeper_scene()
	var sleepers: Array = []
	for c in without.creatures.creatures:
		if c.asleep:
			sleepers.append(c)
	var n := sleepers.size()
	check_eq(with_them.world.sleeping_ids().size(), n, "the twin sims are the same")
	if n < SLEEPER_MIN:
		if Gates.content_path() != Gates.REAL_WORLD:
			print("test-endless-cost: sleeper waits on the real content: %d sleepers on %s (need %d)" % [n, Gates.content_path(), SLEEPER_MIN])
			return
		check(false, "only %d sleepers after the swim on the real content (need %d)" % [n, SLEEPER_MIN])
		return
	for c in sleepers:
		without.creatures.remove(c, "evicted", without.tick, false)
	without.drain_events()
	check_eq(without.world.sleeping_ids().size(), 0, "the twin has no sleepers")
	var still := SimIntent.new()
	var per: Array[float] = []
	for k in SLEEPER_ROUNDS:
		var a: Array[float] = []
		var b: Array[float] = []
		for i in SLEEPER_TICKS:
			a.append(_timed_step(with_them, still).us)
			b.append(_timed_step(without, still).us)
		per.append((Yardstick.median(a) - Yardstick.median(b)) / n)
	var cost := Yardstick.median(per)
	print("test-endless-cost: %d sleepers cost %.2f us each (rounds %s); %d still asleep at the end" % [
		n, cost, _joined(per, "%.2f"), with_them.world.sleeping_ids().size()])
	check(with_them.world.sleeping_ids().size() == n, "they slept through the timing")
	check(cost <= SLEEPER_LIMIT_US, "a sleeper costs %.2f us (limit %.1f)" % [cost, SLEEPER_LIMIT_US])


## A racer that swam east and stopped, leaving the creatures it passed asleep behind it.
static func _sleeper_scene() -> Variant:
	var sim: Variant = _swimmer()
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in SLEEPER_SWIM_TICKS:
		sim.step(bot.next_intent(sim))
		sim.drain_events()
	for i in SLEEPER_REST_TICKS:
		sim.step(SimIntent.new())
		sim.drain_events()
	return sim


func test_slow_a_rebase_tick_costs_at_most_2_yardsticks_more() -> void:
	if _waits("rebase"):
		return
	var sim: Variant = _swimmer()
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in WARM_TICKS:
		sim.step(bot.next_intent(sim))
		sim.drain_events()
	var excess: Array[float] = []
	var tries := 0
	while excess.size() < REBASES and tries < REBASES * 3:
		tries += 1
		for i in REBASE_GAP_TICKS:
			sim.step(bot.next_intent(sim))
			sim.drain_events()
		var before := _timed_step(sim, bot.next_intent(sim))
		if _rebases(before.events) != 0:
			continue
		var by := Vector2i(REBASE_CHUNKS if sim.motion.position.x >= 0.0 else -REBASE_CHUNKS, 0)
		var at := _timed_step(sim, bot.next_intent(sim), by)
		if _rebases(at.events) != 1:
			continue
		excess.append(float(at.ratio) - float(before.ratio))
	check_eq(excess.size(), REBASES, "%d rebase ticks timed in %d tries" % [excess.size(), tries])
	var m := Yardstick.median(excess) if not excess.is_empty() else INF
	print("test-endless-cost: a rebase tick costs %.2f yardsticks more than the tick before it (median of %d: %s)" % [
		m, excess.size(), _joined(excess, "%.2f")])
	check(m <= REBASE_LIMIT_YARDSTICKS, "a rebase tick costs %.2f yardsticks more (limit %.1f)" % [m, REBASE_LIMIT_YARDSTICKS])


static func _rebases(events: Array) -> int:
	var n := 0
	for e in events:
		n += 1 if e.type == "rebased" else 0
	return n


static func _joined(values: Array[float], format: String) -> String:
	return ", ".join(values.map(func(v: float) -> String: return format % v))
