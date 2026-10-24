extends SceneTree
## Runs every tests/test_*.gd file. Each test is a method named test_*.
## Usage: godot --headless --path . --script res://tests/run_tests.gd [-- flags]
## Exit code 0 when every test passes, 1 otherwise. A test that hits a script error (a crash in
## the code under test or in the test itself) fails, even if its checks before the error passed.
## Each test prints "run" as it starts and "ok" or "FAIL" as it ends, at once, so a run killed by a
## time limit (tools/check.sh) still shows every result so far and names the test that hung; the
## failures are repeated after the last test, above the totals.
##
## Flags (tools/check.sh passes none and runs everything but soak):
##   --skip-slow     skips the methods named test_slow_*, for quick local loops
##   --only=a,b      runs only these files, named without ".gd" (test_creature_brain,test_pool_sim)
##   --skip=a,b      runs every file but these (S1 build plan B-14); a file named in both is skipped
## A name in --only or --skip that matches no file fails the run, so a typo cannot pass unnoticed.
##
## Soak tier (S1): the methods named test_soak_* never run by default; --soak runs only them (still
## honouring --only= and --skip=). tools/check_soak.sh passes --soak, in CI's two parallel jobs:
## soak-a runs --only=test_endless_gates,test_endless_cost and soak-b --skip= the same files, so a
## new soak file lands in soak-b without a list edit.
##
## Fast-suite budget report (S2 gate S2G30): a run of every file outside the soak tier (check.sh's,
## or --skip-slow's) ends with each S2 track's fast time against its share: the time of the fast
## test methods (not test_slow_* or test_soak_*) in the test files the track owns (S2 build plan
## 5.1, BUDGET_FILES), less the same files' time on S2's base (S1_FAST_MS, read on e2's base
## 99ec158 here), and the whole fast tier against S1's. It is a reading, not a gate: wall-clock
## times move with the machine and its load.


## Counts script errors (not push_error messages, which some tests expect) as they are logged.
class ScriptErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


const SLOW_PREFIX := "test_slow_"
const SOAK_PREFIX := "test_soak_"

## S2G30's shares (s): what each S2 track may add to the fast tier (S2 build plan section 10). The
## whole fast tier's share is their sum (31 s: the build plan raised T2's 10 s to 11).
const BUDGET_SHARES := {"T0": 3.0, "T1": 6.0, "T2": 11.0, "T3": 4.0, "T4": 2.0, "T5": 5.0}
## The test files each S2 track owns or adds to (S2 build plan 5.1), named without ".gd". A file in
## none is S1's, which no S2 track changes.
const BUDGET_FILES := {
	"T0": ["test_hash_identity", "test_growth_gates", "test_endless_cost", "test_threat_fuzz", "test_endless_gates",
		"test_sim_purity", "test_endless_fuzz"],
	"T1": ["test_phenotype", "test_creature_brain", "test_interactions", "test_species_catalog", "test_threats_sim",
		"test_threat_gates", "test_relationships", "test_at_size", "test_brain_sources", "test_habits"],
	"T2": ["test_fuzz_invariants", "test_growth", "test_remnants", "test_growth_tick", "test_world_stream",
		"test_endless_sim", "test_dead_state", "test_creature_field", "test_carrion_field", "test_float_origin",
		"test_niches_endless"],
	"T3": ["test_world_config", "test_tile_catalog", "test_home_block", "test_world_gen", "test_tiles",
		"test_home_block_content", "test_world_layout_gates", "test_seams", "test_world_content"],
	"T4": ["test_persistence", "test_game_session", "test_endless_save", "test_checkpoints", "test_user_settings"],
	"T5": ["test_growth_view", "test_ghosts", "test_growth_hud", "test_world_scene", "test_world_hud",
		"test_ambience_contract", "test_debug_panel", "test_project_settings", "test_look_probe", "test_food_view",
		"test_pool_view", "test_ui_text", "test_run_flags", "test_rebase_view"],
}
## Each test file's fast tier (ms) on e2's base 99ec158, the S2 start (S1 with main merged), read on
## the 4-CPU build container with --skip-slow at load 3.5 to 3.8 (137.2 s in all, 954 tests); a file
## not in it is new in S2 and counts from 0.
const S1_FAST_MS := {
	"test_actor_state": 2, "test_ambience": 204, "test_ambience_contract": 895, "test_art_ladder": 195,
	"test_assets": 6430, "test_audio": 4274, "test_carrion_field": 1110, "test_checkpoints": 13489,
	"test_chunk_arena": 1532, "test_creature_brain": 3912, "test_creature_field": 268,
	"test_creature_senses": 1, "test_dead_state": 2178, "test_debug_panel": 860, "test_ecology": 1,
	"test_editor_session": 4, "test_endless_cost": 0, "test_endless_fuzz": 2049, "test_endless_gates": 266,
	"test_endless_save": 329, "test_endless_sim": 3923, "test_float_origin": 1121, "test_food_view": 1046,
	"test_game_session": 3293, "test_genome": 3, "test_home_block": 978, "test_home_block_content": 755,
	"test_interactions": 5, "test_json_values": 0, "test_kit_assets": 384, "test_kit_tints": 24,
	"test_lineage": 4, "test_locomotion": 34, "test_look_probe": 2, "test_m1_goldens": 2877,
	"test_membranes": 43, "test_menus": 44, "test_niches_endless": 2772, "test_part_placement": 382,
	"test_perf_sim_caches": 5787, "test_perf_world_caches": 4323, "test_persistence": 1271,
	"test_phenotype": 12, "test_placeholders": 86, "test_placement_kit": 198, "test_plane_space": 1,
	"test_plankton_field": 866, "test_pool_arena": 978, "test_pool_layout": 227, "test_pool_look": 76,
	"test_pool_sim": 3333, "test_pool_view": 440, "test_project_settings": 152, "test_rebase_view": 254,
	"test_respawn_rules": 0, "test_run_flags": 0, "test_s2_assets": 948, "test_settings": 16,
	"test_sim_purity": 195, "test_species_catalog": 186, "test_stable_id": 0, "test_swim_bot": 1824,
	"test_swim_input": 0, "test_threat_fuzz": 9989, "test_threat_indicators": 17, "test_threats_sim": 40823,
	"test_tile_catalog": 885, "test_tiles": 595, "test_ui_text": 117, "test_view_footprint": 2,
	"test_warm_up": 1, "test_world_checks": 1448, "test_world_config": 34, "test_world_content": 353,
	"test_world_gen": 1389, "test_world_hash": 30, "test_world_hud": 215, "test_world_scene": 830,
	"test_world_stream": 3582, "test_zone_lights": 3,
}


