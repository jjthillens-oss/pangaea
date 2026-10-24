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
##
## S2 (S2G7): each check runs again at size 2, the band's second size, in that size's tm (a tile is
## 40 tm there; the cell keeps r 0.5 tm and the starving budget): the colliders there (no "sink"
## shells), the zones there ("drop" gone, "thin" at capacity x 0.4, a zone that can hold no item is
## no food), each live site's discs with k and, for two posts, both posts and their union. Threat
## coverage at sizes 1 and 2 is the region design's and TileCatalog's rule 7: at size 2 a sunlit or
## reef tile of set 0 keeps one M1 site live (a rammer on the feast zone, a lair; the cell now
## outgrows them), one of set 1 a size-2 threat, so edge neighbours of a region alternate.

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
## A sunlit tile's size-2 threat (S2, set 1): an elder rammer guarding a zone, or a Lurker where every
## zone's disc would reach too near the landmark anchor (PROPOSED).
const SUNLIT_THREATS_AT_TWO := ["elder_rammer", "lurker"]
## The set whose sunlit and reef tiles keep an M1 site live at size 2 instead of a threat (PROPOSED;
## TileCatalog's rule 7): one live site a tile, as the site sample allows (B-17: a 40 tm disc meets
## about nine 40 tm tiles; with an M1 site and a threat in each it met 13, the limit is 10).
const OUTGROWN_SET := TileCatalog.SECOND_SIZE_OUTGROWN_SET
## A tile's zones at size 2 (PROPOSED): one of this capacity or more thins (x 0.4; a thinned 8 or 16
## would hold no item, floor(3.2 / 8) = 0), unless a size-2 threat guards it there; the rest keep.
## So the food bound holds at size 2 (all kept, it measures 188 against the cap of 120).
const THIN_FROM_CAPACITY := 32.0
## The smallest slack a site keeps inside its tile (rule 6's inset) and from the landmark anchor
## (rule 8), so retuning cannot wear them down to the rule unnoticed; per size, in that size's bu
## (the size-2 discs were placed by search near the rule: 0.24 and 0.27 measured; PROPOSED).
const MIN_INSET_SLACK := {1: 1.0, 2: 0.2}
const MIN_ANCHOR_SLACK := {1: 1.0, 2: 0.2}
## The seam check's positive control (s1-content 5.2): a shell put just across the seam from
## giant_husk's lair la, inside its reach circle where rule 9 wants clear water; with giant_husk east
## of reef_a, it sits in reef_a's frame at CONTROL_SHELL.
const CONTROL_A := "reef_a"
const CONTROL_B := "giant_husk"
const CONTROL_SHELL := [35.5, -4.0]
const CONTROL_R := 0.6
const IDENTITY: PackedInt32Array = [0]
## The size-2 controls (S2G7): giant_husk's one-post Lurker, reef_e's two-post one (west of
## giant_husk for its control), the ring's elder rammer, and the home block's edge slot east of it.
const CONTROL_2_SITE := "lk"
const CONTROL_U := "reef_e"
const CONTROL_2_HOME_SITE := "re"
const CONTROL_2_SLOT := Vector2i(1, -1)
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


## The sizes this build runs.
func _sizes() -> Array:
	return range(content.config.size_start, content.config.max_size_in_build + 1)


## Tile t turned to orientation o at `size`, in that size's tm: its colliders there (with or without
## the landmark's) and its zones there that can hold an item, as ReachGrid takes them, and the homes
## (both posts' for two) of its sites live there (must_reach).
func _placed(t: Dictionary, o: int, with_anchor: bool = true, size := 1) -> Dictionary:
	var s := WorldConfig.bu_to_tm(size)
	var colliders: Array[Dictionary] = []
	for c in TileCatalog.colliders_at(t, TileCatalog.colliders_of(t, kit), size):
		if with_anchor or c.id != TileCatalog.LANDMARK_ID:
			colliders.append({"id": "%s/%s" % [t.id, c.id], "center": _orient(c.center, o) * s, "radius": float(c.radius) * s})
	var zones: Array[Dictionary] = []
	for z in WorldChecks.zones_at(t.zones, int(t.band), size, content):
		if _items(z) >= 1:
			zones.append({"id": "%s/%s" % [t.id, z.id], "center": _orient(Vector2(z.center[0], z.center[1]), o) * s, "radius": float(z.radius) * s})
	var homes: Array[Vector2] = []
	for site in t.sites:
		if site.sizes.has(size):
			homes.append(_orient(Vector2(site.home[0], site.home[1]), o) * s)
			if not site.get("post_b", {}).is_empty():
				homes.append(_orient(Vector2(site.post_b.home[0], site.post_b.home[1]), o) * s)
	return {"colliders": colliders, "zones": zones, "homes": homes}


## A tile at `size`, in that size's tm: [-32, 32)^2 bu x bu_to_tm(size).
static func _tile_bounds(size: int) -> Rect2:
	var s := WorldConfig.bu_to_tm(size)
	return Rect2(TILE_BOUNDS.position * s, TILE_BOUNDS.size * s)


