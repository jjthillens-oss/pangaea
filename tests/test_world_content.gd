extends TestCase
## The world content as one (docs/s1/s1-interfaces.md section 3.3, docs/s1/s1-core.md section 6.1):
## the fixture world loads its kit, tiles and home ring and has no problems; each check across files
## refuses the mistake it is for with one problem; the checks stay cheap (G24).

const WorldChecks := preload("res://tests/world_checks.gd")
const WORLD := "res://tests/fixtures/world/world_min.json"
const MAX_PROBLEMS_MS := 50.0

var species: SpeciesCatalog
var parts: PartCatalog


func before_each() -> void:
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()


func _content(p_species: SpeciesCatalog = null) -> WorldContent:
	return WorldContent.load_from(WORLD, PoolLayout.load_from(), p_species if p_species != null else species)


func test_the_fixture_content_has_no_problems() -> void:
	var content := _content()
	check_eq(content.problems(parts, species), PackedStringArray(), "no problems")
	check_eq(content.kit.assets.size(), 20, "the fixture kit")
	check_eq(content.tiles.tiles.size(), 20, "the fixture tiles")
	check_eq(content.home.zones.filter(func(z: Dictionary) -> bool: return not z.m1).size(), 20, "the fixture ring's zones")
	check_eq(content.tiles.rare_kinds(0), PackedStringArray(TileCatalog.RARE_KINDS_BY_BAND[0]), "both rare kinds")


## The endless gates run on the fixture world until the real tiles land, so its settings must be the
## shipped ones: only the note, the content paths and switches.growth differ. Growth is off there, so
## S1's gates on it keep S1's endless world (docs/s2/s2-build-plan.md BP-6).
func test_the_fixture_world_has_the_shipped_settings() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WORLD))
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WorldConfig.DEFAULT_PATH))
	check_eq(fixture.keys(), shipped.keys(), "the same keys in the same order")
	for key in shipped:
		if key not in ["note", "content", "switches", "sizes"]:
			check_eq(fixture[key], shipped[key], key)
	check_eq([fixture.sizes.start, fixture.sizes.max_in_build, shipped.sizes.max_in_build], [1.0, 2.0, 4.0],
		"the fixture stays at S2's top (BP3-17); the game reaches size 4 (D-89)")
	check_eq(fixture.content.keys(), shipped.content.keys(), "the same content keys")
	check(str(fixture.content.home).begins_with("res://tests/fixtures/world/"), "fixture paths")
	check_eq(fixture.switches.keys(), shipped.switches.keys(), "the same switches in the same order")
	for key in shipped.switches:
		if key not in ["growth", "landmark_return"]:
			check_eq(fixture.switches[key], shipped.switches[key], "switches." + key)
	check_eq([fixture.switches.growth, shipped.switches.growth], [false, true], "growth off in the fixture, on in the game")
	check_eq([fixture.switches.landmark_return, shipped.switches.landmark_return], [false, true],
		"the landmark return off in the size-2 fixture, on in the game (BP3-17)")


## BP3-17: a build whose top is size 2 loads band 0 only, though world_cell.json names band 1's tiles
## and cradle (the shipped world reaches size 4 from S3, D-89; this is it at a size-2 top).
func test_a_size_2_world_loads_band_0_only() -> void:
	var shipped := WorldContent.load_from(WorldChecks.shipped_world_at(2), PoolLayout.load_from(), species)
	check_eq(shipped.config.max_size_in_build, 2, "the top is size 2")
	check_eq(shipped.tiles.bands, [0] as Array[int], "band 0's tiles only")
	check_eq(shipped.cradles, {}, "no cradle")
	check_eq(shipped.problems(parts, species), PackedStringArray(), "the shipped content has no problems")


