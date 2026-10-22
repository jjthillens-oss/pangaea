class_name PartPlacement
extends RefCounted
## Where a genome part sits on the cell body (M1 step 2). Pure math, no nodes.
##
## The body is an ellipsoid with the sample cell's socket radii. A part at `angle` (0 = front,
## +PI/2 = the cell's right, as in PlaneSpace) sits on that surface, and its -Z axis follows the
## outward surface normal. Part models have their origin at the attachment point and extend
## along -Z, so this transform is all they need.

const RX := 0.46   ## half width: socket_side_R
const RY := 0.39   ## half height: socket_top
const RZ := 0.5    ## half length: socket_mouth and socket_tail
## Parts that sit up on the body instead of on its equator, by type: height above the swim plane.
## The eye spot sits on the head, above the sample cell's baked eyes (their tops are at y 0.26),
## so at any angle it clears them instead of growing out of one.
const RAISED_Y := {"eye_spot": 0.30}


## Height of a part type's attachment point above the swim plane.
static func height_for(type: String) -> float:
	return float(RAISED_Y.get(type, 0.0))


## The point on the body surface at `angle` and height `y`: the horizontal semi-axes shrink with
## height, as on any ellipsoid.
static func surface_point(angle: float, y: float = 0.0) -> Vector3:
	var shrink := sqrt(maxf(0.0, 1.0 - (y / RY) * (y / RY)))
	return Vector3(RX * shrink * sin(angle), y, -RZ * shrink * cos(angle))


## Outward unit normal of the body surface at a point on it.
static func outward_normal(p: Vector3) -> Vector3:
	return Vector3(p.x / (RX * RX), p.y / (RY * RY), p.z / (RZ * RZ)).normalized()


## The local transform of a part in the cell model's frame: origin on the surface, -Z outward,
## up as close to the cell's up as the normal allows, then the genome's uniform scale.
static func transform_for(angle: float, type: String, scale: float = 1.0) -> Transform3D:
	var p := surface_point(angle, height_for(type))
	var basis := Basis.looking_at(outward_normal(p), Vector3.UP)
	return Transform3D(basis.scaled(Vector3.ONE * scale), p)
