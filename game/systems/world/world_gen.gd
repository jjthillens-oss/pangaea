class_name WorldGen
extends RefCounted
## The endless world's generator (S1): which tile lies where, and what each 32 x 32 tm chunk holds,
## as a pure function of (world_seed, gen_version, content, size, chunk). It binds the seed, the
## generator version and the content at creation (docs/s1/s1-interfaces.md, D-7), reads no clock,
## input, tree or global random numbers, and gives the same chunk along any route.
##
## The arrangement (spine 3.6, docs/s1/s1-core.md 6.4): a value-noise region per tile from a lattice
## every region_period_tiles, the coordinate drift rule, the home tiles, one rare tile per 6 x 6 block (block
## (0, 0)'s fixed), a tile id per (region, set) and a landmark per 2 x 2 cell. Every stream is a
## WorldHash of fixed coordinates. Tile infos and lattice values are memoised per instance; clearing
## the memo changes nothing (tests/test_world_gen.gd).
##
## The region rule is the coordinate rule (docs/s1/s1-build-plan.md B-11, replacing the spine's
## drift swap): a raw drift tile on every (max_drift_run + 1)th column or row is sunlit. Drift keeps
## about 14.8% of the tiles, and no row or column holds more than max_drift_run drift tiles running.
##
## A chunk (docs/s1/s1-core.md 6.5) holds every object of the tiles under it whose centre lies in
## it: shells with their hashed kit asset, yaw and dressing, zones, live sites with their reach
## discs (built small in the tile's own frame, then oriented and placed), landmark anchors and
## colliders, and rare set pieces with their colliders. Places also carry the yaw and mirror their
## colliders were placed with (docs/s1/s1-content.md 17.10), so the scene can draw them over them.
## S1 builds size 1 only; at_second_size (S2) is carried in the data and not applied here.

const HOME := "home"
const RARE := "rare"
const DRIFT := "drift"
const SUNLIT := "sunlit"
## _framed marks a point this close to a tile's centre line (bu) as lying on both sides of it.
const FRAME_EPS := 1e-6

# The purposes' str32, computed once (WorldHash: a str32 costs about a microsecond).
static var STR_REGION := WorldHash.str32("region")
static var STR_TILE := WorldHash.str32("tile")
static var STR_RARE := WorldHash.str32("rare")
static var STR_LANDMARK := WorldHash.str32("landmark")
static var STR_SHELL := WorldHash.str32("shell")
static var STR_HOME := WorldHash.str32("home")

var content: WorldContent
var species: SpeciesCatalog
var world_seed := 0
var gen_version := 1

# The arrangement, read once from content.config.arrangement.
var _period := 8
var _t0 := 0.395
var _t1 := 0.605
var _order := PackedStringArray(["drift", "sunlit", "reef"])
var _drift_index := 0
var _drift_run := 2
var _home_lo := -1
var _home_hi := 0
var _block_first := -3
var _block_tiles := 6
var _cell_tiles := 2
var _fixed_tile := Vector2i(2, -1)
var _fixed_kind := ""

## Vector3i(b, tx, ty) -> tile info. Never handed out: tile_info returns copies.
var _tile_memo := {}
## Vector3i(b, i, j) -> lattice value in [0, 1).
var _lattice_memo := {}
## "<b>/<region>/<set>" -> the tile catalog's sorted ids, and band -> its sorted rare kinds (the
## catalog sorts on every call): content.derived's, like every content-only cache below.
var _ids_memo := {}
var _rare_kinds_memo := {}
## Vector3i(b, lx, ly) -> landmark_of_cell's answer plus its hash "h"; Vector3i(b, bx, by) -> the
## block's rare tile.
var _cell_memo := {}
var _rare_memo := {}
## "<b>/<group>" -> the kit's sorted landmark models.
var _models_memo := {}
## band -> {r_bu -> the kit's sorted fitting shells}: content.derived's, shared with every generator
## bound to the same content.
var _fit_memo := {}
## "<tile id or home>/<site id>" -> {territory, reach} in the tile's (or the block's) own frame, bu:
## content.derived's, per species catalog.
var _disc_memo := {}
## "<tile id>/<o>" -> the tile's objects in its oriented frame (_framed): content.derived's too.
var _frame_memo := {}


