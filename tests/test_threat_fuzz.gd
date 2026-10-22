extends TestCase
## The threat fuzz (plan section 18): KiterBot circles creature after creature in the real pool, with
## the real species, sites and niches, for 60 s on each of four seeds, and on every tick every
## creature is checked against the fairness and physics invariants below. The cell's start shelter
## is ended at once; a dead cell comes back at its checkpoint, with its real shelter, after
## DEATH_NOTICE_TICKS. The brains' own timers are never trusted to judge them: chase lengths, tells
## and senses are worked out again here from events, positions and CreatureSenses.
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
##     before the step) or was hurt by it within its memory
## 10  health and energy within range, for the cell and every creature
## 11  each niche counts exactly its live data creatures, within its cap

const KiterBot := preload("res://game/dev/kiter_bot.gd")
const SEEDS: Array[int] = [401, 402, 403, 404]
## The starting body of each seed's lineage: two jaws to wound creatures (flee), and the jawless grazer.
const BODIES: PackedStringArray = ["hunter", "omnivore", "grazer", "hunter"]
## Where each seed's cell starts: the checkpoint, then open water between the northern territories
## and the gap's lair, so most of each minute is spent among creatures rather than swimming to them.
const STARTS: Array[Vector2] = [Vector2.INF, Vector2(-10.0, -6.0), Vector2(0.0, -12.0), Vector2(10.0, -6.0)]
const RUN_TICKS := 3600                  ## 60 s per seed
const DEATH_NOTICE_TICKS := 90           ## a player reading the death notice before Continue
const ROCK_SLACK_M := 0.001
const LEASH_SLACK_M := 1e-3
const WALL_SLACK_M := 1e-4               ## PoolArena.CLEAR_EPSILON: float32 rounding at the limit
const SPEED_LIMIT := 6.0                 ## combat.max_speed_after_hit, the tunnelling bound (T10)
const SPEED_SLACK := 1e-4
const MIN_TELL_TICKS := 72               ## fairness F1: every tell lasts at least 1.2 s
const LANE_HEADING_SLACK := 1e-6         ## rad: a strike's heading is its lane's (both are the lock)
## m: how far a strike may start from the origin its tell's lane showed. The body brakes from rest
## through the tell, but a body leaning on it can still push it: the four seeds' worst is 0.446 m
## (seed 402, the z_n rammer c_4 pushed by its neighbour c_5 through its puff); most are under 0.03.
const LANE_DRIFT_M := 0.5
const LANE_HIT_SLACK := 1e-3             ## m: float32 positions
## The give-up fires on the exact tick it falls due, and a last tell may start the tick before.
const CHASE_SLACK_TICKS := 2
const STALL_TICKS := 150
const STALL_MIN_M := 0.25
const STALL_LABELS: PackedStringArray = ["chase/pursue", "forage/seek"]   ## and every wander/* phase
## Non-vacuity, over all seeds (plan section 18).
const MIN_TELLS := 10
const MIN_GIVE_UPS := 3
const MIN_HITS_ON_CELL := 1
const MIN_FLEES := 1

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog
var _bad := {}   ## invariant -> {"count", "first"}


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()
	_bad = {}


