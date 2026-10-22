extends SceneTree
## Runs every tests/test_*.gd file. Each test is a method named test_*.
## Usage: godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 when every test passes, 1 otherwise.


func _initialize() -> void:
	var files := DirAccess.get_files_at("res://tests")
	var total := 0
	var failed := 0
	var lines := PackedStringArray()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + file)
		var suite: TestCase = script.new()
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.current_test = "%s::%s" % [file.get_basename(), name]
			var before := suite.failures.size()
			suite.before_each()
			suite.call(name)
			suite.after_each()
			if suite.failures.size() > before:
				failed += 1
				lines.append("FAIL " + suite.current_test)
				for i in range(before, suite.failures.size()):
					lines.append("     " + suite.failures[i])
			else:
				lines.append("ok   " + suite.current_test)
	for line in lines:
		print(line)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
