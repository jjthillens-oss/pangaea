extends SceneTree
## Records the endless identity hashes (S2 build plan BP-6 and 7.5): the runs of
## tests/test_endless_gates.gd's IDENTITY_RUNS on the real content, with growth off, to each tick
## count of IDENTITY_TICKS. It is not part of the test suite: tests/test_hash_identity.gd compares
## against what it wrote (S2G1, "with growth off, endless size 1 equals S1"). The file is recorded on
## the e2 base before any S2 merge. Re-recording needs a docs/DECISIONS.md line that names the S1
## change forcing it (s1-content's band-0 tiles, for one).
##
##   Write:   godot --headless --path . --script res://tools/godot/record_endless_hashes.gd -- \
##              --out=res://tests/fixtures/endless_s1_hashes.json --commit=<sha>
##   Compare: godot --headless --path . --script res://tools/godot/record_endless_hashes.gd -- \
##              --compare=res://tests/fixtures/endless_s1_hashes.json
## --compare re-runs every record and exits 1 on any difference. A run to 18,000 ticks takes about
## 20 s here.
##
## --set=s2 records S3's identity instead (S3 build plan BP3-2 and 7.5; T0.1, on e3-base): the runs of
## IDENTITY_S2_RUNS with growth on, under IDENTITY_S2_OVERRIDES, into
## res://tests/fixtures/endless_s2_hashes.json. Re-recording it needs a DECISIONS line that names the
## change forcing it.
## Exit code: 0 written or equal, 1 a difference, 2 bad arguments, content that is not the real
## world, or an unwritable file.

const Gates := preload("res://tests/test_endless_gates.gd")


func _initialize() -> void:
	var out := ""
	var compare := ""
	var commit := ""
	var s2 := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--compare="):
			compare = arg.trim_prefix("--compare=")
		elif arg.begins_with("--commit="):
			commit = arg.trim_prefix("--commit=")
		elif arg == "--set=s2":
			s2 = true
		elif arg != "--set=s1":
			push_error("record_endless_hashes: unknown argument %s" % arg)
			quit(2)
			return
	if out.is_empty() == compare.is_empty():
		push_error("record_endless_hashes: pass exactly one of --out= and --compare=")
		quit(2)
		return
	if not Gates.missing(Gates.SIM).is_empty() or Gates.content_path() != Gates.REAL_WORLD:
		push_error("record_endless_hashes: needs an endless sim on the real content (%s; content %s)" % [
			"; ".join(Gates.missing(Gates.SIM)), Gates.content_path()])
		quit(2)
		return
	if not out.is_empty() and commit.is_empty():
		push_error("record_endless_hashes: --out= needs --commit=<the e2 base commit>")
		quit(2)
		return
	var runs := _record_all(s2)
	if not compare.is_empty():
		quit(_compare(runs, Gates.identity_file(compare)))
		return
	var data := {"base_commit": commit, "content": Gates.REAL_WORLD, "growth": false, "runs": runs}
	if s2:
		data = {"base_commit": commit, "content": Gates.REAL_WORLD, "overrides": Gates.IDENTITY_S2_OVERRIDES,
			"overrides_note": "an override applies only where its key exists (landmark_return is absent on e3-base)",
			"runs": runs}
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("record_endless_hashes: cannot write %s" % out)
		quit(2)
		return
	f.store_string(JSON.stringify(data, "\t", false) + "\n")
	f.close()
	print("record_endless_hashes: wrote %d runs to %s" % [runs.size(), out])
	quit(0)


## Every run of IDENTITY_RUNS (or, with `s2`, IDENTITY_S2_RUNS) with its hashes, in that order.
func _record_all(s2: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in (Gates.IDENTITY_S2_RUNS if s2 else Gates.IDENTITY_RUNS):
		var t0 := Time.get_ticks_msec()
		var record := run.duplicate()
		record["hashes"] = Gates.identity_run_s2(run, Gates.IDENTITY_TICKS) if s2 else Gates.identity_run(run, Gates.IDENTITY_TICKS)
		out.append(record)
		print("record_endless_hashes: %s %s in %.1f s" % [run.name, record.hashes, (Time.get_ticks_msec() - t0) / 1000.0])
	return out


func _compare(runs: Array[Dictionary], file: Dictionary) -> int:
	if file.is_empty():
		push_error("record_endless_hashes: the identity file is missing or unreadable")
		return 2
	var want := {}
	for r in file.get("runs", []):
		if r is Dictionary:
			want[str(r.get("name", ""))] = r.get("hashes", {})
	var bad := 0
	for r in runs:
		for n in r.hashes:
			var w := str((want.get(r.name, {}) as Dictionary).get(n, ""))
			if w != str(r.hashes[n]):
				bad += 1
				print("record_endless_hashes: %s tick %s: %s, recorded %s" % [r.name, n, r.hashes[n], w])
	print("record_endless_hashes: %d runs, %d records differ" % [runs.size(), bad])
	return 1 if bad > 0 else 0
