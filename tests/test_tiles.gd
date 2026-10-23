extends TestCase
## The shipped band-0 tiles, game/data/tiles/b0 (S1, G2 and G5; docs/s1/s1-content.md sections 3.4,
## 3.5 and 5.2): 18 ordinary tiles and the two rare places, on the real kit. TileCatalog's rules are
## T1's (tests/test_tile_catalog.gd, on fixtures); these tests hold the real content to them, to the
## region designs, to the margins the tiles were authored with, and to the heavy checks of spine 4.2:
## per-tile reach (slow), the identity seams with a positive control (slow), every rule and reach at
## all 8 orientations (soak), the food bound (coarse fast, fine soak) and the site sample (soak), the
## last four through T1.10's world_checks. docs/s1/s1-build-plan.md corrects them: zones keep 0.7 bu
## from every collider (B-3), the cathedral's nave is sealed (B-28), the seams and orientations are
## world_checks' (B-16), and the sample counts reach discs per 40 tm disc (B-17).

const WorldChecks := preload("res://tests/world_checks.gd")
const ReachGrid := preload("res://tests/reach_grid.gd")
## The starving budget as tests/test_pool_layout.gd computes it, pinned before any grid runs (G5).
const BUDGET_TM := 16.32
const BUDGET_PIN := 0.01
const TILE_BOUNDS := Rect2(-32.0, -32.0, 64.0, 64.0)
const RARE_KINDS: PackedStringArray = ["giant_husk", "shell_cathedral"]
## The region designs (s1-content 3.2): what each kind of tile is for.
const SUNLIT_RICH_R := 5.0
const SUNLIT_RICH_CAPACITY := 64.0
const SUNLIT_RAMMER_CAPACITY := 48.0
const REEF_SHELLS := 18
const DRIFT_MAX_SHELLS := 5
const DRIFT_MAX_CAPACITY := 16.0
const DRIFT_MAX_ITEMS := 12
## A sunlit tile's size-2 threat (S2): an elder rammer guarding a zone, or a Lurker where every zone's
## disc would reach too near the landmark anchor (PROPOSED).
const SUNLIT_THREATS_AT_TWO := ["elder_rammer", "lurker"]
## The smallest slack a site keeps inside its tile (rule 6's inset) and from the landmark anchor
## (rule 8), so retuning cannot wear them down to the rule unnoticed.
const MIN_INSET_SLACK := 1.0
const MIN_ANCHOR_SLACK := 1.0
## The seam check's positive control (s1-content 5.2): a shell put just across the seam from
## giant_husk's lair la, inside its reach circle where rule 9 wants clear water; with giant_husk east
## of reef_a, it sits in reef_a's frame at CONTROL_SHELL.
const CONTROL_A := "reef_a"
const CONTROL_B := "giant_husk"
const CONTROL_SHELL := [35.5, -4.0]
const CONTROL_R := 0.6
const IDENTITY: PackedInt32Array = [0]
const FOOD_COARSE_TM := 4.0
const FOOD_FINE_TM := 1.0
## A coarse bound below this would mean food_bound saw no tiles (it measures 100; s1-content 5.2 had 91).
const FOOD_FLOOR := 60
## The site sample (B-17, B-14): arrangements x discs uniform over a 2 km square round home, each
## disc 40 tm; no disc meets more than 10 live reach discs.
const SAMPLE_ARRANGEMENTS := 1000
const SAMPLE_DISCS := 100
const SAMPLE_SEED := 4242
const SAMPLE_HALF_TM := 1000.0
const SAMPLE_RADIUS_TM := 40.0
const SAMPLE_MAX_SITES := 10
## B-28: no zone point or site home within this of the cathedral's centre (ring 3.4 + pillar 0.9 +
## the 0.7 zone gap).
const CATHEDRAL_CLEAR_BU := 5.0

var species: SpeciesCatalog
var parts: PartCatalog
var content: WorldContent
var kit: PlacementKit
var tiles: TileCatalog
var radii := {}


func before_each() -> void:
	if content != null:
		return
	species = SpeciesCatalog.load_from()
	parts = PartCatalog.load_from()
	content = WorldContent.load_from(WorldConfig.DEFAULT_PATH, PoolLayout.load_from(), species)
	kit = content.kit
	tiles = content.tiles
	for id in species.species_ids():
		radii[id] = species.phenotype(id, parts).radius


