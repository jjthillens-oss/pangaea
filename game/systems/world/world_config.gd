class_name WorldConfig
extends RefCounted
## The endless world's settings (game/data/world_cell.json, S1): the mode, the size ladder's units,
## the streaming rings and caps, the floating origin, the tile arrangement and where the content
## lives. Plain data plus checks of the data itself (docs/s1/s1-interfaces.md, section 4.1).
##
## Also the schema helper the four world loaders share (world_cell, placement kit, tiles, home
## block): every file refuses unknown and missing keys, and every problem names its JSON path, as
## "world_cell.rings_tm.foo: unknown key". Numbers are JSON numbers (JSON parses every number as a
## float), and a whole number must have no fraction.
##
## The S1 code assumes the units (rule 3) and the arrangement's grid (rule 7), so those are refused
## when they differ, and the checks that build on them use the constants below.

const DEFAULT_PATH := "res://game/data/world_cell.json"
const SCHEMA_VERSION := 1
const MODES: PackedStringArray = ["pool", "endless"]
const STATUSES: PackedStringArray = ["PROPOSED", "APPROVED"]
const FILE_NAME := "world_cell"
const HEADER_KEYS: PackedStringArray = ["schema_version", "status", "note"]
const TOP_KEYS: PackedStringArray = ["schema_version", "status", "note", "mode", "gen_version", "sizes", "units",
	"rings_tm", "caps", "origin", "arrangement", "content", "switches"]
const SIZES_KEYS: PackedStringArray = ["start", "max_in_build"]
const UNITS_KEYS: PackedStringArray = ["growth_factor", "band_factor", "tile_bu", "chunk_tm"]
## Inner to outer: every ring lies strictly outside the one before it (rule 4).
const RING_KEYS: PackedStringArray = ["mirror", "view", "wake", "sleep", "food", "load", "unload"]
const CAP_KEYS: PackedStringArray = ["awake", "sleepers", "food_items", "food_per_zone", "chunks", "view_set_chunks",
	"loads_per_tick"]
const ORIGIN_KEYS: PackedStringArray = ["rebase_beyond_tm", "rebase_step_tm", "local_bound_tm"]
const ARRANGEMENT_KEYS: PackedStringArray = ["region_period_tiles", "region_order", "region_thresholds", "max_drift_run",
	"landmark_cell_tiles", "rare_block_tiles", "rare_block_first_tile", "home_tiles", "fixed_rare"]
const FIXED_RARE_KEYS: PackedStringArray = ["tile", "kind"]
const CONTENT_KEYS: PackedStringArray = ["home", "tiles", "kit"]
const SWITCH_KEYS: PackedStringArray = ["generated_creatures"]
const REGIONS: PackedStringArray = ["drift", "sunlit", "reef"]

# The numbers the S1 code is written for (rules 3 and 7).
const GROWTH_FACTOR := 1.6     ## tm grows by this per size (plan A.1)
const BAND_FACTOR := 2.56      ## bu grows by this per band: GROWTH_FACTOR squared, two sizes a band
const TILE_BU := 64.0
const CHUNK_TM := 32.0
const MAX_SIZE := 10
const S1_MAX_SIZE := 1         ## a larger size needs growth, which is S2
const MAX_DRIFT_RUN := 2
const LANDMARK_CELL_TILES := 2
const RARE_BLOCK_TILES := 6
const RARE_BLOCK_FIRST_TILE := -3
const HOME_TILES := [-1, 0]
## rings: sleep stays this far beyond wake, so a creature does not flip between them every tick.
const MIN_SLEEP_GAP_TM := 2.0

