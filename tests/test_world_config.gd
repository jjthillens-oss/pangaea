extends TestCase
## The endless world's settings (game/data/world_cell.json, S1): the shipped file passes its checks,
## each rule of docs/s1/s1-interfaces.md section 4.1 refuses the mistake it is for, unknown and
## missing keys are refused with their JSON path (G24), the --world override, the size ladder's
## units, and the cross-file numbers the rings and caps rest on. S2 (docs/s2/s2-sim.md 3.10 and 4.1,
## docs/s2/s2-build-plan.md 7.3): the growth, second_size and ladder blocks and the new switches,
## each of their rules with a failing case (S2G29), and the size ladder's tm_to_am and k. S3
## (docs/s3/s3-interfaces.md 5.1 and 6.1, s3-build-plan.md BP3-17): band 1's tables, arrangement.bands,
## content.cradle, the new plant looks and the landmark_return switch, each rule with a failing case
## (S3G8), and a size-2 top that keeps band 1's entries without needing them.

## Existing paths that stand in for the content in the rule cases, so a case's one problem is its own.
const PRESENT_CONTENT := {"home": "res://game/data/pool_m1.json", "tiles": {"0": "res://game/data"},
	"kit": "res://game/data/creatures_m1.json"}


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(WorldConfig.DEFAULT_PATH))


## The shipped data with content paths that exist.
func _base() -> Dictionary:
	var data := _shipped()
	data.content = PRESENT_CONTENT.duplicate(true)
	return data


## Sets the value at a dotted path ("rings_tm.sleep") in `data`.
static func _set_at(data: Dictionary, path: String, value: Variant) -> void:
	var keys := path.split(".")
	var d: Dictionary = data
	for i in keys.size() - 1:
		d = d[keys[i]]
	d[keys[-1]] = value


static func _erase_at(data: Dictionary, path: String) -> void:
	var keys := path.split(".")
	var d: Dictionary = data
	for i in keys.size() - 1:
		d = d[keys[i]]
	d.erase(keys[-1])


func _problems_after(path: String, value: Variant) -> PackedStringArray:
	var data := _base()
	_set_at(data, path, value)
	return WorldConfig.from_dict(data).validate()


func test_the_shipped_world_cell_has_no_problems() -> void:
	var config := WorldConfig.load_from()
	check_eq(config.validate(), PackedStringArray(), "the shipped world file, with the content it names")
	check(WorldConfig.from_dict(_base()).validate().is_empty(), "with content that exists, no problems: %s" % [WorldConfig.from_dict(_base()).validate()])
	check_eq(config.mode, "endless", "Joshua plays the endless world (D-4)")
	check_eq(config.gen_version, 1, "generator version")
	check_eq(config.rings.view, 33.9, "view ring")
	check_eq(config.rings.hold, 96.0, "hold ring (B-6)")
	check_eq(config.caps.chunks, 36, "chunk cap")
	check_eq(config.arrangement.fixed_rare.tile, Vector2i(2, -1), "the fixed rare tile")
	check_eq(config.arrangement.fixed_rare.kind, "giant_husk", "is the giant husk")
	check_eq(config.content.tiles, {"0": "res://game/data/tiles/b0"}, "band 0 tiles")
	check_eq(config.switches, {"generated_creatures": true, "growth": true, "lumps": true, "habits": true,
		"landmark_return": true}, "tile creatures, growth, lumps, habits and the landmark return on")
	check_eq(config.max_size_in_build, 2, "S2's top is size 2 (BP-5)")


