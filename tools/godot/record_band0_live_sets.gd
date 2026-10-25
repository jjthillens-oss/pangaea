extends SceneTree
## Writes tests/fixtures/world/band0_live_sets.json: for every band-0 tile and the home block, the
## sites live at sizes 1 and 2 by S2's rule (the size is in the site's sizes and the species is live
## there, SpeciesCatalog.live_at). BP3-18: TileCatalog.site_role must give the same sets. Recorded on
## e3-base's rule; run it again only to show the sets have not moved.
## Usage: godot --headless --path . --script res://tools/godot/record_band0_live_sets.gd

const OUT := "res://tests/fixtures/world/band0_live_sets.json"


func _initialize() -> void:
	var species := SpeciesCatalog.load_from()
	var parts := PartCatalog.load_from()
	var tiles := TileCatalog.load_from({"0": "res://game/data/tiles/b0"})
	var home := HomeBlock.load_from("res://game/data/home_b0.json", PoolLayout.load_from(), species)
	var out := {"note": "BP3-18: the band-0 live site ids per tile and the home block at sizes 1 and 2, by S2's rule (sizes has n and SpeciesCatalog.live_at). Written by tools/godot/record_band0_live_sets.gd.",
		"tiles": {}, "home": {}}
	for id in WorldConfig._sorted(tiles.tiles.keys()):
		out.tiles[id] = _sets(tiles.tiles[id].sites, species, parts)
	out.home = _sets(home.sites, species, parts)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", false) + "\n")
	f.close()
	print("record_band0_live_sets: %d tiles and the home block" % tiles.tiles.size())
	quit(0)


static func _sets(sites: Array, species: SpeciesCatalog, parts: PartCatalog) -> Dictionary:
	var out := {}
	for n in [1, 2]:
		var live: Array = []
		for s in sites:
			if (s.sizes as Array).has(n) and species.live_at(str(s.species), n, parts):
				live.append(str(s.id))
		out[str(n)] = live
	return out
