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
##
## At a band's second size (S2, docs/s2/s2-sim.md 3.10) at_second_size applies: "sink" shells and
## "drop" zones are not generated, and a "thin" zone holds capacity x second_size.zone_thin_share
## (D-60). Reach discs are the species' lengths times k (WorldConfig.k_of, D-39, D-69); a two-post
## site carries `posts` and reaches over their union disc (D-82). Every shell, set-piece and landmark
## `scale` is x s, as its radius is (BP-16). At a band's first size every chunk is S1's, byte for byte.
##
## S3 (docs/s3: spine 5.5, s3-sim 3.11, D-94 to D-97, D-104, D-128, D-138): each band has its own
## arrangement (its region order and fixed rare kind, WorldConfig.arrangement_of); a site is placed by
## its ladder role at the size (TileCatalog.site_role): a threat, rival or prey site as a creature site,
## a morsel site as food in `morsel_sites`, any other not at all; an elder Warden's site and its two
## meadows carry one `bloom` phase hashed from the placed site id; band 1 and up has the cradle where
## band 0 has its home block. The quarter prefilter runs at every band's first size (D-96). Pure
## helpers give the old band's pieces (landmark_piece, rare_piece, old_pool_pieces) exactly where its
## chunks put them, for the scene below a band-up (D-110). Band 0's chunks are unchanged.

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
static var STR_CRADLE := WorldHash.str32("cradle")
static var STR_BLOOM := WorldHash.str32("bloom")
## The roles a placed site may have; anything else ("ghost", "haze", "") is not placed.
const CREATURE_ROLES: PackedStringArray = ["threat", "rival", "prey"]
const MORSEL := "morsel"

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
## "<band>/<tile id or home>/<site id>" -> {territory, reach, posts?} in the tile's (or the block's)
## own frame, bu: content.derived's, per species catalog (k is the band's).
var _disc_memo := {}
## "<tile id>/<o>" -> the tile's objects in its oriented frame (_framed): content.derived's too.
var _frame_memo := {}
## band -> {order, drift_index, fixed_kind} (band 0's are the fields above).
var _band_memo := {}
## "<species>/<n>" -> its ladder role at n as a placed site ("" when not placed).
var _role_memo := {}
## "<band>/<tile id or cradle>/<n>" -> {zone id -> [slot, site id, species]}: the bloom meadows live at n.
var _bloom_memo := {}


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
	for memo in [_tile_memo, _lattice_memo, _cell_memo, _rare_memo, _band_memo, _role_memo, _bloom_memo]:
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
	_band_memo.clear()
	_role_memo.clear()
	_bloom_memo.clear()
	if content != null:
		content.derived.erase("home")
		for b in content.cradles:
			content.derived.erase("cradle/%d" % b)


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
					if b == 0:
						_emit_home(out, n, b, s)
					else:
						_emit_cradle(out, n, b, s)
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
	# At a band's first size a chunk is one quarter of the tile: only the objects that may lie in it
	# are tried (D-96).
	var quarter := -1
	if WorldConfig.bu_to_tm(n) == 1.0:
		quarter = 1 << ((out.key.x - 2 * tx) + 2 * (out.key.y - 2 * ty))
	var second := WorldConfig.is_second_size(n)
	# Shells: a kit asset that fits the slot, a yaw and a dressing per slot from the slot's hash.
	var shell_key := -1
	for e in f.shells:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var sh: Dictionary = t.shells[e.k]
		if second and sh.at_second_size == "sink":
			continue
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		if not _in(out, x, y):
			continue
		if shell_key < 0:
			shell_key = _key(b, tx, ty, STR_SHELL)
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
				"kind": "set_piece", "asset": t.set_piece.asset, "yaw_deg": yaw, "scale": 1.0 * s, "tint": ""})
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
		var z: Dictionary = t.zones[e.k]
		if _in(out, x, y) and not (second and z.at_second_size == "drop"):
			var zone := {"id": "z_%s_%s" % [prefix, z.id], "x": x, "y": y, "radius": float(z.radius) * s,
				"capacity": _capacity(z, second), "growth_rate": float(z.growth_rate), "tile": tile, "region": info.region}
			_mark_bloom(zone, _blooms("%d/%s/%d" % [b, t.id, n], t.sites, n), z.id, "t_%s_" % prefix)
			out.zones.append(zone)
	if not bool(content.config.switches.get("generated_creatures", true)):
		return
	for e in f.sites:
		if quarter > 0 and e.q & quarter == 0:
			continue
		var site: Dictionary = t.sites[e.k]
		var x: float = (cx + e.x) * s
		var y: float = (cy + e.y) * s
		var role := _role(site.species, n) if (site.sizes as Array).has(n) else ""
		if role.is_empty() or not _in(out, x, y):
			continue
		if role == MORSEL:
			out.morsel_sites.append(_morsel_site("m_%s_%s" % [prefix, site.id], "%s/%s" % [t.id, site.id], site.species, x, y, n, tile))
			continue
		var discs := _site_discs("%d/%s/%s" % [b, t.id, site.id], site, TileCatalog._zone(t, site.territory_zone),
			_k(site.species, n), TileCatalog._zone(t, str(site.get("post_b", {}).get("territory_zone", ""))))
		var placed := _placed_site("t_%s_%s" % [prefix, site.id], site, discs, x, y, cx, cy, o, s, tile)
		_mark_site_bloom(placed)
		out.sites.append(placed)


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
	var at: Dictionary = index.chunks.get(out.key, {}) if WorldConfig.bu_to_tm(n) == 1.0 else index.all
	var second := WorldConfig.is_second_size(n)
	var ring_key := -1
	for i in at.get("shells", []):
		var sh: Dictionary = home.shells[i]
		if second and sh.at_second_size == "sink":
			continue
		var x: float = sh.x * s
		var y: float = sh.y * s
		if not _in(out, x, y):
			continue
		if sh.fixed:
			out.shells.append({"id": sh.id, "x": x, "y": y, "r": float(sh.r) * s, "kind": "shell", "asset": sh.asset,
				"yaw_deg": float(sh.yaw_deg), "scale": float(sh.scale) * s, "tint": ""})
			continue
		if ring_key < 0:
			ring_key = _key(b, 0, 0, STR_HOME)
		_append_shell(out, "s_h_%s" % sh.id, x, y, float(sh.r), s, WorldHash.mix32(ring_key, index.ring_k[i]), b,
			sh.yaw_range, 0)
	for i in at.get("zones", []):
		var z: Dictionary = home.zones[i]
		var x: float = z.x * s
		var y: float = z.y * s
		if _in(out, x, y) and not (second and z.at_second_size == "drop"):
			out.zones.append({"id": z.id if z.m1 else "z_h_%s" % z.id, "x": x, "y": y, "radius": float(z.radius) * s,
				"capacity": _capacity(z, second), "growth_rate": float(z.growth_rate), "tile": _home_tile(z.x, z.y),
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
		var post: Dictionary = site.get("post_b", {})
		if not post.is_empty():
			data["post_b"] = post
		var discs := _site_discs("%d/home/%s" % [b, site.id], data, index.zones_by_id.get(site.territory_zone, {}),
			_k(site.species, n), index.zones_by_id.get(str(post.get("territory_zone", "")), {}))
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


## The cradle of band b at the home tiles (D-138), at its own origin, orientation 0: its hashed
## shells ("s_c_<id>"), zones ("z_c_<id>", region home, tile its quadrant, bloom marks) and sites by
## role ("t_c_<id>" creature sites, "m_c_<id>" morsel sites) when generated creatures are on.
func _emit_cradle(out: WorldChunk, n: int, b: int, s: float) -> void:
	var cradle := content.cradle_of(b)
	if cradle == null:
		return
	var index := _cradle_index(b)
	var at: Dictionary = index.chunks.get(out.key, {}) if s == 1.0 else index.all
	var second := WorldConfig.is_second_size(n)
	var shell_key := -1
	for i in at.get("shells", []):
		var sh: Dictionary = cradle.shells[i]
		if second and sh.at_second_size == "sink":
			continue
		var x: float = sh.center[0] * s
		var y: float = sh.center[1] * s
		if not _in(out, x, y):
			continue
		if shell_key < 0:
			shell_key = _key(b, 0, 0, STR_CRADLE)
		_append_shell(out, "s_c_%s" % sh.id, x, y, float(sh.radius), s, WorldHash.mix32(shell_key, i), b, sh.yaw_deg, 0)
	var blooms := _blooms("%d/cradle/%d" % [b, n], cradle.sites, n)
	for i in at.get("zones", []):
		var z: Dictionary = cradle.zones[i]
		var x: float = z.center[0] * s
		var y: float = z.center[1] * s
		if _in(out, x, y) and not (second and z.at_second_size == "drop"):
			var zone := {"id": "z_c_%s" % z.id, "x": x, "y": y, "radius": float(z.radius) * s,
				"capacity": _capacity(z, second), "growth_rate": float(z.growth_rate),
				"tile": CradleBlock.quadrant_of(z.center[0], z.center[1]), "region": HOME}
			_mark_bloom(zone, blooms, z.id, "t_c_")
			out.zones.append(zone)
	if not bool(content.config.switches.get("generated_creatures", true)):
		return
	var block := cradle._block()
	for i in at.get("sites", []):
		var site: Dictionary = cradle.sites[i]
		var role := _role(site.species, n) if (site.sizes as Array).has(n) else ""
		var x: float = site.home[0] * s
		var y: float = site.home[1] * s
		if role.is_empty() or not _in(out, x, y):
			continue
		var tile := CradleBlock.quadrant_of(site.home[0], site.home[1])
		if role == MORSEL:
			out.morsel_sites.append(_morsel_site("m_c_%s" % site.id, "cradle/%s" % site.id, site.species, x, y, n, tile))
			continue
		var discs := _site_discs("%d/cradle/%s" % [b, site.id], site, TileCatalog._zone(block, site.territory_zone),
			_k(site.species, n), TileCatalog._zone(block, str(site.post_b.get("territory_zone", ""))))
		var placed := _placed_site("t_c_%s" % site.id, site, discs, x, y, 0.0, 0.0, 0, s, tile)
		_mark_site_bloom(placed)
		out.sites.append(placed)


## The cradle's lists indexed once per content and band, as _home_index does the home block's.
func _cradle_index(b: int) -> Dictionary:
	var memo_key := "cradle/%d" % b
	if content.derived.has(memo_key):
		return content.derived[memo_key]
	var cradle := content.cradle_of(b)
	var c: float = content.config.chunk_tm
	var index := {"chunks": {}, "all": {"shells": [], "zones": [], "sites": []}}
	for list_name in ["shells", "zones", "sites"]:
		var list: Array = cradle.get(list_name)
		for i in list.size():
			var p: PackedFloat64Array = list[i].home if list_name == "sites" else list[i].center
			var key := Vector2i(floori(p[0] / c), floori(p[1] / c))
			if not index.chunks.has(key):
				index.chunks[key] = {"shells": [], "zones": [], "sites": []}
			index.chunks[key][list_name].append(i)
			index.all[list_name].append(i)
	content.derived[memo_key] = index
	return index


## A species' role as a placed site at size n (TileCatalog.site_role without the site's sizes):
## threat, rival, prey or morsel, else "" (not placed). Without a species catalog every site is a
## creature site, as before S3.
func _role(species_id: String, n: int) -> String:
	if species == null:
		return "threat"
	var memo_key := "%s/%d" % [species_id, n]
	if not _role_memo.has(memo_key):
		var role := ""
		if species.species.has(species_id) and n >= species.entry_size(species_id):
			role = Relationships.ladder_role(species.entry_size(species_id), n, species.radius_at(species_id, n),
				species.share_tolerance())
			if not (CREATURE_ROLES.has(role) or role == MORSEL):
				role = ""
		_role_memo[memo_key] = role
	return _role_memo[memo_key]


## A morsel site's record (spine 5.6, s3-sim 3.11): food, not a creature. r is the species' radius at
## n (tm); the item is r, at most growth.remnants.morsel_max_radius_tm, and holds carcass.energy x r /
## the player's radius (X3-23).
func _morsel_site(id: String, key: String, species_id: String, x: float, y: float, n: int, tile: Vector2i) -> Dictionary:
	var r := species.radius_at(species_id, n)
	var energy := float(species.species[species_id].get("carcass", {}).get("energy", 0.0))
	return {"id": id, "key": key, "species": species_id, "x": x, "y": y, "tile": tile,
		"radius": minf(r, content.tiles.morsel_max_radius_tm), "energy": energy * r / Relationships.PLAYER_RADIUS}


## The bloom meadows of `sites` live at n (D-104, D-128): {zone id -> [slot, site id, species]}, slot 0 the
## site's territory_zone and slot 1 its post_b's, for each site whose habit blooms and that is a
## creature site at n. Memoised under `memo_key`.
func _blooms(memo_key: String, sites: Array, n: int) -> Dictionary:
	if _bloom_memo.has(memo_key):
		return _bloom_memo[memo_key]
	var out := {}
	if species != null:
		for site in sites:
			if not (site.sizes as Array).has(n) or not CREATURE_ROLES.has(_role(site.species, n)) \
					or str(species.habit_of(site.species).get("post_switch", "")) != "bloom":
				continue
			out[str(site.territory_zone)] = [0, site.id, site.species]
			var zone_b := str(site.get("post_b", {}).get("territory_zone", ""))
			if not zone_b.is_empty():
				out[zone_b] = [1, site.id, site.species]
	_bloom_memo[memo_key] = out
	return out


## The bloom phase of a placed site: {offset_ticks, cycle_ticks}, the offset hashed from the placed
## id (X3-12), so two placements of one tile bloom out of step.
func _bloom_phase(placed_id: String, species_id: String) -> Dictionary:
	var cycle := CreatureBrain.ticks(species.habit_of(species_id).bloom_cycle_s)
	var h := WorldHash.hash_ints(PackedInt64Array([world_seed, gen_version, WorldHash.str32(placed_id), STR_BLOOM]))
	return {"offset_ticks": h % cycle, "cycle_ticks": cycle}


## Marks a placed zone record with its meadow's bloom {slot, offset_ticks, cycle_ticks} when `blooms`
## names it; the phase is its site's (placed id `site_prefix` + the site id).
func _mark_bloom(zone: Dictionary, blooms: Dictionary, zone_id: String, site_prefix: String) -> void:
	if not blooms.has(zone_id):
		return
	var meadow: Array = blooms[zone_id]
	var phase := _bloom_phase(site_prefix + str(meadow[1]), str(meadow[2]))
	zone["bloom"] = {"slot": int(meadow[0]), "offset_ticks": phase.offset_ticks, "cycle_ticks": phase.cycle_ticks}


## Gives a placed creature site whose habit blooms its bloom phase.
func _mark_site_bloom(placed: Dictionary) -> void:
	if species != null and str(species.habit_of(placed.species).get("post_switch", "")) == "bloom":
		placed["bloom"] = _bloom_phase(placed.id, placed.species)


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
		"asset": lm.model, "yaw_deg": yaw, "scale": float(dressing.get("scale", 1.0)) * s, "tint": str(dressing.get("tint", ""))})
	out.anchors.append({"id": "a_%d_%d_%d" % [b, lx, ly], "x": x, "y": y, "model": lm.model, "dressing": lm.dressing,
		"tile": tile})


