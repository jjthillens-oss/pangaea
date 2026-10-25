extends TestCase
## The gait planner (game/domain/creature/gait_planner.gd), ported from the creature lab's tests/run_tests.gd:
## speed and cadence from leg length through the Froude table, duty factors, feet in reach, determinism, no NaN.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const DT := 1.0 / 60.0
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyDescription := preload("res://game/domain/creature/body_description.gd")
const ArmPose := preload("res://game/scenes/creature/arm_pose.gd")


func run(body_name: String, program: String, seconds: float, seed_value := 1) -> RefCounted:
	var p = Fixtures.planner(body_name)
	for f in int(round(seconds / DT)):
		var input := Fixtures.drive(program, f * DT, seed_value)
		p.step(DT, input.x, input.y)
	return p


func test_envelope_scales_with_root_leg_length() -> void:
	var short = Fixtures.gait_body("quad_short")
	var long = Fixtures.gait_body("quad_long")
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
				var input := Fixtures.drive(program, 4.0 + f * DT)
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


## The table's duty factors fall from walk to run, and every band's is a stance share between 0 and 1.
func test_duty_factors() -> void:
	var table = Fixtures.CreatureData.gait_table()
	var bands: Array = table.bands
	check(bands.size() >= 3, "at least walk, trot and run bands (%d)" % bands.size())
	var previous := 2.0
	for band in bands:
		var duty := float(band["duty"])
		check(duty > 0.0 and duty < 1.0, "%s duty factor %.2f is a stance share" % [band["name"], duty])
		check(duty <= previous, "%s duty factor %.2f does not rise from the band before" % [band["name"], duty])
		previous = duty


func test_patterns() -> void:
	var quad = Fixtures.gait_body("quad_short")
	# Legs: 0 LF, 1 LH, 2 RF, 3 RH.
	check(quad.pattern_offset(0, "trot") == quad.pattern_offset(3, "trot")
			and quad.pattern_offset(1, "trot") == quad.pattern_offset(2, "trot")
			and quad.pattern_offset(0, "trot") != quad.pattern_offset(1, "trot"), "quad trot moves diagonal pairs")
	var hexa = Fixtures.gait_body("hexapod")
	# Legs: 0 L1, 1 L2, 2 L3, 3 R1, 4 R2, 5 R3. Tripods: L1 L3 R2 and L2 R1 R3.
	var o := []
	for i in 6:
		o.append(hexa.pattern_offset(i, "trot"))
	check(o[0] == o[2] and o[2] == o[4] and o[1] == o[3] and o[3] == o[5] and o[0] != o[1], "hexapod trot is tripods")
	# Walk lifts hind before fore on the same side: larger offset lifts earlier.
	check(quad.pattern_offset(1, "walk") > quad.pattern_offset(0, "walk"), "quad walk wave runs back to front")


func test_stance_feet_never_move() -> void:
	var worst := 0.0
	for body_name in Fixtures.GAIT_BODY_NAMES:
		var p = Fixtures.planner(body_name)
		for f in 600:
			var before: Array[Vector3] = p.foot.duplicate()
			var was: PackedInt32Array = p.state.duplicate()
			var input := Fixtures.drive("demo", f * DT)
			p.step(DT, input.x, input.y)
			for i in p.foot.size():
				if was[i] == 0 and p.state[i] == 0:
					worst = maxf(worst, before[i].distance_to(p.foot[i]))
	check(worst == 0.0, "planned stance feet stay fixed in the world (worst move %.6f m)" % worst)