## Problems found while reading (unknown or missing keys, wrong kinds, an unknown --world mode).
## validate() reports them first.
var load_problems := PackedStringArray()
var mode := "endless"
var gen_version := 1
var size_start := 1
var max_size_in_build := 1
var growth_factor := 1.6
var band_factor := 2.56
var tile_bu := 64.0
var chunk_tm := 32.0
## "mirror", "view", "wake", "sleep", "food", "load", "unload" -> float tm
var rings := {}
## "awake", "sleepers", "food_items", "food_per_zone", "chunks", "view_set_chunks", "loads_per_tick" -> int
var caps := {}
var rebase_beyond_tm := 96.0
var rebase_step_tm := 32.0
var local_bound_tm := 256.0
## {"region_period_tiles": int, "region_order": PackedStringArray, "region_thresholds": PackedFloat64Array,
##  "max_drift_run": int, "landmark_cell_tiles": int, "rare_block_tiles": int, "rare_block_first_tile": int,
##  "home_tiles": Array[int] (two), "fixed_rare": {"tile": Vector2i, "kind": String}}
var arrangement := {}
## {"home": String, "tiles": {band String -> dir String}, "kit": String}, res:// paths
var content := {}
## {"generated_creatures": bool}
var switches := {}


## Never null: a missing or unreadable file gives a config whose validate() says why.
static func load_from(path: String = DEFAULT_PATH) -> WorldConfig:
	var data: Variant = read_json(path)
	if data == null:
		var broken := WorldConfig.new()
		broken.load_problems.append("%s: missing or not readable JSON" % path.get_file())
		return broken
	return from_dict(data)


static func from_dict(data: Variant) -> WorldConfig:
	var config := WorldConfig.new()
	var problems := config.load_problems
	var w := FILE_NAME
	problems.append_array(schema_problems(w, data, TOP_KEYS))
	if not data is Dictionary:
		return config
	header_check(w, data, problems)
	config.mode = text_at(w, data, "mode", problems)
	config.gen_version = int(number_at(w, data, "gen_version", problems, true))

	var sizes := object_at(w, data, "sizes", SIZES_KEYS, problems)
	config.size_start = int(number_at(w + ".sizes", sizes, "start", problems, true))
	config.max_size_in_build = int(number_at(w + ".sizes", sizes, "max_in_build", problems, true))

	var units := object_at(w, data, "units", UNITS_KEYS, problems)
	config.growth_factor = number_at(w + ".units", units, "growth_factor", problems)
	config.band_factor = number_at(w + ".units", units, "band_factor", problems)
	config.tile_bu = number_at(w + ".units", units, "tile_bu", problems)
	config.chunk_tm = number_at(w + ".units", units, "chunk_tm", problems)

	var ring_data := object_at(w, data, "rings_tm", RING_KEYS, problems)
	for key in RING_KEYS:
		config.rings[key] = number_at(w + ".rings_tm", ring_data, key, problems)
	var cap_data := object_at(w, data, "caps", CAP_KEYS, problems)
	for key in CAP_KEYS:
		config.caps[key] = int(number_at(w + ".caps", cap_data, key, problems, true))

	var origin := object_at(w, data, "origin", ORIGIN_KEYS, problems)
	config.rebase_beyond_tm = number_at(w + ".origin", origin, "rebase_beyond_tm", problems)
	config.rebase_step_tm = number_at(w + ".origin", origin, "rebase_step_tm", problems)
	config.local_bound_tm = number_at(w + ".origin", origin, "local_bound_tm", problems)

	config.arrangement = _read_arrangement(w + ".arrangement", object_at(w, data, "arrangement", ARRANGEMENT_KEYS, problems), problems)

	var content_data := object_at(w, data, "content", CONTENT_KEYS, problems)
	var tile_dirs := {}
	var raw_tiles: Variant = content_data.get("tiles")
	if raw_tiles is Dictionary:
		for band in _sorted(raw_tiles.keys()):
			tile_dirs[str(band)] = text_at(w + ".content.tiles", raw_tiles, band, problems)
	elif content_data.has("tiles"):
		problems.append("%s.content.tiles: must be an object" % w)
	config.content = {"home": text_at(w + ".content", content_data, "home", problems), "tiles": tile_dirs,
		"kit": text_at(w + ".content", content_data, "kit", problems)}

	var switch_data := object_at(w, data, "switches", SWITCH_KEYS, problems)
	config.switches = {"generated_creatures": flag_at(w + ".switches", switch_data, "generated_creatures", problems)}
	return config


