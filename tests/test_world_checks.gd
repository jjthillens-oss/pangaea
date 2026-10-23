extends TestCase
## The endless world's heavy checks (tests/world_checks.gd; docs/s1/s1-interfaces.md 4.2,
## docs/s1/s1-core.md 6.7, docs/s1/s1-build-plan.md B-13 and B-29): each refuses the case it is for
## and passes its control.

const WorldChecks := preload("res://tests/world_checks.gd")
const ReachGrid := preload("res://tests/reach_grid.gd")
const BOUNDS := Rect2(-16.0, -16.0, 32.0, 32.0)
## A ring of 8 pillars r 0.9 on a 3.4 bu circle, as the shell cathedral's: the gaps between them
## (0.80 bu) are narrower than a cell, so the nave inside (r <= 2.5) is a sealed pocket.
const POCKET := Vector2(6.0, -5.0)


## The pillars round POCKET, as ChunkArena circles.
static func _pillars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in 8:
		out.append({"id": "p%d" % k, "center": POCKET + Vector2.from_angle(k * TAU / 8.0) * 3.4, "radius": 0.9})
	return out


## Zones that leave no open point of BOUNDS outside the pocket more than a few tm from food.
static func _zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in [Vector2(-8.0, -8.0), Vector2(-8.0, 8.0), Vector2(8.0, 8.0), Vector2(-1.0, 0.0), Vector2(12.0, -12.0)]:
		out.append({"id": "z%d" % out.size(), "center": c, "radius": 4.0})
	return out


## B-29: the reach rule measures the sea the border reaches; an empty sealed pocket is legal.
func test_an_empty_sealed_pocket_passes_the_reach_rule() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var grid = ReachGrid.over(arena, _zones(), BOUNDS, PoolLayout.CELL_RADIUS)
	var inside: int = grid.index_near(POCKET)
	var from_border: PackedFloat32Array = grid.distances_from(grid.border_points())
	check(grid.open[inside] == 1 and not is_finite(from_border[inside]), "the nave is open water the border cannot reach")
	var labels: PackedInt32Array = grid.components()
	check(labels[inside] != labels[grid.border_points()[0]], "and it is a component of its own")
	var outside := {}
	for i in grid.border_points():
		outside[labels[i]] = true
	var differ := 0
	for i in grid.open.size():
		if grid.open[i] == 1 and is_finite(from_border[i]) != outside.has(labels[i]):
			differ += 1
	check_eq(differ, 0, "the labels give the border's reach exactly, at points the distance pass reaches")
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3), PackedStringArray(), "the pocket is empty, so the sea passes")


## A pocket holding food is a problem: a cell outside can never reach it.
func test_a_sealed_pocket_holding_a_zone_fails() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var zones := _zones()
	zones.append({"id": "nave", "center": POCKET, "radius": 1.0})
	var problems := WorldChecks.reach_problems(arena, zones, BOUNDS, 16.3)
	check_eq(problems.size(), 1, "one problem: %s" % [problems])
	check(problems.size() == 1 and problems[0].begins_with("reach: ") and problems[0].ends_with("zone points around (6.0, -5.0) lie in a sealed pocket"),
		"the food in the pocket, named by its centre: %s" % [problems])


## must_reach (site homes, the spawn): a point in the pocket or under a collider fails; one in the
## open sea passes.
func test_a_must_reach_point_in_a_sealed_pocket_fails() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var outside: Array[Vector2] = [Vector2(-10.0, 10.0), Vector2(0.0, 0.0)]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, outside), PackedStringArray(), "homes in the sea pass")
	var inside: Array[Vector2] = [Vector2(-10.0, 10.0), POCKET]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, inside),
		PackedStringArray(["reach: (6.0, -5.0) must be reached but lies in a sealed pocket or under a collider"]), "a home in the nave")
	var under: Array[Vector2] = [POCKET + Vector2(3.4, 0.0)]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, under),
		PackedStringArray(["reach: (9.4, -5.0) must be reached but lies in a sealed pocket or under a collider"]), "a home under a pillar")


