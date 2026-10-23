class_name TileCatalog
extends RefCounted
## The band's authored tiles (game/data/tiles/b<band>/*.json, S1; docs/s1/s1-interfaces.md section
## 4.2): 64 x 64 bu places the seed arranges, each with its shell slots, zones, sites and landmark
## anchor (plan A.2), or a rare set piece. Plain data plus checks of the data itself.
##
## Coordinates are bu, tile-local, origin at the tile centre, x east and y south, kept as float64
## pairs (PackedFloat64Array): a tile becomes absolute only in WorldGen, in float64. validate() runs
## the per-tile rules at the identity orientation and one size, and only the cheap ones; the heavy
## gates (every orientation, seams, reach, the food bound) live in tests/world_checks.gd.

const FILE_KEYS: PackedStringArray = ["schema_version", "status", "note", "id", "band", "region", "set", "rare",
	"landmark_anchor", "set_piece", "shells", "zones", "sites"]
const SHELL_KEYS: PackedStringArray = ["id", "center", "radius", "yaw_deg", "at_second_size"]
const ZONE_KEYS: PackedStringArray = ["id", "center", "radius", "capacity", "growth_rate", "at_second_size"]
const SITE_KEYS: PackedStringArray = ["id", "species", "home", "heading", "sizes"]
const SITE_OPTIONAL: PackedStringArray = ["territory_zone"]
const SET_PIECE_KEYS: PackedStringArray = ["asset", "center", "yaw_deg"]
const RARE := "rare"
const REGIONS: PackedStringArray = ["sunlit", "reef", "drift"]
const SETS := 2
const TILES_PER_SET := 3
## Band 0's rare kinds (rule 1). The fixed rare tile of world_cell.json names one of them.
const BAND0_RARE_KINDS: PackedStringArray = ["giant_husk", "shell_cathedral"]
## The species a site may name at a band's second size in S1 (rule 6); S2 adds its own.
const S1_SPECIES: PackedStringArray = ["ambush_hunter", "rammer"]
## Rule 7: the behaviours of a threat.
const THREAT_BEHAVIORS: PackedStringArray = ["ambush", "territorial"]
const LOCAL_ID_PATTERN := "^[a-z][a-z0-9]{0,7}$"
## The ids WorldGen gives a tile's landmark collider (lm) and set-piece colliders (r<k>).
const LANDMARK_ID := "lm"
const PIECE_ID_PATTERN := "^r[0-9]+$"
const SHELL_SECOND_SIZE: PackedStringArray = ["keep", "sink"]
const ZONE_SECOND_SIZE: PackedStringArray = ["keep", "thin", "drop"]
const HALF_TILE_BU := 32.0
const SHELL_EDGE_BU := 28.0       ## rules 2 and 5: shells and set-piece colliders keep 4 bu clear of the edges
const ZONE_EDGE_BU := 31.0        ## rule 3: zones keep 1 bu clear
const ANCHOR_EDGE_BU := 25.0      ## rule 4: 28 less the 3 bu anchor
const MIN_SHELL_R := 0.6
const MAX_SHELL_R := 1.5
const MIN_ZONE_R := 2.0
const MAX_ZONE_R := 8.0
## Rule 2's tunnelling check runs at the band's second size, where a bu is 0.625 tm.
const SECOND_SIZE_SCALE := 0.625
## Static #33: growth x capacity x (YIELD_SHARE + EcologyRegion.REGROW_FLOOR) <= MAX_ZONE_YIELD, the M1
## unguarded maximum (z_center, z_s: the zones by the spawn #33's camper measures; the guarded z_n
## and z_nw yield 2.304).
const MAX_ZONE_YIELD := 1.152
const STATIC_33_LABEL := "the M1 unguarded maximum (z_center, z_s)"
const YIELD_SHARE := 0.25
## Rule 6 against the anchor: a reach disc keeps respawn_clear_m + ANCHOR_CLEAR_EXTRA beyond the
## anchor's collider, a cell and ANCHOR_GAP_BU.
const ANCHOR_CLEAR_EXTRA := 1.0
const ANCHOR_GAP_BU := 0.5
## Rule 7: live creature sites per tile at the band's first and second sizes.
const MAX_SITES_FIRST_SIZE := 4
const MAX_SITES_SECOND_SIZE := 2
const MIN_THREAT_BEHAVIORS := 2

