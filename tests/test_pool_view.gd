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


func test_a_hit_on_or_by_the_cell_rises_as_a_number_and_a_dodge_says_so() -> void:
	var camera := _camera()
	var fx := _feedback(camera)
	var taken := {"type": "hit", "attacker": "c_1", "target": CreatureField.PLAYER_ID, "kind": "bite",
		"damage": 12.0, "dealt": 12.0, "position": Vector2(1.0, 2.0)}
	fx.show_hit(taken)
	var labels := fx.hit_labels()
	check_eq(labels.size(), 1, "a hit on the cell shows a number")
	if labels.size() == 1:
		check_eq(labels[0].text, "−12", "the health it took")
		check(labels[0].modulate.is_equal_approx(FeedbackFx.HIT_TAKEN_COLOR), "in the taken colour")
		check(labels[0].position.is_equal_approx(PlaneSpace.to_world(Vector2(1.0, 2.0), FeedbackFx.HIT_START_Y)), "over the cell")
	fx.show_hit({"type": "hit", "attacker": CreatureField.PLAYER_ID, "target": "c_2", "kind": "bite", "damage": 8.0,
		"dealt": 7.6, "position": Vector2.ZERO})
	check_eq(fx.hit_labels().size(), 2, "a hit by the cell shows one too")
	if fx.hit_labels().size() == 2:
		check(fx.hit_labels()[1].modulate.is_equal_approx(FeedbackFx.HIT_DEALT_COLOR) and fx.hit_labels()[1].text == "−8",
			"in the dealt colour, rounded")
	fx.show_hit({"type": "hit", "attacker": "c_3", "target": "c_2", "kind": "ram", "damage": 9.0, "dealt": 9.0, "position": Vector2.ZERO})
	check_eq(fx.hit_labels().size(), 2, "hits between creatures show nothing")
	check_eq(FeedbackFx.hit_text({"dealt": 0.3}), "−1", "a scratch shows at least 1")
	fx._process(FeedbackFx.HIT_LIFE_S + 0.01)
	check_eq(fx.hit_labels().size(), 0, "the numbers are gone after their life")
	check(not fx.dodged_label().visible, "no dodge yet")
	fx.show_dodged(Vector2(3.0, -1.0))
	check(fx.dodged_label().visible and fx.dodged_label().text == "Dodged!", "a dodge shows 'Dodged!'")
	fx._process(FeedbackFx.DODGED_LIFE_S * 0.5)
	check(fx.dodged_label().visible and fx.dodged_label().position.y > FeedbackFx.DODGED_START_Y, "rising")
	fx._process(FeedbackFx.DODGED_LIFE_S * 0.5 + 0.01)
	check(not fx.dodged_label().visible, "gone after 0.8 s")
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


# --- threats (M1 step 3): creature views, the creature layer, the player's hurt and shelter ---

const CREATURE_VIEW := "res://game/scenes/pool/creature_view.tscn"
const CELL_VIEW := "res://game/scenes/pool/player_cell_view.tscn"
## Every brain label a creature can show, for the pose sweeps.
const PHASES: PackedStringArray = ["rest/lurk", "rest/watch", "rest", "wander/patrol", "wander/return", "forage/seek",
	"forage/eat", "notice", "notice/wait", "chase/pursue", "chase/aim", "attack/tell", "attack/strike", "attack/glide",
	"attack/recover", "flee"]


## A pool with the real layout and species (seven creatures at their sites) for a new grazer.
func _threat_sim(seed_value := 4242) -> PoolSim:
	var catalog := PartCatalog.load_from()
	var layout := PoolLayout.load_from()
	var r := Lineage.found(seed_value, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, SpeciesCatalog.load_from())
	sim.drain_events()
	return sim


func _creature_view(species_id: String) -> CreatureView:
	var view := (load(CREATURE_VIEW) as PackedScene).instantiate() as CreatureView
	view.build(SpeciesCatalog.load_from(), species_id, PartCatalog.load_from(), "c_test")
	return view


