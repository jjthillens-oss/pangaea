class_name PoolSim
extends RefCounted
## The pool's gameplay (M1 step 2): one cell, plankton, carrion and rocks, advanced in fixed 60 Hz
## ticks by step(). It is deterministic for a world seed and the intents given. Scenes draw its
## state and react to its events; they never pass it a frame delta.
##
## Feeding always goes through InteractionResolver, and every point goes through Lineage.earn.
## Tick order (tests depend on it): steer, move, metabolism, ecology, sync the resolver actor,
## feed, advance the tick. A dead cell skips steering, moving, metabolism and feeding; the world
## keeps living behind the death notice.

const DT := 1.0 / 60.0
const MAX_FOOD_RADIUS := 0.3          ## the largest food item; the reach search includes it
const TOUCH_MARGIN := 0.05            ## food within both radii plus this is "touching" the cell
const REFUSAL_REPEAT_S := 0.5         ## the same refusal is reported at most this often
const FEED_LOG_SIZE := 6
## World and encounter seeds come from the world seed, kept apart (Bible section 13).
const SEED_STRIDE := 1000003
const REGION_SEED_OFFSET := 1
const CARRION_SEED_OFFSET := 2
const DEBUG_CARRION_AHEAD_M := 4.0
## Refusals never reported: no food in reach is normal, and swallowing is a meal in progress.
const QUIET_REASONS: PackedStringArray = ["out of reach", "still swallowing"]

var tick := 0
var save: SaveGame
var catalog: PartCatalog
var layout: PoolLayout
var phenotype: Phenotype
var state: ActorState
var motion: Locomotion.MotionState
var actor: InteractionResolver.Actor   ## persistent, so cooldowns survive between ticks
var region: EcologyRegion
var arena: PoolArena
var plankton: PlanktonField
var carrion: CarrionField
var alive_s := 0.0                     ## since spawn, respawn or continue; drives survival points
var dead := false
var stats := {"plankton_eaten": 0, "carrion_eaten": 0, "plant_taken": 0.0, "energy_supplied": 0.0,
	"energy_absorbed": 0.0, "points_food": 0, "points_survival": 0, "distance_m": 0.0}
## The last FEED_LOG_SIZE reported feeding results, newest last:
## {"tick", "food_id", "kind", "allowed", "reason"}
var feed_log: Array[Dictionary] = []

var _events: Array[Dictionary] = []
var _alive_ticks := 0
var _was_starving := false
var _last_refusal := {}    ## {"food_id", "reason", "touching", "at"}
var _contact := {}         ## {"food_id", "since"}: the food being touched, and since when


## Builds the pool for a save. The save's position is used when it is a clear place inside the
## soft wall; otherwise the cell starts at the layout spawn.
static func create(p_save: SaveGame, p_catalog: PartCatalog, p_layout: PoolLayout) -> PoolSim:
	var sim := PoolSim.new()
	sim.save = p_save
	sim.catalog = p_catalog
	sim.layout = p_layout
	sim.phenotype = Phenotype.derive(p_save.genome, p_catalog)
	sim.state = ActorState.fresh(sim.phenotype)
	sim.arena = p_layout.build_arena()
	sim.region = p_layout.build_region(p_save.world_seed * SEED_STRIDE + REGION_SEED_OFFSET)

	var position := p_layout.spawn
	var heading := p_layout.spawn_heading
	var saved = p_save.player.get("position")
	var restored := PlaneSpace.from_save(saved) if saved is Array else Vector2.INF
	if sim.arena.is_clear(restored, sim.phenotype.radius) and not restored.is_equal_approx(p_layout.spawn):
		# Continuing elsewhere: face the nearest zone (heading is not saved).
		position = restored
		heading = sim._nearest_zone_direction(position).angle()
	sim.motion = Locomotion.MotionState.new(position, heading)
	sim.actor = InteractionResolver.Actor.new("player", position, heading, sim.phenotype)

	sim.plankton = PlanktonField.create(p_layout.plankton)
	sim.plankton.fill(sim.region, sim.arena, 0, 0.0)
	sim.carrion = CarrionField.create(p_layout.carrion, p_save.world_seed * SEED_STRIDE + CARRION_SEED_OFFSET)
	sim.carrion.place_initial(sim.arena)
	# The starting world is not news.
	sim.plankton.events.clear()
	sim.carrion.events.clear()
	sim._was_starving = sim.state.is_starving()
	return sim


## Sim time in seconds: the only clock (cooldowns, carrion age, drift).
func now() -> float:
	return tick * DT


func step(intent: SimIntent) -> void:
	if not dead:
		var move := intent.move if intent != null and intent.move.is_finite() else Vector2.ZERO
		Locomotion.steer(motion, move, phenotype, state.speed_multiplier(), DT)
		var moved := arena.move(motion, phenotype.radius, DT)
		stats.distance_m += moved
		_metabolism(moved)
	else:
		motion.prev_position = motion.position
		motion.prev_heading = motion.heading
	region.tick(DT)
	plankton.tick(region, arena, tick, now())
	carrion.tick(DT, now(), region, arena)
	_take_field_events()
	_sync_actor()
	if not dead:
		_try_feed()
	tick += 1


