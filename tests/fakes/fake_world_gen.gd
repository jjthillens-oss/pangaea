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
## At size 3 (S3, D-145) each site chunk also holds a veil site "v_f_<cx>_<cy>" (live at 3) VEIL_SHIFT
## south of the zone centre, heading 0, with the veil's reach disc. At size 4 it holds an elder-Warden
## site "e_f_<cx>_<cy>" (live at 4) with two posts guarding the zone disc and the meadow "z_fb_<cx>_<cy>"
## MEADOW_SHIFT east of it, both meadows blooming at its phase, and a morsel site "m_f_<cx>_<cy>" (a
## rammer, radius MORSEL_R, energy MORSEL_ENERGY) at the t_f_ site's home. At sizes 3 and 4
## ANCHOR_CHUNK holds the landmark anchor "a_f_lm" at its centre, inside a landmark collider of
## ANCHOR_R. The fake's content answers reach_max_threat from these sites (Content).
## At size 2 (S2) every chunk is the same pattern in size-2 tm, and each site chunk also holds two
## two-post sites live only at size 2 (S2 spine 3.17): a Lurker, "l_f_<cx>_<cy>", with posts LURKER_GAP
## apart and no territory, and an elder rammer, "e_f_<cx>_<cy>", whose first post guards the chunk's
## zone disc and whose second guards a disc of ELDER_ZONE_R to the south-west; each site's reach is
## the union of its posts' REACH_R discs (D-82). The fake applies no at_second_size.
## `extra_shells` adds shells to one chunk at one size (Vector3i(cx, cy, n) -> [{x, y, r}], absolute
## tm), so a test can wedge the cell at the next size; `extra_anchors` adds landmark anchors the same
## way (Vector3i(cx, cy, n) -> [{id, x, y, model}]), so a test can find one.
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
## The size-2 two-post sites (tm at size 2): the Lurker's two homes LURKER_GAP apart west of the zone
## centre and north of it, and the elder rammer's second zone disc.
const LURKER_GAP := 5.0
const ELDER_ZONE_R := 3.0
const VEIL_SHIFT := 8.0
const MEADOW_SHIFT := 12.0
const ANCHOR_CHUNK := Vector2i(2, -2)
const ANCHOR_R := 1.25
const ANCHOR_MODEL := "landmark_b1_heliozoan"
## The size-4 morsel site's item: the rammer's radius at 4 (0.625 x 1.6^-3) and its energy (D-145).
const MORSEL_R := 0.15259
const MORSEL_ENERGY := 7.3242
## ladder_species' minnow body size.
const MINNOW_BODY := 0.5

## Chunks built so far, by key: tests count generator calls with it.
var built := {}
## A site per site_period x site_period chunks (1: one in every chunk).
var site_period := 4
## Vector3i(cx, cy, size) -> Array of {x, y, r} (absolute tm at that size): more shells for a test.
var extra_shells := {}
## Vector3i(cx, cy, size) -> Array of {id, x, y, model} (absolute tm at that size): landmark anchors.
var extra_anchors := {}


func _init(p_content: WorldContent = null, p_species: SpeciesCatalog = null, p_seed := 0) -> void:
	setup(p_content, p_species, p_seed)