func test_an_ambush_hunter_coils_over_its_tell_and_stretches_only_in_its_strike() -> void:
	var rest := CreatureView.pose("ambush", "attack/tell", 0.0)
	check(rest.scale.is_equal_approx(Vector3.ONE), "neutral at the tell's start (%s)" % rest.scale)
	check_near(rest.jaw_open, 0.0, 1e-9, "jaw shut at the start")
	var coil := CreatureView.pose("ambush", "attack/tell", 1.0)
	check_near(coil.scale.z, 0.82, 1e-6, "coiled along its length at the tell's end")
	check_near(coil.scale.x, 1.08, 1e-6, "and wider")
	check_near(coil.jaw_open, 1.0, 1e-9, "jaw open")
	check_near(coil.eye_glow, 1.0, 1e-9, "eyes at full glow")
	check_eq(coil.stretch, 0.0, "a coil is not a stretch")
	var early := CreatureView.pose("ambush", "attack/tell", 24.0 / 72.0)
	check(early.scale.z < 0.92 and early.jaw_open > 0.4,
		"the coil already shows at the 0.4 s a player needs to react (z %.3f, jaw %.2f)" % [early.scale.z, early.jaw_open])
	var deeper := true
	var last := rest
	for i in range(1, 73):
		var p := CreatureView.pose("ambush", "attack/tell", i / 72.0)
		deeper = deeper and p.scale.z <= last.scale.z + 1e-9 and p.eye_glow >= last.eye_glow - 1e-9
		last = p
	check(deeper, "the coil only deepens and the eyes only brighten over the tell")
	var lunge := CreatureView.pose("ambush", "attack/strike", 0.5)
	check_near(lunge.scale.z, 1.15, 1e-6, "stretched along the lunge")
	check_eq(lunge.stretch, 1.0, "the strike stretches")
	check_eq(CreatureView.pose("ambush", "attack/glide", 0.5).stretch, 1.0, "so does the glide")
	check(CreatureView.pose("ambush", "rest/watch", 0.0).eye_glow > CreatureView.pose("ambush", "rest/lurk", 0.0).eye_glow,
		"watching eyes glow brighter than lurking ones")


func test_a_rammer_puffs_up_over_its_tell_with_its_crest_and_spikes_raised() -> void:
	var rest := CreatureView.pose("territorial", "attack/tell", 0.0)
	check(rest.scale.is_equal_approx(Vector3.ONE) and rest.hood == 0.0 and rest.spike_raise == 0.0, "neutral at the tell's start")
	var puff := CreatureView.pose("territorial", "attack/tell", 1.0)
	check(puff.scale.is_equal_approx(Vector3.ONE * 1.25), "puffed to 1.25 at the tell's end (%s)" % puff.scale)
	check_near(puff.spike_raise, 1.0, 1e-9, "spikes raised")
	check_near(puff.hood, 1.0, 1e-9, "crest raised")
	var charge := CreatureView.pose("territorial", "attack/strike", 0.3)
	check(charge.scale.is_equal_approx(Vector3.ONE * 1.2) and charge.spike_raise == 1.0, "held puffed through the charge")
	check_eq(CreatureView.pose("territorial", "attack/tell", 1.0).eye_glow, 0.0, "a rammer's eyes never glow")