func _ids() -> Array:
	return WorldConfig._sorted(tiles.tiles.keys())


## The budget every reach test uses, after its pin.
func _budget() -> float:
	var budget := WorldChecks.starving_budget(parts)
	check(absf(budget - BUDGET_TM) <= BUDGET_PIN, "the starving budget is %.2f tm (%.3f)" % [BUDGET_TM, budget])
	return budget


## Items a full zone shows (PlanktonField.max_count, capped per zone by the world file).
func _items(z: Dictionary) -> int:
	var unit := float(content.layout.plankton.unit_energy)
	return mini(int(content.config.caps.food_per_zone), floori(float(z.capacity) / unit + 0.000001))


func _zone_of(t: Dictionary, id: String) -> Dictionary:
	for z in t.zones:
		if z.id == id:
			return z
	return {}


## {center, radius} of a site's reach disc in its tile's identity frame.
func _disc(t: Dictionary, s: Dictionary) -> Dictionary:
	var z := _zone_of(t, str(s.territory_zone))
	var territory := species.territory_from({"species": s.species}, {} if z.is_empty() else {
		"center": Vector2(z.center[0], z.center[1]), "radius": float(z.radius)})
	return species.reach_disc_for({"species": s.species, "home": Vector2(s.home[0], s.home[1]), "heading": float(s.heading)}, territory)


static func _orient(p: Vector2, o: int) -> Vector2:
	var q := WorldGen.orient_point(p.x, p.y, o)
	return Vector2(q[0], q[1])


## Tile t turned to orientation o: its colliders (with or without the landmark's) and zones as
## ReachGrid takes them, and the homes of its live sites (must_reach).
func _placed(t: Dictionary, o: int, with_anchor: bool = true) -> Dictionary:
	var colliders: Array[Dictionary] = []
	for c in TileCatalog.colliders_of(t, kit):
		if with_anchor or c.id != TileCatalog.LANDMARK_ID:
			colliders.append({"id": "%s/%s" % [t.id, c.id], "center": _orient(c.center, o), "radius": float(c.radius)})
	var zones: Array[Dictionary] = []
	for z in t.zones:
		zones.append({"id": "%s/%s" % [t.id, z.id], "center": _orient(Vector2(z.center[0], z.center[1]), o), "radius": float(z.radius)})
	var homes: Array[Vector2] = []
	for s in t.sites:
		if s.sizes.has(1):
			homes.append(_orient(Vector2(s.home[0], s.home[1]), o))
	return {"colliders": colliders, "zones": zones, "homes": homes}


## The worst walk to food over the open points the sea outside reaches (a sealed, empty pocket such as
## the cathedral's nave has none; B-29), and where, for the printed margins.
static func _worst_reach(arena: PoolArena, zones: Array[Dictionary], bounds: Rect2) -> Dictionary:
	var grid = ReachGrid.over(arena, zones, bounds, PoolLayout.CELL_RADIUS)
	var to_food: PackedFloat32Array = grid.distances_from(grid.zone_points())
	var from_border: PackedFloat32Array = grid.distances_from(grid.border_points())
	var worst := -1.0
	var at := Vector2.ZERO
	for i in grid.open.size():
		if grid.open[i] == 1 and is_finite(from_border[i]) and is_finite(to_food[i]) and to_food[i] > worst:
			worst = to_food[i]
			at = grid.point(i)
	return {"worst": worst, "at": at}


# ---- Fast ----

## G2: every rule of spine 4.2 at identity and size 1, with the kit, the home block and the world file
## (WorldContent.problems runs TileCatalog.validate on these tiles).
func test_the_band_0_content_validates() -> void:
	check_eq(tiles.load_problems, PackedStringArray(), "the tiles read")
	check_eq(_ids().size(), 20, "18 ordinary tiles and 2 rare ones")
	check_eq(content.problems(parts, species), PackedStringArray(), "world_cell.json and everything it names")
	# B-6's content bound in problems(): rebase_beyond + hold + reach_max + chunk x sqrt 2 < local bound.
	var widest := content.reach_max(species)
	print("test-tiles: reach_max %.2f tm at %s" % [widest.radius_tm, widest.where])


