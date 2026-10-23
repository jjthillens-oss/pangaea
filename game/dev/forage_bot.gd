extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path). Each tick it
## swims toward the nearest food the cell can eat, steering round rocks in the way, and rests
## while the cell is too full to eat. Like player input, it only returns a SimIntent and never
## changes the sim. With `park_at` set it swims there and holds still. It is not creature AI.
##
## With `avoid_threats` (M1 step 3; the smoke phases turn it on) it keeps clear of creatures: it
## passes over food within THREAT_FOOD_M of any creature, steers away from creatures within
## THREAT_AVOID_M, and dodges a tell aimed at the cell with the EvadeBot reaction (out of its line on
## the side the cell faces, 0.4 s after the tell starts). The pool asks only next_intent(sim), so it
## cannot hear the sim's events; it watches the creatures' attack phases instead, as a player watches
## their poses, and hands EvadeBot the tells and their ends it sees.
##
##     var bot = load("res://game/dev/forage_bot.gd").new()
##     sim.step(bot.next_intent(sim))

const ARRIVE_M := 1.2          ## ease off the throttle within this distance of the target
const MIN_THROTTLE := 0.35     ## approaching a place
const TURN_THROTTLE := 0.08    ## at the food: just above the input deadzone, so the cell turns its mouth onto it
const CONTACT_MARGIN_M := 0.1  ## "at the food": within both radii plus this
const PARK_RADIUS_M := 0.3
const SWITCH_SHARE := 0.6      ## change food only for one this much nearer than the current one
const THREAT_FOOD_M := 8.0     ## with avoid_threats: food this near a creature is passed over (plan section 16)
const THREAT_AVOID_M := 6.0    ## with avoid_threats: creatures this near push the cell away
## With avoid_threats: how hard a creature pushes, per unit of nearness (1 at contact, 0 at
## THREAT_AVOID_M), against the forage intent's 1; at 3 m a creature outweighs any food.
const THREAT_AVOID_GAIN := 2.0

const EvadeBot := preload("res://game/dev/evade_bot.gd")

## Where to swim and stop instead of foraging; Vector2.INF to forage.
var park_at := Vector2.INF
var avoid_threats := false
var _target_id := ""
var evade = null               ## with avoid_threats: the EvadeBot it dodges with, made when first needed
var _attacking := {}           ## creature id -> true: telling or striking at the cell last tick


## The id of the food the last intent swam for, or "" when there was none.
func target_id() -> String:
	return _target_id


func next_intent(sim: PoolSim) -> SimIntent:
	if not avoid_threats or sim.creatures == null:
		return _forage(sim)
	if evade == null:
		evade = EvadeBot.new()
		evade.base = _wary_forage
	return evade.next_intent(sim, _attack_events(sim))


func _forage(sim: PoolSim) -> SimIntent:
	if sim.dead:
		return SimIntent.new()
	var pos := sim.motion.position
	if park_at.is_finite():
		return _swim_to(sim, park_at, MIN_THROTTLE, PARK_RADIUS_M)
	var food := _chosen_food(sim)
	if food.is_empty():
		return _swim_to(sim, _waiting_spot(sim), MIN_THROTTLE, PARK_RADIUS_M)
	var room := sim.state.energy_capacity - sim.state.energy
	if room < float(food.energy) * InteractionResolver.FEED_MIN_ROOM_SHARE:
		return SimIntent.new()
	var contact := sim.phenotype.radius + float(food.radius) + CONTACT_MARGIN_M
	var aim := _route(sim, pos, food.position)
	var throttle := clampf((pos.distance_to(food.position) - contact) / ARRIVE_M, TURN_THROTTLE, 1.0)
	return SimIntent.new((aim - pos).normalized() * throttle)


