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
const SITE_OPTIONAL: PackedStringArray = ["territory_zone", "post_b"]
## A two-post site's second post (B.7, D-38): its home and heading, and its own territory zone when
## the species is territorial (refused when it is not).
const POST_KEYS: PackedStringArray = ["home", "heading"]
const POST_OPTIONAL: PackedStringArray = ["territory_zone"]
const SET_PIECE_KEYS: PackedStringArray = ["asset", "center", "yaw_deg"]
const RARE := "rare"
const REGIONS: PackedStringArray = ["sunlit", "reef", "drift"]
const SETS := 2
const TILES_PER_SET := 3
## Band 0's rare kinds (rule 1). The fixed rare tile of world_cell.json names one of them.
const BAND0_RARE_KINDS: PackedStringArray = ["giant_husk", "shell_cathedral"]
## The species the home block lets a site name at a band's second size (S1's rule; T3.4 moves the home
## block to SpeciesCatalog.live_at as the tiles here).
const S1_SPECIES: PackedStringArray = ["ambush_hunter", "rammer"]
## Rule 7: the behaviours of a threat (a threat at size n is also of entry size n: the ladder's
## "threat" role, Relationships.ladder_role).
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
## D-61: how far apart a two-post site's homes lie, in the species' own tm (q = 1), by its habit's
## post_switch: the Lurker's 4 to 6 tm, the elder rammer's 6.0 to 10.5 tm. Times k_of in bu.
const POST_SPACING_TM := {"out_of_sight": [4.0, 6.0], "nearer_cell": [6.0, 10.5]}
## D-61: a move between the posts at wander speed takes at most this share of nav_timeout_s, so it
## never times out on the way.
const POST_TRAVEL_NAV_SHARE := 0.8
## D-61: a two-post site's union reach radius at most, tm at the size (B-6 keeps reach_max < 18.745).
const MAX_UNION_REACH_TM := 18.0