## A zone's circle ({center, radius}) for the discs, or {} for none.
static func _circle(z: Dictionary) -> Dictionary:
	return {} if z.is_empty() else {"center": Vector2(z.center[0], z.center[1]), "radius": float(z.radius)}


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
		# S2 (s2-interfaces 4.3, PROPOSED): a size-2 threat lives at size 2 only; an M1 site at size 1,
		# and at size 2 too for the one a sunlit or reef tile of OUTGROWN_SET keeps there (the sunlit
		# rammer on the feast zone, BP-5's parked grazer's; a reef lair), in place of a threat.
		var threats_at_two := []
		var outgrown_at_two := []
		for s in t.sites:
			if species.entry_size(s.species) == 2:
				check_eq(s.sizes, [2] as Array[int], "%s site '%s': a size-2 threat lives at size 2 only" % [id, s.id])
				threats_at_two.append(s.species)
				continue
			if s.sizes.has(2):
				outgrown_at_two.append("%s:%s" % [species.behavior_of(s.species), s.territory_zone])
			check(s.sizes == ([1] as Array[int]) or s.sizes == ([1, 2] as Array[int]), "%s site '%s': an M1 site lives at size 1, or 1 and 2 (%s)" % [id, s.id, s.sizes])
			if species.behavior_of(s.species) == "territorial":
				var z := _zone_of(t, s.territory_zone)
				if t.region == "sunlit" and float(z.get("capacity", 0.0)) >= SUNLIT_RAMMER_CAPACITY:
					rammers += 1
			elif species.behavior_of(s.species) == "ambush":
				ambushes += 1
		var guarded := []
		for s in t.sites:
			if s.sizes.has(2) and species.entry_size(s.species) == 2 and not str(s.territory_zone).is_empty():
				guarded.append(s.territory_zone)
		var outgrown: bool = t.region in ["sunlit", "reef"] and int(t.set) == OUTGROWN_SET
		for z in t.zones:
			var want := "thin" if float(z.capacity) >= THIN_FROM_CAPACITY and not guarded.has(z.id) else "keep"
			check_eq(z.at_second_size, want, "%s zone '%s' (capacity %s%s) at size 2" % [id, z.id, z.capacity, ", guarded" if guarded.has(z.id) else ""])
		match t.region:
			"sunlit":
				var rich := _zone_of(t, "ra")
				check(float(rich.get("radius", 0.0)) == SUNLIT_RICH_R and float(rich.get("capacity", 0.0)) == SUNLIT_RICH_CAPACITY,
					"%s: the feast zone ra is R %s, capacity %s (%s)" % [id, SUNLIT_RICH_R, SUNLIT_RICH_CAPACITY, rich])
				check(rammers >= 1, "%s: a rammer guards a zone of capacity %s or more" % [id, SUNLIT_RAMMER_CAPACITY])
				sunlit_least = mini(sunlit_least, items)
				if outgrown:
					check_eq(threats_at_two, [], "%s (set %d): no threat at size 2" % [id, t.set])
					check_eq(outgrown_at_two, ["territorial:ra"], "%s (set %d): its rammer on the feast zone lives at size 2" % [id, t.set])
				else:
					check(threats_at_two.size() == 1 and threats_at_two[0] in SUNLIT_THREATS_AT_TWO,
						"%s: one size-2 threat, an elder rammer or a Lurker where the anchor leaves it no zone (%s)" % [id, threats_at_two])
					check_eq(outgrown_at_two, [], "%s (set %d): no M1 site at size 2" % [id, t.set])
			"reef":
				check_eq(t.shells.size(), REEF_SHELLS, "%s: the reef's shells" % id)
				check(t.sites.size() >= 2 and ambushes >= 1, "%s: at least 2 sites, an ambush lair among them (%d, %d)" % [id, t.sites.size(), ambushes])
				if outgrown:
					check_eq(threats_at_two, [], "%s (set %d): no threat at size 2" % [id, t.set])
					check_eq(outgrown_at_two, ["ambush:"], "%s (set %d): one lair lives at size 2" % [id, t.set])
				else:
					check_eq(threats_at_two, ["lurker"], "%s: one Lurker at size 2" % id)
					check_eq(outgrown_at_two, [], "%s (set %d): no M1 site at size 2" % [id, t.set])
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
				check_eq(outgrown_at_two, [], "%s: no M1 site at size 2" % id)
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


## Rule 6's inset and rule 8's anchor clearance, with the slack each site keeps beyond the rule, at
## each size in that size's bu (rule 8 binds the species that can attack the cell there). Formulas as
## TileCatalog's rule 6; the table is printed for T4.4's retuning.
func test_sites_keep_a_margin_inside_their_tile_and_from_the_landmark() -> void:
	for size in _sizes():
		var m := _margins(size)
		check(int(m.sites) > 0 and m.rows.size() >= int(m.sites), "size %d: the table covers all %d live sites (%d rows)" % [size, m.sites, m.rows.size()])
		check(float(m.inset) >= float(MIN_INSET_SLACK[size]), "size %d: every reach disc keeps %.1f bu inside its tile's inset; %s keeps %.2f" % [
			size, MIN_INSET_SLACK[size], m.inset_at, m.inset])
		check(float(m.anchor) >= float(MIN_ANCHOR_SLACK[size]), "size %d: every reach disc keeps %.1f bu beyond rule 8 from the anchor; %s keeps %.2f" % [
			size, MIN_ANCHOR_SLACK[size], m.anchor_at, m.anchor])
		print("test-tiles: size %d: least inset slack %.2f (%s), least anchor slack %.2f (%s)" % [size, m.inset, m.inset_at, m.anchor, m.anchor_at])
		print("test-tiles: size %d: %s" % [size, "; ".join(m.rows)])


