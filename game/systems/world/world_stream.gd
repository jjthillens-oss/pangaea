class_name WorldStream
extends RefCounted
## The endless world's streaming (S1): which chunks of the generated sea are loaded around the cell,
## where the floating origin is, and the frame every local position is measured in. PoolSim owns one
## in endless mode (null in the pool) and runs step() first in every tick, before the M1 tick; it
## reads and changes only sim state, never a clock, input or the scene.
##
## Positions. The sim keeps float32 local positions in tm, relative to the origin; the origin and
## every generated object are absolute and float64 (am, at size 1 equal to tm). A local value is
## always derived from an absolute one by subtracting in float64 and then casting, never by adding up
## shifts, so a zone, site or collider is exact however far the cell swims. When the cell gets more
## than rebase_beyond_tm from the origin, the origin moves by whole chunks (rebase): bodies, brain
## memories and food items shift by exactly that offset (RebaseShift), everything else re-derives,
## and "rebased" tells the scene.
##
## Chunks are 32 tm squares keyed by Vector2i, loaded from WorldGen.chunk (pure, so a chunk comes
## back the same whatever route reaches it). The view set (view_set_keys) is the 3 x 3 chunks round
## the cell's chunk plus every chunk within VIEW_SET_MARGIN_TM of the widest camera view: it is
## loaded at once when the world starts, so nothing in view is ever missing. After that the nearest
## missing chunk within the load ring loads each tick, and a chunk unloads once it lies beyond the
## unload ring and no awake, held creature's reach touches it (D-9; a creature whose reach lies beyond
## the hold ring, 96 tm, is let go: B-6); the gap between the rings keeps a chunk from flickering in
## and out at a boundary. Unloading forgets a chunk entirely: it comes back from
## the generator, with its food zones' streams restarted.
##
## Sites. A loaded chunk's live creature sites enter the site table (local records re-derived from
## their absolute values on every origin move) and are queued to spawn at once; the niche caps are
## the table's sites per role, recomputed on every change, so a niche never holds more creatures than
## the ground loaded round the cell can home. A site's creature leaves with its home chunk.
##
## Sleep. A site creature far from the cell (beyond the sleep ring, out of view, calm and not
## holding the token) sleeps: it is kept, lying still, but neither thinks, moves nor is sensed, and
## it holds no chunk. It wakes inside the wake ring or in view, its site's reach chunks loaded first,
## and thinks on the emptiest of the six think slots. The gap between the rings keeps a creature
## from sleeping and waking at a boundary. Over caps.awake the farthest calm creature between the
## rings sleeps early; over caps.sleepers the farthest sleeper is evicted, its site requeued. While
## the cell is dead every distance is to the nearer of the body and the checkpoint.
##
## Respawn. A respawn waits for the next step (step 0): near the body, with the checkpoint's view set
## loaded, the cell comes back there; otherwise the world moves home behind the camera cut (teleport).
##
## Food. Only the zones whose nearest point lies within the food ring (52 tm) show plankton, and
## carrion beyond it is dropped for good: both happen out of view (the view reaches 35.7 tm with its
## margin). A zone entering the ring regrows one item a tick, out of view. Over caps.food_items the
## farthest zones wholly out of view are trimmed. A new world, a Continue and a teleport fill every
## food zone at once (S1 core C-9).

## tm: look_ahead_max (2.5) + spawn_view_margin_m (1.0) + MAX_ZONE_RADIUS_TM. Every zone touching the
## view plus its margin has its centre in a view-set chunk (S1 core C-1).
const VIEW_SET_MARGIN_TM := 11.5
## tm: the largest zone radius at size 1 (tile rule 3).
const MAX_ZONE_RADIUS_TM := 8.0
## The Vector2 keys a rebase shifts on each plankton and carrion item (RebaseShift.items).
const PLANKTON_POSITIONS: PackedStringArray = ["position", "anchor"]
const CARRION_POSITIONS: PackedStringArray = ["position"]
## The (state/phase) pairs a creature may sleep in (spine 3.11): resting, patrolling or foraging, not
## watching, noticing, chasing, attacking, fleeing or going home. _calm tests them without a key.
const CALM := {"rest/lurk": true, "rest/": true, "wander/patrol": true, "forage/seek": true, "forage/eat": true}
## Look-ahead generation: tm beyond the load ring a chunk may be generated ahead, how many are kept,
## how far ahead along its velocity (s) the cell is taken to be, and how long (ticks) a look that
## found nothing to generate waits before the next.
const AHEAD_MARGIN_TM := 16.0
const AHEAD_KEEP := 4
const AHEAD_LEAD_S := 1.0
const AHEAD_REFRESH_TICKS := 15
## tm: what the wake bound allows for float32 rounding in the distances and the path it sums, which
## is under a thousandth of this at 128 tm and a million ticks.
const WAKE_SLACK_TM := 0.05
## tm: how far the view's reach may differ from the bound's before the bound restarts (a float32
## footprint at another place differs by about 1e-5).
const WAKE_FAR_TOLERANCE_TM := 0.001
## tm: the load bound scans this much beyond the load ring, so every chunk outside its box lies at
## least this far beyond the ring; and what the load and unload bounds allow for float64 rounding.
const LOAD_BOUND_TM := 8.0
const RING_BOUND_SLACK_TM := 1e-6
## tm: what the food view's bound allows for float32 rounding in a zone's distance and the body's
## movement (each under 1e-5 at 128 tm).
const FOOD_BOUND_SLACK_TM := 0.001

var content: WorldContent
var gen: WorldGen
var size := 1
var origin_x_am := 0.0
var origin_y_am := 9.0
var checkpoint_am := PackedFloat64Array([0.0, 9.0, -1.5708, 1.0])    ## x, y, heading, size
## Backstops that fired: awake_overflow (more awake creatures than the cap and none calm to sleep),
## chunk_waits (a load past the chunk cap waited), food_trimmed (a far zone's food hidden over the
## item cap), evictions (a sleeper removed over the sleeper cap).
var counters := {"awake_overflow": 0, "chunk_waits": 0, "food_trimmed": 0, "evictions": 0}
## The world file's rings (tm) and caps, read once.
var rings := {}
var caps := {}
var chunk_tm := 32.0
var rebase_beyond_tm := 96.0
var rebase_step_tm := 32.0
var world_seed := 0
var gen_version := 1
## The camera table the view set is measured with (the layout's camera), and the spawn view's
## aspect and margin (fairness: the widest screen, look-ahead plus the safety gap).
var camera := {}
var view_aspect := 2.4
var view_margin := 3.5

