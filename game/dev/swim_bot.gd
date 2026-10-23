extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): the endless
## world's plainest swimmers (S1 spine 3.15), for the streaming gates (tests/test_endless_gates.gd,
## tests/test_endless_cost.gd) and the endless smokes.
##  - A straight swimmer asks for the same move every tick: `dir` at `throttle`, whatever happens,
##    as a player holding one key would. At full throttle the cell swims at its body's top speed.
##    The gates are written for 6 tm/s (PoolLayout.MAX_SPEED, the cap), but no legal body reaches
##    it: the fastest starting body, the hunter, makes 3.26 tm/s and the fastest legal body (the
##    gates' racer, a jaw and three flagella at scale 2) 4.41. So the streaming swims, the 10 km hash
##    and the cost swims overdrive the racer to 6 tm/s (overdrive(), S1 build plan B-12), and each
##    also keeps one run of the racer as it is (docs/DECISIONS.md, S1 build decisions).
##  - A camper (camper(zone_id)) swims to its zone's centre, round rocks, and holds still within
##    half the zone's radius. It looks the zone up in sim.region.zones every tick, so it follows the
##    zone through a rebase of the floating origin. A greedy camper (#33) also eats its zone's food:
##    it swims to the nearest item in the zone it can eat, as soon as it has room for half of it,
##    and holds at the centre while the zone is empty.
##  - A homing swimmer (toward(at)) swims to an absolute point (am), round rocks, as a player steering
##    for a place they mean to reach would, and holds still within ARRIVE_M of it. It reads the
##    point's local position from the stream every tick, so it follows the point through a rebase.
##    The gates that start out in the sea arrive at their points with it (tests/test_endless_gates.gd,
##    arrive()). It frees itself where it wedges between shells (Unjam, which HuntBot shares).
## Like player input next_intent only returns a SimIntent and never changes the sim. overdrive()
## does change it, and only tests and soak gates call it. Every swimmer's `keys` (EvadeBot.GrowthKeys,
## S2) send the growth trigger on its first intent and, in a press run, Grow while the ring is full.
##
##     const SwimBot := preload("res://game/dev/swim_bot.gd")
##     var east = SwimBot.new(Vector2.RIGHT)
##     var camper = SwimBot.camper("z_center")
##     var homing = SwimBot.toward(PackedFloat64Array([-1258.0, 162.0]))
##     sim.step(east.next_intent(sim))
##     SwimBot.overdrive(sim)                 # tests and soak gates only, before each step
##     sim.step(east.next_intent(sim))

const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const ARRIVE_M := 1.2          ## a camper eases off within this distance of the centre
const MIN_THROTTLE := 0.35     ## and never below this while it still has to arrive

var dir := Vector2.RIGHT
var throttle := 1.0
var zone_id := ""              ## a camper's zone; "" for a straight swimmer
var goal_am := PackedFloat64Array()   ## a homing swimmer's point (x, y am); empty for the others
var greedy := false
var keys := EvadeBot.GrowthKeys.new()
var _forager = null            ## a greedy camper's way to an item (ForageBot parked on it)
var _unjam: Unjam = null       ## a homing swimmer's way out of a crack


