extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): the endless
## world's plainest swimmers (S1 spine 3.15), for the streaming gates (tests/test_endless_gates.gd,
## tests/test_endless_cost.gd) and the endless smokes.
##  - A straight swimmer asks for the same move every tick: `dir` at `throttle`, whatever happens,
##    as a player holding one key would. At full throttle the cell swims at its body's top speed.
##    The gates are written for 6 tm/s (PoolLayout.MAX_SPEED, the cap), but no body reaches it: the
##    fastest starting body, the hunter, makes 3.26 tm/s and the fastest legal body (the gates'
##    racer, a jaw and three flagella at scale 2) 4.41, so the straight swims and the cost gates swim
##    the racer and print the speed it reached (docs/DECISIONS.md, S1 build decisions).
##  - A camper (camper(zone_id)) swims to its zone's centre, round rocks, and holds still within
##    half the zone's radius. It looks the zone up in sim.region.zones every tick, so it follows the
##    zone through a rebase of the floating origin. A greedy camper (#33) also eats its zone's food:
##    it swims to the nearest item in the zone it can eat, as soon as it has room for half of it,
##    and holds at the centre while the zone is empty.
## Like player input it only returns a SimIntent and never changes the sim.
##
##     const SwimBot := preload("res://game/dev/swim_bot.gd")
##     var east = SwimBot.new(Vector2.RIGHT)
##     var camper = SwimBot.camper("z_center")
##     sim.step(east.next_intent(sim))

const ForageBot := preload("res://game/dev/forage_bot.gd")
const ARRIVE_M := 1.2          ## a camper eases off within this distance of the centre
const MIN_THROTTLE := 0.35     ## and never below this while it still has to arrive

var dir := Vector2.RIGHT
var throttle := 1.0
var zone_id := ""              ## a camper's zone; "" for a straight swimmer
var greedy := false
var _forager = null            ## a greedy camper's way to an item (ForageBot parked on it)


func _init(p_dir: Vector2, p_throttle := 1.0) -> void:
	dir = p_dir
	throttle = p_throttle


## A camper in `p_zone_id`; with `p_greedy` it also eats that zone's food (#33).
static func camper(p_zone_id: String, p_greedy := false) -> RefCounted:
	var bot = (load("res://game/dev/swim_bot.gd") as GDScript).new(Vector2.ZERO)
	bot.zone_id = p_zone_id
	bot.greedy = p_greedy
	return bot


func next_intent(sim: PoolSim) -> SimIntent:
	if zone_id.is_empty():
		return SimIntent.new(dir.normalized() * throttle)
	return _camp(sim)


func _camp(sim: PoolSim) -> SimIntent:
	var z := sim.region.zone(zone_id)
	if sim.dead or z.is_empty():
		return SimIntent.new()
	var center: Vector2 = z.center
	if greedy:
		var food := _zone_food(sim, center, float(z.radius))
		if not food.is_empty():
			if sim.state.energy_capacity - sim.state.energy < float(food.energy) * InteractionResolver.FEED_MIN_ROOM_SHARE:
				return SimIntent.new()   # too full to eat it: wait
			if _forager == null:
				_forager = ForageBot.new()
			_forager.park_at = Vector2(food.position)
			return _forager.next_intent(sim)
	var pos := sim.motion.position
	var d := pos.distance_to(center)
	if d <= float(z.radius) * 0.5:
		return SimIntent.new()
	var aim := sim.arena.route_point(pos, center, sim.phenotype.radius)
	var to := aim - pos
	if to.length() < 1e-6:
		return SimIntent.new()
	return SimIntent.new(to.normalized() * clampf(d / ARRIVE_M, MIN_THROTTLE, 1.0) * throttle)


## The nearest item inside the zone the cell can eat (ties by id), or {}.
static func _zone_food(sim: PoolSim, center: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for list in [sim.plankton.items, sim.carrion.items]:
		for item in list:
			if not sim.phenotype.can_eat(item.kind) or Vector2(item.position).distance_to(center) > radius:
				continue
			var d := sim.motion.position.distance_to(item.position)
			if d < best_d or (d == best_d and str(item.id) < str(best.id)):
				best_d = d
				best = item
	return best
