class_name CreatureSenses
extends RefCounted
## What a creature can perceive (M1 step 3). Pure: it gets the viewer, a list of bodies and the
## arena, and returns percepts, so a creature's brain only ever sees what these senses let through,
## never the world's tables or the player's live state.
##
## Senses, checked in this order for each body:
## - near: within both radii plus `near`, whatever the direction and rocks (touch, a lateral line);
## - sight: within `sight` plus the body's radius, inside the field of view (edges included), with
##   a line of sight that passes no rock (grazing a rock's edge still sees, PoolArena.segment_clear).
## Food is found by range and field of view only: it does not hide or flee, and routing goes round
## rocks anyway.
##
## Viewer: {"id", "species", "position", "heading", "radius", "sight", "fov", "near"}, with `fov` the
## whole field of view in radians and `sight` and `near` in metres.
## Bodies: [{"id", "species", "position", "velocity", "radius", "alive", "concealed", "engageable",
## "bite", "spikes"}], the start-of-tick snapshot the sim builds once, before anything moves.

## Positions are 32-bit floats, so a body placed exactly on the edge of the field of view comes back
## a hair to either side; this much past the edge still counts as on it.
const FOV_EPSILON := 1e-5


## Every body the viewer senses, nearest first (ties by id), as fresh percepts: {"id", "species",
## "position", "velocity", "radius", "distance", "bearing", "by": "near"|"sight", "engageable",
## "bite": bool, "spikes": int}. Skips the viewer itself, dead bodies and concealed bodies.
static func perceive(viewer: Dictionary, bodies: Array, arena: PoolArena) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from: Vector2 = viewer.position
	var viewer_r: float = viewer.radius
	var sight: float = viewer.sight
	var half_fov: float = float(viewer.fov) / 2.0
	var near: float = viewer.near
	for body in bodies:
		if body.id == viewer.id or not bool(body.get("alive", true)) or bool(body.get("concealed", false)):
			continue
		var at: Vector2 = body.position
		var r: float = body.radius
		var d := from.distance_to(at)
		var b := bearing(viewer, at)
		var by := ""
		if d <= viewer_r + r + near:
			by = "near"
		elif d <= sight + r and absf(b) <= half_fov + FOV_EPSILON and (arena == null or arena.segment_clear(from, at)):
			by = "sight"
		if by.is_empty():
			continue
		out.append({
			"id": str(body.id), "species": str(body.species), "position": at, "velocity": Vector2(body.velocity),
			"radius": r, "distance": d, "bearing": b, "by": by, "engageable": bool(body.get("engageable", true)),
			"bite": bool(body.get("bite", false)), "spikes": int(body.get("spikes", 0)),
		})
	out.sort_custom(_nearer)
	return out


## The food items of the given kinds (diets) in range and in the field of view, nearest first (ties
## by id): {"id", "kind", "position", "radius", "distance", "bearing"}. No line of sight.
static func perceive_food(viewer: Dictionary, items: Array, kinds: PackedStringArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from: Vector2 = viewer.position
	var sight: float = viewer.sight
	var half_fov: float = float(viewer.fov) / 2.0
	for item in items:
		if not kinds.has(str(item.kind)):
			continue
		var at: Vector2 = item.position
		var r: float = item.radius
		var d := from.distance_to(at)
		var b := bearing(viewer, at)
		if d <= sight + r and absf(b) <= half_fov + FOV_EPSILON:
			out.append({"id": str(item.id), "kind": str(item.kind), "position": at, "radius": r, "distance": d, "bearing": b})
	out.sort_custom(_nearer)
	return out


## The angle from the viewer's heading to `p`, in -PI..PI (positive is clockwise seen from above,
## the viewer's right).
static func bearing(viewer: Dictionary, p: Vector2) -> float:
	var from: Vector2 = viewer.position
	return angle_difference(float(viewer.heading), (p - from).angle())


## Nearest first; equal distances go to the lower id, because sort_custom is not stable.
static func _nearer(a: Dictionary, b: Dictionary) -> bool:
	if a.distance != b.distance:
		return a.distance < b.distance
	return a.id < b.id
