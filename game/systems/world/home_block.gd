class_name HomeBlock
extends RefCounted
## The home block of band 0 (S1; docs/s1/s1-interfaces.md sections 3.5 and 4.3): the 128 x 128 bu
## block at the origin, which is the M1 pool as built, unwalled (its rocks, zones, spawn, starting
## carrion and sites, with their ids), plus an authored seam ring from seam_inner_r to the block
## edge (game/data/home_b0.json, plan A.3).
##
## The M1 half comes from the layout and species objects the session already uses (one source,
## D-5), widened to float64; the file names them (base_layout, base_sites) and supplies only the
## ring. Coordinates are bu relative to abs (0, 0).

const DEFAULT_PATH := "res://game/data/home_b0.json"
const FILE_KEYS: PackedStringArray = ["schema_version", "status", "note", "band", "base_layout", "base_sites",
	"seam_inner_r", "shells", "zones", "sites"]
const HALF_BLOCK_BU := 64.0
const SHELL_EDGE_BU := 60.0       ## rule 2: ring shells keep 4 bu clear of the block's edges
const ZONE_EDGE_BU := 63.0        ## rule 3: ring zones keep 1 bu clear
const MIN_RING_SHELLS := 6
const MAX_RING_SHELLS := 8
## Rule 3, as amended by docs/s1/s1-content.md 17.1: eight zones of R 4 to 5 at |c| 46 to 50 (the
## spine's rule) leave the block's corners 37.6 tm from food against a 16.3 tm budget, so the ring
## holds 16 to 24 zones of R 4 to 6 and capacity 8 to 24, anywhere outside seam_inner_r.
const MIN_RING_ZONES := 16
const MAX_RING_ZONES := 24
const MIN_RING_ZONE_R := 4.0
const MAX_RING_ZONE_R := 6.0
const MIN_RING_CAPACITY := 8.0
const MAX_RING_CAPACITY := 24.0
const ZONE_GAP_BU := 1.0          ## ring zones keep this far from each other
const ZONE_SHELL_GAP_BU := 0.5    ## and this far from every shell
## Rule 4: no new site inside this radius at the band's first size.
const MIN_SITE_R_FIRST_SIZE := 44.0

## Problems found while reading (unknown or missing keys, wrong types, ids, base files).
var load_problems := PackedStringArray()
## The file's name without .json, which every message starts with.
var where := "home_b0"
var band := 0
var seam_inner_r := 36.0
## {id, x, y, r (bu), asset, yaw_deg, scale, fixed: bool, yaw_range: [lo, hi], at_second_size}; M1
## rocks first in data order (fixed, as pool_m1.json places them), then the seam ring (asset ""
## and scale 0.0: WorldGen picks them per seed).
var shells: Array[Dictionary] = []
## {id, x, y, radius, capacity, growth_rate, at_second_size, m1: bool}; M1 zones first.
var zones: Array[Dictionary] = []
## {id, species, x, y, heading, territory_zone, sizes: Array[int], m1: bool}; M1 sites (sizes [1, 2]) first.
var sites: Array[Dictionary] = []
var spawn := PackedFloat64Array([0.0, 9.0])
var spawn_heading := -1.5708
## [[x, y], ...] from pool_m1.json.
var carrion_initial: Array = []


## Never null: a missing or unreadable file gives a block whose validate() says why. A null layout or
## species is loaded from the file's base_layout or base_sites.
static func load_from(path: String, layout: PoolLayout, species: SpeciesCatalog) -> HomeBlock:
	var data: Variant = WorldConfig.read_json(path)
	if data == null:
		var broken := HomeBlock.new()
		broken.where = path.get_file().get_basename()
		broken.load_problems.append("%s: missing or not readable JSON" % path.get_file())
		return broken
	return from_dict(data, layout, species, path.get_file().get_basename())


