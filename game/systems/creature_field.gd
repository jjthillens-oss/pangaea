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
## In the endless world (S1, `endless`) sites stream in and out with the ground (WorldStream's site
## table), a far creature sleeps (it is kept but not simulated: awake() leaves it out) and an awake
## one thinks on its own slot of the 10 Hz schedule. Spawn checks then measure from every place the
## cell has (its body, and its checkpoint while dead: PoolSim._player_places()), and a site near the
## checkpoint stays dormant. A site's creature is the same whatever route reaches it: its number, id,
## brain seed and respawn delay are hashes of the world seed, the site and how many creatures the
## site has had (spawn_site). The pool never sets `endless`, so there the field runs exactly as M1's:
## awake() is the creature list itself and every place list holds one.

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
## Endless mode: dev and test creatures take numbers from here up, so they sort after every site
## creature and their ids ("c_" + number) never meet a site creature's ("c_<size>_<site>_<count>").
const DEBUG_NUMBER_BASE := 1 << 30
## The think schedule's slots (10 Hz at 60 ticks a second) and the pass key of a sleeper in the
## streaming block's sleep and wake pass (after every slot).
const THINK_SLOTS := 6
const ASLEEP_KEY := 6
## Endless site creatures' numbers lie in [1, SITE_NUMBERS].
const SITE_NUMBERS := 1 << 30
## Endless mode: how many site creatures a tick's spawn pass (PoolSim.step's tick_spawns_at) spawns
## asleep at most; a due site that would spawn asleep after them waits, still due, for the next tick.
const SLEEPER_SPAWNS_PER_TICK := 1
## Endless mode: the creatures made ahead (prepare_site) are let go all at once when they outnumber
## the stream's site table by more than this (those of chunks generated ahead but never loaded).
const PREPARED_SLACK := 64


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
	## Its fields of the senses' body format that never change, for body_snapshot (built on first use).
	var body_info := {}
	## Endless mode: the colliders its forage seek's route looks at (ChunkArena.route_point_kept), made
	## on its first such seek.
	var route_keep: ChunkArena.RouteKeep = null


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
var world: WorldStream = null

var _phenotypes := {}   ## species id -> Phenotype
## Endless mode: the awake creatures, sorted (number, id) like `creatures`.
var _awake: Array[Creature] = []
## Endless mode: how many awake creatures think on each slot.
var _slot_counts := PackedInt32Array()
## Endless mode: site id -> its creature.
var _by_site := {}
var _str_brain := WorldHash.str32("brain")
var _str_respawn := WorldHash.str32("respawn")
var _senses := {}       ## species id -> {"sight", "fov" (radians, whole), "near"}
## Endless mode: a sleeper's brain may hold events (it went to sleep with some, or a hook on every
## brain gave it some), so the next take_events scans every creature; otherwise the awake ones only.
var _scan_all := true
## CreatureBrain.emitted when take_events last emptied the brains it scans; while it is unchanged
## (and _scan_all is not set) no brain it scans has an event to take. -1 (a creature woke holding
## events) scans.
var _taken_at := -1
## Endless mode: site id -> [what it was made for (_made_for), the creature] for the creatures made
## ahead of their spawn (prepare_site).
var _prepared := {}


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


## The endless world's field (S1): as create, but every niche starts at cap 0 (WorldStream sets the
## caps from the sites it has loaded) and creatures come only from streamed sites. `rng` is seeded
## but never drawn: every endless stream is a hash of the world seed and the site.
static func create_endless(p_species: SpeciesCatalog, p_catalog: PartCatalog, p_layout: PoolLayout,
		p_region: EcologyRegion, p_world: WorldStream, p_seed: int) -> CreatureField:
	var field := create(p_species, p_catalog, p_layout, p_region, p_seed)
	for role in field.region.niches:
		field.region.set_niche(role, 0)
	field.endless = true
	field.world = p_world
	field._slot_counts.resize(THINK_SLOTS)
	field._slot_counts.fill(0)
	return field


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


