extends TestCase
## The shipped home block, game/data/home_b0.json (S1, G3; docs/s1/s1-content.md sections 3.6 and
## 5.3): the M1 pool exactly as pool mode builds it, unwalled, plus the seam ring of 20 zones and 8
## shells that fills the rest of the 128 x 128 bu block. HomeBlock's own rules are T1's
## (tests/test_home_block.gd, on a fixture); these tests hold the real content to them, to the
## starving budget over the whole block, and to the margins the ring was authored with. The slow and
## soak tests run the block with the tiles round it as WorldGen.chunk builds them, seed by seed.
## S2 (S2G7, D-37): the reach rules and static #33 run again at size 2, in that size's tm (the block
## is 80 tm a side there; the cell keeps r 0.5 tm and the starving budget), with the colliders there,
## the zones there (the M1 zones thinned) and the sites live there.

const WorldChecks := preload("res://tests/world_checks.gd")
## The starving budget as tests/test_pool_layout.gd computes it (30 health at 1.5 a second, the
## omnivore's 2.72 tm/s at starving speed, times 0.6). Pinned first, so a changed budget fails here
## before any grid runs (G5).
const BUDGET_TM := 16.32
const BUDGET_PIN := 0.01
const RING_ZONES := 20
const RING_SHELLS := 8
## The ring zones keep 1 bu inside the block's edge, the ring shells 4 bu.
const ZONE_EDGE_BU := 63.0
const SHELL_EDGE_BU := 60.0
## Each ring zone keeps this far from every other ring zone (HomeBlock's rule 3).
const ZONE_GAP_BU := 1.0
## A ring shell's surface keeps this far from every M1 reach-disc circle (measured 6.46), far more
## than rules 9 and 10 need (r + 0.1), so the ring never constrains M1 tuning.
const SEAM_TO_M1_DISC_BU := 4.0
const BLOCK := Rect2(-64.0, -64.0, 128.0, 128.0)
## D-37 (S2): the M1 sites that stay at size 2 (one ambush hunter, two rammers), the M1 zones thinned
## there, and the ring's size-2 threats: [id, species, live sizes, two posts].
const M1_AT_SIZE_2: PackedStringArray = ["lair_s", "terr_nw", "terr_ne"]
const M1_ZONES_AT_SIZE_2 := "thin"
const RING_SITES := [["rl", "lurker", [2], true], ["re", "elder_rammer", [2], false]]
## The block and the ring of tiles round it: 4 x 4 whole tiles, 8 x 8 chunks at size 1 (whole tiles,
## so no point lacks food that lies beyond the bounds). B-17 asks for 50 seeds, 10 of them slow, but
## one seed is a 512 x 512 grid of about 3 s here and B-13 moves any slow test over 20 s to soak: so
## seeds 1 to 5 are slow and 6 to 50 soak.
const NEIGHBOURS := Rect2(-128.0, -128.0, 256.0, 256.0)
const NEIGHBOUR_CHUNKS := Rect2i(-4, -4, 8, 8)
const SLOW_SEEDS := Vector2i(1, 5)
const SOAK_SEEDS := Vector2i(6, 50)

var species: SpeciesCatalog
var parts: PartCatalog
var layout: PoolLayout
var kit: PlacementKit
var home: HomeBlock
var content: WorldContent


func before_each() -> void:
	if home != null:
		return
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	kit = PlacementKit.load_from()
	home = HomeBlock.load_from(HomeBlock.DEFAULT_PATH, layout, species)


func _ring_zones() -> Array:
	return home.zones.filter(func(z: Dictionary) -> bool: return not z.m1)


func _ring_shells() -> Array:
	return home.shells.filter(func(s: Dictionary) -> bool: return not s.fixed)


## The budget every reach test uses, after its pin.
func _budget() -> float:
	var budget := WorldChecks.starving_budget(parts)
	check(absf(budget - BUDGET_TM) <= BUDGET_PIN, "the starving budget is %.2f tm (%.3f)" % [BUDGET_TM, budget])
	return budget


