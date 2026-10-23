class_name CreatureField
extends RefCounted
## The pool's creatures (M1 step 3): their records, niche spawning at their own sites, the respawn
## queue, the engagement token on the player and the carcasses kills leave. PoolSim owns one when it
## is given species data and runs it inside its fixed 60 Hz tick; nothing here reads a clock, input
## or the scene.
##
## Spawning follows the habitat, not the player. Each species fills a niche (EcologyRegion.set_niche)
## of `cap` creatures, and creatures appear only at their species' sites, one per site. A site spawns
## when the player is at least spawn_safe_m away, the site is out of the widest camera view (with a
## margin for the look-ahead and the body), the home is clear of rocks and no creature is within
## min_gap_m of it; otherwise it waits retry_s and tries again. A killed creature's site respawns
## respawn_s +/- respawn_jitter_s later, drawn from this field's own encounter RNG (never the
## region's). Debug spawns bypass the niche cap, are not counted and never respawn.
##
## The token (fairness F4): at most max_engaged_on_player creatures chase or attack the player at
## once. Before each creature's think, in number order, the player is engageable (on its percept and
## on the brain's memory of it) only while the token has room or that creature already holds it;
## right after the think (or a hook) the list is updated from the brain, and never past its limit.
## Other bodies are always engageable.
##
## Creatures are not saved: a continued run repopulates from the encounter seed.
##
## In the endless world (S1, `endless`) sites stream in and out with the ground, a far creature
## sleeps (it is kept but not simulated: awake() leaves it out) and an awake one thinks on its own
## slot of the 10 Hz schedule. Spawn checks then measure from every place the cell has (its body, and
## its checkpoint while dead: PoolSim._player_places()). The pool never sets `endless`, so there the
## field runs exactly as M1's: awake() is the creature list itself and every place list holds one.

const ID_PREFIX := "c_"
## The id and species the player's body carries in the senses' body format.
const PLAYER_ID := "player"
## Each creature's brain is seeded from the field's seed and its number, so its choices do not
## depend on the order other creatures think in.
const BRAIN_SEED_STRIDE := 31
## m: a carcass chunk is tried at these distances from the body's center, in order; the first spot
## clear of rocks wins, else the center (plan section 10).
const CARCASS_RINGS_M := [0.45, 0.9]
const CARCASS_SOURCE := "kill"


## One creature. Its phenotype is shared with its species; everything else is its own.
class Creature:
	var id := ""
	var number := 0
	var species_id := ""
	var site_id := ""                  ## "" for a creature placed by a test or a dev command
	var role := ""                     ## its species' niche
	var debug := false                 ## a dev spawn: outside the niche count, never respawned
	var phenotype: Phenotype
	var state: ActorState
	var motion: Locomotion.MotionState
	var actor: InteractionResolver.Actor   ## persistent, so cooldowns survive between ticks
	var brain: CreatureBrain.Memory
	var drive := {}                    ## the last CreatureBrain.drive() result
	var last_hit_by := ""
	var strike_hit := false            ## a hit has landed in the current strike
	var born_tick := 0
	## A scripted body (a test decoy): no brain, no niche and no site; the sim swims it by
	## `script_move` like the player's intent and hits it through the player's path.
	var scripted := false
	var script_move := Vector2.ZERO
	## Endless mode only. A sleeper lies still out of the tick; think_slot is the awake creature's
	## slot of the 10 Hz think schedule (-1 asleep, and always in the pool); spawn_count is its
	## site's spawn count when it spawned.
	var asleep := false
	var think_slot := -1
	var spawn_count := 0


var species: SpeciesCatalog
var catalog: PartCatalog
var layout: PoolLayout
var region: EcologyRegion
## Live creatures in number order, which is the order they think, move and strike in.
var creatures: Array[Creature] = []
var next_number := 1
var seed_value := 0
## The encounter stream: respawn delays only.
var rng := RandomNumberGenerator.new()
## Sites waiting to spawn: [{"site", "species", "at_tick"}], sorted by (at_tick, site).
var queue: Array[Dictionary] = []
## Creature ids engaged (chase or attack) with the player, in the order they took the token.
var engaged_on_player := PackedStringArray()
## creature_spawned / creature_removed and the brains' events (with the creature's id), since the
## sim last took them.
var events: Array[Dictionary] = []

