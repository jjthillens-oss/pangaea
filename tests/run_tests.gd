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
			suite.before_each()
			suite.call(name)
			suite.after_each()
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
	var note := " (%d slow skipped)" % skipped if flags.skip_slow else ""
	if not flags.soak and soak_skipped > 0:
		note += " (%d soak skipped)" % soak_skipped
	print("\n%d tests, %d failed%s" % [total, failed, note])
	quit(1 if failed > 0 or total == 0 else 0)


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
