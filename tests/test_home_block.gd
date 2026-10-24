extends TestCase
## The home block (docs/s1/s1-interfaces.md sections 3.5 and 4.3): the M1 pool comes from its base
## files unchanged, the minimal fixture ring passes, each rule refuses the mistake it is for, unknown
## and missing keys are refused with their JSON path (G24), and every point of the block reaches food
## within the starving budget (G3).
##
## Rule 3 is the amended rule of docs/s1/s1-content.md 17.1 (see HomeBlock.MIN_RING_ZONES): the
## spine's eight zones cannot feed the block's corners.
##
## S2 (T3.4; docs/s2/s2-sim.md 3.10, D-37, D-38, BP-11): the file names the M1 sites live at size 2
## and what the M1 zones do there; ring sites may have two posts, checked at size 2 as tiles are
## (WorldChecks.s2_species gives the Lurker and the elder rammer until T1.7 ships them).

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
	lurker_data.species.lurker["entry_size"] = 2
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
		[func(d: Dictionary) -> void: _zone(d, "e").center = [48.3, 16.84], "home_min: rule 3: Zone 'e' is 0.25 bu from collider 'sa'; it keeps 0.7.", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").growth_rate = 0.25, "home_min: rule 3: zone 'e' yields 1.200 a second", 1],
		[func(d: Dictionary) -> void: _zone(d, "e").at_second_size = "grow", "home_min: rule 3: zone 'e' at_second_size 'grow'", 1],
		# Rule 4: ring sites.
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -40.0], "heading": 0.0, "sizes": [1]}],
			"home_min: rule 4: site 'a' home (0.0, -40.0) lies inside r 44.0", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "kraken", "home": [0.0, -50.0], "heading": 0.0, "sizes": [2]}],
			"home_min: rule 4: site 'a' names unknown species 'kraken'", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -50.0], "heading": 0.0, "sizes": [3]}],
			"home_min: rule 4: site 'a': sizes [3] must be some of [1, 2]", 1],
		[func(d: Dictionary) -> void: d.sites = [{"id": "a", "species": "lurker", "home": [0.0, -50.0], "heading": 0.0, "sizes": [1]}],
			"home_min: rule 4: site 'a': 'lurker' enters at size 2, so it cannot be live at size 1", 1, with_lurker],
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


## Rule 3's gap (B-2): every home zone, M1 and ring, keeps 0.7 bu from every home collider, ring
## shells and M1 rocks alike. 0.69 bu is refused, 0.70 passes: a ring zone by a ring shell, a ring
## zone by an M1 rock (seam_inner_r lowered to let it come near) and an M1 zone by an M1 rock (the
## layout's z_center moved east, towards rock_01).
func test_rule_3_keeps_every_home_zone_0_7_bu_from_every_collider() -> void:
	var r01: float = layout.rocks[0].radius
	var r14: float = layout.rocks[13].radius
	check_eq([layout.rocks[0].id, layout.rocks[13].id, layout.zones[0].id], ["rock_01", "rock_14", "z_center"], "the pieces used")
	for gap in [0.69, 0.70]:
		var label := "%.2f bu" % gap
		var by_ring_shell := _problems(func(d: Dictionary) -> void: _zone(d, "e").center = [40.65 + 1.4 + 6.0 + gap, 16.84])
		var diagonal: float = (5.0 + r14 + gap) / sqrt(2.0)
		var by_rock := _problems(func(d: Dictionary) -> void:
			d.seam_inner_r = 30.0
			_zone(d, "ise").center = [24.0 + diagonal, 24.0 + diagonal])
		var moved := PoolLayout.load_from()
		moved.zones[0].center = Vector2(12.0 - r01 - 5.0 - gap, 0.0)
		var m1_zone := HomeBlock.from_dict(_data(), moved, species, "home_min").validate(species, kit, parts, 1)
		if gap < 0.7:
			check_eq(by_ring_shell, PackedStringArray(["home_min: rule 3: Zone 'e' is 0.69 bu from collider 'sa'; it keeps 0.7."]), "%s: a ring zone by a ring shell" % label)
			check_eq(by_rock, PackedStringArray(["home_min: rule 3: Zone 'ise' is 0.69 bu from collider 'rock_14'; it keeps 0.7."]), "%s: a ring zone by an M1 rock" % label)
			check_eq(m1_zone, PackedStringArray(["home_min: rule 3: Zone 'z_center' is 0.69 bu from collider 'rock_01'; it keeps 0.7."]), "%s: an M1 zone by an M1 rock" % label)
		else:
			check_eq(by_ring_shell, PackedStringArray(), "%s: a ring zone by a ring shell passes" % label)
			check_eq(by_rock, PackedStringArray(), "%s: a ring zone by an M1 rock passes" % label)
			check_eq(m1_zone, PackedStringArray(), "%s: an M1 zone by an M1 rock passes" % label)


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


