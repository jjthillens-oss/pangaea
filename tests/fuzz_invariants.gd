extends RefCounted
## The fuzz invariants (S1 core 8.7), checked after every tick of a swim. A run calls start_run() on
## a new sim, then before(sim) before each step and after(...) with the step's drained events; `bad`
## holds every broken invariant (count and first case) across runs, and `counts` the run's
## non-vacuity counters. The brains' own timers are never trusted to judge them: chase lengths,
## tells and senses are worked out again here from events, positions and CreatureSenses.
##
## Every sim (M1, moved here unchanged from test_threat_fuzz; in the endless world restated as S1
## core 8.7 says):
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
##     creature 0.25 m (endless: awake creatures, the window starting afresh when one wakes, and a
##     creature that got 0.25 m away within the window and came back has moved: _went_away)
##  8  at most one creature engaged (chase or attack) on the cell, and the token list within its limit
##     and holding every engaged creature
##  9  a creature that first targets the cell sensed it on that tick (CreatureSenses, from the bodies
##     before the step) or was hurt by it within its memory; and on every tick, whatever the creature
##     is doing, any change to its memory of the cell is a percept its senses give from where it
##     looked before the step (the same sense, position and velocity) or a hurt by the cell then
## 10  health and energy within range, for the cell and every creature
## 11  each niche counts exactly its live data creatures, within its cap
##
## The endless world (from the cell's point of view; "in view" is inside the widest view's footprint
## grown by the spawn margin plus the object's radius, as the spawn check measures):
## 12  nothing appears in or vanishes from view: a creature that spawns, wakes, sleeps or leaves
##     (unloaded, evicted, stuck) is at least spawn_safe_m from the cell and out of view (one that
##     spawns while the cell is dead, from the checkpoint as well: the respawn looks there); every shell,
##     zone, anchor and place of a chunk that loads or unloads is out of view; a zone that joins or
##     leaves the food view is out of view; no zone gains more than one plankton item in a tick; a
##     plankton item of a zone that left the food view, and a carrion item gone with no expiry or meal
##     naming it, went out of view.
##     Block-step events (chunks, sleep, wake, eviction, "unloaded", the food view) are measured from
##     the cell before the step, M1-step events (spawns, "stuck") from the cell after it. A tick with a
##     respawn or a dev teleport is a camera cut: step 0's own events (up to and including respawned or
##     debug teleport_abs) and its fill at once are exempt (D-10, D-11, C-9), and everything after is
##     measured from the cell after the step; a teleport cut's food drops are its own too (C-10).
## 13  every position the sim stores (the explicit list of core 8.7) is under 256 tm long.
## 16  every sleeper is at least spawn_safe_m from the cell and out of its view.
##
## S3 (D-141, BP3-4, BP3-20; s3-sim 3.12):
##  3  at a landmark checkpoint (the run's last checkpoint change a checkpoint_moved of reason
##     "landmark", until a growth moves it) only the creatures at q == 1 at the cell's size count.
##  5  a hazard's sting is no strike: invariant 15 judges it.
##  7  a hazard form: a hazard DRIFT_SETTLE_TICKS in DRIFT lies within 1.0 x q tm of its drift goal.
## 12  a morsel site's carrion_spawned is an M1-step event (at least spawn_safe_m from the cell and out
##     of view, from the checkpoint too while dead); a carrion_expired "unloaded" off a growth tick is
##     a block-step event (out of view); after every step morsel_claims() is the number of morsel-site
##     entries holding an item (S3G17d).
## 15  stings on the cell: (a) in any STING_WINDOW_TICKS at most floor(window / the least hazard
##     cooldown) + 1, each dealing under max_single_hit_share x the smallest starting health; (b) no
##     sting within STING_WINDOW_TICKS of a strike hit on the cell, either first; (c) no sting whose
##     `engaged` (the token holders when it landed, BP3-4) is non-empty. A debug set_size clears the
##     windows, as it clears the sim's own fields (BP3-20); a respawn does not.
## Invariant 14 (test_threat_fuzz.broken_14) counts a sting from a q < 1 hazard as a hit on the cell.
##
## Each event's positions are in the frame in force at its place in the list: a rebased changes it.
## The positions kept from before the step (where each creature looked, its lane, its stall ring) move
## with the tick's rebases, as the sim's own do.
##
## Sizes (S2, BP-2). Positions are compared in absolute am: a local p in the frame (origin, k) is
## origin + p k, a chunk's stored tm is x tm_to_am(its size), and a distance is the am difference
## divided by the k of the point it is measured from: before()'s k for the cell before the step, the
## current k for the cell after it, so "in view" and spawn_safe_m are in that size's tm. A
## `debug set_size` is a cut like a respawn or a dev teleport (its events up to it are its own). A
## growth tick (its events hold growth_began) re-expresses the world: before `grew` its conversions,
## its morsels, its "growth" unloads, its loads and the plankton it turns to haze are exempt, while
## its sleepers that leave ("growth") and its carrion that expires are checked from the cell before
## the step at the old size; `grew` moves the frame to growth_began's centre_am at the new size, and
## every later event of the tick is checked from the cell after the step. The food view's zone checks
## and its plankton half are skipped on a growth tick. Remnants, two-post brains' posts and the site
## records' posts join invariant 13.