static func create(p_content: WorldContent, p_species: SpeciesCatalog, p_world_seed: int) -> WorldGen:
	var gen := WorldGen.new()
	gen.setup(p_content, p_species, p_world_seed)
	return gen


## Binds the immutable inputs. create() calls it; a subclass (a test's fake generator) made with
## new() calls it too.
func setup(p_content: WorldContent, p_species: SpeciesCatalog, p_world_seed: int) -> void:
	content = p_content
	species = p_species
	world_seed = p_world_seed
	gen_version = p_content.config.gen_version if p_content != null and p_content.config != null else 1
	for memo in [_tile_memo, _lattice_memo, _cell_memo, _rare_memo]:
		memo.clear()
	_ids_memo = {}
	_rare_kinds_memo = {}
	_models_memo = {}
	_disc_memo = {}
	_fit_memo = {}
	_frame_memo = {}
	if p_content == null or p_content.config == null:
		return
	_ids_memo = p_content.derived.get_or_add("ids", {})
	_rare_kinds_memo = p_content.derived.get_or_add("rare_kinds", {})
	_models_memo = p_content.derived.get_or_add("models", {})
	_fit_memo = p_content.derived.get_or_add("fits", {})
	_frame_memo = p_content.derived.get_or_add("frames", {})
	if p_species != null:
		_disc_memo = p_content.derived.get_or_add("discs/%d" % p_species.get_instance_id(), {})
	var a: Dictionary = p_content.config.arrangement
	if a.is_empty():
		return
	_period = maxi(1, int(a.region_period_tiles))
	var t: PackedFloat64Array = a.region_thresholds
	if t.size() == 2:
		_t0 = t[0]
		_t1 = t[1]
	if (a.region_order as PackedStringArray).size() == 3:
		_order = a.region_order
	_drift_index = _order.find(DRIFT)
	_drift_run = maxi(1, int(a.max_drift_run))
	_home_lo = int(a.home_tiles[0])
	_home_hi = int(a.home_tiles[1])
	_block_first = int(a.rare_block_first_tile)
	_block_tiles = maxi(1, int(a.rare_block_tiles))
	_cell_tiles = maxi(1, int(a.landmark_cell_tiles))
	_fixed_tile = a.fixed_rare.tile
	_fixed_kind = str(a.fixed_rare.kind)


## Forgets every memoised value, the content-only caches it shares with other generators included
## (tests: results must not depend on the memo).
func clear_memo() -> void:
	_tile_memo.clear()
	_lattice_memo.clear()
	_ids_memo.clear()
	_rare_kinds_memo.clear()
	_cell_memo.clear()
	_rare_memo.clear()
	_models_memo.clear()
	_disc_memo.clear()
	_fit_memo.clear()
	_frame_memo.clear()
	if content != null:
		content.derived.erase("home")


## The chunk (cx, cy) at size n: every object whose centre lies in it, in absolute tm (float64),
## tile by tile in (ty, tx) order and each tile's lists in their order.
func chunk(n: int, cx: int, cy: int) -> WorldChunk:
	var out := WorldChunk.new()
	out.key = Vector2i(cx, cy)
	out.size = n
	if content == null or content.config == null:
		return out
	var b := WorldConfig.band_of(n)
	var s := WorldConfig.bu_to_tm(n)
	var chunk_tm: float = content.config.chunk_tm
	var tile_tm: float = content.config.tile_bu * s
	var tx0 := floori(cx * chunk_tm / tile_tm)
	var tx1 := ceili((cx + 1) * chunk_tm / tile_tm) - 1
	var ty0 := floori(cy * chunk_tm / tile_tm)
	var ty1 := ceili((cy + 1) * chunk_tm / tile_tm) - 1
	var home_done := false
	for ty in range(ty0, ty1 + 1):
		for tx in range(tx0, tx1 + 1):
			var info := _tile_ref(b, tx, ty)
			if info.region == HOME:
				if not home_done:
					_emit_home(out, n, b, s)
					home_done = true
				continue
			var t: Dictionary = content.tiles.tiles.get(info.id, {})
			if not t.is_empty():
				_emit_tile(out, t, info, n, b, s, tx, ty)
	return out