## tick_spawns, with the spawn check measured from every place in `places`. In the endless world the
## sites that wait again go into the queue after the loop, in the same order (_enqueue_retries): the
## only other inserts meanwhile (a spawn loading its chunks queues their sites) are due now, never
## at the retry tick, and a sorted queue ends the same whatever order distinct keys arrive in. With
## `sleepers` 0 or more (endless mode), once that many have spawned asleep each later due site that
## would spawn asleep goes back as it was, still due, for the next tick (a chunk loaded with many
## sites out of reach spawns them over a few ticks); awake spawns never wait. The world's creation
## passes none, and spawns every site that passes.
func tick_spawns_at(arena: PoolArena, places: Array[Vector2], tick: int, sleepers := -1) -> void:
	if queue.is_empty() or int(queue[0].at_tick) > tick:
		return
	var due: Array[Dictionary] = []
	while not queue.is_empty() and int(queue[0].at_tick) <= tick:
		due.append(queue.pop_front())
	var retry_at := tick + species.spawn_retry_ticks
	var later := endless and retry_at > tick
	var retries: Array[Dictionary] = []
	var full := _caps_full()   # then _try_site says "no room" to every site, and nothing spawns
	var left := sleepers if endless else -1   # asleep spawns this tick may still make (-1: any)
	var waiting: Array[Dictionary] = []
	for entry in due:
		var s := _site(str(entry.site))
		if s.is_empty() or _occupant(s.id) != null:
			continue   # a site holds one creature; a stale entry is dropped
		if left == 0 and spawns_asleep(s, places):
			waiting.append(entry)
			continue
		if full or not _try_site(s, arena, places, tick):
			if later:
				retries.append(s)
			else:
				_enqueue(s.id, s.species, retry_at)
		elif left > 0 and _by_site[s.id].asleep:
			left -= 1
	if not retries.is_empty():
		_enqueue_retries(retries, retry_at)
	for entry in waiting:
		queue.insert(_lower_bound(int(entry.at_tick), str(entry.site)), entry)


## Endless mode: the sleepers and the awake are both at their caps, so _try_site's "no room" holds
## whether a site's creature would sleep or not.
func _caps_full() -> bool:
	return endless and _no_room(true) and _no_room(false)


## Endless mode: whether the cap a site's creature would count against is full: the sleepers' when it
## would spawn asleep, else the awake ones' (blocker_from's "no room", _try_site's first check).
func _no_room(asleep: bool) -> bool:
	if asleep:
		return creatures.size() - _awake.size() >= int(world.caps.sleepers)
	return _awake.size() >= int(world.caps.awake)


## Why a creature may not appear at this site now, or "": too close to the player (spawn_safe_m), in
## the widest camera view of the player, a home that is not clear, or another creature within
## min_gap_m of the home (the player is spawn_safe_m away already).
func spawn_blocker(s: Dictionary, arena: PoolArena, player_pos: Vector2) -> String:
	return blocker_from(s, arena, [player_pos])


## spawn_blocker measured from every place in `places`: "near the player" when any place is within
## spawn_safe_m, "in view" when the home is in any place's view, then M1's "not clear" and "occupied",
## then in the endless world "dormant" (the site's reach comes near the checkpoint) and "no room"
## (the creature would spawn asleep with the sleepers at their cap, or awake with the awake ones at
## theirs: S1 core C-5, D-12).
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
	var gap := float(species.spawning.min_gap_m)
	for c in creatures:
		if c.motion.position.distance_to(home) < gap:
			return "occupied"
	# Endless runtime rule 8: no site whose reach comes within respawn_clear_m of the checkpoint
	# spawns, so a respawned cell never finds a creature at its door.
	if endless:
		var reach: Dictionary = s.reach
		if world.checkpoint_local().distance_to(reach.center) - float(reach.radius) - r < float(fairness.respawn_clear_m):
			return "dormant"
		if _no_room(spawns_asleep(s, places)):
			return "no room"
	return ""