## Appends a shell slot's shell: its asset (one of the kit's fitting shells), yaw (free, or within
## the slot's range for a "slot" asset; then oriented by o) and dressing tint from the slot's hash h,
## at scale radius / footprint (x s: the radius in tm over the footprint, BP-16).
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
			"scale": 1.0 * s, "tint": ""})
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
		"yaw_deg": orient_yaw_deg(yaw, o), "scale": r_bu / float(asset.footprint_radius_m) * s, "tint": tint})


## A site's territory and reach disc in its own frame (bu), built once per band, tile and site: small
## numbers, so the brain's float32 disc is exact enough (a home 100 km out would round to 7.8 mm).
## k is the band's (_k). A two-post site (post_b, its zone `zone_b`) reaches over the union of its
## posts' discs (SpeciesCatalog.two_post_disc_for) and keeps each post's territory in "posts".
func _site_discs(memo_key: String, site: Dictionary, zone: Dictionary, k := 1.0, zone_b := {}) -> Dictionary:
	if not _disc_memo.has(memo_key):
		var home := Vector2(site.home[0], site.home[1])
		var s := {"species": site.species, "home": home, "heading": float(site.heading)}
		var territory := species.territory_from(s, _circle(zone)) if species != null else {}
		var post: Dictionary = site.get("post_b", {})
		if post.is_empty() or species == null:
			var reach := species.reach_disc_for(s, territory, k) if species != null else {}
			_disc_memo[memo_key] = {"territory": territory, "reach": reach}
		else:
			var territory_b := species.territory_from(s, _circle(zone_b))
			var both := species.two_post_disc_for(s, territory, {"home": Vector2(post.home[0], post.home[1]),
				"heading": float(post.heading)}, territory_b, k)
			var reach := {} if both.is_empty() else {"center": both.center, "radius": both.radius}
			_disc_memo[memo_key] = {"territory": territory, "reach": reach, "posts": [territory, territory_b]}
	return _disc_memo[memo_key]