## Whether an absolute tm point lies in the chunk.
func _in(out: WorldChunk, x: float, y: float) -> bool:
	var c: float = content.config.chunk_tm
	return floori(x / c) == out.key.x and floori(y / c) == out.key.y


func _emit_tile(out: WorldChunk, t: Dictionary, info: Dictionary, n: int, b: int, s: float, tx: int, ty: int) -> void:
	var o: int = info.orientation
	var f := _framed(t, o)
	var tile := Vector2i(tx, ty)
	var cx := TileCatalog.HALF_TILE_BU * (2 * tx + 1)
	var cy := TileCatalog.HALF_TILE_BU * (2 * ty + 1)
	var prefix := "%d_%d_%d" % [b, tx, ty]
	# At size 1 a chunk is one quarter of the tile: only the objects that may lie in it are tried.
	var quarter := -1
	if n == 1:
		quarter = 1 << ((out.key.x - 2 * tx) + 2 * (out.key.y - 2 * ty))
	# Shells: a kit asset that fits the slot, a yaw and a dressing per slot from the slot's hash.
	var shell_key := -1
	for e in f.shells:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if not _in(out, x, y):
			continue
		if shell_key < 0:
			shell_key = _key(b, tx, ty, STR_SHELL)
		var sh: Dictionary = t.shells[e.k]
		_append_shell(out, "s_%s_%s" % [prefix, sh.id], x, y, float(sh.radius), s, WorldHash.mix32(shell_key, e.k), b,
			sh.yaw_deg, o)
	# The landmark, when this tile is its cell's pick.
	for e in f.anchor:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var lx := fdiv(tx, _cell_tiles)
		var ly := fdiv(ty, _cell_tiles)
		var lm := _cell(b, lx, ly)
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if not lm.is_empty() and lm.tile == tile and _in(out, x, y):
			_emit_landmark(out, lm, b, lx, ly, o, x, y, s, prefix, tile)
	# The rare set piece: its colliders (record colliders turned by the piece's yaw, moved to its
	# centre, then oriented with the tile), and the place, which carries the yaw and mirror.
	var yaw := orient_yaw_deg(float(t.set_piece.get("yaw_deg", 0.0)), o)
	for e in f.pieces:
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if (quarter < 0 or e.q & quarter != 0) and _in(out, x, y):
			out.shells.append({"id": "s_%s_r%d" % [prefix, e.k], "x": x, "y": y, "r": float(e.r) * s,
				"kind": "set_piece", "asset": t.set_piece.asset, "yaw_deg": yaw, "scale": 1.0, "tint": ""})
	for e in f.place:
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if (quarter < 0 or e.q & quarter != 0) and _in(out, x, y):
			out.places.append({"id": "p_%s" % prefix, "kind": t.rare, "x": x, "y": y, "tile": tile, "yaw_deg": yaw,
				"mirror": (o >> 2) & 1 == 1})
	for e in f.zones:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if _in(out, x, y):
			var z: Dictionary = t.zones[e.k]
			out.zones.append({"id": "z_%s_%s" % [prefix, z.id], "x": x, "y": y, "radius": float(z.radius) * s,
				"capacity": float(z.capacity), "growth_rate": float(z.growth_rate), "tile": tile, "region": info.region})
	if not bool(content.config.switches.get("generated_creatures", true)):
		return
	for e in f.sites:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var site: Dictionary = t.sites[e.k]
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if not (site.sizes as Array).has(n) or not _in(out, x, y):
			continue
		var discs := _site_discs("%s/%s" % [t.id, site.id], site, TileCatalog._zone(t, site.territory_zone))
		out.sites.append(_placed_site("t_%s_%s" % [prefix, site.id], site, discs, x, y, cx, cy, o, s, tile))