const LEASH_SLACK_M := 1e-3
const ROCK_SLACK_M := 0.001
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
const LOCAL_BOUND := 256.0
const PLACE_RADIUS_TM := 4.0           ## core 8.7: a place's extent
const ANCHOR_RADIUS_BU := 3.0          ## core 8.7: an anchor's extent, times the band's bu-to-tm
## Reasons a creature leaves that the player must not see happen.
const STING_WINDOW_TICKS := 120         ## invariant 15's window and the sting/strike gap (D-126)
const DRIFT_SETTLE_TICKS := 120         ## invariant 7's hazard form: ticks in DRIFT before it is held
const HIDDEN_REMOVALS := {"unloaded": "block", "evicted": "block", "stuck": "step", "growth": "block", "remnant_left": "step"}

var bad := {}      ## invariant -> {"count": int, "first": String}, across runs
var counts := {}   ## the run's non-vacuity counters
var k := {}        ## the run's bookkeeping: tells, lanes, strikes, engagements, stall rings, ...
var species: SpeciesCatalog
var layout: PoolLayout
var _quad := PackedVector2Array()   ## the widest view's footprint round (0, 0)
var _margin := 0.0                  ## look-ahead plus the spawn gap
var _safe := 0.0
var _endless := false                ## the sim checked last has a world (invariant 7's restated measure)
var _sting_cap := 0                  ## invariant 15 (a): stings allowed in a window (0: no hazard species)
var _sting_damage_limit := -1.0      ## invariant 15 (a): max_single_hit_share x the smallest starting health


func _init(p_species: SpeciesCatalog, p_layout: PoolLayout) -> void:
	species = p_species
	layout = p_layout
	var fairness := species.fairness
	_quad = ViewFootprint.corners(Vector2.ZERO, layout.camera, float(layout.camera.zoom_max), float(fairness.spawn_view_aspect))
	_margin = float(layout.camera.look_ahead_max) + float(fairness.spawn_view_margin_m)
	_safe = float(fairness.spawn_safe_m)
	var least := 0
	for id: String in species.species:
		var hz: Dictionary = species.species[id].get("hazard", {})
		if not hz.is_empty():
			var cd := CreatureBrain.ticks(float(hz.threads.cooldown_s))
			least = cd if least == 0 else mini(least, cd)
	if least > 0:
		_sting_cap = STING_WINDOW_TICKS / least + 1
	start_run()


## A new run (a new sim): the counters and the bookkeeping start again; `bad` is kept.
func start_run() -> void:
	counts = {"tells": 0, "strikes": 0, "hits_on_cell": 0, "hits_by_cell": 0, "give_ups": 0, "flees": 0,
		"notices": 0, "deaths": 0, "creature_deaths": 0, "visits": 0, "drift": 0.0, "memory_checks": 0,
		"checked": 0, "spawns": 0, "sleeps": 0, "wakes": 0, "loads": 0, "unloads": 0, "evictions": 0,
		"zone_changes": 0, "rebases": 0, "cuts": 0, "growths": 0, "set_sizes": 0, "after_growth": 0,
		"stings": 0, "strike_hits_on_cell": 0, "morsel_spawns": 0, "morsel_unloads": 0, "drift_checks": 0}
	k = {
		"tell_at": {}, "tell_since": {}, "striking": {}, "strike_hits": {}, "engaged_from": {}, "noticed_at": {},
		"hurt_by_cell": {}, "label": {}, "label_since": {}, "visit": {}, "ring": {}, "lane": {}, "strike_lane": {},
		"memory_checks": 0,
		"stings": [], "strike_hit_ticks": [], "landmark_checkpoint": false, "drift_since": {},
	}


## "inv 12: 3 (first: …)" lines, by invariant; "" when every invariant held.
func report() -> String:
	var lines := PackedStringArray()
	var invs := bad.keys()
	invs.sort()
	for inv in invs:
		lines.append("inv %d: %d (first: %s)" % [inv, bad[inv].count, bad[inv].first])
	return "\n".join(lines)


## What `after` needs from before the step: invariant 9's looks and the cell's body; in the endless
## world also the frame and its k (tm to am) and size, the cell (local and absolute am), the loaded
## chunks, the food view, every plankton and carrion item, every creature's radius and every
## remnant's position and radius.
func before(sim: PoolSim) -> Dictionary:
	var was := _before(sim) if sim.creatures != null else {"looks": {}, "cell": {}}
	if sim.world == null:
		return was
	var w := sim.world
	var chunks := {}
	for key in w.loaded_keys():
		chunks[key] = w.chunk(key)
	var zones := {}
	for z in sim.region.zones:
		zones[z.id] = {"center": z.center, "radius": float(z.radius)}
	var plankton := {}
	for item in sim.plankton.items:
		plankton[item.id] = {"zone": item.zone, "position": item.position}
	var carrion := {}
	for item in sim.carrion.items:
		carrion[item.id] = item.position
	var radii := {}
	if sim.creatures != null:
		for c in sim.creatures.creatures:
			radii[c.id] = c.phenotype.radius
	var remnants := {}
	if sim.remnants != null:
		for r in sim.remnants.items:
			remnants[r.id] = {"position": r.motion.position, "radius": r.phenotype.radius}
	was.merge({"origin": PackedFloat64Array([w.origin_x_am, w.origin_y_am]), "cell_at": sim.motion.position, "dead": sim.dead,
		"k": w._tm_to_am, "size": w.size, "cell_am": w.abs_of_local(sim.motion.position), "remnants": remnants,
		"checkpoint": w.checkpoint_local(),
		"chunks": chunks, "active": sim.plankton.active_zones.duplicate(), "zones": zones, "plankton": plankton,
		"pending": sim.plankton.pending_fill.duplicate(), "carrion": carrion, "radii": radii})
	return was


