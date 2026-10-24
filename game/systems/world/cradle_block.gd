class_name CradleBlock
extends RefCounted
## The cradle (S3, D-94; docs/s3: spine 5.4 and 6.4, s3-sim 4.4, build plan 7.2): the four home tiles
## at band 1 and up, 128 x 128 bu round the absolute origin. Each quadrant is ordinary band content
## round a calm centre, where the old pool lies shrunk and drawn only (D-95): inside clear_r_bu there
## is no shell and no reach disc, only food.
##
## Shells, zones and sites have TileCatalog's shapes and keys, in bu from the absolute origin (x east,
## y south). A quadrant is the home tile quadrant_of(x, y) of an item's centre (a home for a site).
## validate() runs the tile rules at a size of the band: the geometry ones (rules 2, 3, 6, 11 and 12)
## once over the whole block, so a quadrant line is no edge and a shell across it still meets its
## neighbours, rule 2's and 3's edge tests at the block's outer edge only; the counting ones (rules 7,
## 9 and 10 and D-135) per quadrant, as one tile each; rule 8 over the block. Then the clear disc,
## the ring inside it and a clear view point.

const FILE_KEYS: PackedStringArray = ["schema_version", "status", "note", "band", "pool_ring", "clear_r_bu",
	"view_point_bu", "shells", "zones", "sites"]
const POOL_RING_KEYS := {"radius_bu": "number", "glitter_radius_bu": "number", "caption": "text", "dressing": "text"}
const HALF_BU := 64.0                                     ## the block spans [-64, 64)^2 bu
const REGION := "home"                                    ## a quadrant's region, as WorldGen names it
## The four quadrants, sorted (-1, -1), (0, -1), (-1, 0), (0, 0): WorldGen's row-major tile order.
const QUADRANTS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]

var load_problems := PackedStringArray()
var where := "cradle_b1"
var band := 1
var pool_ring := {}
var clear_r_bu := 16.0
var view_point_bu := Vector2(0.0, 18.0)
var shells: Array[Dictionary] = []                        ## TileCatalog shell shape, bu from the origin
var zones: Array[Dictionary] = []
var sites: Array[Dictionary] = []


static func load_from(path: String) -> CradleBlock:
	var data: Variant = WorldConfig.read_json(path)
	if data == null:
		var broken := CradleBlock.new()
		broken.where = path.get_file().get_basename()
		broken.load_problems.append("%s: missing or not readable JSON" % path.get_file())
		return broken
	return from_dict(data, path.get_file().get_basename())


static func from_dict(data: Variant, file_id: String = "cradle_b1") -> CradleBlock:
	var cradle := CradleBlock.new()
	cradle.where = file_id
	var w := file_id
	var problems := cradle.load_problems
	problems.append_array(WorldConfig.schema_problems(w, data, FILE_KEYS))
	if not data is Dictionary:
		return cradle
	WorldConfig.header_check(w, data, problems)
	cradle.band = int(WorldConfig.number_at(w, data, "band", problems, true))
	if data.has("band") and cradle.band < 1:
		problems.append("%s.band: a cradle is band 1 or more; band 0's home is home_b0 (D-94)" % w)
	var ring := WorldConfig.object_at(w, data, "pool_ring", PackedStringArray(POOL_RING_KEYS.keys()), problems)
	for key in POOL_RING_KEYS:
		if not ring.has(key):
			continue
		if POOL_RING_KEYS[key] == "number":
			cradle.pool_ring[key] = WorldConfig.number_at(w + ".pool_ring", ring, key, problems)
		else:
			cradle.pool_ring[key] = WorldConfig.text_at(w + ".pool_ring", ring, key, problems)
	cradle.clear_r_bu = WorldConfig.number_at(w, data, "clear_r_bu", problems)
	var view := TileCatalog._pair(w, data, "view_point_bu", problems)
	cradle.view_point_bu = Vector2(view[0], view[1])
	cradle.shells = TileCatalog.read_list(w, data, "shells", TileCatalog.SHELL_KEYS, PackedStringArray(), problems, TileCatalog.read_shell)
	cradle.zones = TileCatalog.read_list(w, data, "zones", TileCatalog.ZONE_KEYS, PackedStringArray(), problems, TileCatalog.read_zone)
	cradle.sites = TileCatalog.read_list(w, data, "sites", TileCatalog.SITE_KEYS, TileCatalog.SITE_OPTIONAL, problems, TileCatalog.read_site)
	# Shells and zones share the block's ids, as a tile's do (a tile reads each list on its own).
	var seen := {}
	for list in [cradle.shells, cradle.zones]:
		for item in list:
			if seen.has(item.id):
				problems.append("%s: '%s' is both a shell and a zone id" % [w, item.id])
			seen[item.id] = true
	return cradle


