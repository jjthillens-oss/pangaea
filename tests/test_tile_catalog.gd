extends TestCase
## The endless world's tiles (docs/s1/s1-interfaces.md sections 3.5 and 4.2): the 20 minimal fixture
## tiles pass, each rule refuses the mistake it is for with one problem that names the rule, the
## file, band and local-id rules hold, unknown and missing keys are refused with their JSON path
## (G24), and the lookups the generator uses answer from the data alone.
##
## The tests use tests/fixtures/world/tiles/b0 (written by a script from three templates under six
## square symmetries; not game content) and the fixture kit. T4's tiles are checked by the same rules
## once they land.

const DIR := "res://tests/fixtures/world/tiles/b0"
const KIT := "res://tests/fixtures/world/kit_min.json"
## Two tiles with S2's two-post sites (a reef Lurker, a sunlit elder rammer), checked with
## WorldChecks.s2_species; written by hand for these tests, not game content.
const S2_DIR := "res://tests/fixtures/world/tiles_s2/b0"
const WorldChecks := preload("res://tests/world_checks.gd")

var species: SpeciesCatalog
var parts: PartCatalog
var kit: PlacementKit


func before_each() -> void:
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()
	kit = PlacementKit.load_from(KIT)


## The fixture files' data: file id -> parsed JSON.
static func _files() -> Dictionary:
	var out := {}
	for name in DirAccess.get_files_at(DIR):
		if name.get_extension() == "json":
			out[name.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(name)))
	return out


## A catalog of the fixture tiles after `change` edits their data (file id -> dict).
static func _catalog(change: Callable) -> TileCatalog:
	var files := _files()
	change.call(files)
	var cat := TileCatalog.new()
	for id in WorldConfig._sorted(files.keys()):
		cat.add_tile(files[id], 0, id)
	return cat


func _problems(change: Callable, p_species: SpeciesCatalog = null, p_kit: PlacementKit = null) -> PackedStringArray:
	return _catalog(change).validate(p_species if p_species != null else species, p_kit if p_kit != null else kit, parts, 1)


static func _shell(id: String, x: float, y: float, r: float) -> Dictionary:
	return {"id": id, "center": [x, y], "radius": r, "yaw_deg": [0.0, 360.0], "at_second_size": "keep"}


func _check_case(problems: PackedStringArray, fragment: String, count: int, label: String) -> void:
	var found := false
	for p in problems:
		found = found or p.contains(fragment)
	check(found and problems.size() == count, "%s: %d problem(s), one containing '%s': %s" % [label, count, fragment, problems])


func test_the_fixture_tiles_have_no_problems() -> void:
	var cat := TileCatalog.load_from({"0": DIR})
	check_eq(cat.validate(species, kit, parts, 1), PackedStringArray(), "the 20 minimal tiles")
	check_eq(cat.tiles.size(), 20, "6 per region and the 2 rare tiles")
	check_eq(cat.bands, [0] as Array[int], "band 0")
	var t := cat.tile("sunlit_a")
	check_eq(t.landmark_anchor, PackedFloat64Array([0.0, -25.0]), "coordinates stay float64 pairs")
	check_eq(t.shells[0].center, PackedFloat64Array([-16.0, -8.0]), "a shell's centre")
	check_eq(t.sites[0].sizes, [1] as Array[int], "a site's sizes")
	check_eq([t.sites[2].species, t.sites[2].sizes], ["elder_rammer", [2] as Array[int]], "S2: the size-2 threat")
	check_eq(cat.validate(species, kit, parts, 2), PackedStringArray(), "the 20 minimal tiles at size 2")
	check_eq(cat.tile("rare_giant_husk").set, -1, "a rare tile has no set")
	check(cat.tile("rare_giant_husk").landmark_anchor.is_empty(), "nor an anchor")
	check(cat.tile("nowhere").is_empty(), "an unknown id")


