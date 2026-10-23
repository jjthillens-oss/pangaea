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
##  8. sync the resolver actors; 9. feeding: the player, then each creature eating by its drive;
## 10. combat, only through InteractionResolver: (a) the cell's automatic bite and ram on the
##     creatures it touches, (b) creature strikes in number order (only in a strike's burst or
##     glide, at most one hit per strike), each landed hit with its knockback and the speed clamp
##     (c), then (d) deaths: the cell first, then creatures in number order (carcass, removal,
##     queue). Every body alive when combat begins may attack, so a mutual kill kills both (T12);
## 11. dodges: a strike on the cell that ended this tick without a hit (missed or blocked);
## 12. shelter: when its last tick passes, grace_ended {reason: "timeout"}.
## Creatures are not saved; every timer is a whole tick and every RNG is seeded from the world seed.
##
## The endless world (S1): create(..., p_world) with world content builds the sea that goes on
## instead of the walled pool. `world` (a WorldStream) streams generated chunks in and out round the
## cell, moves the floating origin and decides which creatures sleep; its block runs first in every
## tick (WorldStream.step), and every creature loop of the tick runs over the awake creatures only.
## Positions stay local (tm, float32) to the origin; absolute_position_am() is the float64 place.
## Pool mode (p_world null) never builds any of it, so its ticks and hashes are exactly M1's.
##
## Checkpoints (plan section 13): a death returns the cell to checkpoint(), the generation start.
## With creatures, respawn_player() follows rules C1-C5: the cell at the checkpoint (or the nearest
## clear point), every creature within respawn_clear_m sent home, every brain forgetting the cell
## (its killer ignores it for killer_ignore_s), fresh condition with the streak's energy share, and
## the streak's shelter. Sheltered, the cell is concealed (no creature senses it) and no strike
## hits it; a new lineage and a continued run start sheltered too. Its own landed hit ends shelter.

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
const DEBUG_KILLER := "debug"           ## `by` for a death caused by a dev command
## Refusals never reported: no food in reach is normal, and swallowing is a meal in progress.
const QUIET_REASONS: PackedStringArray = ["out of reach", "still swallowing"]
## Attack refusals never reported (plan section 9): contact without a weapon, a weapon cooling down
## or a body backing away are normal and say nothing the player can act on. The others ("jaw is not
## facing it", "no spike points at it", "too big to bite") become hints.
const ATTACK_QUIET_REASONS: PackedStringArray = ["out of reach", "jaw is recovering", "spikes are recovering",
	"not moving toward it", "needs a jaw", "needs a spike"]
const ATTACK_LOG_SIZE := 6              ## a bite and a ram for the last three ticks, like FEED_LOG_SIZE
## m: when the checkpoint is not clear (never for the real layout), the cell goes to the nearest
## clear point on rings this far apart (rule C1), up to CLEAR_SPIRAL_RINGS rings out.
const CLEAR_SPIRAL_STEP_M := 0.5
const CLEAR_SPIRAL_RINGS := 40

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
## The endless world's streaming; null in the pool (exactly M1).
var world: WorldStream = null
## Endless mode: a respawn was asked for (respawn_player); the next step's streaming block performs it.
var respawn_pending := false
## Dev switches (debug_set_ai_frozen, debug_set_hidden); part of the state, so they are hashed.
var dev_ai_frozen := false
var dev_hidden := false
## Shelter (rule C5): the cell is concealed from every creature, and no strike hits it, on every
## tick before this one. Set when a lineage starts or continues and at every respawn; -1 without
## creatures. Not saved (D16).
var grace_until := -1
## Deaths in a row, each within streak_window_s of the last respawn (RespawnRules.streak_after); it
## picks the shelter and the energy of the next respawn. 0 before the first death; not saved (D16).
var death_streak := 0
var stats := {"plankton_eaten": 0, "carrion_eaten": 0, "plant_taken": 0.0, "energy_supplied": 0.0,
	"energy_absorbed": 0.0, "points_food": 0, "points_survival": 0, "distance_m": 0.0,
	"kills": 0, "hits_dealt": 0, "hits_taken": 0, "damage_dealt": 0.0, "damage_taken": 0.0, "dodges": 0,
	"creature_meals": 0, "creature_deaths": 0}
## The last FEED_LOG_SIZE reported feeding results, newest last:
## {"tick", "food_id", "kind", "allowed", "reason"}
var feed_log: Array[Dictionary] = []
## The cell's last ATTACK_LOG_SIZE attack results on the nearest creature it touches, quiet
## refusals included, newest last: {"tick", "target", "kind", "allowed", "reason"} (debug panel, tests).
var attack_log: Array[Dictionary] = []

