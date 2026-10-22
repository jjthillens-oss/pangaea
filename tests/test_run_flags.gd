extends TestCase


func test_launch_flags_are_read_after_the_double_dash() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=4242", "--slot=user://smoke/slot_1.json", "--perf-tour", "--phase=found"]))
	check_eq(flags.seed_value, 4242, "seed")
	check_eq(flags.slot, "user://smoke/slot_1.json", "slot")
	check(flags.perf_tour, "perf tour")
	check_eq(flags.other, PackedStringArray(["--phase=found"]), "other flags kept for their tools")
	check(flags.problems.is_empty(), "no problems: %s" % [flags.problems])


func test_no_flags_mean_defaults() -> void:
	var flags := RunFlags.from_args(PackedStringArray())
	check_eq(flags.seed_value, -1, "no seed")
	check_eq(flags.slot, "", "default slot")
	check(not flags.perf_tour, "no tour")


func test_unusable_flags_are_reported_and_ignored() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=-3", "--seed=abc", "--slot=res://game/data/x.json", "--slot="]))
	check_eq(flags.seed_value, -1, "bad seeds ignored")
	check_eq(flags.slot, "", "a slot inside the game files is refused")
	check_eq(flags.problems.size(), 4, "each one explained: %s" % [flags.problems])