var _chunks := {}                      ## Vector2i -> WorldChunk (absolute)
var _keys: Array[Vector2i] = []        ## loaded, sorted (y, x)
## site id -> {id, species, home: Vector2, heading, territory: {} or {center: Vector2, radius},
## reach: {center: Vector2, radius}, chunks: Array[Vector2i], home_chunk: Vector2i, abs: the
## WorldChunk's site}: the loaded live sites, local. Read it freely; only _load_chunk and
## _unload_chunk add or remove a site (they keep the home and role counts below with it). A site
## added or removed elsewhere is taken in when the table's size no longer matches those counts
## (they are recounted then); one that replaces another at the same size goes unseen.
var sites := {}
## site id -> how many creatures it has spawned this session (never cleared by an unload, so a
## reloaded site's next creature is a new one).
var site_counts := {}
## The niche caps' count kept as sites enter and leave the table, so a load or an unload need not
## look up every site's species again: site id -> its species' role, and role -> how many sites of
## the table fill it (a role leaves at 0).
var _site_role := {}
var _role_sites := {}
## The table's sites by home chunk (Vector2i -> {site id: true}), so an unload finds its own without
## walking the table; recounted if the table's size no longer matches it (a test's own site).
var _home_sites := {}
var _home_count := 0
var _zone_abs := {}                    ## zone id -> PackedFloat64Array [x, y] (absolute tm)
var _zone_chunk := {}                  ## zone id -> Vector2i
var _str_plankton := WorldHash.str32("plankton")
var _fill := {}                        ## zone id -> true: fill at once in the next food view
var _fill_all := false                 ## fill every food zone at once in the next food view
var _trimmed := {}                     ## zone id -> true while trimmed (counted once, C-11)
## The region's zones packed for the food view, in their order: id, centre, radius and the zone
## itself, and for a rebase its absolute centre (tm; NaN for a zone without one). This stream is the
## only one to add, remove or move a zone in the endless world, and bumps _zones_version when it
## does; the index is rebuilt when that or the zone count changed.
var _zones_version := 0
var _zones_indexed := -1
var _zone_ids := PackedStringArray()
var _zone_c := PackedVector2Array()
var _zone_r := PackedFloat64Array()
var _zone_refs: Array[Dictionary] = []
var _zone_ax := PackedFloat64Array()
var _zone_ay := PackedFloat64Array()
var _index_epoch := 0                  ## bumped on every change to the index (a zone in, out or moved)
## The food view's last measure of the zones: the index places of those within the food ring, in
## index order, good while the index epoch and the ring are the same and the body has moved less than
## every zone's distance from the ring (a distance changes by no more than the body moves): [x, y,
## room, ring, epoch], empty to measure every zone.
var _food_at := PackedInt32Array()
var _food_bound := PackedFloat64Array()
## The food set last given to the plankton (PlanktonField.active_zones), the index places it shows
## and the index epoch they are of.
var _shown_food := {}
var _shown_at := PackedInt32Array()
var _shown_epoch := -1
var _cell_tile := Vector2i.ZERO
## Chunks generated ahead (WorldGen.chunk is pure, so a chunk is the same whatever tick builds it):
## on a tick that loads nothing, the missing chunk nearest where the cell is heading is generated
## and kept here, Vector3i(x, y, size) -> WorldChunk, so the tick that loads it does not pay for it.
## Each is handed out once; a teleport, another generator or the same one bound again (WorldGen.setup
## to other content, species, seed or version) forgets them.
var _ahead := {}
var _ahead_gen: WorldGen = null
var _ahead_binding := []               ## [content, species, world seed, gen version] they were made with
var _ahead_tick := 0                   ## the first tick the next look may run (a load resets it)
var _loads := 0                        ## chunks loaded so far (whether a tick loaded any)
var _tm_to_am := 1.0                   ## 1.6^(size - 1): 1.0 in S1
var _field: WeakRef = null             ## the sim's CreatureField (weak: the field holds this stream)
var _sim: WeakRef = null               ## the sim (weak: it holds this stream), for load_site_chunks
## This tick's waking sleepers, from _wakers for step 5 (a sleeper lies still, so the pass would find
## the same): the view they were measured from, the sleepers of the pass that wake (in creature
## order) and their wake distances.
var _waking_view: Variant = null
var _waking: Array[CreatureField.Creature] = []
var _waking_d := PackedFloat64Array()
## The wake bound. A sleeper lies still, and while the cell has one place it comes no nearer a
## sleeper than the path that place has moved, so a sleeper measured as not waking cannot wake before
## the place has moved by its distance less the farthest it could wake from (the wake ring, or the
## view's reach plus its margin and radius). Each such sleeper keeps [its position, the path length
## at which it may first wake] and _wakers skips its test until then (or until it is moved). The bound
## restarts, every sleeper measured again, when the cell has two places or the view or rings change.
var _wake_bound := {}                  ## sleeper (Creature) -> [position, path length]
var _swum := 0.0                       ## tm the cell's one place has moved since the bound restarted
var _swum_from := Vector2.INF          ## that place at the last _wakers
var _bound_view := PackedFloat64Array([-1.0, 0.0, 0.0])   ## [far, wake ring, view margin] it holds for
## The ring bounds. A chunk's distance from the body changes by no more than the body moves, so after
## a scan found no missing chunk within the load ring (_nearest_missing), none can come within it
## before the body has moved the nearest missing one's distance less the ring, unless a chunk
## unloads; and after a scan found every loaded chunk within the unload ring (_unload), none can leave
## it before the body has moved the farthest one's distance short of the ring, unless a chunk loads.
## Each is [the body's absolute x, y (tm) at the scan, that distance, the ring], or empty.
var _load_bound := PackedFloat64Array()
var _unload_bound := PackedFloat64Array()


static func create(p_content: WorldContent, p_gen: WorldGen) -> WorldStream:
	var w := WorldStream.new()
	w.content = p_content
	w.gen = p_gen
	var config := p_content.config
	w.size = config.size_start
	w.rings = config.rings.duplicate()
	w.caps = config.caps.duplicate()
	w.chunk_tm = config.chunk_tm
	w.rebase_beyond_tm = config.rebase_beyond_tm
	w.rebase_step_tm = config.rebase_step_tm
	w.world_seed = p_gen.world_seed
	w.gen_version = p_gen.gen_version
	var spawn: PackedFloat64Array = p_content.home.spawn
	w.checkpoint_am = PackedFloat64Array([spawn[0], spawn[1], p_content.home.spawn_heading, float(w.size)])
	w.origin_x_am = spawn[0]
	w.origin_y_am = spawn[1]
	return w


## The streaming block, first in every endless tick (spine 3.11): a pending respawn (step 0), the
## floating origin (step 2), unload (step 3), load (step 4), sleep and wake (step 5), then the food
## view (step 6). Load, unload and food always measure from the body, alive or dead; sleep and wake
## from every place the cell has (PoolSim._player_places), the same for steps 4 and 5.
func step(sim: PoolSim) -> void:
	if sim.respawn_pending:
		_respawn(sim)
	var p := sim.motion.position
	if p.length() > rebase_beyond_tm:
		rebase(sim, Vector2(roundf(p.x / rebase_step_tm) * rebase_step_tm, roundf(p.y / rebase_step_tm) * rebase_step_tm))
	_unload(sim)
	var view := _wake_view(sim)
	var loads := _loads
	_load(sim, view)
	if _loads == loads:
		_look_ahead(sim)
	_sleep_and_wake(sim, view)
	_food_view(sim)


## The food view now with every food zone filled at once (a new world, a Continue, a teleport).
func fill_all_food_now(sim: PoolSim) -> void:
	_fill_all = true
	_food_view(sim)


## The rest of a new world once the cell is placed (PoolSim._create_endless): the cell's tile, the
## creature field sleeping_ids() reads and the sim load_site_chunks loads into.
func start(sim: PoolSim) -> void:
	_cell_tile = tile_of_local(sim.motion.position)
	_field = weakref(sim.creatures) if sim.creatures != null else null
	_sim = weakref(sim)


## B-9: every missing chunk of site record `s` loads now, before its creature spawns awake (never
## refused and never counted), so an awake creature always stands on its whole reach.
func load_site_chunks(s: Dictionary) -> void:
	var sim: PoolSim = _sim.get_ref() if _sim != null else null
	if sim == null:
		return
	for key in s.chunks:
		if not _chunks.has(key):
			_load_chunk(sim, key)


# --- frames ---

## The checkpoint's local position (it may be far outside the loaded ground).
func checkpoint_local() -> Vector2:
	return local_of_abs(checkpoint_am[0], checkpoint_am[1])


## The local position (tm, float32) of an absolute point (am), through float64.
func local_of_abs(x_am: float, y_am: float) -> Vector2:
	return Vector2((x_am - origin_x_am) / _tm_to_am, (y_am - origin_y_am) / _tm_to_am)


