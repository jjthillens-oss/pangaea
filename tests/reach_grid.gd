extends RefCounted
## Test helper (not a test file): swimming distances over a pool layout on a grid. A grid point
## is open when a cell of radius `body_r` fits there (inside the soft wall, clear of rocks).
## Paths move between neighbouring open points (8 directions), so distances are walking
## distances round rocks, never straight lines through them.
##
##     var grid = preload("res://tests/reach_grid.gd").new(layout, 0.5)

const STEP := 0.5
const UNITS_PER_STEP := 10       ## integer path costs: straight 10, diagonal 14 (x STEP / 10 m)
const DIAGONAL_UNITS := 14
const UNREACHED := 1 << 30

var layout: PoolLayout
var arena: PoolArena
var size := 0                     ## points per side
var origin := Vector2.ZERO        ## plane position of index (0, 0)
var open := PackedByteArray()


func _init(p_layout: PoolLayout, body_r: float) -> void:
	layout = p_layout
	arena = p_layout.build_arena()
	var half := ceili(p_layout.soft_start / STEP)
	size = half * 2 + 1
	origin = Vector2(-half * STEP, -half * STEP)
	open.resize(size * size)
	for i in open.size():
		open[i] = 1 if arena.is_clear(point(i), body_r) else 0


func point(index: int) -> Vector2:
	return origin + Vector2(index % size, floori(index / float(size))) * STEP


func index_near(p: Vector2) -> int:
	var x := clampi(roundi((p.x - origin.x) / STEP), 0, size - 1)
	var y := clampi(roundi((p.y - origin.y) / STEP), 0, size - 1)
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
					if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= size or ny >= size:
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


## Open points inside any plankton zone.
func zone_points() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in open.size():
		if open[i] == 0:
			continue
		for z in layout.zones:
			if point(i).distance_to(z.center) <= z.radius:
				out.append(i)
				break
	return out