func test_no_pose_stretches_outside_a_strike_and_recovery_returns_to_rest() -> void:
	var stretched := PackedStringArray()
	for behavior in ["ambush", "territorial"]:
		for phase in PHASES:
			for i in 11:
				var p := CreatureView.pose(behavior, phase, i / 10.0, "missed", 1.0)
				var striking := phase == "attack/strike" or phase == "attack/glide"
				if p.stretch != 0.0 and not (striking and behavior == "ambush"):
					stretched.append("%s %s %.1f" % [behavior, phase, i / 10.0])
	check(stretched.is_empty(), "stretch only in an ambush strike: %s" % stretched)
	for behavior in ["ambush", "territorial"]:
		for outcome in ["hit", "missed", "blocked", "cancelled", "interrupted"]:
			var start := CreatureView.pose(behavior, "attack/recover", 0.0, outcome, 2.0)
			var done := CreatureView.pose(behavior, "attack/recover", 1.0, outcome, 2.0)
			var calm := CreatureView.pose(behavior, "rest/watch", 0.0)
			check(not start.scale.is_equal_approx(Vector3.ONE), "%s %s recover starts from the attack's pose" % [behavior, outcome])
			check(done.scale.is_equal_approx(Vector3.ONE) and done.jaw_open == 0.0 and done.spike_raise == 0.0 \
				and done.hood == 0.0 and absf(done.wobble) < 1e-9 and is_equal_approx(done.eye_glow, calm.eye_glow),
				"%s %s recover ends at rest" % [behavior, outcome])
	var wobbles := false
	for i in 18:
		wobbles = wobbles or absf(CreatureView.pose("territorial", "attack/recover", i / 120.0, "blocked", 2.0).wobble) > 0.05
	check(wobbles, "a rammer blocked by a rock wobbles at the start of its recover")
	check_eq(CreatureView.pose("territorial", "attack/recover", 0.2, "missed", 1.2).wobble, 0.0, "a miss does not wobble")


## How far a shown pose is from rest: its scale's distance from one and each 0..1 amount.
func _tell_amounts(p: Dictionary) -> PackedFloat64Array:
	var s: Vector3 = p.scale
	return PackedFloat64Array([(s - Vector3.ONE).length(), p.jaw_open, p.hood, p.spike_raise, p.brow])


func test_a_cancelled_tell_deflates_from_the_pose_it_reached_and_never_swells_first() -> void:
	for species_id in ["rammer", "ambush_hunter"]:
		for cancel_at in [5, 20, 47]:
			# A real view drawn at 60 fps: the tell entered at tick 100, so the sim's tick is 101 at its
			# first drawn frame; the step at tick T cancels it into recover, drawn from tick T + 1.
			var view := _creature_view(species_id)
			var mem := _memory_in(view, "attack", "tell")
			var tick := 101
			for i in cancel_at:
				view.show_brain(mem, tick, 0.0)
				view._process(1.0 / 60.0)
				tick += 1
			var at_cancel := view.shown_pose.duplicate()
			mem.phase = CreatureBrain.RECOVER
			mem.phase_tick = tick - 1
			mem.outcome = "cancelled"
			mem.recover_ticks = CreatureBrain.CANCEL_RECOVER_TICKS
			var last := _tell_amounts(at_cancel)
			var rises := PackedStringArray()
			var first := {}
			for i in mem.recover_ticks + 6:
				view.show_brain(mem, tick, 0.0)
				view._process(1.0 / 60.0)
				if first.is_empty():
					first = view.shown_pose.duplicate()
				var now := _tell_amounts(view.shown_pose)
				for k in now.size():
					if now[k] > last[k] + 1e-6:
						rises.append("frame %d: %.3f > %.3f" % [i, now[k], last[k]])
				last = now
				tick += 1
			var what := "%s cancelled %d ticks into its tell" % [species_id, cancel_at]
			check(_tell_amounts(at_cancel)[0] > 0.01, "%s had begun its tell (scale %s)" % [what, at_cancel.scale])
			check((first.scale as Vector3).is_equal_approx(at_cancel.scale), "%s starts its recover from the pose it reached (%s, then %s)" % [what, at_cancel.scale, first.scale])
			check(rises.is_empty(), "%s only deflates: %s" % [what, rises])
			check((view.shown_pose.scale as Vector3).is_equal_approx(Vector3.ONE), "%s ends at rest" % what)
			view.free()