## Endless mode (S1): set by create_endless; false in the pool.
var endless := false

var _phenotypes := {}   ## species id -> Phenotype
## Endless mode: the awake creatures, sorted (number, id) like `creatures`.
var _awake: Array[Creature] = []
var _senses := {}       ## species id -> {"sight", "fov" (radians, whole), "near"}


## `seed_value` is the encounter seed (PoolSim: world seed x SEED_STRIDE + 3). Sets each species'
## niche in the region; spawns nothing yet (populate()).
static func create(p_species: SpeciesCatalog, p_catalog: PartCatalog, p_layout: PoolLayout, p_region: EcologyRegion,
		p_seed: int) -> CreatureField:
	var field := CreatureField.new()
	field.species = p_species
	field.catalog = p_catalog
	field.layout = p_layout
	field.region = p_region
	field.seed_value = p_seed
	field.rng.seed = p_seed
	for id in p_species.species_ids():
		var niche := p_species.niche_of(id)
		p_region.set_niche(str(niche.role), int(niche.cap))
		var p := p_species.phenotype(id, p_catalog)
		field._phenotypes[id] = p
		var senses: Dictionary = p_species.species[id].senses
		field._senses[id] = {"sight": p.sight, "fov": deg_to_rad(float(senses.fov_deg)), "near": float(senses.near_m)}
	return field


## The creatures that act this tick, in number order: every creature in the pool (the list itself),
## the awake ones in the endless world.
func awake() -> Array[Creature]:
	return _awake if endless else creatures


## Fills every site, in data order: a site that passes the spawn check gets its creature now, any
## other waits in the queue. `player_pos` is where the player is (the checkpoint while dead).
func populate(arena: PoolArena, player_pos: Vector2, tick: int) -> void:
	for s in species.sites:
		if _occupant(s.id) != null:
			continue
		if not _try_site(s, arena, [player_pos], tick):
			_enqueue(s.id, s.species, tick + species.spawn_retry_ticks)


## Spawns the queue entries that are due and pass the spawn check; the others wait retry_s more.
func tick_spawns(arena: PoolArena, player_pos: Vector2, tick: int) -> void:
	tick_spawns_at(arena, [player_pos], tick)


## tick_spawns, with the spawn check measured from every place in `places`.
func tick_spawns_at(arena: PoolArena, places: Array[Vector2], tick: int) -> void:
	if queue.is_empty() or int(queue[0].at_tick) > tick:
		return
	var due: Array[Dictionary] = []
	while not queue.is_empty() and int(queue[0].at_tick) <= tick:
		due.append(queue.pop_front())
	for entry in due:
		var s := _site(str(entry.site))
		if s.is_empty() or _occupant(s.id) != null:
			continue   # a site holds one creature; a stale entry is dropped
		if not _try_site(s, arena, places, tick):
			_enqueue(s.id, s.species, tick + species.spawn_retry_ticks)


## Why a creature may not appear at this site now, or "": too close to the player (spawn_safe_m), in
## the widest camera view of the player, a home that is not clear, or another creature within
## min_gap_m of the home (the player is spawn_safe_m away already).
func spawn_blocker(s: Dictionary, arena: PoolArena, player_pos: Vector2) -> String:
	return blocker_from(s, arena, [player_pos])


## spawn_blocker measured from every place in `places`: "near the player" when any place is within
## spawn_safe_m, "in view" when the home is in any place's view, then M1's "not clear" and "occupied".
func blocker_from(s: Dictionary, arena: PoolArena, places: Array[Vector2]) -> String:
	var home: Vector2 = s.home
	var r: float = _phenotypes[s.species].radius
	var fairness := species.fairness
	for place in places:
		if home.distance_to(place) < float(fairness.spawn_safe_m):
			return "near the player"
	var margin := float(layout.camera.look_ahead_max) + float(fairness.spawn_view_margin_m) + r
	for place in places:
		if ViewFootprint.contains(place, home, layout.camera, float(layout.camera.zoom_max), float(fairness.spawn_view_aspect), margin):
			return "in view"
	if not arena.is_clear(home, r):
		return "not clear"
	for c in creatures:
		if c.motion.position.distance_to(home) < float(species.spawning.min_gap_m):
			return "occupied"
	return ""


