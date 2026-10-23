extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): the driver of
## test_threat_fuzz. It swims at full throttle to the nearest creature and circles it, at a distance
## that swings between ORBIT_MIN_M and ORBIT_MAX_M, for a dwell drawn from DWELL_TICKS; then it picks
## the nearest creature it has not just visited, so over a run it crosses lairs and territories. It
## never evades: notices, chases, tells, strikes and give-ups all play out on it.
##
## Each visit also draws its circling throttle (THROTTLE_RANGE), its direction and whether it stops
## dead while the creature aims and tells at it (HOLD_SHARE), so some strikes land. With `bite_dazed`
## it closes in, at full throttle, on the creature once that one is committed to a strike (burst,
## glide and recover), so the cell's jaw (contact combat, OD3) wounds creatures until they flee.
##
## In the endless world (S1) it circles awake creatures only: one that falls asleep is passed over.
##
## Unlike EvadeBot it reads the sim's creatures (bodies and brains), as a test would. Like player
## input it only returns a SimIntent and never changes the sim. Its choices come from its own seeded
## RNG, so a run repeats exactly.
##
## Its `keys` (EvadeBot.GrowthKeys, S2) send the growth trigger on its first intent and, in a press
## run, Grow while the ring is full.
##
##     var bot = load("res://game/dev/kiter_bot.gd").new(seed_value)
##     sim.step(bot.next_intent(sim))

## The orbit distance swings between these. The plan's 3-6 m, reaching in to 2.5 m so the swing
## passes through the lunge's 2.5-3.0 m window: a sated ambush hunter strikes only there.
const ORBIT_MIN_M := 2.5
const ORBIT_MAX_M := 6.0
const ORBIT_PERIOD_TICKS := 300   ## the distance goes from min to max and back every 5 s
const ARRIVED_M := 2.0            ## within ORBIT_MAX_M plus this the dwell starts counting
## Ticks round one creature, drawn per visit: up to 18 s, past the longest chase's give-up plus an
## attack cycle (the rammer's 12.4 s), so a chase that ignored its timer would show.
const DWELL_TICKS: Array[int] = [600, 1080]
const RADIAL_GAIN := 0.8          ## share of the move spent per metre off the orbit distance
const RECENT := 2                 ## creatures it has just visited and passes over when choosing
const LOOK_AHEAD_M := 2.0         ## it steers at a point this far along the wanted direction (round rocks)
## Each visit's throttle is drawn from this range: slow visits let a creature aim and tell, fast
## ones make it turn and give up.
const THROTTLE_RANGE := [0.35, 0.9]
## Share of visits on which it stops dead while the creature it circles aims and tells at it, so the
## strike has no lead to miss by and lands (moving prey is safe by design).
const HOLD_SHARE := 0.5

const EvadeBot := preload("res://game/dev/evade_bot.gd")

var bite_dazed := true
var keys := EvadeBot.GrowthKeys.new()
var visits := 0                   ## creatures it has circled (tests guard that it got round)
var _rng := RandomNumberGenerator.new()
var _target := ""
var _dwell_left := 0
var _arrived := false
var _dir := 1.0                   ## +1 or -1: which way round
var _phase := 0                   ## offset into the orbit period
var _throttle := 0.7
var _hold := false                ## this visit it stops dead while aimed at
var _recent: Array[String] = []


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## The id of the creature it is circling or heading for, or "".
func target_id() -> String:
	return _target


func next_intent(sim: PoolSim) -> SimIntent:
	return keys.apply(sim, _kite(sim))