## T3.7 at the size-4 top (I-3's flip): bands 0 and 1 load with band 1's cradle, and the content has
## no problems at sizes 1 to 4 (every size, the cradle, band 1's fixed rare kind, the B-6 bound).
## D-108: a band's place kinds are its rare kinds and landmark models, 2 + 6 in band 0, 4 + 6 in 1.
func test_the_size_4_world_has_no_problems_and_its_place_kinds() -> void:
	var content := WorldContent.load_from(WorldChecks.shipped_world_at(4), PoolLayout.load_from(), species)
	check_eq(content.tiles.bands, [0, 1] as Array[int], "bands 0 and 1")
	check_eq(content.cradles.keys(), [1], "band 1's cradle")
	check_eq(content.problems(parts, species), PackedStringArray(), "no problems at sizes 1 to 4")
	check_eq(content.place_kinds(0).size(), 8, "band 0: 2 rare kinds and 6 landmark models (%s)" % [content.place_kinds(0)])
	check_eq(content.place_kinds(1).size(), 10, "band 1: 4 rare kinds and 6 landmark models (%s)" % [content.place_kinds(1)])
	for band in [0, 1]:
		var kinds := Array(content.place_kinds(band))
		var sorted := kinds.duplicate()
		sorted.sort()
		check_eq(kinds, sorted, "band %d sorted" % band)
		for kind in content.tiles.rare_kinds(band):
			check(kinds.has(kind), "band %d holds rare kind %s" % [band, kind])
	check(not Array(content.place_kinds(1)).has("giant_husk"), "no band-0 kind in band 1")


## S3G42c (BP3-8): landmark_find_tm + 4 + D(max_in_build) < rings_tm.load, D = respawn_clear_m + the
## cell's radius + 2 x reach_max_threat. At size 4 that is 6 + 4 + 39.1, under 56 and over 48.
func test_the_landmark_pass_stays_inside_the_load_ring() -> void:
	var content := WorldContent.load_from(WorldChecks.shipped_world_at(4), PoolLayout.load_from(), species)
	content.config.rings.load = 48.0
	var problems := content.problems(parts, species)
	check_has_error(problems, "world_cell.rings_tm.load: landmark_find_tm + 4 + D at size 4 (6.00 + 4 + 39.11) must be below it (48.00)")
	content.config.switches.landmark_return = false
	check(not Array(content.problems(parts, species)).any(func(p: String) -> bool: return p.contains("landmark_find_tm")),
		"no landmark pass, no bound")


func test_an_unknown_fixed_rare_kind_is_a_problem() -> void:
	var content := _content()
	content.config.arrangement.fixed_rare.kind = "kraken_shell"
	var problems := content.problems(parts, species)
	check_eq(problems.size(), 1, "one problem: %s" % [problems])
	check_has_error(problems, "world_cell.arrangement.fixed_rare.kind: 'kraken_shell'")
	# A kind the tiles do not hold is refused even when it is a kind of the kit.
	var tiles := content.tiles
	for id in tiles.tiles.keys():
		if tiles.tiles[id].rare == "giant_husk":
			tiles.tiles.erase(id)
	content.config.arrangement.fixed_rare.kind = "giant_husk"
	check_has_error(content.problems(parts, species), "world_cell.arrangement.fixed_rare.kind: 'giant_husk'")


## C-13: its drop points depend on the zones loaded, so on the route; pool mode keeps it.
func test_an_enabled_interim_supply_is_refused_in_endless_mode() -> void:
	var content := _content()
	content.layout.carrion.interim_supply.enabled = true
	var problems := content.problems(parts, species)
	check_eq(problems.size(), 1, "one problem: %s" % [problems])
	check_has_error(problems, "layout.carrion.interim_supply.enabled")
	content.config = content.config.with_mode("pool")
	check_eq(content.problems(parts, species), PackedStringArray(), "not refused with with_mode(\"pool\")")


func test_a_camera_that_does_not_match_the_rings_is_a_problem() -> void:
	for change in [["zoom_max", 25.0], ["pitch_deg", 50.0], ["fov_deg", 40.0]]:
		var content := _content()
		content.layout.camera[change[0]] = change[1]
		var problems := content.problems(parts, species)
		check_eq(problems.size(), 1, "%s %s: one problem: %s" % [change[0], change[1], problems])
		check_has_error(problems, "layout.camera.%s" % change[0])
	var wide := SpeciesCatalog.load_from()
	wide.fairness.spawn_view_aspect = 16.0 / 9.0
	var problems := _content(wide).problems(parts, wide)
	check_eq(problems.size(), 1, "aspect 16:9: one problem: %s" % [problems])
	check_has_error(problems, "species.fairness.spawn_view_aspect")


