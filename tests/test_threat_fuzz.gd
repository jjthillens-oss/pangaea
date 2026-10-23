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
##
## The endless runner at size 2 (S2 T0.3, gate S2G8; endless-cell plan B.6): on the real content with
## growth on, each seed's cell is set to size 2 at home on its first tick (debug_set_size, a cut for
## the checker, BP-2) and lives 5 minutes there, KiterBot on two seeds (biting every creature it
## visits, bite_visits) and EvadeBot over ForageBot (unjam on) on two. At size 2 the home's sites are
## in view of the spawn and never spawn there, so each cell goes to meet the creatures as a player
## would: a SwimBot.SiteTour (SIZE_TWO_TOURS) of the sites live at size 2 (the M1 species' in set-0
## tiles and the home, and the size-2 species'), keeping near each site's creature while its bot
## drives; an evading cell that eats plants breaks off to forage when hungry (SIZE_TWO_HUNGRY to
## SIZE_TWO_FED), as a player would. Every tick is checked against
## FuzzInvariants as the endless fuzz has them (1 to 13 and 16; 2 on the two-post disc the brain's
## leash_disc gives, and 3, 7 and 11 over the creature field, which holds no remnant) and against
## 14  no creature at q < 1 at the cell's size notices, tells at, chases or hits the cell: none holds
##     the cell as its target, names it in creature_noticed, creature_tell or creature_strike, or
##     lands a hit on it (a remnant's too).
## Non-vacuity: each pair of SIZE_TWO_PAIRS had the cell in its senses on at least
## SIZE_TWO_MIN_SENSED ticks and was bitten by it at least once, so the rule against answering a
## larger body (relationship rule 4) was asked. The runner waits on the S2 seams it reads
## (Gates.s2_missing).