## The border-connected sea still has to reach food within the budget and stay one sea.
func test_the_sea_outside_still_meets_the_budget_and_stays_connected() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var far: Array[Dictionary] = [{"id": "z", "center": Vector2(-12.0, -12.0), "radius": 3.0}]
	var problems := WorldChecks.reach_problems(arena, far, BOUNDS, 16.3)
	check(problems.size() == 1 and problems[0].contains("tm from food; the budget is 16.3 tm"), "one zone in a corner is too far: %s" % [problems])
	# A wall of touching shells across the bounds cuts the sea in two; each half has food.
	var wall: Array[Dictionary] = []
	for k in 17:
		wall.append({"id": "w%d" % k, "center": Vector2(-16.0 + 2.0 * k, 3.0), "radius": 1.0})
	var split := WorldChecks.reach_problems(ChunkArena.from_shells(wall), _zones(), BOUNDS, 16.3)
	check(split.size() == 1 and split[0].contains("are cut off from"), "the far half is cut off: %s" % [split])


## B-13: zone_points() buckets zones on an 8 bu grid and finds exactly the points the plain loop over
## every zone finds, in the same order, for zones that straddle buckets on both sides of 0.
func test_bucketed_zone_points_equal_the_plain_loop() -> void:
	var zones: Array[Dictionary] = []
	for k in 40:
		var c := Vector2(-25.0 + fposmod(k * 7.3, 50.0), -25.0 + fposmod(k * 11.9, 50.0))
		zones.append({"id": "z%d" % k, "center": c, "radius": 2.0 + fposmod(k * 1.7, 6.0)})
	var arena := ChunkArena.from_shells(_pillars())
	var grid = ReachGrid.over(arena, zones, Rect2(-24.0, -24.0, 48.0, 48.0), PoolLayout.CELL_RADIUS)
	var plain := PackedInt32Array()
	for i in grid.open.size():
		if grid.open[i] == 0:
			continue
		for z in zones:
			if grid.point(i).distance_to(z.center) <= z.radius:
				plain.append(i)
				break
	check(plain.size() > 1000, "the zones cover %d points" % plain.size())
	check_eq(grid.zone_points(), plain, "the same points in the same order")


## components() joins open points by the same 8 moves distances_from takes, so a diagonal-only link
## joins: on a 3 x 3 grid open along its diagonal, one component, which a distance pass crosses too.
func test_components_join_what_distances_from_reaches() -> void:
	var grid = ReachGrid.new()
	grid.size = 3
	grid.rows = 3
	grid.open = PackedByteArray([1, 0, 0, 0, 1, 0, 0, 0, 1])
	check_eq(grid.components(), PackedInt32Array([0, -1, -1, -1, 0, -1, -1, -1, 0]), "one component along the diagonal")
	check(is_finite(grid.distances_from(PackedInt32Array([0]))[8]), "the corner reaches the far corner")


# --- orientations (B-16) ---

const WORLD := "res://tests/fixtures/world/world_min.json"


func _content() -> WorldContent:
	return WorldContent.load_from(WORLD, PoolLayout.load_from(), SpeciesCatalog.load_from())


## An oriented copy puts every collider where WorldGen puts it: the identity-frame centre through
## orient_point. The fixture cathedral's colliders are not symmetric, so its mirrored copies show
## that the piece is mirrored in its own x before it turns.
func test_oriented_tiles_put_their_colliders_where_world_gen_does() -> void:
	var content := _content()
	var bad := 0
	for id in content.tiles.tiles:
		var t: Dictionary = content.tiles.tiles[id]
		var base := TileCatalog.colliders_of(t, content.kit)
		for o in 8:
			var turned := TileCatalog.colliders_of(WorldChecks.oriented_tile(t, o), content.kit)
			for k in base.size():
				var want := WorldGen.orient_point(base[k].center.x, base[k].center.y, o)
				if turned[k].id != base[k].id or turned[k].center.distance_to(Vector2(want[0], want[1])) > 1e-5:
					bad += 1
					if bad <= 5:
						check(false, "%s o%d %s at %s, WorldGen %s" % [id, o, base[k].id, turned[k].center, want])
	check_eq(bad, 0, "colliders off where WorldGen puts them")
	var cathedral := WorldChecks.oriented_tile(content.tiles.tiles.rare_shell_cathedral, 4)
	check_eq([cathedral.where, cathedral.set_piece.mirror, cathedral.set_piece.yaw_deg], ["b0/rare_shell_cathedral@o4", true, 270.0],
		"o4 mirrors, and the yaw 90 becomes -90, kept as 270")


