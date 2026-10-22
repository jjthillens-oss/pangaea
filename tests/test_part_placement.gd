extends TestCase
## Genome parts must sit where the rules say they are: a part at angle 0 on the mouth socket,
## +PI/2 on the cell's right, PI on the tail, each pointing outward from the body. The cell view
## must build one part node per genome part and draw the sim's position exactly.

const SAMPLE_CELL := "res://assets/export/sample_cell.glb"
const CELL_VIEW := "res://game/scenes/pool/player_cell_view.tscn"
const SOCKET_TOLERANCE_M := 0.03


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


func _genome(body: String) -> Genome:
	var catalog := PartCatalog.load_from()
	return Lineage.found(7, "test+dev", catalog, body).save.genome


func test_parts_at_the_socket_angles_land_on_the_sample_cell_sockets() -> void:
	var packed: PackedScene = load(SAMPLE_CELL)
	check(packed != null, "sample cell loads")
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	var cases := {"socket_mouth": 0.0, "socket_side_R": PI / 2.0, "socket_tail": PI, "socket_side_L": -PI / 2.0}
	for socket in cases:
		var at := _socket_position(root, socket)
		check(at.is_finite(), "%s exists" % socket)
		for type in ["mouth_filter", "mouth_jaw", "flagellum"]:
			var placed := PartPlacement.transform_for(cases[socket], type).origin
			check(placed.distance_to(at) <= SOCKET_TOLERANCE_M,
				"%s at %.2f rad lands on %s: %s vs %s" % [type, cases[socket], socket, placed, at])
	root.free()


func test_a_parts_minus_z_axis_is_the_outward_surface_normal() -> void:
	for type in ["mouth_filter", "flagellum", "eye_spot"]:
		for i in 16:
			var angle := -PI + TAU * i / 16.0
			var t := PartPlacement.transform_for(angle, type)
			var forward := -t.basis.z.normalized()
			var normal := PartPlacement.outward_normal(t.origin)
			check(forward.is_equal_approx(normal), "%s at %.2f: -Z %s is the normal %s" % [type, angle, forward, normal])
			var radial := Vector3(t.origin.x, 0.0, t.origin.z).normalized()
			check(forward.dot(radial) > 0.5, "%s at %.2f points away from the body" % [type, angle])
			check(t.basis.y.normalized().dot(Vector3.UP) > 0.5, "%s at %.2f keeps its top up" % [type, angle])


func test_on_the_equator_the_normal_is_the_planned_horizontal_one() -> void:
	for angle in [0.3, 1.2, -2.0, 2.8]:
		var t := PartPlacement.transform_for(angle, "flagellum")
		var planned := Vector3(sin(angle) / PartPlacement.RX, 0.0, -cos(angle) / PartPlacement.RZ).normalized()
		check((-t.basis.z).normalized().is_equal_approx(planned), "angle %.2f" % angle)
		check_near(t.origin.y, 0.0, 1e-6, "on the swim plane")


func test_the_eye_spot_sits_up_on_the_body_surface() -> void:
	for angle in [0.0, 0.6, -1.4]:
		var p := PartPlacement.transform_for(angle, "eye_spot").origin
		check_near(p.y, 0.18, 1e-6, "eye spot height")
		var on_surface := pow(p.x / PartPlacement.RX, 2) + pow(p.y / PartPlacement.RY, 2) + pow(p.z / PartPlacement.RZ, 2)
		check_near(on_surface, 1.0, 1e-5, "eye spot at %.2f lies on the ellipsoid" % angle)


func test_a_part_angle_on_the_right_is_on_the_cells_right_in_the_world() -> void:
	# Cell heading east: its right is world +Z (PlaneSpace); a part at +PI/2 must point there.
	var yaw := Basis(Vector3.UP, PlaneSpace.yaw_for_heading(0.0))
	var t := PartPlacement.transform_for(PI / 2.0, "flagellum")
	check((yaw * t.origin).normalized().is_equal_approx(Vector3(0.0, 0.0, 1.0)), "position on world +Z")
	check((yaw * -t.basis.z).normalized().is_equal_approx(Vector3(0.0, 0.0, 1.0)), "pointing at world +Z")


func test_scale_grows_a_part_uniformly_without_moving_it() -> void:
	var one := PartPlacement.transform_for(0.7, "flagellum")
	var two := PartPlacement.transform_for(0.7, "flagellum", 2.0)
	check(one.origin.is_equal_approx(two.origin), "same attachment point")
	check_near(two.basis.get_scale().x, 2.0, 1e-5, "x scale")
	check_near(two.basis.get_scale().z, 2.0, 1e-5, "z scale")


func test_the_cell_view_builds_one_node_per_genome_part() -> void:
	var view := (load(CELL_VIEW) as PackedScene).instantiate() as PlayerCellView
	var catalog := PartCatalog.load_from()
	for body in ["grazer", "hunter", "omnivore"]:
		var genome := _genome(body)
		view.build(genome, Phenotype.derive(genome, catalog))
		var nodes := view.part_nodes()
		check_eq(nodes.size(), genome.parts.size(), "%s part nodes" % body)
		for i in mini(nodes.size(), genome.parts.size()):
			var node := nodes[i] as Node3D
			var part: Dictionary = genome.parts[i]
			check_eq(node.get_meta("part_type"), part.type, "%s part %d type" % [body, i])
			check_near(node.get_meta("part_angle"), part.angle, 1e-9, "%s part %d angle" % [body, i])
			check(node.transform.is_equal_approx(PartPlacement.transform_for(part.angle, part.type, part.scale)),
				"%s part %d placed by PartPlacement" % [body, i])
			check_eq(node.get_child_count(), 1, "%s part %d has its model" % [body, i])
	var model := view.get_node("%Model")
	for path in PlayerCellView.HIDDEN_MODEL_NODES:
		var baked := model.get_node_or_null(path) as Node3D
		check(baked != null and not baked.visible, "baked %s is hidden" % path)
	check((model.get_node_or_null("Body/Pupil_L") as Node3D).visible, "the sample's eyes stay")
	view.free()


func test_a_part_without_a_model_still_gets_a_node() -> void:
	var view := (load(CELL_VIEW) as PackedScene).instantiate() as PlayerCellView
	var catalog := PartCatalog.load_from()
	var genome := _genome("grazer")
	genome.add_part("spike", -1.0)
	view.build(genome, Phenotype.derive(genome, catalog))
	var nodes := view.part_nodes()
	check_eq(nodes.size(), 4, "every part has a node")
	check_eq(nodes[3].get_meta("part_type"), "spike", "the spike marker")
	check_eq(nodes[3].get_child_count(), 0, "no model until step 4")
	view.free()


func test_the_view_draws_the_sim_position_and_heading() -> void:
	var view := (load(CELL_VIEW) as PackedScene).instantiate() as PlayerCellView
	var motion := Locomotion.MotionState.new(Vector2(3.0, -2.0), 0.4)
	motion.position = Vector2(3.1, -1.95)
	motion.heading = 0.5
	view.show_motion(motion, 1.0)
	check(view.position.distance_to(PlaneSpace.to_world(motion.position)) < 0.001, "at the current tick")
	check_near(view.rotation.y, PlaneSpace.yaw_for_heading(0.5), 1e-5, "facing the current heading")
	view.show_motion(motion, 0.0)
	check(view.position.distance_to(PlaneSpace.to_world(motion.prev_position)) < 0.001, "at the previous tick")
	view.show_motion(motion, 0.5)
	check(view.position.distance_to(PlaneSpace.to_world(Vector2(3.05, -1.975))) < 0.001, "halfway")
	view.free()
