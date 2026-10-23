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
	"rock_a": 1300, "rock_b": 1300, "rock_c": 1300,
	"plankton": 400, "carrion": 400,
	"part_mouth_filter": 1500, "part_mouth_jaw": 1500, "part_flagellum": 1500, "part_eye_spot": 1500,
}
const PART_IDS := ["part_mouth_filter", "part_mouth_jaw", "part_flagellum", "part_eye_spot", "part_spike"]
const ROCK_IDS := ["rock_a", "rock_b", "rock_c"]
## Food record id -> its block in the pool layout, which holds the gameplay item_radius.
const FOOD_LAYOUT_KEYS := {"plankton": "plankton", "carrion": "carrion"}
## Where the camera's view lands on a level plane (shared with tests/test_pool_look.gd).
const ViewReach := preload("res://tests/view_reach.gd")
## The rim's shelf (the old pool floor's) starts here; past it the rim is flat at about +1.0 m.
const SHELF_R := 45.0
## A rock reaches at least this far below the swim plane (m), into the fluid's height fog.
const ROCK_BASE_M := -1.5
## The cell's height band around the swim plane: it reaches 0.39 m above and below it.
const SWIM_BAND_M := 0.45
## Section heights through the swim band, for rock outlines.
const SWIM_BAND_HEIGHTS: Array[float] = [-0.45, -0.3375, -0.225, -0.1125, 0.0, 0.1125, 0.225, 0.3375, 0.45]
## The step 3 threat blockouts (step 3 plan section 17): their review state, generator and
## triangle budgets, kept here so a record cannot loosen its own.
const THREAT_REVIEW := "blockout - M1 step 3, not visually approved"
const THREAT_GENERATOR := "tools/blender/make_m1_threats.py"
## The production swaps (M1 production art) keep the blockouts' contract and name their own generator.
const THREAT_PRODUCTION_GENERATOR := "tools/blender/make_m1_production.py"
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
## The microscopic world's rim (docs/micro-world-plan.md, commit C3): an engineering placeholder
## from its own generator until the owner picks how the world's edge looks, with its budget kept
## here so its record cannot loosen it.
const RIM_ID := "pool_rim"
const RIM_REVIEW := "blockout - M1 micro world, not visually approved"
const RIM_GENERATOR := "tools/blender/make_m1_micro_rim.py"
const RIM_BUDGET := 4000
## The rim's surface crosses the swim plane between the layout's hard radius, where the collision
## stops the cell's side, and this far outside it, so the wall the player sees is where the cell stops.
const RIM_PLANE_BAND_M := 1.0
## The wall's inner face lies in this band at every azimuth and at each of these heights, from
## under the swim plane down to the skirt's least depth (5 m).
const RIM_INNER_M := Vector2(38.5, 38.8)
const RIM_SKIRT_HEIGHTS: Array[float] = [-1.5, -3.0, -5.0]
## As the old floor's: the cell's centre stops at r 39 and the cell reaches 0.39 m below the swim
## plane, so inside r 39 the rim stays at or below -0.45 m. (radius, height)
const RIM_CLEAR_M := Vector2(39.0, -0.45)
## The old floor's lip (+1.2 m at r 42) and shelf (+1.0 m from SHELF_R out), with their 0.1 m of
## rocky noise: the heights the rim keeps over the lip's radii and over the shelf.
const RIM_LIP_R := Vector2(41.5, 43.0)
const RIM_LIP_HEIGHT_M := Vector2(0.8, 1.4)
const RIM_SHELF_HEIGHT_M := Vector2(0.85, 1.15)
## The placeholder look (PROPOSED). The lip's linear albedo luminance is at most RIM_MAX_LUMINANCE,
## as tests/test_pool_look.gd holds it, and every albedo at least RIM_MIN_LUMINANCE. The
## wall's face below RIM_WALL_BELOW_M gets no sun on the north side, only the blue ambient light,
## so its albedo is at least RIM_WALL_MIN_LUMINANCE: in the lip's dark stone it rendered near
## black (L* 6; docs/DECISIONS.md).
const RIM_MAX_LUMINANCE := 0.40
const RIM_MIN_LUMINANCE := 0.01
const RIM_WALL_BELOW_M := -1.0
const RIM_WALL_MIN_LUMINANCE := 0.08


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
			var box := _relative(n, root) * _rest_aabb((n as MeshInstance3D).mesh)
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds


## A mesh's bounds in its rest shape. Godot grows get_aabb() to cover every blend shape at full
## weight, but records measure the rest shape, so meshes with blend shapes are measured from their
## vertices.
func _rest_aabb(mesh: Mesh) -> AABB:
	if not mesh is ArrayMesh or (mesh as ArrayMesh).get_blend_shape_count() == 0:
		return mesh.get_aabb()
	var box := AABB()
	var first := true
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			box = AABB(v, Vector3.ZERO) if first else box.expand(v)
			first = false
	return box


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
## that mesh instance's own triangles count (in root space). With `nearest`, each bin holds the
## nearest point instead (INF where none reaches).
func _section_outline(root: Node3D, heights: Array[float], only: MeshInstance3D = null, nearest := false) -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(360)
	if nearest:
		best.fill(INF)
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
						best[bin] = minf(best[bin], c.length()) if nearest else maxf(best[bin], c.length())
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


## Blender adds shape keys at full value, and the GLB stores that as each mesh's default morph weights.
## Godot's importer leaves blend shapes at 0, but Blender, viewers and other glTF readers draw those
## defaults, so a key left at 1 shows the cell ripe and stretched there. Reads the GLB's JSON chunk.
func test_sample_cell_morph_weights_rest_at_zero() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://assets/export/sample_cell.glb")
	check(bytes.size() > 20, "sample_cell.glb reads")
	if bytes.size() <= 20:
		return
	var length := bytes.decode_u32(12)
	var gltf: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	check(gltf is Dictionary, "sample_cell.glb has a JSON chunk")
	if not gltf is Dictionary:
		return
	var found := 0
	for mesh: Dictionary in gltf.get("meshes", []):
		for w in mesh.get("weights", []):
			found += 1
			check_near(float(w), 0.0, 1e-6, "%s morph weight rests at 0" % mesh.get("name", "?"))
	check(found >= 2, "sample_cell has its Ripeness and Stretch morph targets, found %d" % found)


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
		# Pivot on the swim plane at the footprint centre. There is no floor to bury the base in: the
		# rock reaches at least ROCK_BASE_M below the plane, where the fluid's height fog starts to
		# fade it (pool_environment.tres), so its cut-off base never reads as an edge.
		check(box.position.y <= ROCK_BASE_M and box.end.y > 0.0, "%s spans the swim plane down to %.1f m, where the fog takes it: %.2f to %.2f m" % [id, ROCK_BASE_M, box.position.y, box.end.y])
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