## Endless mode: whether site `s`'s creature would spawn asleep, its home at least the wake ring from
## every place (and, past the spawn check's "in view", out of view of every place: the negation of
## the wake test).
func spawns_asleep(s: Dictionary, places: Array[Vector2]) -> bool:
	var home: Vector2 = s.home
	for place in places:
		if home.distance_to(place) < float(world.rings.wake):
			return false
	return true


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
		_release_slot(c)
		if not c.site_id.is_empty() and _by_site.get(c.site_id) == c:
			_by_site.erase(c.site_id)
	if not c.debug:
		region.on_creature_removed(c.role)
	var token_at := engaged_on_player.find(c.id)
	if token_at >= 0:
		engaged_on_player.remove_at(token_at)
	_scan_all = true   # the hooks below reach sleepers too
	_forget_in(creatures, c.id, tick)
	var removed := {"type": "creature_removed", "id": c.id, "species": c.species_id, "reason": reason}
	if endless:
		removed["position"] = c.motion.position
	events.append(removed)
	if requeue and not c.debug and not c.site_id.is_empty():
		var wait := species.spawn_retry_ticks
		if reason != "stuck":
			wait = respawn_delay_for(c) if endless else respawn_delay(c.species_id)
		_enqueue(c.site_id, c.species_id, tick + wait)


## remove(c, reason, tick, false) on each creature of `list` (the field's, in that order), in one
## pass over the others when no one holds the token and no brain's target or attacker is one of them
## or is the player it chases or attacks: then each remove's _forget_in only drops the others'
## memories of the gone (seen, landed_on), which come out the same in any order, and calls neither
## on_target_gone nor update_token. Otherwise one by one. The unload does this for a chunk's sites.
func remove_all(list: Array[Creature], reason: String, tick: int) -> void:
	var gone := {}
	for c in list:
		gone[c.id] = true
	var quiet := list.size() > 1 and engaged_on_player.is_empty()
	if quiet:
		for other in creatures:
			var b := other.brain
			if b != null and (gone.has(b.target) or gone.has(b.attacker) or (b.target == PLAYER_ID
					and (b.state == CreatureBrain.CHASE or b.state == CreatureBrain.ATTACK))):
				quiet = false
				break
	if not quiet:
		for c in list:
			remove(c, reason, tick, false)
		return
	# remove's own steps for each, in order, then the others forget them all at once (the gone
	# creatures' own memories of each other are dropped with them).
	for i in range(creatures.size() - 1, -1, -1):
		if gone.has(creatures[i].id):
			creatures.remove_at(i)
	for c in list:
		if endless:
			_awake.erase(c)
			_release_slot(c)
			if not c.site_id.is_empty() and _by_site.get(c.site_id) == c:
				_by_site.erase(c.site_id)
		if not c.debug:
			region.on_creature_removed(c.role)
		var removed := {"type": "creature_removed", "id": c.id, "species": c.species_id, "reason": reason}
		if endless:
			removed["position"] = c.motion.position
		events.append(removed)
	_scan_all = true
	for other in creatures:
		var b := other.brain
		if b == null:
			continue
		if not b.seen.is_empty():
			for id in gone:
				b.seen.erase(id)
		if not b.landed_on.is_empty():
			for id in gone:
				b.landed_on.erase(id)


## Endless mode (B-6, the hold pass): an awake creature held beyond the hold ring leaves, "unloaded",
## and its site is queued at this tick with no respawn delay, so the spawn rule refills it as a
## sleeper (or not at all once its chunks unload). A debug or siteless creature is not requeued.
func let_go(c: Creature, tick: int) -> void:
	remove(c, "unloaded", tick, false)
	if not c.debug and not c.site_id.is_empty():
		_enqueue(c.site_id, c.species_id, tick)


## Ticks until a dead creature's site respawns: respawn_s +/- respawn_jitter_s, one encounter draw.
func respawn_delay(species_id: String) -> int:
	var niche := species.niche_of(species_id)
	var jitter := float(niche.respawn_jitter_s)
	return roundi((float(niche.respawn_s) + rng.randf_range(-jitter, jitter)) * CreatureBrain.TICKS_PER_SECOND)


## Endless mode: ticks until a site's creature comes back, respawn_s +/- respawn_jitter_s by a hash
## of the world seed, the site and the creature's spawn count, so the delay is the same whatever
## route reached the site.
func respawn_delay_for(c: Creature) -> int:
	var niche := species.niche_of(c.species_id)
	var u := WorldHash.unit(WorldHash.hash_ints(PackedInt64Array([world.world_seed, world.gen_version,
		WorldHash.str32(c.site_id), c.spawn_count, _str_respawn])))
	return roundi((float(niche.respawn_s) + (2.0 * u - 1.0) * float(niche.respawn_jitter_s)) * CreatureBrain.TICKS_PER_SECOND)


