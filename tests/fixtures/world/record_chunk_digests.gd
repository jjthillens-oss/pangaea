extends SceneTree
## Records tests/fixtures/world/chunk_digests.json, the chunk-digest golden that
## tests/test_world_gen.gd holds WorldGen to: on the fixture world at seed 401 and size 1, the
## eight home-block chunks x -2 to 1, y -1 to 0 (docs/s1/s1-core.md 12.2), then tile chunks chosen
## to hold each kind of object: a landmark, an ambush site, a territorial site, the fixed rare
## tile's place, a hashed rare tile's place at a mirrored orientation, a drift zone, and a chunk
## 100 km out. Re-record only for a deliberate change to the generator or the fixture world (core
## C-15: once at the region-rule answer), and say why in the commit:
##
##     godot --headless --path . --script res://tests/fixtures/world/record_chunk_digests.gd

const WORLD := "res://tests/fixtures/world/world_min.json"
const OUT := "res://tests/fixtures/world/chunk_digests.json"
const SEED := 401
const KEYS: Array[Vector2i] = [Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(3, -12), Vector2i(-6, -12), Vector2i(-7, -12), Vector2i(5, -2), Vector2i(11, 1), Vector2i(-3, -8),
	Vector2i(3125, -3126)]


func _initialize() -> void:
	var species := SpeciesCatalog.load_from()
	var content := WorldContent.load_from(WORLD, PoolLayout.load_from(), species)
	var gen := WorldGen.create(content, species, SEED)
	var rows := PackedStringArray()
	for k in KEYS:
		var c := gen.chunk(1, k.x, k.y)
		rows.append('  {"key": [%d, %d], "digest": "%s", "holds": "%d shells, %d zones, %d sites, %d anchors, %d places"}'
			% [k.x, k.y, c.digest(), c.shells.size(), c.zones.size(), c.sites.size(), c.anchors.size(), c.places.size()])
	var text := '{"note": "Written by record_chunk_digests.gd; do not edit by hand.", "world": "%s", "seed": %d, "size": 1,\n "chunks": [\n%s]}\n' % [WORLD, SEED, ",\n".join(rows)]
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)
	quit()