## Checks the tick that `events` came from (`t` its number, `where` names it in a failure) against
## `was`, what `before` returned before it: invariants 1 to 11, then in the endless world 12, 13, 16.
func after(sim: PoolSim, events: Array[Dictionary], t: int, where: String, was: Dictionary) -> void:
	_endless = sim.world != null
	if sim.world != null:
		_follow_rebases(events, was)
	for e in events:
		if e.type == "checkpoint_moved":
			k.landmark_checkpoint = str(e.get("reason", "")) == "landmark"
		elif e.type == "grew":
			k.landmark_checkpoint = false
	if sim.creatures != null:
		take_events(sim, events, t, where)
		check_15(sim, events, t, where)
		_check_bodies(sim, where)
		_check_creatures(sim, t, where, was, k)
		counts.memory_checks = k.memory_checks
	if sim.world != null:
		_check_12(sim, events, t, where, was)
		_check_13(sim, where)
		_check_16(sim, where)


## Events drained outside a step (a respawn's in the pool) for invariants 2, 4, 5 and the starts of
## 6 and 9.
func take_events(sim: PoolSim, events: Array[Dictionary], t: int, where: String) -> void:
	_take_events(sim, events, t, where, k, counts)


## The positions kept from before the step move with the tick's rebases (all of M1 runs after the
## streaming block, in the last frame).
func _follow_rebases(events: Array[Dictionary], was: Dictionary) -> void:
	var by := Vector2.ZERO
	for e in events:
		if e.type == "rebased":
			by += Vector2(e.offset_tm)
	if by == Vector2.ZERO:
		return
	for id in was.looks:
		var look: Dictionary = was.looks[id]
		look.position -= by
		if look.memory.has("position"):
			look.memory.position -= by
	if was.cell.has("position"):
		was.cell.position -= by
	for id in k.lane:
		k.lane[id].origin -= by
	for id in k.strike_lane:
		k.strike_lane[id].lane.origin -= by
	for id in k.ring:
		var ring: Array = k.ring[id]
		for i in ring.size():
			if ring[i] != null:
				ring[i] -= by


## Records a broken invariant: its first message and how often it broke.
func _fail(inv: int, text: String) -> void:
	if not bad.has(inv):
		bad[inv] = {"count": 0, "first": text}
	bad[inv].count += 1


# --- 1 to 11 (moved from test_threat_fuzz) ---

## What invariant 9 needs from before the step: each creature's target, where it looked from and
## what it remembered of the cell, and the cell's body as creatures may perceive it.
func _before(sim: PoolSim) -> Dictionary:
	var looks := {}
	for c in sim.creatures.creatures:
		if c.brain != null:
			looks[c.id] = {"target": c.brain.target, "position": c.motion.position, "heading": c.motion.heading,
				"memory": _sensed_part(c.brain.seen.get(CreatureField.PLAYER_ID, {}))}
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
				if str(e.get("kind", "")) == "sting":
					continue   # a hazard's sting is no strike: invariant 15 judges it
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
		var counted: bool = not k.landmark_checkpoint or sim.species.q_of(c.species_id, sim.size()) == 1.0
		if not c.debug and counted and checkpoint.distance_to(c.motion.position) - c.phenotype.radius < clear_m:
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
		if b.behavior == CreatureBrain.HAZARD:
			_check_drift(sim, c, t, where, k)
		var looked: Dictionary = before.looks.get(c.id, {})
		if b.target == CreatureField.PLAYER_ID and not looked.is_empty() and looked.target != CreatureField.PLAYER_ID:
			_check_sensed(c, t, where, looked, before.cell, sim.arena, k, sim.creatures)
		var memory := _sensed_part(b.seen.get(CreatureField.PLAYER_ID, {}))
		if not looked.is_empty() and not memory.is_empty() and memory != looked.memory:
			_check_memory(c, t, where, looked, before.cell, sim.arena, k, sim.creatures)
		k.label[c.id] = label


