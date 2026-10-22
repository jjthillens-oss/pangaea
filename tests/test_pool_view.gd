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


func _meal(at: Vector2) -> Dictionary:
	return {"type": "ate", "kind": "plant", "position": at, "absorbed": 8.0, "points": 1}


func _feedback(camera: PoolCamera) -> FeedbackFx:
	var fx := FeedbackFx.new()
	var zones: Array[Dictionary] = []
	fx.setup(zones, camera)
	return fx


## Where a world point shows on a 1920x1080 screen through `camera`. The camera is not in a
## viewport, so this projects the way Camera3D does (vertical field of view, 16:9).
func _on_screen(camera: Camera3D, p: Vector3) -> Vector2:
	var view := camera.transform.affine_inverse() * p
	var clip := Projection.create_perspective(camera.fov, 16.0 / 9.0, camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	return Vector2(clip.x / clip.w + 1.0, 1.0 - clip.y / clip.w) * Vector2(960.0, 540.0)


## How far label a's centre shows above label b's through `camera`, in lines of text (the font's
## height, as the camera shows it between them); negative is below.
func _lines_above(camera: Camera3D, a: Label3D, b: Label3D) -> float:
	var line_m := ThemeDB.fallback_font.get_height(FeedbackFx.FONT_SIZE) * FeedbackFx.PIXEL_SIZE
	var middle := (a.position + b.position) / 2.0
	var line_px := _on_screen(camera, middle).distance_to(_on_screen(camera, middle + camera.basis.y * line_m))
	return (_on_screen(camera, b.position).y - _on_screen(camera, a.position).y) / line_px


## A meal at `older`, then `age` s later one at the plane origin, with the pool camera looking at
## it. Follows both labels at 60 Hz for `frames` frames from the newer label's first, or until the
## older one is gone: "apart" is how far the older label shows above the newer one (_lines_above),
## and "older_y" is the older label's height.
func _follow_two_labels(older: Vector2, age: float, frames: int) -> Dictionary:
	var camera := _camera()
	camera.snap_to(Vector3.ZERO)
	var fx := _feedback(camera)
	fx.show_meal(_meal(older))
	fx._process(age)
	fx.show_meal(_meal(Vector2.ZERO))
	var labels := fx.meal_labels()
	var out := {"apart": PackedFloat32Array(), "older_y": PackedFloat32Array()}
	if labels.size() == 2:
		for frame in frames:
			if not labels[0].visible:
				break
			out.apart.append(_lines_above(camera, labels[0], labels[1]))
			out.older_y.append(labels[0].position.y)
			fx._process(1.0 / 60.0)
	fx.free()
	camera.free()
	return out


func test_a_quick_second_meal_close_by_adds_to_the_first_meal_label() -> void:
	var camera := _camera()
	var fx := _feedback(camera)
	fx.show_meal(_meal(Vector2.ZERO))
	fx._process(0.3)
	fx.show_meal(_meal(Vector2(0.8, 0.5)))
	var labels := fx.meal_labels()
	check_eq(labels.size(), 1, "one label for both meals")
	if labels.size() == 1:
		check_eq(labels[0].text, "+16 energy · +2", "the label sums the meals")
		check(labels[0].position.is_equal_approx(PlaneSpace.to_world(Vector2(0.8, 0.5), FeedbackFx.MEAL_START_Y)),
			"and rises again from the newer meal (%s)" % labels[0].position)
	fx._process(FeedbackFx.MEAL_MERGE_S + 0.05)
	fx.show_meal(_meal(Vector2(0.8, 0.5)))
	check_eq(fx.meal_labels().size(), 2, "a meal after the merge window gets its own label")
	fx.free()
	camera.free()


func test_a_new_meal_label_pushes_the_rising_labels_near_it_up_a_line_without_crossing() -> void:
	var camera := _camera()
	var line := FeedbackFx.MEAL_LINE_M / cos(deg_to_rad(camera.pitch_degrees()))   # as a world height
	var fx := _feedback(camera)
	fx.show_meal(_meal(Vector2.ZERO))
	fx._process(0.1)
	fx.show_meal(_meal(Vector2(2.0, 0.0)))   # too far to merge, near enough to collide
	var labels := fx.meal_labels()
	check_eq(labels.size(), 2, "two labels")
	if labels.size() != 2:
		fx.free()
		camera.free()
		return
	var closest := INF
	for frame in 12:
		fx._process(1.0 / 60.0)
		closest = minf(closest, labels[0].position.y - labels[1].position.y)
	check(closest > 0.0, "the older label never drops to the newer one (closest %.3f m)" % closest)
	var gap := labels[0].position.y - labels[1].position.y
	check(gap >= line * 0.95, "after 0.2 s the older label is a line above (%.3f m)" % gap)
	fx.free()
	fx = _feedback(camera)
	fx.show_meal(_meal(Vector2.ZERO))
	fx._process(0.1)
	fx.show_meal(_meal(Vector2(FeedbackFx.MEAL_NEAR_M + 1.0, 0.0)))
	fx._process(0.2)
	var far := fx.meal_labels()[0]
	check_near(far.position.y, FeedbackFx.MEAL_START_Y + FeedbackFx.MEAL_RISE_M * ease(0.3 / FeedbackFx.MEAL_LIFE_S, 0.4), 1e-4,
		"a label far from the new one stays where it was")
	fx.free()
	camera.free()


func test_an_older_meal_label_nearer_the_camera_stays_a_line_below_a_new_one_on_screen() -> void:
	# Seen from above at an angle, a label nearer the camera (plane +y) shows lower. Pushing it up a
	# line, as if both were the same distance away, ran it up into or through the new label. The
	# first case is the live one that showed it: 1 m nearer, past the merge window, nearly in line.
	# The others are too far from the new meal to merge with it.
	for case in [[Vector2(0.2, 1.0), 0.65], [Vector2(1.2, 1.0), 0.1], [Vector2(1.5, 0.5), 0.1], [Vector2(1.6, 0.3), 0.05]]:
		var apart: PackedFloat32Array = _follow_two_labels(case[0], case[1], 45).apart
		check(apart.size() >= 30, "two labels for %s" % [case])
		var closest := INF
		for d in apart:
			closest = minf(closest, -d)
		check(closest >= 1.0, "an older label at %s, %.2f s old, shows a line below the new one on every frame (closest %.2f lines)"
			% [case[0], case[1], closest])


func test_an_older_meal_label_farther_from_the_camera_stays_a_line_above_and_moves_only_as_far_as_it_must() -> void:
	# 1 m farther away it already shows well above the new label, so it stays where it was.
	var far := _follow_two_labels(Vector2(1.2, -1.0), 0.1, 45)
	check(far.apart.size() == 45, "two labels")
	var closest := INF
	for d in far.apart:
		closest = minf(closest, d)
	check(closest >= 1.0, "a label 1 m farther away shows a line above on every frame (closest %.2f lines)" % closest)
	for frame in far.older_y.size():
		var rise := FeedbackFx.MEAL_RISE_M * ease((0.1 + frame / 60.0) / FeedbackFx.MEAL_LIFE_S, 0.4)
		if absf(far.older_y[frame] - (FeedbackFx.MEAL_START_Y + rise)) > 1e-4:
			check(false, "and is not pushed (frame %d: %.3f m)" % [frame, far.older_y[frame]])
			break
	# 0.3 m farther away it shows less than a line above, so it moves up, and never below.
	var near := _follow_two_labels(Vector2(1.5, -0.3), 0.1, 45)
	check(near.apart.size() == 45, "two labels")
	closest = INF
	var settled := INF
	for frame in near.apart.size():
		closest = minf(closest, near.apart[frame])
		if frame >= 12:
			settled = minf(settled, near.apart[frame])
	check(closest > 0.0, "a label 0.3 m farther away never shows below the new one (closest %.2f lines)" % closest)
	check(settled >= 1.0, "and is a line above it from 0.2 s on (closest %.2f lines)" % settled)


func test_a_pushed_meal_label_carries_up_the_labels_stacked_above_it() -> void:
	# Three meals 2 m apart sideways: the first and last labels are too far apart to overlap, but
	# each overlaps the middle one, which the last pushes up into the first unless that moves too.
	var camera := _camera()
	var fx := _feedback(camera)
	fx.show_meal(_meal(Vector2(-2.0, 0.0)))
	fx._process(0.05)
	fx.show_meal(_meal(Vector2.ZERO))
	fx._process(0.05)
	fx.show_meal(_meal(Vector2(2.0, 0.0)))
	var labels := fx.meal_labels()
	check_eq(labels.size(), 3, "three labels")
	if labels.size() != 3:
		fx.free()
		camera.free()
		return
	var closest := INF
	for frame in 30:
		fx._process(1.0 / 60.0)
		closest = minf(closest, _lines_above(camera, labels[0], labels[1]))
	check(closest > 0.0, "the first label never shows below the middle one (closest %.2f lines)" % closest)
	check(_lines_above(camera, labels[0], labels[1]) >= 1.0,
		"after 0.5 s the first label shows a line above the middle one (%.2f lines)" % _lines_above(camera, labels[0], labels[1]))
	check(_lines_above(camera, labels[1], labels[2]) >= 1.0,
		"and the middle one a line above the last (%.2f lines)" % _lines_above(camera, labels[1], labels[2]))
	fx.free()
	camera.free()


func test_meal_labels_that_the_moving_camera_brings_closer_than_a_line_move_apart_again() -> void:
	# The new label starts a line above an older one 1 m nearer the camera. When the camera moves
	# south and zooms in, both show higher up and the nearer one grows more, so it closes on the
	# label above it.
	var camera := _camera()
	camera.snap_to(Vector3.ZERO)
	var fx := _feedback(camera)
	fx.show_meal(_meal(Vector2(1.6, 1.0)))
	fx._process(0.65)
	fx.show_meal(_meal(Vector2.ZERO))
	var labels := fx.meal_labels()
	check_eq(labels.size(), 2, "two labels")
	if labels.size() != 2:
		fx.free()
		camera.free()
		return
	check(_lines_above(camera, labels[1], labels[0]) >= 1.0,
		"the new label starts a line above the older one (%.2f lines)" % _lines_above(camera, labels[1], labels[0]))
	camera.zoom_by(-2)
	camera.snap_to(Vector3(0.0, 0.0, 4.0))
	var closest := INF
	for frame in 30:
		fx._process(1.0 / 60.0)
		if frame >= 12:
			closest = minf(closest, _lines_above(camera, labels[1], labels[0]))
	check(closest >= 1.0, "after the camera moves they are a line apart again within 0.2 s (closest %.2f lines)" % closest)
	fx.free()
	camera.free()


func test_the_food_arrow_label_never_covers_the_cell_and_stays_by_its_arrow() -> void:
	var arrow := StarvingArrow.new()
	arrow.size = Vector2(1920, 1080)
	var cell := Vector2(960, 540)
	var closest := INF
	var farthest := 0.0
	for radius in [47.0, 66.0]:   # the cell's radius at the default zoom and fully zoomed in
		for k in 16:
			var direction := Vector2.RIGHT.rotated(TAU * k / 16.0)
			for food_px in [110.0, 140.0, 170.0, 220.0, 400.0]:
				arrow.point(cell, direction, cell + direction * food_px, food_px / 94.0, radius)
				var r := arrow.label_rect()
				closest = minf(closest, cell.clamp(r.position, r.end).distance_to(cell) - radius * StarvingArrow.CELL_CLEAR)
				farthest = maxf(farthest, r.get_center().distance_to(arrow.arrow_position))
	check(closest >= 0.0, "the label keeps clear of the cell, its mouth and eyes (closest %.1f px)" % closest)
	check(farthest < 110.0, "and stays next to its arrow (farthest %.0f px)" % farthest)
	arrow.point(cell, Vector2.RIGHT, Vector2.INF, 12.0, 47.0)
	check(arrow.label_rect().get_center().x < arrow.arrow_position.x and absf(arrow.label_rect().get_center().y - cell.y) < 1.0,
		"far from the cell the label sits behind the arrow, on its axis")
	arrow.free()


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


func test_new_carrion_sinks_onto_the_floor_and_starting_carrion_is_simply_there() -> void:
	var meat := FoodView.new()
	meat.kind = "meat"
	var start := {"id": "cr_2", "position": Vector2(1.0, 2.0), "age": 0.0, "lifetime": 90.0, "source": "initial"}
	var t := meat._transform_for(start, 0.0)
	check_near(t.basis.get_scale().x, 1.0, 1e-5, "starting carrion is full size")
	check_near(t.origin.y, FoodView.MEAT_Y, 1e-6, "and on the floor")
	var dropped := {"id": "cr_3", "position": Vector2(1.0, 2.0), "age": 0.0, "lifetime": 90.0, "source": "interim"}
	t = meat._transform_for(dropped, 0.0)
	check(t.basis.get_scale().x < 0.5 and t.origin.y > FoodView.MEAT_Y + 0.3,
		"new carrion appears small and above the floor (scale %.2f, y %.2f)" % [t.basis.get_scale().x, t.origin.y])
	var steady := true
	var last := t
	for tick in range(1, 37):
		dropped.age = tick / 60.0
		t = meat._transform_for(dropped, 0.0)
		steady = steady and t.basis.get_scale().x >= last.basis.get_scale().x - 1e-6 and t.origin.y <= last.origin.y + 1e-6
		last = t
	check(steady, "it only grows and sinks")
	check_near(t.basis.get_scale().x, 1.0, 1e-5, "full size after %.1f s" % FoodView.MEAT_SETTLE_S)
	check(t.origin.is_equal_approx(PlaneSpace.to_world(Vector2(1.0, 2.0), FoodView.MEAT_Y)), "and on the floor where it landed")
	meat.free()
