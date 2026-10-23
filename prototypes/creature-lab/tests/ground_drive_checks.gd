extends RefCounted
## Shared checks for the required Gait Lab runner and the standalone ground-drive runner.

const LabSpine := preload("res://lab_spine.gd")
const Drives := preload("res://lab_drives.gd")
const GroundDrive := preload("res://domain/ground_drive.gd")
const DT := 1.0 / 60.0


static func run_checks() -> int:
	var failed := 0
	var short_speed := GroundDrive.speed_for_slither(1.0, 8)
	var long_speed := GroundDrive.speed_for_slither(2.0, 8)
	var segmented_speed := GroundDrive.speed_for_slither(2.0, 20)
	failed += _check(long_speed > short_speed and segmented_speed > long_speed,
			"slither speed grows with body length and segment count (%.3f, %.3f, %.3f m/s)"
			% [short_speed, long_speed, segmented_speed])
	failed += _check(segmented_speed <= 0.55 and GroundDrive.speed_for_slither(100.0, 100) <= 0.55,
			"slither speed remains at or below 0.55 m/s")

	var snake = GroundDrive.create(LabSpine.body("s1_snake"))
	var stub = GroundDrive.create(LabSpine.body("s1_tiny"))
	failed += _check(snake.mode == "slither" and stub.mode == "shuffle",
			"spine-only snake slithers and two-joint tiny legs shuffle")
	for p in [snake, stub]:
		var first_position: Vector3 = p.position
		var finite := true
		for f in 3600:
			var input := Drives.input("random", f * DT, 17)
			p.step(DT, input.x, input.y)
			finite = finite and p.is_finite_state()
		failed += _check(finite and p.position.distance_to(first_position) > 0.01,
				"%s: 60 s random drive is finite and moves (distance %.3f m)" % [p.mode, p.distance])
		failed += _check(p.max_pitch <= deg_to_rad(5.0) and p.max_roll <= deg_to_rad(5.0),
				"%s: 60 s pitch/roll remains within 5 degrees" % p.mode)
	failed += _check(snake.max_belly_slip_ratio <= 0.12,
			"slither belly contact slip <= 12%% body length (%.2f%%)" % (100.0 * snake.max_belly_slip_ratio))
	failed += _check(stub.max_foot_slip_ratio <= 0.25,
			"shuffle stance slip <= 25%% short-leg length (%.2f%%)" % (100.0 * stub.max_foot_slip_ratio))
	return failed


static func _check(ok: bool, label: String) -> int:
	print(("PASS  " if ok else "FAIL  ") + label)
	return 0 if ok else 1