## The margin table at `size`: a row per disc of each site live there (a two-post site's posts and
## union), and the least slack of each kind.
func _margins(size: int) -> Dictionary:
	var fair := species.fairness
	var st := WorldConfig.bu_to_tm(size)
	var radii_n := TileCatalog.radii_at(species, parts, size)
	var out := {"inset": INF, "inset_at": "", "anchor": INF, "anchor_at": "", "rows": PackedStringArray(), "sites": 0}
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		for s in t.sites:
			if not s.sizes.has(size):
				continue
			out.sites += 1
			var post_b: Dictionary = s.get("post_b", {})
			var r := float(radii_n[s.species])
			var attacks := Relationships.can_attack_player(species.q_of(s.species, size))
			for d in WorldChecks.site_discs(species, s, Vector2(s.home[0], s.home[1]), _circle(_zone_of(t, s.territory_zone)), post_b,
					_circle(_zone_of(t, str(post_b.get("territory_zone", "")))), size):
				var c: Vector2 = d.disc.center
				var where := "%s/%s%s" % [id, s.id, d.label]
				var inset := TileCatalog.HALF_TILE_BU - maxf(absf(c.x), absf(c.y)) - float(d.disc.radius) - r - float(fair.leash_band_margin_m) / st
				if inset < float(out.inset):
					out.inset = inset
					out.inset_at = where
				var anchor := INF
				if attacks and t.landmark_anchor.size() == 2:
					var a := Vector2(t.landmark_anchor[0], t.landmark_anchor[1])
					anchor = a.distance_to(c) - float(d.disc.radius) - r - (kit.collide_radius_bu + PoolLayout.CELL_RADIUS / st + TileCatalog.ANCHOR_GAP_BU) \
						- (float(fair.respawn_clear_m) + TileCatalog.ANCHOR_CLEAR_EXTRA) / st
					if anchor < float(out.anchor):
						out.anchor = anchor
						out.anchor_at = where
				out.rows.append("%s inset %.2f anchor %s" % [where, inset, "-" if anchor == INF else "%.2f" % anchor])
	return out


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


## world_checks.zones_at, the zones the size-2 checks take (as WorldGen.chunk(2, ...) does): at the
## band's second size a "drop" zone is gone and a "thin" one holds capacity x
## second_size.zone_thin_share (0.4, D-60), the rest as they are; at size 1 every zone as it is.
func test_the_size_2_checks_take_the_zones_there() -> void:
	check_eq(float(content.config.second_size.zone_thin_share), 0.4, "D-60's share")
	var zones: Array = tiles.tiles.reef_a.zones.duplicate(true)
	zones[0].at_second_size = "drop"
	zones[1].at_second_size = "thin"
	zones[2].at_second_size = "keep"
	check_eq(WorldChecks.zones_at(zones, 0, 1, content), zones, "size 1: every zone as it is")
	var at_2 := WorldChecks.zones_at(zones, 0, 2, content)
	check_eq(at_2.size(), zones.size() - 1, "size 2: the drop zone is gone")
	if at_2.size() == zones.size() - 1:
		check_eq([at_2[0].id, float(at_2[0].capacity)], [zones[1].id, float(zones[1].capacity) * 0.4], "the thin zone at x 0.4")
		check_eq([at_2[1].id, float(at_2[1].capacity)], [zones[2].id, float(zones[2].capacity)], "the kept zone as it is")
	check_eq(WorldChecks.zones_at(zones, 1, 2, content), zones, "size 2 is band 1's first size: every zone as it is")


## Plan A.2's food bound at each size: the most items any arrangement puts within the food ring of a
## point stays under caps.food_items (at size 2 with the zones there: drop gone, thin thinned).
func test_the_coarse_food_bound_stays_under_the_cap() -> void:
	var cap := int(content.config.caps.food_items)
	for size in _sizes():
		var bound := WorldChecks.food_bound(content, FOOD_COARSE_TM, size)
		check(int(bound.worst) <= cap, "size %d: at most %d items within the food ring of any point (%d at %s)" % [size, cap, int(bound.worst), bound.get("at")])
		check(int(bound.worst) >= FOOD_FLOOR, "size %d: the bound saw the tiles (%d >= %d)" % [size, int(bound.worst), FOOD_FLOOR])
		print("test-tiles: size %d: coarse food bound %d at %s (cap %d)" % [size, int(bound.worst), bound.get("at"), cap])