## Invariant 7's hazard form (D-141): after DRIFT_SETTLE_TICKS in DRIFT (awake), a hazard lies within
## 1.0 x q tm of CreatureBrain.drift_goal at the tick.
func _check_drift(sim: PoolSim, c: CreatureField.Creature, t: int, where: String, k: Dictionary) -> void:
	if c.asleep or c.brain.state != CreatureBrain.DRIFT:
		k.drift_since.erase(c.id)
		return
	if not k.drift_since.has(c.id):
		k.drift_since[c.id] = t
	if t - int(k.drift_since[c.id]) < DRIFT_SETTLE_TICKS:
		return
	counts.drift_checks += 1
	var q := sim.species.q_of(c.species_id, sim.size())
	var off := c.motion.position.distance_to(CreatureBrain.drift_goal(c.brain, t))
	if off > 1.0 * q:
		_fail(7, "%s: %s (%s) %d ticks in drift is %.3f tm from its drift goal (bound %.3f)" % [where, c.id,
			c.species_id, t - int(k.drift_since[c.id]), off, q])


## Invariant 15 on the tick's events (`t` the tick, `where` names it in a failure): the stings on the
## cell and the strike hits on it, in order; a debug set_size clears both windows first (BP3-20).
func check_15(sim: PoolSim, events: Array[Dictionary], t: int, where: String) -> void:
	var stings: Array = k.stings
	var strikes: Array = k.strike_hit_ticks
	for e in events:
		if e.type == "debug" and str(e.get("command", "")) == "set_size":
			stings.clear()
			strikes.clear()
			continue
		if e.type != "hit" or e.target != CreatureField.PLAYER_ID or e.attacker == CreatureField.PLAYER_ID:
			continue
		if str(e.get("kind", "")) != "sting":
			counts.strike_hits_on_cell += 1
			for s: int in stings:
				if t - s < STING_WINDOW_TICKS:
					_fail(15, "%s: (b) %s hit the cell %d ticks after a sting" % [where, e.attacker, t - s])
					break
			strikes.append(t)
			continue
		counts.stings += 1
		if not (e.get("engaged", []) as Array).is_empty():
			_fail(15, "%s: (c) %s stung the cell with %s engaged on it" % [where, e.attacker, e.engaged])
		if float(e.damage) >= _damage_limit(sim):
			_fail(15, "%s: (a) %s's sting dealt %.3f (limit %.3f)" % [where, e.attacker, float(e.damage), _damage_limit(sim)])
		for s: int in strikes:
			if t - s < STING_WINDOW_TICKS:
				_fail(15, "%s: (b) %s stung the cell %d ticks after a strike hit" % [where, e.attacker, t - s])
				break
		stings.append(t)
		var n := 0
		for s: int in stings:
			if t - s < STING_WINDOW_TICKS:
				n += 1
		if n > _sting_cap:
			_fail(15, "%s: (a) %d stings in %d ticks (at most %d)" % [where, n, STING_WINDOW_TICKS, _sting_cap])
	k.stings = stings.filter(func(s: int) -> bool: return t - s < STING_WINDOW_TICKS)
	k.strike_hit_ticks = strikes.filter(func(s: int) -> bool: return t - s < STING_WINDOW_TICKS)


## max_single_hit_share x the smallest starting health (rule 14 (b)'s limit), worked out once.
func _damage_limit(sim: PoolSim) -> float:
	if _sting_damage_limit < 0.0:
		var bodies := SpeciesCatalog._starting_bodies(PartCatalog.load_from())
		_sting_damage_limit = float(species.fairness.max_single_hit_share) * float(bodies.smallest_health)
	return _sting_damage_limit


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
	if c.asleep:   # endless: a sleeper has no window, and one starts afresh when it wakes
		k.visit.erase(c.id)
		k.ring.erase(c.id)
		return
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
		if _endless and _went_away(ring, from):
			return
		_fail(7, "%s: %s in %s for %d ticks moved %.3f m in the last %d" % [where, c.id, label, t - since,
			from.distance_to(c.motion.position), STALL_TICKS])


## Invariant 7 restated for the endless world: a creature that got STALL_MIN_M from where it was
## STALL_TICKS ago and came back moved (a rammer backing off for its run-up, then charging); one
## that never got that far is stuck. The pool keeps M1's measure, from end to end.
static func _went_away(ring: Array, from: Vector2) -> bool:
	for p in ring:
		if p != null and from.distance_to(p) >= STALL_MIN_M:
			return true
	return false


## Invariant 9: CreatureSenses again, from where the creature looked before the step, on the cell's
## body alone (other bodies never hide it; only rocks do).
func _check_sensed(c: CreatureField.Creature, t: int, where: String, looked: Dictionary, cell: Dictionary, arena: PoolArena,
		k: Dictionary, field: CreatureField = null) -> void:
	if not CreatureSenses.perceive(_viewer(c, looked, field), [cell], arena).is_empty():
		return
	var hurt: int = int(k.hurt_by_cell.get(c.id, -1))
	if hurt >= 0 and t - hurt <= int(c.brain.cfg.memory_ticks):
		return
	_fail(9, "%s: %s targeted the cell without sensing it (hurt by it at %d)" % [where, c.id, hurt])


