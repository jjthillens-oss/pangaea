extends TestCase
## The threat fuzz (plan section 18): KiterBot circles creature after creature in the real pool, with
## the real species, sites and niches, for 60 s on each of four seeds, and on every tick every
## creature is checked against the fairness and physics invariants below. The cell's start shelter
## is ended at once; a dead cell comes back at its checkpoint, with its real shelter, after
## DEATH_NOTICE_TICKS. The invariants are FuzzInvariants' 1 to 11 (tests/fuzz_invariants.gd, where
## they moved for the endless fuzz unchanged): the brains' own timers are never trusted to judge
## them; chase lengths, tells and senses are worked out again from events, positions and
## CreatureSenses.
##
##  1  no body more than 1 mm into a rock or past the hard limit, no NaN, no speed above 6 m/s
##  2  every creature inside its leash disc in every state (flee too), and every tell's lane ends
##     inside it, so no strike runs into the hard clamp
##  3  no data creature within respawn_clear_m of the checkpoint (its edge, as rule 8 measures)
##  4  every creature_strike comes exactly its tell (at least 1.2 s) after the same creature's
##     creature_tell, in attack/tell on every tick between, along that tell's lane: the same heading,
##     from within LANE_DRIFT_M of the lane's origin
##  5  every creature's hit lands inside its own strike or glide, at most one per strike, and a hit
##     on the cell lands inside the lane its tell showed (grown by how far that strike started from it)
##  6  every chase ends within give-up plus one attack cycle of its start (a notice, a chase from
##     rest or the creature's own hit); every notice within notice plus give-up
##  7  no stall: 150 ticks in chase/pursue, wander/* or forage/seek (toward one goal) move the
##     creature 0.25 m
##  8  at most one creature engaged (chase or attack) on the cell, and the token list within its limit
##     and holding every engaged creature
##  9  a creature that first targets the cell sensed it on that tick (CreatureSenses, from the bodies
##     before the step) or was hurt by it within its memory; and on every tick, whatever the creature
##     is doing, any change to its memory of the cell is a percept its senses give from where it
##     looked before the step (the same sense, position and velocity) or a hurt by the cell then
## 10  health and energy within range, for the cell and every creature
## 11  each niche counts exactly its live data creatures, within its cap