func test_the_home_block_validates() -> void:
	check_eq(home.validate(species, kit, parts, 1), PackedStringArray(), "home_b0 against the shipped kit at size 1")
	check_eq(home.where, "home_b0", "messages name the file")
	# S2: at size 2 too (D-70), with the Lurker and the elder rammer the ring holds there.
	check_eq(home.validate(species, kit, parts, 2), PackedStringArray(), "home_b0 against the shipped kit at size 2")


## D-37 at size 2: five live sites, the three M1 sites it keeps (an ambush hunter and two rammers,
## rivals and prey there) and the ring's two threats, a two-post Lurker and an elder rammer; the M1
## zones thin. Both behaviours a threat can have are in the block at size 2.
func test_the_home_block_at_size_2_is_d37s() -> void:
	check_eq(home.m1_second_size_sites, M1_AT_SIZE_2, "the M1 sites kept at size 2")
	check_eq(home.m1_zones_at_second_size, M1_ZONES_AT_SIZE_2, "the M1 zones at size 2")
	check(home.zones.filter(func(z: Dictionary) -> bool: return z.m1).all(func(z: Dictionary) -> bool: return z.at_second_size == "thin"),
		"every M1 zone thins at size 2")
	var live := home.sites.filter(func(s: Dictionary) -> bool: return s.sizes.has(2))
	check_eq(live.map(func(s: Dictionary) -> String: return s.id), Array(M1_AT_SIZE_2) + ["rl", "re"], "five sites live at size 2")
	var behaviours := {}
	for s in live:
		if species.entry_size(s.species) == 2:
			behaviours[species.behavior_of(s.species)] = true
	check_eq(WorldConfig._sorted(behaviours.keys()), ["ambush", "territorial"], "both threat behaviours at size 2")
	var ring := home.sites.filter(func(s: Dictionary) -> bool: return not s.m1)
	check_eq(ring.size(), RING_SITES.size(), "the ring's sites")
	for i in mini(ring.size(), RING_SITES.size()):
		var want: Array = RING_SITES[i]
		var sizes: Array[int] = []
		sizes.assign(want[2])
		check_eq([ring[i].id, ring[i].species, ring[i].sizes, not ring[i].post_b.is_empty()], [want[0], want[1], sizes, want[3]],
			"ring site %d" % i)


func test_the_ring_is_twenty_zones_and_eight_shells_outside_the_m1_pool() -> void:
	var zones := _ring_zones()
	var shells := _ring_shells()
	check_eq(zones.size(), RING_ZONES, "ring zones")
	check_eq(shells.size(), RING_SHELLS, "ring shells")
	for z in zones:
		var c := Vector2(z.x, z.y)
		var label := "zone %s at %s" % [z.id, c]
		check(c.length() - z.radius >= home.seam_inner_r, "%s keeps outside seam_inner_r %s" % [label, home.seam_inner_r])
		check(absf(z.x) + z.radius <= ZONE_EDGE_BU and absf(z.y) + z.radius <= ZONE_EDGE_BU, "%s keeps 1 bu inside the block" % label)
		var yield_rate: float = z.growth_rate * z.capacity * (TileCatalog.YIELD_SHARE + EcologyRegion.REGROW_FLOOR)
		check(yield_rate <= TileCatalog.MAX_ZONE_YIELD, "%s yields %.3f; static #33 allows %.3f" % [label, yield_rate, TileCatalog.MAX_ZONE_YIELD])
		for o in zones:
			if o.id != z.id:
				var gap: float = c.distance_to(Vector2(o.x, o.y)) - z.radius - o.radius
				check(gap >= ZONE_GAP_BU, "%s is %.2f bu from zone %s" % [label, gap, o.id])
	for s in shells:
		var c := Vector2(s.x, s.y)
		check(c.length() - s.r >= home.seam_inner_r, "shell %s at %s keeps outside seam_inner_r" % [s.id, c])
		check(absf(s.x) + s.r <= SHELL_EDGE_BU and absf(s.y) + s.r <= SHELL_EDGE_BU, "shell %s keeps 4 bu inside the block" % s.id)


