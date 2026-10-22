extends TestCase
## The slow gates of M1 step 3 (plan section 18 #29-31), in the real pool with the real species.
## They are named test_slow_* so a quick local loop can skip them (run_tests.gd -- --skip-slow);
## tools/check.sh and CI run them every time. Each prints its numbers for docs/milestones/M1.md.
## Their seeds were written here before any run. If a gate fails after a change, the data is tuned
## (plan section 10: five knobs, in order, within their bounds), never the gate.
##
## #29 stress: 24 creatures round a ring for 30 s; the average tick stays under 2.5 ms. The same 30 s
##     are timed three times (the bot's run, then two replays of its intents) and each 5 s window
##     counts at its fastest, so a burst of load from other processes on a shared machine does not
##     fail the gate. The replays end in the bot's run's state hash: all three timed the same ticks.
## #30 hunter viability (plan D2): HuntBot keeps a hunter lineage alive on what it kills, now that
##     the interim carrion supply is off, in at least 5 of 6 seeds.
## #31 predation balance: with the cell hidden at the spawn, five minutes of creatures preying on
##     each other empty no niche for long, kill few, and leave nobody stalled.
## #32 pressure (step 3 review): a forager started at the spawn meets threats, and one that dodges
##     is not worn down by them. ForageBot swims for the nearest food its body eats and never minds a
##     creature; EvadeBot dodges each tell aimed at the cell 0.4 s after it starts (F2), as a player
##     reading the tells would. Notices of the cell and tells at it are its meetings with threats.

const HuntBot := preload("res://game/dev/hunt_bot.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")

## #29: 24 creatures, ambush hunters and rammers in turn, 28 m out from the pool's center, facing in.
## The ring starts 7.5 degrees off north-east-south-west so every site sits between the rim rocks
## (at 30 m, every 60 degrees from east), clear of them.
const STRESS_CREATURES := 24
const STRESS_RING_M := 28.0
const STRESS_RING_START := PI / 24.0
const STRESS_SPECIES: PackedStringArray = ["ambush_hunter", "rammer"]
const STRESS_TICKS := 1800
const STRESS_LIMIT_US := 2500.0
const STRESS_RUNS := 3              ## the bot's run and two replays of its intents
const STRESS_WINDOW_TICKS := 300    ## each 5 s window of the 30 counts at its fastest of the runs
## #30 (plan section 10): seeds fixed before any run; a seed passes with no starvation death, at most
## one death to a threat and at least three pieces of carrion eaten in 240 s.
const HUNTER_SEEDS: Array[int] = [201, 202, 203, 204, 205, 206]
const HUNTER_TICKS := 240 * 60
const HUNTER_PASSES_NEEDED := 5
const HUNTER_MAX_THREAT_DEATHS := 1
const HUNTER_MIN_MEAT := 3
const DEATH_NOTICE_TICKS := 90          ## a player reading the death notice before Continue
## #31: seeds fixed before any run, 300 s each.
const BALANCE_SEEDS: Array[int] = [1, 2, 3, 4]
const BALANCE_TICKS := 300 * 60
const EMPTY_NICHE_LIMIT_TICKS := 90 * 60   ## no niche at 0 for longer than this
const MAX_PREDATION_DEATHS := 6            ## creatures killed by creatures, per run
## Every creature on the move (wander, forage seek, chase pursue or flee) for at least
## ON_THE_MOVE_MIN_TICKS of a MOVE_WINDOW_TICKS window it lived through gets MOVE_MIN_M from where it
## began that window.
const MOVE_WINDOW_TICKS := 3600
const MOVE_MIN_M := 1.0
const ON_THE_MOVE_MIN_TICKS := 300
## #32 (docs/DECISIONS.md, "M1 step 3 review fixes: pressure"): seeds fixed before any run, 300 s
## each for each plankton body. A dead cell continues at its checkpoint after DEATH_NOTICE_TICKS.
const PRESSURE_SEEDS: Array[int] = [501, 502, 503]
const PRESSURE_BODIES: PackedStringArray = ["grazer", "omnivore"]
const PRESSURE_TICKS := 300 * 60
const PRESSURE_MIN_MEETINGS_PER_MIN := 1.0   ## for each body, over its seeds, and some in every seed
const PRESSURE_MAX_DEATHS_PER_5_MIN := 0.5   ## over every run: a careful player is not worn down

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog
var test_species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()
	test_species = SpeciesCatalog.load_from("res://tests/fixtures/creatures_test.json")