## Each part's problems come through, in the pinned order: the world file, the kit, the tiles, the
## home block, then the checks across files.
func test_problems_come_in_the_pinned_order() -> void:
	var content := _content()
	content.config.caps.awake = 0
	content.kit.assets.rock_a.yaw_rule = "spin"
	content.tiles.tiles.sunlit_a.zones[0].growth_rate = 0.5
	content.home.zones.filter(func(z: Dictionary) -> bool: return not z.m1)[0].radius = 7.0
	content.config.arrangement.fixed_rare.kind = "kraken_shell"
	content.layout.camera.zoom_max = 25.0
	content.config.local_bound_tm = 240.0
	var problems := content.problems(parts, species)
	var expected := ["world_cell.caps.awake", "placement_kit.assets[", "b0/sunlit_a: ", "home_min: rule 3",
		"world_cell.arrangement.fixed_rare.kind", "layout.camera.zoom_max", "world_cell.origin.local_bound_tm"]
	check_eq(problems.size(), expected.size(), "one problem each: %s" % [problems])
	for i in mini(problems.size(), expected.size()):
		check(problems[i].begins_with(expected[i]), "problem %d '%s' begins '%s'" % [i, problems[i], expected[i]])


## D-70: problems() checks the tiles, then the home block, at every size the build runs (size_start
## to max_size_in_build), so a rule broken only at size 2 is a problem; one broken alike at both sizes
## is listed once.
func test_problems_check_every_size() -> void:
	var content := _content()
	# sunlit_b is of set 1, which keeps a threat at size 2 (TileCatalog's rule 7).
	var t: Dictionary = content.tiles.tiles.sunlit_b
	t.sites = t.sites.filter(func(s: Dictionary) -> bool: return s.id != "er")
	var site: Dictionary = content.home.sites.filter(func(s: Dictionary) -> bool: return s.id == "terr_n_a")[0]
	var zone: Dictionary = content.home.zones.filter(func(z: Dictionary) -> bool: return z.id == site.territory_zone)[0]
	zone.at_second_size = "drop"
	var tile_2 := "b0/sunlit_b: rule 7: a sunlit tile needs a live threat site at size 2"
	var home_2 := "home_min: rule 5 at size 2: site '%s' territory_zone '%s' is dropped at size 2"
	check_eq(content.tiles.validate(species, content.kit, parts, 1), PackedStringArray(), "the tiles pass at size 1")
	check_eq(content.home.validate(species, content.kit, parts, 1), PackedStringArray(), "the home block passes at size 1")
	var problems := content.problems(parts, species)
	print("test-world-content: at size 2 only: %s" % [problems])
	# Both of z_n's rammers name it.
	check_eq(problems, PackedStringArray([tile_2, home_2 % ["terr_n_a", zone.id], home_2 % ["terr_n_b", zone.id]]),
			"the tile's, then the home block's")
	# A size-free problem is the same at both sizes and listed once, where it first came; the tiles at
	# every size come before the home block at any.
	content = _content()
	content.tiles.tiles.sunlit_a.zones[0].growth_rate = 0.5
	content.tiles.tiles.sunlit_b.sites = content.tiles.tiles.sunlit_b.sites.filter(
			func(s: Dictionary) -> bool: return s.species != "elder_rammer")
	content.home.zones.filter(func(z: Dictionary) -> bool: return not z.m1)[0].radius = 7.0
	var free := content.tiles.validate(species, content.kit, parts, 1)
	check_eq(free.size(), 1, "the size-free tile problem at size 1: %s" % [free])
	check(free.size() == 1 and content.tiles.validate(species, content.kit, parts, 2).has(free[0]), "and again at size 2")
	problems = content.problems(parts, species)
	var expected := ["b0/sunlit_a: ", "b0/sunlit_b: rule 7: a sunlit tile needs a live threat site at size 2", "home_min: rule 3"]
	check_eq(problems.size(), expected.size(), "one problem each: %s" % [problems])
	for i in mini(problems.size(), expected.size()):
		check(problems[i].begins_with(expected[i]), "problem %d '%s' begins '%s'" % [i, problems[i], expected[i]])