func test_each_region_has_three_tiles_per_set_and_two_rare_kinds() -> void:
	for region in TileCatalog.REGIONS:
		for set_index in TileCatalog.SETS:
			check_eq(tiles.ids_of(0, region, set_index).size(), TileCatalog.TILES_PER_SET, "%s set %d" % [region, set_index])
	check_eq(tiles.rare_kinds(0), RARE_KINDS, "band 0's rare kinds")
	for kind in RARE_KINDS:
		check_eq(str(tiles.rare_tile(0, kind).get("id", "")), kind, "the %s tile is named for its kind" % kind)


func test_tiles_keep_their_region_design() -> void:
	var sunlit_least := 1 << 30
	var drift_most := 0
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		var items := 0
		for z in t.zones:
			items += _items(z)
		var rammers := 0
		var ambushes := 0
		# S2 (s2-interfaces 4.3): an M1 site lives at size 1, or at 1 and 2; a size-2 threat at 2 only.
		var m1_at_two := {}
		var threats_at_two := []
		for s in t.sites:
			if species.entry_size(s.species) == 2:
				check_eq(s.sizes, [2] as Array[int], "%s site '%s': a size-2 threat lives at size 2 only" % [id, s.id])
				threats_at_two.append(s.species)
				continue
			check(s.sizes == ([1] as Array[int]) or s.sizes == ([1, 2] as Array[int]), "%s site '%s' lives at size 1, or 1 and 2 (%s)" % [id, s.id, s.sizes])
			if s.sizes.has(2):
				m1_at_two[s.species] = int(m1_at_two.get(s.species, 0)) + 1
			if species.behavior_of(s.species) == "territorial":
				var z := _zone_of(t, s.territory_zone)
				if t.region == "sunlit" and float(z.get("capacity", 0.0)) >= SUNLIT_RAMMER_CAPACITY:
					rammers += 1
			elif species.behavior_of(s.species) == "ambush":
				ambushes += 1
		match t.region:
			"sunlit":
				var rich := _zone_of(t, "ra")
				check(float(rich.get("radius", 0.0)) == SUNLIT_RICH_R and float(rich.get("capacity", 0.0)) == SUNLIT_RICH_CAPACITY,
					"%s: the feast zone ra is R %s, capacity %s (%s)" % [id, SUNLIT_RICH_R, SUNLIT_RICH_CAPACITY, rich])
				check(rammers >= 1, "%s: a rammer guards a zone of capacity %s or more" % [id, SUNLIT_RAMMER_CAPACITY])
				sunlit_least = mini(sunlit_least, items)
				check_eq(m1_at_two, {"rammer": 1}, "%s: at size 2 one M1 rammer stays" % id)
				check(threats_at_two.size() == 1 and threats_at_two[0] in SUNLIT_THREATS_AT_TWO,
					"%s: one size-2 threat, an elder rammer or a Lurker where the anchor leaves it no zone (%s)" % [id, threats_at_two])
			"reef":
				check_eq(t.shells.size(), REEF_SHELLS, "%s: the reef's shells" % id)
				check(t.sites.size() >= 2 and ambushes >= 1, "%s: at least 2 sites, an ambush lair among them (%d, %d)" % [id, t.sites.size(), ambushes])
				check_eq(threats_at_two, ["lurker"], "%s: one Lurker at size 2" % id)
				check_eq(m1_at_two, {"ambush_hunter": 1} if t.set == 0 else {}, "%s: an ambush hunter stays at size 2 in set 0 only" % id)
			"drift":
				check(t.sites.is_empty(), "%s: drift has no sites" % id)
				check(t.shells.size() <= DRIFT_MAX_SHELLS, "%s: at most %d shells (%d)" % [id, DRIFT_MAX_SHELLS, t.shells.size()])
				for z in t.zones:
					check(float(z.capacity) <= DRIFT_MAX_CAPACITY, "%s zone '%s': capacity %s, at most %s" % [id, z.id, z.capacity, DRIFT_MAX_CAPACITY])
				check(items <= DRIFT_MAX_ITEMS, "%s: %d items, at most %d" % [id, items, DRIFT_MAX_ITEMS])
				drift_most = maxi(drift_most, items)
			"rare":
				check_eq(float(t.set_piece.yaw_deg), 0.0, "%s: the set piece stands at yaw 0" % id)
				check_eq(str(t.set_piece.asset), kit.rare_asset(0, t.rare), "%s: the kit's piece of its kind" % id)
				check(not t.sites.filter(func(s: Dictionary) -> bool: return s.sizes.has(1) and TileCatalog.THREAT_BEHAVIORS.has(species.behavior_of(s.species))).is_empty(),
					"%s: a live threat guards it" % id)
				check(threats_at_two.size() >= 1, "%s: a threat guards it at size 2 too" % id)
	check(drift_most < sunlit_least, "drift tiles hold fewer items (at most %d) than any sunlit tile (at least %d)" % [drift_most, sunlit_least])


