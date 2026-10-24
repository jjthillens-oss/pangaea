class_name ViewFootprint
extends RefCounted
## What the pool camera shows of the swim plane (M1 step 3): the trapezoid where the north-up
## camera's view meets the plane, from its pitch, vertical field of view, zoom distance and the
## screen's aspect. Pure, so the spawner can keep new creatures out of sight without a camera node;
## a scene test checks it against the real Camera3D.
##
## The camera (PoolCamera) looks at a target on the plane from `distance` away, `pitch_deg` below
## the horizon and facing north (plane -y), with `fov_deg` the vertical field of view (Godot's
## default, keep height). The screen's top edge meets the plane north of the target and the bottom
## edge south of it, so the trapezoid is wider at the far (north) end.
##
## A margin grows it by a disc: contains() is true within `margin` of the trapezoid. The spawner's
## margin covers the camera's look-ahead, a safety gap and the creature's radius.


## How many cameras _shape keeps (a free zoom could ask for any number of distances).
const _SHAPES_MAX := 16

## quad_contains_boxed answers from the boxes only this far inside or outside them: far more than the
## float32 corners and the edge tests round by.
const BOX_SLACK := 1e-3

## [pitch_deg, fov_deg, distance, aspect] -> _shape's answer: the trig is the same wherever the
## camera looks, and the sim asks for the same few views every tick.
static var _shapes := {}


## The trapezoid's corners for a camera looking at `look_target`: far-left, far-right, near-right,
## near-left (north is -y, east +x). Empty when the screen's top edge would not meet the plane (a
## pitch no steeper than half the field of view), where the view has no far end.
static func corners(look_target: Vector2, camera: Dictionary, distance: float, aspect: float) -> PackedVector2Array:
	var key := [float(camera.pitch_deg), float(camera.fov_deg), distance, aspect]
	var k: PackedFloat64Array = _shapes.get(key, PackedFloat64Array())
	if k.is_empty():
		k = _shape(float(camera.pitch_deg), float(camera.fov_deg), distance, aspect)
		if _shapes.size() >= _SHAPES_MAX:
			_shapes.clear()
		_shapes[key] = k
	if k.size() == 1:
		return PackedVector2Array()
	var far_y := look_target.y + k[0] - k[1]
	var near_y := look_target.y + k[0] - k[3]
	return PackedVector2Array([Vector2(look_target.x - k[2], far_y), Vector2(look_target.x + k[2], far_y),
		Vector2(look_target.x + k[4], near_y), Vector2(look_target.x - k[4], near_y)])


## The trapezoid's shape, the float64 terms corners() adds to the look target: [back, far edge's
## reach term, far half width, near edge's reach term, near half width], or [0.0] when the view has
## no far end.
static func _shape(pitch_deg: float, fov_deg: float, distance: float, aspect: float) -> PackedFloat64Array:
	var pitch := deg_to_rad(pitch_deg)
	var t := tan(deg_to_rad(fov_deg) / 2.0)
	var height := distance * sin(pitch)
	var back := distance * cos(pitch)    # the camera sits this far south of its target
	var out := PackedFloat64Array([back])
	for edge: float in [1.0, -1.0]:   # the screen's top (far) edge, then its bottom (near) edge
		var down := sin(pitch) - edge * t * cos(pitch)
		if down <= 1e-6:
			return PackedFloat64Array([0.0])
		var reach := height / down             # along the ray from the camera to the plane
		out.append(reach * (cos(pitch) + edge * t * sin(pitch)))
		out.append(reach * t * aspect)
	return out


## True when `p` lies in the camera's view of the plane, or within `margin` of it. A view with no
## far end contains everything, so a caller keeping things out of sight stays safe.
static func contains(look_target: Vector2, p: Vector2, camera: Dictionary, distance: float, aspect: float, margin: float = 0.0) -> bool:
	return quad_contains(corners(look_target, camera, distance, aspect), p, margin)


## contains() on corners() already made: a caller testing many points against one view makes the
## corners once.
static func quad_contains(quad: PackedVector2Array, p: Vector2, margin: float = 0.0) -> bool:
	return quad.is_empty() or distance_outside(quad, p) <= margin


## For quad_contains_boxed: the box a corners() trapezoid spans and the box of its narrower end's
## width over its whole depth (inside it, as the trapezoid is convex with level ends), as
## [outer lo x, outer hi x, inner lo x, inner hi x, far y, near y]; empty for an empty quad.
static func boxes(quad: PackedVector2Array) -> PackedFloat64Array:
	if quad.size() != 4:
		return PackedFloat64Array()
	return PackedFloat64Array([minf(quad[0].x, quad[3].x), maxf(quad[1].x, quad[2].x),
		maxf(quad[0].x, quad[3].x), minf(quad[1].x, quad[2].x),
		maxf(quad[0].y, quad[1].y), minf(quad[2].y, quad[3].y)])


## quad_contains(quad, p, margin), answered from boxes(quad) when `p` lies clearly inside the inner
## box (in the view: true for a margin of 0 or more) or clearly further than `margin` outside the
## outer one (false); "clearly" is by BOX_SLACK. Otherwise, and for an empty quad, quad_contains itself.
static func quad_contains_boxed(quad: PackedVector2Array, box: PackedFloat64Array, p: Vector2, margin: float = 0.0) -> bool:
	if box.size() == 6:
		var x := p.x
		var y := p.y
		if margin >= 0.0 and x > box[2] + BOX_SLACK and x < box[3] - BOX_SLACK and y > box[4] + BOX_SLACK \
				and y < box[5] - BOX_SLACK:
			return true
		var out := margin + BOX_SLACK
		if x < box[0] - out or x > box[1] + out or y < box[4] - out or y > box[5] + out:
			return false
	return quad_contains(quad, p, margin)


## How far `p` lies outside the convex polygon `quad` (clockwise on screen, as corners() gives it):
## 0 inside or on an edge, else the distance to the nearest edge.
static func distance_outside(quad: PackedVector2Array, p: Vector2) -> float:
	var inside := true
	for i in quad.size():
		var a := quad[i]
		var b := quad[(i + 1) % quad.size()]
		# Clockwise on screen (y down) puts the inside on each edge's right: cross(b - a, p - a) >= 0.
		if (b - a).cross(p - a) < 0.0:
			inside = false
			break
	if inside:
		return 0.0
	var nearest := INF
	for i in quad.size():
		var a := quad[i]
		var b := quad[(i + 1) % quad.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab.length_squared() > 0.0 else 0.0
		nearest = minf(nearest, p.distance_to(a + ab * t))
	return nearest
