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
##
## Threats (M1 step 3) join only when species data is given (create(..., species)); without it the
## tick is exactly step 2's. With it the tick runs, in this fixed order:
##  1. the senses' body snapshot, once, before anything moves (the player, then creatures in number
##     order);
##  2. each creature in number order: think when due (it perceives the snapshot through its own
##     senses; the token decides whether the player is engageable to it), drive, and set its
##     velocity by the drive (steer, tell, burst or glide). A frozen creature (dev) coasts;
##  3. the player steers;
##  4. the player moves, then each creature;
##  5. contacts: overlapping bodies are pushed apart once (positions only, by inverse mass), each
##     pushed body settles against rocks and the wall, every creature is clamped to its leash disc
##     last, and a striking creature touching a rock ahead is blocked;
##  6. metabolism: the player as in step 2, creatures at their species' metabolism share (a
##     starved creature dies and leaves no carcass);
##  7. ecology, then the creature field's respawn queue and stuck removals;
##  8. sync the resolver actors; 9. feeding: the player, then each creature eating by its drive.
## Creatures are not saved; every timer is a whole tick and every RNG is seeded from the world seed.

const DT := 1.0 / 60.0
const MAX_FOOD_RADIUS := 0.3          ## the largest food item; the reach search includes it
const TOUCH_MARGIN := 0.05            ## food within both radii plus this is "touching" the cell
const REFUSAL_REPEAT_S := 0.5         ## the same refusal is reported at most this often
const FEED_LOG_SIZE := 6
## World and encounter seeds come from the world seed, kept apart (Bible section 13).
const SEED_STRIDE := 1000003
const REGION_SEED_OFFSET := 1
const CARRION_SEED_OFFSET := 2
const ENCOUNTER_SEED_OFFSET := 3       ## the creature field's stream: respawn delays and brain seeds
const DEBUG_CARRION_AHEAD_M := 4.0
## m: debug_spawn_threat_ahead places the creature this far in front of the cell, facing it, so it
## is in view and inside the ambush hunter's sight.
const DEBUG_THREAT_AHEAD_M := 6.0
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
## Why the cell died, while it is dead: {"cause": "starved"|"killed", "by" (creature id, "debug" or
## ""), "by_species", "reason" (the killer species' death_reason, or "")}. {} while alive.
var death := {}
var species: SpeciesCatalog            ## null: the step 2 pool, with no creatures
var creatures: CreatureField           ## null without species
## Dev switches (debug_set_ai_frozen, debug_set_hidden); part of the state, so they are hashed.
var dev_ai_frozen := false
var dev_hidden := false
var stats := {"plankton_eaten": 0, "carrion_eaten": 0, "plant_taken": 0.0, "energy_supplied": 0.0,
	"energy_absorbed": 0.0, "points_food": 0, "points_survival": 0, "distance_m": 0.0,
	"kills": 0, "hits_dealt": 0, "hits_taken": 0, "damage_dealt": 0.0, "damage_taken": 0.0, "dodges": 0,
	"creature_meals": 0, "creature_deaths": 0}
## The last FEED_LOG_SIZE reported feeding results, newest last:
## {"tick", "food_id", "kind", "allowed", "reason"}
var feed_log: Array[Dictionary] = []

var _events: Array[Dictionary] = []
var _alive_ticks := 0
var _was_starving := false
var _last_refusal := {}    ## {"food_id", "reason", "touching", "at"}
var _contact := {}         ## {"food_id", "since"}: the food being touched, and since when


## Builds the pool for a save. The save's position is used when it is a clear place inside the
## soft wall; otherwise the cell starts at the layout spawn. With `p_species` the pool has creatures:
## every site that passes the spawn check from the cell's place is filled, the others wait.
static func create(p_save: SaveGame, p_catalog: PartCatalog, p_layout: PoolLayout, p_species: SpeciesCatalog = null) -> PoolSim:
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
	if p_species != null:
		sim.species = p_species
		sim.creatures = CreatureField.create(p_species, p_catalog, p_layout, sim.region,
			p_save.world_seed * SEED_STRIDE + ENCOUNTER_SEED_OFFSET)
		sim.creatures.populate(sim.arena, sim.motion.position, 0)
	# The starting world is not news.
	sim.plankton.events.clear()
	sim.carrion.events.clear()
	if sim.creatures != null:
		sim.creatures.take_events()
	sim._was_starving = sim.state.is_starving()
	return sim


## Sim time in seconds: the only clock (cooldowns, carrion age, drift).
func now() -> float:
	return tick * DT


