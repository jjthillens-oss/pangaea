extends TestCase
## Asset admission checks (Bible sections 16 and 22): every export has a record and a Blender
## source, loads in Godot, and arrives at the agreed scale and orientation.

const RECORDS_DIR := "res://assets/records"


func _records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(RECORDS_DIR):
		if f.ends_with(".json"):
			out.append(JSON.parse_string(FileAccess.get_file_as_string(RECORDS_DIR + "/" + f)))
	return out


func _load_scene(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	return packed.instantiate() if packed else null


## Transform of `node` relative to `root`, computed without a scene tree.
func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _mesh_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh:
			var box := _relative(n, root) * (n as MeshInstance3D).mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds


func test_every_export_has_a_record_and_blender_source() -> void:
	var exported := {}
	for f in DirAccess.get_files_at("res://assets/export"):
		if f.ends_with(".glb"):
			exported["assets/export/" + f] = false
	for record in _records():
		var src: String = record.get("source_blend", "")
		check(src.ends_with(".blend") and FileAccess.file_exists("res://" + src), "%s: Blender source %s exists" % [record.get("id"), src])
		check(exported.has(record.get("export_path", "")), "%s: export listed in assets/export" % record.get("id"))
		exported[record.get("export_path", "")] = true
		for key in ["id", "owner", "revision", "dimensions_m", "triangles", "provenance", "review_state"]:
			check(record.has(key), "%s: record has %s" % [record.get("id"), key])
	for path in exported:
		check(exported[path], "%s has an asset record" % path)


func test_every_export_loads() -> void:
	for record in _records():
		var node := _load_scene("res://" + record.export_path)
		check(node != null, "%s loads as a scene" % record.id)
		if node:
			node.free()


func test_sample_cell_scale_matches_blender_meters() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDS_DIR + "/sample_cell.json"))
	var node := _load_scene("res://assets/export/sample_cell.glb")
	if node == null:
		check(false, "sample_cell loads")
		return
	var size := _mesh_bounds(node).size
	# Blender X -> Godot X, Blender Z (up) -> Godot Y, Blender Y (forward) -> Godot Z.
	check_near(size.x, record.dimensions_m.x, 0.05, "width")
	check_near(size.y, record.dimensions_m.z_up, 0.05, "height")
	check_near(size.z, record.dimensions_m.y_forward, 0.05, "length")
	node.free()


func test_sample_cell_faces_godot_forward_and_has_sockets() -> void:
	var node := _load_scene("res://assets/export/sample_cell.glb")
	if node == null:
		check(false, "sample_cell loads")
		return
	for socket in ["socket_mouth", "socket_tail", "socket_top", "socket_side_L", "socket_side_R"]:
		check(node.find_child(socket, true, false) != null, "has %s" % socket)
	var mouth: Node3D = node.find_child("socket_mouth", true, false)
	var top: Node3D = node.find_child("socket_top", true, false)
	var left: Node3D = node.find_child("socket_side_L", true, false)
	if mouth and top and left:
		var m := _relative(mouth, node).origin
		check(m.z < -0.3 and absf(m.x) < 0.01, "mouth points to Godot forward (-Z), got %s" % m)
		check(_relative(top, node).origin.y > 0.3, "top socket points up (+Y)")
		check(_relative(left, node).origin.x < -0.3, "left socket is on -X")
	node.free()