## Invariant 9 on every tick: the creature's memory of the cell changed this step, so it must be a
## fresh percept that CreatureSenses gives from where the creature looked before the step (the same
## sense, position and velocity), or the pain of a hit by the cell on this tick. A memory that moved
## without a new percept, or a percept the senses would not give (an eye in the back of its head,
## a memory that follows the cell), fails.
func _check_memory(c: CreatureField.Creature, t: int, where: String, looked: Dictionary, cell: Dictionary, arena: PoolArena,
		k: Dictionary, field: CreatureField = null) -> void:
	k.memory_checks += 1
	var e: Dictionary = c.brain.seen[CreatureField.PLAYER_ID]
	var by := str(e.by)
	if int(e.tick) != t:
		_fail(9, "%s: %s's memory of the cell changed with no percept on this tick (%s at %d)" % [where, c.id, by, int(e.tick)])
		return
	if by == "pain":
		if int(k.hurt_by_cell.get(c.id, -1)) != t:
			_fail(9, "%s: %s felt the cell's pain without a hit by it" % [where, c.id])
		return
	var got := CreatureSenses.perceive(_viewer(c, looked, field), [cell], arena)
	if got.is_empty():
		_fail(9, "%s: %s holds a %s percept of the cell its senses do not give from %s" % [where, c.id, by, looked.position])
	elif got[0].by != by or not Vector2(got[0].position).is_equal_approx(e.position) \
			or not Vector2(got[0].velocity).is_equal_approx(e.velocity):
		_fail(9, "%s: %s's percept (%s at %s) is not what its senses give (%s at %s)" % [where, c.id, by, e.position,
			got[0].by, got[0].position])


## The creature as CreatureSenses' viewer, where it looked from before the step: its senses are
## `field`'s at its size (CreatureField.viewer_of: SpeciesCatalog.at_size's sight, fov and near_m x q).
## Without a field (a caller's hand-built check), its species block's own, which are the same at the
## species' entry size, so everywhere in S1.
func _viewer(c: CreatureField.Creature, looked: Dictionary, field: CreatureField = null) -> Dictionary:
	if field != null:
		var out := field.viewer_of(c)
		out.position = looked.position
		out.heading = looked.heading
		return out
	var senses: Dictionary = species.species[c.species_id].senses
	return {"id": c.id, "species": c.species_id, "position": looked.position, "heading": looked.heading,
		"radius": c.phenotype.radius, "sight": c.phenotype.sight, "fov": deg_to_rad(float(senses.fov_deg)),
		"near": float(senses.near_m)}


## What only the senses (or a hurt) write in a memory of the cell: all of it but the token's flag,
## which CreatureField sets before every think.
static func _sensed_part(memory: Dictionary) -> Dictionary:
	var out := memory.duplicate()
	out.erase("engageable")
	return out


## Invariant 1 for one body.
func _check_motion(who: String, m: Locomotion.MotionState, r: float, arena: PoolArena, where: String) -> void:
	if not m.position.is_finite() or not m.velocity.is_finite():
		_fail(1, "%s: %s at %s moving %s" % [where, who, m.position, m.velocity])
		return
	# Endless: hundreds of colliders are loaded, so the arena's own query finds whether any is dug
	# into (dig > slack exactly when the body of radius r - slack is not clear) before the loop names it.
	if not (arena is ChunkArena) or not arena.is_clear(m.position, r - ROCK_SLACK_M + PoolArena.CLEAR_EPSILON):
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


# --- 12 ---