static func _read_arrangement(w: String, a: Dictionary, problems: PackedStringArray) -> Dictionary:
	var order := PackedStringArray()
	var raw_order: Variant = a.get("region_order")
	if raw_order is Array:
		for v in raw_order:
			order.append(str(v))
	elif a.has("region_order"):
		problems.append("%s.region_order: must be a list" % w)
	var thresholds := PackedFloat64Array()
	var raw_thresholds: Variant = a.get("region_thresholds")
	if raw_thresholds is Array:
		for i in raw_thresholds.size():
			thresholds.append(number_at(w + ".region_thresholds", {str(i): raw_thresholds[i]}, str(i), problems))
	elif a.has("region_thresholds"):
		problems.append("%s.region_thresholds: must be a list" % w)
	var home := pair_at(w, a, "home_tiles", problems)
	var fixed := object_at(w, a, "fixed_rare", FIXED_RARE_KEYS, problems)
	var fixed_tile := pair_at(w + ".fixed_rare", fixed, "tile", problems)
	for pair in [[home, "home_tiles"], [fixed_tile, "fixed_rare.tile"]]:
		var p: PackedFloat64Array = pair[0]
		if p.size() == 2 and (fposmod(p[0], 1.0) != 0.0 or fposmod(p[1], 1.0) != 0.0):
			problems.append("%s.%s: must be two whole numbers" % [w, pair[1]])
	return {
		"region_period_tiles": int(number_at(w, a, "region_period_tiles", problems, true)),
		"region_order": order,
		"region_thresholds": thresholds,
		"max_drift_run": int(number_at(w, a, "max_drift_run", problems, true)),
		"landmark_cell_tiles": int(number_at(w, a, "landmark_cell_tiles", problems, true)),
		"rare_block_tiles": int(number_at(w, a, "rare_block_tiles", problems, true)),
		"rare_block_first_tile": int(number_at(w, a, "rare_block_first_tile", problems, true)),
		"home_tiles": [int(home[0]), int(home[1])] if home.size() == 2 else [0, 0],
		"fixed_rare": {"tile": Vector2i(int(fixed_tile[0]), int(fixed_tile[1])) if fixed_tile.size() == 2 else Vector2i.ZERO,
			"kind": text_at(w + ".fixed_rare", fixed, "kind", problems)},
	}


