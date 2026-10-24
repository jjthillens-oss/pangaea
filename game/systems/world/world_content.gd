class_name WorldContent
extends RefCounted
## Everything the endless world is made of (S1): the world settings, the band's tiles, the home
## block and the placement kit, loaded together from world_cell.json's content paths, and the cheap
## checks across them (docs/s1/s1-interfaces.md section 3.3, docs/s1/s1-core.md section 6.1).
##
## This file only calls the four loaders; it never touches files itself (tests/test_sim_purity.gd).

## The camera the rings and the view set were derived from (spine 4.1's view ring: the zoom-max
## footprint's far corner on a 2.4:1 screen plus look_ahead_max). A layout with another camera would
## see past the loaded chunks, so problems() refuses it.
const CAMERA_ASSUMED := {"zoom_max": 20.0, "pitch_deg": 55.0, "fov_deg": 45.0}
## species.fairness.spawn_view_aspect, the screen shape the same derivation assumes.
const VIEW_ASPECT_ASSUMED := 2.4

var config: WorldConfig
var tiles: TileCatalog
var home: HomeBlock
var kit: PlacementKit
## S3 (D-94): {int band: CradleBlock}, the home tiles of each band from 1 to band_of(max_size_in_build)
## that content.cradle names.
var cradles := {}
## The M1 pool layout the home block builds on (its camera and carrion are checked here too).
var layout: PoolLayout
## What WorldGen derives from the content alone (each tile's objects in each orientation, the kit's
## fitting shells per slot radius), cached here so every generator bound to this content shares
## it. Only WorldGen reads or writes it; change the content only before the first generator runs.
var derived := {}


## Never null; what failed to load shows in problems(). A null layout is loaded from
## PoolLayout.DEFAULT_PATH; a null species leaves the home block to load its base_sites file.
static func load_from(config_path: String, p_layout: PoolLayout, species: SpeciesCatalog) -> WorldContent:
	var world := WorldContent.new()
	world.layout = p_layout if p_layout != null else PoolLayout.load_from()
	world.config = WorldConfig.load_from(config_path)
	var paths: Dictionary = world.config.content
	world.kit = PlacementKit.load_from(str(paths.get("kit", "")))
	world.tiles = TileCatalog.load_from(paths.get("tiles", {}))
	world.home = HomeBlock.load_from(str(paths.get("home", "")), world.layout, species)
	for band in WorldConfig._sorted(world.config.cradle_paths.keys()):
		if int(band) >= 1 and int(band) <= WorldConfig.band_of(world.config.max_size_in_build):
			world.cradles[int(band)] = CradleBlock.load_from(world.config.cradle_paths[band])
	world.tiles.morsel_max_radius_tm = float(world.config.growth.get("remnants", {}).get("morsel_max_radius_tm",
		world.tiles.morsel_max_radius_tm))
	return world


## Band `band`'s cradle, or null (band 0, or none loaded).
func cradle_of(band: int) -> CradleBlock:
	return cradles.get(band)