func test_the_pose_progress_follows_the_sim_tick_and_the_draw_fraction() -> void:
	var sim := _threat_sim()
	var c: CreatureField.Creature = sim.creatures.creatures[0]
	c.brain.state = CreatureBrain.ATTACK
	c.brain.phase = CreatureBrain.TELL
	c.brain.phase_tick = 100
	check_eq(CreatureView.phase_ticks(c.brain), 72, "a tell lasts its 72 ticks")
	# The step that entered the tell ran at tick 100, so the sim's tick is now 101.
	check_near(CreatureView.phase_progress(c.brain, 101, 0.0), 0.0, 1e-9, "the drawn moment before that step's motion")
	check_near(CreatureView.phase_progress(c.brain, 101, 1.0), 1.0 / 72.0, 1e-9, "after one tick of it")
	check_near(CreatureView.phase_progress(c.brain, 136, 0.5), 35.5 / 72.0, 1e-9, "halfway through a tick")
	check_near(CreatureView.phase_progress(c.brain, 172, 1.0), 1.0, 1e-9, "full on the tick the strike starts")
	c.brain.phase = CreatureBrain.STRIKE
	check_eq(CreatureView.phase_ticks(c.brain), 21, "the lunge's burst")
	c.brain.state = CreatureBrain.REST
	c.brain.phase = CreatureBrain.LURK
	check_eq(CreatureView.phase_progress(c.brain, 500, 0.5), 0.0, "an untimed phase has no progress")


