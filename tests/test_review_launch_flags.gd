extends TestCase
## Launch inputs are parsed before a scene is chosen. Bad values must not reach a save or sim.


func test_seed_zero_is_valid() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=0"]))
	check_eq(flags.seed_value, 0, "zero seed is usable")
	check(flags.problems.is_empty(), "zero has no warning")


func test_seed_maximum_is_valid() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=4294967295"]))
	check_eq(flags.seed_value, RunFlags.MAX_SEED, "maximum exact JSON seed")


func test_seed_over_maximum_falls_back_with_warning() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=4294967296"]))
	check_eq(flags.seed_value, -1, "invalid seed is not used")
	check_has_error(flags.problems, "--seed needs a whole number")


func test_seed_fraction_falls_back_with_warning() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=1.5"]))
	check_eq(flags.seed_value, -1, "fraction is not rounded")
	check_has_error(flags.problems, "--seed needs a whole number")


func test_seed_very_long_text_falls_back_without_overflow() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=99999999999999999999999999"]))
	check_eq(flags.seed_value, -1, "overlong seed is not parsed")
	check_eq(flags.problems.size(), 1, "one warning")


func test_user_slot_file_is_accepted() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--slot=user://saves/slot_2.json"]))
	check_eq(flags.slot, "user://saves/slot_2.json", "slot file retained")
	check(flags.problems.is_empty(), "no warning")


func test_resource_slot_is_rejected_without_loading_it() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--slot=res://game/data/pool.json"]))
	check_eq(flags.slot, "", "resource is not a save destination")
	check_has_error(flags.problems, "--slot needs a file")


func test_slot_directory_is_rejected() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--slot=user://saves/"]))
	check_eq(flags.slot, "", "a directory is not a slot")
	check_eq(flags.problems.size(), 1, "one warning")


func test_perf_tour_and_tool_args_stay_separate() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--perf-tour", "--phase=play"]))
	check(flags.perf_tour, "tour selected")
	check_eq(flags.other, PackedStringArray(["--phase=play"]), "tool flag passed through")
