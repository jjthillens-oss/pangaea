extends Node3D
## A generated creature walking: the Stage 1 skeleton and skin (rig/spine_rig.gd) with one TwoBoneIK3D chain per leg,
## driven by a gait planner built from the same body description (domain/gait_body.gd). Limbs the planner does not
## own (arms) hang from their attach joint instead of keeping their editor pose: elbow a little forward, the tip just
## above the ground when the arm reaches it, swinging with the gait's cadence (arm_pose.gd). Measures stance slip
## like rig/creature_rig.gd.

const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const ArmPose := preload("res://game/scenes/creature/arm_pose.gd")

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
## Per arm (a limb chain the planner does not own): {chain, root, middle, end: bone indices (middle -1 on a two-joint
## stub), upper, lower, length: m, side: -1.0 left / 1.0 right, lift: m the tip hangs above the ground}.
var arms: Array = []
## Per arm: the tip's last world position, from the last sync, for tests.
var arm_tips: Array[Vector3] = []

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
	for c in chains.size():
		if legs.has(c):
			continue
		var pts: PackedVector3Array = chains[c]["points"]
		var count := pts.size()
		var first: int = body.limb_roots[c]
		var arm := {"chain": c, "root": first, "middle": first + 1 if count >= 3 else -1, "end": first + count - 1,
				"upper": pts[0].distance_to(pts[1]), "lower": pts[1].distance_to(pts[count - 1]) if count >= 3 else 0.0,
				"length": 0.0, "side": -1.0 if pts[0].x < 0.0 else 1.0,
				"lift": (chains[c]["radii"] as PackedFloat32Array)[count - 1]}
		for k in count - 1:
			arm["length"] += pts[k].distance_to(pts[k + 1])
		for p in body.part_nodes:
			if p["ground"] and p["entry"]["bone"] == arm["end"]:
				arm["lift"] = load("res://game/domain/creature/anchor_resolver.gd").GROUND_ANKLE_M * p["scale"]
		arms.append(arm)
		arm_tips.append(Vector3.ZERO)
	# Arms start hanging, so a rig that is never synced (a far rival) still carries them at rest.
	body.transform = _body_pose()
	_pose_arms(false)
	skeleton.skeleton_updated.connect(_on_skeleton_updated)


## The body's world transform from the planner: its ground pose with the gait origin at the hips' centre.
func _body_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, planner.yaw), planner.position) * planner.body_pose_local() \
			* Transform3D(Basis(), -(gait["centre"] as Vector3))


## Copies the planner's body pose and foot targets to the rig and queues one IK solve.
func sync(dt: float) -> void:
	var basis := Basis(Vector3.UP, planner.yaw)
	# The body is top_level, so its own transform is its world transform.
	body.transform = _body_pose()
	for i in targets.size():
		var leg: Dictionary = planner.mech.legs[i]
		# The targets and poles are top_level too, so their positions are world positions, in or out of the tree.
		targets[i].position = planner.foot[i] + Vector3(0.0, tip_lift[i], 0.0)
		poles[i].position = planner.hip_world(i) + basis * ((leg["pole"] as Vector3) * leg["length"])
		_stance_snapshot[i] = planner.state[i]
		_target_snapshot[i] = targets[i].position
	_pose_arms(true)
	_synced = true
	body.skeleton.advance(dt)


## Poses every arm on the skeleton: hanging from its root with the elbow bent forward, the tip just above the
## ground when the arm reaches it, swinging with the gait when `alive` (arm_pose.gd). Plain bone poses, so they
## hold outside the tree and under the leg IK, which touches other bones.
func _pose_arms(alive: bool) -> void:
	var skeleton: Skeleton3D = body.skeleton
	var to_world: Transform3D = body.transform * skeleton.transform
	var to_body := to_world.affine_inverse()
	var heading := Basis(Vector3.UP, planner.yaw)
	var speed: float = clampf(absf(planner.v) / planner.mech.v_top, 0.0, 1.0) if alive else 0.0
	var time: float = planner.time if alive else 0.0
	for i in arms.size():
		var arm: Dictionary = arms[i]
		var root: int = arm["root"]
		var parent := skeleton.get_bone_parent(root)
		var parent_pose: Transform3D = skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
		var root_rest: Transform3D = skeleton.get_bone_rest(root)
		var shoulder_body: Vector3 = (parent_pose * root_rest).origin
		var shoulder: Vector3 = to_world * shoulder_body
		var aim: Dictionary = ArmPose.hang(shoulder, heading, arm["side"], arm["length"], planner.position.y + arm["lift"],
				planner.cycle_phase, speed, time)
		# The chain's rest directions, in the root's parent space (the bones' rest bases are identity).
		var mid_rest: Vector3 = skeleton.get_bone_rest(root + 1).origin
		var tip_rest := Vector3.ZERO
		for b in range(root + 1, int(arm["end"]) + 1):
			tip_rest += skeleton.get_bone_rest(b).origin
		var space := (parent_pose * root_rest).basis
		var target_local: Vector3 = space.inverse() * (to_body * (aim["target"] as Vector3) - shoulder_body)
		var pole_local: Vector3 = space.inverse() * (to_body * (aim["pole"] as Vector3) - shoulder_body)
		if int(arm["middle"]) < 0:
			skeleton.set_bone_pose_rotation(root, ArmPose.arc(tip_rest, target_local))
		else:
			var poses: Array = ArmPose.two_bone(mid_rest, tip_rest, target_local, pole_local)
			skeleton.set_bone_pose_rotation(root, poses[0])
			skeleton.set_bone_pose_rotation(int(arm["middle"]), poses[1])
		arm_tips[i] = to_world * skeleton.get_bone_global_pose(int(arm["end"])).origin


func _on_skeleton_updated() -> void:
	# The skeleton's update can still fire once after the rig left the tree (the stage swapping the world out), where
	# there is no global transform to read.
	if not _synced or not is_inside_tree():
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
	# A foot on an arm's tip hangs level there too.
	for i in arms.size():
		var tip := skeleton.global_transform * skeleton.get_bone_global_pose(int(arms[i]["end"])).origin
		solved_finite = solved_finite and tip.is_finite()
		arm_tips[i] = tip
		_place_ground_parts(int(arms[i]["end"]), tip)


func _exit_tree() -> void:
	_synced = false


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