## B-6: rebase_beyond + hold + reach_max + chunk_tm x sqrt 2 stays below the local bound. reach_max
## is the largest reach disc of a site live at size 1, tiles and home block alike; a bound just above
## the sum passes and one at it fails (the world file's own rule 6 passes both, 237.25 < 240).
func test_the_local_bound_covers_a_held_creatures_reach() -> void:
	var content := _content()
	var reach := content.reach_max(species)
	print("test-world-content: reach_max %.2f tm at %s" % [reach.radius_tm, reach.where])
	check_eq([reach.radius_tm, reach.where], [11.0, "home_min site 'terr_n_a'"], "the M1 rammer guarding z_n: 6 + 2 + 3 tm")
	var at := 96.0 + 96.0 + float(reach.radius_tm) + 32.0 * sqrt(2.0)
	content.config.local_bound_tm = at
	var problems := content.problems(parts, species)
	check_eq(problems.size(), 1, "one problem at the sum: %s" % [problems])
	check_has_error(problems, "world_cell.origin.local_bound_tm: rebase_beyond_tm + hold + reach_max + chunk_tm x sqrt 2 (%.2f)" % at)
	check_has_error(problems, "reach_max is %.2f tm, %s" % [reach.radius_tm, reach.where])
	content.config.local_bound_tm = at + 0.01
	check_eq(content.problems(parts, species), PackedStringArray(), "a hundredth above it passes")
	# A wider leash on a tile's site raises reach_max to that site.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	data.species.ambush_hunter.leash_m = float(data.species.ambush_hunter.leash_m) + 8.0
	var wider := content.reach_max(SpeciesCatalog.from_dict(data))
	check(float(wider.radius_tm) > float(reach.radius_tm) and str(wider.where).contains("site"), "a wider leash, %s" % [wider])


