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
## shifts, so a zone, site or collider is exact however far the cell swims.
##
## Chunks are 32 tm squares keyed by Vector2i, loaded from WorldGen.chunk (pure, so a chunk comes
## back the same whatever route reaches it). The view set (view_set_keys) is the 3 x 3 chunks round
## the cell's chunk plus every chunk within VIEW_SET_MARGIN_TM of the widest camera view: it is
## loaded at once when the world starts, so nothing in view is ever missing.

## tm: look_ahead_max (2.5) + spawn_view_margin_m (1.0) + MAX_ZONE_RADIUS_TM. Every zone touching the
## view plus its margin has its centre in a view-set chunk (S1 core C-1).
const VIEW_SET_MARGIN_TM := 11.5
## tm: the largest zone radius at size 1 (tile rule 3).
const MAX_ZONE_RADIUS_TM := 8.0

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
var world_seed := 0
var gen_version := 1
## The camera table the view set is measured with (the layout's camera), and the spawn view's
## aspect and margin (fairness: the widest screen, look-ahead plus the safety gap).
var camera := {}
var view_aspect := 2.4
var view_margin := 3.5

var _chunks := {}                      ## Vector2i -> WorldChunk (absolute)
var _keys: Array[Vector2i] = []        ## loaded, sorted (y, x)
var _zone_abs := {}                    ## zone id -> PackedFloat64Array [x, y] (absolute tm)
var _zone_chunk := {}                  ## zone id -> Vector2i
var _cell_tile := Vector2i.ZERO
var _tm_to_am := 1.0                   ## 1.6^(size - 1): 1.0 in S1


static func create(p_content: WorldContent, p_gen: WorldGen) -> WorldStream:
	var w := WorldStream.new()
	w.content = p_content
	w.gen = p_gen
	var config := p_content.config
	w.size = config.size_start
	w.rings = config.rings.duplicate()
	w.caps = config.caps.duplicate()
	w.chunk_tm = config.chunk_tm
	w.world_seed = p_gen.world_seed
	w.gen_version = p_gen.gen_version
	var spawn: PackedFloat64Array = p_content.home.spawn
	w.checkpoint_am = PackedFloat64Array([spawn[0], spawn[1], p_content.home.spawn_heading, float(w.size)])
	w.origin_x_am = spawn[0]
	w.origin_y_am = spawn[1]
	return w


## The streaming block, first in every endless tick (spine 3.11).
func step(sim: PoolSim) -> void:
	pass


## The rest of a new world once the cell is placed (PoolSim._create_endless): the cell's tile.
func start(sim: PoolSim) -> void:
	_cell_tile = tile_of_local(sim.motion.position)


# --- frames ---

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
	return PackedStringArray()


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
		"site_counts": {},
		"sleeping": Array(sleeping_ids()),
		"slots": {},
		"cell_tile": [_cell_tile.x, _cell_tile.y],
		"counters": counters.duplicate(),
	}


func _load_chunk(sim: PoolSim, key: Vector2i) -> void:
	var ch := gen.chunk(size, key.x, key.y)
	var colliders: Array[Dictionary] = []
	for s in ch.shells:
		colliders.append({"id": s.id, "x": float(s.x), "y": float(s.y), "r": float(s.r)})
	(sim.arena as ChunkArena).add_chunk(key, colliders)
	for z in ch.zones:
		sim.region.add_zone(z.id, local_of_tm(float(z.x), float(z.y)), float(z.radius), float(z.capacity), float(z.growth_rate))
		_zone_abs[z.id] = PackedFloat64Array([float(z.x), float(z.y)])
		_zone_chunk[z.id] = key
	if sim.motion != null and not sim.dead:
		# A new collider never holds the cell: the loads come from 56 tm out, but a debug move or a
		# test may put the cell anywhere.
		sim.arena.settle(sim.motion, sim.phenotype.radius)
		sim.actor.position = sim.motion.position
	_insert_key(key)
	_chunks[key] = ch
	_emit(sim, _chunk_loaded_event(ch))


## Every local value that is derived from an absolute one, again from its absolute value.
func _rederive(sim: PoolSim) -> void:
	if sim.arena is ChunkArena:
		(sim.arena as ChunkArena).set_origin(origin_x_am / _tm_to_am, origin_y_am / _tm_to_am)
	for z in sim.region.zones:
		var a: PackedFloat64Array = _zone_abs.get(z.id, PackedFloat64Array())
		if a.size() == 2:
			z.center = local_of_tm(a[0], a[1])


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
		places.append({"id": p.id, "kind": p.kind, "position": local_of_tm(float(p.x), float(p.y))})
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


static func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out