func _check_12(sim: PoolSim, events: Array[Dictionary], _t: int, where: String, was: Dictionary) -> void:
	var w := sim.world
	var held := 0
	for id: String in w.morsel_sites:
		if not str(w.morsel_sites[id].get("food_id", "")).is_empty():
			held += 1
	if w.morsel_claims() != held:
		_fail(12, "%s: morsel_claims() is %d with %d morsel-site entries holding an item (S3G17d)" % [where,
			w.morsel_claims(), held])
	var k_now := w._tm_to_am
	var k_was := float(was.k)
	var now_origin := PackedFloat64Array([w.origin_x_am, w.origin_y_am])
	var cell_after := _at(sim.motion.position, now_origin, k_now)
	# The cut: everything up to the last respawned, teleport_abs or set_size is step 0's (or the dev
	# command's) own (exempt). A growth tick runs from growth_began to grew.
	var cut_at := -1
	var began := {}
	for i in events.size():
		var e := events[i]
		var command := str(e.get("command", "")) if e.type == "debug" else ""
		if e.type == "respawned" or command == "teleport_abs" or command == "set_size":
			cut_at = i
		if command == "set_size":
			counts.set_sizes += 1
		if e.type == "growth_began":
			began = e
			counts.growths += 1
	var cut := cut_at >= 0
	if cut:
		counts.cuts += 1
	var growing := not began.is_empty()
	var cell_block := cell_after if cut else PackedFloat64Array([float(was.cell_am[0]), float(was.cell_am[1]), k_was])
	var block := cell_block   # where block-step events are measured from: the cell after a growth's grew
	var frame: PackedFloat64Array = was.origin
	var fk := k_was           # the frame's k: the current one after a cut, the new size's after grew
	var in_growth := false
	var gone_carrion := {}
	for i in events.size():
		var e := events[i]
		if e.type == "rebased":
			frame = PackedFloat64Array([float(e.origin_am[0]), float(e.origin_am[1])])
			counts.rebases += 1
			continue
		if e.type == "carrion_expired" or e.type == "ate" or e.type == "creature_ate":
			gone_carrion[str(e.get("food_id", ""))] = true
		if i <= cut_at:
			if i == cut_at:
				fk = k_now
			continue
		if e.type == "growth_began":
			in_growth = true
			continue
		if e.type == "grew":
			in_growth = false
			frame = PackedFloat64Array([float(began.center_am[0]), float(began.center_am[1])])
			fk = WorldConfig.tm_to_am(int(e.to))
			block = cell_after
			continue
		if in_growth and (e.type == "chunk_loaded" or e.type == "chunk_unloaded"):
			continue   # the re-expression's own: the scene draws it behind the beat (S2G24)
		if growing and not in_growth:
			counts.after_growth += 1
		var tag := "%s: %s" % [where, e.type]
		match e.type:
			"creature_spawned":
				if bool(e.get("debug", false)):
					continue
				counts.spawns += 1
				_creature_hidden(sim, e, _at(e.position, frame, fk), cell_after, was, tag)
				if was.dead and sim.dead:   # dead, the checkpoint is a place too: the respawn will look there
					_creature_hidden(sim, e, _at(e.position, frame, fk), _at(was.checkpoint, was.origin, k_was), was,
						"%s (by the checkpoint)" % tag)
			"creature_removed":
				var when := str(HIDDEN_REMOVALS.get(str(e.reason), ""))
				if when.is_empty():
					continue
				if e.reason == "evicted":
					counts.evictions += 1
				_creature_hidden(sim, e, _at(e.position, frame, fk), block if when == "block" else cell_after, was,
					"%s (%s)" % [tag, e.reason])
			"creature_slept", "creature_woke":
				counts["sleeps" if e.type == "creature_slept" else "wakes"] += 1
				_creature_hidden(sim, e, _at(e.position, frame, fk), block, was, tag)
			"carrion_expired":
				if str(e.get("reason", "")) == "growth":
					_out_of_view(_at(e.position, frame, fk), sim.carrion.item_radius * fk, block, "%s %s" % [tag, e.food_id])
				elif str(e.get("reason", "")) == "unloaded" and not in_growth:
					counts.morsel_unloads += 1
					_out_of_view(_at(e.position, frame, fk), sim.carrion.item_radius * fk, block,
						"%s %s (unloaded)" % [tag, e.food_id])
			"carrion_spawned":
				if str(e.get("source", "")) != "morsel_site":
					continue
				counts.morsel_spawns += 1
				var item := sim.carrion.find(str(e.food_id))
				var r_am := float(item.get("radius", sim.carrion.item_radius)) * fk
				var at := _at(e.position, frame, fk)
				_morsel_hidden(at, r_am, cell_after, "%s %s" % [tag, e.food_id])
				if was.dead and sim.dead:
					_morsel_hidden(at, r_am, _at(was.checkpoint, was.origin, k_was), "%s %s (by the checkpoint)" % [tag, e.food_id])
			"chunk_loaded":
				counts.loads += 1
				for s in e.shells:
					_out_of_view(_at(s.position, frame, fk), float(s.radius) * fk, block, "%s %s shell %s" % [tag, e.key, s.id])
				for z in e.zones:
					_out_of_view(_at(z.center, frame, fk), float(z.radius) * fk, block, "%s %s zone %s" % [tag, e.key, z.id])
				for a in e.anchors:
					_out_of_view(_at(a.position, frame, fk), _anchor_r(w.size) * fk, block, "%s %s anchor %s" % [tag, e.key, a.id])
				for p in e.places:
					_out_of_view(_at(p.position, frame, fk), PLACE_RADIUS_TM * fk, block, "%s %s place %s" % [tag, e.key, p.id])
			"chunk_unloaded":
				counts.unloads += 1
				var ch: WorldChunk = was.chunks.get(e.key, null)
				if ch == null:
					_fail(12, "%s %s: not loaded before the tick" % [tag, e.key])
					continue
				var ck := WorldConfig.tm_to_am(ch.size)
				for s in ch.shells:
					_out_of_view(_am(s.x, s.y, ck), float(s.r) * ck, block, "%s %s shell %s" % [tag, e.key, s.id])
				for z in ch.zones:
					_out_of_view(_am(z.x, z.y, ck), float(z.radius) * ck, block, "%s %s zone %s" % [tag, e.key, z.id])
				for a in ch.anchors:
					_out_of_view(_am(a.x, a.y, ck), _anchor_r(ch.size) * ck, block, "%s %s anchor %s" % [tag, e.key, a.id])
				for p in ch.places:
					_out_of_view(_am(p.x, p.y, ck), PLACE_RADIUS_TM * ck, block, "%s %s place %s" % [tag, e.key, p.id])
	if cut:
		# A teleport (a far respawn, a dev teleport or a size set) drops every item behind the cut (C-10,
		# CC-10); a near respawn keeps them, so what it drops is measured from the cell after.
		var last := events[cut_at]
		if not (last.type == "debug" or bool(last.get("teleport", false))):
			_check_food_gone(sim, where, was, gone_carrion, cell_block, false)
		return
	if growing:
		# The food view's zones all went with the old size; its plankton turned to haze (D-29). The
		# carrion half: what the tick dropped with no expiry, meal or conversion naming it.
		_check_food_gone(sim, where, was, gone_carrion, cell_block, true)
		return
	# The food view: zones that joined or left it, and how fast each zone grows.
	var active := sim.plankton.active_zones
	for id in active:
		if not was.active.has(id):
			counts.zone_changes += 1
			var z := sim.region.zone(id)
			_out_of_view(_at(z.center, now_origin, k_now), float(z.radius) * k_now, cell_block, "%s: zone %s joined the food view" % [where, id])
	for id in was.active:
		if not active.has(id):
			counts.zone_changes += 1
			var z: Dictionary = was.zones.get(id, {})
			if not z.is_empty():
				_out_of_view(_at(z.center, was.origin, k_was), float(z.radius) * k_was, cell_block,
					"%s: zone %s left the food view" % [where, id])
	var had := {}
	for id in was.plankton:
		var zone := str(was.plankton[id].zone)
		had[zone] = int(had.get(zone, 0)) + 1
	var has := {}
	for item in sim.plankton.items:
		has[item.zone] = int(has.get(item.zone, 0)) + 1
	# A zone whose growth fill was pending before the step fills at once on its tick (C-V15 as amended:
	# FILL_ZONES_PER_TICK a tick after the growth tick, nearest first); any other gains one item a tick.
	var pending: Dictionary = was.get("pending", {})
	for zone in has:
		if int(has[zone]) - int(had.get(zone, 0)) > 1 and not pending.has(zone):
			_fail(12, "%s: zone %s gained %d plankton items" % [where, zone, int(has[zone]) - int(had.get(zone, 0))])
	_check_food_gone(sim, where, was, gone_carrion, cell_block, false)


