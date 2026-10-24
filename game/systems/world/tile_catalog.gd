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
##
## S3 (spine 5.3, s3-sim 3.11): band 1's regions and rare kinds, and which sites are live as what
## (site_role, D-97): a threat, rival or prey site is a creature site, a morsel site is food (it
## counts against MAX_MORSEL_SITES, not the creature caps). Tile rules 9 to 12 hold at band 1 and
## up: prey or morsel at both sizes (9), the morsel cap (10), a Deep lurker's channel (11, D-137)
## and room round a hazard's home (12, D-137); D-135 caps a band-1 tile's shells and zones.
##
## A tile dict may carry "half_bu" and "frame" (CradleBlock's whole block: 64.0, "block"): the edge
## tests of rules 2, 3 and 6 then measure from that half-width and name that frame. Every file tile
## has neither, so its rules are S1's.

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
## Band 0's regions (S1); each band's are WorldConfig.regions_of(band).
const REGIONS: PackedStringArray = ["sunlit", "reef", "drift"]
const SETS := 2
const TILES_PER_SET := 3
## Each band's rare kinds (rule 1). The fixed rare tile of each band's arrangement names one of them.
const RARE_KINDS_BY_BAND := {0: ["giant_husk", "shell_cathedral"],
	1: ["fallen_lattice", "shed_shell", "sponge_grove", "sunbeam_well"]}
## Rule 7: the behaviours of a threat (a site whose site_role is "threat": the ladder's role at its
## species' entry size).
const THREAT_BEHAVIORS: PackedStringArray = ["ambush", "territorial", "hazard"]
## The site roles that are creatures (D-97); "morsel" is food.
const CREATURE_ROLES: PackedStringArray = ["threat", "rival", "prey"]
## Rule 10: morsel sites per tile at any size.
const MAX_MORSEL_SITES := 3
## Rule 11 (D-137): a channel lane is flanked at a station when a shell collider's edge lies within
## CHANNEL_FLANK_M (tm) on each side, and at least CHANNEL_FLANK_SHARE of the stations, every
## CHANNEL_STATION_BU along the lane, are flanked.
const CHANNEL_FLANK_M := 3.0
const CHANNEL_FLANK_SHARE := 0.6
const CHANNEL_STATION_BU := 0.25
## D-135, band 1 and up: shells and zones per tile, and zones live at the band's second size (keep
## or thin) at most.
const MAX_SHELLS_B1 := 18
const MAX_ZONES_B1 := 12
const MAX_ZONES_SECOND_SIZE_B1 := 6
## D-147: an elder Warden's meadows (the bloom habit's zones) are 5 to 6 bu round.
const BLOOM_ZONE_R := [5.0, 6.0]
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
## Rule 7 at the band's second size (PROPOSED): a sunlit or reef tile of this set needs a live site
## there, not a threat: one of the first size's species the cell now outgrows (a rammer, a lair).
## The other set's tiles each need a threat, so of two edge neighbours of a region (the sets
## alternate, WorldGen) one holds a threat. A threat in every tile as well would put two live sites
## in each, and the site sample (B-17) allows about one per 40 tm tile.
const SECOND_SIZE_OUTGROWN_SET := 0
const MIN_THREAT_BEHAVIORS := 2
## D-61: how far apart a two-post site's homes lie, in the species' own tm (q = 1), by its habit's
## post_switch: the Lurker's 4 to 6 tm, the elder rammer's 6.0 to 10.5 tm. Times k_of in bu.
## S3's bloom (D-147): 13 to 16.5 bu apart at band 1, k 1.6, so 8.125 to 10.3125 tm.
const POST_SPACING_TM := {"out_of_sight": [4.0, 6.0], "nearer_cell": [6.0, 10.5], "bloom": [8.125, 10.3125]}
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
## tm: a morsel site's radius at most (world_cell.json growth.remnants.morsel_max_radius_tm, which
## WorldContent sets here before validate; this is the shipped value).
var morsel_max_radius_tm := 0.225


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
	var regions := WorldConfig.regions_of(band)
	if data.has("region") and not (regions.has(t.region) or is_rare):
		problems.append("%s.region: '%s' is not one of %s, %s" % [w, t.region, ", ".join(regions), RARE])
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


