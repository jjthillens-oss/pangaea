extends TestCase
## The cradle (S3 T3.4; docs/s3: spine 5.4 and 6.4, s3-sim 4.4, build plan 7.2; D-94, D-95): the
## shipped game/data/cradle_b1.json passes at sizes 3 and 4 (S3G3), the schema example reads (BP3-10),
## quadrants split the block as the home tiles do, and each rule refuses the mistake it is for: a
## shell or a reach disc in the clear disc, the ring outside it, a blocked view point, the block's
## outer edge (and no edge at a quadrant line), and the per-quadrant counts. The home block is band
## 0's (D-94's band split).

const CRADLE := "res://game/data/cradle_b1.json"
const EXAMPLE := "res://tests/fixtures/world/cradle_schema_example.json"

var species: SpeciesCatalog
var parts: PartCatalog
var kit: PlacementKit


func before_each() -> void:
	if species != null:
		return
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()
	kit = PlacementKit.load_from()


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CRADLE))


## The shipped cradle with `change` applied to its data, validated at `size`.
func _problems(change: Callable, size: int) -> PackedStringArray:
	var data := _data()
	change.call(data)
	return CradleBlock.from_dict(data).validate(species, kit, parts, size)


static func _item(list: Array, id: String) -> Dictionary:
	for item in list:
		if item.id == id:
			return item
	return {}


func _has(problems: PackedStringArray, text: String) -> bool:
	return Array(problems).any(func(p: String) -> bool: return p.contains(text))


func test_the_shipped_cradle_passes_at_sizes_3_and_4() -> void:
	var cradle := CradleBlock.load_from(CRADLE)
	check_eq(cradle.load_problems, PackedStringArray(), "it reads")
	check_eq(cradle.band, 1, "band 1")
	check_eq(cradle.validate(species, kit, parts, 3), PackedStringArray(), "size 3")
	check_eq(cradle.validate(species, kit, parts, 4), PackedStringArray(), "size 4")
	check_eq(cradle.pool_ring.caption, "Your lineage began here", "the caption (D-116)")
	check_eq(cradle.pool_ring.radius_bu, 14.0625, "the ring at the old pool's radius (D-95, BP3-14)")


func test_the_schema_example_reads() -> void:
	var example := CradleBlock.load_from(EXAMPLE)
	check_eq(example.load_problems, PackedStringArray(), "no load problems (BP3-10)")
	check_eq(example.view_point_bu, Vector2(0.0, 18.0), "the view point")
	check_eq([example.shells.size(), example.zones.size(), example.sites.size()], [1, 2, 1], "its lists")


func test_reading_refuses_wrong_keys_and_bands() -> void:
	var data := _data()
	data.erase("clear_r_bu")
	data["sunlit"] = 1
	var problems := CradleBlock.from_dict(data).load_problems
	check(_has(problems, "clear_r_bu"), "a missing key (%s)" % [problems])
	check(_has(problems, "sunlit"), "an unknown key")
	data = _data()
	data.band = 0
	check(_has(CradleBlock.from_dict(data).load_problems, "a cradle is band 1 or more"), "band 0 refused")
	data = _data()
	data.pool_ring["tint"] = "#FFFFFF"
	check(_has(CradleBlock.from_dict(data).load_problems, "tint"), "an unknown pool_ring key")
	data = _data()
	data.zones[0].id = data.shells[0].id
	check(_has(CradleBlock.from_dict(data).load_problems, "both a shell and a zone id"), "a shared id")
	check(_has(CradleBlock.load_from("res://tests/fixtures/world/no_such_cradle.json").load_problems, "not readable"), "a missing file")


func test_the_home_block_is_band_0s() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/home_b0.json"))
	check_eq(HomeBlock.from_dict(data, null, null).load_problems, PackedStringArray(), "home_b0 reads")
	data.band = 1
	check(_has(HomeBlock.from_dict(data, null, null).load_problems, "band 1 and up have a cradle"), "band 1 refused (D-94)")