## Plankton of zones no longer in the food view (not on a growth tick: `carrion_only`), and carrion
## gone with no expiry or meal, went out of view; both as they were before the step (before()'s k).
func _check_food_gone(sim: PoolSim, where: String, was: Dictionary, gone_carrion: Dictionary,
		cell_block: PackedFloat64Array, carrion_only: bool) -> void:
	var k_was := float(was.k)
	if not carrion_only:
		var now_plankton := {}
		for item in sim.plankton.items:
			now_plankton[item.id] = true
		for id in was.plankton:
			var zone := str(was.plankton[id].zone)
			if not now_plankton.has(id) and not sim.plankton.active_zones.has(zone):
				_out_of_view(_at(was.plankton[id].position, was.origin, k_was), sim.plankton.item_radius * k_was, cell_block,
					"%s: plankton %s of zone %s dropped" % [where, id, zone])
	var now_carrion := {}
	for item in sim.carrion.items:
		now_carrion[item.id] = true
	for id in was.carrion:
		if not now_carrion.has(id) and not gone_carrion.has(id):
			_out_of_view(_at(was.carrion[id], was.origin, k_was), sim.carrion.item_radius * k_was, cell_block,
				"%s: carrion %s dropped" % [where, id])


## A creature event's body (at `at`, am): at least spawn_safe_m from the measuring point and out of
## view, in the measuring point's tm. Its radius is the live body's (a creature or a remnant) at the
## current size, else the one before() recorded at the old size.
func _creature_hidden(sim: PoolSim, e: Dictionary, at: PackedFloat64Array, m: PackedFloat64Array, was: Dictionary,
		tag: String) -> void:
	counts.checked += 1
	var id := str(e.id)
	var k_now := sim.world._tm_to_am
	var r_am := float(was.radii.get(id, 0.0)) * float(was.k)
	if was.remnants.has(id):
		r_am = float(was.remnants[id].radius) * float(was.k)
	if sim.creatures != null:
		var c := sim.creatures.find(id)
		if c != null:
			r_am = c.phenotype.radius * k_now
	if sim.remnants != null:
		var rem := sim.remnants.find(id)
		if rem != null:
			r_am = rem.phenotype.radius * k_now
	var rel := _rel(at, m)
	if rel.length() < _safe:
		_fail(12, "%s %s %.2f tm from the cell" % [tag, id, rel.length()])
	elif _in_view(rel, r_am / m[2]):
		_fail(12, "%s %s in view at %s from the cell" % [tag, id, rel])


## A morsel site's item (radius `r_am`, am, at `at`): at least spawn_safe_m from the measuring point
## `m` and out of its view.
func _morsel_hidden(at: PackedFloat64Array, r_am: float, m: PackedFloat64Array, tag: String) -> void:
	counts.checked += 1
	var rel := _rel(at, m)
	if rel.length() < _safe:
		_fail(12, "%s %.2f tm from the cell" % [tag, rel.length()])
	elif _in_view(rel, r_am / m[2]):
		_fail(12, "%s in view at %s from the cell" % [tag, rel])


