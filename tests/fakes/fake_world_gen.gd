extends WorldGen
## Test helper (not a test file): a generator for T2's streaming tests (S1 spine 3.16), so they do
## not depend on tile content. Every chunk (cx, cy) holds, in absolute tm at size 1:
##   - one shell of radius SHELL_R at the chunk's centre + (8, 8);
##   - with cx and cy both even (one per 2 x 2 chunks), a zone of radius ZONE_R and capacity
##     ZONE_CAPACITY at the chunk's centre;
##   - with cx and cy both 2 mod 4 (one per 4 x 4 chunks; `site_period` changes the 4), a rammer
##     site "t_f_<cx>_<cy>" whose territory is the disc of radius ZONE_R at the chunk's centre (the
##     zone's, where there is one), home ZONE_R - 2 east of that centre, reach disc of radius
##     REACH_R centred REACH_SHIFT east of it (so it reaches into the chunk to the east: its chunks
##     are both), live at size 1; and beside it a second rammer site of the same shape,
##     "u_f_<cx>_<cy>", live only at size 2 (so never in a size 1 table).
## Chunk (-2, 3) holds a rare place, "p_f_husk" (kind "giant_husk"), at its centre with yaw_deg
## PLACE_YAW and mirrored, as WorldGen emits places (B-15).
## Chunk (-3, 1) also holds the zone "z_edge" (capacity EDGE_CAPACITY) centred 2 tm inside its west
## edge, so its disc crosses into chunk (-4, 1), which holds the shell "s_edge" exactly
## ZONE_CLEAR_MARGIN from that disc (the gap rule, B-3).
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
const REACH_SHIFT := 6.0
## The fixture world the integration tests run the real generator on.
const FIXTURE_WORLD := "res://tests/fixtures/world/world_min.json"
const PLACE_CHUNK := Vector2i(-2, 3)
const PLACE_YAW := 135.0
const EDGE_CHUNK := Vector2i(-3, 1)
const EDGE_CAPACITY := 96.0
const ZONE_CLEAR_MARGIN := 0.7