# --- S2: the second size (T3.4) ---

## The fixture with a ring Lurker (posts 7 bu apart) and a ring elder rammer guarding two added zones
## 12 bu apart, both live at size 2 only, placed where every rule passes at both sizes.
static func _two_post(d: Dictionary) -> void:
	d.zones.append({"id": "ea", "center": [34.0, -44.0], "radius": 4.0, "capacity": 16.0, "growth_rate": 0.05, "at_second_size": "keep"})
	d.zones.append({"id": "eb", "center": [46.0, -44.0], "radius": 4.0, "capacity": 16.0, "growth_rate": 0.05, "at_second_size": "keep"})
	d.sites = [{"id": "re", "species": "elder_rammer", "home": [34.0, -44.0], "heading": 0.0, "territory_zone": "ea", "sizes": [2],
			"post_b": {"home": [46.0, -44.0], "heading": 3.1416, "territory_zone": "eb"}},
		{"id": "rl", "species": "lurker", "home": [-43.5, -44.0], "heading": 0.0, "sizes": [2],
			"post_b": {"home": [-36.5, -44.0], "heading": 3.1416}}]


## The problems at `size` of the two-post fixture changed by `change`, with the S2 species.
func _s2_problems(change: Callable, size := 2, p_species: SpeciesCatalog = null) -> PackedStringArray:
	var data := _data()
	_two_post(data)
	change.call(data)
	var sp := p_species if p_species != null else WorldChecks.s2_species()
	return HomeBlock.from_dict(data, layout, sp, "home_min").validate(sp, kit, parts, size)


static func _site(d: Dictionary, id: String) -> Dictionary:
	for s in d.sites:
		if s.id == id:
			return s
	return {}


## Moves the fixture's ring shell sf (r 1.3) to (x, y), marked `second` at size 2.
static func _move_sf(d: Dictionary, x: float, y: float, second := "keep") -> void:
	for s in d.shells:
		if s.id == "sf":
			s.center = [x, y]
			s.at_second_size = second


## D-37: the M1 sites the file lists are live at sizes 1 and 2, the rest at 1 only; the M1 zones take
## m1_zones_at_second_size; the ring keeps its own. The fixture lists every M1 site and keeps (S1's
## world); the shipped values are one ambush, two rammers and "thin".
func test_m1_second_size_sites_and_zones_come_from_the_file() -> void:
	var data := _data()
	data.m1_second_size_sites = ["lair_s", "terr_nw", "terr_ne"]
	data.m1_zones_at_second_size = "thin"
	var home := HomeBlock.from_dict(data, layout, species, "home_min")
	for s in home.sites:
		var want: Array[int] = []
		want.assign([1, 2] if s.id in ["lair_s", "terr_nw", "terr_ne"] else [1])
		check_eq(s.sizes, want, "M1 site %s" % s.id)
	for z in home.zones:
		check_eq(z.at_second_size, "thin" if z.m1 else _zone(data, z.id).at_second_size, "zone %s" % z.id)
	for n in [1, 2]:
		check_eq(home.validate(WorldChecks.s2_species(), kit, parts, n), PackedStringArray(), "valid at size %d" % n)
	var fixture := HomeBlock.from_dict(_data(), layout, species, "home_min")
	check(fixture.sites.all(func(s: Dictionary) -> bool: return s.sizes == [1, 2]), "the fixture: every M1 site at both sizes")
	check(fixture.zones.filter(func(z: Dictionary) -> bool: return z.m1).all(func(z: Dictionary) -> bool: return z.at_second_size == "keep"),
		"the fixture: the M1 zones keep")


func test_the_d37_keys_are_checked() -> void:
	var cases := [
		[func(d: Dictionary) -> void: d.m1_second_size_sites = ["lair_s", "kraken"],
			"home_min: rule 1: m1_second_size_sites names 'kraken', which is not an M1 site or is repeated"],
		[func(d: Dictionary) -> void: d.m1_second_size_sites = ["lair_s", "lair_s"],
			"home_min: rule 1: m1_second_size_sites names 'lair_s', which is not an M1 site or is repeated"],
		[func(d: Dictionary) -> void: d.m1_zones_at_second_size = "drop",
			"home_min: rule 3: m1_zones_at_second_size 'drop' is not one of keep, thin"],
		[func(d: Dictionary) -> void: d.erase("m1_zones_at_second_size"), "home_min.m1_zones_at_second_size: missing"],
		[func(d: Dictionary) -> void: d.m1_second_size_sites = "lair_s", "home_min.m1_second_size_sites"],
		[func(d: Dictionary) -> void: d.m1_second_size_sites = ["lair_s", 3], "home_min.m1_second_size_sites.1"],
	]
	for i in cases.size():
		var problems := _problems(cases[i][0])
		check(problems.size() == 1 and problems[0].begins_with(cases[i][1]), "case %d: one problem '%s': %s" % [i, cases[i][1], problems])