## B-2 and B-3: every home zone, the M1 zones and the ring, keeps the open water a plankton anchor
## needs (PoolLayout.ZONE_CLEAR_MARGIN, 0.7 bu) from every home collider, the M1 rocks and the ring
## shells, so no zone's anchors depend on what else is loaded.
func test_every_home_zone_keeps_0_7_bu_from_every_home_collider() -> void:
	var least := INF
	var least_at := ""
	for z in home.zones:
		var c := Vector2(z.x, z.y)
		for s in home.shells:
			var gap: float = c.distance_to(Vector2(s.x, s.y)) - z.radius - s.r
			check(gap >= PoolLayout.ZONE_CLEAR_MARGIN, "zone %s is %.2f bu from shell %s; it keeps %.1f" % [z.id, gap, s.id, PoolLayout.ZONE_CLEAR_MARGIN])
			if gap < least:
				least = gap
				least_at = "%s to %s" % [z.id, s.id]
	check(home.zones.size() > RING_ZONES and home.shells.size() > RING_SHELLS, "the M1 zones and rocks are counted too")
	print("test-home-content: least zone gap %.2f bu (%s)" % [least, least_at])


func test_the_m1_pool_is_kept_exactly() -> void:
	check(home.shells.size() >= layout.rocks.size(), "the M1 rocks come first")
	for i in layout.rocks.size():
		var r: Dictionary = layout.rocks[i]
		var s: Dictionary = home.shells[i]
		check_eq([s.id, s.x, s.y, s.r, s.asset, s.yaw_deg, s.scale, s.fixed],
			[r.id, float(r.center.x), float(r.center.y), float(r.radius), r.asset, float(r.yaw_deg), float(r.scale), true], "rock %d" % i)
	for i in layout.zones.size():
		var z: Dictionary = layout.zones[i]
		var h: Dictionary = home.zones[i]
		check_eq([h.id, h.x, h.y, h.radius, h.capacity, h.growth_rate, h.m1],
			[z.id, float(z.center.x), float(z.center.y), float(z.radius), float(z.capacity), float(z.growth_rate), true], "zone %d" % i)
	check_eq(home.sites.size(), species.sites.size() + RING_SITES.size(), "the 7 M1 sites, then the ring's (S2)")
	for i in species.sites.size():
		var s: Dictionary = species.sites[i]
		var h: Dictionary = home.sites[i]
		var sizes: Array[int] = []
		sizes.assign([1, 2] if M1_AT_SIZE_2.has(s.id) else [1])
		check_eq([h.id, h.species, h.x, h.y, h.heading, h.territory_zone, h.sizes],
			[s.id, s.species, float(s.home.x), float(s.home.y), float(s.heading), str(s.get("territory_zone", "")), sizes],
			"site %d, live at size 2 only when D-37 keeps it" % i)
	check_eq(home.spawn, PackedFloat64Array([0.0, 9.0]), "the spawn")
	check_eq(home.spawn_heading, -1.5708, "its heading")
	var carrion := []
	for p: Vector2 in layout.carrion.initial:
		carrion.append([float(p.x), float(p.y)])
	check(not carrion.is_empty(), "pool_m1.json places starting carrion")
	check_eq(home.carrion_initial, carrion, "the starting carrion")


func _content() -> WorldContent:
	if content == null:
		content = WorldContent.load_from(WorldConfig.DEFAULT_PATH, layout, species)
	return content


## The sizes this build runs.
func _sizes() -> Array:
	return range(_content().config.size_start, _content().config.max_size_in_build + 1)


## Items a full zone shows (PlanktonField.max_count, capped per zone by the world file).
func _items(capacity: float) -> int:
	return mini(int(_content().config.caps.food_per_zone), floori(capacity / float(layout.plankton.unit_energy) + 0.000001))