func test_each_tile_rule_has_a_failing_variant() -> void:
	var lurker_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	lurker_data.species["lurker"] = lurker_data.species.ambush_hunter.duplicate(true)
	lurker_data.species.lurker.entry_size = 2
	var with_lurker := SpeciesCatalog.from_dict(lurker_data)
	var short_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	short_data.species.rammer.leash_m = 0.5
	var short_rammer := SpeciesCatalog.from_dict(short_data)
	var kit_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	for a in kit_data.assets:
		if a.id == "shell_m_lens":
			a.scale = [1.0, 1.25]     # fp_m loses its second shell over (1.125, 1.2)
	var thin_kit := PlacementKit.from_dict(kit_data)
	# [change, fragment, problems, species, kit]
	var cases := [
		# Rule 1: counts and rare kinds.
		[func(f: Dictionary) -> void: f.erase("sunlit_a"), "tiles b0: rule 1: sunlit has [2, 3] tiles by set", 1],
		[func(f: Dictionary) -> void: f.reef_a.set = 1, "tiles b0: rule 1: reef has [2, 4] tiles by set", 1],
		[func(f: Dictionary) -> void: f.erase("rare_shell_cathedral"), "tiles b0: rule 1: the rare kinds are [\"giant_husk\"]", 1],
		[func(f: Dictionary) -> void:
			f.rare_shell_cathedral.rare = "giant_husk"
			f.rare_shell_cathedral.set_piece = {"asset": "rare_giant_husk", "center": [0.0, -14.0], "yaw_deg": 0.0},
			"tiles b0: rule 1: the rare kind 'giant_husk' has 2 tiles", 2],
		# Rule 2: shells.
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].radius = 1.6, "b0/sunlit_a: rule 2: shell 'a' radius 1.6 is outside", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].radius = 0.3, "b0/sunlit_a: rule 2: Rock 'a' radius 0.19 m is not above 0.20 m", 2],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].radius = 1.15, "b0/sunlit_a: rule 2: shell 'a' radius 1.15 fits [\"shell_m_pill\"]", 1, null, thin_kit],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].center = [-27.0, -8.0], "b0/sunlit_a: rule 2: shell 'a' at [-27.0, -8.0] comes within 4.0 bu", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[1].center = [-16.0, -9.5], "b0/sunlit_a: rule 2: 'a' and 'b' overlap by 0.50 bu", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].yaw_deg = [200.0, 100.0], "b0/sunlit_a: rule 2: shell 'a' yaw_deg", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[0].at_second_size = "grow", "b0/sunlit_a: rule 2: shell 'a' at_second_size 'grow'", 1],
		# Rule 3: zones.
		[func(f: Dictionary) -> void: f.sunlit_a.zones[1].radius = 9.0, "b0/sunlit_a: rule 3: zone 'b' needs 2.0 <= radius <= 8.0", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.zones[1].center = [-14.0, 29.0], "b0/sunlit_a: rule 3: zone 'b' at [-14.0, 29.0] comes within 1.0 bu", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.zones[1].at_second_size = "grow", "b0/sunlit_a: rule 3: zone 'b' at_second_size 'grow'", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.zones[1].capacity = 50.0, "b0/sunlit_a: rule 3: zone 'b' yields 1.200 a second", 1],
		[func(f: Dictionary) -> void: f.drift_a.shells[4] = _shell("e", -9.11, -10.0, 1.2), "b0/drift_a: rule 3: Zone 'b' is 0.69 bu from collider 'e'; it keeps 0.7.", 1],
		# Rule 4: the landmark anchor.
		[func(f: Dictionary) -> void: f.sunlit_a.landmark_anchor = [0.0, -26.0], "b0/sunlit_a: rule 4: the landmark anchor [0.0, -26.0] lies beyond", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[2].center = [-3.5, -23.0], "b0/sunlit_a: rule 4: the landmark collider leaves 1.03 bu to shell 'c'", 1],
		# Rule 5: the set piece.
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.asset = "rare_shell_cathedral", "b0/rare_giant_husk: rule 5: the set piece 'rare_shell_cathedral'", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.yaw_deg = 45.0, "b0/rare_giant_husk: rule 5: the set piece's yaw_deg 45.0", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.center = [0.0, -26.0], "b0/rare_giant_husk: rule 5: set-piece collider 'r0'", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.center = [-18.0, -18.0], "b0/rare_giant_husk: rule 5: 'a' and 'r0' overlap", 1],
		# Rule 6: sites.
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].species = "kraken", "b0/sunlit_a: rule 6: site 'b' names unknown species 'kraken'", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].sizes = [3], "b0/sunlit_a: rule 6: site 'b': sizes [3] must be some of [1, 2]", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].sizes = [], "b0/sunlit_a: rule 6: site 'b': sizes [] must be some of", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].species = "lurker", "rule 6: site 'b': 'lurker' enters at size 2, so it cannot be live at size 1", 1, with_lurker],
		[func(f: Dictionary) -> void: f.sunlit_a.shells.append(_shell("z", -12.0, 12.5, 0.6)), "b0/sunlit_a: rule 6: site 'b' home [-12.0, 12.0] is not clear", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].home = [12.0, 14.5], "b0/sunlit_a: rule 6: site 'b' is 1.50 bu from site 'a'", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[0].territory_zone = "q", "b0/sunlit_a: rule 6: site 'a' territory_zone 'q' is not a zone", 1],
		# G2's case: the reach disc crosses the inset by 0.05.
		[func(f: Dictionary) -> void:
			f.sunlit_a.zones[0].center = [22.325, 12.0]
			f.sunlit_a.sites[0].home = [22.325, 13.0],
			"b0/sunlit_a: rule 6: site 'a' reach disc at (22.325, 12.0), r 9.00, comes within 0.72 bu", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells.append(_shell("z", -12.0, 21.5, 0.6)), "b0/sunlit_a: rule 6: Rule 9 (", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.landmark_anchor = [8.0, -12.0], "b0/sunlit_a: rule 6: site 'a' can reach 11.71 bu from the landmark anchor", 1],
		# Rule 7: content.
		[func(f: Dictionary) -> void: f.drift_a.zones = [], "b0/drift_a: rule 7: a tile needs at least one zone", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites = [], "b0/sunlit_a: rule 7: a sunlit tile needs a live threat site at size 1", 1],
		[func(f: Dictionary) -> void: f.drift_a.sites = [{"id": "a", "species": "ambush_hunter", "home": [-6.0, 8.0], "heading": 0.0, "sizes": [1]}],
			"b0/drift_a: rule 7: a drift tile has no threat site", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites.append({"id": "c", "species": "rammer", "home": [0.0, 0.0], "heading": 0.0, "territory_zone": "a", "sizes": [2]}),
			"b0/sunlit_a: rule 7: 2 sites are live at size 1 and 3 at size 2", 1],
		[func(f: Dictionary) -> void:
			for id in f:
				for s in f[id].sites:
					if s.species == "ambush_hunter":
						s.sizes = [2],
			"tiles b0: rule 7: the live threats at size 1 are [\"territorial\"]", 1],
		# Rule 8: the strike lane over the tiles' smallest territory.
		[func(f: Dictionary) -> void: f.sunlit_a.zones[0].radius = 2.0, "tiles: rule 8: species 'rammer' strike lane 5.67 m is longer than its smallest territory plus its leash (4.50 m)", 1, short_rammer],
	]
	check(_problems(func(_f: Dictionary) -> void: pass).is_empty(), "the base passes")
	for i in cases.size():
		var c: Array = cases[i]
		var p_species: SpeciesCatalog = c[3] if c.size() > 3 else null
		var p_kit: PlacementKit = c[4] if c.size() > 4 else null
		_check_case(_problems(c[0], p_species, p_kit), c[1], c[2], "case %d" % i)


## C-4: a site's home lies inside its own reach disc, so its home chunk is one the disc touches.
func test_rule_6_refuses_a_home_outside_its_reach_disc() -> void:
	# The rammer's disc is its zone (12, 12), r 4 + 2 + 3 = 9; a home 9 - r + 0.1 from its centre.
	var r := species.phenotype("rammer", parts).radius
	var out := _problems(func(f: Dictionary) -> void: f.sunlit_a.sites[0].home = [12.0, 12.0 + 9.0 - r + 0.1])
	_check_case(out, "b0/sunlit_a: rule 6: site 'a' home [12.0, 20.475] is not inside its reach disc", 1, "0.1 outside")
	check(_problems(func(f: Dictionary) -> void: f.sunlit_a.sites[0].home = [12.0, 12.0 + 9.0 - r - 0.1]).is_empty(), "0.1 inside passes")


