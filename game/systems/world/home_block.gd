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
##
## S2 (docs/s2/s2-sim.md 3.10, D-37): the file names the M1 sites live at the band's second size
## (m1_second_size_sites; the rest are live at its first size only) and what the M1 zones do there
## (m1_zones_at_second_size), and a ring site may have a second post (post_b, D-38). validate() runs
## at any size of the band, with TileCatalog's per-size rules: the species live there, radii and
## fairness lengths in that size's bu, discs with k, the colliders there, the two-post checks and the
## post path (BP-11).

const DEFAULT_PATH := "res://game/data/home_b0.json"
const FILE_KEYS: PackedStringArray = ["schema_version", "status", "note", "band", "base_layout", "base_sites",
	"seam_inner_r", "m1_second_size_sites", "m1_zones_at_second_size", "shells", "zones", "sites"]
## What the M1 zones may do at the band's second size: they are the pool's own food, so never "drop".
const M1_ZONE_SECOND_SIZE: PackedStringArray = ["keep", "thin"]
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
## Every home zone, M1 and ring, keeps this far from every home collider, the M1 rocks and the ring
## shells (docs/s1/s1-build-plan.md B-2; the gap rule of PoolLayout.zone_problems, B-3).
const ZONE_SHELL_GAP_BU := PoolLayout.ZONE_CLEAR_MARGIN
## Rule 4: no new site inside this radius at the band's first size.
const MIN_SITE_R_FIRST_SIZE := 44.0

## Problems found while reading (unknown or missing keys, wrong types, ids, base files).
var load_problems := PackedStringArray()
## The file's name without .json, which every message starts with.
var where := "home_b0"
var band := 0
var seam_inner_r := 36.0
## The M1 site ids live at the band's second size too (D-37), as the file lists them.
var m1_second_size_sites := PackedStringArray()
## The M1 zones' at_second_size (D-37): "keep" or "thin".
var m1_zones_at_second_size := "keep"
## {id, x, y, r (bu), asset, yaw_deg, scale, fixed: bool, yaw_range: [lo, hi], at_second_size}; M1
## rocks first in data order (fixed, as pool_m1.json places them), then the seam ring (asset ""
## and scale 0.0: WorldGen picks them per seed).
var shells: Array[Dictionary] = []
## {id, x, y, radius, capacity, growth_rate, at_second_size, m1: bool}; M1 zones first.
var zones: Array[Dictionary] = []
## {id, species, x, y, heading, territory_zone, sizes: Array[int], m1: bool, post_b: {} or {home,
## heading, territory_zone}}; M1 sites first (sizes [first, first + 1] when m1_second_size_sites lists
## them, else [first]; no post_b).
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
	var listed := WorldConfig.list_at(w, data, "m1_second_size_sites", problems)
	for i in listed.size():
		home.m1_second_size_sites.append(WorldConfig.text_at(w + ".m1_second_size_sites", {str(i): listed[i]}, str(i), problems))
	if data.has("m1_zones_at_second_size"):
		home.m1_zones_at_second_size = WorldConfig.text_at(w, data, "m1_zones_at_second_size", problems)
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
	home._take_m1_second_size()
	# The ring, read as tile lists are (the same keys, local ids and messages).
	for s in TileCatalog.read_list(w, data, "shells", TileCatalog.SHELL_KEYS, PackedStringArray(), problems, TileCatalog.read_shell):
		home.shells.append({"id": s.id, "x": s.center[0], "y": s.center[1], "r": float(s.radius), "asset": "",
			"yaw_deg": s.yaw_deg[0], "scale": 0.0, "fixed": false, "yaw_range": s.yaw_deg, "at_second_size": s.at_second_size})
	for z in TileCatalog.read_list(w, data, "zones", TileCatalog.ZONE_KEYS, PackedStringArray(), problems, TileCatalog.read_zone):
		home.zones.append({"id": z.id, "x": z.center[0], "y": z.center[1], "radius": float(z.radius), "capacity": float(z.capacity),
			"growth_rate": float(z.growth_rate), "at_second_size": z.at_second_size, "m1": false})
	for s in TileCatalog.read_list(w, data, "sites", TileCatalog.SITE_KEYS, TileCatalog.SITE_OPTIONAL, problems, TileCatalog.read_site):
		home.sites.append({"id": s.id, "species": s.species, "x": s.home[0], "y": s.home[1], "heading": float(s.heading),
			"territory_zone": s.territory_zone, "sizes": s.sizes, "m1": false, "post_b": s.post_b})
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
			"territory_zone": str(s.get("territory_zone", "")), "sizes": sizes, "m1": true, "post_b": {}})


