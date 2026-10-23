extends TestCase
## The growth gates (S2G16) and the bots that drive them (s2-sim 3.12; S2 build plan BP-5, BP-13).
##
## Fast, the bots:
##  - every bot's growth keys (EvadeBot.GrowthKeys): its first intent carries its trigger and no
##    later one does, and in a press run it holds Grow on every tick its ring is full, never in an
##    auto run or a press run that does not press;
##  - ForageBot's unjam (S2's size-2 threat runner): across a row of rocks with cracks narrower than
##    the body, route_point alone wedges the forager in a crack, and with unjam it steps aside and
##    arrives;
##  - ClumsyBot's two modes, in the pool, where every M1 species is at q == 1: "clumsy" swims at a
##    q == 1 creature on screen until a hit, then passes that one over, and forages only after two
##    deaths; "die" swims at the nearest q == 1 creature within 40 tm below half its energy, holds
##    still with none, and forages above half.
##
## The gates (S2G16), on the real content with growth on and every bot in auto (its keys' default),
## each run from home as a new endless game starts, a dead cell continued after the death notice:
##  - soak, first growth: ForageBot grazer and omnivore (wary: avoid_threats) and HuntBot, 6 seeds
##    each; the median of the 18 first growths lies in 3 to 5 minutes and none takes over 6 (a run
##    with none by then fails). Each bot's median is printed.
##  - soak, the reversal (BP-13), on the same 18 runs: the first tick after grew at which a body of a
##    species that entered at the old size, now at q < 1, flees the cell inside the default-zoom
##    footprint (D-49: camera.distance, fairness.spawn_view_aspect, grown by its radius): a remnant,
##    or a creature in FLEE whose fear_of or attacker is the cell. Median at most 30 s; a run with
##    none in 120 s counts 120 s.
##  - soak, clumsy: ClumsyBot "clumsy" on the grazer and the omnivore, 6 seeds each; median first
##    growth at most 6 minutes (a run with none by CAP_S counts CAP_S).
##  - soak, die on purpose: ClumsyBot "die" on the same bodies and seeds; its median first growth is
##    at least the wary foragers' (a run with none by CAP_S counts CAP_S).
##  - slow, the parked grazer (BP-5): a ForageBot grazer at size 2 (debug_set_size) arrives at the
##    nearest sunlit zone inside a live rammer territory, read from WorldGen.chunk up to
##    PARK_SEARCH_RINGS chunks round the cell's (the loaded chunks alone hold none on some seeds),
##    and holds still there; from the tick it holds, a run of PARK_CALM_TICKS ticks with
##    Growth.blocker_of(sim, false) == "" starts within 28.5 s, on 6 seeds. Non-vacuous: a rammer
##    flees the cell in view during each run.
## Each waits on the S2 seams it reads (Gates.s2_missing).

