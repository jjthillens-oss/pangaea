extends TestCase
## M1 step 3 threats in the running PoolSim: creatures sense the cell only through their own senses
## (rocks hide it, sight has a range and a field of view, touch works behind them), remember it for
## a while and give up when it is gone; their state depends on nothing they did not sense (T5 and
## the decoy); the sim stays deterministic, hashes everything it keeps, and without creatures is
## exactly the step 2 pool. Most tests use the threats fixture (an open pool with a wall of rocks at
## y = 8) and the real species with no sites, so every creature is placed exactly.

const ForageBot := preload("res://game/dev/forage_bot.gd")
const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"
const DT := PoolSim.DT
const PLAYER := "player"
const STEP_COST_LIMIT_US := 1000.0
## Snapshot keys only a pool with creatures has (T14 compares everything else).
const CREATURE_KEYS: PackedStringArray = ["creatures", "creature_next", "creature_rng", "spawn_queue",
	"engaged_on_player", "niches"]
## What #25 perturbs, one sim each (_perturb).
const PERTURBATIONS: PackedStringArray = ["creature position.x by one float32 step", "creature velocity",
	"creature heading", "creature health", "creature energy", "a cooldown", "phase_tick", "target", "lock_heading",
	"a seen position", "an ignore entry", "landed_on", "the brain RNG", "the field RNG", "a queue at_tick",
	"engaged_on_player", "the AI frozen switch", "the hidden switch", "the cell's death"]

var catalog: PartCatalog
var fixture: PoolLayout
var layout: PoolLayout
var test_species: SpeciesCatalog
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	fixture = PoolLayout.load_from(THREATS_FIXTURE)
	layout = PoolLayout.load_from()
	test_species = SpeciesCatalog.load_from(TEST_SPECIES)
	species = SpeciesCatalog.load_from()


## A new lineage with creatures (the fixture and the site-less species unless given), the cell at
## `at` facing `heading` (else at the layout spawn). Starting events are dropped.
func _sim(body: String, seed_value: int, at := Vector2.INF, heading := 0.0, p_layout: PoolLayout = null,
		p_species: SpeciesCatalog = null) -> PoolSim:
	var use := p_layout if p_layout != null else fixture
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(use.spawn)
	var sim := PoolSim.create(r.save, catalog, use, p_species if p_species != null else test_species)
	if at.is_finite():
		check(sim.debug_teleport(at, heading), "the cell placed at %s" % at)
	sim.drain_events()
	return sim


## The step 2 pool for the same lineage: no species at all.
func _plain_sim(body: String, seed_value: int, p_layout: PoolLayout) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(p_layout.spawn)
	return PoolSim.create(r.save, catalog, p_layout)


## A creature placed at `at` facing `heading`, settled (it may notice from its first think), at
## `energy_share` of its capacity when given (below its hungry share it hunts or forages).
func _creature(sim: PoolSim, species_id: String, at: Vector2, heading: float, energy_share := -1.0) -> CreatureField.Creature:
	var c := sim.creatures.spawn_at(species_id, at, heading, "", sim.tick, true)
	check(c != null, "a %s placed at %s" % [species_id, at])
	c.brain.ignore_all_until = 0
	if energy_share >= 0.0:
		c.state.energy = c.state.energy_capacity * energy_share
	sim.drain_events()
	return c