func test_quadrants_are_the_home_tiles() -> void:
	check_eq(CradleBlock.quadrant_of(-0.1, -0.1), Vector2i(-1, -1), "south-west")
	check_eq(CradleBlock.quadrant_of(0.0, -5.0), Vector2i(0, -1), "x 0 is east")
	check_eq(CradleBlock.quadrant_of(-5.0, 0.0), Vector2i(-1, 0), "y 0 is south")
	check_eq(CradleBlock.quadrant_of(0.0, 0.0), Vector2i(0, 0), "the centre is (0, 0)'s")
	var cradle := CradleBlock.load_from(CRADLE)
	var tiles := cradle.as_tiles()
	check_eq(tiles.map(func(t: Dictionary) -> Vector2i: return t.quadrant), CradleBlock.QUADRANTS, "four, in row order")
	var counts := [0, 0, 0]
	for t in tiles:
		var off := Vector2(2 * t.quadrant.x + 1, 2 * t.quadrant.y + 1) * TileCatalog.HALF_TILE_BU
		for key in ["shells", "zones", "sites"]:
			counts[["shells", "zones", "sites"].find(key)] += t[key].size()
			for item in t[key]:
				var at: PackedFloat64Array = item.home if key == "sites" else item.center
				var whole: Array = cradle[key]
				var source := _item(whole, item.id)
				var abs_at: PackedFloat64Array = source.home if key == "sites" else source.center
				check(absf(at[0] + off.x - abs_at[0]) <= 1e-9 and absf(at[1] + off.y - abs_at[1]) <= 1e-9,
					"%s %s in its tile's frame (%s + %s = %s)" % [key, item.id, at, off, abs_at])
				check_eq(CradleBlock.quadrant_of(abs_at[0], abs_at[1]), t.quadrant, "%s %s in its quadrant" % [key, item.id])
		for s in t.sites:
			if not s.post_b.is_empty():
				var b: PackedFloat64Array = _item(cradle.sites, s.id).post_b.home
				check(absf(s.post_b.home[0] + off.x - b[0]) <= 1e-9 and absf(s.post_b.home[1] + off.y - b[1]) <= 1e-9,
					"site %s's second post moves with it" % s.id)
	check_eq(counts, [cradle.shells.size(), cradle.zones.size(), cradle.sites.size()], "every item in one quadrant")
	check_eq(cradle.shells[0].center, CradleBlock.load_from(CRADLE).shells[0].center, "as_tiles leaves the block as it was")


## S3G3's mutation: a shell at (8, 0) bu.
func test_a_shell_in_the_clear_disc_is_refused() -> void:
	var problems := _problems(func(d: Dictionary) -> void:
		d.shells.append({"id": "cx", "center": [8.0, 0.0], "radius": 1.0, "yaw_deg": [0.0, 360.0], "at_second_size": "keep"}), 3)
	check(_has(problems, "the clear disc: shell 'cx' lies 8.00 bu from the centre; it needs 17.00"), "refused (%s)" % [problems])


func test_a_reach_disc_in_the_clear_disc_is_refused() -> void:
	# The south-east veil moved in to 20 bu from the centre: its disc reaches inside 16.
	var problems := _problems(func(d: Dictionary) -> void: _item(d.sites, "seva").home = [12.0, -16.0], 3)
	check(_has(problems, "the clear disc at size 3: site 'seva' reach disc comes"), "refused (%s)" % [problems])
	check(not _has(_problems(func(d: Dictionary) -> void: _item(d.sites, "seva").home = [12.0, -16.0], 4), "site 'seva'"),
		"the veil is not live at 4, so not there")
	# The north-east elder Warden's union disc comes 38.4 bu from the centre: a 40 bu clear disc meets it.
	problems = _problems(func(d: Dictionary) -> void: d.clear_r_bu = 40.0, 4)
	check(_has(problems, "site 'neew' union reach disc comes 38.40 bu from the centre; it keeps 40.0 away"),
		"a two-post union disc too (%s)" % [problems])


func test_the_ring_stays_inside_the_clear_disc() -> void:
	var problems := _problems(func(d: Dictionary) -> void: d.pool_ring.radius_bu = 16.0, 3)
	check(_has(problems, "pool_ring: radius_bu 16.0 must lie in (0, clear_r_bu 16.0)"), "refused (%s)" % [problems])


