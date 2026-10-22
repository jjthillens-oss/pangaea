class_name PoolArena
extends RefCounted
## The pool's walls and rocks on the movement plane (M1 step 2). Moves a swimmer by its velocity
## and keeps it out of rocks and inside the pool. No physics bodies.
##
## Soft wall: past soft_start, outward swimming fades with depth into the band and a gentle return
## current pulls the cell back, so the edge is felt rather than hit. Rocks push out along their
## normal and remove only the inward velocity, so the cell slides. A hard limit is the failsafe.

const RETURN_SPEED := 1.0   ## m/s at full depth into the soft band
const ROCK_PASSES := 2      ## pushing out of one rock can push into another; two passes settle it
## Overlap is_clear forgives. Pushing out of a rock lands within float32 rounding of its surface
## (a few micrometres either side at pool distances), so this is above that and far below 1 mm.
const CLEAR_EPSILON := 1e-4

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
	return m.position.distance_to(m.prev_position)
