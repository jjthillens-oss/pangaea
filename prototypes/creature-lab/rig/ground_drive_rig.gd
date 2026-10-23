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
	body.global_transform = Transform3D(Basis(Vector3.UP, planner.yaw),
			planner.position + Vector3(0.0, planner.body_lift(), 0.0))
	var skeleton: Skeleton3D = body.skeleton
	for i in planner.segments:
		if i != body.root_bone:
			skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.UP, planner.spine_angle(i)))
	for i in body.limb_roots.size():
		skeleton.set_bone_pose_rotation(body.limb_roots[i],
				Quaternion(Vector3.RIGHT, planner.limb_angle(i)))
	max_stance_slip_ratio = planner.max_belly_slip_ratio if mode == "slither" else planner.max_foot_slip_ratio