func test_orientation_problems_pass_the_fixture_in_all_eight_orientations() -> void:
	var content := _content()
	var species := SpeciesCatalog.load_from()
	check_eq(WorldChecks.orientation_problems(content, species, PartCatalog.load_from(), 1), PackedStringArray(), "rules 2 to 8 in every orientation")


## A tile problem is named once per orientation, with the orientation; a band-wide problem (drift_f
## gone, so rule 1's counts fail) is the same in every orientation and is given once.
func test_orientation_problems_name_the_tile_and_orientation() -> void:
	var content := _content()
	content.tiles.tiles.sunlit_a.shells[0].center = PackedFloat64Array([-27.0, -8.0])
	content.tiles.tiles.erase("drift_f")
	var species := SpeciesCatalog.load_from()
	var parts := PartCatalog.load_from()
	var band := Array(content.tiles.validate(species, content.kit, parts, 1)).filter(func(p: String) -> bool: return p.begins_with("tiles b0: "))
	check(band.size() > 0, "drift_f's absence breaks rule 1: %s" % [band])
	var problems := WorldChecks.orientation_problems(content, species, parts, 1, PackedInt32Array([0, 3, 6]))
	var tile := Array(problems).filter(func(p: String) -> bool: return p.begins_with("b0/"))
	check_eq(tile.size(), 3, "one tile problem per orientation: %s" % [problems])
	for i in mini(tile.size(), 3):
		check(tile[i].begins_with("b0/sunlit_a@o%d: rule 2: shell 'a' at " % [0, 3, 6][i]), tile[i])
	check_eq(problems.size(), tile.size() + band.size(), "and each band-wide problem once: %s" % [problems])
	for p in band:
		check_eq(Array(problems).count(p), 1, p)


# --- the food bound ---

## A tile with one zone, laid flat for food_bound (no shells, sites or anchor).
static func _food_tile(id: String, center: Vector2, capacity: float) -> Dictionary:
	return {"id": id, "where": "b0/" + id, "band": 0, "region": "sunlit", "set": 0, "rare": "", "shells": [], "sites": [],
		"zones": [{"id": "a", "center": PackedFloat64Array([center.x, center.y]), "radius": 2.0, "capacity": capacity, "growth_rate": 0.01, "at_second_size": "keep"}],
		"landmark_anchor": PackedFloat64Array(), "set_piece": {}}


## Two tiles: X holds 960 energy at its centre, 120 units, which food_per_zone caps at 12 items; Y
## holds 3 items 28 bu east of its centre (so 28 bu off in every orientation). The food ring is 52 tm and zones are r 2, so a slot counts a zone within 54.
## Away from the home: a point near a tile corner has X within 54 in the four slots round that
## corner (4 x 12 = 48), and no Y elsewhere comes near; the first such point in the scan is
## (-30, -30). With the home block holding five 12-item zones at block (62, 62), the worst lies in
## tile (1, 1), south-east of the block, at (14, -18): the block's 60, X in the centre, north and
## east slots (36) and Y in the west and north-east slots (6), 102. Both answers were computed again
## by a separate brute force in Python over the same grid and slots.
func test_food_bound_finds_the_worst_point_of_a_fixture() -> void:
	var content := _content()
	var cat := TileCatalog.new()
	cat.bands = [0]
	cat.tiles = {"x": _food_tile("x", Vector2.ZERO, 960.0), "y": _food_tile("y", Vector2(28.0, 0.0), 24.0)}
	content.tiles = cat
	var none: Array[Dictionary] = []
	content.home.zones = none
	var away := WorldChecks.food_bound(content, 4.0)
	check_eq([away.worst, away.at, away.home], [48, Vector2(-30.0, -30.0), false], "away from the home")
	var corner: Array[Dictionary] = []
	for k in 5:
		corner.append({"id": "c%d" % k, "x": 62.0, "y": 62.0, "radius": 2.0, "capacity": 96.0, "growth_rate": 0.01, "at_second_size": "keep", "m1": false})
	content.home.zones = corner
	var home := WorldChecks.food_bound(content, 4.0)
	check_eq([home.worst, home.at, home.home, home.tile], [102, Vector2(14.0, -18.0), true, Vector2i(1, 1)], "south-east of the home block")