## Events since the last call, oldest first. Each has a "type":
##   ate {kind, food_id, zone, supplied, absorbed, points, position}
##   refused {kind, food_id, reason, touching, contact_s}
##   earned {points, reason}; starving_started; starving_ended; died {cause}; respawned
##   zone_empty {zone}; zone_regrown {zone}
##   carrion_spawned {source, food_id, position}; carrion_expired {food_id, position}
##   debug {command, ...}
func drain_events() -> Array[Dictionary]:
	_take_field_events()
	var out := _events
	_events = []
	return out


## Full state, for the debug panel and for hashing. Ids that are random per run (lineage, genome)
## are left out, so two runs from the same seed and intents compare equal.
func snapshot() -> Dictionary:
	var zones := []
	for z in region.zones:
		zones.append({"id": z.id, "amount": z.amount})
	var plants := []
	for item in plankton.items:
		plants.append({"id": item.id, "zone": item.zone, "position": _pair(item.position), "anchor": _pair(item.anchor)})
	var meats := []
	for item in carrion.items:
		meats.append({"id": item.id, "position": _pair(item.position), "age": item.age, "energy": item.energy,
			"source": item.source})
	return {
		"tick": tick,
		"alive_ticks": _alive_ticks,
		"dead": dead,
		"position": _pair(motion.position),
		"velocity": _pair(motion.velocity),
		"heading": motion.heading,
		"energy": state.energy,
		"health": state.health,
		"cooldowns": actor.cooldowns.duplicate(),
		"points": save.adaptation_points,
		"zones": zones,
		"region_rng": region.rng.state,
		"plankton": plants,
		"plankton_next": plankton.next_number,
		"carrion": meats,
		"carrion_next": carrion.next_number,
		"carrion_rng": carrion.rng.state,
		"next_supply_at": carrion.next_supply_at if is_finite(carrion.next_supply_at) else -1.0,
		"stats": stats.duplicate(),
	}


func state_hash() -> int:
	return hash(JSON.stringify(snapshot(), "", true, true))


## The nearest food this body can eat: {} or {"id", "kind", "position"}. For the starving arrow.
func nearest_edible() -> Dictionary:
	var best := {}
	var best_d := INF
	for list in [plankton.items, carrion.items]:
		for item in list:
			if not phenotype.can_eat(item.kind):
				continue
			var d := motion.position.distance_squared_to(item.position)
			if d < best_d or (d == best_d and str(item.id) < str(best.id)):
				best_d = d
				best = item
	return {} if best.is_empty() else {"id": best.id, "kind": best.kind, "position": best.position}


## The interim death checkpoint: back to the layout spawn with fresh condition and no cooldowns.
## The world is kept.
func respawn_player() -> void:
	motion.place(layout.spawn, layout.spawn_heading)
	state = ActorState.fresh(phenotype)
	actor.cooldowns.clear()
	_sync_actor()
	alive_s = 0.0
	_alive_ticks = 0
	dead = false
	_was_starving = state.is_starving()
	_contact.clear()
	_last_refusal.clear()
	_emit({"type": "respawned"})


func write_position_to_save() -> void:
	save.player["position"] = PlaneSpace.to_save(motion.position)


## Movement over the last tick, per second (for camera look-ahead).
func display_velocity() -> Vector2:
	return (motion.position - motion.prev_position) / DT


## The zone whose center is nearest the cell, or "".
func nearest_zone_id() -> String:
	var best := ""
	var best_d := INF
	for z in region.zones:
		var d := motion.position.distance_squared_to(z.center)
		if d < best_d:
			best_d = d
			best = z.id
	return best


# Dev commands (dev tools and tests only). Each reports a "debug" event and returns whether it applied.

func debug_set_energy(value: float) -> bool:
	if not is_finite(value):
		return false
	state.energy = clampf(value, 0.0, state.energy_capacity)
	_emit({"type": "debug", "command": "set_energy", "value": state.energy})
	_update_starving()
	return true


func debug_empty_zone(zone_id: String) -> bool:
	var z := region.zone(zone_id)
	if z.is_empty():
		return false
	region.take(zone_id, z.amount)
	plankton.clear_zone(zone_id)
	_emit({"type": "debug", "command": "empty_zone", "zone": zone_id})
	return true


func debug_spawn_carrion_ahead() -> bool:
	var p := motion.position + Vector2.from_angle(motion.heading) * DEBUG_CARRION_AHEAD_M
	if not arena.is_clear(p, carrion.item_radius):
		return false
	carrion.spawn(p, "debug")
	_emit({"type": "debug", "command": "spawn_carrion", "position": p})
	return true


## Moves the cell to a clear point at rest; keeps the heading unless one is given.
func debug_teleport(p: Vector2, heading: float = NAN) -> bool:
	if not arena.is_clear(p, phenotype.radius):
		return false
	motion.place(p, heading if is_finite(heading) else motion.heading)
	_sync_actor()
	_contact.clear()
	_emit({"type": "debug", "command": "teleport", "position": p})
	return true