## A new lineage in the real pool at the spawn. `p_species` is the real data unless given.
func _sim(body: String, seed_value: int, p_species: SpeciesCatalog = null) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, p_species if p_species != null else species)
	sim.drain_events()
	return sim


func test_slow_twenty_four_creatures_cost_well_under_three_milliseconds_a_tick() -> void:
	# Plan #29: the real species placed as dev creatures (outside the niche caps, so none need
	# raising), with the cell foraging at the spawn while minding them. Only sim.step is timed.
	var windows := ceili(float(STRESS_TICKS) / STRESS_WINDOW_TICKS)
	var best := PackedInt64Array()
	best.resize(windows)
	best.fill(9223372036854775807)
	var intents: Array[Vector2] = []
	var first_average := 0.0
	var deaths := 0
	var left := 0
	var end_hash := 0
	for run in STRESS_RUNS:
		var sim := _stress_sim()
		check_eq(sim.creatures.creatures.size(), STRESS_CREATURES, "run %d: %d creatures" % [run, STRESS_CREATURES])
		var bot = null
		if run == 0:
			bot = ForageBot.new()
			bot.avoid_threats = true
		var spent := PackedInt64Array()
		spent.resize(windows)
		for i in STRESS_TICKS:
			var intent: SimIntent
			if run == 0:
				intent = bot.next_intent(sim)
				intents.append(intent.move)
			else:
				intent = SimIntent.new(intents[i])
			var t0 := Time.get_ticks_usec()
			sim.step(intent)
			spent[floori(float(i) / STRESS_WINDOW_TICKS)] += Time.get_ticks_usec() - t0
			for e in sim.drain_events():
				if run == 0 and e.type == "creature_died":
					deaths += 1
		var total := 0
		for w in windows:
			best[w] = mini(best[w], spent[w])
			total += spent[w]
		if run == 0:
			first_average = total / float(STRESS_TICKS)
			left = sim.creatures.creatures.size()
			end_hash = sim.state_hash()
		else:
			check_eq(sim.state_hash(), end_hash, "replay %d ended in the bot's run's state, so it timed the same ticks" % run)
	var average := 0.0
	for w in windows:
		average += best[w]
	average /= float(STRESS_TICKS)
	print("test-threats-stress-cost: %.1f us per tick over %d ticks with %d creatures, each window at its best of %d runs (the bot's run alone %.1f us; %d died, %d left)" % [
		average, STRESS_TICKS, STRESS_CREATURES, STRESS_RUNS, first_average, deaths, left])
	check(average <= STRESS_LIMIT_US, "average %.1f us per tick (limit %.0f)" % [average, STRESS_LIMIT_US])


## The #29 pool: a new omnivore lineage at the spawn, and the ring of creatures facing in.
func _stress_sim() -> PoolSim:
	var sim := _sim("omnivore", 291, test_species)
	for k in STRESS_CREATURES:
		var a := STRESS_RING_START + k * TAU / STRESS_CREATURES
		var p := Vector2.from_angle(a) * STRESS_RING_M
		check(sim.debug_spawn_creature(STRESS_SPECIES[k % STRESS_SPECIES.size()], p, a + PI), "creature %d placed at %s" % [k, p])
	sim.drain_events()
	return sim