## The block at `size` for the reach rule, in that size's tm: {arena (the colliders there), zones
## (those there that can hold an item: the M1 zones thinned at size 2), bounds, homes (the spawn and
## the homes of the sites live there, both posts' for two: B-29's must_reach)}.
func _block_at(size: int) -> Dictionary:
	var st := WorldConfig.bu_to_tm(size)
	var zones: Array[Dictionary] = []
	for z in WorldChecks.zones_at(home.zones, home.band, size, _content()):
		if _items(float(z.capacity)) >= 1:
			zones.append({"id": z.id, "center": Vector2(z.x, z.y) * st, "radius": float(z.radius) * st})
	var homes: Array[Vector2] = [Vector2(home.spawn[0], home.spawn[1]) * st]
	for s in home.sites:
		if s.sizes.has(size):
			homes.append(Vector2(s.x, s.y) * st)
			if not s.post_b.is_empty():
				homes.append(Vector2(s.post_b.home[0], s.post_b.home[1]) * st)
	return {"arena": ChunkArena.from_shells(WorldChecks.scaled(home.circles_at(size), st)), "zones": zones,
		"bounds": Rect2(BLOCK.position * st, BLOCK.size * st), "homes": homes}


## G3 at each size (F9 at size 2): from every open point of the block a starving cell reaches food
## (the M1 zones and the ring) within the budget, round the M1 rocks and the ring shells, with no
## wall; the spawn and the live site homes lie in that open sea. Measured 14.7 tm at (64, -17) on the
## block's east edge at size 1.
func test_every_point_of_the_home_block_reaches_food_within_the_budget() -> void:
	var budget := _budget()
	for size in _sizes():
		var b := _block_at(size)
		check(b.zones.size() >= 20 and b.homes.size() >= 4, "size %d: the block's food and homes (%d, %d)" % [size, b.zones.size(), b.homes.size()])
		check_eq(WorldChecks.reach_problems(b.arena, b.zones, b.bounds, budget, b.homes), PackedStringArray(), "size %d: every point of %s" % [size, b.bounds])
		var worst := WorldChecks.worst_reach(b.arena, b.zones, b.bounds)
		print("test-home-content: size %d: reach worst %.1f tm at %s (budget %.2f)" % [size, worst.worst, worst.at, budget])


## Static #33 at size 2: every zone of the block there, at its capacity there (the M1 zones thinned,
## D-37; a "thin" ring zone x 0.4), yields at most the M1 unguarded maximum.
func test_every_home_zone_meets_static_33_at_size_2() -> void:
	var checked := 0
	for z in WorldChecks.zones_at(home.zones, home.band, 2, _content()):
		checked += 1
		var yield_rate := float(z.growth_rate) * float(z.capacity) * (TileCatalog.YIELD_SHARE + EcologyRegion.REGROW_FLOOR)
		check(yield_rate <= TileCatalog.MAX_ZONE_YIELD, "zone %s yields %.3f at size 2; static #33 allows %.3f" % [z.id, yield_rate, TileCatalog.MAX_ZONE_YIELD])
	check_eq(checked, home.zones.size(), "every zone is there at size 2 (none dropped)")


func test_seam_shells_stay_well_clear_of_the_m1_reach_discs() -> void:
	var zone_by_id := {}
	for z in home.zones:
		zone_by_id[z.id] = z
	var nearest := INF
	var checked := 0
	for site in home.sites.filter(func(s: Dictionary) -> bool: return s.m1):
		var z: Dictionary = zone_by_id.get(site.territory_zone, {})
		var territory := species.territory_from({"species": site.species}, {} if z.is_empty() else {"center": Vector2(z.x, z.y), "radius": z.radius})
		var disc := species.reach_disc_for({"species": site.species, "home": Vector2(site.x, site.y), "heading": site.heading}, territory)
		var c: Vector2 = disc.center
		for s in _ring_shells():
			var gap: float = absf(c.distance_to(Vector2(s.x, s.y)) - float(disc.radius)) - s.r
			nearest = minf(nearest, gap)
			checked += 1
			check(gap >= SEAM_TO_M1_DISC_BU, "ring shell %s is %.2f bu from site %s's reach circle" % [s.id, gap, site.id])
	check_eq(checked, 7 * RING_SHELLS, "every M1 site against every ring shell")
	print("test-home-content: nearest ring shell to an M1 reach circle %.2f bu" % nearest)


