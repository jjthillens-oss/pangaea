extends SceneTree
## Standalone ground-drive checks; the same checks also run from tests/run_tests.gd.

const Checks := preload("res://tests/ground_drive_checks.gd")


func _init() -> void:
	var failures: int = Checks.run_checks()
	await process_frame
	failures += Checks.run_pose_checks(root)
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
