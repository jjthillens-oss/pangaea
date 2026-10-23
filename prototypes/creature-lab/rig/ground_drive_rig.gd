extends Node3D
## Visual adapter for GroundDrive. It poses the existing generated spine/skin without changing
## the skin builders or the normal WalkerRig's IK path.

const SpineRig := preload("res://rig/spine_rig.gd")

var planner: RefCounted
var body: Node3D
var mode := ""
var max_stance_slip_ratio := 0.0


func setup(desc: RefCounted, arrays: Dictionary, ground_drive: RefCounted, color: Color) -> void:
	planner = ground_drive
	mode = ground_drive.mode
	body = SpineRig.new()
	body.name = "Body"
	add_child(body)
	body.setup(desc, arrays, color)


func sync(_dt: float) -> void:
	body.global_transform = planner.posed_root_transform()
	var skeleton: Skeleton3D = body.skeleton
	for i in planner.segments:
		if i != body.root_bone:
			skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.UP, planner.spine_angle(i)))
	for i in body.limb_roots.size():
		var root_bone: int = body.limb_roots[i]
		skeleton.set_bone_pose_rotation(root_bone,
				Quaternion(Vector3.RIGHT, planner.limb_angle(i)))
		if mode == "shuffle":
			var tip := root_bone + 1
			var target_local: Vector3 = body.global_transform.affine_inverse() * planner.foot_target_world[i]
			var parent_local: Vector3 = skeleton.get_bone_global_pose(root_bone).affine_inverse() * target_local
			skeleton.set_bone_pose_position(tip, parent_local)
	max_stance_slip_ratio = planner.max_belly_slip_ratio if mode == "slither" else planner.max_foot_slip_ratio