func _metabolism(moved: float) -> void:
	state.tick(phenotype, DT, moved)
	_update_starving()
	if not state.is_alive():
		dead = true
		motion.velocity = Vector2.ZERO
		_emit({"type": "died", "cause": "starved"})
		return
	var before := alive_s
	_alive_ticks += 1
	alive_s = _alive_ticks * DT
	var earned := Lineage.earn(save, Lineage.survival_points(before, alive_s))
	if earned > 0:
		stats.points_survival += earned
		_emit({"type": "earned", "points": earned, "reason": "survival"})


func _update_starving() -> void:
	var starving := state.is_starving()
	if starving != _was_starving:
		_was_starving = starving
		_emit({"type": "starving_started" if starving else "starving_ended"})


## Offers the food in reach to the resolver, nearest first (ties by id). The first allowed meal is
## committed; otherwise the nearest reportable refusal is noted.
func _try_feed() -> void:
	var reach := phenotype.radius + InteractionResolver.FEED_REACH + MAX_FOOD_RADIUS
	var candidates := plankton.items_near(motion.position, reach)
	candidates.append_array(carrion.items_near(motion.position, reach))
	candidates.sort_custom(_closer_then_id)
	var room := state.energy_capacity - state.energy
	var refused := {}
	var reason := ""
	for food in candidates:
		var r := InteractionResolver.feed(actor, food, now(), room)
		if r.allowed:
			_commit_feed(food, r.effect)
			return
		if r.reason == "still swallowing":
			return
		if refused.is_empty() and not QUIET_REASONS.has(r.reason):
			refused = food
			reason = r.reason
	if refused.is_empty():
		_contact.clear()
	else:
		_note_refusal(refused, reason)


func _closer_then_id(a: Dictionary, b: Dictionary) -> bool:
	var da := motion.position.distance_squared_to(a.position)
	var db := motion.position.distance_squared_to(b.position)
	return da < db if da != db else str(a.id) < str(b.id)


func _commit_feed(food: Dictionary, effect: Dictionary) -> void:
	var wanted := float(effect.energy)
	var supplied := wanted
	var zone := ""
	if food.kind == "plant":
		zone = food.zone
		supplied = region.take(zone, wanted)   # stock first
		plankton.consume(food.id)
	else:
		carrion.consume(food.id)
	_contact.clear()
	_last_refusal.clear()
	if supplied <= 0.0:
		return   # a stale item: removed, nothing granted
	var absorbed := state.eat(supplied)
	var points := Lineage.earn(save, int(effect.points) if supplied >= wanted - 1e-6 else 0)
	if food.kind == "plant":
		stats.plankton_eaten += 1
		stats.plant_taken += supplied
	else:
		stats.carrion_eaten += 1
	stats.energy_supplied += supplied
	stats.energy_absorbed += absorbed
	stats.points_food += points
	_log_feed(food, true, "")
	_emit({"type": "ate", "kind": food.kind, "food_id": food.id, "zone": zone, "supplied": supplied,
		"absorbed": absorbed, "points": points, "position": food.position})
	_update_starving()


## Reports a refusal when the (food, reason) pair changes, when the cell starts touching that
## food, or every REFUSAL_REPEAT_S while it lasts. Diet refusals come before reach, so one can be
## reported before contact; the touching report (the one hints wait for) is never held back by it.
## contact_s is how long the cell has been touching that food.
func _note_refusal(food: Dictionary, reason: String) -> void:
	var touching := motion.position.distance_to(food.position) <= phenotype.radius + float(food.radius) + TOUCH_MARGIN
	if not touching:
		_contact.clear()
	elif _contact.get("food_id", "") != food.id:
		_contact = {"food_id": food.id, "since": now()}
	var contact_s: float = now() - float(_contact.since) if touching else 0.0
	var same: bool = _last_refusal.get("food_id", "") == food.id and _last_refusal.get("reason", "") == reason \
		and (not touching or bool(_last_refusal.get("touching", false)))
	if same and now() - float(_last_refusal.at) < REFUSAL_REPEAT_S - 1e-9:
		return
	_last_refusal = {"food_id": food.id, "reason": reason, "touching": touching, "at": now()}
	_log_feed(food, false, reason)
	_emit({"type": "refused", "kind": food.kind, "food_id": food.id, "reason": reason,
		"touching": touching, "contact_s": contact_s})


func _log_feed(food: Dictionary, allowed: bool, reason: String) -> void:
	feed_log.append({"tick": tick, "food_id": food.id, "kind": food.kind, "allowed": allowed, "reason": reason})
	if feed_log.size() > FEED_LOG_SIZE:
		feed_log.pop_front()


func _nearest_zone_direction(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for z in region.zones:
		var d := from.distance_squared_to(z.center)
		if d < best_d:
			best_d = d
			best = z.center - from
	return best


func _sync_actor() -> void:
	actor.position = motion.position
	actor.heading = motion.heading


func _take_field_events() -> void:
	_events.append_array(plankton.events)
	plankton.events.clear()
	_events.append_array(carrion.events)
	carrion.events.clear()


func _emit(event: Dictionary) -> void:
	_events.append(event)


static func _pair(v: Vector2) -> Array:
	return [v.x, v.y]
