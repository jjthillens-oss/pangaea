extends TestCase
## ViewFootprint (M1 step 3): the swim plane the north-up pool camera shows, as a trapezoid from the
## layout's camera settings, and a contains() test grown by a margin. The numbers are the step 3
## plan's camera table (pitch 55 degrees, vertical field of view 45 degrees).

var camera: Dictionary


func before_each() -> void:
	camera = PoolLayout.load_from().camera


## [ahead, behind, far corner distance] of the trapezoid around a look target.
func _measure(target: Vector2, distance: float, aspect: float) -> Array:
	var q := ViewFootprint.corners(target, camera, distance, aspect)
	return [target.y - q[0].y, q[3].y - target.y, maxf(q[0].distance_to(target), q[1].distance_to(target))]


func test_the_camera_settings_are_the_ones_the_numbers_were_measured_for() -> void:
	check_eq(camera.pitch_deg, 55.0, "pitch")
	check_eq(camera.fov_deg, 45.0, "vertical field of view")
	check_eq(camera.distance, 14.0, "default zoom")
	check_eq(camera.zoom_max, 20.0, "maximum zoom")


func test_the_corners_match_the_measured_footprint() -> void:
	# zoom, aspect, ahead, behind, corner distance (-1: not measured)
	var table := [
		[10.0, 16.0 / 9.0, 7.12, 3.92, -1.0],
		[14.0, 16.0 / 9.0, 9.97, 5.49, 17.61],
		[14.0, 2.4, 9.97, 5.49, 21.99],
		[20.0, 16.0 / 9.0, 14.24, 7.84, 25.16],
		[20.0, 2.4, 14.24, 7.84, 31.42],
	]
	for target in [Vector2.ZERO, Vector2(0.0, 9.0), Vector2(-24.1, 16.6)]:
		for row in table:
			var got := _measure(target, row[0], row[1])
			var label := "zoom %d aspect %.2f at %s" % [row[0], row[1], target]
			check_near(got[0], row[2], 0.01, label + ": ahead (north)")
			check_near(got[1], row[3], 0.01, label + ": behind (south)")
			if row[4] > 0.0:
				check_near(got[2], row[4], 0.01, label + ": far corner")


func test_the_footprint_is_a_trapezoid_wider_at_the_far_end() -> void:
	var q := ViewFootprint.corners(Vector2(2.0, 3.0), camera, 14.0, 16.0 / 9.0)
	check_eq(q.size(), 4, "four corners")
	check_near(q[0].y, q[1].y, 1e-6, "the far edge runs east-west")
	check_near(q[2].y, q[3].y, 1e-6, "so does the near edge")
	check(q[0].y < q[3].y, "far is north of near")
	check(q[1].x - q[0].x > q[2].x - q[3].x, "wider at the far end")
	check_near((q[0].x + q[1].x) / 2.0, 2.0, 1e-5, "centred on the target's x")


func test_contains_is_true_at_the_target_and_false_just_outside_each_edge() -> void:
	for zoom in [14.0, 20.0]:
		for aspect in [16.0 / 9.0, 2.4]:
			var target := Vector2(5.0, -3.0)
			var q := ViewFootprint.corners(target, camera, zoom, aspect)
			check(ViewFootprint.contains(target, target, camera, zoom, aspect), "the look target")
			for i in 4:
				var a := q[i]
				var b := q[(i + 1) % 4]
				var mid := (a + b) / 2.0
				# Clockwise on screen (y down), the inside is on each edge's right, so orthogonal() points out.
				var outward := (b - a).normalized().orthogonal()
				check(ViewFootprint.contains(target, mid - outward * 0.01, camera, zoom, aspect), "zoom %d aspect %.2f: 1 cm inside edge %d" % [zoom, aspect, i])
				check(not ViewFootprint.contains(target, mid + outward * 0.01, camera, zoom, aspect), "zoom %d aspect %.2f: 1 cm outside edge %d" % [zoom, aspect, i])
				check(ViewFootprint.contains(target, a, camera, zoom, aspect), "corner %d is on the footprint" % i)


func test_a_margin_grows_the_footprint_by_a_disc() -> void:
	var target := Vector2.ZERO
	var q := ViewFootprint.corners(target, camera, 20.0, 2.4)
	var north := Vector2(0.0, q[0].y - 3.0)
	check(not ViewFootprint.contains(target, north, camera, 20.0, 2.4), "3 m past the far edge")
	check(not ViewFootprint.contains(target, north, camera, 20.0, 2.4, 2.99), "a 2.99 m margin does not reach it")
	check(ViewFootprint.contains(target, north, camera, 20.0, 2.4, 3.01), "a 3.01 m margin does")
	# Past a corner the margin is round: 3 m out along the diagonal, not 3 m out on both axes.
	var diagonal := q[0] + Vector2(-1.0, -1.0).normalized() * 3.0
	check(ViewFootprint.contains(target, diagonal, camera, 20.0, 2.4, 3.01), "3 m out past a corner")
	check(not ViewFootprint.contains(target, q[0] + Vector2(-3.0, -3.0), camera, 20.0, 2.4, 3.01), "but not 3 m out on both axes")
	check_near(ViewFootprint.distance_outside(q, diagonal), 3.0, 1e-4, "the distance outside")
	check_eq(ViewFootprint.distance_outside(q, target), 0.0, "zero inside")


func test_a_camera_that_sees_the_horizon_has_no_footprint_and_contains_everything() -> void:
	var flat := {"pitch_deg": 20.0, "fov_deg": 45.0}
	check(ViewFootprint.corners(Vector2.ZERO, flat, 14.0, 2.4).is_empty(), "no far edge")
	check(ViewFootprint.contains(Vector2.ZERO, Vector2(0.0, -500.0), flat, 14.0, 2.4), "so nothing is safely out of view")
