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
	check_eq(t.landmark_anchor, PackedFloat64Array([0.0, -20.0]), "coordinates stay float64 pairs")
	check_eq(t.shells[0].center, PackedFloat64Array([-16.0, -8.0]), "a shell's centre")
	check_eq(t.sites[0].sizes, [1, 2] as Array[int], "a site's sizes")
	check_eq(cat.tile("rare_giant_husk").set, -1, "a rare tile has no set")
	check(cat.tile("rare_giant_husk").landmark_anchor.is_empty(), "nor an anchor")
	check(cat.tile("nowhere").is_empty(), "an unknown id")


func test_each_tile_rule_has_a_failing_variant() -> void:
	var lurker_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	lurker_data.species["lurker"] = lurker_data.species.ambush_hunter.duplicate(true)
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
		[func(f: Dictionary) -> void:
			f.drift_a.shells[5] = _shell("f", 5.0, 8.0, 1.5)
			f.drift_a.shells[4] = _shell("e", 8.0, 8.5, 1.2),
			"b0/drift_a: rule 3: Zone 'a' has", 1],
		# Rule 4: the landmark anchor.
		[func(f: Dictionary) -> void: f.sunlit_a.landmark_anchor = [0.0, -26.0], "b0/sunlit_a: rule 4: the landmark anchor [0.0, -26.0] lies beyond", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.shells[2].center = [-3.5, -23.0], "b0/sunlit_a: rule 4: the landmark collider leaves 1.61 bu to shell 'c'", 1],
		# Rule 5: the set piece.
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.asset = "rare_shell_cathedral", "b0/rare_giant_husk: rule 5: the set piece 'rare_shell_cathedral'", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.yaw_deg = 45.0, "b0/rare_giant_husk: rule 5: the set piece's yaw_deg 45.0", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.center = [0.0, -26.0], "b0/rare_giant_husk: rule 5: set-piece collider 'r0'", 1],
		[func(f: Dictionary) -> void: f.rare_giant_husk.set_piece.center = [-18.0, -18.0], "b0/rare_giant_husk: rule 5: 'a' and 'r0' overlap", 1],
		# Rule 6: sites.
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].species = "kraken", "b0/sunlit_a: rule 6: site 'b' names unknown species 'kraken'", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].sizes = [3], "b0/sunlit_a: rule 6: site 'b': sizes [3] must be some of [1, 2]", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].sizes = [], "b0/sunlit_a: rule 6: site 'b': sizes [] must be some of", 1],
		[func(f: Dictionary) -> void: f.sunlit_a.sites[1].species = "lurker", "rule 6: site 'b': 'lurker' is not an S1 species", 1, with_lurker],
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


## Static #33: growth x capacity x (0.25 + REGROW_FLOOR) <= 1.152, the unguarded M1 maximum.
func test_static_33_refuses_a_zone_that_yields_more_than_the_unguarded_m1_maximum() -> void:
	var refused := _problems(func(f: Dictionary) -> void: f.sunlit_a.zones[1].capacity = 1.16 / 0.3 / 0.08)
	_check_case(refused, "b0/sunlit_a: rule 3: zone 'b' yields 1.160 a second; static #33 allows 1.152", 1, "1.16")
	check(_problems(func(f: Dictionary) -> void: f.sunlit_a.zones[1].capacity = 48.0).is_empty(), "z_center's 48 x 0.08 x 0.30 = 1.152 passes")


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
	check_eq(ordinary[-1], {"id": "lm", "center": Vector2(0.0, -20.0), "radius": 2.0}, "the landmark collider comes last")
	check_eq(ordinary.size(), cat.tile("sunlit_a").shells.size() + 1, "the shells, then the anchor")
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		for p in [Vector2(1.5, 0.5), Vector2(-2.0, 3.0)]:
			var turned := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(p.x, 0.0, p.y)
			var mine := TileCatalog.yaw_point(p.x, p.y, yaw)
			check(absf(mine[0] - turned.x) < 1e-6 and absf(mine[1] - turned.z) < 1e-6, "yaw %s turns %s as the mesh turns: %s vs %s" % [yaw, p, mine, turned])