## Problems found while reading (unknown or missing keys, wrong types, the file and id rules).
var load_problems := PackedStringArray()
## id -> parsed tile; coordinates kept as float64 pairs (PackedFloat64Array), never Vector2:
## {id, band, region, set (-1 on a rare tile), rare, landmark_anchor (empty on a rare tile),
## set_piece ({} or {asset, center, yaw_deg}), shells [{id, center, radius, yaw_deg: [lo, hi],
## at_second_size}], zones [{id, center, radius, capacity, growth_rate, at_second_size}],
## sites [{id, species, home, heading, territory_zone, sizes: Array[int]}], where}
var tiles := {}
## The bands read, ascending.
var bands: Array[int] = []


## Every *.json in each band's directory ({"0": "res://game/data/tiles/b0"}), in file-name order.
## Never null: a missing directory or an unreadable file is a load problem.
static func load_from(dirs: Dictionary) -> TileCatalog:
	var catalog := TileCatalog.new()
	for band_key in WorldConfig._sorted(dirs.keys()):
		var dir := str(dirs[band_key])
		if not (str(band_key).is_valid_int() and int(str(band_key)) >= 0):
			catalog.load_problems.append("tiles.%s: a band is a whole number of 0 or more" % band_key)
			continue
		var band := int(str(band_key))
		if not DirAccess.dir_exists_absolute(dir):
			catalog.load_problems.append("tiles.%s: the directory '%s' does not exist" % [band_key, dir])
			continue
		catalog.bands.append(band)
		var names := Array(DirAccess.get_files_at(dir)).filter(func(n: String) -> bool: return n.get_extension() == "json")
		names.sort()
		for name: String in names:
			var data: Variant = WorldConfig.read_json(dir.path_join(name))
			if data == null:
				catalog.load_problems.append("b%d/%s: missing or not readable JSON" % [band, name.get_basename()])
				continue
			catalog.add_tile(data, band, name.get_basename())
	catalog.bands.sort()
	return catalog


## Reads one tile file's data as band `band`'s file `file_id` (its name without .json) and adds it.
## load_from uses it for every file; tests build variants with it.
func add_tile(data: Variant, band: int, file_id: String) -> void:
	var w := "b%d/%s" % [band, file_id]
	var problems := load_problems
	if not bands.has(band):
		bands.append(band)
		bands.sort()
	problems.append_array(WorldConfig.schema_problems(w, data, FILE_KEYS))
	if not data is Dictionary:
		return
	WorldConfig.header_check(w, data, problems)
	var t := {"where": w, "set": -1, "landmark_anchor": PackedFloat64Array(), "set_piece": {}}
	t.id = WorldConfig.text_at(w, data, "id", problems)
	if data.has("id") and t.id != file_id:
		problems.append("%s.id: '%s' is not the file's name '%s'" % [w, t.id, file_id])
	t.band = int(WorldConfig.number_at(w, data, "band", problems, true))
	if data.has("band") and t.band != band:
		problems.append("%s.band: %d is not its directory's band %d" % [w, t.band, band])
	t.region = WorldConfig.text_at(w, data, "region", problems)
	t.rare = WorldConfig.text_at(w, data, "rare", problems)
	var is_rare: bool = t.region == RARE
	if data.has("region") and not (REGIONS.has(t.region) or is_rare):
		problems.append("%s.region: '%s' is not one of %s, %s" % [w, t.region, ", ".join(REGIONS), RARE])
	if data.has("rare") and is_rare == str(t.rare).is_empty():
		problems.append("%s.rare: a rare tile names its kind; an ordinary tile has \"\"" % w)
	# What only an ordinary tile has (a set and a landmark anchor), and what only a rare one has.
	if is_rare:
		for key in ["set", "landmark_anchor"]:
			if data.has(key) and data[key] != null:
				problems.append("%s.%s: must be null on a rare tile" % [w, key])
		if data.has("set_piece"):
			var piece := WorldConfig.object_at(w, data, "set_piece", SET_PIECE_KEYS, problems)
			var pw := w + ".set_piece"
			t.set_piece = {"asset": WorldConfig.text_at(pw, piece, "asset", problems),
				"center": WorldConfig.pair_at(pw, piece, "center", problems),
				"yaw_deg": WorldConfig.number_at(pw, piece, "yaw_deg", problems)}
	else:
		var before := problems.size()
		var set_index := WorldConfig.number_at(w, data, "set", problems, true)
		if data.has("set") and problems.size() == before:
			if set_index < 0.0 or set_index >= SETS:
				problems.append("%s.set: must be 0 or 1" % w)
			t.set = int(set_index)
		t.landmark_anchor = WorldConfig.pair_at(w, data, "landmark_anchor", problems)
		if data.has("set_piece") and data.set_piece != null:
			problems.append("%s.set_piece: must be null on an ordinary tile" % w)
	t.shells = read_list(w, data, "shells", SHELL_KEYS, PackedStringArray(), problems, read_shell)
	t.zones = read_list(w, data, "zones", ZONE_KEYS, PackedStringArray(), problems, read_zone)
	t.sites = read_list(w, data, "sites", SITE_KEYS, SITE_OPTIONAL, problems, read_site)
	if str(t.id).is_empty():
		return
	if tiles.has(t.id):
		problems.append("%s.id: '%s' is repeated" % [w, t.id])
	else:
		tiles[t.id] = t