## Static #33 at each size (S2G7): every zone there, at its capacity there (a "thin" zone's x 0.4),
## yields at most the M1 unguarded maximum, growth x capacity x (0.25 + REGROW_FLOOR) <= 1.152.
func test_every_zone_meets_static_33_at_each_size() -> void:
	var zones := 0
	for size in _sizes():
		var most := 0.0
		var most_at := ""
		for id in _ids():
			var t: Dictionary = tiles.tiles[id]
			for z in WorldChecks.zones_at(t.zones, int(t.band), size, content):
				zones += 1
				var yield_rate := float(z.growth_rate) * float(z.capacity) * (TileCatalog.YIELD_SHARE + EcologyRegion.REGROW_FLOOR)
				check(yield_rate <= TileCatalog.MAX_ZONE_YIELD, "size %d: %s zone '%s' yields %.3f; static #33 allows %.3f" % [
					size, id, z.id, yield_rate, TileCatalog.MAX_ZONE_YIELD])
				if yield_rate > most:
					most = yield_rate
					most_at = "%s/%s" % [id, z.id]
		print("test-tiles: size %d: the richest yield %.3f (%s)" % [size, most, most_at])
	check(zones > 300, "every tile's zones at both sizes (%d)" % zones)


# ---- Slow ----

## G5 and F9 at each size: from every open point of each tile the sea outside reaches, a starving cell
## reaches one of the tile's own zones within the budget, with and without its landmark's collider
## (a rare tile: with its set piece), and every live site home lies in that sea (B-29's must_reach).
## At size 2 in that size's tm, with the colliders and the zones there.
func test_slow_every_tile_reaches_food_within_the_starving_budget() -> void:
	var budget := _budget()
	for size in _sizes():
		var rows := PackedStringArray()
		for id in _ids():
			var t: Dictionary = tiles.tiles[id]
			var worst := 0.0
			for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
				var p := _placed(t, 0, with_anchor, size)
				var arena := ChunkArena.from_shells(p.colliders)
				check_eq(WorldChecks.reach_problems(arena, p.zones, _tile_bounds(size), budget, p.homes), PackedStringArray(),
					"size %d: %s %s its anchor" % [size, id, "with" if with_anchor else "without"])
				worst = maxf(worst, float(_worst_reach(arena, p.zones, _tile_bounds(size)).worst))
			rows.append("%s %.1f" % [id, worst])
		print("test-tiles: size %d: reach worst per tile (budget %.2f): %s" % [size, budget, ", ".join(rows)])


## G2's seams at identity (B-16), at each size: world_checks.seam_problems with every ordered pair of
## tiles placed east, north and on the diagonal, and the home block against every tile in the 8 slots
## along its edges. The soak over every orientation is T1's (tests/test_seams.gd). The positive
## control: the same check run on reef_a with one shell more, inside the reach of giant_husk's lair
## across the seam, must report it (size 2's controls follow).
func test_slow_seams_hold_between_tiles_and_against_the_home_edges() -> void:
	for size in _sizes():
		check_eq(WorldChecks.seam_problems(content, species, parts, size, IDENTITY), PackedStringArray(),
			"size %d: rules 9 and 10 and no overlap across every seam at identity" % size)
	var found := WorldChecks.tile_seam_problems(_control(CONTROL_A, Vector2(CONTROL_SHELL[0], CONTROL_SHELL[1]), CONTROL_R), species, parts, 1, IDENTITY)
	var reported := _control_reports(found, CONTROL_A, "site 'la' of")
	check(not reported.is_empty(), "the control shell at %s, r %s, west of %s is reported: %s" % [CONTROL_SHELL, CONTROL_R, CONTROL_B, found])
	print("test-tiles: the identity seams are clean at each size; the control reports %s" % [reported])


