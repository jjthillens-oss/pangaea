extends Node3D
## A generated creature walking: the Stage 1 skeleton and skin (rig/spine_rig.gd) with one TwoBoneIK3D chain per leg,
## driven by a gait planner built from the same body description (domain/gait_body.gd). Arms and other limbs keep
## their rest pose. Measures stance slip like rig/creature_rig.gd.

const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")

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


func setup(desc: RefCounted, arrays: Dictionary, gait_planner: RefCounted, gait_info: Dictionary, color: Color,
		placements := [], orientations := {}) -> void:
	planner = gait_planner
	gait = gait_info
	body = SpineRig.new()
	body.name = "Body"
	body.top_level = true
	add_child(body)
	body.setup(desc, arrays, color)
	if not placements.is_empty():
		body.add_parts(placements, orientations, true)
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
	# A leg wearing a foot stands on the foot's sole: the tip rides at the ankle height instead of its radius.
	for i in leg_bones.size():
		for p in body.part_nodes:
			if p["ground"] and p["entry"]["bone"] == leg_bones[i][2]:
				tip_lift[i] = load("res://game/domain/creature/anchor_resolver.gd").GROUND_ANKLE_M * p["scale"]
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
		_place_ground_parts(leg_bones[i][2], tip)
		if _stance_snapshot[i] == 0:
			var length: float = planner.mech.legs[i]["length"]
			max_stance_slip_ratio = maxf(max_stance_slip_ratio, tip.distance_to(_target_snapshot[i]) / length)


## Ground parts (feet) on this tip bone stand on the tip, level, facing the creature's heading, so a foot stays flat
## while the shin turns. Their twins are mirrored the same way.
func _place_ground_parts(tip_bone: int, tip: Vector3) -> void:
	var heading := Basis(Vector3.UP, planner.yaw)
	for p in body.part_nodes:
		if not p["ground"] or p["entry"]["bone"] != tip_bone:
			continue
		var b := heading.scaled_local(Vector3.ONE * p["scale"])
		if p["entry"]["twin"]:
			b = b * Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
		var lift: float = load("res://game/domain/creature/anchor_resolver.gd").GROUND_ANKLE_M * p["scale"]
		(p["node"] as Node3D).global_transform = Transform3D(b, tip - Vector3(0.0, lift, 0.0))
