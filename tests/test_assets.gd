extends TestCase
## Asset admission checks (Bible sections 16 and 22): every export has a record and a Blender
## source, loads in Godot, and arrives at the agreed scale and orientation.

const RECORDS_DIR := "res://assets/records"
const LAYOUT_PATH := "res://game/data/pool_m1.json"
const BLOCKOUT_REVIEW := "blockout - M1 step 2, not visually approved"
## Production replacements (tools/blender/make_m1_production.py) keep the blockout's id, contract
## and budget; they are PROPOSED until Joshua reviews the look.
const PRODUCTION_REVIEW := "production rev 1 - M1, awaiting owner look review"
## Texture sizes allowed by the art direction (section 4): 512 px for microscopic creatures and
## props, up to 2048 px for prominent assets.
const MAX_TEXTURE_PX := 2048
## Triangle budgets from the M1 step 2 plan, kept here so a record cannot loosen its own.
const BLOCKOUT_BUDGETS := {
	"pool_floor": 20000,
	"rock_a": 1300, "rock_b": 1300, "rock_c": 1300,
	"plankton": 400, "carrion": 400,
	"part_mouth_filter": 1500, "part_mouth_jaw": 1500, "part_flagellum": 1500, "part_eye_spot": 1500,
}
const PART_IDS := ["part_mouth_filter", "part_mouth_jaw", "part_flagellum", "part_eye_spot", "part_spike"]
const ROCK_IDS := ["rock_a", "rock_b", "rock_c"]
## Food record id -> its block in the pool layout, which holds the gameplay item_radius.
const FOOD_LAYOUT_KEYS := {"plankton": "plankton", "carrion": "carrion"}
## The screen shape the pool view is planned for (1080p).
const SCREEN_ASPECT := 16.0 / 9.0
## The pool floor's shelf starts here; past it the floor is flat at about +1.0 m.
const FLOOR_SHELF_R := 45.0
## The cell's height band around the swim plane: it reaches 0.39 m above and below it.
const SWIM_BAND_M := 0.45
## Section heights through the swim band, for rock outlines.
const SWIM_BAND_HEIGHTS: Array[float] = [-0.45, -0.3375, -0.225, -0.1125, 0.0, 0.1125, 0.225, 0.3375, 0.45]
## The step 3 threat blockouts (step 3 plan section 17): their review state, generator and
## triangle budgets, kept here so a record cannot loosen its own.
const THREAT_REVIEW := "blockout - M1 step 3, not visually approved"
const THREAT_GENERATOR := "tools/blender/make_m1_threats.py"
const THREAT_BUDGETS := {"creature_ambush_body": 4000, "creature_rammer_body": 4000, "part_spike": 600}
## Nodes under Body that the creature view poses, by body.
const THREAT_POSE_NODES := {
	"creature_ambush_body": ["Eye_L", "Eye_R", "Brow"],
	"creature_rammer_body": ["Eye_L", "Eye_R", "Hood"],
}
## Silhouette contracts. The ambush hunter at its body_size is at least AMBUSH_FOOTPRINT_SHARE
## times as long and wide as the sample cell (compared as the square root of their top-down
## areas), and its height is at most AMBUSH_MAX_HEIGHT_SHARE of its width. A spike at scale 1
## reaches SPIKE_MIN_REACH_M past the body outline. Bodies meet the swim plane on PartPlacement's
## ellipse to within FRAME_TOLERANCE_M, so every part GLB sits on their surface.
const AMBUSH_FOOTPRINT_SHARE := 1.4
const AMBUSH_MAX_HEIGHT_SHARE := 0.35
const SPIKE_MIN_REACH_M := 0.25
const FRAME_TOLERANCE_M := 0.01
## The species data gives the ambush hunter's body_size; until it exists, the plan's value.
const CREATURES_PATH := "res://game/data/creatures_m1.json"
const AMBUSH_PLANNED_SIZE := 1.5
## docs/art/ART_DIRECTION.md: the threat colour goes on spikes and attack tells; eyes may be amber.
const THREAT_COLOR := Color("#D9466B")
const MINERAL_AMBER := Color("#E3A64A")


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


## The pool layout as raw data, or {} when it is missing or not an object.
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