var _events: Array[Dictionary] = []
var _alive_ticks := 0
var _was_starving := false
var _last_refusal := {}    ## {"food_id", "reason", "touching", "at"}
var _contact := {}         ## {"food_id", "since"}: the food being touched, and since when
var _last_attack_refusal := {}   ## kind -> {"target", "reason", "at"}: the attack refusal throttle
var _killer := ""          ## the creature whose hit on the cell landed last this tick
## Strikes on the cell that ended this tick without a hit, {"id", "species"}; dodged at step 11.
var _dodges: Array[Dictionary] = []


## Builds the pool for a save. The save's position is used when it is a clear place inside the
## soft wall; otherwise the cell starts at the layout spawn. With `p_species` the pool has creatures:
## every site that passes the spawn check from the cell's place is filled, the others wait.
## With `p_world` it builds the endless world instead (S1; _create_endless).
static func create(p_save: SaveGame, p_catalog: PartCatalog, p_layout: PoolLayout, p_species: SpeciesCatalog = null,
		p_world: WorldContent = null) -> PoolSim:
	if p_world != null:
		return _create_endless(p_save, p_catalog, p_layout, p_species, p_world,
			WorldGen.create(p_world, p_species, p_save.world_seed))
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
		# A new lineage and a continued run both start sheltered, so a load never drops the cell
		# into danger.
		sim.grace_until = p_species.start_grace_ticks
	# The starting world is not news.
	sim.plankton.events.clear()
	sim.carrion.events.clear()
	if sim.creatures != null:
		sim.creatures.take_events()
	sim._was_starving = sim.state.is_starving()
	return sim


## The endless world for a save, generated by `p_gen` (WorldGen.create; tests pass a fake). The
## origin is the save's absolute place exactly (PlaneSpace.from_save_abs; the home spawn for a save
## without one) and the cell starts at the first clear point near it (C1), facing the spawn heading
## at the spawn, else the nearest zone (as M1 does). The view set is loaded at once, the home
## block's starting carrion within the food ring is placed, every food zone is filled at once, the
## loaded sites that pass their spawn checks get their creatures (as M1's populate), and the cell
## starts sheltered. The layout gives the camera, the food and carrion tuning; its walls, zones and
## rocks are not used (the home block holds the M1 pool's).
static func _create_endless(p_save: SaveGame, p_catalog: PartCatalog, p_layout: PoolLayout, p_species: SpeciesCatalog,
		p_world: WorldContent, p_gen: WorldGen) -> PoolSim:
	var sim := PoolSim.new()
	sim.save = p_save
	sim.catalog = p_catalog
	sim.layout = p_layout
	sim.phenotype = Phenotype.derive(p_save.genome, p_catalog)
	sim.state = ActorState.fresh(sim.phenotype)
	sim.arena = ChunkArena.create_endless(p_world.config.chunk_tm)
	# Its rng is never drawn in endless mode: every zone draws its own stream.
	sim.region = EcologyRegion.create(p_save.world_seed * SEED_STRIDE + REGION_SEED_OFFSET)
	var world := WorldStream.create(p_world, p_gen)
	world.camera = p_layout.camera
	if p_species != null:
		world.view_aspect = float(p_species.fairness.spawn_view_aspect)
		world.view_margin = float(p_layout.camera.look_ahead_max) + float(p_species.fairness.spawn_view_margin_m)
	sim.world = world
	# The save's absolute place becomes the origin exactly; a new game's is the home spawn.
	var at := PlaneSpace.from_save_abs(p_save.player.get("position"))
	if at.is_empty():
		at = p_world.home.spawn
	world.set_origin_abs(sim, at[0], at[1])
	sim.plankton = PlanktonField.create(p_layout.plankton)
	sim.plankton.endless = true
	sim.plankton.max_items_per_zone = int(world.caps.food_per_zone)
	sim.carrion = CarrionField.create(p_layout.carrion, p_save.world_seed * SEED_STRIDE + CARRION_SEED_OFFSET)
	sim.carrion.initial = []
	if p_species != null:
		sim.species = p_species
		sim.creatures = CreatureField.create_endless(p_species, p_catalog, p_layout, sim.region, world,
			p_save.world_seed * SEED_STRIDE + ENCOUNTER_SEED_OFFSET)
	world.load_view_set_now(sim, Vector2.ZERO)
	var place := sim._clear_point_near(Vector2.ZERO, sim.phenotype.radius)
	# A restored place inside a collider moves the cell off the origin: its own view set loads too (B-8).
	world.load_view_set_now(sim, place)
	var at_spawn := at[0] == p_world.home.spawn[0] and at[1] == p_world.home.spawn[1]
	var heading := p_world.home.spawn_heading if at_spawn else sim._nearest_zone_direction(place).angle()
	sim.motion = Locomotion.MotionState.new(place, heading)
	sim.actor = InteractionResolver.Actor.new("player", place, heading, sim.phenotype)
	world.start(sim)
	# The home block's starting carrion that lies within the food ring (absolute pairs).
	for p: Array in p_world.home.carrion_initial:
		var local := world.local_of_abs(float(p[0]), float(p[1]))
		if local.distance_to(place) <= float(world.rings.food) and sim.arena.is_clear(local, sim.carrion.item_radius):
			sim.carrion.spawn(local, "initial")
	world.fill_all_food_now(sim)
	if sim.creatures != null:
		# M1's populate: every site queued by the view set's load that passes its checks spawns now.
		sim.creatures.tick_spawns_at(sim.arena, sim._player_places(), 0)
		sim.grace_until = p_species.start_grace_ticks
	# The starting world is not news (its chunk_loaded events are: the scene builds from them).
	sim.plankton.events.clear()
	sim.carrion.events.clear()
	if sim.creatures != null:
		sim.creatures.take_events()
	sim._was_starving = sim.state.is_starving()
	return sim


