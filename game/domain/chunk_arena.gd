class_name ChunkArena
extends PoolArena
## The endless world's colliders (S1): PoolArena without walls, its rocks loaded and unloaded a
## chunk at a time (docs/s1/s1-interfaces.md section 3.7, docs/s1/s1-core.md section 6.3).
##
## Every collider keeps its absolute centre in float64; the local centre the sim uses is that minus
## the origin, subtracted in float64 and only then cast (C-2), so a world 100 km out rounds no worse
## than one at home, and set_origin() recomputes every local centre from its absolute value.
##
## The inherited arrays (rocks, _centers, _radii) stay in one canonical order: chunk key sorted by
## (y, x), then each chunk's own list order. With rock_grid false every query is PoolArena's own loop
## over those arrays, the brute-force reference. With rock_grid true a query visits only the chunks
## its box can reach, in that same order, behind a per-chunk near grid: the same arithmetic over
## every collider that could change the answer, so the results are bit-identical (C-3).
##
## A chunk's near grid holds, per 2 tm cell, how many loaded colliders a body of GRID_BODY_R there
## could touch. Adding or removing a chunk counts its colliders into or out of its own and its
## neighbours' grids, so a cell is non-zero exactly when a full re-mark would set it, for about 12 µs
## a load instead of a 1.36 ms re-mark (C-19).

const CHUNK_GRID_N := 16          ## near-grid cells per chunk side (2 tm at chunk_tm 32 = GRID_CELL_M)
const MAX_COLLIDER_R := 4.0       ## tm; add_chunk refuses larger colliders (the kit caps set pieces at it)
## tm: how far settle() may push a body before it hands the whole settle to the reference (a push
## that deep needs a body placed inside a collider, which only a debug move does).
const SETTLE_TRAVEL_TM := 2.0
const FAR_BOX_TM := 1e12          ## a query box reaching past this covers every loaded chunk

var chunk_tm := 32.0
var origin_x := 0.0               ## float64 abs tm of local (0, 0)
var origin_y := 0.0
## How often settle() fell back to the reference; read only by tests.
var settle_fallbacks := 0

var _keys: Array[Vector2i] = []   # loaded, sorted (y, x): the canonical order
var _abs_x := PackedFloat64Array()  # per collider, canonical order
var _abs_y := PackedFloat64Array()
var _range := {}                  # Vector2i -> Vector2i(first index, count) into the canonical arrays
var _grids := {}                  # Vector2i -> PackedInt32Array(CHUNK_GRID_N^2) of near counts
var _chunk_colliders := {}        # Vector2i -> Array[Dictionary] {id, x, y, r} as added (abs, float64)
var _ring := 1                    # neighbours a collider's near reach can cross into, per side
# The last _candidates() call: index ranges [first, end) into the canonical arrays, ascending.
var _cand := PackedInt32Array()
var _cand_n := 0


static func create_endless(p_chunk_tm: float = 32.0) -> ChunkArena:
	var arena := ChunkArena.new()
	arena.radius = INF
	arena.soft_start = INF
	arena.hard_radius = INF
	arena.chunk_tm = p_chunk_tm
	arena._ring = ceili((MAX_COLLIDER_R + GRID_BODY_R + GRID_SLACK) / p_chunk_tm)
	return arena


## An arena at origin 0 holding `shells` ({id, center: Vector2 local tm, radius}), grouped into
## chunks in input order. For tests and static checks over tile-local or block-local coordinates.
static func from_shells(shells: Array[Dictionary], p_chunk_tm: float = 32.0) -> ChunkArena:
	var arena := create_endless(p_chunk_tm)
	var by_key := {}
	for s in shells:
		var c: Vector2 = s.center
		var key := Vector2i(floori(c.x / p_chunk_tm), floori(c.y / p_chunk_tm))
		if not by_key.has(key):
			var list: Array[Dictionary] = []
			by_key[key] = list
		by_key[key].append({"id": str(s.id), "x": float(c.x), "y": float(c.y), "r": float(s.radius)})
	var keys: Array = by_key.keys()
	keys.sort_custom(_key_before)
	for key: Vector2i in keys:
		arena.add_chunk(key, by_key[key])
	return arena