## A zone's {center: Vector2, radius} for SpeciesCatalog.territory_from ({} for none).
static func _circle(zone: Dictionary) -> Dictionary:
	return {} if zone.is_empty() else {"center": Vector2(zone.center[0], zone.center[1]), "radius": float(zone.radius)}


## k for a site of `species_id` at size n (D-39): 1 for an entry-size-1 species in band 0.
func _k(species_id: String, n: int) -> float:
	return WorldConfig.k_of(species.entry_size(species_id), n) if species != null else 1.0


## A zone's capacity at the size: x second_size.zone_thin_share for a "thin" zone at a band's second
## size (D-60), else its own.
func _capacity(z: Dictionary, second: bool) -> float:
	if second and z.at_second_size == "thin":
		return float(z.capacity) * float(content.config.second_size.zone_thin_share)
	return float(z.capacity)


## A site's chunk record: its discs oriented and placed like its home, and the chunks its reach disc
## touches. A two-post site also gets `posts`: [{x, y, heading, territory}] for its two posts, each
## placed and oriented like the home (the first post is the home), its reach the union disc.
func _placed_site(id: String, site: Dictionary, discs: Dictionary, x: float, y: float, cx: float, cy: float, o: int,
		s: float, tile: Vector2i) -> Dictionary:
	var territory := _placed_disc(discs.territory, cx, cy, o, s)
	var reach := _placed_disc(discs.reach, cx, cy, o, s)
	var chunks: Array[Vector2i] = []
	if not reach.is_empty():
		chunks = disc_chunks(reach.x, reach.y, reach.radius, content.config.chunk_tm)
	var sizes: Array[int] = []
	sizes.assign(site.sizes)
	var heading := orient_heading(float(site.heading), o)
	var out := {"id": id, "species": site.species, "x": x, "y": y, "heading": heading,
		"territory": territory, "reach": reach, "chunks": chunks, "sizes": sizes, "tile": tile}
	if discs.has("posts"):
		var post: Dictionary = site.post_b
		var p := orient_point(post.home[0], post.home[1], o)
		out["posts"] = [{"x": x, "y": y, "heading": heading, "territory": territory},
			{"x": (cx + p[0]) * s, "y": (cy + p[1]) * s, "heading": orient_heading(float(post.heading), o),
				"territory": _placed_disc(discs.posts[1], cx, cy, o, s)}]
	return out