func test_turn_in_place_time_and_reach() -> void:
	for body_name in Fixtures.GAIT_BODY_NAMES:
		var p = Fixtures.planner(body_name)
		var m = p.mech
		while p.turned < 4.0 * PI and p.time < 60.0:
			p.step(DT, 0.0, 1.0)
		var predicted: float = 4.0 * PI / m.omega_max + m.omega_max / (2.0 * m.angular_accel_max)
		check(absf(p.time / predicted - 1.0) <= 0.10, "%s: 720 deg turn in %.2f s, predicted %.2f s (+-10%%)"
				% [body_name, p.time, predicted])
		check(p.max_stance_reach_ratio <= 1.0, "%s: turning, no stance foot past reach (max %.3f of leg length)"
				% [body_name, p.max_stance_reach_ratio])


func test_reversal_keeps_feet_in_reach() -> void:
	for body_name in Fixtures.GAIT_BODY_NAMES:
		var p = Fixtures.planner(body_name)
		for f in 180:
			p.step(DT, 0.6, 0.0)
		var yaw0: float = p.yaw
		while p.yaw - yaw0 < PI and p.time < 60.0:
			p.step(DT, 0.6, 1.0)
		check(p.yaw - yaw0 >= PI and p.max_stance_reach_ratio <= 1.0,
				"%s: 180 deg reversal at a trot in %.2f s, max stance reach %.3f, early lifts %d"
				% [body_name, p.time - 3.0, p.max_stance_reach_ratio, p.early_lifts])


func test_stop_settles_feet() -> void:
	for body_name in Fixtures.GAIT_BODY_NAMES:
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
	for body_name in Fixtures.GAIT_BODY_NAMES:
		var logs := []
		for attempt in 2:
			var p = Fixtures.planner(body_name)
			var lines := PackedStringArray()
			for f in 1200:
				var input := Fixtures.drive("random", f * DT, 7)
				p.step(DT, input.x, input.y)
				lines.append(p.log_line())
			logs.append("\n".join(lines).sha256_text())
		check(logs[0] == logs[1], "%s: two 20 s runs give byte-identical foot logs" % body_name)


func test_sixty_seconds_random_drive_stays_finite() -> void:
	for body_name in Fixtures.GAIT_BODY_NAMES:
		var p = Fixtures.planner(body_name)
		var finite := true
		for f in 3600:
			var input := Fixtures.drive("random", f * DT, 3)
			p.step(DT, input.x, input.y)
			finite = finite and p.is_finite_state()
		check(finite and p.max_stance_reach_ratio <= 1.0,
				"%s: 60 s random drive, finite state, max stance reach %.3f, steps %d, early lifts %d"
				% [body_name, p.max_stance_reach_ratio, p.steps, p.early_lifts])


## Uneven legs (body_mechanics.gd header): an ape on long arms stands front-up; a frog-like body on long hind legs
## folds them under it and sits about level; every hip at its own leg's standing height, and both walk with their feet
## in reach.
func test_uneven_legs_tilt_the_body_and_keep_each_hip_at_its_own_height() -> void:
	var table = CreatureData.gait_table()
	var ape := {"legs": [
		{"side": "L", "hip": [-0.25, 0.0, -0.45], "upper": 0.5, "lower": 0.5, "knee": "back"},
		{"side": "L", "hip": [-0.2, 0.0, 0.45], "upper": 0.25, "lower": 0.25, "knee": "forward"},
		{"side": "R", "hip": [0.25, 0.0, -0.45], "upper": 0.5, "lower": 0.5, "knee": "back"},
		{"side": "R", "hip": [0.2, 0.0, 0.45], "upper": 0.25, "lower": 0.25, "knee": "forward"}]}
	var frog := ape.duplicate(true)
	for leg in frog["legs"]:
		leg["hip"][2] = -float(leg["hip"][2])
	for case in [["ape", ape, 1.0], ["frog", frog, -1.0]]:
		var mech = BodyMechanics.create(case[0], case[1], table)
		if case[2] > 0:
			check(mech.rest_pitch > deg_to_rad(5.0), "%s: the body tilts front up (%.1f deg)" % [case[0],
					rad_to_deg(mech.rest_pitch)])
		else:
			check(mech.long_hind and absf(mech.rest_pitch) < deg_to_rad(5.0),
					"%s: long hind legs fold, the body sits about level (%.1f deg)" % [case[0],
					rad_to_deg(mech.rest_pitch)])
		var p = GaitPlanner.create(mech)
		for i in mech.legs.size():
			var ratio: float = table.long_hind_stance_ratio if mech.long_hind and mech.legs[i]["k"] > 0 \
					else table.stance_height_ratio
			var want: float = ratio * float(mech.legs[i]["length"])
			check(absf(p.hip_world(i).y - want) < 0.03, "%s leg %d: hip at %.3f m, its own height %.3f m" % [
					case[0], i, p.hip_world(i).y, want])
		for f in 240:
			var input := Fixtures.drive("walk", f * DT)
			p.step(DT, input.x, input.y)
		check(p.is_finite_state(), "%s: the walk stays finite" % case[0])
		for i in mech.legs.size():
			var reach: float = p.hip_world(i).distance_to(p.foot[i]) / float(mech.legs[i]["length"])
			check(reach <= 1.0, "%s leg %d: its foot stays in reach (%.2f of its length)" % [case[0], i, reach])


