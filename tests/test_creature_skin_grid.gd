extends TestCase
## Direct grid-layout gates for the creature skin builders. The shared grid must leave room beyond
## the body's bounds so the extracted surface can close without touching a boundary cell.

const SkinGrid := preload("res://game/systems/creature/skin_grid.gd")


class BoxDescription:
	extends RefCounted
	var box: AABB
	var radius: float

	func _init(body_box: AABB, maximum_radius: float) -> void:
		box = body_box
		radius = maximum_radius

	func bounds_m() -> AABB:
		return box

	func max_radius_m() -> float:
		return radius


func test_grid_contains_an_offset_body_with_the_blend_margin() -> void:
	var desc := BoxDescription.new(AABB(Vector3(3.0, -2.0, 7.0), Vector3(4.0, 2.0, 1.0)), 0.8)
	var grid: Dictionary = SkinGrid.layout(desc, 20)
	var cell: float = grid.cell
	var low: Vector3 = grid.origin
	var high: Vector3 = low + Vector3(grid.dims - Vector3i.ONE) * cell
	var required_margin := 0.15 * desc.radius + 2.0 * cell
	check(is_equal_approx(cell, 0.2), "cell size follows the longest 4 m axis at 20 divisions")
	for axis in 3:
		check(
			desc.box.position[axis] - low[axis] >= required_margin - 0.00001,
			"low grid face %d leaves the blend and two-cell margin" % axis
		)
		check(
			high[axis] - desc.box.end[axis] >= required_margin - 0.00001,
			"high grid face %d leaves the blend and two-cell margin" % axis
		)


func test_grid_resolution_changes_cell_size_without_losing_coverage() -> void:
	var desc := BoxDescription.new(AABB(Vector3(-1.0, 2.0, -3.0), Vector3(6.0, 1.0, 2.0)), 0.5)
	var coarse: Dictionary = SkinGrid.layout(desc, 12)
	var fine: Dictionary = SkinGrid.layout(desc, 24)
	check(
		is_equal_approx(fine.cell * 2.0, coarse.cell),
		"doubling divisions halves the sample spacing"
	)
	for grid in [coarse, fine]:
		var end: Vector3 = grid.origin + Vector3(grid.dims - Vector3i.ONE) * grid.cell
		for axis in 3:
			check(
				grid.origin[axis] < desc.box.position[axis] and end[axis] > desc.box.end[axis],
				"both resolutions contain the full body on axis %d" % axis
			)


func test_translating_the_body_translates_the_grid_without_changing_shape() -> void:
	var box := AABB(Vector3(-2.0, -1.0, 0.0), Vector3(3.0, 4.0, 5.0))
	var shift := Vector3(11.0, -7.0, 2.5)
	var a: Dictionary = SkinGrid.layout(BoxDescription.new(box, 1.0), 20)
	var b: Dictionary = SkinGrid.layout(
		BoxDescription.new(AABB(box.position + shift, box.size), 1.0), 20
	)
	check(
		a.dims == b.dims and is_equal_approx(a.cell, b.cell),
		"translation preserves dimensions and spacing"
	)
	check(
		a.origin.is_equal_approx(b.origin - shift),
		"translation moves the grid origin by the same offset"
	)
