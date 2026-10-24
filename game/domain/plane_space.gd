class_name PlaneSpace
extends RefCounted
## The one mapping between the movement plane and the 3D world (M1 step 2, PROPOSED convention).
##
## Plane Vector2(x, y) is world (x, SWIM_Y, y), so plane +y is world +Z: screen-down under the
## north-up camera. Heading 0 faces +X (east), as in InteractionResolver. Positive part angles lie
## on the cell's right (clockwise seen from above). Models face -Z.

const SWIM_Y := 0.0


static func to_world(p: Vector2, y: float = SWIM_Y) -> Vector3:
	return Vector3(p.x, y, p.y)


static func to_plane(w: Vector3) -> Vector2:
	return Vector2(w.x, w.z)


## Rotation about world up that turns a model facing -Z toward `heading`.
static func yaw_for_heading(heading: float) -> float:
	return -heading - PI / 2.0


## Direction of a part at `angle` in the model's own frame (front is -Z, +PI/2 is +X).
static func part_local_dir(angle: float) -> Vector3:
	return Vector3(sin(angle), 0.0, -cos(angle))


## The save's three-number player position.
static func to_save(p: Vector2) -> Array:
	return [p.x, SWIM_Y, p.y]


## Vector2.INF unless `a` holds three finite numbers.
static func from_save(a: Array) -> Vector2:
	if a.size() != 3:
		return Vector2.INF
	for value in a:
		if not (value is float or value is int) or not is_finite(value):
			return Vector2.INF
	return Vector2(float(a[0]), float(a[2]))


## The endless save's three-number position: absolute am at the current size, float64, y = SWIM_Y.
## Never routed through a Vector2, which is float32 and would cost 3.9 mm at 100 km. Pool saves
## keep to_save and from_save, with their float32 meaning.
static func to_save_abs(x_am: float, y_am: float) -> Array:
	return [x_am, SWIM_Y, y_am]


## [x, z] as float64, exactly as given; empty unless `a` is an Array of three finite numbers.
## JSON gives every number as a float; an int (a hand-written file, a test) is taken as its value.
static func from_save_abs(a: Variant) -> PackedFloat64Array:
	if not (a is Array) or a.size() != 3:
		return PackedFloat64Array()
	for value in a:
		if not (value is float or value is int) or not is_finite(float(value)):
			return PackedFloat64Array()
	return PackedFloat64Array([float(a[0]), float(a[2])])


## Where a ray meets the swim plane, as a plane point, or null when it runs parallel to the plane
## or points away from it.
static func ray_to_plane(origin: Vector3, dir: Vector3, y: float = SWIM_Y) -> Variant:
	if absf(dir.y) < 1e-6:
		return null
	var t := (y - origin.y) / dir.y
	if t < 0.0:
		return null
	return to_plane(origin + dir * t)