## B-3: every zone disc keeps 0.7 bu (PoolLayout.ZONE_CLEAR_MARGIN) from every collider of its tile
## (shells, the landmark's collider, the set piece's), so a plankton anchor is clear whatever else is
## loaded. Tiles keep shells 4 bu and zones 1 bu from their edges, so pairs across a seam are 5 apart.
func test_every_zone_keeps_0_7_bu_from_every_collider_of_its_tile() -> void:
	var least := INF
	var least_at := ""
	var zones := 0
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		var colliders := TileCatalog.colliders_of(t, kit)
		for z in t.zones:
			zones += 1
			var c := Vector2(z.center[0], z.center[1])
			for k in colliders:
				var gap: float = c.distance_to(k.center) - float(z.radius) - float(k.radius)
				check(gap >= PoolLayout.ZONE_CLEAR_MARGIN, "%s zone '%s' is %.2f bu from collider '%s'; it keeps %.1f" % [
					id, z.id, gap, k.id, PoolLayout.ZONE_CLEAR_MARGIN])
				if gap < least:
					least = gap
					least_at = "%s/%s to %s" % [id, z.id, k.id]
	check(zones >= 20, "every tile's zones (%d)" % zones)
	print("test-tiles: least zone gap %.3f bu (%s)" % [least, least_at])


## Rule 6's inset and rule 8's anchor clearance, with the slack each site keeps beyond the rule.
## Formulas as TileCatalog's rule 6; the table is printed for T4.4's retuning.
func test_sites_keep_a_margin_inside_their_tile_and_from_the_landmark() -> void:
	var fair := species.fairness
	var inset_least := INF
	var anchor_least := INF
	var inset_at := ""
	var anchor_at := ""
	var rows := PackedStringArray()
	var sites := 0
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		sites += t.sites.size()
		for s in t.sites:
			var d := _disc(t, s)
			var c: Vector2 = d.center
			var r := float(radii[s.species])
			var inset := TileCatalog.HALF_TILE_BU - maxf(absf(c.x), absf(c.y)) - float(d.radius) - r - float(fair.leash_band_margin_m)
			if inset < inset_least:
				inset_least = inset
				inset_at = "%s/%s" % [id, s.id]
			var anchor := INF
			if t.landmark_anchor.size() == 2:
				var a := Vector2(t.landmark_anchor[0], t.landmark_anchor[1])
				anchor = a.distance_to(c) - float(d.radius) - r - (kit.collide_radius_bu + PoolLayout.CELL_RADIUS + TileCatalog.ANCHOR_GAP_BU) \
					- (float(fair.respawn_clear_m) + TileCatalog.ANCHOR_CLEAR_EXTRA)
				if anchor < anchor_least:
					anchor_least = anchor
					anchor_at = "%s/%s" % [id, s.id]
			rows.append("%s/%s inset %.2f anchor %s" % [id, s.id, inset, "-" if anchor == INF else "%.2f" % anchor])
	check(sites > 0 and rows.size() == sites, "the table covers all %d sites (%d rows)" % [sites, rows.size()])
	check(inset_least >= MIN_INSET_SLACK, "every reach disc keeps %.1f bu inside its tile's inset; %s keeps %.2f" % [MIN_INSET_SLACK, inset_at, inset_least])
	check(anchor_least >= MIN_ANCHOR_SLACK, "every reach disc keeps %.1f bu beyond rule 8 from the anchor; %s keeps %.2f" % [MIN_ANCHOR_SLACK, anchor_at, anchor_least])
	print("test-tiles: least inset slack %.2f (%s), least anchor slack %.2f (%s)" % [inset_least, inset_at, anchor_least, anchor_at])
	print("test-tiles: " + "; ".join(rows))