## A disc ({center: Vector2, radius} bu in the tile's frame, or {}) oriented and placed: {x, y,
## radius} in absolute tm, or {}.
static func _placed_disc(disc: Dictionary, cx: float, cy: float, o: int, s: float) -> Dictionary:
	if disc.is_empty():
		return {}
	var p := orient_point(disc.center.x, disc.center.y, o)
	return {"x": (cx + p[0]) * s, "y": (cy + p[1]) * s, "radius": float(disc.radius) * s}


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
		return {"tile": _fixed_tile, "kind": _band_arr(band).fixed_kind, "orientation": 0}
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


# --- the old band's pieces (S3, D-110): pure, in absolute bu of their band ---

## The landmark of cell (lx, ly) in band b where its chunks place it, or {} when the cell has none:
## {id "a_<b>_<lx>_<ly>", model, dressing, x_bu, y_bu, yaw_deg, scale, collide_r_bu, tile}. At a size n
## of the band, x_bu and y_bu x bu_to_tm(n) are the chunk's anchor (and landmark shell) position, the
## yaw is the shell's, and scale x bu_to_tm(n) its scale (S3G29).
func landmark_piece(band: int, lx: int, ly: int) -> Dictionary:
	var lm := _cell(band, lx, ly)
	if lm.is_empty():
		return {}
	var info := _tile_ref(band, lm.tile.x, lm.tile.y)
	var t: Dictionary = content.tiles.tiles.get(info.id, {})
	if t.is_empty() or t.landmark_anchor.size() != 2:
		return {}
	var o: int = info.orientation
	var p := orient_point(t.landmark_anchor[0], t.landmark_anchor[1], o)
	var model: Dictionary = content.kit.assets.get(lm.model, {})
	var dressing := {}
	for d in model.get("dressings", []):
		if d.id == lm.dressing:
			dressing = d
	var h := WorldHash.mix32(lm.h, 3)
	var yaw := 360.0 * WorldHash.unit(h)
	if model.get("yaw_rule", "") == "steps_90":
		yaw = orient_yaw_deg(90.0 * WorldHash.pick(h, 4), o)
	return {"id": "a_%d_%d_%d" % [band, lx, ly], "model": lm.model, "dressing": lm.dressing,
		"x_bu": TileCatalog.HALF_TILE_BU * (2 * lm.tile.x + 1) + p[0], "y_bu": TileCatalog.HALF_TILE_BU * (2 * lm.tile.y + 1) + p[1],
		"yaw_deg": yaw, "scale": float(dressing.get("scale", 1.0)), "collide_r_bu": content.kit.collide_radius_bu, "tile": lm.tile}