static func from_dict(data: Variant, layout: PoolLayout, species: SpeciesCatalog, file_id: String = "home_b0") -> HomeBlock:
	var home := HomeBlock.new()
	home.where = file_id
	var w := file_id
	var problems := home.load_problems
	problems.append_array(WorldConfig.schema_problems(w, data, FILE_KEYS))
	if not data is Dictionary:
		return home
	WorldConfig.header_check(w, data, problems)
	home.band = int(WorldConfig.number_at(w, data, "band", problems, true))
	home.seam_inner_r = WorldConfig.number_at(w, data, "seam_inner_r", problems)
	var base_layout := WorldConfig.text_at(w, data, "base_layout", problems)
	var base_sites := WorldConfig.text_at(w, data, "base_sites", problems)
	for pair in [["base_layout", base_layout], ["base_sites", base_sites]]:
		if data.has(pair[0]) and not (str(pair[1]).begins_with("res://") and FileAccess.file_exists(pair[1])):
			problems.append("%s.%s: the file '%s' does not exist" % [w, pair[0], pair[1]])
	if layout == null and FileAccess.file_exists(base_layout):
		layout = PoolLayout.load_from(base_layout)
	if species == null and FileAccess.file_exists(base_sites):
		species = SpeciesCatalog.load_from(base_sites)
	if layout != null:
		home._take_m1_layout(layout)
	if species != null:
		home._take_m1_sites(species)
	# The ring, read as tile lists are (the same keys, local ids and messages).
	for s in TileCatalog.read_list(w, data, "shells", TileCatalog.SHELL_KEYS, PackedStringArray(), problems, TileCatalog.read_shell):
		home.shells.append({"id": s.id, "x": s.center[0], "y": s.center[1], "r": float(s.radius), "asset": "",
			"yaw_deg": s.yaw_deg[0], "scale": 0.0, "fixed": false, "yaw_range": s.yaw_deg, "at_second_size": s.at_second_size})
	for z in TileCatalog.read_list(w, data, "zones", TileCatalog.ZONE_KEYS, PackedStringArray(), problems, TileCatalog.read_zone):
		home.zones.append({"id": z.id, "x": z.center[0], "y": z.center[1], "radius": float(z.radius), "capacity": float(z.capacity),
			"growth_rate": float(z.growth_rate), "at_second_size": z.at_second_size, "m1": false})
	for s in TileCatalog.read_list(w, data, "sites", TileCatalog.SITE_KEYS, TileCatalog.SITE_OPTIONAL, problems, TileCatalog.read_site):
		home.sites.append({"id": s.id, "species": s.species, "x": s.home[0], "y": s.home[1], "heading": float(s.heading),
			"territory_zone": s.territory_zone, "sizes": s.sizes, "m1": false})
	return home


func _take_m1_layout(layout: PoolLayout) -> void:
	spawn = PackedFloat64Array([layout.spawn.x, layout.spawn.y])
	spawn_heading = layout.spawn_heading
	for p: Vector2 in layout.carrion.get("initial", []):
		carrion_initial.append([float(p.x), float(p.y)])
	for r in layout.rocks:
		var yaw := float(r.yaw_deg)
		shells.append({"id": r.id, "x": float(r.center.x), "y": float(r.center.y), "r": float(r.radius), "asset": r.asset,
			"yaw_deg": yaw, "scale": float(r.scale), "fixed": true, "yaw_range": PackedFloat64Array([yaw, yaw]), "at_second_size": "keep"})
	for z in layout.zones:
		zones.append({"id": z.id, "x": float(z.center.x), "y": float(z.center.y), "radius": float(z.radius), "capacity": float(z.capacity),
			"growth_rate": float(z.growth_rate), "at_second_size": "keep", "m1": true})


func _take_m1_sites(species: SpeciesCatalog) -> void:
	var first := 2 * band + 1
	for s in species.sites:
		var sizes: Array[int] = [first, first + 1]
		sites.append({"id": s.id, "species": s.species, "x": float(s.home.x), "y": float(s.home.y), "heading": float(s.heading),
			"territory_zone": str(s.get("territory_zone", "")), "sizes": sizes, "m1": true})


## The block's circles ({id, center: Vector2, radius}): the M1 rocks, then the ring shells.
func circles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in shells:
		out.append({"id": s.id, "center": Vector2(s.x, s.y), "radius": float(s.r)})
	return out


## The block's zones as a PoolLayout gives them ({id, center: Vector2, radius, capacity, growth_rate}).
func zone_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z in zones:
		out.append({"id": z.id, "center": Vector2(z.x, z.y), "radius": z.radius, "capacity": z.capacity, "growth_rate": z.growth_rate})
	return out


## Problems with the block; empty when the world can place it. Reading problems come back alone.
## The rules of spine 4.3 (rule 3 as amended, see MIN_RING_ZONES) at `size` (1 in S1).
func validate(species: SpeciesCatalog, kit: PlacementKit, part_catalog: PartCatalog, size: int = 1) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var w := where
	var ring_shells := shells.filter(func(s: Dictionary) -> bool: return not s.fixed)
	var ring_zones := zones.filter(func(z: Dictionary) -> bool: return not z.m1)
	var ring_sites := sites.filter(func(s: Dictionary) -> bool: return not s.m1)
	# Rule 1: the ring never redefines an M1 id (its lists' own repeats are reading problems).
	var m1_ids := {}
	for list in [shells, zones, sites]:
		for item in list:
			if (item.has("fixed") and item.fixed) or item.get("m1", false):
				m1_ids[item.id] = true
	for list in [ring_shells, ring_zones, ring_sites]:
		for item in list:
			if m1_ids.has(item.id):
				errors.append("%s: rule 1: the ring's id '%s' is an M1 id" % [w, item.id])
	_check_ring_shells(ring_shells, kit, errors)
	_check_ring_zones(ring_zones, errors)
	_check_sites(ring_sites, species, part_catalog, size, errors)
	return errors