## Checks that asset `id`'s shelf, its vertices from `shelf_r` out, reaches past what the widest
## zoom shows from a cell at the wall, and that its record's radius_m is its edge.
func _check_shelf_reaches_past_the_widest_view(id: String, shelf_r: float) -> void:
	var layout := _layout()
	var camera: Dictionary = layout.get("camera", {})
	var pool: Dictionary = layout.get("pool", {})
	check(camera.has("zoom_max") and pool.has("hard_radius"), "the layout has the camera and pool blocks")
	var node := _load_scene("res://assets/export/%s.glb" % id)
	if node == null or camera.is_empty() or pool.is_empty():
		check(false, "%s loads" % id)
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
		if r >= shelf_r:
			shelf_low = minf(shelf_low, v.y)
	check(shelf_low < INF, "%s has a shelf past r %.0f" % [id, shelf_r])
	# The edge is a polygon on the outermost ring; it covers the circle through its edge midpoints.
	var edge_count := 0
	for v in verts:
		if Vector2(v.x, v.z).length() >= edge_r - 0.01:
			edge_count += 1
	check(edge_count >= 32, "%s ends in a ring of vertices, got %d" % [id, edge_count])
	var covered := edge_r * cos(PI / maxi(edge_count, 3))
	var needed := focus_r + ViewReach.corner_reach(camera, float(camera.zoom_max), shelf_low)
	check(covered >= needed,
		"at the widest zoom (%.0f m) from the wall the view reaches r %.1f, %s covers r %.1f" % [float(camera.zoom_max), needed, id, covered])
	check_near(float(_record(id).get("radius_m", 0.0)), edge_r, 0.05, "%s record radius_m is its edge" % id)
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
		var production: bool = record.get("review_state") == PRODUCTION_REVIEW
		check(production or record.get("review_state") == THREAT_REVIEW, "%s review state is the step 3 blockout's or production, got %s" % [id, record.get("review_state")])
		var generator := THREAT_PRODUCTION_GENERATOR if production else THREAT_GENERATOR
		check_eq(record.get("generator_script"), generator, "%s generator" % id)
		check(String(record.get("provenance", "")).contains("procedurally") and String(record.get("provenance", "")).contains(generator),
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
		# The import points the body material at an external .tres that draws the vertex colours as
		# sRGB albedo in every renderer.
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
		# The imported scene has textured materials, not flat colours: an albedo texture, or (a
		# vertex-coloured asset) vertex colours with a detail normal map.
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


# --- The microscopic world's rim (docs/micro-world-plan.md, commit C3) ---------------------------


func test_the_pool_rim_is_a_micro_world_blockout_within_its_budget() -> void:
	var record := _record(RIM_ID)
	if record.is_empty():
		check(false, "%s has a record" % RIM_ID)
		return
	check_eq(record.get("status"), "PROPOSED", "%s status" % RIM_ID)
	check_eq(record.get("review_state"), RIM_REVIEW, "%s review state" % RIM_ID)
	check_eq(record.get("generator_script"), RIM_GENERATOR, "%s generator" % RIM_ID)
	var provenance := String(record.get("provenance", ""))
	check(provenance.contains("procedurally") and provenance.contains(RIM_GENERATOR), "%s provenance is procedural and names its generator" % RIM_ID)
	var tris := int(record.get("triangles", 1 << 30))
	check(tris > 0 and tris <= RIM_BUDGET, "%s has %d triangles, budget %d" % [RIM_ID, tris, RIM_BUDGET])


# The rim's shape is its gameplay contract. These checks read only its triangles, never its
# material, so art can swap the look (the owner's question on the world edge) without them.


func test_the_pool_rim_wall_meets_the_swim_plane_where_the_collision_stops_the_cell() -> void:
	var pool: Variant = _layout().get("pool", {})
	var hard := float(pool.get("hard_radius", 0.0)) if pool is Dictionary else 0.0
	check(hard > 0.0, "the layout gives the pool a hard radius")
	var node := _load_scene("res://assets/export/%s.glb" % RIM_ID)
	if node == null:
		check(false, "%s loads" % RIM_ID)
		return
	# At every azimuth the surface crosses the swim plane, and only between the hard radius and a
	# metre outside it. (A bin with no crossing holds INF nearest and 0 farthest.)
	var near := _section_outline(node, [0.0] as Array[float], null, true)
	var far := _section_outline(node, [0.0] as Array[float])
	var off := 0
	for bin in 360:
		off += 0 if near[bin] >= hard and far[bin] <= hard + RIM_PLANE_BAND_M and near[bin] <= far[bin] else 1
	check(off == 0, "%s crosses the swim plane in r %.1f-%.1f at every azimuth: r %.3f-%.3f (%d degrees off)"
		% [RIM_ID, hard, hard + RIM_PLANE_BAND_M, Array(near).min(), Array(far).max(), off])
	# Below it the wall faces the pool from just outside the cell's reach, all round and at least
	# 5 m down, and nothing reaches further in.
	for h in RIM_SKIRT_HEIGHTS:
		var wall := _section_outline(node, [h] as Array[float], null, true)
		var outside := 0
		for r in wall:
			outside += 0 if r >= RIM_INNER_M.x and r <= RIM_INNER_M.y else 1
		check(outside == 0, "%s wall at y %.1f is in r %.1f-%.1f at every azimuth: r %.3f-%.3f (%d degrees outside or missing)"
			% [RIM_ID, h, RIM_INNER_M.x, RIM_INNER_M.y, Array(wall).min(), Array(wall).max(), outside])
	var innermost := INF
	for v in _vertices(node):
		innermost = minf(innermost, Vector2(v.x, v.z).length())
	check(innermost >= RIM_INNER_M.x, "nothing of %s reaches inside r %.1f, got %.3f" % [RIM_ID, RIM_INNER_M.x, innermost])
	node.free()


func test_the_pool_rim_clears_the_cell_keeps_the_floors_lip_and_shelf_and_faces_the_pool() -> void:
	var node := _load_scene("res://assets/export/%s.glb" % RIM_ID)
	if node == null:
		check(false, "%s loads" % RIM_ID)
		return
	var inside := -INF
	var lip := Vector2(INF, -INF)
	var shelf := Vector2(INF, -INF)
	var away := 0
	var count := 0
	for mi in _mesh_instances(node):
		var t := _relative(mi, node)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				var v := t * verts[i]
				var r := Vector2(v.x, v.z).length()
				count += 1
				if r <= RIM_CLEAR_M.x:
					inside = maxf(inside, v.y)
				elif r >= RIM_LIP_R.x and r <= RIM_LIP_R.y:
					lip = Vector2(minf(lip.x, v.y), maxf(lip.y, v.y))
				elif r >= SHELF_R:
					shelf = Vector2(minf(shelf.x, v.y), maxf(shelf.y, v.y))
				# The wall shows its inner side and the lip and shelf their top: each vertex's normal
				# points up or in toward the pool's axis, never down or out.
				var n := (t.basis * normals[i]).normalized() if i < normals.size() else Vector3.ZERO
				away += 0 if n.y - n.dot(Vector3(v.x, 0.0, v.z).normalized()) > 0.0 else 1
	check(count > 0, "%s has vertices" % RIM_ID)
	check(inside <= RIM_CLEAR_M.y, "inside r %.0f %s is at most %.2f m, got %.3f" % [RIM_CLEAR_M.x, RIM_ID, RIM_CLEAR_M.y, inside])
	check(lip.x > RIM_LIP_HEIGHT_M.x and lip.y <= RIM_LIP_HEIGHT_M.y,
		"over r %.1f-%.0f the lip is %.3f-%.3f m, within %.1f-%.1f" % [RIM_LIP_R.x, RIM_LIP_R.y, lip.x, lip.y, RIM_LIP_HEIGHT_M.x, RIM_LIP_HEIGHT_M.y])
	check(shelf.x >= RIM_SHELF_HEIGHT_M.x and shelf.y <= RIM_SHELF_HEIGHT_M.y,
		"from r %.0f the shelf is %.3f-%.3f m, within %.2f-%.2f" % [SHELF_R, shelf.x, shelf.y, RIM_SHELF_HEIGHT_M.x, RIM_SHELF_HEIGHT_M.y])
	check(away == 0, "every %s normal points up or into the pool: %d of %d point away" % [RIM_ID, away, count])
	node.free()


func test_the_pool_rim_shelf_reaches_past_the_widest_view_from_the_wall() -> void:
	_check_shelf_reaches_past_the_widest_view(RIM_ID, SHELF_R)


## The rim's linear albedo at vertex `i` as `mat` draws it: its colour times the vertex colour when
## it uses them. Black when the albedo cannot be read from the mesh (a texture).
func _rim_albedo(mat: BaseMaterial3D, colors: PackedColorArray, i: int) -> Color:
	if mat == null or mat.albedo_texture != null:
		return Color.BLACK
	var albedo := mat.albedo_color.srgb_to_linear()
	if mat.vertex_color_use_as_albedo and i < colors.size():
		albedo *= colors[i].srgb_to_linear() if mat.vertex_color_is_srgb else colors[i]
	return albedo


## Dark and cool: luminance in [RIM_MIN_LUMINANCE, `most`], and blue at least green at least red
## (within 8-bit rounding), so it never leans toward food's yellow-green or the threat's pink.
func _is_dark_cool(c: Color, most: float) -> bool:
	var lum := c.get_luminance()
	return lum >= RIM_MIN_LUMINANCE and lum <= most and c.b >= c.g - 0.004 and c.g >= c.r - 0.004


# The placeholder look, read through the material the import gives the rim. A new look for the
# world's edge replaces this test, not the shape tests above.
func test_the_pool_rim_is_dark_cool_stone_never_near_white_and_its_wall_never_black() -> void:
	var palette: Dictionary = _record(RIM_ID).get("vertex_colors", {})
	for key in ["stone", "wall"]:
		var rgb: Variant = palette.get(key)
		var ok: bool = rgb is Array and (rgb as Array).size() == 3
		check(ok, "the %s record gives its %s colour" % [RIM_ID, key])
		if ok:
			var c := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
			check(_is_dark_cool(c, RIM_MAX_LUMINANCE), "the %s colour %s is dark and cool" % [key, c])
	var node := _load_scene("res://assets/export/%s.glb" % RIM_ID)
	if node == null:
		check(false, "%s loads" % RIM_ID)
		return
	var on_lip := 0
	var brightest := 0.0
	var on_wall := 0
	var darkest_wall := INF
	var off := 0
	var count := 0
	for mi in _mesh_instances(node):
		var t := _relative(mi, node)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			check(mat != null and mat.albedo_texture == null, "%s %s surface %d has a standard material without a texture, whose albedo this test reads" % [RIM_ID, mi.name, s])
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			for i in verts.size():
				var albedo := _rim_albedo(mat, colors, i)
				count += 1
				off += 0 if _is_dark_cool(albedo, RIM_MAX_LUMINANCE) else 1
				var v := t * verts[i]
				var r := Vector2(v.x, v.z).length()
				if r >= RIM_LIP_R.x and r <= RIM_LIP_R.y:
					on_lip += 1
					brightest = maxf(brightest, albedo.get_luminance())
				elif v.y <= RIM_WALL_BELOW_M:
					on_wall += 1
					darkest_wall = minf(darkest_wall, albedo.get_luminance())
	check(count > 0 and off == 0, "every %s vertex is dark, cool stone as drawn: %d of %d are not" % [RIM_ID, off, count])
	check(on_lip > 0 and on_wall > 0, "%s has vertices on the lip and on the wall" % RIM_ID)
	check(brightest <= RIM_MAX_LUMINANCE, "the lip's brightest albedo has luminance %.3f, at most %.2f" % [brightest, RIM_MAX_LUMINANCE])
	check(darkest_wall >= RIM_WALL_MIN_LUMINANCE, "below y %.0f the wall's darkest albedo has luminance %.3f, at least %.2f" % [RIM_WALL_BELOW_M, darkest_wall, RIM_WALL_MIN_LUMINANCE])
	node.free()
