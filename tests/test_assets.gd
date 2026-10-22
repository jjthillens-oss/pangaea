extends TestCase
## Asset admission checks (Bible sections 16 and 22): every export has a record and a Blender
## source, loads in Godot, and arrives at the agreed scale and orientation.

const RECORDS_DIR := "res://assets/records"
const LAYOUT_PATH := "res://game/data/pool_m1.json"
const BLOCKOUT_REVIEW := "blockout - M1 step 2, not visually approved"
## Triangle budgets from the M1 step 2 plan, kept here so a record cannot loosen its own.
const BLOCKOUT_BUDGETS := {
	"pool_floor": 20000,
	"rock_a": 1300, "rock_b": 1300, "rock_c": 1300,
	"plankton": 400, "carrion": 400,
	"part_mouth_filter": 1500, "part_mouth_jaw": 1500, "part_flagellum": 1500, "part_eye_spot": 1500,
}
const PART_IDS := ["part_mouth_filter", "part_mouth_jaw", "part_flagellum", "part_eye_spot"]
const ROCK_IDS := ["rock_a", "rock_b", "rock_c"]
## Food record id -> its block in the pool layout, which holds the gameplay item_radius.
const FOOD_LAYOUT_KEYS := {"plankton": "plankton", "carrion": "carrion"}


## Top-level records only: get_files_at lists no folders, so assets/records/placeholders/ is skipped.
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


func _record(id: String) -> Dictionary:
	var path := RECORDS_DIR + "/%s.json" % id
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## The pool layout, or {} until the pool systems add it.
func _layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return data if data is Dictionary else {}


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			out.append(n)
	return out


