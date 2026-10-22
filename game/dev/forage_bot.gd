extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path). Each tick it
## swims toward the nearest food the cell can eat, steering round rocks in the way, and rests
## while the cell is too full to eat. Like player input, it only returns a SimIntent and never
## changes the sim. With `park_at` set it swims there and holds still. It is not creature AI;
## that starts fresh in step 3.
##
##     var bot = load("res://game/dev/forage_bot.gd").new()
##     sim.step(bot.next_intent(sim))

const ARRIVE_M := 1.2          ## ease off the throttle within this distance of the target
const MIN_THROTTLE := 0.35     ## approaching a place
const TURN_THROTTLE := 0.08    ## at the food: just above the input deadzone, so the cell turns its mouth onto it
const CONTACT_MARGIN_M := 0.1  ## "at the food": within both radii plus this
const PARK_RADIUS_M := 0.3
const ROCK_CLEARANCE_M := 0.1  ## a rock blocks the straight line when the cell would pass this close
const DETOUR_MARGIN_M := 0.6   ## room kept from a rock when going round it
const SWITCH_SHARE := 0.6      ## change food only for one this much nearer than the current one

## Where to swim and stop instead of foraging; Vector2.INF to forage.
var park_at := Vector2.INF
var _target_id := ""


## The id of the food the last intent swam for, or "" when there was none.
func target_id() -> String:
	return _target_id


func next_intent(sim: PoolSim) -> SimIntent:
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


## With nothing to eat, wait at the nearest zone's center (carrion and plankton both appear there).
func _waiting_spot(sim: PoolSim) -> Vector2:
	var z := sim.region.zone(sim.nearest_zone_id())
	return z.center if not z.is_empty() else sim.layout.spawn


## The point to swim at now: the target itself, or a point beside the first rock in the way.
func _route(sim: PoolSim, pos: Vector2, target: Vector2) -> Vector2:
	var to := target - pos
	var length := to.length()
	if length < 1e-6:
		return target
	var dir := to / length
	var body_r := sim.phenotype.radius
	var blocking := {}
	var nearest_along := INF
	for rock in sim.arena.rocks:
		var c: Vector2 = rock.center - pos
		var along := c.dot(dir)
		if along <= 0.0 or along >= length + rock.radius:
			continue
		var off := c - dir * along
		if off.length() < rock.radius + body_r + ROCK_CLEARANCE_M and along < nearest_along:
			nearest_along = along
			blocking = {"center": rock.center, "radius": rock.radius, "off": off}
	if blocking.is_empty():
		return target
	# Go round on the side the line already passes, so the detour is the short way.
	var off: Vector2 = blocking.off
	var away := -off.normalized() if off.length() > 1e-6 else dir.orthogonal()
	return blocking.center + away * (blocking.radius + body_r + DETOUR_MARGIN_M)
