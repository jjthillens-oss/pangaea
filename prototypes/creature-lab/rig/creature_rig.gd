extends Node3D
## Presents one gait planner: a generated Skeleton3D with one TwoBoneIK3D chain per leg, driven by the planner's foot
## positions, plus primitive visuals (allowed in prototypes only) and per-frame rig measurements.
##
## Godot applies skeleton modifiers after the frame's process step and restores the unmodified pose afterwards, so the
## solved pose is read in the skeleton_updated signal. Measurements compare it with the targets set in sync().

var planner: RefCounted
var skeleton: Skeleton3D
var ik: TwoBoneIK3D
var targets: Array[Marker3D] = []
var poles: Array[Marker3D] = []
## Per leg: bone indices [hip, knee, foot].
var leg_bones: Array = []

## Rig measurements. Slip: solved foot to planned foot on a stance leg, over leg length.
var max_stance_slip_ratio := 0.0
var slip_samples := 0
var slip_sum := 0.0
var knee_flips := 0
var solved_frames := 0
var solved_finite := true
## Time.get_ticks_usec() when the last solved pose was read (for cost measurements).
var last_solved_usec := 0

var _body_visual: Node3D
var _segments: Array[MeshInstance3D] = []
var _joints: Array[MeshInstance3D] = []
var _stance_snapshot := PackedInt32Array()
var _target_snapshot: Array[Vector3] = []
var _knee_side := PackedFloat64Array()
var _show_visuals := true


func setup(gait_planner: RefCounted, body: Dictionary, color: Color, show_visuals := true) -> void:
	planner = gait_planner
	_show_visuals = show_visuals
	var mech = planner.mech
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	skeleton.add_bone("body")
	skeleton.set_bone_rest(0, Transform3D(Basis(), Vector3(0.0, mech.hip_height, 0.0)))
	for i in mech.legs.size():
		var leg: Dictionary = mech.legs[i]
		var hip: Vector3 = leg["hip"]
		var hip_bone := skeleton.add_bone("hip_%d" % i)
		skeleton.set_bone_parent(hip_bone, 0)
		skeleton.set_bone_rest(hip_bone, Transform3D(Basis(), Vector3(hip.x, hip.y - mech.hip_height, hip.z)))
		var knee_bone := skeleton.add_bone("knee_%d" % i)
		skeleton.set_bone_parent(knee_bone, hip_bone)
		skeleton.set_bone_rest(knee_bone, Transform3D(Basis(), Vector3(0.0, -leg["upper"], 0.0)))
		var foot_bone := skeleton.add_bone("foot_%d" % i)
		skeleton.set_bone_parent(foot_bone, knee_bone)
		skeleton.set_bone_rest(foot_bone, Transform3D(Basis(), Vector3(0.0, -leg["lower"], 0.0)))
		leg_bones.append([hip_bone, knee_bone, foot_bone])
	skeleton.reset_bone_poses()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL

	ik = TwoBoneIK3D.new()
	ik.name = "LegIK"
	skeleton.add_child(ik)
	ik.set_setting_count(mech.legs.size())
	for i in mech.legs.size():
		var target := Marker3D.new()
		target.name = "Target%d" % i
		target.top_level = true
		add_child(target)
		targets.append(target)
		var pole := Marker3D.new()
		pole.name = "Pole%d" % i
		pole.top_level = true
		add_child(pole)
		poles.append(pole)
		ik.set_root_bone(i, leg_bones[i][0])
		ik.set_middle_bone(i, leg_bones[i][1])
		ik.set_end_bone(i, leg_bones[i][2])
		ik.set_target_node(i, ik.get_path_to(target))
		ik.set_pole_node(i, ik.get_path_to(pole))
		_stance_snapshot.append(0)
		_target_snapshot.append(Vector3.ZERO)
		_knee_side.append(0.0)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)
	if show_visuals:
		_build_visuals(body, color)