## Problems across the content; empty when the world can run. Cheap checks only (at most 50 ms,
## tests/test_world_content.gd), in this order: the world file, the kit, the tiles and the home block
## at each size from size_start to max_size_in_build (D-70), then the checks across files: the fixed
## rare kind, the interim carrion supply (C-13), the camera the rings assume, the local bound round a
## held creature's reach (B-6) and the largest shell (BP-4). A world file that did not read gives its
## own problems alone, since the content paths came from it.
func problems(part_catalog: PartCatalog, species: SpeciesCatalog) -> PackedStringArray:
	var out := config.validate()
	if not config.load_problems.is_empty():
		return out
	out.append_array(kit.validate())
	# D-70: the tiles, then the home block, at every size the build runs; a problem the same at two
	# sizes (a size-free rule's, or a reading problem) is listed once, where it first came.
	var sizes := range(config.size_start, config.max_size_in_build + 1)
	var seen := {}
	for n in sizes:
		_add_new(out, seen, tiles.validate(species, kit, part_catalog, n))
	for n in sizes:
		_add_new(out, seen, home.validate(species, kit, part_catalog, n))
	var kind := str(config.arrangement.fixed_rare.kind)
	var kinds := tiles.rare_kinds(0)
	if not kinds.has(kind):
		out.append("world_cell.arrangement.fixed_rare.kind: '%s' is not a rare kind of band 0's tiles %s" % [kind, kinds])
	# C-13: the interim supply draws its points over the zones in the region, which in endless mode
	# depend on the route the cell swam, so the same seed would not give the same world.
	if config.mode == "endless" and bool(layout.carrion.get("interim_supply", {}).get("enabled", false)):
		out.append("layout.carrion.interim_supply.enabled: endless mode refuses the interim supply (its points depend on the route)")
	for key in CAMERA_ASSUMED:
		var v := float(layout.camera.get(key, NAN))
		if v != CAMERA_ASSUMED[key]:
			out.append("layout.camera.%s: %s, but the rings and the view set assume %s" % [key, v, CAMERA_ASSUMED[key]])
	var aspect := float(species.fairness.get("spawn_view_aspect", NAN))
	if aspect != VIEW_ASPECT_ASSUMED:
		out.append("species.fairness.spawn_view_aspect: %s, but the rings and the view set assume %s" % [aspect, VIEW_ASPECT_ASSUMED])
	# B-6: the cell rebases beyond rebase_beyond_tm, a held creature's reach disc centre lies within
	# hold of it, its disc reaches reach_max further and the disc's chunks a chunk's diagonal more.
	var reach := reach_max(species)
	var farthest := config.rebase_beyond_tm + float(config.rings.hold) + float(reach.radius_tm) + config.chunk_tm * sqrt(2.0)
	if not (farthest < config.local_bound_tm):
		out.append("%s.origin.local_bound_tm: rebase_beyond_tm + hold + reach_max + chunk_tm x sqrt 2 (%.2f) must be below it (%.2f); reach_max is %.2f tm, %s"
			% [WorldConfig.FILE_NAME, farthest, config.local_bound_tm, reach.radius_tm, reach.where])
	# BP-4: the growth tick's spiral at the next size stays within wedge_tm of the cell, in the 3 x 3
	# chunks round it; a shell no wider than chunk_tm - 2 x wedge_tm keeps every collider that can touch
	# it in those chunks. At every size the build runs (the widest is at a band's first size).
	var widest := config.chunk_tm - 2.0 * float(config.growth.get("wedge_tm", 0.0))
	for n in sizes:
		var shell := largest_shell(n)
		if float(shell.radius_tm) > widest:
			out.append("%s: BP-4: radius %.2f tm at size %d; every shell keeps <= chunk_tm - 2 x wedge_tm (%.2f tm)"
				% [shell.where, shell.radius_tm, n, widest])
	return out


static func _add_new(out: PackedStringArray, seen: Dictionary, problems: PackedStringArray) -> void:
	for p in problems:
		if not seen.has(p):
			seen[p] = true
			out.append(p)


## The largest reach-disc radius in tm over the home block and every tile, among the sites live at
## the sizes this build runs (size_start to max_size_in_build), and where it is:
## {radius_tm, where: "b0/reef_c site 'a'"}; radius 0 and where "" with no live site. A site's disc at
## size n is its brain's there: the species' lengths times k_of(entry size, n) in the tile frame's bu
## (D-39, D-69), over the union of both posts for a two-post site (D-38, D-82), then times
## bu_to_tm(n). Sites the validators refuse (an unknown species, a missing territory, a size below the
## species' entry size) are skipped.
func reach_max(species: SpeciesCatalog) -> Dictionary:
	var best := {"radius_tm": 0.0, "where": ""}
	var sizes := range(config.size_start, config.max_size_in_build + 1)
	for id in WorldConfig._sorted(tiles.tiles.keys()):
		var t: Dictionary = tiles.tiles[id]
		for s in t.sites:
			var post: Dictionary = s.get("post_b", {})
			var b := {} if post.is_empty() else {"home": TileCatalog._vec(post.home), "heading": float(post.heading),
				"zone": TileCatalog._circle_of(TileCatalog._zone(t, str(post.territory_zone)))}
			_take_reach(best, species, s.species, TileCatalog._vec(s.home), float(s.heading),
				TileCatalog._circle_of(TileCatalog._zone(t, s.territory_zone)), b, s.sizes, sizes, "%s site '%s'" % [t.where, s.id])
	var zone_by_id := {}
	for zone in home.zones:
		zone_by_id[zone.id] = HomeBlock._circle(zone)
	for s in home.sites:
		var post: Dictionary = s.post_b
		var b := {} if post.is_empty() else {"home": Vector2(post.home[0], post.home[1]), "heading": float(post.heading),
			"zone": zone_by_id.get(str(post.territory_zone), {})}
		_take_reach(best, species, s.species, Vector2(s.x, s.y), float(s.heading), zone_by_id.get(s.territory_zone, {}), b,
			s.sizes, sizes, "%s site '%s'" % [home.where, s.id])
	return best


