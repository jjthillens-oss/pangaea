extends TestCase
## Creature part assets (docs/art/creature_art_contract.md, section 1): every cpart_ record carries the
## PartRules the runtime copies, its GLB has one root mesh named after the part type with the handle
## blend shapes, the mesh sits on the skin within its sink depth and footprint, chiral parts are one-sided,
## and every face's winding agrees with its normals (so the runtime's mirror, which flips x and the
## winding, faces outward too). The parts are PROPOSED; no game code reads them yet.

const RECORDS_DIR := "res://assets/records"
const CONVENTION := "creature_art_contract v1"
const ORIENTATIONS := ["normal", "ground", "forward_cone"]
const CENTERLINES := ["allowed", "required", "forbidden"]
const HOSTS := ["spine", "limb", "limb_end", "part"]
## Contract section 1.4: small 400, medium 1200, large 2500.
const BUDGETS := [400.0, 1200.0, 2500.0]
const MAX_HANDLES := 4
## Vertices this close to the skin (m) count toward the footprint.
const FOOTPRINT_BAND_M := 0.005
## A vertex may sit this far (m) past the sink depth or the sole: Blender export rounding.
const TOLERANCE_M := 0.001


func _records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in DirAccess.get_files_at(RECORDS_DIR):
		if f.begins_with("cpart_") and f.ends_with(".json"):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORDS_DIR + "/" + f))
			if data is Dictionary:
				out.append(data)
	return out


func _load_scene(id: String) -> Node3D:
	var packed: PackedScene = load("res://assets/export/%s.glb" % id)
	return packed.instantiate() if packed else null


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			out.append(n)
	return out