func test_kiting_round_the_real_creatures_for_four_minutes_breaks_no_fairness_or_physics_rule_on_any_tick() -> void:
	var totals := {"tells": 0, "strikes": 0, "hits_on_cell": 0, "give_ups": 0, "flees": 0}
	for i in SEEDS.size():
		var counts := _fuzz(SEEDS[i], BODIES[i], STARTS[i])
		print("test-threat-fuzz: seed %d (%s): %d tells, %d strikes, %d hits on the cell, %d by the cell, %d give-ups, %d flees, %d notices, %d cell deaths, %d creature deaths, %d visits; strikes up to %.3f m from their lanes' origins" % [
			SEEDS[i], BODIES[i], counts.tells, counts.strikes, counts.hits_on_cell, counts.hits_by_cell, counts.give_ups,
			counts.flees, counts.notices, counts.deaths, counts.creature_deaths, counts.visits, counts.drift])
		for key in totals.keys():
			totals[key] += int(counts[key])
	for inv in range(1, 12):
		if _bad.has(inv):
			check(false, "invariant %d broken %d times; first: %s" % [inv, _bad[inv].count, _bad[inv].first])
	check(totals.tells >= MIN_TELLS, "at least %d tells over all seeds (%d)" % [MIN_TELLS, totals.tells])
	check(totals.give_ups >= MIN_GIVE_UPS, "at least %d give-ups (%d)" % [MIN_GIVE_UPS, totals.give_ups])
	check(totals.hits_on_cell >= MIN_HITS_ON_CELL, "at least %d hit on the cell (%d)" % [MIN_HITS_ON_CELL, totals.hits_on_cell])
	check(totals.flees >= MIN_FLEES, "at least %d flee (%d)" % [MIN_FLEES, totals.flees])


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
	var counts := {"tells": 0, "strikes": 0, "hits_on_cell": 0, "hits_by_cell": 0, "give_ups": 0, "flees": 0,
		"notices": 0, "deaths": 0, "creature_deaths": 0, "visits": 0, "drift": 0.0}
	var k := {
		"tell_at": {}, "tell_since": {}, "striking": {}, "strike_hits": {}, "engaged_from": {}, "noticed_at": {},
		"hurt_by_cell": {}, "label": {}, "label_since": {}, "visit": {}, "ring": {}, "lane": {}, "strike_lane": {},
	}
	var dead_since := -1
	for i in RUN_TICKS:
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS:
				sim.respawn_player()
				dead_since = -1
				# Cancelled strikes and the respawn itself, before the next step.
				_take_events(sim, sim.drain_events(), sim.tick, "seed %d respawn at %d" % [seed_value, sim.tick], k, counts)
		var before := _before(sim)
		var t := sim.tick
		sim.step(bot.next_intent(sim))
		var where := "seed %d tick %d" % [seed_value, t]
		_take_events(sim, sim.drain_events(), t, where, k, counts)
		_check_bodies(sim, where)
		_check_creatures(sim, t, where, before, k)
	counts.visits = bot.visits
	return counts


## What invariant 9 needs from before the step: each creature's target and where it looked from, and
## the cell's body as creatures may perceive it.
func _before(sim: PoolSim) -> Dictionary:
	var looks := {}
	for c in sim.creatures.creatures:
		if c.brain != null:
			looks[c.id] = {"target": c.brain.target, "position": c.motion.position, "heading": c.motion.heading}
	var cell := {"id": CreatureField.PLAYER_ID, "species": SpeciesCatalog.PLAYER_SPECIES, "position": sim.motion.position,
		"velocity": sim.motion.velocity, "radius": sim.phenotype.radius, "alive": not sim.dead,
		"concealed": sim.dev_hidden or sim.tick < sim.grace_until, "engageable": true}
	return {"looks": looks, "cell": cell}