## Copies the planner's body pose and foot targets to the rig and queues one IK solve.
func sync(dt: float) -> void:
	var basis := Basis(Vector3.UP, planner.yaw)
	global_transform = Transform3D(basis, planner.position)
	var forward := basis * Vector3(0.0, 0.0, -1.0)
	for i in targets.size():
		var leg: Dictionary = planner.mech.legs[i]
		targets[i].global_position = planner.foot[i]
		var hip: Vector3 = planner.hip_world(i)
		# Knees bend forward: the pole sits a leg length ahead of the hip, a little below it.
		poles[i].global_position = hip + forward * leg["length"] - Vector3.UP * 0.25 * leg["length"]
		_stance_snapshot[i] = planner.state[i]
		_target_snapshot[i] = planner.foot[i]
	skeleton.advance(dt)


func solved_joint_positions(i: int) -> Array[Vector3]:
	var to_world := skeleton.global_transform
	var bones: Array = leg_bones[i]
	return [to_world * skeleton.get_bone_global_pose(bones[0]).origin,
			to_world * skeleton.get_bone_global_pose(bones[1]).origin,
			to_world * skeleton.get_bone_global_pose(bones[2]).origin]


func _on_skeleton_updated() -> void:
	solved_frames += 1
	var mech = planner.mech
	for i in leg_bones.size():
		var joints := solved_joint_positions(i)
		var hip: Vector3 = joints[0]
		var knee: Vector3 = joints[1]
		var foot: Vector3 = joints[2]
		solved_finite = solved_finite and hip.is_finite() and knee.is_finite() and foot.is_finite()
		var length: float = mech.legs[i]["length"]
		if _stance_snapshot[i] == 0:
			var slip := foot.distance_to(_target_snapshot[i]) / length
			max_stance_slip_ratio = maxf(max_stance_slip_ratio, slip)
			slip_sum += slip
			slip_samples += 1
		# Knee side: which side of the hip-foot line the knee is on, along the pole direction. A sign change while the
		# leg is clearly bent is a knee flip.
		var axis := (foot - hip).normalized()
		var mid := (hip + foot) * 0.5
		var pole_dir := poles[i].global_position - mid
		pole_dir = (pole_dir - axis * pole_dir.dot(axis)).normalized()
		var side := (knee - mid).dot(pole_dir) / length
		if absf(side) > 0.02:
			if _knee_side[i] != 0.0 and signf(side) != signf(_knee_side[i]):
				knee_flips += 1
			_knee_side[i] = side
		if _show_visuals:
			_place_segment(_segments[2 * i], hip, knee)
			_place_segment(_segments[2 * i + 1], knee, foot)
			_joints[3 * i].global_position = hip
			_joints[3 * i + 1].global_position = knee
			_joints[3 * i + 2].global_position = foot
	if _show_visuals:
		_body_visual.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(0)
	last_solved_usec = Time.get_ticks_usec()


func _build_visuals(body: Dictionary, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = color.darkened(0.45)
	dark.roughness = 0.7
	# The body node follows the root bone; the capsule inside it lies along Z (its own long axis is Y).
	_body_visual = Node3D.new()
	_body_visual.top_level = true
	add_child(_body_visual)
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45 * float(body["body_width"])
	capsule.height = float(body["body_length"])
	capsule.material = mat
	torso.mesh = capsule
	torso.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_body_visual.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.3 * float(body["body_width"])
	head_mesh.height = 2.0 * head_mesh.radius
	head_mesh.material = dark
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.08, -0.5 * float(body["body_length"]))
	_body_visual.add_child(head)
	for i in planner.mech.legs.size():
		var leg: Dictionary = planner.mech.legs[i]
		for part in 2:
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.07 * leg["length"] * (1.0 if part == 0 else 0.75)
			cyl.bottom_radius = cyl.top_radius * 0.8
			cyl.height = 1.0
			cyl.radial_segments = 12
			cyl.material = mat
			seg.mesh = cyl
			seg.top_level = true
			add_child(seg)
			_segments.append(seg)
		for j in 3:
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.075 * leg["length"] * (1.0 if j < 2 else 0.9)
			sphere.height = 2.0 * sphere.radius
			sphere.radial_segments = 12
			sphere.rings = 6
			sphere.material = dark
			ball.mesh = sphere
			ball.top_level = true
			add_child(ball)
			_joints.append(ball)


func _place_segment(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-6:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	seg.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
