extends SceneTree
## Runs walker rigs with arms through the real main loop for tests/test_creature_arms.gd, which cannot put nodes
## inside the tree itself (the runner's tests execute before the tree's first frame, and a skeleton outside the
## tree does not refresh its bone poses). Builds the quadruped with a pair of limbs grown from the side of the neck
## by the limb tool (as the lab's showcase does), then the same with a two-joint stub on the chest and a four-joint
## arm on the back, drives each and prints one "PROBE_RESULT {json}" line, then quits. Not a test file.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const Session := preload("res://game/domain/creature/creature_editor_session.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const ArmPose := preload("res://game/scenes/creature/arm_pose.gd")
const DT := 1.0 / 60.0


class ScriptErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _errors := ScriptErrorCounter.new()
var _rules := {}
var _part_rules := {}


func _initialize() -> void:
	OS.add_logger(_errors)
	_rules = CreatureData.rules()
	_part_rules = CreatureData.part_rules()
	_run()


func _run() -> void:
	await process_frame
	var out := {}
	var desc := body_with_neck_arms()
	out["neck_arms_ok"] = desc != null
	var rig := walker(desc)
	out["neck"] = {"legs": (rig.gait["legs"] as Array).size(), "arms": rig.arms.size(), "sides": [],
			"setup": []}
	for i in rig.arms.size():
		out["neck"]["sides"].append(rig.arms[i]["side"])
		# Before any sync (a far rival in the world), where the arms already hang.
		out["neck"]["setup"].append((shoulder_of(rig, rig.arms[i]).y - (rig.arm_tips[i] as Vector3).y)
				/ float(rig.arms[i]["length"]))
	out["neck"]["demo"] = await drive(rig, "demo", 600)
	out["neck"]["solved_finite"] = rig.solved_finite
	out["neck"]["solved_frames"] = rig.solved_frames
	rig.free()
	desc = body_with_neck_arms()
	add_stub_and_long_arm(desc)
	out["more_valid"] = desc.validate(_rules).is_empty()
	rig = walker(desc)
	out["more"] = {"legs": (rig.gait["legs"] as Array).size(), "arms": rig.arms.size()}
	out["more"]["demo"] = await drive(rig, "demo", 420)
	out["more"]["stand"] = await drive(rig, "stand", 240)
	# While standing, a long arm's tip rides on the ground line (the ground plus what the tip must clear).
	var long_arms := []
	for i in rig.arms.size():
		var arm: Dictionary = rig.arms[i]
		var shoulder := shoulder_of(rig, arm)
		if float(arm["length"]) * ArmPose.HANG_RATIO > shoulder.y - rig.planner.position.y:
			long_arms.append((rig.arm_tips[i] as Vector3).y - (rig.planner.position.y + float(arm["lift"])))
	out["more"]["long_arm_tip_over_line"] = long_arms
	out["more"]["trot"] = await drive(rig, "trot", 240)
	rig.free()
	out["script_errors"] = _errors.count
	print("PROBE_RESULT " + JSON.stringify(out))
	OS.remove_logger(_errors)
	quit(0)


## The quadruped with a mirrored pair of arms grown from the side of the neck by the limb tool, or null.
func body_with_neck_arms() -> RefCounted:
	var s := Session.new(Fixtures.body("s1_quadruped"), _rules, _part_rules, CreatureData.editor_costs(), 300)
	var neck: Vector3 = s.working.position_m(1)
	var hit: Dictionary = Picking.ray_to_skin(BodyField.from_description(s.working), neck + Vector3.RIGHT * 3.0, Vector3.LEFT)
	if not hit["hit"]:
		return null
	var limb: Dictionary = Picking.limb_at(s.working, _rules, hit["point"], hit["normal"])
	var r: Dictionary = s.add_limb(limb["attach"], limb["joints"], limb["mirror"])
	if not r["ok"] or not limb["mirror"]:
		return null
	return s.working


## A two-joint stub on the chest, pointing straight out, and a four-joint arm on the back, pointing up.
static func add_stub_and_long_arm(desc: RefCounted) -> void:
	var r0 := int(desc.vertebrae[2]["r"])
	var c2: Array = desc.vertebrae[2]["p"]
	var c4: Array = desc.vertebrae[4]["p"]
	desc.add_limb(desc.vertebrae[2]["id"], [[Vector3i(c2[0] + int(0.6 * r0), c2[1], c2[2]), int(0.5 * r0)],
			[Vector3i(c2[0] + 3 * r0, c2[1], c2[2]), int(0.45 * r0)]], true)
	desc.add_limb(desc.vertebrae[4]["id"], [[Vector3i(c4[0] + int(0.5 * r0), c4[1] + int(0.5 * r0), c4[2]), int(0.5 * r0)],
			[Vector3i(c4[0] + r0, c4[1] + 2 * r0, c4[2]), int(0.45 * r0)],
			[Vector3i(c4[0] + r0, c4[1] + 4 * r0, c4[2]), int(0.4 * r0)],
			[Vector3i(c4[0] + r0, c4[1] + 6 * r0, c4[2] - r0 / 2), int(0.35 * r0)]], true)


## A walker rig on `desc` in the tree, its planner at the origin heading -Z.
func walker(desc: RefCounted) -> Node3D:
	var info: Dictionary = GaitBody.from_description(desc)
	var mech = BodyMechanics.create("arms", info["body"], CreatureData.gait_table())
	var orientations: Dictionary = CreatureData.part_orientations(_part_rules)
	var rig: Node3D = WalkerRig.new()
	root.add_child(rig)
	rig.setup(desc, SkinCpu.build(desc, 24), GaitPlanner.create(mech, Vector3.ZERO, 0.0), info, Color.WHITE,
			AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	return rig


static func shoulder_of(rig: Node3D, arm: Dictionary) -> Vector3:
	return rig.body.transform * rig.body.skeleton.get_bone_global_pose(int(arm["root"])).origin


## Drives `program` for `frames` process frames, checking every arm tip after each sync: {least_drop: the smallest
## drop of a tip below its shoulder as a share of the arm's length, under_line: tips found under the ground line,
## over_reach: tips found further from the shoulder than the arm is long, finite: bool, travel: the first arm's
## tip z travel relative to its shoulder over the second half, below: tips found below the shoulder every frame}.
func drive(rig: Node3D, program: String, frames: int) -> Dictionary:
	var r := {"least_drop": INF, "under_line": 0, "over_reach": 0, "finite": true, "travel": 0.0, "frames": frames}
	var lo := INF
	var hi := -INF
	for f in frames:
		var input := Fixtures.drive(program, f * DT) if program != "stand" else Vector2.ZERO
		rig.planner.step(DT, input.x, input.y)
		rig.sync(DT)
		await process_frame
		for i in rig.arms.size():
			var arm: Dictionary = rig.arms[i]
			var tip: Vector3 = rig.arm_tips[i]
			var shoulder := shoulder_of(rig, arm)
			r["finite"] = r["finite"] and tip.is_finite()
			r["least_drop"] = minf(r["least_drop"], (shoulder.y - tip.y) / float(arm["length"]))
			if tip.y < rig.planner.position.y + float(arm["lift"]) - 1e-3:
				r["under_line"] += 1
			if shoulder.distance_to(tip) > float(arm["length"]) + 1e-3:
				r["over_reach"] += 1
			if i == 0 and f >= frames / 2:
				var dz: float = (rig.body.transform.basis.inverse() * (tip - shoulder)).z
				lo = minf(lo, dz)
				hi = maxf(hi, dz)
	r["travel"] = hi - lo
	return r
