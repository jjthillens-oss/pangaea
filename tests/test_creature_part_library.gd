extends TestCase
## Direct checks for the creature stage's imported-part cache and shape-key handle mapping.

const PartLibrary := preload("res://game/scenes/creature/part_library.gd")


func before_each() -> void:
	PartLibrary.clear()


func after_each() -> void:
	PartLibrary.clear()


func test_asset_paths_and_missing_parts() -> void:
	check_eq(
		PartLibrary.asset_path("cpart_beak.glb"), "res://assets/export/cpart_beak.glb", "part path"
	)
	check(PartLibrary.instance("no_such_part_type") == null, "a missing part has no instance")
	check(PartLibrary.instance("no_such_part_type") == null, "a cached miss stays absent")
	PartLibrary.clear()
	check(PartLibrary.instance("no_such_part_type") == null, "a miss stays safe after cache clear")


func test_existing_part_instances_are_independent() -> void:
	var first := PartLibrary.instance("beak")
	var second := PartLibrary.instance("beak")
	check(first != null and second != null, "the authored beak scene loads twice")
	if first != null and second != null:
		check(first != second, "each placement owns a distinct scene instance")
		check_eq(
			first.get_child_count(),
			second.get_child_count(),
			"instances have the same scene structure"
		)
	if first != null:
		first.free()
	if second != null:
		second.free()


func test_handles_apply_to_nested_matching_shape_keys_only() -> void:
	var part := Node3D.new()
	var group := Node3D.new()
	part.add_child(group)
	var mesh_instance := MeshInstance3D.new()
	group.add_child(mesh_instance)
	mesh_instance.mesh = _shape_mesh()
	var empty_mesh := MeshInstance3D.new()
	part.add_child(empty_mesh)
	PartLibrary.set_handles(part, [250, 800])
	check_near(
		mesh_instance.get_blend_shape_value(0), 0.25, 0.0001, "first handle uses per-mille units"
	)
	check_near(
		mesh_instance.get_blend_shape_value(1), 0.8, 0.0001, "second handle reaches nested meshes"
	)
	check_near(mesh_instance.get_blend_shape_value(2), 0.0, 0.0001, "unmatched shape is unchanged")
	PartLibrary.set_handles(part, [1000])
	check_near(
		mesh_instance.get_blend_shape_value(0), 1.0, 0.0001, "the first handle can be updated"
	)
	check_near(
		mesh_instance.get_blend_shape_value(1), 0.8, 0.0001, "an omitted handle keeps its value"
	)
	part.free()


func _shape_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for name in ["H1_width", "H2_bend", "unrelated"]:
		mesh.add_blend_shape(name)
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shapes := []
	for delta in [0.1, 0.2, 0.3]:
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[
				Vector3(0.0, 0.0, delta),
				Vector3(1.0, 0.0, delta),
				Vector3(0.0, 1.0, delta),
			]
		)
		shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	return mesh