## Problems with the data itself; empty when the world can run. Reading problems come back alone,
## since the rules cannot be judged on values that did not read.
func validate() -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var w := FILE_NAME
	# Rule 1: the mode and the generator version.
	if not MODES.has(mode):
		errors.append("%s.mode: '%s' is not one of %s" % [w, mode, ", ".join(MODES)])
	if gen_version < 1:
		errors.append("%s.gen_version: must be 1 or more (%d)" % [w, gen_version])

	# Rule 2: the sizes this build can reach.
	if size_start != 1:
		errors.append("%s.sizes.start: must be 1 (%d)" % [w, size_start])
	if max_size_in_build < 1 or max_size_in_build > MAX_SIZE:
		errors.append("%s.sizes.max_in_build: must be 1 to %d (%d)" % [w, MAX_SIZE, max_size_in_build])
	elif max_size_in_build > S1_MAX_SIZE:
		errors.append("%s.sizes.max_in_build: size %d needs growth (S2)" % [w, max_size_in_build])

	# Rule 3: the units the S1 code assumes.
	for pair in [["growth_factor", growth_factor, GROWTH_FACTOR], ["band_factor", band_factor, BAND_FACTOR],
			["tile_bu", tile_bu, TILE_BU], ["chunk_tm", chunk_tm, CHUNK_TM]]:
		if pair[1] != pair[2]:
			errors.append("%s.units.%s: must be %s (the S1 code assumes it), not %s" % [w, pair[0], pair[2], pair[1]])

	# Rule 4: the rings rise strictly, with room between wake and sleep and between load and unload.
	var rising := float(rings.mirror) > 0.0
	for i in range(1, RING_KEYS.size()):
		rising = rising and float(rings[RING_KEYS[i]]) > float(rings[RING_KEYS[i - 1]])
	if not rising:
		errors.append("%s.rings_tm: must rise strictly, 0 < %s" % [w, " < ".join(RING_KEYS)])
	else:
		if float(rings.sleep) - float(rings.wake) < MIN_SLEEP_GAP_TM:
			errors.append("%s.rings_tm.sleep: must lie %.1f tm or more beyond wake" % [w, MIN_SLEEP_GAP_TM])
		if float(rings.unload) - float(rings.load) < CHUNK_TM / 2.0:
			errors.append("%s.rings_tm.unload: must lie %.1f tm (half a chunk) or more beyond load" % [w, CHUNK_TM / 2.0])

	# Rule 5: the caps.
	if caps.awake < 1:
		errors.append("%s.caps.awake: must be 1 or more" % w)
	if caps.sleepers < caps.awake:
		errors.append("%s.caps.sleepers: must be at least caps.awake" % w)
	if caps.food_per_zone < 1 or caps.food_per_zone > caps.food_items:
		errors.append("%s.caps.food_per_zone: must be 1 to caps.food_items" % w)
	if caps.view_set_chunks < 9:
		errors.append("%s.caps.view_set_chunks: must be 9 or more (the 3 x 3 around the cell)" % w)
	if caps.chunks < 32:
		errors.append("%s.caps.chunks: must be 32 or more (a 72 tm disc touches up to 32)" % w)
	if caps.loads_per_tick < 1:
		errors.append("%s.caps.loads_per_tick: must be 1 or more" % w)

	# Rule 6: the floating origin keeps every local position inside the bound.
	if rebase_step_tm != CHUNK_TM:
		errors.append("%s.origin.rebase_step_tm: must equal chunk_tm (%s)" % [w, CHUNK_TM])
	var farthest := rebase_beyond_tm + float(rings.unload) + CHUNK_TM * sqrt(2.0)
	if not (farthest < local_bound_tm):
		errors.append("%s.origin.local_bound_tm: rebase_beyond_tm + unload + chunk_tm x sqrt 2 (%.2f) must be below it (%.2f)"
			% [w, farthest, local_bound_tm])

	# Rule 7: the arrangement.
	_check_arrangement(w + ".arrangement", errors)

	# Rule 8: the content paths.
	for key in ["home", "kit"]:
		_check_path("%s.content.%s" % [w, key], str(content[key]), false, errors)
	var tile_dirs: Dictionary = content.tiles
	# Every band the build can reach needs its tiles (judged on the sizes only when rule 2 holds).
	var top := max_size_in_build if size_start == 1 and max_size_in_build >= 1 and max_size_in_build <= S1_MAX_SIZE else 1
	for band in range(band_of(1), band_of(top) + 1):
		if not tile_dirs.has(str(band)):
			errors.append("%s.content.tiles.%d: missing (band %d is reachable)" % [w, band, band])
	for band in _sorted(tile_dirs.keys()):
		if not (str(band).is_valid_int() and int(band) >= 0):
			errors.append("%s.content.tiles.%s: a band must be a whole number of 0 or more" % [w, band])
		_check_path("%s.content.tiles.%s" % [w, band], str(tile_dirs[band]), true, errors)
	# Rule 9 (switches are bools) is a reading rule: from_dict refuses anything else.
	return errors


