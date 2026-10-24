extends TestCase
## The plane mapping must agree with the rules (InteractionResolver angles) and with the sample
## cell's sockets, or the mouth the player sees would not be the mouth the rules use.

const SAMPLE_CELL := "res://assets/export/sample_cell.glb"


## Position of a named node relative to the scene root, computed without a scene tree.
func _socket_position(root: Node3D, socket: String) -> Vector3:
	var node := root.find_child(socket, true, false) as Node3D
	if node == null:
		return Vector3.INF
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t.origin


func test_a_model_yawed_for_a_heading_faces_that_heading_on_the_plane() -> void:
	for heading in [0.0, 0.7, -2.0, PI]:
		var facing := Basis(Vector3.UP, PlaneSpace.yaw_for_heading(heading)) * Vector3(0.0, 0.0, -1.0)
		var expected := PlaneSpace.to_world(Vector2.from_angle(heading))
		check(facing.is_equal_approx(expected), "heading %.2f: model faces %s, plane says %s" % [heading, facing, expected])


func test_round_trips_are_exact() -> void:
	var p := Vector2(12.345678901, -0.000123)
	check_eq(PlaneSpace.to_plane(PlaneSpace.to_world(p)), p, "plane -> world -> plane")
	check_eq(PlaneSpace.from_save(PlaneSpace.to_save(p)), p, "plane -> save -> plane")
	check_eq(PlaneSpace.to_world(p), Vector3(p.x, PlaneSpace.SWIM_Y, p.y), "plane y is world z")


func test_bad_saved_positions_are_not_a_place() -> void:
	check_eq(PlaneSpace.from_save([1.0, 2.0]), Vector2.INF, "two numbers")
	check_eq(PlaneSpace.from_save([1.0, 0.0, "x"]), Vector2.INF, "text")
	check_eq(PlaneSpace.from_save([NAN, 0.0, 1.0]), Vector2.INF, "NaN")
	check_eq(PlaneSpace.from_save([1, 0, 2]), Vector2(1.0, 2.0), "whole numbers are fine")


func test_food_at_world_plus_z_is_on_the_right_of_a_cell_heading_east() -> void:
	var actor := InteractionResolver.Actor.new("a", Vector2.ZERO, 0.0, Phenotype.new())
	var food := PlaneSpace.to_plane(Vector3(0.0, 0.0, 1.0))
	check_near(InteractionResolver.relative_angle(actor, food), PI / 2.0, 1e-6, "+Z is +PI/2")
	# Seen from above with north up, east-facing cell: +Z is screen-down, its right-hand side.
	var right := Basis(Vector3.UP, PlaneSpace.yaw_for_heading(0.0)) * PlaneSpace.part_local_dir(PI / 2.0)
	check(right.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "a +PI/2 part of that cell points at +Z, got %s" % right)


func test_part_directions_point_at_the_sample_cell_sockets() -> void:
	var packed: PackedScene = load(SAMPLE_CELL)
	check(packed != null, "sample cell loads")
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	var cases := {"socket_mouth": 0.0, "socket_side_R": PI / 2.0, "socket_tail": PI, "socket_side_L": -PI / 2.0}
	for socket in cases:
		var at := _socket_position(root, socket)
		check(at.is_finite(), "%s exists" % socket)
		if not at.is_finite():
			continue
		var flat := Vector3(at.x, 0.0, at.z).normalized()
		var dir := PlaneSpace.part_local_dir(cases[socket])
		check(dir.dot(flat) > 0.999, "%s: part at %.2f rad points at it (%s vs %s)" % [socket, cases[socket], dir, flat])
	root.free()


func test_a_ray_meets_the_swim_plane_or_reports_none() -> void:
	var hit = PlaneSpace.ray_to_plane(Vector3(1.0, 10.0, 2.0), Vector3(0.0, -1.0, 1.0).normalized())
	check(hit is Vector2, "downward ray hits")
	if hit is Vector2:
		check(hit.is_equal_approx(Vector2(1.0, 12.0)), "hit point, got %s" % hit)
	check(PlaneSpace.ray_to_plane(Vector3(0.0, 5.0, 0.0), Vector3(1.0, 0.0, 0.0)) == null, "parallel ray")
	check(PlaneSpace.ray_to_plane(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 1.0, 0.0)) == null, "ray pointing away")


# Endless saves (S1 T3.1): an absolute position in float64, never through a float32 Vector2.

## Values a float32 cannot hold, at 5 km, 100 km and 1e9 m: a Vector2 anywhere on the path shows.
const FAR_VALUES := [5000.123456789012, -3.25, 100000.3, -100000.7, 1000000000.123, -999999999.987]


func test_to_save_abs_writes_three_float64_numbers_with_y_zero() -> void:
	var a := PlaneSpace.to_save_abs(5000.123456789012, -3.25)
	check_eq(a, [5000.123456789012, 0.0, -3.25], "x, swim plane, y")
	for value in a:
		check_eq(typeof(value), TYPE_FLOAT, "every number is a float: %s" % [a])
	check(Vector2(a[0], 0.0).x != a[0], "the test value is one a float32 cannot hold")
	for i in range(0, FAR_VALUES.size(), 2):
		var x: float = FAR_VALUES[i]
		var y: float = FAR_VALUES[i + 1]
		var far := PlaneSpace.to_save_abs(x, y)
		check(far[0] == x and far[2] == y and far[1] == PlaneSpace.SWIM_Y, "(%.9f, %.9f) kept exactly: %s" % [x, y, far])


func test_from_save_abs_returns_the_two_float64_values_exactly() -> void:
	for i in range(0, FAR_VALUES.size(), 2):
		var x: float = FAR_VALUES[i]
		var y: float = FAR_VALUES[i + 1]
		check(Vector2(x, y).x != x or Vector2(x, y).y != y, "(%.9f, %.9f) is beyond float32" % [x, y])
		var back := PlaneSpace.from_save_abs([x, 0.0, y])
		check_eq(back.size(), 2, "two numbers")
		if back.size() == 2:
			check(back[0] == x and back[1] == y, "(%.9f, %.9f) came back as (%.9f, %.9f)" % [x, y, back[0], back[1]])
		var round_trip := PlaneSpace.from_save_abs(PlaneSpace.to_save_abs(x, y))
		check_eq(round_trip, PackedFloat64Array([x, y]), "to_save_abs then from_save_abs at (%.9f, %.9f)" % [x, y])
	check_eq(PlaneSpace.from_save_abs([3, 0, 4]), PackedFloat64Array([3.0, 4.0]), "whole numbers are their values")
	check_eq(PlaneSpace.from_save_abs([1.5, 7.0, 2.5]), PackedFloat64Array([1.5, 2.5]), "the height is not the plane")


func test_from_save_abs_refuses_non_arrays_wrong_sizes_and_non_finite() -> void:
	var bad := [null, {}, "1, 0, 2", PackedFloat64Array([1.0, 0.0, 2.0]), [1, 2], [1, 2, 3, 4], ["1", 0, 0],
		[1.0, 0.0, true], [INF, 0, 0], [0, 0, -INF], [NAN, 0, 0], [0, NAN, 0], [[1], 0, 0]]
	for a in bad:
		check_eq(PlaneSpace.from_save_abs(a), PackedFloat64Array(), "refused: %s" % [a])


func test_from_save_keeps_its_float32_meaning_for_pool_saves() -> void:
	check_eq(PlaneSpace.from_save([100000.3, 0, 0]).x, 100000.296875, "pool mode reads a float32 place")
	check_eq(PlaneSpace.to_save(Vector2(100000.3, -2.0)), [100000.296875, 0.0, -2.0], "and writes one")