## Static #33: growth x capacity x (0.25 + REGROW_FLOOR) <= 1.152, the M1 unguarded maximum (z_center, z_s).
func test_static_33_refuses_a_zone_that_yields_more_than_the_unguarded_m1_maximum() -> void:
	var refused := _problems(func(f: Dictionary) -> void: f.sunlit_a.zones[1].capacity = 1.16 / 0.3 / 0.08)
	_check_case(refused, "b0/sunlit_a: rule 3: zone 'b' yields 1.160 a second; static #33 allows <= 1.152, the M1 unguarded maximum (z_center, z_s)", 1, "1.16")
	check(_problems(func(f: Dictionary) -> void: f.sunlit_a.zones[1].capacity = 48.0).is_empty(), "z_center's 48 x 0.08 x 0.30 = 1.152 passes")


## The gap rule (B-3): every zone keeps 0.7 bu from every collider of its tile: a shell, the landmark
## collider (r 2.0 round the anchor) and a set piece's colliders. 0.69 bu is refused, 0.70 passes.
## drift_a's zone 'b' is (-14, -10) r 3, and the husk's fixture collider r 3 sits at (0, -14).
func test_rule_3_keeps_every_zone_0_7_bu_from_every_collider() -> void:
	for gap in [0.69, 0.70]:
		var label := "%.2f bu" % gap
		var cases := [
			[func(f: Dictionary) -> void: f.drift_a.shells[4] = _shell("e", -14.0 + 3.0 + 1.2 + gap, -10.0, 1.2),
				"b0/drift_a: rule 3: Zone 'b' is 0.69 bu from collider 'e'; it keeps 0.7.", "a shell"],
			[func(f: Dictionary) -> void: f.drift_a.landmark_anchor = [-14.0 + 3.0 + 2.0 + gap, -10.0],
				"b0/drift_a: rule 3: Zone 'b' is 0.69 bu from collider 'lm'; it keeps 0.7.", "the landmark collider"],
			[func(f: Dictionary) -> void: f.rare_giant_husk.zones[1].center = [-3.0 - 3.0 - gap, -14.0],
				"b0/rare_giant_husk: rule 3: Zone 'b' is 0.69 bu from collider 'r0'; it keeps 0.7.", "a set-piece collider"],
		]
		for c in cases:
			var problems := _problems(c[0])
			if gap < 0.7:
				check_eq(problems, PackedStringArray([c[1]]), "%s from %s is refused" % [label, c[2]])
			else:
				check_eq(problems, PackedStringArray(), "%s from %s passes" % [label, c[2]])


func test_ids_of_returns_three_sorted_ids_per_region_and_set() -> void:
	var cat := TileCatalog.load_from({"0": DIR})
	for region in TileCatalog.REGIONS:
		for set_index in 2:
			var ids := cat.ids_of(0, region, set_index)
			var sorted := Array(ids)
			sorted.sort()
			check(ids.size() == 3 and Array(ids) == sorted, "%s set %d: %s" % [region, set_index, ids])
			for id in ids:
				check(cat.tile(id).region == region and cat.tile(id).set == set_index, "%s is %s set %d" % [id, region, set_index])
	check_eq(cat.ids_of(0, "sunlit", 0), PackedStringArray(["sunlit_a", "sunlit_c", "sunlit_e"]), "sunlit set 0")
	check_eq(cat.ids_of(1, "sunlit", 0), PackedStringArray(), "band 1 has none")
	check_eq(cat.rare_kinds(0), PackedStringArray(["giant_husk", "shell_cathedral"]), "rare kinds, sorted")
	check_eq(cat.rare_tile(0, "giant_husk").id, "rare_giant_husk", "the giant husk's tile")
	check(cat.rare_tile(0, "kraken").is_empty(), "an unknown kind")


func test_file_band_and_local_id_rules() -> void:
	var files := _files()
	var cases := [
		[files.sunlit_a.duplicate(true), "sunlit_x", "b0/sunlit_x.id: 'sunlit_a' is not the file's name 'sunlit_x'"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.band = 1), "sunlit_a", "b0/sunlit_a.band: 1 is not its directory's band 0"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.shells[0].id = "lm"), "sunlit_a", "b0/sunlit_a.shells[0].id: 'lm' is repeated, reserved"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.zones[0].id = "r1"), "sunlit_a", "b0/sunlit_a.zones[0].id: 'r1' is repeated, reserved"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.sites[0].id = "Bad"), "sunlit_a", "b0/sunlit_a.sites[0].id: 'Bad' is repeated, reserved"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.shells[1].id = "a"), "sunlit_a", "b0/sunlit_a.shells[1].id: 'a' is repeated"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.region = "abyss"), "sunlit_a", "b0/sunlit_a.region: 'abyss' is not one of"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.set = 2), "sunlit_a", "b0/sunlit_a.set: must be 0 or 1"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.rare = "giant_husk"), "sunlit_a", "b0/sunlit_a.rare: a rare tile names its kind"],
		[_edited(files.sunlit_a, func(d: Dictionary) -> void: d.set_piece = {"asset": "rare_giant_husk", "center": [0.0, 0.0], "yaw_deg": 0.0}),
			"sunlit_a", "b0/sunlit_a.set_piece: must be null on an ordinary tile"],
		[_edited(files.rare_giant_husk, func(d: Dictionary) -> void: d.set = 0), "rare_giant_husk", "b0/rare_giant_husk.set: must be null on a rare tile"],
		[_edited(files.rare_giant_husk, func(d: Dictionary) -> void: d.landmark_anchor = [0.0, 0.0]), "rare_giant_husk", "b0/rare_giant_husk.landmark_anchor: must be null on a rare tile"],
		[_edited(files.rare_giant_husk, func(d: Dictionary) -> void: d.rare = ""), "rare_giant_husk", "b0/rare_giant_husk.rare: a rare tile names its kind"],
	]
	for c in cases:
		var cat := TileCatalog.new()
		cat.add_tile(c[0], 0, c[1])
		var problems := cat.validate(species, kit, parts, 1)
		check(problems.size() == 1 and problems[0].begins_with(c[2]), "one problem starting '%s': %s" % [c[2], problems])
	var twice := TileCatalog.new()
	twice.add_tile(files.sunlit_a, 0, "sunlit_a")
	twice.add_tile(files.sunlit_a, 0, "sunlit_a")
	check_eq(twice.load_problems, PackedStringArray(["b0/sunlit_a.id: 'sunlit_a' is repeated"]), "a tile id once per catalog")
	var missing := TileCatalog.load_from({"0": "res://tests/fixtures/world/tiles/b9"})
	check_eq(missing.validate(species, kit, parts, 1), PackedStringArray(["tiles.0: the directory 'res://tests/fixtures/world/tiles/b9' does not exist"]),
		"a missing directory")
	var bad_band := TileCatalog.load_from({"x": DIR})
	check_eq(bad_band.load_problems, PackedStringArray(["tiles.x: a band is a whole number of 0 or more"]), "a band key")