## The rare place of 6 x 6 block (bx, by) in band b where its chunks place it, or {}: {id
## "p_<b>_<tx>_<ty>", kind, asset, x_bu, y_bu, yaw_deg, mirror, orientation, tile}, as landmark_piece.
func rare_piece(band: int, bx: int, by: int) -> Dictionary:
	var rare := rare_of_block(band, bx, by)
	if str(rare.kind).is_empty() or is_home_tile(rare.tile.x, rare.tile.y):
		return {}
	var t: Dictionary = content.tiles.rare_tile(band, rare.kind)
	if t.is_empty() or t.set_piece.is_empty() or t.set_piece.center.size() != 2:
		return {}
	var o: int = rare.orientation
	var p := orient_point(t.set_piece.center[0], t.set_piece.center[1], o)
	return {"id": "p_%d_%d_%d" % [band, rare.tile.x, rare.tile.y], "kind": rare.kind, "asset": t.set_piece.asset,
		"x_bu": TileCatalog.HALF_TILE_BU * (2 * rare.tile.x + 1) + p[0], "y_bu": TileCatalog.HALF_TILE_BU * (2 * rare.tile.y + 1) + p[1],
		"yaw_deg": orient_yaw_deg(float(t.set_piece.yaw_deg), o), "mirror": (o >> 2) & 1 == 1, "orientation": o, "tile": rare.tile}


