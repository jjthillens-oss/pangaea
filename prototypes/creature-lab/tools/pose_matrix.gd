extends "res://tests/run_stage1_tests.gd"
## Posing error of linear blend skinning against the regenerated posed surface, for each Stage 1 body over a range
## of spine bends and limb swings (CREATURE_GEOMETRY_SPEC.md section 10 test 6). Writes results/pose_error.json.
## Run: godot --headless --path prototypes/creature-lab --script res://tools/pose_matrix.gd

const SETUPS := [[60.0, 0.0], [0.0, 30.0], [0.0, 45.0], [0.0, 90.0], [60.0, 30.0], [60.0, 90.0]]


func _init() -> void:
	rules = Lab.rules()
	var out := {"note": "max distance of a skinned vertex from the posed surface, as a fraction of body length",
			"setups": SETUPS, "bodies": {}}
	print("body              " + "  ".join(SETUPS.map(func(s): return "b%d/s%d" % [s[0], s[1]])))
	for body_name in Lab.stage1_names():
		var desc = Lab.body(body_name)
		var skin := SkinCpu.build(desc, int(rules["preview_divisions"]))
		var row := []
		for setup in SETUPS:
			var worst := 0.0
			for side in [-1.0, 1.0]:
				worst = maxf(worst, await pose_error(desc, skin, side, setup[0], setup[1]))
			row.append(snappedf(worst, 0.0001))
		out["bodies"][body_name] = row
		print("%-16s %s" % [body_name, "  ".join(row.map(func(e): return "%5.1f%%" % (100.0 * e)))])
	var f := FileAccess.open("res://results/pose_error.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t", false) + "\n")
	quit()
