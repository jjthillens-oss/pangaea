class_name TileCatalog
extends RefCounted
## The band's authored tiles (game/data/tiles/b<band>/*.json, S1): 64 x 64 bu places the seed
## arranges, each with its shell slots, zones, sites and landmark anchor (plan A.2).
##
## T1.1 skeleton: the pinned API, empty; loading and the tile rules land with T1.5.

var load_problems := PackedStringArray()
## id -> parsed tile; coordinates kept as float64 pairs (PackedFloat64Array), never Vector2.
var tiles := {}


static func load_from(_dirs: Dictionary) -> TileCatalog:
	return TileCatalog.new()


func tile(id: String) -> Dictionary:
	return tiles.get(id, {})


## The 3 tile ids of a band's region and set, sorted.
func ids_of(_band: int, _region: String, _set_index: int) -> PackedStringArray:
	return PackedStringArray()


func rare_kinds(_band: int) -> PackedStringArray:
	return PackedStringArray()


func rare_tile(_band: int, _kind: String) -> Dictionary:
	return {}


func validate(_species: SpeciesCatalog, _kit: PlacementKit, _part_catalog: PartCatalog, _size: int = 1) -> PackedStringArray:
	return PackedStringArray(load_problems)