## True in the endless world (S1), false in the pool.
func is_endless() -> bool:
	return world != null


## The cell's absolute place in am, float64: the checkpoint's exactly while dead or waiting for its
## respawn (it may be kilometres from the origin), else the origin plus the local position. In the
## pool, position_for_save().
func absolute_position_am() -> PackedFloat64Array:
	if world == null:
		var p := position_for_save()
		return PackedFloat64Array([p.x, p.y])
	if dead or respawn_pending:
		return PackedFloat64Array([world.checkpoint_am[0], world.checkpoint_am[1]])
	return world.abs_of_local(motion.position)


## Sim time in seconds: the only clock (cooldowns, carrion age, drift).
func now() -> float:
	return tick * DT


func step(intent: SimIntent) -> void:
	if world != null:
		world.step(self)   # the streaming block (S1 spine 3.11): first, reading sim state only
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
	var swim := {}
	if creatures != null:
		creature_moved = _move_creatures()
		swim = _swim_velocities()
		_contacts()
	if not dead:
		_metabolism(moved)
	if creatures != null:
		_creature_metabolism(creature_moved)
	region.tick(DT)
	plankton.tick(region, arena, tick, now())
	carrion.tick(DT, now(), region, arena)
	if creatures != null:
		creatures.tick_spawns_at(arena, _player_places(), tick)
		creatures.remove_stuck_at(_player_places(), tick)
	_take_field_events()
	_sync_actor()
	if creatures != null:
		_sync_creatures()
	if not dead:
		_try_feed()
	if creatures != null:
		_creatures_feed()
		_take_field_events()
		_combat(swim)
		_emit_dodges()
		if not dead and grace_until == tick + 1:
			_emit({"type": "grace_ended", "reason": "timeout"})   # this was the shelter's last tick
	tick += 1


## Events since the last call, oldest first. Each has a "type":
##   ate {kind, food_id, zone, supplied, absorbed, points, position}
##   refused {kind, food_id, reason, touching, contact_s}
##   earned {points, reason}; starving_started; starving_ended
##   respawned {grace_s, energy, relocated (creature ids sent home), streak}
##   died {cause, by, by_species, reason, position} (cause "starved" or "killed")
##   grace_ended {reason: "timeout"|"attacked"} (the shelter ended; with creatures only)
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
##   hit {attacker, target, kind, damage, dealt, target_health, knockback, position} (every landed hit,
##     either way; position is the target's); attack_refused {target, kind, reason} (the cell only,
##     throttled, quiet reasons never); dodged {id, species} (a strike on the cell ended without a hit)
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
		out["grace_until"] = grace_until
		out["death_streak"] = death_streak
	if world != null:
		out["world"] = world.snapshot(self)
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


## Brings the cell back at its checkpoint after a death (plan section 13); the world is kept. The
## cell is placed at checkpoint() facing its heading, or at the nearest clear point when the
## checkpoint is not clear (C1), with fresh condition, no cooldowns and the alive timer reset.
## With creatures, also: the death streak grows by one when this life was shorter than
## streak_window_s, else it starts again at 1; the energy is the streak's respawn_energy_share of
## capacity (C4); every creature within respawn_clear_m of the cell is sent home and every brain
## forgets the cell, the one that killed it ignoring it for killer_ignore_s (C2, C3); and the
## streak's shelter starts (C5). Emits respawned {grace_s, energy, relocated, streak}.
##
## Endless: only sets respawn_pending; the next step's streaming block performs the respawn first
## (spine 3.11 step 0), near the body or by a teleport home, through _respawn_now.
func respawn_player() -> void:
	if world != null:
		respawn_pending = true
		return
	_respawn_now()


