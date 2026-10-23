extends TestCase
## Direct presentation rules that do not need a renderer or an active world simulation.


func test_camera_zoom_stops_at_near_limit() -> void:
	var camera := PoolCamera.new()
	camera.configure({"zoom_min": 8.0, "zoom_max": 16.0, "distance": 12.0, "zoom_step": 2.0})
	camera.zoom_by(-100)
	check_eq(camera.distance, 8.0, "zoom cannot cross near boundary")
	camera.free()


func test_camera_zoom_stops_at_far_limit() -> void:
	var camera := PoolCamera.new()
	camera.configure({"zoom_min": 8.0, "zoom_max": 16.0, "distance": 12.0, "zoom_step": 2.0})
	camera.zoom_by(100)
	check_eq(camera.distance, 16.0, "zoom cannot cross far boundary")
	camera.free()


func test_camera_snap_looks_at_target_without_lag() -> void:
	var camera := PoolCamera.new()
	camera.configure({"pitch_deg": 50.0, "distance": 13.0})
	camera.snap_to(Vector3(4.0, 0.0, -3.0))
	check_eq(camera.focus, Vector3(4.0, 0.0, -3.0), "teleport follows now")
	check_near(camera.pitch_degrees(), 50.0, 0.001, "configured pitch")
	camera.free()


func test_camera_look_ahead_is_bounded_by_speed_cap() -> void:
	var camera := PoolCamera.new()
	camera.configure({"follow_half_life_s": 0.12, "look_ahead_s": 1.0, "look_ahead_max": 2.0})
	camera.snap_to(Vector3.ZERO)
	camera.follow(Vector3.ZERO, Vector2(100.0, 0.0), 10.0)
	check_near(camera.focus.x, 2.0, 0.001, "large speed cannot move aim past look-ahead cap")
	camera.free()


func test_arrow_zero_direction_has_safe_up_fallback() -> void:
	var arrow := StarvingArrow.new()
	arrow.size = Vector2(800.0, 600.0)
	arrow.point(Vector2(400.0, 300.0), Vector2.ZERO, Vector2.INF, 12.0)
	check_eq(arrow.arrow_direction, Vector2.UP, "zero vector becomes north")
	check(arrow.arrow_position.is_finite(), "position is finite")
	arrow.free()


func test_arrow_to_offscreen_food_stays_inside_edge_margin() -> void:
	var arrow := StarvingArrow.new()
	arrow.size = Vector2(800.0, 600.0)
	arrow.point(Vector2(400.0, 300.0), Vector2.RIGHT, Vector2.INF, 12.0)
	check_near(arrow.arrow_position.x, 800.0 - StarvingArrow.EDGE_MARGIN_PX, 0.001, "edge inset")
	check_eq(arrow.label_text(), "Food 12 m", "distance text")
	arrow.free()


func test_arrow_stops_short_of_visible_food() -> void:
	var arrow := StarvingArrow.new()
	arrow.size = Vector2(800.0, 600.0)
	arrow.point(Vector2(400.0, 300.0), Vector2.RIGHT, Vector2(650.0, 300.0), 7.0)
	check_near(arrow.arrow_position.x, 650.0 - StarvingArrow.SHORT_OF_FOOD_PX, 0.001, "food stays visible")
	arrow.free()


func test_arrow_does_not_cover_cell_for_near_food() -> void:
	var arrow := StarvingArrow.new()
	arrow.size = Vector2(800.0, 600.0)
	arrow.point(Vector2(400.0, 300.0), Vector2.RIGHT, Vector2(430.0, 300.0), 1.0, 30.0)
	check_near(arrow.arrow_position.distance_to(arrow.cell_position), StarvingArrow.MIN_FROM_CELL_PX,
		0.001, "minimum offset")
	check(not arrow._over_cell(arrow.label_rect()), "text clears the body")
	arrow.free()


func test_fx_hit_text_rounds_small_damage_up_to_one() -> void:
	check_eq(FeedbackFx.hit_text({"dealt": 0.2}), "−1", "a real scratch is visible")


func test_fx_hit_text_prefers_actual_dealt_damage() -> void:
	check_eq(FeedbackFx.hit_text({"dealt": 4.6, "damage": 20.0}), "−5", "show applied amount")


func test_fx_meal_text_omits_unearned_points() -> void:
	check_eq(FeedbackFx.meal_text({"absorbed": 3.6, "points": 0}), "+4 energy", "no zero point marker")


func test_fx_hit_lifetime_is_an_integer_number_of_sim_ticks() -> void:
	check_near(FeedbackFx.HIT_LIFE_S * 60.0, 54.0, 0.0001, "0.9 seconds is 54 ticks")
	check_near(FeedbackFx.DODGED_LIFE_S * 60.0, 48.0, 0.0001, "0.8 seconds is 48 ticks")