func _check_arrangement(w: String, errors: PackedStringArray) -> void:
	var a := arrangement
	if int(a.region_period_tiles) < 1:
		errors.append("%s.region_period_tiles: must be 1 or more" % w)
	var order: PackedStringArray = a.region_order
	var sorted_order := Array(order)
	sorted_order.sort()
	var regions := Array(REGIONS)
	regions.sort()
	if sorted_order != regions:
		errors.append("%s.region_order: must be a permutation of %s" % [w, ", ".join(REGIONS)])
	var t: PackedFloat64Array = a.region_thresholds
	if t.size() != 2 or not (0.0 < t[0] and t[0] < t[1] and t[1] < 1.0):
		errors.append("%s.region_thresholds: must be two numbers rising strictly within (0, 1)" % w)
	for pair in [["max_drift_run", MAX_DRIFT_RUN], ["landmark_cell_tiles", LANDMARK_CELL_TILES],
			["rare_block_tiles", RARE_BLOCK_TILES], ["rare_block_first_tile", RARE_BLOCK_FIRST_TILE]]:
		if int(a[pair[0]]) != pair[1]:
			errors.append("%s.%s: must be %d (the S1 code assumes it)" % [w, pair[0], pair[1]])
	if int(a.home_tiles[0]) != HOME_TILES[0] or int(a.home_tiles[1]) != HOME_TILES[1]:
		errors.append("%s.home_tiles: must be %s (the S1 code assumes it)" % [w, HOME_TILES])
	var fixed: Vector2i = a.fixed_rare.tile
	var last := RARE_BLOCK_FIRST_TILE + RARE_BLOCK_TILES - 1
	if fixed.x < RARE_BLOCK_FIRST_TILE or fixed.x > last or fixed.y < RARE_BLOCK_FIRST_TILE or fixed.y > last:
		errors.append("%s.fixed_rare.tile: %s is outside block (0, 0) (tiles %d to %d)" % [w, fixed, RARE_BLOCK_FIRST_TILE, last])
	elif HOME_TILES.has(fixed.x) and HOME_TILES.has(fixed.y):
		errors.append("%s.fixed_rare.tile: %s is a home tile" % [w, fixed])
	if str(a.fixed_rare.kind).is_empty():
		errors.append("%s.fixed_rare.kind: must name a rare kind" % w)


static func _check_path(where: String, path: String, is_dir: bool, errors: PackedStringArray) -> void:
	if not path.begins_with("res://"):
		errors.append("%s: '%s' must begin with res://" % [where, path])
	elif is_dir and not DirAccess.dir_exists_absolute(path):
		errors.append("%s: the directory '%s' does not exist" % [where, path])
	elif not is_dir and not FileAccess.file_exists(path):
		errors.append("%s: the file '%s' does not exist" % [where, path])


## A copy with the mode overridden (the --world flag). "" keeps the file's own mode. An unknown mode
## keeps it too and becomes a reading problem, so the session refuses to start instead of guessing.
func with_mode(p_mode: String) -> WorldConfig:
	var copy := WorldConfig.new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = get(property.name)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			elif value is PackedStringArray:
				value = value.duplicate()
			copy.set(property.name, value)
	if p_mode.is_empty():
		return copy
	if MODES.has(p_mode):
		copy.mode = p_mode
	else:
		copy.load_problems.append("%s.mode: the --world mode '%s' is not one of %s" % [FILE_NAME, p_mode, ", ".join(MODES)])
	return copy


## How many tm one bu is at size n: pow(band_factor, band_of(n)) / pow(growth_factor, n - 1). Since
## band_factor is growth_factor squared and a band spans two sizes, that is 1 at a band's first size
## and 1 / growth_factor at its second, written so the float64 result is exact (1.0 and 0.625).
static func bu_to_tm(n: int) -> float:
	return 1.0 if posmod(n - 1, 2) == 0 else 1.0 / GROWTH_FACTOR


## The band of size n (n >= 1): sizes 1 and 2 are band 0, 3 and 4 band 1, and so on.
static func band_of(n: int) -> int:
	return (n - 1) / 2


# --- the schema helper the world loaders share ---