## The fixture world's bound at 4 tm, printed for the record and held to caps.food_items.
func test_food_bound_on_the_fixture_world_stays_within_the_food_cap() -> void:
	var content := _content()
	var t0 := Time.get_ticks_msec()
	var bound := WorldChecks.food_bound(content, 4.0)
	print("test-world-checks: fixture food bound %d at %s (home %s, tile %s), cap %d, %d ms" % [bound.worst, bound.at, bound.home,
		bound.tile, content.config.caps.food_items, Time.get_ticks_msec() - t0])
	check(int(bound.worst) > 0 and int(bound.worst) <= int(content.config.caps.food_items), "worst %d <= %d" % [bound.worst, content.config.caps.food_items])


# --- the site sample (B-17) ---

## The live sites at size 1 whose reach discs meet the 40 tm disc round `c`, over every chunk of
## `gen` within 104 tm (40 + 2 x the fixture's reach_max of 11, and more).
static func _brute_sites(gen: WorldGen, c: Vector2) -> int:
	var count := 0
	for ky in range(floori((c.y - 104.0) / 32.0), floori((c.y + 104.0) / 32.0) + 1):
		for kx in range(floori((c.x - 104.0) / 32.0), floori((c.x + 104.0) / 32.0) + 1):
			for s in gen.chunk(1, kx, ky).sites:
				if s.sizes.has(1) and c.distance_to(Vector2(s.reach.x, s.reach.y)) < 40.0 + float(s.reach.radius):
					count += 1
	return count


## 1 arrangement x 50 discs on the fixture world, and four by the home block: each count equals a
## brute-force count over every chunk within 104 tm, from a fresh generator. At (50.95, -22) the
## home site terr_n_a's reach disc (centre (0, -22), r 11) meets the disc while its home's chunk
## (-1, -1) lies wholly beyond it: the case the 2 x reach_max margin is for.
func test_sample_sites_counts_reach_discs_over_a_40_tm_disc() -> void:
	var content := _content()
	var species := SpeciesCatalog.load_from()
	var gen := WorldGen.create(content, species, 77)
	var fresh := WorldGen.create(content, species, 77)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var centres: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(30.0, -20.0), Vector2(-70.0, 64.0), Vector2(50.95, -22.0)]
	for i in 50:
		centres.append(Vector2(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-1000.0, 1000.0)))
	var worst := 0
	var bad := 0
	var total := 0
	var wants := []
	for c in centres:
		var got := WorldChecks.sample_sites(gen, 0, 1, PackedFloat64Array([c.x, c.y]))
		var want := _brute_sites(fresh, c)
		wants.append(want)
		total += want
		worst = maxi(worst, got)
		if got != want:
			bad += 1
			check(false, "disc at %s: %d, brute force %d" % [c, got, want])
	print("test-world-checks: sample of %d discs at seed 77: worst %d, %d sites met in all" % [centres.size(), worst, total])
	check_eq(bad, 0, "discs whose count differs")
	check(total > centres.size(), "the discs meet sites (%d)" % total)
	check_eq(WorldChecks.sample_sites(gen, 1, 1, PackedFloat64Array([0.0, 0.0])), -1, "a band that is not the size's")
	# Another generator drops the cache: at the first sampled disc where seed 78 meets another count
	# than seed 77, seed 78's sample is its own brute force, and so is 77's again after it.
	var other := WorldGen.create(content, species, 78)
	var other_fresh := WorldGen.create(content, species, 78)
	var k := 0
	var want_other := _brute_sites(other_fresh, centres[0])
	while k < centres.size() - 1 and want_other == wants[k]:
		k += 1
		want_other = _brute_sites(other_fresh, centres[k])
	check(want_other != wants[k], "a disc where the seeds differ (%d: %d against %d)" % [k, want_other, wants[k]])
	var at := PackedFloat64Array([centres[k].x, centres[k].y])
	check_eq(WorldChecks.sample_sites(other, 0, 1, at), want_other, "seed 78 after seed 77's cache")
	check_eq(WorldChecks.sample_sites(gen, 0, 1, at), wants[k], "and seed 77 after seed 78's")


# --- the seams (G4) ---

## The fixture world with only sunlit_a and drift_a, after `change` edits their data.
func _pair(change: Callable) -> WorldContent:
	var content := _content()
	var cat := TileCatalog.new()
	cat.bands = [0]
	cat.tiles = {"sunlit_a": content.tiles.tiles.sunlit_a, "drift_a": content.tiles.tiles.drift_a}
	change.call(cat.tiles)
	content.tiles = cat
	return content