## Chunks built so far, by key: tests count generator calls with it.
var built := {}
## A site per site_period x site_period chunks (1: one in every chunk).
var site_period := 4


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
## with creatures when `p_species` is, and a site per `p_site_period` x `p_site_period` chunks.
## Growth (S2) is switched off unless `growth` is true, on every call (BP-6: the S1 tests run the
## world as S1 did; the content may be shared).
static func endless_sim(seed_value: int, catalog: PartCatalog, layout: PoolLayout, p_species: SpeciesCatalog,
		content: WorldContent = null, at := PackedFloat64Array(), p_site_period := 4, growth := false) -> PoolSim:
	var c := content if content != null else fixture_content()
	c.config.switches["growth"] = growth
	var r := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	var place: PackedFloat64Array = at if not at.is_empty() else c.home.spawn
	r.save.player["position"] = PlaneSpace.to_save_abs(place[0], place[1])
	var Fake: GDScript = load("res://tests/fakes/fake_world_gen.gd")
	var gen: Variant = Fake.new(c, p_species, seed_value)
	gen.site_period = p_site_period
	return PoolSim._create_endless(r.save, catalog, layout, p_species, c, gen)


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
	if key == PLACE_CHUNK:
		c.places.append({"id": "p_f_husk", "kind": "giant_husk", "x": x0 + 16.0, "y": y0 + 16.0, "tile": tile,
			"yaw_deg": PLACE_YAW, "mirror": true})
	var edge := Vector2(chunk_tm * EDGE_CHUNK.x + 2.0, chunk_tm * EDGE_CHUNK.y + 16.0)
	if key == EDGE_CHUNK:
		c.zones.append({"id": "z_edge", "x": edge.x, "y": edge.y, "radius": ZONE_R, "capacity": EDGE_CAPACITY,
			"growth_rate": ZONE_GROWTH, "tile": tile, "region": "sunlit"})
	if key == EDGE_CHUNK + Vector2i(-1, 0):
		c.shells.append({"id": "s_edge", "x": edge.x - ZONE_R - ZONE_CLEAR_MARGIN - SHELL_R, "y": edge.y, "r": SHELL_R,
			"kind": "shell", "asset": "rock_a", "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
	if posmod(cx, 2) == 0 and posmod(cy, 2) == 0:
		c.zones.append({"id": "z_f_%d_%d" % [cx, cy], "x": x0 + 16.0, "y": y0 + 16.0, "radius": ZONE_R,
			"capacity": ZONE_CAPACITY, "growth_rate": ZONE_GROWTH, "tile": tile, "region": "sunlit"})
	var creatures_on: bool = content == null or bool(content.config.switches.get("generated_creatures", true))
	var at := site_period >> 1
	if posmod(cx, site_period) == at and posmod(cy, site_period) == at and creatures_on:
		var zx := x0 + 16.0
		var zy := y0 + 16.0
		var reach := {"x": zx + REACH_SHIFT, "y": zy, "radius": REACH_R}
		var reach_chunks := disc_chunks(zx + REACH_SHIFT, zy, REACH_R, chunk_tm)
		c.sites.append({"id": "t_f_%d_%d" % [cx, cy], "species": SITE_SPECIES, "x": zx + ZONE_R - 2.0, "y": zy,
			"heading": SITE_HEADING, "territory": {"x": zx, "y": zy, "radius": ZONE_R},
			"reach": reach.duplicate(), "chunks": reach_chunks.duplicate(), "sizes": [1] as Array[int], "tile": tile})
		c.sites.append({"id": "u_f_%d_%d" % [cx, cy], "species": SITE_SPECIES, "x": zx - ZONE_R + 2.0, "y": zy,
			"heading": SITE_HEADING, "territory": {"x": zx, "y": zy, "radius": ZONE_R},
			"reach": reach.duplicate(), "chunks": reach_chunks.duplicate(), "sizes": [2] as Array[int], "tile": tile})
	return c


## An endless sim on the real WorldGen (T1.9) and the fixture world (T1.7), for a new omnivore
## lineage of `seed_value` saved at the home spawn (or at `at`, absolute am), as a new game starts.
## Growth (S2) as endless_sim: off unless `growth` is true (BP-6).
static func real_sim(seed_value: int, catalog: PartCatalog, layout: PoolLayout, p_species: SpeciesCatalog,
		at := PackedFloat64Array(), growth := false) -> PoolSim:
	var c := WorldContent.load_from(FIXTURE_WORLD, layout, p_species)
	c.config.switches["growth"] = growth
	var r := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	var place: PackedFloat64Array = at if not at.is_empty() else c.home.spawn
	r.save.player["position"] = PlaneSpace.to_save_abs(place[0], place[1])
	return PoolSim.create(r.save, catalog, layout, p_species, c)


## The shipped species plus the two size-2 species as spine 4.2 builds them on the M1 ones, until T1.7
## puts them in creatures_m1.json: a "lurker" (ambush) and an "elder_rammer" (territorial), entry_size
## 2, each in a role of its own at cap 0. No habit: two posts are T1.6's.
static func s2_species() -> SpeciesCatalog:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	if not data.species.has("lurker"):
		var lurker: Dictionary = data.species.ambush_hunter.duplicate(true)
		lurker.name = "Lurker"
		lurker.entry_size = 2
		lurker.niche = {"role": "lurker", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		data.species["lurker"] = lurker
	if not data.species.has("elder_rammer"):
		var elder: Dictionary = data.species.rammer.duplicate(true)
		elder.name = "elder rammer"
		elder.entry_size = 2
		elder.niche = {"role": "elder_rammer", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		data.species["elder_rammer"] = elder
	return SpeciesCatalog.from_dict(data)


## The chunks a disc (absolute tm) touches, sorted (y, x).
static func disc_chunks(x: float, y: float, r: float, chunk_tm: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ky in range(floori((y - r) / chunk_tm), floori((y + r) / chunk_tm) + 1):
		for kx in range(floori((x - r) / chunk_tm), floori((x + r) / chunk_tm) + 1):
			var dx := maxf(0.0, maxf(chunk_tm * kx - x, x - chunk_tm * (kx + 1)))
			var dy := maxf(0.0, maxf(chunk_tm * ky - y, y - chunk_tm * (ky + 1)))
			if dx * dx + dy * dy <= r * r:
				out.append(Vector2i(kx, ky))
	return out


func tile_info(band: int, tx: int, ty: int) -> Dictionary:
	return {"id": "fake", "region": "sunlit", "rare": "", "set": posmod(tx + ty, 2), "orientation": 0}