func step(intent: SimIntent) -> void:
	if creatures != null:
		_creatures_act(creatures.bodies(player_body()))
	var moved := 0.0
	if not dead:
		var move := intent.move if intent != null and intent.move.is_finite() else Vector2.ZERO
		Locomotion.steer(motion, move, phenotype, state.speed_multiplier(), DT)
		moved = arena.move(motion, phenotype.radius, DT)
		stats.distance_m += moved
	else:
		motion.prev_position = motion.position
		motion.prev_heading = motion.heading
	var creature_moved: Array[float] = []
	if creatures != null:
		creature_moved = _move_creatures()
		_contacts()
	if not dead:
		_metabolism(moved)
	if creatures != null:
		_creature_metabolism(creature_moved)
	region.tick(DT)
	plankton.tick(region, arena, tick, now())
	carrion.tick(DT, now(), region, arena)
	if creatures != null:
		creatures.tick_spawns(arena, _player_place(), tick)
		creatures.remove_stuck(_player_place(), tick)
	_take_field_events()
	_sync_actor()
	if creatures != null:
		_sync_creatures()
	if not dead:
		_try_feed()
	if creatures != null:
		_creatures_feed()
		_take_field_events()
	tick += 1


## Events since the last call, oldest first. Each has a "type":
##   ate {kind, food_id, zone, supplied, absorbed, points, position}
##   refused {kind, food_id, reason, touching, contact_s}
##   earned {points, reason}; starving_started; starving_ended; respawned
##   died {cause, by, by_species, reason, position} (cause "starved" or "killed")
##   zone_empty {zone}; zone_regrown {zone}
##   carrion_spawned {source, food_id, position}; carrion_expired {food_id, position}
##   debug {command, ...}
## With creatures (M1 step 3), from the field and the brains (each with the creature's id):
##   creature_spawned {id, species, site, position, heading, debug}
##   creature_removed {id, species, reason}
##   creature_noticed {id, target, by, position}; creature_gave_up {id, target, reason, position}
##   creature_tell {id, target, kind, ticks, lane, position}; tell_cancelled {id, target, reason, position}
##   creature_strike {id, target, kind, position, heading}
##   creature_recovered {id, target, outcome, position}; creature_fled {id, from, position}
## and from the sim: creature_ate {id, kind, food_id}; creature_died {id, species, cause, by, position, carcass}
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
	var out := {
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
		"death": death.duplicate(),
		"dev_ai_frozen": dev_ai_frozen,
		"dev_hidden": dev_hidden,
	}
	if creatures != null:
		# creatures, creature_next, creature_rng, spawn_queue, engaged_on_player
		out.merge(creatures.snapshot())
		out["niches"] = region.niches.duplicate(true)
	return out


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
	death = {}
	_update_starving()   # a cell that starved to death comes back fed
	_contact.clear()
	_last_refusal.clear()
	_emit({"type": "respawned"})


func write_position_to_save() -> void:
	save.player["position"] = PlaneSpace.to_save(motion.position)


## Where the lineage returns after a death: the generation start, which in M1 is the layout spawn
## (derived, never saved). {"position", "heading"}.
func checkpoint() -> Dictionary:
	return {"position": layout.spawn, "heading": layout.spawn_heading}


## The cell in the senses' body format (CreatureSenses), as creatures may perceive it this tick.
func player_body() -> Dictionary:
	return {"id": CreatureField.PLAYER_ID, "species": SpeciesCatalog.PLAYER_SPECIES, "position": motion.position,
		"velocity": motion.velocity, "radius": phenotype.radius, "alive": not dead, "concealed": is_concealed(),
		"engageable": true, "bite": phenotype.bite_damage > 0.0, "spikes": phenotype.spikes.size()}


## True while no creature can sense or strike the cell (the dev "hide from AI" switch).
func is_concealed() -> bool:
	return dev_hidden


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


## Places a dev creature (debug: outside the niche count, never respawned) at a clear point.
func debug_spawn_creature(species_id: String, p: Vector2, heading: float) -> bool:
	if creatures == null or not species.has_species(species_id) or not is_finite(heading):
		return false
	if not arena.is_clear(p, species.phenotype(species_id, catalog).radius):
		return false
	var c := creatures.spawn_at(species_id, p, heading, "", tick, true)
	if c == null:
		return false
	_take_field_events()
	_emit({"type": "debug", "command": "spawn_creature", "species": species_id, "id": c.id, "position": p})
	return true


