class_name PoolCamera
extends Camera3D
## The pool camera (M1 step 2): a fixed north-up view at a fixed pitch that follows the cell with a
## little look-ahead along its motion, and zooms with the wheel. Screen up is always north
## (plane -y), so the swim keys match the screen. No shake, roll or FOV kick, so there is nothing
## to turn off for reduced motion. Settings come from the layout's "camera" block.

const ZOOM_HALF_LIFE_S := 0.06   ## a zoom step settles in about 0.25 s
const NEAR_M := 0.1
const FAR_M := 200.0

var pitch_deg := 55.0
var distance := 14.0             ## the zoom distance asked for; the view eases toward it
var zoom_min := 10.0
var zoom_max := 20.0
var zoom_step := 2.0
var follow_half_life_s := 0.12
var look_ahead_s := 0.35
var look_ahead_max := 2.5
## The point on the swim plane the camera looks at.
var focus := Vector3.ZERO

var _shown_distance := 14.0


## settings: PoolLayout.camera.
func configure(settings: Dictionary) -> void:
	pitch_deg = settings.get("pitch_deg", pitch_deg)
	fov = settings.get("fov_deg", fov)
	zoom_min = settings.get("zoom_min", zoom_min)
	zoom_max = settings.get("zoom_max", zoom_max)
	zoom_step = settings.get("zoom_step", zoom_step)
	distance = clampf(settings.get("distance", distance), zoom_min, zoom_max)
	follow_half_life_s = settings.get("follow_half_life_s", follow_half_life_s)
	look_ahead_s = settings.get("look_ahead_s", look_ahead_s)
	look_ahead_max = settings.get("look_ahead_max", look_ahead_max)
	near = NEAR_M
	far = FAR_M
	_shown_distance = distance
	_place()


## Jumps straight to a target with no easing (start, respawn, teleport).
func snap_to(target: Vector3) -> void:
	focus = target
	_shown_distance = distance
	_place()


## A rebase moved the world by `delta` (S1): moves the focus and the camera with it, keeping the zoom
## easing and the follow lag, so nothing on screen jumps. Respawns and teleports snap_to instead.
func shift_focus(delta: Vector3) -> void:
	focus += delta
	_place()


## Eases toward `target` plus a look-ahead along `velocity` (plane m/s), capped at look_ahead_max.
func follow(target: Vector3, velocity: Vector2, delta: float) -> void:
	var ahead := (velocity * look_ahead_s).limit_length(look_ahead_max)
	var goal := target + PlaneSpace.to_world(ahead, 0.0)
	focus = goal.lerp(focus, pow(0.5, delta / follow_half_life_s))
	_shown_distance = lerpf(distance, _shown_distance, pow(0.5, delta / ZOOM_HALF_LIFE_S))
	_place()


## Steps the zoom: negative steps move closer, positive ones further away.
func zoom_by(steps: int) -> void:
	distance = clampf(distance + steps * zoom_step, zoom_min, zoom_max)


## The current downward pitch in degrees (55 means looking 55 degrees below the horizon).
func pitch_degrees() -> float:
	return -rad_to_deg(rotation.x)


func _place() -> void:
	var pitch := deg_to_rad(pitch_deg)
	rotation = Vector3(-pitch, 0.0, 0.0)
	position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * _shown_distance