## respawn_player's work. Endless: `teleport` tells whether step 0 moved the world to the checkpoint,
## and the respawned event says so.
func _respawn_now(teleport := false) -> void:
	var killer := str(death.get("by", ""))
	var cp := checkpoint()
	motion.place(_clear_point_near(cp.position, phenotype.radius), cp.heading)
	state = ActorState.fresh(phenotype)
	actor.cooldowns.clear()
	_sync_actor()
	var relocated := PackedStringArray()
	var grace := 0
	if creatures != null:
		death_streak = RespawnRules.streak_after(death_streak, _alive_ticks, species.streak_window_ticks)
		state.energy = state.energy_capacity * RespawnRules.pick(species.respawn_energy_share, death_streak)
		grace = int(RespawnRules.pick(species.grace_ticks, death_streak))
		grace_until = tick + grace
		relocated = _clear_checkpoint(motion.position, killer)
	alive_s = 0.0
	_alive_ticks = 0
	dead = false
	death = {}
	_update_starving()   # a cell that starved to death comes back fed
	_contact.clear()
	_last_refusal.clear()
	_last_attack_refusal.clear()
	var respawned := {"type": "respawned", "grace_s": float(grace) / CreatureBrain.TICKS_PER_SECOND, "energy": state.energy,
		"relocated": Array(relocated), "streak": death_streak}
	if world != null:
		respawned["teleport"] = teleport
	_emit(respawned)


## Writes position_for_save() into the save (the checkpoint while the cell is dead, never its body).
## Endless: the absolute place in am, float64, through PlaneSpace.to_save_abs (the checkpoint's
## exactly while dead or waiting for the respawn).
func write_position_to_save() -> void:
	if world != null:
		var a := absolute_position_am()
		save.player["position"] = PlaneSpace.to_save_abs(a[0], a[1])
		return
	save.player["position"] = PlaneSpace.to_save(position_for_save())


## Where the lineage returns after a death: the generation start, which in M1 is the layout spawn
## (derived, never saved; step 4 makes it the generation's spawning spot). {"position", "heading"}.
## Endless: the world's absolute checkpoint (the home spawn in S1) in the current frame, plus its
## absolute "x_am", "y_am" and "size".
func checkpoint() -> Dictionary:
	if world != null:
		var cp := world.checkpoint_am
		return {"position": world.local_of_abs(cp[0], cp[1]), "heading": cp[2], "x_am": cp[0], "y_am": cp[1], "size": int(cp[3])}
	return {"position": layout.spawn, "heading": layout.spawn_heading}


## Where a save puts the cell: its checkpoint while it is dead (a death resolves to a respawn
## there), else where it is.
func position_for_save() -> Vector2:
	return checkpoint().position if dead else motion.position


## True while the living cell is sheltered (rule C5): after a start, a continue or a respawn, until
## grace_until or its own first landed hit. Sheltered, it is concealed from every creature.
func is_sheltered() -> bool:
	return not dead and tick < grace_until


## The cell in the senses' body format (CreatureSenses), as creatures may perceive it this tick.
func player_body() -> Dictionary:
	return {"id": CreatureField.PLAYER_ID, "species": SpeciesCatalog.PLAYER_SPECIES, "position": motion.position,
		"velocity": motion.velocity, "radius": phenotype.radius, "alive": not dead, "concealed": is_concealed(),
		"engageable": true, "bite": phenotype.bite_damage > 0.0, "spikes": phenotype.spikes.size()}


## True while no creature can sense or strike the cell: it is sheltered, or the dev "hide from AI"
## switch is on.
func is_concealed() -> bool:
	return dev_hidden or is_sheltered()


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


## Kills the creature nearest the cell (ties by id) as if by a hit: cause "killed", by "debug". It
## leaves its carcass and its site is queued.
func debug_kill_nearest_creature() -> bool:
	if creatures == null:
		return false
	var best: CreatureField.Creature = null
	var best_d := INF
	for c in creatures.creatures:
		var d := motion.position.distance_squared_to(c.motion.position)
		if d < best_d or (d == best_d and best != null and c.id < best.id):
			best_d = d
			best = c
	if best == null:
		return false
	_emit({"type": "debug", "command": "kill_nearest", "id": best.id, "species": best.species_id})
	best.state.take_damage(best.state.health)
	best.last_hit_by = DEBUG_KILLER
	_creature_dies(best, "killed", DEBUG_KILLER)
	return true


## Takes `amount` health from the living cell as if by a hit; at 0 it dies (killed, by "debug").
func debug_hurt_player(amount: float) -> bool:
	if dead or not is_finite(amount) or amount <= 0.0:
		return false
	var dealt := state.take_damage(amount)
	_emit({"type": "debug", "command": "hurt_player", "amount": dealt, "health": state.health})
	if not state.is_alive():
		_player_dies("killed", DEBUG_KILLER, "", "")
	return true


## Moves the cell to a clear point at rest; keeps the heading unless one is given.
## Dev (endless): moves the cell to an absolute place (am) at once, as a teleport respawn does: the
## old ground unloads, the origin moves there, the new view set loads with its food, and the cell
## takes the clear point nearest it. False in the pool or for a place that is not finite.
func debug_teleport_abs(x_am: float, y_am: float, heading: float = NAN) -> bool:
	if world == null or not is_finite(x_am) or not is_finite(y_am):
		return false
	world.teleport(self, x_am, y_am)
	motion.place(_clear_point_near(Vector2.ZERO, phenotype.radius), heading if is_finite(heading) else motion.heading)
	_sync_actor()
	_contact.clear()
	world.fill_all_food_now(self)
	_emit({"type": "debug", "command": "teleport_abs", "x_am": x_am, "y_am": y_am})
	return true