## The absolute position (am, float64) of a local point.
func abs_of_local(p: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([origin_x_am + float(p.x) * _tm_to_am, origin_y_am + float(p.y) * _tm_to_am])


## The local position of a generated object's absolute tm coordinates (WorldChunk), through float64.
func local_of_tm(x_tm: float, y_tm: float) -> Vector2:
	return local_of_abs(x_tm * _tm_to_am, y_tm * _tm_to_am)


## The tile under a local point, at the current size (a tile is 64 bu).
func tile_of_local(p: Vector2) -> Vector2i:
	var a := abs_of_local(p)
	var tile_tm := content.config.tile_bu * WorldConfig.bu_to_tm(size)
	return Vector2i(floori(a[0] / _tm_to_am / tile_tm), floori(a[1] / _tm_to_am / tile_tm))


## The chunk holding a local point.
func chunk_of_local(p: Vector2) -> Vector2i:
	var a := abs_of_local(p)
	return Vector2i(floori(a[0] / _tm_to_am / chunk_tm), floori(a[1] / _tm_to_am / chunk_tm))


## Moves the origin to an absolute point (am) exactly and re-derives every local value that comes
## from an absolute one: the arena's colliders and the zones. Bodies and items are the caller's.
func set_origin_abs(sim: PoolSim, x_am: float, y_am: float) -> void:
	origin_x_am = x_am
	origin_y_am = y_am
	_rederive(sim)


## Moves the origin by `offset` (tm, whole chunks in each axis): every position the sim stores moves
## by -offset. Bodies (with their previous positions, so the view's interpolation stays continuous),
## actors, every creature's memories (sleepers too) and food items shift by it exactly; zones and
## colliders re-derive from their absolute values. Emits rebased {offset_tm, origin_am}.
func rebase(sim: PoolSim, offset: Vector2) -> void:
	origin_x_am += float(offset.x) * _tm_to_am
	origin_y_am += float(offset.y) * _tm_to_am
	RebaseShift.motion(sim.motion, offset)
	sim.actor.position -= offset
	if sim.creatures != null:
		# RebaseShift.motion written out, and every position a brain remembers: what it has seen, its
		# strike lane, its goal, its progress check, what it flees, its home and its territory. One pass
		# over the creatures, in a timed tick (G17).
		for c in sim.creatures.creatures:
			var m := c.motion
			m.position -= offset
			m.prev_position -= offset
			c.actor.position -= offset
			var mem := c.brain
			if mem == null:
				continue
			if not mem.seen.is_empty():
				for entry in mem.seen.values():
					entry.position -= offset
			if not mem.lane.is_empty():
				mem.lane.origin -= offset
			if mem.goal.is_finite():
				mem.goal -= offset
			if not mem.progress.is_empty():
				mem.progress.position -= offset
			if mem.flee_from.is_finite():
				mem.flee_from -= offset
			mem.home -= offset
			if mem.territory_center.is_finite():
				mem.territory_center -= offset
	RebaseShift.items(sim.plankton.items, PLANKTON_POSITIONS, offset)
	RebaseShift.items(sim.carrion.items, CARRION_POSITIONS, offset)
	if _swum_from.is_finite():
		_swum_from -= offset   # the wake bound's place and sleepers, as the bodies moved
	for b in _wake_bound.values():
		b[0] -= offset
	var food_bound := _food_bound
	var epoch := _index_epoch
	if _rederive(sim):
		# The zone index kept its places, so the food view's measure and food set hold for the moved
		# bodies and zones: each distance changes only by the float32 rounding of the moved values (under
		# a tenth of FOOD_BOUND_SLACK_TM), which the bound gives up one slack's room for.
		if _shown_epoch == epoch:
			_shown_epoch = _index_epoch
		if not food_bound.is_empty() and food_bound[4] == epoch and food_bound[2] > FOOD_BOUND_SLACK_TM:
			_food_bound = PackedFloat64Array([food_bound[0] - offset.x, food_bound[1] - offset.y,
				food_bound[2] - FOOD_BOUND_SLACK_TM, food_bound[3], _index_epoch])
	_emit(sim, {"type": "rebased", "offset_tm": offset, "origin_am": [origin_x_am, origin_y_am]})


## The teleport path (spine 3.11 step 0, D-10), behind a camera cut: every loaded chunk unloads,
## every creature leaves ("unloaded"), all carrion goes (C-10), the origin moves to the absolute
## point exactly (rebased), and the view set round it loads at once, its food zones flagged to fill
## at once (C-9). The caller places the cell near the new origin.
func teleport(sim: PoolSim, x_am: float, y_am: float) -> void:
	for key in _keys.duplicate():
		_unload_chunk(sim, key)
	if sim.creatures != null:
		for c in sim.creatures.creatures.duplicate():
			sim.creatures.remove(c, "unloaded", sim.tick, false)   # siteless ones too
	sim.carrion.drop_all()
	_ahead.clear()
	_wake_bound.clear()
	_swum_from = Vector2.INF
	var old_x := origin_x_am
	var old_y := origin_y_am
	set_origin_abs(sim, x_am, y_am)
	_emit(sim, {"type": "rebased", "offset_tm": Vector2((origin_x_am - old_x) / _tm_to_am, (origin_y_am - old_y) / _tm_to_am),
		"origin_am": [origin_x_am, origin_y_am]})
	for key in view_set_keys(Vector2.ZERO):
		_load_chunk(sim, key)
	_fill_all = true
	recompute_caps(sim)


## Step 0 (spine 3.11, D-10, D-11): the pending respawn. When the checkpoint's whole view set is
## loaded the cell comes back there as M1's respawn does, and the zones touching its new view fill at
## once. Otherwise the world moves home behind the camera cut: every chunk unloads (its creatures
## first), the rest of the creatures and every carrion item go, the origin becomes the checkpoint
## (rebased), its view set loads with every food zone filled, and the cell comes back at the origin.
func _respawn(sim: PoolSim) -> void:
	var near := true
	for key in view_set_keys(checkpoint_local()):
		if not _chunks.has(key):
			near = false
			break
	if near:
		sim._respawn_now(false)
		_flag_fill_touching(sim, sim.motion.position)
	else:
		teleport(sim, checkpoint_am[0], checkpoint_am[1])
		sim._respawn_now(true)
	sim.respawn_pending = false
	recompute_caps(sim)


## D-11: every zone touching the view from `p` (its footprint grown by the spawn-view margin) fills at
## once in this tick's food view.
func _flag_fill_touching(sim: PoolSim, p: Vector2) -> void:
	var quad := ViewFootprint.corners(p, camera, float(camera.zoom_max), view_aspect)
	for z in sim.region.zones:
		if quad.is_empty() or ViewFootprint.distance_outside(quad, z.center) <= view_margin + float(z.radius):
			_fill[z.id] = true


# --- chunks ---

func loaded_keys() -> Array[Vector2i]:
	return _keys.duplicate()


func chunk(key: Vector2i) -> WorldChunk:
	return _chunks.get(key, null)


## The chunks that must be loaded for a cell at `center_local`: the 3 x 3 round its chunk, plus
## every chunk whose square comes within VIEW_SET_MARGIN_TM of the widest camera view of it.
## Sorted (y, x). At most 11 at size 1 (measured), against caps.view_set_chunks 12.
func view_set_keys(center_local: Vector2) -> Array[Vector2i]:
	var c := chunk_of_local(center_local)
	var found := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			found[Vector2i(c.x + dx, c.y + dy)] = true
	var quad := ViewFootprint.corners(center_local, camera, float(camera.zoom_max), view_aspect)
	if not quad.is_empty():
		# The quad in chunk-relative float64 coordinates: local + origin, in tm.
		var qx := PackedFloat64Array()
		var qy := PackedFloat64Array()
		var ox := origin_x_am / _tm_to_am
		var oy := origin_y_am / _tm_to_am
		for v in quad:
			qx.append(ox + float(v.x))
			qy.append(oy + float(v.y))
		var lo_x := floori((_min(qx) - VIEW_SET_MARGIN_TM) / chunk_tm)
		var hi_x := floori((_max(qx) + VIEW_SET_MARGIN_TM) / chunk_tm)
		var lo_y := floori((_min(qy) - VIEW_SET_MARGIN_TM) / chunk_tm)
		var hi_y := floori((_max(qy) + VIEW_SET_MARGIN_TM) / chunk_tm)
		for ky in range(lo_y, hi_y + 1):
			for kx in range(lo_x, hi_x + 1):
				var key := Vector2i(kx, ky)
				if found.has(key):
					continue
				if _quad_square_distance(qx, qy, kx * chunk_tm, ky * chunk_tm, chunk_tm) <= VIEW_SET_MARGIN_TM:
					found[key] = true
	var out: Array[Vector2i] = []
	for key in found:
		out.append(key)
	out.sort_custom(_key_less)
	return out


## Loads every missing chunk of the view set round `center_local` now (a new world, a Continue, a
## teleport).
func load_view_set_now(sim: PoolSim, center_local: Vector2) -> void:
	for key in view_set_keys(center_local):
		if not _chunks.has(key):
			_load_chunk(sim, key)


## The sleeping creatures' ids, sorted.
func sleeping_ids() -> PackedStringArray:
	var field: CreatureField = _field.get_ref() if _field != null else null
	var out := PackedStringArray()
	if field != null:
		for c in field.creatures:
			if c.asleep:
				out.append(c.id)
	out.sort()
	return out


## The distance from a local point to the square of chunk `key`: 0 inside it. Measured on absolute
## values in float64, so it does not depend on where the origin is.
func nearest(key: Vector2i, p: Vector2) -> float:
	var a := abs_of_local(p)
	return _square_distance(key, a[0] / _tm_to_am, a[1] / _tm_to_am)


## The keys of every chunk a disc ({center: local Vector2, radius}) reaches, sorted (y, x).
func disc_keys(disc: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := abs_of_local(disc.center)
	var x := a[0] / _tm_to_am
	var y := a[1] / _tm_to_am
	var r := float(disc.radius)
	for ky in range(floori((y - r) / chunk_tm), floori((y + r) / chunk_tm) + 1):
		for kx in range(floori((x - r) / chunk_tm), floori((x + r) / chunk_tm) + 1):
			if _square_distance(Vector2i(kx, ky), x, y) <= r:
				out.append(Vector2i(kx, ky))
	return out


## The endless state for snapshots and hashing (spine 3.12's "world" block).
func snapshot(sim: PoolSim) -> Dictionary:
	var keys := []
	for key in _keys:
		keys.append([key.x, key.y])
	var zone_rngs := {}
	for id in _sorted(_zone_abs.keys()):
		var stream: RandomNumberGenerator = sim.region.streams.get(id, null)
		zone_rngs[id] = stream.state if stream != null else 0
	return {
		"gen_version": gen_version, "size": size,
		"origin_am": [origin_x_am, origin_y_am],
		"checkpoint_am": [checkpoint_am[0], checkpoint_am[1], checkpoint_am[2], checkpoint_am[3]],
		"respawn_pending": sim.respawn_pending,
		"chunks": keys,
		"zone_rngs": zone_rngs,
		"site_counts": _sorted_dict(site_counts),
		"sleeping": Array(sleeping_ids()),
		"slots": _slots(sim),
		"cell_tile": [_cell_tile.x, _cell_tile.y],
		"counters": counters.duplicate(),
	}


# --- step 3: unload ---

## Unloads every chunk whose nearest point lies beyond the unload ring from the body, unless an awake
## creature's reach touches it (its site's chunks, or the leash disc of a creature with no site; a
## token holder is awake, so it holds its ground too). Keys are visited in (y, x) order.
func _unload(sim: PoolSim) -> void:
	var a := abs_of_local(sim.motion.position)   # nearest() for every key, the body's part once
	var x := a[0] / _tm_to_am
	var y := a[1] / _tm_to_am
	var ring := float(rings.unload)
	if _within_bound(_unload_bound, x, y, ring):
		return   # every loaded chunk is still within the ring
	var held: Variant = null   # the holds are only needed for a chunk beyond the ring
	var gone: Array[Vector2i] = []
	var far := 0.0
	var size_tm := chunk_tm
	for key in _keys:
		# _square_distance written out.
		var x0 := key.x * size_tm
		var y0 := key.y * size_tm
		var dx := maxf(maxf(x0 - x, x - (x0 + size_tm)), 0.0)
		var dy := maxf(maxf(y0 - y, y - (y0 + size_tm)), 0.0)
		var d := sqrt(dx * dx + dy * dy)
		far = maxf(far, d)
		if d > ring:
			if held == null:
				held = _held_keys(sim)
			if not held.has(key):
				gone.append(key)
	_unload_bound = _bound_at(x, y, ring - far, ring) if far <= ring else PackedFloat64Array()
	for key in gone:
		_unload_chunk(sim, key)
	if not gone.is_empty():
		_apply_caps(sim)   # after the unloaded sites' creatures left (G7)


## The chunks awake creatures hold: a site creature its site's reach chunks, a creature with no site
## the chunks its leash disc reaches (C-6); a scripted body (no brain) holds none.
func _held_keys(sim: PoolSim) -> Dictionary:
	var held := {}
	if sim.creatures == null:
		return held
	for c in sim.creatures.awake():
		if c.brain == null:
			continue
		var keys: Array[Vector2i] = sites[c.site_id].chunks if sites.has(c.site_id) else disc_keys(CreatureBrain.leash_disc(c.brain))
		for key in keys:
			held[key] = true
	return held


## Forgets one chunk: the creatures of the sites homed in it leave ("unloaded", in (number, id)
## order) with their queue entries and site records, its zones' plankton is dropped and the zones
## leave the region, its colliders leave the arena, and chunk_unloaded tells the scene.
func _unload_chunk(sim: PoolSim, key: Vector2i) -> void:
	var ch: WorldChunk = _chunks[key]
	if _home_count != sites.size():
		_index_homes()
	var mine: Dictionary = _home_sites.get(key, {})
	_home_sites.erase(key)
	_home_count -= mine.size()
	if sim.creatures != null and not mine.is_empty():
		for c in sim.creatures.creatures.duplicate():
			if mine.has(c.site_id):
				sim.creatures.remove(c, "unloaded", sim.tick, false)
		var kept: Array[Dictionary] = []
		for e in sim.creatures.queue:
			if not mine.has(e.site):
				kept.append(e)
		sim.creatures.queue = kept
	for id in mine:
		sites.erase(id)
		_forget_role(id)
	for z in ch.zones:
		sim.plankton.drop_zone(z.id)
		sim.plankton.active_zones.erase(z.id)
		var was := sim.region.zone(z.id)
		sim.region.remove_zone(z.id)
		_zones_version += 1
		_unindex_zone(sim.region, was)
		_zone_abs.erase(z.id)
		_zone_chunk.erase(z.id)
		_fill.erase(z.id)
		_trimmed.erase(z.id)
	(sim.arena as ChunkArena).remove_chunk(key)
	_chunks.erase(key)
	_keys.erase(key)
	_load_bound = PackedFloat64Array()   # a missing chunk now
	_emit(sim, {"type": "chunk_unloaded", "key": key})


# --- step 4: load ---

## Loads the nearest missing chunk within the load ring (ties by key), up to caps.loads_per_tick a
## tick, after the sleepers that wake this tick have their site chunks. With caps.chunks loaded, the
## nearest missing chunk of the view set loads instead (never refused), and chunk_waits counts each
## time the nearest missing chunk had to give way or wait (B-5: a backstop a swim should never need).
func _load(sim: PoolSim, view_from: Dictionary) -> void:
	# The sleepers step 5 will wake: their reach chunks load first, never refused and never counted.
	for c in _wakers(sim, view_from):
		for key in sites[c.site_id].chunks:
			if not _chunks.has(key):
				_load_chunk(sim, key)
	var body := sim.motion.position
	var view: Array[Vector2i] = []
	for i in int(caps.loads_per_tick):
		var key: Variant = _nearest_missing(body, float(rings.load))
		if key == null:
			break
		if _keys.size() >= int(caps.chunks):
			if view.is_empty():
				view = view_set_keys(body)
			var vkey: Variant = _nearest_missing_of(view, body)
			if vkey == null:
				counters.chunk_waits += 1
				break
			if vkey != key:
				counters.chunk_waits += 1
			key = vkey
		_load_chunk(sim, key)


## The missing key of `keys` nearest `body`, least (distance, y, x); null when all are loaded.
func _nearest_missing_of(keys: Array[Vector2i], body: Vector2) -> Variant:
	var best: Variant = null
	var best_d := INF
	for key in keys:
		if _chunks.has(key):
			continue
		var d := nearest(key, body)
		if best == null or d < best_d or (d == best_d and _key_less(key, best)):
			best = key
			best_d = d
	return best


## The missing chunk nearest `body` within `ring`, least (distance, y, x); null when every chunk in
## reach is loaded.
func _nearest_missing(body: Vector2, ring: float) -> Variant:
	var a := abs_of_local(body)
	var x := a[0] / _tm_to_am
	var y := a[1] / _tm_to_am
	if _within_bound(_load_bound, x, y, ring):
		return null   # still no missing chunk within the ring
	var best: Variant = null
	var best_d := INF
	# The ring's box, scanned within the bound's wider box (every chunk outside that lies at least
	# `wide` away); the nearest missing chunk of the wider box sets the bound.
	var kx0 := floori((x - ring) / chunk_tm)
	var kx1 := floori((x + ring) / chunk_tm)
	var ky0 := floori((y - ring) / chunk_tm)
	var ky1 := floori((y + ring) / chunk_tm)
	var wide := ring + LOAD_BOUND_TM
	var nearest_d := wide
	# Keys run (y, x), so the first of equal distances is the least key.
	for ky in range(floori((y - wide) / chunk_tm), floori((y + wide) / chunk_tm) + 1):
		for kx in range(floori((x - wide) / chunk_tm), floori((x + wide) / chunk_tm) + 1):
			var key := Vector2i(kx, ky)
			if _chunks.has(key):
				continue
			var d := _square_distance(key, x, y)
			nearest_d = minf(nearest_d, d)
			if d <= ring and d < best_d and kx >= kx0 and kx <= kx1 and ky >= ky0 and ky <= ky1:
				best = key
				best_d = d
	_load_bound = _bound_at(x, y, nearest_d - ring, ring) if best == null else PackedFloat64Array()
	return best


## A ring bound for a body at absolute (x, y) that may move `room` tm (less the rounding slack), or
## empty when it may not move at all.
static func _bound_at(x: float, y: float, room: float, ring: float) -> PackedFloat64Array:
	var r := room - RING_BOUND_SLACK_TM
	return PackedFloat64Array([x, y, r, ring]) if r > 0.0 else PackedFloat64Array()


## Whether a body at absolute (x, y) lies strictly within `bound`'s room of where it was set, for
## the same ring.
static func _within_bound(bound: PackedFloat64Array, x: float, y: float, ring: float) -> bool:
	if bound.size() != 4 or bound[3] != ring:
		return false
	var dx := x - bound[0]
	var dy := y - bound[1]
	return dx * dx + dy * dy < bound[2] * bound[2]


## Loads one chunk: its colliders into the arena, its zones into the region (each with its own
## plankton stream, seeded from the world seed, the generator version and the zone's id, so a zone's
## food is the same whatever route reaches it), then every awake body and the cell are settled
## against the new colliders, and chunk_loaded tells the scene.
func _load_chunk(sim: PoolSim, key: Vector2i) -> void:
	var ch := _generated(key)
	_loads += 1
	var colliders: Array[Dictionary] = []
	for s in ch.shells:
		colliders.append({"id": s.id, "x": float(s.x), "y": float(s.y), "r": float(s.r)})
	(sim.arena as ChunkArena).add_chunk(key, colliders)
	for z in ch.zones:
		var fresh := sim.region.add_zone(z.id, local_of_tm(float(z.x), float(z.y)), float(z.radius), float(z.capacity),
			float(z.growth_rate))
		var stream := RandomNumberGenerator.new()
		stream.seed = WorldHash.hash_ints(PackedInt64Array([world_seed, gen_version, WorldHash.str32(z.id), _str_plankton]))
		sim.region.streams[z.id] = stream
		_zone_abs[z.id] = PackedFloat64Array([float(z.x), float(z.y)])
		_zone_chunk[z.id] = key
		_zones_version += 1
		if fresh:
			_index_added_zone(sim.region)
	if sim.creatures != null:
		for s in ch.sites:
			if (s.sizes as Array).has(size):
				_note_home(s.id, key)
				sites[s.id] = _site_record(s, key)
				_note_role(sim, s.id, str(s.species))
				sim.creatures._enqueue(s.id, s.species, sim.tick)
	# The backstop: no body is left inside a new collider. The loads come from 56 tm out, but a debug
	# move, a waking creature or a test may put a body anywhere.
	if sim.creatures != null:
		for c in sim.creatures.awake():
			sim.arena.settle(c.motion, c.phenotype.radius)
			c.actor.position = c.motion.position
	if sim.motion != null and not sim.dead:
		sim.arena.settle(sim.motion, sim.phenotype.radius)
		sim.actor.position = sim.motion.position
	_insert_key(key)
	_chunks[key] = ch
	_unload_bound = PackedFloat64Array()   # a loaded chunk that may lie beyond the unload ring
	_emit(sim, _chunk_loaded_event(ch))
	_apply_caps(sim)


## Chunk `key` at the current size: the one generated ahead when there is one (taken), else now.
func _generated(key: Vector2i) -> WorldChunk:
	_check_ahead_gen()
	var k := Vector3i(key.x, key.y, size)
	var ch: WorldChunk = _ahead.get(k)
	if ch == null:
		return gen.chunk(size, key.x, key.y)
	_ahead.erase(k)
	_ahead_tick = 0
	return ch


## Forgets the chunks generated ahead unless `gen` is the generator they came from, bound to the same
## content, species, seed and version (WorldGen.chunk's every input but the key and the size).
func _check_ahead_gen() -> void:
	var g := gen
	if is_same(_ahead_gen, g) and _ahead_binding.size() == 4 and is_same(_ahead_binding[0], g.content) \
			and is_same(_ahead_binding[1], g.species) and _ahead_binding[2] == g.world_seed \
			and _ahead_binding[3] == g.gen_version:
		return
	_ahead.clear()
	_ahead_gen = g
	_ahead_binding = [g.content, g.species, g.world_seed, g.gen_version] if g != null else []


## On a tick that loads nothing: generates the missing chunk nearest the point AHEAD_LEAD_S ahead of
## the cell along its velocity, within the load ring plus AHEAD_MARGIN_TM of it (least (distance, y,
## x)), and keeps it; with AHEAD_KEEP kept, in place of the kept chunk farthest from that point when
## it is nearer. A look that generates nothing waits AHEAD_REFRESH_TICKS ticks, or until a load
## takes a kept chunk, before the next.
func _look_ahead(sim: PoolSim) -> void:
	if sim.tick < _ahead_tick:
		return
	_ahead_tick = sim.tick + AHEAD_REFRESH_TICKS
	_check_ahead_gen()
	var a := abs_of_local(sim.motion.position + sim.motion.velocity * AHEAD_LEAD_S)
	var x := a[0] / _tm_to_am
	var y := a[1] / _tm_to_am
	var ring := float(rings.load) + AHEAD_MARGIN_TM
	var best: Variant = null
	var best_d := INF
	for ky in range(floori((y - ring) / chunk_tm), floori((y + ring) / chunk_tm) + 1):
		for kx in range(floori((x - ring) / chunk_tm), floori((x + ring) / chunk_tm) + 1):
			var key := Vector2i(kx, ky)
			if _chunks.has(key) or _ahead.has(Vector3i(kx, ky, size)):
				continue
			var d := _square_distance(key, x, y)
			if d <= ring and d < best_d:
				best = key
				best_d = d
	if best == null:
		return
	if _ahead.size() >= AHEAD_KEEP:
		var far: Variant = null
		var far_d := -1.0
		for k in _ahead:
			var d := _square_distance(Vector2i(k.x, k.y), x, y)
			if d > far_d:
				far = k
				far_d = d
		if far_d <= best_d:
			return
		_ahead.erase(far)
	_ahead[Vector3i(best.x, best.y, size)] = gen.chunk(size, best.x, best.y)
	_ahead_tick = 0   # look again on the next quiet tick, until the keep is full or nothing is nearer


# --- sleep and wake (step 5) ---

## What steps 4 and 5 measure sleep and wake from, once a tick: {"places": every place the cell has,
## "quads": the widest view's footprint of each place, "far": the farthest any footprint reaches
## from its place}.
func _wake_view(sim: PoolSim) -> Dictionary:
	var places := sim._player_places()
	var quads: Array[PackedVector2Array] = []
	var far := 0.0
	for place in places:
		var quad := ViewFootprint.corners(place, camera, float(camera.zoom_max), view_aspect)
		quads.append(quad)
		for corner in quad:
			far = maxf(far, place.distance_to(corner))
	return {"places": places, "quads": quads, "far": far}


## The wake distance: from `p` to the nearest place.
static func _wake_distance(p: Vector2, view_from: Dictionary) -> float:
	var d := INF
	for place in view_from.places:
		d = minf(d, p.distance_to(place))
	return d


## Whether a body of radius `r` at `p`, `d` from the nearest place, is in view of any place: within
## the spawn-view margin plus r of a footprint (as the spawn check measures it). No footprint reaches
## past `far`, so a body beyond it plus the margin is out of view without the quad test.
func _in_view(p: Vector2, r: float, d: float, view_from: Dictionary) -> bool:
	var margin := view_margin + r
	if d > float(view_from.far) + margin + 0.01:
		return false
	for quad in view_from.quads:
		if quad.is_empty() or ViewFootprint.distance_outside(quad, p) <= margin:
			return true
	return false


## The sleepers step 5 will wake this tick: inside the wake ring or in view. Those whose site is in the
## table are returned (their reach chunks load first); those step 5's pass visits are kept for it.
func _wakers(sim: PoolSim, view_from: Dictionary) -> Array:
	var out := []
	_waking_view = view_from
	_waking.clear()
	_waking_d.clear()
	if sim.creatures == null:
		return out
	var wake_r := float(rings.wake)
	var places: Array = view_from.places
	var far := float(view_from.far)
	var bounded := places.size() == 1
	if bounded and _swum_from.is_finite() and absf(far - _bound_view[0]) <= WAKE_FAR_TOLERANCE_TM \
			and wake_r == _bound_view[1] and view_margin == _bound_view[2]:
		var place: Vector2 = places[0]
		_swum += place.distance_to(_swum_from)
		_swum_from = place
	else:
		_wake_bound.clear()
		_swum = 0.0
		_swum_from = places[0] if bounded else Vector2.INF
		_bound_view = PackedFloat64Array([far, wake_r, view_margin])
	if _wake_bound.size() > sim.creatures.creatures.size() + 64:
		_wake_bound.clear()   # mostly creatures gone since: measure the rest again
	var reach := _bound_view[0] + WAKE_FAR_TOLERANCE_TM + view_margin + 0.01   # _in_view's own cut, plus r
	for c in sim.creatures.creatures:
		if not c.asleep:
			continue
		var b: Variant = _wake_bound.get(c)
		if b != null and _swum < b[1] and b[0] == c.motion.position:
			continue
		var passed := _in_pass(c)
		var sited := sites.has(c.site_id)
		if not passed and not sited:
			continue
		var at := c.motion.position
		var r := c.phenotype.radius
		var d := _wake_distance(at, view_from)
		if d < wake_r or _in_view(at, r, d, view_from):
			if sited:
				out.append(c)
			if passed:
				_waking.append(c)
				_waking_d.append(d)
		elif bounded:
			_wake_bound[c] = [at, _swum + d - maxf(wake_r, reach + r) - WAKE_SLACK_TM]
	return out


## Whether step 5's pass visits `c`: scripted and siteless creatures never sleep (C-6).
static func _in_pass(c: CreatureField.Creature) -> bool:
	return not c.scripted and c.brain != null and not c.site_id.is_empty()


## Step 5: first the hold pass (B-6, _hold_pass), then one pass over the site creatures in (slot, or
## ASLEEP_KEY for a sleeper; number; id) order.
## An awake one sleeps when it is calm, beyond the sleep ring, out of view and not a token holder; a
## sleeper wakes inside the wake ring or in view. Then over caps.awake the farthest calm creature
## between the rings sleeps (none: awake_overflow counts once), and over caps.sleepers the farthest
## sleeper is evicted and its site requeued (D-12). Scripted and siteless creatures never sleep (C-6).
##
## The sleepers that wake are _wakers' (the same test on the same view, nothing having moved them
## since), woken after every awake creature, as their key orders them. A sleeper's distance is only
## needed for an eviction, so it is measured only then.
func _sleep_and_wake(sim: PoolSim, view_from: Dictionary) -> void:
	var field := sim.creatures
	if field == null:
		return
	if not is_same(_waking_view, view_from):
		_wakers(sim, view_from)
	_waking_view = null
	_hold_pass(sim, view_from)
	var buckets: Array = []
	for i in CreatureField.ASLEEP_KEY:
		buckets.append([])
	for c in field.awake():   # sorted (number, id), so each bucket is too
		if _in_pass(c):
			buckets[c.think_slot].append(c)
	var list: Array = []
	for b in buckets:
		list.append_array(b)
	var dist := {}
	var sleep_r := float(rings.sleep)
	for c in list:
		var d := _wake_distance(c.motion.position, view_from)
		dist[c.id] = d
		if _calm(c) and d > sleep_r and not _in_view(c.motion.position, c.phenotype.radius, d, view_from) \
				and not field.engaged_on_player.has(c.id):
			field.sleep(c, sim.tick)
	for i in _waking.size():
		var c := _waking[i]
		dist[c.id] = _waking_d[i]
		field.wake(c, sim.tick)
		list.append(c)
	_waking.clear()
	while field.awake().size() > int(caps.awake):
		var pick: CreatureField.Creature = null
		for c in list:
			if c.asleep:
				continue
			var d: float = dist[c.id]
			if not _calm(c) or field.engaged_on_player.has(c.id) or d < float(rings.wake) or d > sleep_r:
				continue
			if pick == null or d > dist[pick.id] or (d == dist[pick.id] and c.id < pick.id):
				pick = c
		if pick == null:
			counters.awake_overflow += 1
			break
		field.sleep(pick, sim.tick)
	if field.creatures.size() - field.awake().size() <= int(caps.sleepers):
		return
	# Every sleeper the pass visits (those it put to sleep are among them), with its distance.
	var asleep: Array[CreatureField.Creature] = []
	for c in field.creatures:
		if c.asleep and _in_pass(c):
			asleep.append(c)
			if not dist.has(c.id):
				dist[c.id] = _wake_distance(c.motion.position, view_from)
	while field.creatures.size() - field.awake().size() > int(caps.sleepers):
		var e: CreatureField.Creature = null
		for c in asleep:
			if e == null or dist[c.id] > dist[e.id] or (dist[c.id] == dist[e.id] and c.id < e.id):
				e = c
		if e == null:
			break
		field.remove(e, "evicted", sim.tick, true)
		asleep.erase(e)   # still marked asleep: left in the list it would be picked again forever
		counters.evictions += 1


## Step 5's first pass (B-6): an awake creature whose site's reach-disc centre (a siteless one's
## leash-disc centre) lies beyond the hold ring of every place leaves, "unloaded", its site queued
## again at once (CreatureField.let_go); step 3 releases its chunks on the next tick. It is at least
## hold minus the reach radius (85 tm) away, so out of view. A scripted body holds nothing and stays.
func _hold_pass(sim: PoolSim, view_from: Dictionary) -> void:
	var hold := float(rings.hold)
	for c in sim.creatures.awake().duplicate():
		if c.brain == null:
			continue
		var center: Vector2 = sites[c.site_id].reach.center if sites.has(c.site_id) else CreatureBrain.leash_disc(c.brain).center
		if _wake_distance(center, view_from) > hold:
			sim.creatures.let_go(c, sim.tick)


## Whether the creature's (state/phase) is in CALM, without building the key (a pass asks for every
## awake creature; tests/test_perf_world_caches.gd holds the two together).
static func _calm(c: CreatureField.Creature) -> bool:
	var m := c.brain
	var state := m.state
	if state == "forage":
		return m.phase == "seek" or m.phase == "eat"
	if state == "rest":
		return m.phase == "lurk" or m.phase == ""
	return state == "wander" and m.phase == "patrol"


## {creature id: think slot} of the awake creatures, sorted by id.
func _slots(sim: PoolSim) -> Dictionary:
	var out := {}
	if sim.creatures != null:
		for c in sim.creatures.awake():
			out[c.id] = c.think_slot
	return _sorted_dict(out)


## The niche caps: per role, the live sites in the table whose species fills it (summed over the
## species, so two species sharing a role share the cap). Roles with no loaded site get 0. A niche
## keeps its count (EcologyRegion.set_niche), so no creature is removed by a lower cap. This counts
## the table afresh, for a caller that changed it; the stream's own loads and unloads keep the count.
func recompute_caps(sim: PoolSim) -> void:
	if sim.creatures == null:
		return
	_site_role.clear()
	_role_sites.clear()
	for id in sites:
		_note_role(sim, id, str(sites[id].species))
	_apply_caps(sim)


## recompute_caps from the kept count (counted afresh if the table changed size behind it).
func _apply_caps(sim: PoolSim) -> void:
	if sim.creatures == null:
		return
	if _site_role.size() != sites.size():
		recompute_caps(sim)
		return
	var per_role := {}
	for id in sim.species.species_ids():
		per_role[str(sim.species.niche_of(id).role)] = 0
	for role in _role_sites:
		per_role[role] = int(per_role.get(role, 0)) + int(_role_sites[role])
	var roles := per_role.keys()
	roles.sort()
	for role in roles:
		sim.region.set_niche(role, per_role[role])


## Site `id` entered under its home chunk `key` (before its record goes into the table).
func _note_home(id: String, key: Vector2i) -> void:
	if _home_count != sites.size():
		_index_homes()
	if sites.has(id):
		var was: Vector2i = sites[id].home_chunk
		_home_sites[was].erase(id)
		_home_count -= 1
	if not _home_sites.has(key):
		_home_sites[key] = {}
	_home_sites[key][id] = true
	_home_count += 1


## _home_sites counted afresh from the table.
func _index_homes() -> void:
	_home_sites.clear()
	for id in sites:
		var key: Vector2i = sites[id].home_chunk
		if not _home_sites.has(key):
			_home_sites[key] = {}
		_home_sites[key][id] = true
	_home_count = sites.size()


## Site `id` (of `species_id`) counted in its role, once.
func _note_role(sim: PoolSim, id: String, species_id: String) -> void:
	_forget_role(id)
	var role := str(sim.species.niche_of(species_id).role)
	_site_role[id] = role
	_role_sites[role] = int(_role_sites.get(role, 0)) + 1


func _forget_role(id: String) -> void:
	if not _site_role.has(id):
		return
	var role: String = _site_role[id]
	_site_role.erase(id)
	var n := int(_role_sites[role]) - 1
	if n == 0:
		_role_sites.erase(role)
	else:
		_role_sites[role] = n


## A site's local record from its WorldChunk entry (absolute) and its home chunk: its local home,
## territory and reach (derived), and "abs_tm", their absolute values [home x, y, territory x, y,
## reach x, y] (tm; the territory's NaN when it has none) that a rebase derives them from again.
func _site_record(s: Dictionary, key: Vector2i) -> Dictionary:
	var chunks: Array[Vector2i] = []
	chunks.assign(s.chunks)
	var t: Dictionary = s.territory
	var r: Dictionary = s.reach
	var rec := {"id": s.id, "species": s.species, "heading": float(s.heading), "chunks": chunks, "home_chunk": key, "abs": s,
		"abs_tm": PackedFloat64Array([float(s.x), float(s.y), NAN if t.is_empty() else float(t.x),
			NAN if t.is_empty() else float(t.y), float(r.x), float(r.y)]),
		"territory": {} if t.is_empty() else {"center": Vector2.ZERO, "radius": float(t.radius)},
		"reach": {"center": Vector2.ZERO, "radius": float(r.radius)}}
	_derive_site_local(rec, _tm_to_am, origin_x_am, origin_y_am)
	return rec


## A site record's local home, territory centre and reach centre, again from "abs_tm", in place.
## Each is local_of_tm's own float64 expression written out (so the same float32 result): a rebase
## does this for every loaded site, and a rebase tick is timed (G17).
static func _derive_site_local(rec: Dictionary, k: float, ox: float, oy: float) -> void:
	var a: PackedFloat64Array = rec.abs_tm
	rec.home = Vector2((a[0] * k - ox) / k, (a[1] * k - oy) / k)
	if not rec.territory.is_empty():
		rec.territory.center = Vector2((a[2] * k - ox) / k, (a[3] * k - oy) / k)
	rec.reach.center = Vector2((a[4] * k - ox) / k, (a[5] * k - oy) / k)


## Every local value that is derived from an absolute one, again from its absolute value (zones
## with local_of_tm written out, as sites are). With the food view's index current, a zone's
## absolute centre comes from its packed copy there (the same float64 values as _zone_abs); a zone
## that is not the index's own at its place sends the index to a rebuild. True when the index kept
## its places and every zone in it has an absolute centre (so each moved with the origin).
func _rederive(sim: PoolSim) -> bool:
	var k := _tm_to_am
	var ox := origin_x_am
	var oy := origin_y_am
	if sim.arena is ChunkArena:
		(sim.arena as ChunkArena).set_origin(ox / k, oy / k)
	var indexed := _zones_indexed == _zones_version and _zone_refs.size() == sim.region.zones.size()
	var refs := _zone_refs
	var ax := _zone_ax
	var ay := _zone_ay
	var cs := _zone_c
	var moved := true
	var i := 0
	for z in sim.region.zones:
		if indexed and is_same(refs[i], z):
			if not is_nan(ax[i]):
				var c := Vector2((ax[i] * k - ox) / k, (ay[i] * k - oy) / k)
				z.center = c
				cs[i] = c   # the food view's index moves with its zones
			else:
				cs[i] = z.center
				moved = false
		else:
			indexed = false
			var a: Variant = _zone_abs.get(z.id)
			if a != null:
				z.center = Vector2((a[0] * k - ox) / k, (a[1] * k - oy) / k)
		i += 1
	_zones_version += 1
	_index_epoch += 1   # the centres moved
	if indexed:
		_zones_indexed = _zones_version
	else:
		_index_zones(sim.region)
	# _derive_site_local written out.
	for rec: Dictionary in sites.values():
		var a: PackedFloat64Array = rec.abs_tm
		rec.home = Vector2((a[0] * k - ox) / k, (a[1] * k - oy) / k)
		var t: Dictionary = rec.territory
		if not t.is_empty():
			t.center = Vector2((a[2] * k - ox) / k, (a[3] * k - oy) / k)
		rec.reach.center = Vector2((a[4] * k - ox) / k, (a[5] * k - oy) / k)
	return indexed and moved


## chunk_loaded's payload (spine 3.12), in the frame in force now.
func _chunk_loaded_event(ch: WorldChunk) -> Dictionary:
	var shells := []
	for s in ch.shells:
		shells.append({"id": s.id, "position": local_of_tm(float(s.x), float(s.y)), "radius": float(s.r), "kind": s.kind,
			"asset": s.asset, "yaw_deg": s.yaw_deg, "scale": s.scale, "tint": s.tint})
	var zones := []
	for z in ch.zones:
		zones.append({"id": z.id, "center": local_of_tm(float(z.x), float(z.y)), "radius": float(z.radius), "region": z.region})
	var anchors := []
	for a in ch.anchors:
		anchors.append({"id": a.id, "position": local_of_tm(float(a.x), float(a.y)), "model": a.model, "dressing": a.dressing})
	var places := []
	for p in ch.places:
		places.append({"id": p.id, "kind": p.kind, "position": local_of_tm(float(p.x), float(p.y)), "yaw_deg": float(p.yaw_deg),
			"mirror": bool(p.mirror)})
	return {"type": "chunk_loaded", "key": ch.key, "shells": shells, "zones": zones, "anchors": anchors, "places": places}


## Every stream event goes out after the field and brain events already pending, so the drained list
## stays in step order and each event's positions are in the frame in force at its place.
func _emit(sim: PoolSim, event: Dictionary) -> void:
	sim._take_field_events()
	sim._emit(event)


func _insert_key(key: Vector2i) -> void:
	var i := _keys.bsearch_custom(key, _key_less)
	_keys.insert(i, key)


static func _key_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


# --- step 6: food view ---

## Which zones show plankton: those whose nearest point lies within the food ring of the body. Over
## caps.food_items (their summed item targets), the zones wholly out of view (by the spawn view's
## margin plus their radius) are trimmed, farthest first, ties to the lower id, until the rest fit;
## a zone in view is never trimmed. Zones that leave the set drop their items without events (they
## are out of view). Carrion beyond the ring goes for good. Zones flagged to fill at once fill now.
## Last, tile_entered when the cell's tile changed.
func _food_view(sim: PoolSim) -> void:
	var body := sim.motion.position
	_index_zones(sim.region)
	var ring := float(rings.food)
	var at: PackedInt32Array              # the food zones' places in the index, in zone order
	var reach := PackedFloat64Array()     # and their distances (measured again for a trim when kept)
	var bound := _food_bound
	if not bound.is_empty() and bound[3] == ring and bound[4] == _index_epoch \
			and Vector2(bound[0], bound[1]).distance_to(body) < bound[2]:
		at = _food_at   # the same zones within the ring as the last measure
	else:
		at = PackedInt32Array()
		var room := INF
		for i in _zone_ids.size():
			var d := body.distance_to(_zone_c[i]) - _zone_r[i]
			if d <= ring:
				at.append(i)
				reach.append(d)
			room = minf(room, absf(d - ring))
		_food_at = at
		room -= FOOD_BOUND_SLACK_TM
		_food_bound = PackedFloat64Array([body.x, body.y, room, ring, _index_epoch]) if room > 0.0 else PackedFloat64Array()
	var plankton := sim.plankton
	var most := plankton.max_items_per_zone
	var unit := plankton.unit_energy
	var counts := PackedInt32Array()      # and their item targets (PlanktonField.target_count written out)
	var total := 0
	for i in at:
		var n := mini(most, floori(float(_zone_refs[i].amount) / unit + PlanktonField.COUNT_EPSILON))
		counts.append(n)
		total += n
	var shown := at                       # the food zones less those trimmed
	var cap := int(caps.food_items)
	if total > cap:
		if reach.size() != at.size():
			for i in at:
				reach.append(body.distance_to(_zone_c[i]) - _zone_r[i])
		# The food zones farthest first, ties to the lower id (picked one at a time, as few are needed),
		# each trimmed when it is out of view, until the rest fit.
		var quad := ViewFootprint.corners(body, camera, float(camera.zoom_max), view_aspect)
		var box := _box(quad)
		var cut := PackedByteArray()
		cut.resize(at.size())
		var left := range(at.size())
		while total > cap and not left.is_empty():
			var best := 0
			for m in range(1, left.size()):
				var j: int = left[m]
				var b: int = left[best]
				if reach[j] > reach[b] or (reach[j] == reach[b] and _zone_ids[at[j]] < _zone_ids[at[b]]):
					best = m
			var j: int = left[best]
			left.remove_at(best)
			if not _out_of_view(quad, box, _zone_c[at[j]], _zone_r[at[j]]):
				continue
			var id := _zone_ids[at[j]]
			cut[j] = 1
			total -= counts[j]
			if not _trimmed.has(id):
				_trimmed[id] = true
				counters.food_trimmed += 1
		shown = PackedInt32Array()
		for m in at.size():
			if cut[m] == 0:
				shown.append(at[m])
	# The food set: the one given to the plankton last time while the same zones are shown (nothing
	# else changes it), else built afresh in zone order.
	var food: Dictionary = plankton.active_zones
	var same := shown == _shown_at and _index_epoch == _shown_epoch and is_same(food, _shown_food)
	if not same:
		food = {}
		for i in shown:
			food[_zone_ids[i]] = true
	# A zone stays counted as trimmed until it shows food again (or unloads).
	for id in _trimmed.keys():
		if food.has(id) or sim.region.zone(id).is_empty():
			_trimmed.erase(id)
	if not same:
		if food != plankton.active_zones:   # the same zones (in a new index): none to drop
			for id in plankton.active_zones.keys():
				if not food.has(id):
					plankton.drop_zone(id)
		plankton.active_zones = food
		_shown_at = shown
		_shown_epoch = _index_epoch
		_shown_food = food
	sim.carrion.drop_beyond(body, float(rings.food))
	var fill: Array = food.keys() if _fill_all else _fill.keys()
	fill.sort()
	for id in fill:
		if food.has(id):
			sim.plankton.fill_zone(sim.region.zone(id), sim.region, sim.arena, sim.tick, sim.now())
	_fill.clear()
	_fill_all = false
	var tile := tile_of_local(body)
	if tile != _cell_tile:
		_cell_tile = tile
		var info := gen.tile_info(WorldConfig.band_of(size), tile.x, tile.y)
		_emit(sim, {"type": "tile_entered", "tile": tile, "region": str(info.get("region", "")), "rare": str(info.get("rare", ""))})


## The zone add_zone just appended, appended to the index too when the index was current before it
## (so a load does not rebuild the index: the same entries, in the same order as a rebuild's).
func _index_added_zone(region: EcologyRegion) -> void:
	if _zones_indexed != _zones_version - 1 or _zone_refs.size() + 1 != region.zones.size():
		return
	var z: Dictionary = region.zones.back()
	var a: Variant = _zone_abs.get(z.id)
	_zone_ids.append(z.id)
	_zone_c.append(z.center)
	_zone_r.append(float(z.radius))
	_zone_refs.append(z)
	_zone_ax.append(NAN if a == null else float(a[0]))
	_zone_ay.append(NAN if a == null else float(a[1]))
	_zones_indexed = _zones_version
	_index_epoch += 1


## Zone `z`, just removed from the region (which keeps the others in order), taken out of the index
## too when the index was current before it.
func _unindex_zone(region: EcologyRegion, z: Dictionary) -> void:
	if z.is_empty() or _zones_indexed != _zones_version - 1 or _zone_refs.size() - 1 != region.zones.size():
		return
	var i := _zone_ids.find(z.id)
	if i < 0 or not is_same(_zone_refs[i], z):
		return
	_zone_ids.remove_at(i)
	_zone_c.remove_at(i)
	_zone_r.remove_at(i)
	_zone_refs.remove_at(i)
	_zone_ax.remove_at(i)
	_zone_ay.remove_at(i)
	_zones_indexed = _zones_version
	_index_epoch += 1


## Rebuilds the packed zone index when the zones changed since it was built.
func _index_zones(region: EcologyRegion) -> void:
	if _zones_indexed == _zones_version and _zone_refs.size() == region.zones.size():
		return
	_zone_ids.clear()
	_zone_c.clear()
	_zone_r.clear()
	_zone_refs.clear()
	_zone_ax.clear()
	_zone_ay.clear()
	for z in region.zones:
		_zone_ids.append(z.id)
		_zone_c.append(z.center)
		_zone_r.append(float(z.radius))
		_zone_refs.append(z)
		var a: Variant = _zone_abs.get(z.id)
		_zone_ax.append(NAN if a == null else float(a[0]))
		_zone_ay.append(NAN if a == null else float(a[1]))
	_zones_indexed = _zones_version
	_index_epoch += 1


## A footprint's bounding box [min x, min y, max x, max y] (empty for an empty footprint).
static func _box(quad: PackedVector2Array) -> PackedFloat64Array:
	if quad.is_empty():
		return PackedFloat64Array()
	var box := PackedFloat64Array([INF, INF, -INF, -INF])
	for v in quad:
		box[0] = minf(box[0], v.x)
		box[1] = minf(box[1], v.y)
		box[2] = maxf(box[2], v.x)
		box[3] = maxf(box[3], v.y)
	return box


## Whether a zone at `c` of radius `r` lies wholly out of the footprint `quad` grown by the spawn
## view's margin. A centre more than the margin, the radius and 0.01 tm (float32 rounding) from the
## footprint's box is farther still from the footprint, so it needs no edge test.
func _out_of_view(quad: PackedVector2Array, box: PackedFloat64Array, c: Vector2, r: float) -> bool:
	if quad.is_empty():
		return true
	var limit := view_margin + r
	var dx := maxf(maxf(box[0] - c.x, c.x - box[2]), 0.0)
	var dy := maxf(maxf(box[1] - c.y, c.y - box[3]), 0.0)
	var far := limit + 0.01
	if dx * dx + dy * dy > far * far:
		return true
	return ViewFootprint.distance_outside(quad, c) > limit


## The distance from the absolute point (x, y) (tm) to the square of chunk `key`, in float64.
func _square_distance(key: Vector2i, x: float, y: float) -> float:
	var x0 := key.x * chunk_tm
	var y0 := key.y * chunk_tm
	var dx := maxf(maxf(x0 - x, x - (x0 + chunk_tm)), 0.0)
	var dy := maxf(maxf(y0 - y, y - (y0 + chunk_tm)), 0.0)
	return sqrt(dx * dx + dy * dy)


## The distance from a convex quad (qx, qy) to the square [x0, x0 + side) x [y0, y0 + side): 0
## when they overlap (no separating axis), else the least vertex-to-edge distance either way.
static func _quad_square_distance(qx: PackedFloat64Array, qy: PackedFloat64Array, x0: float, y0: float, side: float) -> float:
	var sx := PackedFloat64Array([x0, x0 + side, x0 + side, x0])
	var sy := PackedFloat64Array([y0, y0, y0 + side, y0 + side])
	if not _separated(qx, qy, sx, sy) and not _separated(sx, sy, qx, qy):
		return 0.0
	var best := INF
	for i in qx.size():
		var dx := maxf(maxf(x0 - qx[i], qx[i] - (x0 + side)), 0.0)
		var dy := maxf(maxf(y0 - qy[i], qy[i] - (y0 + side)), 0.0)
		best = minf(best, sqrt(dx * dx + dy * dy))
	for k in 4:
		for i in qx.size():
			var j := (i + 1) % qx.size()
			best = minf(best, _point_segment(sx[k], sy[k], qx[i], qy[i], qx[j], qy[j]))
	return best


## True when one of polygon a's edge normals separates polygon a from polygon b (both convex).
static func _separated(ax: PackedFloat64Array, ay: PackedFloat64Array, bx: PackedFloat64Array, by: PackedFloat64Array) -> bool:
	for i in ax.size():
		var j := (i + 1) % ax.size()
		var nx := -(ay[j] - ay[i])
		var ny := ax[j] - ax[i]
		var a_lo := INF
		var a_hi := -INF
		for k in ax.size():
			var d := ax[k] * nx + ay[k] * ny
			a_lo = minf(a_lo, d)
			a_hi = maxf(a_hi, d)
		var b_lo := INF
		var b_hi := -INF
		for k in bx.size():
			var d := bx[k] * nx + by[k] * ny
			b_lo = minf(b_lo, d)
			b_hi = maxf(b_hi, d)
		if a_hi < b_lo or b_hi < a_lo:
			return true
	return false


static func _point_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var ex := bx - ax
	var ey := by - ay
	var len_sq := ex * ex + ey * ey
	var t := clampf(((px - ax) * ex + (py - ay) * ey) / len_sq, 0.0, 1.0) if len_sq > 0.0 else 0.0
	var dx := ax + ex * t - px
	var dy := ay + ey * t - py
	return sqrt(dx * dx + dy * dy)


static func _min(a: PackedFloat64Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m


static func _max(a: PackedFloat64Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, v)
	return m


static func _sorted_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in _sorted(d.keys()):
		out[k] = d[k]
	return out


static func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out
