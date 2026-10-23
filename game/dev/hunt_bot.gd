extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): a hunter cell
## that lives on what it kills, now that carrion comes only from kills (plan D1). It drives the
## hunter viability gate (plan D2, test_threat_gates) and threats_sim #22. Unlike EvadeBot it may
## read the whole sim (creatures, their brains, the carrion), as a test would; like player input it
## only returns a SimIntent and never changes the sim. The cell's jaw bites on contact (OD3), so
## hunting is swimming into the prey jaw first.
##
## Its priorities, highest first (plan section 16):
##  1. the EvadeBot reaction: a tell aimed at the cell is dodged out of its line on the side the cell
##     faces 0.4 s after it starts and held until the strike is over (it wraps an EvadeBot, which
##     hears the sim's events);
##  2. eat the carrion it can see (on screen at the default zoom), nearest first, and wait beside it
##     while too full to eat;
##  3. hurt below RETREAT_BELOW of its health, while it can still heal (energy above half), swim to
##     the unguarded RETREAT_ZONE and rest there until RESUME_ABOVE;
##  4. close on the nearest rammer that is not telling or striking, to a point BEHIND_M behind its
##     tail, and swim into it from its rear arc, or from any side once inside the nearest distance
##     its charge may start from (its attack's start_min_m), so the jaw bites where no charge can;
##  5. with no rammer to hunt, patrol PATROL's zones in turn.
## Travel keeps LAIR_CLEARANCE_M from every ambush lair; only the last CLOSE_IN_FAR_M to a rammer
## may go nearer.
##
##     var bot = load("res://game/dev/hunt_bot.gd").new()
##     sim.step(bot.next_intent(sim, events_from_the_last_step))

const EvadeBot := preload("res://game/dev/evade_bot.gd")

## m: the point it closes on lies this far behind the rammer's tail (plan section 16).
const BEHIND_M := 1.2
## rad: the cell is in the rammer's rear arc when its bearing from the rammer's heading is at least
## this (the rear 160 degrees); from there it swims straight in.
const REAR_ARC := deg_to_rad(100.0)
## m: the lair rule gives way this close to the rammer it hunts, which may graze by a lair.
const CLOSE_IN_FAR_M := 6.0
const RETREAT_BELOW := 0.4         ## health share that sends it to rest (plan section 16)
const RESUME_ABOVE := 0.7          ## health share at which it hunts again
const HEAL_ENERGY_SHARE := ActorState.REGEN_THRESHOLD   ## health regrows only above this energy share
const RETREAT_ZONE := "z_center"
const PATROL: PackedStringArray = ["z_n", "z_ne", "z_nw"]
const PATROL_ARRIVE_M := 3.0
const REST_M := 1.5                ## at the retreat spot, or beside food it cannot eat yet, it holds still
## m: every lair (an ambush species' site) is passed at least this far off, its 9 m leash plus 1.
const LAIR_CLEARANCE_M := 10.0
const DETOUR_MARGIN_M := 1.0       ## a detour aims this far outside the clearance circle
const SWITCH_SHARE := 0.6          ## change prey only for one this much nearer than the current one
## What it sees: the camera's view of the plane at the default zoom, on a 16:9 screen.
const VIEW_ASPECT := 16.0 / 9.0
const ARRIVE_M := 1.2              ## ease off the throttle within this distance of food
const TURN_THROTTLE := 0.08        ## at the food: just above the input deadzone, so the mouth turns onto it
const CONTACT_MARGIN_M := 0.1

var evade = EvadeBot.new()
var kills := 0                     ## creatures its own bites killed (from the events it is given)
var _prey_id := ""
var _patrol_index := 0
var _retreating := false


func _init() -> void:
	evade.base = _hunt
	# After a dodged strike the rammer recovers on the spot, unable to turn or strike: the time to
	# bite, not to swim away.
	evade.away_ticks = 0


## The intent for the coming tick. `events` are the ones the sim reported since the last call.
func next_intent(sim: PoolSim, events: Array) -> SimIntent:
	for e in events:
		if e.get("type", "") == "creature_died" and e.get("by", "") == CreatureField.PLAYER_ID:
			kills += 1
	return evade.next_intent(sim, events)


## The id of the rammer it hunts, or "".
func prey_id() -> String:
	return _prey_id


## True while it rests at the retreat spot to heal.
func is_retreating() -> bool:
	return _retreating


## Priorities 2-5 (EvadeBot's base intent).
func _hunt(sim: PoolSim) -> SimIntent:
	if sim.dead:
		return SimIntent.new()
	var pos := sim.motion.position
	var food := _seen_meat(sim)
	if not food.is_empty():
		return _eat(sim, food)
	var health_share := sim.state.health / sim.state.max_health
	var can_heal := sim.state.energy >= sim.state.energy_capacity * HEAL_ENERGY_SHARE
	if health_share < RETREAT_BELOW and can_heal:
		_retreating = true
	if _retreating and (health_share >= RESUME_ABOVE or not can_heal):
		_retreating = false
	if _retreating:
		var spot := _zone_center(sim, RETREAT_ZONE)
		return _travel(sim, spot, REST_M)
	var prey := _prey(sim)
	if prey != null:
		return _close_on(sim, prey)
	var goal := _zone_center(sim, PATROL[_patrol_index % PATROL.size()])
	if pos.distance_to(goal) <= PATROL_ARRIVE_M:
		_patrol_index = (_patrol_index + 1) % PATROL.size()
		goal = _zone_center(sim, PATROL[_patrol_index])
	return _travel(sim, goal, 0.0)


