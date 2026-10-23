extends TestCase
## The shipped band-0 tiles, game/data/tiles/b0 (S1, G2 and G5; docs/s1/s1-content.md sections 3.4,
## 3.5 and 5.2): 18 ordinary tiles and the two rare places, on the real kit. TileCatalog's rules are
## T1's (tests/test_tile_catalog.gd, on fixtures); these tests hold the real content to them, to the
## region designs, to the margins the tiles were authored with, and to the heavy checks of spine 4.2:
## per-tile reach (slow), seams (slow), every rule and reach at all 8 orientations (soak), the food
## bound and the site sample (T1.10's world_checks; they wait until it lands, see _waits).

const WorldChecks := preload("res://tests/world_checks.gd")
## The same script as a plain Script, for the functions T1.10 adds (called by name until they land).
const CHECKS_PATH := "res://tests/world_checks.gd"
const DIR := "res://game/data/tiles/b0"
## The starving budget as tests/test_pool_layout.gd computes it, pinned before any grid runs (G5).
const BUDGET_TM := 16.32
const BUDGET_PIN := 0.01
const TILE_BOUNDS := Rect2(-32.0, -32.0, 64.0, 64.0)
const TILE_BU := 64.0
const RARE_KINDS: PackedStringArray = ["giant_husk", "shell_cathedral"]
## The region designs (s1-content 3.2): what each kind of tile is for.
const SUNLIT_RICH_R := 5.0
const SUNLIT_RICH_CAPACITY := 64.0
const SUNLIT_RAMMER_CAPACITY := 48.0
const REEF_SHELLS := 18
const DRIFT_MAX_SHELLS := 5
const DRIFT_MAX_CAPACITY := 16.0
const DRIFT_MAX_ITEMS := 12
## The smallest slack a site keeps inside its tile (rule 6's inset) and from the landmark anchor
## (rule 8), so retuning cannot wear them down to the rule unnoticed.
const MIN_INSET_SLACK := 1.0
const MIN_ANCHOR_SLACK := 1.0
## The seam check's positive control (s1-content 5.2): a shell put just across the seam from
## giant_husk's lair la, inside its reach circle where rule 9 wants clear water.
const CONTROL_A := "reef_a"
const CONTROL_B := "giant_husk"
const CONTROL_SHELL := Vector2(35.5, -4.0)
const CONTROL_R := 0.6
## The home block's edge slots: the centres of the 8 tiles that touch it, in its frame.
const HOME_SLOTS: Array[Vector2] = [Vector2(96, -32), Vector2(96, 32), Vector2(-96, -32), Vector2(-96, 32),
	Vector2(-32, -96), Vector2(32, -96), Vector2(-32, 96), Vector2(32, 96)]
## T1.10 brings world_checks.food_bound and sample_sites with tests/test_world_checks.gd; with that
## file in the tree the waiting tests below must run (test_the_heavy_checks_wait_only_on_t1_10).
const CHECKS_LANDED := "res://tests/test_world_checks.gd"
const FOOD_COARSE_TM := 4.0
const FOOD_FINE_TM := 1.0
## A coarse bound below this would mean food_bound saw no tiles (s1-content 5.2 measured 91).
const FOOD_FLOOR := 60
const SAMPLE_ARRANGEMENTS := 5000
const SAMPLE_DISCS := 100
const SAMPLE_SEED := 4242
const SAMPLE_MAX_SITES := 10

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


## Whether a heavy check waits on T1.10, saying so.
func _waits(check_name: String) -> bool:
	if _missing_checks().is_empty():
		return false
	print("test-tiles: %s waits on T1.10's world_checks: %s" % [check_name, ", ".join(_missing_checks())])
	return true


func _missing_checks() -> PackedStringArray:
	var have := {}
	var checks: Script = load(CHECKS_PATH)
	for m in checks.get_script_method_list():
		have[str(m.name)] = true
	var out := PackedStringArray()
	for fn in ["food_bound", "sample_sites"]:
		if not have.has(fn):
			out.append(fn)
	return out


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


