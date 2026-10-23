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
	return world


## Problems across the content; empty when the world can run. Cheap checks only (at most 50 ms,
## tests/test_world_content.gd), in this order: the world file, the kit, the tiles, the home block,
## then the checks across files: the fixed rare kind, the interim carrion supply (C-13) and the
## camera the rings assume. A world file that did not read gives its own problems alone, since the
## content paths came from it.
func problems(part_catalog: PartCatalog, species: SpeciesCatalog) -> PackedStringArray:
	var out := config.validate()
	if not config.load_problems.is_empty():
		return out
	out.append_array(kit.validate())
	out.append_array(tiles.validate(species, kit, part_catalog, config.size_start))
	out.append_array(home.validate(species, kit, part_catalog, config.size_start))
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
	return out