func test_even_legs_stand_level() -> void:
	check(Fixtures.gait_body("quad_short").rest_pitch == 0.0, "even legs: no tilt")
	check(Fixtures.gait_body("hexapod").rest_pitch == 0.0, "six even legs: no tilt")


## A monkey-like body through the real body description: an upright trunk on short hind legs, with arms long enough
## (`arm_reach` 1.0) to reach the ground or short ones (0.45) that cannot. Coordinates as tools/make_creature_presets.py.
func monkey_description(arm_reach: float) -> RefCounted:
	var d: RefCounted = BodyDescription.create()
	for v in [[600, -260, 95], [560, -170, 55], [450, -130, 110], [340, -70, 105], [250, 0, 95], [200, 90, 40]]:
		d.add_vertebra(Vector3i(0, v[0], v[1]), v[2])
	d.add_limb("v_5", [[Vector3i(90, 210, 0), 60], [Vector3i(125, 50, -70), 48], [Vector3i(120, -110, 0), 40],
			[Vector3i(120, -170, -70), 36]])
	var shoulder := Vector3(110, 460, -130)
	var arm: Array = []
	for j in [[Vector3(110, 460, -130), 45], [Vector3(220, 310, -160), 38], [Vector3(250, 110, -180), 32],
			[Vector3(250, -40, -190), 28]]:
		var p: Vector3 = shoulder + ((j[0] as Vector3) - shoulder) * arm_reach
		arm.append([Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)), j[1]])
	d.add_limb("v_3", arm)
	return d


## A frog-like body through the body description: short front legs, hind legs about twice as long, folded.
func frog_description() -> RefCounted:
	var d: RefCounted = BodyDescription.create()
	for v in [[170, -300, 70], [160, -200, 100], [150, -50, 110], [150, 80, 105], [150, 160, 80]]:
		d.add_vertebra(Vector3i(0, v[0], v[1]), v[2])
	d.add_limb("v_2", [[Vector3i(80, 150, -200), 40], [Vector3i(120, 50, -230), 30], [Vector3i(130, -30, -230), 25]])
	d.add_limb("v_4", [[Vector3i(90, 150, 80), 55], [Vector3i(220, 110, -70), 45], [Vector3i(170, -20, 170), 32],
			[Vector3i(170, -30, 90), 25]])
	return d


func drive_body(mech: RefCounted, program: String, seconds: float, seed_value := 1) -> RefCounted:
	var p = GaitPlanner.create(mech)
	for f in int(round(seconds / DT)):
		var input := Fixtures.drive(program, f * DT, seed_value)
		p.step(DT, input.x, input.y)
	return p