## Loads chunk `key` with its colliders ({id, x, y, r}: ABS tm, float64), in list order. A collider
## that is not finite, has r <= 0 or r > MAX_COLLIDER_R, or whose centre lies outside `key` is
## refused (push_error, skipped); so is a key already loaded.
func add_chunk(key: Vector2i, colliders: Array[Dictionary]) -> void:
	if _range.has(key):
		push_error("ChunkArena: chunk %s is already loaded" % key)
		return
	var kept: Array[Dictionary] = []
	for c in colliders:
		var x := float(c.x)
		var y := float(c.y)
		var r := float(c.r)
		if not (is_finite(x) and is_finite(y) and is_finite(r)) or r <= 0.0 or r > MAX_COLLIDER_R:
			push_error("ChunkArena: collider %s (%s, %s, r %s) refused" % [c.get("id", "?"), x, y, r])
			continue
		if floori(x / chunk_tm) != key.x or floori(y / chunk_tm) != key.y:
			push_error("ChunkArena: collider %s at (%s, %s) is not in chunk %s" % [c.get("id", "?"), x, y, key])
			continue
		kept.append({"id": str(c.id), "x": x, "y": y, "r": r})
	# 1. The key's place in the canonical order, and its colliders' place in the arrays.
	var pos := _keys.bsearch_custom(key, _key_before)
	var first := _centers.size() if pos == _keys.size() else (_range[_keys[pos]] as Vector2i).x
	for i in kept.size():
		var c: Dictionary = kept[i]
		var local := Vector2(c.x - origin_x, c.y - origin_y)   # float64 subtraction, then the cast (C-2)
		rocks.insert(first + i, {"id": c.id, "center": local, "radius": c.r})
		_centers.insert(first + i, local)
		_radii.insert(first + i, c.r)
		_abs_x.insert(first + i, c.x)
		_abs_y.insert(first + i, c.y)
	for j in range(pos, _keys.size()):
		var later: Vector2i = _range[_keys[j]]
		_range[_keys[j]] = Vector2i(later.x + kept.size(), later.y)
	_keys.insert(pos, key)
	_range[key] = Vector2i(first, kept.size())
	_chunk_colliders[key] = kept
	# 2. Its grid counts its own colliders and its loaded neighbours' that reach into it;
	# 3. its colliders are counted into the loaded neighbours' grids they reach.
	var grid := PackedInt32Array()
	grid.resize(CHUNK_GRID_N * CHUNK_GRID_N)
	grid.fill(0)
	_grids[key] = grid
	for dy in range(-_ring, _ring + 1):
		for dx in range(-_ring, _ring + 1):
			var other := key + Vector2i(dx, dy)
			if not _range.has(other):
				continue
			for c in _chunk_colliders[other]:
				_count(key, c, 1)
			if other != key:
				for c in kept:
					_count(other, c, 1)


## Unloads chunk `key`: its colliders leave the arrays and every near grid. Unknown keys are ignored.
func remove_chunk(key: Vector2i) -> void:
	if not _range.has(key):
		return
	var own: Array = _chunk_colliders[key]
	for dy in range(-_ring, _ring + 1):
		for dx in range(-_ring, _ring + 1):
			var other := key + Vector2i(dx, dy)
			if other != key and _range.has(other):
				for c in own:
					_count(other, c, -1)
	var span: Vector2i = _range[key]
	for i in span.y:
		rocks.remove_at(span.x)
		_centers.remove_at(span.x)
		_radii.remove_at(span.x)
		_abs_x.remove_at(span.x)
		_abs_y.remove_at(span.x)
	var pos := _keys.find(key)
	_keys.remove_at(pos)
	for j in range(pos, _keys.size()):
		var later: Vector2i = _range[_keys[j]]
		_range[_keys[j]] = Vector2i(later.x - span.y, later.y)
	_range.erase(key)
	_grids.erase(key)
	_chunk_colliders.erase(key)


func has_chunk(key: Vector2i) -> bool:
	return _range.has(key)


## The loaded keys in canonical order, sorted by (y, x).
func chunk_keys() -> Array[Vector2i]:
	return _keys.duplicate()