## The cathedral's drums stand closer than a cell can pass (the kit's piece: 0.80 bu between
## neighbours), so its nave is a sealed pocket (B-28), legal while it is empty (B-29): no shell, zone
## point or site home lies within 5 bu of the piece's centre. If the piece is rebuilt with gaps a cell
## can swim through, this fails, and the nave must then meet the reach rule as open water.
func test_the_cathedral_nave_is_sealed_and_nothing_lives_in_it() -> void:
	var t := tiles.rare_tile(0, "shell_cathedral")
	var centre := Vector2(t.set_piece.center[0], t.set_piece.center[1])
	for z in t.zones:
		var gap := centre.distance_to(Vector2(z.center[0], z.center[1])) - float(z.radius)
		check(gap >= CATHEDRAL_CLEAR_BU, "zone '%s' comes %.2f bu from the cathedral's centre; it keeps %.1f" % [z.id, gap, CATHEDRAL_CLEAR_BU])
	for s in t.sites:
		var d := centre.distance_to(Vector2(s.home[0], s.home[1]))
		check(d >= CATHEDRAL_CLEAR_BU, "site '%s' lives %.2f bu from the cathedral's centre; it keeps %.1f" % [s.id, d, CATHEDRAL_CLEAR_BU])
	var drums := TileCatalog.colliders_of(t, kit).filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("r"))
	check_eq(drums.size(), 8, "eight drums")
	var widest := 0.0
	for i in drums.size():
		var a: Dictionary = drums[i]
		var b: Dictionary = drums[(i + 1) % drums.size()]
		widest = maxf(widest, a.center.distance_to(b.center) - a.radius - b.radius)
	check(widest < 2.0 * PoolLayout.CELL_RADIUS, "the drums leave at most %.2f bu between neighbours, less than a cell (%.1f)" % [widest, 2.0 * PoolLayout.CELL_RADIUS])
	for s in t.shells:
		var gap := centre.distance_to(Vector2(s.center[0], s.center[1])) - float(s.radius)
		check(gap >= CATHEDRAL_CLEAR_BU, "shell '%s' comes %.2f bu from the cathedral's centre; the nave holds nothing" % [s.id, gap])
	print("test-tiles: the cathedral's drums leave %.2f bu; the nave is sealed and empty" % widest)


func test_the_coarse_food_bound_stays_under_the_cap() -> void:
	var bound := WorldChecks.food_bound(content, FOOD_COARSE_TM)
	var cap := int(content.config.caps.food_items)
	check(int(bound.worst) <= cap, "at most %d items within the food ring of any point (%d at %s)" % [cap, int(bound.worst), bound.get("at")])
	check(int(bound.worst) >= FOOD_FLOOR, "the bound saw the tiles (%d >= %d)" % [int(bound.worst), FOOD_FLOOR])
	print("test-tiles: coarse food bound %d at %s (cap %d)" % [int(bound.worst), bound.get("at"), cap])


# ---- Slow ----

## G5: from every open point of each tile the sea outside reaches, a starving cell reaches one of the
## tile's own zones within the budget, with and without its landmark's collider (a rare tile: with
## its set piece), and every site home lies in that sea (B-29's must_reach).
func test_slow_every_tile_reaches_food_within_the_starving_budget() -> void:
	var budget := _budget()
	var rows := PackedStringArray()
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		var worst := 0.0
		for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
			var p := _placed(t, 0, with_anchor)
			var arena := ChunkArena.from_shells(p.colliders)
			check_eq(WorldChecks.reach_problems(arena, p.zones, TILE_BOUNDS, budget, p.homes), PackedStringArray(),
				"%s %s its anchor" % [id, "with" if with_anchor else "without"])
			worst = maxf(worst, float(_worst_reach(arena, p.zones, TILE_BOUNDS).worst))
		rows.append("%s %.1f" % [id, worst])
	print("test-tiles: reach worst per tile (budget %.2f): %s" % [budget, ", ".join(rows)])