## The S2 numbers as s2-sim 4.1 and the build plan (BP-4, D-60, D-68) give them.
func test_the_shipped_growth_ladder_and_second_size() -> void:
	var config := WorldConfig.load_from()
	var g := config.growth
	check_eq(g.trigger, "auto", "the sim's default trigger (BP-3: the player's comes through the intent)")
	check_eq(g.rings, PackedFloat64Array([90, 120, 150, 170, 180, 190, 200, 205, 210]), "a ring per size 1 to 9")
	check_eq([g.drain_floor_share, g.drain_ring_seconds], [0.8, 190.0], "the drain (190 s a ring: S2G16's first-growth floor, DECISIONS)")
	check_eq([g.calm_ticks, g.quiet_ticks, g.chase_window_ticks], [90, 120, 60], "the calm window, as ticks")
	check(g.calm_ticks is int and g.beat_loads_per_tick is int and g.prefetch_per_tick is int and g.remnants.cap is int
		and g.top_payout_points is int, "counts are ints")
	check_eq([g.chase_close_tm, g.chase_track_tm, g.wedge_tm], [1.0, 15.0, 2.0], "the chase and wedge lengths")
	check_eq([g.showcase_s, g.blocked_hint_s, g.shelter_s, g.beat_s, g.beat_loads_per_tick], [20.0, 3.0, 5.0, 2.0, 2], "times and beat loads")
	check_eq([g.death_meter_share, g.respawn_floor_share, g.respawn_cap_over_death, g.top_payout_points], [0.25, 0.8, 20.0, 10],
		"death, respawn and the top payout")
	check_eq([g.prefetch_share, g.prefetch_per_tick], [0.9, 1], "the prefetch (BP-4)")
	check_eq(g.lumps, {"threat_kill": 0.15, "place": 0.10, "landmark_at_top": 0.10, "food_look": 0.05, "kill_carcass_share": 0.25}, "lumps")
	check_eq(g.remnants, {"cap": 12, "min_rel": 0.45, "morsel_min_rel": 0.25, "life_s": 30.0, "morsel_max_radius_tm": 0.225,
		"morsel_rot_s": 120.0}, "remnants")
	check_eq(g.discovery, {"place_find_tm": 10.0, "landmark_find_tm": 6.0}, "discovery")
	check_eq(config.second_size, {"zone_thin_share": 0.4}, "a thin zone keeps 0.4 of its capacity (D-60)")
	check_eq(config.ladder.labels.size(), WorldConfig.MAX_SIZE, "a label per size")
	check_eq([config.ladder.labels[0], config.ladder.labels[1]], ["about 20 µm", "about 32 µm"], "sizes 1 and 2")
	check_eq(config.ladder.food_looks, [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball", "meat": "carrion"}],
		"plankton at size 1, the algae ball at size 2")


func test_each_rule_has_a_failing_case() -> void:
	check(WorldConfig.from_dict(_base()).validate().is_empty(), "the base passes")
	# [path, bad value, the problem's prefix]
	var cases := [
		["mode", "lake", "world_cell.mode: 'lake'"],
		["gen_version", 0, "world_cell.gen_version:"],
		["sizes.start", 2, "world_cell.sizes.start:"],
		["sizes.max_in_build", 5, "world_cell.sizes.max_in_build: size 5 is above this build's top (4"],
		["sizes.max_in_build", 11, "world_cell.sizes.max_in_build: must be 1 to 10"],
		["units.growth_factor", 1.5, "world_cell.units.growth_factor:"],
		["units.band_factor", 2.5, "world_cell.units.band_factor:"],
		["units.tile_bu", 63.0, "world_cell.units.tile_bu:"],
		["units.chunk_tm", 16.0, "world_cell.units.chunk_tm:"],
		["rings_tm.mirror", 0.0, "world_cell.rings_tm: must rise"],
		["rings_tm.sleep", 40.0, "world_cell.rings_tm: must rise"],
		["rings_tm.sleep", 41.0, "world_cell.rings_tm.sleep:"],
		["rings_tm.unload", 71.0, "world_cell.rings_tm.unload:"],
		["rings_tm.hold", 72.0, "world_cell.rings_tm: must rise"],
		["rings_tm.hold", 120.0, "world_cell.origin.local_bound_tm: rebase_beyond_tm + max(unload, hold) + chunk_tm x sqrt 2 (261.25)"],
		["caps.awake", 0, "world_cell.caps.awake:"],
		["caps.sleepers", 11, "world_cell.caps.sleepers:"],
		["caps.food_per_zone", 0, "world_cell.caps.food_per_zone:"],
		["caps.food_per_zone", 121, "world_cell.caps.food_per_zone:"],
		["caps.view_set_chunks", 8, "world_cell.caps.view_set_chunks:"],
		["caps.chunks", 31, "world_cell.caps.chunks:"],
		["caps.loads_per_tick", 0, "world_cell.caps.loads_per_tick:"],
		["caps.awake", 1.5, "world_cell.caps.awake: must be a whole number"],
		["origin.rebase_step_tm", 16.0, "world_cell.origin.rebase_step_tm:"],
		["origin.rebase_beyond_tm", 150.0, "world_cell.origin.local_bound_tm:"],
		["arrangement.region_period_tiles", 0, "world_cell.arrangement.region_period_tiles:"],
		["arrangement.region_order", ["drift", "drift", "reef"], "world_cell.arrangement.region_order:"],
		["arrangement.region_thresholds", [0.6, 0.4], "world_cell.arrangement.region_thresholds:"],
		["arrangement.region_thresholds", [0.0, 0.5], "world_cell.arrangement.region_thresholds:"],
		["arrangement.max_drift_run", 3, "world_cell.arrangement.max_drift_run:"],
		["arrangement.landmark_cell_tiles", 3, "world_cell.arrangement.landmark_cell_tiles:"],
		["arrangement.rare_block_tiles", 5, "world_cell.arrangement.rare_block_tiles:"],
		["arrangement.rare_block_first_tile", -2, "world_cell.arrangement.rare_block_first_tile:"],
		["arrangement.home_tiles", [0, 1], "world_cell.arrangement.home_tiles:"],
		["arrangement.fixed_rare.tile", [-1, 0], "world_cell.arrangement.fixed_rare.tile: (-1, 0) is a home tile"],
		["arrangement.fixed_rare.tile", [4, 0], "world_cell.arrangement.fixed_rare.tile: (4, 0) is outside block (0, 0)"],
		["arrangement.fixed_rare.tile", [2.5, -1], "world_cell.arrangement.fixed_rare.tile: must be two whole numbers"],
		["content.home", "game/data/pool_m1.json", "world_cell.content.home:"],
		["content.kit", "res://game/data/no_such_kit.json", "world_cell.content.kit:"],
		["content.tiles", {"0": "res://game/data/tiles/nowhere"}, "world_cell.content.tiles.0:"],
		["content.tiles", {}, "world_cell.content.tiles.0: missing"],
		["switches.generated_creatures", "yes", "world_cell.switches.generated_creatures:"],
		["switches.growth", "yes", "world_cell.switches.growth: must be true or false"],
		["switches.lumps", 1, "world_cell.switches.lumps: must be true or false"],
		["switches.habits", null, "world_cell.switches.habits: must be true or false"],
		["switches.landmark_return", "on", "world_cell.switches.landmark_return: must be true or false"],
		# Rule 10: the growth block.
		["growth.trigger", "sometimes", "world_cell.growth.trigger: rule 10: 'sometimes'"],
		["growth.trigger", 1, "world_cell.growth.trigger: must be text"],
		["growth.rings", [90, 120], "world_cell.growth.rings: rule 10"],
		["growth.rings", [90, 0, 150, 170, 180, 190, 200, 205, 210], "world_cell.growth.rings: rule 10"],
		["growth.rings", [90, "a", 150, 170, 180, 190, 200, 205, 210], "world_cell.growth.rings.1: must be a number"],
		["growth.rings", 90, "world_cell.growth.rings: must be a list"],
		["growth.drain_floor_share", 0.0, "world_cell.growth.drain_floor_share: rule 10: a share"],
		["growth.death_meter_share", 1.25, "world_cell.growth.death_meter_share: rule 10: a share"],
		["growth.respawn_floor_share", -0.5, "world_cell.growth.respawn_floor_share: rule 10: a share"],
		["growth.prefetch_share", 0.0, "world_cell.growth.prefetch_share: rule 10: a share"],
		["growth.prefetch_share", 1.01, "world_cell.growth.prefetch_share: rule 10: a share"],
		["growth.lumps.food_look", 0.0, "world_cell.growth.lumps.food_look: rule 10: a share"],
		["growth.lumps.kill_carcass_share", 2.0, "world_cell.growth.lumps.kill_carcass_share: rule 10: a share"],
		["growth.prefetch_per_tick", 0, "world_cell.growth.prefetch_per_tick: rule 10: must be 1 or more"],
		["growth.prefetch_per_tick", 1.5, "world_cell.growth.prefetch_per_tick: must be a whole number"],
		["growth.calm_ticks", 0, "world_cell.growth.calm_ticks: rule 10: must be 1 or more"],
		["growth.beat_loads_per_tick", 0, "world_cell.growth.beat_loads_per_tick: rule 10: must be 1 or more"],
		["growth.remnants.cap", 0, "world_cell.growth.remnants.cap: rule 10: must be 1 or more"],
		["growth.remnants.cap", 2.5, "world_cell.growth.remnants.cap: must be a whole number"],
		["growth.quiet_ticks", 60, "world_cell.growth.chase_window_ticks: rule 10: must be below quiet_ticks"],
		["growth.chase_window_ticks", 120, "world_cell.growth.chase_window_ticks: rule 10: must be below quiet_ticks"],
		["growth.drain_ring_seconds", 0.0, "world_cell.growth.drain_ring_seconds: rule 10: must be above 0"],
		["growth.wedge_tm", 0.0, "world_cell.growth.wedge_tm: rule 10: must be above 0"],
		["growth.chase_track_tm", -1.0, "world_cell.growth.chase_track_tm: rule 10: must be above 0"],
		["growth.beat_s", 0.0, "world_cell.growth.beat_s: rule 10: must be above 0"],
		["growth.remnants.morsel_rot_s", 0.0, "world_cell.growth.remnants.morsel_rot_s: rule 10: must be above 0"],
		["growth.discovery.landmark_find_tm", 0.0, "world_cell.growth.discovery.landmark_find_tm: rule 10: must be above 0"],
		["growth.respawn_cap_over_death", -1.0, "world_cell.growth.respawn_cap_over_death: rule 10: must be 0 or more"],
		["growth.top_payout_points", -1, "world_cell.growth.top_payout_points: rule 10: must be 0 or more"],
		["growth.top_payout_points", 0.5, "world_cell.growth.top_payout_points: must be a whole number"],
		# D-68: the conversion thresholds are the ladder's.
		["growth.remnants.min_rel", 0.5, "world_cell.growth.remnants.min_rel: rule 10: must be 0.45"],
		["growth.remnants.morsel_min_rel", 0.2, "world_cell.growth.remnants.morsel_min_rel: rule 10: must be 0.25"],
		# Rule 11: the second size (D-60).
		["second_size.zone_thin_share", 0.0, "world_cell.second_size.zone_thin_share: rule 11"],
		["second_size.zone_thin_share", 1.5, "world_cell.second_size.zone_thin_share: rule 11"],
		# Rule 12: the ladder.
		["ladder.labels", ["a", "b", "c", "d", "e", "f", "g", "h", "i"], "world_cell.ladder.labels: rule 12"],
		["ladder.labels", ["a", "b", "c", "d", "", "f", "g", "h", "i", "j"], "world_cell.ladder.labels: rule 12"],
		["ladder.labels", ["a", "b", "c", "d", 5, "f", "g", "h", "i", "j"], "world_cell.ladder.labels.4: must be text"],
		["ladder.food_looks", [{"plant": "plankton", "meat": "carrion"}], "world_cell.ladder.food_looks: rule 12: 1 looks for 2 sizes"],
		["ladder.food_looks", [{"plant": "plankton", "meat": "carrion"}, {"plant": "kelp", "meat": "carrion"}],
			"world_cell.ladder.food_looks[1].plant: rule 12: 'kelp'"],
		["ladder.food_looks", [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball", "meat": "fish"}],
			"world_cell.ladder.food_looks[1].meat: rule 12: 'fish'"],
		["ladder.food_looks", [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball"}],
			"world_cell.ladder.food_looks[1].meat: missing"],
	]
	for c in cases:
		var problems := _problems_after(c[0], c[1])
		check(problems.size() == 1 and problems[0].begins_with(c[2]),
			"%s = %s gives one problem starting '%s': %s" % [c[0], c[1], c[2], problems])


## The shipped data reaching size 4: band 1's arrangement entry, cradle, tiles and four food looks,
## with content paths that exist (S3: s3-interfaces.md 6.1).
func _band_one() -> Dictionary:
	var data := _base()
	data.sizes.max_in_build = 4
	data.arrangement["bands"] = {"1": {"region_order": ["veil_garden", "warden_flat", "glass_reef"], "fixed_rare_kind": "sunbeam_well"}}
	data.content.tiles["1"] = "res://game/data/tiles/b1"
	data.content["cradle"] = {"1": "res://game/data/cradle_b1.json"}
	data.ladder.food_looks = [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball", "meat": "carrion"},
		{"plant": "glass_flake", "meat": "carrion"}, {"plant": "bead_cluster", "meat": "carrion"}]
	return data


## S3G8: band 1's rules, each with a failing case; a size-2 top keeps band 1's entries (BP3-17).
func test_the_band_one_rules_each_have_a_failing_case() -> void:
	var config := WorldConfig.from_dict(_band_one())
	check_eq(config.validate(), PackedStringArray(), "a size-4 world with band 1's entries passes")
	check_eq(config.cradle_paths, {1: "res://game/data/cradle_b1.json"}, "the cradle by band")
	var top_two := _band_one()
	top_two.sizes.max_in_build = 2
	check_eq(WorldConfig.from_dict(top_two).validate(), PackedStringArray(), "a size-2 top keeps band 1's entries (BP3-17)")
	var cases := [
		["arrangement.bands", {}, "world_cell.arrangement.bands.1: missing (band 1 is reachable)"],
		["arrangement.bands.1.region_order", ["veil_garden", "veil_garden", "glass_reef"], "world_cell.arrangement.bands.1.region_order: must be a permutation"],
		["arrangement.bands.1.region_order", ["drift", "sunlit", "reef"], "world_cell.arrangement.bands.1.region_order: must be a permutation"],
		["arrangement.bands.1.region_order", "veil_garden", "world_cell.arrangement.bands.1.region_order: must be a list"],
		["arrangement.bands.1.fixed_rare_kind", "", "world_cell.arrangement.bands.1.fixed_rare_kind: must name a rare kind"],
		["arrangement.bands.1.colour", "pink", "world_cell.arrangement.bands.1.colour: unknown key"],
		["arrangement.bands.2", {"region_order": [], "fixed_rare_kind": "x"}, "world_cell.arrangement.bands.2: a band must be 1 to 1"],
		["arrangement.bands", [], "world_cell.arrangement.bands: must be an object"],
		["content.cradle", {}, "world_cell.content.cradle.1: missing (band 1 is reachable)"],
		["content.cradle.1", "res://game/data/no_cradle.json", "world_cell.content.cradle.1: the file"],
		["content.cradle.2", "res://game/data/cradle_b1.json", "world_cell.content.cradle.2: a band must be 1 to 1"],
		["content.cradle", "res://game/data/cradle_b1.json", "world_cell.content.cradle: must be an object"],
		["content.tiles.1", "res://game/data/tiles/b9", "world_cell.content.tiles.1: the directory"],
		["sizes.max_in_build", 5, "world_cell.sizes.max_in_build: size 5 is above this build's top (4"],
		["ladder.food_looks", [{"plant": "plankton", "meat": "carrion"}, {"plant": "algae_ball", "meat": "carrion"},
			{"plant": "glass_flake", "meat": "carrion"}], "world_cell.ladder.food_looks: rule 12: 3 looks for 4 sizes"],
	]
	for c in cases:
		var data := _band_one()
		_set_at(data, c[0], c[1])
		var problems := WorldConfig.from_dict(data).validate()
		check(problems.size() == 1 and problems[0].begins_with(c[2]),
			"%s = %s gives one problem starting '%s': %s" % [c[0], c[1], c[2], problems])
	var no_tiles := _band_one()
	no_tiles.content.tiles.erase("1")
	check_eq(WorldConfig.from_dict(no_tiles).validate(), PackedStringArray(["world_cell.content.tiles.1: missing (band 1 is reachable)"]),
		"band 1's tiles are needed at a size-4 top")


## D-146: the band-1 test world reaches size 4 with every band-1 entry, and the band-0 test world
## keeps the landmark return off, so S2's tests at the size-2 top are unchanged (BP3-17).
func test_the_test_worlds_read_and_pass() -> void:
	var b1 := WorldConfig.load_from("res://tests/fixtures/world/world_b1_min.json")
	check_eq(b1.validate(), PackedStringArray(), "world_b1_min.json")
	check_eq(b1.max_size_in_build, 4, "it reaches size 4")
	check_eq(b1.content.tiles.keys().size(), 2, "tiles for bands 0 and 1")
	check_eq(b1.switches.landmark_return, true, "the landmark return on")
	var b0 := WorldConfig.load_from("res://tests/fixtures/world/world_min.json")
	check_eq(b0.validate(), PackedStringArray(), "world_min.json")
	check_eq(b0.switches.landmark_return, false, "the landmark return off in the size-2 test world")
	check_eq(b0.cradle_paths, {}, "no cradle")


func test_the_band_tables_and_arrangement_of() -> void:
	check_eq(WorldConfig.regions_of(0), PackedStringArray(["drift", "sunlit", "reef"]), "band 0's regions")
	check_eq(WorldConfig.regions_of(1), PackedStringArray(["veil_garden", "warden_flat", "glass_reef"]), "band 1's")
	check_eq(WorldConfig.regions_of(2), PackedStringArray(), "no tables past band 1")
	check_eq(WorldConfig.transit_of(0), "drift", "band 0's transit region")
	check_eq(WorldConfig.transit_of(1), "", "band 1 has none")
	var data := _band_one()
	data.arrangement.bands["1"].region_order = ["glass_reef", "veil_garden", "warden_flat"]
	var config := WorldConfig.from_dict(data)
	check(config.arrangement_of(0) == config.arrangement, "band 0 is the file's own arrangement")
	var one := config.arrangement_of(1)
	check_eq(one.region_order, PackedStringArray(["glass_reef", "veil_garden", "warden_flat"]), "band 1's order")
	check_eq(one.fixed_rare, {"tile": Vector2i(2, -1), "kind": "sunbeam_well"}, "band 1's fixed rare kind at band 0's tile")
	check_eq(one.region_thresholds, config.arrangement.region_thresholds, "the rest is band 0's")
	check_eq(config.arrangement.region_order, PackedStringArray(["drift", "sunlit", "reef"]), "band 0's order untouched")
	check_eq(config.arrangement_of(2), {}, "none for a band not in the file")


func test_unknown_and_missing_keys_are_refused_with_their_path() -> void:
	var data := _base()
	data["colour"] = "blue"
	data.rings_tm["foo"] = 1.0
	_erase_at(data, "caps.awake")
	_erase_at(data, "arrangement.fixed_rare.kind")
	var problems := WorldConfig.from_dict(data).validate()
	check_eq(problems, PackedStringArray(["world_cell.colour: unknown key", "world_cell.rings_tm.foo: unknown key",
		"world_cell.caps.awake: missing", "world_cell.arrangement.fixed_rare.kind: missing"]),
		"each named by its path, unknown before missing within an object")
	var header := _base()
	header.erase("note")
	header["status"] = "DONE"
	check_eq(WorldConfig.from_dict(header).validate(), PackedStringArray(["world_cell.note: missing",
		"world_cell.status: must be one of PROPOSED, APPROVED"]), "the header")
	var not_object := _base()
	not_object["sizes"] = [1, 1]
	check_eq(WorldConfig.from_dict(not_object).validate(), PackedStringArray(["world_cell.sizes: must be an object"]), "an object")
	check_eq(WorldConfig.from_dict([1]).validate(), PackedStringArray(["world_cell: must be an object"]), "the top")
	var missing := WorldConfig.load_from("res://game/data/no_world.json")
	check_eq(missing.validate(), PackedStringArray(["no_world.json: missing or not readable JSON"]), "never null")


## S2G29: the S2 blocks refuse unknown and missing keys too, each named by its path.
func test_the_s2_blocks_refuse_unknown_and_missing_keys() -> void:
	var data := _base()
	data.growth["ring"] = 90
	_erase_at(data, "growth.lumps.place")
	data.growth.remnants["leave_s"] = 3.0
	_erase_at(data, "growth.discovery.place_find_tm")
	data.second_size["zone_drop_share"] = 0.0
	data.ladder.food_looks[1]["fish"] = "carrion"
	_erase_at(data, "switches.habits")
	check_eq(WorldConfig.from_dict(data).validate(), PackedStringArray(["world_cell.growth.ring: unknown key",
		"world_cell.growth.lumps.place: missing", "world_cell.growth.remnants.leave_s: unknown key",
		"world_cell.growth.discovery.place_find_tm: missing", "world_cell.second_size.zone_drop_share: unknown key",
		"world_cell.ladder.food_looks[1].fish: unknown key", "world_cell.switches.habits: missing"]), "each by its path")
	for key in ["growth", "second_size", "ladder"]:
		var without := _base()
		without.erase(key)
		check_eq(WorldConfig.from_dict(without).validate(), PackedStringArray(["world_cell.%s: missing" % key]), "%s is required" % key)
	var not_object := _base()
	not_object.ladder.food_looks = ["plankton", {"plant": "algae_ball", "meat": "carrion"}]
	check_eq(WorldConfig.from_dict(not_object).validate(), PackedStringArray(["world_cell.ladder.food_looks[0]: must be an object"]),
		"a look is an object")


## tm_to_am is the stream's frame factor and k turns a species' q = 1 lengths into a tile frame's bu
## (D-39): both exact in float64 at the sizes S2 runs.
func test_tm_to_am_is_second_size_and_k_follow_the_ladder() -> void:
	check_eq([WorldConfig.tm_to_am(1), WorldConfig.tm_to_am(2)], [1.0, 1.6], "1 and 1.6 exactly")
	check_eq(WorldConfig.tm_to_am(3), 1.6 * 1.6, "the product, the same on every platform")
	for n in range(1, 11):
		check_near(WorldConfig.tm_to_am(n), pow(WorldConfig.GROWTH_FACTOR, n - 1), 1e-9 * WorldConfig.tm_to_am(n), "size %d is 1.6^(n - 1)" % n)
		# A bu is the same length at both sizes of a band: am per bu is band_factor^band.
		check_near(WorldConfig.tm_to_am(n) * WorldConfig.bu_to_tm(n), pow(WorldConfig.BAND_FACTOR, WorldConfig.band_of(n)), 1e-9,
			"size %d: am per bu" % n)
	check_eq([WorldConfig.is_second_size(1), WorldConfig.is_second_size(2), WorldConfig.is_second_size(3), WorldConfig.is_second_size(4)],
		[false, true, false, true], "the second size of each band")
	check_eq([WorldConfig.k_of(1, 1), WorldConfig.k_of(1, 2), WorldConfig.k_of(2, 2)], [1.0, 1.0, 1.6], "band 0: 1, 1 and 1.6 exactly")
	check_eq([WorldConfig.k_of(3, 3), WorldConfig.k_of(4, 4), WorldConfig.k_of(1, 3), WorldConfig.k_of(2, 4)], [1.0, 1.6, 0.390625, 0.625],
		"band 1: exact powers of 1.6 and 0.625")
	for c in range(1, 5):
		for n in range(c, 7):
			var formula := WorldConfig.tm_to_am(c) / pow(WorldConfig.BAND_FACTOR, WorldConfig.band_of(n))
			check_near(WorldConfig.k_of(c, n), formula, 1e-12, "k(%d, %d) is tm_to_am(c) / 2.56^band(n)" % [c, n])


func test_with_mode_overrides_the_mode_and_refuses_an_unknown_one() -> void:
	var config := WorldConfig.from_dict(_base())
	var pool := config.with_mode("pool")
	check_eq(pool.mode, "pool", "overridden")
	check_eq(config.mode, "endless", "the original is unchanged")
	check(pool.validate().is_empty(), "a pool copy is valid")
	pool.rings.view = 1.0
	pool.arrangement.fixed_rare.kind = "x"
	check_eq(config.rings.view, 33.9, "the copy's rings are its own")
	check_eq(config.arrangement.fixed_rare.kind, "giant_husk", "and so is its arrangement")
	check_eq(config.with_mode("").mode, "endless", "no flag keeps the file's mode")
	var lake := config.with_mode("lake")
	var problems := lake.validate()
	check(problems.size() == 1 and problems[0].contains("'lake'"), "an unknown mode is one problem naming it: %s" % [problems])
	check(config.validate().is_empty(), "and leaves the original alone")


func test_bu_to_tm_and_band_of_follow_the_size_ladder() -> void:
	check_eq(WorldConfig.bu_to_tm(1), 1.0, "size 1")
	check_eq(WorldConfig.bu_to_tm(2), 0.625, "size 2: the same reef, 1.6 times smaller")
	check_eq(WorldConfig.bu_to_tm(3), 1.0, "size 3")
	check_eq(WorldConfig.bu_to_tm(10), 0.625, "size 10")
	for n in range(1, 11):
		var formula := pow(WorldConfig.BAND_FACTOR, WorldConfig.band_of(n)) / pow(WorldConfig.GROWTH_FACTOR, n - 1)
		check_near(WorldConfig.bu_to_tm(n), formula, 1e-12, "size %d is the plan's formula" % n)
	check_eq([WorldConfig.band_of(1), WorldConfig.band_of(2), WorldConfig.band_of(3), WorldConfig.band_of(10)], [0, 0, 1, 4], "bands")


func test_the_view_ring_covers_the_zoom_max_footprint_plus_look_ahead() -> void:
	var config := WorldConfig.load_from()
	var layout := PoolLayout.load_from()
	var species := SpeciesCatalog.load_from()
	var quad := ViewFootprint.corners(Vector2.ZERO, layout.camera, float(layout.camera.zoom_max), float(species.fairness.spawn_view_aspect))
	var far := 0.0
	for p in quad:
		far = maxf(far, p.length())
	check_near(far, 31.42, 0.01, "the zoom-max footprint's far corner")
	check_near(float(config.rings.view), far + float(layout.camera.look_ahead_max), 0.05, "the view ring is that plus the look-ahead")


## A chunk unloads only beyond the unload ring, so a 72 tm disc's chunks plus the four a sleeper's
## reach disc may hold must fit the chunk cap.
func test_a_72_tm_disc_touches_at_most_caps_chunks_minus_4() -> void:
	var config := WorldConfig.load_from()
	var c := float(config.chunk_tm)
	var r := float(config.rings.unload)
	var worst := 0
	# The count is symmetric about the chunk's centre lines, so a quarter of the chunk covers it.
	for i in 65:
		for j in 65:
			var p := Vector2(i * 0.25, j * 0.25)
			var n := 0
			for cy in range(floori((p.y - r) / c), floori((p.y + r) / c) + 1):
				for cx in range(floori((p.x - r) / c), floori((p.x + r) / c) + 1):
					var dx := maxf(maxf(cx * c - p.x, p.x - (cx + 1) * c), 0.0)
					var dy := maxf(maxf(cy * c - p.y, p.y - (cy + 1) * c), 0.0)
					if dx * dx + dy * dy <= r * r:
						n += 1
			worst = maxi(worst, n)
	check_eq(worst, 32, "the worst cell position touches 32 chunks")
	check(worst <= int(config.caps.chunks) - 4, "within caps.chunks - 4")
