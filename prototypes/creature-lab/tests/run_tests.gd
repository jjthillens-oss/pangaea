extends SceneTree
## Gait Lab domain tests. Run: godot --headless --path prototypes/creature-lab --script res://tests/run_tests.gd

const Lab := preload("res://lab_data.gd")
const Drives := preload("res://lab_drives.gd")
const GroundDriveChecks := preload("res://tests/ground_drive_checks.gd")
const DT := 1.0 / 60.0

var failures := 0


func _init() -> void:
	test_envelope_scales_with_root_leg_length()
	test_measured_speed_and_cadence_ratios()
	test_patterns()
	test_stance_feet_never_move()
	test_turn_in_place_time_and_reach()
	test_reversal_keeps_feet_in_reach()
	test_stop_settles_feet()
	test_deterministic_logs()
	test_sixty_seconds_random_drive()
	failures += GroundDriveChecks.run_checks()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func run(body_name: String, program: String, seconds: float, seed_value := 1) -> RefCounted:
	var p = Lab.planner(body_name)
	for f in int(round(seconds / DT)):
		var input := Drives.input(program, f * DT, seed_value)
		p.step(DT, input.x, input.y)
	return p


func test_envelope_scales_with_root_leg_length() -> void:
	var short = Lab.body("quad_short")
	var long = Lab.body("quad_long")
	check(is_equal_approx(long.v_top / short.v_top, sqrt(2.0)), "top speed ratio long/short is sqrt(2) (%.4f)"
			% (long.v_top / short.v_top))
	check(is_equal_approx(long.accel_max, short.accel_max), "acceleration limit does not depend on leg length")


## Speed and cadence measured from simulation over the last 4 s of an 8 s straight run, per gait.
func test_measured_speed_and_cadence_ratios() -> void:
	for program in ["walk", "trot", "run"]:
		var stats := {}
		for body_name in ["quad_short", "quad_long"]:
			var p = run(body_name, program, 4.0)
			var d0: float = p.distance
			var c0: float = p.cycles
			var e0: int = p.early_lifts
			for f in 240:
				var input := Drives.input(program, 4.0 + f * DT)
				p.step(DT, input.x, input.y)
			stats[body_name] = {"speed": (p.distance - d0) / 4.0, "cadence": (p.cycles - c0) / 4.0,
					"band": p.table.bands[p.band]["name"], "early": p.early_lifts - e0}
		var speed_ratio: float = stats["quad_long"]["speed"] / stats["quad_short"]["speed"]
		var cadence_ratio: float = stats["quad_long"]["cadence"] / stats["quad_short"]["cadence"]
		check(absf(speed_ratio / sqrt(2.0) - 1.0) <= 0.05, "%s: speed ratio long/short %.4f is sqrt(2) +-5%%"
				% [program, speed_ratio])
		check(absf(cadence_ratio * sqrt(2.0) - 1.0) <= 0.05, "%s: cadence ratio long/short %.4f is 1/sqrt(2) +-5%%"
				% [program, cadence_ratio])
		check(stats["quad_long"]["band"] == program and stats["quad_short"]["band"] == program,
				"%s: both bodies settle in the %s band" % [program, program])
		check(stats["quad_long"]["early"] == 0 and stats["quad_short"]["early"] == 0,
				"%s: no early (out-of-reach) lifts once the gait is steady" % program)


func test_patterns() -> void:
	var quad = Lab.body("quad_short")
	# Legs: 0 LF, 1 LH, 2 RF, 3 RH.
	check(quad.pattern_offset(0, "trot") == quad.pattern_offset(3, "trot")
			and quad.pattern_offset(1, "trot") == quad.pattern_offset(2, "trot")
			and quad.pattern_offset(0, "trot") != quad.pattern_offset(1, "trot"), "quad trot moves diagonal pairs")
	var hexa = Lab.body("hexapod")
	# Legs: 0 L1, 1 L2, 2 L3, 3 R1, 4 R2, 5 R3. Tripods: L1 L3 R2 and L2 R1 R3.
	var o := []
	for i in 6:
		o.append(hexa.pattern_offset(i, "trot"))
	check(o[0] == o[2] and o[2] == o[4] and o[1] == o[3] and o[3] == o[5] and o[0] != o[1], "hexapod trot is tripods")
	# Walk lifts hind before fore on the same side: larger offset lifts earlier.
	check(quad.pattern_offset(1, "walk") > quad.pattern_offset(0, "walk"), "quad walk wave runs back to front")


