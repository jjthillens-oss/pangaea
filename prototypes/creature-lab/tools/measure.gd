extends SceneTree
## Gait Lab rig measurements, headless. Runs every body through the scripted drives with the TwoBoneIK3D rig, then
## times 50 creatures. Writes results/measurements.json and prints a summary.
## Run: godot --headless --path prototypes/creature-lab --script res://tools/measure.gd

const Lab := preload("res://lab_data.gd")
const Drives := preload("res://lab_drives.gd")
const CreatureRig := preload("res://rig/creature_rig.gd")
const DT := 1.0 / 60.0

const RUNS := [["walk", 10.0], ["trot", 10.0], ["run", 10.0], ["turn_in_place", 6.0], ["reversal", 6.0],
		["random", 60.0]]


func _init() -> void:
	await process_frame
	var bodies: Dictionary = Lab.read_json("res://data/test_bodies.json")["bodies"]
	var results := {"engine": Engine.get_version_info()["string"], "dt": DT, "runs": [], "cost": []}
	for body_name in Lab.BODY_NAMES:
		for run in RUNS:
			var r := await _measure_run(body_name, bodies[body_name], run[0], run[1])
			results["runs"].append(r)
			print("%-10s %-13s slip max %.3f%% mean %.4f%%  knee flips %d  finite %s  reach %.3f  steps %d  early %d"
					% [body_name, run[0], 100.0 * r["max_slip_ratio"], 100.0 * r["mean_slip_ratio"], r["knee_flips"],
					r["finite"], r["max_stance_reach_ratio"], r["steps"], r["early_lifts"]])
	for count in [1, 10, 50]:
		var c := await _measure_cost(bodies, count)
		results["cost"].append(c)
		print("cost %2d quadrupeds: planner %.3f ms, rig sync %.3f ms, IK solve + callbacks %.3f ms, total %.3f ms/frame"
				% [count, c["planner_ms"], c["sync_ms"], c["solve_ms"], c["planner_ms"] + c["sync_ms"] + c["solve_ms"]])
	var f := FileAccess.open("res://results/measurements.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t", false, true) + "\n")
	quit()


func _measure_run(body_name: String, body: Dictionary, program: String, seconds: float) -> Dictionary:
	var planner = Lab.planner(body_name)
	var rig = CreatureRig.new()
	root.add_child(rig)
	rig.setup(planner, body, Color.WHITE, false)
	for f in int(round(seconds / DT)):
		var input := Drives.input(program, f * DT, 11)
		planner.step(DT, input.x, input.y)
		rig.sync(DT)
		await process_frame
	await process_frame
	var r := {
		"body": body_name, "drive": program, "seconds": seconds,
		"max_slip_ratio": rig.max_stance_slip_ratio,
		"mean_slip_ratio": rig.slip_sum / maxf(1.0, rig.slip_samples),
		"knee_flips": rig.knee_flips, "finite": rig.solved_finite and planner.is_finite_state(),
		"solved_frames": rig.solved_frames,
		"max_stance_reach_ratio": planner.max_stance_reach_ratio, "steps": planner.steps,
		"early_lifts": planner.early_lifts, "distance_m": planner.distance, "turned_deg": rad_to_deg(planner.turned),
		"top_speed_mps": planner.mech.v_top, "cycles": planner.cycles,
	}
	rig.queue_free()
	await process_frame
	return r


## Frame cost with `count` short quadrupeds on random drives (no visuals). The IK solve runs after the process step,
## deferred, so its cost is timed from the end of the sync loop to the last rig's skeleton_updated callback (IK solve
## plus the rig's measurement callback). Headless frames are capped, so frame time is not work time.
func _measure_cost(bodies: Dictionary, count: int) -> Dictionary:
	var rigs := []
	for n in count:
		var planner = Lab.planner("quad_short", Vector3((n % 10) * 3.0, 0.0, (n / 10) * 3.0))
		var rig = CreatureRig.new()
		root.add_child(rig)
		rig.setup(planner, bodies["quad_short"], Color.WHITE, false)
		rigs.append(rig)
	var frames := 600
	var planner_us := 0
	var sync_us := 0
	var solve_us := 0
	await process_frame
	for f in frames:
		var inputs: Array[Vector2] = []
		for n in count:
			inputs.append(Drives.input("random", f * DT, n + 1))
		var t0 := Time.get_ticks_usec()
		for n in count:
			rigs[n].planner.step(DT, inputs[n].x, inputs[n].y)
		var t1 := Time.get_ticks_usec()
		for n in count:
			rigs[n].sync(DT)
		var t2 := Time.get_ticks_usec()
		sync_us += t2 - t1
		planner_us += t1 - t0
		await process_frame
		var last := t2
		for r in rigs:
			last = maxi(last, r.last_solved_usec)
		solve_us += last - t2
	for r in rigs:
		r.queue_free()
	await process_frame
	var c := {"count": count, "frames": frames, "planner_ms": planner_us / 1000.0 / frames,
			"sync_ms": sync_us / 1000.0 / frames, "solve_ms": solve_us / 1000.0 / frames}
	return c