func _initialize() -> void:
	var errors := ScriptErrorCounter.new()
	OS.add_logger(errors)
	var flags := _flags(OS.get_cmdline_user_args())
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	var skipped := 0
	var soak_skipped := 0
	var failures: Array[String] = []   ## every FAIL line and its details, repeated at the end
	var fast_ms := {}                   ## test file -> its fast methods' time (the budget report)
	for problem in flag_problems(files, flags):
		# A misspelt name would otherwise run nothing (--only) or everything (--skip) and look fine.
		total += 1
		failed += 1
		_report(failures, ["FAIL " + problem])
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if not file_selected(file.get_basename(), flags):
			continue
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			# A file that fails to parse counts as a failure instead of stopping the run.
			total += 1
			failed += 1
			_report(failures, ["FAIL %s: script did not load (see the parse error above)" % file.get_basename()])
			continue
		var instance = script.new()
		if not instance is TestCase:
			total += 1
			failed += 1
			_report(failures, ["FAIL %s: does not extend TestCase" % file.get_basename()])
			continue
		var suite: TestCase = instance
		for method in suite.get_method_list():
			var name: String = method["name"]
			match tier_of(name, flags):
				"not a test":
					continue
				"soak skipped":
					soak_skipped += 1
					continue
				"slow skipped":
					skipped += 1
					continue
			total += 1
			suite.current_test = "%s::%s" % [file.get_basename(), name]
			if method["args"].size() > method["default_args"].size():
				# Calling it would raise a script error here in the runner and stop the run.
				failed += 1
				_report(failures, ["FAIL %s: test methods must take no arguments" % suite.current_test])
				continue
			var before := suite.failures.size()
			var errors_before := errors.count
			print("run  " + suite.current_test)
			var t0 := Time.get_ticks_usec()
			suite.before_each()
			suite.call(name)
			suite.after_each()
			if not name.begins_with(SLOW_PREFIX) and not name.begins_with(SOAK_PREFIX):
				var key := file.get_basename()
				fast_ms[key] = float(fast_ms.get(key, 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0
			if errors.count > errors_before:
				suite.failures.append("%s: %d script error(s), see the log above" % [suite.current_test, errors.count - errors_before])
			if suite.failures.size() > before:
				failed += 1
				var lines: Array[String] = ["FAIL " + suite.current_test]
				for i in range(before, suite.failures.size()):
					lines.append("     " + suite.failures[i])
				_report(failures, lines)
			else:
				print("ok   " + suite.current_test)
	OS.remove_logger(errors)
	if not failures.is_empty():
		print("\nFailed:")
		for line in failures:
			print(line)
	if (flags.only as PackedStringArray).is_empty() and (flags.skip as PackedStringArray).is_empty() and not flags.soak:
		for line in budget_report(fast_ms):
			print(line)
	var note := " (%d slow skipped)" % skipped if flags.skip_slow else ""
	if not flags.soak and soak_skipped > 0:
		note += " (%d soak skipped)" % soak_skipped
	print("\n%d tests, %d failed%s" % [total, failed, note])
	quit(1 if failed > 0 or total == 0 else 0)


## The S2 track that owns test file `name` (without ".gd"; BUDGET_FILES), or "S1".
static func track_of(name: String) -> String:
	for track in BUDGET_FILES:
		if (BUDGET_FILES[track] as Array).has(name):
			return track
	return "S1"


## Per S2 track, then S1's files and the whole fast tier: {"track", "share_s" (INF for S1's own
## files), "now_s", "base_s", "added_s"}, from each file's fast time now (`fast_ms`) and on S2's base
## (`base_ms`). Only files that ran count, so a file that is gone counts neither now nor before.
static func budget_rows(fast_ms: Dictionary, base_ms: Dictionary = S1_FAST_MS) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var all := {"track": "all", "share_s": 0.0, "now_s": 0.0, "base_s": 0.0, "added_s": 0.0}
	for track in BUDGET_SHARES:
		all.share_s += float(BUDGET_SHARES[track])
	for track in BUDGET_SHARES.keys() + ["S1"]:
		var row := {"track": track, "share_s": float(BUDGET_SHARES.get(track, INF)), "now_s": 0.0, "base_s": 0.0}
		for file in fast_ms:
			if track_of(file) == track:
				row.now_s += float(fast_ms[file]) / 1000.0
				row.base_s += float(base_ms.get(file, 0.0)) / 1000.0
		row["added_s"] = row.now_s - row.base_s
		all.now_s += row.now_s
		all.base_s += row.base_s
		rows.append(row)
	all.added_s = all.now_s - all.base_s
	rows.append(all)
	return rows


## The budget report's lines (S2G30).
static func budget_report(fast_ms: Dictionary, base_ms: Dictionary = S1_FAST_MS) -> PackedStringArray:
	var out := PackedStringArray(["", "Fast-suite budget (S2G30; a reading, not a gate): the fast tier's time per S2 track, now and on S2's base, against its share"])
	for row in budget_rows(fast_ms, base_ms):
		var share := "" if not is_finite(row.share_s) else ", share %.0f s%s" % [row.share_s, "" if row.added_s <= row.share_s else " (OVER)"]
		out.append("  %-3s %7.2f s now, %7.2f s on the base, %+7.2f s%s" % [row.track, row.now_s, row.base_s, row.added_s, share])
	return out


## Prints a failure's lines now and keeps them for the recap after the last test.
static func _report(failures: Array[String], lines: Array[String]) -> void:
	for line in lines:
		print(line)
		failures.append(line)


## What the run does with a method: "run", "not a test", "soak skipped" (a soak test without
## --soak, or any other test with it) or "slow skipped". tests/test_m1_goldens.gd checks it.
static func tier_of(method_name: String, flags: Dictionary) -> String:
	if not method_name.begins_with("test_"):
		return "not a test"
	if method_name.begins_with(SOAK_PREFIX) != flags.soak:
		return "soak skipped"
	if flags.skip_slow and method_name.begins_with(SLOW_PREFIX):
		return "slow skipped"
	return "run"


## Whether the run takes the test file `name` (without ".gd"): in --only when it is given, and
## never in --skip. tests/test_m1_goldens.gd checks it.
static func file_selected(name: String, flags: Dictionary) -> bool:
	var only: PackedStringArray = flags.only
	var skip: PackedStringArray = flags.skip
	return not skip.has(name) and (only.is_empty() or only.has(name))


## One message for each name in --only or --skip that matches none of `files` (the file names in
## tests/), each of which fails the run.
static func flag_problems(files: PackedStringArray, flags: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for flag in ["only", "skip"]:
		for wanted in flags[flag]:
			if not files.has(wanted + ".gd"):
				out.append("--%s: there is no tests/%s.gd" % [flag, wanted])
	return out


## {"skip_slow": bool, "soak": bool, "only": PackedStringArray, "skip": PackedStringArray} from the
## arguments after "--".
static func _flags(args: PackedStringArray) -> Dictionary:
	var skip_slow := false
	var soak := false
	var only := PackedStringArray()
	var skip := PackedStringArray()
	for arg in args:
		if arg == "--skip-slow":
			skip_slow = true
		elif arg == "--soak":
			soak = true
		elif arg.begins_with("--only="):
			only.append_array(_names(arg.trim_prefix("--only=")))
		elif arg.begins_with("--skip="):
			skip.append_array(_names(arg.trim_prefix("--skip=")))
	return {"skip_slow": skip_slow, "soak": soak, "only": only, "skip": skip}


## "a, b.gd" -> ["a", "b"].
static func _names(list: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in list.split(",", false):
		out.append(name.strip_edges().trim_suffix(".gd"))
	return out
