extends TestCase
## The growth gates (S2G16) and the bots that drive them (s2-sim 3.12; S2 build plan BP-5, BP-13).
##
## Fast, the bots:
##  - every bot's growth keys (EvadeBot.GrowthKeys): its first intent carries its trigger and no
##    later one does, and in a press run it holds Grow on every tick its ring is full, never in an
##    auto run or a press run that does not press;
##  - ClumsyBot's two modes, in the pool, where every M1 species is at q == 1: "clumsy" swims at a
##    q == 1 creature on screen until a hit, then passes that one over, and forages only after two
##    deaths; "die" swims at the nearest q == 1 creature within 40 tm below half its energy, holds
##    still with none, and forages above half.

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