## Moves the frame: every local centre is recomputed from its absolute value (never shifted, so no
## error accumulates). The near grids are absolute and do not change.
func set_origin(ox_tm: float, oy_tm: float) -> void:
	origin_x = ox_tm
	origin_y = oy_tm
	for k in _centers.size():
		var local := Vector2(_abs_x[k] - origin_x, _abs_y[k] - origin_y)
		_centers[k] = local
		rocks[k].center = local


# --- the overrides ---

## Colliders come only through add_chunk: a pool-wide grid cannot be sized for an unbounded world.
func add_rock(id: String, _center: Vector2, _rock_radius: float) -> void:
	push_error("ChunkArena: rock '%s' refused; add colliders with add_chunk" % id)


func _mark_grid(_center: Vector2, _rock_radius: float) -> void:
	pass


## No walls: there is no soft band to be in (the base would give NaN for an infinite one).
func wall_depth(_p: Vector2) -> float:
	return 0.0


func is_clear(p: Vector2, r: float) -> bool:
	if not rock_grid or not p.is_finite():
		return super.is_clear(p, r)
	if not rocks_near(p, r):
		return true
	var h := MAX_COLLIDER_R + r + GRID_SLACK
	for i in _candidates(p.x - h, p.y - h, p.x + h, p.y + h):
		for k in range(_cand[2 * i], _cand[2 * i + 1]):
			if p.distance_to(_centers[k]) < _radii[k] + r - CLEAR_EPSILON:
				return false
	return true


func settle(m: Locomotion.MotionState, body_r: float) -> void:
	if not rock_grid:
		super.settle(m, body_r)
		return
	if rocks_near(m.position, body_r):
		var p0 := m.position
		var v0 := m.velocity
		var h := MAX_COLLIDER_R + body_r + GRID_SLACK + SETTLE_TRAVEL_TM
		var n := _candidates(p0.x - h, p0.y - h, p0.x + h, p0.y + h)
		for pass_index in ROCK_PASSES:
			for i in n:
				for k in range(_cand[2 * i], _cand[2 * i + 1]):
					# PoolArena.settle's loop body, unchanged.
					var center := _centers[k]
					var offset: Vector2 = m.position - center
					var min_dist: float = _radii[k] + body_r
					if absf(offset.x) >= min_dist or absf(offset.y) >= min_dist:
						continue
					var dist := offset.length()
					if dist >= min_dist:
						continue
					var normal := offset / dist if dist > 1e-9 else Vector2.RIGHT
					m.position = center + normal * min_dist
					var inward := m.velocity.dot(normal)
					if inward < 0.0:
						m.velocity -= normal * inward
					if absf(m.position.x - p0.x) > SETTLE_TRAVEL_TM or absf(m.position.y - p0.y) > SETTLE_TRAVEL_TM:
						# Out of the box: a collider no candidate covers could now overlap. Start again
						# with the reference, over every loaded collider.
						m.position = p0
						m.velocity = v0
						settle_fallbacks += 1
						super.settle(m, body_r)
						return
	# The reference's hard limit is hard_radius - body_r = INF here, so it never acts.


func segment_clear(a: Vector2, b: Vector2, shrink: float = SIGHT_SHRINK) -> bool:
	if not rock_grid:
		return super.segment_clear(a, b, shrink)
	var ab := b - a
	var len_sq := ab.length_squared()
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var h := MAX_COLLIDER_R * maxf(shrink, 1.0) + GRID_SLACK
	for i in _candidates(low.x - h, low.y - h, high.x + h, high.y + h):
		for k in range(_cand[2 * i], _cand[2 * i + 1]):
			# PoolArena.segment_clear's loop body, unchanged.
			var p := _centers[k]
			var block := _radii[k] * shrink + GRID_SLACK
			if p.x < low.x - block or p.x > high.x + block or p.y < low.y - block or p.y > high.y + block:
				continue
			var dist: float
			if len_sq < 1e-12:
				dist = p.distance_to(a)
			else:
				dist = p.distance_to(a + ab * clampf((p - a).dot(ab) / len_sq, 0.0, 1.0))
			if dist < _radii[k] * shrink:
				return false
	return true