## S2G36 (D-69, D-82): reach_max builds each live site's disc as its brain has it at the size: the
## species' lengths times k_of(entry size, n), over the union of both posts for a two-post site, then
## times bu_to_tm(n). With every other site gone, the one site's disc is reach_max.
func test_reach_max_takes_k_and_the_union_at_each_size() -> void:
	var lurker := {"species": "lurker", "x": -40.0, "y": -44.0, "territory_zone": ""}
	var elder := {"species": "elder_rammer", "x": 34.0, "y": -44.0, "territory_zone": "ea"}
	var post_b := {"home": [46.0, -44.0], "heading": 0.0, "territory_zone": "eb"}
	var cases := [
		# [the site's changes, reach_max in tm, why]
		[lurker.merged({"sizes": [2]}), 9.0, "the Lurker at size 2: leash 9 x k 1.6 = 14.4 bu, x 0.625"],
		[lurker.merged({"sizes": [1, 2]}), 9.0, "listed at size 1 too, below its entry size: only size 2 counts"],
		[lurker.merged({"sizes": [1]}), 0.0, "never live: no disc"],
		[elder.merged({"sizes": [2]}), 7.5, "the elder rammer on zone ea (r 4): 4 + (2 + 3) x 1.6 = 12 bu, x 0.625"],
		[elder.merged({"sizes": [2], "post_b": post_b}), 11.25, "both posts, 12 bu apart: the union's r (12 + 12 + 12) / 2 = 18 bu, x 0.625"],
		[elder.merged({"sizes": [2], "post_b": post_b.merged({"territory_zone": "ez"}, true)}), 0.0,
			"post b's zone is not the block's: the validators refuse the site, so it is skipped"],
		[elder.merged({"species": "rammer", "sizes": [2]}, true), 5.625, "the M1 rammer at size 2: k 1, 4 + 2 + 3 = 9 bu, x 0.625"],
		[elder.merged({"species": "rammer", "sizes": [1, 2]}, true), 9.0, "and at sizes 1 and 2: 9 tm at size 1"],
	]
	for c in cases:
		var content := _alone_at_home(c[0])
		var reach := content.reach_max(species)
		check_near(float(reach.radius_tm), c[1], 1e-9, "%s: %s" % [c[2], reach])
		check_eq(reach.where, "home_min site 're'" if c[1] > 0.0 else "", "%s: where" % c[2])
	# A tile's two-post site: post b's territory is its own zone's.
	var content := _alone_at_home({"species": "rammer", "x": 0.0, "y": 0.0, "territory_zone": "", "sizes": []})
	var t: Dictionary = content.tiles.tiles.reef_a
	t.zones.append({"id": "ta", "center": PackedFloat64Array([-6.0, 0.0]), "radius": 4.0})
	t.zones.append({"id": "tb", "center": PackedFloat64Array([6.0, 0.0]), "radius": 4.0})
	var site := {"id": "te", "species": "elder_rammer", "home": PackedFloat64Array([-6.0, 0.0]), "heading": 0.0,
		"territory_zone": "ta", "sizes": [2], "post_b": {"home": PackedFloat64Array([6.0, 0.0]), "heading": 0.0, "territory_zone": "tb"}}
	t.sites.append(site)
	var reach := content.reach_max(species)
	check_near(float(reach.radius_tm), 11.25, 1e-9, "a tile's two-post elder: %s" % [reach])
	check_eq(reach.where, "b0/reef_a site 'te'", "on the tile")
	t.zones[-1].radius = 6.0
	check_near(float(content.reach_max(species).radius_tm), (12.0 + 12.0 + 14.0) / 2.0 * 0.625, 1e-9,
		"post b's zone r 6 widens its disc to 14 bu: the union (12 + 12 + 14) / 2 bu")
	t.sites[-1].post_b = {}
	check_near(float(content.reach_max(species).radius_tm), 7.5, 1e-9, "one post: post a's disc alone")


## S2G36: the B-6 bound takes reach_max's union: a two-post elder rammer of 11.25 tm, above the M1
## rammer's 11 tm, sets it.
func test_the_local_bound_takes_a_two_post_sites_union() -> void:
	var content := _content()
	_add_zones(content)
	content.home.sites.append({"id": "re", "species": "elder_rammer", "x": 34.0, "y": -44.0, "heading": 0.0,
		"territory_zone": "ea", "sizes": [2], "m1": false, "post_b": {"home": [46.0, -44.0], "heading": 0.0, "territory_zone": "eb"}})
	var reach := content.reach_max(species)
	check_eq([reach.radius_tm, reach.where], [11.25, "home_min site 're'"], "the union sets reach_max")
	var at := 96.0 + 96.0 + 11.25 + 32.0 * sqrt(2.0)
	content.config.local_bound_tm = at
	check_has_error(content.problems(parts, species), "world_cell.origin.local_bound_tm: rebase_beyond_tm + hold + reach_max + chunk_tm x sqrt 2 (%.2f)" % at)
	content.config.local_bound_tm = at + 0.01
	for p in content.problems(parts, species):
		check(not p.begins_with("world_cell.origin.local_bound_tm"), "a hundredth above it passes: %s" % p)


## The fixture content with every site gone but one ring site 're' made of `changes` (zones ea and eb,
## r 4, 12 bu apart, added to the block).
func _alone_at_home(changes: Dictionary) -> WorldContent:
	var content := _content()
	for id in content.tiles.tiles:
		content.tiles.tiles[id].sites = []
	content.home.sites.clear()
	_add_zones(content)
	content.home.sites.append({"id": "re", "heading": 0.0, "m1": false, "post_b": {}}.merged(changes, true))
	return content


func _add_zones(content: WorldContent) -> void:
	for z in [["ea", 34.0], ["eb", 46.0]]:
		content.home.zones.append({"id": z[0], "x": z[1], "y": -44.0, "radius": 4.0, "capacity": 8, "growth_rate": 1.0,
			"at_second_size": "keep", "m1": false})