## Rule 2: 6 to 8 ring shells outside seam_inner_r, 4 bu clear of the edges, each with two kit
## shells to fill it; plus the tile rules a ring slot shares (yaw range, second size, no overlap).
func _check_ring_shells(ring: Array, kit: PlacementKit, errors: PackedStringArray) -> void:
	var w := where
	if ring.size() < MIN_RING_SHELLS or ring.size() > MAX_RING_SHELLS:
		errors.append("%s: rule 2: the ring has %d shells; it needs %d to %d" % [w, ring.size(), MIN_RING_SHELLS, MAX_RING_SHELLS])
	for i in ring.size():
		var s: Dictionary = ring[i]
		var c := Vector2(s.x, s.y)
		var r := float(s.r)
		if c.length() - r < seam_inner_r:
			errors.append("%s: rule 2: shell '%s' at %s reaches inside seam_inner_r %s" % [w, s.id, c, seam_inner_r])
		if absf(s.x) + r > SHELL_EDGE_BU or absf(s.y) + r > SHELL_EDGE_BU:
			errors.append("%s: rule 2: shell '%s' at %s comes within %s bu of the block's edge" % [w, s.id, c, HALF_BLOCK_BU - SHELL_EDGE_BU])
		var fits := kit.fitting(r, band)
		if fits.size() < PlacementKit.MIN_PICKABLE_PER_CLASS:
			errors.append("%s: rule 2: shell '%s' radius %s fits %s; it needs %d kit shells" % [w, s.id, r, fits, PlacementKit.MIN_PICKABLE_PER_CLASS])
		var yaw: PackedFloat64Array = s.yaw_range
		if not (0.0 <= yaw[0] and yaw[0] <= yaw[1] and yaw[1] <= 360.0):
			errors.append("%s: rule 2: shell '%s' yaw_deg %s needs 0 <= lo <= hi <= 360" % [w, s.id, yaw])
		if not TileCatalog.SHELL_SECOND_SIZE.has(s.at_second_size):
			errors.append("%s: rule 2: shell '%s' at_second_size '%s' is not one of %s" % [w, s.id, s.at_second_size, ", ".join(TileCatalog.SHELL_SECOND_SIZE)])
		# No overlap with an M1 rock, or with a later ring shell (each pair once).
		var others := shells.filter(func(o: Dictionary) -> bool: return o.fixed)
		others.append_array(ring.slice(i + 1))
		for o in others:
			var gap := c.distance_to(Vector2(o.x, o.y)) - r - float(o.r)
			if gap < 0.0:
				errors.append("%s: rule 2: shells '%s' and '%s' overlap by %.2f bu" % [w, s.id, o.id, -gap])


## Rule 3 (amended): 16 to 24 ring zones, R 4 to 6, capacity 8 to 24, outside seam_inner_r and 1 bu
## clear of the edges, 1 bu from each other and 0.5 bu from every shell, and static #33.
func _check_ring_zones(ring: Array, errors: PackedStringArray) -> void:
	var w := where
	if ring.size() < MIN_RING_ZONES or ring.size() > MAX_RING_ZONES:
		errors.append("%s: rule 3: the ring has %d zones; it needs %d to %d" % [w, ring.size(), MIN_RING_ZONES, MAX_RING_ZONES])
	for i in ring.size():
		var z: Dictionary = ring[i]
		var c := Vector2(z.x, z.y)
		var r := float(z.radius)
		if not (r >= MIN_RING_ZONE_R and r <= MAX_RING_ZONE_R and z.capacity >= MIN_RING_CAPACITY and z.capacity <= MAX_RING_CAPACITY and z.growth_rate > 0.0):
			errors.append("%s: rule 3: zone '%s' needs %s <= radius <= %s, %s <= capacity <= %s and a positive growth rate"
				% [w, z.id, MIN_RING_ZONE_R, MAX_RING_ZONE_R, MIN_RING_CAPACITY, MAX_RING_CAPACITY])
			continue
		if c.length() - r < seam_inner_r:
			errors.append("%s: rule 3: zone '%s' at %s reaches inside seam_inner_r %s" % [w, z.id, c, seam_inner_r])
		if absf(z.x) + r > ZONE_EDGE_BU or absf(z.y) + r > ZONE_EDGE_BU:
			errors.append("%s: rule 3: zone '%s' at %s comes within %s bu of the block's edge" % [w, z.id, c, HALF_BLOCK_BU - ZONE_EDGE_BU])
		if not TileCatalog.ZONE_SECOND_SIZE.has(z.at_second_size):
			errors.append("%s: rule 3: zone '%s' at_second_size '%s' is not one of %s" % [w, z.id, z.at_second_size, ", ".join(TileCatalog.ZONE_SECOND_SIZE)])
		var yield_rate := float(z.growth_rate) * float(z.capacity) * (TileCatalog.YIELD_SHARE + EcologyRegion.REGROW_FLOOR)
		if yield_rate > TileCatalog.MAX_ZONE_YIELD:
			errors.append("%s: rule 3: zone '%s' yields %.3f a second; static #33 allows %.3f" % [w, z.id, yield_rate, TileCatalog.MAX_ZONE_YIELD])
		for j in range(i + 1, ring.size()):
			var o: Dictionary = ring[j]
			var gap := c.distance_to(Vector2(o.x, o.y)) - r - float(o.radius)
			if gap < ZONE_GAP_BU:
				errors.append("%s: rule 3: zones '%s' and '%s' are %.2f bu apart; they keep %.1f" % [w, z.id, o.id, gap, ZONE_GAP_BU])
		for s in shells:
			var gap := c.distance_to(Vector2(s.x, s.y)) - r - float(s.r)
			if gap < ZONE_SHELL_GAP_BU:
				errors.append("%s: rule 3: zone '%s' is %.2f bu from shell '%s'; it keeps %.1f" % [w, z.id, gap, s.id, ZONE_SHELL_GAP_BU])