## S2G7's seam controls at size 2, placed from the species' own discs (k_of, two_post_disc_for), not
## world_checks': a shell of the tile west of giant_husk on its Lurker's leash circle is reported, but
## not when the shell sinks at size 2 nor at size 1 (no Lurker there); a shell of giant_husk on the
## leash circle of reef_e's two-post Lurker's union (reef_e west of giant_husk), clear of both posts'
## bands, is reported against the union; a shell of the tile in the home block's edge slot on the
## ring elder rammer's leash circle is reported across the block's edge.
func test_the_size_2_seam_controls_are_reported() -> void:
	var tile_bu := TileCatalog.HALF_TILE_BU * 2.0
	var k := WorldConfig.k_of(2, 2)
	var lk := _site(tiles.tiles[CONTROL_B], CONTROL_2_SITE)
	var d := species.reach_disc_for({"species": lk.species, "home": _v(lk.home), "heading": float(lk.heading)}, {}, k)
	var at: Vector2 = Vector2(d.center) - Vector2(float(d.radius), 0.0) + Vector2(tile_bu, 0.0)
	var one := "site '%s' of b0/%s@o0" % [CONTROL_2_SITE, CONTROL_B]
	var found := WorldChecks.tile_seam_problems(_control(CONTROL_A, at, CONTROL_R), species, parts, 2, IDENTITY)
	check(not _control_reports(found, CONTROL_A, one).is_empty(), "the shell at %s on %s's leash circle: %s" % [at, one, found])
	var sunk := WorldChecks.tile_seam_problems(_control(CONTROL_A, at, CONTROL_R, "sink"), species, parts, 2, IDENTITY)
	check(_control_reports(sunk, CONTROL_A, one).is_empty(), "the same shell sunk at size 2 is not there: %s" % [sunk])
	var at_1 := WorldChecks.tile_seam_problems(_control(CONTROL_A, at, CONTROL_R), species, parts, 1, IDENTITY)
	check(_control_reports(at_1, CONTROL_A, "site '%s'" % CONTROL_2_SITE).is_empty(), "the Lurker is not there at size 1")
	# Rule 9's band there is the size's radius in tm plus leash_band_margin_m: a shell 0.05 tm inside
	# it is reported, one 0.05 tm outside it is not.
	var band_tm := (species.at_size(lk.species, 2, parts).phenotype as Phenotype).radius + float(species.fairness.leash_band_margin_m)
	for side in [[-0.05, true], [0.05, false]]:
		var off: Vector2 = Vector2(d.center) - Vector2(float(d.radius) + (band_tm + side[0]) / WorldConfig.bu_to_tm(2) + CONTROL_R, 0.0)
		var near := WorldChecks.tile_seam_problems(_control(CONTROL_A, off + Vector2(tile_bu, 0.0), CONTROL_R), species, parts, 2, IDENTITY)
		check_eq(not _control_reports(near, CONTROL_A, one).is_empty(), side[1], "a shell %+.2f tm from the band of %.2f tm: %s" % [side[0], band_tm, near])
	# Two posts: the union's leash circle where it leaves both posts' discs.
	var two := _site(tiles.tiles[CONTROL_U], CONTROL_2_SITE)
	var both := species.two_post_disc_for({"species": two.species, "home": _v(two.home), "heading": float(two.heading)}, {},
		{"home": _v(two.post_b.home), "heading": float(two.post_b.heading)}, {}, k)
	var axis := (Vector2(both.posts[1].center) - Vector2(both.posts[0].center)).normalized()
	var point: Vector2 = Vector2(both.center) + Vector2(-axis.y, axis.x) * float(both.radius)
	var band := (float(species.fairness.leash_band_margin_m) + PoolLayout.CELL_RADIUS) / WorldConfig.bu_to_tm(2) + CONTROL_R
	for post in both.posts:
		check(point.distance_to(post.center) - float(post.radius) > band, "the point %s is clear of the post at %s" % [point, post.center])
	var union := "site '%s' union of b0/%s@o0" % [CONTROL_2_SITE, CONTROL_U]
	var found_u := WorldChecks.tile_seam_problems(_control(CONTROL_B, point - Vector2(tile_bu, 0.0), CONTROL_R, "keep", CONTROL_U), species, parts, 2, IDENTITY)
	check(not _control_reports(found_u, CONTROL_B, union, CONTROL_U).is_empty(), "the shell at %s on %s's leash circle: %s" % [point, union, found_u])
	# The home block's edge: the ring elder's leash circle, east of it, in the slot's tile frame.
	var home := content.home
	var re: Dictionary = home.sites.filter(func(x: Dictionary) -> bool: return x.id == CONTROL_2_HOME_SITE)[0]
	var zone: Dictionary = home.zones.filter(func(z: Dictionary) -> bool: return z.id == re.territory_zone)[0]
	var de := species.reach_disc_for({"species": re.species, "home": Vector2(re.x, re.y), "heading": float(re.heading)},
		{"center": Vector2(zone.x, zone.y), "radius": float(zone.radius)}, k)
	var east: Vector2 = Vector2(de.center) + Vector2(float(de.radius), 0.0)
	var slot := Vector2(CONTROL_2_SLOT.x * 2 + 1, CONTROL_2_SLOT.y * 2 + 1) * TileCatalog.HALF_TILE_BU
	var edge := "site '%s' of %s" % [CONTROL_2_HOME_SITE, home.where]
	var found_h := WorldChecks.home_seam_problems(_control(CONTROL_A, east - slot, CONTROL_R), species, parts, 2, IDENTITY)
	var hits := Array(found_h).filter(func(e: String) -> bool:
		return e.contains("at tile %s" % CONTROL_2_SLOT) and e.contains("%s@o0:control" % CONTROL_A) and e.contains(edge))
	check(not hits.is_empty(), "the shell at %s on %s's leash circle: %s" % [east, edge, found_h])
	print("test-tiles: the size-2 controls report %s; %s; %s" % [_control_reports(found, CONTROL_A, one), _control_reports(found_u, CONTROL_B, union, CONTROL_U), hits])


func _site(t: Dictionary, id: String) -> Dictionary:
	return t.sites.filter(func(x: Dictionary) -> bool: return x.id == id)[0]


static func _v(p: PackedFloat64Array) -> Vector2:
	return Vector2(p[0], p[1])


## `west` (reef_a) and giant_husk only, with one shell more in `tile` at `at` (bu), r `r`, that
## `second` at size 2.
func _control(tile: String, at: Vector2, r: float, second := "keep", west := CONTROL_A) -> WorldContent:
	var control := WorldContent.new()
	control.config = content.config
	control.kit = content.kit
	control.home = content.home
	control.layout = content.layout
	control.tiles = TileCatalog.new()
	control.tiles.bands = tiles.bands.duplicate()
	for id in [west, CONTROL_B]:
		control.tiles.tiles[id] = tiles.tiles[id].duplicate(true)
	control.tiles.tiles[tile].shells.append({"id": "control", "center": PackedFloat64Array([at.x, at.y]), "radius": r, "at_second_size": second})
	return control