static func _edited(data: Dictionary, change: Callable) -> Dictionary:
	var copy := data.duplicate(true)
	change.call(copy)
	return copy


func test_unknown_and_missing_keys_are_refused() -> void:
	var data: Dictionary = _files().sunlit_a
	data["colour"] = "blue"
	data.shells[0]["tint"] = "#FFFFFF"
	data.sites[0].erase("heading")
	data.zones[1].erase("capacity")
	data.erase("note")
	var cat := TileCatalog.new()
	cat.add_tile(data, 0, "sunlit_a")
	check_eq(cat.validate(species, kit, parts, 1), PackedStringArray(["b0/sunlit_a.colour: unknown key", "b0/sunlit_a.note: missing",
		"b0/sunlit_a.shells[0].tint: unknown key", "b0/sunlit_a.zones[1].capacity: missing", "b0/sunlit_a.sites[0].heading: missing"]),
		"each named by its path; the rules wait for tiles that read")
	var rare: Dictionary = _files().rare_giant_husk
	rare.set_piece["scale"] = 1.0
	rare.set_piece.erase("yaw_deg")
	var rare_cat := TileCatalog.new()
	rare_cat.add_tile(rare, 0, "rare_giant_husk")
	check_eq(rare_cat.load_problems, PackedStringArray(["b0/rare_giant_husk.set_piece.scale: unknown key",
		"b0/rare_giant_husk.set_piece.yaw_deg: missing"]), "inside the set piece")
	var types: Dictionary = _files().sunlit_a
	types.shells[0].center = [1.0]
	types.sites[0].sizes = [1.5]
	var type_cat := TileCatalog.new()
	type_cat.add_tile(types, 0, "sunlit_a")
	check_eq(type_cat.load_problems, PackedStringArray(["b0/sunlit_a.shells[0].center: must be two numbers",
		"b0/sunlit_a.sites[0].sizes.0: must be a whole number"]), "types")


## A set piece's colliders are the kit record's, turned by the piece's yaw a quarter at a time (as
## RockField turns its mesh) and moved to its centre; an ordinary tile's landmark collider is the anchor.
func test_colliders_of_turns_the_set_piece_as_its_mesh_turns() -> void:
	var cat := TileCatalog.load_from({"0": DIR})
	var cathedral := TileCatalog.colliders_of(cat.tile("rare_shell_cathedral"), kit)
	var pieces := cathedral.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("r"))
	check_eq(pieces.size(), 2, "two colliders")
	check_eq(pieces[0], {"id": "r0", "center": Vector2(0.0, -12.5), "radius": 2.0}, "(-1.5, 0) turned 90 degrees, at (0, -14)")
	check_eq(pieces[1], {"id": "r1", "center": Vector2(0.5, -15.5), "radius": 1.5}, "(1.5, 0.5) turned 90 degrees")
	var ordinary := TileCatalog.colliders_of(cat.tile("sunlit_a"), kit)
	check_eq(ordinary[-1], {"id": "lm", "center": Vector2(0.0, -25.0), "radius": 2.0}, "the landmark collider comes last")
	check_eq(ordinary.size(), cat.tile("sunlit_a").shells.size() + 1, "the shells, then the anchor")
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		for p in [Vector2(1.5, 0.5), Vector2(-2.0, 3.0)]:
			var turned := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(p.x, 0.0, p.y)
			var mine := TileCatalog.yaw_point(p.x, p.y, yaw)
			check(absf(mine[0] - turned.x) < 1e-6 and absf(mine[1] - turned.z) < 1e-6, "yaw %s turns %s as the mesh turns: %s vs %s" % [yaw, p, mine, turned])


# --- S2: the rules at a band's second size and two-post sites ---

## The S2 fixture tiles after `change`, validated at `size` with the S2 species (or `p_species`),
## each tile's own problems and rule 8's: the two tiles are not a band, so the band-wide rules 1 and
## 7 ("tiles b0: ...") are left out.
func _s2_problems(change: Callable, size := 2, p_species: SpeciesCatalog = null) -> PackedStringArray:
	var files := {}
	for name in DirAccess.get_files_at(S2_DIR):
		if name.get_extension() == "json":
			files[name.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string(S2_DIR.path_join(name)))
	change.call(files)
	var cat := TileCatalog.new()
	for id in WorldConfig._sorted(files.keys()):
		cat.add_tile(files[id], 0, id)
	var out := PackedStringArray()
	for p in cat.validate(p_species if p_species != null else WorldChecks.s2_species(), kit, parts, size):
		if not p.begins_with("tiles b0: "):
			out.append(p)
	return out


func _s2_species_with(change: Callable) -> SpeciesCatalog:
	var data := WorldChecks.s2_species_data()
	change.call(data)
	return SpeciesCatalog.from_dict(data)


