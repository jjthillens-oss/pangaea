extends TestCase
## Arms on a walker (game/scenes/creature/walker_rig.gd, arm_pose.gd): limbs the gait planner does not own hang
## from their attach joint instead of keeping their editor pose. In a process of its own through the real main loop
## (tests/creature_arms_probe.gd), the quadruped with a pair of limbs grown from the side of the neck by the limb
## tool, then with a two-joint stub and a four-joint arm as well, is driven through the demo drive: every arm tip
## stays below its shoulder, above the ground line, within the arm's length and finite; the arms are not legs; a
## long arm's tip rides on the ground line while standing; the arms swing at a trot. The two-bone solver and the
## hang rule are checked here directly.

const ArmPose := preload("res://game/scenes/creature/arm_pose.gd")
const PROBE_SCRIPT := "res://tests/creature_arms_probe.gd"


func probe() -> Dictionary:
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", PROBE_SCRIPT], output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("PROBE_RESULT "):
			line = l.trim_prefix("PROBE_RESULT ")
	check(code == 0 and not line.is_empty(), "the probe ran (exit %d): %s" % [code, text.right(1200)])
	if line.is_empty():
		return {}
	return JSON.parse_string(line)


func check_drive(r: Dictionary, what: String, least_drop: float) -> void:
	check(bool(r["finite"]), "%s: every arm tip finite over %d frames" % [what, int(r["frames"])])
	check(int(r["under_line"]) == 0, "%s: no arm tip under the ground line (%d found)" % [what, int(r["under_line"])])
	check(int(r["over_reach"]) == 0, "%s: no arm tip further from its shoulder than the arm is long (%d found)"
			% [what, int(r["over_reach"])])
	check(float(r["least_drop"]) > least_drop, "%s: every arm tip stays at least %.2f of the arm's length below its shoulder (least %.3f)"
			% [what, least_drop, float(r["least_drop"])])


func test_arms_hang_below_the_shoulders_above_the_ground_and_swing_in_the_tree() -> void:
	var r := probe()
	if r.is_empty():
		return
	check(int(r["script_errors"]) == 0, "no script errors in the probe")
	check(bool(r["neck_arms_ok"]), "a mirrored pair of arms grown from the side of the neck")
	var neck: Dictionary = r["neck"]
	check_eq(int(neck["legs"]), 4, "the quadruped still walks on its four legs")
	check_eq(int(neck["arms"]), 2, "the two neck limbs are arms")
	check((neck["sides"] as Array).has(-1.0) and (neck["sides"] as Array).has(1.0), "one on each side (%s)" % str(neck["sides"]))
	for drop in neck["setup"]:
		check(float(drop) > 0.5, "an arm hangs before any sync, as a far rival's does (drop %.3f)" % float(drop))
	check_drive(neck["demo"], "neck arms, demo drive", 0.5)
	check(bool(neck["solved_finite"]) and int(neck["solved_frames"]) >= 500, "the leg IK solved every frame and stayed finite (%d)" % int(neck["solved_frames"]))
	check(bool(r["more_valid"]), "the body with a stub and a long arm is valid")
	var more: Dictionary = r["more"]
	check_eq(int(more["legs"]), 4, "still four legs")
	check_eq(int(more["arms"]), 6, "six arms: the neck pair, the stubs and the long pair")
	check_drive(more["demo"], "stub and long arms, demo drive", 0.3)
	check_drive(more["stand"], "stub and long arms, standing", 0.3)
	var long_arms: Array = more["long_arm_tip_over_line"]
	check(long_arms.size() == 2, "the four-joint arms reach the ground (%d)" % long_arms.size())
	for over in long_arms:
		check(absf(float(over)) < 0.02, "a long arm's tip rides on the ground line while standing (%.3f m over it)" % float(over))
	check_drive(more["trot"], "stub and long arms, trot", 0.3)
	check(float(more["trot"]["travel"]) > 0.01, "the arms swing at a trot (%.4f m of travel)" % float(more["trot"]["travel"]))
	check(float(more["stand"]["travel"]) < float(more["trot"]["travel"]), "and less while standing (%.4f m)" % float(more["stand"]["travel"]))


func test_the_two_bone_solver_and_the_hang() -> void:
	var mid := Vector3(0.0, -0.3, 0.0)
	var tip := Vector3(0.0, -0.7, 0.0)
	var target := Vector3(0.1, -0.5, -0.1)
	var poses: Array = ArmPose.two_bone(mid, tip, target, Vector3(0.0, 0.0, -1.0))
	var q_root: Quaternion = poses[0]
	var q_mid: Quaternion = poses[1]
	var mid_now: Vector3 = q_root * mid
	var tip_now: Vector3 = mid_now + (q_root * q_mid) * (tip - mid)
	check(tip_now.distance_to(target) < 1e-4, "a reachable target is reached (%s)" % tip_now)
	check(mid_now.z < 0.0, "the elbow bends towards the pole (%s)" % mid_now)
	poses = ArmPose.two_bone(mid, tip, Vector3(0.0, -2.0, 0.0), Vector3(0.0, 0.0, -1.0))
	tip_now = (poses[0] as Quaternion) * mid + ((poses[0] as Quaternion) * (poses[1] as Quaternion)) * (tip - mid)
	check(absf(tip_now.length() - 0.7) < 1e-3 and tip_now.y < -0.69, "an unreachable target gets a straight arm (%s)" % tip_now)
	var h: Dictionary = ArmPose.hang(Vector3(0.0, 1.0, 0.0), Basis(), 1.0, 0.5, 0.0, 0.0, 0.0, 0.0)
	check(is_equal_approx((h["target"] as Vector3).y, 1.0 - 0.5 * ArmPose.HANG_RATIO), "a short arm hangs most of its length (%s)" % h["target"])
	h = ArmPose.hang(Vector3(0.0, 1.0, 0.0), Basis(), 1.0, 2.0, 0.1, 0.0, 0.0, 0.0)
	check(is_equal_approx((h["target"] as Vector3).y, 0.1), "a long arm's hand stops at the floor line (%s)" % h["target"])
	check(((h["pole"] as Vector3).z < 0.0) and ((h["pole"] as Vector3).x > 0.0), "the elbow aims forward and out (%s)" % h["pole"])
	check(ArmPose.arc(Vector3.UP, Vector3.DOWN).is_normalized() and (ArmPose.arc(Vector3.UP, Vector3.DOWN) * Vector3.UP).is_equal_approx(Vector3.DOWN),
			"an about-turn still turns")