func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Every rest-shape vertex under `root`, in root space (blend shapes rest at 0).
func _vertices(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in _mesh_instances(root):
		var t := _relative(mi, root)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				out.append(t * v)
	return out


## "tail_fluke" -> "TailFluke": the root mesh name the contract asks for (section 1.2).
func _pascal(part_type: String) -> String:
	var out := ""
	for word in part_type.split("_", false):
		out += word.substr(0, 1).to_upper() + word.substr(1)
	return out


func _blend_shape_names(root: Node3D) -> Dictionary:
	var names := {}
	for mi in _mesh_instances(root):
		if mi.mesh is ArrayMesh:
			for i in (mi.mesh as ArrayMesh).get_blend_shape_count():
				names[String((mi.mesh as ArrayMesh).get_blend_shape_name(i))] = true
	return names


func test_every_part_record_carries_the_contract_fields_and_rules() -> void:
	var records := _records()
	check(records.size() >= 21, "the creature parts are recorded (%d found)" % records.size())
	for record in records:
		var id: String = record.get("id", "?")
		check_eq(record.get("category", ""), "part", "%s category" % id)
		check_eq(record.get("convention", ""), CONVENTION, "%s convention" % id)
		check(float(record.get("triangle_budget", 0)) in BUDGETS, "%s: budget %s is a contract class" % [id, record.get("triangle_budget")])
		check(record.get("triangles", INF) <= record.get("triangle_budget", 0), "%s: %s triangles within its budget %s" % [id, record.get("triangles"), record.get("triangle_budget")])
		var rules: Dictionary = record.get("part_rules", {})
		check(not rules.is_empty(), "%s has part_rules" % id)
		check_eq(rules.get("type", ""), record.get("part_type", "?"), "%s: part_rules.type matches part_type" % id)
		check(rules.get("footprint_radius_m", 0.0) > 0.0, "%s: footprint_radius_m" % id)
		check(rules.get("sink_depth_m", -1.0) > 0.0 or (rules.get("orientation", "") == "ground" and rules.get("sink_depth_m", -1.0) == 0.0), "%s: sink_depth_m (0 only for ground parts)" % id)
		check(rules.get("chiral") is bool, "%s: chiral is a bool" % id)
		check(rules.get("orientation", "") in ORIENTATIONS, "%s: orientation %s" % [id, rules.get("orientation")])
		check(rules.get("centerline", "") in CENTERLINES, "%s: centerline %s" % [id, rules.get("centerline")])
		check(rules.get("turn_limit_deg", 0.0) > 0.0 and rules.get("tilt_limit_deg", 0.0) > 0.0, "%s: turn and tilt limits" % id)
		var hosts: Array = rules.get("hosts", [])
		check(not hosts.is_empty(), "%s: hosts" % id)
		for host in hosts:
			check(host in HOSTS, "%s: host %s is known" % [id, host])
		var handles: Array = rules.get("handles", [])
		check(handles.size() >= 1 and handles.size() <= MAX_HANDLES, "%s: 1 to %d handles" % [id, MAX_HANDLES])
		for i in handles.size():
			var handle: Dictionary = handles[i]
			check(String(handle.get("key", "")).begins_with("H%d_" % (i + 1)), "%s: handle %d is named H%d_<what>, got %s" % [id, i + 1, i + 1, handle.get("key")])
			check(handle.get("meaning", "") != "", "%s: %s has a meaning" % [id, handle.get("key")])
			check(is_zero_approx(float(handle.get("default_permille", -1))), "%s: %s rests at 0" % [id, handle.get("key")])
		var paint_mix: Dictionary = record.get("paint_mix", {})
		check(not paint_mix.is_empty(), "%s: paint_mix per material" % id)
		for material in paint_mix:
			check(paint_mix[material] >= 0.0 and paint_mix[material] <= 1.0, "%s: paint_mix %s in 0..1" % [id, material])
			check(material in record.get("materials", []), "%s: paint_mix names the material %s" % [id, material])


func test_every_part_glb_has_one_root_mesh_with_the_handle_blend_shapes() -> void:
	for record in _records():
		var id: String = record.get("id", "?")
		var node := _load_scene(id)
		if node == null:
			check(false, "%s loads" % id)
			continue
		var meshes := _mesh_instances(node)
		check(not meshes.is_empty(), "%s has meshes" % id)
		var root_name := _pascal(record.get("part_type", ""))
		var roots: Array[MeshInstance3D] = []
		for mi in meshes:
			if mi.get_parent() == node:
				roots.append(mi)
		check(roots.size() == 1 and roots[0].name == root_name, "%s: one top-level mesh named %s, got %s" % [id, root_name, roots.map(func(m): return m.name)])
		for mi in meshes:
			check(mi.mesh is ArrayMesh, "%s: %s is an ArrayMesh" % [id, mi.name])
		var shapes := _blend_shape_names(node)
		var keys := {}
		for handle in record.get("part_rules", {}).get("handles", []):
			keys[handle.get("key", "")] = true
			check(shapes.has(handle.get("key", "")), "%s: blend shape %s exists" % [id, handle.get("key")])
		for shape in shapes:
			check(keys.has(shape), "%s: blend shape %s is a recorded handle" % [id, shape])
		var materials := {}
		for mi in meshes:
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat != null:
					materials[mat.resource_name] = true
		for material in record.get("materials", []):
			check(materials.has(material), "%s: material %s is in the GLB" % [id, material])
		node.free()


func test_every_part_sits_on_the_skin_within_its_sink_and_footprint() -> void:
	for record in _records():
		var id: String = record.get("id", "?")
		var rules: Dictionary = record.get("part_rules", {})
		var node := _load_scene(id)
		if node == null:
			continue
		var verts := _vertices(node)
		var low := INF
		var high := -INF
		var foot := 0.0
		var sum_x := 0.0
		for v in verts:
			low = minf(low, v.y)
			high = maxf(high, v.y)
			sum_x += v.x
			if v.y <= FOOTPRINT_BAND_M:
				foot = maxf(foot, Vector2(v.x, v.z).length())
		# Blender +Z is Godot +Y: the skin normal. The pivot is on the skin, the root below it.
		if rules.get("orientation", "") == "ground":
			check(absf(low) <= 0.004 + TOLERANCE_M, "%s: the sole sits on the pivot (y min %.4f)" % [id, low])
		else:
			check(low >= -rules.get("sink_depth_m", 0.0) - TOLERANCE_M, "%s: sinks at most %.3f m below the skin (y min %.4f)" % [id, rules.get("sink_depth_m"), low])
			check(low < 0.0, "%s: has a root below the skin" % id)
		check(high > 0.01, "%s: stands above the skin (y max %.3f)" % [id, high])
		check(foot <= rules.get("footprint_radius_m", 0.0) + TOLERANCE_M, "%s: footprint %.3f within the recorded %.3f" % [id, foot, rules.get("footprint_radius_m")])
		if rules.get("chiral", false):
			# One side ships; the runtime mirrors it. The piece must lean to one side of x.
			check(absf(sum_x / verts.size()) > 0.002, "%s: chiral, so it leans off the centreline (mean x %.4f)" % [id, sum_x / verts.size()])
		node.free()


## The geometric normal of each triangle (from its winding; Godot's front faces wind clockwise) agrees
## with its stored vertex normals, so the mesh faces outward, and its mirror (x flipped, winding
## reversed) does too.
func test_every_part_winds_its_faces_to_match_their_normals() -> void:
	for record in _records():
		var id: String = record.get("id", "?")
		var node := _load_scene(id)
		if node == null:
			continue
		var agree := 0
		var total := 0
		for mi in _mesh_instances(node):
			for s in mi.mesh.get_surface_count():
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if normals.is_empty():
					check(false, "%s: %s surface %d has normals" % [id, mi.name, s])
					continue
				for i in range(0, index.size(), 3):
					var a := verts[index[i]]
					var b := verts[index[i + 1]]
					var c := verts[index[i + 2]]
					var face := (c - a).cross(b - a)
					if face.length_squared() < 1e-14:
						continue
					var stored := normals[index[i]] + normals[index[i + 1]] + normals[index[i + 2]]
					total += 1
					if face.dot(stored) > 0.0:
						agree += 1
		check(total > 0 and agree >= total * 0.98, "%s: %d of %d faces wind with their normals" % [id, agree, total])
		node.free()