const KiterBot := preload("res://game/dev/kiter_bot.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
const SEEDS: Array[int] = [401, 402, 403, 404]
## The starting body of each seed's lineage: two jaws to wound creatures (flee), and the jawless grazer.
const BODIES: PackedStringArray = ["hunter", "omnivore", "grazer", "hunter"]
## Where each seed's cell starts: the checkpoint, then open water between the northern territories
## and the gap's lair, so most of each minute is spent among creatures rather than swimming to them.
const STARTS: Array[Vector2] = [Vector2.INF, Vector2(-10.0, -6.0), Vector2(0.0, -12.0), Vector2(10.0, -6.0)]
const RUN_TICKS := 3600                  ## 60 s per seed
const DEATH_NOTICE_TICKS := 90           ## a player reading the death notice before Continue
## Non-vacuity, over all seeds (plan section 18).
const MIN_TELLS := 10
const MIN_GIVE_UPS := 3
const MIN_HITS_ON_CELL := 1
const MIN_FLEES := 1
## Invariant 9's floor: changed memories of the cell checked over the four seeds (3333 measured).
const MIN_MEMORY_CHECKS := 2000

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog
var _fz: FuzzInvariants   ## the test's invariants: `bad` across the seeds, `counts` per seed


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()
	_fz = FuzzInvariants.new(species, layout)


func test_kiting_round_the_real_creatures_for_four_minutes_breaks_no_fairness_or_physics_rule_on_any_tick() -> void:
	var totals := {"tells": 0, "strikes": 0, "hits_on_cell": 0, "give_ups": 0, "flees": 0, "memory_checks": 0}
	for i in SEEDS.size():
		var counts := _fuzz(SEEDS[i], BODIES[i], STARTS[i])
		print("test-threat-fuzz: seed %d (%s): %d tells, %d strikes, %d hits on the cell, %d by the cell, %d give-ups, %d flees, %d notices, %d cell deaths, %d creature deaths, %d visits; strikes up to %.3f m from their lanes' origins" % [
			SEEDS[i], BODIES[i], counts.tells, counts.strikes, counts.hits_on_cell, counts.hits_by_cell, counts.give_ups,
			counts.flees, counts.notices, counts.deaths, counts.creature_deaths, counts.visits, counts.drift])
		print("test-threat-fuzz: seed %d: %d changed memories of the cell checked against the senses" % [SEEDS[i], counts.memory_checks])
		for key in totals.keys():
			totals[key] += int(counts[key])
	for inv in range(1, 12):
		if _fz.bad.has(inv):
			check(false, "invariant %d broken %d times; first: %s" % [inv, _fz.bad[inv].count, _fz.bad[inv].first])
	check(totals.tells >= MIN_TELLS, "at least %d tells over all seeds (%d)" % [MIN_TELLS, totals.tells])
	check(totals.give_ups >= MIN_GIVE_UPS, "at least %d give-ups (%d)" % [MIN_GIVE_UPS, totals.give_ups])
	check(totals.hits_on_cell >= MIN_HITS_ON_CELL, "at least %d hit on the cell (%d)" % [MIN_HITS_ON_CELL, totals.hits_on_cell])
	check(totals.flees >= MIN_FLEES, "at least %d flee (%d)" % [MIN_FLEES, totals.flees])
	check(totals.memory_checks >= MIN_MEMORY_CHECKS, "at least %d memories of the cell checked (%d)" % [MIN_MEMORY_CHECKS, totals.memory_checks])


func test_invariant_9_fails_a_memory_of_the_cell_that_its_senses_did_not_give() -> void:
	# Invariant 9's check on memories made up for the lair_se hunter at home: what its senses give
	# passes; a percept from behind it, one 1 cm off the cell, an old one moved, or pain with no hit
	# fails.
	var r := Lineage.found(SEEDS[0], "test+dev", catalog, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	var c: CreatureField.Creature = sim.creatures.creatures[0]
	var looked := {"target": "", "position": c.motion.position, "heading": c.motion.heading, "memory": {}}
	var ahead: Vector2 = c.motion.position + Vector2.from_angle(c.motion.heading) * 3.0
	var behind: Vector2 = c.motion.position - Vector2.from_angle(c.motion.heading) * 3.0
	var t := sim.tick + 100
	var cases := [   # [what, the cell at, remembered at, by, remembered tick, hurt by the cell at, fails]
		["seen ahead, as its senses give it", ahead, ahead, "sight", t, -1, false],
		["seen behind it, outside its field of view", behind, behind, "sight", t, -1, true],
		["seen ahead 1 cm off where the cell is", ahead, ahead + Vector2(0.01, 0.0), "sight", t, -1, true],
		["an older percept moved onto the cell", ahead, ahead, "sight", t - 5, -1, true],
		["pain with no hit by the cell", behind, behind, "pain", t, -1, true],
		["pain from the cell's hit on this tick", behind, behind, "pain", t, t, false],
	]
	for case in cases:
		_fz = FuzzInvariants.new(species, layout)
		var cell := {"id": CreatureField.PLAYER_ID, "species": SpeciesCatalog.PLAYER_SPECIES, "position": case[1],
			"velocity": Vector2.ZERO, "radius": sim.phenotype.radius, "alive": true, "concealed": false, "engageable": true}
		c.brain.seen[CreatureField.PLAYER_ID] = {"position": case[2], "velocity": Vector2.ZERO, "tick": case[4], "by": case[3],
			"species": SpeciesCatalog.PLAYER_SPECIES, "radius": sim.phenotype.radius, "engageable": true}
		var k := {"hurt_by_cell": {c.id: case[5]}, "memory_checks": 0}
		_fz._check_memory(c, t, "self-test", looked, cell, sim.arena, k)
		check_eq(_fz.bad.has(9), case[6], "%s: %s" % [case[0], "fails" if case[6] else "passes"])
		check_eq(k.memory_checks, 1, "%s: counted" % case[0])


## One seed's run, the cell starting at `start` (the checkpoint when not finite). Returns its event
## counts.
func _fuzz(seed_value: int, body: String, start: Vector2) -> Dictionary:
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	sim.grace_until = sim.tick
	if start.is_finite():
		check(sim.debug_teleport(start, 0.0), "seed %d: the cell placed at %s" % [seed_value, start])
	sim.drain_events()
	var bot = KiterBot.new(seed_value)
	_fz.start_run()
	var dead_since := -1
	for i in RUN_TICKS:
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS:
				sim.respawn_player()
				dead_since = -1
				# Cancelled strikes and the respawn itself, before the next step.
				_fz.take_events(sim, sim.drain_events(), sim.tick, "seed %d respawn at %d" % [seed_value, sim.tick])
		var before := _fz.before(sim)
		var t := sim.tick
		sim.step(bot.next_intent(sim))
		_fz.after(sim, sim.drain_events(), t, "seed %d tick %d" % [seed_value, t], before)
	var counts := _fz.counts
	counts.visits = bot.visits
	return counts