## D-37: the M1 zones take m1_zones_at_second_size, and an M1 site is live at the band's second size
## only when m1_second_size_sites lists it. Before S2 every M1 site was live at both and every M1 zone
## kept (C-3).
func _take_m1_second_size() -> void:
	var first := 2 * band + 1
	for z in zones:
		if z.m1:
			z.at_second_size = m1_zones_at_second_size
	for s in sites:
		if s.m1 and not m1_second_size_sites.has(s.id):
			var sizes: Array[int] = [first]
			s.sizes = sizes


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
## The rules of spine 4.3 (rule 3 as amended, see MIN_RING_ZONES) at `size`, a size of the block's
## band (WorldContent asks for each size of the build, D-70). Rules 1 to 4 are the same at every size;
## rules 5 and 6 are the size's (see _check_sites). At the band's first size every value is S1's.
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
	# D-37: the M1 sites listed live at the second size are M1 sites, each once; the M1 zones keep or thin.
	var m1_sites := {}
	for site in sites:
		if site.m1:
			m1_sites[site.id] = true
	for i in m1_second_size_sites.size():
		var id := m1_second_size_sites[i]
		if not m1_sites.has(id) or m1_second_size_sites.find(id) != i:
			errors.append("%s: rule 1: m1_second_size_sites names '%s', which is not an M1 site or is repeated" % [w, id])
	if not M1_ZONE_SECOND_SIZE.has(m1_zones_at_second_size):
		errors.append("%s: rule 3: m1_zones_at_second_size '%s' is not one of %s" % [w, m1_zones_at_second_size, ", ".join(M1_ZONE_SECOND_SIZE)])
	_check_ring_shells(ring_shells, kit, errors)
	_check_ring_zones(ring_zones, errors)
	_check_zone_gaps(errors)
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
## clear of the edges, 1 bu from each other, and static #33. The gap to the colliders is checked for
## every home zone in _check_zone_gaps.
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
			errors.append("%s: rule 3: zone '%s' yields %.3f a second; static #33 allows <= %.3f, %s" % [w, z.id, yield_rate, TileCatalog.MAX_ZONE_YIELD, TileCatalog.STATIC_33_LABEL])
		for j in range(i + 1, ring.size()):
			var o: Dictionary = ring[j]
			var gap := c.distance_to(Vector2(o.x, o.y)) - r - float(o.radius)
			if gap < ZONE_GAP_BU:
				errors.append("%s: rule 3: zones '%s' and '%s' are %.2f bu apart; they keep %.1f" % [w, z.id, o.id, gap, ZONE_GAP_BU])


## Rule 3's gap (B-2): every home zone, M1 and ring, keeps ZONE_SHELL_GAP_BU from every home collider,
## M1 rocks included. A zone whose values the ring check refused is left to that message.
func _check_zone_gaps(errors: PackedStringArray) -> void:
	var valid: Array[Dictionary] = []
	for z in zone_list():
		if z.radius > 0.0 and z.capacity > 0.0 and z.growth_rate > 0.0:
			valid.append(z)
	for p in PoolLayout.zone_problems(valid, circles(), INF):
		errors.append("%s: rule 3: %s" % [where, p])


