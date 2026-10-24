extends Node3D
## Visual adapter for the aquatic drive. It reuses the generated skin and skeleton.

const SpineRig := preload("res://rig/spine_rig.gd")

var planner: RefCounted
var body: Node3D
var mode := ""
var max_stance_slip_ratio := 0.0


func setup(desc: RefCounted, arrays: Dictionary, drive: RefCounted, color: Color,
		placements := [], orientations := {}) -> void:
	planner = drive
	mode = drive.mode
	body = SpineRig.new()
	body.name = "Body"
	add_child(body)
	body.setup(desc, arrays, color)
	if not placements.is_empty():
		body.add_parts(placements, orientations)


func sync(_dt: float) -> void:
	body.global_transform = planner.posed_root_transform()
	var skeleton: Skeleton3D = body.skeleton
	for i in planner.desc.vertebrae.size():
		if i != body.root_bone:
			skeleton.set_bone_pose_rotation(i, Quaternion(Vector3.UP, planner.spine_angle(i)))
	for i in body.limb_roots.size():
		skeleton.set_bone_pose_rotation(body.limb_roots[i], Quaternion(Vector3.RIGHT, planner.fin_angle(i)))
