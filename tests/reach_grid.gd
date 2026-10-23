extends RefCounted
## Test helper (not a test file): swimming distances over a pool layout on a grid. A grid point
## is open when a cell of radius `body_r` fits there (inside the soft wall, clear of rocks).
## Paths move between neighbouring open points (8 directions), so distances are walking
## distances round rocks, never straight lines through them.
##
##     var grid = preload("res://tests/reach_grid.gd").new(layout, 0.5)
##     var grid = preload("res://tests/reach_grid.gd").over(arena, zones, bounds, 0.5)   # any arena

const STEP := 0.5
const UNITS_PER_STEP := 10       ## integer path costs: straight 10, diagonal 14 (x STEP / 10 m)
const DIAGONAL_UNITS := 14
const UNREACHED := 1 << 30
## zone_points() buckets zones on this grid (bu), so a point tests only the zones near it.
const ZONE_BUCKET := 8.0

var layout: PoolLayout           ## null for a grid made by over()
var arena: PoolArena
var zones: Array[Dictionary] = [] ## {center, radius}: what zone_points() counts
var size := 0                     ## points per row
var rows := 0                     ## points per column (size, for a pool)
var origin := Vector2.ZERO        ## plane position of index (0, 0)
var open := PackedByteArray()


## The grid over a pool layout's soft wall. With no layout, an empty grid for over() to fill.
func _init(p_layout: PoolLayout = null, body_r: float = 0.0) -> void:
	if p_layout == null:
		return
	layout = p_layout
	var half := ceili(p_layout.soft_start / STEP)
	_build(p_layout.build_arena(), p_layout.zones, Rect2(-half * STEP, -half * STEP, 2 * half * STEP, 2 * half * STEP), body_r)


## The grid over `bounds` (points STEP apart from its corner, covering it) on any arena, with
## `zones` for zone_points(): an endless world's chunk arena, a tile, a seam.
static func over(p_arena: PoolArena, p_zones: Array[Dictionary], bounds: Rect2, body_r: float) -> RefCounted:
	var grid = new()
	grid._build(p_arena, p_zones, bounds, body_r)
	return grid


func _build(p_arena: PoolArena, p_zones: Array[Dictionary], bounds: Rect2, body_r: float) -> void:
	arena = p_arena
	zones = p_zones
	origin = bounds.position
	size = ceili(bounds.size.x / STEP) + 1
	rows = ceili(bounds.size.y / STEP) + 1
	open.resize(size * rows)
	for i in open.size():
		open[i] = 1 if arena.is_clear(point(i), body_r) else 0


func point(index: int) -> Vector2:
	return origin + Vector2(index % size, floori(index / float(size))) * STEP


func index_near(p: Vector2) -> int:
	var x := clampi(roundi((p.x - origin.x) / STEP), 0, size - 1)
	var y := clampi(roundi((p.y - origin.y) / STEP), 0, rows - 1)
	return y * size + x


func open_count() -> int:
	return open.count(1)


## Walking distance in meters from the nearest source to every point (INF where none). Points
## further than `max_m` are left at INF, which saves time when only nearby points matter.
func distances_from(sources: PackedInt32Array, max_m: float = INF) -> PackedFloat32Array:
	var limit := UNREACHED if is_inf(max_m) else floori(max_m / STEP * UNITS_PER_STEP)
	var units := PackedInt32Array()
	units.resize(open.size())
	units.fill(UNREACHED)
	# Bucket queue (integer costs), so no priority heap is needed.
	var buckets: Array = [[]]
	for s in sources:
		if open[s] == 1:
			units[s] = 0
			buckets[0].append(s)
	var b := 0
	while b < buckets.size():
		for i in buckets[b]:
			if units[i] != b:
				continue
			var x: int = i % size
			var y: int = floori(i / float(size))
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx
					var ny: int = y + dy
					if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= size or ny >= rows:
						continue
					var n := ny * size + nx
					if open[n] == 0:
						continue
					var cost := b + (DIAGONAL_UNITS if dx != 0 and dy != 0 else UNITS_PER_STEP)
					if cost < units[n] and cost <= limit:
						units[n] = cost
						while buckets.size() <= cost:
							buckets.append([])
						buckets[cost].append(n)
		b += 1
	var meters := PackedFloat32Array()
	meters.resize(units.size())
	for i in units.size():
		meters[i] = INF if units[i] == UNREACHED else units[i] * STEP / UNITS_PER_STEP
	return meters


## Open points within `radius` of `center`.
func points_in_circle(center: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var low := index_near(center - Vector2(radius, radius))
	var high := index_near(center + Vector2(radius, radius))
	for y in range(floori(low / float(size)), floori(high / float(size)) + 1):
		for x in range(low % size, high % size + 1):
			var i := y * size + x
			if open[i] == 1 and point(i).distance_to(center) <= radius:
				out.append(i)
	return out


## Open points inside any plankton zone, in index order. Zones are bucketed on a ZONE_BUCKET grid
## first, so each point tests only the zone discs that reach its bucket.
func zone_points() -> PackedInt32Array:
	var buckets := {}
	for z in zones:
		var c: Vector2 = z.center
		var r := float(z.radius)
		for by in range(floori((c.y - r) / ZONE_BUCKET), floori((c.y + r) / ZONE_BUCKET) + 1):
			for bx in range(floori((c.x - r) / ZONE_BUCKET), floori((c.x + r) / ZONE_BUCKET) + 1):
				buckets.get_or_add(Vector2i(bx, by), []).append(z)
	var out := PackedInt32Array()
	for i in open.size():
		if open[i] == 0:
			continue
		var p := point(i)
		for z in buckets.get(Vector2i(floori(p.x / ZONE_BUCKET), floori(p.y / ZONE_BUCKET)), []):
			if p.distance_to(z.center) <= z.radius:
				out.append(i)
				break
	return out


## A component label per point (-1 where closed): open points joined by the moves distances_from
## takes (8 directions) share a label, numbered in index order from 0. Cheaper than a distance pass
## when only connection matters.
func components() -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(open.size())
	labels.fill(-1)
	var next := 0
	var stack := PackedInt32Array()
	for first in open.size():
		if open[first] == 0 or labels[first] != -1:
			continue
		labels[first] = next
		stack.append(first)
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var x := i % size
			var y := floori(i / float(size))
			for ny in range(maxi(y - 1, 0), mini(y + 2, rows)):
				for nx in range(maxi(x - 1, 0), mini(x + 2, size)):
					var n := ny * size + nx
					if open[n] == 1 and labels[n] == -1:
						labels[n] = next
						stack.append(n)
		next += 1
	return labels


## Open points on the grid's outer rows and columns, in index order.
func border_points() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in open.size():
		var x := i % size
		var y := floori(i / float(size))
		if open[i] == 1 and (x == 0 or y == 0 or x == size - 1 or y == rows - 1):
			out.append(i)
	return out
