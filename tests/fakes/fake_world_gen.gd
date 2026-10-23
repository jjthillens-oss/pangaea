extends WorldGen
## Test helper (not a test file): a generator for T2's streaming tests (S1 spine 3.16), so they do
## not depend on tile content. Every chunk (cx, cy) holds, in absolute tm at size 1:
##   - one shell of radius SHELL_R at the chunk's centre + (8, 8);
##   - with cx and cy both even (one per 2 x 2 chunks), a zone of radius ZONE_R and capacity
##     ZONE_CAPACITY at the chunk's centre;
##   - with cx and cy both 2 mod 4 (one per 4 x 4 chunks), a rammer site whose territory is that
##     zone, home ZONE_R - 2 east of its centre, reach disc of radius REACH_R on the zone (so it
##     lies inside the chunk), live at size 1.
## The nearest sites to the home spawn (0, 9) are at (-48, -48) and (80, 80) and so on: no creature
## starts in view. tile_info gives every tile the "sunlit" region.
##
##     var gen = FakeWorldGen.new(content, species, world_seed)

const SHELL_R := 1.0
const SHELL_OFFSET := 8.0
const ZONE_R := 5.0
const ZONE_CAPACITY := 40.0
const ZONE_GROWTH := 0.08
const REACH_R := 12.0
const SITE_SPECIES := "rammer"
const SITE_HEADING := -PI / 2.0

## Chunks built so far, by key: tests count generator calls with it.
var built := {}


func _init(p_content: WorldContent = null, p_species: SpeciesCatalog = null, p_seed := 0) -> void:
	setup(p_content, p_species, p_seed)


## The fixture content the fake streams with: the world file's rings and caps (a copy, so a test may
## change them), and the home block's spawn. `config_path` names another world file.
static func fixture_content(config_path: String = WorldConfig.DEFAULT_PATH) -> WorldContent:
	var c := WorldContent.new()
	c.config = WorldConfig.load_from(config_path)
	c.home = HomeBlock.new()
	return c


## An endless sim on this generator for a new omnivore lineage of `seed_value`, saved at the home
## spawn as a new game is (or at `at`, absolute am): the fixture content unless `content` is given,
## with creatures when `p_species` is.
static func endless_sim(seed_value: int, catalog: PartCatalog, layout: PoolLayout, p_species: SpeciesCatalog,
		content: WorldContent = null, at := PackedFloat64Array()) -> PoolSim:
	var c := content if content != null else fixture_content()
	var r := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	var place: PackedFloat64Array = at if not at.is_empty() else c.home.spawn
	r.save.player["position"] = PlaneSpace.to_save_abs(place[0], place[1])
	var Fake: GDScript = load("res://tests/fakes/fake_world_gen.gd")
	return PoolSim._create_endless(r.save, catalog, layout, p_species, c, Fake.new(c, p_species, seed_value))


func chunk(n: int, cx: int, cy: int) -> WorldChunk:
	var key := Vector2i(cx, cy)
	built[key] = int(built.get(key, 0)) + 1
	var c := WorldChunk.new()
	c.key = key
	c.size = n
	var chunk_tm := 32.0
	var x0 := chunk_tm * cx
	var y0 := chunk_tm * cy
	var tile := Vector2i(floori(cx / 2.0), floori(cy / 2.0))
	c.shells.append({"id": "s_f_%d_%d" % [cx, cy], "x": x0 + 16.0 + SHELL_OFFSET, "y": y0 + 16.0 + SHELL_OFFSET,
		"r": SHELL_R, "kind": "shell", "asset": "rock_a", "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
	if posmod(cx, 2) == 0 and posmod(cy, 2) == 0:
		c.zones.append({"id": "z_f_%d_%d" % [cx, cy], "x": x0 + 16.0, "y": y0 + 16.0, "radius": ZONE_R,
			"capacity": ZONE_CAPACITY, "growth_rate": ZONE_GROWTH, "tile": tile, "region": "sunlit"})
	var creatures_on: bool = content == null or bool(content.config.switches.get("generated_creatures", true))
	if posmod(cx, 4) == 2 and posmod(cy, 4) == 2 and creatures_on:
		var zx := x0 + 16.0
		var zy := y0 + 16.0
		c.sites.append({"id": "t_f_%d_%d" % [cx, cy], "species": SITE_SPECIES, "x": zx + ZONE_R - 2.0, "y": zy,
			"heading": SITE_HEADING, "territory": {"x": zx, "y": zy, "radius": ZONE_R},
			"reach": {"x": zx, "y": zy, "radius": REACH_R}, "chunks": [key] as Array[Vector2i], "sizes": [1] as Array[int],
			"tile": tile})
	return c


func tile_info(band: int, tx: int, ty: int) -> Dictionary:
	return {"id": "fake", "region": "sunlit", "rare": "", "set": posmod(tx + ty, 2), "orientation": 0}