func route_point(from: Vector2, to: Vector2, body_r: float, clearance: float = ROUTE_CLEARANCE,
		margin: float = ROUTE_MARGIN, side: int = 0) -> Vector2:
	if not rock_grid:
		return super.route_point(from, to, body_r, clearance, margin, side)
	var to_target := to - from
	var length := to_target.length()
	if length < 1e-6:
		return to
	var dir := to_target / length
	# A collider blocks when its centre projects into (0, length + its radius) along the line and
	# lies within its radius + body_r + clearance of it, so the box runs MAX_COLLIDER_R past `to`.
	var past := to + dir * MAX_COLLIDER_R
	var h := MAX_COLLIDER_R + body_r + clearance + GRID_SLACK
	var blocking := -1
	var blocking_off := Vector2.ZERO
	var nearest_along := INF
	for i in _candidates(minf(minf(from.x, to.x), past.x) - h, minf(minf(from.y, to.y), past.y) - h,
			maxf(maxf(from.x, to.x), past.x) + h, maxf(maxf(from.y, to.y), past.y) + h):
		for k in range(_cand[2 * i], _cand[2 * i + 1]):
			# PoolArena.route_point's loop body, unchanged: candidates come in canonical order, so the
			# first strict-nearest blocker is the reference's.
			var c: Vector2 = _centers[k] - from
			var along := c.dot(dir)
			var rock_r := _radii[k]
			if along <= 0.0 or along >= length + rock_r:
				continue
			var off := c - dir * along
			if off.length() < rock_r + body_r + clearance and along < nearest_along:
				nearest_along = along
				blocking = k
				blocking_off = off
	if blocking < 0:
		return to
	var away := -blocking_off.normalized() if blocking_off.length() > 1e-6 else dir.orthogonal()
	if side != 0:
		away = dir.orthogonal() * signf(side)
	return _centers[blocking] + away * (_radii[blocking] + body_r + margin)


func rock_contact(p: Vector2, r: float, slack: float = CONTACT_SLACK, facing: float = NAN, max_bearing: float = PI) -> String:
	if not rock_grid:
		return super.rock_contact(p, r, slack, facing, max_bearing)
	var best := ""
	var best_gap := INF
	if not rocks_near(p, r + maxf(slack, 0.0)):
		return best
	var h := MAX_COLLIDER_R + r + maxf(slack, 0.0) + GRID_SLACK
	for i in _candidates(p.x - h, p.y - h, p.x + h, p.y + h):
		for k in range(_cand[2 * i], _cand[2 * i + 1]):
			# PoolArena.rock_contact's loop body, unchanged.
			var gap: float = p.distance_to(_centers[k]) - _radii[k] - r
			if gap > slack:
				continue
			if is_finite(facing) and absf(angle_difference(facing, (_centers[k] - p).angle())) > max_bearing:
				continue
			var id: String = rocks[k].id
			if gap < best_gap or (gap == best_gap and id < best):
				best_gap = gap
				best = id
	return best


## False only when the near grid of the chunk under `p` shows no collider a body of radius `body_r`
## could touch there. True with the grid off, for a larger body, off the loaded chunks or for a point
## that is not finite (the caller then checks every candidate).
func rocks_near(p: Vector2, body_r: float) -> bool:
	if not rock_grid or body_r > GRID_BODY_R or not p.is_finite():
		return true
	var ax := origin_x + p.x
	var ay := origin_y + p.y
	var key := Vector2i(floori(ax / chunk_tm), floori(ay / chunk_tm))
	var grid: Variant = _grids.get(key)
	if grid == null:
		return true
	var cell := chunk_tm / CHUNK_GRID_N
	var gx := clampi(floori((ax - key.x * chunk_tm) / cell), 0, CHUNK_GRID_N - 1)
	var gy := clampi(floori((ay - key.y * chunk_tm) / cell), 0, CHUNK_GRID_N - 1)
	return (grid as PackedInt32Array)[gy * CHUNK_GRID_N + gx] != 0


# --- helpers ---