func test_slow_a_hunter_lineage_lives_on_its_kills_in_five_of_six_seeds() -> void:
	# Plan #30, the hunter viability gate (D2).
	var passed := 0
	var meat_from_kills := 0
	for seed_value in HUNTER_SEEDS:
		var run := _hunter_run(seed_value)
		var ok: bool = run.starved == 0 and run.killed <= HUNTER_MAX_THREAT_DEATHS and run.meat >= HUNTER_MIN_MEAT
		if ok:
			passed += 1
		meat_from_kills += int(run.meat_from_kills)
		print("test-threats-hunter-gate: seed %d: %s; %d kills, %d meat eaten (%d from its kills), %d starved, %d killed, %d hits taken, %d tells dodged of %d" % [
			seed_value, "pass" if ok else "FAIL", run.kills, run.meat, run.meat_from_kills, run.starved, run.killed, run.hits_taken,
			run.dodges, run.tells])
	print("test-threats-hunter-gate: %d of %d seeds pass (need %d)" % [passed, HUNTER_SEEDS.size(), HUNTER_PASSES_NEEDED])
	check(meat_from_kills > 0, "the hunters ate meat from their own kills, not only the world-start carrion")
	check(passed >= HUNTER_PASSES_NEEDED, "%d of %d seeds pass (need %d)" % [passed, HUNTER_SEEDS.size(), HUNTER_PASSES_NEEDED])


## One seed's 240 s: a new hunter lineage at the spawn, with its real start shelter, driven by HuntBot.
## A dead cell continues at its checkpoint after DEATH_NOTICE_TICKS.
func _hunter_run(seed_value: int) -> Dictionary:
	var sim := _sim("hunter", seed_value)
	var bot = HuntBot.new()
	var run := {"starved": 0, "killed": 0, "meat": 0, "meat_from_kills": 0, "kills": 0, "hits_taken": 0, "tells": 0, "dodges": 0}
	var kill_meat := {}   # food ids of the carcasses the cell's kills left
	var events: Array = []
	var dead_since := -1
	for i in HUNTER_TICKS:
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS:
				sim.respawn_player()
				dead_since = -1
				events.append_array(sim.drain_events())
		sim.step(bot.next_intent(sim, events))
		events = sim.drain_events()
		for e in events:
			match str(e.type):
				"died":
					if e.cause == "starved":
						run.starved += 1
					else:
						run.killed += 1
				"ate":
					if e.kind == "meat":
						run.meat += 1
						if kill_meat.has(e.food_id):
							run.meat_from_kills += 1
				"creature_died":
					if e.by == CreatureField.PLAYER_ID:
						run.kills += 1
						for id in e.carcass:
							kill_meat[id] = true
				"hit":
					if e.target == CreatureField.PLAYER_ID:
						run.hits_taken += 1
				"creature_tell":
					if e.target == CreatureField.PLAYER_ID:
						run.tells += 1
				"dodged":
					run.dodges += 1
	return run


func test_slow_creatures_left_to_prey_on_each_other_keep_every_niche_filled_and_keep_moving() -> void:
	# Plan #31, the predation balance.
	var windows := 0
	for seed_value in BALANCE_SEEDS:
		var run := _balance_run(seed_value)
		windows += int(run.windows)
		print("test-threats-balance: seed %d: %d predation deaths (%s), %d starved, %d respawns, longest empty niche %.1f s, %d move windows checked" % [
			seed_value, run.predation, run.by_kind, run.starved, run.respawns, run.longest_empty / 60.0, run.windows])
		check(run.longest_empty <= EMPTY_NICHE_LIMIT_TICKS, "seed %d: no niche empty for over %d s (longest %.1f s, %s)" % [
			seed_value, EMPTY_NICHE_LIMIT_TICKS / 60, run.longest_empty / 60.0, run.empty_role])
		check(run.predation <= MAX_PREDATION_DEATHS, "seed %d: at most %d predation deaths (%d)" % [seed_value, MAX_PREDATION_DEATHS, run.predation])
		check(run.stalls.is_empty(), "seed %d: every creature on the move got %.0f m in each minute; stalled: %s" % [
			seed_value, MOVE_MIN_M, run.stalls])
	check(windows > 0, "some creature was on the move for a whole window (%d)" % windows)


