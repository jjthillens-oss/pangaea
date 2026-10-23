class_name WorldGen
extends RefCounted
## The endless world's generator (S1): which tile lies where, and what each 32 x 32 tm chunk holds,
## as a pure function of (world_seed, gen_version, content, size, chunk). It binds the seed, the
## generator version and the content at creation (docs/s1/s1-interfaces.md, D-7), reads no clock,
## input, tree or global random numbers, and gives the same chunk along any route.
##
## The arrangement (spine 3.6, docs/s1/s1-core.md 6.4): a value-noise region per tile from a lattice
## every region_period_tiles, the drift swap, the home tiles, one rare tile per 6 x 6 block (block
## (0, 0)'s fixed), a tile id per (region, set) and a landmark per 2 x 2 cell. Every stream is a
## WorldHash of fixed coordinates. Tile infos and lattice values are memoised per instance; clearing
## the memo changes nothing (tests/test_world_gen.gd).
##
## The region rule is the spine's drift swap (core C-15: it ships until the integrator answers core
## question 17.1; the coordinate rule both S1 designs recommend would keep 14.5% drift, not 1.7%).
##
## T1.8: the arrangement. chunk() gives an empty chunk until the chunk content (T1.9) lands.

const HOME := "home"
const RARE := "rare"
const DRIFT := "drift"
const SUNLIT := "sunlit"

# The purposes' str32, computed once (WorldHash: a str32 costs about a microsecond).
static var STR_REGION := WorldHash.str32("region")
static var STR_TILE := WorldHash.str32("tile")
static var STR_RARE := WorldHash.str32("rare")
static var STR_LANDMARK := WorldHash.str32("landmark")

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
## catalog sorts on every call; the content is fixed once bound).
var _ids_memo := {}
var _rare_kinds_memo := {}


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
	clear_memo()
	if p_content == null or p_content.config == null:
		return
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
	_home_lo = int(a.home_tiles[0])
	_home_hi = int(a.home_tiles[1])
	_block_first = int(a.rare_block_first_tile)
	_block_tiles = maxi(1, int(a.rare_block_tiles))
	_cell_tiles = maxi(1, int(a.landmark_cell_tiles))
	_fixed_tile = a.fixed_rare.tile
	_fixed_kind = str(a.fixed_rare.kind)


## Forgets every memoised tile info and lattice value (tests: results must not depend on the memo).
func clear_memo() -> void:
	_tile_memo.clear()
	_lattice_memo.clear()
	_ids_memo.clear()
	_rare_kinds_memo.clear()


## The chunk (cx, cy) at size n: every object whose centre lies in it, in absolute tm.
func chunk(n: int, cx: int, cy: int) -> WorldChunk:
	var out := WorldChunk.new()
	out.key = Vector2i(cx, cy)
	out.size = n
	return out


# --- the arrangement ---

## {id, region: "sunlit"|"reef"|"drift"|"home"|"rare", rare, set, orientation} of tile (tx, ty) in
## band b: home first, then the block's rare tile, then the ordinary tile of its region and set.
func tile_info(band: int, tx: int, ty: int) -> Dictionary:
	var k := Vector3i(band, tx, ty)
	if not _tile_memo.has(k):
		_tile_memo[k] = _tile_info(band, tx, ty)
	return _tile_memo[k].duplicate()


func _tile_info(band: int, tx: int, ty: int) -> Dictionary:
	if is_home_tile(tx, ty):
		return {"id": "", "region": HOME, "rare": "", "set": -1, "orientation": 0}
	var rare := rare_of_block(band, fdiv(tx - _block_first, _block_tiles), fdiv(ty - _block_first, _block_tiles))
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


## Whether tile (tx, ty) is one of the home block's (home_tiles on both axes).
func is_home_tile(tx: int, ty: int) -> bool:
	return tx >= _home_lo and tx <= _home_hi and ty >= _home_lo and ty <= _home_hi


## The rare tile of 6 x 6 block (bx, by): {tile: Vector2i, kind, orientation}. Block (0, 0) holds the
## world file's fixed_rare at orientation 0; any other block's is one of its four central tiles.
func rare_of_block(band: int, bx: int, by: int) -> Dictionary:
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
	var candidates: Array[Vector2i] = []
	for dy in _cell_tiles:
		for dx in _cell_tiles:
			var t := Vector2i(_cell_tiles * lx + dx, _cell_tiles * ly + dy)
			var region: String = tile_info(band, t.x, t.y).region
			if region != HOME and region != RARE:
				candidates.append(t)
	var group := posmod(lx, 2) + 2 * posmod(ly, 2)
	var models := content.kit.landmarks(band, group)
	if candidates.is_empty() or models.is_empty():
		return {}
	var h := _key(band, lx, ly, STR_LANDMARK)
	var model := models[WorldHash.pick(WorldHash.mix32(h, 1), models.size())]
	var dressings: Array = content.kit.assets[model].dressings
	var dressing := ""
	if not dressings.is_empty():
		dressing = str(dressings[WorldHash.pick(WorldHash.mix32(h, 2), dressings.size())].id)
	return {"tile": candidates[WorldHash.pick(h, candidates.size())], "model": model, "dressing": dressing}


## The final region of an ordinary tile: the raw region, with the spine's drift swap (a drift tile
## whose two raw west or two raw north neighbours are drift becomes sunlit). It reads raw neighbours
## only, so it is route-independent, and no row or column holds three final drift tiles running.
func _region(band: int, tx: int, ty: int) -> String:
	var r := _raw(band, tx, ty)
	if r == _drift_index and ((_raw(band, tx - 1, ty) == _drift_index and _raw(band, tx - 2, ty) == _drift_index)
			or (_raw(band, tx, ty - 1) == _drift_index and _raw(band, tx, ty - 2) == _drift_index)):
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
