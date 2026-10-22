class_name SwimInput
extends Node
## Player input for the pool (M1 step 2): the swim keys, or holding the swim button to swim toward
## the cursor, become one SimIntent per tick. It has the same next_intent(sim) as the dev
## ForageBot, so the pool steps the sim the same way for both. It never changes the sim.
##
## Rules: a held swim key wins over the mouse. Swimming to the cursor starts only on a press the
## GUI did not take, so clicking a button never starts a swim, and stops on release.
## release_all() (pause, dialogs, focus loss) clears everything held; the mouse must then be
## pressed again. Eating is automatic on contact, so there is no eat key.

const POINTER_DEAD_M := 0.3   ## closer than this to the cursor point: no thrust
const POINTER_FULL_M := 2.5   ## this far or further: full thrust
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const POINTER_ACTION := &"swim_to_cursor"

## Used to find the cursor's point on the swim plane.
@export var camera: Camera3D

## True from a press of the swim button (that the GUI did not take) until its release.
var pointer_held := false
## The plane point under the cursor while swimming toward it, else null. For the target ring.
var pointer_target: Variant = null


## Thrust toward a plane point: zero within POINTER_DEAD_M, ramping to full at POINTER_FULL_M.
static func pointer_move(cell_pos: Vector2, target: Vector2) -> Vector2:
	var to := target - cell_pos
	var d := to.length()
	if d <= POINTER_DEAD_M:
		return Vector2.ZERO
	return to / d * clampf((d - POINTER_DEAD_M) / (POINTER_FULL_M - POINTER_DEAD_M), 0.0, 1.0)


## Keys win over the pointer whenever any swim key is held.
static func combine(keys: Vector2, pointer: Vector2) -> Vector2:
	return keys if not keys.is_zero_approx() else pointer


func next_intent(sim: PoolSim) -> SimIntent:
	var keys := Input.get_vector(MOVE_ACTIONS[0], MOVE_ACTIONS[1], MOVE_ACTIONS[2], MOVE_ACTIONS[3])
	pointer_target = null
	var pointer := Vector2.ZERO
	if pointer_held and keys.is_zero_approx():
		pointer_target = cursor_on_plane()
		if pointer_target is Vector2:
			pointer = pointer_move(sim.motion.position, pointer_target)
	return SimIntent.new(combine(keys, pointer))


## The swim-plane point under the mouse cursor, or null.
func cursor_on_plane() -> Variant:
	if camera == null or not camera.is_inside_tree():
		return null
	var m := camera.get_viewport().get_mouse_position()
	return PlaneSpace.ray_to_plane(camera.project_ray_origin(m), camera.project_ray_normal(m))


## Clears every held input: the pointer swim and the swim keys.
func release_all() -> void:
	pointer_held = false
	pointer_target = null
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(POINTER_ACTION):
		pointer_held = true
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Releases are watched before the GUI, so letting go over a button still stops the swim.
func _input(event: InputEvent) -> void:
	if event.is_action_released(POINTER_ACTION):
		pointer_held = false
		pointer_target = null
