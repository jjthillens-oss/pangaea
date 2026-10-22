class_name PoolArena
extends RefCounted
## The pool's walls and rocks on the movement plane (M1 step 2). Moves a swimmer by its velocity
## and keeps it out of rocks and inside the pool. No physics bodies.
##
## Soft wall: past soft_start, outward swimming fades with depth into the band and a gentle return
## current pulls the cell back, so the edge is felt rather than hit. Rocks push out along their
## normal and remove only the inward velocity, so the cell slides. A hard limit is the failsafe.
##
## M1 step 3 adds the geometry creatures share with the player: line of sight past rocks, a detour
## point round the first rock in the way, pushing two overlapping bodies apart, the rock a body
## touches, and a hard clamp to a disc (a creature's leash).

const RETURN_SPEED := 1.0   ## m/s at full depth into the soft band
const ROCK_PASSES := 2      ## pushing out of one rock can push into another; two passes settle it
## Overlap is_clear forgives. Pushing out of a rock lands within float32 rounding of its surface
## (a few micrometres either side at pool distances), so this is above that and far below 1 mm.
const CLEAR_EPSILON := 1e-4
## Line of sight is blocked only within this share of a rock's radius, so grazing the edge still sees.
const SIGHT_SHRINK := 0.9
const ROUTE_CLEARANCE := 0.1   ## m: a rock blocks the straight line when the body would pass this close
const ROUTE_MARGIN := 0.6      ## m: room kept from a rock when going round it
const CONTACT_SLACK := 0.05    ## m: a rock counts as touched within this gap
## The rock grid (plan section 20's first remedy): square cells over the pool, each marked when a
## rock could touch a body of radius up to GRID_BODY_R somewhere in it. Where a cell is unmarked,
## which is most of the pool, settle() and the other per-body rock loops are skipped, since none of
## their rocks could act; elsewhere they run unchanged, so results are the same to the bit.
const GRID_CELL_M := 2.0
const GRID_BODY_R := 1.5       ## m: a larger body (or reach) always runs the full loop
const GRID_SLACK := 0.01       ## m: a cell is marked this far beyond the touch distance (rounding)

var radius := 40.0
var soft_start := 36.0
var hard_radius := 39.5
var return_speed := RETURN_SPEED
## [{"id": String, "center": Vector2, "radius": float}]; add rocks with add_rock() only.
var rocks: Array[Dictionary] = []

# The rocks' centers and radii again, as packed arrays: the per-tick loops (every body's move, every
# line of sight, every detour) read these, several times faster than the dictionaries (M1 step 3,
# when seven creatures joined the cell). Same values, same arithmetic, so the same results.
var _centers := PackedVector2Array()
var _radii := PackedFloat64Array()
# The rock grid: _grid_n x _grid_n cells of GRID_CELL_M from (-_grid_half, -_grid_half), row by row;
# 1 where a rock is near. Made with the first rock.
var _grid_near := PackedByteArray()
var _grid_n := 0
var _grid_half := 0.0
## false: every rock loop checks every rock everywhere, as before the grid and the line-of-sight box
## (the tests' reference).
var rock_grid := true


static func create(p_radius: float, p_soft_start: float, p_hard_radius: float, p_return_speed: float = RETURN_SPEED) -> PoolArena:
	var arena := PoolArena.new()
	arena.radius = p_radius
	arena.soft_start = p_soft_start
	arena.hard_radius = p_hard_radius
	arena.return_speed = p_return_speed
	return arena


func add_rock(id: String, center: Vector2, rock_radius: float) -> void:
	rocks.append({"id": id, "center": center, "radius": rock_radius})
	_centers.append(center)
	_radii.append(rock_radius)
	_mark_grid(center, rock_radius)


## How far into the soft band a point is: 0 inside soft_start, 1 at the hard radius.
func wall_depth(p: Vector2) -> float:
	return clampf((p.length() - soft_start) / (hard_radius - soft_start), 0.0, 1.0)