## What a site is at the cell's size n (D-97): "threat", "rival", "prey" or "morsel" when n is one
## of its sizes and Relationships.ladder_role says so (at the species' radius there, radius_at),
## else "" (not live: not one of its sizes, or its species is a ghost or haze there).
static func site_role(species: SpeciesCatalog, site: Dictionary, n: int) -> String:
	var sp := str(site.species)
	if not (site.sizes as Array).has(n) or not species.species.has(sp) or n < species.entry_size(sp):
		return ""
	var role := Relationships.ladder_role(species.entry_size(sp), n, species.radius_at(sp, n), species.share_tolerance())
	return role if role in ["threat", "rival", "prey", "morsel"] else ""


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
		_check_sites(t, species, radii, kit, there, part_catalog, size, errors, morsel_max_radius_tm)
		_check_content(t, species, size, behaviors, smallest, errors)
	for band in bands:
		var covered: Array = WorldConfig._sorted(behaviors.get(band, {}).keys())
		if covered.size() < MIN_THREAT_BEHAVIORS:
			errors.append("tiles b%d: rule 7: the live threats at size %d are %s; they need %d behaviours"
				% [band, size, covered, MIN_THREAT_BEHAVIORS])
	check_strike_room("tiles", species, radii, smallest, part_catalog, size, errors)
	return errors


## Rule 8: each live species' strike lane fits the smallest live territory (`smallest`, bu, by species,
## as _check_content gathers it), at the size (the q-scaled lane and leash, the territory in tm, D-70).
static func check_strike_room(w: String, species: SpeciesCatalog, radii: Dictionary, smallest: Dictionary,
		part_catalog: PartCatalog, size: int, errors: PackedStringArray) -> void:
	for id in species.species_ids():
		if not radii.has(id):
			continue
		var territory: float = float(smallest[id]) * WorldConfig.bu_to_tm(size) if smallest.has(id) \
				else CreatureBrain.DEFAULT_TERRITORY_M * species.q_of(id, size)
		var text := species.strike_room_problem(id, territory, "species '%s'" % id, part_catalog, size)
		if not text.is_empty():
			errors.append("%s: rule 8: %s" % [w, text])


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

## Rule 1: 6 tiles per region of the band, 3 in each set, and one rare tile per rare kind.
func _check_counts(band: int, errors: PackedStringArray) -> void:
	for region in WorldConfig.regions_of(band):
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
	if RARE_KINDS_BY_BAND.has(band) and Array(rare_kinds(band)) != RARE_KINDS_BY_BAND[band]:
		errors.append("tiles b%d: rule 1: the rare kinds are %s, not %s" % [band, rare_kinds(band), RARE_KINDS_BY_BAND[band]])