## Dev (endless): moves the floating origin by whole chunks now, as the streaming block does when the
## cell swims far from it. False in the pool.
func debug_rebase(by_chunks: Vector2i) -> bool:
	if world == null:
		return false
	world.rebase(self, Vector2(by_chunks) * world.rebase_step_tm)
	_emit({"type": "debug", "command": "rebase", "by": [by_chunks.x, by_chunks.y]})
	return true


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
	if creatures != null:
		_forget_player_everywhere()   # a dead body is gone to every brain (target_gone); the token is freed


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
		var taken := creatures.take_events()
		for e in taken:
			if e.type == "creature_recovered" and e.target == CreatureField.PLAYER_ID \
					and (e.outcome == "missed" or e.outcome == "blocked"):
				var c := creatures.find(e.id)
				_dodges.append({"id": e.id, "species": c.species_id if c != null else ""})
		_events.append_array(taken)


## Where the field measures spawn safety from: the cell, or its checkpoint while it is dead.
func _player_place() -> Vector2:
	return position_for_save()


## Every place the field measures spawn safety and stuck removals from (CreatureField's *_at):
## in the pool, _player_place() alone. In the endless world the body, and while dead the checkpoint
## too (the cell will come back there, and the body is still in view until it does).
func _player_places() -> Array[Vector2]:
	if world == null:
		return [_player_place()]
	if dead:
		return [motion.position, checkpoint().position]
	return [motion.position]


## Rule C1: `p` when a body of radius `r` fits there, else the first clear point on rings
## CLEAR_SPIRAL_STEP_M apart going out from it (each ring in angle order from +x), else `p`.
func _clear_point_near(p: Vector2, r: float) -> Vector2:
	if arena.is_clear(p, r):
		return p
	for ring in range(1, CLEAR_SPIRAL_RINGS + 1):
		var d := ring * CLEAR_SPIRAL_STEP_M
		var n := ceili(TAU * d / CLEAR_SPIRAL_STEP_M)
		for k in n:
			var q := p + Vector2.from_angle(k * TAU / n) * d
			if arena.is_clear(q, r):
				return q
	return p


## Rules C2 and C3 at a respawn at `at`: every creature within respawn_clear_m goes back to its
## home and heading now, and every brain forgets the cell, `killer` ignoring it for killer_ignore_s;
## the token is freed. Returns the ids sent home, sorted. A scripted body has no home and stays.
func _clear_checkpoint(at: Vector2, killer: String) -> PackedStringArray:
	creatures._scan_all = true   # every brain is told, sleepers too
	var minded: Array[Dictionary] = []
	for c in creatures.creatures:
		if c.brain != null:
			minded.append(creatures.body_of(c))
	var ids := RespawnRules.to_relocate(at, float(species.fairness.respawn_clear_m), minded)
	for c in creatures.creatures:
		if c.brain == null:
			continue
		var until := tick + species.killer_ignore_ticks if c.id == killer else 0
		if ids.has(c.id):
			c.motion.place(c.brain.home, c.brain.home_heading)
			c.actor.position = c.motion.position
			c.actor.heading = c.motion.heading
			CreatureBrain.force_return(c.brain, CreatureField.PLAYER_ID, until, tick)
		else:
			CreatureBrain.forget(c.brain, CreatureField.PLAYER_ID, until, tick)
		creatures.update_token(c, tick)
	_take_field_events()
	return ids


# --- creatures (M1 step 3) ---

## Tick steps 1-2: each creature in number order thinks when due (on `snapshot`, the bodies as
## they were at the start of the tick), drives, and sets its velocity. Scripted bodies swim by
## their script; frozen creatures coast.
func _creatures_act(snapshot_bodies: Array[Dictionary]) -> void:
	var food: Array = []
	var food_at := PackedVector2Array()    # the food's positions and radii, packed for the senses
	var food_r := PackedFloat64Array()
	var food_listed := false
	var endless := creatures.endless
	for c in creatures.awake():
		var speed_mul := c.state.speed_multiplier()
		if c.scripted:
			Locomotion.steer(c.motion, c.script_move, c.phenotype, speed_mul, DT)
			continue
		if dev_ai_frozen:
			c.drive = CreatureField.idle_drive(c.motion.heading)
			Locomotion.steer(c.motion, Vector2.ZERO, c.phenotype, speed_mul, DT)
			continue
		var self_view := creatures.self_view_of(c)
		# creatures.think_due(c, tick) written out (a creature here always has a brain).
		if CreatureBrain.think_due(c.brain, c.think_slot if endless else c.number, tick):
			if c.brain.state == CreatureBrain.FORAGE and not food_listed:
				# The two lists joined (a new array), or the plankton list itself when there is no
				# carrion: the senses only read it.
				food = plankton.items + carrion.items if not carrion.items.is_empty() else plankton.items
				food_at.resize(food.size())
				for i in food.size():
					food_at[i] = food[i].position
				food_r = plankton.packed_radii()   # the plankton's own copy, then the carrion's
				for item in carrion.items:
					food_r.append(item.radius)
				food_listed = true
			creatures.think(c, snapshot_bodies, food, arena, tick, self_view, food_at, food_r)
		var d := creatures.drive(c, arena, tick, self_view)
		CreatureBrain.move_body(c.brain, c.motion, d, c.phenotype, speed_mul, DT)
	_take_field_events()


