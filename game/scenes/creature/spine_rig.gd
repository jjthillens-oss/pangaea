extends Node3D
## Presents a spine body: a generated Skeleton3D (one bone per vertebra), the generated skin as a skinned ArrayMesh,
## and a simple swim wave to show the automatic weights bending the skin. Primitive-free, but still prototype-only.

var desc: RefCounted
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var root_bone := 0
## First bone of each limb chain (its joint 0), in limb_chains() order.
var limb_roots := PackedInt32Array()
## Placed parts: {node: Node3D, entry: placement from AnchorResolver, ground: bool, scale: float}.
var part_nodes: Array = []
var swim_amplitude_deg := 9.0
var swim_wavelength := 0.9  # in body lengths
var swim_frequency := 0.8  # cycles per second

var _phase := 0.0


func setup(description: RefCounted, arrays: Dictionary, color: Color) -> void:
	desc = description
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	var n: int = desc.vertebrae.size()
	# Root at the vertebra nearest the middle of the body, chains out to the head and to the tail.
	var centre := Vector3.ZERO
	for i in n:
		centre += desc.position_m(i)
	centre /= n
	var best := INF
	for i in n:
		var d: float = desc.position_m(i).distance_to(centre)
		if d < best:
			best = d
			root_bone = i
	for i in n:
		skeleton.add_bone("spine_%02d" % i)
	for i in n:
		var parent := -1
		if i < root_bone:
			parent = i + 1
		elif i > root_bone:
			parent = i - 1
		skeleton.set_bone_parent(i, parent)
		var local: Vector3 = desc.position_m(i) - (desc.position_m(parent) if parent >= 0 else Vector3.ZERO)
		skeleton.set_bone_rest(i, Transform3D(Basis(), local))
	# Limb bones follow, one per joint: joint 0 hangs from its vertebra, each later joint from the one before.
	var rest_points := PackedVector3Array()
	for i in n:
		rest_points.append(desc.position_m(i))
	for c in desc.limb_chains():
		var pts: PackedVector3Array = c["points"]
		var first: int = rest_points.size()
		limb_roots.append(first)
		for k in pts.size():
			var bone := skeleton.add_bone("limb_%02d_%d" % [c["limb_id"], k])
			var parent: int = c["attach"] if k == 0 else first + k - 1
			skeleton.set_bone_parent(bone, parent)
			skeleton.set_bone_rest(bone, Transform3D(Basis(), pts[k] - rest_points[parent]))
			rest_points.append(pts[k])
	skeleton.reset_bone_poses()
	var skin := Skin.new()
	for i in rest_points.size():
		skin.add_bind(i, Transform3D(Basis(), rest_points[i]).affine_inverse())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Skin"
	skeleton.add_child(mesh_instance)
	mesh_instance.mesh = build_mesh(arrays, color)
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")


static func build_mesh(arrays: Dictionary, color: Color) -> ArrayMesh:
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = arrays["vertices"]
	surface[Mesh.ARRAY_NORMAL] = arrays["normals"]
	surface[Mesh.ARRAY_BONES] = arrays["bones"]
	surface[Mesh.ARRAY_WEIGHTS] = arrays["weights"]
	surface[Mesh.ARRAY_CUSTOM0] = arrays["custom0"]
	# CUSTOM1.xyz: rest-pose position, so skin patterns stay round and fixed to the body when it bends (art contract §2.2).
	var rest := PackedFloat32Array()
	rest.resize(4 * arrays["vertices"].size())
	for i in arrays["vertices"].size():
		var v: Vector3 = arrays["vertices"][i]
		rest[4 * i] = v.x
		rest[4 * i + 1] = v.y
		rest[4 * i + 2] = v.z
	surface[Mesh.ARRAY_CUSTOM1] = rest
	surface[Mesh.ARRAY_INDEX] = arrays["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface, [], {},
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	mat.rim_enabled = true
	mat.rim = 0.25
	mesh.surface_set_material(0, mat)
	return mesh


## A travelling wave from head to tail about the vertical axis; each bone turns relative to its parent.
func swim(dt: float) -> void:
	_phase += TAU * swim_frequency * dt
	var n: int = desc.vertebrae.size()
	var length: float = desc.bounds_m().get_longest_axis_size()
	for i in n:
		if i == root_bone:
			continue
		var along: float = desc.position_m(i).distance_to(desc.position_m(0)) / length
		var tailward := 1.0 if i > root_bone else 0.35
		var angle := deg_to_rad(swim_amplitude_deg) * tailward * sin(_phase - TAU * along / swim_wavelength)
		skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.UP, angle))
	# Limbs paddle: each swings about the body's X axis at its root, the pairs in opposite phase.
	for c in limb_roots.size():
		var swing := deg_to_rad(2.0 * swim_amplitude_deg) * sin(_phase + PI * float(c % 2) + 0.7 * float(c / 2))
		skeleton.set_bone_pose_rotation(limb_roots[c], Quaternion(Vector3.RIGHT, swing))