## The home tile of a point (bu from the origin): x < 0 gives -1, else 0; y likewise.
static func quadrant_of(x_bu: float, y_bu: float) -> Vector2i:
	return Vector2i(-1 if x_bu < 0.0 else 0, -1 if y_bu < 0.0 else 0)


## Each quadrant as a TileCatalog tile dict in its own tile's frame (bu from the tile centre, which is
## (2 q + 1) x 32 bu from the origin), in QUADRANTS order, with "quadrant" (Vector2i) and a "where"
## that names it ("cradle_b1/q-1_0"). Shells and zones go by their centres, sites by their homes; a
## second post moves with its site. Region "home", set -1, no anchor and no set piece.
func as_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in QUADRANTS:
		var off := Vector2(2 * q.x + 1, 2 * q.y + 1) * TileCatalog.HALF_TILE_BU
		var t := {"id": "q%d_%d" % [q.x, q.y], "where": "%s/q%d_%d" % [where, q.x, q.y], "band": band, "region": REGION,
			"set": -1, "rare": "", "landmark_anchor": PackedFloat64Array(), "set_piece": {}, "quadrant": q,
			"shells": _in(shells, q, "center", off), "zones": _in(zones, q, "center", off), "sites": _in(sites, q, "home", off)}
		for s in t.sites:
			if not s.post_b.is_empty():
				s.post_b.home = PackedFloat64Array([s.post_b.home[0] - off.x, s.post_b.home[1] - off.y])
		out.append(t)
	return out


## Problems with the block at `size` (a size of its band); empty when the world can place it. Reading
## problems come back alone.
func validate(species: SpeciesCatalog, kit: PlacementKit, part_catalog: PartCatalog, size: int) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var first := 2 * band + 1
	if size != first and size != first + 1:
		errors.append("%s: size %d is not a size of band %d" % [where, size, band])
		return errors
	var block := _block()
	var radii := TileCatalog.radii_at(species, part_catalog, size)
	var colliders := TileCatalog.colliders_of(block, kit)
	var there := TileCatalog.colliders_at(block, colliders, size)
	TileCatalog._check_shells(block, kit, colliders, errors)
	TileCatalog._check_zones(block, colliders, errors)
	TileCatalog._check_sites(block, species, radii, kit, there, part_catalog, size, errors)
	var behaviors := {}
	var smallest := {}
	for t in as_tiles():
		TileCatalog._check_content(t, species, size, behaviors, smallest, errors)
	TileCatalog.check_strike_room(where, species, radii, smallest, part_catalog, size, errors)
	_check_centre(species, radii, there, size, errors)
	return errors


