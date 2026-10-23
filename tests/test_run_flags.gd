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


func test_the_world_flag_picks_the_mode() -> void:
	check_eq(RunFlags.from_args(PackedStringArray(["--world=pool"])).world, "pool", "pool")
	check_eq(RunFlags.from_args(PackedStringArray(["--world=endless"])).world, "endless", "endless")
	var none := RunFlags.from_args(PackedStringArray())
	check_eq(none.world, "", "no flag: the world file's own mode")
	check(none.problems.is_empty() and none.other.is_empty(), "nothing else reported: %s %s" % [none.problems, none.other])


func test_an_unknown_world_is_a_problem() -> void:
	var flags := RunFlags.from_args(PackedStringArray(["--world=sea"]))
	check_eq(flags.world, "", "the value is not taken")
	check_eq(flags.problems.size(), 1, "one problem: %s" % [flags.problems])
	check(flags.problems.size() == 1 and flags.problems[0].contains("'sea'"), "it names the value: %s" % [flags.problems])
	check(flags.other.is_empty(), "not passed on to a tool: %s" % [flags.other])


func test_the_perf_tour_takes_an_optional_swim_route() -> void:
	var plain := RunFlags.from_args(PackedStringArray(["--perf-tour"]))
	check(plain.perf_tour and plain.perf_route == "", "plain: the M1 tour (%s, '%s')" % [plain.perf_tour, plain.perf_route])
	var swim := RunFlags.from_args(PackedStringArray(["--perf-tour=swim"]))
	check(swim.perf_tour and swim.perf_route == "swim", "=swim: the swim route (%s, '%s')" % [swim.perf_tour, swim.perf_route])
	check(swim.problems.is_empty() and swim.other.is_empty(), "=swim is understood: %s %s" % [swim.problems, swim.other])
	var fly := RunFlags.from_args(PackedStringArray(["--perf-tour=fly"]))
	check(not fly.perf_tour and fly.perf_route == "", "=fly runs no tour (%s, '%s')" % [fly.perf_tour, fly.perf_route])
	check(fly.problems.size() == 1 and fly.problems[0].contains("'fly'"), "=fly is a problem naming the value: %s" % [fly.problems])