const ForageBot := preload("res://game/dev/forage_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")
const KiterBot := preload("res://game/dev/kiter_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const ClumsyBot := preload("res://game/dev/clumsy_bot.gd")
const Gates := preload("res://tests/test_endless_gates.gd")

const BOT_SEED := 401
const KEYS_SEED := 6101
const BOT_NAMES: PackedStringArray = ["forage", "forage_wary", "hunt", "kiter", "evade", "swim", "camper_greedy",
	"homing", "clumsy", "die"]
const NEAR_M := 3.0               ## the cell is put this far from the creature it should charge
const STRAIGHT_DOT := 0.9         ## "straight at it": the move's cosine to the line to the creature
## ForageBot's unjam: a row of CRACK_ROCKS rocks of radius CRACK_R across the way at x = CRACK_X, their
## surfaces CRACK_GAP apart (less than the body is wide); the forager starts CRACK_FROM west of the
## row and parks as far east of it (test_swim_bot's crack, for SwimBot.Unjam).
const CRACK_X := 10.0
const CRACK_R := 1.0
const CRACK_GAP := 0.6
const CRACK_ROCKS := 3
const CRACK_FROM := 6.0
const CRACK_Y := 0.3                  ## off the middle rock's centre, so the way round picks a side
const CRACK_TICKS := 1200
const CRACK_ARRIVED_M := 1.0

## The gates (S2G16). Seeds written here before any run.
const GATE_NEEDS: PackedStringArray = ["set_size", "force_growth", "remnants", "size_two_content"]
const PARK_NEEDS: PackedStringArray = ["set_size", "size_two_content"]
const GROWTH_SEEDS: Array[int] = [601, 602, 603, 604, 605, 606]
const FIRST_BOTS: Array[Dictionary] = [{"bot": "forage", "body": "grazer"}, {"bot": "forage", "body": "omnivore"},
	{"bot": "hunt", "body": "hunter"}]
const FIRST_MIN_S := 180.0        ## the median first growth: 3 to 5 minutes
const FIRST_MAX_MEDIAN_S := 300.0
const FIRST_MAX_S := 360.0        ## and none over 6
const REVERSAL_MAX_MEDIAN_S := 30.0
const REVERSAL_NONE_S := 120.0    ## a run with no reversal in this long counts this long
const CLUMSY_BODIES: PackedStringArray = ["grazer", "omnivore"]
const CLUMSY_MAX_MEDIAN_S := 360.0
const CAP_S := 720.0              ## a clumsy or die run with no growth by now counts this long
const DEATH_NOTICE_TICKS := 90    ## a player reading the death notice before Continue
const PARK_SEEDS: Array[int] = [611, 612, 613, 614, 615, 616]
const PARK_CALM_TICKS := 90
const PARK_START_LIMIT_S := 28.5  ## the calm run starts by then, so it ends by 30 s
const PARK_SETTLE_TICKS := 120    ## after the size is set, before the zone is chosen (the stream loads)
const ARRIVE_GRACE_TICKS := 600   ## the parked bot's ticks to stop once it has arrived
## The parked grazer's zone is looked for in the chunks up to this many rings round the cell's: 8
## rings at size 2 reach 256 tm, about six 40 tm tiles, each way.
const PARK_SEARCH_RINGS := 8
const TPS := 60.0

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func test_every_bot_sends_its_trigger_on_its_first_intent_and_never_again() -> void:
	# The first intent comes while the cell is dead, so a bot inside another (ForageBot in a greedy
	# camper or a ClumsyBot) first runs on a later tick: its own keys must not send anything then.
	for trigger in ["auto", "press", ""]:
		for name in BOT_NAMES:
			var sim := _pool_sim("omnivore")
			var bot = _bot(name)
			bot.keys.trigger = trigger
			sim.debug_hurt_player(1.0e9)
			var first := _intent(bot, sim)
			sim.respawn_player()
			if name != "die":
				sim.debug_set_energy(sim.state.energy_capacity * 0.2)   # hungry: the greedy camper takes its food
			var later: Array[SimIntent] = [_intent(bot, sim), _intent(bot, sim)]
			var what := "%s, trigger '%s'" % [name, trigger]
			check_eq(first.trigger, trigger, "%s: the first intent carries it" % what)
			for i in later.size():
				check_eq(later[i].trigger, "", "%s: intent %d carries none" % [what, i + 2])
				check(not later[i].grow, "%s: no Grow in the pool" % what)
			var inner = _inner(bot, name)
			if inner != null:
				check(inner.keys._sent, "%s: its inner bot ran after the first intent" % what)


func test_a_press_run_holds_grow_on_every_full_tick_and_no_other_run_does() -> void:
	var waits := Gates.missing(Gates.SIM)
	if not waits.is_empty():
		check(false, "the endless sim is missing: %s" % "; ".join(waits))
		return
	# [trigger, press, ring full, Grow held]
	var cases := [["press", true, true, true], ["press", true, false, false], ["press", false, true, false],
		["auto", true, true, false], ["", true, true, false]]
	for case in cases:
		var sim: Variant = Gates.make_sim("hunter", KEYS_SEED, true)
		check(sim.growth != null, "growth on")
		var bot = SwimBot.new(Vector2.RIGHT, 0.0)
		bot.keys.trigger = case[0]
		bot.keys.press = case[1]
		var what := "trigger '%s', press %s, full %s" % case.slice(0, 3)
		for t in 3:
			sim.growth.meter = sim.growth.ring(sim.size()) if case[2] else 0.0
			check_eq(sim.growth.is_full(sim.size()), case[2], "%s: the ring as set" % what)
			var intent: SimIntent = bot.next_intent(sim)
			check_eq(intent.grow, case[3], "%s: Grow on tick %d" % [what, t])
			sim.step(intent)
			check_eq(sim.intent_grow, case[3], "%s: the sim took the press on tick %d" % [what, t])
		check_eq(bot.keys.presses, 3 if case[3] else 0, "%s: presses counted" % what)
		if not str(case[0]).is_empty():
			check_eq(sim.growth.trigger, case[0], "%s: the meter took the trigger" % what)
	var off: Variant = Gates.make_sim("hunter", KEYS_SEED, false)
	var press = SwimBot.new(Vector2.RIGHT, 0.0)
	press.keys.trigger = "press"
	check(not press.next_intent(off).grow, "growth off: nothing to press")


func test_a_forager_with_unjam_steps_out_of_a_crack_that_wedges_it_without() -> void:
	var goal := Vector2(CRACK_X + CRACK_FROM, CRACK_Y)
	var arrived := {}
	var wedges := 0
	for unjam in [false, true]:
		var r := Lineage.found(BOT_SEED, "test+dev", catalog, "grazer")
		r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
		var sim := PoolSim.create(r.save, catalog, layout, null)
		sim.arena = PoolArena.create(layout.pool_radius, layout.soft_start, layout.hard_radius)
		var step := 2.0 * CRACK_R + CRACK_GAP
		for k in CRACK_ROCKS:
			sim.arena.add_rock("crack_%d" % k, Vector2(CRACK_X, (k - (CRACK_ROCKS - 1) / 2.0) * step), CRACK_R)
		check(2.0 * sim.phenotype.radius > CRACK_GAP, "the cracks (%.2f) are narrower than the body (%.2f)" % [
			CRACK_GAP, 2.0 * sim.phenotype.radius])
		check(sim.debug_teleport(Vector2(CRACK_X - CRACK_FROM, CRACK_Y), 0.0), "placed west of the row")
		sim.drain_events()
		var bot = ForageBot.new()
		bot.park_at = goal
		bot.unjam = unjam
		arrived[unjam] = -1
		for i in CRACK_TICKS:
			if sim.motion.position.distance_to(goal) <= CRACK_ARRIVED_M:
				arrived[unjam] = i
				break
			if i % 300 == 0:
				sim.debug_set_energy(sim.state.energy_capacity)
			sim.step(bot.next_intent(sim))
			sim.drain_events()
		if unjam:
			wedges = bot._unjam.wedges if bot._unjam != null else 0
	check_eq(int(arrived[false]), -1, "without unjam the forager stays wedged in a crack (the row is a real trap)")
	check(int(arrived[true]) >= 0, "with unjam it gets round the row")
	check(wedges >= 1, "it stepped aside (%d times)" % wedges)


func test_a_clumsy_bot_charges_a_q1_creature_on_screen_until_a_hit_and_forages_after_two_deaths() -> void:
	var sim := _pool_sim("grazer")
	var c := _put_near_creature(sim)
	if c == null:
		return
	var bot = ClumsyBot.new(ClumsyBot.CLUMSY)
	var intent: SimIntent = bot.next_intent(sim)
	check_eq(bot.target_id(), c.id, "it charges the creature on screen beside it")
	_check_straight_at(sim, intent, c, "clumsy")
	check_eq(bot.charges, 1, "one charge")
	bot.next_intent(sim)
	check_eq(bot.charges, 1, "the charge holds from tick to tick")
	sim.stats.hits_taken += 1   # the cell, as the bot sees it: a hit landed
	bot.next_intent(sim)
	check(bot.target_id() != c.id, "after the hit it passes that creature over (now '%s')" % bot.target_id())
	for death in 2:
		check(sim.debug_hurt_player(1.0e9) and sim.dead, "death %d" % (death + 1))
		for t in 2:
			check(bot.next_intent(sim).move == Vector2.ZERO, "a dead cell holds still")
		sim.respawn_player()
		bot.next_intent(sim)
	check_eq(bot.deaths, 2, "two deaths seen")
	var fresh := _pool_sim("grazer")
	var c2 := _put_near_creature(fresh)
	var learned = ClumsyBot.new(ClumsyBot.CLUMSY)
	learned.deaths = 2
	var want: SimIntent = ForageBot.new().next_intent(fresh)
	var got: SimIntent = learned.next_intent(fresh)
	check(c2 != null and learned.target_id().is_empty() and learned.charges == 0, "after two deaths it charges nothing")
	check_eq(got.move, want.move, "and forages as ForageBot does")


func test_a_clumsy_bot_passes_over_a_creature_not_at_q1() -> void:
	var sim := _pool_sim("grazer")
	var c := _put_near_creature(sim)
	if c == null:
		return
	for id in sim.species.species_ids():
		sim.species.species[id]["entry_size"] = 2   # q = 1.6 at size 1: none at q == 1
	check(not ClumsyBot.at_q1(sim, c), "%s is not at q == 1 now" % c.species_id)
	var bot = ClumsyBot.new(ClumsyBot.CLUMSY)
	var got: SimIntent = bot.next_intent(sim)
	check(bot.target_id().is_empty() and bot.charges == 0, "nothing to charge")
	check_eq(got.move, ForageBot.new().next_intent(sim).move, "so it forages")


func test_a_clumsy_bot_charges_nothing_off_screen() -> void:
	var sim := _pool_sim("grazer")
	var c := _put_near_creature(sim)
	if c == null:
		return
	# The creature moved straight back until it leaves the default zoom's view (only the bot reads
	# it; the sim does not step), every other one with it.
	var cam := sim.layout.camera
	var away := (c.motion.position - sim.motion.position).normalized()
	var d := NEAR_M
	while d < 200.0 and ViewFootprint.contains(sim.motion.position, sim.motion.position + away * d, cam, float(cam.distance), ClumsyBot.VIEW_ASPECT):
		d += 0.5
	for k: CreatureField.Creature in sim.creatures.creatures:
		k.motion.position = sim.motion.position + away * (d + 1.0)
	check(d < 200.0, "the view ends %.1f tm out" % d)
	var bot = ClumsyBot.new(ClumsyBot.CLUMSY)
	var got: SimIntent = bot.next_intent(sim)
	check(bot.target_id().is_empty() and bot.charges == 0, "off screen: nothing charged")
	check_eq(got.move, ForageBot.new().next_intent(sim).move, "it forages")


func test_a_die_bot_seeks_a_q1_creature_below_half_its_energy_and_holds_still_with_none() -> void:
	var sim := _pool_sim("grazer")
	var c := _put_near_creature(sim)
	if c == null:
		return
	var bot = ClumsyBot.new(ClumsyBot.DIE)
	var fed: SimIntent = bot.next_intent(sim)
	check(bot.target_id().is_empty(), "fed: no creature sought")
	check_eq(fed.move, ForageBot.new().next_intent(sim).move, "fed: it forages")
	sim.debug_set_energy(sim.state.energy_capacity * (ClumsyBot.DIE_BELOW - 0.01))
	var hungry: SimIntent = bot.next_intent(sim)
	check_eq(bot.target_id(), _nearest_q1(sim).id, "below half: the nearest creature at q == 1")
	if bot.target_id() == c.id:
		_check_straight_at(sim, hungry, c, "die")
	for id in sim.species.species_ids():
		sim.species.species[id]["entry_size"] = 2
	var alone: SimIntent = bot.next_intent(sim)
	check(bot.target_id().is_empty() and alone.move == Vector2.ZERO, "with none at q == 1 it holds still to starve")


func test_a_die_bot_looks_no_farther_than_40_tm() -> void:
	var sim := _pool_sim("grazer")
	var bot = ClumsyBot.new(ClumsyBot.DIE)
	sim.debug_set_energy(sim.state.energy_capacity * 0.1)
	var near := _nearest_q1(sim)
	check(near != null, "a creature")
	if near == null:
		return
	var d := sim.motion.position.distance_to(near.motion.position)
	bot.next_intent(sim)
	check_eq(bot.target_id(), near.id if d <= ClumsyBot.DIE_REACH_TM else "", "the nearest at %.1f tm" % d)
	# Every creature moved out past the reach (only the bot reads them; the sim does not step).
	for k: CreatureField.Creature in sim.creatures.creatures:
		var off := k.motion.position - sim.motion.position
		k.motion.position = sim.motion.position + off.normalized() * (ClumsyBot.DIE_REACH_TM + 1.0)
	bot.next_intent(sim)
	check(bot.target_id().is_empty(), "none within 40 tm: none sought")


func test_soak_the_first_growth_comes_in_3_to_5_minutes_and_old_threats_turn_within_30_s() -> void:
	if _gate_waits("first growth and the reversal", GATE_NEEDS):
		return
	var firsts: Array[float] = []
	var reversals: Array[float] = []
	for b in FIRST_BOTS:
		var mine: Array[float] = []
		for seed_value in GROWTH_SEEDS:
			var run := _growth_run(str(b.bot), str(b.body), seed_value, FIRST_MAX_S, true)
			print("test-growth-gates: %s %s seed %d: first growth %s, reversal %s, %d deaths, %d meals" % [
				b.bot, b.body, seed_value, _s(run.grew_s), _s(run.reversal_s), run.deaths, run.meals])
			check(run.grew_s <= FIRST_MAX_S, "%s %s seed %d grew within 6 minutes (%s)" % [b.bot, b.body, seed_value, _s(run.grew_s)])
			mine.append(run.grew_s)
			firsts.append(run.grew_s)
			if run.grew_s <= FIRST_MAX_S:
				reversals.append(minf(run.reversal_s, REVERSAL_NONE_S))
		print("test-growth-gates: %s %s: median first growth %s" % [b.bot, b.body, _s(median(mine))])
	var m := median(firsts)
	print("test-growth-gates: first growth median %s over %d runs (max %s); reversal median %s over %d" % [
		_s(m), firsts.size(), _s(firsts.max()), _s(median(reversals)), reversals.size()])
	check(m >= FIRST_MIN_S and m <= FIRST_MAX_MEDIAN_S, "the median first growth lies in 3 to 5 minutes (%s)" % _s(m))
	check(reversals.size() == firsts.size(), "every run grew, so every run has a reversal reading")
	check(median(reversals) <= REVERSAL_MAX_MEDIAN_S, "the median reversal is within 30 s (%s)" % _s(median(reversals)))


func test_soak_a_clumsy_player_still_grows_within_6_minutes() -> void:
	if _gate_waits("the clumsy player", GATE_NEEDS):
		return
	var times: Array[float] = []
	for body in CLUMSY_BODIES:
		for seed_value in GROWTH_SEEDS:
			var run := _growth_run("clumsy", body, seed_value, CAP_S, false)
			print("test-growth-gates: clumsy %s seed %d: first growth %s, %d deaths, %d charges" % [
				body, seed_value, _s(run.grew_s), run.deaths, run.charges])
			times.append(minf(run.grew_s, CAP_S))
	print("test-growth-gates: clumsy median first growth %s over %d runs" % [_s(median(times)), times.size()])
	check(median(times) <= CLUMSY_MAX_MEDIAN_S, "the clumsy median is at most 6 minutes (%s)" % _s(median(times)))


func test_soak_dying_on_purpose_never_grows_a_cell_faster_than_foraging() -> void:
	if _gate_waits("die on purpose", GATE_NEEDS):
		return
	var dying: Array[float] = []
	var foraging: Array[float] = []
	for body in CLUMSY_BODIES:
		for seed_value in GROWTH_SEEDS:
			var die := _growth_run("die", body, seed_value, CAP_S, false)
			var forage := _growth_run("forage", body, seed_value, CAP_S, false)
			print("test-growth-gates: %s seed %d: dying grew at %s (%d deaths), foraging at %s" % [
				body, seed_value, _s(die.grew_s), die.deaths, _s(forage.grew_s)])
			dying.append(minf(die.grew_s, CAP_S))
			foraging.append(minf(forage.grew_s, CAP_S))
	print("test-growth-gates: median first growth dying %s, foraging %s" % [_s(median(dying)), _s(median(foraging))])
	check(median(dying) >= median(foraging), "dying on purpose is no faster (%s against %s)" % [_s(median(dying)), _s(median(foraging))])


func test_slow_a_parked_grazer_at_size_two_finds_its_calm_window_within_30_s() -> void:
	if _gate_waits("the parked grazer", PARK_NEEDS):
		return
	for seed_value in PARK_SEEDS:
		var run := _park_run(seed_value)
		print("test-growth-gates: parked grazer seed %d: zone %s, arrived %s; calm run from %s after parking; %d ticks with a rammer fleeing in view; blockers %s" % [
			seed_value, run.zone, run.arrival, _s(run.calm_s), run.fleeing_ticks, run.blockers])
		check(not str(run.zone).is_empty(), "seed %d: a sunlit zone in a live rammer territory" % seed_value)
		check(run.calm_s <= PARK_START_LIMIT_S, "seed %d: %d calm ticks in a row start within 28.5 s (%s)" % [
			seed_value, PARK_CALM_TICKS, _s(run.calm_s)])
		check(int(run.fleeing_ticks) > 0, "seed %d: a rammer fled the cell in view" % seed_value)


## The median of `xs` (the mean of the middle two for an even count); INF for none.
static func median(xs: Array[float]) -> float:
	if xs.is_empty():
		return INF
	var s := xs.duplicate()
	s.sort()
	var n := s.size()
	return s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) / 2.0