## Invariants 2 (lanes), 4, 5 and the starts of 6 and 9, from the tick's events in their order.
func _take_events(sim: PoolSim, events: Array[Dictionary], t: int, where: String, k: Dictionary, counts: Dictionary) -> void:
	for e in events:
		match str(e.type):
			"creature_tell":
				counts.tells += 1
				k.tell_at[e.id] = t
				k.lane[e.id] = e.lane
				var c := sim.creatures.find(e.id)
				if c != null and c.brain != null:
					var lane: Dictionary = e.lane
					var disc := CreatureBrain.leash_disc(c.brain)
					var end: Vector2 = Vector2(lane.origin) + Vector2.from_angle(float(lane.heading)) * float(lane.travel)
					var past: float = end.distance_to(disc.center) - float(disc.radius)
					if past > LEASH_SLACK_M:
						_fail(2, "%s: %s's tell lane ends %.3f m past its leash" % [where, e.id, past])
			"creature_strike":
				counts.strikes += 1
				var c := sim.creatures.find(e.id)
				var tell: int = c.brain.cfg.attack.tell_ticks if c != null and c.brain != null else MIN_TELL_TICKS
				if tell < MIN_TELL_TICKS:
					_fail(4, "%s: %s's tell is %d ticks, under %d" % [where, e.id, tell, MIN_TELL_TICKS])
				if int(k.tell_at.get(e.id, -1)) != t - tell or int(k.tell_since.get(e.id, -1)) != t - tell:
					_fail(4, "%s: %s struck with its tell at tick %d and attack/tell held since %d (wanted %d)" % [
						where, e.id, int(k.tell_at.get(e.id, -1)), int(k.tell_since.get(e.id, -1)), t - tell])
				k.striking[e.id] = true
				k.strike_hits[e.id] = 0
				_check_strike_lane(e, where, k, counts)
			"creature_recovered":
				k.striking.erase(e.id)
				k.lane.erase(e.id)
				k.strike_lane.erase(e.id)
			"hit":
				if e.target == CreatureField.PLAYER_ID:
					counts.hits_on_cell += 1
				if e.attacker == CreatureField.PLAYER_ID:
					counts.hits_by_cell += 1
					k.hurt_by_cell[e.target] = t
					continue
				if not k.striking.has(e.attacker) or int(k.strike_hits.get(e.attacker, 0)) > 0:
					_fail(5, "%s: %s hit %s outside a strike or twice in one (%d before)" % [
						where, e.attacker, e.target, int(k.strike_hits.get(e.attacker, 0))])
				k.strike_hits[e.attacker] = int(k.strike_hits.get(e.attacker, 0)) + 1
				var shown: Dictionary = k.strike_lane.get(e.attacker, {})
				if e.target == CreatureField.PLAYER_ID and not shown.is_empty() \
						and not CreatureBrain.lane_contains(_grown(shown.lane, float(shown.drift) + LANE_HIT_SLACK), e.position):
					_fail(5, "%s: %s hit the cell at %s, outside the lane its tell showed (%s)" % [where, e.attacker, e.position, shown.lane])
				k.engaged_from[e.attacker] = t   # a landed hit restarts the give-up timer
			"creature_noticed":
				counts.notices += 1
				k.engaged_from[e.id] = t
				k.noticed_at[e.id] = t
			"creature_gave_up":
				counts.give_ups += 1
			"creature_fled":
				counts.flees += 1
			"died":
				counts.deaths += 1
			"creature_died":
				counts.creature_deaths += 1


## Invariant 4's lane: the strike runs along the lane its tell showed. Its heading is the lane's, and
## it starts within LANE_DRIFT_M of the lane's origin. Keeps the lane and that drift for invariant 5.
func _check_strike_lane(e: Dictionary, where: String, k: Dictionary, counts: Dictionary) -> void:
	var lane: Dictionary = k.lane.get(e.id, {})
	k.lane.erase(e.id)
	if lane.is_empty():
		_fail(4, "%s: %s struck with no tell lane" % [where, e.id])
		return
	var off := absf(angle_difference(float(e.heading), float(lane.heading)))
	if off > LANE_HEADING_SLACK:
		_fail(4, "%s: %s struck %.2f degrees off the lane its tell showed" % [where, e.id, rad_to_deg(off)])
	var drift: float = Vector2(e.position).distance_to(lane.origin)
	counts.drift = maxf(float(counts.drift), drift)
	if drift > LANE_DRIFT_M:
		_fail(4, "%s: %s struck from %.3f m off its lane's origin" % [where, e.id, drift])
	k.strike_lane[e.id] = {"lane": lane, "drift": drift}


## The lane grown by `m` on every side: the origin moved back, the length and half-width added to.
static func _grown(lane: Dictionary, m: float) -> Dictionary:
	var heading := float(lane.heading)
	return {"origin": Vector2(lane.origin) - Vector2.from_angle(heading) * m, "heading": heading,
		"length": float(lane.length) + 2.0 * m, "half_width": float(lane.half_width) + m}