## One seed's 300 s with the cell hidden (dev_hidden) and fed at the spawn.
func _balance_run(seed_value: int) -> Dictionary:
	var sim := _sim("grazer", seed_value)
	check(sim.debug_set_hidden(true), "seed %d: the cell hidden" % seed_value)
	sim.drain_events()
	var run := {"predation": 0, "by_kind": {}, "starved": 0, "respawns": 0, "longest_empty": 0, "empty_role": "",
		"windows": 0, "stalls": []}
	var empty_since := {}    # role -> tick its count fell to 0
	var watch := {}          # creature id -> {"from", "born", "moving", "farthest"} for the current window
	for i in BALANCE_TICKS:
		sim.state.energy = sim.state.energy_capacity   # the cell only watches
		var t := sim.tick
		if t % MOVE_WINDOW_TICKS == 0:
			_close_windows(sim, watch, run, t)
		sim.step(SimIntent.new())
		for e in sim.drain_events():
			match str(e.type):
				"creature_died":
					if e.cause == "starved":
						run.starved += 1
					elif str(e.by).begins_with(CreatureField.ID_PREFIX):
						run.predation += 1
						var killer := sim.creatures.find(e.by)
						var kind := "%s on %s" % [killer.species_id if killer != null else "?", e.species]
						run.by_kind[kind] = int(run.by_kind.get(kind, 0)) + 1
				"creature_spawned":
					run.respawns += 1
		for role in sim.region.niches:
			var count := int(sim.region.niches[role].count)
			if count > 0:
				empty_since.erase(role)
				continue
			if not empty_since.has(role):
				empty_since[role] = t
			var empty := t + 1 - int(empty_since[role])
			if empty > run.longest_empty:
				run.longest_empty = empty
				run.empty_role = role
		for c in sim.creatures.creatures:
			if not watch.has(c.id):
				continue   # born inside this window: its first full window starts at the next
			var w: Dictionary = watch[c.id]
			w.farthest = maxf(float(w.farthest), c.motion.position.distance_to(w.from))
			if _on_the_move(c):
				w.moving += 1
	return run


## Ends the window before tick `t` for every creature that lived through it, then starts the next.
func _close_windows(sim: PoolSim, watch: Dictionary, run: Dictionary, t: int) -> void:
	if t > 0:
		for c in sim.creatures.creatures:
			if not watch.has(c.id) or int(watch[c.id].moving) < ON_THE_MOVE_MIN_TICKS:
				continue
			run.windows += 1
			if float(watch[c.id].farthest) < MOVE_MIN_M:
				run.stalls.append("%s (%s) %.2f m in the minute before %.0f s, on the move %d ticks, now %s/%s" % [
					c.id, c.species_id, watch[c.id].farthest, t / 60.0, watch[c.id].moving, c.brain.state, c.brain.phase])
	watch.clear()
	for c in sim.creatures.creatures:
		watch[c.id] = {"from": c.motion.position, "moving": 0, "farthest": 0.0}


static func _on_the_move(c: CreatureField.Creature) -> bool:
	if c.brain == null:
		return false
	match c.brain.state:
		CreatureBrain.WANDER, CreatureBrain.FLEE:
			return true
		CreatureBrain.FORAGE:
			return c.brain.phase == CreatureBrain.SEEK
		CreatureBrain.CHASE:
			return c.brain.phase == CreatureBrain.PURSUE
	return false


