extends TestCase
## The home block (docs/s1/s1-interfaces.md sections 3.5 and 4.3): the M1 pool comes from its base
## files unchanged, the minimal fixture ring passes, each rule refuses the mistake it is for, unknown
## and missing keys are refused with their JSON path (G24), and every point of the block reaches food
## within the starving budget (G3).
##
## Rule 3 is the amended rule of docs/s1/s1-content.md 17.1 (see HomeBlock.MIN_RING_ZONES): the
## spine's eight zones cannot feed the block's corners.

const WorldChecks := preload("res://tests/world_checks.gd")
const HOME := "res://tests/fixtures/world/home_min.json"
const KIT := "res://tests/fixtures/world/kit_min.json"

var species: SpeciesCatalog
var parts: PartCatalog
var layout: PoolLayout
var kit: PlacementKit


func before_each() -> void:
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	kit = PlacementKit.load_from(KIT)


static func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(HOME))


func _problems(change: Callable, p_species: SpeciesCatalog = null) -> PackedStringArray:
	var data := _data()
	change.call(data)
	var sp := p_species if p_species != null else species
	return HomeBlock.from_dict(data, layout, sp, "home_min").validate(sp, kit, parts, 1)


static func _zone(data: Dictionary, id: String) -> Dictionary:
	for z in data.zones:
		if z.id == id:
			return z
	return {}


func test_the_minimal_home_block_has_no_problems() -> void:
	var home := HomeBlock.load_from(HOME, layout, species)
	check_eq(home.validate(species, kit, parts, 1), PackedStringArray(), "the fixture ring")
	check_eq(home.where, "home_min", "messages start with the file's name")
	check_eq(home.shells.size(), layout.rocks.size() + 8, "the M1 rocks, then 8 ring shells")
	check_eq(home.zones.size(), layout.zones.size() + 20, "the M1 zones, then 20 ring zones")
	check_eq(home.sites.size(), species.sites.size(), "the M1 sites; S1's ring has none")
	var ring: Dictionary = home.shells[layout.rocks.size()]
	check_eq([ring.id, ring.x, ring.y, ring.r, ring.fixed, ring.asset], ["sa", 40.65, 16.84, 1.4, false, ""], "a ring shell, asset picked later")
	check_eq(HomeBlock.load_from(HOME, null, null).validate(species, kit, parts, 1), PackedStringArray(), "with no objects given, the base files are loaded")


func test_m1_rocks_zones_sites_and_spawn_come_from_the_base_files_unchanged() -> void:
	var home := HomeBlock.load_from(HOME, layout, species)
	for i in layout.rocks.size():
		var r: Dictionary = layout.rocks[i]
		var s: Dictionary = home.shells[i]
		check_eq([s.id, s.x, s.y, s.r, s.asset, s.yaw_deg, s.scale, s.fixed],
			[r.id, float(r.center.x), float(r.center.y), float(r.radius), r.asset, float(r.yaw_deg), float(r.scale), true], "rock %d" % i)
		check_eq(s.yaw_range, PackedFloat64Array([r.yaw_deg, r.yaw_deg]), "%s keeps its yaw" % r.id)
	for i in layout.zones.size():
		var z: Dictionary = layout.zones[i]
		var h: Dictionary = home.zones[i]
		check_eq([h.id, h.x, h.y, h.radius, h.capacity, h.growth_rate, h.m1],
			[z.id, float(z.center.x), float(z.center.y), float(z.radius), float(z.capacity), float(z.growth_rate), true], "zone %d" % i)
	for i in species.sites.size():
		var s: Dictionary = species.sites[i]
		var h: Dictionary = home.sites[i]
		check_eq([h.id, h.species, h.x, h.y, h.heading, h.territory_zone, h.sizes, h.m1],
			[s.id, s.species, float(s.home.x), float(s.home.y), float(s.heading), str(s.get("territory_zone", "")), [1, 2] as Array[int], true],
			"site %d" % i)
	check_eq(home.spawn, PackedFloat64Array([0.0, 9.0]), "the spawn")
	check_eq(home.spawn_heading, layout.spawn_heading, "its heading")
	var carrion := []
	for p: Vector2 in layout.carrion.initial:
		carrion.append([float(p.x), float(p.y)])
	check_eq(home.carrion_initial, carrion, "the starting carrion")
	check_eq(home.carrion_initial.size(), 3, "three pieces")