## The fixture block passes at size 2 with the S2 species: its M1 sites are rivals and prey there,
## so rule 6 does not bind them (Relationships.can_attack_player), and their discs, k 1, pass rule 5 in
## size-2 bu. With the two ring two-post sites it passes at both sizes.
func test_the_block_passes_at_size_2_with_and_without_two_post_sites() -> void:
	var s2 := WorldChecks.s2_species()
	var home := HomeBlock.from_dict(_data(), layout, s2, "home_min")
	check_eq(home.validate(s2, kit, parts, 2), PackedStringArray(), "the fixture at size 2")
	for n in [1, 2]:
		check_eq(_s2_problems(func(_d: Dictionary) -> void: pass, n), PackedStringArray(), "with a Lurker and an elder rammer, size %d" % n)
	var data := _data()
	_two_post(data)
	var two := HomeBlock.from_dict(data, layout, s2, "home_min")
	var rl: Dictionary = two.sites.filter(func(s: Dictionary) -> bool: return s.id == "rl")[0]
	check_eq([rl.post_b.home, rl.post_b.heading, rl.post_b.territory_zone], [PackedFloat64Array([-36.5, -44.0]), 3.1416, ""], "post_b is read")
	check(two.sites.filter(func(s: Dictionary) -> bool: return s.m1).all(func(s: Dictionary) -> bool: return s.post_b.is_empty()), "M1 sites have none")


## Rule 6 binds a species that can attack the cell at the size: the Lurker near the spawn at size 2 is
## refused (12 tm is 19.2 bu there); an M1 ambush hunter near it at size 2 is a rival and passes, and
## at size 1 (q 1, it attacks) the same place is refused.
func test_rule_6_binds_the_species_that_attack_at_the_size() -> void:
	var near := func(d: Dictionary) -> void:
		var s := _site(d, "rl")
		s.home = [-3.5, -20.0]
		s.post_b.home = [3.5, -20.0]
	var problems := _s2_problems(near)
	check(Array(problems).any(func(p: String) -> bool: return p.begins_with("home_min: rule 6 at size 2: site 'rl' union can reach")),
		"the Lurker near the spawn: %s" % [problems])
	var rival := func(d: Dictionary) -> void:
		d.sites = [{"id": "a", "species": "ambush_hunter", "home": [0.0, -12.0], "heading": 0.0, "sizes": [2]}]
	check_eq(_s2_problems(rival), PackedStringArray(), "an M1 ambush hunter there is a rival at size 2")
	var at_one := _s2_problems(func(d: Dictionary) -> void:
		rival.call(d)
		d.sites[0].sizes = [1], 1)
	check(Array(at_one).any(func(p: String) -> bool: return p.begins_with("home_min: rule 6: site 'a' can reach 11.25 bu from the spawn")),
		"the same place at size 1: %s" % [at_one])


func test_each_two_post_rule_has_a_failing_variant() -> void:
	var no_habit_data: Dictionary = WorldChecks.s2_species_data()
	no_habit_data.species.lurker.erase("habit")
	var wide_data: Dictionary = WorldChecks.s2_species_data()
	wide_data.species.lurker.leash_m = 16.0
	var cases := [
		# BP-11: a kept ring shell across the Lurker's post path; sunk, it is not there at size 2.
		[func(d: Dictionary) -> void: _move_sf(d, -40.0, -44.0),
			"home_min: rule 5 at size 2: site 'rl': the path between its posts passes -1.30 bu from 'sf'; it needs 1.36 (BP-11)"],
		[func(d: Dictionary) -> void: _move_sf(d, -36.5, -46.0), "home_min: rule 5 at size 2: site 'rl' post_b home (-36.5, -44.0) is not clear of 'sf'"],
		[func(d: Dictionary) -> void: _site(d, "rl").post_b.home = [-33.0, -44.0], "home_min: rule 4: site 'rl': its posts are 10.50 bu apart"],
		[func(_d: Dictionary) -> void: pass, "home_min: rule 4: site 'rl': post_b needs a species with a habit; 'lurker' has none",
			SpeciesCatalog.from_dict(no_habit_data)],
		[func(d: Dictionary) -> void: _site(d, "re").post_b.erase("territory_zone"), "home_min: rule 4: site 're': post_b needs a territory_zone"],
		[func(d: Dictionary) -> void: _site(d, "re").post_b.territory_zone = "ea", "home_min: rule 4: site 're': post_b guards zone 'ea' as post a does"],
		[func(d: Dictionary) -> void: _zone(d, "eb").at_second_size = "drop", "home_min: rule 5 at size 2: site 're' post_b.territory_zone 'eb' is dropped at size 2"],
		[func(d: Dictionary) -> void: _site(d, "rl").sizes = [1, 2], "home_min: rule 4: site 'rl': 'lurker' enters at size 2, so it cannot be live at size 1"],
		[func(_d: Dictionary) -> void: pass, "home_min: rule 5 at size 2: site 'rl' union reach disc r", SpeciesCatalog.from_dict(wide_data)],
		[func(d: Dictionary) -> void: _move_sf(d, -40.0, -25.5), "home_min: rule 5 at size 2: Rule 9 (leash band): site 'rl' union: sf lies"],
		[func(d: Dictionary) -> void:
			_site(d, "re").home = [34.0, -52.0]
			_zone(d, "ea").center = [34.0, -52.0], "home_min: rule 5 at size 2: site 're' post a reach disc at (34.0, -52.0), r 12.00"],
	]
	for i in cases.size():
		var c: Array = cases[i]
		var problems := _s2_problems(c[0], 2, c[2] if c.size() > 2 else null)
		check(Array(problems).any(func(p: String) -> bool: return p.begins_with(c[1])), "case %d: a problem beginning '%s': %s" % [i, c[1], problems])
	# Sunk at size 2, the shell across the path is not there.
	check_eq(_s2_problems(func(d: Dictionary) -> void: _move_sf(d, -40.0, -44.0, "sink")), PackedStringArray(),
		"a sunk shell is no collider at size 2")


