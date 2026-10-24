extends RefCounted
## Test helper (not a test file): the endless world's heavy checks (docs/s1/s1-interfaces.md 4.2,
## docs/s1/s1-core.md 6.7, docs/s1/s1-build-plan.md B-16 and B-17). The validators keep to cheap
## per-file rules; these walk grids, every orientation and every seam, and T4 runs them on the real
## content: reach_problems (G5), orientation_problems, food_bound, sample_sites and seam_problems (G4).
## Each takes the size it checks (S2G7): at a band's second size the shells marked "sink" are gone,
## the "drop" zones too, a "thin" zone holds capacity x second_size.zone_thin_share, discs take k and
## a two-post site's posts and union, and the seams, the food ring and the tile frames are measured in
## that size's tm (bu x bu_to_tm(size)); at size 1 every value is S1's.
##
##     const WorldChecks := preload("res://tests/world_checks.gd")
##     WorldChecks.reach_problems(arena, zones, bounds, WorldChecks.starving_budget(catalog), homes)
##     WorldChecks.orientation_problems(content, species, parts, 1)
##     WorldChecks.food_bound(content, 4.0).worst <= content.config.caps.food_items
##     WorldChecks.food_bound(content, 4.0, 2)     # at size 2
##     WorldChecks.sample_sites(gen, 0, 1, PackedFloat64Array([x_tm, y_tm])) <= 10
##     WorldChecks.seam_problems(content, species, parts, 1)

const ReachGrid := preload("res://tests/reach_grid.gd")
## S2 spine 4.2's relationships block, every rule on.
const S2_RELATIONSHIPS := {"rules": {"prey_share": true, "intruder_share": true, "fear": true, "no_engage_above": true,
	"outgrown_hazards": true}, "prey_share": 1.0, "intruder_max_radius_share": 1.2, "fear_radius_share": 1.25,
	"tolerance": 1e-6}
## A starving cell should reach food using at most this share of the distance it can swim before it
## dies (tests/test_pool_layout.gd, the pool's own starvation rule).
const STARVATION_PATH_SHARE := 0.6


## The starving budget in tm: the shortest distance any starting body swims at starving speed before
## starvation kills it, times STARVATION_PATH_SHARE (16.3 today), computed as the pool's test does.
static func starving_budget(catalog: PartCatalog) -> float:
	var budget := INF
	for body in catalog.starting_bodies:
		var r := Lineage.found(1, "test+dev", catalog, body)
		var p := Phenotype.derive(r.save.genome, catalog)
		var starving_s := p.max_health / ActorState.STARVATION_DAMAGE
		budget = minf(budget, p.speed * ActorState.STARVING_SPEED * starving_s * STARVATION_PATH_SHARE)
	return budget


## Every open point of `bounds` (a cell fits there, on a 0.5 tm grid over `arena`) that the sea
## outside can reach, through the bounds' border, walks to the edge of one of `zones` within
## budget_tm, and those points form one connected sea. A sealed pocket (open points the border cannot
## reach, such as the shell cathedral's nave) is legal while it is empty (B-29); it is a problem when
## it holds a zone point, or one of `must_reach` (site homes, the spawn). One problem per failure,
## each naming where: points walled off from food (their centre), the worst point over the budget,
## food in a pocket, a must-reach point in one, points cut off from the rest.
static func reach_problems(arena: PoolArena, zones: Array[Dictionary], bounds: Rect2, budget_tm: float,
		must_reach: Array[Vector2] = []) -> PackedStringArray:
	var grid = ReachGrid.over(arena, zones, bounds, PoolLayout.CELL_RADIUS)
	var food: PackedInt32Array = grid.zone_points()
	var to_food: PackedFloat32Array = grid.distances_from(food)
	var labels: PackedInt32Array = grid.components()
	var outside := {}
	for i in grid.border_points():
		outside[labels[i]] = true
	var problems := PackedStringArray()
	var walled := 0
	var walled_sum := Vector2.ZERO
	var worst := -1.0
	var worst_at := Vector2.ZERO
	var start := -1
	var cut := 0
	var cut_at := Vector2.ZERO
	for i in grid.open.size():
		if grid.open[i] == 0 or not outside.has(labels[i]):
			continue
		if not is_finite(to_food[i]):
			walled += 1
			walled_sum += grid.point(i)
			continue
		if start < 0:
			start = i
		elif labels[i] != labels[start]:
			if cut == 0:
				cut_at = grid.point(i)
			cut += 1
		if to_food[i] > worst:
			worst = to_food[i]
			worst_at = grid.point(i)
	if walled > 0:
		problems.append("reach: %d open points around %s cannot reach food" % [walled, walled_sum / walled])
	if worst > budget_tm:
		problems.append("reach: %s is %.1f tm from food; the budget is %.1f tm" % [worst_at, worst, budget_tm])
	var sealed := 0
	var sealed_sum := Vector2.ZERO
	for i in food:
		if not outside.has(labels[i]):
			sealed += 1
			sealed_sum += grid.point(i)
	if sealed > 0:
		problems.append("reach: %d zone points around %s lie in a sealed pocket" % [sealed, sealed_sum / sealed])
	for p in must_reach:
		var i: int = grid.index_near(p)
		if grid.open[i] == 0 or not outside.has(labels[i]):
			problems.append("reach: %s must be reached but lies in a sealed pocket or under a collider" % p)
	if cut > 0:
		problems.append("reach: %d open points from %s are cut off from %s" % [cut, cut_at, grid.point(start)])
	return problems