## Rules 4 to 6. Rule 4, the ring's sites at every size: a known species, sizes of the band, each one
## the species is live at (SpeciesCatalog.live_at), no new site inside r 44 at the first size, and a
## second post's own rules (TileCatalog._check_post_b: a habit, its zone, the spacing and travel of
## D-61). Rules 5 and 6 for every site live at `size`, M1 and ring, as TileCatalog's rule 6: a body
## radius at_size(id, size).phenotype.radius / bu_to_tm(size) bu (TileCatalog.radii_at), a reach disc
## with k (D-39) inside the block that holds the home, rules 9 and 10 in tm against the home colliders
## there (circles_at) with no wall, and, for a species that can attack the cell at the size
## (Relationships.can_attack_player), rule 6 against the spawn. A two-post site also has its second
## post's home clear and its zone there, each check on each post's disc and on their union (D-82), the
## union within TileCatalog.MAX_UNION_REACH_TM, and a path between its posts (BP-11). A fairness
## length is its tm / bu_to_tm(size) in bu. A rule broken at the second size says so ("rule 5 at size 2").
func _check_sites(ring: Array, species: SpeciesCatalog, part_catalog: PartCatalog, size: int, errors: PackedStringArray) -> void:
	var w := where
	var first := 2 * band + 1
	var as_tile := {"band": band, "where": w}
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
		else:
			for n in sizes:
				var c := species.entry_size(s.species)
				if n < c:
					errors.append("%s: '%s' enters at size %d, so it cannot be live at size %d" % [label, s.species, c, n])
				elif not species.live_at(s.species, n, part_catalog):
					errors.append("%s: '%s' is haze at size %d, so it cannot be live there" % [label, s.species, n])
		if sizes.has(first) and Vector2(s.x, s.y).length() < MIN_SITE_R_FIRST_SIZE:
			errors.append("%s home (%s, %s) lies inside r %s at size %d" % [label, s.x, s.y, MIN_SITE_R_FIRST_SIZE, first])
		if not s.post_b.is_empty():
			TileCatalog._check_post_b(label, as_tile, _tile_site(s), species, part_catalog, errors)
	var radii := TileCatalog.radii_at(species, part_catalog, size)
	var st := WorldConfig.bu_to_tm(size)
	var there := circles_at(size)
	var scaled: Array[Dictionary] = there if st == 1.0 else TileCatalog._scaled(there, st)
	var zone_by_id := {}
	for z in zones:
		zone_by_id[z.id] = z
	for s in sites:
		if not s.sizes.has(size) or not radii.has(s.species):
			continue
		var label := "%s: %s: site '%s'" % [w, _rule_at(5, size), s.id]
		var r := float(radii[s.species])
		var home := Vector2(s.x, s.y)
		var territorial := species.behavior_of(s.species) == "territorial"
		var z: Dictionary = zone_by_id.get(s.territory_zone, {})
		if territorial and not _zone_there(label, "territory_zone", s.territory_zone, z, size, errors):
			continue
		var territory := species.territory_from({"species": s.species}, _circle(z))
		var k := WorldConfig.k_of(species.entry_size(s.species), size)
		var at_a := {"species": s.species, "home": home, "heading": s.heading}
		var discs: Array[Dictionary] = []
		var post: Dictionary = s.post_b
		if post.is_empty():
			discs.append({"label": "", "disc": species.reach_disc_for(at_a, territory, k), "homes": [home]})
		else:
			var home_b := Vector2(post.home[0], post.home[1])
			for c in there:
				if home_b.distance_to(c.center) < float(c.radius) + r:
					errors.append("%s post_b home %s is not clear of '%s'" % [label, home_b, c.id])
			var z_b: Dictionary = zone_by_id.get(str(post.territory_zone), {})
			if territorial and (str(post.territory_zone).is_empty()
					or not _zone_there(label, "post_b.territory_zone", post.territory_zone, z_b, size, errors)):
				continue
			var both := species.two_post_disc_for(at_a, territory, {"home": home_b, "heading": float(post.heading)},
				species.territory_from({"species": s.species}, _circle(z_b)), k)
			discs.append({"label": " post a", "disc": both.posts[0], "homes": [home]})
			discs.append({"label": " post b", "disc": both.posts[1], "homes": [home_b]})
			discs.append({"label": " union", "disc": both, "homes": [home, home_b]})
			if float(both.radius) * st > TileCatalog.MAX_UNION_REACH_TM:
				errors.append("%s union reach disc r %.2f bu is %.2f tm; D-61 keeps it <= %.1f tm"
					% [label, float(both.radius), float(both.radius) * st, TileCatalog.MAX_UNION_REACH_TM])
			var half := r + float(CreatureBrain.WORLD_LENGTHS.route_clearance) * species.q_of(s.species, size) / st
			for p in TileCatalog.post_path_problems(home, home_b, half, there):
				errors.append("%s: %s" % [label, p])
		var attacks := Relationships.can_attack_player(species.q_of(s.species, size))
		for d in discs:
			_check_disc("site '%s'%s" % [s.id, d.label], label + d.label, d.disc, d.homes, r, st, attacks, size, species, scaled, errors)