func test_a_creature_view_builds_its_species_body_parts_and_its_own_eye_glow() -> void:
	var ambush := _creature_view("ambush_hunter")
	var parts := ambush.get_node("%Parts").get_children()
	check_eq(parts.size(), 3, "a jaw and two flagella")
	check(ambush.get_node_or_null("%Model/Body/Body/Eye_L") != null, "the ambush body blockout with its eyes")
	check(ambush.get_node("%Model").scale.is_equal_approx(Vector3.ONE * 1.5), "scaled by its body_size")
	var rammer := _creature_view("rammer")
	var spikes := rammer.get_node("%Parts").get_children().filter(func(n: Node) -> bool: return n.get_meta("part_type") == "spike")
	check_eq(spikes.size(), 4, "four spike holders")
	check(spikes.all(func(n: Node) -> bool: return n.get_child_count() == 1), "each with the spike model")
	check(rammer.get_node_or_null("%Model/Body/Body/Hood") != null, "the rammer body with its crest")
	# The thin crest's shadow read as a dark hole in the pale back; the bodies keep theirs.
	var hood := rammer.get_node_or_null("%Model/Body/Body/Hood") as GeometryInstance3D
	check(hood != null and hood.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the crest casts no shadow")
	for view in [ambush, rammer]:
		var body := view.get_node("%Model/Body/Body") as GeometryInstance3D
		check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the %s body casts its shadow" % view.species_id)
	check(ambush.get_node_or_null("%Model/Body/Body/Hood") == null, "an ambush body has no crest and builds without one")
	var other := _creature_view("ambush_hunter")
	other.show_brain(_memory_in(other, "attack", "tell"), 173, 1.0)
	var eye := ambush.get_node("%Model/Body/Body/Eye_L") as MeshInstance3D
	var other_eye := other.get_node("%Model/Body/Body/Eye_L") as MeshInstance3D
	var mine := eye.get_active_material(0) as StandardMaterial3D
	var theirs := other_eye.get_active_material(0) as StandardMaterial3D
	check(mine != theirs, "each view has its own eye material")
	ambush._apply_pose(ambush.shown_pose)
	other._apply_pose(other.shown_pose)
	check_near(theirs.emission_energy_multiplier, 1.0 / 0.4, 1e-4, "a coiled hunter's eyes glow at full strength")
	check_near(mine.emission_energy_multiplier, 0.2 / 0.4, 1e-4, "a lurking one's stay dim")
	for view in [ambush, rammer, other]:
		view.free()


## A brain in `state`/`phase` that entered it at tick 100 (for posing a view without a sim).
func _memory_in(view: CreatureView, state: String, phase: String) -> CreatureBrain.Memory:
	var species := SpeciesCatalog.load_from()
	var cfg := species.brain_config(view.species_id)
	var mem := CreatureBrain.create(cfg.behavior, cfg, Vector2.ZERO, 0.0, {}, 1, 0)
	mem.state = state
	mem.phase = phase
	mem.phase_tick = 100
	return mem


func test_a_creature_view_draws_the_sim_position_and_heading() -> void:
	var view := _creature_view("rammer")
	var motion := Locomotion.MotionState.new(Vector2(-2.5, -22.0), 1.0)
	motion.position = Vector2(-2.45, -21.9)
	motion.heading = 1.1
	view.show_motion(motion, 1.0)
	check(view.position.distance_to(PlaneSpace.to_world(motion.position)) < 0.001, "within a millimetre at fraction 1")
	check_near((view.get_node("%Pivot") as Node3D).rotation.y, PlaneSpace.yaw_for_heading(1.1), 1e-5, "facing the heading")
	view.show_motion(motion, 0.0)
	check(view.position.distance_to(PlaneSpace.to_world(motion.prev_position)) < 0.001, "at the previous tick at fraction 0")
	view.free()


func test_the_creature_layer_builds_a_view_per_creature_and_lets_a_dead_one_go() -> void:
	var sim := _threat_sim()
	var layer := CreatureLayer.new()
	layer.attach(sim)
	check_eq(sim.creatures.creatures.size(), 7, "seven creatures at their sites")
	check_eq(layer.views().size(), 7, "one view each")
	var placed := true
	for c in sim.creatures.creatures:
		var view := layer.view_of(c.id)
		placed = placed and view != null and view.position.distance_to(PlaneSpace.to_world(c.motion.position)) < 0.001 \
			and view.species_id == c.species_id
	check(placed, "each view is its creature's species, at its place")
	sim.debug_teleport(Vector2(24.0, 12.0), 0.0)   # nearest to lair_se
	check(sim.debug_kill_nearest_creature(), "a dev kill")
	var died := ""
	for e in sim.drain_events():
		layer.on_event(e)
		if e.type == "creature_died":
			died = str(e.id)
	check(died != "", "the creature died")
	check(layer.view_of(died) == null, "its view is let go")
	check_eq(layer.views().size(), 6, "six live views")
	var dying := layer.get_node_or_null(NodePath(died)) as CreatureView
	check(dying != null and dying.dying, "the view stays to shrink away")
	if dying != null:
		dying._process(CreatureView.DIE_S + 0.01)
		check(dying.is_queued_for_deletion(), "and frees itself once its death pose has played")
	var c := sim.creatures.spawn_at("rammer", Vector2(5.0, 5.0), 0.0, "", sim.tick, true)
	for e in sim.drain_events():
		layer.on_event(e)
	var spawned := layer.view_of(c.id)
	check(spawned != null, "a spawned creature gets a view")
	if spawned != null:
		check_near(spawned.get_node("%Model").scale.x, 1.25 * CreatureView.SPAWN_SCALE, 1e-4, "that grows in as it fades in")
	sim.creatures.remove(c, "stuck", sim.tick, false)
	for e in sim.drain_events():
		layer.on_event(e)
	check(layer.view_of(c.id) == null and layer.get_node_or_null(NodePath(c.id)) == null, "a removed creature's view goes at once")
	layer.free()


func test_the_creature_layer_shows_the_marker_lane_and_flash_its_events_ask_for() -> void:
	var sim := _threat_sim()
	var layer := CreatureLayer.new()
	layer.attach(sim)
	var hunter := sim.creatures.creatures.filter(func(x: CreatureField.Creature) -> bool: return x.species_id == "ambush_hunter")[0] as CreatureField.Creature
	var view := layer.view_of(hunter.id)
	var marker := view.get_node("%Marker") as Label3D
	var lane := CreatureBrain.strike_lane(sim.species.brain_config("ambush_hunter").attack, 0.75, 0.5, hunter.motion.position, 0.0)
	layer.on_event({"type": "creature_noticed", "id": hunter.id, "target": "c_other", "by": "sight"})
	check(not marker.visible, "no marker when it notices another creature")
	layer.on_event({"type": "creature_noticed", "id": hunter.id, "target": CreatureField.PLAYER_ID, "by": "sight"})
	check(marker.visible, "a marker when it notices the player")
	view._process(CreatureView.MARKER_S + 0.01)
	check(not marker.visible, "for %.1f s" % CreatureView.MARKER_S)
	layer.on_event({"type": "creature_tell", "id": hunter.id, "target": "c_other", "kind": "lunge", "lane": lane})
	check(not view.lane_visible(), "no lane for a tell on another creature")
	layer.on_event({"type": "creature_tell", "id": hunter.id, "target": CreatureField.PLAYER_ID, "kind": "lunge", "lane": lane})
	check(view.lane_visible(), "a lane for a tell on the player")
	layer.on_event({"type": "tell_cancelled", "id": hunter.id})
	check(not view.lane_visible(), "taken down when the tell is cancelled")
	layer.on_event({"type": "creature_tell", "id": hunter.id, "target": CreatureField.PLAYER_ID, "kind": "lunge", "lane": lane})
	layer.on_event({"type": "creature_recovered", "id": hunter.id, "outcome": "missed"})
	check(view.lane_visible(), "a finished strike's lane fades instead of vanishing")
	view._process(CreatureView.LANE_FADE_S + 0.01)
	check(not view.lane_visible(), "and is gone after %.1f s" % CreatureView.LANE_FADE_S)
	layer.on_event({"type": "hit", "attacker": CreatureField.PLAYER_ID, "target": hunter.id, "kind": "bite"})
	view._process(0.03)
	check(view.get_node("%Model").scale.y < view.body_size - 0.01, "a hit on it squashes it")
	layer.free()


func test_a_tell_on_the_player_lays_its_strike_lane_on_the_floor_and_fills_it() -> void:
	var view := _creature_view("ambush_hunter")
	var sim := _threat_sim()
	var species := sim.species
	var cfg := species.brain_config("ambush_hunter")
	var lane := CreatureBrain.strike_lane(cfg.attack, 0.75, 0.5, Vector2(3.0, -4.0), 0.6)
	view.show_lane(lane)
	var node := view.get_node("%Lane") as MeshInstance3D
	var material := node.material_override as ShaderMaterial
	check(view.lane_visible(), "the lane shows")
	# The view's state and the uniform the shader multiplies every pixel's alpha by. The lane's pixels
	# themselves (alpha math, depth against the floor) are checked only in rendered frames.
	check_eq(material.get_shader_parameter("strength"), 1.0, "at full strength")
	# The unit quad's corners land on the lane rectangle: from its origin forward along its heading.
	var t := node.transform   # the lane is top_level, so this is its world transform
	check(node.top_level, "the lane does not turn with the creature")
	var far_left := PlaneSpace.to_plane(t * Vector3(-0.5, 0.0, -0.5))
	var near_right := PlaneSpace.to_plane(t * Vector3(0.5, 0.0, 0.5))
	var ahead := Vector2.from_angle(0.6)
	var side := ahead.orthogonal()
	var far_corner := Vector2(3.0, -4.0) + ahead * float(lane.length) - side * float(lane.half_width)
	var near_corner := Vector2(3.0, -4.0) + side * float(lane.half_width)
	check(far_left.distance_to(far_corner) < 0.001 or far_left.distance_to(far_corner + 2.0 * side * float(lane.half_width)) < 0.001,
		"the far end is the lane's length ahead (%s vs %s)" % [far_left, far_corner])
	check(near_right.distance_to(near_corner) < 0.001 or near_right.distance_to(near_corner - 2.0 * side * float(lane.half_width)) < 0.001,
		"the near end is at the creature (%s vs %s)" % [near_right, near_corner])
	check(t.basis.get_scale().is_equal_approx(Vector3(2.0 * float(lane.half_width), 1.0, float(lane.length))), "the lane's size")
	check(t.origin.y < 0.0 and t.origin.y > -0.1, "just under the swim plane")
	view.show_brain(_memory_in(view, "attack", "tell"), 137, 0.0)
	view._process(1.0 / 60.0)
	check_near(material.get_shader_parameter("fill"), 36.0 / 72.0, 1e-6, "filled halfway through the tell")
	check(view.lane_visible() and material.get_shader_parameter("strength") == 1.0, "and still at full strength")
	view.hide_lane()
	check(not view.lane_visible(), "a cancelled tell takes the lane down at once")
	view.show_lane(lane)
	view.hide_lane(0.3)
	view._process(0.15)
	check(view.lane_visible() and material.get_shader_parameter("strength") < 0.6, "a finished strike fades it out")
	view._process(0.2)
	check(not view.lane_visible(), "and then it is gone")
	view.free()


func test_the_lane_shader_never_draws_above_a_quarter_alpha() -> void:
	var code := (load("res://game/scenes/pool/threat_lane.gdshader") as Shader).code
	check(code.contains("const float MAX_ALPHA = 0.25;"), "the lane's alpha cap is 0.25 (plan section 14)")
	check(code.contains("ALPHA = min(a, MAX_ALPHA) * strength;"), "and every pixel is capped by it")
	var writes := Array(code.split("\n")).filter(func(line: String) -> bool: return line.strip_edges().begins_with("ALPHA"))
	check_eq(writes.size(), 1, "with no other alpha written")
	for name in ["BASE_ALPHA", "FILL_ALPHA", "CHEVRON_ALPHA"]:
		var at := code.find("const float %s = " % name)
		var value := float(code.substr(at).get_slice("=", 1).get_slice(";", 0))
		check(at >= 0 and value > 0.0 and value < 0.25, "%s is under the cap (%.2f)" % [name, value])


func test_the_player_view_builds_a_spike_model_for_a_spike_part() -> void:
	var view := (load(CELL_VIEW) as PackedScene).instantiate() as PlayerCellView
	var catalog := PartCatalog.load_from()
	var genome: Genome = Lineage.found(1, "test+dev", catalog, "grazer").save.genome
	genome.add_part("spike", 1.2)
	view.build(genome, Phenotype.derive(genome, catalog))
	var holder := view.part_nodes().back() as Node3D
	check_eq(holder.get_meta("part_type"), "spike", "the spike's holder")
	check_eq(holder.get_child_count(), 1, "with its model")
	if holder.get_child_count() == 1:
		check_eq(String(holder.get_child(0).scene_file_path), "res://assets/export/part_spike.glb", "the part_spike blockout")
	check(holder.transform.is_equal_approx(PartPlacement.transform_for(1.2, "spike")), "placed by PartPlacement")
	view.free()


func test_a_hit_flashes_and_flinches_the_cell_and_shelter_rims_it_softly() -> void:
	var view := (load(CELL_VIEW) as PackedScene).instantiate() as PlayerCellView
	var catalog := PartCatalog.load_from()
	var r := Lineage.found(1, "test+dev", catalog, "grazer")
	view.build(r.save.genome, Phenotype.derive(r.save.genome, catalog))
	view._process(0.01)
	check_eq((view.overlay_colors().tint as Color).a, 0.0, "no tint on a healthy cell")
	view.hurt()
	view._process(0.03)
	var tint: Color = view.overlay_colors().tint
	check(tint.a > 0.3 and tint.r > tint.g * 2.0, "a hit flashes the cell red (%s)" % tint)
	check(not (view.get_node("%Pivot") as Node3D).scale.is_equal_approx(Vector3.ONE), "and it flinches")
	view._process(0.2)
	check_eq((view.overlay_colors().tint as Color).a, 0.0, "the flash is gone after 0.15 s")
	check((view.get_node("%Pivot") as Node3D).scale.is_equal_approx(Vector3.ONE), "and so is the flinch")
	view.set_sheltered(true)
	var top := 0.0
	var low := 1.0
	for i in 120:
		view._process(1.0 / 60.0)
		var a := (view.overlay_colors().rim as Color).a
		if i >= 30:
			top = maxf(top, a)
			low = minf(low, a)
	check(top <= 0.25 + 1e-6 and top > 0.2, "the shelter rim pulses up to a quarter alpha (%.3f)" % top)
	check(low < top - 0.1, "and back down, once a second (%.3f)" % low)
	view.set_sheltered(false)
	for i in 30:
		view._process(1.0 / 60.0)
	check_eq((view.overlay_colors().rim as Color).a, 0.0, "the rim fades out when shelter ends")
	view.free()


func test_the_footprint_contains_every_floor_point_the_pool_camera_shows() -> void:
	var layout := PoolLayout.load_from()
	var camera := PoolCamera.new()
	camera.configure(layout.camera)
	var target := Vector2(3.0, 9.0)
	var size := Vector2(1920.0, 1080.0)
	var screen := Rect2(Vector2.ZERO, size)
	for zoom in [14.0, 20.0]:
		camera.distance = zoom
		camera.snap_to(PlaneSpace.to_world(target))
		var shown := 0
		var missed := PackedStringArray()
		for i in 20:
			for j in 10:
				var p := target + Vector2(-36.0 + 72.0 * i / 19.0, -22.0 + 34.0 * j / 9.0)
				var px := _unproject(camera, PlaneSpace.to_world(p), size)
				if px.x != px.x or not screen.has_point(px):   # NaN: behind the camera
					continue
				shown += 1
				if not ViewFootprint.contains(target, p, layout.camera, zoom, size.aspect(), 0.01):
					missed.append(str(p))
		check(shown > 20 and shown < 180, "zoom %d: the sample has points on and off the screen (%d on)" % [zoom, shown])
		check(missed.is_empty(), "zoom %d: shown but outside the footprint: %s" % [zoom, missed])
		var quad := ViewFootprint.corners(target, layout.camera, zoom, size.aspect())
		var center := (quad[0] + quad[1] + quad[2] + quad[3]) / 4.0
		var corners_shown := true
		for q in quad:
			corners_shown = corners_shown and screen.grow(1.0).has_point(_unproject(camera, PlaneSpace.to_world(q.lerp(center, 0.01)), size))
		check(corners_shown, "zoom %d: the footprint's corners are the screen's" % zoom)
	camera.free()


## Camera3D.unproject_position for a camera outside the scene tree (the test runner has no live
## viewport): the projection Camera3D builds for its keep-height fov, from the PoolCamera node's own
## fov, clip planes and transform. A live 1920x1080 SubViewport agreed with it within 0.001 px at
## zooms 14 and 20. A point behind the camera comes back as NaN.
func _unproject(camera: Camera3D, world: Vector3, size: Vector2) -> Vector2:
	var view := camera.transform.affine_inverse() * world
	if view.z >= 0.0:
		return Vector2(NAN, NAN)
	var clip := Projection.create_perspective(camera.fov, size.aspect(), camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * size.x, (1.0 - ndc.y) * 0.5 * size.y)


func test_the_tell_cues_last_as_long_as_the_species_tells() -> void:
	var lengths := PoolScene.tell_lengths(SpeciesCatalog.load_from())
	check_eq(lengths, {"lunge": 1.2, "puff": 1.2}, "both tells are 1.2 s in the data")
	var audio := PlaceholderAudio.new()
	check_near(audio.length_of("tell_lunge"), 1.2, 0.001, "the growl lasts the default tell")
	audio.configure_tells({"lunge": 1.5, "puff": 1.3})
	check_near(audio.length_of("tell_lunge"), 1.5, 0.001, "the growl follows the lunge tell")
	check_near(audio.length_of("tell_puff"), 1.3, 0.001, "the hiss follows the puff tell")
	for cue in PlaceholderAudio.CUES:
		check(audio.length_of(cue) > 0.05, "%s is synthesized" % cue)
	audio.free()