## True when a circle of radius `r` at `p` lies inside soft_start and touches no rock.
func is_clear(p: Vector2, r: float) -> bool:
	if not p.is_finite() or p.length() > soft_start - r + CLEAR_EPSILON:
		return false
	if not rocks_near(p, r):
		return true
	for i in _centers.size():
		if p.distance_to(_centers[i]) < _radii[i] + r - CLEAR_EPSILON:
			return false
	return true


## Advances `m` by its velocity over dt for a body of radius `body_r`. Returns the distance
## actually moved, which metabolism charges for.
func move(m: Locomotion.MotionState, body_r: float, dt: float) -> float:
	m.prev_position = m.position
	var r := m.position.length()
	# A body at rest inside the soft wall and clear of rocks stays put: nothing below would move it
	# (plan section 20's fourth remedy, a resting creature costs next to nothing).
	if m.velocity == Vector2.ZERO and r <= soft_start and r <= hard_radius - body_r and not rocks_near(m.position, body_r):
		return 0.0
	var step := m.velocity * dt
	if r > soft_start:
		var n := m.position / r
		var depth := wall_depth(m.position)
		step -= n * maxf(0.0, step.dot(n)) * depth
		step -= n * return_speed * depth * dt
	m.position += step
	settle(m, body_r)
	return m.position.distance_to(m.prev_position)


## Pushes a body of radius `body_r` out of every rock it overlaps and back inside the hard limit,
## removing only the velocity into each. move() ends with this; the sim also calls it after
## separate() pushes bodies apart.
func settle(m: Locomotion.MotionState, body_r: float) -> void:
	# Away from every rock (the grid says so) the passes would change nothing.
	if rocks_near(m.position, body_r):
		for i in ROCK_PASSES:
			for k in _centers.size():
				var center := _centers[k]
				var offset: Vector2 = m.position - center
				var min_dist: float = _radii[k] + body_r
				if absf(offset.x) >= min_dist or absf(offset.y) >= min_dist:
					continue   # clear along one axis, so clear: most rocks, ruled out without a square root
				var dist := offset.length()
				if dist >= min_dist:
					continue
				# Dead centre has no normal; push toward +X so the result stays deterministic.
				var normal := offset / dist if dist > 1e-9 else Vector2.RIGHT
				m.position = center + normal * min_dist
				var inward := m.velocity.dot(normal)
				if inward < 0.0:
					m.velocity -= normal * inward
	var limit := hard_radius - body_r
	var out_r := m.position.length()
	if out_r > limit:
		var n := m.position / out_r
		m.position = n * limit
		var outward := m.velocity.dot(n)
		if outward > 0.0:
			m.velocity -= n * outward


## Line of sight: false when the segment a-b passes within `shrink` times a rock's radius of its
## center. Grazing a rock's edge still sees past it.
func segment_clear(a: Vector2, b: Vector2, shrink: float = SIGHT_SHRINK) -> bool:
	# The distance from each rock's center to the segment, worked out inline (no call per rock).
	var ab := b - a
	var len_sq := ab.length_squared()
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) if rock_grid else -Vector2.INF
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) if rock_grid else Vector2.INF
	for k in _centers.size():
		var p := _centers[k]
		# Outside the segment's box grown by the blocking radius (and GRID_SLACK, so rounding cannot
		# matter), a rock cannot block.
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


## The point to swim at now on the way from `from` to `to` for a body of radius `body_r`: `to`
## itself, or a point beside the first rock in the way, `margin` clear of it. A rock is in the way
## when the straight line would pass within `clearance` of it. `side` 0 goes round on the side the
## line already passes (the short way); +1 forces the side of dir.orthogonal(), -1 the other one, so
## a body that stalls can try the other way.
func route_point(from: Vector2, to: Vector2, body_r: float, clearance: float = ROUTE_CLEARANCE,
		margin: float = ROUTE_MARGIN, side: int = 0) -> Vector2:
	var to_target := to - from
	var length := to_target.length()
	if length < 1e-6:
		return to
	var dir := to_target / length
	var blocking := -1
	var blocking_off := Vector2.ZERO
	var nearest_along := INF
	for k in _centers.size():
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
	# Go round on the side the line already passes, so the detour is the short way.
	var away := -blocking_off.normalized() if blocking_off.length() > 1e-6 else dir.orthogonal()
	if side != 0:
		away = dir.orthogonal() * signf(side)
	return _centers[blocking] + away * (_radii[blocking] + body_r + margin)


