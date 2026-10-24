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
##
## Growth (S2). With a meter (PoolSim.growth), step 1 grows the cell when the meter says it is due
## (grow): the world is re-expressed one size up round the cell's absolute point, and for the beat
## after it the load step loads beat_loads_per_tick chunks a tick. The next size's settle point is a
## pure function of the cell's absolute point (next_size_clear_point, BP-4); a last step (_prefetch)
## generates the next size's chunks round the cell a few at a time while the ring is nearly full, so
## the point and the growth tick seldom generate them. Neither cache changes a result, and neither
## is in the snapshot.

## tm: look_ahead_max (2.5) + spawn_view_margin_m (1.0) + MAX_ZONE_RADIUS_TM. Every zone touching the
## view plus its margin has its centre in a view-set chunk (S1 core C-1).
const VIEW_SET_MARGIN_TM := 11.5
## tm: the largest zone radius at size 1 (tile rule 3).
const MAX_ZONE_RADIUS_TM := 8.0
## The Vector2 keys a rebase shifts on each plankton and carrion item (RebaseShift.items).
const PLANKTON_POSITIONS: PackedStringArray = ["position", "anchor"]
const CARRION_POSITIONS: PackedStringArray = ["position"]
## The (state/phase) pairs a creature may sleep in (spine 3.11): resting, patrolling or foraging, not
## watching, noticing, chasing, attacking, fleeing or going home. The set is the brain's (D-62); this
## name stays for tests/test_perf_world_caches.gd, which reads it.
const CALM := CreatureBrain.CALM
## Look-ahead generation: tm beyond the load ring a chunk may be generated ahead, how many are kept,
## how far ahead along its velocity (s) the cell is taken to be, and how long (ticks) a look that
## found nothing to generate waits before the next.
const AHEAD_MARGIN_TM := 16.0
const AHEAD_KEEP := 4
const AHEAD_LEAD_S := 1.0
const AHEAD_REFRESH_TICKS := 15
## s: how far ahead along its velocity the cell is taken to be when the next size's arena gets the
## 3 x 3 round the new-size chunk it heads for (BP-4; _arena_chore).
const NEXT_LEAD_S := 2.0
## Ticks the chore keeps the set of next-size chunks it wants the arena to hold (the growth tick's
## view set round the cell's point and the 3 x 3 round the chunk it heads for) before taking it again,
## unless the cell's or the heading's new-size chunk changes first.
const NEXT_WANT_TICKS := 30
## How many sites of the chunks generated ahead have their record and creature made on a quiet tick
## (_prepare_ahead).
const PREPARE_PER_TICK := 2
## How many of the pieces the unloads let go (_let_go) a quiet tick frees.
const RELEASE_PER_TICK := 1
## S2 (C-V15 as amended): the food zones each tick of a growth's beat fills, nearest first, from the tick
## after the growth (which fills none) until every zone shown at the growth has filled (the beat is 120
## ticks; a view set shows about 16).
const FILL_ZONES_PER_TICK := 4
## Bytes of the block a tick that loads nothing asks for and drops at its end (_settle_heap).
const HEAP_SETTLE_BYTES := 4096
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
## The build's top size (world file sizes.max_in_build), set with growth (S2); 1 without it.
var max_size := 1
var origin_x_am := 0.0
var origin_y_am := 9.0
var checkpoint_am := PackedFloat64Array([0.0, 9.0, -1.5708, 1.0])    ## x, y, heading, size
## Backstops that fired: awake_overflow (more awake creatures than the cap and none calm to sleep),
## chunk_waits (a load past the chunk cap waited), food_trimmed (a far zone's food hidden over the
## item cap), evictions (a sleeper removed over the sleeper cap). With growth (S2, BP-20) also
## remnant_overflow (a growth tick with more remnants than their cap).
var counters := {"awake_overflow": 0, "chunk_waits": 0, "food_trimmed": 0, "evictions": 0}
## Morsel sites (S3, D-98, D-129): placed morsel-site id -> {food_id, due_tick}. An entry's food_id is
## its live item's carrion id ("" when it has none); due_tick is when it may spawn one. Only
## _set_food and _drop_entry write a food_id or erase an entry (BP3-3).
var morsel_sites := {}
const MORSEL_PASS_TICKS := 30
var _morsel_loaded := {}               ## loaded morsel-site id -> {abs, species, radius, energy, chunk}
var _claims := 0                       ## entries of morsel_sites with a food_id (BP3-3)
var _food_total := 0                   ## the last food view's total, the morsel claims included
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
## WorldChunk's site, and for a two-post site (S2) posts: [{home, heading, territory}] x 2}: the
## loaded live sites, local. Read it freely; only _load_chunk and
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
var _fill_spread := false              ## the growth tick: every shown food zone waits for its fill
var _fill_sort := false                ## the tick after it: queue the waiting zones nearest first
var grew_tick := -1                    ## the tick of the last growth (the sim's spawn pass skips it)
var _fill_queue: Array[String] = []    ## zone ids still to fill, FILL_ZONES_PER_TICK a tick (the beat)
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
## [content's and species' instance ids, world seed, gen version] they were made with (ids, so the
## stream holds no second path to the absolute world data)
var _ahead_binding := PackedInt64Array()
var _ahead_tick := 0                   ## the first tick the next look may run (a load resets it)
## The site records of the chunks generated ahead, made a few a tick on quiet ticks (_prepare_ahead)
## with each site's next creature (CreatureField.prepare_site), so the tick that loads the chunk and
## spawns its sites does not make them: the same key -> {site id: record}, forgotten with the chunk.
## _prepare_todo holds [key, next site index] for each chunk still to be gone through, in turn (-1:
## its parts, _ahead_parts, are still to be made).
var _ahead_sites := {}
var _prepare_todo: Array = []
## The rest of what a load makes from a chunk generated ahead, made on a quiet tick before its site
## records (_prepare_parts), so the load tick does not: the same key -> {"colliders", "streams" (zone
## id -> its plankton stream), "zone_abs", "zone_local", "event" (the chunk_loaded payload), "frame"
## (origin and scale they were made in), "mixed" (a site record was made in another frame)}. The
## colliders, streams and absolute centres are the chunk's alone; the local values and the payload
## are used only when every part and record was made in the frame in force at the load.
var _ahead_parts := {}
## What the ring's unloads let go, in pieces (each chunk; the creatures that left; its site records
## and zones; its colliders), freed RELEASE_PER_TICK pieces a tick, the last first, on the ticks that
## generate, load, unload and rebase nothing. Freed on the unload tick, which often loads a chunk too,
## their few thousand small blocks cost that tick their teardown and the allocator's sweep of them
## (glibc's malloc sweeps its fast bins at the next large request), B-7's tick 564 most of all.
## Nothing reads them, so when they are freed changes nothing else; a teleport frees them at once.
var _let_go: Array = []
var _quiet := true                     ## nothing loaded, unloaded or rebased since the last step ended
var _loads := 0                        ## chunks loaded so far (whether a tick loaded any)
var _loaded_now := false               ## the last step loaded a chunk (loaded_now)
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
## The hold pass's bound, on the same path: an awake creature's hold centre (its site's reach centre,
## or its leash disc's) stays put until a load, an unload or an origin set (_site_epoch) or a change
## of the table's size, so one measured inside the hold ring cannot leave it before the place has
## moved the ring less its distance. Each keeps [_site_epoch, the table's size, the path length at
## which it may first leave, the hold ring]; the bound restarts with the wake bound's. A rebase moves
## the centres, the place and the path's last place by the same offset, so it holds through one: each
## distance changes by float32 rounding only (some 1e-5 tm), and a bound lives no more than the hold
## ring of path, over which the stream rebases once or twice (it waits for 80 tm swum), well inside
## WAKE_SLACK_TM.
var _hold_bound := {}                  ## awake creature (Creature) -> that
var _site_epoch := 0                   ## bumped by every load, unload and set_origin_abs
## The ring bounds. A chunk's distance from the body changes by no more than the body moves, so after
## a scan found no missing chunk within the load ring (_nearest_missing), none can come within it
## before the body has moved the nearest missing one's distance less the ring, unless a chunk
## unloads; and after a scan found every loaded chunk within the unload ring (_unload), none can leave
## it before the body has moved the farthest one's distance short of the ring, unless a chunk loads.
## Each is [the body's absolute x, y (tm) at the scan, that distance, the ring], or empty.
var _load_bound := PackedFloat64Array()
var _unload_bound := PackedFloat64Array()
## The next size (S2, BP-4). The new-size chunks round the cell's new-size chunk, Vector2i -> WorldChunk
## at _next_size (size + 1 while the ring fills; the new size itself through the growth tick's beat,
## whose loads take from it), absolute tm with no local positions; the arena of the 3 x 3 of them
## round _next_key in its own frame (origin the cell's absolute point _next_from, at the new size);
## and the rings the point's spiral may go out (growth.wedge_tm / CLEAR_SPIRAL_STEP_M). WorldGen.chunk
## is pure, so a chunk from here is the one a load would make: the caches never change a result.
## The arena is kept, not rebuilt: a new _next_key adds only the chunks of its 3 x 3 it lacks, and
## on quiet ticks _arena_chore adds the chunks it wants held (_next_want: the view set the growth
## tick at the cell's point would load, and the 3 x 3 round the chunk the cell heads for), one chunk
## a tick, and takes out one a tick that is in neither that set nor _next_key's 3 x 3 (_next_held, the
## arena's keys). A collider outside A's own 3 x 3 cannot reach the spiral (the largest-shell rule),
## so the extra chunks never change a point; they keep the tick A crosses into a new chunk from
## adding three (about 160 us each), and the growth tick from adding the view set's chunks (about
## 100 us each): its loads find them held.
var _next_chunks := {}
var _next_arena: ChunkArena = null
var _next_key := Vector2i.MAX
var _next_held := {}                   ## Vector2i -> true: the chunks _next_arena holds
var _next_from := PackedFloat64Array()
var _next_want := {}                   ## Vector2i -> true: the chunks the chore wants held
var _next_want_c := Vector2i.MAX       ## the cell's new-size chunk when _next_want was taken
var _next_want_head := Vector2i.MAX    ## the heading's new-size chunk when _next_want was taken
var _next_want_tick := 0               ## the tick _next_want is taken again by
var _next_size := 0
## Quiet ticks with nothing to generate and no arena chore prepare the cached chunks' loads, one chunk a
## tick: its zones' plankton streams, seeded and unused (zone id -> RandomNumberGenerator), its
## chunk_loaded payload with every position still to place (key -> that), its zones' region records
## with their centres still to place and their absolute places (key -> [records, places]), and its
## sites' records with their local places still to derive (key -> site id -> record). A load from the
## cache takes them, so the growth tick does not make them; each is what the load would make.
var _next_streams := {}
var _next_events := {}
var _next_zones := {}
var _next_sites := {}
var wedge_rings := 4
## Tests turn this off to show the caches never change a result (S2G35): every point is then
## computed from freshly generated chunks, and nothing is prefetched or taken from the cache.
var next_cache := true
var _growing := false                  ## inside grow: its loads take from the next size's chunks
## What the growth tick lets go of (the old size's chunks, its arena, its plankton list and the
## tables of the old size's zones, sites and chunks), held so that freeing it, a large share of that
## tick's cost, falls on quiet ticks after the beat instead: one a tick (step). Nothing reads it; it
## changes no result.
var _retired: Array = []


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
	w.wedge_rings = ceili(float(config.growth.wedge_tm) / PoolSim.CLEAR_SPIRAL_STEP_M)
	var spawn: PackedFloat64Array = p_content.home.spawn
	w.checkpoint_am = PackedFloat64Array([spawn[0], spawn[1], p_content.home.spawn_heading, float(w.size)])
	w.origin_x_am = spawn[0]
	w.origin_y_am = spawn[1]
	return w