## The forage intent, pushed away from the creatures within THREAT_AVOID_M (EvadeBot's base).
func _wary_forage(sim: PoolSim) -> SimIntent:
	var intent := _forage(sim)
	if sim.dead:
		return intent
	var push := Vector2.ZERO
	for c in sim.creatures.creatures:
		var off := sim.motion.position - c.motion.position
		var d := off.length()
		if d < THREAT_AVOID_M and d > 1e-6:
			push += off / d * (1.0 - d / THREAT_AVOID_M) * THREAT_AVOID_GAIN
	if push == Vector2.ZERO:
		return intent
	var move := intent.move + push
	return SimIntent.new(move.normalized() if move.length() > 1.0 else move)


## What EvadeBot would have heard since the last tick, from what the creatures show: a
## creature_tell (with the tick it began) when one starts telling at the cell, and its end
## (creature_recovered, or creature_removed when it is gone) when it stops telling or striking at it.
func _attack_events(sim: PoolSim) -> Array:
	var out: Array = []
	var now := {}
	for c in sim.creatures.creatures:
		var b := c.brain
		if b == null or b.target != CreatureField.PLAYER_ID or b.state != CreatureBrain.ATTACK or b.phase == CreatureBrain.RECOVER:
			continue
		now[c.id] = true
		if not _attacking.has(c.id) and b.phase == CreatureBrain.TELL:
			out.append({"type": "creature_tell", "id": c.id, "target": CreatureField.PLAYER_ID, "lane": b.lane,
				"tick": b.phase_tick})
	for id in _attacking:
		if now.has(id):
			continue
		var c := sim.creatures.find(id)
		if c == null:
			out.append({"type": "creature_removed", "id": id})
		else:
			out.append({"type": "creature_recovered", "id": id, "position": c.motion.position})
	_attacking = now
	return out


func _swim_to(sim: PoolSim, target: Vector2, slowest: float, stop_within: float) -> SimIntent:
	var pos := sim.motion.position
	var dist := pos.distance_to(target)
	if dist <= stop_within:
		return SimIntent.new()
	var aim := _route(sim, pos, target)
	return SimIntent.new((aim - pos).normalized() * clampf(dist / ARRIVE_M, slowest, 1.0))


## The food being chased, kept until it is gone or a much nearer one appears. {} when nothing
## edible exists.
func _chosen_food(sim: PoolSim) -> Dictionary:
	var pos := sim.motion.position
	var current := {}
	var nearest := {}
	var nearest_d := INF
	for list in [sim.plankton.items, sim.carrion.items]:
		for item in list:
			if not sim.phenotype.can_eat(item.kind):
				continue
			if avoid_threats and _near_creature(sim, item.position, THREAT_FOOD_M):
				continue
			if item.id == _target_id:
				current = item
			var d := pos.distance_to(item.position)
			if d < nearest_d:
				nearest_d = d
				nearest = item
	if current.is_empty() or nearest_d < pos.distance_to(current.position) * SWITCH_SHARE:
		current = nearest
	_target_id = current.get("id", "")
	return current


## With nothing to eat, wait at the nearest zone's center (carrion and plankton both appear there);
## with avoid_threats, the nearest one with no creature within THREAT_FOOD_M (else the spawn).
func _waiting_spot(sim: PoolSim) -> Vector2:
	if not avoid_threats or sim.creatures == null:
		var z := sim.region.zone(sim.nearest_zone_id())
		return z.center if not z.is_empty() else sim.layout.spawn
	var best := sim.layout.spawn
	var best_d := INF
	for z in sim.region.zones:
		var d := sim.motion.position.distance_to(z.center)
		if d < best_d and not _near_creature(sim, z.center, THREAT_FOOD_M):
			best_d = d
			best = z.center
	return best


static func _near_creature(sim: PoolSim, p: Vector2, within: float) -> bool:
	if sim.creatures == null:
		return false
	for c in sim.creatures.creatures:
		if c.motion.position.distance_to(p) < within:
			return true
	return false


## The point to swim at now: the target itself, or a point beside the first rock in the way
## (PoolArena.route_point, which creatures share).
func _route(sim: PoolSim, pos: Vector2, target: Vector2) -> Vector2:
	return sim.arena.route_point(pos, target, sim.phenotype.radius)