## Tile t turned to orientation o and moved so its centre sits at `at`: its colliders (with or
## without the landmark's) and zones as ReachGrid and check_disc_against_shells take them, and the
## reach disc of each live site (computed at identity, then oriented, as spine 3.6 places them).
func _placed(t: Dictionary, o: int, at: Vector2, with_anchor: bool = true) -> Dictionary:
	var colliders: Array[Dictionary] = []
	for c in TileCatalog.colliders_of(t, kit):
		if with_anchor or c.id != TileCatalog.LANDMARK_ID:
			colliders.append({"id": "%s/%s" % [t.id, c.id], "center": at + _orient(c.center, o), "radius": float(c.radius)})
	var zones: Array[Dictionary] = []
	for z in t.zones:
		zones.append({"id": "%s/%s" % [t.id, z.id], "center": at + _orient(Vector2(z.center[0], z.center[1]), o), "radius": float(z.radius)})
	var discs: Array[Dictionary] = []
	for s in t.sites:
		if s.sizes.has(1):
			var d := _disc(t, s)
			discs.append({"where": "%s o%d site '%s'" % [t.id, o, s.id], "r": float(radii[s.species]),
				"disc": {"center": at + _orient(d.center, o), "radius": float(d.radius)}})
	return {"colliders": colliders, "zones": zones, "discs": discs}


# ---- Fast ----

## G2: every rule of spine 4.2 at identity and size 1, with the kit, the home block and the world file
## (WorldContent.problems runs TileCatalog.validate on these tiles).
func test_the_band_0_content_validates() -> void:
	check_eq(tiles.load_problems, PackedStringArray(), "the tiles read")
	check_eq(_ids().size(), 20, "18 ordinary tiles and 2 rare ones")
	check_eq(content.problems(parts, species), PackedStringArray(), "world_cell.json and everything it names")


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
		for s in t.sites:
			check_eq(s.sizes, [1] as Array[int], "%s site '%s' is live at size 1 only (S2 revisits it)" % [id, s.id])
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
			"reef":
				check_eq(t.shells.size(), REEF_SHELLS, "%s: the reef's shells" % id)
				check(t.sites.size() >= 2 and ambushes >= 1, "%s: at least 2 sites, an ambush lair among them (%d, %d)" % [id, t.sites.size(), ambushes])
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
	check(drift_most < sunlit_least, "drift tiles hold fewer items (at most %d) than any sunlit tile (at least %d)" % [drift_most, sunlit_least])


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
## neighbours), so its nave is sealed water no grid point can reach food from, and the tile fills it
## with shells. If the piece is rebuilt with gaps a cell can swim through, this fails: the filler
## shells come out and the nave becomes open water again.
func test_the_cathedral_nave_is_filled_while_its_drums_seal_it() -> void:
	var t := tiles.rare_tile(0, "shell_cathedral")
	var drums := TileCatalog.colliders_of(t, kit).filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("r"))
	check_eq(drums.size(), 8, "eight drums")
	var widest := 0.0
	for i in drums.size():
		var a: Dictionary = drums[i]
		var b: Dictionary = drums[(i + 1) % drums.size()]
		widest = maxf(widest, a.center.distance_to(b.center) - a.radius - b.radius)
	check(widest < 2.0 * PoolLayout.CELL_RADIUS, "the drums leave at most %.2f bu between neighbours, less than a cell (%.1f)" % [widest, 2.0 * PoolLayout.CELL_RADIUS])
	var filler: Array = t.shells.filter(func(s: Dictionary) -> bool: return Vector2(s.center[0], s.center[1]).length() < 3.4)
	check_eq(filler.size(), 9, "the nave shells n0 to n8 fill the space inside the drums")
	print("test-tiles: the cathedral's drums leave %.2f bu; %d shells fill the nave" % [widest, filler.size()])


func test_the_coarse_food_bound_stays_under_the_cap() -> void:
	if _waits("the coarse food bound"):
		return
	var bound: Dictionary = (load(CHECKS_PATH) as Script).call("food_bound", content, FOOD_COARSE_TM)
	var cap := int(content.config.caps.food_items)
	check(int(bound.worst) <= cap, "at most %d items within the food ring of any point (%d at %s)" % [cap, int(bound.worst), bound.get("at")])
	check(int(bound.worst) >= FOOD_FLOOR, "the bound saw the tiles (%d >= %d)" % [int(bound.worst), FOOD_FLOOR])
	print("test-tiles: coarse food bound %d at %s (cap %d)" % [int(bound.worst), bound.get("at"), cap])


## Waiting is not a pass for ever: once T1.10's test file is in the tree, world_checks must have the
## functions the waiting tests call.
func test_the_heavy_checks_wait_only_on_t1_10() -> void:
	if FileAccess.file_exists(CHECKS_LANDED):
		check_eq(_missing_checks(), PackedStringArray(), "%s is in the tree, so T1.10 has landed" % CHECKS_LANDED)
	elif not _missing_checks().is_empty():
		print("test-tiles: the food bound and the site sample wait on T1.10: %s" % ", ".join(_missing_checks()))


# ---- Slow ----