## Endless mode: spawns site `s` (a WorldStream site record) now if its niche has room. Its number,
## id ("c_<size>_<site>_<count>"), brain seed and respawn delay come from the world seed, the site
## and its spawn count, which rises only on a real spawn. An awake spawn first has its site's reach
## chunks loaded (B-9). Null when the niche is full. The creature made ahead for the site
## (prepare_site) is taken when it was made for the same inputs; otherwise it is made now.
func spawn_site(s: Dictionary, tick: int, asleep := false) -> Creature:
	var site_id := str(s.id)
	var species_id := str(s.species)
	var count: int = world.site_counts.get(site_id, 0)
	var role := str(species.niche_of(species_id).role)
	if not region.try_spawn(role):
		return null
	if not asleep:
		world.load_site_chunks(s)
	world.site_counts[site_id] = count + 1
	var c: Creature = null
	if not _prepared.is_empty():
		var made: Array = _prepared.get(site_id, [])
		if not made.is_empty():
			_prepared.erase(site_id)
			if made[0] == _made_for(s, count):
				c = made[1]
	if c == null:
		c = _site_creature(s, count, role)
	c.born_tick = tick
	CreatureBrain.start(c.brain, tick)
	c.asleep = asleep
	_by_site[site_id] = c
	_add(c)
	return c


## Endless mode: makes site `s`'s next creature now, ahead of its spawn (the stream does it for the
## sites of a chunk generated ahead, on quiet ticks), and keeps it for spawn_site with what it was
## made for. It is the creature spawn_site would make from the same record and spawn count but for
## its birth tick and its brain's start, which the spawn sets; nothing is drawn from a shared stream.
func prepare_site(s: Dictionary) -> void:
	var site_id := str(s.id)
	var count: int = world.site_counts.get(site_id, 0)
	if _prepared.size() > world.sites.size() + PREPARED_SLACK:
		_prepared.clear()   # mostly sites of chunks that never loaded: made again if needed
	_prepared[site_id] = [_made_for(s, count), _site_creature(s, count, str(species.niche_of(str(s.species)).role))]


## Endless mode: drops what prepare_site made for site `id` (its ground unloaded or was let go).
func forget_prepared(id: String) -> void:
	_prepared.erase(id)


## What a site's creature is made from besides the catalogs: the spawn count, the world's size,
## seed and generator version, and the record's species, home, heading and territory.
func _made_for(s: Dictionary, count: int) -> Array:
	return [count, world.size, world.world_seed, world.gen_version, str(s.species), s.home, float(s.heading),
		(s.territory as Dictionary).duplicate()]


## Endless mode: site `s`'s creature for spawn count `count`, as spawn_site places it but for its
## birth tick, its brain's start and its sleep.
func _site_creature(s: Dictionary, count: int, role: String) -> Creature:
	var site_id := str(s.id)
	var species_id := str(s.species)
	var p: Phenotype = _phenotypes[species_id]
	var c := Creature.new()
	var site_hash := WorldHash.str32(site_id)   # for the number and the brain's seed
	c.number = 1 + WorldHash.mix32(site_hash, count) % SITE_NUMBERS
	c.id = "c_%d_%s_%d" % [world.size, site_id, count]
	c.spawn_count = count
	c.species_id = species_id
	c.phenotype = p
	c.state = ActorState.fresh(p)
	c.state.energy = c.state.energy_capacity * float(species.species[species_id].start_energy_share)
	c.motion = Locomotion.MotionState.new(s.home, float(s.heading))
	c.actor = InteractionResolver.Actor.new(c.id, s.home, float(s.heading), p)
	c.drive = idle_drive(float(s.heading))
	c.site_id = site_id
	c.role = role
	var cfg := species.brain_config(species_id)
	c.brain = CreatureBrain.made(str(cfg.behavior), cfg, s.home, float(s.heading), s.territory,
		WorldHash.hash_ints(PackedInt64Array([world.world_seed, world.gen_version, site_hash, count, _str_brain])))
	return c