## Tick step 4 for creatures: each moves by its velocity. Returns the distances, in creature order.
func _move_creatures() -> Array[float]:
	var out: Array[float] = []
	for c in creatures.awake():
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
	for c in creatures.awake():
		motions.append(c.motion)
		radii.append(c.phenotype.radius)
		masses.append(c.phenotype.mass)
	var n := motions.size()
	# The positions again, packed: the pair loop reads them n x n times. A push updates both entries.
	var at := PackedVector2Array()
	for m in motions:
		at.append(m.position)
	var pushed := PackedByteArray()
	pushed.resize(n)
	for i in n:
		var ri := radii[i]
		var at_i := at[i]
		for j in range(i + 1, n):
			var reach := ri + radii[j]
			if at_i.distance_squared_to(at[j]) >= reach * reach:
				continue   # apart: the common case, checked here without a call
			if PoolArena.separate(motions[i], ri, masses[i], motions[j], radii[j], masses[j]):
				pushed[i] = 1
				pushed[j] = 1
				at_i = motions[i].position
				at[i] = at_i
				at[j] = motions[j].position
	for i in n:
		if pushed[i] == 1:
			arena.settle(motions[i], radii[i])
	for c in creatures.awake():
		var mem := c.brain
		if mem == null:
			continue
		# CreatureBrain.leash_disc written out, without its dictionary.
		if mem.behavior == CreatureBrain.TERRITORIAL:
			PoolArena.clamp_to_disc(c.motion, mem.territory_center, mem.territory_r + float(mem.cfg.leash_m))
		else:
			PoolArena.clamp_to_disc(c.motion, mem.home, float(mem.cfg.leash_m))
		if mem.state == CreatureBrain.ATTACK and CreatureBrain.is_striking(mem):   # a strike is an attack phase
			var rock := arena.rock_contact(c.motion.position, c.phenotype.radius, PoolArena.CONTACT_SLACK, c.motion.heading,
				CreatureBrain.BLOCKED_BEARING)
			if not rock.is_empty():
				CreatureBrain.on_blocked(mem, tick)
	_take_field_events()


## Tick step 6 for creatures: metabolism at the species' share of the cell's rates (upkeep, moving,
## starving and regrowth together); a scripted body uses the cell's own rates. `moved` is in
## creature order. A creature that starves dies.
func _creature_metabolism(moved: Array[float]) -> void:
	var list := creatures.awake().duplicate()
	var blocks := species.species
	for i in list.size():
		var c: CreatureField.Creature = list[i]
		var share := 1.0 if c.scripted else float(blocks[c.species_id].metabolism_share)
		var st := c.state
		st.tick(c.phenotype, DT * share, moved[i] * share)
		if not st.is_alive():
			_creature_dies(c, "starved", "")


## A creature dies: creature_died reports it (with its carcass's food ids) and the field removes it,
## freeing its niche slot and queueing its site. Only a kill leaves a carcass, unless the species'
## carcass.on_starve says otherwise; a scripted body leaves none.
func _creature_dies(c: CreatureField.Creature, cause: String, by: String) -> void:
	_take_field_events()   # its brain's last events come before its death
	var carcass := PackedStringArray()
	if not c.scripted and (cause == "killed" or bool(species.species[c.species_id].carcass.on_starve)):
		carcass = creatures.drop_carcass(c, carrion, arena)
	stats.creature_deaths += 1
	if by == CreatureField.PLAYER_ID:
		stats.kills += 1
	_emit({"type": "creature_died", "id": c.id, "species": c.species_id, "cause": cause, "by": by,
		"position": c.motion.position, "carcass": Array(carcass)})
	creatures.remove(c, cause, tick, true)
	_take_field_events()


func _sync_creatures() -> void:
	for c in creatures.awake():
		var m := c.motion
		var a := c.actor
		a.position = m.position
		a.heading = m.heading


## Tick step 9 for creatures: each one whose drive names a food item eats it through the resolver,
## after the cell has fed. No points: those are the lineage's alone.
func _creatures_feed() -> void:
	for c in creatures.awake():
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


## Every body's velocity after this tick's motion and before contacts, by id: a ram's closing speed
## comes from these (plan section 9), not from what separation or a leash clamp left.
func _swim_velocities() -> Dictionary:
	var out := {}
	if not dead:
		out[CreatureField.PLAYER_ID] = motion.velocity
	for c in creatures.awake():
		out[c.id] = c.motion.velocity
	return out