func test_stance_feet_never_move() -> void:
	var worst := 0.0
	for body_name in Lab.BODY_NAMES:
		var p = Lab.planner(body_name)
		for f in 600:
			var before: Array[Vector3] = p.foot.duplicate()
			var was: PackedInt32Array = p.state.duplicate()
			var input := Drives.input("demo", f * DT)
			p.step(DT, input.x, input.y)
			for i in p.foot.size():
				if was[i] == 0 and p.state[i] == 0:
					worst = maxf(worst, before[i].distance_to(p.foot[i]))
	check(worst == 0.0, "planned stance feet stay fixed in the world (worst move %.6f m)" % worst)


func test_turn_in_place_time_and_reach() -> void:
	for body_name in Lab.BODY_NAMES:
		var p = Lab.planner(body_name)
		var m = p.mech
		while p.turned < 4.0 * PI and p.time < 60.0:
			p.step(DT, 0.0, 1.0)
		var predicted: float = 4.0 * PI / m.omega_max + m.omega_max / (2.0 * m.angular_accel_max)
		check(absf(p.time / predicted - 1.0) <= 0.10, "%s: 720 deg turn in %.2f s, predicted %.2f s (+-10%%)"
				% [body_name, p.time, predicted])
		check(p.max_stance_reach_ratio <= 1.0, "%s: turning, no stance foot past reach (max %.3f of leg length)"
				% [body_name, p.max_stance_reach_ratio])


func test_reversal_keeps_feet_in_reach() -> void:
	for body_name in Lab.BODY_NAMES:
		var p = Lab.planner(body_name)
		for f in 180:
			p.step(DT, 0.6, 0.0)
		var yaw0: float = p.yaw
		while p.yaw - yaw0 < PI and p.time < 60.0:
			p.step(DT, 0.6, 1.0)
		check(p.yaw - yaw0 >= PI and p.max_stance_reach_ratio <= 1.0,
				"%s: 180 deg reversal at a trot in %.2f s, max stance reach %.3f, early lifts %d"
				% [body_name, p.time - 3.0, p.max_stance_reach_ratio, p.early_lifts])


func test_stop_settles_feet() -> void:
	for body_name in Lab.BODY_NAMES:
		var p = run(body_name, "trot", 3.0)
		for f in 240:
			p.step(DT, 0.0, 0.0)
		var worst := 0.0
		for i in p.foot.size():
			worst = maxf(worst, p.foot[i].distance_to(p.rest_world(i)) / p.mech.legs[i]["length"])
		check(worst <= p.table.settle_threshold_ratio and not p.state.has(1),
				"%s: 4 s after stopping every foot is planted near rest (worst %.3f of leg length, %d settle steps)"
				% [body_name, worst, p.settle_steps])


func test_deterministic_logs() -> void:
	for body_name in Lab.BODY_NAMES:
		var logs := []
		for attempt in 2:
			var p = Lab.planner(body_name)
			var lines := PackedStringArray()
			for f in 1200:
				var input := Drives.input("random", f * DT, 7)
				p.step(DT, input.x, input.y)
				lines.append(p.log_line())
			logs.append("\n".join(lines).sha256_text())
		check(logs[0] == logs[1], "%s: two 20 s runs give byte-identical foot logs" % body_name)


func test_sixty_seconds_random_drive() -> void:
	for body_name in Lab.BODY_NAMES:
		var p = Lab.planner(body_name)
		var finite := true
		for f in 3600:
			var input := Drives.input("random", f * DT, 3)
			p.step(DT, input.x, input.y)
			finite = finite and p.is_finite_state()
		check(finite and p.max_stance_reach_ratio <= 1.0,
				"%s: 60 s random drive, finite state, max stance reach %.3f, steps %d, early lifts %d"
				% [body_name, p.max_stance_reach_ratio, p.steps, p.early_lifts])