## A tile's objects in its oriented frame (bu from the tile centre, float64), memoised per tile and
## orientation: for shells, zones, sites, set-piece colliders, the landmark anchor and the place,
## a list of {k (list index), x, y, q}, where q marks the quarters of the tile (the chunks at size
## 1) the point may lie in. A point within FRAME_EPS of a centre line is marked on both sides, and
## chunk() still tests every point exactly.
func _framed(t: Dictionary, o: int) -> Dictionary:
	var memo_key := "%s/%d" % [t.id, o]
	if _frame_memo.has(memo_key):
		return _frame_memo[memo_key]
	var f := {"shells": [], "zones": [], "sites": [], "pieces": [], "anchor": [], "place": []}
	for k in t.shells.size():
		f.shells.append(_framed_point(k, t.shells[k].center[0], t.shells[k].center[1], o))
	for k in t.zones.size():
		f.zones.append(_framed_point(k, t.zones[k].center[0], t.zones[k].center[1], o))
	for k in t.sites.size():
		f.sites.append(_framed_point(k, t.sites[k].home[0], t.sites[k].home[1], o))
	if t.landmark_anchor.size() == 2:
		f.anchor.append(_framed_point(0, t.landmark_anchor[0], t.landmark_anchor[1], o))
	if not t.set_piece.is_empty() and t.set_piece.center.size() == 2:
		var piece: Dictionary = t.set_piece
		var colliders: Array = content.kit.assets.get(piece.asset, {}).get("colliders", [])
		for k in colliders.size():
			var c: Dictionary = colliders[k]
			if c.center.size() != 2:
				continue
			var q := TileCatalog.yaw_point(c.center[0], c.center[1], float(piece.yaw_deg))
			var e := _framed_point(k, piece.center[0] + q[0], piece.center[1] + q[1], o)
			e["r"] = float(c.radius)
			f.pieces.append(e)
		f.place.append(_framed_point(0, piece.center[0], piece.center[1], o))
	_frame_memo[memo_key] = f
	return f


func _framed_point(k: int, x: float, y: float, o: int) -> Dictionary:
	var p := orient_point(x, y, o)
	var q := 0
	for qy in 2:
		if (qy == 0 and p[1] >= FRAME_EPS) or (qy == 1 and p[1] <= -FRAME_EPS):
			continue
		for qx in 2:
			if (qx == 0 and p[0] >= FRAME_EPS) or (qx == 1 and p[0] <= -FRAME_EPS):
				continue
			q |= 1 << (qx + 2 * qy)
	return {"k": k, "x": p[0], "y": p[1], "q": q}


## The home block at its own origin, orientation 0: the M1 rocks and the ring's hashed shells, the
## zones, and the sites (M1 sites always; ring sites when generated creatures are on).
func _emit_home(out: WorldChunk, n: int, b: int, s: float) -> void:
	var home := content.home
	var index := _home_index()
	var at: Dictionary = index.chunks.get(out.key, {}) if n == 1 else index.all
	var ring_key := -1
	for i in at.get("shells", []):
		var sh: Dictionary = home.shells[i]
		var x: float = sh.x * s
		var y: float = sh.y * s
		if not _in(out, x, y):
			continue
		if sh.fixed:
			out.shells.append({"id": sh.id, "x": x, "y": y, "r": float(sh.r) * s, "kind": "shell", "asset": sh.asset,
				"yaw_deg": float(sh.yaw_deg), "scale": float(sh.scale), "tint": ""})
			continue
		if ring_key < 0:
			ring_key = _key(b, 0, 0, STR_HOME)
		_append_shell(out, "s_h_%s" % sh.id, x, y, float(sh.r), s, WorldHash.mix32(ring_key, index.ring_k[i]), b,
			sh.yaw_range, 0)
	for i in at.get("zones", []):
		var z: Dictionary = home.zones[i]
		var x: float = z.x * s
		var y: float = z.y * s
		if _in(out, x, y):
			out.zones.append({"id": z.id if z.m1 else "z_h_%s" % z.id, "x": x, "y": y, "radius": float(z.radius) * s,
				"capacity": float(z.capacity), "growth_rate": float(z.growth_rate), "tile": _home_tile(z.x, z.y),
				"region": HOME})
	var generated := bool(content.config.switches.get("generated_creatures", true))
	for i in at.get("sites", []):
		var site: Dictionary = home.sites[i]
		if not (site.m1 or generated) or not (site.sizes as Array).has(n):
			continue
		var x: float = site.x * s
		var y: float = site.y * s
		if not _in(out, x, y):
			continue
		var data := {"species": site.species, "home": PackedFloat64Array([site.x, site.y]), "heading": site.heading,
			"sizes": site.sizes}
		var discs := _site_discs("home/%s" % site.id, data, index.zones_by_id.get(site.territory_zone, {}))
		var id: String = site.id if site.m1 else "t_h_%s" % site.id
		out.sites.append(_placed_site(id, data, discs, x, y, 0.0, 0.0, 0, s, _home_tile(site.x, site.y)))