## Fills _cand with the canonical index ranges of the loaded chunks overlapping the local box
## [lo, hi] and returns how many there are. The box is turned absolute in float64; chunks are
## visited by rows (y ascending, then x), so the indices come out ascending: a candidate loop visits
## a subset of the canonical arrays in canonical order. A box that is not finite covers everything.
func _candidates(lo_x: float, lo_y: float, hi_x: float, hi_y: float) -> int:
	_cand_n = 0
	# Beyond FAR_BOX_TM (or not finite) a box is treated as covering everything, before any key
	# arithmetic could overflow.
	if not (absf(lo_x) < FAR_BOX_TM and absf(lo_y) < FAR_BOX_TM and absf(hi_x) < FAR_BOX_TM and absf(hi_y) < FAR_BOX_TM):
		if not _centers.is_empty():
			_push_range(0, _centers.size())
		return _cand_n
	var kx0 := floori((origin_x + lo_x) / chunk_tm)
	var ky0 := floori((origin_y + lo_y) / chunk_tm)
	var kx1 := floori((origin_x + hi_x) / chunk_tm)
	var ky1 := floori((origin_y + hi_y) / chunk_tm)
	if (kx1 - kx0 + 1) * (ky1 - ky0 + 1) > _keys.size():
		# A box wider than the loaded set: walk the loaded keys (already canonical) instead.
		for key in _keys:
			if key.x >= kx0 and key.x <= kx1 and key.y >= ky0 and key.y <= ky1:
				var span: Vector2i = _range[key]
				_push_range(span.x, span.x + span.y)
		return _cand_n
	for ky in range(ky0, ky1 + 1):
		for kx in range(kx0, kx1 + 1):
			var span: Variant = _range.get(Vector2i(kx, ky))
			if span != null:
				_push_range((span as Vector2i).x, (span as Vector2i).x + (span as Vector2i).y)
	return _cand_n


## Appends [first, end) to _cand, joining it to the previous range when they touch.
func _push_range(first: int, end: int) -> void:
	if first == end:
		return
	if _cand_n > 0 and _cand[2 * _cand_n - 1] == first:
		_cand[2 * _cand_n - 1] = end
		return
	if _cand.size() < 2 * (_cand_n + 1):
		_cand.resize(2 * (_cand_n + 1))
	_cand[2 * _cand_n] = first
	_cand[2 * _cand_n + 1] = end
	_cand_n += 1


## Adds `delta` to every cell of chunk `grid_key`'s near grid that a body of GRID_BODY_R could touch
## collider `c` ({x, y, r}, abs) from, plus GRID_SLACK: the arithmetic of PoolArena._mark_grid, in
## absolute float64. A pure function of the collider and the cell, so -1 undoes +1 exactly.
func _count(grid_key: Vector2i, c: Dictionary, delta: int) -> void:
	var grid: PackedInt32Array = _grids[grid_key]
	var cell := chunk_tm / CHUNK_GRID_N
	var cx: float = c.x
	var cy: float = c.y
	var reach: float = c.r + GRID_BODY_R + GRID_SLACK
	var x_base := grid_key.x * chunk_tm
	var y_base := grid_key.y * chunk_tm
	var gx0 := clampi(floori((cx - reach - x_base) / cell), 0, CHUNK_GRID_N - 1)
	var gx1 := clampi(floori((cx + reach - x_base) / cell), 0, CHUNK_GRID_N - 1)
	var gy0 := clampi(floori((cy - reach - y_base) / cell), 0, CHUNK_GRID_N - 1)
	var gy1 := clampi(floori((cy + reach - y_base) / cell), 0, CHUNK_GRID_N - 1)
	for gy in range(gy0, gy1 + 1):
		var y0 := y_base + gy * cell
		var dy := maxf(maxf(y0 - cy, cy - (y0 + cell)), 0.0)
		if dy >= reach:
			continue
		for gx in range(gx0, gx1 + 1):
			var x0 := x_base + gx * cell
			var dx := maxf(maxf(x0 - cx, cx - (x0 + cell)), 0.0)
			if dx * dx + dy * dy < reach * reach:
				grid[gy * CHUNK_GRID_N + gx] += delta
	_grids[grid_key] = grid


## Canonical key order: by y, then x.
static func _key_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