static func _s(seconds: float) -> String:
	return "none" if not is_finite(seconds) else "%.1f s" % seconds


func _gate_waits(what: String, needs: PackedStringArray) -> bool:
	var waits := Gates.s2_missing(needs)
	if waits.is_empty():
		return false
	print("test-growth-gates: %s waits on: %s" % [what, "; ".join(waits)])
	return true


## One run from home with growth on (auto): `bot_name` ("forage" wary, "hunt", "clumsy" or "die")
## on `body` until the first grew or `cap_s`; with `reversal`, on after grew until the reversal or
## REVERSAL_NONE_S. Returns {"grew_s" (INF for none), "reversal_s" (INF for none), "deaths",
## "meals", "charges"}.
func _growth_run(bot_name: String, body: String, seed_value: int, cap_s: float, reversal: bool) -> Dictionary:
	var sim: Variant = Gates.make_sim(body, seed_value, true)
	var bot: Variant
	match bot_name:
		"forage":
			bot = ForageBot.new()
			bot.avoid_threats = true
		"hunt":
			bot = HuntBot.new()
		_:
			bot = ClumsyBot.new(bot_name)
	var out := {"grew_s": INF, "reversal_s": INF, "deaths": 0, "meals": 0, "charges": 0}
	var events: Array[Dictionary] = []
	var dead := {}
	var grew_at := -1
	var old_size := 0
	var cap := int(cap_s * TPS)
	for i in cap + int(REVERSAL_NONE_S * TPS):
		if grew_at < 0 and i >= cap:
			break
		if grew_at >= 0 and (not reversal or sim.tick - grew_at > int(REVERSAL_NONE_S * TPS)):
			break
		events.append_array(Gates.continue_after_death(sim, dead))
		var intent: SimIntent = bot.next_intent(sim, events) if bot_name == "hunt" else bot.next_intent(sim)
		events = Gates.tick(sim, intent)
		for e in events:
			match str(e.type):
				"died":
					out.deaths += 1
				"ate":
					out.meals += 1
				"grew":
					if grew_at < 0:
						grew_at = sim.tick - 1   # the tick that grew
						old_size = int(e.get("from", int(e.get("to", 2)) - 1))
						out.grew_s = i / TPS
		if grew_at >= 0 and sim.tick - 1 > grew_at and reversal and not is_finite(out.reversal_s) and reversed_in_view(sim, old_size):
			out.reversal_s = (sim.tick - 1 - grew_at) / TPS
	if bot_name in ["clumsy", "die"]:
		out.charges = bot.charges
	return out


