class_name HomeBlock
extends RefCounted
## The home block of band 0 (S1): the 128 x 128 bu block at the origin, which is the M1 pool as
## built, unwalled (its rocks, zones, spawn, starting carrion and sites, with their ids), plus an
## authored seam ring from r 36 to the block edge (game/data/home_b0.json, plan A.3).
##
## T1.1 skeleton: the spawn, its heading and the starting carrion come from the M1 layout; the rest
## lands with T1.6.

const DEFAULT_PATH := "res://game/data/home_b0.json"

var load_problems := PackedStringArray()
## {id, x, y, r (bu), asset, yaw_deg, scale, fixed: bool, yaw_range: [lo, hi]}; M1 rocks first in
## data order, then the seam ring.
var shells: Array[Dictionary] = []
## {id, x, y, radius, capacity, growth_rate, at_second_size}; M1 zones first.
var zones: Array[Dictionary] = []
## {id, species, x, y, heading, territory_zone, sizes}; M1 sites (sizes [1, 2]) first.
var sites: Array[Dictionary] = []
var spawn := PackedFloat64Array([0.0, 9.0])
var spawn_heading := -1.5708
## [[x, y], ...] from pool_m1.json.
var carrion_initial: Array = []


static func load_from(_path: String, layout: PoolLayout, _species: SpeciesCatalog) -> HomeBlock:
	var home := HomeBlock.new()
	if layout != null:
		home.spawn = PackedFloat64Array([layout.spawn.x, layout.spawn.y])
		home.spawn_heading = layout.spawn_heading
		for p: Vector2 in layout.carrion.get("initial", []):
			home.carrion_initial.append([p.x, p.y])
	return home


func validate(_species: SpeciesCatalog, _kit: PlacementKit, _part_catalog: PartCatalog, _size: int = 1) -> PackedStringArray:
	return PackedStringArray(load_problems)