func test_the_view_point_must_be_clear() -> void:
	var problems := _problems(func(d: Dictionary) -> void:
		d.shells.append({"id": "vx", "center": [0.0, 18.5], "radius": 1.0, "yaw_deg": [0.0, 360.0], "at_second_size": "keep"}), 3)
	check(_has(problems, "view_point_bu (0.0, 18.0) is not clear for the cell at size 3"), "a shell on it (%s)" % [problems])
	problems = _problems(func(d: Dictionary) -> void: d.view_point_bu = [0.0, 70.0], 3)
	check(_has(problems, "view_point_bu (0.0, 70.0) is not clear"), "outside the block")


func test_edges_are_the_blocks_outer_edges_only() -> void:
	var at := func(x: float, y: float) -> Callable:
		return func(d: Dictionary) -> void:
			d.shells.append({"id": "ex", "center": [x, y], "radius": 0.8, "yaw_deg": [0.0, 360.0], "at_second_size": "keep"})
	var outer := _problems(at.call(61.0, 0.5), 3)
	check(_has(outer, "rule 2: shell 'ex' at [61.0, 0.5] comes within 4.0 bu of the block's edge"), "the outer edge (%s)" % [outer])
	var inner := _problems(at.call(0.4, 30.0), 3)
	check(not _has(inner, "edge"), "a quadrant line is no edge (%s)" % [inner])
	var zone := _problems(func(d: Dictionary) -> void: _item(d.zones, "g1").center = [0.0, -58.0], 3)
	check(_has(zone, "rule 3: zone 'g1' at [0.0, -58.0] comes within 1.0 bu of the block's edge"), "a zone at the outer edge (%s)" % [zone])


func test_counts_hold_per_quadrant() -> void:
	# Rule 9: the north-east rammer only at 3 leaves that quadrant no prey or morsel at 4.
	var problems := _problems(func(d: Dictionary) -> void: _item(d.sites, "nera").sizes = [3], 4)
	check(_has(problems, "cradle_b1/q0_0: rule 9: a tile needs a prey or morsel site at both sizes"), "rule 9 (%s)" % [problems])
	# Rule 7: no live threat in the south-west at 3 (neither its Warden nor its elder ambush hunter).
	problems = _problems(func(d: Dictionary) -> void:
		d.sites.erase(_item(d.sites, "swwa"))
		d.sites.erase(_item(d.sites, "swea")), 3)
	check(_has(problems, "cradle_b1/q-1_-1: rule 7: a home tile needs a live threat site at size 3"), "rule 7 (%s)" % [problems])
	# D-135: a thirteenth zone in the north-west.
	problems = _problems(func(d: Dictionary) -> void:
		d.zones.append({"id": "nwx", "center": [-30.0, 60.0], "radius": 2.0, "capacity": 4.0, "growth_rate": 0.05, "at_second_size": "drop"}), 3)
	check(_has(problems, "cradle_b1/q-1_0: D-135: 9 shells, 13 zones"), "D-135 (%s)" % [problems])


## A site at a size where its species is haze (once home_block's rule 4, now the cradle's rule 6): a
## speck (a rammer of body size 1.0, entry 1) at 3 and 4 is a morsel at 3 and haze at 4.
func test_a_site_where_its_species_is_haze_is_refused() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	data.species["speck"] = data.species.rammer.duplicate(true)
	data.species.speck.body_size = 1.0
	var with_speck := SpeciesCatalog.from_dict(data)
	var cradle := _data()
	cradle.sites.append({"id": "sx", "species": "speck", "home": [-30.0, -30.0], "heading": 0.0, "sizes": [3, 4]})
	var problems := CradleBlock.from_dict(cradle).validate(with_speck, kit, parts, 3)
	check(Array(problems).has("cradle_b1: rule 6: site 'sx': 'speck' is haze at size 4, so it cannot be live there"), "%s" % [problems])
	check(not Array(problems).any(func(p: String) -> bool: return p.contains("haze at size 3")), "a morsel at 3")
