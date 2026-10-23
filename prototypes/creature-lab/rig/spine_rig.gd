extends Node3D
## Presents a spine body: a generated Skeleton3D (one bone per vertebra), the generated skin as a skinned ArrayMesh,
## and a simple swim wave to show the automatic weights bending the skin. Primitive-free, but still prototype-only.

var desc: RefCounted
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var root_bone := 0
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
	skeleton.reset_bone_poses()
	var skin := Skin.new()
	for i in n:
		skin.add_bind(i, Transform3D(Basis(), desc.position_m(i)).affine_inverse())
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
	surface[Mesh.ARRAY_INDEX] = arrays["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
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