func test_slow_a_forager_near_the_spawn_meets_threats_and_one_that_dodges_is_not_worn_down() -> void:
	# #32, the pressure gate: the zones by the spawn no longer feed a cell for ever out of every
	# threat's reach (lair_s watches z_s, and z_center alone no longer feeds a cell).
	var deaths := 0
	var starved := 0
	var minutes := 0.0
	for body in PRESSURE_BODIES:
		var meetings := 0
		var met_in := 0
		for seed_value in PRESSURE_SEEDS:
			var run := _pressure_run(body, seed_value)
			var met := int(run.notices) + int(run.tells)
			meetings += met
			met_in += 1 if met > 0 else 0
			deaths += int(run.killed)
			starved += int(run.starved)
			print("test-threats-pressure: %s seed %d: %d notices and %d tells (first at %s), %d dodged, %d hits taken, %d killed, %d starved, %d meals; fed most in %s" % [
				body, seed_value, run.notices, run.tells, "%.0f s" % (run.first_met / 60.0) if run.first_met >= 0 else "none",
				run.dodges, run.hits_taken, run.killed, run.starved, run.meals, run.fed_most])
		var body_minutes := PRESSURE_SEEDS.size() * PRESSURE_TICKS / 3600.0
		minutes += body_minutes
		var rate := meetings / body_minutes
		print("test-threats-pressure: %s: %.2f meetings a minute (need %.1f), met in %d of %d seeds" % [
			body, rate, PRESSURE_MIN_MEETINGS_PER_MIN, met_in, PRESSURE_SEEDS.size()])
		check(rate >= PRESSURE_MIN_MEETINGS_PER_MIN, "%s: %.2f meetings a minute (need %.1f)" % [body, rate, PRESSURE_MIN_MEETINGS_PER_MIN])
		# Every seed, not just the average: a run spent feeding in one quiet zone must not hide
		# behind the others' meetings.
		check_eq(met_in, PRESSURE_SEEDS.size(), "%s: met a threat in every seed" % body)
	var death_rate := deaths / minutes * 5.0
	print("test-threats-pressure: %d deaths in %.0f minutes, %.2f per 5 minutes (at most %.1f); %d starved" % [
		deaths, minutes, death_rate, PRESSURE_MAX_DEATHS_PER_5_MIN, starved])
	check(death_rate <= PRESSURE_MAX_DEATHS_PER_5_MIN, "%.2f deaths per 5 minutes (at most %.1f)" % [death_rate, PRESSURE_MAX_DEATHS_PER_5_MIN])
	check_eq(starved, 0, "the forager never starved, so the zones it roams to still feed it")


## One seed's 300 s: a new `body` lineage at the spawn, ForageBot's nearest food under EvadeBot's dodge.
func _pressure_run(body: String, seed_value: int) -> Dictionary:
	var sim := _sim(body, seed_value)
	var forager = ForageBot.new()
	var bot = EvadeBot.new()
	bot.base = forager.next_intent
	var run := {"notices": 0, "tells": 0, "first_met": -1, "dodges": 0, "hits_taken": 0, "killed": 0, "starved": 0, "meals": 0,
		"fed_most": ""}
	var fed := {}   # zone id -> meals there ("" for carrion)
	var events: Array = []
	var dead_since := -1
	for i in PRESSURE_TICKS:
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS:
				sim.respawn_player()
				dead_since = -1
				events.append_array(sim.drain_events())
		sim.step(bot.next_intent(sim, events))
		events = sim.drain_events()
		for e in events:
			match str(e.type):
				"creature_noticed", "creature_tell":
					if e.target != CreatureField.PLAYER_ID:
						continue
					run[("notices" if e.type == "creature_noticed" else "tells")] += 1
					if run.first_met < 0:
						run.first_met = sim.tick
				"dodged":
					run.dodges += 1
				"hit":
					if e.target == CreatureField.PLAYER_ID:
						run.hits_taken += 1
				"died":
					run[("starved" if e.cause == "starved" else "killed")] += 1
				"ate":
					run.meals += 1
					fed[str(e.zone)] = int(fed.get(str(e.zone), 0)) + 1
	var most := 0
	for zone in fed:
		if int(fed[zone]) > most:
			most = int(fed[zone])
			run.fed_most = zone if not str(zone).is_empty() else "carrion"
	return run