func tile(id: String) -> Dictionary:
	return tiles.get(id, {})


## The 3 tile ids of a band's region and set, sorted.
func ids_of(band: int, region: String, set_index: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in WorldConfig._sorted(tiles.keys()):
		var t: Dictionary = tiles[id]
		if t.band == band and t.region == region and t.set == set_index:
			out.append(id)
	return out


## The band's rare kinds, sorted.
func rare_kinds(band: int) -> PackedStringArray:
	var kinds := {}
	for id in tiles:
		var t: Dictionary = tiles[id]
		if t.band == band and t.region == RARE:
			kinds[t.rare] = true
	return PackedStringArray(WorldConfig._sorted(kinds.keys()))


## The band's rare tile of `kind` (the first by id if rule 1 is broken), or {}.
func rare_tile(band: int, kind: String) -> Dictionary:
	for id in WorldConfig._sorted(tiles.keys()):
		var t: Dictionary = tiles[id]
		if t.band == band and t.region == RARE and t.rare == kind:
			return t
	return {}


## The circles a tile's sites and zones live among, in the tile's identity frame ({id, center:
## Vector2, radius} bu): its shells, then its landmark collider (lm) or its set piece's colliders
## (r<k>: the record's colliders turned by the piece's yaw_deg, then moved to its centre).
static func colliders_of(t: Dictionary, kit: PlacementKit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in t.shells:
		out.append({"id": s.id, "center": _vec(s.center), "radius": float(s.radius)})
	if t.landmark_anchor.size() == 2:
		out.append({"id": LANDMARK_ID, "center": _vec(t.landmark_anchor), "radius": kit.collide_radius_bu})
	if not t.set_piece.is_empty() and t.set_piece.center.size() == 2:
		var colliders: Array = kit.assets.get(t.set_piece.asset, {}).get("colliders", [])
		for k in colliders.size():
			var c: Dictionary = colliders[k]
			if c.center.size() != 2:
				continue
			var p := yaw_point(c.center[0], c.center[1], float(t.set_piece.yaw_deg))
			out.append({"id": "r%d" % k, "center": Vector2(t.set_piece.center[0] + p[0], t.set_piece.center[1] + p[1]),
				"radius": float(c.radius)})
	return out


## A point of a piece turned by its visual yaw (RockField: rotation.y = deg_to_rad(yaw_deg), which on
## the plane maps (x, y) to (x cos + y sin, -x sin + y cos)), for whole quarter turns, exactly.
static func yaw_point(x: float, y: float, yaw_deg: float) -> PackedFloat64Array:
	match posmod(roundi(yaw_deg / 90.0), 4):
		1:
			return PackedFloat64Array([y, -x])
		2:
			return PackedFloat64Array([-x, -y])
		3:
			return PackedFloat64Array([-y, x])
	return PackedFloat64Array([x, y])


## Problems with the tiles; empty when the world can place them. Reading problems come back alone.
## The rules of spine 4.2 at the identity orientation, at `size` (1 in S1).
func validate(species: SpeciesCatalog, kit: PlacementKit, part_catalog: PartCatalog, size: int = 1) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var radii := {}
	var r_max := 0.0
	for id in species.species_ids():
		radii[id] = species.phenotype(id, part_catalog).radius
		r_max = maxf(r_max, radii[id])
	for band in bands:
		_check_counts(band, errors)
	var behaviors := {}
	var smallest := {}
	for id in WorldConfig._sorted(tiles.keys()):
		var t: Dictionary = tiles[id]
		var colliders := colliders_of(t, kit)
		_check_shells(t, kit, colliders, errors)
		_check_zones(t, colliders, errors)
		if t.region == RARE:
			_check_set_piece(t, kit, colliders, errors)
		else:
			_check_anchor(t, kit, species, r_max, errors)
		_check_sites(t, species, radii, kit, colliders, size, errors)
		_check_content(t, species, size, behaviors, smallest, errors)
	for band in bands:
		var covered: Array = WorldConfig._sorted(behaviors.get(band, {}).keys())
		if covered.size() < MIN_THREAT_BEHAVIORS:
			errors.append("tiles b%d: rule 7: the live threats at size %d are %s; they need %d behaviours"
				% [band, size, covered, MIN_THREAT_BEHAVIORS])
	# Rule 8: each species' strike lane fits the smallest live territory of the tiles.
	for id in species.species_ids():
		var text := species.strike_room_problem(id, float(smallest.get(id, CreatureBrain.DEFAULT_TERRITORY_M)), "species '%s'" % id, part_catalog)
		if not text.is_empty():
			errors.append("tiles: rule 8: %s" % text)
	return errors


# --- the rules ---

## Rule 1: 6 tiles per region, 3 in each set, and one rare tile per rare kind.
func _check_counts(band: int, errors: PackedStringArray) -> void:
	for region in REGIONS:
		var per_set := []
		for set_index in SETS:
			per_set.append(ids_of(band, region, set_index).size())
		if per_set != [TILES_PER_SET, TILES_PER_SET]:
			errors.append("tiles b%d: rule 1: %s has %s tiles by set; it needs [%d, %d]" % [band, region, per_set, TILES_PER_SET, TILES_PER_SET])
	var counts := {}
	for id in tiles:
		var t: Dictionary = tiles[id]
		if t.band == band and t.region == RARE:
			counts[t.rare] = int(counts.get(t.rare, 0)) + 1
	for kind in WorldConfig._sorted(counts.keys()):
		if counts[kind] != 1:
			errors.append("tiles b%d: rule 1: the rare kind '%s' has %d tiles; it needs 1" % [band, kind, counts[kind]])
	if band == 0 and rare_kinds(band) != BAND0_RARE_KINDS:
		errors.append("tiles b0: rule 1: the rare kinds are %s, not %s" % [rare_kinds(band), BAND0_RARE_KINDS])


## Rule 2: shell radii and kit fit, edges, overlaps, tunnelling at the second size, yaw ranges.
static func _check_shells(t: Dictionary, kit: PlacementKit, colliders: Array[Dictionary], errors: PackedStringArray) -> void:
	var w: String = t.where
	var for_tunnel: Array[Dictionary] = []
	for s in t.shells:
		var r := float(s.radius)
		var c: PackedFloat64Array = s.center
		for_tunnel.append({"id": s.id, "radius": r})
		if r < MIN_SHELL_R or r > MAX_SHELL_R or kit.class_of(r).is_empty():
			errors.append("%s: rule 2: shell '%s' radius %s is outside [%s, %s]" % [w, s.id, r, MIN_SHELL_R, MAX_SHELL_R])
		elif kit.fitting(r, t.band).size() < PlacementKit.MIN_PICKABLE_PER_CLASS:
			errors.append("%s: rule 2: shell '%s' radius %s fits %s; it needs %d kit shells"
				% [w, s.id, r, kit.fitting(r, t.band), PlacementKit.MIN_PICKABLE_PER_CLASS])
		if absf(c[0]) + r > SHELL_EDGE_BU or absf(c[1]) + r > SHELL_EDGE_BU:
			errors.append("%s: rule 2: shell '%s' at %s comes within %s bu of the tile's edge" % [w, s.id, c, HALF_TILE_BU - SHELL_EDGE_BU])
		var yaw: PackedFloat64Array = s.yaw_deg
		if not (yaw.size() == 2 and 0.0 <= yaw[0] and yaw[0] <= yaw[1] and yaw[1] <= 360.0):
			errors.append("%s: rule 2: shell '%s' yaw_deg %s needs 0 <= lo <= hi <= 360" % [w, s.id, yaw])
		if not SHELL_SECOND_SIZE.has(s.at_second_size):
			errors.append("%s: rule 2: shell '%s' at_second_size '%s' is not one of %s" % [w, s.id, s.at_second_size, ", ".join(SHELL_SECOND_SIZE)])
	for p in PoolLayout.tunnel_problems(for_tunnel, PoolLayout.MAX_SPEED, SECOND_SIZE_SCALE):
		errors.append("%s: rule 2: %s" % [w, p])
	# No two circles overlap: shells with shells (rule 2) and with set-piece colliders (rule 5). A set
	# piece's own colliders are one piece; the landmark collider is rule 4's.
	for i in colliders.size():
		for j in range(i + 1, colliders.size()):
			var a: Dictionary = colliders[i]
			var b: Dictionary = colliders[j]
			if a.id == LANDMARK_ID or b.id == LANDMARK_ID or (_is_piece(a.id) and _is_piece(b.id)):
				continue
			var gap: float = Vector2(a.center).distance_to(b.center) - a.radius - b.radius
			if gap < 0.0:
				errors.append("%s: rule %d: '%s' and '%s' overlap by %.2f bu" % [w, 5 if _is_piece(b.id) else 2, a.id, b.id, -gap])


## Rule 3: zone values and edges, the gap rule against the tile's colliders (its shells, its landmark
## collider or its set piece's colliders; PoolLayout.zone_problems, B-3), and static #33.
static func _check_zones(t: Dictionary, colliders: Array[Dictionary], errors: PackedStringArray) -> void:
	var w: String = t.where
	for z in t.zones:
		var c: PackedFloat64Array = z.center
		var r := float(z.radius)
		if not (r >= MIN_ZONE_R and r <= MAX_ZONE_R and z.capacity > 0.0 and z.growth_rate > 0.0):
			errors.append("%s: rule 3: zone '%s' needs %s <= radius <= %s and a positive capacity and growth rate"
				% [w, z.id, MIN_ZONE_R, MAX_ZONE_R])
			continue
		if absf(c[0]) + r > ZONE_EDGE_BU or absf(c[1]) + r > ZONE_EDGE_BU:
			errors.append("%s: rule 3: zone '%s' at %s comes within %s bu of the tile's edge" % [w, z.id, c, HALF_TILE_BU - ZONE_EDGE_BU])
		if not ZONE_SECOND_SIZE.has(z.at_second_size):
			errors.append("%s: rule 3: zone '%s' at_second_size '%s' is not one of %s" % [w, z.id, z.at_second_size, ", ".join(ZONE_SECOND_SIZE)])
		var yield_rate := float(z.growth_rate) * float(z.capacity) * (YIELD_SHARE + EcologyRegion.REGROW_FLOOR)
		if yield_rate > MAX_ZONE_YIELD:
			errors.append("%s: rule 3: zone '%s' yields %.3f a second; static #33 allows <= %.3f, %s" % [w, z.id, yield_rate, MAX_ZONE_YIELD, STATIC_33_LABEL])
		var one: Array[Dictionary] = [{"id": z.id, "center": _vec(c), "radius": r, "capacity": z.capacity, "growth_rate": z.growth_rate}]
		for p in PoolLayout.zone_problems(one, colliders, INF):
			errors.append("%s: rule 3: %s" % [w, p])


## Rule 4 (ordinary tiles): the anchor stays inside, and its collider leaves room for the largest
## body to pass between it and every shell.
static func _check_anchor(t: Dictionary, kit: PlacementKit, species: SpeciesCatalog, r_max: float, errors: PackedStringArray) -> void:
	var w: String = t.where
	var a: PackedFloat64Array = t.landmark_anchor
	if absf(a[0]) > ANCHOR_EDGE_BU or absf(a[1]) > ANCHOR_EDGE_BU:
		errors.append("%s: rule 4: the landmark anchor %s lies beyond %s bu of the centre" % [w, a, ANCHOR_EDGE_BU])
	var need := 2.0 * r_max + float(species.fairness.pinch_margin_m)
	for s in t.shells:
		var gap: float = _vec(a).distance_to(_vec(s.center)) - kit.collide_radius_bu - float(s.radius)
		if gap < need:
			errors.append("%s: rule 4: the landmark collider leaves %.2f bu to shell '%s'; it needs %.2f" % [w, gap, s.id, need])


## Rule 5 (rare tiles): the set piece is the kit's piece of this kind, turned a whole quarter at a
## time, its colliders 4 bu clear of the edges (their overlaps with shells are rule 2's loop).
static func _check_set_piece(t: Dictionary, kit: PlacementKit, colliders: Array[Dictionary], errors: PackedStringArray) -> void:
	var w: String = t.where
	var piece: Dictionary = t.set_piece
	var asset: Dictionary = kit.assets.get(piece.get("asset", ""), {})
	if asset.is_empty() or asset.kind != "rare" or asset.rare_kind != t.rare or asset.band != t.band:
		errors.append("%s: rule 5: the set piece '%s' is not the band-%d kit piece of kind '%s'" % [w, piece.get("asset", ""), t.band, t.rare])
		return
	var yaw := float(piece.yaw_deg)
	if fposmod(yaw, 90.0) != 0.0 or yaw < 0.0 or yaw >= 360.0:
		errors.append("%s: rule 5: the set piece's yaw_deg %s is not 0, 90, 180 or 270" % [w, yaw])
	for c in colliders:
		if _is_piece(c.id) and (absf(c.center.x) + c.radius > SHELL_EDGE_BU or absf(c.center.y) + c.radius > SHELL_EDGE_BU):
			errors.append("%s: rule 5: set-piece collider '%s' at %s comes within %s bu of the tile's edge"
				% [w, c.id, c.center, HALF_TILE_BU - SHELL_EDGE_BU])


## Rule 6: each site's species and sizes; for the sites live at `size`, a clear home, the gap between
## sites, the territory, a reach disc inside the tile that holds the home, rules 9 and 10 against
## the tile's colliders with no wall, and rule 8 against the landmark anchor.
static func _check_sites(t: Dictionary, species: SpeciesCatalog, radii: Dictionary, kit: PlacementKit,
		colliders: Array[Dictionary], size: int, errors: PackedStringArray) -> void:
	var w: String = t.where
	var first := 2 * int(t.band) + 1
	var arena := ChunkArena.from_shells(_arena_circles(colliders))
	var fair := species.fairness
	var live: Array[Dictionary] = []
	for s in t.sites:
		var where := "%s: rule 6: site '%s'" % [w, s.id]
		if not species.species.has(s.species):
			errors.append("%s names unknown species '%s'" % [where, s.species])
			continue
		var sizes: Array = s.sizes
		var sizes_ok := not sizes.is_empty()
		for n in sizes:
			sizes_ok = sizes_ok and (n == first or n == first + 1) and sizes.count(n) == 1
		if not sizes_ok:
			errors.append("%s: sizes %s must be some of [%d, %d]" % [where, sizes, first, first + 1])
		elif sizes.has(first + 1) and not S1_SPECIES.has(s.species):
			errors.append("%s: '%s' is not an S1 species, so it cannot be live at size %d" % [where, s.species, first + 1])
		if sizes.has(size):
			live.append(s)
	for i in live.size():
		var s: Dictionary = live[i]
		var where := "%s: rule 6: site '%s'" % [w, s.id]
		var r := float(radii[s.species])
		var home := _vec(s.home)
		if not arena.is_clear(home, r):
			errors.append("%s home %s is not clear" % [where, s.home])
		for j in i:
			var gap := home.distance_to(_vec(live[j].home))
			if gap < float(species.spawning.min_gap_m):
				errors.append("%s is %.2f bu from site '%s'; sites keep %.1f apart" % [where, gap, live[j].id, float(species.spawning.min_gap_m)])
		var zone := _zone(t, s.territory_zone)
		if species.behavior_of(s.species) == "territorial" and zone.is_empty():
			errors.append("%s territory_zone '%s' is not a zone of this tile" % [where, s.territory_zone])
			continue
		var territory := species.territory_from({"species": s.species}, {} if zone.is_empty() else {"center": _vec(zone.center), "radius": float(zone.radius)})
		var disc := species.reach_disc_for({"species": s.species, "home": home, "heading": float(s.heading)}, territory)
		var c: Vector2 = disc.center
		var reach := float(disc.radius)
		var inset := reach + r + float(fair.leash_band_margin_m)
		if absf(c.x) + inset > HALF_TILE_BU or absf(c.y) + inset > HALF_TILE_BU:
			errors.append("%s reach disc at %s, r %.2f, comes within %.2f bu of the tile's edge" % [where, c, reach, r + float(fair.leash_band_margin_m)])
		if home.distance_to(c) + r > reach:
			errors.append("%s home %s is not inside its reach disc at %s, r %.2f" % [where, s.home, c, reach])
		var pinches := PackedStringArray()
		species.check_disc_against_shells("site '%s'" % s.id, disc, r, colliders, INF, pinches)
		for p in pinches:
			errors.append("%s: rule 6: %s" % [w, p])
		if t.landmark_anchor.size() == 2:
			var clear := _vec(t.landmark_anchor).distance_to(c) - reach - r - (kit.collide_radius_bu + PoolLayout.CELL_RADIUS + ANCHOR_GAP_BU)
			var need := float(fair.respawn_clear_m) + ANCHOR_CLEAR_EXTRA
			if clear < need:
				errors.append("%s can reach %.2f bu from the landmark anchor; it must stay %.1f away" % [where, clear, need])


## Rule 7: a zone in every tile, threats where they belong, the band's behaviours and density.
## Also gathers rule 8's smallest live territory per species.
static func _check_content(t: Dictionary, species: SpeciesCatalog, size: int, behaviors: Dictionary,
		smallest: Dictionary, errors: PackedStringArray) -> void:
	var w: String = t.where
	if t.zones.is_empty():
		errors.append("%s: rule 7: a tile needs at least one zone" % w)
	var first := 2 * int(t.band) + 1
	var threats := 0
	var at_first := 0
	var at_second := 0
	var any_threat := false
	for s in t.sites:
		var behavior := species.behavior_of(s.species)
		var threat := THREAT_BEHAVIORS.has(behavior)
		any_threat = any_threat or threat
		at_first += 1 if s.sizes.has(first) else 0
		at_second += 1 if s.sizes.has(first + 1) else 0
		if not s.sizes.has(size):
			continue
		if threat:
			threats += 1
			if not behaviors.has(t.band):
				behaviors[t.band] = {}
			behaviors[t.band][behavior] = true
		var zone := _zone(t, s.territory_zone)
		if behavior == "territorial" and not zone.is_empty():
			smallest[s.species] = minf(float(smallest.get(s.species, INF)), float(zone.radius))
	if t.region == "drift" and any_threat:
		errors.append("%s: rule 7: a drift tile has no threat site" % w)
	elif t.region != "drift" and threats == 0:
		errors.append("%s: rule 7: a %s tile needs a live threat site at size %d" % [w, t.region, size])
	if at_first > MAX_SITES_FIRST_SIZE or at_second > MAX_SITES_SECOND_SIZE:
		errors.append("%s: rule 7: %d sites are live at size %d and %d at size %d; at most %d and %d"
			% [w, at_first, first, at_second, first + 1, MAX_SITES_FIRST_SIZE, MAX_SITES_SECOND_SIZE])


# --- reading ---

## The list at `key`, each item checked against its keys and read by `reader`.
static func read_list(w: String, data: Dictionary, key: String, keys: PackedStringArray, optional: PackedStringArray,
		problems: PackedStringArray, reader: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw := WorldConfig.list_at(w, data, key, problems)
	var seen := {}
	for i in raw.size():
		var iw := "%s.%s[%d]" % [w, key, i]
		problems.append_array(WorldConfig.schema_problems(iw, raw[i], keys, optional))
		if not raw[i] is Dictionary:
			continue
		var item: Dictionary = reader.call(iw, raw[i], problems)
		var id: String = item.id
		if raw[i].has("id") and (seen.has(id) or not WorldConfig.matches(id, LOCAL_ID_PATTERN) or id == LANDMARK_ID or _is_piece(id)):
			problems.append("%s.id: '%s' is repeated, reserved (lm, r<digits>) or does not match %s" % [iw, id, LOCAL_ID_PATTERN])
		seen[id] = true
		out.append(item)
	return out


static func read_shell(w: String, d: Dictionary, problems: PackedStringArray) -> Dictionary:
	return {"id": WorldConfig.text_at(w, d, "id", problems), "center": _pair(w, d, "center", problems),
		"radius": WorldConfig.number_at(w, d, "radius", problems), "yaw_deg": _pair(w, d, "yaw_deg", problems),
		"at_second_size": WorldConfig.text_at(w, d, "at_second_size", problems)}


static func read_zone(w: String, d: Dictionary, problems: PackedStringArray) -> Dictionary:
	return {"id": WorldConfig.text_at(w, d, "id", problems), "center": _pair(w, d, "center", problems),
		"radius": WorldConfig.number_at(w, d, "radius", problems), "capacity": WorldConfig.number_at(w, d, "capacity", problems),
		"growth_rate": WorldConfig.number_at(w, d, "growth_rate", problems),
		"at_second_size": WorldConfig.text_at(w, d, "at_second_size", problems)}


static func read_site(w: String, d: Dictionary, problems: PackedStringArray) -> Dictionary:
	var sizes: Array[int] = []
	var raw := WorldConfig.list_at(w, d, "sizes", problems)
	for i in raw.size():
		sizes.append(int(WorldConfig.number_at(w + ".sizes", {str(i): raw[i]}, str(i), problems, true)))
	return {"id": WorldConfig.text_at(w, d, "id", problems), "species": WorldConfig.text_at(w, d, "species", problems),
		"home": _pair(w, d, "home", problems), "heading": WorldConfig.number_at(w, d, "heading", problems),
		"territory_zone": WorldConfig.text_at(w, d, "territory_zone", problems), "sizes": sizes}


## pair_at, or [0, 0] when it is absent or wrong (the problem is already recorded), so the rules never
## index an empty pair.
static func _pair(w: String, d: Dictionary, key: String, problems: PackedStringArray) -> PackedFloat64Array:
	var p := WorldConfig.pair_at(w, d, key, problems)
	return p if p.size() == 2 else PackedFloat64Array([0.0, 0.0])


static func _vec(p: PackedFloat64Array) -> Vector2:
	return Vector2(p[0], p[1])


static func _is_piece(id: String) -> bool:
	return WorldConfig.matches(id, PIECE_ID_PATTERN)


static func _zone(t: Dictionary, id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for z in t.zones:
		if z.id == id:
			return z
	return {}


## The circles a chunk arena takes (it refuses radii outside (0, MAX_COLLIDER_R]; rules 2 and 6 of
## the kit report those).
static func _arena_circles(colliders: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in colliders:
		if c.radius > 0.0 and c.radius <= ChunkArena.MAX_COLLIDER_R:
			out.append(c)
	return out