## The tiles' own rules hold at both sizes: the elder rammer and the Lurker live only at size 2, the
## M1 sites at size 1 (and the rammer at 2), each two-post site passing D-61 and BP-11.
func test_the_two_post_fixture_tiles_pass_at_both_sizes() -> void:
	var noop := func(_f: Dictionary) -> void: pass
	check_eq(_s2_problems(noop, 1), PackedStringArray(), "size 1")
	check_eq(_s2_problems(noop, 2), PackedStringArray(), "size 2")
	var cat := TileCatalog.load_from({"0": S2_DIR})
	check_eq(cat.tile("reef_posts").sites[1].post_b, {"home": PackedFloat64Array([-7.0, 11.0]), "heading": 2.4, "territory_zone": ""},
		"post_b read as float64 pairs, with an empty zone")
	check_eq(cat.tile("reef_posts").sites[0].post_b, {}, "a one-post site has none")


## A two-post site turns with its tile: WorldChecks.oriented_tile lays the second post's home and
## heading as WorldGen does the first's, so both tiles pass at size 2 in all eight orientations.
func test_the_two_post_fixture_tiles_pass_in_every_orientation() -> void:
	var s2 := WorldChecks.s2_species()
	var base := TileCatalog.load_from({"0": S2_DIR})
	for o in WorldChecks.ALL_ORIENTATIONS:
		var cat := TileCatalog.new()
		for id in WorldConfig._sorted(base.tiles.keys()):
			cat.tiles[id] = WorldChecks.oriented_tile(base.tiles[id], o)
		cat.bands = [0] as Array[int]
		var own := Array(cat.validate(s2, kit, parts, 2)).filter(func(p: String) -> bool: return not p.begins_with("tiles b0: "))
		check_eq(own, [], "orientation %d" % o)
	var turned := WorldChecks.oriented_tile(base.tile("reef_posts"), 2)
	check_eq(turned.sites[1].post_b.home, PackedFloat64Array([7.0, -11.0]), "a half turn moves post b's home too")


