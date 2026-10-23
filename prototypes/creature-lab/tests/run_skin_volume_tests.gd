extends SceneTree
## Headless hip/knee cross-section retention at extreme limb swings.
## Compares the skinned radius around each limb capsule with its rest radius.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const BodyField := preload("res://domain/body_field.gd")
const SpineRig := preload("res://rig/spine_rig.gd")
const ANGLES := [0.0, 45.0, 90.0]
const MIN_HIP_RADIUS := 0.75

func _init() -> void:
	var desc = Lab.body("s1_quadruped")
	var arrays: Dictionary = SkinCpu.build(desc, 48)
	var failures := 0
	for angle in ANGLES:
		var result := await measure(desc, arrays, angle)
		print("SKIN_VOLUME %ddeg hip_radius=%.3f knee_radius=%.3f hip_error=%.4f knee_error=%.4f samples=%d/%d" % [
				int(angle), result.hip_radius, result.knee_radius, result.hip_error, result.knee_error,
				result.hip_count, result.knee_count])
		if result.hip_count == 0 or result.knee_count == 0 or result.hip_radius < MIN_HIP_RADIUS:
			failures += 1
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)

func measure(desc: RefCounted, arrays: Dictionary, angle: float) -> Dictionary:
	var rig = SpineRig.new()
	root.add_child(rig)
	rig.setup(desc, arrays, Color.WHITE)
	var skel: Skeleton3D = rig.skeleton
	for first in rig.limb_roots:
		skel.set_bone_pose_rotation(first, Quaternion(Vector3.RIGHT, deg_to_rad(angle)))
	var skinning: Array[Transform3D] = []
	var origins := PackedVector3Array()
	for b in skel.get_bone_count():
		var g := skel.get_bone_global_pose(b)
		skinning.append(g * skel.get_bone_global_rest(b).affine_inverse())
		origins.append(g.origin)
	var rest_field = BodyField.from_description(desc)
	var field = BodyField.from_description(desc)
	for k in field.capsule_count():
		field.a[k] = origins[field.bone_a[k]]
		field.b[k] = origins[field.bone_b[k]]
	var vertices: PackedVector3Array = arrays.vertices
	var bones: PackedInt32Array = arrays.bones
	var weights: PackedFloat32Array = arrays.weights
	var custom: PackedFloat32Array = arrays.custom0
	var length: float = desc.bounds_m().get_longest_axis_size()
	var h: float = arrays.cell * 0.25
	var hip_radius := INF
	var knee_radius := INF
	var hip_error := 0.0
	var knee_error := 0.0
	var hip_count := 0
	var knee_count := 0
	for i in vertices.size():
		if custom[4 * i + 2] == 0.0:
			continue
		var along: float = custom[4 * i + 3]
		if along > 0.7:
			continue
		var p := Vector3.ZERO
		for slot in 4:
			p += weights[4 * i + slot] * (skinning[bones[4 * i + slot]] * vertices[i])
		var cap: int = rest_field.dominant(vertices[i])
		var rest_radius: float = vertices[i].distance_to(Geometry3D.get_closest_point_to_segment(
				vertices[i], rest_field.a[cap], rest_field.b[cap]))
		var posed_radius: float = p.distance_to(Geometry3D.get_closest_point_to_segment(
				p, field.a[cap], field.b[cap]))
		var ratio := posed_radius / maxf(rest_radius, 1e-6)
		var gradient := Vector3(field.sample(p + Vector3(h, 0, 0)) - field.sample(p - Vector3(h, 0, 0)),
				field.sample(p + Vector3(0, h, 0)) - field.sample(p - Vector3(0, h, 0)),
				field.sample(p + Vector3(0, 0, h)) - field.sample(p - Vector3(0, 0, h))) / (2.0 * h)
		var error: float = absf(field.sample(p) - BodyField.ISO) / maxf(gradient.length(), 1e-6) / length
		if along < 0.35:
			hip_radius = minf(hip_radius, ratio)
			hip_error = maxf(hip_error, error)
			hip_count += 1
		else:
			knee_radius = minf(knee_radius, ratio)
			knee_error = maxf(knee_error, error)
			knee_count += 1
	rig.queue_free()
	await process_frame
	return {"hip_radius": hip_radius, "knee_radius": knee_radius, "hip_error": hip_error,
			"knee_error": knee_error, "hip_count": hip_count, "knee_count": knee_count}