## The reversal on this tick (BP-13): a body of a species that entered at `old_size`, at q < 1 now,
## flees the cell inside the default-zoom footprint (D-49): a remnant, or a creature in FLEE whose
## fear_of or attacker is the cell.
static func reversed_in_view(sim: Variant, old_size: int) -> bool:
	var n: int = sim.size()
	var sp: SpeciesCatalog = sim.species
	var cam: Dictionary = sim.layout.camera
	var aspect := float(sp.fairness.spawn_view_aspect)
	var at: Vector2 = sim.motion.position
	var p := CreatureField.PLAYER_ID
	for r in sim.remnants.items:
		if sp.has_species(r.species_id) and sp.entry_size(r.species_id) == old_size \
				and ViewFootprint.contains(at, r.motion.position, cam, float(cam.distance), aspect, r.phenotype.radius):
			return true
	for c: CreatureField.Creature in sim.creatures.awake():
		if c.brain == null or c.brain.state != CreatureBrain.FLEE or not sp.has_species(c.species_id):
			continue
		if sp.entry_size(c.species_id) != old_size or sp.q_of(c.species_id, n) >= 1.0:
			continue
		if (c.brain.fear_of == p or c.brain.attacker == p) \
				and ViewFootprint.contains(at, c.motion.position, cam, float(cam.distance), aspect, c.phenotype.radius):
			return true
	return false