## S2G41 (BP-11): the path between the posts, R + route_clearance x q wide (1.2 + 0.16 bu for the
## Lurker at size 2), crosses no shell there at that size. A kept shell on the segment is refused; the
## same shell sunk at the second size is not there, so it passes.
func test_s2g41_a_kept_shell_across_the_post_path_is_refused() -> void:
	var across := func(second: String) -> Callable:
		return func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", -10.0, 8.0, 0.8).merged({"at_second_size": second}, true))
	_check_case(_s2_problems(across.call("keep")),
		"b0/reef_posts: rule 6 at size 2: site 'lk': the path between its posts passes -0.80 bu from 'z'; it needs 1.36 (BP-11)", 1, "kept")
	check_eq(_s2_problems(across.call("sink")), PackedStringArray(), "sunk at size 2: no shell on the path")
	# Just clear of the path passes; a hair inside is refused (the segment's normal through (-10, 8)).
	var normal := Vector2(1.0, -1.0).normalized()
	for gap in [0.01, -0.01]:
		var at: Vector2 = Vector2(-10.0, 8.0) + normal * (1.36 + 0.8 + gap)
		var problems := _s2_problems(func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", at.x, at.y, 0.8)))
		check_eq(problems.size(), 0 if gap > 0.0 else 1, "%+.2f bu from the capsule: %s" % [gap, problems])


func test_each_two_post_rule_has_a_failing_variant() -> void:
	var slow_elder := _s2_species_with(func(d: Dictionary) -> void: d.species.elder_rammer.nav_timeout_s = 12.0)
	var short_elder := _s2_species_with(func(d: Dictionary) -> void: d.species.elder_rammer.leash_m = 0.5)
	var short_rammer := _s2_species_with(func(d: Dictionary) -> void: d.species.rammer.leash_m = 0.5)
	# [change, fragment, problems, size, species]
	var cases := [
		# D-38: post_b's own keys.
		[func(f: Dictionary) -> void: f.reef_posts.sites[1].post_b["territory_zone"] = "a",
			"b0/reef_posts: rule 6: site 'lk': post_b.territory_zone is refused, as 'lurker' is not territorial", 1, 2],
		[func(f: Dictionary) -> void: f.sunlit_posts.sites[1].post_b.erase("territory_zone"),
			"b0/sunlit_posts: rule 6: site 'er': post_b needs a territory_zone, as 'elder_rammer' is territorial", 1, 2],
		[func(f: Dictionary) -> void: f.sunlit_posts.sites[1].post_b.territory_zone = "a",
			"b0/sunlit_posts: rule 6: site 'er': post_b guards zone 'a' as post a does", 1, 2],
		[func(f: Dictionary) -> void: f.reef_posts.sites[0]["post_b"] = {"home": [10.0, 4.0], "heading": 0.0},
			"b0/reef_posts: rule 6: site 'b': post_b needs a species with a habit; 'ambush_hunter' has none", 1, 1],
		[func(f: Dictionary) -> void: f.sunlit_posts.zones[1].at_second_size = "drop",
			"b0/sunlit_posts: rule 6 at size 2: site 'er' post_b.territory_zone 'b' is dropped at size 2", 1, 2],
		[func(f: Dictionary) -> void: f.sunlit_posts.zones[0].at_second_size = "drop",
			"b0/sunlit_posts: rule 6 at size 2: site 'er' territory_zone 'a' is dropped at size 2", 2, 2],
		# D-61: spacing (6.4 to 9.6 bu for the Lurker), travel and the union's reach.
		[func(f: Dictionary) -> void: f.reef_posts.sites[1].post_b.home = [-9.0, 9.0],
			"b0/reef_posts: rule 6: site 'lk': its posts are 5.66 bu apart; a 'out_of_sight' habit keeps them 6.40 to 9.60 bu", 1, 2],
		[func(f: Dictionary) -> void: f.reef_posts.sites[1].post_b.home = [-5.0, 13.0],
			"b0/reef_posts: rule 6: site 'lk': its posts are 11.31 bu apart", 1, 2],
		[func(f: Dictionary) -> void: pass,
			"b0/sunlit_posts: rule 6: site 'er': the move between its posts takes 11.74 s at wander speed; 0.8 x nav_timeout_s allows 9.60 s", 1, 2, slow_elder],
		# The second post's home, and the rules at size 2 in bu (R 1.2 bu for the Lurker).
		[func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", -7.0, 11.5, 0.6)),
			"b0/reef_posts: rule 6 at size 2: site 'lk' post_b home [-7.0, 11.0] is not clear", 2, 2],
		[func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", -13.0, 20.4, 1.0)),
			"b0/reef_posts: rule 6 at size 2: Rule 9 (leash band): site 'lk' post a: z lies 0.00 m from its leash circle; it needs 0.85 m.", 1, 2],
		# The anchor rule binds the elder rammer (post a and union), not the M1 rammer 'a', a rival at size 2.
		[func(f: Dictionary) -> void: f.sunlit_posts.landmark_anchor = [-24.0, 10.0],
			"b0/sunlit_posts: rule 6 at size 2: site 'er' union can reach", 2, 2],
		[func(f: Dictionary) -> void: f.reef_posts.sites[1].sizes = [1, 2],
			"b0/reef_posts: rule 6: site 'lk': 'lurker' enters at size 2, so it cannot be live at size 1", 1, 1],
		# Rule 4 at size 2: the largest live body is the Lurker's 1.2 bu, so the collider needs 2 x 1.2 +
		# 0.5 / 0.625 = 3.2 bu to a kept shell (2.0 at size 1).
		[func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", 24.0, -18.5, 1.0)),
			"b0/reef_posts: rule 4 at size 2: the landmark collider leaves 2.50 bu to shell 'z'; it needs 3.20", 1, 2],
		# Rule 7 at size 2: a zone that is there, and a threat of entry size 2.
		[func(f: Dictionary) -> void:
			for z in f.reef_posts.zones:
				z.at_second_size = "drop",
			"b0/reef_posts: rule 7 at size 2: every zone is dropped", 1, 2],
		# A tile of set 1 needs a threat at size 2; one of set 0 (both fixtures) a live site, an M1 one
		# (the cell outgrows it) or a threat (PROPOSED, TileCatalog.SECOND_SIZE_OUTGROWN_SET).
		[func(f: Dictionary) -> void: f.reef_posts.sites.pop_back(), "b0/reef_posts: rule 7: a reef tile of set 0 needs a live site at size 2", 1, 2],
		[func(f: Dictionary) -> void:
			f.reef_posts.set = 1
			f.reef_posts.sites.pop_back(),
			"b0/reef_posts: rule 7: a reef tile needs a live threat site at size 2", 1, 2],
		[func(f: Dictionary) -> void:
			f.sunlit_posts.set = 1
			f.sunlit_posts.sites[1].species = "rammer"
			f.sunlit_posts.sites[1].erase("post_b"),
			"b0/sunlit_posts: rule 7: a sunlit tile needs a live threat site at size 2", 1, 2],
		# Rule 8 at size 2: the elder's own lane against its smallest territory there, in tm.
		[func(f: Dictionary) -> void: pass,
			"tiles: rule 8: species 'elder_rammer' strike lane 5.67 m is longer than its smallest territory plus its leash (4.38 m)", 1, 2, short_elder],
		# The M1 rammer at size 2 (q 0.625): its lane, leash and margin x q against 3 bu x 0.625 = 1.875 tm.
		[func(f: Dictionary) -> void: pass,
			"tiles: rule 8: species 'rammer' strike lane 3.73 m is longer than its smallest territory plus its leash (3.44 m)", 1, 2, short_rammer],
	]
	for i in cases.size():
		var c: Array = cases[i]
		_check_case(_s2_problems(c[0], c[3], c[4] if c.size() > 4 else null), c[1], c[2], "case %d" % i)
	# Rule 7 at size 2: a set-0 tile whose one live site there is its M1 rammer passes; at set 1 not.
	var outgrown := func(set_index: int) -> Callable:
		return func(f: Dictionary) -> void:
			f.sunlit_posts.set = set_index
			f.sunlit_posts.sites.pop_back()
	check_eq(_s2_problems(outgrown.call(0), 2), PackedStringArray(), "rule 7 at size 2: set 0 with its rammer live there")
	_check_case(_s2_problems(outgrown.call(1), 2), "b0/sunlit_posts: rule 7: a sunlit tile needs a live threat site at size 2", 1,
		"rule 7 at size 2: set 1 with the same rammer")
	check_eq(_s2_problems(outgrown.call(0), 1), PackedStringArray(), "rule 7 at size 1: the rammer is its threat there")
	# The same shell near the anchor passes at size 1 (2.0 bu), and at size 2 once it sinks there.
	check_eq(_s2_problems(func(f: Dictionary) -> void: f.reef_posts.shells.append(_shell("z", 24.0, -18.5, 1.0)), 1), PackedStringArray(),
		"rule 4 at size 1")
	check_eq(_s2_problems(func(f: Dictionary) -> void:
		f.reef_posts.shells.append(_shell("z", 24.0, -18.5, 1.0).merged({"at_second_size": "sink"}, true)), 2), PackedStringArray(),
		"rule 4 at size 2, sunk")


## Rule 6 refuses a size where the species is haze (SpeciesCatalog.live_at). No band-0 species can be
## (a body_size of at least 1 keeps rel >= 0.625 at size 2), so a band-1 tile shows it: a body of
## radius 0.5 is a morsel at size 3 (rel 0.39) and haze at size 4 (0.24).
func test_rule_6_refuses_a_size_where_the_species_is_haze() -> void:
	var speck := _s2_species_with(func(d: Dictionary) -> void:
		d.species["speck"] = d.species.rammer.duplicate(true)
		d.species.speck.body_size = 1.0)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("drift_a.json")))
	data.band = 1
	data.region = "veil_garden"   # a band-1 region (S3: band 1 has its own)
	data.sites = [{"id": "s", "species": "speck", "home": [6.0, 9.0], "heading": 0.0, "territory_zone": "a", "sizes": [3, 4]}]
	var cat := TileCatalog.new()
	cat.add_tile(data, 1, "drift_a")
	var sizes := Array(cat.validate(speck, kit, parts, 3)).filter(func(p: String) -> bool: return p.contains("'speck'"))
	check_eq(sizes, ["b1/drift_a: rule 6: site 's': 'speck' is haze at size 4, so it cannot be live there"], "size 4 only")
	check(speck.live_at("speck", 3, parts) and not speck.live_at("speck", 4, parts), "a morsel at 3, haze at 4")