## The problems that name the control shell of `tile`, giant_husk east of `west` (reef_a), and `site`.
static func _control_reports(found: PackedStringArray, tile: String, site: String, west := CONTROL_A) -> PackedStringArray:
	var out := PackedStringArray()
	for e in found:
		if e.contains("%s@o0:control" % tile) and e.contains("seam b0/%s@o0 | b0/%s@o0 east" % [west, CONTROL_B]) and e.contains(site):
			out.append(e)
	return out


# ---- Soak ----

## G2 at every orientation the generator may place a tile in, at each size:
## world_checks.orientation_problems (B-16), rules 2 to 8 with every tile laid in each orientation.
func test_soak_every_tile_keeps_every_rule_at_all_8_orientations() -> void:
	for size in _sizes():
		check_eq(WorldChecks.orientation_problems(content, species, parts, size), PackedStringArray(), "size %d: every tile at every orientation" % size)


func test_soak_every_tile_reaches_food_at_all_8_orientations() -> void:
	var budget := _budget()
	for size in _sizes():
		var worst := 0.0
		var worst_at := ""
		for id in _ids():
			var t: Dictionary = tiles.tiles[id]
			for o in 8:
				for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
					var p := _placed(t, o, with_anchor, size)
					var arena := ChunkArena.from_shells(p.colliders)
					check_eq(WorldChecks.reach_problems(arena, p.zones, _tile_bounds(size), budget, p.homes), PackedStringArray(),
						"size %d: %s at orientation %d %s its anchor" % [size, id, o, "with" if with_anchor else "without"])
					var w := float(_worst_reach(arena, p.zones, _tile_bounds(size)).worst)
					if w > worst:
						worst = w
						worst_at = "%s o%d" % [id, o]
		print("test-tiles: size %d: reach worst over 8 orientations %.1f tm (%s; budget %.2f)" % [size, worst, worst_at, budget])


func test_soak_the_fine_food_bound_stays_under_the_cap() -> void:
	var cap := int(content.config.caps.food_items)
	for size in _sizes():
		var bound := WorldChecks.food_bound(content, FOOD_FINE_TM, size)
		check(int(bound.worst) <= cap, "size %d: at most %d items within the food ring of any point (%d at %s)" % [size, cap, int(bound.worst), bound.get("at")])
		print("test-tiles: size %d: fine food bound %d at %s (cap %d)" % [size, int(bound.worst), bound.get("at"), cap])


## B-17: sample_sites(gen, band, size, centre, 40) counts the live reach discs that meet a 40 tm disc,
## at each size. Each arrangement is a world seed; its discs are uniform over the 2 km square round home.
func test_soak_no_disc_of_any_arrangement_wakes_more_than_10_sites() -> void:
	for size in _sizes():
		var worst := -1
		var worst_at := ""
		for i in SAMPLE_ARRANGEMENTS:
			var gen := WorldGen.create(content, species, SAMPLE_SEED + i)
			var rng := RandomNumberGenerator.new()
			rng.seed = SAMPLE_SEED + i
			for k in SAMPLE_DISCS:
				var at := PackedFloat64Array([rng.randf_range(-SAMPLE_HALF_TM, SAMPLE_HALF_TM), rng.randf_range(-SAMPLE_HALF_TM, SAMPLE_HALF_TM)])
				var n := WorldChecks.sample_sites(gen, 0, size, at, SAMPLE_RADIUS_TM)
				if n > worst:
					worst = n
					worst_at = "seed %d at %s" % [SAMPLE_SEED + i, at]
		check(worst <= SAMPLE_MAX_SITES, "size %d: at most %d live reach discs meet any %.0f tm disc (%d, %s)" % [size, SAMPLE_MAX_SITES, SAMPLE_RADIUS_TM, worst, worst_at])
		check(worst > 0, "size %d: the sample met live sites" % size)
		print("test-tiles: size %d: site sample worst %d (%s) over %d x %d" % [size, worst, worst_at, SAMPLE_ARRANGEMENTS, SAMPLE_DISCS])


## S3G5c (BP3-8): every band-1 landmark anchor, in all 8 orientations, at sizes 3 and 4, has a clear
## point for the cell within LANDMARK_SPIRAL_RINGS rings of the spiral on its own tile's colliders
## (sink shells gone at 4). A neighbour cannot matter: an anchor sits at least 7 bu inside its tile
## (rule 4) and a neighbour's colliders keep 4 bu from the edge (rules 2 and 5), 11 bu in all, past
## the 7.2 bu the spiral and the cell reach at size 4. The control grows the landmark collider to 5 bu.
const B1_DIR := "res://tests/fixtures/world/tiles_b1/b1"
const LANDMARK_SPIRAL_RINGS := 8
const GROWN_LANDMARK_BU := 5.0