## The home block's lists indexed once per content: at size 1 the indices of the shells, zones and
## sites whose centres lie in each chunk (in list order), every index for other sizes, each ring
## shell's slot number k (its place among the ring shells) and the zones by id.
func _home_index() -> Dictionary:
	if content.derived.has("home"):
		return content.derived.home
	var home := content.home
	var c: float = content.config.chunk_tm
	var index := {"chunks": {}, "all": {"shells": [], "zones": [], "sites": []}, "ring_k": [], "zones_by_id": {}}
	var ring := 0
	for list_name in ["shells", "zones", "sites"]:
		var list: Array = home.get(list_name)
		for i in list.size():
			var item: Dictionary = list[i]
			var key := Vector2i(floori(float(item.x) / c), floori(float(item.y) / c))
			if not index.chunks.has(key):
				index.chunks[key] = {"shells": [], "zones": [], "sites": []}
			index.chunks[key][list_name].append(i)
			index.all[list_name].append(i)
			if list_name == "shells":
				index.ring_k.append(-1 if item.fixed else ring)
				if not item.fixed:
					ring += 1
	for z in home.zones:
		index.zones_by_id[z.id] = {"center": PackedFloat64Array([z.x, z.y]), "radius": z.radius}
	content.derived.home = index
	return index


## The tile of the home block that holds a block point (bu).
func _home_tile(x: float, y: float) -> Vector2i:
	var t: float = content.config.tile_bu
	return Vector2i(floori(x / t), floori(y / t))


func _emit_landmark(out: WorldChunk, lm: Dictionary, b: int, lx: int, ly: int, o: int, x: float, y: float, s: float,
		prefix: String, tile: Vector2i) -> void:
	var model: Dictionary = content.kit.assets.get(lm.model, {})
	var dressing := {}
	for d in model.get("dressings", []):
		if d.id == lm.dressing:
			dressing = d
	var h := WorldHash.mix32(lm.h, 3)
	var yaw := 360.0 * WorldHash.unit(h)
	if model.get("yaw_rule", "") == "steps_90":
		yaw = orient_yaw_deg(90.0 * WorldHash.pick(h, 4), o)
	out.shells.append({"id": "s_%s_lm" % prefix, "x": x, "y": y, "r": content.kit.collide_radius_bu * s, "kind": "landmark",
		"asset": lm.model, "yaw_deg": yaw, "scale": float(dressing.get("scale", 1.0)), "tint": str(dressing.get("tint", ""))})
	out.anchors.append({"id": "a_%d_%d_%d" % [b, lx, ly], "x": x, "y": y, "model": lm.model, "dressing": lm.dressing,
		"tile": tile})


## Appends a shell slot's shell: its asset (one of the kit's fitting shells), yaw (free, or within
## the slot's range for a "slot" asset; then oriented by o) and dressing tint from the slot's hash h,
## at scale radius / footprint.
func _append_shell(out: WorldChunk, id: String, x: float, y: float, r_bu: float, s: float, h: int, b: int,
		yaw_range: PackedFloat64Array, o: int) -> void:
	if not _fit_memo.has(b):
		_fit_memo[b] = {}
	var fits: Dictionary = _fit_memo[b]
	if not fits.has(r_bu):
		fits[r_bu] = content.kit.fitting(r_bu, b)
	var ids: PackedStringArray = fits[r_bu]
	if ids.is_empty():
		out.shells.append({"id": id, "x": x, "y": y, "r": r_bu * s, "kind": "shell", "asset": "", "yaw_deg": 0.0,
			"scale": 1.0, "tint": ""})
		return
	var asset: Dictionary = content.kit.assets[ids[WorldHash.pick(h, ids.size())]]
	var u := WorldHash.unit(WorldHash.mix32(h, 1))
	var yaw := 360.0 * u
	if asset.yaw_rule == "slot" and yaw_range.size() == 2:
		yaw = lerpf(yaw_range[0], yaw_range[1], u)
	var tint := ""
	var dressings: Array = asset.dressings
	if dressings.size() == 1:
		tint = dressings[0].tint   # pick(mix32(h, 2), 1) is 0: the hash is skipped
	elif dressings.size() > 1:
		tint = dressings[WorldHash.pick(WorldHash.mix32(h, 2), dressings.size())].tint
	out.shells.append({"id": id, "x": x, "y": y, "r": r_bu * s, "kind": "shell", "asset": asset.id,
		"yaw_deg": orient_yaw_deg(yaw, o), "scale": r_bu / float(asset.footprint_radius_m), "tint": tint})


