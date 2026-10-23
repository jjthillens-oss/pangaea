extends Node3D
## A generated creature walking: the Stage 1 skeleton and skin (rig/spine_rig.gd) with one TwoBoneIK3D chain per leg,
## driven by a gait planner built from the same body description (domain/gait_body.gd). Arms and other limbs keep
## their rest pose. Measures stance slip like rig/creature_rig.gd.

const SpineRig := preload("res://rig/spine_rig.gd")

var planner: RefCounted
var gait: Dictionary
var body: Node3D
var ik: TwoBoneIK3D
var targets: Array[Marker3D] = []
var poles: Array[Marker3D] = []
## Per leg: bone indices [hip, knee, tip].
var leg_bones: Array = []
## Per leg: the tip's radius, so the skin, not the bone, touches the ground.
var tip_lift := PackedFloat32Array()

var max_stance_slip_ratio := 0.0
var solved_frames := 0
var solved_finite := true
var _stance_snapshot := PackedInt32Array()
var _target_snapshot: Array[Vector3] = []
## The skeleton can update once before the first sync (after setup), when no targets are set yet; that is not a step.
var _synced := false


func setup(desc: RefCounted, arrays: Dictionary, gait_planner: RefCounted, gait_info: Dictionary, color: Color) -> void:
	planner = gait_planner
	gait = gait_info
	body = SpineRig.new()
	body.name = "Body"
	body.top_level = true
	add_child(body)
	body.setup(desc, arrays, color)
	var skeleton: Skeleton3D = body.skeleton
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	ik = TwoBoneIK3D.new()
	ik.name = "LegIK"
	skeleton.add_child(ik)
	var legs: Array = gait["legs"]
	ik.set_setting_count(legs.size())
	var chains: Array = desc.limb_chains()
	for i in legs.size():
		var first: int = body.limb_roots[legs[i]]
		var count: int = (chains[legs[i]]["points"] as PackedVector3Array).size()
		leg_bones.append([first, first + 1, first + count - 1])
		tip_lift.append((chains[legs[i]]["radii"] as PackedFloat32Array)[count - 1])
		var target := Marker3D.new()
		target.top_level = true
		add_child(target)
		targets.append(target)
		var pole := Marker3D.new()
		pole.top_level = true
		add_child(pole)
		poles.append(pole)
		ik.set_root_bone(i, first)
		ik.set_middle_bone(i, first + 1)
		ik.set_end_bone(i, first + count - 1)
		ik.set_target_node(i, ik.get_path_to(target))
		ik.set_pole_node(i, ik.get_path_to(pole))
		_stance_snapshot.append(0)
		_target_snapshot.append(Vector3.ZERO)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)


## Copies the planner's body pose and foot targets to the rig and queues one IK solve.
func sync(dt: float) -> void:
	var basis := Basis(Vector3.UP, planner.yaw)
	body.global_transform = Transform3D(basis, planner.position) * planner.body_pose_local() \
			* Transform3D(Basis(), -(gait["centre"] as Vector3))
	for i in targets.size():
		var leg: Dictionary = planner.mech.legs[i]
		targets[i].global_position = planner.foot[i] + Vector3(0.0, tip_lift[i], 0.0)
		poles[i].global_position = planner.hip_world(i) + basis * ((leg["pole"] as Vector3) * leg["length"])
		_stance_snapshot[i] = planner.state[i]
		_target_snapshot[i] = targets[i].global_position
	_synced = true
	body.skeleton.advance(dt)


func _on_skeleton_updated() -> void:
	if not _synced:
		return
	solved_frames += 1
	var skeleton: Skeleton3D = body.skeleton
	for i in leg_bones.size():
		var tip := skeleton.global_transform * skeleton.get_bone_global_pose(leg_bones[i][2]).origin
		solved_finite = solved_finite and tip.is_finite()
		if _stance_snapshot[i] == 0:
			var length: float = planner.mech.legs[i]["length"]
			max_stance_slip_ratio = maxf(max_stance_slip_ratio, tip.distance_to(_target_snapshot[i]) / length)