func _b1_tiles() -> TileCatalog:
	var cat := TileCatalog.new()
	var files := {}
	for name in DirAccess.get_files_at(B1_DIR):
		if name.get_extension() == "json":
			files[name.get_basename()] = JSON.parse_string(FileAccess.get_file_as_string(B1_DIR.path_join(name)))
	for id in WorldConfig._sorted(files.keys()):
		cat.add_tile(files[id], 1, id)
	return cat


## The (tile@orientation, size) cases whose anchor has no clear point within the rings, and how many
## cases there were.
func _anchors_without_room(cat: TileCatalog, p_kit: PlacementKit) -> Dictionary:
	var blocked := PackedStringArray()
	var cases := 0
	for id in WorldConfig._sorted(cat.tiles.keys()):
		var t: Dictionary = cat.tiles[id]
		if t.landmark_anchor.size() != 2:
			continue
		for o in WorldChecks.ALL_ORIENTATIONS:
			var ot := WorldChecks.oriented_tile(t, o)
			for size in [3, 4]:
				var s := WorldConfig.bu_to_tm(size)
				var arena := PoolArena.create(1000.0, 1000.0, 1000.0)
				for c in TileCatalog.colliders_at(ot, TileCatalog.colliders_of(ot, p_kit), size):
					arena.add_rock(c.id, c.center * s, float(c.radius) * s)
				var anchor := Vector2(ot.landmark_anchor[0], ot.landmark_anchor[1]) * s
				cases += 1
				if not PoolSim.clear_point_on(arena, anchor, Relationships.PLAYER_RADIUS, LANDMARK_SPIRAL_RINGS).is_finite():
					blocked.append("%s at %d" % [ot.where, size])
	return {"blocked": blocked, "cases": cases}


func test_every_band_1_anchor_has_a_clear_point_within_8_rings() -> void:
	var cat := _b1_tiles()
	check_eq(cat.load_problems, PackedStringArray(), "the band-1 fixture tiles load")
	var got := _anchors_without_room(cat, PlacementKit.load_from())
	check(got.cases > 0, "some anchors were tried (%d)" % got.cases)
	check_eq(got.blocked, PackedStringArray(), "every anchor has a clear point within %d rings" % LANDMARK_SPIRAL_RINGS)
	var grown := PlacementKit.load_from()
	grown.collide_radius_bu = GROWN_LANDMARK_BU
	var control := _anchors_without_room(cat, grown)
	# At 3 it reaches past the spiral and the cell (5.5 tm against 4); at 4 it is 3.125 tm and the
	# eighth ring clears it, so the control blocks every case at size 3.
	var at_3 := Array(control.blocked).filter(func(b: String) -> bool: return b.ends_with(" at 3"))
	check_eq(at_3.size(), control.cases / 2, "control: a %.0f bu landmark blocks every anchor at size 3 (%d)" % [GROWN_LANDMARK_BU, at_3.size()])


## T3.7: the shipped band-1 tiles (18 ordinary and 4 rare) read at the size-4 top pass every rule at
## sizes 3 and 4, and every anchor of theirs keeps S3G5c's clear point in all 8 orientations. The
## soak test below runs rules 2 to 8 in every orientation, as band 0's does.
const B1_SHIPPED := "res://game/data/tiles/b1"
var content_4: WorldContent


func _content_4() -> WorldContent:
	if content_4 == null:
		content_4 = WorldContent.load_from(WorldChecks.shipped_world_at(4), PoolLayout.load_from(), species)
	return content_4


func test_the_shipped_band_1_tiles_validate_and_keep_room_at_their_anchors() -> void:
	var c := _content_4()
	var b1 := TileCatalog.load_from({1: B1_SHIPPED})
	check_eq(b1.load_problems, PackedStringArray(), "the band-1 tiles read")
	check_eq(b1.tiles.size(), 22, "18 ordinary tiles and 4 rare ones")
	for size in [3, 4]:
		check_eq(c.tiles.validate(species, c.kit, parts, size), PackedStringArray(), "size %d: every rule" % size)
	# A zone that lives at 4 holds an item there (a thinned 8 or 12 would hold none, floor(4.8 / 8) = 0).
	var blocks: Array = b1.tiles.values()
	blocks.append(c.cradle_of(1)._block())
	for t in blocks:
		for z in WorldChecks.zones_at(t.zones, 1, 4, c):
			check(_items(z) >= 1, "%s zone '%s' holds an item at size 4 (capacity %s, %s)" % [t.where, z.id, z.capacity, z.at_second_size])
	var got := _anchors_without_room(b1, c.kit)
	check(got.cases > 0, "some anchors were tried (%d)" % got.cases)
	check_eq(got.blocked, PackedStringArray(), "every shipped anchor has a clear point within %d rings" % LANDMARK_SPIRAL_RINGS)


func test_soak_every_band_1_tile_keeps_every_rule_at_all_8_orientations() -> void:
	for size in [3, 4]:
		check_eq(WorldChecks.orientation_problems(_content_4(), species, parts, size), PackedStringArray(),
			"size %d: every band-1 tile at every orientation" % size)