## Tick step 10: combat. Who may attack is fixed when it begins: the living cell (a), and every
## living creature in a strike's burst or glide that has not hit yet in this strike (b). A body at
## 0 health is never a target, so nothing is hit twice after its death blow. Deaths come last (d).
func _combat(swim: Dictionary) -> void:
	_killer = ""
	var striking: Array[CreatureField.Creature] = []
	for c in creatures.awake():
		var b := c.brain
		if b == null or not c.state.is_alive():
			continue
		if b.phase == CreatureBrain.STRIKE and b.phase_tick == tick:
			c.strike_hit = false   # a new strike
		if CreatureBrain.is_striking(b) and bool(c.drive.get("strike", false)) and not c.strike_hit:
			striking.append(c)
	if not dead:
		_player_attacks(swim)
	for c in striking:
		_creature_strike(c, swim)
	_deaths()


## Step 10a: the cell bites and rams what it touches, with no key (OD3): the creatures within its
## radius + theirs + RAM_REACH, nearest first (ties by id); the first allowed bite and the first
## allowed ram, at most one of each. A refusal on the nearest one is reported (throttled) unless
## its reason is quiet. A landed hit ends the cell's shelter (grace_ended {reason: "attacked"}).
func _player_attacks(swim: Dictionary) -> void:
	var near: Array[Dictionary] = []
	var at := motion.position
	var own_r := phenotype.radius
	for c in creatures.awake():
		if not c.state.is_alive():
			continue
		var d := at.distance_to(c.motion.position)
		if d <= own_r + c.phenotype.radius + InteractionResolver.RAM_REACH:
			near.append({"d": d, "c": c})
	if near.is_empty():
		return
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d if a.d != b.d else a.c.id < b.c.id)
	var nearest: CreatureField.Creature = near[0].c
	var on_nearest := {}   # kind -> reason
	var landed := {}       # kind -> true
	for entry in near:
		var c: CreatureField.Creature = entry.c
		for kind in ["bite", "ram"]:
			if landed.has(kind) or not c.state.is_alive():
				continue
			var r: Dictionary
			if kind == "bite":
				r = InteractionResolver.bite(actor, c.actor, now())
			else:
				r = InteractionResolver.ram(actor, c.actor, _closing(swim, CreatureField.PLAYER_ID, motion, c.id, c.motion), now())
			if c == nearest:
				on_nearest[kind] = r.reason
				_log_attack(c.id, kind, r.allowed, r.reason)
			if not r.allowed:
				continue
			landed[kind] = true
			if is_sheltered():
				# Attacking gives up the shelter (rule C5): from now on creatures sense the cell.
				grace_until = tick
				_emit({"type": "grace_ended", "reason": "attacked"})
			var knockback := float(species.combat.player_bite_knockback if kind == "bite" else species.combat.player_ram_knockback)
			var dealt := _apply_hit(CreatureField.PLAYER_ID, motion, c.id, c.motion, c.state, kind, float(r.effect.damage), knockback)
			c.last_hit_by = CreatureField.PLAYER_ID
			stats.hits_dealt += 1
			stats.damage_dealt += dealt
			if c.brain != null:
				CreatureBrain.on_hurt(c.brain, player_body(), tick)
			_take_field_events()
	for kind in ["bite", "ram"]:
		if not landed.has(kind) and on_nearest.has(kind) and not ATTACK_QUIET_REASONS.has(on_nearest[kind]):
			_note_attack_refusal(nearest.id, kind, on_nearest[kind])


## Step 10b: one creature's strike at its target, through the resolver. A concealed, dead or gone
## target is skipped. A refused strike carries on until its ticks run out.
func _creature_strike(c: CreatureField.Creature, swim: Dictionary) -> void:
	var target_id := str(c.drive.get("target", ""))
	var kind := str(c.brain.cfg.attack.kind)
	var knockback := float(c.brain.cfg.attack.knockback)
	if target_id == CreatureField.PLAYER_ID:
		if dead or is_concealed() or not state.is_alive():
			return
		var r: Dictionary
		if kind == "bite":
			r = InteractionResolver.bite(c.actor, actor, now())
		else:
			r = InteractionResolver.ram(c.actor, actor, _closing(swim, c.id, c.motion, CreatureField.PLAYER_ID, motion), now())
		if not r.allowed:
			return
		var dealt := _apply_hit(c.id, c.motion, CreatureField.PLAYER_ID, motion, state, kind, float(r.effect.damage), knockback)
		c.strike_hit = true
		_killer = c.id
		stats.hits_taken += 1
		stats.damage_taken += dealt
		CreatureBrain.on_strike_landed(c.brain, tick)
		_take_field_events()
		return
	var t := creatures.find(target_id)
	if t == null or t == c or not t.state.is_alive():
		return
	var rt: Dictionary
	if kind == "bite":
		rt = InteractionResolver.bite(c.actor, t.actor, now())
	else:
		rt = InteractionResolver.ram(c.actor, t.actor, _closing(swim, c.id, c.motion, t.id, t.motion), now())
	if not rt.allowed:
		return
	_apply_hit(c.id, c.motion, t.id, t.motion, t.state, kind, float(rt.effect.damage), knockback)
	c.strike_hit = true
	t.last_hit_by = c.id
	CreatureBrain.on_strike_landed(c.brain, tick)
	if t.brain != null:
		CreatureBrain.on_hurt(t.brain, creatures.body_of(c), tick)
	_take_field_events()