## The fixture content the fake streams with: the world file's rings and caps (a copy, so a test may
## change them), and the home block's spawn. `config_path` names another world file.
static func fixture_content(config_path: String = WorldConfig.DEFAULT_PATH) -> WorldContent:
	var c := Content.new()
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
	var more: Array = extra_shells.get(Vector3i(cx, cy, n), [])
	for i in more.size():
		c.shells.append({"id": "s_x_%d_%d_%d" % [cx, cy, i], "x": float(more[i].x), "y": float(more[i].y), "r": float(more[i].r),
			"kind": "shell", "asset": "rock_a", "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
	if key == ANCHOR_CHUNK and n >= 3:
		c.shells.append({"id": "s_f_lm", "x": x0 + 16.0, "y": y0 + 16.0, "r": ANCHOR_R, "kind": "landmark",
			"asset": ANCHOR_MODEL, "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
		c.anchors.append({"id": "a_f_lm", "x": x0 + 16.0, "y": y0 + 16.0, "model": ANCHOR_MODEL, "dressing": "plain", "tile": tile})
	for a in extra_anchors.get(Vector3i(cx, cy, n), []):
		c.anchors.append({"id": str(a.id), "x": float(a.x), "y": float(a.y), "model": str(a.model), "dressing": {}, "tile": tile})
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
		if n == 3 and species != null and species.has_species("veil"):
			c.sites.append(_veil("v_f_%d_%d" % [cx, cy], Vector2(zx, zy + VEIL_SHIFT), tile, chunk_tm))
		if n == 4 and species != null and species.has_species("elder_warden"):
			_add_elder_warden(c, "%d_%d" % [cx, cy], zx, zy, tile, chunk_tm)
		if n == 4:
			c.morsel_sites.append({"id": "m_f_%d_%d" % [cx, cy], "key": "fake/m_f_%d_%d" % [cx, cy], "species": SITE_SPECIES,
				"x": zx + ZONE_R - 2.0, "y": zy, "tile": tile, "radius": MORSEL_R, "energy": MORSEL_ENERGY})
		if n == 2:
			c.sites.append(_two_post("l_f_%d_%d" % [cx, cy], "lurker", [
				{"x": zx - 6.0, "y": zy - 8.0, "heading": SITE_HEADING, "territory": {}},
				{"x": zx - 6.0 + LURKER_GAP, "y": zy - 8.0, "heading": SITE_HEADING, "territory": {}}], tile, chunk_tm))
			c.sites.append(_two_post("e_f_%d_%d" % [cx, cy], "elder_rammer", [
				{"x": zx + 2.0, "y": zy + 4.0, "heading": SITE_HEADING, "territory": {"x": zx, "y": zy, "radius": ZONE_R}},
				{"x": zx - 7.0, "y": zy + 8.0, "heading": SITE_HEADING,
					"territory": {"x": zx - 8.0, "y": zy + 8.0, "radius": ELDER_ZONE_R}}], tile, chunk_tm))
	return c


## A veil site live at 3 at `home` (absolute tm), heading 0, with the veil's reach disc (D-145).
func _veil(id: String, home: Vector2, tile: Vector2i, chunk_tm: float) -> Dictionary:
	var disc := species.reach_disc_for({"species": "veil", "home": home, "heading": 0.0}, {})
	var at: Vector2 = disc.center
	return {"id": id, "species": "veil", "x": home.x, "y": home.y, "heading": 0.0, "territory": {},
		"reach": {"x": at.x, "y": at.y, "radius": float(disc.radius)},
		"chunks": disc_chunks(at.x, at.y, float(disc.radius), chunk_tm), "sizes": [3] as Array[int], "tile": tile}


## An elder Warden live at 4 (D-145): its posts guard the zone disc at (zx, zy) and the meadow z_fb_
## MEADOW_SHIFT east, its reach their union disc; both meadows bloom at the site's phase, slots 0 and 1.
func _add_elder_warden(c: WorldChunk, suffix: String, zx: float, zy: float, tile: Vector2i, chunk_tm: float) -> void:
	var id := "e_f_" + suffix
	var posts := [
		{"x": zx + 2.0, "y": zy + 4.0, "heading": SITE_HEADING, "territory": {"x": zx, "y": zy, "radius": ZONE_R}},
		{"x": zx + MEADOW_SHIFT + 2.0, "y": zy + 4.0, "heading": SITE_HEADING,
			"territory": {"x": zx + MEADOW_SHIFT, "y": zy, "radius": ZONE_R}}]
	var circle := func(t: Dictionary) -> Dictionary: return {"center": Vector2(t.x, t.y), "radius": float(t.radius)}
	var u := species.two_post_disc_for({"species": "elder_warden", "home": Vector2(posts[0].x, posts[0].y),
		"heading": SITE_HEADING}, circle.call(posts[0].territory), {"home": Vector2(posts[1].x, posts[1].y),
		"heading": SITE_HEADING}, circle.call(posts[1].territory))
	var at: Vector2 = u.center
	var phase := _bloom_phase(id, "elder_warden")
	c.sites.append({"id": id, "species": "elder_warden", "x": posts[0].x, "y": posts[0].y, "heading": SITE_HEADING,
		"territory": posts[0].territory.duplicate(), "reach": {"x": at.x, "y": at.y, "radius": float(u.radius)},
		"chunks": disc_chunks(at.x, at.y, float(u.radius), chunk_tm), "sizes": [4] as Array[int], "tile": tile,
		"posts": posts, "bloom": phase})
	for z in c.zones:
		if z.id == "z_f_" + suffix:
			z["bloom"] = {"slot": 0, "offset_ticks": phase.offset_ticks, "cycle_ticks": phase.cycle_ticks}
	c.zones.append({"id": "z_fb_" + suffix, "x": zx + MEADOW_SHIFT, "y": zy, "radius": ZONE_R, "capacity": ZONE_CAPACITY,
		"growth_rate": ZONE_GROWTH, "tile": tile, "region": "sunlit",
		"bloom": {"slot": 1, "offset_ticks": phase.offset_ticks, "cycle_ticks": phase.cycle_ticks}})


## A two-post site live only at size 2, as WorldGen places one (s2-sim 3.10): its home, heading and
## territory are its first post's, its reach the union of the posts' REACH_R discs.
static func _two_post(id: String, species_id: String, posts: Array, tile: Vector2i, chunk_tm: float) -> Dictionary:
	var u := CreatureBrain.union_disc({"center": Vector2(posts[0].x, posts[0].y), "radius": REACH_R},
		{"center": Vector2(posts[1].x, posts[1].y), "radius": REACH_R})
	var cx := float(u.center.x)
	var cy := float(u.center.y)
	return {"id": id, "species": species_id, "x": posts[0].x, "y": posts[0].y, "heading": posts[0].heading,
		"territory": posts[0].territory.duplicate(), "reach": {"x": cx, "y": cy, "radius": float(u.radius)},
		"chunks": disc_chunks(cx, cy, float(u.radius), chunk_tm), "sizes": [2] as Array[int], "tile": tile, "posts": posts}


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
## 2, each in a role of its own at cap 0, with spine 4.2's habits.
static func s2_species() -> SpeciesCatalog:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	_add_s2(data)
	return SpeciesCatalog.from_dict(data)


static func _add_s2(data: Dictionary) -> void:
	if not data.species.has("lurker"):
		var lurker: Dictionary = data.species.ambush_hunter.duplicate(true)
		lurker.name = "Lurker"
		lurker.entry_size = 2
		lurker.niche = {"role": "lurker", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		lurker.habit = {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}
		data.species["lurker"] = lurker
	if not data.species.has("elder_rammer"):
		var elder: Dictionary = data.species.rammer.duplicate(true)
		elder.name = "elder rammer"
		elder.entry_size = 2
		elder.niche = {"role": "elder_rammer", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
		elder.habit = {"post_switch": "nearer_cell", "post_hysteresis_m": 2.0}
		data.species["elder_rammer"] = elder


## s2_species plus a "minnow": the rammer at body size MINNOW_BODY (the smallest body), entry size 1,
## in a role of its own at cap 0, so it is a morsel at size 2 (rel 0.3125) for the growth tick's
## conversions.
static func ladder_species() -> SpeciesCatalog:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	var minnow: Dictionary = data.species.rammer.duplicate(true)
	minnow.name = "minnow"
	minnow.body_size = MINNOW_BODY
	minnow.niche = {"role": "minnow", "cap": 0, "respawn_s": 60.0, "respawn_jitter_s": 10.0}
	_add_s2(data)
	data.species["minnow"] = minnow
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


## The fake's content (BP3-8): reach_max_threat from the fake's own sites, the largest reach radius
## plus body radius over a site chunk's sites live at n whose species is the cell's size there.
class Content extends WorldContent:
	## The fake's kinds of place (D-133): the husk in band 0, the landmark model in band 1.
	func place_kinds(band: int) -> PackedStringArray:
		return PackedStringArray(["giant_husk"] if band == 0 else [ANCHOR_MODEL])

	func reach_max_threat(n: int, p_species: SpeciesCatalog) -> float:
		var gen: WorldGen = load("res://tests/fakes/fake_world_gen.gd").new(self, p_species, 0)
		gen.site_period = 1
		var best := 0.0
		for s in gen.chunk(n, 0, 0).sites:
			if (s.sizes as Array).has(n) and p_species.q_of(s.species, n) == 1.0:
				best = maxf(best, float(s.reach.radius) + p_species.radius_at(s.species, n))
		return best