## Every fairness length is its tm / bu_to_tm(2) in size-2 bu. Rule 5's inset: the elder rammer's post
## a disc (r 12 bu, body 1.0 bu) and leash_band_margin_m 0.1 tm, 0.16 bu, put the edge at |y| 50.84; at
## 50.87 it is refused, at 50.81 it is not. Rule 6: 12 tm is 19.2 bu, so a Lurker whose union keeps
## 15.9 bu from the spawn is refused at size 2.
func test_rules_5_and_6_take_their_lengths_in_size_2_bu() -> void:
	for y in [-50.87, -50.81]:
		var problems := _s2_problems(func(d: Dictionary) -> void:
			_site(d, "re").home = [34.0, y]
			_zone(d, "ea").center = [34.0, y])
		var inset := Array(problems).filter(func(p: String) -> bool: return p.begins_with("home_min: rule 5 at size 2: site 're' post a reach disc"))
		check_eq(inset.size(), 1 if y < -50.84 else 0, "post a at y %s: %s" % [y, inset])
	var problems := _s2_problems(func(d: Dictionary) -> void:
		_site(d, "rl").home = [-3.5, -26.0]
		_site(d, "rl").post_b.home = [3.5, -26.0])
	check(Array(problems).any(func(p: String) -> bool:
		return p.begins_with("home_min: rule 6 at size 2: site 'rl' union can reach 15.90 bu from the spawn; it must stay 19.2 away")),
		"the Lurker 15.9 bu from the spawn: %s" % [problems])


## Each post's own disc is checked, not only the union: a shell on post b's leash circle, well inside
## the union's, is refused for post b.
func test_each_posts_disc_is_checked_as_well_as_the_union() -> void:
	var problems := _s2_problems(func(d: Dictionary) -> void: _move_sf(d, -36.5, -29.6))
	check(Array(problems).any(func(p: String) -> bool: return p.begins_with("home_min: rule 5 at size 2: Rule 9 (leash band): site 'rl' post b: sf lies")),
		"post b's circle: %s" % [problems])
	check(not Array(problems).any(func(p: String) -> bool: return p.contains("site 'rl' union:")), "the union's circle is clear: %s" % [problems])


## Rule 4 refuses a ring site at a size where its species is haze: a band-1 block (sizes 3 and 4) with
## a speck (a rammer of body size 1.0, entry 1) at 3 and 4: a morsel at 3, haze at 4.
func test_rule_4_refuses_a_size_where_the_species_is_haze() -> void:
	var data: Dictionary = WorldChecks.s2_species_data()
	data.species["speck"] = data.species.rammer.duplicate(true)
	data.species.speck.body_size = 1.0
	var speck := SpeciesCatalog.from_dict(data)
	var problems := _problems(func(d: Dictionary) -> void:
		d.band = 1
		d.sites = [{"id": "a", "species": "speck", "home": [0.0, -50.0], "heading": 0.0, "territory_zone": "n", "sizes": [3, 4]}], speck)
	check(Array(problems).has("home_min: rule 4: site 'a': 'speck' is haze at size 4, so it cannot be live there"), "%s" % [problems])
	check(not Array(problems).any(func(p: String) -> bool: return p.contains("haze at size 3")), "a morsel at 3")
