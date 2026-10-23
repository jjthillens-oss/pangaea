extends SceneTree
## Standalone ground-drive checks; the same checks also run from tests/run_tests.gd.

const Checks := preload("res://tests/ground_drive_checks.gd")


func _initialize() -> void:
	var failures: int = Checks.run_checks()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