func test_seam_problems_pass_the_fixture_at_identity() -> void:
	var content := _content()
	check_eq(WorldChecks.seam_problems(content, SpeciesCatalog.load_from(), PartCatalog.load_from(), 1, PackedInt32Array([0])), PackedStringArray(),
		"every pair at o0, and the home edges")


## sunlit_a's rammer territory moved to its east edge (its disc reaches x 31.4) and drift_a's shell
## 'f' to its west edge: east of sunlit_a, the shell lies 0.5 bu from the rammer's leash circle. The
## same with the territory at the north edge and at the north-east corner (f 10.1 bu from the
## territory's centre along the diagonal). Both turned half round (o2), the rammer's disc lies at
## sunlit_a's west edge, so the pair meets with drift_a west of it: the site is on the far side of
## the seam, its disc turned with its tile.
func test_seam_problems_flags_a_fixture_pair_whose_lane_crosses_the_seam() -> void:
	var d := 10.1 / sqrt(2.0)
	var cases := [["east", Vector2(22.4, 12.0), Vector2(-31.5, 12.0)], ["north", Vector2(12.0, -22.4), Vector2(12.0, 31.5)],
		["north-east", Vector2(22.4, -22.4), Vector2(22.4 + d - 64.0, -22.4 - d + 64.0)]]
	for c in cases:
		var content := _pair(func(t: Dictionary) -> void:
			t.sunlit_a.zones[0].center = PackedFloat64Array([c[1].x, c[1].y])
			t.drift_a.shells[5].center = PackedFloat64Array([c[2].x, c[2].y]))
		var problems := WorldChecks.tile_seam_problems(content, SpeciesCatalog.load_from(), PartCatalog.load_from(), 1, PackedInt32Array([0]))
		check_eq(problems.size(), 1, "one problem %s: %s" % [c[0], problems])
		check(problems.size() == 1 and problems[0].begins_with("seam b0/sunlit_a@o0 | b0/drift_a@o0 %s: Rule 9 (" % c[0])
			and problems[0].contains("site 'a' of b0/sunlit_a@o0: b0/drift_a@o0:f lies 0.50 m from its leash circle"), "names both tiles and orientations: %s" % [problems])
		if c[0] != "east":
			continue
		var turned := WorldChecks.tile_seam_problems(content, SpeciesCatalog.load_from(), PartCatalog.load_from(), 1, PackedInt32Array([2]))
		check_eq(turned.size(), 1, "one problem at o2: %s" % [turned])
		check(turned.size() == 1 and turned[0].begins_with("seam b0/drift_a@o2 | b0/sunlit_a@o2 east: Rule 9 (")
			and turned[0].contains("site 'a' of b0/sunlit_a@o2: b0/drift_a@o2:f lies 0.50 m from its leash circle"), "the far side's site: %s" % [turned])


## Circles may not overlap across a seam: drift_a's 'f' pushed 5.5 bu past its west edge meets
## sunlit_a's 'h' (25, 25) r 1.35.
func test_seam_problems_refuse_circles_overlapping_across_a_seam() -> void:
	var content := _pair(func(t: Dictionary) -> void: t.drift_a.shells[5].center = PackedFloat64Array([-37.5, 25.0]))
	var problems := WorldChecks.tile_seam_problems(content, SpeciesCatalog.load_from(), PartCatalog.load_from(), 1, PackedInt32Array([0]))
	check_eq(problems, PackedStringArray(["seam b0/sunlit_a@o0 | b0/drift_a@o0 east: rule 2: 'b0/sunlit_a@o0:h' and 'b0/drift_a@o0:f' overlap by 0.45 bu across the seam"]),
		"one overlap")