## The outline of `root`'s triangles seen from above over `heights`: for each 1-degree azimuth
## bin, the farthest point of any horizontal section at those heights (0 where none reaches).
## Each cut is sampled densely, so sparse vertices never read as a narrow side. With `only`, just
## that mesh instance's own triangles count (in root space).
func _section_outline(root: Node3D, heights: Array[float], only: MeshInstance3D = null) -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(360)
	var instances := _mesh_instances(root)
	if only != null:
		instances = [only]
	for mi in instances:
		var t := _relative(mi, root)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(verts.size())
				for i in verts.size():
					indices[i] = i
			for k in range(0, indices.size() - 2, 3):
				var tri := [t * verts[indices[k]], t * verts[indices[k + 1]], t * verts[indices[k + 2]]]
				for h in heights:
					var cut: Array[Vector2] = []
					for e in 3:
						var a: Vector3 = tri[e]
						var b: Vector3 = tri[(e + 1) % 3]
						if (a.y - h) * (b.y - h) <= 0.0 and a.y != b.y:
							var c := a.lerp(b, (h - a.y) / (b.y - a.y))
							cut.append(Vector2(c.x, c.z))
					if cut.size() < 2:
						continue
					var steps := int(rad_to_deg(absf(cut[0].angle_to(cut[1]))) * 4.0) + 1
					for j in steps + 1:
						var c := cut[0].lerp(cut[1], float(j) / steps)
						var bin := int(fposmod(rad_to_deg(c.angle()), 360.0)) % 360
						best[bin] = maxf(best[bin], c.length())
	return best


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
		check(record.get("review_state") in [BLOCKOUT_REVIEW, PRODUCTION_REVIEW], "%s review state is blockout or production, got %s" % [id, record.get("review_state")])
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
	check(not layout.is_empty(), "the pool layout %s exists and is an object" % LAYOUT_PATH)
	for id in FOOD_LAYOUT_KEYS:
		var record := _record(id)
		check(record.has("item_radius_m"), "%s record has item_radius_m" % id)
		var block: Variant = layout.get(FOOD_LAYOUT_KEYS[id], {})
		var item_radius := float(block.get("item_radius", -1.0)) if block is Dictionary else -1.0
		check(item_radius > 0.0, "the layout gives %s an item radius" % id)
		check_near(float(record.get("item_radius_m", 0.0)), item_radius, 0.0001, "%s record item radius matches the layout" % id)
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
		# What the cell sees around its own height is about as wide as the collision circle, on
		# every side: over the swim band, and in the swim plane where the cell is widest.
		for heights: Array[float] in [SWIM_BAND_HEIGHTS, [0.0] as Array[float]]:
			var outline := _section_outline(node, heights)
			var narrow := 0
			var wide := 0
			for r in outline:
				narrow += 1 if r < 0.85 * footprint else 0
				wide += 1 if r > 1.15 * footprint else 0
			var where := "swim band" if heights.size() > 1 else "swim plane"
			check(narrow == 0 and wide == 0,
				"%s %s outline is %.3f-%.3f m, within 15%% of the %.2f m footprint at every azimuth (%d degrees narrow, %d wide)"
				% [id, where, Array(outline).min(), Array(outline).max(), footprint, narrow, wide])
		var record := _record(id)
		check(float(record.get("swim_band_min_radius_m", 0.0)) >= 0.85 * footprint, "%s record swim_band_min_radius_m" % id)
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
	node.free()


## How far from the camera's focus the top screen corners reach on a level plane `height` above
## the swim plane, with the layout camera's pitch and vertical FOV at `distance`.
func _corner_reach(camera: Dictionary, distance: float, height: float) -> float:
	var pitch := deg_to_rad(float(camera.get("pitch_deg", 0.0)))
	var half_fov := deg_to_rad(float(camera.get("fov_deg", 0.0))) / 2.0
	var eye := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	var ray := Basis(Vector3.RIGHT, -pitch) * Vector3(tan(half_fov) * SCREEN_ASPECT, tan(half_fov), -1.0)
	if ray.y >= 0.0:
		return INF   # the corner looks at or above the horizon
	var hit := eye + ray * ((height - eye.y) / ray.y)
	return Vector2(hit.x, hit.z).length()