## The posing sweep of CREATURE_GEOMETRY_SPEC.md section 10 test 6 at time t: the spine bends to +-60 degrees in
## total and each limb swings +-90 degrees at its root, on slower and faster sines so every combination shows.
func pose_sweep(t: float) -> void:
	var n: int = desc.vertebrae.size()
	var bend := deg_to_rad(60.0) * sin(TAU * 0.25 * t) / float(maxi(1, n - 1))
	for i in n:
		if i != root_bone:
			skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.UP, bend))
	for c in limb_roots.size():
		var swing := deg_to_rad(90.0) * sin(TAU * 0.4 * t + PI * float(c % 2))
		skeleton.set_bone_pose_rotation(limb_roots[c], Quaternion(Vector3.RIGHT, swing))


## Length of the body along the spine in metres, end cap to end cap: the `body_length_m` shader uniform.
func body_length_m() -> float:
	var n: int = desc.vertebrae.size()
	var length: float = desc.radius_m(0) + desc.radius_m(n - 1)
	for i in n - 1:
		length += desc.position_m(i).distance_to(desc.position_m(i + 1))
	return length


## Puts the art team's part meshes on the body. `placements` comes from AnchorResolver.resolve_all. Each part rides on
## its host bone through a BoneAttachment3D; with `free_ground`, ground parts (feet) are left as top-level nodes for a
## walker to place each frame, so they stay flat while the shin turns.
func add_parts(placements: Array, orientations: Dictionary, free_ground := false) -> void:
	var PartLibrary := load("res://game/scenes/creature/part_library.gd")
	for e in placements:
		var part: Dictionary = desc.parts.filter(func(x): return x["id"] == e["part"])[0]
		var node: Node3D = PartLibrary.instance(part["type"])
		if node == null:
			continue
		PartLibrary.set_handles(node, part["handles"])
		node.name = "%s_%s%s" % [part["type"], part["id"], "_twin" if e["twin"] else ""]
		var ground: bool = orientations.get(part["type"], "normal") == "ground"
		var t: Transform3D = e["transform"]
		if ground and free_ground:
			node.top_level = true
			add_child(node)
		else:
			var attach := BoneAttachment3D.new()
			attach.bone_idx = e["bone"]
			skeleton.add_child(attach)
			attach.add_child(node)
			node.transform = skeleton.get_bone_global_rest(e["bone"]).affine_inverse() * t
		part_nodes.append({"node": node, "entry": e, "ground": ground, "scale": float(part["scale"]) / 1000.0})


## Uses the art team's creature skin shader on the body, sized by its length. Returns false if it is missing.
func use_skin_shader(params := {}) -> bool:
	var shader: Shader = load("res://game/scenes/creature/part_library.gd").skin_shader()
	if shader == null:
		return false
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("body_length_m", body_length_m())
	for k in params:
		mat.set_shader_parameter(k, params[k])
	mesh_instance.material_override = mat
	return true