## Rule 2: shell radii and kit fit, edges, overlaps, tunnelling at the second size, yaw ranges.
static func _check_shells(t: Dictionary, kit: PlacementKit, colliders: Array[Dictionary], errors: PackedStringArray) -> void:
	var w: String = t.where
	var half := _half(t)
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
		if absf(c[0]) + r > half - (HALF_TILE_BU - SHELL_EDGE_BU) or absf(c[1]) + r > half - (HALF_TILE_BU - SHELL_EDGE_BU):
			errors.append("%s: rule 2: shell '%s' at %s comes within %s bu of the %s's edge" % [w, s.id, c, HALF_TILE_BU - SHELL_EDGE_BU, _frame(t)])
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
	var half := _half(t)
	for z in t.zones:
		var c: PackedFloat64Array = z.center
		var r := float(z.radius)
		if not (r >= MIN_ZONE_R and r <= MAX_ZONE_R and z.capacity > 0.0 and z.growth_rate > 0.0):
			errors.append("%s: rule 3: zone '%s' needs %s <= radius <= %s and a positive capacity and growth rate"
				% [w, z.id, MIN_ZONE_R, MAX_ZONE_R])
			continue
		if absf(c[0]) + r > half - (HALF_TILE_BU - ZONE_EDGE_BU) or absf(c[1]) + r > half - (HALF_TILE_BU - ZONE_EDGE_BU):
			errors.append("%s: rule 3: zone '%s' at %s comes within %s bu of the %s's edge" % [w, z.id, c, HALF_TILE_BU - ZONE_EDGE_BU, _frame(t)])
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
## size); lengths are bu, a fairness length its tm / bu_to_tm(size). Rule 8 against the anchor (the
## checkpoint's respawn clearance) binds the species that can attack the cell at the size
## (Relationships.can_attack_player): every live one at a band's first size, the band's own threats at
## its second (the M1 species are rivals and prey there).
static func _check_sites(t: Dictionary, species: SpeciesCatalog, radii: Dictionary, kit: PlacementKit,
		there: Array[Dictionary], part_catalog: PartCatalog, size: int, errors: PackedStringArray,
		morsel_max_r_tm := 0.225) -> void:
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
		if radii.has(site.species) and site_role(species, site, size) != "":
			live.append(site)
	for i in live.size():
		var site: Dictionary = live[i]
		var where := "%s: %s: site '%s'" % [w, rule, site.id]
		var r := float(radii[site.species])
		var home := _vec(site.home)
		var morsel := site_role(species, site, size) == "morsel"
		if morsel:
			# A morsel site is food (D-97): a clear home inside the tile at the morsel's radius, and the gap.
			r = minf(species.radius_at(site.species, size), morsel_max_r_tm) / s
			if absf(home.x) + r > _half(t) or absf(home.y) + r > _half(t):
				errors.append("%s home %s is not inside the %s" % [where, site.home, _frame(t)])
		if not arena.is_clear(home, r):
			errors.append("%s home %s is not clear" % [where, site.home])
		var min_gap := float(species.spawning.min_gap_m) / s
		for j in i:
			var gap := home.distance_to(_vec(live[j].home))
			if gap < min_gap:
				errors.append("%s is %.2f bu from site '%s'; sites keep %.1f apart" % [where, gap, live[j].id, min_gap])
		if morsel:
			continue
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
		var attacks := Relationships.can_attack_player(species.q_of(site.species, size))
		for d in discs:
			_check_disc(t, "site '%s'%s" % [site.id, d.label], where + d.label, d.disc, d.homes, r, s, rule, species, kit,
				scaled, attacks, errors)
		if species.behavior_of(site.species) == "hazard":
			_check_hazard_room(t, site, species, r, s, size, there, errors)
		if bool(species.habit_of(site.species).get("channel", false)) and species.q_of(site.species, size) == 1.0:
			_check_channel(t, site, species, r, s, size, there, errors)


## Rule 12 (D-137): no collider within the hazard's leash plus its body of its home, the collider's
## own radius added (in bu at the size: (leash_m x q + R) / bu_to_tm), so its drift and a flee never
## meet a shell.
static func _check_hazard_room(t: Dictionary, site: Dictionary, species: SpeciesCatalog, r: float, s: float, size: int,
		there: Array[Dictionary], errors: PackedStringArray) -> void:
	var home := _vec(site.home)
	var room := float(species.brain_config(site.species).leash_m) * species.q_of(site.species, size) / s + r
	for c in there:
		var gap: float = home.distance_to(c.center) - float(c.radius)
		if gap < room:
			errors.append("%s: %s: site '%s': '%s' lies %.2f bu from the hazard's home; it needs %.2f (its leash and body)"
				% [t.where, _rule_at(12, t, size), site.id, c.id, gap, room])


## Rule 11 (D-137): a channel lair's strike lane, from its home along its heading for start_max_m
## plus the strike's travel and as wide as CreatureBrain.strike_lane's, hits no collider, and at
## least CHANNEL_FLANK_SHARE of its stations have a collider edge within CHANNEL_FLANK_M of them on
## each side (left and right of the heading).
## Lengths in bu at the size (tm / bu_to_tm); the site is at q = 1.
static func _check_channel(t: Dictionary, site: Dictionary, species: SpeciesCatalog, r: float, s: float, size: int,
		there: Array[Dictionary], errors: PackedStringArray) -> void:
	var where := "%s: %s: site '%s'" % [t.where, _rule_at(11, t, size), site.id]
	var cfg := species.brain_config(site.species)
	var lane := CreatureBrain.strike_lane(cfg.attack, r * s, PoolLayout.CELL_RADIUS, Vector2.ZERO, 0.0)
	var length := (float(cfg.attack.start_max_m) + float(cfg.attack.travel)) / s
	var half := float(lane.half_width) / s
	var home := _vec(site.home)
	var along := Vector2.from_angle(float(site.heading))
	var tip := home + along * length
	for c in there:
		var center: Vector2 = c.center
		var to_lane := center.distance_to(Geometry2D.get_closest_point_to_segment(center, home, tip)) - float(c.radius)
		if to_lane < half:
			errors.append("%s: '%s' lies %.2f bu from its channel's lane; the lane is %.2f wide each side" % [where, c.id, to_lane, half])
	var flank := CHANNEL_FLANK_M / s
	var stations := maxi(1, floori(length / CHANNEL_STATION_BU) + 1)
	var flanked := 0
	for k in stations:
		var p := home + along * minf(k * CHANNEL_STATION_BU, length)
		var left := false
		var right := false
		for c in there:
			var rel: Vector2 = Vector2(c.center) - p
			if rel.length() - float(c.radius) <= flank:
				var side := along.cross(rel)
				left = left or side > 0.0
				right = right or side < 0.0
		flanked += 1 if left and right else 0
	if float(flanked) < CHANNEL_FLANK_SHARE * stations:
		errors.append("%s: %d of its channel's %d stations are flanked on both sides within %.2f bu; it needs %d%%"
			% [where, flanked, stations, flank, roundi(CHANNEL_FLANK_SHARE * 100.0)])