func test_the_floor_reaches_past_the_widest_view_from_the_wall() -> void:
	var layout := _layout()
	var camera: Dictionary = layout.get("camera", {})
	var pool: Dictionary = layout.get("pool", {})
	check(camera.has("zoom_max") and pool.has("hard_radius"), "the layout has the camera and pool blocks")
	var node := _load_scene("res://assets/export/pool_floor.glb")
	if node == null or camera.is_empty() or pool.is_empty():
		check(false, "pool_floor loads")
		if node:
			node.free()
		return
	# The farthest the camera's focus gets from the centre: the cell's centre at the hard limit
	# plus the whole look-ahead pointing outward.
	var focus_r := float(pool.hard_radius) - PartCatalog.load_from().base("radius", 0.5) + float(camera.get("look_ahead_max", 0.0))
	var verts := _vertices(node)
	var shelf_low := INF
	var edge_r := 0.0
	for v in verts:
		var r := Vector2(v.x, v.z).length()
		edge_r = maxf(edge_r, r)
		if r >= FLOOR_SHELF_R:
			shelf_low = minf(shelf_low, v.y)
	check(shelf_low < INF, "the floor has a shelf past r %.0f" % FLOOR_SHELF_R)
	# The floor's edge is a polygon on its outermost ring; it covers the circle through its edge midpoints.
	var edge_count := 0
	for v in verts:
		if Vector2(v.x, v.z).length() >= edge_r - 0.01:
			edge_count += 1
	check(edge_count >= 32, "the floor ends in a ring of vertices, got %d" % edge_count)
	var covered := edge_r * cos(PI / maxi(edge_count, 3))
	var needed := focus_r + _corner_reach(camera, float(camera.zoom_max), shelf_low)
	check(covered >= needed,
		"at the widest zoom (%.0f m) from the wall the view reaches r %.1f, the floor covers r %.1f" % [float(camera.zoom_max), needed, covered])
	check_near(float(_record("pool_floor").get("radius_m", 0.0)), edge_r, 0.05, "record radius_m is the floor's edge")
	node.free()


func test_the_corner_reach_matches_the_camera_geometry() -> void:
	# Looking straight down with a 90 degree FOV from 10 m, the top corners land 10 m up and
	# 10 x 16/9 m across from the focus.
	var reach := _corner_reach({"pitch_deg": 90.0, "fov_deg": 90.0}, 10.0, 0.0)
	check_near(reach, Vector2(10.0, 10.0 * SCREEN_ASPECT).length(), 1e-3, "straight-down reach")
	check_near(_corner_reach({"pitch_deg": 90.0, "fov_deg": 90.0}, 10.0, 5.0), reach / 2.0, 1e-3, "a plane halfway up halves it")
	check(_corner_reach({"pitch_deg": 10.0, "fov_deg": 45.0}, 10.0, 0.0) == INF, "a corner above the horizon never lands")