## The home block's edges: ring shell 'sa' moved just inside each edge of the block's south-east
## quarter meets drift_a's 'f' moved just past the facing edge of the tile beyond it, in that slot.
func test_home_seam_problems_check_the_block_edges() -> void:
	# [sa in the block, f in its tile, the slot]: east, west, north, south.
	var cases := [[Vector2(63.5, 40.0), Vector2(-33.0, 8.0), Vector2i(1, 0)], [Vector2(-63.5, 40.0), Vector2(33.0, 8.0), Vector2i(-2, 0)],
		[Vector2(40.0, -63.5), Vector2(8.0, 33.0), Vector2i(0, -2)], [Vector2(40.0, 63.5), Vector2(8.0, -33.0), Vector2i(0, 1)]]
	for c in cases:
		var content := _pair(func(t: Dictionary) -> void: t.drift_a.shells[5].center = PackedFloat64Array([c[1].x, c[1].y]))
		for s in content.home.shells:
			if s.id == "sa":
				s.x = c[0].x
				s.y = c[0].y
		var problems := WorldChecks.home_seam_problems(content, SpeciesCatalog.load_from(), PartCatalog.load_from(), 1, PackedInt32Array([0]))
		check_eq(problems.size(), 1, "one problem at %s: %s" % [c[2], problems])
		check(problems.size() == 1 and problems[0].begins_with("seam home_min | b0/drift_a@o0 at tile %s: rule 2: 'home_min:sa' and 'b0/drift_a@o0:f' overlap" % c[2]),
			"names the block, the tile and its slot: %s" % [problems])


## A home site's disc meets a tile's circles across the block's edge: drift_a's 'f' set 0.5 bu
## beyond lair_se's leash circle, in the frame of the tile east of the block's south half.
func test_home_seam_problems_check_the_home_sites() -> void:
	var content := _content()
	var species := SpeciesCatalog.load_from()
	var parts := PartCatalog.load_from()
	var lair := {}
	for s in WorldChecks._home_frame(content, species, parts, 1).sites:
		if s.where == "site 'lair_se' of home_min":
			lair = s
	check(not lair.is_empty(), "lair_se is live at size 1")
	if lair.is_empty():
		return
	var at: Vector2 = lair.disc.center + Vector2(float(lair.disc.radius) + 0.6 + 0.5, 0.0) - Vector2(96.0, 32.0)
	content = _pair(func(t: Dictionary) -> void: t.drift_a.shells[5].center = PackedFloat64Array([at.x, at.y]))
	var problems := WorldChecks.home_seam_problems(content, species, parts, 1, PackedInt32Array([0]))
	var hits := Array(problems).filter(func(p: String) -> bool:
		return p.begins_with("seam home_min | b0/drift_a@o0 at tile (1, 0): Rule 9 (") and p.contains("site 'lair_se' of home_min: b0/drift_a@o0:f lies 0.50 m"))
	check_eq(hits.size(), 1, "the lair's leash circle meets 'f': %s" % [problems])


## The seam check leaves out far circles that cannot change rules 9 and 10, never one that can. A
## site r 0.5 with its disc r 5 at A's origin; B lies east, its circles given in B's frame. Far 'c'
## (r 3) reaches into the disc and pinches far 'c2' 0.5 bu away; own 'o2' reaches in and pinches far
## 'c3', which lies wholly outside the disc and its leash band. Only far circles change the count.
func test_seam_sites_keep_every_far_circle_that_can_pinch() -> void:
	var offset := Vector2(64.0, 0.0)
	var own: Array[Dictionary] = [{"id": "o", "center": Vector2(-2.0, 0.0), "radius": 0.5}, {"id": "o2", "center": Vector2(0.0, 5.2), "radius": 1.0}]
	var far: Array[Dictionary] = []
	for c in [["c", Vector2(7.0, 0.0), 3.0], ["c2", Vector2(11.5, 0.0), 1.0], ["c3", Vector2(0.0, 7.7), 1.0]]:
		far.append({"id": c[0], "center": c[1] - offset, "radius": c[2]})
	var a := {"where": "A", "circles": own, "max_r": 1.0, "sites": [{"where": "site", "r": 0.5, "disc": {"center": Vector2.ZERO, "radius": 5.0}}]}
	var b := {"where": "B", "circles": far, "max_r": 3.0, "sites": []}
	var out := PackedStringArray()
	WorldChecks._seam(a, b, offset, "L", SpeciesCatalog.load_from(), out)
	check_eq(out, PackedStringArray([
		"L: Rule 10 (%s): site: o2 leaves 0.50 m to c3; it needs 1.50 m." % SpeciesCatalog.RULE_NAMES[10],
		"L: Rule 9 (%s): site: c lies -1.00 m from its leash circle; it needs 0.60 m." % SpeciesCatalog.RULE_NAMES[9],
		"L: Rule 10 (%s): site: c leaves 0.50 m to c2; it needs 1.50 m." % SpeciesCatalog.RULE_NAMES[10]]),
		"o2's passage to c3, c's band and c's passage to c2; o2's own band is its side's")