## One landed hit (steps 10a-c): the damage, a knockback of `knockback` m/s on the target away from
## the attacker, both speeds clamped to combat.max_speed_after_hit (the tunnelling bound, T10), and
## the hit event. Returns the health taken.
func _apply_hit(attacker_id: String, a: Locomotion.MotionState, target_id: String, t: Locomotion.MotionState,
		t_state: ActorState, kind: String, damage: float, knockback: float) -> float:
	var dealt := t_state.take_damage(damage)
	var away := t.position - a.position
	var dir := away / away.length() if away.length() > 1e-6 else Vector2.from_angle(a.heading)
	t.velocity += dir * knockback
	var top := float(species.combat.max_speed_after_hit)
	for m in [a, t]:
		if m.velocity.length() > top:
			m.velocity = m.velocity.normalized() * top
	_emit({"type": "hit", "attacker": attacker_id, "target": target_id, "kind": kind, "damage": damage, "dealt": dealt,
		"target_health": t_state.health, "knockback": knockback, "position": t.position})
	return dealt


## Closing speed of `a` on `b`: their relative swim velocity along the line from a to b.
func _closing(swim: Dictionary, a_id: String, a: Locomotion.MotionState, b_id: String, b: Locomotion.MotionState) -> float:
	var line := b.position - a.position
	if line.length() <= 1e-6:
		return 0.0
	var va: Vector2 = swim.get(a_id, a.velocity)
	var vb: Vector2 = swim.get(b_id, b.velocity)
	return (va - vb).dot(line / line.length())


## Step 10d: the cell first (killed by the last creature that hit it this tick, with that species'
## death_reason), then creatures in number order.
func _deaths() -> void:
	if not dead and not state.is_alive():
		var by := creatures.find(_killer)
		var sp := by.species_id if by != null else ""
		_player_dies("killed", _killer, sp, str(species.species[sp].death_reason) if species.has_species(sp) else "")
	var fallen: Array[CreatureField.Creature] = []
	for c in creatures.awake():
		if not c.state.is_alive():
			fallen.append(c)
	for c in fallen:
		_creature_dies(c, "killed", c.last_hit_by)


## Step 11: every strike on the living cell that ended this tick without a hit. A strike that
## ended while the cell was concealed (sheltered or hidden) was no dodge: nothing could hit it.
func _emit_dodges() -> void:
	_take_field_events()
	if dead or is_concealed():
		_dodges.clear()
	for d in _dodges:
		stats.dodges += 1
		_emit({"type": "dodged", "id": d.id, "species": d.species})
	_dodges.clear()


## Reports an attack refusal when the (target, reason) pair of that kind changes, or every
## REFUSAL_REPEAT_S while it lasts (the feeding throttle).
func _note_attack_refusal(target_id: String, kind: String, reason: String) -> void:
	var last: Dictionary = _last_attack_refusal.get(kind, {})
	if last.get("target", "") == target_id and last.get("reason", "") == reason \
			and now() - float(last.at) < REFUSAL_REPEAT_S - 1e-9:
		return
	_last_attack_refusal[kind] = {"target": target_id, "reason": reason, "at": now()}
	_emit({"type": "attack_refused", "target": target_id, "kind": kind, "reason": reason})


func _log_attack(target_id: String, kind: String, allowed: bool, reason: String) -> void:
	attack_log.append({"tick": tick, "target": target_id, "kind": kind, "allowed": allowed, "reason": reason})
	if attack_log.size() > ATTACK_LOG_SIZE:
		attack_log.pop_front()


func _food_item(id: String) -> Dictionary:
	var plant := plankton.find(id)   # by its id index: the first match of a scan (ids are unique)
	if not plant.is_empty():
		return plant
	for item in carrion.items:
		if item.id == id:
			return item
	return {}


## Every brain forgets the cell, as if it had left the world (target_gone), and the token is freed.
func _forget_player_everywhere() -> void:
	creatures._scan_all = true   # every brain is told, sleepers too
	for c in creatures.creatures:
		if c.brain != null:
			CreatureBrain.on_target_gone(c.brain, CreatureField.PLAYER_ID, tick)
			creatures.update_token(c, tick)
	_take_field_events()


func _emit(event: Dictionary) -> void:
	_events.append(event)


static func _pair(v: Vector2) -> Array:
	return [v.x, v.y]