## BP-4: at every size the build runs, the widest collider (a tile's shells, landmark and set piece
## colliders, the home block's circles) is no wider than chunk_tm - 2 x wedge_tm, so every collider
## that can touch the growth tick's bounded spiral lies in its 3 x 3 chunks. At the limit it passes;
## a hundredth past it, it fails once.
func test_the_largest_shell_rule() -> void:
	var content := _content()
	var at_1 := content.largest_shell(1)
	check_eq([at_1.radius_tm, at_1.where], [3.0, "b0/rare_giant_husk 'r0'"], "the husk's collider at size 1")
	var at_2 := content.largest_shell(2)
	check_eq([at_2.radius_tm, at_2.where], [1.875, "b0/rare_giant_husk 'r0'"], "x 0.625 at size 2")
	content.config.growth.wedge_tm = (32.0 - 3.0) / 2.0
	check_eq(content.problems(parts, species), PackedStringArray(), "at the limit")
	content.config.growth.wedge_tm += 0.005
	var problems := content.problems(parts, species)
	check_eq(problems.size(), 1, "one problem past it: %s" % [problems])
	check_has_error(problems, "b0/rare_giant_husk 'r0': BP-4: radius 3.00 tm at size 1; every shell keeps <= chunk_tm - 2 x wedge_tm (2.99 tm)")
	# Each kind of collider counts, at the size it exists.
	content = _content()
	var t: Dictionary = content.tiles.tiles.reef_a
	t.shells[0].radius = 4.0
	t.shells[0].at_second_size = "sink"
	check_eq(content.largest_shell(1), {"radius_tm": 4.0, "where": "b0/reef_a '%s'" % t.shells[0].id}, "a tile's shell")
	check_eq(content.largest_shell(2).where, "b0/rare_giant_husk 'r0'", "sunk at size 2")
	t.shells[0].at_second_size = "keep"
	check_eq(content.largest_shell(2), {"radius_tm": 2.5, "where": "b0/reef_a '%s'" % t.shells[0].id}, "kept at size 2")
	var ring := content.home.shells[-1]
	ring.r = 6.0
	check_eq(content.largest_shell(1), {"radius_tm": 6.0, "where": "home_min '%s'" % ring.id}, "a home ring shell")
	check_eq(content.largest_shell(2), {"radius_tm": 3.75, "where": "home_min '%s'" % ring.id}, "kept at size 2")
	ring.at_second_size = "sink"
	check_eq(content.largest_shell(2).where, "b0/reef_a '%s'" % t.shells[0].id, "a sunk ring shell is gone at size 2")
	content.kit.collide_radius_bu = 7.0
	check_eq(content.largest_shell(1), {"radius_tm": 7.0, "where": "b0/drift_a 'lm'"}, "a landmark collider (the first tile with an anchor)")
	content.home.band = 1
	for id in content.tiles.tiles:
		content.tiles.tiles[id].band = 1
	check_eq(content.largest_shell(1), {"radius_tm": 0.0, "where": ""}, "band 1's content is not at size 1")


func test_a_broken_world_file_gives_its_own_problems_alone() -> void:
	var content := WorldContent.load_from("res://tests/fixtures/world/no_such_world.json", PoolLayout.load_from(), species)
	var problems := content.problems(parts, species)
	check_eq(problems.size(), 1, "one problem: %s" % [problems])
	check_has_error(problems, "no_such_world.json")
	check(content.kit != null and content.tiles != null and content.home != null, "never null parts")


func test_problems_take_at_most_50_ms() -> void:
	var content := _content()
	var best := INF
	for i in 3:
		var t0 := Time.get_ticks_usec()
		var problems := content.problems(parts, species)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		check(problems.is_empty(), "no problems")
	print("test-world-content: problems() fastest of 3 is %.1f ms (limit %.0f ms)" % [best, MAX_PROBLEMS_MS])
	check(best <= MAX_PROBLEMS_MS, "problems() takes %.1f ms" % best)