## Places a dev creature DEBUG_THREAT_AHEAD_M in front of the cell, facing it.
func debug_spawn_threat_ahead(species_id: String) -> bool:
	var p := motion.position + Vector2.from_angle(motion.heading) * DEBUG_THREAT_AHEAD_M
	return debug_spawn_creature(species_id, p, (motion.position - p).angle())


## Freezes every brain: creatures think and drive nothing and coast (their timers keep counting).
func debug_set_ai_frozen(on: bool) -> bool:
	if creatures == null:
		return false
	dev_ai_frozen = on
	_emit({"type": "debug", "command": "freeze_ai", "on": on})
	return true


## Hides the cell from every creature: it is concealed, so the senses skip it, and every brain
## forgets it now (an engagement with it gives up, target_gone).
func debug_set_hidden(on: bool) -> bool:
	if creatures == null:
		return false
	dev_hidden = on
	if on:
		_forget_player_everywhere()
	_emit({"type": "debug", "command": "hide_from_ai", "on": on})
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
		_player_dies("starved", "", "", "")
		return
	var before := alive_s
	_alive_ticks += 1
	alive_s = _alive_ticks * DT
	var earned := Lineage.earn(save, Lineage.survival_points(before, alive_s))
	if earned > 0:
		stats.points_survival += earned
		_emit({"type": "earned", "points": earned, "reason": "survival"})


## The cell dies: it stops where it is, `death` records why and `died` reports it. The cell leaves
## no carrion (plan D12).
func _player_dies(cause: String, by: String, by_species: String, reason: String) -> void:
	dead = true
	motion.velocity = Vector2.ZERO
	death = {"cause": cause, "by": by, "by_species": by_species, "reason": reason}
	_emit({"type": "died", "cause": cause, "by": by, "by_species": by_species, "reason": reason, "position": motion.position})


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
	var zone: String = food.zone if food.kind == "plant" else ""
	var supplied := _take_food(food, wanted)
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


## Takes an eaten item out of the world and returns the energy it supplies: a plant draws on its
## zone's stock first (a stale item supplies nothing), meat supplies what it holds. Shared by the
## cell and the creatures; points are the caller's business.
func _take_food(food: Dictionary, wanted: float) -> float:
	if food.kind == "plant":
		var supplied := region.take(food.zone, wanted)   # stock first
		plankton.consume(food.id)
		return supplied
	carrion.consume(food.id)
	return wanted


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
	if creatures != null:
		_events.append_array(creatures.take_events())


## Where the field measures spawn safety from: the cell, or its checkpoint while it is dead.
func _player_place() -> Vector2:
	return checkpoint().position if dead else motion.position


# --- creatures (M1 step 3) ---

## Tick steps 1-2: each creature in number order thinks when due (on `snapshot`, the bodies as
## they were at the start of the tick), drives, and sets its velocity. Scripted bodies swim by
## their script; frozen creatures coast.
func _creatures_act(snapshot_bodies: Array[Dictionary]) -> void:
	var food: Array = []
	var food_listed := false
	for c in creatures.creatures:
		var speed_mul := c.state.speed_multiplier()
		if c.scripted:
			Locomotion.steer(c.motion, c.script_move, c.phenotype, speed_mul, DT)
			continue
		if dev_ai_frozen:
			c.drive = CreatureField.idle_drive(c.motion.heading)
			Locomotion.steer(c.motion, Vector2.ZERO, c.phenotype, speed_mul, DT)
			continue
		var self_view := creatures.self_view_of(c)
		if creatures.think_due(c, tick):
			if c.brain.state == CreatureBrain.FORAGE and not food_listed:
				food = plankton.items + carrion.items
				food_listed = true
			creatures.think(c, snapshot_bodies, food, arena, tick, self_view)
		var d := creatures.drive(c, arena, tick, self_view)
		CreatureBrain.move_body(c.brain, c.motion, d, c.phenotype, speed_mul, DT)
	_take_field_events()


## Tick step 4 for creatures: each moves by its velocity. Returns the distances, in creature order.
func _move_creatures() -> Array[float]:
	var out: Array[float] = []
	for c in creatures.creatures:
		out.append(arena.move(c.motion, c.phenotype.radius, DT))
	return out