## A site's territory and reach disc in its own frame (bu), built once per tile and site: small
## numbers, so the brain's float32 disc is exact enough (a home 100 km out would round to 7.8 mm).
func _site_discs(memo_key: String, site: Dictionary, zone: Dictionary) -> Dictionary:
	if not _disc_memo.has(memo_key):
		var home := Vector2(site.home[0], site.home[1])
		var z := {} if zone.is_empty() else {"center": Vector2(zone.center[0], zone.center[1]), "radius": float(zone.radius)}
		var s := {"species": site.species, "home": home, "heading": float(site.heading)}
		var territory := species.territory_from(s, z) if species != null else {}
		var reach := species.reach_disc_for(s, territory) if species != null else {}
		_disc_memo[memo_key] = {"territory": territory, "reach": reach}
	return _disc_memo[memo_key]


## A site's chunk record: its discs oriented and placed like its home, and the chunks its reach disc
## touches.
func _placed_site(id: String, site: Dictionary, discs: Dictionary, x: float, y: float, cx: float, cy: float, o: int,
		s: float, tile: Vector2i) -> Dictionary:
	var territory := {}
	if not discs.territory.is_empty():
		var p := orient_point(discs.territory.center.x, discs.territory.center.y, o)
		territory = {"x": (cx + p[0]) * s, "y": (cy + p[1]) * s, "radius": float(discs.territory.radius) * s}
	var reach := {}
	var chunks: Array[Vector2i] = []
	if not discs.reach.is_empty():
		var p := orient_point(discs.reach.center.x, discs.reach.center.y, o)
		reach = {"x": (cx + p[0]) * s, "y": (cy + p[1]) * s, "radius": float(discs.reach.radius) * s}
		chunks = disc_chunks(reach.x, reach.y, reach.radius, content.config.chunk_tm)
	var sizes: Array[int] = []
	sizes.assign(site.sizes)
	return {"id": id, "species": site.species, "x": x, "y": y, "heading": orient_heading(float(site.heading), o),
		"territory": territory, "reach": reach, "chunks": chunks, "sizes": sizes, "tile": tile}