## Owner direction 2026-10-24 (walking follows limb sizes): long arms that reach the ground are front legs the body
## knuckle-walks on, leaning onto them; short arms that cannot reach stay arms the walker hangs (arm_pose.gd).
func test_long_arms_are_front_legs_and_short_arms_hang() -> void:
	var table = CreatureData.gait_table()
	var long_info := GaitBody.from_description(monkey_description(1.0))
	check((long_info["legs"] as Array).size() == 4, "long-armed monkey walks on 4 limbs (%d)"
			% (long_info["legs"] as Array).size())
	var mech = BodyMechanics.create("monkey", long_info["body"], table)
	var chains: Array = monkey_description(1.0).limb_chains()
	for i in mech.legs.size():
		var chain: int = long_info["legs"][i]
		var is_arm: bool = chains[chain]["source"] == "l_2"
		check(int(mech.legs[i]["k"]) == (0 if is_arm else 1), "monkey leg %d (%s) is %s on its side" % [i,
				"arm" if is_arm else "leg", "in front" if is_arm else "behind"])
	check(mech.rest_pitch < 0.0, "the sitting-up monkey leans forward onto its arms (%.1f deg)"
			% rad_to_deg(mech.rest_pitch))
	check(not mech.long_hind, "the monkey does not bound")
	for program in ["walk", "trot", "run", "random"]:
		var p = GaitPlanner.create(mech)
		var finite := true
		var worst := 0.0
		for f in 600:
			var input := Fixtures.drive(program, f * DT, 5)
			p.step(DT, input.x, input.y)
			finite = finite and p.is_finite_state()
			for i in mech.legs.size():
				if p.state[i] == GaitPlanner.STANCE:
					worst = maxf(worst, p.hip_world(i).distance_to(p.foot[i]) / float(mech.legs[i]["length"]))
		check(finite and worst <= 1.0 and p.max_stance_reach_ratio <= 1.0,
				"monkey %s: finite, stance feet in reach (worst %.3f of leg length)" % [program, worst])
		check(p.pattern() != "bound", "monkey %s steps in %s, not a bound" % [program, p.pattern()])
	var short_desc := monkey_description(0.45)
	var short_info := GaitBody.from_description(short_desc)
	var short_chains: Array = short_desc.limb_chains()
	check((short_info["legs"] as Array).size() == 2, "short-armed monkey walks on its 2 legs (%d)"
			% (short_info["legs"] as Array).size())
	for c in short_info["legs"]:
		check(short_chains[c]["source"] == "l_1", "chain %d the planner owns is a hind leg" % c)
	# The arms hang: a hand cannot reach the floor, so it hangs at its slight bend above it.
	var short_mech = BodyMechanics.create("short", short_info["body"], table)
	var centre: Vector3 = short_info["centre"]
	for c in short_chains.size():
		if (short_info["legs"] as Array).has(c):
			continue
		var pts: PackedVector3Array = short_chains[c]["points"]
		var length := 0.0
		for k in pts.size() - 1:
			length += pts[k].distance_to(pts[k + 1])
		var shoulder: Vector3 = pts[0] - centre + Vector3(0.0, short_mech.hip_height, 0.0)
		var aim: Dictionary = ArmPose.hang(shoulder, Basis(), signf(pts[0].x), length, 0.0, 0.0, 0.0, 0.0)
		check((aim["target"] as Vector3).y > 0.05 and shoulder.distance_to(aim["target"]) <= length,
				"short arm %d hangs in reach of its shoulder, its hand %.2f m above the floor" % [c,
				(aim["target"] as Vector3).y])