## Tick step 5: one separation pass over every overlapping pair (the cell first, then creatures in
## number order), each pushed body settled against rocks and the wall, then every creature clamped
## to its leash disc (last, so the leash holds at the end of every tick), then a strike that runs
## into a rock ahead is blocked.
func _contacts() -> void:
	var motions: Array[Locomotion.MotionState] = []
	var radii := PackedFloat64Array()
	var masses := PackedFloat64Array()
	if not dead:
		motions.append(motion)
		radii.append(phenotype.radius)
		masses.append(phenotype.mass)
	for c in creatures.creatures:
		motions.append(c.motion)
		radii.append(c.phenotype.radius)
		masses.append(c.phenotype.mass)
	var n := motions.size()
	var pushed := PackedByteArray()
	pushed.resize(n)
	for i in n:
		for j in range(i + 1, n):
			var reach := radii[i] + radii[j]
			if motions[i].position.distance_squared_to(motions[j].position) >= reach * reach:
				continue   # apart: the common case, checked here without a call
			if PoolArena.separate(motions[i], radii[i], masses[i], motions[j], radii[j], masses[j]):
				pushed[i] = 1
				pushed[j] = 1
	for i in n:
		if pushed[i] == 1:
			arena.settle(motions[i], radii[i])
	for c in creatures.creatures:
		if c.brain == null:
			continue
		var disc := CreatureBrain.leash_disc(c.brain)
		PoolArena.clamp_to_disc(c.motion, disc.center, disc.radius)
		if CreatureBrain.is_striking(c.brain):
			var rock := arena.rock_contact(c.motion.position, c.phenotype.radius, PoolArena.CONTACT_SLACK, c.motion.heading,
				CreatureBrain.BLOCKED_BEARING)
			if not rock.is_empty():
				CreatureBrain.on_blocked(c.brain, tick)
	_take_field_events()


## Tick step 6 for creatures: metabolism at the species' share of the cell's rates (upkeep, moving,
## starving and regrowth together); a scripted body uses the cell's own rates. `moved` is in
## creature order. A creature that starves dies.
func _creature_metabolism(moved: Array[float]) -> void:
	var list := creatures.creatures.duplicate()
	for i in list.size():
		var c: CreatureField.Creature = list[i]
		var share := 1.0 if c.scripted else float(species.species[c.species_id].metabolism_share)
		c.state.tick(c.phenotype, DT * share, moved[i] * share)
		if not c.state.is_alive():
			_creature_dies(c, "starved", "")


## A creature dies: creature_died reports it (with its carcass's food ids) and the field removes it,
## freeing its niche slot and queueing its site. Only a kill leaves a carcass, unless the species'
## carcass.on_starve says otherwise; a scripted body leaves none.
func _creature_dies(c: CreatureField.Creature, cause: String, by: String) -> void:
	var carcass := PackedStringArray()
	if not c.scripted and (cause == "killed" or bool(species.species[c.species_id].carcass.on_starve)):
		carcass = creatures.drop_carcass(c, carrion, arena)
	stats.creature_deaths += 1
	_emit({"type": "creature_died", "id": c.id, "species": c.species_id, "cause": cause, "by": by,
		"position": c.motion.position, "carcass": Array(carcass)})
	creatures.remove(c, cause, tick, true)
	_take_field_events()


func _sync_creatures() -> void:
	for c in creatures.creatures:
		c.actor.position = c.motion.position
		c.actor.heading = c.motion.heading


## Tick step 9 for creatures: each one whose drive names a food item eats it through the resolver,
## after the cell has fed. No points: those are the lineage's alone.
func _creatures_feed() -> void:
	for c in creatures.creatures:
		var food_id := str(c.drive.get("feed", ""))
		if food_id.is_empty():
			continue
		var food := _food_item(food_id)
		if food.is_empty():
			continue
		var r := InteractionResolver.feed(c.actor, food, now(), c.state.energy_capacity - c.state.energy)
		if not r.allowed:
			continue
		var supplied := _take_food(food, float(r.effect.energy))
		if supplied <= 0.0:
			continue
		c.state.eat(supplied)
		stats.creature_meals += 1
		_emit({"type": "creature_ate", "id": c.id, "kind": food.kind, "food_id": food.id})


func _food_item(id: String) -> Dictionary:
	for list in [plankton.items, carrion.items]:
		for item in list:
			if item.id == id:
				return item
	return {}


## Every brain forgets the cell, as if it had left the world (target_gone), and the token is freed.
func _forget_player_everywhere() -> void:
	for c in creatures.creatures:
		if c.brain != null:
			CreatureBrain.on_target_gone(c.brain, CreatureField.PLAYER_ID, tick)
			creatures.update_token(c)
	_take_field_events()


func _emit(event: Dictionary) -> void:
	_events.append(event)


static func _pair(v: Vector2) -> Array:
	return [v.x, v.y]