## Every chunk whose square a disc touches (the nearest point of the square closer than r), sorted
## by (y, x).
static func disc_chunks(x: float, y: float, r: float, chunk_tm: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ky in range(floori((y - r) / chunk_tm), floori((y + r) / chunk_tm) + 1):
		for kx in range(floori((x - r) / chunk_tm), floori((x + r) / chunk_tm) + 1):
			var dx := x - clampf(x, kx * chunk_tm, (kx + 1) * chunk_tm)
			var dy := y - clampf(y, ky * chunk_tm, (ky + 1) * chunk_tm)
			if dx * dx + dy * dy < r * r:
				out.append(Vector2i(kx, ky))
	return out


# --- the arrangement ---

## {id, region: "sunlit"|"reef"|"drift"|"home"|"rare", rare, set, orientation} of tile (tx, ty) in
## band b: home first, then the block's rare tile, then the ordinary tile of its region and set.
func tile_info(band: int, tx: int, ty: int) -> Dictionary:
	return _tile_ref(band, tx, ty).duplicate()


## The memoised tile info (not a copy: read only).
func _tile_ref(band: int, tx: int, ty: int) -> Dictionary:
	var k := Vector3i(band, tx, ty)
	if not _tile_memo.has(k):
		_tile_memo[k] = _tile_info(band, tx, ty)
	return _tile_memo[k]


func _tile_info(band: int, tx: int, ty: int) -> Dictionary:
	if is_home_tile(tx, ty):
		return {"id": "", "region": HOME, "rare": "", "set": -1, "orientation": 0}
	var rare := _rare_at(band, tx, ty)
	if rare.tile == Vector2i(tx, ty):
		var t: Dictionary = content.tiles.rare_tile(band, rare.kind)
		return {"id": str(t.get("id", "")), "region": RARE, "rare": rare.kind, "set": -1, "orientation": rare.orientation}
	var region := _region(band, tx, ty)
	var set_index := posmod(tx + ty, 2)
	var ids_key := "%d/%s/%d" % [band, region, set_index]
	if not _ids_memo.has(ids_key):
		_ids_memo[ids_key] = content.tiles.ids_of(band, region, set_index)
	var ids: PackedStringArray = _ids_memo[ids_key]
	var h := _key(band, tx, ty, STR_TILE)
	return {"id": ids[h % ids.size()] if not ids.is_empty() else "", "region": region, "rare": "", "set": set_index,
		"orientation": (h / 3) % 8}


## The memoised rare tile of the block holding tile (tx, ty) (not a copy: read only).
func _rare_at(band: int, tx: int, ty: int) -> Dictionary:
	var k := Vector3i(band, fdiv(tx - _block_first, _block_tiles), fdiv(ty - _block_first, _block_tiles))
	if not _rare_memo.has(k):
		_rare_memo[k] = _rare_of_block(band, k.y, k.z)
	return _rare_memo[k]


## Whether tile (tx, ty) is one of the home block's (home_tiles on both axes).
func is_home_tile(tx: int, ty: int) -> bool:
	return tx >= _home_lo and tx <= _home_hi and ty >= _home_lo and ty <= _home_hi


## The rare tile of 6 x 6 block (bx, by): {tile: Vector2i, kind, orientation}. Block (0, 0) holds the
## world file's fixed_rare at orientation 0; any other block's is one of its four central tiles.
func rare_of_block(band: int, bx: int, by: int) -> Dictionary:
	var k := Vector3i(band, bx, by)
	if not _rare_memo.has(k):
		_rare_memo[k] = _rare_of_block(band, bx, by)
	return _rare_memo[k].duplicate()


func _rare_of_block(band: int, bx: int, by: int) -> Dictionary:
	if bx == 0 and by == 0:
		return {"tile": _fixed_tile, "kind": _fixed_kind, "orientation": 0}
	var h := _key(band, bx, by, STR_RARE)
	if not _rare_kinds_memo.has(band):
		_rare_kinds_memo[band] = content.tiles.rare_kinds(band)
	var kinds: PackedStringArray = _rare_kinds_memo[band]
	var tile := Vector2i(_block_first + _block_tiles * bx + 2 + h % 2, _block_first + _block_tiles * by + 2 + (h / 2) % 2)
	return {"tile": tile, "kind": kinds[WorldHash.pick(h / 4, kinds.size())] if not kinds.is_empty() else "",
		"orientation": WorldHash.mix32(h, 3) % 8}


## {tile: Vector2i, model, dressing} of landmark cell (lx, ly) in band b, or {} when it has none:
## one of the cell's ordinary tiles (not home, not rare), a model of the cell's parity group, and a
## dressing (the dressing's id in the kit record).
func landmark_of_cell(band: int, lx: int, ly: int) -> Dictionary:
	var lm := _cell(band, lx, ly).duplicate()
	lm.erase("h")
	return lm


## The memoised landmark of a cell with its hash "h" (not a copy: read only).
func _cell(band: int, lx: int, ly: int) -> Dictionary:
	var k := Vector3i(band, lx, ly)
	if not _cell_memo.has(k):
		_cell_memo[k] = _landmark_of_cell(band, lx, ly)
	return _cell_memo[k]


func _landmark_of_cell(band: int, lx: int, ly: int) -> Dictionary:
	var candidates: Array[Vector2i] = []
	for dy in _cell_tiles:
		for dx in _cell_tiles:
			var t := Vector2i(_cell_tiles * lx + dx, _cell_tiles * ly + dy)
			if not is_home_tile(t.x, t.y) and _rare_at(band, t.x, t.y).tile != t:
				candidates.append(t)
	var group := posmod(lx, 2) + 2 * posmod(ly, 2)
	var models_key := "%d/%d" % [band, group]
	if not _models_memo.has(models_key):
		_models_memo[models_key] = content.kit.landmarks(band, group)
	var models: PackedStringArray = _models_memo[models_key]
	if candidates.is_empty() or models.is_empty():
		return {}
	var h := _key(band, lx, ly, STR_LANDMARK)
	var model := models[WorldHash.pick(WorldHash.mix32(h, 1), models.size())]
	var dressings: Array = content.kit.assets[model].dressings
	var dressing := ""
	if not dressings.is_empty():
		dressing = str(dressings[WorldHash.pick(WorldHash.mix32(h, 2), dressings.size())].id)
	return {"tile": candidates[WorldHash.pick(h, candidates.size())], "model": model, "dressing": dressing, "h": h}


## The final region of an ordinary tile (B-11): the raw region, except that a raw drift tile whose
## column or row is m mod (m + 1), with m = max_drift_run, is sunlit. It reads the tile's own
## coordinates only, so it is route-independent, and every run of m + 1 tiles along a row or column
## holds one such column or row, so no row or column holds more than m final drift tiles running.
func _region(band: int, tx: int, ty: int) -> String:
	var r := _raw(band, tx, ty)
	if r == _drift_index and (posmod(tx, _drift_run + 1) == _drift_run or posmod(ty, _drift_run + 1) == _drift_run):
		return SUNLIT
	return _order[r]


## The raw region index into region_order: value noise (smoothstep between lattice values every
## _period tiles, sampled at tile centres) cut at the two thresholds.
func _raw(band: int, tx: int, ty: int) -> int:
	var i0 := fdiv(tx, _period)
	var j0 := fdiv(ty, _period)
	var fx := (float(tx - i0 * _period) + 0.5) / _period
	var fy := (float(ty - j0 * _period) + 0.5) / _period
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var top := lerpf(_lattice(band, i0, j0), _lattice(band, i0 + 1, j0), sx)
	var bottom := lerpf(_lattice(band, i0, j0 + 1), _lattice(band, i0 + 1, j0 + 1), sx)
	var v := lerpf(top, bottom, sy)
	return 0 if v < _t0 else (1 if v < _t1 else 2)


func _lattice(band: int, i: int, j: int) -> float:
	var k := Vector3i(band, i, j)
	if not _lattice_memo.has(k):
		_lattice_memo[k] = WorldHash.unit(_key(band, i, j, STR_REGION))
	return _lattice_memo[k]


## WorldHash.key with the purpose's str32 precomputed.
func _key(band: int, i: int, j: int, purpose: int) -> int:
	return WorldHash.hash_ints(PackedInt64Array([world_seed, gen_version, band, i, j, purpose]))


## floor(a / n) for ints, exactly (GDScript's int / truncates toward zero).
static func fdiv(a: int, n: int) -> int:
	return (a - posmod(a, n)) / n


# --- orientation (spine 3.6): o in 0..7, mirror m = o >> 2, then k = o & 3 quarter turns ---

## A tile-local point under orientation o: mirrored in x when m, then turned k times by
## (x, y) -> (-y, x). Exact in float64 (negation and swap only).
static func orient_point(x: float, y: float, o: int) -> PackedFloat64Array:
	if (o >> 2) & 1 == 1:
		x = -x
	match o & 3:
		1:
			return PackedFloat64Array([-y, x])
		2:
			return PackedFloat64Array([-x, -y])
		3:
			return PackedFloat64Array([y, -x])
	return PackedFloat64Array([x, y])


## A heading (radians, as Vector2.from_angle reads it) under orientation o, in [-PI, PI).
static func orient_heading(h: float, o: int) -> float:
	if (o >> 2) & 1 == 1:
		h = PI - h
	return wrapf(h + (o & 3) * (PI / 2.0), -PI, PI)


## A visual yaw in degrees (RockField's rotation.y) under orientation o: negated when mirrored, then
## 90 less per quarter turn. With the piece mirrored in its own x first, it lands where orient_point
## puts its points.
static func orient_yaw_deg(yaw: float, o: int) -> float:
	if (o >> 2) & 1 == 1:
		yaw = -yaw
	return yaw - 90.0 * (o & 3)