## A bot's way round colliders that frees it where route_point wedges it (the endless bots use it;
## it works in the pool too, where its test builds a crack). route_point goes round the nearest collider in the way on the side the straight line passes. Where shells
## stand in a row closer than the body is wide, the way round one leads into the crack beside the
## next, and the cell pushes on and stays put (the M1 pool's rocks leave no such crack). A bot asks
## aim() for the point to swim at instead of calling route_point. Once the cell, touching a
## collider, has moved less than STUCK_TM over STUCK_TICKS asks in a row, it steps aside along the
## row: for up to SIDESTEP_TICKS it swims (round single shells) to a point SIDESTEP_TM to one side
## of the line to its goal and BACK_TM back, alternating sides and reaching further each other
## wedge (6, 6, 12, 12, ... tm), then heads for the goal again. It reads absolute positions, so a
## rebase does not look like a move.
class Unjam:
	const STUCK_TICKS := 60
	const STUCK_TM := 0.3
	const TOUCH_SLACK := 0.15      ## tm: a collider this near the body counts as touched
	const SIDESTEP_TM := 6.0
	const BACK_TM := 1.5
	const SIDESTEP_TICKS := 180
	const REACHED_TM := 1.0

	var wedges := 0                ## how many times it has stepped aside
	var _anchor := PackedFloat64Array()
	var _anchor_tick := 0
	var _last_tick := -2
	var _step_am := PackedFloat64Array()   ## the sidestep's point (am) while stepping aside
	var _step_until := -1

	## The cell's-frame position of the absolute point `at` (am): through the stream in the endless
	## world; in the pool absolute and local are one.
	static func local_of(sim: PoolSim, at: PackedFloat64Array) -> Vector2:
		var world: Object = sim.get("world")
		return world.call("local_of_abs", at[0], at[1]) if world != null else Vector2(at[0], at[1])

	## The point to swim at now on the way to `goal` (the cell's frame). Call it every tick the bot
	## travels; a tick it skips starts the watch again.
	func aim(sim: PoolSim, goal: Vector2) -> Vector2:
		var pos := sim.motion.position
		var t := sim.tick
		var here := sim.absolute_position_am()
		if t > _last_tick + 1 or t < _last_tick or _anchor.is_empty():
			_anchor = here
			_anchor_tick = t
		_last_tick = t
		if t - _anchor_tick >= STUCK_TICKS:
			var moved := Vector2(here[0] - _anchor[0], here[1] - _anchor[1]).length()
			if moved < STUCK_TM and not sim.arena.rock_contact(pos, sim.phenotype.radius, TOUCH_SLACK).is_empty():
				wedges += 1
				var ahead := (goal - pos).normalized() if pos.distance_to(goal) > 1e-6 else Vector2.RIGHT
				var side := 1.0 if wedges % 2 == 1 else -1.0
				var step := ahead.orthogonal() * side * SIDESTEP_TM * ceili(wedges / 2.0) - ahead * BACK_TM
				_step_am = PackedFloat64Array([here[0] + step.x, here[1] + step.y])
				_step_until = t + SIDESTEP_TICKS
			_anchor = here
			_anchor_tick = t
		var to := goal
		if t < _step_until:
			var step_at := local_of(sim, _step_am)
			if pos.distance_to(step_at) > REACHED_TM:
				to = step_at
			else:
				_step_until = -1
		return sim.arena.route_point(pos, to, sim.phenotype.radius)


func _init(p_dir: Vector2, p_throttle := 1.0) -> void:
	dir = p_dir
	throttle = p_throttle


## A camper in `p_zone_id`; with `p_greedy` it also eats that zone's food (#33).
static func camper(p_zone_id: String, p_greedy := false) -> RefCounted:
	var bot = (load("res://game/dev/swim_bot.gd") as GDScript).new(Vector2.ZERO)
	bot.zone_id = p_zone_id
	bot.greedy = p_greedy
	return bot


## A homing swimmer for the absolute point `at` (x, y am; in the pool, its own coordinates).
static func toward(at: PackedFloat64Array, p_throttle := 1.0) -> RefCounted:
	var bot = (load("res://game/dev/swim_bot.gd") as GDScript).new(Vector2.ZERO, p_throttle)
	bot.goal_am = PackedFloat64Array([at[0], at[1]])
	return bot


## Tests and soak gates only, never game code or a smoke (tests/test_swim_bot.gd checks): sets the
## cell's top speed to PoolLayout.MAX_SPEED (6 tm/s), the cap the rings, the chunk timings and the
## rocks are proven against, which no legal body reaches, and refills its energy to capacity so it
## never slows to the starving speed. Call it before each step, since a respawn keeps the phenotype
## but not the energy. An overdriven straight swim averages at least 5.9 tm/s once up to speed.
static func overdrive(sim: PoolSim) -> void:
	sim.phenotype.speed = PoolLayout.MAX_SPEED
	sim.state.energy = sim.state.energy_capacity


func next_intent(sim: PoolSim) -> SimIntent:
	return keys.apply(sim, _swim(sim))


func _swim(sim: PoolSim) -> SimIntent:
	if not goal_am.is_empty():
		return _home_in(sim)
	if zone_id.is_empty():
		return SimIntent.new(dir.normalized() * throttle)
	return _camp(sim)


func _home_in(sim: PoolSim) -> SimIntent:
	if sim.dead:
		return SimIntent.new()
	var goal := Unjam.local_of(sim, goal_am)
	var pos := sim.motion.position
	var d := pos.distance_to(goal)
	if d <= ARRIVE_M:
		return SimIntent.new()
	if _unjam == null:
		_unjam = Unjam.new()
	var to := _unjam.aim(sim, goal) - pos
	if to.length() < 1e-6:
		return SimIntent.new()
	return SimIntent.new(to.normalized() * clampf(d / ARRIVE_M, MIN_THROTTLE, 1.0) * throttle)


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
				_forager.keys.trigger = ""   # this bot sends the keys
			_forager.park_at = Vector2(food.position)
			return _forager.next_intent(sim)
	return _swim_to(sim, center, float(z.radius) * 0.5)


## Swims to `target` round rocks, easing off within ARRIVE_M; holds still within `stop_within`.
func _swim_to(sim: PoolSim, target: Vector2, stop_within: float) -> SimIntent:
	var pos := sim.motion.position
	var d := pos.distance_to(target)
	if d <= stop_within:
		return SimIntent.new()
	var aim := sim.arena.route_point(pos, target, sim.phenotype.radius)
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
