extends TestCase
## The endless world's settings (game/data/world_cell.json, S1): the shipped file passes its checks,
## each rule of docs/s1/s1-interfaces.md section 4.1 refuses the mistake it is for, unknown and
## missing keys are refused with their JSON path (G24), the --world override, the size ladder's
## units, and the cross-file numbers the rings and caps rest on.

## The content files T4 ships. Until they land, the shipped file may name them although they do not
## exist yet; nothing else may be wrong with it.
const T4_CONTENT: PackedStringArray = ["res://game/data/home_b0.json", "res://game/data/tiles/b0",
	"res://game/data/placement_kit.json"]
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
	var problems := config.validate()
	var waiting := PackedStringArray()
	for p in problems:
		var allowed := false
		for path in T4_CONTENT:
			allowed = allowed or (p.contains("'%s' does not exist" % path) and not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)))
		if allowed:
			waiting.append(p)
		else:
			check(false, "unexpected problem: %s" % p)
	check(waiting.size() <= T4_CONTENT.size(), "only T4's missing content may be named: %s" % [waiting])
	check(WorldConfig.from_dict(_base()).validate().is_empty(), "with content that exists, no problems: %s" % [WorldConfig.from_dict(_base()).validate()])
	check_eq(config.mode, "endless", "Joshua plays the endless world (D-4)")
	check_eq(config.gen_version, 1, "generator version")
	check_eq(config.rings.view, 33.9, "view ring")
	check_eq(config.caps.chunks, 36, "chunk cap")
	check_eq(config.arrangement.fixed_rare.tile, Vector2i(2, -1), "the fixed rare tile")
	check_eq(config.arrangement.fixed_rare.kind, "giant_husk", "is the giant husk")
	check_eq(config.content.tiles, {"0": "res://game/data/tiles/b0"}, "band 0 tiles")
	check_eq(config.switches.generated_creatures, true, "tile creatures on")


func test_each_rule_has_a_failing_case() -> void:
	check(WorldConfig.from_dict(_base()).validate().is_empty(), "the base passes")
	# [path, bad value, the problem's prefix]
	var cases := [
		["mode", "lake", "world_cell.mode: 'lake'"],
		["gen_version", 0, "world_cell.gen_version:"],
		["sizes.start", 2, "world_cell.sizes.start:"],
		["sizes.max_in_build", 2, "world_cell.sizes.max_in_build: size 2 needs growth"],
		["sizes.max_in_build", 11, "world_cell.sizes.max_in_build: must be 1 to 10"],
		["units.growth_factor", 1.5, "world_cell.units.growth_factor:"],
		["units.band_factor", 2.5, "world_cell.units.band_factor:"],
		["units.tile_bu", 63.0, "world_cell.units.tile_bu:"],
		["units.chunk_tm", 16.0, "world_cell.units.chunk_tm:"],
		["rings_tm.mirror", 0.0, "world_cell.rings_tm: must rise"],
		["rings_tm.sleep", 40.0, "world_cell.rings_tm: must rise"],
		["rings_tm.sleep", 41.0, "world_cell.rings_tm.sleep:"],
		["rings_tm.unload", 71.0, "world_cell.rings_tm.unload:"],
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
	]
	for c in cases:
		var problems := _problems_after(c[0], c[1])
		check(problems.size() == 1 and problems[0].begins_with(c[2]),
			"%s = %s gives one problem starting '%s': %s" % [c[0], c[1], c[2], problems])


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