## One site's reach at each size of `sizes` it is live at (`live`, its sizes): `zone` is its territory
## circle ({} for none) and `post_b` {} or its second post {home, heading, zone}.
func _take_reach(best: Dictionary, species: SpeciesCatalog, kind: String, home_bu: Vector2, heading: float, zone: Dictionary,
		post_b: Dictionary, live: Array, sizes: Array, where: String) -> void:
	if not species.species.has(kind):
		return
	if species.behavior_of(kind) == "territorial" and (zone.is_empty() or (not post_b.is_empty() and post_b.zone.is_empty())):
		return
	var site := {"species": kind, "home": home_bu, "heading": heading}
	var territory := species.territory_from(site, zone)
	var entry := species.entry_size(kind)
	for n in sizes:
		if not live.has(n) or n < entry:
			continue
		var k := WorldConfig.k_of(entry, n)
		var disc := species.reach_disc_for(site, territory, k) if post_b.is_empty() \
				else species.two_post_disc_for(site, territory, post_b, species.territory_from(site, post_b.zone), k)
		if disc.is_empty():
			continue
		var radius := float(disc.radius) * WorldConfig.bu_to_tm(n)
		if radius > float(best.radius_tm):
			best.radius_tm = radius
			best.where = where


## BP3-8: the farthest a threat's body reaches from its reach disc's centre at size n, in tm: the
## largest reach radius plus body radius (SpeciesCatalog.radius_at) over every site of band_of(n)
## (tiles and cradle) live at n whose species is the cell's size there (q_of 1). 0.0 with none.
func reach_max_threat(n: int, species: SpeciesCatalog) -> float:
	var best := {"radius_tm": 0.0, "where": ""}
	var band := WorldConfig.band_of(n)
	var blocks: Array[Dictionary] = []
	for id in WorldConfig._sorted(tiles.tiles.keys()):
		if int(tiles.tiles[id].band) == band:
			blocks.append(tiles.tiles[id])
	if cradle_of(band) != null:
		blocks.append(cradle_of(band)._block())
	for t in blocks:
		for s in t.sites:
			if not species.species.has(s.species) or species.q_of(s.species, n) != 1.0 or not (s.sizes as Array).has(n):
				continue
			var post: Dictionary = s.get("post_b", {})
			var b := {} if post.is_empty() else {"home": TileCatalog._vec(post.home), "heading": float(post.heading),
				"zone": TileCatalog._circle_of(TileCatalog._zone(t, str(post.territory_zone)))}
			var one := {"radius_tm": 0.0, "where": ""}
			_take_reach(one, species, s.species, TileCatalog._vec(s.home), float(s.heading),
				TileCatalog._circle_of(TileCatalog._zone(t, s.territory_zone)), b, s.sizes, [n], "")
			if float(one.radius_tm) > 0.0:
				best.radius_tm = maxf(float(best.radius_tm), float(one.radius_tm) + species.radius_at(s.species, n))
	return float(best.radius_tm)


## The widest collider circle at size n, in tm, over the tiles of n's band (TileCatalog.colliders_at:
## shells, the landmark collider, a set piece's colliders) and the home block (circles_at), and where
## it is: {radius_tm, where: "b0/reef_c 's2'"}; radius 0 and where "" with none.
func largest_shell(n: int) -> Dictionary:
	var best := {"radius_tm": 0.0, "where": ""}
	var s := WorldConfig.bu_to_tm(n)
	var band := WorldConfig.band_of(n)
	for id in WorldConfig._sorted(tiles.tiles.keys()):
		var t: Dictionary = tiles.tiles[id]
		if int(t.band) == band:
			for c in TileCatalog.colliders_at(t, TileCatalog.colliders_of(t, kit), n):
				_take_shell(best, float(c.radius) * s, "%s '%s'" % [t.where, c.id])
	if home.band == band:
		for c in home.circles_at(n):
			_take_shell(best, float(c.radius) * s, "%s '%s'" % [home.where, c.id])
	return best


static func _take_shell(best: Dictionary, radius_tm: float, where: String) -> void:
	if radius_tm > float(best.radius_tm):
		best.radius_tm = radius_tm
		best.where = where
