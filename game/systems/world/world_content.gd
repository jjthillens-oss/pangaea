class_name WorldContent
extends RefCounted
## Everything the endless world is made of (S1): the world settings, the band's tiles, the home
## block and the placement kit, loaded together from world_cell.json's content paths, and the cheap
## checks across them (docs/s1/s1-interfaces.md, section 3.3).
##
## T1.1 skeleton: the settings and the home block's spawn load; the tiles, the kit and the checks
## across files land with T1.5 to T1.7.

var config: WorldConfig
var tiles: TileCatalog
var home: HomeBlock
var kit: PlacementKit
## The M1 pool layout the home block builds on (its camera and carrion are checked here too).
var layout: PoolLayout


static func load_from(config_path: String, p_layout: PoolLayout, species: SpeciesCatalog) -> WorldContent:
	var world := WorldContent.new()
	world.layout = p_layout
	world.config = WorldConfig.load_from(config_path)
	var paths: Dictionary = world.config.content
	world.kit = PlacementKit.load_from(str(paths.get("kit", "")))
	world.tiles = TileCatalog.load_from(paths.get("tiles", {}))
	world.home = HomeBlock.load_from(str(paths.get("home", "")), p_layout, species)
	return world


## Problems across the content; empty when the world can run. Cheap checks only.
func problems(_part_catalog: PartCatalog, _species: SpeciesCatalog) -> PackedStringArray:
	return config.validate()
