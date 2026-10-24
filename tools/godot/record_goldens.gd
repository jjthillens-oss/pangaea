extends SceneTree
## Records the golden M1 hashes (endless plan D.4; S1 spine T0.2): every scenario of
## tests/m1_scenarios.gd at every seed, to the last tick count once, recording each tick count on
## the way (3 scenarios x 4 seeds x 3 ticks = 36 records). It is not part of the test suite:
## tests/test_m1_goldens.gd compares against what it wrote. Pool mode stays bit-identical through
## S1, so the file is recorded once, at the base, and re-run at older commits whose sim is the same.
##
##   Write:   godot --headless --path . --script res://tools/godot/record_goldens.gd -- \
##              --out=res://tests/fixtures/m1_goldens.json --commit=<sha> [--reverified=<sha>,<sha>]
##   Compare: godot --headless --path . --script res://tools/godot/record_goldens.gd -- \
##              --compare=res://tests/fixtures/m1_goldens.json
## --compare re-runs every record and exits 1 on any difference (in a scratch copy at another
## commit, with this file and tests/m1_scenarios.gd copied in). It takes about 2 minutes here.
## Exit code: 0 written or equal, 1 a difference, 2 bad arguments or an unwritable file.

const Scenarios := preload("res://tests/m1_scenarios.gd")


func _initialize() -> void:
	var out := ""
	var compare := ""
	var commit := ""
	var reverified := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--compare="):
			compare = arg.trim_prefix("--compare=")
		elif arg.begins_with("--commit="):
			commit = arg.trim_prefix("--commit=")
		elif arg.begins_with("--reverified="):
			reverified = arg.trim_prefix("--reverified=").split(",", false)
	if out.is_empty() == compare.is_empty():
		push_error("record_goldens: pass exactly one of --out= and --compare=")
		quit(2)
		return
	var records := _record_all()
	if not compare.is_empty():
		quit(_compare(records, Scenarios.load_goldens(compare)))
		return
	var data := {
		"schema_version": Scenarios.SCHEMA_VERSION,
		"recorded_at": commit,
		"reverified_at": Array(reverified),
		"engine": Engine.get_version_info().string,
		"body": Scenarios.BODY,
		"scenarios": Array(Scenarios.SCENARIOS),
		"seeds": Scenarios.SEEDS,
		"ticks": Scenarios.TICKS,
		"hashes": records,
	}
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("record_goldens: cannot write %s" % out)
		quit(2)
		return
	f.store_string(JSON.stringify(data, "\t", false) + "\n")
	f.close()
	print("record_goldens: wrote %d records to %s" % [records.size(), out])
	quit(0)


## Every record, sorted by (scenario index, seed index, tick).
func _record_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for scenario in Scenarios.SCENARIOS:
		for seed_value in Scenarios.SEEDS:
			var t0 := Time.get_ticks_msec()
			out.append_array(Scenarios.run(scenario, seed_value, Scenarios.TICKS))
			print("record_goldens: %s seed %d in %.1f s" % [scenario, seed_value, (Time.get_ticks_msec() - t0) / 1000.0])
	return out


func _compare(records: Array[Dictionary], goldens: Dictionary) -> int:
	if goldens.is_empty():
		push_error("record_goldens: the goldens file is missing or unreadable")
		return 2
	var bad := 0
	for r in records:
		var why := Scenarios.difference(r, Scenarios.golden(goldens, r.scenario, r.seed, r.tick))
		if not why.is_empty():
			bad += 1
			print("record_goldens: " + why)
	print("record_goldens: %d records, %d differ" % [records.size(), bad])
	return 1 if bad > 0 else 0
