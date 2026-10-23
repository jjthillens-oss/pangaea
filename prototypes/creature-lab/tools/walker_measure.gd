extends SceneTree
## Walker Lab measurements, headless: each Stage 1 body with legs runs the scripted drives on the generated rig.
## Reports stance slip (tip against the planned foot, over leg length) and whether the solve stayed finite.
## Writes results/walker_measurements.json.
## Run: godot --headless --path prototypes/creature-lab --script res://tools/walker_measure.gd

const Lab := preload("res://lab_data.gd")
const LabSpine := preload("res://lab_spine.gd")
const Drives := preload("res://lab_drives.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const GaitBody := preload("res://domain/gait_body.gd")
const WalkerRig := preload("res://rig/walker_rig.gd")
const DT := 1.0 / 60.0
const RUNS := [["walk", 6.0], ["trot", 6.0], ["run", 6.0], ["turn_in_place", 4.0], ["demo", 10.0]]


func _init() -> void:
	await process_frame
	var table = Lab.table()
	var results := {"runs": []}
	for body_name in LabSpine.stage1_names():
		var desc = LabSpine.body(body_name)
		var info := GaitBody.from_description(desc)
		if info["legs"].is_empty():
			print("%-16s no legs" % body_name)
			continue
		var arrays := SkinCpu.build(desc, 40)
		for run in RUNS:
			var mech = Lab.BodyMechanics.create(body_name, info["body"], table)
			var planner = Lab.GaitPlanner.create(mech)
			var rig = WalkerRig.new()
			root.add_child(rig)
			rig.setup(desc, arrays, planner, info, Color.WHITE)
			for f in int(round(run[1] / DT)):
				var input := Drives.input(run[0], f * DT, 11)
				planner.step(DT, input.x, input.y)
				rig.sync(DT)
				await process_frame
			await process_frame
			var r := {"body": body_name, "drive": run[0], "legs": info["legs"].size(),
					"max_slip_ratio": rig.max_stance_slip_ratio, "finite": rig.solved_finite and planner.is_finite_state(),
					"max_stance_reach_ratio": planner.max_stance_reach_ratio, "early_lifts": planner.early_lifts,
					"steps": planner.steps}
			results["runs"].append(r)
			print("%-16s %-13s legs %d  slip max %.3f%%  finite %s  reach %.3f  steps %d  early %d" % [body_name, run[0],
					r["legs"], 100.0 * r["max_slip_ratio"], r["finite"], r["max_stance_reach_ratio"], r["steps"],
					r["early_lifts"]])
			rig.queue_free()
			await process_frame
	var f := FileAccess.open("res://results/walker_measurements.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t", false, true) + "\n")
	quit()