## Band 0's home block as its chunks draw it at size 1: the M1 pool's rocks, then the ring shells,
## each {id, asset, x_bu, y_bu, r_bu, yaw_deg, scale} (the cradle draws them sunk, D-95; C3V-8).
func old_pool_pieces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if content == null or content.home == null:
		return out
	var index := _home_index()
	var ring_key := _key(0, 0, 0, STR_HOME)
	var drawn := WorldChunk.new()
	for i in content.home.shells.size():
		var sh: Dictionary = content.home.shells[i]
		if sh.fixed:
			out.append({"id": sh.id, "asset": sh.asset, "x_bu": float(sh.x), "y_bu": float(sh.y), "r_bu": float(sh.r),
				"yaw_deg": float(sh.yaw_deg), "scale": float(sh.scale)})
			continue
		_append_shell(drawn, "s_h_%s" % sh.id, sh.x, sh.y, float(sh.r), 1.0, WorldHash.mix32(ring_key, index.ring_k[i]), 0,
			sh.yaw_range, 0)
		var d: Dictionary = drawn.shells.back()
		out.append({"id": d.id, "asset": d.asset, "x_bu": d.x, "y_bu": d.y, "r_bu": d.r, "yaw_deg": d.yaw_deg, "scale": d.scale})
	return out


