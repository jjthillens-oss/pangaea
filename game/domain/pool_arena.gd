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

var radius := 40.0
var soft_start := 36.0
var hard_radius := 39.5
var return_speed := RETURN_SPEED
## [{"id": String, "center": Vector2, "radius": float}]
var rocks: Array[Dictionary] = []


static func create(p_radius: float, p_soft_start: float, p_hard_radius: float, p_return_speed: float = RETURN_SPEED) -> PoolArena:
	var arena := PoolArena.new()
	arena.radius = p_radius
	arena.soft_start = p_soft_start
	arena.hard_radius = p_hard_radius
	arena.return_speed = p_return_speed
	return arena


func add_rock(id: String, center: Vector2, rock_radius: float) -> void:
	rocks.append({"id": id, "center": center, "radius": rock_radius})


## How far into the soft band a point is: 0 inside soft_start, 1 at the hard radius.
func wall_depth(p: Vector2) -> float:
	return clampf((p.length() - soft_start) / (hard_radius - soft_start), 0.0, 1.0)


## True when a circle of radius `r` at `p` lies inside soft_start and touches no rock.
func is_clear(p: Vector2, r: float) -> bool:
	if not p.is_finite() or p.length() > soft_start - r + CLEAR_EPSILON:
		return false
	for rock in rocks:
		if p.distance_to(rock.center) < rock.radius + r - CLEAR_EPSILON:
			return false
	return true


## Advances `m` by its velocity over dt for a body of radius `body_r`. Returns the distance
## actually moved, which metabolism charges for.
func move(m: Locomotion.MotionState, body_r: float, dt: float) -> float:
	m.prev_position = m.position
	var step := m.velocity * dt
	var r := m.position.length()
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
	for i in ROCK_PASSES:
		for rock in rocks:
			var offset: Vector2 = m.position - rock.center
			var dist := offset.length()
			var min_dist: float = rock.radius + body_r
			if dist >= min_dist:
				continue
			# Dead centre has no normal; push toward +X so the result stays deterministic.
			var normal := offset / dist if dist > 1e-9 else Vector2.RIGHT
			m.position = rock.center + normal * min_dist
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
	for rock in rocks:
		if _segment_distance(rock.center, a, b) < rock.radius * shrink:
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
	var blocking := {}
	var nearest_along := INF
	for rock in rocks:
		var c: Vector2 = rock.center - from
		var along := c.dot(dir)
		if along <= 0.0 or along >= length + rock.radius:
			continue
		var off := c - dir * along
		if off.length() < rock.radius + body_r + clearance and along < nearest_along:
			nearest_along = along
			blocking = {"center": rock.center, "radius": rock.radius, "off": off}
	if blocking.is_empty():
		return to
	# Go round on the side the line already passes, so the detour is the short way.
	var off: Vector2 = blocking.off
	var away := -off.normalized() if off.length() > 1e-6 else dir.orthogonal()
	if side != 0:
		away = dir.orthogonal() * signf(side)
	return blocking.center + away * (blocking.radius + body_r + margin)


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
	for rock in rocks:
		var gap: float = p.distance_to(rock.center) - rock.radius - r
		if gap > slack:
			continue
		if is_finite(facing) and absf(angle_difference(facing, (rock.center - p).angle())) > max_bearing:
			continue
		if gap < best_gap or (gap == best_gap and str(rock.id) < best):
			best_gap = gap
			best = rock.id
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


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