## Every mesh vertex under `root`, in root space.
func _vertices(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		var t := _relative(mi, root)
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(t * v)
	return out


## Widest distance of any point from the vertical axis through the origin.
func _horizontal_radius(points: PackedVector3Array) -> float:
	var r := 0.0
	for p in points:
		r = maxf(r, Vector2(p.x, p.z).length())
	return r


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


func test_every_record_with_dimensions_matches_its_export() -> void:
	for record in _records():
		if not record.has("dimensions_m"):
			continue
		var node := _load_scene("res://" + record.export_path)
		if node == null:
			check(false, "%s loads" % record.id)
			continue
		var size := _mesh_bounds(node).size
		var dims: Dictionary = record.dimensions_m
		# Blender X -> Godot X, Blender Z (up) -> Godot Y, Blender Y (forward) -> Godot Z.
		check_near(size.x, dims.x, 0.05, "%s width" % record.id)
		check_near(size.y, dims.z_up, 0.05, "%s height" % record.id)
		check_near(size.z, dims.y_forward, 0.05, "%s length" % record.id)
		node.free()


func test_blockout_records_are_proposed_unapproved_and_within_budget() -> void:
	for id in BLOCKOUT_BUDGETS:
		var record := _record(id)
		if record.is_empty():
			check(false, "%s has a record" % id)
			continue
		check_eq(record.get("status"), "PROPOSED", "%s status" % id)
		check_eq(record.get("review_state"), BLOCKOUT_REVIEW, "%s review state" % id)
		check(String(record.get("provenance", "")).contains("procedurally"), "%s provenance is procedural" % id)
		var tris := int(record.get("triangles", 1 << 30))
		check(tris > 0 and tris <= BLOCKOUT_BUDGETS[id], "%s has %d triangles, budget %d" % [id, tris, BLOCKOUT_BUDGETS[id]])


func test_parts_start_at_their_attachment_point_and_extend_forward() -> void:
	var catalog := PartCatalog.load_from()
	for id in PART_IDS:
		var record := _record(id)
		check(catalog.has_part(String(record.get("part_type", ""))), "%s names a catalog part" % id)
		var node := _load_scene("res://assets/export/%s.glb" % id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		# The origin is the attachment point and Blender +Y (outward) is Godot -Z, so a part may
		# sink only a little into the body behind its origin.
		var box := _mesh_bounds(node)
		check(box.end.z <= 0.05, "%s reaches at most 0.05 m behind its origin, got %.3f" % [id, box.end.z])
		check(box.get_center().z < -0.05, "%s extends outward along -Z, centre z %.3f" % [id, box.get_center().z])
		node.free()


func test_food_is_one_mesh_sized_to_its_item_radius() -> void:
	var layout := _layout()
	for id in FOOD_LAYOUT_KEYS:
		var record := _record(id)
		var item_radius := float(record.get("item_radius_m", 0.0))
		if not layout.is_empty():
			var block: Dictionary = layout.get(FOOD_LAYOUT_KEYS[id], {})
			check_near(item_radius, float(block.get("item_radius", -1.0)), 0.0001, "%s record item radius matches the layout" % id)
			item_radius = float(block.get("item_radius", item_radius))
		check(item_radius > 0.0, "%s has an item radius" % id)
		var node := _load_scene("res://assets/export/%s.glb" % id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		# The pool draws food with a MultiMesh, which takes exactly one mesh.
		check_eq(_mesh_instances(node).size(), 1, "%s MeshInstance3D count" % id)
		var radius := _horizontal_radius(_vertices(node))
		check_near(radius, item_radius, 0.2 * item_radius, "%s mesh radius within 20%% of the item radius" % id)
		node.free()


func test_rocks_fit_their_footprint_and_stay_low_enough_to_read_as_obstacles() -> void:
	for id in ROCK_IDS:
		var footprint := float(_record(id).get("footprint_radius_m", 0.0))
		check(footprint > 0.0, "%s record has footprint_radius_m" % id)
		var node := _load_scene("res://assets/export/%s.glb" % id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		var verts := _vertices(node)
		var box := _mesh_bounds(node)
		check_near(_horizontal_radius(verts), footprint, 0.15 * footprint, "%s widest radius" % id)
		check(box.end.y <= 0.6, "%s top at scale 1 is %.3f m, at most 0.6" % [id, box.end.y])
		# Pivot on the swim plane at the footprint centre, buried to the bowl's deepest point (-1.6 m).
		check(box.position.y <= -1.6 and box.end.y > 0.0, "%s spans the swim plane down to the floor" % id)
		check(Vector2(box.get_center().x, box.get_center().z).length() <= 0.15, "%s is centred on its pivot" % id)
		# What the cell sees around its own height is about as wide as the collision circle.
		var band := PackedVector3Array()
		for v in verts:
			if absf(v.y) <= 0.45:
				band.append(v)
		check(_horizontal_radius(band) >= 0.85 * footprint, "%s is as wide as its footprint at the swim plane" % id)
		node.free()


func test_pool_floor_stays_under_the_cell_and_rises_into_a_rim() -> void:
	var node := _load_scene("res://assets/export/pool_floor.glb")
	if node == null:
		check(false, "pool_floor loads")
		return
	# The cell's centre stops at r = 39 and the cell reaches 0.39 m below the swim plane.
	var highest_inside := -INF
	var lowest_rim := INF
	for v in _vertices(node):
		var r := Vector2(v.x, v.z).length()
		if r <= 39.0:
			highest_inside = maxf(highest_inside, v.y)
		elif r >= 41.5 and r <= 43.0:
			lowest_rim = minf(lowest_rim, v.y)
	check(highest_inside > -INF and lowest_rim < INF, "floor has vertices inside r 39 and on the rim")
	check(highest_inside <= -0.45, "inside r 39 the floor is at most -0.45 m, got %.3f" % highest_inside)
	check(lowest_rim > 0.8, "over r 41.5-43 the rim is above +0.8 m, got %.3f" % lowest_rim)
	var box := _mesh_bounds(node)
	check(box.position.x <= -57.95 and box.end.x >= 57.95 and box.position.z <= -57.95 and box.end.z >= 57.95,
			"floor runs to r 58 so the camera never sees past it")
	var materials := {}
	for mi in _mesh_instances(node):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			materials[mat.resource_name if mat else ""] = true
	var names: Array = materials.keys()
	names.sort()
	check_eq(names, ["M_PoolRimStone", "M_PoolSand", "M_PoolSilt"], "floor materials")
	node.free()


func test_sample_cell_has_the_nodes_the_pool_hides_and_keeps() -> void:
	var node := _load_scene("res://assets/export/sample_cell.glb")
	if node == null:
		check(false, "sample_cell loads")
		return
	# The pool hides the baked mouth and flagellum (genome parts replace them) and keeps the eyes.
	for path in ["Body/Mouth", "Body/Flagellum", "Body/Pupil_L", "Body/Pupil_R"]:
		check(node.get_node_or_null(path) is MeshInstance3D, "sample_cell has %s" % path)
	node.free()