## The clear disc (D-95): no shell within clear_r_bu of the origin plus its radius, no live site's
## reach disc (each post's and the union for two posts) within clear_r_bu, its body included; the
## ring inside the disc; the view point inside the block and clear of the colliders there for the cell.
func _check_centre(species: SpeciesCatalog, radii: Dictionary, there: Array[Dictionary], size: int,
		errors: PackedStringArray) -> void:
	var s := WorldConfig.bu_to_tm(size)
	for shell in shells:
		var d := TileCatalog._vec(shell.center).length()
		if d < clear_r_bu + float(shell.radius):
			errors.append("%s: the clear disc: shell '%s' lies %.2f bu from the centre; it needs %.2f"
				% [where, shell.id, d, clear_r_bu + float(shell.radius)])
	for site in sites:
		if not radii.has(site.species) or TileCatalog.site_role(species, site, size) in ["", "morsel"]:
			continue
		for d in _discs(species, site, size):
			var gap := float(d.disc.center.length()) - float(d.disc.radius) - float(radii[site.species])
			if gap < clear_r_bu:
				errors.append("%s: the clear disc at size %d: site '%s'%s reach disc comes %.2f bu from the centre; it keeps %.1f away"
					% [where, size, site.id, d.label, gap, clear_r_bu])
	var ring := float(pool_ring.get("radius_bu", 0.0))
	if not (ring > 0.0 and ring < clear_r_bu and float(pool_ring.get("glitter_radius_bu", 0.0)) > 0.0):
		errors.append("%s: pool_ring: radius_bu %s must lie in (0, clear_r_bu %s), and glitter_radius_bu %s above 0"
			% [where, ring, clear_r_bu, pool_ring.get("glitter_radius_bu", 0.0)])
	var arena := ChunkArena.from_shells(TileCatalog._arena_circles(there))
	var cell := PoolLayout.CELL_RADIUS / s
	var v := view_point_bu
	if absf(v.x) + cell > HALF_BU or absf(v.y) + cell > HALF_BU or not arena.is_clear(v, cell):
		errors.append("%s: view_point_bu %s is not clear for the cell at size %d" % [where, v, size])


## A live site's reach discs at `size` in bu, as TileCatalog._check_sites makes them: [{label, disc}]
## (one, or each post's and their union). A territorial site whose zone is not there has none here
## (rule 6 reports it).
func _discs(species: SpeciesCatalog, site: Dictionary, size: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var block := _block()
	var territorial := species.behavior_of(site.species) == "territorial"
	var zone := TileCatalog._zone(block, site.territory_zone)
	if territorial and (zone.is_empty() or (size == 2 * band + 2 and zone.at_second_size == "drop")):
		return out
	var k := WorldConfig.k_of(species.entry_size(site.species), size)
	var at_a := {"species": site.species, "home": TileCatalog._vec(site.home), "heading": float(site.heading)}
	var territory := species.territory_from({"species": site.species}, TileCatalog._circle_of(zone))
	if site.post_b.is_empty():
		out.append({"label": "", "disc": species.reach_disc_for(at_a, territory, k)})
		return out
	var zone_b := TileCatalog._zone(block, str(site.post_b.territory_zone))
	if territorial and (zone_b.is_empty() or (size == 2 * band + 2 and zone_b.at_second_size == "drop")):
		return out
	var both := species.two_post_disc_for(at_a, territory, {"home": TileCatalog._vec(site.post_b.home),
		"heading": float(site.post_b.heading)}, species.territory_from({"species": site.species}, TileCatalog._circle_of(zone_b)), k)
	out.append({"label": " post a", "disc": both.posts[0]})
	out.append({"label": " post b", "disc": both.posts[1]})
	out.append({"label": " union", "disc": both})
	return out


## The whole block as one tile dict for the geometry rules (bu from the origin, edge tests at its
## outer edge).
func _block() -> Dictionary:
	return {"id": where, "where": where, "band": band, "region": REGION, "set": -1, "rare": "",
		"landmark_anchor": PackedFloat64Array(), "set_piece": {}, "shells": shells, "zones": zones, "sites": sites,
		"half_bu": HALF_BU, "frame": "block"}


## Deep copies of the items of `list` in quadrant q (by their `key` point), moved by -off.
static func _in(list: Array[Dictionary], q: Vector2i, key: String, off: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in list:
		var p: PackedFloat64Array = item[key]
		if quadrant_of(p[0], p[1]) != q:
			continue
		var copy := item.duplicate(true)
		copy[key] = PackedFloat64Array([p[0] - off.x, p[1] - off.y])
		out.append(copy)
	return out
