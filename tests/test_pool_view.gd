extends TestCase
## The pool's presentation pieces that need no running scene: the camera's fixed view and zoom,
## refusal hints (when a refused meal is worth telling the player), the meal label and the food
## views' drawn transforms. The running pool itself is covered by the scene smoke.

const CAMERA_SETTINGS := {"pitch_deg": 55.0, "fov_deg": 45.0, "distance": 14.0, "zoom_min": 10.0,
	"zoom_max": 20.0, "zoom_step": 2.0, "follow_half_life_s": 0.12, "look_ahead_s": 0.35, "look_ahead_max": 2.5}


func _camera() -> PoolCamera:
	var camera := PoolCamera.new()
	camera.configure(CAMERA_SETTINGS)
	return camera


func test_the_camera_looks_north_down_at_the_set_pitch_and_distance() -> void:
	var camera := _camera()
	var target := Vector3(5.0, 0.0, -3.0)
	camera.snap_to(target)
	check_near(camera.pitch_degrees(), 55.0, 1e-4, "pitch")
	check_near(camera.rotation.y, 0.0, 1e-9, "no yaw: screen up is north")
	check_near(camera.rotation.z, 0.0, 1e-9, "no roll")
	check_near(camera.fov, 45.0, 1e-6, "vertical field of view")
	check_near(camera.position.distance_to(target), 14.0, 1e-4, "distance")
	var looking := -camera.basis.z
	check(looking.is_equal_approx((target - camera.position).normalized()), "looking at the target")
	camera.free()


func test_the_wheel_zoom_steps_within_its_limits() -> void:
	var camera := _camera()
	camera.zoom_by(-1)
	check_near(camera.distance, 12.0, 1e-6, "one step in")
	camera.zoom_by(-5)
	check_near(camera.distance, 10.0, 1e-6, "no closer than zoom_min")
	camera.zoom_by(9)
	check_near(camera.distance, 20.0, 1e-6, "no further than zoom_max")
	for i in 15:
		camera.follow(Vector3.ZERO, Vector2.ZERO, 1.0 / 60.0)
	check(camera.position.length() > 19.4, "the view is nine tenths of the way after a quarter second")
	for i in 45:
		camera.follow(Vector3.ZERO, Vector2.ZERO, 1.0 / 60.0)
	check_near(camera.position.length(), 20.0, 0.01, "and settled after a second")
	camera.free()


func test_the_camera_follows_with_a_capped_look_ahead() -> void:
	var camera := _camera()
	camera.snap_to(Vector3.ZERO)
	for i in 120:
		camera.follow(Vector3.ZERO, Vector2(3.0, 0.0), 1.0 / 60.0)
	check_near(camera.focus.x, 3.0 * 0.35, 0.01, "looks ahead along the motion")
	for i in 120:
		camera.follow(Vector3.ZERO, Vector2(0.0, 40.0), 1.0 / 60.0)
	check_near(camera.focus.z, 2.5, 0.01, "look-ahead is capped")
	check_near(camera.focus.x, 0.0, 0.01, "and follows the new direction")
	camera.free()


func test_diet_hints_show_only_while_touching_and_at_most_every_four_seconds() -> void:
	var hints := RefusalHints.new()
	var event := {"reason": "needs a jaw", "touching": false, "contact_s": 0.0}
	check_eq(hints.consider(event, 1.0), "", "not touching")
	event.touching = true
	check_eq(hints.consider(event, 1.2), "Needs a jaw: your filter mouth only eats plankton", "touching")
	check_eq(hints.consider(event, 3.0), "", "again too soon")
	check(hints.consider(event, 5.3) != "", "after four seconds")
	check(RefusalHints.is_diet("needs a filter mouth") and not RefusalHints.is_diet("not hungry"), "diet reasons")


func test_facing_and_full_hints_follow_their_own_rules() -> void:
	var hints := RefusalHints.new()
	var facing := {"reason": "mouth is not facing it", "touching": true, "contact_s": 0.2}
	check_eq(hints.consider(facing, 1.0), "", "touching for less than half a second")
	facing.contact_s = 0.5
	check_eq(hints.consider(facing, 1.3), "Turn your mouth toward it", "after half a second")
	var full := {"reason": "not hungry", "touching": true, "contact_s": 0.0}
	check_eq(hints.consider(full, 2.0), "Full", "full")
	check_eq(hints.consider(full, 6.9), "", "within five seconds")
	check_eq(hints.consider(full, 7.0), "Full", "after five seconds")
	check_eq(hints.consider({"reason": "too big to bite", "touching": true}, 8.0), "too big to bite", "unknown reasons as given")
	hints.reset()
	check_eq(hints.consider(full, 7.5), "Full", "reset forgets")


func test_the_meal_label_names_energy_and_points() -> void:
	check_eq(FeedbackFx.meal_text({"absorbed": 8.0, "points": 1}), "+8 energy · +1", "plankton")
	check_eq(FeedbackFx.meal_text({"absorbed": 17.54, "points": 3}), "+18 energy · +3", "rounded")
	check_eq(FeedbackFx.meal_text({"absorbed": 4.0, "points": 0}), "+4 energy", "no points")


func test_food_views_draw_items_on_the_swim_plane_and_shrink_rotting_carrion() -> void:
	var plants := FoodView.new()
	plants.kind = "plant"
	var start := {"id": "pk_1", "position": Vector2(2.0, -3.0), "phase": Vector2(0.4, 1.1), "born_tick": 0}
	var t := plants._transform_for(start, 10.0)
	check_near(t.origin.x, 2.0, 1e-6, "plankton x")
	check_near(t.origin.z, -3.0, 1e-6, "plankton z")
	check(absf(t.origin.y) <= FoodView.PLANT_BOB_M + 1e-6, "plankton bobs within its amplitude")
	check_near(t.basis.get_scale().x, 1.0, 1e-5, "starting plankton is full size")
	var regrown := {"id": "pk_9", "position": Vector2.ZERO, "phase": Vector2.ZERO, "born_tick": 600}
	check(plants._transform_for(regrown, 10.1).basis.get_scale().x < 0.5, "new plankton grows in")
	plants.free()
	var meat := FoodView.new()
	meat.kind = "meat"
	var fresh := {"id": "cr_1", "position": Vector2(1.5, 4.0), "age": 3.0, "lifetime": 90.0}
	var rotting := {"id": "cr_1", "position": Vector2(1.5, 4.0), "age": 85.0, "lifetime": 90.0}
	check_near(meat._transform_for(fresh, 0.0).basis.get_scale().x, 1.0, 1e-5, "fresh carrion is full size")
	check_near(meat._transform_for(rotting, 0.0).basis.get_scale().x, 0.5, 1e-5, "half size five seconds before rotting")
	check(meat._transform_for(fresh, 0.0).origin.is_equal_approx(meat._transform_for(fresh, 7.0).origin), "carrion lies still")
	meat.free()