## D-61's union cap: a Lurker with a 16 tm leash reaches 25.6 bu from each post, so its union is
## 25.6 + 4.24 = 29.84 bu, 18.65 tm at size 2, above 18 tm.
func test_a_union_reach_above_18_tm_is_refused() -> void:
	var long := _s2_species_with(func(d: Dictionary) -> void: d.species.lurker.leash_m = 16.0)
	check_has_error(_s2_problems(func(_f: Dictionary) -> void: pass, 2, long),
		"b0/reef_posts: rule 6 at size 2: site 'lk' union reach disc r 29.84 bu is 18.65 tm; D-61 keeps it <= 18.0 tm")


func test_post_b_keys_are_read_and_checked() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(S2_DIR.path_join("reef_posts.json")))
	data.sites[1].post_b["speed"] = 1.0
	data.sites[1].post_b.erase("heading")
	data.sites[0]["post_b"] = [1.0, 2.0]
	var cat := TileCatalog.new()
	cat.add_tile(data, 0, "reef_posts")
	check_eq(cat.load_problems, PackedStringArray(["b0/reef_posts.sites[0].post_b: must be an object",
		"b0/reef_posts.sites[1].post_b.speed: unknown key", "b0/reef_posts.sites[1].post_b.heading: missing"]), "by their paths")



# --- S3: band 1 (spine 5.3, s3-sim 3.11; T3.3) ---

const B1_DIR := "res://tests/fixtures/world/tiles_b1/b1"
const B1_SCHEMA_EXAMPLE := "res://tests/fixtures/world/b1_schema_example.json"
const BAND0_LIVE := "res://tests/fixtures/world/band0_live_sets.json"


## The band-1 fixture tiles (world_b1_min.json's) with `change` applied to their data by file id,
## validated at `size` with the shipped species and kit.
func _b1_problems(change: Callable, size: int) -> PackedStringArray:
	var files := {}
	for name in DirAccess.get_files_at(B1_DIR):
		if name.get_extension() == "json":
			files[name.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string(B1_DIR.path_join(name)))
	change.call(files)
	var cat := TileCatalog.new()
	for id in WorldConfig._sorted(files.keys()):
		cat.add_tile(files[id], 1, id)
	return cat.validate(SpeciesCatalog.load_from(), PlacementKit.load_from(), parts, size)


func _site_of(tile: Dictionary, id: String) -> Dictionary:
	for s in tile.sites:
		if s.id == id:
			return s
	return {}


## S3G1 (the fixture part): the band-1 fixture tiles pass rules 1 to 12 at both sizes.
func test_the_band_1_fixture_tiles_pass_at_sizes_3_and_4() -> void:
	var noop := func(_f: Dictionary) -> void: pass
	check_eq(_b1_problems(noop, 3), PackedStringArray(), "size 3")
	check_eq(_b1_problems(noop, 4), PackedStringArray(), "size 4")


## BP3-10: the schema example reads with no reading problems (the content rules are the real tiles').
func test_the_band_1_schema_example_reads() -> void:
	var cat := TileCatalog.new()
	cat.add_tile(JSON.parse_string(FileAccess.get_file_as_string(B1_SCHEMA_EXAMPLE)), 1, "veil_garden_a")
	check_eq(cat.load_problems, PackedStringArray(), "no load problems")
	check_eq(cat.tile("veil_garden_a").region, "veil_garden", "a band-1 region")
	var wrong := TileCatalog.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(B1_SCHEMA_EXAMPLE))
	data.region = "sunlit"
	wrong.add_tile(data, 1, "veil_garden_a")
	check_has_error(wrong.load_problems, "b1/veil_garden_a.region: 'sunlit' is not one of veil_garden, warden_flat, glass_reef, rare")


## D-97: a site's role at each size of band 1.
func test_site_roles_follow_the_ladder() -> void:
	var sp := SpeciesCatalog.load_from()
	var roles := {}
	for id in ["veil", "warden", "deep_lurker", "elder_warden", "ambush_hunter", "rammer", "lurker", "elder_rammer"]:
		var site := {"species": id, "sizes": [3, 4]}
		roles[id] = [TileCatalog.site_role(sp, site, 3), TileCatalog.site_role(sp, site, 4)]
	check_eq(roles.veil, ["threat", "rival"], "the veil")
	check_eq(roles.warden, ["threat", "rival"], "the Warden")
	check_eq(roles.deep_lurker, ["", "threat"], "the Deep lurker is a ghost at 3")
	check_eq(roles.elder_warden, ["", "threat"], "the elder Warden")
	check_eq(roles.ambush_hunter, ["prey", "morsel"], "an ambush hunter")
	check_eq(roles.rammer, ["prey", "morsel"], "a rammer")
	check_eq(roles.lurker, ["rival", "prey"], "a Lurker")
	check_eq(TileCatalog.site_role(sp, {"species": "veil", "sizes": [3]}, 4), "", "not one of its sizes")
	check_eq(TileCatalog.site_role(sp, {"species": "kraken", "sizes": [3]}, 3), "", "an unknown species")


## BP3-18: site_role gives every band-0 tile and the home block the live sets S2's rule gave.
func test_band_0_live_sets_are_s2s() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BAND0_LIVE))
	var sp := SpeciesCatalog.load_from()
	var tiles := TileCatalog.load_from({"0": "res://game/data/tiles/b0"})
	var home := HomeBlock.load_from("res://game/data/home_b0.json", PoolLayout.load_from(), sp)
	var groups := {"home": home.sites}
	for id in tiles.tiles:
		groups[id] = tiles.tiles[id].sites
	check_eq(groups.size(), expected.tiles.size() + 1, "every tile and the home block")
	for key in groups:
		var want: Dictionary = expected.home if key == "home" else expected.tiles[key]
		for n in [1, 2]:
			var live := []
			for s in groups[key]:
				if TileCatalog.site_role(sp, s, n) != "":
					live.append(str(s.id))
			check_eq(live, want[str(n)], "%s at size %d" % [key, n])