## One reach disc of a live site (`label` names it in rules 9 and 10, `where` elsewhere): inside the
## tile, inset (|disc.c| + disc.r + r + leash_band_margin_m <= 32 bu on both axes), holding each of
## `homes`, rules 9 and 10 against the colliders there with no wall, and, when the species `attacks`
## the cell at the size, rule 8 against the landmark anchor. Rules 9 and 10 run in tm (the disc, r and
## `scaled`, the colliders, times s), so their own margins stay the species'; at s 1 every value is S1's.
static func _check_disc(t: Dictionary, label: String, where: String, disc: Dictionary, homes: Array, r: float, s: float,
		rule: String, species: SpeciesCatalog, kit: PlacementKit, scaled: Array[Dictionary], attacks: bool,
		errors: PackedStringArray) -> void:
	var fair := species.fairness
	var c: Vector2 = disc.center
	var reach := float(disc.radius)
	var margin := float(fair.leash_band_margin_m) / s
	var inset := reach + r + margin
	if absf(c.x) + inset > _half(t) or absf(c.y) + inset > _half(t):
		errors.append("%s reach disc at %s, r %.2f, comes within %.2f bu of the %s's edge" % [where, c, reach, r + margin, _frame(t)])
	for home: PackedFloat64Array in homes:
		if _vec(home).distance_to(c) + r > reach:
			errors.append("%s home %s is not inside its reach disc at %s, r %.2f" % [where, home, c, reach])
	var pinches := PackedStringArray()
	var in_tm: Dictionary = disc if s == 1.0 else {"center": c * s, "radius": reach * s}
	species.check_disc_against_shells(label, in_tm, r * s, scaled, INF, pinches)
	for p in pinches:
		errors.append("%s: %s: %s" % [t.where, rule, p])
	if attacks and t.landmark_anchor.size() == 2:
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
	if str(habit.get("post_switch", "")) == "bloom":
		# D-147: the elder Warden's two meadows, 5 to 6 bu round, do not overlap.
		var za := _zone(t, site.territory_zone)
		var zb := _zone(t, zone_b)
		for z in [za, zb]:
			if not z.is_empty() and (float(z.radius) < BLOOM_ZONE_R[0] or float(z.radius) > BLOOM_ZONE_R[1]):
				errors.append("%s: meadow '%s' has radius %.2f bu; a bloom habit's meadows are %.1f to %.1f"
					% [where, z.id, float(z.radius), BLOOM_ZONE_R[0], BLOOM_ZONE_R[1]])
		if not za.is_empty() and not zb.is_empty():
			var between := _vec(za.center).distance_to(_vec(zb.center)) - float(za.radius) - float(zb.radius)
			if between < 0.0:
				errors.append("%s: its meadows '%s' and '%s' overlap by %.2f bu" % [where, za.id, zb.id, -between])
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
## belong, the band's behaviours and density; rules 9 and 10 and D-135 at band 1 and up. A threat at
## `size` is a site whose site_role there is "threat" and whose species has a threat behaviour.
## Band 0 keeps S2's second size: a sunlit or reef tile of SECOND_SIZE_OUTGROWN_SET needs only a live
## creature site there. Otherwise every ordinary tile not of the band's transit region
## (WorldConfig.transit_of: band 0's drift; band 1 has none), and every rare tile, needs a threat at
## each size, and a transit tile has none. Creature roles count against MAX_SITES_FIRST_SIZE and
## MAX_SITES_SECOND_SIZE, morsel roles against MAX_MORSEL_SITES (D-97). Also gathers rule 8's smallest
## live territory per species, bu (both posts' zones).
static func _check_content(t: Dictionary, species: SpeciesCatalog, size: int, behaviors: Dictionary,
		smallest: Dictionary, errors: PackedStringArray) -> void:
	var w: String = t.where
	var band := int(t.band)
	var first := 2 * band + 1
	if t.zones.is_empty():
		errors.append("%s: rule 7: a tile needs at least one zone" % w)
	elif size == first + 1 and t.zones.all(func(z: Dictionary) -> bool: return z.at_second_size == "drop"):
		errors.append("%s: rule 7 at size %d: every zone is dropped; a tile keeps or thins one" % [w, size])
	var threats := 0
	var live := 0
	var creatures := [0, 0]      # creature sites at the band's first and second sizes
	var morsels := [0, 0]
	var food := [false, false]   # rule 9: a prey or morsel site at each size
	var any_threat := false
	for s in t.sites:
		var behavior := species.behavior_of(s.species)
		var threat := THREAT_BEHAVIORS.has(behavior)
		any_threat = any_threat or threat
		for i in 2:
			var role := site_role(species, s, first + i)
			if role in CREATURE_ROLES:
				creatures[i] += 1
			elif role == "morsel":
				morsels[i] += 1
			food[i] = food[i] or role == "prey" or role == "morsel"
		var here := site_role(species, s, size)
		if not (here in CREATURE_ROLES):
			continue
		live += 1
		if threat and here == "threat":
			threats += 1
			if not behaviors.has(band):
				behaviors[band] = {}
			behaviors[band][behavior] = true
		if behavior == "territorial":
			for zone_id in [s.territory_zone, s.get("post_b", {}).get("territory_zone", "")]:
				var zone := _zone(t, zone_id)
				if not zone.is_empty():
					smallest[s.species] = minf(float(smallest.get(s.species, INF)), float(zone.radius))
	var transit := WorldConfig.transit_of(band)
	if not transit.is_empty() and t.region == transit and any_threat:
		errors.append("%s: rule 7: a %s tile has no threat site" % [w, transit])
	elif band == 0 and t.region != transit and size == first + 1 and int(t.set) == SECOND_SIZE_OUTGROWN_SET:
		if live == 0:
			errors.append("%s: rule 7: a %s tile of set %d needs a live site at size %d" % [w, t.region, t.set, size])
	elif t.region != transit and threats == 0:
		errors.append("%s: rule 7: a %s tile needs a live threat site at size %d" % [w, t.region, size])
	if creatures[0] > MAX_SITES_FIRST_SIZE or creatures[1] > MAX_SITES_SECOND_SIZE:
		errors.append("%s: rule 7: %d sites are live at size %d and %d at size %d; at most %d and %d"
			% [w, creatures[0], first, creatures[1], first + 1, MAX_SITES_FIRST_SIZE, MAX_SITES_SECOND_SIZE])
	if band < 1:
		return
	if t.region != RARE and not (food[0] and food[1]):
		errors.append("%s: rule 9: a tile needs a prey or morsel site at both sizes (at %d: %s, at %d: %s)"
			% [w, first, food[0], first + 1, food[1]])
	if morsels[0] > MAX_MORSEL_SITES or morsels[1] > MAX_MORSEL_SITES:
		errors.append("%s: rule 10: %d and %d morsel sites at sizes %d and %d; at most %d"
			% [w, morsels[0], morsels[1], first, first + 1, MAX_MORSEL_SITES])
	var second_zones: int = t.zones.filter(func(z: Dictionary) -> bool: return z.at_second_size != "drop").size()
	if t.shells.size() > MAX_SHELLS_B1 or t.zones.size() > MAX_ZONES_B1 or second_zones > MAX_ZONES_SECOND_SIZE_B1:
		errors.append("%s: D-135: %d shells, %d zones and %d live at size %d; at most %d, %d and %d"
			% [w, t.shells.size(), t.zones.size(), second_zones, first + 1, MAX_SHELLS_B1, MAX_ZONES_B1, MAX_ZONES_SECOND_SIZE_B1])


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


## The half-width the edge tests measure from, and the frame's name in their messages (see the top).
static func _half(t: Dictionary) -> float:
	return float(t.get("half_bu", HALF_TILE_BU))


static func _frame(t: Dictionary) -> String:
	return str(t.get("frame", "tile"))


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