const KiterBot := preload("res://game/dev/kiter_bot.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
const Gates := preload("res://tests/test_endless_gates.gd")
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
## The size-2 runner (S2G8): seeds, bots and bodies (the kiters bite, so they have jaws).
const SIZE_TWO_SEEDS: Array[int] = [421, 422, 423, 424]
const SIZE_TWO_BOTS: PackedStringArray = ["kiter", "evade", "kiter", "evade"]
const SIZE_TWO_BODIES: PackedStringArray = ["hunter", "grazer", "omnivore", "hunter"]
const SIZE_TWO := 2
const SIZE_TWO_TICKS := 5 * 60 * 60
## The (species, size) pairs invariant 14 is asked of, and how often each must have sensed the cell.
const SIZE_TWO_PAIRS := [["ambush_hunter", 2], ["rammer", 2]]
const SIZE_TWO_MIN_SENSED := 600
const SIZE_TWO_NEEDS: PackedStringArray = ["set_size", "fuzz_growth", "size_two_species", "remnants",
	"size_two_content"]
## The runner's tours (SwimBot.SiteTour) per bot: the groups of species whose sites it goes to meet,
## in order of want, the ticks it stays at each and how near it keeps to the site's creature (tm). The
## evading cells meet the rammers, which dart in and out of range; the kiters bite whichever M1
## creature is nearer and go on to the size-2 species when no M1 site is in reach.
const SIZE_TWO_TOURS := {
	"kiter": {"groups": [["rammer", "ambush_hunter"], ["lurker", "elder_rammer"]], "stay": 1800, "keep": 3.0},
	"evade": {"groups": [["rammer"], ["ambush_hunter"]], "stay": 3600, "keep": 3.0},
}
## An evading cell that eats plants forages instead of touring once its energy is below SIZE_TWO_HUNGRY
## of its capacity, until it is back to SIZE_TWO_FED.
const SIZE_TWO_HUNGRY := 0.5
const SIZE_TWO_FED := 0.9
const Q_SLACK := 1e-9                    ## q is exactly 1.0 at the entry size (Relationships.q_of)

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


func test_slow_at_size_two_no_creature_below_its_size_notices_tells_chases_or_hits_the_cell() -> void:
	var waits := Gates.s2_missing(SIZE_TWO_NEEDS)
	if not waits.is_empty():
		print("test-threat-fuzz: the size-2 runner waits on: %s" % "; ".join(waits))
		return
	var fz: Variant = Gates.new_fuzz()
	var pairs := {}   # species -> {"sensed": ticks, "bitten": hits by the cell}
	for pair in SIZE_TWO_PAIRS:
		pairs[pair[0]] = {"sensed": 0, "bitten": 0}
	var broken := PackedStringArray()
	for i in SIZE_TWO_SEEDS.size():
		var run := _size_two_run(fz, SIZE_TWO_SEEDS[i], SIZE_TWO_BOTS[i], SIZE_TWO_BODIES[i], pairs)
		broken.append_array(run.broken)
		print("test-threat-fuzz: size 2, seed %d (%s, %s): size %d at the end, %d deaths, %d sites met, %d of the cell's bites on creatures below it, %d checked by 14; %s" % [
			SIZE_TWO_SEEDS[i], SIZE_TWO_BOTS[i], SIZE_TWO_BODIES[i], run.size, run.deaths, run.sites, run.bites_below, run.checked, run.counts])
		check(int(run.sites) > 0, "size 2 seed %d: the cell's tour met at least one site" % SIZE_TWO_SEEDS[i])
	print("test-threat-fuzz: size 2 pairs: %s" % pairs)
	check_eq(str(fz.report()), "", "every invariant on every tick at size 2")
	check(broken.is_empty(), "invariant 14 broken %d times; first: %s" % [broken.size(), broken[0] if not broken.is_empty() else ""])
	for pair in SIZE_TWO_PAIRS:
		var p: Dictionary = pairs[pair[0]]
		check(int(p.sensed) >= SIZE_TWO_MIN_SENSED, "(%s, %d) had the cell in its senses on %d ticks (at least %d)" % [
			pair[0], pair[1], p.sensed, SIZE_TWO_MIN_SENSED])
		check(int(p.bitten) >= 1, "(%s, %d) was bitten by the cell (%d)" % [pair[0], pair[1], p.bitten])


func test_invariant_14_fails_a_creature_below_its_size_that_engages_the_cell() -> void:
	# Hand-built at size 2 on the pool's creatures (M1 species, entry size 1: q = 0.625): a target, a
	# notice, a tell, a strike or a hit on the cell fails; a flight, a percept or the same at size 1
	# does not.
	var r := Lineage.found(SEEDS[0], "test+dev", catalog, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	var c: CreatureField.Creature = sim.creatures.creatures[0]
	var known := {c.id: c.species_id}
	var p := CreatureField.PLAYER_ID
	var cases := [   # [what, target, events, size, fails]
		["calm", "", [], 2, false],
		["fleeing the cell", "", [{"type": "creature_fled", "id": c.id, "from": p}], 2, false],
		["holding the cell as its target", p, [], 2, true],
		["noticing the cell", "", [{"type": "creature_noticed", "id": c.id, "target": p, "by": "sight"}], 2, true],
		["telling at the cell", "", [{"type": "creature_tell", "id": c.id, "target": p}], 2, true],
		["striking at the cell", "", [{"type": "creature_strike", "id": c.id, "target": p}], 2, true],
		["hitting the cell", "", [{"type": "hit", "attacker": c.id, "target": p}], 2, true],
		["hit by the cell", "", [{"type": "hit", "attacker": p, "target": c.id}], 2, false],
		["holding the cell as its target at q == 1", p, [], 1, false],
		["telling at another creature", "", [{"type": "creature_tell", "id": c.id, "target": "c_99"}], 2, false],
	]
	for case in cases:
		c.brain.target = case[1]
		var out := broken_14(sim, case[3], case[2], known, case[0])
		check_eq(not out.is_empty(), case[4], "%s: %s" % [case[0], "fails" if case[4] else "passes"])
	c.brain.target = ""


## Invariant 14 on one tick at the cell's `size`: what broke it, as text. `known` maps every body id
## seen this tick (creatures before and after the step, and remnants) to its species, so a creature
## gone in the tick is still judged.
static func broken_14(sim: PoolSim, size: int, events: Array, known: Dictionary, where: String) -> PackedStringArray:
	var out := PackedStringArray()
	var p := CreatureField.PLAYER_ID
	for c: CreatureField.Creature in sim.creatures.creatures:
		if c.brain != null and c.brain.target == p and _below(sim, c.species_id, size):
			out.append("%s: %s (%s) at q < 1 holds the cell as its target in %s/%s" % [where, c.id, c.species_id, c.brain.state, c.brain.phase])
	for e in events:
		var type := str(e.get("type", ""))
		var who := ""
		if type in ["creature_noticed", "creature_tell", "creature_strike"] and str(e.get("target", "")) == p:
			who = str(e.get("id", ""))
		elif type == "hit" and str(e.get("target", "")) == p:
			who = str(e.get("attacker", ""))
		if who.is_empty() or not known.has(who):
			continue
		if _below(sim, str(known[who]), size):
			out.append("%s: %s (%s) at q < 1: %s on the cell" % [where, who, known[who], type])
	return out


static func _below(sim: PoolSim, species_id: String, size: int) -> bool:
	if not sim.species.has_species(species_id):
		return false
	return sim.species.q_of(species_id, size) < 1.0 - Q_SLACK


## One size-2 seed: the cell set to size 2 on its first tick, then SIZE_TWO_TICKS with `bot_name` on
## a SiteTour (the tour drives while it travels, the bot at each site), every tick through the
## checker and invariant 14. Adds to `pairs`; returns {"broken", "size", "deaths", "sites",
## "bites_below", "checked", "counts"}.
func _size_two_run(fz: Variant, seed_value: int, bot_name: String, body: String, pairs: Dictionary) -> Dictionary:
	var sim: Variant = Gates.make_sim(body, seed_value, true)
	sim.grace_until = sim.tick
	sim.drain_events()
	fz.start_run()
	var bot: Variant
	var plan: Dictionary = SIZE_TWO_TOURS[bot_name]
	var groups: Array[PackedStringArray] = []
	for group: Array in plan.groups:
		groups.append(PackedStringArray(group))
	var tour = SwimBot.SiteTour.new(groups, int(plan.stay), float(plan.keep))
	var forage = ForageBot.new()   # the evading cell's base, kept here for as long as the run
	forage.keys.trigger = ""       # the EvadeBot sends the keys
	forage.unjam = true
	if bot_name == "kiter":
		bot = KiterBot.new(seed_value)
		bot.bite_visits = true
	else:
		bot = EvadeBot.new()
		var hungry := [false]
		bot.base = func(s: PoolSim) -> SimIntent:
			if s.phenotype.can_eat("plant"):
				var share: float = s.state.energy / s.state.energy_capacity
				if share < SIZE_TWO_HUNGRY:
					hungry[0] = true
				elif share >= SIZE_TWO_FED:
					hungry[0] = false
				if hungry[0]:
					return forage.next_intent(s)
			var move: SimIntent = tour.next_move(s)
			return move if move != null else forage.next_intent(s)
	var out := {"broken": PackedStringArray(), "size": 0, "deaths": 0, "sites": 0, "bites_below": 0, "checked": 0,
		"counts": {}}
	var dead := {}
	var events: Array[Dictionary] = []
	for i in SIZE_TWO_TICKS:
		events.append_array(Gates.continue_after_death(sim, dead, fz))
		var t: int = sim.tick
		var was: Dictionary = fz.before(sim)
		var known := _species_of(sim)
		if i == 0:
			check(sim.debug_set_size(SIZE_TWO), "seed %d: the cell set to size 2" % seed_value)
		var intent: SimIntent
		if bot_name == "evade":
			intent = bot.next_intent(sim, events)
		else:
			var move: SimIntent = tour.next_move(sim)
			intent = bot.keys.apply(sim, move) if move != null else bot.next_intent(sim)
		sim.step(intent)
		events = sim.drain_events()
		var where := "size 2 seed %d tick %d" % [seed_value, t]
		fz.after(sim, events, t, where, was)
		known.merge(_species_of(sim))
		var size: int = sim.size()
		out.broken.append_array(broken_14(sim, size, events, known, where))
		out.checked += _tally(sim, size, events, known, pairs)
		for e in events:
			if e.type == "died":
				out.deaths += 1
			elif e.type == "hit" and e.attacker == CreatureField.PLAYER_ID and known.has(e.target) and _below(sim, known[e.target], size):
				out.bites_below += 1
	out.size = sim.size()
	out.sites = tour.visits
	out.counts = fz.counts.duplicate()
	return out


## Every body id of the tick -> its species: the creature field's and the remnants'.
static func _species_of(sim: Variant) -> Dictionary:
	var out := {}
	for c: CreatureField.Creature in sim.creatures.creatures:
		out[c.id] = c.species_id
	var remnants: Variant = sim.get("remnants")
	if remnants != null:
		for c in remnants.items:
			out[c.id] = c.species_id
	return out


## Non-vacuity of 14 on one tick: for each pair's species below the cell's size, the ticks one of its
## creatures had a percept of the cell from this tick and the cell's hits on one. Returns how many
## creatures at q < 1 the tick held.
static func _tally(sim: Variant, size: int, events: Array, known: Dictionary, pairs: Dictionary) -> int:
	var below := 0
	var sensed := {}
	for c: CreatureField.Creature in sim.creatures.creatures:
		if c.brain == null or not _below(sim, c.species_id, size):
			continue
		below += 1
		var seen: Dictionary = c.brain.seen.get(CreatureField.PLAYER_ID, {})
		if pairs.has(c.species_id) and not seen.is_empty() and int(seen.get("tick", -1)) == sim.tick - 1:
			sensed[c.species_id] = true
	for id in sensed:
		pairs[id].sensed += 1
	for e in events:
		if e.get("type", "") == "hit" and e.get("attacker", "") == CreatureField.PLAYER_ID:
			var sp := str(known.get(e.get("target", ""), ""))
			if pairs.has(sp) and _below(sim, sp, size):
				pairs[sp].bitten += 1
	return below


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
