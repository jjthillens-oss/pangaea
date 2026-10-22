extends TestCase
## Player input becomes the same SimIntent the dev bot gives: swim keys by physical position,
## or swimming toward the cursor's point on the plane. Keys win, the GUI never starts a swim,
## and pausing lets go of everything. Key names come from the bindings, safely headless.

const MOVE_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]


func after_each() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _mouse(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func test_the_pointer_gives_no_thrust_close_to_the_cell() -> void:
	# Vector2 holds 32-bit floats, so the test stays just inside the 0.3 m edge.
	for d in [0.0, 0.1, 0.29, SwimInput.POINTER_DEAD_M - 1e-4]:
		check_eq(SwimInput.pointer_move(Vector2.ZERO, Vector2(d, 0.0)), Vector2.ZERO, "at %.2f m" % d)


func test_the_pointer_gives_full_thrust_from_two_and_a_half_meters() -> void:
	for d in [SwimInput.POINTER_FULL_M, 3.0, 40.0]:
		check_near(SwimInput.pointer_move(Vector2.ZERO, Vector2(0.0, -d)).length(), 1.0, 1e-6, "at %.1f m" % d)
	var halfway := (SwimInput.POINTER_DEAD_M + SwimInput.POINTER_FULL_M) / 2.0
	check_near(SwimInput.pointer_move(Vector2.ZERO, Vector2(halfway, 0.0)).length(), 0.5, 1e-6, "ramps in between")


func test_the_pointer_direction_is_exact() -> void:
	var cell := Vector2(-3.0, 7.0)
	for target in [Vector2(5.0, 2.0), Vector2(-9.0, 7.5), Vector2(-3.0, -1.0), Vector2(-1.0, 8.0)]:
		var move := SwimInput.pointer_move(cell, target)
		check_near(angle_difference(move.angle(), (target - cell).angle()), 0.0, 1e-6, "toward %s" % target)


func test_the_cursor_ray_meets_the_plane_or_reports_none() -> void:
	var hit = PlaneSpace.ray_to_plane(Vector3(2.0, 11.5, 8.0), Vector3(0.0, -sin(deg_to_rad(55.0)), -cos(deg_to_rad(55.0))))
	check(hit is Vector2, "a ray down the camera's view hits the plane")
	if hit is Vector2:
		check(hit.is_equal_approx(Vector2(2.0, 8.0 - 11.5 / tan(deg_to_rad(55.0)))), "hit point %s" % hit)
	check(PlaneSpace.ray_to_plane(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 0.0, -1.0)) == null, "a parallel ray")


func test_a_held_key_wins_over_the_pointer() -> void:
	check_eq(SwimInput.combine(Vector2(0.0, -1.0), Vector2(1.0, 0.0)), Vector2(0.0, -1.0), "keys")
	check_eq(SwimInput.combine(Vector2.ZERO, Vector2(1.0, 0.0)), Vector2(1.0, 0.0), "pointer when no key")
	check_eq(SwimInput.combine(Vector2.ZERO, Vector2.ZERO), Vector2.ZERO, "nothing")


func test_swim_keys_give_a_screen_direction_intent() -> void:
	var input := SwimInput.new()
	Input.action_press("move_right")
	check_eq(input.next_intent(null).move, Vector2(1.0, 0.0), "right is plane +x")
	Input.action_release("move_right")
	Input.action_press("move_up")
	check_eq(input.next_intent(null).move, Vector2(0.0, -1.0), "up is north, plane -y")
	input.release_all()
	check_eq(input.next_intent(null).move, Vector2.ZERO, "release_all lets go of the keys")
	input.free()


func test_only_an_unclaimed_press_starts_the_pointer_swim_and_any_release_stops_it() -> void:
	var input := SwimInput.new()
	input._input(_mouse(true))
	check(not input.pointer_held, "a press seen before the GUI does not start a swim")
	input._unhandled_input(_mouse(true))
	check(input.pointer_held, "a press the GUI did not take starts it")
	input._input(_mouse(false))
	check(not input.pointer_held, "the release stops it")
	input._unhandled_input(_mouse(true))
	input.release_all()
	check(not input.pointer_held, "release_all stops it; the button must be pressed again")
	check(input.pointer_target == null, "and forgets the target")
	input.free()


func test_swim_actions_are_bound_by_physical_key() -> void:
	for action in MOVE_ACTIONS:
		var keys := 0
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys += 1
				check(event.physical_keycode != KEY_NONE and event.keycode == KEY_NONE, "%s binds a physical key" % action)
		check(keys >= 2, "%s has a letter and an arrow key" % action)


func test_key_labels_name_the_physical_keys_headless() -> void:
	check_eq(KeyLabel.for_action("move_up"), "W", "move_up")
	check_eq(KeyLabel.for_action("move_left"), "A", "move_left")
	check_eq(KeyLabel.all_for_action("move_up"), PackedStringArray(["W", "Up"]), "both keys")
	check_eq(KeyLabel.all_for_action("swim_to_cursor"), PackedStringArray(["Left mouse"]), "mouse button")
	check_eq(KeyLabel.all_for_action("pause"), PackedStringArray(["Escape", "P"]), "pause keys")
	check_eq(KeyLabel.for_action("swim_to_cursor"), "", "no key bound")
	check_eq(KeyLabel.for_action("no_such_action"), "", "unknown action")
	for action in MOVE_ACTIONS:
		check(not KeyLabel.for_action(action).contains("Physical"), "%s label is a plain key name" % action)