## Rules 4 to 6: the ring's sites (species, sizes, no new site inside r 44 at the first size), and
## for every live site, M1 and ring: a reach disc inside the block that holds the home, rules 9 and
## 10 against every home shell with no wall, and rule 8 against the spawn.
func _check_sites(ring: Array, species: SpeciesCatalog, part_catalog: PartCatalog, size: int, errors: PackedStringArray) -> void:
	var w := where
	var first := 2 * band + 1
	var fair := species.fairness
	for s in ring:
		var label := "%s: rule 4: site '%s'" % [w, s.id]
		if not species.species.has(s.species):
			errors.append("%s names unknown species '%s'" % [label, s.species])
			continue
		var sizes: Array = s.sizes
		var sizes_ok := not sizes.is_empty()
		for n in sizes:
			sizes_ok = sizes_ok and (n == first or n == first + 1) and sizes.count(n) == 1
		if not sizes_ok:
			errors.append("%s: sizes %s must be some of [%d, %d]" % [label, sizes, first, first + 1])
		elif sizes.has(first + 1) and not TileCatalog.S1_SPECIES.has(s.species):
			errors.append("%s: '%s' is not an S1 species, so it cannot be live at size %d" % [label, s.species, first + 1])
		if sizes.has(first) and Vector2(s.x, s.y).length() < MIN_SITE_R_FIRST_SIZE:
			errors.append("%s home (%s, %s) lies inside r %s at size %d" % [label, s.x, s.y, MIN_SITE_R_FIRST_SIZE, first])
	var all_circles := circles()
	var zone_by_id := {}
	for z in zones:
		zone_by_id[z.id] = z
	var spawn_v := Vector2(spawn[0], spawn[1])
	for s in sites:
		if not s.sizes.has(size) or not species.species.has(s.species):
			continue
		var label := "%s: rule 5: site '%s'" % [w, s.id]
		var r := species.phenotype(s.species, part_catalog).radius
		var home := Vector2(s.x, s.y)
		var z: Dictionary = zone_by_id.get(s.territory_zone, {})
		if species.behavior_of(s.species) == "territorial" and z.is_empty():
			errors.append("%s territory_zone '%s' is not a zone of the block" % [label, s.territory_zone])
			continue
		var territory := species.territory_from({"species": s.species}, {} if z.is_empty() else {"center": Vector2(z.x, z.y), "radius": z.radius})
		var disc := species.reach_disc_for({"species": s.species, "home": home, "heading": s.heading}, territory)
		var c: Vector2 = disc.center
		var reach := float(disc.radius)
		var inset := reach + r + float(fair.leash_band_margin_m)
		if absf(c.x) + inset > HALF_BLOCK_BU or absf(c.y) + inset > HALF_BLOCK_BU:
			errors.append("%s reach disc at %s, r %.2f, comes within %.2f bu of the block's edge" % [label, c, reach, r + float(fair.leash_band_margin_m)])
		if home.distance_to(c) + r > reach:
			errors.append("%s home %s is not inside its reach disc at %s, r %.2f" % [label, home, c, reach])
		var pinches := PackedStringArray()
		species.check_disc_against_shells("site '%s'" % s.id, disc, r, all_circles, INF, pinches)
		for p in pinches:
			errors.append("%s: rule 5: %s" % [w, p])
		var clear := spawn_v.distance_to(c) - reach - r
		if clear < float(fair.respawn_clear_m):
			errors.append("%s: rule 6: site '%s' can reach %.2f bu from the spawn; it must stay %.1f away" % [w, s.id, clear, float(fair.respawn_clear_m)])