## Endless mode (S1 core C-7): `c` sleeps where it lies. It leaves the awake list and its think slot,
## stops (no velocity, an idle drive, its previous pose its pose, so no view interpolates it), forgets
## what it had seen (B-21: it re-decides on waking), and every awake brain forgets it as if it had
## gone, the token following.
func sleep(c: Creature, tick: int) -> void:
	_scan_all = true   # its brain may still hold events
	c.asleep = true
	_release_slot(c)
	_awake.erase(c)
	c.motion.velocity = Vector2.ZERO
	c.motion.prev_position = c.motion.position
	c.motion.prev_heading = c.motion.heading
	c.drive = idle_drive(c.motion.heading)
	if c.brain != null:
		c.brain.seen.clear()
	_forget_in(_awake, c.id, tick)
	events.append({"type": "creature_slept", "id": c.id, "position": c.motion.position})


## Endless mode: `c` wakes on the think slot with the fewest awake creatures and re-decides on its
## first tick.
func wake(c: Creature, _tick: int) -> void:
	c.asleep = false
	c.think_slot = _take_slot()
	_insert_sorted(_awake, c)
	if c.brain != null:
		c.brain.wake = true
		if not c.brain.events.is_empty():
			_taken_at = -1   # it held events through its sleep: the next take_events scans
	events.append({"type": "creature_woke", "id": c.id, "position": c.motion.position, "slot": c.think_slot})


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
		var b := c.brain
		if b != null and b.stuck:
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


## bodies() as a CreatureSenses.Bodies snapshot (perceive_bodies): the same bodies in the same
## order and the same values. `player_body` is its own info.
func body_snapshot(player_body: Dictionary) -> CreatureSenses.Bodies:
	var out := CreatureSenses.Bodies.new()
	if not player_body.is_empty():
		out.info.append(player_body)
		out.at.append(player_body.position)
		out.velocity.append(player_body.velocity)
		out.radius.append(player_body.radius)
		out.alive.append(1 if bool(player_body.get("alive", true)) else 0)
	for c in awake():
		var m := c.motion
		var p := c.phenotype
		if c.body_info.is_empty():
			c.body_info = {"id": c.id, "species": c.species_id, "concealed": false, "engageable": true,
				"bite": p.bite_damage > 0.0, "spikes": p.spikes.size()}
		out.info.append(c.body_info)
		out.at.append(m.position)
		out.velocity.append(m.velocity)
		out.radius.append(p.radius)
		out.alive.append(1 if c.state.health > 0.0 else 0)
	return out


## One creature in the senses' body format.
func body_of(c: Creature) -> Dictionary:
	var m := c.motion
	var p := c.phenotype
	return {"id": c.id, "species": c.species_id, "position": m.position, "velocity": m.velocity,
		"radius": p.radius, "alive": c.state.is_alive(), "concealed": false, "engageable": true,
		"bite": p.bite_damage > 0.0, "spikes": p.spikes.size()}


## What a creature senses with (CreatureSenses' viewer).
func viewer_of(c: Creature) -> Dictionary:
	var species_id := c.species_id
	var senses: Dictionary = _senses[species_id]
	var m := c.motion
	return {"id": c.id, "species": species_id, "position": m.position, "heading": m.heading,
		"radius": c.phenotype.radius, "sight": senses.sight, "fov": senses.fov, "near": senses.near}


## What a creature knows of itself (CreatureBrain's self_view).
func self_view_of(c: Creature) -> Dictionary:
	var m := c.motion
	var p := c.phenotype
	var s := c.state
	var velocity := m.velocity
	return {"id": c.id, "species": c.species_id, "position": m.position, "heading": m.heading,
		"velocity": velocity, "speed_now": velocity.length(), "radius": p.radius,
		"speed": p.speed, "acceleration": p.acceleration,
		"health_share": s.health / s.max_health if s.max_health > 0.0 else 0.0,
		"energy_share": s.energy / s.energy_capacity if s.energy_capacity > 0.0 else 0.0}