## The parked grazer (BP-5): a grazer at size 2 arrives (Gates.arrive) at the nearest sunlit zone
## whose centre lies in a live rammer territory, then a ForageBot parks on its centre. From the
## first tick it holds still, each tick reads Growth.blocker_of(sim, false). Returns {"zone",
## "arrival", "calm_s" (when the first PARK_CALM_TICKS calm run started, INF for none in 30 s),
## "fleeing_ticks", "blockers" (ticks per blocker)}.
func _park_run(seed_value: int) -> Dictionary:
	var sim: Variant = Gates.make_sim("grazer", seed_value, true)
	var out := {"zone": "", "arrival": "", "calm_s": INF, "fleeing_ticks": 0, "blockers": {}}
	check(sim.debug_set_size(2), "seed %d: size 2" % seed_value)
	sim.debug_set_hidden(true)
	for i in PARK_SETTLE_TICKS:
		Gates.keep_fed(sim)
		Gates.tick(sim, SimIntent.new())
	sim.debug_set_hidden(false)
	var zone := _rammer_zone(sim)
	if zone.is_empty():
		return out
	out.zone = str(zone.id)
	var to_am := WorldConfig.tm_to_am(sim.size())
	var arrival := Gates.arrive(sim, PackedFloat64Array([float(zone.x) * to_am, float(zone.y) * to_am]), seed_value)
	out.arrival = "%.0f tm away, %.1f tm off after %d ticks" % [zone.distance, arrival.left_tm, arrival.ticks]
	var bot = ForageBot.new()
	var parked_at := -1
	var run_from := -1
	var limit := int((PARK_START_LIMIT_S + PARK_CALM_TICKS / TPS) * TPS)
	for i in limit + ARRIVE_GRACE_TICKS:
		var z: Dictionary = sim.region.zone(out.zone)
		if z.is_empty():
			break
		bot.park_at = z.center
		var intent: SimIntent = bot.next_intent(sim)
		if parked_at < 0 and intent.move == Vector2.ZERO:
			parked_at = sim.tick
		Gates.tick(sim, intent)
		if parked_at < 0:
			continue
		if sim.tick - parked_at > limit:
			break
		var blocker: String = sim.growth.blocker_of(sim, false)
		out.blockers[blocker] = int(out.blockers.get(blocker, 0)) + 1
		if _rammer_flees_in_view(sim):
			out.fleeing_ticks += 1
		if blocker != "":
			run_from = -1
			continue
		if run_from < 0:
			run_from = sim.tick
		if sim.tick - run_from + 1 >= PARK_CALM_TICKS and not is_finite(out.calm_s):
			out.calm_s = (run_from - parked_at) / TPS
	return out


