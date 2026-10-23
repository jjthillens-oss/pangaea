extends RefCounted
## Test helper (not a test file): where the pool camera's view lands on a level plane, from the
## layout's camera block (pitch_deg, fov_deg) at a zoom distance. The rim's shelf (test_assets.gd)
## and the fluid's Backdrop (test_pool_look.gd) must both cover what the widest view shows.
##
##     const ViewReach := preload("res://tests/view_reach.gd")

## The screen shape the pool view is planned for (1080p)...
const SCREEN_ASPECT := 16.0 / 9.0
## ...and the widest window checked (21:9). The camera keeps its vertical field of view.
const WIDE_ASPECT := 21.0 / 9.0


## How far from the camera's focus the top screen corners reach on a level plane `height` above
## the swim plane, with the camera's pitch and vertical FOV at `distance`. INF when the corner looks
## at or above the horizon.
static func corner_reach(camera: Dictionary, distance: float, height: float, aspect := SCREEN_ASPECT) -> float:
	var hit := _corner_hit(camera, distance, height, aspect)
	return INF if hit == Vector3.INF else Vector2(hit.x, hit.z).length()


## How far that corner's point lies from the camera itself (m). INF as corner_reach.
static func corner_slant(camera: Dictionary, distance: float, height: float, aspect := SCREEN_ASPECT) -> float:
	var hit := _corner_hit(camera, distance, height, aspect)
	return INF if hit == Vector3.INF else hit.distance_to(_eye(camera, distance))


static func _eye(camera: Dictionary, distance: float) -> Vector3:
	var pitch := deg_to_rad(float(camera.get("pitch_deg", 0.0)))
	return Vector3(0.0, sin(pitch), cos(pitch)) * distance


## The top corner ray's point on the plane, relative to the focus, or Vector3.INF.
static func _corner_hit(camera: Dictionary, distance: float, height: float, aspect: float) -> Vector3:
	var pitch := deg_to_rad(float(camera.get("pitch_deg", 0.0)))
	var half_fov := deg_to_rad(float(camera.get("fov_deg", 0.0))) / 2.0
	var eye := _eye(camera, distance)
	var ray := Basis(Vector3.RIGHT, -pitch) * Vector3(tan(half_fov) * aspect, tan(half_fov), -1.0)
	if ray.y >= 0.0:
		return Vector3.INF
	return eye + ray * ((height - eye.y) / ray.y)