func test_each_home_rule_has_a_failing_variant() -> void:
	var lurker_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	lurker_data.species["lurker"] = lurker_data.species.ambush_hunter.duplicate(true)
	var with_lurker := SpeciesCatalog.from_dict(lurker_data)
	var cases := [
		# Rule 1: ids. A repeat within a ring list is a reading problem; an M1 id cannot match the
		# local-id pattern, so the ring never redefines one.
		[func(d: Dictionary) -> void: d.zones[1].id = "e", "home_min.zones[1].id: 'e' is repeated", 1],
		[func(d: Dictionary) -> void: d.shells[0].id = "rock_01", "home_min.shells[0].id: 'rock_01' is repeated, reserved", 1],
		# Rule 2: ring shells.
		[func(d: Dictionary) -> void: d.shells.resize(5), "home_min: rule 2: the ring has 5 shells; it needs 6 to 8", 1],
		[func(d: Dictionary) -> void: d.shells.append({"id": "si", "center": [0.0, -42.0], "radius": 1.0, "yaw_deg": [0.0, 360.0], "at_second_size": "keep"}),
			"home_min: rule 2: the ring has 9 shells", 1],
		[func(d: Dictionary) -> void: d.shells[1].center = [10.0, 35.5], "home_min: rule 2: shell 'sb' at (10.0, 35.5) reaches inside seam_inner_r", 1],
		[func(d: Dictionary) -> void: d.shells[0].center = [59.0, 16.84], "home_min: rule 2: shell 'sa' at (59.0, 16.84) comes within 4.0 bu", 1],
		[func(d: Dictionary) -> void: d.shells[0].radius = 1.6, "home_min: rule 2: shell 'sa' radius 1.6 fits []", 1],
		[func(d: Dictionary) -> void: d.shells[1].center = [40.65, 18.5], "home_min: rule 2: shells 'sa' and 'sb' overlap", 1],
		[func(d: Dictionary) -> void: d.shells[0].yaw_deg = [90.0, 10.0], "home_min: rule 2: shell 'sa' yaw_deg", 1],
		# Rule 3 (amended): ring zones.
		[func(d: Dictionary) -> void: d.zones.resize(15), "home_min: rule 3: the ring has 15 zones; it needs 16 to 24", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").radius = 7.0, "home_min: rule 3: zone 'e' needs 4.0 <= radius <= 6.0", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").capacity = 30.0, "home_min: rule 3: zone 'e' needs", 1],
		[func(d: Dictionary) -> void: _zone(d, "ine").center = [24.0, -26.0], "home_min: rule 3: zone 'ine' at (24.0, -26.0) reaches inside seam_inner_r", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").center = [58.0, 0.0], "home_min: rule 3: zone 'e' at (58.0, 0.0) comes within 1.0 bu", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").center = [50.0, 16.5], "home_min: rule 3: zones 'e' and 'ese' are", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").center = [48.3, 16.84], "home_min: rule 3: zone 'e' is 0.25 bu from shell 'sa'", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").growth_rate = 0.25, "home_min: rule 3: zone 'e' yields 1.200 a second", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").at_second_size = "grow", "home_min: rule 3: zone 'e' at_second_size 'grow'", 1],
		# Rule 4: ring sites.
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -40.0], "heading": 0.0, "sizes": [1]}],
			"home_min: rule 4: site 'a' home (0.0, -40.0) lies inside r 44.0", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "kraken", "home": [0.0, -50.0], "heading": 0.0, "sizes": [2]}],
			"home_min: rule 4: site 'a' names unknown species 'kraken'", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -50.0], "heading": 0.0, "sizes": [3]}],
			"home_min: rule 4: site 'a': sizes [3] must be some of [1, 2]", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "lurker", "home": [0.0, -50.0], "heading": 0.0, "sizes": [2]}],
			"home_min: rule 4: site 'a': 'lurker' is not an S1 species", 1, with_lurker],
		# Rule 5: reach discs inside the block, holding the home, clear of every home shell.
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -55.0], "heading": 0.0, "sizes": [1]}],
			"home_min: rule 5: site 'a' reach disc at (0.0, -55.0), r 9.00, comes within 0.85 bu of the block's edge", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "rammer", "home": [0.0, -50.0], "heading": 0.0, "territory_zone": "q", "sizes": [1]}],
			"home_min: rule 5: site 'a' territory_zone 'q' is not a zone of the block", 1],
		[func(d: Dictionary) -> void: d.shells[0].center = [36.4, 14.0], "home_min: rule 5: Rule 9 (", 1],
	]
	check(_problems(func(_d: Dictionary) -> void: pass).is_empty(), "the base passes")
	for i in cases.size():
		var c: Array = cases[i]
		var problems := _problems(c[0], c[3] if c.size() > 3 else null)
		var found := false
		for p in problems:
			found = found or p.contains(c[1])
		check(found and problems.size() == c[2], "case %d: %d problem(s), one containing '%s': %s" % [i, c[2], c[1], problems])