## Pushes two overlapping bodies apart along the line between their centers until they just touch.
## The push is split by inverse mass (the heavier body moves less) and changes positions only, so
## velocities, and the closing speed a ram reads, stay those of real swimming. Returns true when
## they overlapped.
static func separate(a: Locomotion.MotionState, ra: float, ma: float, b: Locomotion.MotionState, rb: float, mb: float) -> bool:
	var offset := b.position - a.position
	var dist := offset.length()
	var overlap := ra + rb - dist
	if overlap <= 0.0:
		return false
	# Coincident centers have no line between them; push along +X so the result stays deterministic.
	var normal := offset / dist if dist > 1e-9 else Vector2.RIGHT
	var a_share := mb / (ma + mb) if ma + mb > 0.0 else 0.5
	a.position -= normal * (overlap * a_share)
	b.position += normal * (overlap * (1.0 - a_share))
	return true


## The id of the rock whose surface is nearest a body of radius `r` at `p`, among those within
## `slack` of it; "" when none is. With `facing` given, only rocks whose center lies within
## `max_bearing` of that heading count (a strike checks for a rock ahead). Ties go to the lower id.
func rock_contact(p: Vector2, r: float, slack: float = CONTACT_SLACK, facing: float = NAN, max_bearing: float = PI) -> String:
	var best := ""
	var best_gap := INF
	if not rocks_near(p, r + maxf(slack, 0.0)):
		return best
	for k in _centers.size():
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


## Holds a body inside the disc (center, radius): outside it, the body is put back on the circle
## and only its outward velocity is removed, like the pool's hard limit, so it slides along the
## edge. Returns true when it was outside.
static func clamp_to_disc(m: Locomotion.MotionState, center: Vector2, disc_radius: float) -> bool:
	var offset := m.position - center
	var dist := offset.length()
	if dist <= disc_radius:
		return false
	var n := offset / dist
	m.position = center + n * disc_radius
	var outward := m.velocity.dot(n)
	if outward > 0.0:
		m.velocity -= n * outward
	return true


## False only when the rock grid shows no rock that a body of radius `body_r` at `p` could touch.
## Outside the grid, for a larger body, before any rock or with the grid off, true (the caller then
## checks every rock).
func rocks_near(p: Vector2, body_r: float) -> bool:
	if not rock_grid or _grid_n == 0 or body_r > GRID_BODY_R or not p.is_finite():
		return true
	var gx := floori((p.x + _grid_half) / GRID_CELL_M)
	var gy := floori((p.y + _grid_half) / GRID_CELL_M)
	if gx < 0 or gy < 0 or gx >= _grid_n or gy >= _grid_n:
		return true
	return _grid_near[gy * _grid_n + gx] != 0


## Marks every cell with a point a body of radius GRID_BODY_R could touch the rock from, plus
## GRID_SLACK. The grid covers the pool's disc and a cell beyond, from the first rock on.
func _mark_grid(center: Vector2, rock_radius: float) -> void:
	if _grid_n == 0:
		_grid_half = ceilf(maxf(radius, hard_radius) / GRID_CELL_M + 1.0) * GRID_CELL_M
		_grid_n = roundi(2.0 * _grid_half / GRID_CELL_M)
		_grid_near.resize(_grid_n * _grid_n)
		_grid_near.fill(0)
	var reach := rock_radius + GRID_BODY_R + GRID_SLACK
	for gy in _grid_n:
		var y0 := -_grid_half + gy * GRID_CELL_M
		var dy := maxf(maxf(y0 - center.y, center.y - (y0 + GRID_CELL_M)), 0.0)
		if dy >= reach:
			continue
		for gx in _grid_n:
			var x0 := -_grid_half + gx * GRID_CELL_M
			var dx := maxf(maxf(x0 - center.x, center.x - (x0 + GRID_CELL_M)), 0.0)
			if dx * dx + dy * dy < reach * reach:
				_grid_near[gy * _grid_n + gx] = 1