## Problems found while reading (unknown or missing keys, wrong types, the file and id rules).
var load_problems := PackedStringArray()
## id -> parsed tile; coordinates kept as float64 pairs (PackedFloat64Array), never Vector2:
## {id, band, region, set (-1 on a rare tile), rare, landmark_anchor (empty on a rare tile),
## set_piece ({} or {asset, center, yaw_deg}), shells [{id, center, radius, yaw_deg: [lo, hi],
## at_second_size}], zones [{id, center, radius, capacity, growth_rate, at_second_size}],
## sites [{id, species, home, heading, territory_zone, sizes: Array[int], post_b ({} or {home,
## heading, territory_zone})}], where}
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
## (r<k>: the record's colliders turned by the piece's yaw_deg, then moved to its centre). A set
## piece marked "mirror": true (never in a file: tests/world_checks.gd's oriented copies, as a
## mirrored tile's place draws it) is mirrored in its own x before it turns.
static func colliders_of(t: Dictionary, kit: PlacementKit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in t.shells:
		out.append({"id": s.id, "center": _vec(s.center), "radius": float(s.radius)})
	if t.landmark_anchor.size() == 2:
		out.append({"id": LANDMARK_ID, "center": _vec(t.landmark_anchor), "radius": kit.collide_radius_bu})
	if not t.set_piece.is_empty() and t.set_piece.center.size() == 2:
		var colliders: Array = kit.assets.get(t.set_piece.asset, {}).get("colliders", [])
		var mx := -1.0 if t.set_piece.get("mirror", false) else 1.0
		for k in colliders.size():
			var c: Dictionary = colliders[k]
			if c.center.size() != 2:
				continue
			var p := yaw_point(mx * c.center[0], c.center[1], float(t.set_piece.yaw_deg))
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
## The rules of spine 4.2 at the identity orientation, at `size` (WorldContent asks for each size of
## the build, D-70). Rules 1, 2, 3 and 5 are the same at every size. Rules 4, 6, 7 and 8 are the
## size's: the species live there (SpeciesCatalog.live_at) with radii at_size(id, size).phenotype
## .radius / bu_to_tm(size) bu, the colliders there (colliders_at), reach discs with k (D-39, D-69)
## and every fairness length in bu (its tm / bu_to_tm(size)). At a band's first size every value is
## S1's, bit for bit. A rule broken at a band's second size says so ("rule 6 at size 2").
func validate(species: SpeciesCatalog, kit: PlacementKit, part_catalog: PartCatalog, size: int = 1) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var radii := radii_at(species, part_catalog, size)
	for band in bands:
		_check_counts(band, errors)
	var behaviors := {}
	var smallest := {}
	for id in WorldConfig._sorted(tiles.keys()):
		var t: Dictionary = tiles[id]
		var colliders := colliders_of(t, kit)
		var there := colliders_at(t, colliders, size)
		_check_shells(t, kit, colliders, errors)
		_check_zones(t, colliders, errors)
		if t.region == RARE:
			_check_set_piece(t, kit, colliders, errors)
		else:
			_check_anchor(t, kit, species, radii, there, size, errors)
		_check_sites(t, species, radii, kit, there, part_catalog, size, errors)
		_check_content(t, species, size, behaviors, smallest, errors)
	for band in bands:
		var covered: Array = WorldConfig._sorted(behaviors.get(band, {}).keys())
		if covered.size() < MIN_THREAT_BEHAVIORS:
			errors.append("tiles b%d: rule 7: the live threats at size %d are %s; they need %d behaviours"
				% [band, size, covered, MIN_THREAT_BEHAVIORS])
	# Rule 8: each live species' strike lane fits the smallest live territory of the tiles, at the size
	# (the q-scaled lane and leash, the territory in tm, D-70).
	for id in species.species_ids():
		if not radii.has(id):
			continue
		var territory: float = float(smallest[id]) * WorldConfig.bu_to_tm(size) if smallest.has(id) \
				else CreatureBrain.DEFAULT_TERRITORY_M * species.q_of(id, size)
		var text := species.strike_room_problem(id, territory, "species '%s'" % id, part_catalog, size)
		if not text.is_empty():
			errors.append("tiles: rule 8: %s" % text)
	return errors


## The species live at `size` (SpeciesCatalog.live_at), each with its body radius there in the bu of
## size's tile frame: at_size(id, size).phenotype.radius / bu_to_tm(size) (D-70). At size 1 that is
## phenotype(id).radius exactly (q 1, and a bu is a tm).
static func radii_at(species: SpeciesCatalog, part_catalog: PartCatalog, size: int) -> Dictionary:
	var radii := {}
	for id in species.species_ids():
		if species.live_at(id, size, part_catalog):
			radii[id] = (species.at_size(id, size, part_catalog).phenotype as Phenotype).radius / WorldConfig.bu_to_tm(size)
	return radii


## The colliders of colliders_of(t) that exist at size n: at the band's second size the shells marked
## "sink" are gone (S2); at any other size, all of them.
static func colliders_at(t: Dictionary, colliders: Array[Dictionary], n: int) -> Array[Dictionary]:
	if n != 2 * int(t.band) + 2:
		return colliders
	var sunk := {}
	for s in t.shells:
		if s.at_second_size == "sink":
			sunk[s.id] = true
	var out: Array[Dictionary] = []
	for c in colliders:
		if not sunk.has(c.id):
			out.append(c)
	return out


## The rule's name in a message: "rule 6" at the band's first size, "rule 6 at size 2" at its second.
static func _rule_at(rule: int, t: Dictionary, size: int) -> String:
	return "rule %d" % rule if size == 2 * int(t.band) + 1 else "rule %d at size %d" % [rule, size]


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
## body live at `size` (radii, bu) to pass between it and every shell there (`there`, colliders_at).
static func _check_anchor(t: Dictionary, kit: PlacementKit, species: SpeciesCatalog, radii: Dictionary,
		there: Array[Dictionary], size: int, errors: PackedStringArray) -> void:
	var w: String = t.where
	var a: PackedFloat64Array = t.landmark_anchor
	if absf(a[0]) > ANCHOR_EDGE_BU or absf(a[1]) > ANCHOR_EDGE_BU:
		errors.append("%s: rule 4: the landmark anchor %s lies beyond %s bu of the centre" % [w, a, ANCHOR_EDGE_BU])
	var r_max := 0.0
	for id in radii:
		r_max = maxf(r_max, radii[id])
	var need := 2.0 * r_max + float(species.fairness.pinch_margin_m) / WorldConfig.bu_to_tm(size)
	var live := {}
	for c in there:
		live[c.id] = true
	for s in t.shells:
		if not live.has(s.id):
			continue
		var gap: float = _vec(a).distance_to(_vec(s.center)) - kit.collide_radius_bu - float(s.radius)
		if gap < need:
			errors.append("%s: %s: the landmark collider leaves %.2f bu to shell '%s'; it needs %.2f" % [w, _rule_at(4, t, size), gap, s.id, need])


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


## Rule 6: each site's species and sizes (every size it names is one its species is live at,
## SpeciesCatalog.live_at) and a second post's own rules (_check_post_b); for the sites live at
## `size`: a clear home, the gap between sites, the territory, and a reach disc with k (D-39) that
## passes _check_disc. A two-post site (B.7, D-38) also has its second post's home clear and its zone
## there, passes _check_disc on each post's disc and on their union (D-82), keeps the union's reach
## (D-61) and a path between its posts (post_path_problems, BP-11). `there` is colliders_at(t, …,
## size); lengths are bu, a fairness length its tm / bu_to_tm(size).
static func _check_sites(t: Dictionary, species: SpeciesCatalog, radii: Dictionary, kit: PlacementKit,
		there: Array[Dictionary], part_catalog: PartCatalog, size: int, errors: PackedStringArray) -> void:
	var w: String = t.where
	var first := 2 * int(t.band) + 1
	var s := WorldConfig.bu_to_tm(size)
	var rule := _rule_at(6, t, size)
	var arena := ChunkArena.from_shells(_arena_circles(there))
	var scaled: Array[Dictionary] = there if s == 1.0 else _scaled(there, s)
	var live: Array[Dictionary] = []
	for site in t.sites:
		var where := "%s: rule 6: site '%s'" % [w, site.id]
		if not species.species.has(site.species):
			errors.append("%s names unknown species '%s'" % [where, site.species])
			continue
		var sizes: Array = site.sizes
		var sizes_ok := not sizes.is_empty()
		for n in sizes:
			sizes_ok = sizes_ok and (n == first or n == first + 1) and sizes.count(n) == 1
		if not sizes_ok:
			errors.append("%s: sizes %s must be some of [%d, %d]" % [where, sizes, first, first + 1])
		else:
			for n in sizes:
				var c := species.entry_size(site.species)
				if n < c:
					errors.append("%s: '%s' enters at size %d, so it cannot be live at size %d" % [where, site.species, c, n])
				elif not species.live_at(site.species, n, part_catalog):
					errors.append("%s: '%s' is haze at size %d, so it cannot be live there" % [where, site.species, n])
		if not site.get("post_b", {}).is_empty():
			_check_post_b(where, t, site, species, part_catalog, errors)
		if sizes.has(size) and radii.has(site.species):
			live.append(site)
	for i in live.size():
		var site: Dictionary = live[i]
		var where := "%s: %s: site '%s'" % [w, rule, site.id]
		var r := float(radii[site.species])
		var home := _vec(site.home)
		if not arena.is_clear(home, r):
			errors.append("%s home %s is not clear" % [where, site.home])
		var min_gap := float(species.spawning.min_gap_m) / s
		for j in i:
			var gap := home.distance_to(_vec(live[j].home))
			if gap < min_gap:
				errors.append("%s is %.2f bu from site '%s'; sites keep %.1f apart" % [where, gap, live[j].id, min_gap])
		var territorial := species.behavior_of(site.species) == "territorial"
		var zone := _zone(t, site.territory_zone)
		if territorial and not _zone_there(where, "territory_zone", site.territory_zone, zone, t, size, errors):
			continue
		var territory := species.territory_from({"species": site.species}, _circle_of(zone))
		var k := WorldConfig.k_of(species.entry_size(site.species), size)
		var at_a := {"species": site.species, "home": home, "heading": float(site.heading)}
		var discs: Array[Dictionary] = []
		if site.get("post_b", {}).is_empty():
			discs.append({"label": "", "disc": species.reach_disc_for(at_a, territory, k), "homes": [site.home]})
		else:
			var post: Dictionary = site.post_b
			var home_b := _vec(post.home)
			if not arena.is_clear(home_b, r):
				errors.append("%s post_b home %s is not clear" % [where, post.home])
			var zone_b := _zone(t, post.territory_zone)
			if territorial and (str(post.territory_zone).is_empty()
					or not _zone_there(where, "post_b.territory_zone", post.territory_zone, zone_b, t, size, errors)):
				continue
			var both := species.two_post_disc_for(at_a, territory, {"home": home_b, "heading": float(post.heading)},
				species.territory_from({"species": site.species}, _circle_of(zone_b)), k)
			discs.append({"label": " post a", "disc": both.posts[0], "homes": [site.home]})
			discs.append({"label": " post b", "disc": both.posts[1], "homes": [post.home]})
			discs.append({"label": " union", "disc": both, "homes": [site.home, post.home]})
			if float(both.radius) * s > MAX_UNION_REACH_TM:
				errors.append("%s union reach disc r %.2f bu is %.2f tm; D-61 keeps it <= %.1f tm"
					% [where, float(both.radius), float(both.radius) * s, MAX_UNION_REACH_TM])
			var half := r + float(CreatureBrain.WORLD_LENGTHS.route_clearance) * species.q_of(site.species, size) / s
			for p in post_path_problems(home, home_b, half, there):
				errors.append("%s: %s" % [where, p])
		for d in discs:
			_check_disc(t, "site '%s'%s" % [site.id, d.label], where + d.label, d.disc, d.homes, r, s, rule, species, kit,
				scaled, errors)


## One reach disc of a live site (`label` names it in rules 9 and 10, `where` elsewhere): inside the
## tile, inset (|disc.c| + disc.r + r + leash_band_margin_m <= 32 bu on both axes), holding each of
## `homes`, rules 9 and 10 against the colliders there with no wall, and rule 8 against the landmark
## anchor. Rules 9 and 10 run in tm (the disc, r and `scaled`, the colliders, times s), so their own
## margins stay the species'; at s 1 every value is S1's.
static func _check_disc(t: Dictionary, label: String, where: String, disc: Dictionary, homes: Array, r: float, s: float,
		rule: String, species: SpeciesCatalog, kit: PlacementKit, scaled: Array[Dictionary], errors: PackedStringArray) -> void:
	var fair := species.fairness
	var c: Vector2 = disc.center
	var reach := float(disc.radius)
	var margin := float(fair.leash_band_margin_m) / s
	var inset := reach + r + margin
	if absf(c.x) + inset > HALF_TILE_BU or absf(c.y) + inset > HALF_TILE_BU:
		errors.append("%s reach disc at %s, r %.2f, comes within %.2f bu of the tile's edge" % [where, c, reach, r + margin])
	for home: PackedFloat64Array in homes:
		if _vec(home).distance_to(c) + r > reach:
			errors.append("%s home %s is not inside its reach disc at %s, r %.2f" % [where, home, c, reach])
	var pinches := PackedStringArray()
	var in_tm: Dictionary = disc if s == 1.0 else {"center": c * s, "radius": reach * s}
	species.check_disc_against_shells(label, in_tm, r * s, scaled, INF, pinches)
	for p in pinches:
		errors.append("%s: %s: %s" % [t.where, rule, p])
	if t.landmark_anchor.size() == 2:
		var clear := _vec(t.landmark_anchor).distance_to(c) - reach - r - (kit.collide_radius_bu + PoolLayout.CELL_RADIUS / s + ANCHOR_GAP_BU)
		var need := (float(fair.respawn_clear_m) + ANCHOR_CLEAR_EXTRA) / s
		if clear < need:
			errors.append("%s can reach %.2f bu from the landmark anchor; it must stay %.1f away" % [where, clear, need])


## A second post's rules that hold at every size (D-38, D-61): a species with a habit; its own
## territory zone exactly when the species is territorial, and not the first post's zone; the posts'
## homes POST_SPACING_TM apart by the habit's post_switch (times k_of in bu); and the move between
## them, at wander speed, within POST_TRAVEL_NAV_SHARE of nav_timeout_s.
static func _check_post_b(where: String, t: Dictionary, site: Dictionary, species: SpeciesCatalog, part_catalog: PartCatalog,
		errors: PackedStringArray) -> void:
	var id: String = site.species
	var habit := species.habit_of(id)
	if habit.is_empty():
		errors.append("%s: post_b needs a species with a habit; '%s' has none" % [where, id])
		return
	var post: Dictionary = site.post_b
	var zone_b := str(post.territory_zone)
	var territorial := species.behavior_of(id) == "territorial"
	if territorial and zone_b.is_empty():
		errors.append("%s: post_b needs a territory_zone, as '%s' is territorial" % [where, id])
	elif not territorial and not zone_b.is_empty():
		errors.append("%s: post_b.territory_zone is refused, as '%s' is not territorial" % [where, id])
	elif territorial and zone_b == site.territory_zone:
		errors.append("%s: post_b guards zone '%s' as post a does; the posts guard two zones" % [where, zone_b])
	var k := WorldConfig.k_of(species.entry_size(id), 2 * int(t.band) + 1)
	var apart := _vec(site.home).distance_to(_vec(post.home))
	var spacing: Array = POST_SPACING_TM.get(str(habit.get("post_switch", "")), [])
	if spacing.size() == 2 and (apart < float(spacing[0]) * k or apart > float(spacing[1]) * k):
		errors.append("%s: its posts are %.2f bu apart; a '%s' habit keeps them %.2f to %.2f bu (%.1f to %.1f tm at q = 1)"
			% [where, apart, habit.post_switch, float(spacing[0]) * k, float(spacing[1]) * k, spacing[0], spacing[1]])
	var wander := species.phenotype(id, part_catalog).speed * float(species.species[id].speeds.wander)
	var allowed := POST_TRAVEL_NAV_SHARE * float(species.brain_config(id).get("nav_timeout_ticks", 0)) * CreatureBrain.DT
	if wander > 0.0 and apart / k / wander > allowed:
		errors.append("%s: the move between its posts takes %.2f s at wander speed; %.1f x nav_timeout_s allows %.2f s"
			% [where, apart / k / wander, POST_TRAVEL_NAV_SHARE, allowed])


## BP-11 (S2G41): the path between a two-post site's homes a and b, the segment widened by
## `half_width` (the body radius plus CreatureBrain.WORLD_LENGTHS.route_clearance x q, in the frame's
## units at the size), overlaps none of `colliders` ({id, center, radius}: those that exist at that
## size). One problem per collider it overlaps. HomeBlock checks its ring sites with it too.
static func post_path_problems(a: Vector2, b: Vector2, half_width: float, colliders: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for c in colliders:
		var center: Vector2 = c.center
		var to_path := center.distance_to(Geometry2D.get_closest_point_to_segment(center, a, b)) - float(c.radius)
		if to_path < half_width:
			out.append("the path between its posts passes %.2f bu from '%s'; it needs %.2f (BP-11)" % [to_path, c.id, half_width])
	return out


## Rule 7: a zone in every tile (one not dropped at the band's second size), threats where they
## belong, the band's behaviours and density. A threat at `size` is a site live there whose species
## has a threat behaviour and entry size `size` (the ladder's "threat"; the M1 species are rivals and
## prey at size 2). Also gathers rule 8's smallest live territory per species, bu (both posts' zones).
static func _check_content(t: Dictionary, species: SpeciesCatalog, size: int, behaviors: Dictionary,
		smallest: Dictionary, errors: PackedStringArray) -> void:
	var w: String = t.where
	var first := 2 * int(t.band) + 1
	if t.zones.is_empty():
		errors.append("%s: rule 7: a tile needs at least one zone" % w)
	elif size == first + 1 and t.zones.all(func(z: Dictionary) -> bool: return z.at_second_size == "drop"):
		errors.append("%s: rule 7 at size %d: every zone is dropped; a tile keeps or thins one" % [w, size])
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
		if threat and species.entry_size(s.species) == size:
			threats += 1
			if not behaviors.has(t.band):
				behaviors[t.band] = {}
			behaviors[t.band][behavior] = true
		if behavior == "territorial":
			for zone_id in [s.territory_zone, s.get("post_b", {}).get("territory_zone", "")]:
				var zone := _zone(t, zone_id)
				if not zone.is_empty():
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
	var post_b := {}
	var raw_b := WorldConfig.object_at(w, d, "post_b", POST_KEYS, problems, POST_OPTIONAL)
	if not raw_b.is_empty():
		var pw := w + ".post_b"
		post_b = {"home": _pair(pw, raw_b, "home", problems), "heading": WorldConfig.number_at(pw, raw_b, "heading", problems),
			"territory_zone": WorldConfig.text_at(pw, raw_b, "territory_zone", problems)}
	return {"id": WorldConfig.text_at(w, d, "id", problems), "species": WorldConfig.text_at(w, d, "species", problems),
		"home": _pair(w, d, "home", problems), "heading": WorldConfig.number_at(w, d, "heading", problems),
		"territory_zone": WorldConfig.text_at(w, d, "territory_zone", problems), "sizes": sizes, "post_b": post_b}


## pair_at, or [0, 0] when it is absent or wrong (the problem is already recorded), so the rules never
## index an empty pair.
static func _pair(w: String, d: Dictionary, key: String, problems: PackedStringArray) -> PackedFloat64Array:
	var p := WorldConfig.pair_at(w, d, key, problems)
	return p if p.size() == 2 else PackedFloat64Array([0.0, 0.0])


static func _vec(p: PackedFloat64Array) -> Vector2:
	return Vector2(p[0], p[1])


static func _is_piece(id: String) -> bool:
	return WorldConfig.matches(id, PIECE_ID_PATTERN)


## A zone's {center, radius} for SpeciesCatalog.territory_from, or {} for no zone.
static func _circle_of(zone: Dictionary) -> Dictionary:
	return {} if zone.is_empty() else {"center": _vec(zone.center), "radius": float(zone.radius)}


## Whether a territorial site's zone `id` (named by `key`) is a zone of the tile that is there at
## `size` (a band's second size drops the "drop" ones); records the problem when it is not.
static func _zone_there(where: String, key: String, id: String, zone: Dictionary, t: Dictionary, size: int,
		errors: PackedStringArray) -> bool:
	if zone.is_empty():
		errors.append("%s %s '%s' is not a zone of this tile" % [where, key, id])
		return false
	if size == 2 * int(t.band) + 2 and zone.at_second_size == "drop":
		errors.append("%s %s '%s' is dropped at size %d" % [where, key, id, size])
		return false
	return true


## Circles ({id, center, radius}) times s, for the rules that measure in tm.
static func _scaled(circles: Array[Dictionary], s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in circles:
		out.append({"id": c.id, "center": Vector2(c.center) * s, "radius": float(c.radius) * s})
	return out


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