## Rule 6 holds for the M1 sites (species rule 8 against the checkpoint, unchanged); moved closer, it fails.
func test_rule_6_keeps_every_reach_disc_twelve_metres_from_the_spawn() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	for s in data.sites:
		if s.id == "lair_se":
			s.home = [12.0, 25.0]
	var moved := SpeciesCatalog.from_dict(data)
	var home := HomeBlock.from_dict(_data(), layout, moved, "home_min")
	var problems := home.validate(moved, kit, parts, 1)
	check(problems.size() == 1 and problems[0].begins_with("home_min: rule 6: site 'lair_se' can reach 10.25 bu from the spawn"),
		"one problem, as species rule 8 gives it: %s" % [problems])


## C-4 for the M1 sites: every home lies inside its own reach disc (ambush discs are centred on the
## home; territorial homes lie within their zone, far inside zone + margin + leash).
func test_every_m1_site_home_lies_inside_its_reach_disc() -> void:
	for s in species.sites:
		var disc := species.reach_disc(s, layout)
		var r := species.phenotype(s.species, parts).radius
		var slack: float = float(disc.radius) - Vector2(s.home).distance_to(disc.center) - r
		check(slack >= 0.0, "%s: home inside its disc by %.2f bu" % [s.id, slack])
	var outside := func(d: Dictionary) -> void:
		d.sites = [{"id": "a", "species": "rammer", "home": [0.0, -40.5], "heading": 0.0, "territory_zone": "n", "sizes": [2]}]
	check(_problems(outside).is_empty(), "a site live only at size 2 is not placed at size 1")


## G3: from every open point of the block a starving cell reaches food (the M1 zones and the ring)
## within the budget, walking round the M1 rocks and the ring shells, with no wall.
func test_every_point_of_the_home_block_reaches_food_within_16_3_tm() -> void:
	var budget := WorldChecks.starving_budget(parts)
	check(budget > 16.0 and budget < 16.6, "the budget is 16.3 tm (%.2f)" % budget)
	var home := HomeBlock.load_from(HOME, layout, species)
	var arena := ChunkArena.from_shells(home.circles())
	var bounds := Rect2(-64.0, -64.0, 128.0, 128.0)
	check_eq(WorldChecks.reach_problems(arena, home.zone_list(), bounds, budget), PackedStringArray(), "every point")
	var worst := WorldChecks.worst_reach(arena, home.zone_list(), bounds)
	print("test-home-reach: worst %.1f tm at %s (budget %.2f)" % [worst.worst, worst.at, budget])


func test_unknown_and_missing_keys_are_refused_with_their_path() -> void:
	var data := _data()
	data["colour"] = "blue"
	data.erase("seam_inner_r")
	data.shells[0]["tint"] = "#FFFFFF"
	data.zones[2].erase("growth_rate")
	data.sites = [{"id": "a", "species": "rammer", "home": [0.0, -50.0], "sizes": [2]}]
	var home := HomeBlock.from_dict(data, layout, species, "home_min")
	check_eq(home.validate(species, kit, parts, 1), PackedStringArray(["home_min.colour: unknown key", "home_min.seam_inner_r: missing",
		"home_min.shells[0].tint: unknown key", "home_min.zones[2].growth_rate: missing", "home_min.sites[0].heading: missing"]),
		"each named by its path; the rules wait for a block that reads")
	var base := _data()
	base.base_layout = "res://game/data/no_pool.json"
	check_eq(HomeBlock.from_dict(base, layout, species, "home_min").load_problems,
		PackedStringArray(["home_min.base_layout: the file 'res://game/data/no_pool.json' does not exist"]), "a base file")
	check_eq(HomeBlock.load_from("res://tests/fixtures/world/no_home.json", layout, species).validate(species, kit, parts, 1),
		PackedStringArray(["no_home.json: missing or not readable JSON"]), "never null")