## S3G4, rule 9: the veil gardens' rammers are their morsels at size 4.
func test_rule_9_needs_prey_or_a_morsel_at_both_sizes() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		for s in f.veil_garden_a.sites:
			if s.species == "rammer":
				s.sizes = [3], 4)
	check_has_error(problems, "b1/veil_garden_a: rule 9: a tile needs a prey or morsel site at both sizes (at 3: true, at 4: false)")


## Rule 10: at most 3 morsel sites a size.
func test_rule_10_caps_morsel_sites() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		for k in 2:
			f.veil_garden_a.sites.append({"id": "m%d" % k, "species": "ambush_hunter", "home": [-6.0 + 8.0 * k, -26.0],
				"heading": 0.0, "territory_zone": "", "sizes": [4]}), 4)
	check_has_error(problems, "b1/veil_garden_a: rule 10: 0 and 4 morsel sites at sizes 3 and 4; at most 3")


## S3G6: a third creature site live at size 4.
func test_a_third_size_4_creature_site_is_refused() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		f.veil_garden_a.sites.append({"id": "vc", "species": "veil", "home": [-8.0, -2.0], "heading": 0.0,
			"territory_zone": "", "sizes": [4]}), 4)
	check_has_error(problems, "b1/veil_garden_a: rule 7: 4 sites are live at size 3 and 3 at size 4; at most 4 and 2")


## S3G6b (D-135): at most 6 zones live at size 4.
func test_seven_zones_at_size_4_are_refused() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		for z in f.veil_garden_a.zones:
			if z.id == "f2" or z.id == "f3":
				z.at_second_size = "keep", 4)
	check_has_error(problems, "b1/veil_garden_a: D-135: 13 shells, 12 zones and 7 live at size 4; at most 18, 12 and 6")


## S3G7: every ordinary band-1 tile has a live threat at both sizes (band 1 has no transit region).
func test_a_glass_reef_with_no_deep_lurker_has_no_threat_at_size_4() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		f.glass_reef_a.sites = f.glass_reef_a.sites.filter(func(s: Dictionary) -> bool: return s.species != "deep_lurker"), 4)
	check_has_error(problems, "b1/glass_reef_a: rule 7: a glass_reef tile needs a live threat site at size 4")


## S3G7b, rule 12: a shell 4 bu from a veil's home (it needs 5.55: its 4.75 leash and its body).
func test_rule_12_keeps_shells_off_a_veils_drift() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		f.veil_garden_a.shells.append({"id": "sx", "center": [23.0, -10.0], "radius": 1.0, "yaw_deg": [0.0, 360.0],
			"at_second_size": "keep"}), 3)
	check_has_error(problems, "b1/veil_garden_a: rule 12: site 'va': 'sx' lies 4.00 bu from the hazard's home; it needs 5.55")


## S3G16, rule 11: the Deep lurker's channel is clear and flanked; one flank shell gone, or a shell
## in the lane, breaks it.
func test_rule_11_keeps_a_channel_clear_and_flanked() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		f.glass_reef_a.shells = f.glass_reef_a.shells.filter(func(s: Dictionary) -> bool: return s.id != "s0"), 4)
	var mine := Array(problems).filter(func(p: String) -> bool: return p.contains("rule 11 at size 4"))
	check_eq(mine.size(), 1, "one problem: %s" % [problems])
	check_has_error(PackedStringArray(mine), "b1/glass_reef_a: rule 11 at size 4: site 'dl': 5 of its channel's 33 stations are flanked")
	problems = _b1_problems(func(f: Dictionary) -> void:
		for s in f.glass_reef_a.shells:
			if s.id == "s4":
				s.center = [10.5, -4.0], 4)
	check_has_error(problems, "b1/glass_reef_a: rule 11 at size 4: site 'dl': 's4' lies")


## S3G5b (D-134): the anchor rule in tm. At size 4 a bu is 0.625 tm, so a Deep lurker that can
## reach 9 tm (14.4 bu) from the anchor's clear ring is refused, though 14.4 bu is more than S1's 13.
func test_the_anchor_rule_is_in_tm_at_size_4() -> void:
	var sp := SpeciesCatalog.load_from()
	var real_kit := PlacementKit.load_from()
	var s := WorldConfig.bu_to_tm(4)
	var home := Vector2(10.0, -10.0)
	var reach := float(sp.reach_disc_for({"species": "deep_lurker", "home": home, "heading": 0.0}, {},
		WorldConfig.k_of(4, 4)).radius)
	var r := sp.radius_at("deep_lurker", 4) / s
	var d := 9.0 / s + reach + r + real_kit.collide_radius_bu + PoolLayout.CELL_RADIUS / s + TileCatalog.ANCHOR_GAP_BU
	var anchor := home + Vector2(-1.0, 1.0).normalized() * d
	var problems := _b1_problems(func(f: Dictionary) -> void: f.glass_reef_a.landmark_anchor = [anchor.x, anchor.y], 4)
	check_has_error(problems, "b1/glass_reef_a: rule 6 at size 4: site 'dl' can reach 14.40 bu from the landmark anchor; it must stay 20.8 away")


## D-147: an elder Warden's meadows are 13 to 16.5 bu apart, 5 to 6 bu round, and do not overlap.
func test_an_elder_wardens_meadows_keep_apart() -> void:
	var problems := _b1_problems(func(f: Dictionary) -> void:
		var ew := _site_of(f.veil_garden_a, "ew")
		ew.post_b.home = [8.0, 8.0]
		for z in f.veil_garden_a.zones:
			if z.id == "mb":
				z.center = [8.0, 8.0]
				z.radius = 6.5, 4)
	check_has_error(problems, "b1/veil_garden_a: rule 6: site 'ew': its posts are 10.00 bu apart; a 'bloom' habit keeps them 13.00 to 16.50 bu")
	check_has_error(problems, "meadow 'mb' has radius 6.50 bu; a bloom habit's meadows are 5.0 to 6.0")
	check_has_error(problems, "its meadows 'ma' and 'mb' overlap by 1.50 bu")