## The home block and its neighbour tiles for each seed in [seeds.x, seeds.y] at `size`, from the
## generator: one arena of every shell, every chunk's zones that can hold an item, and the spawn and
## every live site home (both posts') as must-reach points, over the block and its ring of whole
## tiles ([-128, 128)^2 bu, in that size's tm) and the chunks that hold them. With `measure`, returns
## the worst walk to food on the first seed (a grid more).
func _neighbours_reach(seeds: Vector2i, measure: bool, size := 1) -> float:
	var budget := _budget()
	var st := WorldConfig.bu_to_tm(size)
	var bounds := Rect2(NEIGHBOURS.position * st, NEIGHBOURS.size * st)
	var chunk_tm := float(_content().config.chunk_tm)
	var lo := Vector2i(floori(bounds.position.x / chunk_tm), floori(bounds.position.y / chunk_tm))
	var hi := Vector2i(ceili(bounds.end.x / chunk_tm), ceili(bounds.end.y / chunk_tm))
	check(size != 1 or Rect2i(lo, hi - lo) == NEIGHBOUR_CHUNKS, "size 1: the 8 x 8 chunks of S1")
	var worst := -1.0
	for seed in range(seeds.x, seeds.y + 1):
		var gen := WorldGen.create(content, species, seed)
		var circles: Array[Dictionary] = []
		var zones: Array[Dictionary] = []
		var homes: Array[Vector2] = [Vector2(home.spawn[0], home.spawn[1]) * st]
		for cy in range(lo.y, hi.y):
			for cx in range(lo.x, hi.x):
				var c := gen.chunk(size, cx, cy)
				for sh in c.shells:
					circles.append({"id": sh.id, "center": Vector2(sh.x, sh.y), "radius": float(sh.r)})
				for z in c.zones:
					if _items(float(z.capacity)) >= 1:
						zones.append({"id": z.id, "center": Vector2(z.x, z.y), "radius": float(z.radius)})
				for site in c.sites:
					if not site.sizes.has(size):
						continue
					homes.append(Vector2(site.x, site.y))
					for post in site.get("posts", []).slice(1):
						homes.append(Vector2(post.x, post.y))
		check(zones.size() > home.zones.size() and homes.size() > 2, "seed %d size %d: the tiles round home were built (%d zones, %d homes)" % [seed, size, zones.size(), homes.size()])
		var arena := ChunkArena.from_shells(circles)
		check_eq(WorldChecks.reach_problems(arena, zones, bounds, budget, homes), PackedStringArray(), "seed %d size %d: %s" % [seed, size, bounds])
		if measure and seed == seeds.x:
			worst = float(WorldChecks.worst_reach(arena, zones, bounds).worst)
	return worst


## G3 across the block's edges at each size: the home block and the tiles round it, seeds 1 to 5.
func test_slow_the_home_block_and_its_neighbour_tiles_reach_food() -> void:
	for size in _sizes():
		_neighbours_reach(SLOW_SEEDS, false, size)
		print("test-home-content: size %d: home and neighbours, seeds %d to %d clean" % [size, SLOW_SEEDS.x, SLOW_SEEDS.y])


func test_soak_the_home_block_and_its_neighbour_tiles_reach_food_on_45_more_seeds() -> void:
	for size in _sizes():
		var worst := _neighbours_reach(SOAK_SEEDS, true, size)
		print("test-home-content: size %d: home and neighbours, seeds %d to %d clean; reach worst on seed %d %.1f tm" % [size, SOAK_SEEDS.x, SOAK_SEEDS.y, SOAK_SEEDS.x, worst])