## One reach disc of a live site (`name` names it in rules 9 and 10 and 6, `label` elsewhere): inside
## the block, inset by r and leash_band_margin_m, holding each of `homes`, rules 9 and 10 in tm against
## the colliders there (`scaled`, x st) with no wall, and, when the species `attacks` the cell at the
## size, rule 6: respawn_clear_m from the spawn. At st 1 every value is S1's.
func _check_disc(name: String, label: String, disc: Dictionary, homes: Array, r: float, st: float, attacks: bool, size: int,
		species: SpeciesCatalog, scaled: Array[Dictionary], errors: PackedStringArray) -> void:
	var fair := species.fairness
	var c: Vector2 = disc.center
	var reach := float(disc.radius)
	var margin := float(fair.leash_band_margin_m) / st
	var inset := reach + r + margin
	if absf(c.x) + inset > HALF_BLOCK_BU or absf(c.y) + inset > HALF_BLOCK_BU:
		errors.append("%s reach disc at %s, r %.2f, comes within %.2f bu of the block's edge" % [label, c, reach, r + margin])
	for home: Vector2 in homes:
		if home.distance_to(c) + r > reach:
			errors.append("%s home %s is not inside its reach disc at %s, r %.2f" % [label, home, c, reach])
	var pinches := PackedStringArray()
	var in_tm: Dictionary = disc if st == 1.0 else {"center": c * st, "radius": reach * st}
	species.check_disc_against_shells(name, in_tm, r * st, scaled, INF, pinches)
	for p in pinches:
		errors.append("%s: %s: %s" % [where, _rule_at(5, size), p])
	if not attacks:
		return
	var clear := Vector2(spawn[0], spawn[1]).distance_to(c) - reach - r
	var need := float(fair.respawn_clear_m) / st
	if clear < need:
		errors.append("%s: %s: %s can reach %.2f bu from the spawn; it must stay %.1f away" % [where, _rule_at(6, size), name, clear, need])


## The block's circles that exist at size n (circles()): at the band's second size the ring shells
## marked "sink" are gone; the M1 rocks always keep.
func circles_at(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var second := n == 2 * band + 2
	for s in shells:
		if not (second and s.at_second_size == "sink"):
			out.append({"id": s.id, "center": Vector2(s.x, s.y), "radius": float(s.r)})
	return out


## The rule's name in a message: "rule 5" at the band's first size, "rule 5 at size 2" at its second.
func _rule_at(rule: int, size: int) -> String:
	return "rule %d" % rule if size == 2 * band + 1 else "rule %d at size %d" % [rule, size]


## Whether a territorial site's zone `id` (named by `key`) is a zone of the block there at `size` (the
## band's second size drops the "drop" ones); records the problem when it is not.
func _zone_there(label: String, key: String, id: String, zone: Dictionary, size: int, errors: PackedStringArray) -> bool:
	if zone.is_empty():
		errors.append("%s %s '%s' is not a zone of the block" % [label, key, id])
		return false
	if size == 2 * band + 2 and zone.at_second_size == "drop":
		errors.append("%s %s '%s' is dropped at size %d" % [label, key, id, size])
		return false
	return true


## A zone's {center, radius} for SpeciesCatalog.territory_from, or {} for none.
static func _circle(zone: Dictionary) -> Dictionary:
	return {} if zone.is_empty() else {"center": Vector2(zone.x, zone.y), "radius": float(zone.radius)}


## A ring site as a tile's site (home as a float64 pair), for TileCatalog's two-post checks.
static func _tile_site(s: Dictionary) -> Dictionary:
	return {"id": s.id, "species": s.species, "home": PackedFloat64Array([s.x, s.y]), "heading": s.heading,
		"territory_zone": s.territory_zone, "sizes": s.sizes, "post_b": s.post_b}