## Something of radius `r_am` (am) at `at` (am) is out of the view of the measuring point `m`.
func _out_of_view(at: PackedFloat64Array, r_am: float, m: PackedFloat64Array, tag: String) -> void:
	counts.checked += 1
	var rel := _rel(at, m)
	if _in_view(rel, r_am / m[2]):
		_fail(12, "%s in view at %s from the cell" % [tag, rel])


# --- 13 ---

func _check_13(sim: PoolSim, where: String) -> void:
	var far := {"length": 0.0, "what": ""}
	_far(far, sim.motion.position, "cell position")
	_far(far, sim.motion.prev_position, "cell prev_position")
	_far(far, sim.actor.position, "cell actor")
	if sim.creatures != null:
		for c in sim.creatures.creatures:
			_far(far, c.motion.position, "%s position" % c.id)
			_far(far, c.motion.prev_position, "%s prev_position" % c.id)
			_far(far, c.actor.position, "%s actor" % c.id)
			var b := c.brain
			if b == null:
				continue
			for id in b.seen:
				_far(far, b.seen[id].position, "%s seen %s" % [c.id, id])
			if not b.lane.is_empty():
				_far(far, b.lane.origin, "%s lane origin" % c.id)
			_far(far, b.goal, "%s goal" % c.id)
			if not b.progress.is_empty():
				_far(far, b.progress.position, "%s progress" % c.id)
			_far(far, b.flee_from, "%s flee_from" % c.id)
			_far(far, b.home, "%s home" % c.id)
			_far(far, b.territory_center, "%s territory_center" % c.id)
	for item in sim.plankton.items:
		_far(far, item.position, "plankton %s" % item.id)
		_far(far, item.anchor, "plankton %s anchor" % item.id)
	for item in sim.carrion.items:
		_far(far, item.position, "carrion %s" % item.id)
	for z in sim.region.zones:
		_far(far, z.center, "zone %s" % z.id)
	if sim.creatures != null:
		for c in sim.creatures.creatures:   # S2: a two-post brain's posts and union leash (D-83)
			var b := c.brain
			if b == null or b.posts.is_empty():
				continue
			for i in b.posts.size():
				_far(far, b.posts[i].home, "%s post %d home" % [c.id, i])
				if not b.posts[i].territory.is_empty():
					_far(far, b.posts[i].territory.center, "%s post %d territory" % [c.id, i])
			_far(far, b.leash_center, "%s leash_center" % c.id)
	if sim.remnants != null:
		for r in sim.remnants.items:
			_far(far, r.motion.position, "remnant %s position" % r.id)
			_far(far, r.motion.prev_position, "remnant %s prev_position" % r.id)
			_far(far, r.actor.position, "remnant %s actor" % r.id)
	for id in sim.world.sites:
		var s: Dictionary = sim.world.sites[id]
		_far(far, s.home, "site %s home" % id)
		if not s.territory.is_empty():
			_far(far, s.territory.center, "site %s territory" % id)
		_far(far, s.reach.center, "site %s reach" % id)
		if s.has("posts"):
			for i in s.posts.size():
				_far(far, s.posts[i].home, "site %s post %d home" % [id, i])
	if sim.arena is ChunkArena:
		for p in (sim.arena as ChunkArena)._centers:
			_far(far, p, "a collider")
	if float(far.length) >= LOCAL_BOUND:
		_fail(13, "%s: %s at %.1f tm" % [where, far.what, far.length])


func _far(far: Dictionary, p: Vector2, what: String) -> void:
	if p.is_finite() and p.length() > float(far.length):
		far.length = p.length()
		far.what = what


# --- 16 ---

func _check_16(sim: PoolSim, where: String) -> void:
	if sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if not c.asleep:
			continue
		var rel := c.motion.position - sim.motion.position
		if rel.length() < _safe:
			_fail(16, "%s: sleeper %s %.2f tm from the cell" % [where, c.id, rel.length()])
		elif _in_view(rel, c.phenotype.radius):
			_fail(16, "%s: sleeper %s in view at %s" % [where, c.id, rel])


# --- frames ---

## A local position in the frame (`origin` am, `k` am per tm) as absolute am in float64, with `k`
## third: as a measuring point, distances from it are in its size's tm.
static func _at(p: Vector2, origin: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return PackedFloat64Array([origin[0] + float(p.x) * k, origin[1] + float(p.y) * k, k])


## A chunk's stored absolute tm at its size (`ck` = tm_to_am(size)) as absolute am.
static func _am(x: Variant, y: Variant, ck: float) -> PackedFloat64Array:
	return PackedFloat64Array([float(x) * ck, float(y) * ck])


## `at` from the measuring point `m`, in m's tm.
static func _rel(at: PackedFloat64Array, m: PackedFloat64Array) -> Vector2:
	return Vector2((at[0] - m[0]) / m[2], (at[1] - m[1]) / m[2])


func _in_view(rel: Vector2, r: float) -> bool:
	return _quad.is_empty() or ViewFootprint.distance_outside(_quad, rel) <= _margin + r


## An anchor's extent in tm at size `n`.
static func _anchor_r(n: int) -> float:
	return ANCHOR_RADIUS_BU * WorldConfig.bu_to_tm(n)