## The streaming block, first in every endless tick (spine 3.11): a pending respawn (step 0), the
## growth tick when the meter is due (step 1, S2), the floating origin (step 2), unload (step 3),
## load (step 4), sleep and wake (step 5), the food view (step 6), then the next size's prefetch (S2,
## BP-4). Load, unload and food always measure from the body, alive or dead; sleep and wake from
## every place the cell has (PoolSim._player_places), the same for steps 4 and 5.
func step(sim: PoolSim) -> void:
	if sim.respawn_pending:
		_respawn(sim)
	var g := sim.growth
	var grew := false
	if g != null and g.due:
		if not sim.dead and not sim.respawn_pending and size < max_size:
			grow(sim)
			grew = true
		else:
			g.due = false
	var p := sim.motion.position
	if p.length() > rebase_beyond_tm:
		rebase(sim, Vector2(roundf(p.x / rebase_step_tm) * rebase_step_tm, roundf(p.y / rebase_step_tm) * rebase_step_tm))
	var unloaded := _unload(sim)
	var view := _wake_view(sim)
	var loads := _loads
	if not grew:
		_load(sim, view, unloaded == 0)   # the growth tick's loads are its view set; the beat's begin the next tick
	_loaded_now = _loads != loads
	# Nothing loaded or unloaded (B-7: such a tick does one of them): the ahead work, the prefetch and
	# the frees may run.
	var quiet := not _loaded_now and unloaded == 0 and not grew
	var made := quiet and _look_ahead(sim)   # one chunk generation a tick: the prefetch waits
	_sleep_and_wake(sim, view)
	_food_view(sim)
	_morsel_pass(sim)
	var busy := made   # this tick generated a chunk ahead, or the prefetch worked: the sites' prep waits
	if g != null:
		busy = _prefetch(sim, quiet and not made) or busy
		if quiet and not made and not _retired.is_empty() and sim.tick >= g.beat_until:
			_retired.pop_back()
	if quiet and not busy:
		_prepare_ahead(sim)
	if quiet and not made and _quiet:
		for i in mini(RELEASE_PER_TICK, _let_go.size()):
			_let_go.pop_back()
	if not _loaded_now and not grew:
		_settle_heap()
	_quiet = true


## Whether this tick's step loaded a chunk (step 4, or a sleeper's wake): PoolSim's spawn pass then
## waits for the next tick (B-7).
func loaded_now() -> bool:
	return _loaded_now


## Makes the allocator settle, on this tick, the small blocks freed since the last tick that
## loaded nothing: a block of HEAP_SETTLE_BYTES is asked for and dropped. To glibc's malloc (Linux,
## CI) that is a large request, and a large request first merges every small block freed since the
## last one, a cost that grows with how many were freed. Without it a load tick's first large request
## (a chunk's near grid, 1 KB) paid for all the ticks before it: 230 to 280 us of B-7's tick 564,
## measured. Other allocators take it as a plain request and free. No state changes.
static func _settle_heap() -> void:
	var block := PackedByteArray()
	block.resize(HEAP_SETTLE_BYTES)


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
	_site_epoch += 1   # the bodies are the caller's: the hold bound measures again
	_quiet = false
	origin_x_am = x_am
	origin_y_am = y_am
	_rederive(sim)


## The size the world is expressed at (S2): every local tm is 1.6^(n - 1) am. Forgets what was kept
## for the old size: the next size's caches, the chunks generated ahead, and the ring, wake and hold
## bounds (they hold tm at the old size). The caller re-expresses the world (grow, set_size_teleport).
func set_size(n: int) -> void:
	size = n
	_tm_to_am = WorldConfig.tm_to_am(n)
	_clear_next()
	_ahead.clear()
	_load_bound = PackedFloat64Array()
	_unload_bound = PackedFloat64Array()
	_wake_bound.clear()
	_hold_bound.clear()
	_swum_from = Vector2.INF


## D-76: the world at size `n` round the cell's absolute place, by the teleport path: every remnant
## leaves ("unloaded"), the checkpoint keeps its place and heading at size n, the creature field takes
## size n's records, and the view set round the place loads. The caller places the cell
## (PoolSim.debug_set_size).
func set_size_teleport(sim: PoolSim, n: int) -> void:
	var a := sim.absolute_position_am()
	if sim.remnants != null:
		for r in sim.remnants.items.duplicate():
			sim.remnants.remove(r, "unloaded", sim.tick)
	set_size(n)
	checkpoint_am[3] = float(n)
	if sim.creatures != null:
		sim.creatures.set_size(n)
	teleport(sim, a[0], a[1])


## Moves the origin by `offset` (tm, whole chunks in each axis): every position the sim stores moves
## by -offset. Bodies (with their previous positions, so the view's interpolation stays continuous),
## actors, every creature's memories (sleepers too) and food items shift by it exactly; zones and
## colliders re-derive from their absolute values. Emits rebased {offset_tm, origin_am}.
func rebase(sim: PoolSim, offset: Vector2) -> void:
	_quiet = false
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
			RebaseShift.posts(mem, offset)   # S2: a two-post brain's posts and union leash (D-83)
	if sim.remnants != null:
		for r in sim.remnants.items:   # S2: a remnant is a body and an actor, with no brain
			RebaseShift.motion(r.motion, offset)
			r.actor.position -= offset
	if sim.kin != null:
		sim.kin.rebase(offset)
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
## every remnant and creature leaves ("unloaded"), all carrion goes (C-10), the origin moves to the absolute
## point exactly (rebased), and the view set round it loads at once, its food zones flagged to fill
## at once (C-9). The caller places the cell near the new origin.
func teleport(sim: PoolSim, x_am: float, y_am: float) -> void:
	for key in _keys.duplicate():
		_unload_chunk(sim, key)
	if sim.remnants != null:
		for r in sim.remnants.items.duplicate():
			sim.remnants.remove(r, "unloaded", sim.tick)
	if sim.creatures != null:
		for c in sim.creatures.creatures.duplicate():
			sim.creatures.remove(c, "unloaded", sim.tick, false)   # siteless ones too
	sim.carrion.drop_all()
	_ahead.clear()
	_clear_next()
	_forget_ahead_sites()
	_wake_bound.clear()
	_hold_bound.clear()
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
	_let_go.clear()   # behind the camera cut


## Step 0 (spine 3.11, D-10, D-11): the pending respawn. When the checkpoint's whole view set is
## loaded the cell comes back there as M1's respawn does, and the zones touching its new view fill at
## once. Otherwise the world moves home behind the camera cut: every chunk unloads (its creatures
## first), the rest of the creatures and every carrion item go, the origin becomes the checkpoint
## (rebased), its view set loads with every food zone filled, and the cell comes back at the origin.
func _respawn(sim: PoolSim) -> void:
	_clear_next()
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
		_add_keys_near_quad(found, quad, origin_x_am / _tm_to_am, origin_y_am / _tm_to_am)
	var out: Array[Vector2i] = []
	for key in found:
		out.append(key)
	out.sort_custom(_key_less)
	return out


## Adds to `found` every chunk (not in it yet) whose square comes within VIEW_SET_MARGIN_TM of `quad`
## (local tm corners) with the origin at (ox, oy) tm.
func _add_keys_near_quad(found: Dictionary, quad: PackedVector2Array, ox: float, oy: float) -> void:
	# The quad in chunk-relative float64 coordinates: local + origin, in tm.
	var qx := PackedFloat64Array()
	var qy := PackedFloat64Array()
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