## The landmark cells (cell_tiles x cell_tiles tiles of tile_bu) whose squares meet `rect_bu`, sorted
## by (y, x).
static func landmark_cells_touching(rect_bu: Rect2, cell_tiles: int, tile_bu: float) -> Array[Vector2i]:
	return _squares_touching(rect_bu, cell_tiles * tile_bu, 0.0)


## The rare blocks (block_tiles x block_tiles tiles from tile first_tile) whose squares meet `rect_bu`,
## sorted by (y, x).
static func rare_blocks_touching(rect_bu: Rect2, block_tiles: int, first_tile: int, tile_bu: float) -> Array[Vector2i]:
	return _squares_touching(rect_bu, block_tiles * tile_bu, first_tile * tile_bu)


static func _squares_touching(rect: Rect2, side: float, origin: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for j in range(floori((rect.position.y - origin) / side), floori((rect.end.y - origin) / side) + 1):
		for i in range(floori((rect.position.x - origin) / side), floori((rect.end.x - origin) / side) + 1):
			out.append(Vector2i(i, j))
	return out


## The final region of an ordinary tile (B-11): the raw region, except that a raw drift tile whose
## column or row is m mod (m + 1), with m = max_drift_run, is sunlit. It reads the tile's own
## coordinates only, so it is route-independent, and every run of m + 1 tiles along a row or column
## holds one such column or row, so no row or column holds more than m final drift tiles running.
func _region(band: int, tx: int, ty: int) -> String:
	var r := _raw(band, tx, ty)
	var arr := _band_arr(band)
	if r == arr.drift_index and (posmod(tx, _drift_run + 1) == _drift_run or posmod(ty, _drift_run + 1) == _drift_run):
		return SUNLIT
	return arr.order[r]


## Band b's region order, drift index (-1: no drift, so no swap) and fixed rare kind, from
## WorldConfig.arrangement_of (S3): band 0's are the fields setup() read, so its tiles are S1's.
func _band_arr(band: int) -> Dictionary:
	if not _band_memo.has(band):
		if band == 0 or content == null or content.config == null:
			_band_memo[band] = {"order": _order, "drift_index": _drift_index, "fixed_kind": _fixed_kind}
		else:
			var a := content.config.arrangement_of(band)
			var order := PackedStringArray(a.get("region_order", []))
			_band_memo[band] = {"order": order, "drift_index": order.find(DRIFT),
				"fixed_kind": str(a.get("fixed_rare", {}).get("kind", ""))}
	return _band_memo[band]


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