func _kite(sim: PoolSim) -> SimIntent:
	if sim.dead or sim.creatures == null:
		_target = ""
		return SimIntent.new()
	var c := sim.creatures.find(_target)
	if c == null or c.get("asleep") == true or (_arrived and _dwell_left <= 0):
		c = _choose(sim)
	if c == null:
		return SimIntent.new()
	var pos := sim.motion.position
	var off := pos - c.motion.position
	var d := off.length()
	if not _arrived and d <= ORBIT_MAX_M + ARRIVED_M:
		_arrived = true
		visits += 1
	if _arrived:
		_dwell_left -= 1
	if _hold and _aiming_at_cell(c):
		return SimIntent.new()
	var radial := off / d if d > 1e-6 else Vector2.from_angle(sim.motion.heading + PI)
	var want: Vector2
	var closing := bite_dazed and _committed(c)
	if closing:
		want = -radial   # straight at it, jaw first, while it cannot turn
	else:
		var swing := 0.5 - 0.5 * cos(TAU * float(sim.tick + _phase) / ORBIT_PERIOD_TICKS)
		var orbit := ORBIT_MIN_M + (ORBIT_MAX_M - ORBIT_MIN_M) * swing
		var correct := clampf((orbit - d) * RADIAL_GAIN, -1.0, 1.0)
		want = (radial.orthogonal() * _dir + radial * correct).normalized()
	var aim := sim.arena.route_point(pos, pos + want * LOOK_AHEAD_M, sim.phenotype.radius)
	var to := aim - pos
	if to.length() < 1e-6:
		return SimIntent.new()
	return SimIntent.new(to.normalized() * (1.0 if closing or not _arrived else _throttle))


## The next creature: the nearest one with a brain that it has not just visited (ties by id); any
## nearest one when all are recent. Draws the visit's dwell, direction, orbit phase, throttle and hold.
func _choose(sim: PoolSim) -> CreatureField.Creature:
	if not _target.is_empty():
		_recent.append(_target)
		while _recent.size() > RECENT:
			_recent.pop_front()
	var best: CreatureField.Creature = null
	var best_d := INF
	var fallback: CreatureField.Creature = null
	var fallback_d := INF
	for c: CreatureField.Creature in _active(sim):
		if c.brain == null:
			continue
		var d := sim.motion.position.distance_to(c.motion.position)
		if d < fallback_d or (d == fallback_d and c.id < fallback.id):
			fallback_d = d
			fallback = c
		if _recent.has(c.id):
			continue
		if d < best_d or (d == best_d and c.id < best.id):
			best_d = d
			best = c
	if best == null:
		best = fallback
	_target = best.id if best != null else ""
	_arrived = false
	_dwell_left = _rng.randi_range(DWELL_TICKS[0], DWELL_TICKS[1])
	_dir = 1.0 if _rng.randi_range(0, 1) == 1 else -1.0
	_phase = _rng.randi_range(0, ORBIT_PERIOD_TICKS - 1)
	_throttle = _rng.randf_range(THROTTLE_RANGE[0], THROTTLE_RANGE[1])
	_hold = _rng.randf() < HOLD_SHARE
	return best


## Aiming at the cell (chase/aim) or telling at it.
static func _aiming_at_cell(c: CreatureField.Creature) -> bool:
	if c.brain == null or c.brain.target != CreatureField.PLAYER_ID:
		return false
	return (c.brain.state == CreatureBrain.CHASE and c.brain.phase == CreatureBrain.AIM) \
		or (c.brain.state == CreatureBrain.ATTACK and c.brain.phase == CreatureBrain.TELL)


## Committed to a strike: in its burst, glide or recover it cannot turn (no homing) or start another
## tell, so a player closes in to bite it then.
static func _committed(c: CreatureField.Creature) -> bool:
	if c.brain == null or c.brain.state != CreatureBrain.ATTACK:
		return false
	return c.brain.phase == CreatureBrain.STRIKE or c.brain.phase == CreatureBrain.GLIDE or c.brain.phase == CreatureBrain.RECOVER


## The creatures that act this tick: all of them in the pool, the awake ones in the endless world
## (CreatureField.awake(), S1 spine 3.10, which is the creature list itself in the pool). Read by
## name, so the bot also loads before the endless world.
static func _active(sim: PoolSim) -> Array:
	var field: Object = sim.creatures
	return field.call("awake") if field.has_method("awake") else sim.creatures.creatures
