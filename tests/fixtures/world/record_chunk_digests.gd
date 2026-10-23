extends SceneTree
## Records the chunk-digest goldens that tests/test_world_gen.gd holds WorldGen to, on the fixture
## world at seed 401: tests/fixtures/world/chunk_digests.json at size 1 and chunk_digests_s2.json at
## size 2 (S2: sunk shells, dropped and thinned zones, k, scale x s). The keys are the eight
## home-block chunks x -2 to 1, y -1 to 0 (docs/s1/s1-core.md 12.2), then tile chunks chosen to hold
## each kind of object at size 1: a landmark, an ambush site, a territorial site, the fixed rare
## tile's place, a hashed rare tile's place at a mirrored orientation, a drift zone, and a chunk 100 km
## out (at size 2 the same keys, which hold what lies there, and KEYS_S2). Re-record only for a
## deliberate change to the generator or the fixture world (core C-15: once at the region-rule
## answer; S2 T3.3 added size 2 with size 1 unchanged), and say why in the commit:
##
##     godot --headless --path . --script res://tests/fixtures/world/record_chunk_digests.gd

const WORLD := "res://tests/fixtures/world/world_min.json"
const OUT := {1: "res://tests/fixtures/world/chunk_digests.json", 2: "res://tests/fixtures/world/chunk_digests_s2.json"}
const SEED := 401
const KEYS: Array[Vector2i] = [Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(3, -12), Vector2i(-6, -12), Vector2i(-7, -12), Vector2i(5, -2), Vector2i(11, 1), Vector2i(-3, -8),
	Vector2i(3125, -3126)]
## Size 2 adds chunks that hold a landmark, the fixed rare tile's place and a hashed rare place there
## (a tile is 40 tm at size 2, so the size-1 keys hold neither).
const KEYS_S2: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, -1), Vector2i(0, -8)]


func _initialize() -> void:
	var species := SpeciesCatalog.load_from()
	var content := WorldContent.load_from(WORLD, PoolLayout.load_from(), species)
	for size in OUT:
		var gen := WorldGen.create(content, species, SEED)
		var rows := PackedStringArray()
		for k in KEYS + (KEYS_S2 if size == 2 else [] as Array[Vector2i]):
			var c := gen.chunk(size, k.x, k.y)
			rows.append('  {"key": [%d, %d], "digest": "%s", "holds": "%d shells, %d zones, %d sites, %d anchors, %d places"}'
				% [k.x, k.y, c.digest(), c.shells.size(), c.zones.size(), c.sites.size(), c.anchors.size(), c.places.size()])
		var text := '{"note": "Written by record_chunk_digests.gd; do not edit by hand.", "world": "%s", "seed": %d, "size": %d,\n "chunks": [\n%s]}\n' % [WORLD, SEED, size, ",\n".join(rows)]
		var f := FileAccess.open(OUT[size], FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print(text)
	quit()