## Steps `ticks` times (intent from `intent.call(sim)`, else none) and returns the events, each
## stamped with the tick it happened on. `each.call(sim, tick)` runs after every step; when it
## returns true the run stops early.
func _run(sim: PoolSim, ticks: int, intent := Callable(), each := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		var t := sim.tick
		var wanted: SimIntent = intent.call(sim) if intent.is_valid() else SimIntent.new()
		sim.step(wanted)
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
		if each.is_valid() and each.call(sim, t) == true:
			break
	return out


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _creature_json(sim: PoolSim) -> String:
	return JSON.stringify(sim.creatures.snapshot(), "", true, true)


# --- senses: it cannot see your coordinates (plan threats_sim #14-17) ---

func test_a_cell_behind_rocks_beyond_sight_or_behind_a_creature_outside_its_touch_is_never_noticed() -> void:
	# [what, creature at, facing, cell at, how it should be found ("" never)]
	var cases := [
		["behind the wall, within sight range", Vector2(0.0, 4.5), PI / 2.0, Vector2(0.0, 10.5), ""],
		["in the open at 6.6 m, past sight 6 + 0.5", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, 1.6), ""],
		["in the open at 6.4 m", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, 1.4), "sight"],
		["right behind it at 2.30 m, outside touch", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, -7.3), ""],
		["right behind it at 2.20 m, inside touch", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, -7.2), "near"],
	]
	for case in cases:
		var sim := _sim("grazer", 14, case[3], 0.0)
		var c := _creature(sim, "ambush_hunter", case[1], case[2])
		if case[0].begins_with("behind the wall"):
			var viewer := sim.creatures.viewer_of(c)
			check_eq(CreatureSenses.perceive(viewer, [sim.player_body()], null).size(), 1, "without rocks it would see it")
			check(CreatureSenses.perceive(viewer, [sim.player_body()], sim.arena).is_empty(), "the wall hides it")
		var noticed := _of(_run(sim, 600), "creature_noticed")
		if case[4].is_empty():
			check(noticed.is_empty(), "%s: never noticed in 600 ticks (%d notices)" % [case[0], noticed.size()])
		else:
			check(not noticed.is_empty(), "%s: noticed" % case[0])
			if not noticed.is_empty():
				check_eq(noticed[0].by, case[4], "%s: by %s" % [case[0], case[4]])
				check(int(noticed[0].tick) < 6, "%s: on its first think (tick %d)" % [case[0], noticed[0].tick])
				check_eq(noticed[0].target, PLAYER, "%s: the cell" % case[0])


func test_a_creature_that_loses_sight_of_the_cell_heads_for_where_it_last_saw_it_and_gives_up_lost() -> void:
	var sim := _sim("grazer", 15, Vector2(3.5, 6.0), 0.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, 4.5), PI / 2.0, 0.5)
	var chasing := func(_s: PoolSim, _t: int) -> bool: return c.brain.state == CreatureBrain.CHASE
	var before := _run(sim, 200, Callable(), chasing)
	check_eq(c.brain.state, CreatureBrain.CHASE, "a hungry hunter chases the cell it noticed")
	check_eq(_of(before, "creature_noticed").size(), 1, "after one notice")
	var last_seen: int = c.brain.seen[PLAYER].tick
	var seen_at: Vector2 = c.brain.seen[PLAYER].position
	var hide := Vector2(0.5, 10.0)
	check(sim.debug_teleport(hide), "the cell slips behind the wall")
	check(c.motion.position.distance_to(hide) <= c.phenotype.sight + sim.phenotype.radius, "still within sight range: only the rocks hide it")
	var start_gap := c.motion.position.distance_to(seen_at)
	var closest := [start_gap]
	var leaked := [0]
	var watch := func(s: PoolSim, _t: int) -> bool:
		if c.brain.seen.has(PLAYER) and Vector2(c.brain.seen[PLAYER].position).is_equal_approx(s.motion.position):
			leaked[0] += 1
		closest[0] = minf(closest[0], c.motion.position.distance_to(seen_at))
		return c.brain.state != CreatureBrain.CHASE
	var events := _run(sim, 400, Callable(), watch)
	var gave_up := _of(events, "creature_gave_up")
	check_eq(gave_up.size(), 1, "it gives up once")
	if gave_up.size() == 1:
		check_eq(gave_up[0].reason, "lost", "because it lost the cell")
		var memory: int = c.brain.cfg.memory_ticks
		var late := int(gave_up[0].tick) - last_seen
		check(late >= memory and late <= memory + 3, "%d ticks after the last percept (memory %d)" % [late, memory])
	check_eq(leaked[0], 0, "what it remembered was never the hidden cell's real position")
	check(closest[0] < start_gap - 0.5, "it swam toward where it last saw the cell (%.2f -> %.2f m)" % [start_gap, closest[0]])
	check(_of(events, "creature_noticed").is_empty(), "and never saw it again")