func test_the_floor_fades_silt_patches_and_the_stone_band_in_by_vertex_colour() -> void:
	var record := _record("pool_floor")
	var palette: Dictionary = record.get("vertex_colors", {})
	for key in ["sand", "silt", "stone"]:
		check(palette.get(key) is Array and (palette.get(key) as Array).size() == 3, "the record gives the %s colour" % key)
	var node := _load_scene("res://assets/export/pool_floor.glb")
	if node == null or palette.size() < 3:
		check(false, "pool_floor loads with a palette")
		if node:
			node.free()
		return
	var sand := _linear(palette.sand)
	var silt := _linear(palette.silt)
	var stone := _linear(palette.stone)
	var instances := _mesh_instances(node)
	check(instances.size() == 1 and instances[0].mesh.get_surface_count() == 1, "the floor is one mesh with one surface")
	var mesh := instances[0].mesh
	var mat := mesh.surface_get_material(0) as BaseMaterial3D
	check(mat != null and mat.resource_name == "M_PoolFloor", "the floor material is M_PoolFloor")
	# Godot's glTF importer leaves vertex colours off the material; the import points it at
	# M_PoolFloor.tres, which draws them as sRGB albedo in every renderer.
	check(mat != null and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb, "the floor draws its vertex colours as sRGB albedo")
	check(mat != null and mat.albedo_color.is_equal_approx(Color.WHITE), "nothing tints the vertex colours")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check_eq(colors.size(), verts.size(), "every floor vertex has a colour")
	if colors.size() != verts.size():
		node.free()
		return
	# Where each vertex sits between sand (0) and silt (1), and how close to the stone it is.
	var silt_t := PackedFloat32Array()
	var stone_d := PackedFloat32Array()
	var axis := silt - sand
	for c in colors:
		var lin := Vector3(c.srgb_to_linear().r, c.srgb_to_linear().g, c.srgb_to_linear().b)
		silt_t.append((lin - sand).dot(axis) / axis.length_squared())
		stone_d.append(lin.distance_to(stone) / sand.distance_to(stone))
	var bowl := 0
	var sandy := 0
	var silty := 0
	var between := 0
	for i in verts.size():
		var r := Vector2(verts[i].x, verts[i].z).length()
		if r <= 38.0:
			bowl += 1
			sandy += 1 if silt_t[i] < 0.15 else 0
			silty += 1 if silt_t[i] > 0.85 else 0
			between += 1 if silt_t[i] >= 0.3 and silt_t[i] <= 0.7 else 0
			check(stone_d[i] > 0.5, "no stone in the bowl at %s" % verts[i])
		elif r >= 41.5 and r <= 43.0:
			check(stone_d[i] < 0.1, "the rim lip is stone at %s" % verts[i])
	check(sandy > bowl / 3, "most of the bowl is sand: %d of %d vertices" % [sandy, bowl])
	check(silty > bowl / 20, "the bowl has silt patches: %d of %d vertices" % [silty, bowl])
	check(between > bowl / 50, "silt fades into the sand over several vertices: %d of %d in between" % [between, bowl])
	# Soft edges: silt fades in over at least 0.8 m, never switching at a face edge as the old
	# per-face materials did on the radial grid.
	var steepest := 0.0
	for k in range(0, indices.size(), 3):
		for e in 3:
			var a := indices[k + e]
			var b := indices[k + (e + 1) % 3]
			if Vector2(verts[a].x, verts[a].z).length() <= 38.0:
				var run := Vector2(verts[a].x - verts[b].x, verts[a].z - verts[b].z).length()
				steepest = maxf(steepest, absf(silt_t[a] - silt_t[b]) / maxf(run, 1e-3))
	check(steepest <= 1.25, "silt changes by at most 1.25 sand-to-silt steps per metre, got %.2f" % steepest)
	node.free()


func _linear(rgb: Array) -> Vector3:
	return Vector3(float(rgb[0]), float(rgb[1]), float(rgb[2]))


func test_sample_cell_has_the_nodes_the_pool_hides_and_keeps() -> void:
	var node := _load_scene("res://assets/export/sample_cell.glb")
	if node == null:
		check(false, "sample_cell loads")
		return
	# The pool hides the baked mouth and flagellum (genome parts replace them) and keeps the eyes.
	for path in ["Body/Mouth", "Body/Flagellum", "Body/Pupil_L", "Body/Pupil_R"]:
		check(node.get_node_or_null(path) is MeshInstance3D, "sample_cell has %s" % path)
	node.free()


# --- Step 3 threat blockouts (step 3 plan section 17) -------------------------------------------


## How far a point on the swim plane lies outside PartPlacement's body ellipse, along the ray from
## the body's centre (negative inside).
func _beyond_frame(p: Vector2) -> float:
	return p.length() - _frame_radius(p.angle())


## Distance from the body's centre to PartPlacement's ellipse in the swim plane at `azimuth`
## (Godot x and z, as Vector2.angle() measures it).
func _frame_radius(azimuth: float) -> float:
	return 1.0 / sqrt(pow(cos(azimuth) / PartPlacement.RX, 2.0) + pow(sin(azimuth) / PartPlacement.RZ, 2.0))


## Area of a mesh instance's own triangles seen from above (the convex hull of its vertices on the
## swim plane), in root space.
func _top_area(mi: MeshInstance3D, root: Node3D) -> float:
	var t := _relative(mi, root)
	var points := PackedVector2Array()
	for s in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := t * v
			points.append(Vector2(p.x, p.z))
	var hull := Geometry2D.convex_hull(points)
	var twice := 0.0
	for i in hull.size():
		twice += hull[i].cross(hull[(i + 1) % hull.size()])
	return absf(twice) / 2.0