## The nearest meat on screen (ties by id), or {}.
func _seen_meat(sim: PoolSim) -> Dictionary:
	if not sim.phenotype.can_eat("meat"):
		return {}
	var cam := sim.layout.camera
	var best := {}
	var best_d := INF
	for item in sim.carrion.items:
		if not ViewFootprint.contains(sim.motion.position, item.position, cam, float(cam.distance), VIEW_ASPECT):
			continue
		var d := sim.motion.position.distance_to(item.position)
		if d < best_d or (d == best_d and str(item.id) < str(best.id)):
			best_d = d
			best = item
	return best


func _eat(sim: PoolSim, food: Dictionary) -> SimIntent:
	var pos := sim.motion.position
	var room := sim.state.energy_capacity - sim.state.energy
	if room < float(food.energy) * InteractionResolver.FEED_MIN_ROOM_SHARE:
		return _travel(sim, food.position, REST_M)   # wait beside it until there is room
	var contact := sim.phenotype.radius + float(food.radius) + CONTACT_MARGIN_M
	var aim := sim.arena.route_point(pos, food.position, sim.phenotype.radius)
	var throttle := clampf((pos.distance_to(food.position) - contact) / ARRIVE_M, TURN_THROTTLE, 1.0)
	return SimIntent.new((aim - pos).normalized() * throttle)


## The rammer to hunt: the current one while it lives and is not telling or striking, unless another
## is much nearer; else the nearest such one (ties by id). null when there is none.
func _prey(sim: PoolSim) -> CreatureField.Creature:
	if sim.creatures == null:
		return null
	var pos := sim.motion.position
	var current: CreatureField.Creature = null
	var best: CreatureField.Creature = null
	var best_d := INF
	for c in sim.creatures.creatures:
		if c.brain == null or c.brain.behavior != CreatureBrain.TERRITORIAL or _committed(c):
			continue
		var d := pos.distance_to(c.motion.position)
		if c.id == _prey_id:
			current = c
		if d < best_d or (d == best_d and c.id < best.id):
			best_d = d
			best = c
	if current != null and pos.distance_to(current.motion.position) * SWITCH_SHARE <= best_d:
		best = current
	_prey_id = best.id if best != null else ""
	return best


## Telling or striking: its line is set, so the cell keeps off it (the EvadeBot reaction handles a
## line aimed at the cell).
static func _committed(c: CreatureField.Creature) -> bool:
	return c.brain.state == CreatureBrain.ATTACK and c.brain.phase != CreatureBrain.RECOVER


## Toward the point BEHIND_M behind the rammer's tail; straight into it, jaw first, from its rear arc
## or from nearer than its charge may start (no tell starts there).
func _close_on(sim: PoolSim, prey: CreatureField.Creature) -> SimIntent:
	var pos := sim.motion.position
	var at := prey.motion.position
	var off := pos - at
	var bearing := absf(angle_difference(prey.motion.heading, off.angle())) if off.length() > 1e-6 else PI
	var no_charge_m := float(prey.brain.cfg.attack.start_min_m)
	var goal := at
	if bearing < REAR_ARC and off.length() >= no_charge_m:
		goal = at - Vector2.from_angle(prey.motion.heading) * (prey.phenotype.radius + BEHIND_M + sim.phenotype.radius)
	return _travel(sim, goal, 0.0, off.length() > CLOSE_IN_FAR_M)


## Full throttle toward `goal` round rocks (and lairs when `mind_lairs`); holds still within `stop_m`.
func _travel(sim: PoolSim, goal: Vector2, stop_m: float, mind_lairs := true) -> SimIntent:
	var pos := sim.motion.position
	if pos.distance_to(goal) <= stop_m:
		return SimIntent.new()
	var via := _round_lairs(sim, pos, goal) if mind_lairs else goal
	var aim := sim.arena.route_point(pos, via, sim.phenotype.radius)
	var to := aim - pos
	if to.length() < 1e-6:
		return SimIntent.new()
	return SimIntent.new(to.normalized())


## `goal`, or, when the straight way passes within LAIR_CLEARANCE_M of a lair (the nearest such lair
## first), a point beside that lair outside the clearance circle. A goal inside a circle is
## approached straight.
func _round_lairs(sim: PoolSim, pos: Vector2, goal: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for lair in _lairs(sim):
		if goal.distance_to(lair) < LAIR_CLEARANCE_M:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(lair, pos, goal)
		var gap := closest.distance_to(lair)
		if gap >= LAIR_CLEARANCE_M:
			continue
		var d := pos.distance_to(closest)
		if d < best_d:
			best_d = d
			var out := closest - lair
			if out.length() < 1e-6:
				out = (goal - pos).orthogonal()
			best = lair + out.normalized() * (LAIR_CLEARANCE_M + DETOUR_MARGIN_M)
	return best if best.is_finite() else goal


## Every ambush site's home.
func _lairs(sim: PoolSim) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if sim.species == null:
		return out
	for s in sim.species.sites:
		if sim.species.behavior_of(str(s.species)) == CreatureBrain.AMBUSH:
			out.append(s.home)
	return out


func _zone_center(sim: PoolSim, zone_id: String) -> Vector2:
	var z := sim.region.zone(zone_id)
	return z.center if not z.is_empty() else sim.layout.spawn