## The nearest zone to the cell in the "sunlit" region (its chunk's zone record says so) whose centre
## lies in the territory of a site of a rammer live at the cell's size, as {"id", "x", "y" (absolute
## tm at that size), "distance" (tm)}; {} when none lies within PARK_SEARCH_RINGS chunks of the
## cell's. The chunks are read from WorldGen.chunk (pure, as the stream would load them), ring by
## ring round the cell's chunk: at size 2 the stream's 16 loaded chunks hold no such zone on some
## seeds (612, 613). Once a ring finds one, the next ring is read too, so that a nearer zone there,
## or a site there whose territory reaches back, is not missed.
static func _rammer_zone(sim: Variant) -> Dictionary:
	var world: Variant = sim.world
	var n: int = world.size
	var to_am := WorldConfig.tm_to_am(n)
	var here: PackedFloat64Array = world.abs_of_local(sim.motion.position)
	var hx := here[0] / to_am
	var hy := here[1] / to_am
	var center: Vector2i = world.chunk_of_local(sim.motion.position)
	var zones: Array[Dictionary] = []
	var discs: Array[Dictionary] = []
	var best := {}
	var last := PARK_SEARCH_RINGS
	for r in PARK_SEARCH_RINGS + 1:
		if r > last:
			break
		for key in _chunk_ring(center, r):
			var ch: WorldChunk = world.gen.chunk(n, key.x, key.y)
			for z in ch.zones:
				if str(z.get("region", "")) == "sunlit":
					zones.append(z)
			for s in ch.sites:
				var disc: Dictionary = s.get("territory", {})
				if str(s.species) == "rammer" and not disc.is_empty() and HuntBot._live(s, world):
					discs.append(disc)
		var best_d := INF
		for z in zones:
			var d := Vector2(float(z.x) - hx, float(z.y) - hy).length()
			if d < best_d and _in_a_disc(float(z.x), float(z.y), discs):
				best_d = d
				best = {"id": str(z.id), "x": float(z.x), "y": float(z.y), "distance": d}
		if not best.is_empty() and last == PARK_SEARCH_RINGS:
			last = mini(r + 1, PARK_SEARCH_RINGS)
	return best


