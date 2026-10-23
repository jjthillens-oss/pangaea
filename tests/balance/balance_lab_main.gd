extends SceneTree
## The balance lab's sweep (game/dev/balance_lab.gd): every body and bot over a range of seeds, headless.
## tools/balance_lab.sh runs it in shards and then merges them into the report.
##
##   run:   godot --headless --path . --script res://tests/balance/balance_lab_main.gd -- \
##            --seeds=1001-1008 --seconds=300 [--bodies=grazer,hunter] [--bots=evade,hunt] \
##            [--shard=0/4] --out=builds/balance/shard_0.json
##   merge: ... -- --merge=builds/balance --report=builds/balance/report.md
##
## A shard takes every n-th run of the sweep (body, then bot, then seed), so shards share the work
## evenly. Exit code 0 when every run started; the report is information, not a gate.

const BalanceLab := preload("res://game/dev/balance_lab.gd")


func _initialize() -> void:
	var flags := _flags(OS.get_cmdline_user_args())
	if flags.has("merge"):
		quit(_merge(str(flags.merge), str(flags.get("report", str(flags.merge).path_join("report.md")))))
		return
	var lab = BalanceLab.new()
	var seeds := _seeds(str(flags.get("seeds", "1001-1008")))
	var ticks := int(float(flags.get("seconds", "300")) * 60.0)
	var bodies: PackedStringArray = str(flags.bodies).split(",") if flags.has("bodies") else lab.bodies()
	var bots: PackedStringArray = str(flags.bots).split(",") if flags.has("bots") else BalanceLab.BOTS
	var shard := str(flags.get("shard", "0/1")).split("/")
	var index := int(shard[0])
	var count := maxi(1, int(shard[1]))
	var runs: Array = []
	var n := 0
	var failed := 0
	for body in bodies:
		for bot in bots:
			for seed_value in seeds:
				n += 1
				if (n - 1) % count != index:
					continue
				var t0 := Time.get_ticks_msec()
				var r: Dictionary = lab.run(body, bot, seed_value, ticks)
				if not r.ok:
					failed += 1
					print("balance-lab: FAIL %s %s %d: %s" % [body, bot, seed_value, ", ".join(r.errors)])
					continue
				runs.append(r)
				print("balance-lab: %s %s seed %d: %d deaths (%d starved), %d meals, %d tells, %d dodged, %d kills (%.1f s)" % [
					body, bot, seed_value, r.deaths, r.starved, r.meals, r.tells, r.dodges, r.kills,
					(Time.get_ticks_msec() - t0) / 1000.0])
	var out := str(flags.get("out", "builds/balance/shard_%d.json" % index))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"seeds": seeds, "ticks": ticks, "runs": runs}, "\t"))
	f.close()
	print("balance-lab: wrote %d runs to %s" % [runs.size(), out])
	quit(1 if failed > 0 else 0)


func _merge(dir: String, report_path: String) -> int:
	var runs: Array = []
	var ticks := 0
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if not (file.begins_with("shard_") and file.ends_with(".json")):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if not data is Dictionary:
			print("balance-lab: FAIL %s is not a shard" % file)
			return 1
		ticks = int(data.ticks)
		runs.append_array(data.runs)
	if runs.is_empty():
		print("balance-lab: FAIL no runs in %s" % dir)
		return 1
	var rows := BalanceLab.summarize(runs)
	var all := FileAccess.open(dir.path_join("balance.json"), FileAccess.WRITE)
	all.store_string(JSON.stringify({"ticks": ticks, "summary": rows, "runs": runs}, "\t"))
	all.close()
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	f.store_string(_report(rows, runs.size(), ticks))
	f.close()
	print("balance-lab: %d runs, report in %s" % [runs.size(), report_path])
	return 0


func _report(rows: Array[Dictionary], run_count: int, ticks: int) -> String:
	var seeds: Array = rows[0].seeds if not rows.is_empty() else []
	var lines := PackedStringArray([
		"# Balance lab report",
		"",
		"Build %s. %d runs of %.0f s each, seeds %s, a dead cell continuing after %.1f s. Bots: %s." % [
			BuildInfo.build_id(), run_count, ticks / 60.0, _seed_text(seeds),
			BalanceLab.DEATH_NOTICE_TICKS / 60.0, ", ".join(BalanceLab.BOTS)],
		"Status: information, not a gate. Flags use the lab's own PROPOSED reading thresholds.",
		"",
		"| Body | Bot | Survived whole run | Deaths / 5 min | Starved / 5 min | Median first death | Meals / min alive | Mean energy | Starving | Meetings / min | Tells dodged | Kills | Killed by |",
		"| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
	])
	for row in rows:
		var by := PackedStringArray()
		var names: Array = row.killed_by.keys()
		names.sort()
		for name in names:
			by.append("%s %d" % [name, row.killed_by[name]])
		lines.append("| %s | %s | %d of %d | %.2f | %.2f | %.0f s | %.1f | %.0f%% | %.0f%% | %.2f | %d of %d | %d | %s |" % [
			row.body, row.bot, row.survived_runs, row.runs, row.deaths_per_5_min, row.starved_per_5_min,
			row.median_first_death_s, row.meals_per_min, row.mean_energy_share * 100.0, row.starving_share * 100.0,
			row.meetings_per_min, row.dodges, row.tells, row.kills, ", ".join(by) if not by.is_empty() else "none"])
	lines.append("")
	lines.append("## Flags")
	lines.append("")
	var any := false
	for row in rows:
		var f := BalanceLab.flags(row)
		if f.is_empty():
			continue
		any = true
		lines.append("- **%s / %s:** %s" % [row.body, row.bot, "; ".join(f)])
	if not any:
		lines.append("None.")
	lines.append("")
	return "\n".join(lines)


static func _seed_text(seeds: Array) -> String:
	if seeds.is_empty():
		return "none"
	var sorted := seeds.duplicate()
	sorted.sort()
	return "%d to %d" % [int(sorted[0]), int(sorted[-1])] if sorted.size() > 1 else str(int(sorted[0]))


## "1001-1008" or "1,5,9" (or both, comma-separated) -> the seeds in order.
static func _seeds(text: String) -> Array[int]:
	var out: Array[int] = []
	for part in text.split(",", false):
		if "-" in part:
			var ends := part.split("-")
			for s in range(int(ends[0]), int(ends[1]) + 1):
				out.append(s)
		else:
			out.append(int(part))
	return out


static func _flags(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