## Places a creature now, at rest at `p` facing `heading`, with `p` as its home. A site's creature
## guards that site's territory; a creature with no site (tests, dev) guards the brain's default
## circle round its home. A counted creature first takes a niche slot: null when its niche is full.
## A debug creature skips the niche. Every creature settles for settle_s (it notices nothing).
func spawn_at(species_id: String, p: Vector2, heading: float, site := "", tick := 0, debug := false) -> Creature:
	if not species.has_species(species_id):
		return null
	var role := str(species.niche_of(species_id).role)
	if not debug and not region.try_spawn(role):
		return null
	var block: Dictionary = species.species[species_id]
	var c := _new_creature(species_id, _phenotypes[species_id], p, heading, tick)
	c.site_id = site
	c.role = role
	c.debug = debug
	c.state.energy = c.state.energy_capacity * float(block.start_energy_share)
	var territory := {}
	if not site.is_empty():
		territory = species.territory_of(species.site(site), layout)
	var cfg := species.brain_config(species_id)
	c.brain = CreatureBrain.create(str(cfg.behavior), cfg, p, heading, territory, seed_value * BRAIN_SEED_STRIDE + c.number, tick)
	_add(c)
	return c


## Places a scripted body (a test decoy, never a real creature): any species id and phenotype, no
## brain, outside the niches, never respawned. The sim swims it by its script_move. It is perceived
## like any body, so a test can put it where the player would be and compare what brains do.
func spawn_scripted(species_id: String, p_phenotype: Phenotype, p: Vector2, heading: float, tick := 0) -> Creature:
	var c := _new_creature(species_id, p_phenotype, p, heading, tick)
	c.debug = true
	c.scripted = true
	_add(c)
	return c


## Takes a creature out of the pool: its niche slot is freed (unless it is a debug creature), every
## other brain forgets it (on_target_gone) and it leaves the token. With `requeue`, a counted
## creature's site waits to spawn again: respawn_s +/- respawn_jitter_s after a death (the encounter
## RNG), retry_s after a "stuck" removal. Emits creature_removed {id, species, reason}.
func remove(c: Creature, reason: String, tick: int, requeue: bool) -> void:
	var at := creatures.find(c)
	if at < 0:
		return
	creatures.remove_at(at)
	if endless:
		_awake.erase(c)
	if not c.debug:
		region.on_creature_removed(c.role)
	var token_at := engaged_on_player.find(c.id)
	if token_at >= 0:
		engaged_on_player.remove_at(token_at)
	for other in creatures:
		if other.brain != null:
			CreatureBrain.on_target_gone(other.brain, c.id, tick)
			update_token(other, tick)
	events.append({"type": "creature_removed", "id": c.id, "species": c.species_id, "reason": reason})
	if requeue and not c.debug and not c.site_id.is_empty():
		var wait := species.spawn_retry_ticks if reason == "stuck" else respawn_delay(c.species_id)
		_enqueue(c.site_id, c.species_id, tick + wait)


## Ticks until a dead creature's site respawns: respawn_s +/- respawn_jitter_s, one encounter draw.
func respawn_delay(species_id: String) -> int:
	var niche := species.niche_of(species_id)
	var jitter := float(niche.respawn_jitter_s)
	return roundi((float(niche.respawn_s) + rng.randf_range(-jitter, jitter)) * CreatureBrain.TICKS_PER_SECOND)


## Removes stuck creatures (their brain gave up returning home, D17) where the player cannot see it
## happen: at least spawn_safe_m from `player_pos` and out of the widest view. Each one's site is
## requeued. Elsewhere a stuck creature keeps trying, and the debug panel shows it.
func remove_stuck(player_pos: Vector2, tick: int) -> void:
	remove_stuck_at([player_pos], tick)


