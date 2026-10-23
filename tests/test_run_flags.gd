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
	check(not flags.creature, "the title, not the creature stage")


func test_creature_opens_the_creature_stage_preview() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--creature"]))
	check(flags.creature, "creature stage asked for")
	check(flags.other.is_empty() and flags.problems.is_empty(), "nothing left over: %s %s" % [flags.other, flags.problems])


func test_unusable_flags_are_reported_and_ignored() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--seed=-3", "--seed=abc", "--slot=res://game/data/x.json", "--slot="]))
	check_eq(flags.seed_value, -1, "bad seeds ignored")
	check_eq(flags.slot, "", "a slot inside the game files is refused")
	check_eq(flags.problems.size(), 4, "each one explained: %s" % [flags.problems])


func test_seeds_beyond_the_random_range_are_refused_before_they_reach_a_save() -> void:
	# A save keeps numbers as doubles, so 2^53 + 1 would continue as another world; the 20-digit
	# seed does not even fit a whole number.
	var args := PackedStringArray(["--seed=4294967296", "--seed=9007199254740993", "--seed=99999999999999999999"])
	var flags := RunFlags.from_args(args)
	check_eq(flags.seed_value, -1, "all refused")
	check_eq(flags.problems.size(), 3, "each one explained: %s" % [flags.problems])
	var largest := RunFlags.from_args(PackedStringArray(["--seed=4294967295"]))
	check_eq(largest.seed_value, 4294967295, "the largest random seed is fine")


func test_slots_that_do_not_name_a_file_are_refused() -> void:
	for path in ["uid://abc", "foo://x", "saves:/x", "user:/smoke/x.json", "user://", "user://saves/", "/"]:
		var flags := RunFlags.from_args(PackedStringArray(["--slot=" + path]))
		check(flags.slot == "" and flags.problems.size() == 1, "'%s' refused: slot '%s', %s" % [path, flags.slot, flags.problems])
	for path in ["user://x.json", "/tmp/pangaea/slot.json", "C:\\Users\\me\\slot.json", "D:/saves/slot.json"]:
		var flags := RunFlags.from_args(PackedStringArray(["--slot=" + path]))
		check(flags.slot == path and flags.problems.is_empty(), "'%s' accepted: %s" % [path, flags.problems])