## Whether the creature thinks this tick: on its number's slot of the schedule in the pool, on its
## think slot in the endless world (where numbers are hashes, so slots keep the load even).
func think_due(c: Creature, tick: int) -> bool:
	return c.brain != null and CreatureBrain.think_due(c.brain, c.think_slot if endless else c.number, tick)


## One creature's think: it perceives `bodies` (the tick's snapshot: bodies(), or body_snapshot()'s
## CreatureSenses.Bodies) through its own senses, sees food only while foraging, and decides. The
## player is engageable only if the token lets this creature engage now: the flag goes on a fresh
## percept and on the brain's remembered entry alike, so no decision runs on a flag from an older
## think (or from a hurt, which marks its attacker engageable). The token list follows the brain right
## after. `self_view` may be passed in when the caller already built it this tick (the body has not
## moved since), and so may a packed copy of the food's positions and radii
## (CreatureSenses.perceive_food_packed), taken with `food_items`.
func think(c: Creature, p_bodies: Variant, food_items: Array, arena: PoolArena, tick: int, self_view := {},
		food_at := PackedVector2Array(), food_r := PackedFloat64Array()) -> void:
	var viewer := viewer_of(c)
	var percepts := CreatureSenses.perceive_bodies(viewer, p_bodies, arena) if p_bodies is CreatureSenses.Bodies \
		else CreatureSenses.perceive(viewer, p_bodies, arena)
	var may := may_engage_player(c)
	for percept in percepts:
		if percept.id == PLAYER_ID:
			percept.engageable = may
	if c.brain.seen.has(PLAYER_ID):
		c.brain.seen[PLAYER_ID].engageable = may
	var food: Array[Dictionary] = []
	if c.brain.state == CreatureBrain.FORAGE:
		if food_at.size() == food_items.size() and food_r.size() == food_items.size():
			food = CreatureSenses.perceive_food_packed(viewer, food_items, food_at, food_r, c.phenotype.diets)
		else:
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


## Every brain of `others` forgets body `id`, which left (CreatureBrain.on_target_gone), and the token
## follows (update_token), in list order. A brain whose target and attacker are other bodies only
## drops its memories of `id`: on_target_gone does no more there. Its engagement is then unchanged,
## so update_token is called only when the token is held or the brain is engaged with the player
## (otherwise it finds nothing to do).
func _forget_in(others: Array[Creature], id: String, tick: int) -> void:
	for other in others:
		var b := other.brain
		if b == null:
			continue
		if b.target == id or b.attacker == id:
			CreatureBrain.on_target_gone(b, id, tick)
			update_token(other, tick)
			continue
		b.seen.erase(id)
		b.landed_on.erase(id)
		if not engaged_on_player.is_empty() or (b.target == PLAYER_ID and (b.state == CreatureBrain.CHASE or b.state == CreatureBrain.ATTACK)):
			update_token(other, tick)


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


## A hook outside the field is about to tell every brain, the sleepers' too: the next take_events
## reads every creature's brain.
func note_every_brain_told() -> void:
	_scan_all = true


## Field events plus every creature's brain events (each with its creature's id, and its position
## when the brain gave none), in creature order, oldest first; clears them.
func take_events() -> Array[Dictionary]:
	if _scan_all or CreatureBrain.emitted != _taken_at:
		var scan: Array[Creature] = _awake if endless and not _scan_all else creatures
		_scan_all = false
		for c in scan:
			if c.brain == null or c.brain.events.is_empty():
				continue
			for e in c.brain.events:
				var tagged: Dictionary = e.duplicate()
				tagged["id"] = c.id
				if not tagged.has("position"):
					tagged["position"] = c.motion.position
				events.append(tagged)
			c.brain.events.clear()
		_taken_at = CreatureBrain.emitted
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
	c.number = next_number + (DEBUG_NUMBER_BASE if endless else 0)
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
			if c.brain != null:
				c.think_slot = _take_slot()
			_insert_sorted(_awake, c)
	else:
		creatures.append(c)
	var spawned := {"type": "creature_spawned", "id": c.id, "species": c.species_id, "site": c.site_id,
		"position": c.motion.position, "heading": c.motion.heading, "debug": c.debug}
	if endless:
		spawned["asleep"] = c.asleep
		if c.asleep:
			_scan_all = true
	events.append(spawned)