## G2's seams at identity (B-16): world_checks.seam_problems with every ordered pair of tiles placed
## east, north and on the diagonal, and the home block against every tile in the 8 slots along its
## edges. The soak over every orientation is T1's (tests/test_seams.gd). The positive control: the
## same check run on reef_a with one shell more, inside the reach of giant_husk's lair across the
## seam, must report it.
func test_slow_seams_hold_between_tiles_and_against_the_home_edges() -> void:
	check_eq(WorldChecks.seam_problems(content, species, parts, 1, IDENTITY), PackedStringArray(),
		"rules 9 and 10 and no overlap across every seam at identity")
	var control := WorldContent.new()
	control.config = content.config
	control.kit = content.kit
	control.home = content.home
	control.layout = content.layout
	control.tiles = TileCatalog.new()
	control.tiles.bands = tiles.bands.duplicate()
	for id in [CONTROL_A, CONTROL_B]:
		control.tiles.tiles[id] = tiles.tiles[id].duplicate(true)
	control.tiles.tiles[CONTROL_A].shells.append({"id": "control", "center": PackedFloat64Array(CONTROL_SHELL), "radius": CONTROL_R})
	var found := WorldChecks.tile_seam_problems(control, species, parts, 1, IDENTITY)
	var reported := PackedStringArray()
	for e in found:
		if e.contains("%s@o0:control" % CONTROL_A) and e.contains("| b0/%s@o0 east" % CONTROL_B):
			reported.append(e)
	check(not reported.is_empty(), "the control shell at %s, r %s, west of %s is reported: %s" % [CONTROL_SHELL, CONTROL_R, CONTROL_B, found])
	print("test-tiles: the identity seams are clean; the control reports %s" % [reported])


# ---- Soak ----

## G2 at every orientation the generator may place a tile in: world_checks.orientation_problems
## (B-16), rules 2 to 8 with every tile laid in each orientation.
func test_soak_every_tile_keeps_every_rule_at_all_8_orientations() -> void:
	check_eq(WorldChecks.orientation_problems(content, species, parts, 1), PackedStringArray(), "every tile at every orientation")


func test_soak_every_tile_reaches_food_at_all_8_orientations() -> void:
	var budget := _budget()
	var worst := 0.0
	var worst_at := ""
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		for o in 8:
			for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
				var p := _placed(t, o, with_anchor)
				var arena := ChunkArena.from_shells(p.colliders)
				check_eq(WorldChecks.reach_problems(arena, p.zones, TILE_BOUNDS, budget, p.homes), PackedStringArray(),
					"%s at orientation %d %s its anchor" % [id, o, "with" if with_anchor else "without"])
				var w := float(_worst_reach(arena, p.zones, TILE_BOUNDS).worst)
				if w > worst:
					worst = w
					worst_at = "%s o%d" % [id, o]
	print("test-tiles: reach worst over 8 orientations %.1f tm (%s; budget %.2f)" % [worst, worst_at, budget])


func test_soak_the_fine_food_bound_stays_under_the_cap() -> void:
	var bound := WorldChecks.food_bound(content, FOOD_FINE_TM)
	var cap := int(content.config.caps.food_items)
	check(int(bound.worst) <= cap, "at most %d items within the food ring of any point (%d at %s)" % [cap, int(bound.worst), bound.get("at")])
	print("test-tiles: fine food bound %d at %s (cap %d)" % [int(bound.worst), bound.get("at"), cap])


## B-17: sample_sites(gen, band, size, centre, 40) counts the live reach discs that meet a 40 tm disc.
## Each arrangement is a world seed; its discs are uniform over the 2 km square round home.
func test_soak_no_disc_of_any_arrangement_wakes_more_than_10_sites() -> void:
	var worst := -1
	var worst_at := ""
	for i in SAMPLE_ARRANGEMENTS:
		var gen := WorldGen.create(content, species, SAMPLE_SEED + i)
		var rng := RandomNumberGenerator.new()
		rng.seed = SAMPLE_SEED + i
		for k in SAMPLE_DISCS:
			var at := PackedFloat64Array([rng.randf_range(-SAMPLE_HALF_TM, SAMPLE_HALF_TM), rng.randf_range(-SAMPLE_HALF_TM, SAMPLE_HALF_TM)])
			var n := WorldChecks.sample_sites(gen, 0, 1, at, SAMPLE_RADIUS_TM)
			if n > worst:
				worst = n
				worst_at = "seed %d at %s" % [SAMPLE_SEED + i, at]
	check(worst <= SAMPLE_MAX_SITES, "at most %d live reach discs meet any %.0f tm disc (%d, %s)" % [SAMPLE_MAX_SITES, SAMPLE_RADIUS_TM, worst, worst_at])
	check(worst > 0, "the sample met live sites")
	print("test-tiles: site sample worst %d (%s) over %d x %d" % [worst, worst_at, SAMPLE_ARRANGEMENTS, SAMPLE_DISCS])