## Plan A.2's food bound for band 1 at sizes 3 and 4, its tiles and the cradle. Band 1 is leaner
## than band 0 (54 and 62 measured against band 0's floor of 60), so its own floor shows the bound
## saw the tiles.
const B1_FOOD_FLOOR := 40


func test_the_band_1_coarse_food_bound_stays_under_the_cap() -> void:
	var c := _content_4()
	var cap := int(c.config.caps.food_items)
	for size in [3, 4]:
		var bound := WorldChecks.food_bound(c, FOOD_COARSE_TM, size)
		check(int(bound.worst) <= cap, "size %d: at most %d items within the food ring of any point (%d at %s)" % [size, cap, int(bound.worst), bound.get("at")])
		check(int(bound.worst) >= B1_FOOD_FLOOR, "size %d: the bound saw the tiles (%d >= %d)" % [size, int(bound.worst), B1_FOOD_FLOOR])
		print("test-tiles: band 1, size %d: coarse food bound %d at %s (cap %d)" % [size, int(bound.worst), bound.get("at"), cap])


## S3G38 (F9) at sizes 3 and 4: G5 for band 1. From every open point of each band-1 tile the sea
## outside reaches, a starving cell reaches one of the tile's own zones within the budget, with and
## without its landmark's collider (a rare tile: with its set piece), and every live site home lies
## in that sea; then the same over the whole cradle block, whose centre is food only (D-95).
func test_slow_every_band_1_tile_and_the_cradle_reach_food_within_the_starving_budget() -> void:
	var budget := _budget()
	var c := _content_4()
	var block := c.cradle_of(1)._block()
	for size in [3, 4]:
		var rows := PackedStringArray()
		for id in WorldConfig._sorted(c.tiles.tiles.keys()):
			var t: Dictionary = c.tiles.tiles[id]
			if int(t.band) != 1:
				continue
			var worst := 0.0
			for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
				var p := _placed(t, 0, with_anchor, size)
				var arena := ChunkArena.from_shells(p.colliders)
				check_eq(WorldChecks.reach_problems(arena, p.zones, _tile_bounds(size), budget, p.homes), PackedStringArray(),
					"size %d: %s %s its anchor" % [size, t.where, "with" if with_anchor else "without"])
				worst = maxf(worst, float(_worst_reach(arena, p.zones, _tile_bounds(size)).worst))
			rows.append("%s %.1f" % [t.id, worst])
		var s := WorldConfig.bu_to_tm(size)
		var bounds := Rect2(Vector2.ONE * -CradleBlock.HALF_BU * s, Vector2.ONE * 2.0 * CradleBlock.HALF_BU * s)
		var p := _placed(block, 0, true, size)
		var arena := ChunkArena.from_shells(p.colliders)
		check_eq(WorldChecks.reach_problems(arena, p.zones, bounds, budget, p.homes), PackedStringArray(), "size %d: the cradle" % size)
		rows.append("cradle %.1f" % float(_worst_reach(arena, p.zones, bounds).worst))
		print("test-tiles: size %d: band-1 reach worst per tile (budget %.2f): %s" % [size, budget, ", ".join(rows)])


## S3G2 at identity: band 1's seams at sizes 3 and 4, every ordered pair of band-1 tiles (rare ones
## included) east, north and on the diagonal, and the cradle's outer edges against every band-1 tile;
## every orientation is test_seams' soak. The control puts a cradle shell on the leash circle of the
## first band-1 site as its tile lies east of the cradle (slot (1, 0)): the cradle's side of the seam
## must report it. (A shell at the cradle's own edge is CradleBlock's rule 2, test_cradle_block.)
func test_slow_band_1_seams_hold_and_the_cradle_edges_meet_every_tile() -> void:
	for size in [3, 4]:
		var problems := WorldChecks.seam_problems(_content_4(), species, parts, size, IDENTITY)
		check(problems.is_empty(), "size %d: band 1's seams at identity (%d: %s)" % [size, problems.size(), problems.slice(0, 5)])
	var moved := WorldContent.load_from(WorldChecks.shipped_world_at(4), PoolLayout.load_from(), species)
	var frame: Dictionary = WorldChecks._tile_frames(moved, species, parts, 3, IDENTITY).filter(
		func(f: Dictionary) -> bool: return not f.sites.is_empty())[0]
	var disc: Dictionary = frame.sites[0].disc
	var at: Vector2 = (disc.center - Vector2(disc.radius, 0.0)) / WorldConfig.bu_to_tm(3) + Vector2(3.0, 1.0) * TileCatalog.HALF_TILE_BU
	moved.cradle_of(1).shells.append({"id": "cx", "center": PackedFloat64Array([at.x, at.y]), "radius": CONTROL_R,
		"yaw_deg": PackedFloat64Array([0.0, 360.0]), "at_second_size": "keep"})
	var found := WorldChecks.home_seam_problems(moved, species, parts, 3, IDENTITY)
	print("test-tiles: control: a cradle shell on %s of %s: %s" % [frame.sites[0].where, frame.where, found.slice(0, 1)])
	check(Array(found).any(func(p: String) -> bool: return p.contains("cradle_b1:cx")), "control: the cradle's shell is seen across the seam")