## Invariants 1 and 10 for the cell, and 8 and 11 over all creatures.
func _check_bodies(sim: PoolSim, where: String) -> void:
	if not sim.dead:
		_check_motion("the cell", sim.motion, sim.phenotype.radius, sim.arena, where)
		_check_condition("the cell", sim.state, where)
	var engaged := PackedStringArray()
	var live := {}
	for c in sim.creatures.creatures:
		if c.brain != null and c.brain.target == CreatureField.PLAYER_ID \
				and (c.brain.state == CreatureBrain.CHASE or c.brain.state == CreatureBrain.ATTACK):
			engaged.append(c.id)
		if not c.debug:
			live[c.role] = int(live.get(c.role, 0)) + 1
	if engaged.size() > 1:
		_fail(8, "%s: %s all engaged on the cell" % [where, engaged])
	# The token list itself: within its limit, and holding every creature engaged on the cell.
	var token := sim.creatures.engaged_on_player
	if token.size() > int(species.fairness.max_engaged_on_player):
		_fail(8, "%s: the token list holds %s" % [where, token])
	for id in engaged:
		if not token.has(id):
			_fail(8, "%s: %s is engaged on the cell without the token (%s)" % [where, id, token])
	for role in sim.region.niches:
		var niche: Dictionary = sim.region.niches[role]
		if int(niche.count) != int(live.get(role, 0)) or int(niche.count) > int(niche.cap):
			_fail(11, "%s: niche %s counts %d of %d with %d live" % [where, role, int(niche.count), int(niche.cap), int(live.get(role, 0))])


## Invariants 1-3, 6, 7, 9 and 10 for each creature after the step.
func _check_creatures(sim: PoolSim, t: int, where: String, before: Dictionary, k: Dictionary) -> void:
	var checkpoint: Vector2 = sim.checkpoint().position
	var clear_m := float(species.fairness.respawn_clear_m)
	for c in sim.creatures.creatures:
		var who := "%s (%s)" % [c.id, c.species_id]
		_check_motion(who, c.motion, c.phenotype.radius, sim.arena, where)
		_check_condition(who, c.state, where)
		if not c.debug and checkpoint.distance_to(c.motion.position) - c.phenotype.radius < clear_m:
			_fail(3, "%s: %s is %.2f m from the checkpoint" % [where, who, checkpoint.distance_to(c.motion.position) - c.phenotype.radius])
		if c.brain == null:
			continue
		var b := c.brain
		var disc := CreatureBrain.leash_disc(b)
		var out: float = c.motion.position.distance_to(disc.center) - float(disc.radius)
		if out > LEASH_SLACK_M:
			_fail(2, "%s: %s in %s/%s is %.4f m past its leash" % [where, who, b.state, b.phase, out])
		var label := "%s/%s" % [b.state, b.phase]
		var was := str(k.label.get(c.id, ""))
		# Invariant 4's other half: how long attack/tell has held without a break.
		if label == "attack/tell":
			if was != "attack/tell":
				k.tell_since[c.id] = t
		else:
			k.tell_since.erase(c.id)
		_check_engagement(c, t, where, was, k)
		_check_stall(c, t, where, label, k)
		var looked: Dictionary = before.looks.get(c.id, {})
		if b.target == CreatureField.PLAYER_ID and not looked.is_empty() and looked.target != CreatureField.PLAYER_ID:
			_check_sensed(c, t, where, looked, before.cell, sim.arena, k)
		k.label[c.id] = label


## Invariant 6: the engagement started at a notice, a chase from rest or the creature's own hit.
func _check_engagement(c: CreatureField.Creature, t: int, where: String, was: String, k: Dictionary) -> void:
	var b := c.brain
	var attack: Dictionary = b.cfg.attack
	var engaged := b.state == CreatureBrain.CHASE or b.state == CreatureBrain.ATTACK
	var was_engaged := was.begins_with("chase/") or was.begins_with("attack/") or was.begins_with("notice")
	if engaged and not was_engaged:
		k.engaged_from[c.id] = t   # into a chase from rest (watching) or from nothing
	if engaged:
		var bound: int = int(b.cfg.give_up_ticks) + int(attack.tell_ticks) + int(attack.burst_ticks) + int(attack.glide_ticks) \
			+ maxi(int(attack.recover_ticks), int(attack.blocked_recover_ticks)) + CHASE_SLACK_TICKS
		var lasted: int = t - int(k.engaged_from.get(c.id, t))
		if lasted > bound:
			_fail(6, "%s: %s engaged %d ticks (bound %d) in %s/%s" % [where, c.id, lasted, bound, b.state, b.phase])
	elif b.state == CreatureBrain.NOTICE:
		var notice_bound: int = int(b.cfg.notice_ticks) + int(b.cfg.give_up_ticks) + CHASE_SLACK_TICKS
		var noticed: int = t - int(k.noticed_at.get(c.id, t))
		if noticed > notice_bound:
			_fail(6, "%s: %s noticing %d ticks (bound %d)" % [where, c.id, noticed, notice_bound])