## The ambush hunter's body_size from the species data, or the plan's value before that file exists.
func _ambush_body_size() -> float:
	if not FileAccess.file_exists(CREATURES_PATH):
		return AMBUSH_PLANNED_SIZE
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREATURES_PATH))
	var species: Variant = data.get("species", {}) if data is Dictionary else {}
	var ambush: Variant = species.get("ambush_hunter", {}) if species is Dictionary else {}
	var size: Variant = ambush.get("body_size") if ambush is Dictionary else null
	check(size is float or size is int, "%s gives the ambush hunter a body_size" % CREATURES_PATH)
	return float(size) if size is float or size is int else AMBUSH_PLANNED_SIZE


## Linear luminance of a vertex colour stored sRGB-encoded.
func _luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


func _is_color(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) <= 0.02 and absf(actual.g - expected.g) <= 0.02 and absf(actual.b - expected.b) <= 0.02


## The materials on every surface under `root`.
func _materials(root: Node) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for mi in _mesh_instances(root):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null:
				out.append(mat)
	return out


func test_threat_blockouts_are_proposed_unapproved_and_within_their_step_3_budgets() -> void:
	for id in THREAT_BUDGETS:
		var record := _record(id)
		if record.is_empty():
			check(false, "%s has a record" % id)
			continue
		check_eq(record.get("status"), "PROPOSED", "%s status" % id)
		check_eq(record.get("review_state"), THREAT_REVIEW, "%s review state" % id)
		check_eq(record.get("generator_script"), THREAT_GENERATOR, "%s generator" % id)
		check(String(record.get("provenance", "")).contains("procedurally") and String(record.get("provenance", "")).contains(THREAT_GENERATOR),
			"%s provenance is procedural and names its generator" % id)
		var tris := int(record.get("triangles", 1 << 30))
		check(tris > 0 and tris <= THREAT_BUDGETS[id], "%s has %d triangles, budget %d" % [id, tris, THREAT_BUDGETS[id]])