## The chunk keys at Chebyshev distance `r` from `center`, in (y, x) order.
static func _chunk_ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				out.append(center + Vector2i(dx, dy))
	return out


## Whether the absolute tm point (x, y) lies inside one of `discs` ({x, y, radius}, absolute tm), as
## Gates.covered measures.
static func _in_a_disc(x: float, y: float, discs: Array[Dictionary]) -> bool:
	for disc in discs:
		if Vector2(x - float(disc.x), y - float(disc.y)).length() < float(disc.radius):
			return true
	return false


## A rammer in FLEE from the cell inside the default-zoom footprint (D-49).
static func _rammer_flees_in_view(sim: Variant) -> bool:
	var cam: Dictionary = sim.layout.camera
	var aspect := float(sim.species.fairness.spawn_view_aspect)
	for c: CreatureField.Creature in sim.creatures.awake():
		if c.species_id != "rammer" or c.brain == null or c.brain.state != CreatureBrain.FLEE:
			continue
		if c.brain.fear_of != CreatureField.PLAYER_ID and c.brain.attacker != CreatureField.PLAYER_ID:
			continue
		if ViewFootprint.contains(sim.motion.position, c.motion.position, cam, float(cam.distance), aspect, c.phenotype.radius):
			return true
	return false


## A pool sim (M1, every creature at q == 1) for `body`, its start shelter over.
func _pool_sim(body: String) -> PoolSim:
	var r := Lineage.found(BOT_SEED, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	sim.grace_until = sim.tick
	sim.drain_events()
	return sim


## Puts the cell NEAR_M from the first creature it can stand that close to, facing it; returns that
## creature (null, with a failure, when there is none).
func _put_near_creature(sim: PoolSim) -> CreatureField.Creature:
	for c: CreatureField.Creature in sim.creatures.creatures:
		for k in 16:
			var p: Vector2 = c.motion.position + Vector2.from_angle(TAU * k / 16.0) * NEAR_M
			if sim.debug_teleport(p, (c.motion.position - p).angle()) and _nearest_q1(sim) == c:
				sim.drain_events()
				return c
	check(false, "no creature the cell can be put %.1f tm from, nearer than every other" % NEAR_M)
	return null


func _nearest_q1(sim: PoolSim) -> CreatureField.Creature:
	var best: CreatureField.Creature = null
	var best_d := INF
	for c: CreatureField.Creature in sim.creatures.creatures:
		var d := sim.motion.position.distance_to(c.motion.position)
		if ClumsyBot.at_q1(sim, c) and (d < best_d or (d == best_d and c.id < best.id)):
			best_d = d
			best = c
	return best


func _check_straight_at(sim: PoolSim, intent: SimIntent, c: CreatureField.Creature, what: String) -> void:
	var line := (c.motion.position - sim.motion.position).normalized()
	check(is_equal_approx(intent.move.length(), 1.0), "%s: full throttle (%.3f)" % [what, intent.move.length()])
	check(intent.move.normalized().dot(line) >= STRAIGHT_DOT, "%s: straight at it (cos %.3f)" % [what, intent.move.normalized().dot(line)])


static func _bot(name: String) -> Variant:
	match name:
		"forage":
			return ForageBot.new()
		"forage_wary":
			var b = ForageBot.new()
			b.avoid_threats = true
			return b
		"hunt":
			return HuntBot.new()
		"kiter":
			return KiterBot.new(BOT_SEED)
		"evade":
			var b = EvadeBot.new()
			b.base = func(_sim: PoolSim) -> SimIntent: return SimIntent.new(Vector2.UP * 0.3)
			return b
		"swim":
			return SwimBot.new(Vector2.RIGHT)
		"camper_greedy":
			return SwimBot.camper("z_center", true)
		"homing":
			return SwimBot.toward(PackedFloat64Array([5.0, 5.0]))
		"clumsy":
			return ClumsyBot.new(ClumsyBot.CLUMSY)
		"die":
			return ClumsyBot.new(ClumsyBot.DIE)
	return null


## The bot a bot runs inside it (whose keys it blanks), or null.
static func _inner(bot: Variant, name: String) -> Variant:
	match name:
		"forage_wary", "hunt":
			return bot.evade
		"camper_greedy":
			return bot._forager
		"clumsy", "die":
			return bot.forage
	return null


static func _intent(bot: Variant, sim: PoolSim) -> SimIntent:
	if bot is EvadeBot or bot is HuntBot:
		return bot.next_intent(sim, [])
	return bot.next_intent(sim)
