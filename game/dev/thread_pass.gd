extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): the thread
## pass of D-141's runners (S3 T0.3, s3-sim 3.12). It wraps another bot so a fuzz run meets the
## veils' threads: from PERIOD_TICKS - PASS_TICKS into every PERIOD_TICKS of the run it steers the
## cell at full throttle at the midpoint of the nearest awake hazard's threads
## (CreatureBrain.thread_capsule), until HOLD_TICKS after the pass first touches them or the period
## ends; the rest of the time the inner bot drives. The inner bot is asked every tick (its own bookkeeping
## runs on) and its growth keys ride along; only its move is replaced during a pass. With `strikers`,
## every other period's pass, STRIKER_PASS_TICKS long, steers instead at the nearest living creature
## of the cell's size that is no hazard (q = 1: one that may engage the cell; asleep or not, since
## the cell's coming wakes it), until HOLD_TICKS after the cell first comes within STRIKER_NEAR_TM of
## its rim: a player who swims into a Warden's ground, so a run meets its strikes as well as the
## threads.
##
## `capsule_contact_ticks` counts the ticks on which the cell's disc touches an awake hazard's
## capsule, measured as PoolSim's sting step measures it: the runners' non-vacuity (a veil at q < 1
## that the cell swam through and that never stung it).
##
##     var bot = load("res://game/dev/thread_pass.gd").new(KiterBot.new(seed))
##     sim.step(bot.next_intent(sim, events_from_the_last_step))

const PERIOD_TICKS := 1800
const PASS_TICKS := 600       ## the longest pass: room to cross to a hazard a screen away
const HOLD_TICKS := 30        ## a pass ends this long after its first touch of the threads
const STRIKER_PASS_TICKS := 1200   ## a striker pass may cross farther: its creature may sleep away off
const STRIKER_NEAR_TM := 1.0  ## a striker pass has arrived this near the creature's rim

var inner: Variant                ## the wrapped bot
var with_events := false          ## its next_intent takes the last step's events (EvadeBot)
var capsule_contact_ticks := 0
var passes := 0                   ## passes that found a hazard to steer at
var strikers := false             ## every other pass steers at a creature of the cell's size
var striker_passes := 0           ## passes that found one
var _n := 0                       ## ticks driven so far
var _passing := false
var _touched_at := -1         ## the tick of _n the pass first touched the threads, or -1


func _init(p_inner: Variant, p_with_events := false) -> void:
	inner = p_inner
	with_events = p_with_events


func next_intent(sim: PoolSim, events: Array = []) -> SimIntent:
	var touching := _touching(sim)
	if touching:
		capsule_contact_ticks += 1
	var intent: SimIntent = inner.next_intent(sim, events) if with_events else inner.next_intent(sim)
	var at_striker := strikers and posmod(_n / PERIOD_TICKS, 2) == 1
	var in_pass := posmod(_n, PERIOD_TICKS) >= PERIOD_TICKS - (STRIKER_PASS_TICKS if at_striker else PASS_TICKS)
	var target := _nearest_striker(sim) if at_striker else {}
	var arrived := touching if not at_striker else not target.is_empty() \
		and sim.motion.position.distance_to(target.at) <= float(target.r) + sim.phenotype.radius + STRIKER_NEAR_TM
	if not in_pass:
		_touched_at = -1
	elif arrived and _touched_at < 0:
		_touched_at = _n
	_n += 1
	if not in_pass or sim.dead or (_touched_at >= 0 and _n - _touched_at > HOLD_TICKS):
		_passing = false
		return intent
	var to: Vector2 = target.at if not target.is_empty() else (_nearest_threads(sim) if not at_striker else Vector2.INF)
	if not to.is_finite():
		return intent
	if not _passing:
		_passing = true
		if at_striker:
			striker_passes += 1
		else:
			passes += 1
	var d := to - sim.motion.position
	intent.move = d.normalized() if d.length() > 1e-3 else Vector2.ZERO
	return intent


## The nearest living creature at the cell's size (q = 1) that is no hazard: {"at", "r"} (local tm),
## or {} with none.
static func _nearest_striker(sim: PoolSim) -> Dictionary:
	var best := {}
	var best_d := INF
	if sim.creatures == null:
		return best
	for c in sim.creatures.creatures:
		if c.brain == null or c.brain.behavior == CreatureBrain.HAZARD or not c.state.is_alive():
			continue
		if sim.species.q_of(c.species_id, sim.size()) < 1.0:
			continue
		var d := sim.motion.position.distance_to(c.motion.position)
		if d < best_d:
			best_d = d
			best = {"at": c.motion.position, "r": c.phenotype.radius}
	return best


## The midpoint of the nearest awake hazard's capsule (local tm), or Vector2.INF with none.
static func _nearest_threads(sim: PoolSim) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	if sim.creatures == null:
		return best
	for c in sim.creatures.awake():
		if c.brain == null or c.brain.behavior != CreatureBrain.HAZARD or not c.state.is_alive():
			continue
		var cap := CreatureBrain.thread_capsule(c.brain, c.motion.position, c.motion.heading, c.phenotype.radius)
		var mid: Vector2 = (Vector2(cap.a) + Vector2(cap.b)) * 0.5
		var d := sim.motion.position.distance_to(mid)
		if d < best_d:
			best_d = d
			best = mid
	return best


## Whether the cell's disc touches an awake hazard's capsule now.
static func _touching(sim: PoolSim) -> bool:
	if sim.creatures == null or sim.dead:
		return false
	var me := sim.motion.position
	for c in sim.creatures.awake():
		if c.brain == null or c.brain.behavior != CreatureBrain.HAZARD or not c.state.is_alive():
			continue
		var cap := CreatureBrain.thread_capsule(c.brain, c.motion.position, c.motion.heading, c.phenotype.radius)
		var near := Geometry2D.get_closest_point_to_segment(me, cap.a, cap.b)
		if me.distance_to(near) <= float(cap.r) + sim.phenotype.radius:
			return true
	return false