## The worst walking distance to food over `bounds` (for printing measured margins), and where.
static func worst_reach(arena: PoolArena, zones: Array[Dictionary], bounds: Rect2) -> Dictionary:
	var grid = ReachGrid.over(arena, zones, bounds, PoolLayout.CELL_RADIUS)
	var to_food: PackedFloat32Array = grid.distances_from(grid.zone_points())
	var worst := -1.0
	var at := Vector2.ZERO
	for i in grid.open.size():
		if grid.open[i] == 1 and to_food[i] > worst:
			worst = to_food[i]
			at = grid.point(i)
	return {"worst": worst, "at": at}


# --- the size-2 species (S2) ---

## The shipped species data with S2's two size-2 species and the relationships block (spine 4.2),
## for the world checks at size 2: the Lurker (the ambush hunter's body and attack, entry size 2,
## habit "out_of_sight") and the elder rammer (the rammer's, entry size 2, nav_timeout_s 16 by D-61,
## habit "nearer_cell"). Each one the shipped data already holds is kept as it is, so once S2 T1.7
## ships them this is the shipped data unchanged.
static func s2_species_data() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	if not data.has("relationships"):
		data["relationships"] = S2_RELATIONSHIPS.duplicate(true)
	if not data.species.has("lurker"):
		var lurker: Dictionary = data.species.ambush_hunter.duplicate(true)
		lurker.name = "Lurker"
		lurker.entry_size = 2
		lurker.niche = {"role": "lurker", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		lurker.habit = {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}
		data.species["lurker"] = lurker
	if not data.species.has("elder_rammer"):
		var elder: Dictionary = data.species.rammer.duplicate(true)
		elder.name = "elder rammer"
		elder.entry_size = 2
		elder.nav_timeout_s = 16.0
		elder.niche = {"role": "elder_rammer", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		elder.habit = {"post_switch": "nearer_cell", "post_hysteresis_m": 2.0}
		data.species["elder_rammer"] = elder
	return data


static func s2_species() -> SpeciesCatalog:
	return SpeciesCatalog.from_dict(s2_species_data())


# --- a size's world (S2) ---

## Whether `size` is the second size of `band` (where sink, drop and thin apply).
static func is_second_size(band: int, size: int) -> bool:
	return size == 2 * band + 2


## The zones of `zones` there at `size` (each {center or x and y, radius, capacity, at_second_size}):
## at the band's second size the "drop" ones are gone and a "thin" one holds capacity x
## second_size.zone_thin_share (copies; the rest unchanged).
static func zones_at(zones: Array, band: int, size: int, content: WorldContent) -> Array:
	if not is_second_size(band, size):
		return zones
	var share := float(content.config.second_size.zone_thin_share)
	var out := []
	for z in zones:
		if z.at_second_size == "drop":
			continue
		var kept: Dictionary = z.duplicate()
		if z.at_second_size == "thin":
			kept.capacity = float(z.capacity) * share
		out.append(kept)
	return out


## A live site's reach discs at `size` in its own frame's bu, as the validators build them (D-39,
## D-82): {label, disc: {center, radius}, homes: Array[Vector2]} for its one disc (label ""), or for
## a two-post site post a's (" post a"), post b's (" post b") and their union (" union"). `zone` and
## `zone_b` are the posts' territory circles ({center, radius}, or {} for none). Empty when a
## territorial post has no zone there or the species no brain (the validators report those).
static func site_discs(species: SpeciesCatalog, site: Dictionary, home: Vector2, zone: Dictionary, post_b: Dictionary,
		zone_b: Dictionary, size: int) -> Array:
	var territorial := species.behavior_of(site.species) == "territorial"
	if territorial and zone.is_empty():
		return []
	var k := WorldConfig.k_of(species.entry_size(site.species), size)
	var at_a := {"species": site.species, "home": home, "heading": float(site.heading)}
	var territory := species.territory_from(at_a, zone)
	if post_b.is_empty():
		var disc := species.reach_disc_for(at_a, territory, k)
		return [] if disc.is_empty() else [{"label": "", "disc": disc, "homes": [home]}]
	if territorial and zone_b.is_empty():
		return []
	var home_b := Vector2(post_b.home[0], post_b.home[1])
	var both := species.two_post_disc_for(at_a, territory, {"home": home_b, "heading": float(post_b.heading)},
		species.territory_from(at_a, zone_b), k)
	if both.is_empty():
		return []
	return [{"label": " post a", "disc": both.posts[0], "homes": [home]}, {"label": " post b", "disc": both.posts[1], "homes": [home_b]},
		{"label": " union", "disc": {"center": both.center, "radius": both.radius}, "homes": [home, home_b]}]


## Circles ({id, center, radius}) times s.
static func scaled(circles: Array[Dictionary], s: float) -> Array[Dictionary]:
	if s == 1.0:
		return circles
	var out: Array[Dictionary] = []
	for c in circles:
		out.append({"id": c.id, "center": Vector2(c.center) * s, "radius": float(c.radius) * s})
	return out


# --- every orientation (B-16) ---

## Every orientation, 0 to 7: m = o >> 2 mirrors x first, k = o & 3 quarter turns (WorldGen).
const ALL_ORIENTATIONS := [0, 1, 2, 3, 4, 5, 6, 7]


## A copy of TileCatalog tile `t` laid in orientation o, as WorldGen places it: every point through
## WorldGen.orient_point, headings through orient_heading, the set piece's yaw through
## orient_yaw_deg (kept in [0, 360)) and marked "mirror" when o mirrors, so colliders_of turns its
## colliders where WorldGen puts them. Its `where` gains "@o<o>", so a problem names the orientation.
static func oriented_tile(t: Dictionary, o: int) -> Dictionary:
	var out := t.duplicate(true)
	out.where = "%s@o%d" % [t.where, o]
	for list in [out.shells, out.zones]:
		for item in list:
			item.center = WorldGen.orient_point(item.center[0], item.center[1], o)
	for s in out.sites:
		s.home = WorldGen.orient_point(s.home[0], s.home[1], o)
		s.heading = WorldGen.orient_heading(float(s.heading), o)
		if not s.get("post_b", {}).is_empty():
			s.post_b.home = WorldGen.orient_point(s.post_b.home[0], s.post_b.home[1], o)
			s.post_b.heading = WorldGen.orient_heading(float(s.post_b.heading), o)
	if t.landmark_anchor.size() == 2:
		out.landmark_anchor = WorldGen.orient_point(t.landmark_anchor[0], t.landmark_anchor[1], o)
	if not t.set_piece.is_empty():
		out.set_piece.center = WorldGen.orient_point(t.set_piece.center[0], t.set_piece.center[1], o)
		out.set_piece.yaw_deg = fposmod(WorldGen.orient_yaw_deg(float(t.set_piece.yaw_deg), o), 360.0)
		out.set_piece["mirror"] = (o >> 2) & 1 == 1
	return out


## Tile rules 2 to 8 (TileCatalog.validate) with every tile laid in each of `orientations`; empty
## when all hold. Each tile problem names its tile and orientation ("b0/reef_c@o5: rule 6: ..."); a
## band-wide problem the orientations share is given once.
static func orientation_problems(content: WorldContent, species: SpeciesCatalog, parts: PartCatalog, size: int,
		orientations := PackedInt32Array(ALL_ORIENTATIONS)) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for o in orientations:
		var cat := TileCatalog.new()
		cat.bands = content.tiles.bands.duplicate()
		for id in WorldConfig._sorted(content.tiles.tiles.keys()):
			cat.tiles[id] = oriented_tile(content.tiles.tiles[id], o)
		for p in cat.validate(species, content.kit, parts, size):
			if not seen.has(p):
				seen[p] = true
				out.append(p)
	return out


# --- the food bound (plan A.2) ---

## The most food items any arrangement can put within the food ring of a point: for each point p on
## a `step_tm` grid over one tile (cell centres, tile-local, scanned y then x), the 3 x 3 tile slots
## round p's tile each hold the tile and orientation whose zones put the most items within the ring
## of p (a zone counts min(floor(capacity / unit_energy), food_per_zone) items when its disc comes
## within the ring); the slots sum. Where p's tile lies round or in the home block (tiles -2 to 1 on
## each axis), the block's own zones, counted exactly, replace the slots it covers.
## {worst: int, at: Vector2 (tile-local bu), home: bool, tile: Vector2i (p's tile when home is
## true)}; the gate is worst <= caps.food_items. The first point to reach the worst wins a tie, the
## arrangements away from the home first. At `size` (0: size_start) the zones are those there
## (zones_at: drop gone, thin thinned) and the ring and step are that size's tm in bu (/ bu_to_tm).
static func food_bound(content: WorldContent, step_tm: float, size := 0) -> Dictionary:
	if size <= 0:
		size = content.config.size_start
	var scale := WorldConfig.bu_to_tm(size)
	var ring := float(content.config.rings.food) / scale
	var step := step_tm / scale
	var frames: Array = []
	for id in WorldConfig._sorted(content.tiles.tiles.keys()):
		var t: Dictionary = content.tiles.tiles[id]
		for o in ALL_ORIENTATIONS:
			frames.append(_food_zones(zones_at(oriented_tile(t, o).zones, int(t.band), size, content), content))
	var home_zones := _food_zones(zones_at(content.home.zones.map(func(z: Dictionary) -> Dictionary:
		return {"center": PackedFloat64Array([z.x, z.y]), "radius": z.radius, "capacity": z.capacity,
			"at_second_size": z.at_second_size}), content.home.band, size, content), content)
	var n := roundi(TileCatalog.HALF_TILE_BU * 2.0 / step)
	var best := {"worst": -1, "at": Vector2.ZERO, "tile": Vector2i.ZERO, "home": false}
	var slot_max := {}
	for j in n:
		for i in n:
			var p := Vector2(-TileCatalog.HALF_TILE_BU + (i + 0.5) * step, -TileCatalog.HALF_TILE_BU + (j + 0.5) * step)
			var total := 0
			for sy in range(-1, 2):
				for sx in range(-1, 2):
					var m := 0
					var at := p - Vector2(sx, sy) * TileCatalog.HALF_TILE_BU * 2.0
					for zones in frames:
						m = maxi(m, _items_near(zones, at, ring))
					slot_max[Vector4i(i, j, sx, sy)] = m
					total += m
			if total > int(best.worst):
				best = {"worst": total, "at": p, "tile": Vector2i.ZERO, "home": false}
	var lo := int(content.config.arrangement.home_tiles[0])
	var hi := int(content.config.arrangement.home_tiles[1])
	for ty in range(lo - 1, hi + 2):
		for tx in range(lo - 1, hi + 2):
			for j in n:
				for i in n:
					var p := Vector2(-TileCatalog.HALF_TILE_BU + (i + 0.5) * step, -TileCatalog.HALF_TILE_BU + (j + 0.5) * step)
					var block_p := p + Vector2(tx * 2 + 1, ty * 2 + 1) * TileCatalog.HALF_TILE_BU
					var total := _items_near(home_zones, block_p, ring)
					for sy in range(-1, 2):
						for sx in range(-1, 2):
							var hx := tx + sx
							var hy := ty + sy
							if not (hx >= lo and hx <= hi and hy >= lo and hy <= hi):
								total += int(slot_max[Vector4i(i, j, sx, sy)])
					if total > int(best.worst):
						best = {"worst": total, "at": p, "tile": Vector2i(tx, ty), "home": true}
	return best


## [center: Vector2, radius, items] per zone, items as the plankton field counts them.
static func _food_zones(zones: Array, content: WorldContent) -> Array:
	var unit := float(content.layout.plankton.unit_energy)
	var cap := int(content.config.caps.food_per_zone)
	var out := []
	for z in zones:
		var items := mini(cap, floori(float(z.capacity) / unit + PlanktonField.COUNT_EPSILON))
		out.append([Vector2(z.center[0], z.center[1]), float(z.radius), items])
	return out


## The items of `zones` (in their own tile's frame) whose discs come within `ring` of the point `at`
## in that frame.
static func _items_near(zones: Array, at: Vector2, ring: float) -> int:
	var total := 0
	for z in zones:
		if at.distance_to(z[0]) - float(z[1]) <= ring:
			total += int(z[2])
	return total


# --- the site sample (B-17) ---

static var _sample_gen: WorldGen = null
static var _sample_chunks := {}
static var _sample_margin := 0.0


## How many live sites at `size` have reach discs that meet the disc of `radius_tm` round
## `center_abs_tm` (absolute tm), over the chunks of `gen`. A site lies in the chunk of its home and
## its home lies inside its reach disc, so the chunks within radius + 2 x reach_max hold every such
## site. Chunks are cached while the same generator is passed (a seed's discs share them); passing
## another generator drops the cache. `band` must be size's band; -1 otherwise.
static func sample_sites(gen: WorldGen, band: int, size: int, center_abs_tm: PackedFloat64Array, radius_tm := 40.0) -> int:
	if WorldConfig.band_of(size) != band:
		return -1
	if gen != _sample_gen:
		_sample_gen = gen
		_sample_chunks.clear()
		_sample_margin = 2.0 * float(gen.content.reach_max(gen.species).radius_tm)
	var center := Vector2(center_abs_tm[0], center_abs_tm[1])
	var count := 0
	for key in WorldGen.disc_chunks(center_abs_tm[0], center_abs_tm[1], radius_tm + _sample_margin, gen.content.config.chunk_tm):
		var k := Vector3i(size, key.x, key.y)
		if not _sample_chunks.has(k):
			_sample_chunks[k] = gen.chunk(size, key.x, key.y)
		var c: WorldChunk = _sample_chunks[k]
		for s in c.sites:
			if s.reach.is_empty() or not s.sizes.has(size):
				continue
			if center.distance_to(Vector2(s.reach.x, s.reach.y)) < radius_tm + float(s.reach.radius):
				count += 1
	return count


# --- the seams (G4) ---

## Problems across tile seams and the home block's edges: rules 9 and 10 for every live site against
## the circles of both sides, and no circle overlapping one across the seam (tile rule 2). A
## problem the site's own side already has is not repeated; each names both sides and their
## orientations. Ordered pairs of tiles in `orientations`, B east of A, north of A and at A's
## north-east corner (core 6.7's three placements; the pairs swapped give west, south and the
## south-west corner, and with all eight orientations a quarter turn of the pair gives the other two
## corners); then every tile and orientation along each edge of the home block. At `size`, in its tm:
## the colliders there, each live site's discs with k (both posts and the union for two posts), the
## radius there, and the offsets times bu_to_tm(size).
static func seam_problems(content: WorldContent, species: SpeciesCatalog, part_catalog: PartCatalog, size: int,
		orientations := PackedInt32Array(ALL_ORIENTATIONS)) -> PackedStringArray:
	var out := tile_seam_problems(content, species, part_catalog, size, orientations)
	out.append_array(home_seam_problems(content, species, part_catalog, size, orientations))
	return out


## seam_problems' tile pairs.
static func tile_seam_problems(content: WorldContent, species: SpeciesCatalog, part_catalog: PartCatalog, size: int,
		orientations := PackedInt32Array(ALL_ORIENTATIONS)) -> PackedStringArray:
	var frames := _tile_frames(content, species, part_catalog, size, orientations)
	var tile := TileCatalog.HALF_TILE_BU * 2.0 * WorldConfig.bu_to_tm(size)
	var placements := [["east", Vector2(tile, 0.0)], ["north", Vector2(0.0, -tile)], ["north-east", Vector2(tile, -tile)]]
	var out := PackedStringArray()
	for a in frames:
		for b in frames:
			for placement in placements:
				_seam(a, b, placement[1], "seam %s | %s %s" % [a.where, b.where, placement[0]], species, out)
	return out


## seam_problems' home edges: each tile and orientation in the two tile slots along each edge.
static func home_seam_problems(content: WorldContent, species: SpeciesCatalog, part_catalog: PartCatalog, size: int,
		orientations := PackedInt32Array(ALL_ORIENTATIONS)) -> PackedStringArray:
	var frames := _tile_frames(content, species, part_catalog, size, orientations)
	var home := _home_frame(content, species, part_catalog, size)
	var lo := int(content.config.arrangement.home_tiles[0])
	var hi := int(content.config.arrangement.home_tiles[1])
	var slots: Array[Vector2i] = []
	for k in range(lo, hi + 1):
		slots.append(Vector2i(hi + 1, k))
		slots.append(Vector2i(lo - 1, k))
		slots.append(Vector2i(k, lo - 1))
		slots.append(Vector2i(k, hi + 1))
	var out := PackedStringArray()
	for slot in slots:
		var offset := Vector2(slot.x * 2 + 1, slot.y * 2 + 1) * TileCatalog.HALF_TILE_BU * WorldConfig.bu_to_tm(size)
		for b in frames:
			_seam(home, b, offset, "seam %s | %s at tile %s" % [home.where, b.where, slot], species, out)
	return out


## Side A at the origin, side B moved by `offset`: B's circles near each of A's discs and A's near
## each of B's, and every overlapping pair.
static func _seam(a: Dictionary, b: Dictionary, offset: Vector2, label: String, species: SpeciesCatalog, out: PackedStringArray) -> void:
	var b_circles: Array[Dictionary] = []
	for c in b.circles:
		b_circles.append({"id": c.id, "center": c.center + offset, "radius": c.radius})
	for ca in a.circles:
		for cb in b_circles:
			var gap: float = Vector2(ca.center).distance_to(cb.center) - ca.radius - cb.radius
			if gap < 0.0:
				out.append("%s: rule 2: '%s' and '%s' overlap by %.2f bu across the seam" % [label, ca.id, cb.id, -gap])
	var max_r := maxf(float(a.max_r), float(b.max_r))
	for s in a.sites:
		_seam_site(s, s.disc, a.circles, b_circles, max_r, label, species, out)
	for s in b.sites:
		var disc := {"center": Vector2(s.disc.center) + offset, "radius": s.disc.radius}
		_seam_site(s, disc, b_circles, a.circles, max_r, label, species, out)


## Rules 9 and 10 for one site with the far side's circles added, less what its own side gives. A
## far circle can change them only when it comes near the leash circle (rule 9's band), reaches into
## the disc, or lies within a passage of a circle that does (rule 10), which may be an own circle or
## a far one, so `max_r` is the largest radius on either side; the others are left out, and with
## none near, nothing is checked.
static func _seam_site(s: Dictionary, disc: Dictionary, own: Array[Dictionary], far: Array[Dictionary], max_r: float,
		label: String, species: SpeciesCatalog, out: PackedStringArray) -> void:
	var r := float(s.r)
	var band := r + float(species.fairness.leash_band_margin_m)
	var passage := 2.0 * r + float(species.fairness.pinch_margin_m)
	var reach_near := float(disc.radius) + maxf(band, r + passage + 2.0 * max_r)
	var near: Array[Dictionary] = []
	for c in far:
		if Vector2(disc.center).distance_to(c.center) - float(c.radius) < reach_near:
			near.append(c)
	if near.is_empty():
		return
	var alone := PackedStringArray()
	species.check_disc_against_shells(s.where, disc, r, own, INF, alone)
	var both := PackedStringArray()
	var all: Array[Dictionary] = own.duplicate()
	all.append_array(near)
	species.check_disc_against_shells(s.where, disc, r, all, INF, both)
	for p in both:
		if not alone.has(p):
			out.append("%s: %s" % [label, p])


## Each tile in each orientation as one side of a seam, in tm at `size`: {where, circles (ids
## "<where>:<id>", the colliders there x s), max_r, sites [{where, disc: {center, radius}, r}]}; a
## site's discs are built in the tile's identity frame and then oriented, as WorldGen does
## (docs/s1/s1-core.md 16.12), and a two-post site gives one entry per post and one for the union
## ("site 'lk' post a of ...").
static func _tile_frames(content: WorldContent, species: SpeciesCatalog, part_catalog: PartCatalog, size: int,
		orientations: PackedInt32Array) -> Array:
	var s := WorldConfig.bu_to_tm(size)
	var radii := TileCatalog.radii_at(species, part_catalog, size)
	var out := []
	for id in WorldConfig._sorted(content.tiles.tiles.keys()):
		var t: Dictionary = content.tiles.tiles[id]
		var second := is_second_size(int(t.band), size)
		var discs := []
		for site in t.sites:
			if not site.sizes.has(size) or not radii.has(site.species):
				discs.append([])
				continue
			var post_b: Dictionary = site.get("post_b", {})
			discs.append(site_discs(species, site, TileCatalog._vec(site.home), _tile_zone(t, site.territory_zone, second),
				post_b, _tile_zone(t, str(post_b.get("territory_zone", "")), second), size))
		for o in orientations:
			var ot := oriented_tile(t, o)
			var circles := _named(scaled(TileCatalog.colliders_at(ot, TileCatalog.colliders_of(ot, content.kit), size), s), ot.where)
			var frame := {"where": ot.where, "circles": circles, "max_r": _max_r(circles), "sites": []}
			for k in t.sites.size():
				for d in discs[k]:
					var c := WorldGen.orient_point(d.disc.center.x, d.disc.center.y, o)
					frame.sites.append({"where": "site '%s'%s of %s" % [t.sites[k].id, d.label, ot.where], "r": float(radii[t.sites[k].species]) * s,
						"disc": {"center": Vector2(c[0], c[1]) * s, "radius": float(d.disc.radius) * s}})
			out.append(frame)
	return out


## A tile zone's circle ({center, radius}) by id, or {} for none or one dropped at the second size.
static func _tile_zone(t: Dictionary, id: String, second: bool) -> Dictionary:
	var zone := TileCatalog._zone(t, id)
	if zone.is_empty() or (second and zone.at_second_size == "drop"):
		return {}
	return {"center": TileCatalog._vec(zone.center), "radius": float(zone.radius)}


## The home block as one side of a seam, in its own frame (centre at abs (0, 0)), in tm at `size`.
static func _home_frame(content: WorldContent, species: SpeciesCatalog, part_catalog: PartCatalog, size: int) -> Dictionary:
	var home := content.home
	var s := WorldConfig.bu_to_tm(size)
	var second := is_second_size(home.band, size)
	var radii := TileCatalog.radii_at(species, part_catalog, size)
	var circles := _named(scaled(home.circles_at(size), s), home.where)
	var frame := {"where": home.where, "circles": circles, "max_r": _max_r(circles), "sites": []}
	var zone_by_id := {}
	for zone in home.zones:
		if not (second and zone.at_second_size == "drop"):
			zone_by_id[zone.id] = {"center": Vector2(zone.x, zone.y), "radius": float(zone.radius)}
	for site in home.sites:
		if not site.sizes.has(size) or not radii.has(site.species):
			continue
		var post_b: Dictionary = site.post_b
		for d in site_discs(species, site, Vector2(site.x, site.y), zone_by_id.get(site.territory_zone, {}), post_b,
				zone_by_id.get(str(post_b.get("territory_zone", "")), {}), size):
			frame.sites.append({"where": "site '%s'%s of %s" % [site.id, d.label, home.where], "r": float(radii[site.species]) * s,
				"disc": {"center": Vector2(d.disc.center) * s, "radius": float(d.disc.radius) * s}})
	return frame


static func _max_r(circles: Array[Dictionary]) -> float:
	var out := 0.0
	for c in circles:
		out = maxf(out, float(c.radius))
	return out


static func _named(circles: Array[Dictionary], where: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in circles:
		out.append({"id": "%s:%s" % [where, c.id], "center": c.center, "radius": float(c.radius)})
	return out
