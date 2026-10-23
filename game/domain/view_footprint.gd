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
	var quad := corners(look_target, camera, distance, aspect)
	if quad.is_empty():
		return true
	return distance_outside(quad, p) <= margin


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