## Spawns the site's creature now if the spawn check passes (from every place) and its niche has room.
func _try_site(s: Dictionary, arena: PoolArena, places: Array[Vector2], tick: int) -> bool:
	if endless:
		# blocker_from's "no room" first: with the caps full it is the usual answer, and blocker_from
		# is pure, so asking it first changes no outcome.
		var asleep := spawns_asleep(s, places)
		if _no_room(asleep):
			return false
		if not blocker_from(s, arena, places).is_empty():
			return false
		return spawn_site(s, tick, asleep) != null
	if not blocker_from(s, arena, places).is_empty():
		return false
	return spawn_at(str(s.species), s.home, float(s.heading), str(s.id), tick) != null


## Endless mode: the slot with the fewest awake creatures (ties to the lowest), taken.
func _take_slot() -> int:
	var best := 0
	for i in range(1, _slot_counts.size()):
		if _slot_counts[i] < _slot_counts[best]:
			best = i
	_slot_counts[best] += 1
	return best


func _release_slot(c: Creature) -> void:
	if c.think_slot >= 0:
		_slot_counts[c.think_slot] -= 1
		c.think_slot = -1


## A site's record by id: the species data's in the pool, the stream's site table in the endless world.
func _site(site_id: String) -> Dictionary:
	return world.sites.get(site_id, {}) if endless else species.site(site_id)


## Inserts `c` keeping `list` sorted by (number, id), after every creature not greater: no other
## creature equals it (ids are unique), so that is the first one greater, found by binary search.
static func _insert_sorted(list: Array[Creature], c: Creature) -> void:
	list.insert(list.bsearch_custom(c, _creature_less), c)


static func _creature_less(a: Creature, b: Creature) -> bool:
	return a.number < b.number or (a.number == b.number and a.id < b.id)


## Adds a queue entry, keeping the queue sorted by (at_tick, site): before the first entry that is
## not less. The endless world's queue only ever changes here and in _enqueue_retries, at its front
## and by an order-keeping filter, so it is always sorted and a binary search finds that place; the
## pool's tests edit theirs, so it keeps the scan.
func _enqueue(site_id: String, species_id: String, at_tick: int) -> void:
	var entry := {"site": site_id, "species": species_id, "at_tick": at_tick}
	var i := 0
	if endless:
		i = _lower_bound(at_tick, site_id)
	else:
		while i < queue.size() and (int(queue[i].at_tick) < at_tick or (int(queue[i].at_tick) == at_tick and str(queue[i].site) < site_id)):
			i += 1
	queue.insert(i, entry)


## Endless mode: _enqueue for each site of `sites` in turn, all at `at_tick`. Entries ahead of the
## last insert are less than it, so while each site is not less than the one before (the due entries
## come out of the queue in site order) its place is found by scanning on from there, a step or two;
## otherwise by the binary search. Either way it is the place _enqueue finds.
func _enqueue_retries(sites: Array[Dictionary], at_tick: int) -> void:
	var i := -1
	var before := ""
	for s in sites:
		var site_id := str(s.id)
		if i < 0 or site_id < before:
			i = _lower_bound(at_tick, site_id)
		else:
			while i < queue.size():
				var q: Dictionary = queue[i]
				if int(q.at_tick) < at_tick or (int(q.at_tick) == at_tick and str(q.site) < site_id):
					i += 1
				else:
					break
		queue.insert(i, {"site": site_id, "species": str(s.species), "at_tick": at_tick})
		before = site_id


## The first queue index whose entry is not less than (at_tick, site_id), by binary search: the
## endless queue is always sorted.
func _lower_bound(at_tick: int, site_id: String) -> int:
	var i := 0
	var hi := queue.size()
	while i < hi:
		var mid := (i + hi) >> 1
		var q: Dictionary = queue[mid]
		if int(q.at_tick) < at_tick or (int(q.at_tick) == at_tick and str(q.site) < site_id):
			i = mid + 1
		else:
			hi = mid
	return i


func _occupant(site_id: String) -> Creature:
	if endless:
		return _by_site.get(site_id)
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