## remove_stuck, keeping a stuck creature that is near or in view of any place in `places`.
func remove_stuck_at(places: Array[Vector2], tick: int) -> void:
	var fairness := species.fairness
	var stuck: Array[Creature] = []
	for c in creatures:
		if c.brain != null and c.brain.stuck:
			stuck.append(c)
	for c in stuck:
		var at: Vector2 = c.motion.position
		var margin: float = float(layout.camera.look_ahead_max) + float(fairness.spawn_view_margin_m) + c.phenotype.radius
		var seen := false
		for place in places:
			if at.distance_to(place) < float(fairness.spawn_safe_m) \
					or ViewFootprint.contains(place, at, layout.camera, float(layout.camera.zoom_max), float(fairness.spawn_view_aspect), margin):
				seen = true
				break
		if not seen:
			remove(c, "stuck", tick, true)


## Where a dead creature's carcass chunks land: chunk i is tried at heading + i x TAU / chunks, at
## each CARCASS_RINGS_M distance in turn, and takes the first spot where `item_radius` is clear of
## rocks, else the body's center. Deterministic, with no RNG.
func carcass_points(c: Creature, arena: PoolArena, item_radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var chunks := int(species.species[c.species_id].carcass.chunks)
	var center := c.motion.position
	for i in chunks:
		var dir := Vector2.from_angle(c.motion.heading + i * TAU / chunks)
		var spot := center
		for ring in CARCASS_RINGS_M:
			var p: Vector2 = center + dir * float(ring)
			if arena.is_clear(p, item_radius):
				spot = p
				break
		out.append(spot)
	return out


## Drops a killed creature's carcass into `carrion`: its chunks of carcass.energy each (points at
## the data's rate), source "kill". Returns the new food ids in chunk order.
func drop_carcass(c: Creature, carrion: CarrionField, arena: PoolArena) -> PackedStringArray:
	var ids := PackedStringArray()
	var energy := float(species.species[c.species_id].carcass.energy)
	for p in carcass_points(c, arena, carrion.item_radius):
		var item := carrion.spawn(p, CARCASS_SOURCE, energy)
		if not item.is_empty():
			ids.append(item.id)
	return ids


func find(id: String) -> Creature:
	for c in creatures:
		if c.id == id:
			return c
	return null


## The start-of-tick snapshot the senses read: `player_body` first (unless empty), then every awake
## creature in number order (a sleeper is sensed by no one). Built once per tick, before anything
## moves.
func bodies(player_body: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not player_body.is_empty():
		out.append(player_body)
	for c in awake():
		out.append(body_of(c))
	return out


## One creature in the senses' body format.
func body_of(c: Creature) -> Dictionary:
	return {"id": c.id, "species": c.species_id, "position": c.motion.position, "velocity": c.motion.velocity,
		"radius": c.phenotype.radius, "alive": c.state.is_alive(), "concealed": false, "engageable": true,
		"bite": c.phenotype.bite_damage > 0.0, "spikes": c.phenotype.spikes.size()}


## What a creature senses with (CreatureSenses' viewer).
func viewer_of(c: Creature) -> Dictionary:
	var senses: Dictionary = _senses[c.species_id]
	return {"id": c.id, "species": c.species_id, "position": c.motion.position, "heading": c.motion.heading,
		"radius": c.phenotype.radius, "sight": senses.sight, "fov": senses.fov, "near": senses.near}


## What a creature knows of itself (CreatureBrain's self_view).
func self_view_of(c: Creature) -> Dictionary:
	return {"id": c.id, "species": c.species_id, "position": c.motion.position, "heading": c.motion.heading,
		"velocity": c.motion.velocity, "speed_now": c.motion.velocity.length(), "radius": c.phenotype.radius,
		"speed": c.phenotype.speed, "acceleration": c.phenotype.acceleration,
		"health_share": c.state.health / c.state.max_health if c.state.max_health > 0.0 else 0.0,
		"energy_share": c.state.energy / c.state.energy_capacity if c.state.energy_capacity > 0.0 else 0.0}


## Whether the creature thinks this tick: on its number's slot of the schedule in the pool, on its
## think slot in the endless world (where numbers are hashes, so slots keep the load even).
func think_due(c: Creature, tick: int) -> bool:
	return c.brain != null and CreatureBrain.think_due(c.brain, c.think_slot if endless else c.number, tick)


## One creature's think: it perceives `bodies` (the tick's snapshot) through its own senses, sees
## food only while foraging, and decides. The player is engageable only if the token lets this
## creature engage now: the flag goes on a fresh percept and on the brain's remembered entry alike,
## so no decision runs on a flag from an older think (or from a hurt, which marks its attacker
## engageable). The token list follows the brain right after. `self_view` may be passed in when the
## caller already built it this tick (the body has not moved since).
func think(c: Creature, p_bodies: Array, food_items: Array, arena: PoolArena, tick: int, self_view := {}) -> void:
	var viewer := viewer_of(c)
	var percepts := CreatureSenses.perceive(viewer, p_bodies, arena)
	var may := may_engage_player(c)
	for percept in percepts:
		if percept.id == PLAYER_ID:
			percept.engageable = may
	if c.brain.seen.has(PLAYER_ID):
		c.brain.seen[PLAYER_ID].engageable = may
	var food: Array[Dictionary] = []
	if c.brain.state == CreatureBrain.FORAGE:
		food = CreatureSenses.perceive_food(viewer, food_items, c.phenotype.diets)
	CreatureBrain.think(c.brain, self_view if not self_view.is_empty() else self_view_of(c), percepts, food, tick, arena)
	update_token(c, tick)


## A drive that does nothing: no thrust, no turn, no strike (a new, frozen or scripted creature).
static func idle_drive(heading: float) -> Dictionary:
	return {"mode": CreatureBrain.MODE_STEER, "move": Vector2.ZERO, "speed_mul": 0.0, "face": heading, "strike": false,
		"target": "", "feed": ""}


## The creature's drive for this tick (CreatureBrain.drive), kept on the record.
func drive(c: Creature, arena: PoolArena, tick: int, self_view := {}) -> Dictionary:
	c.drive = CreatureBrain.drive(c.brain, self_view if not self_view.is_empty() else self_view_of(c), tick, arena)
	return c.drive


## True when this creature may chase or attack the player: the token has room, or it holds it.
func may_engage_player(c: Creature) -> bool:
	return engaged_on_player.has(c.id) or engaged_on_player.size() < int(species.fairness.max_engaged_on_player)


## Brings the token list in line with the creature's brain: it holds the token exactly while it is
## engaged with the player. The list never grows past max_engaged_on_player: a brain that engaged
## while the token was full (which the engageable flag should make impossible) is refused and
## stands down, forgetting the player, and the refusal is logged as an error.
func update_token(c: Creature, tick: int) -> void:
	var engaged := c.brain != null and CreatureBrain.is_engaged_with(c.brain, PLAYER_ID)
	var at := engaged_on_player.find(c.id)
	if engaged and at < 0:
		if engaged_on_player.size() < int(species.fairness.max_engaged_on_player):
			engaged_on_player.append(c.id)
			return
		push_error("CreatureField: %s engaged the player at tick %d while %s held the token; it stands down" % [
			c.id, tick, engaged_on_player])
		CreatureBrain.forget(c.brain, PLAYER_ID, 0, tick)
	elif not engaged and at >= 0:
		engaged_on_player.remove_at(at)


## Field events plus every creature's brain events (each with its creature's id, and its position
## when the brain gave none), in creature order, oldest first; clears them.
func take_events() -> Array[Dictionary]:
	for c in creatures:
		if c.brain == null:
			continue
		for e in c.brain.events:
			var tagged: Dictionary = e.duplicate()
			tagged["id"] = c.id
			if not tagged.has("position"):
				tagged["position"] = c.motion.position
			events.append(tagged)
		c.brain.events.clear()
	var taken := events
	events = []
	return taken


## The field's whole state for snapshots and hashing: vectors as [x, y], creatures in number order,
## the queue in its (at_tick, site) order, and the encounter RNG's state.
func snapshot() -> Dictionary:
	var list := []
	for c in creatures:
		var d := c.drive
		list.append({
			"id": c.id, "number": c.number, "species": c.species_id, "site": c.site_id, "debug": c.debug,
			"born_tick": c.born_tick, "position": _pair(c.motion.position), "velocity": _pair(c.motion.velocity),
			"heading": c.motion.heading, "prev_position": _pair(c.motion.prev_position), "prev_heading": c.motion.prev_heading,
			"health": c.state.health, "energy": c.state.energy, "cooldowns": _sorted(c.actor.cooldowns),
			"last_hit_by": c.last_hit_by, "strike_hit": c.strike_hit,
			"drive": {"mode": str(d.get("mode", "")), "move": _pair(d.get("move", Vector2.ZERO)),
				"speed_mul": float(d.get("speed_mul", 0.0)), "face": float(d.get("face", 0.0)),
				"strike": bool(d.get("strike", false)), "target": str(d.get("target", "")), "feed": str(d.get("feed", ""))},
			"brain": c.brain.to_dict() if c.brain != null else {}, "scripted": c.scripted,
			"script_move": _pair(c.script_move),
		})
	var waiting := []
	for entry in queue:
		waiting.append({"site": entry.site, "species": entry.species, "at_tick": entry.at_tick})
	return {"creatures": list, "creature_next": next_number, "creature_rng": rng.state, "spawn_queue": waiting,
		"engaged_on_player": Array(engaged_on_player)}


func _new_creature(species_id: String, p_phenotype: Phenotype, p: Vector2, heading: float, tick: int) -> Creature:
	var c := Creature.new()
	c.number = next_number
	next_number += 1
	c.id = ID_PREFIX + str(c.number)
	c.species_id = species_id
	c.phenotype = p_phenotype
	c.state = ActorState.fresh(p_phenotype)
	c.motion = Locomotion.MotionState.new(p, heading)
	c.actor = InteractionResolver.Actor.new(c.id, p, heading, p_phenotype)
	c.drive = idle_drive(heading)
	c.born_tick = tick
	return c


func _add(c: Creature) -> void:
	if endless:
		_insert_sorted(creatures, c)
		if not c.asleep:
			_insert_sorted(_awake, c)
	else:
		creatures.append(c)
	events.append({"type": "creature_spawned", "id": c.id, "species": c.species_id, "site": c.site_id,
		"position": c.motion.position, "heading": c.motion.heading, "debug": c.debug})


## Spawns the site's creature now if the spawn check passes (from every place) and its niche has room.
func _try_site(s: Dictionary, arena: PoolArena, places: Array[Vector2], tick: int) -> bool:
	if not blocker_from(s, arena, places).is_empty():
		return false
	return spawn_at(str(s.species), s.home, float(s.heading), str(s.id), tick) != null


## A site's record by id: the species data's in the pool.
func _site(site_id: String) -> Dictionary:
	return species.site(site_id)


## Inserts `c` keeping `list` sorted by (number, id).
static func _insert_sorted(list: Array[Creature], c: Creature) -> void:
	var i := list.size()
	while i > 0 and (list[i - 1].number > c.number or (list[i - 1].number == c.number and list[i - 1].id > c.id)):
		i -= 1
	list.insert(i, c)


## Adds a queue entry, keeping the queue sorted by (at_tick, site).
func _enqueue(site_id: String, species_id: String, at_tick: int) -> void:
	var entry := {"site": site_id, "species": species_id, "at_tick": at_tick}
	var i := 0
	while i < queue.size() and (int(queue[i].at_tick) < at_tick or (int(queue[i].at_tick) == at_tick and str(queue[i].site) < site_id)):
		i += 1
	queue.insert(i, entry)


func _occupant(site_id: String) -> Creature:
	for c in creatures:
		if c.site_id == site_id:
			return c
	return null


static func _sorted(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out


static func _pair(v: Vector2) -> Array:
	return [v.x, v.y]