## Invariant 7: one leg (the same phase visit, by its start tick, and the same goal, by the tick it
## was set) for STALL_TICKS moves the creature. A new goal starts a new leg like a new phase does: a
## patrol that times out and turns back for another point is not a stall, while a meal drifting
## under the same goal is the same leg. Each creature's last STALL_TICKS + 1 positions are kept in a
## ring.
func _check_stall(c: CreatureField.Creature, t: int, where: String, label: String, k: Dictionary) -> void:
	var visit := "%s@%d/%d" % [label, c.brain.phase_tick, c.brain.goal_tick]
	if str(k.visit.get(c.id, "")) != visit:
		k.visit[c.id] = visit
		k.label_since[c.id] = t
	if not k.ring.has(c.id):
		var fresh := []
		fresh.resize(STALL_TICKS + 1)
		k.ring[c.id] = fresh
	var ring: Array = k.ring[c.id]
	ring[t % ring.size()] = c.motion.position
	if not (STALL_LABELS.has(label) or label.begins_with("wander/")):
		return
	var since: int = k.label_since[c.id]
	if t - since < STALL_TICKS:
		return
	var from: Vector2 = ring[(t - STALL_TICKS) % ring.size()]
	if from.distance_to(c.motion.position) < STALL_MIN_M:
		_fail(7, "%s: %s in %s for %d ticks moved %.3f m in the last %d" % [where, c.id, label, t - since,
			from.distance_to(c.motion.position), STALL_TICKS])


## Invariant 9: CreatureSenses again, from where the creature looked before the step, on the cell's
## body alone (other bodies never hide it; only rocks do).
func _check_sensed(c: CreatureField.Creature, t: int, where: String, looked: Dictionary, cell: Dictionary, arena: PoolArena,
		k: Dictionary) -> void:
	var senses: Dictionary = species.species[c.species_id].senses
	var viewer := {"id": c.id, "species": c.species_id, "position": looked.position, "heading": looked.heading,
		"radius": c.phenotype.radius, "sight": c.phenotype.sight, "fov": deg_to_rad(float(senses.fov_deg)),
		"near": float(senses.near_m)}
	if not CreatureSenses.perceive(viewer, [cell], arena).is_empty():
		return
	var hurt: int = int(k.hurt_by_cell.get(c.id, -1))
	if hurt >= 0 and t - hurt <= int(c.brain.cfg.memory_ticks):
		return
	_fail(9, "%s: %s targeted the cell without sensing it (hurt by it at %d)" % [where, c.id, hurt])


## Invariant 1 for one body.
func _check_motion(who: String, m: Locomotion.MotionState, r: float, arena: PoolArena, where: String) -> void:
	if not m.position.is_finite() or not m.velocity.is_finite():
		_fail(1, "%s: %s at %s moving %s" % [where, who, m.position, m.velocity])
		return
	for rock in arena.rocks:
		var dig: float = float(rock.radius) + r - m.position.distance_to(rock.center)
		if dig > ROCK_SLACK_M:
			_fail(1, "%s: %s %.4f m into %s" % [where, who, dig, rock.id])
	if m.position.length() > arena.hard_radius - r + WALL_SLACK_M:
		_fail(1, "%s: %s past the hard limit (%.4f m from the center)" % [where, who, m.position.length()])
	if m.velocity.length() > SPEED_LIMIT + SPEED_SLACK:
		_fail(1, "%s: %s at %.3f m/s" % [where, who, m.velocity.length()])


## Invariant 10 for one body.
func _check_condition(who: String, s: ActorState, where: String) -> void:
	if s.health < 0.0 or s.health > s.max_health or s.energy < 0.0 or s.energy > s.energy_capacity:
		_fail(10, "%s: %s health %.3f of %.3f, energy %.3f of %.3f" % [where, who, s.health, s.max_health, s.energy, s.energy_capacity])


## Records a broken invariant: its first message and how often it broke.
func _fail(inv: int, text: String) -> void:
	if not _bad.has(inv):
		_bad[inv] = {"count": 0, "first": text}
	_bad[inv].count += 1
