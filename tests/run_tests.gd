extends SceneTree
## Runs every tests/test_*.gd file. Each test is a method named test_*.
## Usage: godot --headless --path . --script res://tests/run_tests.gd [-- flags]
## Exit code 0 when every test passes, 1 otherwise. A test that hits a script error (a crash in
## the code under test or in the test itself) fails, even if its checks before the error passed.
## Each test prints "run" as it starts and "ok" or "FAIL" as it ends, at once, so a run killed by a
## time limit (tools/check.sh) still shows every result so far and names the test that hung; the
## failures are repeated after the last test, above the totals.
##
## Flags, for quick local loops only (tools/check.sh and CI pass none and run everything but soak):
##   --skip-slow     skips the methods named test_slow_*
##   --only=a,b      runs only these files, named without ".gd" (test_creature_brain,test_pool_sim)
##
## Soak tier (S1): the methods named test_soak_* never run by default; --soak runs only them (still
## honouring --only=). tools/check_soak.sh passes --soak, in CI's parallel job "soak".


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
	var only: PackedStringArray = flags.only
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	var skipped := 0
	var soak_skipped := 0
	var failures: Array[String] = []   ## every FAIL line and its details, repeated at the end
	for wanted in only:
		if not files.has(wanted + ".gd"):
			# A misspelt name would otherwise run nothing and look like a pass.
			total += 1
			failed += 1
			_report(failures, ["FAIL --only: there is no tests/%s.gd" % wanted])
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if not only.is_empty() and not only.has(file.get_basename()):
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


## {"skip_slow": bool, "soak": bool, "only": PackedStringArray} from the arguments after "--".
static func _flags(args: PackedStringArray) -> Dictionary:
	var skip_slow := false
	var soak := false
	var only := PackedStringArray()
	for arg in args:
		if arg == "--skip-slow":
			skip_slow = true
		elif arg == "--soak":
			soak = true
		elif arg.begins_with("--only="):
			for name in arg.trim_prefix("--only=").split(",", false):
				only.append(name.strip_edges().trim_suffix(".gd"))
	return {"skip_slow": skip_slow, "soak": soak, "only": only}