## The parsed JSON at `path`, or null when the file is missing or not JSON (quietly: a broken data
## file is reported as a problem, not an engine error).
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null


## Problems for `data` at JSON path `where`: not an object, an unknown key, a missing key. Unknown
## keys come first, then missing ones, each in sorted key order, so a message list is stable.
## `optional` keys may be absent. Never throws.
static func schema_problems(where: String, data: Variant, required: PackedStringArray,
		optional: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray()
	if not data is Dictionary:
		out.append("%s: must be an object" % where)
		return out
	for key in _sorted(data.keys()):
		if not (key is String and (required.has(key) or optional.has(key))):
			out.append("%s.%s: unknown key" % [where, key])
	for key in _sorted(Array(required)):
		if not data.has(key):
			out.append("%s.%s: missing" % [where, key])
	return out


## The common header every world data file has: schema_version 1, a status and a note.
static func header_check(where: String, data: Dictionary, problems: PackedStringArray) -> void:
	var before := problems.size()
	var version := number_at(where, data, "schema_version", problems, true)
	if data.has("schema_version") and problems.size() == before and int(version) != SCHEMA_VERSION:
		problems.append("%s.schema_version: must be %d" % [where, SCHEMA_VERSION])
	before = problems.size()
	var status := text_at(where, data, "status", problems)
	if data.has("status") and problems.size() == before and not STATUSES.has(status):
		problems.append("%s.status: must be one of %s" % [where, ", ".join(STATUSES)])
	text_at(where, data, "note", problems)


## The number at `key`: a finite JSON number, whole when asked. 0.0 with a problem when it is not;
## an absent key gives 0.0 quietly (schema_problems has named it).
static func number_at(where: String, data: Dictionary, key: String, problems: PackedStringArray, whole := false) -> float:
	if not data.has(key):
		return 0.0
	var value: Variant = data[key]
	if not ((value is float or value is int) and is_finite(value)):
		problems.append("%s.%s: must be a number" % [where, key])
		return 0.0
	if whole and fposmod(float(value), 1.0) != 0.0:
		problems.append("%s.%s: must be a whole number" % [where, key])
	return float(value)


## [x, y] of two finite numbers at `key`, as float64 (never a Vector2: world data stays float64 until
## it becomes a local position). Empty with a problem when it is not; empty quietly when absent.
static func pair_at(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> PackedFloat64Array:
	if not data.has(key):
		return PackedFloat64Array()
	var value: Variant = data[key]
	if value is Array and value.size() == 2:
		var ok := true
		for v in value:
			ok = ok and (v is float or v is int) and is_finite(v)
		if ok:
			return PackedFloat64Array([float(value[0]), float(value[1])])
	problems.append("%s.%s: must be two numbers" % [where, key])
	return PackedFloat64Array()


static func text_at(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> String:
	if not data.has(key):
		return ""
	if data[key] is String:
		return data[key]
	problems.append("%s.%s: must be text" % [where, key])
	return ""


static func flag_at(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> bool:
	if not data.has(key):
		return false
	if data[key] is bool:
		return data[key]
	problems.append("%s.%s: must be true or false" % [where, key])
	return false


## The object at `key`, checked against its keys (all required); {} when it is absent or not one.
static func object_at(where: String, data: Dictionary, key: String, keys: PackedStringArray,
		problems: PackedStringArray, optional: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not data.has(key):
		return {}
	problems.append_array(schema_problems("%s.%s" % [where, key], data[key], keys, optional))
	return data[key] if data[key] is Dictionary else {}


## The list at `key`; [] with a problem when it is not one, [] quietly when absent.
static func list_at(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> Array:
	if not data.has(key):
		return []
	if data[key] is Array:
		return data[key]
	problems.append("%s.%s: must be a list" % [where, key])
	return []


## True when `text` is a String the regular expression `pattern` finds a match in.
static func matches(text: Variant, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return text is String and re.search(text) != null


static func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out