## Bound: four legs with long hind legs (frog, rabbit) bound at run speed, each pair in phase, the front pair landing
## first; walk and trot are unchanged, and bodies with even legs never bound.
func test_long_hind_legs_bound_at_a_run() -> void:
	var table = CreatureData.gait_table()
	var info := GaitBody.from_description(frog_description())
	check((info["legs"] as Array).size() == 4, "frog walks on 4 legs (%d)" % (info["legs"] as Array).size())
	var frog = BodyMechanics.create("frog", info["body"], table)
	check(frog.long_hind, "the frog's hind legs are long enough to bound")
	for body_name in Fixtures.GAIT_BODY_NAMES:
		check(not Fixtures.gait_body(body_name).long_hind, "%s does not bound" % body_name)
	var run_band: int = table.bands.size() - 1
	check(frog.band_pattern(run_band) == "bound" and frog.band_pattern(0) == "walk" and frog.band_pattern(1) == "trot",
			"frog: walk, trot, then bound")
	check(Fixtures.gait_body("quad_short").band_pattern(run_band) == "trot", "an even quadruped still runs at a trot")
	var front: Array = []
	var hind: Array = []
	for i in frog.legs.size():
		(front if frog.legs[i]["k"] == 0 else hind).append(i)
	check(frog.pattern_offset(front[0], "bound") == frog.pattern_offset(front[1], "bound")
			and frog.pattern_offset(hind[0], "bound") == frog.pattern_offset(hind[1], "bound")
			and is_equal_approx(frog.pattern_offset(front[0], "bound") - frog.pattern_offset(hind[0], "bound"),
			table.bound_pair_lag), "bound: front pair together, hind pair together, the front pair %.2f ahead"
			% table.bound_pair_lag)
	var p = drive_body(frog, "run", 3.0)
	check(p.pattern() == "bound", "frog at full throttle bounds (%s)" % p.pattern())
	var pairs_together := true
	var flight_frames := 0
	var pitch_lo := INF
	var pitch_hi := -INF
	var bob_lo := INF
	var bob_hi := -INF
	var finite := true
	for f in 180:
		p.step(DT, 1.0, 0.0)
		finite = finite and p.is_finite_state()
		pairs_together = pairs_together and p.state[front[0]] == p.state[front[1]] \
				and p.state[hind[0]] == p.state[hind[1]]
		if not p.state.has(GaitPlanner.STANCE):
			flight_frames += 1
		pitch_lo = minf(pitch_lo, p.hop_pitch)
		pitch_hi = maxf(pitch_hi, p.hop_pitch)
		bob_lo = minf(bob_lo, p.bob)
		bob_hi = maxf(bob_hi, p.bob)
	check(finite and p.max_stance_reach_ratio <= 1.0, "frog bound: finite, stance feet in reach (max %.3f)"
			% p.max_stance_reach_ratio)
	check(pairs_together, "frog bound: each pair stands and swings together")
	check(flight_frames > 20, "frog bound: a flight with every foot off the ground (%d of 180 frames)" % flight_frames)
	check(rad_to_deg(pitch_hi - pitch_lo) > table.bound_pitch_deg, "frog bound: the body pitches %.1f deg through a hop"
			% rad_to_deg(pitch_hi - pitch_lo))
	check(bob_hi - bob_lo > 0.5 * table.bound_bob_ratio * frog.hip_height and bob_hi <= 1e-9,
			"frog bound: the body dips %.3f m and never rises above its standing height" % (bob_hi - bob_lo))
	for program in ["walk", "trot"]:
		var q = drive_body(frog, program, 4.0)
		check(q.pattern() == program and q.hop_weight < 0.01, "frog at a %s steps in a %s" % [program, q.pattern()])
	var logs := []
	for attempt in 2:
		var r = GaitPlanner.create(frog)
		var lines := PackedStringArray()
		for f in 1800:
			var input := Fixtures.drive("random", f * DT, 11)
			r.step(DT, input.x, input.y)
			lines.append(r.log_line())
		logs.append("\n".join(lines).sha256_text())
		check(r.is_finite_state() and r.max_stance_reach_ratio <= 1.0,
				"frog 30 s random drive: finite, stance reach %.3f" % r.max_stance_reach_ratio)
	check(logs[0] == logs[1], "frog: two random drives give byte-identical foot logs")