## G5: from every open point of each tile a starving cell reaches one of the tile's own zones within
## the budget, with and without its landmark's collider (a rare tile: with its set piece).
func test_slow_every_tile_reaches_food_within_the_starving_budget() -> void:
	var budget := _budget()
	var rows := PackedStringArray()
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		var worst := 0.0
		for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
			var p := _placed(t, 0, Vector2.ZERO, with_anchor)
			var arena := ChunkArena.from_shells(p.colliders)
			check_eq(WorldChecks.reach_problems(arena, p.zones, TILE_BOUNDS, budget), PackedStringArray(),
				"%s %s its anchor" % [id, "with" if with_anchor else "without"])
			worst = maxf(worst, float(WorldChecks.worst_reach(arena, p.zones, TILE_BOUNDS).worst))
		rows.append("%s %.1f" % [id, worst])
	print("test-tiles: reach worst per tile (budget %.2f): %s" % [budget, ", ".join(rows)])


## Problems where two placed tiles (_placed, in one frame) meet: rules 9 and 10 for every live reach
## disc of both against the colliders of both, and no collider of one overlapping one of the other.
func _seam_problems(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var combined: Array[Dictionary] = []
	combined.append_array(a.colliders)
	combined.append_array(b.colliders)
	for d in a.discs + b.discs:
		species.check_disc_against_shells(d.where, d.disc, d.r, combined, INF, errors)
	for ca in a.colliders:
		for cb in b.colliders:
			if ca.center.distance_to(cb.center) < ca.radius + cb.radius:
				errors.append("%s overlaps %s across the seam" % [ca.id, cb.id])
	return errors


## G2's seams at identity: every ordered pair of tiles placed east, north and on the diagonal, and the
## home block against every tile at every orientation in each of the 8 slots along its edges. Spine
## 4.2 gives the seam soak over every orientation pair to T1 (tests/test_seams.gd); this is its
## identity share, run with the same primitives, and it has a positive control.
func test_slow_seams_hold_between_tiles_and_against_the_home_edges() -> void:
	var placements := 0
	var errors := PackedStringArray()
	var ids := _ids()
	for ia in ids:
		var a := _placed(tiles.tiles[ia], 0, Vector2.ZERO)
		for ib in ids:
			for offset in [Vector2(TILE_BU, 0.0), Vector2(0.0, -TILE_BU), Vector2(TILE_BU, -TILE_BU)]:
				errors.append_array(_seam_problems(a, _placed(tiles.tiles[ib], 0, offset)))
				placements += 1
	var home := _home_placed()
	for id in ids:
		for o in 8:
			for slot in HOME_SLOTS:
				errors.append_array(_seam_problems(home, _placed(tiles.tiles[id], o, slot)))
				placements += 1
	check_eq(placements, 20 * 20 * 3 + 20 * 8 * HOME_SLOTS.size(), "placements")
	check_eq(errors, PackedStringArray(), "rules 9 and 10 and no overlap across every seam")
	# The positive control: the same check must see a shell across the seam inside a lair's reach.
	var control := _placed(tiles.tiles[CONTROL_A], 0, Vector2.ZERO)
	control.colliders.append({"id": "%s/control" % CONTROL_A, "center": CONTROL_SHELL, "radius": CONTROL_R})
	var found := _seam_problems(control, _placed(tiles.tiles[CONTROL_B], 0, Vector2(TILE_BU, 0.0)))
	var reported := false
	for e in found:
		reported = reported or e.contains("control")
	check(reported, "the control shell at %s, r %s, west of %s is reported: %s" % [CONTROL_SHELL, CONTROL_R, CONTROL_B, found])
	print("test-tiles: %d seam placements clean; the control reports %s" % [placements, found])


## The home block in its own frame: its colliders and the M1 sites' reach discs (the ring has none).
func _home_placed() -> Dictionary:
	var home := content.home
	var zone_by_id := {}
	for z in home.zones:
		zone_by_id[z.id] = z
	var colliders: Array[Dictionary] = []
	for c in home.circles():
		colliders.append({"id": "home/%s" % c.id, "center": c.center, "radius": c.radius})
	var discs: Array[Dictionary] = []
	for s in home.sites:
		if not s.sizes.has(1):
			continue
		var z: Dictionary = zone_by_id.get(s.territory_zone, {})
		var territory := species.territory_from({"species": s.species}, {} if z.is_empty() else {"center": Vector2(z.x, z.y), "radius": z.radius})
		var d := species.reach_disc_for({"species": s.species, "home": Vector2(s.x, s.y), "heading": s.heading}, territory)
		discs.append({"where": "home site '%s'" % s.id, "r": float(radii[s.species]), "disc": {"center": d.center, "radius": float(d.radius)}})
	return {"colliders": colliders, "zones": [], "discs": discs}


# ---- Soak ----

## Tile file `data` turned to orientation o by WorldGen's maps, as TileCatalog.add_tile reads a file.
## A set piece's colliders are placed in the turned frame and handed to `test_kit` as a piece of
## their own at yaw 0, since a mirrored piece has no yaw that matches it. Shell yaw ranges stay as
## they are: they choose a look, not a place.
static func _oriented_file(data: Dictionary, o: int, test_kit: PlacementKit) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	for s in out.shells:
		s.center = _orient_pair(s.center, o)
	for z in out.zones:
		z.center = _orient_pair(z.center, o)
	for s in out.sites:
		s.home = _orient_pair(s.home, o)
		s.heading = WorldGen.orient_heading(float(s.heading), o)
	if out.landmark_anchor != null:
		out.landmark_anchor = _orient_pair(out.landmark_anchor, o)
	if out.set_piece != null:
		var piece: Dictionary = out.set_piece
		var asset: Dictionary = test_kit.assets[piece.asset]
		var turned: Dictionary = asset.duplicate(true)
		var colliders: Array[Dictionary] = []
		for c in asset.colliders:
			var p := TileCatalog.yaw_point(c.center[0], c.center[1], float(piece.yaw_deg))
			colliders.append({"center": WorldGen.orient_point(p[0], p[1], o), "radius": c.radius})
		turned.colliders = colliders
		var piece_id := "%s_o%d" % [piece.asset, o]
		test_kit.assets[piece_id] = turned
		out.set_piece = {"asset": piece_id, "center": _orient_pair(piece.center, o), "yaw_deg": 0.0}
	return out


static func _orient_pair(p: Array, o: int) -> Array:
	var q := WorldGen.orient_point(float(p[0]), float(p[1]), o)
	return [q[0], q[1]]


## G2 at every orientation the generator may place a tile in: the whole band turned to o, then
## TileCatalog.validate (rules 1 to 8). The check s1-content 17.13 proposes as T1's
## orientation_problems, run here from the pinned primitives until T1 adds it.
func test_soak_every_tile_keeps_every_rule_at_all_8_orientations() -> void:
	var files := {}
	for id in _ids():
		files[id] = WorldConfig.read_json(DIR.path_join("%s.json" % id))
	for o in 8:
		var test_kit := PlacementKit.load_from(str(content.config.content.kit))
		var turned := TileCatalog.new()
		for id in _ids():
			turned.add_tile(_oriented_file(files[id], o, test_kit), 0, id)
		check_eq(turned.validate(species, test_kit, parts, 1), PackedStringArray(), "the band at orientation %d" % o)


func test_soak_every_tile_reaches_food_at_all_8_orientations() -> void:
	var budget := _budget()
	var worst := 0.0
	var worst_at := ""
	for id in _ids():
		var t: Dictionary = tiles.tiles[id]
		for o in 8:
			for with_anchor in ([true, false] if t.landmark_anchor.size() == 2 else [true]):
				var p := _placed(t, o, Vector2.ZERO, with_anchor)
				var arena := ChunkArena.from_shells(p.colliders)
				check_eq(WorldChecks.reach_problems(arena, p.zones, TILE_BOUNDS, budget), PackedStringArray(),
					"%s at orientation %d %s its anchor" % [id, o, "with" if with_anchor else "without"])
				var w := float(WorldChecks.worst_reach(arena, p.zones, TILE_BOUNDS).worst)
				if w > worst:
					worst = w
					worst_at = "%s o%d" % [id, o]
	print("test-tiles: reach worst over 8 orientations %.1f tm (%s; budget %.2f)" % [worst, worst_at, budget])


func test_soak_the_fine_food_bound_stays_under_the_cap() -> void:
	if _waits("the fine food bound"):
		return
	var bound: Dictionary = (load(CHECKS_PATH) as Script).call("food_bound", content, FOOD_FINE_TM)
	var cap := int(content.config.caps.food_items)
	check(int(bound.worst) <= cap, "at most %d items within the food ring of any point (%d at %s)" % [cap, int(bound.worst), bound.get("at")])
	print("test-tiles: fine food bound %d at %s (cap %d)" % [int(bound.worst), bound.get("at"), cap])


func test_soak_no_disc_of_any_arrangement_wakes_more_than_10_sites() -> void:
	if _waits("the site sample"):
		return
	var sample: Dictionary = (load(CHECKS_PATH) as Script).call("sample_sites", content, species, SAMPLE_ARRANGEMENTS, SAMPLE_DISCS, SAMPLE_SEED)
	check(int(sample.worst) <= SAMPLE_MAX_SITES, "at most %d live reach discs meet any 40 tm disc (%s)" % [SAMPLE_MAX_SITES, sample])
	print("test-tiles: site sample worst %s" % [sample])