## The chunks the growth tick at the cell's absolute point `a` (am) would load, view_set_keys(ZERO)
## at size + 1 with the origin at `a`, expression for expression: Vector2i -> true, in that order.
func _next_view_keys(a: PackedFloat64Array) -> Dictionary:
	var s1 := WorldConfig.tm_to_am(size + 1)
	var c := Vector2i(floori(a[0] / s1 / chunk_tm), floori(a[1] / s1 / chunk_tm))
	var found := {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			found[Vector2i(c.x + dx, c.y + dy)] = true
	var quad := ViewFootprint.corners(Vector2.ZERO, camera, float(camera.zoom_max), view_aspect)
	if not quad.is_empty():
		_add_keys_near_quad(found, quad, a[0] / s1, a[1] / s1)
	return found


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


## The endless state for snapshots and hashing (spine 3.12's "world" block). With growth (S2) it
## also holds the meter ("growth"), and each carrion item's radius and lifetime where they are not
## the field's ("carrion_radius", "carrion_lifetime"; D-66); without growth none of these keys exist
## (BP-20), so the block is S1's.
func snapshot(sim: PoolSim) -> Dictionary:
	var keys := []
	for key in _keys:
		keys.append([key.x, key.y])
	var zone_rngs := {}
	for id in _sorted(_zone_abs.keys()):
		var stream: RandomNumberGenerator = sim.region.streams.get(id, null)
		zone_rngs[id] = stream.state if stream != null else 0
	var out := {
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
	if not morsel_sites.is_empty():
		var entries := {}
		for id in _sorted(morsel_sites.keys()):
			entries[id] = {"food_id": morsel_sites[id].food_id, "due_tick": morsel_sites[id].due_tick}
		out["morsel_sites"] = entries
	if sim.growth != null:
		out["growth"] = sim.growth.snapshot()
		out["remnants"] = sim.remnants.snapshot()
		var radii := {}
		var lifetimes := {}
		var carrion := sim.carrion
		for item in carrion.items:
			if float(item.radius) != carrion.item_radius:
				radii[item.id] = item.radius
			if float(item.lifetime) != carrion.lifetime:
				lifetimes[item.id] = item.lifetime
		out["carrion_radius"] = _sorted_dict(radii)
		out["carrion_lifetime"] = _sorted_dict(lifetimes)
	return out


# --- step 3: unload ---

## Unloads every chunk whose nearest point lies beyond the unload ring from the body, unless an awake
## creature's reach touches it (its site's chunks, or the leash disc of a creature with no site; a
## token holder is awake, so it holds its ground too). Keys are visited in (y, x) order. Returns how
## many it unloaded.
func _unload(sim: PoolSim) -> int:
	var a := abs_of_local(sim.motion.position)   # nearest() for every key, the body's part once
	var x := a[0] / _tm_to_am
	var y := a[1] / _tm_to_am
	var ring := float(rings.unload)
	if _within_bound(_unload_bound, x, y, ring):
		return 0   # every loaded chunk is still within the ring
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
	return gone.size()


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
## leave the region, its colliders leave the arena, and chunk_unloaded tells the scene; with its
## `reason` when one is given (the growth tick's "growth", D-67), so S1's payload is unchanged. The
## chunk, the creatures, the records, the zones and the colliders wait in _let_go for the quiet ticks.
## The growth tick's _unload_all, which unloads every chunk (`whole`), has taken every zone out itself
## and grow takes another arena, so the chunk's zones and colliders are left to them, and it holds the
## chunks itself (_retired, freed after the beat): nothing goes to _let_go.
func _unload_chunk(sim: PoolSim, key: Vector2i, reason := "", whole := false) -> void:
	var ch: WorldChunk = _chunks[key]
	_site_epoch += 1
	_quiet = false
	if not whole:
		_let_go.append(ch)
	if _home_count != sites.size():
		_index_homes()
	var mine: Dictionary = _home_sites.get(key, {})
	_home_sites.erase(key)
	_home_count -= mine.size()
	if sim.creatures != null and not mine.is_empty():
		var leaving: Array[CreatureField.Creature] = []
		for c in sim.creatures.creatures:
			if mine.has(c.site_id):
				leaving.append(c)
		sim.creatures.remove_all(leaving, "unloaded", sim.tick)
		if not whole:
			_let_go.append(leaving)
		# Their queue entries leave in place, last first: the others keep their order.
		var queue := sim.creatures.queue
		for i in range(queue.size() - 1, -1, -1):
			if mine.has(queue[i].site):
				queue.remove_at(i)
	var records := []
	for id in mine:
		records.append(sites.get(id))
		sites.erase(id)
		_forget_role(id)
		if sim.creatures != null:
			sim.creatures.forget_prepared(id)   # made ahead but never spawned
	_unload_morsels(sim, ch)
	if not whole:
		for z in ch.zones:
			sim.plankton.drop_zone(z.id)
			records.append(_drop_zone(sim, z.id))
		_let_go.append(records)
		var colliders := []
		(sim.arena as ChunkArena).remove_chunk(key, colliders)
		_let_go.append(colliders)
	_chunks.erase(key)
	_keys.erase(key)
	_load_bound = PackedFloat64Array()   # a missing chunk now
	var event := {"type": "chunk_unloaded", "key": key}
	if not reason.is_empty():
		event["reason"] = reason
	_emit(sim, event)


## The growth tick's unload (step 3): every chunk unloads ("growth") and leaves the stream, the
## region, the food and the creature field as _unload_chunk one chunk at a time leaves them, but the
## zones' plankton goes in one pass (PlanktonField.drop_zones) and the zones leave in the region's own
## order (each removal finds its zone first). The arena is left as it is: another takes its place
## (step 5). The chunks and the plankton list are freed after the beat (_retired).
## The growth tick: every chunk unloads at once ("growth"), whole (the chunks and the plankton items go
## to _retired, nothing to _let_go), by one pass each: every zone leaves the food set, the region and
## the index (rebuilt by the next food view), every site leaves the table with its home, its role, its
## prepared creature and its queue entries (every entry is a loaded site's; the creatures are gone
## already, grow's steps 2 and 3), then chunk_unloaded per key in key order. The state after it is
## _unload_chunk's for every key in turn.
func _unload_all(sim: PoolSim) -> void:
	for key in _keys:
		_retired.append(_chunks[key])
	# The zones, as _drop_zone each in turn leaves them: the versions count each; the index, when it
	# was current, ends empty and current with an epoch per zone, else stays as it was. The tables go
	# to _retired whole, each in place of a fresh one, so that freeing their entries (the zones, the
	# streams, the items' index) falls on quiet ticks after the beat.
	var n := sim.region.zones.size()
	var current := _zones_indexed == _zones_version and _zone_refs.size() == n
	_retired.append(sim.plankton.drop_all_zones())
	sim.plankton.active_zones = {}
	_retired.append(sim.region.take_all_zones())
	_zones_version += n
	var tables := [_zone_abs, _zone_chunk, _fill, _fill_queue, _trimmed]
	if current and n > 0:
		_zone_ids.clear()
		_zone_c.clear()
		_zone_r.clear()
		tables.append(_zone_refs)
		var refs: Array[Dictionary] = []
		_zone_refs = refs
		_zone_ax.clear()
		_zone_ay.clear()
		_zones_indexed = _zones_version
		_index_epoch += n
	var queue_fresh: Array[String] = []
	_retired.append(tables)
	_zone_abs = {}
	_zone_chunk = {}
	_fill = {}
	_fill_queue = queue_fresh
	_trimmed = {}
	# The chunks, each in key order: its sites' creatures leave ("unloaded"), then chunk_unloaded; the
	# table, the roles, the homes, the prepared creatures and the queue entries go once at the end.
	var keys := _keys.duplicate()
	_site_epoch += keys.size()
	_quiet = false
	if _home_count != sites.size():
		_index_homes()
	var field := sim.creatures
	for key in keys:
		_unload_morsels(sim, _chunks[key])
		if field != null and not field.creatures.is_empty():
			var mine: Dictionary = _home_sites.get(key, {})
			var leaving: Array[CreatureField.Creature] = []
			for c in field.creatures:
				if mine.has(c.site_id):
					leaving.append(c)
			if not leaving.is_empty():
				field.remove_all(leaving, "unloaded", sim.tick)
		_emit(sim, {"type": "chunk_unloaded", "key": key, "reason": "growth"})
	if field != null:
		var queue := field.queue
		for i in range(queue.size() - 1, -1, -1):
			if sites.has(queue[i].site):
				queue.remove_at(i)
		field.forget_all_prepared()
	var keys_fresh: Array[Vector2i] = []
	_retired.append([sites, _site_role, _role_sites, _home_sites, _chunks, _keys])
	sites = {}
	_site_role = {}
	_role_sites = {}
	_home_sites = {}
	_home_count = 0
	_chunks = {}
	_keys = keys_fresh
	_load_bound = PackedFloat64Array()


## A zone of an unloading chunk leaves the food set, the region (with its stream) and the index; its
## record, for the caller to let go of later.
func _drop_zone(sim: PoolSim, id: String) -> Dictionary:
	sim.plankton.active_zones.erase(id)
	var was := sim.region.zone(id)
	sim.region.remove_zone(id)
	_zones_version += 1
	_unindex_zone(sim.region, was)
	_zone_abs.erase(id)
	_zone_chunk.erase(id)
	_fill.erase(id)
	_fill_queue.erase(id)
	sim.plankton.pending_fill.erase(id)
	_trimmed.erase(id)
	return was


# --- step 4: load ---

## Loads the nearest missing chunk within the load ring (ties by key), up to caps.loads_per_tick a
## tick (during a growth's beat, at least growth.beat_loads_per_tick: D-80), after the sleepers that
## wake this tick have their site chunks. With caps.chunks loaded, the nearest missing chunk of the
## view set loads instead (never refused), and chunk_waits counts each time the nearest missing chunk
## had to give way or wait (B-5: a backstop a swim should never need).
## With `ring` false (a tick that unloaded a chunk) only the wakers' chunks load: the load ring's
## wait for the next tick, so that no tick pays for an unload and a load (B-7; the load ring lies
## 22 tm beyond the view's, a tick's swim is under 0.2 tm).
func _load(sim: PoolSim, view_from: Dictionary, ring := true) -> void:
	# The sleepers step 5 will wake: their reach chunks load first, never refused and never counted.
	for c in _wakers(sim, view_from):
		for key in sites[c.site_id].chunks:
			if not _chunks.has(key):
				_load_chunk(sim, key)
	if not ring:
		return
	var body := sim.motion.position
	var view: Array[Vector2i] = []
	var per_tick := int(caps.loads_per_tick)
	if sim.growth != null and sim.tick < sim.growth.beat_until:
		per_tick = maxi(per_tick, int(sim.growth.cfg.beat_loads_per_tick))
	for i in per_tick:
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
## against the new colliders unless `settle` is false (the growth tick settles the cell itself, D-67),
## and chunk_loaded tells the scene. In the growth tick and its beat the chunk comes from the next
## size's cache when it is there (BP-4); in the growth tick its colliders may be in the arena already
## (the next size's arena, taken as it is), and the caps are applied once after its loads.
func _load_chunk(sim: PoolSim, key: Vector2i, settle := true) -> void:
	var ch: WorldChunk = null
	var made: Dictionary = {}
	var zone_recs: Array = []
	var site_recs: Dictionary = {}
	if _next_size == size and next_cache and (_growing or (sim.growth != null and sim.tick < sim.growth.beat_until)):
		ch = _next_chunks.get(key)
		_next_chunks.erase(key)
		if ch != null:
			made = _next_events.get(key, {})
			zone_recs = _next_zones.get(key, [])
			site_recs = _next_sites.get(key, {})
		_next_events.erase(key)
		_next_zones.erase(key)
		_next_sites.erase(key)
	if ch == null:
		ch = _generated(key)
	_loads += 1
	_site_epoch += 1
	_quiet = false
	# What a quiet tick made ahead for this chunk at this size (_prepare_parts); its local values hold
	# only in the frame they were made in.
	var k3 := Vector3i(key.x, key.y, size)
	var parts: Dictionary = _ahead_parts.get(k3, {})
	_ahead_parts.erase(k3)
	var have_parts := not parts.is_empty()
	var framed: bool = have_parts and not parts.mixed and parts.frame == _frame()
	var arena := sim.arena as ChunkArena
	if not (_growing and arena.has_chunk(key)):
		arena.add_chunk(key, parts.colliders if have_parts else _colliders(ch))
	var k := _tm_to_am   # local_of_tm written out: (x k - origin) / k, through float64
	var region := sim.region
	var prepared := zone_recs.size() == 2 and (zone_recs[0] as Array).size() == ch.zones.size()
	var i := 0
	for z in ch.zones:
		var fresh: bool
		if prepared:   # the record and the place as made ahead (what add_zone makes), its centre placed now
			fresh = region.add_zone_prepared(zone_recs[0][i], Vector2((float(z.x) * k - origin_x_am) / k, (float(z.y) * k - origin_y_am) / k))
			_zone_abs[z.id] = zone_recs[1][i]
		else:
			var at: Vector2 = parts.zone_local[i] if framed else Vector2((float(z.x) * k - origin_x_am) / k, (float(z.y) * k - origin_y_am) / k)
			fresh = region.add_zone(z.id, at, float(z.radius), float(z.capacity), float(z.growth_rate))
			_zone_abs[z.id] = parts.zone_abs[z.id] if have_parts else PackedFloat64Array([float(z.x), float(z.y)])
		i += 1
		var stream: RandomNumberGenerator = _next_streams.get(z.id)
		if stream == null:
			stream = parts.streams[z.id] if have_parts else _zone_stream(z.id)
		else:
			_next_streams.erase(z.id)
		region.streams[z.id] = stream
		_zone_chunk[z.id] = key
		_zones_version += 1
		if fresh:
			_index_added_zone(region)
	if sim.creatures != null:
		var ahead: Dictionary = _ahead_sites.get(Vector3i(key.x, key.y, size), {})
		var due: Array[Dictionary] = []   # their queue entries, in this order: _enqueue_retries places each as _enqueue would
		for s in ch.sites:
			if (s.sizes as Array).has(size):
				_note_home(s.id, key)
				var rec: Dictionary = ahead.get(s.id, {})
				var framed_rec := framed and not rec.is_empty()   # made in the frame in force (_prepare_parts)
				if rec.is_empty():
					rec = site_recs.get(s.id, {})   # made ahead for the next size (now this one)
				if not rec.is_empty() and is_same(rec.abs, s):
					if not framed_rec:
						_derive_site_local(rec, _tm_to_am, origin_x_am, origin_y_am)   # in the frame in force now
				else:
					rec = _site_record(s, key)
				sites[s.id] = rec
				_note_role(sim, s.id, str(s.species))
				due.append(s)
		sim.creatures._enqueue_retries(due, sim.tick)
		for m in ch.morsel_sites:
			_morsel_loaded[m.id] = {"abs": PackedFloat64Array([float(m.x), float(m.y)]), "species": str(m.species),
				"radius": float(m.radius), "energy": float(m.energy), "chunk": key}
			if not morsel_sites.has(m.id):
				morsel_sites[m.id] = {"food_id": "", "due_tick": sim.tick}
	_ahead_sites.erase(Vector3i(key.x, key.y, size))
	# The backstop: no body is left inside a new collider. The loads come from 56 tm out, but a debug
	# move, a waking creature or a test may put a body anywhere.
	if settle and sim.creatures != null:
		for c in sim.creatures.awake():
			sim.arena.settle(c.motion, c.phenotype.radius)
			c.actor.position = c.motion.position
	if settle and sim.motion != null and not sim.dead:
		sim.arena.settle(sim.motion, sim.phenotype.radius)
		sim.actor.position = sim.motion.position
	_insert_key(key)
	_chunks[key] = ch
	_unload_bound = PackedFloat64Array()   # a loaded chunk that may lie beyond the unload ring
	if not made.is_empty():
		_emit(sim, _placed_event(made, ch))
	else:
		_emit(sim, parts.event if framed else chunk_loaded_event(ch))
	if not _growing:
		_apply_caps(sim)


## A chunk's colliders as ChunkArena.add_chunk takes them ({id, x, y, r}: absolute tm at its size).
static func _colliders(ch: WorldChunk) -> Array[Dictionary]:
	var colliders: Array[Dictionary] = []
	for s in ch.shells:
		colliders.append({"id": s.id, "x": float(s.x), "y": float(s.y), "r": float(s.r)})
	return colliders


## Zone `id`'s plankton stream, seeded: a pure function of the world seed, the generator version and
## the id.
func _zone_stream(id: String) -> RandomNumberGenerator:
	var stream := RandomNumberGenerator.new()
	stream.seed = WorldHash.hash_ints(PackedInt64Array([world_seed, gen_version, WorldHash.str32(id), _str_plankton]))
	return stream


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
	var binding := PackedInt64Array()
	if g != null:
		binding = PackedInt64Array([_id_of(g.content), _id_of(g.species), g.world_seed, g.gen_version])
	if is_same(_ahead_gen, g) and binding == _ahead_binding:
		return
	_ahead.clear()
	_forget_ahead_sites()
	_ahead_gen = g
	_ahead_binding = binding


static func _id_of(o: Object) -> int:
	return 0 if o == null else o.get_instance_id()


## On a tick that loads nothing: generates the missing chunk nearest the point AHEAD_LEAD_S ahead of
## the cell along its velocity, within the load ring plus AHEAD_MARGIN_TM of it (least (distance, y,
## x)), and keeps it; with AHEAD_KEEP kept, in place of the kept chunk farthest from that point when
## it is nearer. A look that generates nothing waits AHEAD_REFRESH_TICKS ticks, or until a load
## takes a kept chunk, before the next. True when it generated one.
func _look_ahead(sim: PoolSim) -> bool:
	if sim.tick < _ahead_tick:
		return false
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
		return false
	if _ahead.size() >= AHEAD_KEEP:
		var far: Variant = null
		var far_d := -1.0
		for k in _ahead:
			var d := _square_distance(Vector2i(k.x, k.y), x, y)
			if d > far_d:
				far = k
				far_d = d
		if far_d <= best_d:
			return false
		_ahead.erase(far)
		_forget_ahead_sites(far)
	var made := Vector3i(best.x, best.y, size)
	_ahead[made] = gen.chunk(size, best.x, best.y)
	_prepare_todo.append([made, -1])   # -1: its parts first (_prepare_parts)
	_ahead_tick = 0   # look again on the next quiet tick, until the keep is full or nothing is nearer
	return true


## On a quiet tick that generated nothing ahead: the next PREPARE_PER_TICK live sites of the chunks
## generated ahead get their record (in the frame in force now; the load derives it again) and their
## next creature (CreatureField.prepare_site), chunk by chunk in the order they were generated.
## Nothing here changes the world: a load or a spawn that finds nothing made, or something made for
## other inputs, makes it then. True when it made any.
func _prepare_ahead(sim: PoolSim) -> bool:
	if sim.creatures == null:
		return false   # no site table to load records into
	var left := PREPARE_PER_TICK
	while left > 0 and not _prepare_todo.is_empty():
		var todo: Array = _prepare_todo[0]
		var k: Vector3i = todo[0]
		var ch: WorldChunk = _ahead.get(k)
		var i: int = todo[1]
		if ch == null or i >= ch.sites.size():
			_prepare_todo.pop_front()   # gone through, loaded or forgotten
			continue
		todo[1] = i + 1
		if i < 0:
			_prepare_parts(k, ch)
			left -= PREPARE_PER_TICK   # the parts are a tick's share
			continue
		var s: Dictionary = ch.sites[i]
		if not (s.sizes as Array).has(k.z):
			continue
		if not _ahead_sites.has(k):
			_ahead_sites[k] = {}
		var parts: Dictionary = _ahead_parts.get(k, {})
		if not parts.is_empty() and parts.frame != _frame():
			parts.mixed = true
		var rec := _site_record(s, Vector2i(k.x, k.y))
		_ahead_sites[k][s.id] = rec
		sim.creatures.prepare_site(rec)
		left -= 1
	return left < PREPARE_PER_TICK


## A chunk's colliders, its zones' plankton streams and absolute centres, and (in the frame in force)
## its zones' local centres and its chunk_loaded payload, as _load_chunk would make them.
func _prepare_parts(k: Vector3i, ch: WorldChunk) -> void:
	var streams := {}
	var zone_abs := {}
	var zone_local: Array[Vector2] = []
	for z in ch.zones:
		streams[z.id] = _zone_stream(z.id)
		zone_abs[z.id] = PackedFloat64Array([float(z.x), float(z.y)])
		zone_local.append(local_of_tm(float(z.x), float(z.y)))
	_ahead_parts[k] = {"colliders": _colliders(ch), "streams": streams, "zone_abs": zone_abs, "zone_local": zone_local,
		"event": chunk_loaded_event(ch), "frame": _frame(), "mixed": false}


## The frame local values are made in: the origin (am) and the scale (am a tm).
func _frame() -> PackedFloat64Array:
	return PackedFloat64Array([origin_x_am, origin_y_am, _tm_to_am])


## Forgets what _prepare_ahead made for the chunk generated ahead at `key` (every one when null): its
## parts and records here and its sites' creatures in the field.
func _forget_ahead_sites(key: Variant = null) -> void:
	var field: CreatureField = _field.get_ref() if _field != null else null
	for k in ([key] if key != null else _ahead_sites.keys()):
		if field != null:
			for id in _ahead_sites.get(k, {}):
				field.forget_prepared(id)
		_ahead_sites.erase(k)
	if key == null:
		_ahead_parts.clear()
		_prepare_todo.clear()
	else:
		_ahead_parts.erase(key)


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
		_hold_bound.clear()
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
		if d > sleep_r and _calm(c) and not _in_view(c.motion.position, c.phenotype.radius, d, view_from) \
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
	var bounded := _swum_from.is_finite()   # _wakers' bound runs: one place, and _swum is its path
	if _hold_bound.size() > sim.creatures.creatures.size() + 64:
		_hold_bound.clear()   # mostly creatures gone since
	var n := sites.size()
	for c in sim.creatures.awake().duplicate():
		if c.brain == null:
			continue
		var b: Variant = _hold_bound.get(c)
		if b != null and _swum < b[2] and b[0] == _site_epoch and b[1] == n and b[3] == hold:
			continue
		var center: Vector2 = sites[c.site_id].reach.center if sites.has(c.site_id) else CreatureBrain.leash_disc(c.brain).center
		var d := _wake_distance(center, view_from)
		if d > hold:
			sim.creatures.let_go(c, sim.tick)
		elif bounded:
			_hold_bound[c] = [_site_epoch, n, _swum + hold - d - WAKE_SLACK_TM, hold]


## Whether the creature's (state/phase) is in CALM (the brain's own test, D-62; a pass asks it of every
## awake creature).
static func _calm(c: CreatureField.Creature) -> bool:
	return CreatureBrain.is_calm(c.brain)


## {creature id: think slot} of the awake creatures, sorted by id.
func _slots(sim: PoolSim) -> Dictionary:
	var out := {}
	if sim.creatures != null:
		for c in sim.creatures.awake():
			out[c.id] = c.think_slot
	return _sorted_dict(out)


# --- growth (S2) ---

## The cell's settle point at the next size (BP-4), in the current frame, or Vector2.INF when it is
## wedged there. A pure function of the cell's absolute point A, the size and the cell's radius: the
## spiral (PoolSim.clear_point_on) at size + 1, round A, in an arena of the 3 x 3 new-size chunks round
## A's new-size chunk with its origin at A, out to wedge_rings rings (2 tm). The growth tick's settle
## lands on the same point bit for bit (grow step 6). Below the build top only.
func next_size_clear_point(sim: PoolSim) -> Vector2:
	var a := abs_of_local(sim.motion.position)
	var q := _next_point(a, sim.phenotype.radius)
	if not q.is_finite():
		return Vector2.INF
	var s1 := WorldConfig.tm_to_am(size + 1)
	return local_of_abs(a[0] + float(q.x) * s1, a[1] + float(q.y) * s1)


## next_size_clear_point's spiral, in the next size's frame (origin `a`, tm at size + 1). When A's
## new-size chunk changes the arena gets the chunks of its 3 x 3 it lacks; it is moved to A whenever
## A changes (a chunk added since was placed at the same origin, by the same expression).
func _next_point(a: PackedFloat64Array, r: float) -> Vector2:
	if _next_size != size + 1 or not next_cache:
		_clear_next()
		_next_size = size + 1
	var s1 := WorldConfig.tm_to_am(size + 1)
	var key := Vector2i(floori(a[0] / s1 / chunk_tm), floori(a[1] / s1 / chunk_tm))
	if _next_arena == null:
		_next_arena = ChunkArena.create_endless(chunk_tm)
		_next_held = {}
		_next_from = PackedFloat64Array()
	if key != _next_key:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k := Vector2i(key.x + dx, key.y + dy)
				if not _next_held.has(k):
					_next_arena.add_chunk(k, _colliders(_next_chunk(k)))
					_next_held[k] = true
		_next_key = key
	if _next_from != a:
		_next_arena.set_origin(a[0] / s1, a[1] / s1)   # the expression _rederive's set_origin makes at A
		_next_from = a.duplicate()
	return PoolSim.clear_point_on(_next_arena, Vector2.ZERO, r, wedge_rings)


## The next size's chunk `key`: from the cache, else generated now and kept (a miss never changes a
## result: WorldGen.chunk is pure).
func _next_chunk(key: Vector2i) -> WorldChunk:
	var ch: WorldChunk = _next_chunks.get(key)
	if ch == null:
		ch = gen.chunk(size + 1, key.x, key.y)
		if next_cache:
			_next_chunks[key] = ch
	return ch


func _clear_next() -> void:
	_next_chunks = {}
	_next_streams = {}
	_next_events = {}
	_next_zones = {}
	_next_sites = {}
	_next_arena = null
	_next_held = {}
	_next_key = Vector2i.MAX
	_next_from = PackedFloat64Array()
	_next_want = {}
	_next_want_c = Vector2i.MAX
	_next_want_head = Vector2i.MAX
	_next_want_tick = 0
	_next_size = 0


## The last streaming step (BP-4): while the ring is nearly full (meter >= prefetch_share x ring) below
## the build top and the cell is alive, at most growth.prefetch_per_tick missing chunks of the 5 x 5
## new-size keys round the cell's new-size chunk are generated and kept, nearest first by the distance
## from the cell to the key's centre (ties by y, then x); keys that left the 5 x 5 are dropped. Any
## other tick forgets the cache, except the growth tick and its beat, whose loads take from it.
## Only a `quiet` tick (step: none loaded, none generated ahead) generates, so a chunk generation does
## not land on a tick that already made one; a quiet tick with nothing to generate does the arena's
## chore instead, or with no chore prepares a cached chunk's load (_next_events). The caches never
## change a result, so neither does which tick fills them. True when it generated, did the chore or
## prepared a load (the sites' prep then waits for the next quiet tick).
func _prefetch(sim: PoolSim, quiet := true) -> bool:
	var g := sim.growth
	if sim.tick < g.beat_until:
		return false
	if not next_cache or sim.dead or sim.respawn_pending or size >= max_size or g.meter < g.prefetch_share * g.ring(size):
		if _next_size != 0:
			_clear_next()
		return false
	if _next_size != size + 1:
		_clear_next()
		_next_size = size + 1
	var s1 := WorldConfig.tm_to_am(size + 1)
	var a := abs_of_local(sim.motion.position)
	var x := a[0] / s1
	var y := a[1] / s1
	var c := Vector2i(floori(x / chunk_tm), floori(y / chunk_tm))
	for key: Vector2i in _next_chunks.keys():
		if absi(key.x - c.x) > 2 or absi(key.y - c.y) > 2:
			if _next_events.has(key):
				_next_events.erase(key)
				_next_zones.erase(key)
				_next_sites.erase(key)
				for z in _next_chunks[key].zones:
					_next_streams.erase(z.id)
			_next_chunks.erase(key)
	if not quiet:
		return false
	var made := 0
	for i in g.prefetch_per_tick:
		var best := Vector2i.MAX
		var best_d := INF
		for ky in range(c.y - 2, c.y + 3):   # (y, x) order: the first of equal distances is the least key
			for kx in range(c.x - 2, c.x + 3):
				var key := Vector2i(kx, ky)
				if _next_chunks.has(key):
					continue
				var dx := (kx + 0.5) * chunk_tm - x
				var dy := (ky + 0.5) * chunk_tm - y
				var d := dx * dx + dy * dy
				if d < best_d:
					best = key
					best_d = d
		if best == Vector2i.MAX:
			break
		_next_chunks[best] = gen.chunk(size + 1, best.x, best.y)
		made += 1
	return made > 0 or _arena_chore(sim) or _prepare_next()


## One quiet tick's preparing (_next_events, _next_zones, _next_sites): the first cached chunk, in the
## order they were made (nearest first), whose load is not prepared yet. True when it prepared one.
## A chunk with a zone add_zone would refuse has no zone records prepared: its load makes them.
func _prepare_next() -> bool:
	if _next_events.size() >= _next_chunks.size():
		return false
	for key: Vector2i in _next_chunks:
		if not _next_events.has(key):
			var ch: WorldChunk = _next_chunks[key]
			var records: Array[Dictionary] = []
			var places: Array[PackedFloat64Array] = []
			var sound := true
			for z in ch.zones:
				_next_streams[z.id] = _zone_stream(z.id)
				var radius := float(z.radius)
				var capacity := float(z.capacity)
				var rate := float(z.growth_rate)
				for value in [radius, capacity, rate]:
					if not (is_finite(value) and value > 0.0):
						sound = false
				records.append({"id": z.id, "center": Vector2.ZERO, "radius": radius, "capacity": capacity,
					"growth_rate": rate, "amount": capacity})
				places.append(PackedFloat64Array([float(z.x), float(z.y)]))
			if sound:
				_next_zones[key] = [records, places]
			var recs := {}
			for s in ch.sites:
				if (s.sizes as Array).has(ch.size):
					recs[s.id] = _site_record_abs(s, key)
			_next_sites[key] = recs
			_next_events[key] = _event_of(ch, false)
			return true
	return false


## One quiet tick's care of the next size's arena (BP-4), once it is in use. The chunks it wants held
## (_next_want): the view set the growth tick would load at the cell's point now (_next_view_keys), and
## the 3 x 3 round the new-size chunk the cell heads for (its point NEXT_LEAD_S along its velocity);
## taken again when the cell's or the heading's new-size chunk changes, or NEXT_WANT_TICKS ticks on.
## The first wanted chunk the arena lacks and the prefetch holds goes in; with none, the first held
## chunk in neither the wanted set nor _next_key's 3 x 3 comes out. True when it did either.
func _arena_chore(sim: PoolSim) -> bool:
	if _next_arena == null or _next_key == Vector2i.MAX:
		return false
	var s1 := WorldConfig.tm_to_am(size + 1)
	var a := abs_of_local(sim.motion.position)
	var c := Vector2i(floori(a[0] / s1 / chunk_tm), floori(a[1] / s1 / chunk_tm))
	var h := abs_of_local(sim.motion.position + sim.motion.velocity * NEXT_LEAD_S)
	var head := Vector2i(floori(h[0] / s1 / chunk_tm), floori(h[1] / s1 / chunk_tm))
	if c != _next_want_c or head != _next_want_head or sim.tick >= _next_want_tick:
		_next_want = _next_view_keys(a)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_next_want[Vector2i(head.x + dx, head.y + dy)] = true
		_next_want_c = c
		_next_want_head = head
		_next_want_tick = sim.tick + NEXT_WANT_TICKS
	for k: Vector2i in _next_want:
		if not _next_held.has(k) and _next_chunks.has(k):
			_next_arena.add_chunk(k, _colliders(_next_chunks[k]))
			_next_held[k] = true
			return true
	for k: Vector2i in _next_held:
		if not _next_want.has(k) and maxi(absi(k.x - _next_key.x), absi(k.y - _next_key.y)) > 1:
			_next_arena.remove_chunk(k)
			_next_held.erase(k)
			return true
	return false


## The growth tick (streaming step 1; plan B.4, s2-sim 3.7 as BP-4 changes it), when the meter is due
## below the build top with the cell alive. In order:
## 1. Record the cell's absolute point A and previous point, and the next size's point q round A;
##    emit growth_began.
## 2. Every awake body, then every remnant, in order, converts by its ladder role at n + 1 (D-68, D-87):
##    rival or prey to a remnant (the nearest remnants.cap of them by (distance, id); the rest to haze,
##    remnant_overflow once, D-78), morsel to a carrion morsel, anything else (and a scripted body) to
##    haze; each leaves its list and emits creature_converted after its morsel's carrion_spawned.
## 3. Sleepers leave ("growth"); carrion within the food ring shrinks by 1.6 in radius and energy
##    (points from the energy as a spawn would), carrion beyond it expires ("growth"), the morsels just
##    made are kept as they are (D-66); plankton becomes haze; every chunk unloads ("growth"); caps.
## 4. Size n + 1 with the origin exactly A: the cell at (0, 0), its previous point and the remnants and
##    carrion again from their absolute values, its velocity / 1.6; the field takes size n + 1.
## 5. The view set round A loads (from the next size's cache) without settling; the food zones fill
##    nearest first, FILL_ZONES_PER_TICK on this tick and on each tick after it until all have (C-V15
##    as amended: each item is born on the tick that filled its zone). The beat's further loads begin
##    the next tick (D-80 as amended), and this tick does none of a quiet tick's work.
## 6. The cell settles by the spiral on the new arena: when q was finite this is q bit for bit
##    (push_error otherwise; test_growth_tick fails on it). The remnants settle.
## 7. The checkpoint is the settled point at n + 1; full energy; the shelter; the meter starts again;
##    the beat; the contact is forgotten.
## 8. Emit grew.
## Every event before step 4 is in the old frame (D-65); chunk_loaded and grew (but its haze) in the
## new one. No rebased is emitted.
func grow(sim: PoolSim) -> void:
	var g := sim.growth
	var n := size
	var f := WorldConfig.GROWTH_FACTOR
	var cell := sim.motion
	var r_cell := sim.phenotype.radius
	grew_tick = sim.tick
	if sim.kin != null:
		# The kin goes before the sea is rescaled (S4.3): it came for the smaller cell.
		sim.kin.leave(sim, "grew")
	# 1. Record.
	var a := abs_of_local(cell.position)
	var ap := abs_of_local(cell.prev_position)
	var q := _next_point(a, r_cell)
	_emit(sim, {"type": "growth_began", "from": n, "to": n + 1, "center_old": cell.position,
		"center_am": [a[0], a[1]], "factor": f})
	# 2. The awake bodies, then the remnants.
	var bodies: Array[CreatureField.Creature] = []
	if sim.creatures != null:
		bodies.append_array(sim.creatures.awake())
	bodies.append_array(sim.remnants.items)
	var fates := {}
	var recs := {}
	var kept: Array[CreatureField.Creature] = []
	for c in bodies:
		var fate := "haze"
		if not c.scripted and sim.species != null and sim.species.has_species(c.species_id):
			var rec := sim.species.at_size(c.species_id, n + 1, sim.catalog)
			var role := str(rec.get("ladder_role", ""))
			if role == "rival" or role == "prey":
				fate = "remnant"
				kept.append(c)
			elif role == "morsel":
				fate = "morsel"
			recs[c] = rec
		fates[c] = fate
	if kept.size() > sim.remnants.cap:
		var at := cell.position
		kept.sort_custom(func(x: CreatureField.Creature, y: CreatureField.Creature) -> bool:
			var dx := at.distance_to(x.motion.position)
			var dy := at.distance_to(y.motion.position)
			return dx < dy or (dx == dy and x.id < y.id))
		for i in range(sim.remnants.cap, kept.size()):
			fates[kept[i]] = "haze"
		counters.remnant_overflow += 1
	var remnant_ids := []
	var morsel_ids := []
	var body_haze := []
	var fresh := {}
	var moved := {}   # remnant -> [x, y, previous x, previous y] (am)
	var cfg: Dictionary = g.cfg.remnants
	for c in bodies:
		var fate: String = fates[c]
		var r_new := float(recs[c].phenotype.radius) if recs.has(c) else c.phenotype.radius / f
		var at := c.motion.position
		var food_id := ""
		if fate == "remnant":
			var rem := sim.remnants.add_from(c, recs[c], sim.tick)
			var pa := abs_of_local(rem.motion.position)
			var pp := abs_of_local(rem.motion.prev_position)
			moved[rem] = PackedFloat64Array([pa[0], pa[1], pp[0], pp[1]])
			remnant_ids.append(c.id)
		elif fate == "morsel":
			var item := sim.carrion.spawn(at, "morsel", sim.carrion.energy * r_new / Relationships.PLAYER_RADIUS, -1,
				minf(r_new, float(cfg.morsel_max_radius_tm)), float(cfg.morsel_rot_s))
			food_id = str(item.get("id", ""))
			fresh[food_id] = true
			morsel_ids.append(food_id)
		else:
			body_haze.append({"kind": "creature", "look": c.species_id, "position": at})
		if c is RemnantField.Remnant:
			if fate != "remnant":
				sim.remnants.items.erase(c)
		else:
			sim.creatures.take_for_growth(c)
		_emit(sim, {"type": "creature_converted", "id": c.id, "species": c.species_id, "to": fate, "position": at,
			"radius": r_new, "food_id": food_id})
	# 3. The rest: sleepers, carrion, plankton, chunks.
	if sim.creatures != null:
		for c in sim.creatures.creatures.duplicate():
			sim.creatures.remove(c, "growth", sim.tick, false)
	var carrion := sim.carrion
	var ring_sq := float(rings.food) * float(rings.food)
	var items: Array[Dictionary] = []
	var item_abs := PackedFloat64Array()
	var gone: Array[Dictionary] = []
	for item in carrion.items:
		if fresh.has(item.id):
			pass
		elif cell.position.distance_squared_to(item.position) <= ring_sq:
			item.radius = float(item.radius) / f
			item.energy = float(item.energy) / f
			item.points = floori(float(item.energy) / carrion.energy * carrion.points + 1e-6)
		else:
			gone.append(item)
			continue
		var ia := abs_of_local(item.position)
		item_abs.append(ia[0])
		item_abs.append(ia[1])
		items.append(item)
	carrion.items = items
	for item in gone:
		_emit(sim, {"type": "carrion_expired", "food_id": item.id, "position": item.position, "reason": "growth"})
	var haze := []
	var plant := str(content.config.ladder.food_looks[n - 1].plant)
	for item in sim.plankton.items:
		haze.append({"kind": "plant", "look": plant, "position": item.position})
	haze.append_array(body_haze)
	_unload_all(sim)
	var old_arena := sim.arena as ChunkArena
	_retired.append(old_arena)
	sim.arena = _arena_after(old_arena, ChunkArena.create_endless(chunk_tm))
	recompute_caps(sim)
	# 4. Size and origin: the next size's cache, its prepared loads and its arena stay for step 5 and
	# the beat.
	var next := _next_chunks
	var next_size := _next_size
	var streams := _next_streams
	var events := _next_events
	var zones := _next_zones
	var next_sites := _next_sites
	var next_arena := _next_arena if next_cache and _next_size == n + 1 and _next_from == a else null
	set_size(n + 1)
	_ahead.clear()   # generated ahead at size n, with its sites' records and creatures
	_forget_ahead_sites()
	_ahead_tick = 0
	_next_chunks = next
	_next_size = next_size
	_next_streams = streams
	_next_events = events
	_next_zones = zones
	_next_sites = next_sites
	origin_x_am = a[0]
	origin_y_am = a[1]
	_rederive(sim)
	cell.position = Vector2.ZERO
	cell.prev_position = local_of_abs(ap[0], ap[1])
	cell.velocity /= f
	sim.actor.position = cell.position
	for rem: RemnantField.Remnant in moved:
		var m: PackedFloat64Array = moved[rem]
		rem.motion.position = local_of_abs(m[0], m[1])
		rem.motion.prev_position = local_of_abs(m[2], m[3])
		rem.actor.position = rem.motion.position
	for i in items.size():
		items[i].position = local_of_abs(item_abs[2 * i], item_abs[2 * i + 1])
	if sim.creatures != null:
		sim.creatures.set_size(n + 1)
	# 5. Load the view set, unsettled. The next size's arena (BP-4) holds the 3 x 3 round A at size
	# n + 1 (and, after the chore's quiet ticks, the view set round A), at origin A by the expression
	# _rederive's set_origin uses, so it is taken as the arena once it gives up its chunks outside the
	# view set: equal colliders and an equal origin are an equal arena (its arrays in canonical order,
	# its near grids counts), whichever order they came in. The loads add only the chunks it lacks.
	var view := view_set_keys(Vector2.ZERO)
	if next_arena != null:
		for key in next_arena.chunk_keys():
			if not view.has(key):
				next_arena.remove_chunk(key)
		sim.arena = _arena_after(old_arena, next_arena)
	_growing = true
	for key in view:
		_load_chunk(sim, key, false)
	_growing = false
	_apply_caps(sim)
	_fill_spread = true
	# 6. Settle.
	var p := PoolSim.clear_point_on(sim.arena, Vector2.ZERO, r_cell)
	if q.is_finite() and p != q:
		push_error("WorldStream.grow: the settle point %s is not the next size's point %s (BP-4)" % [p, q])
	cell.position = p
	sim.actor.position = p
	for rem in sim.remnants.items:
		sim.arena.settle(rem.motion, rem.phenotype.radius)
		rem.actor.position = rem.motion.position
	# 7. Reset.
	var cp := abs_of_local(p)
	checkpoint_am = PackedFloat64Array([cp[0], cp[1], cell.heading, float(n + 1)])
	sim.refill_energy()
	sim.grace_until = sim.tick + CreatureBrain.ticks(g.cfg.shelter_s)
	g.reset_for_size(n + 1)
	g.beat_until = sim.tick + CreatureBrain.ticks(g.cfg.beat_s)
	sim._contact.clear()
	# 8. Emit.
	_emit(sim, {"type": "grew", "from": n, "to": n + 1, "center": Vector2.ZERO, "settled_from": Vector2.ZERO,
		"settled_to": p, "remnants": remnant_ids, "morsels": morsel_ids, "haze": haze,
		"checkpoint_am": [cp[0], cp[1], cell.heading, n + 1]})


## `arena` as the growth tick's new arena in place of `old`: its epoch past every epoch `old` had (so
## no RouteKeep picked on `old` is taken for one of its own), `old`'s grid switch and fallback count.
static func _arena_after(old: ChunkArena, arena: ChunkArena) -> ChunkArena:
	arena.epoch = maxi(arena.epoch, old.epoch) + 1
	arena.rock_grid = old.rock_grid
	arena.settle_fallbacks = old.settle_fallbacks
	return arena


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
	# The roles (BP-10): every role already registered (a size drop leaves it at 0) and those of the
	# species drawn at this size or below, so at size 1 the niches are S1's.
	var per_role := {}
	for role in sim.region.niches:
		per_role[role] = 0
	for id in sim.species.species_ids():
		if sim.species.entry_size(id) <= size:
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
## reach x, y] (tm; the territory's NaN when it has none) that a rebase derives them from again. A
## two-post site (S2) also gets local "posts" [{home, heading, territory: {} or {center, radius}}] x 2,
## as CreatureBrain.set_posts takes them, from "abs_posts" [home x, y, territory x, y] per post.
func _site_record(s: Dictionary, key: Vector2i) -> Dictionary:
	var rec := _site_record_abs(s, key)
	_derive_site_local(rec, _tm_to_am, origin_x_am, origin_y_am)
	return rec


## _site_record but its local places (home, the territory and reach centres, the posts'), which
## _derive_site_local sets in the frame in force: Vector2.ZERO until then.
static func _site_record_abs(s: Dictionary, key: Vector2i) -> Dictionary:
	var chunks: Array[Vector2i] = []
	chunks.assign(s.chunks)
	var t: Dictionary = s.territory
	var r: Dictionary = s.reach
	var rec := {"id": s.id, "species": s.species, "heading": float(s.heading), "chunks": chunks, "home_chunk": key, "abs": s,
		"abs_tm": PackedFloat64Array([float(s.x), float(s.y), NAN if t.is_empty() else float(t.x),
			NAN if t.is_empty() else float(t.y), float(r.x), float(r.y)]),
		"territory": {} if t.is_empty() else {"center": Vector2.ZERO, "radius": float(t.radius)},
		"reach": {"center": Vector2.ZERO, "radius": float(r.radius)}}
	if s.has("posts"):
		var posts := []
		var abs_posts := PackedFloat64Array()
		for post: Dictionary in s.posts:
			var pt: Dictionary = post.territory
			abs_posts.append_array([float(post.x), float(post.y), NAN if pt.is_empty() else float(pt.x),
				NAN if pt.is_empty() else float(pt.y)])
			posts.append({"home": Vector2.ZERO, "heading": float(post.heading),
				"territory": {} if pt.is_empty() else {"center": Vector2.ZERO, "radius": float(pt.radius)}})
		rec["posts"] = posts
		rec["abs_posts"] = abs_posts
	return rec


## A site record's local home, territory centre and reach centre (and its posts'), again from
## "abs_tm" ("abs_posts"), in place. Each is local_of_tm's own float64 expression written out (so the
## same float32 result): a rebase does this for every loaded site, and a rebase tick is timed (G17).
static func _derive_site_local(rec: Dictionary, k: float, ox: float, oy: float) -> void:
	var a: PackedFloat64Array = rec.abs_tm
	rec.home = Vector2((a[0] * k - ox) / k, (a[1] * k - oy) / k)
	if not rec.territory.is_empty():
		rec.territory.center = Vector2((a[2] * k - ox) / k, (a[3] * k - oy) / k)
	rec.reach.center = Vector2((a[4] * k - ox) / k, (a[5] * k - oy) / k)
	if rec.has("posts"):
		_derive_posts(rec, k, ox, oy)


## The posts' local homes and territory centres from "abs_posts".
static func _derive_posts(rec: Dictionary, k: float, ox: float, oy: float) -> void:
	var b: PackedFloat64Array = rec.abs_posts
	var i := 0
	for post: Dictionary in rec.posts:
		post.home = Vector2((b[i] * k - ox) / k, (b[i + 1] * k - oy) / k)
		var pt: Dictionary = post.territory
		if not pt.is_empty():
			pt.center = Vector2((b[i + 2] * k - ox) / k, (b[i + 3] * k - oy) / k)
		i += 4


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
		if rec.has("posts"):
			_derive_posts(rec, k, ox, oy)
	return indexed and moved


## chunk_loaded's payload (spine 3.12, S2 build plan 7.4), in the frame in force now: the one builder
## (BP-17; the scene's WorldSpace.chunk_loaded_event returns this). Places carry `scale`, bu_to_tm at
## the chunk's size (BP-16), and `sites` lists every site live at that size with its posts
## [{position, heading}] (a one-post site: one, at its home; C-V10).
func chunk_loaded_event(ch: WorldChunk) -> Dictionary:
	return _event_of(ch, true)


## chunk_loaded_event's payload, with every position (and zone centre) at Vector2.ZERO unless `placed`:
## the part that does not depend on the frame (_placed_event places the rest).
func _event_of(ch: WorldChunk, placed: bool) -> Dictionary:
	var at := Vector2.ZERO
	var k := _tm_to_am   # local_of_tm written out: (x k - origin) / k, through float64
	var ox := origin_x_am
	var oy := origin_y_am
	var shells := []
	for s in ch.shells:
		if placed:
			at = Vector2((float(s.x) * k - ox) / k, (float(s.y) * k - oy) / k)
		shells.append({"id": s.id, "position": at, "radius": float(s.r), "kind": s.kind,
			"asset": s.asset, "yaw_deg": s.yaw_deg, "scale": s.scale, "tint": s.tint})
	var zones := []
	for z in ch.zones:
		if placed:
			at = Vector2((float(z.x) * k - ox) / k, (float(z.y) * k - oy) / k)
		zones.append({"id": z.id, "center": at, "radius": float(z.radius), "region": z.region})
	var anchors := []
	for a in ch.anchors:
		if placed:
			at = Vector2((float(a.x) * k - ox) / k, (float(a.y) * k - oy) / k)
		anchors.append({"id": a.id, "position": at, "model": a.model, "dressing": a.dressing})
	var places := []
	for p in ch.places:
		if placed:
			at = Vector2((float(p.x) * k - ox) / k, (float(p.y) * k - oy) / k)
		places.append({"id": p.id, "kind": p.kind, "position": at, "yaw_deg": float(p.yaw_deg),
			"mirror": bool(p.mirror), "scale": WorldConfig.bu_to_tm(ch.size)})
	var site_list := []
	for s in ch.sites:
		if not (s.sizes as Array).has(ch.size):
			continue
		var posts := []
		if s.has("posts"):
			for post: Dictionary in s.posts:
				if placed:
					at = Vector2((float(post.x) * k - ox) / k, (float(post.y) * k - oy) / k)
				posts.append({"position": at, "heading": float(post.heading)})
		else:
			if placed:
				at = Vector2((float(s.x) * k - ox) / k, (float(s.y) * k - oy) / k)
			posts.append({"position": at, "heading": float(s.heading)})
		site_list.append({"id": s.id, "species": s.species, "posts": posts})
	return {"type": "chunk_loaded", "key": ch.key, "shells": shells, "zones": zones, "anchors": anchors, "places": places,
		"sites": site_list}


## `event`, _event_of(ch, false), with its positions placed in the frame in force now: then it equals
## chunk_loaded_event(ch).
func _placed_event(event: Dictionary, ch: WorldChunk) -> Dictionary:
	var k := _tm_to_am   # local_of_tm written out, as in _event_of
	var ox := origin_x_am
	var oy := origin_y_am
	var out: Array = event.shells
	var i := 0
	for s in ch.shells:
		out[i].position = Vector2((float(s.x) * k - ox) / k, (float(s.y) * k - oy) / k)
		i += 1
	out = event.zones
	i = 0
	for z in ch.zones:
		out[i].center = Vector2((float(z.x) * k - ox) / k, (float(z.y) * k - oy) / k)
		i += 1
	out = event.anchors
	i = 0
	for a in ch.anchors:
		out[i].position = Vector2((float(a.x) * k - ox) / k, (float(a.y) * k - oy) / k)
		i += 1
	out = event.places
	i = 0
	for p in ch.places:
		out[i].position = Vector2((float(p.x) * k - ox) / k, (float(p.y) * k - oy) / k)
		i += 1
	out = event.sites
	i = 0
	for s in ch.sites:
		if not (s.sizes as Array).has(ch.size):
			continue
		var posts: Array = out[i].posts
		if s.has("posts"):
			var j := 0
			for post: Dictionary in s.posts:
				posts[j].position = Vector2((float(post.x) * k - ox) / k, (float(post.y) * k - oy) / k)
				j += 1
		else:
			posts[0].position = Vector2((float(s.x) * k - ox) / k, (float(s.y) * k - oy) / k)
		i += 1
	return event


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
## The morsel sites' claims: the entries of morsel_sites with a food_id (BP3-3), for the fuzz checker.
func morsel_claims() -> int:
	return _claims


## A growth tick hands a converted creature's morsel item to its site (D-130): the entry holds the
## item, due at once once it is gone.
func adopt_morsel(site_key: String, food_id: String) -> void:
	if not morsel_sites.has(site_key):
		morsel_sites[site_key] = {"food_id": "", "due_tick": 0}
	morsel_sites[site_key].due_tick = 0
	_set_food(site_key, food_id)


## The only writer of an entry's food_id: keeps _claims the count of entries with one (BP3-3).
func _set_food(m_id: String, food_id: String) -> void:
	var e: Dictionary = morsel_sites[m_id]
	_claims += int(not food_id.is_empty()) - int(not str(e.food_id).is_empty())
	e.food_id = food_id


## The only eraser of an entry (BP3-3).
func _drop_entry(m_id: String) -> void:
	if not str(morsel_sites[m_id].food_id).is_empty():
		_claims -= 1
	morsel_sites.erase(m_id)


## An unloading chunk's morsel sites leave: each live item expires ("unloaded"), then the entry and
## the loaded record go.
func _unload_morsels(sim: PoolSim, ch: WorldChunk) -> void:
	for m in ch.morsel_sites:
		if morsel_sites.has(m.id):
			var food_id := str(morsel_sites[m.id].food_id)
			if not food_id.is_empty():
				sim.carrion.expire(food_id, "unloaded")
			_drop_entry(m.id)
		_morsel_loaded.erase(m.id)


## The morsel sites' pass (D-129), every MORSEL_PASS_TICKS ticks after the food view, in site id order:
## an entry whose item is gone (eaten, rotted or dropped) is due again after its species' respawn
## time and a hashed jitter; an entry whose site is not loaded leaves once it holds no item; a due
## site spawns its item when the cell lives, the food total is under the cap, and its place is in the
## food ring, spawn_safe_m from every player place, out of the zoom-max view and clear.
func _morsel_pass(sim: PoolSim) -> void:
	if morsel_sites.is_empty() or posmod(sim.tick, MORSEL_PASS_TICKS) != 0:
		return
	var alive := {}
	for item in sim.carrion.items:
		alive[item.id] = true
	var body := sim.motion.position
	var places := sim._player_places()
	var quad := ViewFootprint.corners(body, camera, float(camera.zoom_max), view_aspect)
	var box := _box(quad)
	var safe := float(sim.species.fairness.spawn_safe_m)
	var ring := float(rings.food)
	var rot := float(content.config.growth.remnants.morsel_rot_s)
	for id in _sorted(morsel_sites.keys()):
		var e: Dictionary = morsel_sites[id]
		var m: Dictionary = _morsel_loaded.get(id, {})
		if not str(e.food_id).is_empty():
			if alive.has(e.food_id):
				continue
			_set_food(id, "")
			if not m.is_empty():
				e.due_tick = sim.tick + _respawn_ticks(sim, id, str(m.species))
		if m.is_empty():
			_drop_entry(id)
			continue
		if sim.tick < int(e.due_tick) or sim.dead or _food_total >= int(caps.food_items):
			continue
		var p := local_of_tm(m.abs[0], m.abs[1])
		var r := float(m.radius)
		if body.distance_to(p) > ring:
			continue
		var ok := true
		for at in places:
			ok = ok and at.distance_to(p) >= safe
		if not ok or not _out_of_view(quad, box, p, r) or not sim.arena.is_clear(p, r):
			continue
		var item := sim.carrion.spawn(p, "morsel_site", float(m.energy), -1, r, rot, {"species": m.species, "site": id})
		if item.is_empty():
			continue
		_set_food(id, str(item.id))
		_food_total += 1


## A morsel site's wait after its item goes: its species' niche respawn_s plus a jitter in
## [-respawn_jitter_s, respawn_jitter_s] hashed from the world, the site and the tick (D-129).
func _respawn_ticks(sim: PoolSim, id: String, species_id: String) -> int:
	var niche := sim.species.niche_of(species_id)
	var u := WorldHash.unit(WorldHash.hash_ints(PackedInt64Array([world_seed, gen_version, WorldHash.str32(id), sim.tick])))
	return CreatureBrain.ticks(niche.respawn_s) + roundi((2.0 * u - 1.0) * CreatureBrain.ticks(niche.respawn_jitter_s))


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
	total += _claims   # the morsel sites' items (BP3-3); no zone trim removes them
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
	_food_total = total
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
	if _fill_spread:
		# The growth tick: every zone shown waits for its fill and does not regrow meanwhile. The tick
		# after it queues them nearest first (the sort is its cost, not the growth tick's) and fills the
		# first FILL_ZONES_PER_TICK; a zone that left the food set by then regrows instead.
		_fill_spread = false
		_fill_sort = true
		var pending := {}
		for i in shown:
			pending[_zone_ids[i]] = true
		plankton.pending_fill = pending
	elif _fill_sort:
		_fill_sort = false
		var pending: Dictionary = plankton.pending_fill
		var waiting := PackedInt32Array()
		for i in shown:
			if pending.has(_zone_ids[i]):
				waiting.append(i)
		_fill_queue = _nearest_first(waiting, body)
		pending.clear()
		for id in _fill_queue:
			pending[id] = true
	var filled := 0
	while filled < FILL_ZONES_PER_TICK and not _fill_queue.is_empty():
		var id: String = _fill_queue.pop_front()
		plankton.pending_fill.erase(id)
		if food.has(id):   # still shown; a zone that left the food set regrows by the plankton's own tick
			plankton.fill_zone(sim.region.zone(id), sim.region, sim.arena, sim.tick, sim.now())
			filled += 1
	var tile := tile_of_local(body)
	if tile != _cell_tile:
		_cell_tile = tile
		var info := gen.tile_info(WorldConfig.band_of(size), tile.x, tile.y)
		_emit(sim, {"type": "tile_entered", "tile": tile, "region": str(info.get("region", "")), "rare": str(info.get("rare", ""))})


## The shown food zones' ids nearest the body first: by the distance from the body to the zone's edge,
## ties by id (the index is current: _food_view built it this tick).
func _nearest_first(shown: PackedInt32Array, body: Vector2) -> Array[String]:
	var rows := []
	for i in shown:
		rows.append([body.distance_to(_zone_c[i]) - _zone_r[i], _zone_ids[i]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ids: Array[String] = []
	for row in rows:
		ids.append(row[1])
	return ids


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