func test_a_creatures_life_is_the_same_wherever_an_unsensed_cell_is() -> void:
	# T5: one hungry ambush hunter foraging round its home; the cell parked 16 m north or south.
	var a := _sim("grazer", 16, Vector2(0.0, -16.0))
	var b := _sim("grazer", 16, Vector2(0.0, 16.0))
	var ca := _creature(a, "ambush_hunter", Vector2.ZERO, PI / 2.0, 0.4)
	_creature(b, "ambush_hunter", Vector2.ZERO, PI / 2.0, 0.4)
	var differing := 0
	var travelled := 0.0
	for i in 1800:
		var was := ca.motion.position
		a.step(SimIntent.new())
		b.step(SimIntent.new())
		travelled += was.distance_to(ca.motion.position)
		if _creature_json(a) != _creature_json(b):
			differing += 1
	check_eq(differing, 0, "the creature snapshots match on all 1800 ticks")
	check(travelled > 10.0, "the creature was busy (it swam %.1f m)" % travelled)
	check(_of(a.drain_events(), "creature_noticed").is_empty(), "it never sensed the cell")

	# The same with both cells within sight range but behind the wall, at different points.
	var hidden_a := _sim("grazer", 17, Vector2(-1.5, 10.5))
	var hidden_b := _sim("grazer", 17, Vector2(1.5, 10.5))
	var seen_c := _sim("grazer", 17, Vector2(3.0, 6.0))
	var h := _creature(hidden_a, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	_creature(hidden_b, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	_creature(seen_c, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	check(h.motion.position.distance_to(hidden_a.motion.position) < h.phenotype.sight + 0.5, "the hidden cells are within sight range")
	differing = 0
	var control_differs := 0
	for i in 1800:
		for s in [hidden_a, hidden_b, seen_c]:
			s.step(SimIntent.new())
		if _creature_json(hidden_a) != _creature_json(hidden_b):
			differing += 1
		if _creature_json(hidden_a) != _creature_json(seen_c):
			control_differs += 1
	check_eq(differing, 0, "behind the wall, the snapshots match on all 1800 ticks")
	check(control_differs > 0, "control: a cell in clear view changes the creature (%d ticks differ)" % control_differs)


func test_a_scripted_decoy_where_the_cell_would_be_gets_the_same_drive_tick_by_tick() -> void:
	var at := Vector2(0.0, -7.25)
	var script := func(t: int) -> Vector2: return Vector2(0.3, 0.0) if t < 90 else Vector2.ZERO
	# Run A: the cell at P. Run B: the cell parked out of every sense, a decoy at P.
	var a := _sim("grazer", 18, at, 0.0)
	var b := _sim("grazer", 18, Vector2(0.0, 20.0), 0.0)
	var ha := _creature(a, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	var hb := _creature(b, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	var decoy := b.creatures.spawn_scripted(SpeciesCatalog.PLAYER_SPECIES, b.phenotype, at, 0.0, b.tick)
	b.drain_events()
	var compared := 0
	var told := false
	var mismatch := ""
	for t in 300:
		decoy.script_move = script.call(t)
		a.step(SimIntent.new(script.call(t)))
		b.step(SimIntent.new())
		var ea := a.drain_events()
		var eb := b.drain_events()
		if not _of(ea, "hit").is_empty() or not _of(eb, "hit").is_empty():
			break
		if ha.motion.position.distance_to(a.motion.position) < ha.phenotype.radius + a.phenotype.radius:
			break   # bodies in contact are pushed apart in a different pair order from here on
		compared += 1
		told = told or not _of(ea, "creature_tell").is_empty()
		var da: Dictionary = ha.drive.duplicate()
		var db: Dictionary = hb.drive.duplicate()
		var target_ok: bool = (da.target == PLAYER and db.target == decoy.id) or (da.target == "" and db.target == "")
		da.erase("target")
		db.erase("target")
		if mismatch.is_empty() and (da != db or not target_ok):
			mismatch = "tick %d: %s vs %s" % [t, ha.drive, hb.drive]
	check(mismatch.is_empty(), "the drives match: %s" % mismatch)
	check(compared >= 100, "compared %d ticks" % compared)
	check(told, "the comparison covered a tell")
	check_eq(b.creatures.snapshot().creatures[1].species, SpeciesCatalog.PLAYER_SPECIES, "the decoy carries the cell's species")


# --- the creatures' own lives ---

func test_a_hungry_rammer_grazes_plankton_in_its_territory_through_the_resolver() -> void:
	var sim := _sim("grazer", 21, Vector2(0.0, 25.0))
	var c := _creature(sim, "rammer", Vector2(0.0, 1.0), 0.0, 0.5)
	var energy_before := c.state.energy
	var events := _run(sim, 1800)
	var meals := _of(events, "creature_ate")
	check(meals.size() >= 3, "it ate (%d meals)" % meals.size())
	for e in meals:
		check_eq(e.id, c.id, "the rammer ate")
		check_eq(e.kind, "plant", "plankton")
		check(sim.plankton.items.all(func(item: Dictionary) -> bool: return item.id != e.food_id), "%s is gone" % e.food_id)
	check(c.state.energy > energy_before, "its energy rose (%.1f -> %.1f)" % [energy_before, c.state.energy])
	check_eq(sim.stats.creature_meals, meals.size(), "counted")
	check_eq(sim.stats.points_food, 0, "no food points for the lineage")
	check(_of(events, "ate").is_empty(), "the cell ate nothing")


func test_a_creature_that_starves_dies_without_a_carcass_and_frees_its_niche() -> void:
	var sim := _sim("grazer", 22, Vector2(0.0, 25.0))
	var c := sim.creatures.spawn_at("rammer", Vector2(10.0, -10.0), 0.0, "", 0)
	check_eq(sim.region.niches.territorial.count, 1, "a counted rammer")
	c.state.energy = 0.0
	c.state.health = 0.005   # starving costs it 1.5 x 0.25 / 60 health a tick
	var events := _run(sim, 2)
	var died := _of(events, "creature_died")
	check_eq(died.size(), 1, "it died")
	if died.size() == 1:
		check_eq(died[0].cause, "starved", "of starvation")
		check_eq(died[0].carcass, [], "no carcass")
		check_eq(died[0].species, "rammer", "a rammer")
	check(_of(events, "carrion_spawned").is_empty(), "no carrion")
	check(sim.creatures.find(c.id) == null, "gone from the pool")
	check_eq(sim.region.niches.territorial.count, 0, "its niche slot is free")
	check_eq(sim.stats.creature_deaths, 1, "counted")
	var removed := _of(events, "creature_removed")
	check(removed.size() == 1 and events.find(died[0]) < events.find(removed[0]), "creature_died comes before creature_removed")


func test_a_creature_stays_inside_its_leash_and_bodies_never_overlap_in_open_water() -> void:
	var sim := _sim("hunter", 23, Vector2(0.0, -14.0), PI / 2.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, -20.0), PI / 2.0, 0.3)
	var disc := CreatureBrain.leash_disc(c.brain)
	var worst_leash := [0.0]
	var worst_overlap := [0.0]
	var chased := [false]
	var away := func(s: PoolSim) -> SimIntent:
		# Swim south, away from its home, then hold still once well out.
		return SimIntent.new(Vector2(0.0, 1.0) if s.tick < 400 else Vector2.ZERO)
	var watch := func(s: PoolSim, _t: int) -> bool:
		chased[0] = chased[0] or c.brain.state == CreatureBrain.CHASE
		worst_leash[0] = maxf(worst_leash[0], c.motion.position.distance_to(disc.center) - float(disc.radius))
		var gap := c.motion.position.distance_to(s.motion.position) - c.phenotype.radius - s.phenotype.radius
		worst_overlap[0] = maxf(worst_overlap[0], -gap)
		return false
	_run(sim, 900, away, watch)
	check(chased[0], "it chased the cell")
	check(worst_leash[0] <= 1e-3, "never past its leash (worst %.4f m)" % worst_leash[0])
	check(worst_overlap[0] <= 1e-3, "the bodies never overlap at the end of a tick (worst %.4f m)" % worst_overlap[0])


# --- dev commands ---

func test_dev_commands_place_freeze_and_hide_and_refuse_what_does_not_fit() -> void:
	var sim := _sim("grazer", 31, Vector2(0.0, -10.0), PI / 2.0)
	check(not sim.debug_spawn_creature("kraken", Vector2.ZERO, 0.0), "an unknown species is refused")
	check(not sim.debug_spawn_creature("rammer", Vector2(0.0, 8.0), 0.0), "a rock is refused")
	check(sim.debug_spawn_threat_ahead("ambush_hunter"), "a threat ahead")
	var events := sim.drain_events()
	var c: CreatureField.Creature = sim.creatures.creatures[-1]
	check_near(c.motion.position.distance_to(sim.motion.position), PoolSim.DEBUG_THREAT_AHEAD_M, 1e-4, "6 m ahead")
	check_near(absf(angle_difference(c.motion.heading, (sim.motion.position - c.motion.position).angle())), 0.0, 1e-5, "facing the cell")
	check(c.debug, "a dev creature")
	check_eq(_of(events, "creature_spawned").size(), 1, "creature_spawned")
	check_eq(_of(events, "debug").size(), 1, "and a debug event")
	var plain := _plain_sim("grazer", 31, fixture)
	check(not plain.debug_spawn_threat_ahead("rammer"), "a pool without species has no creatures to place")
	check(not plain.debug_set_ai_frozen(true), "nor brains to freeze")

	c.brain.ignore_all_until = 0
	c.state.energy = c.state.energy_capacity * 0.4
	var engaged := func(_s: PoolSim, _t: int) -> bool: return CreatureBrain.is_engaged_with(c.brain, PLAYER)
	_run(sim, 120, Callable(), engaged)
	check(CreatureBrain.is_engaged_with(c.brain, PLAYER), "a hungry hunter engages the cell")
	check(sim.debug_set_hidden(true), "hide from AI")
	var hidden := _run(sim, 300)
	var gave_up := _of(hidden, "creature_gave_up")
	check(not gave_up.is_empty() and gave_up[0].reason == "target_gone", "it gives up on the hidden cell (target_gone)")
	check(_of(hidden, "creature_noticed").is_empty(), "and never notices it while hidden")
	check(sim.creatures.engaged_on_player.is_empty(), "the token is free")
	check(sim.debug_set_hidden(false), "unhide")

	check(sim.debug_set_ai_frozen(true), "freeze")
	c.motion.velocity = Vector2(1.0, 0.0)
	var phase := c.brain.phase_tick
	_run(sim, 120)
	check(c.motion.velocity.length() < 0.05, "a frozen creature coasts to a stop")
	check_eq(c.brain.phase_tick, phase, "and decides nothing")
	check_eq(c.drive.mode, CreatureBrain.MODE_STEER, "its drive is idle")
	check(sim.snapshot().dev_ai_frozen and not sim.snapshot().dev_hidden, "the switches are in the snapshot")


# --- determinism and coverage (plan threats_sim #24-28) ---

func test_two_runs_with_the_same_seed_and_intents_hash_the_same_and_another_seed_does_not() -> void:
	var runs := []
	for seed_value in [77, 77, 78]:
		var sim := _sim("hunter", seed_value, Vector2.INF, 0.0, layout, species)
		check(sim.debug_spawn_threat_ahead("ambush_hunter"), "a threat ahead")
		var c: CreatureField.Creature = sim.creatures.creatures[-1]
		c.brain.ignore_all_until = 0
		c.state.energy = c.state.energy_capacity * 0.4   # hungry: it chases
		runs.append({"seed": seed_value, "sim": sim, "bot": ForageBot.new(), "hashes": [], "engaged": 0})
	for t in 3600:
		for run in runs:
			var sim: PoolSim = run.sim
			if run.seed == 78 and t >= 600:
				continue   # seed 78 only has to differ by tick 600
			sim.step(run.bot.next_intent(sim))
			sim.drain_events()
			if not sim.creatures.engaged_on_player.is_empty():
				run.engaged += 1
			if sim.tick % 60 == 0:
				run.hashes.append(sim.state_hash())
	check_eq(runs[0].hashes, runs[1].hashes, "seed 77 twice: the same hash every 60 ticks")
	check(runs[0].hashes.slice(0, 10) != runs[2].hashes.slice(0, 10), "seed 78 differs by tick 600")
	check(runs[0].engaged > 0, "the run included a chase on the cell (%d ticks engaged)" % runs[0].engaged)
	check_eq(runs[0].hashes.size(), 60, "sixty hashes")


## A sim with a creature in the middle of a tell on the cell and every kind of memory filled in.
func _rich_sim() -> PoolSim:
	var sim := _sim("hunter", 25, Vector2(0.0, -7.25), -PI / 2.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	_creature(sim, "rammer", Vector2(10.0, -10.0), 0.0)
	_run(sim, 200, Callable(), func(_s: PoolSim, _t: int) -> bool: return c.brain.phase == CreatureBrain.TELL)
	c.actor.cooldowns["bite:" + PLAYER] = 4.0
	c.brain.ignore["c_9"] = 500
	c.brain.landed_on["c_9"] = 3
	sim.creatures.queue.append({"site": "lair_x", "species": "ambush_hunter", "at_tick": 900})
	return sim


func test_the_state_hash_covers_every_creature_brain_field_and_rng_it_keeps() -> void:
	var base := _rich_sim()
	var c: CreatureField.Creature = base.creatures.creatures[0]
	check_eq(c.brain.phase, CreatureBrain.TELL, "the creature is telling")
	check(base.creatures.engaged_on_player.has(c.id), "and holds the token")
	check(c.brain.seen.has(PLAYER), "it remembers the cell")
	var h0 := base.state_hash()
	check_eq(_rich_sim().state_hash(), h0, "the same build hashes the same")
	for what in PERTURBATIONS:
		var sim := _rich_sim()
		_perturb(sim, what)
		check(sim.state_hash() != h0, "perturbing %s changes the hash" % what)
	check(_no_vectors(base.snapshot()), "every vector in the snapshot is a pair")


func _perturb(s: PoolSim, what: String) -> void:
	var c: CreatureField.Creature = s.creatures.creatures[0]
	match what:
		"creature position.x by one float32 step":
			# 1e-9 m is below float32 resolution away from 0; one step (2^-23 relative) is the smallest change.
			var x := c.motion.position.x
			c.motion.position.x = x + maxf(absf(x) * 1.2e-7, 1e-9)
			check(c.motion.position.x != x, "the position changed")
		"creature velocity":
			c.motion.velocity.y += 1e-3
		"creature heading":
			c.motion.heading += 1e-5
		"creature health":
			c.state.health -= 0.01
		"creature energy":
			c.state.energy -= 0.01
		"a cooldown":
			c.actor.cooldowns["bite:" + PLAYER] = 4.01
		"phase_tick":
			c.brain.phase_tick += 1
		"target":
			c.brain.target = "c_2"
		"lock_heading":
			c.brain.lock_heading += 1e-5
		"a seen position":
			c.brain.seen[PLAYER].position += Vector2(0.001, 0.0)
		"an ignore entry":
			c.brain.ignore["c_9"] = 501
		"landed_on":
			c.brain.landed_on["c_9"] = 4
		"the brain RNG":
			c.brain.rng.randf()
		"the field RNG":
			s.creatures.rng.randf()
		"a queue at_tick":
			s.creatures.queue[0].at_tick = 901
		"engaged_on_player":
			s.creatures.engaged_on_player.append("c_2")
		"the AI frozen switch":
			s.dev_ai_frozen = true
		"the hidden switch":
			s.dev_hidden = true
		"the cell's death":
			s.death = {"cause": "killed"}


func test_without_creatures_the_species_machinery_changes_nothing_in_the_step_2_pool() -> void:
	# T14: the step 2 run (ForageBot, seed 77) with no species and with species but no sites.
	var plain := _plain_sim("omnivore", 77, layout)
	var r := Lineage.found(77, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var empty := PoolSim.create(r.save, catalog, layout, test_species)
	check(empty.creatures != null and empty.creatures.creatures.is_empty(), "species, but no creatures")
	var bots := [ForageBot.new(), ForageBot.new()]
	var snap_diffs := 0
	var event_diffs := 0
	var first := ""
	var events := 0
	for t in 3600:
		plain.step(bots[0].next_intent(plain))
		empty.step(bots[1].next_intent(empty))
		var ea := plain.drain_events()
		var eb := empty.drain_events()
		events += ea.size()
		if ea != eb:
			event_diffs += 1
		var sb := empty.snapshot()
		for k in CREATURE_KEYS:
			sb.erase(k)
		if plain.snapshot() != sb:   # a deep comparison of every key and value
			snap_diffs += 1
			if first.is_empty():
				first = "tick %d" % t
	check_eq(snap_diffs, 0, "the snapshots match minus the creature keys on every tick (first difference %s)" % first)
	check_eq(event_diffs, 0, "and so do the events")
	check(events >= 10 and plain.stats.plankton_eaten > 0, "the run did something (%d events)" % events)


func test_creatures_and_their_respawns_never_draw_from_the_region_rng() -> void:
	# T15: with and without species, the same seed; the creatures frozen, the lair_sw hunter (far from
	# the zones the cell forages in, so the 20 m rule never holds it back) killed and respawned.
	var plain := _plain_sim("grazer", 27, layout)
	var r := Lineage.found(27, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var full := PoolSim.create(r.save, catalog, layout, species)
	check_eq(full.creatures.creatures.size(), 7, "seven creatures")
	check_eq(full.region.rng.state, plain.region.rng.state, "identical after create")
	full.debug_set_ai_frozen(true)
	var start_state := plain.region.rng.state
	var bots := [ForageBot.new(), ForageBot.new()]
	var hunter: CreatureField.Creature = full.creatures.find("c_2")
	check_eq(hunter.site_id, "lair_sw", "c_2 is lair_sw's hunter")
	var diffs := 0
	var respawned := -1
	for t in 4300:
		if t == 30:
			full.creatures.remove(hunter, "killed", full.tick, true)
		plain.step(bots[0].next_intent(plain))
		full.step(bots[1].next_intent(full))
		if respawned < 0 and not _of(full.drain_events(), "creature_spawned").is_empty():
			respawned = t
		if plain.region.rng.state != full.region.rng.state:
			diffs += 1
	check(respawned > 30, "lair_sw respawned (tick %d)" % respawned)
	check_eq(diffs, 0, "the region RNG matched on every tick")
	check(plain.region.rng.state != start_state, "the region RNG was in use (plankton regrowth)")


func test_a_tick_with_seven_creatures_costs_well_under_a_millisecond() -> void:
	var sim := _sim("omnivore", 91, Vector2.INF, 0.0, layout, species)
	check_eq(sim.creatures.creatures.size(), 7, "seven creatures")
	var bot = ForageBot.new()
	var spent := 0
	for i in 3600:
		var intent: SimIntent = bot.next_intent(sim)
		var t0 := Time.get_ticks_usec()
		sim.step(intent)
		spent += Time.get_ticks_usec() - t0
		sim.drain_events()
	var average := spent / 3600.0
	print("test-threats-step-cost: %.1f us per tick over 3600 ticks with %d creatures" % [average, sim.creatures.creatures.size()])
	check(average <= STEP_COST_LIMIT_US, "average %.1f us per tick" % average)


func _no_vectors(value: Variant) -> bool:
	if value is Vector2 or value is Vector3:
		return false
	if value is Dictionary:
		for k in value:
			if not _no_vectors(value[k]):
				return false
	if value is Array:
		for v in value:
			if not _no_vectors(v):
				return false
	return true