func test_threat_bodies_carry_the_pose_nodes_the_creature_view_drives() -> void:
	for id in THREAT_POSE_NODES:
		var node := _load_scene("res://assets/export/%s.glb" % id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		check(node.get_node_or_null(^"Body") is MeshInstance3D, "%s has a Body mesh" % id)
		var listed: Array = _record(id).get("nodes", [])
		for pose_node: String in THREAT_POSE_NODES[id]:
			check(node.get_node_or_null("Body/" + pose_node) is MeshInstance3D, "%s has Body/%s" % [id, pose_node])
			check(listed.has(pose_node), "%s record lists %s" % [id, pose_node])
		# Eyes turn, squint and glow about their own centre.
		for eye in ["Eye_L", "Eye_R"]:
			var mi := node.get_node_or_null("Body/" + eye) as MeshInstance3D
			if mi != null:
				check(mi.mesh.get_aabb().get_center().length() < 0.01, "%s %s has its origin at its centre" % [id, eye])
		node.free()
	# The ambush hunter's eyes share one glowing amber material, whose emission the view drives.
	var ambush := _load_scene("res://assets/export/creature_ambush_body.glb")
	if ambush != null:
		for eye in ["Eye_L", "Eye_R"]:
			var mi := ambush.get_node_or_null("Body/" + eye) as MeshInstance3D
			var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D if mi != null else null
			check(mat != null and mat.resource_name == "M_AmbushEye", "ambush %s wears M_AmbushEye" % eye)
			check(mat != null and mat.emission_enabled, "ambush %s glows" % eye)
			check(mat != null and _is_color(mat.albedo_color, MINERAL_AMBER), "ambush %s is mineral amber" % eye)
		ambush.free()
	# The rammer's crest stands on its pivot on the midline of the back: the view raises it by
	# scaling its up axis, which sinks its base into the body and lifts its points.
	var rammer := _load_scene("res://assets/export/creature_rammer_body.glb")
	if rammer != null:
		var hood := rammer.get_node_or_null(^"Body/Hood") as MeshInstance3D
		if hood != null:
			var box := hood.mesh.get_aabb()
			check(box.position.y < -0.02 and box.end.y > 0.1, "the crest runs from below its pivot to %.3f m above it, got %s" % [box.end.y, box])
			check(absf(box.get_center().x) < 0.01, "the crest sits on the midline")
		rammer.free()


func test_threat_bodies_meet_the_swim_plane_on_the_part_placement_ellipse() -> void:
	for id in THREAT_POSE_NODES:
		var node := _load_scene("res://assets/export/%s.glb" % id)
		var body := node.get_node_or_null(^"Body") as MeshInstance3D if node != null else null
		if body == null:
			check(false, "%s loads with a Body mesh" % id)
			if node:
				node.free()
			continue
		var outline := _section_outline(node, [0.0] as Array[float], body)
		var missing := 0
		var worst := 0.0
		for bin in 360:
			if outline[bin] <= 0.0:
				missing += 1
				continue
			worst = maxf(worst, absf(outline[bin] - _frame_radius(deg_to_rad(bin + 0.5))))
		check(missing == 0 and worst <= FRAME_TOLERANCE_M,
			"%s Body at the swim plane is within %.3f m of PartPlacement's ellipse all round, off by %.4f m (%d degrees empty)"
			% [id, FRAME_TOLERANCE_M, worst, missing])
		node.free()


func test_the_ambush_body_is_flat_and_bigger_than_the_sample_cell_at_its_size() -> void:
	var ambush := _load_scene("res://assets/export/creature_ambush_body.glb")
	var cell := _load_scene("res://assets/export/sample_cell.glb")
	var ambush_body := ambush.get_node_or_null(^"Body") as MeshInstance3D if ambush != null else null
	var cell_body := cell.get_node_or_null(^"Body") as MeshInstance3D if cell != null else null
	check(ambush_body != null and cell_body != null, "both bodies load")
	if ambush_body != null and cell_body != null:
		# Height against width over the whole asset, eyes and brow included; scale does not change it.
		var size := _mesh_bounds(ambush).size
		check(size.y <= AMBUSH_MAX_HEIGHT_SHARE * size.x,
			"the ambush body is %.3f m high and %.3f m wide: height %.3f of the width, at most %.2f" % [size.y, size.x, size.y / size.x, AMBUSH_MAX_HEIGHT_SHARE])
		var body_size := _ambush_body_size()
		var share := body_size * sqrt(_top_area(ambush_body, ambush) / _top_area(cell_body, cell))
		check(share >= AMBUSH_FOOTPRINT_SHARE,
			"at body_size %.2f the ambush body is %.2f times the sample cell's length and width, at least %.2f" % [body_size, share, AMBUSH_FOOTPRINT_SHARE])
	if ambush:
		ambush.free()
	if cell:
		cell.free()


func test_a_spike_placed_on_the_body_points_well_past_the_outline() -> void:
	var node := _load_scene("res://assets/export/part_spike.glb")
	if node == null:
		check(false, "part_spike loads")
		return
	var verts := _vertices(node)
	# The rammer's spike angles, then the sides, the tail and the front.
	for angle in [0.3, -0.3, 1.9, -1.9, PI / 2.0, PI, 0.0]:
		var t := PartPlacement.transform_for(angle, "spike", 1.0)
		var reach := -INF
		for v in verts:
			var p := t * v
			reach = maxf(reach, _beyond_frame(Vector2(p.x, p.z)))
		check(reach >= SPIKE_MIN_REACH_M, "at angle %.2f a spike at scale 1 reaches %.3f m past the body outline, at least %.2f" % [angle, reach, SPIKE_MIN_REACH_M])
	node.free()


func test_spikes_and_the_rammer_crest_points_wear_the_threat_colour() -> void:
	for id in ["part_spike", "creature_rammer_body"]:
		var node := _load_scene("res://assets/export/%s.glb" % id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		var found := false
		var search: Node = node if id == "part_spike" else node.get_node_or_null(^"Body/Hood")
		if search != null:
			for mat in _materials(search):
				found = found or _is_color(mat.albedo_color, THREAT_COLOR)
		check(found, "%s has a surface in the threat colour %s" % [id, THREAT_COLOR.to_html(false)])
		node.free()


func test_threat_bodies_draw_their_vertex_colours_a_dark_ambusher_and_a_banded_rammer() -> void:
	var expected := {"creature_ambush_body": "M_AmbushBody", "creature_rammer_body": "M_RammerBody"}
	var tops := {}
	var bellies := {}
	var midlines := {}
	for id in expected:
		var node := _load_scene("res://assets/export/%s.glb" % id)
		var body := node.get_node_or_null(^"Body") as MeshInstance3D if node != null else null
		if body == null:
			check(false, "%s loads with a Body mesh" % id)
			if node:
				node.free()
			continue
		var mat := body.mesh.surface_get_material(0) as BaseMaterial3D
		# As with the pool floor, the import points the body material at an external .tres that
		# draws the vertex colours as sRGB albedo in every renderer.
		check(mat != null and mat.resource_name == expected[id], "%s body material is %s" % [id, expected[id]])
		check(mat != null and mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb, "%s draws its vertex colours as sRGB albedo" % id)
		check(mat != null and mat.albedo_color.is_equal_approx(Color.WHITE), "nothing tints %s's vertex colours" % id)
		var arrays := body.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		check_eq(colors.size(), verts.size(), "every %s body vertex has a colour" % id)
		var top: Array[float] = []
		var belly: Array[float] = []
		var midline: Array[Vector2] = []   # (forward position, luminance) along the top of the back
		var t := _relative(body, node)
		for i in mini(verts.size(), colors.size()):
			var p := t * verts[i]
			var lum := _luminance(colors[i])
			if p.y > 0.05:
				top.append(lum)
				if absf(p.x) < 0.001:
					midline.append(Vector2(-p.z, lum))
			elif p.y < -0.05:
				belly.append(lum)
		tops[id] = top
		bellies[id] = belly
		midlines[id] = midline
		node.free()
	if tops.size() < 2:
		return
	var mean := func(values: Array[float]) -> float:
		var total := 0.0
		for v in values:
			total += v
		return total / maxi(values.size(), 1)
	# The ambush hunter: a dark back over a pale belly.
	var ambush_back: float = mean.call(tops.creature_ambush_body)
	var ambush_belly: float = mean.call(bellies.creature_ambush_body)
	check(ambush_back < 0.12, "the ambush back is dark: mean luminance %.3f" % ambush_back)
	check(ambush_belly > 3.0 * ambush_back, "the ambush belly (%.3f) is pale next to its back (%.3f)" % [ambush_belly, ambush_back])
	# The rammer: a pale back crossed by three dark bands, front to tail along the midline.
	check(mean.call(tops.creature_rammer_body) > 0.25, "the rammer back is pale")
	var line: Array[Vector2] = midlines.creature_rammer_body
	line.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var bands := 0
	var in_band := false
	for v in line:
		if v.y < 0.1 and not in_band:
			bands += 1
		in_band = v.y < 0.1
	check(line.size() > 20, "the rammer has vertices along the top of its back")
	check_eq(bands, 3, "dark bands across the rammer's back")


func test_production_assets_carry_textures_and_log_every_outside_source() -> void:
	for record in _records():
		if record.get("review_state") != PRODUCTION_REVIEW:
			continue
		var id: String = record.id
		var textures: Array = record.get("textures", [])
		check(not textures.is_empty(), "%s lists its baked textures" % id)
		for tex: Dictionary in textures:
			var size: Array = tex.get("size", [0, 0])
			check(int(size[0]) > 0 and int(size[0]) <= MAX_TEXTURE_PX and int(size[0]) == int(size[1]), "%s texture %s is square and at most %d px" % [id, tex.get("name"), MAX_TEXTURE_PX])
		# Every outside source is CC0, named by URL and kept in the repo (art direction section 8).
		for dep: Variant in record.get("dependencies", []):
			if dep is Dictionary:
				check(String(dep.get("license", "")).begins_with("CC0"), "%s dependency %s is CC0" % [id, dep.get("asset")])
				check(String(dep.get("source_url", "")).begins_with("https://"), "%s dependency %s has a source URL" % [id, dep.get("asset")])
				check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + String(dep.get("path", "")))), "%s dependency %s is kept in the repo" % [id, dep.get("asset")])
		# The imported scene has textured materials, not flat colours: an albedo texture, or (the
		# pool floor) vertex colours with a detail normal map.
		var node := _load_scene("res://" + String(record.export_path))
		if node == null:
			check(false, "%s loads" % id)
			continue
		for mi in _mesh_instances(node):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				var textured := mat != null and (mat.albedo_texture != null or (mat.vertex_color_use_as_albedo and mat.normal_texture != null))
				check(textured, "%s %s surface %d has an albedo texture, or vertex colours and a normal map" % [id, mi.name, s])
		node.free()
