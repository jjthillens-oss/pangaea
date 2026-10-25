class_name WorldConfig
extends RefCounted
## The endless world's settings (game/data/world_cell.json, S1): the mode, the size ladder's units,
## the streaming rings and caps, the floating origin, the tile arrangement and where the content
## lives. Plain data plus checks of the data itself (docs/s1/s1-interfaces.md, section 4.1).
##
## S2 adds the growth economy (growth), the band's second size (second_size), the size ladder's
## labels and food looks (ladder) and three switches (docs/s2/s2-interfaces.md 4.1, docs/s2/s2-sim.md
## 3.10, docs/s2/s2-build-plan.md 7.3), and lets the build reach size 2.
##
## S3 adds band 1 (docs/s3/s3-interfaces.md 5.1 and 6.1, s3-build-plan.md BP3-17): per-band region
## tables, arrangement.bands (band 1's region order and fixed rare kind), content.cradle (each
## band's cradle file), two more plant looks, the landmark_return switch, and a top of size 4. Bands
## past band_of(max_in_build) may be present; only the reachable ones must be.
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
	"rings_tm", "caps", "growth", "second_size", "ladder", "origin", "arrangement", "content", "switches"]
const SIZES_KEYS: PackedStringArray = ["start", "max_in_build"]
const UNITS_KEYS: PackedStringArray = ["growth_factor", "band_factor", "tile_bu", "chunk_tm"]
## Inner to outer: every ring lies strictly outside the one before it (rule 4).
const RING_KEYS: PackedStringArray = ["mirror", "view", "wake", "sleep", "food", "load", "unload", "hold"]
const CAP_KEYS: PackedStringArray = ["awake", "sleepers", "food_items", "food_per_zone", "chunks", "view_set_chunks",
	"loads_per_tick"]
const ORIGIN_KEYS: PackedStringArray = ["rebase_beyond_tm", "rebase_step_tm", "local_bound_tm"]
const ARRANGEMENT_KEYS: PackedStringArray = ["region_period_tiles", "region_order", "region_thresholds", "max_drift_run",
	"landmark_cell_tiles", "rare_block_tiles", "rare_block_first_tile", "home_tiles", "fixed_rare"]
## S3: arrangement.bands {"<band>": {region_order, fixed_rare_kind}} for bands 1 and on, and
## content.cradle {"<band>": path}. Both may be absent in a band-0 world (world_min.json).
const ARRANGEMENT_OPTIONAL: PackedStringArray = ["bands"]
const BAND_KEYS: PackedStringArray = ["region_order", "fixed_rare_kind"]
const FIXED_RARE_KEYS: PackedStringArray = ["tile", "kind"]
const CONTENT_KEYS: PackedStringArray = ["home", "tiles", "kit"]
const CONTENT_OPTIONAL: PackedStringArray = ["cradle"]
## landmark_return (BP3-17): the landmark pass may move the return point at a band's second size.
const SWITCH_KEYS: PackedStringArray = ["generated_creatures", "growth", "lumps", "habits", "landmark_return"]
const REGIONS: PackedStringArray = ["drift", "sunlit", "reef"]
## The regions of each band, and the band's transit region ("" for none: band 1 has no drift).
const REGIONS_BY_BAND := {0: ["drift", "sunlit", "reef"], 1: ["veil_garden", "warden_flat", "glass_reef"]}
const TRANSIT_BY_BAND := {0: "drift", 1: ""}
## The growth block (rule 10). Its nested objects are lumps, remnants, discovery and points.
const GROWTH_KEYS: PackedStringArray = ["trigger", "rings", "drain_floor_share", "drain_ring_seconds", "calm_ticks",
	"quiet_ticks", "chase_window_ticks", "chase_close_tm", "chase_track_tm", "wedge_tm", "showcase_s", "blocked_hint_s",
	"shelter_s", "beat_s", "beat_loads_per_tick", "death_meter_share", "respawn_floor_share", "respawn_cap_over_death",
	"top_payout_points", "prefetch_share", "prefetch_per_tick", "lumps", "remnants", "discovery", "points"]
const LUMP_KEYS: PackedStringArray = ["threat_kill", "place", "landmark_at_top", "food_look", "kill_carcass_share"]
const REMNANT_KEYS: PackedStringArray = ["cap", "min_rel", "morsel_min_rel", "life_s", "morsel_max_radius_tm", "morsel_rot_s"]
const DISCOVERY_KEYS: PackedStringArray = ["place_find_tm", "landmark_find_tm"]
## The adaptation points a find pays (S4.1), whole numbers 0 or more: a place, a landmark.
const POINTS_KEYS: PackedStringArray = ["place", "landmark"]
const SECOND_SIZE_KEYS: PackedStringArray = ["zone_thin_share"]
const LADDER_KEYS: PackedStringArray = ["labels", "food_looks"]
const FOOD_LOOK_KEYS: PackedStringArray = ["plant", "meat"]
## Rule 10, by kind. Shares lie in (0, 1]; counts are whole and 1 or more; lengths and times are
## above 0; the two "at least 0" numbers may be 0.
const GROWTH_SHARES: PackedStringArray = ["drain_floor_share", "death_meter_share", "respawn_floor_share", "prefetch_share"]
const GROWTH_COUNTS: PackedStringArray = ["calm_ticks", "quiet_ticks", "chase_window_ticks", "beat_loads_per_tick",
	"prefetch_per_tick"]
const GROWTH_POSITIVE: PackedStringArray = ["drain_ring_seconds", "chase_close_tm", "chase_track_tm", "wedge_tm", "showcase_s",
	"blocked_hint_s", "shelter_s", "beat_s"]
const GROWTH_AT_LEAST_0: PackedStringArray = ["respawn_cap_over_death", "top_payout_points"]
const REMNANT_POSITIVE: PackedStringArray = ["life_s", "morsel_max_radius_tm", "morsel_rot_s"]
## The trigger the sim starts with when no intent names one (tests and bots; BP-3: the player's
## choice comes from SettingsService through SimIntent.trigger).
const TRIGGERS: PackedStringArray = ["auto", "press"]
## The food looks the scene can draw (s2-sim 3.10): a plant look per size, and carrion for meat.
const PLANT_LOOKS: PackedStringArray = ["plankton", "algae_ball", "glass_flake", "bead_cluster"]
const MEAT_LOOKS: PackedStringArray = ["carrion"]
## D-68: the conversion thresholds are the ladder's (Relationships.PREY_MIN_REL and MORSEL_MIN_REL,
## plan B.7). The file keeps them for the reader, and any other value is refused.
const REMNANT_MIN_REL := 0.45
const MORSEL_MIN_REL := 0.25

# The numbers the S1 code is written for (rules 3 and 7).
const GROWTH_FACTOR := 1.6     ## tm grows by this per size (plan A.1)
const BAND_FACTOR := 2.56      ## bu grows by this per band: GROWTH_FACTOR squared, two sizes a band
const TILE_BU := 64.0
const CHUNK_TM := 32.0
const MAX_SIZE := 10
const S1_MAX_SIZE := 1         ## a larger size needs growth, which is S2
const S2_MAX_SIZE := 2         ## S2's top: S2 had content for sizes 1 and 2 (BP-5)
const S3_MAX_SIZE := 4         ## the top this build can reach: S3 adds band 1, sizes 3 and 4
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
## "mirror", "view", "wake", "sleep", "food", "load", "unload", "hold" -> float tm (hold: an awake
## creature whose reach disc centre lies further than this is removed, so its chunks can unload; B-6)
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
## {"home": String, "tiles": {band String -> dir String}, "kit": String, "cradle": {band String -> file
## String}}, res:// paths
var content := {}
## {int band -> res:// path} from content.cradle (band 1 and on)
var cradle_paths := {}
## The growth economy (rule 10; s2-sim 4.1, BP-4): {"trigger": "auto"|"press", "rings":
## PackedFloat64Array (the meter's ring at sizes 1 to 9), the shares, tm and seconds as float, the
## tick and other counts as int, "lumps": {kind -> share}, "remnants": {cap: int, min_rel,
## morsel_min_rel, life_s, morsel_max_radius_tm, morsel_rot_s}, "discovery": {place_find_tm,
## landmark_find_tm}}.
var growth := {}
## {"zone_thin_share": float}: a "thin" zone's capacity factor at a band's second size (D-60).
var second_size := {}
## {"labels": PackedStringArray (one per size, 1 to MAX_SIZE), "food_looks": [{plant, meat}, ...]
## (one per size the build can reach, or more)}
var ladder := {}
## {"generated_creatures": bool, "growth": bool, "lumps": bool, "habits": bool, "landmark_return": bool}
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

	config.arrangement = _read_arrangement(w + ".arrangement",
		object_at(w, data, "arrangement", ARRANGEMENT_KEYS, problems, ARRANGEMENT_OPTIONAL), problems)

	var content_data := object_at(w, data, "content", CONTENT_KEYS, problems, CONTENT_OPTIONAL)
	var tile_dirs := {}
	var raw_tiles: Variant = content_data.get("tiles")
	if raw_tiles is Dictionary:
		for band in _sorted(raw_tiles.keys()):
			tile_dirs[str(band)] = text_at(w + ".content.tiles", raw_tiles, band, problems)
	elif content_data.has("tiles"):
		problems.append("%s.content.tiles: must be an object" % w)
	var cradles := {}
	var raw_cradles: Variant = content_data.get("cradle", {})
	if raw_cradles is Dictionary:
		for band in _sorted(raw_cradles.keys()):
			cradles[str(band)] = text_at(w + ".content.cradle", raw_cradles, band, problems)
			if str(band).is_valid_int():
				config.cradle_paths[int(band)] = cradles[str(band)]
	else:
		problems.append("%s.content.cradle: must be an object" % w)
	config.content = {"home": text_at(w + ".content", content_data, "home", problems), "tiles": tile_dirs,
		"kit": text_at(w + ".content", content_data, "kit", problems), "cradle": cradles}

	config.growth = _read_growth(w + ".growth", object_at(w, data, "growth", GROWTH_KEYS, problems), problems)
	var second := object_at(w, data, "second_size", SECOND_SIZE_KEYS, problems)
	config.second_size = {"zone_thin_share": number_at(w + ".second_size", second, "zone_thin_share", problems)}
	config.ladder = _read_ladder(w + ".ladder", object_at(w, data, "ladder", LADDER_KEYS, problems), problems)

	var switch_data := object_at(w, data, "switches", SWITCH_KEYS, problems)
	for key in SWITCH_KEYS:
		config.switches[key] = flag_at(w + ".switches", switch_data, key, problems)
	return config


static func _read_growth(w: String, g: Dictionary, problems: PackedStringArray) -> Dictionary:
	var out := {"trigger": text_at(w, g, "trigger", problems)}
	var rings := PackedFloat64Array()
	var raw_rings := list_at(w, g, "rings", problems)
	for i in raw_rings.size():
		rings.append(number_at(w + ".rings", {str(i): raw_rings[i]}, str(i), problems))
	out.rings = rings
	for key in GROWTH_KEYS:
		if out.has(key) or key in ["lumps", "remnants", "discovery", "points"]:
			continue
		var whole := GROWTH_COUNTS.has(key) or key == "top_payout_points"
		var v := number_at(w, g, key, problems, whole)
		out[key] = int(v) if whole else v
	var lumps := object_at(w, g, "lumps", LUMP_KEYS, problems)
	out.lumps = {}
	for key in LUMP_KEYS:
		out.lumps[key] = number_at(w + ".lumps", lumps, key, problems)
	var remnants := object_at(w, g, "remnants", REMNANT_KEYS, problems)
	out.remnants = {"cap": int(number_at(w + ".remnants", remnants, "cap", problems, true))}
	for key in REMNANT_KEYS:
		if key != "cap":
			out.remnants[key] = number_at(w + ".remnants", remnants, key, problems)
	var discovery := object_at(w, g, "discovery", DISCOVERY_KEYS, problems)
	out.discovery = {}
	for key in DISCOVERY_KEYS:
		out.discovery[key] = number_at(w + ".discovery", discovery, key, problems)
	var points := object_at(w, g, "points", POINTS_KEYS, problems)
	out.points = {}
	for key in POINTS_KEYS:
		out.points[key] = int(number_at(w + ".points", points, key, problems, true))
	return out


static func _read_ladder(w: String, l: Dictionary, problems: PackedStringArray) -> Dictionary:
	var labels := PackedStringArray()
	var raw_labels := list_at(w, l, "labels", problems)
	for i in raw_labels.size():
		labels.append(text_at(w + ".labels", {str(i): raw_labels[i]}, str(i), problems))
	var looks: Array[Dictionary] = []
	var raw_looks := list_at(w, l, "food_looks", problems)
	for i in raw_looks.size():
		var lw := "%s.food_looks[%d]" % [w, i]
		problems.append_array(schema_problems(lw, raw_looks[i], FOOD_LOOK_KEYS))
		var look: Dictionary = raw_looks[i] if raw_looks[i] is Dictionary else {}
		looks.append({"plant": text_at(lw, look, "plant", problems), "meat": text_at(lw, look, "meat", problems)})
	return {"labels": labels, "food_looks": looks}


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
	var bands := {}
	var raw_bands: Variant = a.get("bands", {})
	if raw_bands is Dictionary:
		for key in _sorted(raw_bands.keys()):
			var bw := "%s.bands.%s" % [w, key]
			problems.append_array(schema_problems(bw, raw_bands[key], BAND_KEYS))
			var b: Dictionary = raw_bands[key] if raw_bands[key] is Dictionary else {}
			var band_order := PackedStringArray()
			if b.get("region_order") is Array:
				for v in b.region_order:
					band_order.append(str(v))
			elif b.has("region_order"):
				problems.append("%s.region_order: must be a list" % bw)
			bands[str(key)] = {"region_order": band_order, "fixed_rare_kind": text_at(bw, b, "fixed_rare_kind", problems)}
	else:
		problems.append("%s.bands: must be an object" % w)
	return {
		"bands": bands,
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
	elif max_size_in_build > S3_MAX_SIZE:
		errors.append("%s.sizes.max_in_build: size %d is above this build's top (%d; S3 has content for sizes 1 to 4)"
			% [w, max_size_in_build, S3_MAX_SIZE])

	# Rule 3: the units the S1 code assumes.
	for pair in [["growth_factor", growth_factor, GROWTH_FACTOR], ["band_factor", band_factor, BAND_FACTOR],
			["tile_bu", tile_bu, TILE_BU], ["chunk_tm", chunk_tm, CHUNK_TM]]:
		if pair[1] != pair[2]:
			errors.append("%s.units.%s: must be %s (the S1 code assumes it), not %s" % [w, pair[0], pair[2], pair[1]])

	# Rule 4: the rings rise strictly (unload < hold too), with room between wake and sleep and between
	# load and unload.
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

	# Rule 6: the floating origin keeps every local position inside the bound: a loaded chunk lies
	# within unload, a held creature's disc centre within hold (B-6), and a chunk's far corner a
	# diagonal beyond. WorldContent.problems adds the reach discs to the hold.
	if rebase_step_tm != CHUNK_TM:
		errors.append("%s.origin.rebase_step_tm: must equal chunk_tm (%s)" % [w, CHUNK_TM])
	var farthest := rebase_beyond_tm + maxf(float(rings.unload), float(rings.hold)) + CHUNK_TM * sqrt(2.0)
	if not (farthest < local_bound_tm):
		errors.append("%s.origin.local_bound_tm: rebase_beyond_tm + max(unload, hold) + chunk_tm x sqrt 2 (%.2f) must be below it (%.2f)"
			% [w, farthest, local_bound_tm])

	# Rule 7: the arrangement.
	_check_arrangement(w + ".arrangement", errors)

	# Rule 8: the content paths.
	for key in ["home", "kit"]:
		_check_path("%s.content.%s" % [w, key], str(content[key]), false, errors)
	var tile_dirs: Dictionary = content.tiles
	# Every band the build can reach needs its tiles.
	for band in range(band_of(1), band_of(_top()) + 1):
		if not tile_dirs.has(str(band)):
			errors.append("%s.content.tiles.%d: missing (band %d is reachable)" % [w, band, band])
	for band in _sorted(tile_dirs.keys()):
		if not (str(band).is_valid_int() and int(band) >= 0):
			errors.append("%s.content.tiles.%s: a band must be a whole number of 0 or more" % [w, band])
		_check_path("%s.content.tiles.%s" % [w, band], str(tile_dirs[band]), true, errors)
	# S3: a cradle for every reachable band past band 0, and none for a band this build has no tables for.
	var cradles: Dictionary = content.get("cradle", {})
	for band in range(1, band_of(_top()) + 1):
		if not cradles.has(str(band)):
			errors.append("%s.content.cradle.%d: missing (band %d is reachable)" % [w, band, band])
	for band in _sorted(cradles.keys()):
		if not (str(band).is_valid_int() and int(band) >= 1 and int(band) <= band_of(S3_MAX_SIZE)):
			errors.append("%s.content.cradle.%s: a band must be 1 to %d" % [w, band, band_of(S3_MAX_SIZE)])
		_check_path("%s.content.cradle.%s" % [w, band], str(cradles[band]), false, errors)
	# Rule 9 (switches are bools) is a reading rule: from_dict refuses anything else.

	# Rules 10 to 12 (S2): the growth economy, the second size and the ladder.
	_check_growth(w + ".growth", errors)
	var thin := float(second_size.zone_thin_share)
	if not (thin > 0.0 and thin <= 1.0):
		errors.append("%s.second_size.zone_thin_share: rule 11: must lie in (0, 1] (%s)" % [w, thin])
	_check_ladder(w + ".ladder", errors)
	return errors


## The largest size the build reaches, for the rules that depend on it; 1 while rule 2 fails, so a
## wrong top is rule 2's one problem.
func _top() -> int:
	return max_size_in_build if size_start == 1 and max_size_in_build >= 1 and max_size_in_build <= S3_MAX_SIZE else 1


## Rule 10: the growth block. The rings: one per size below the ladder's top, each above 0. Shares
## in (0, 1]; counts whole and 1 or more; lengths and times above 0; the chase window shorter than
## the quiet time (a bite inside the window must still break the calm); the conversion thresholds
## the ladder's (D-68).
func _check_growth(w: String, errors: PackedStringArray) -> void:
	var g := growth
	if not TRIGGERS.has(str(g.trigger)):
		errors.append("%s.trigger: rule 10: '%s' is not one of %s" % [w, g.trigger, ", ".join(TRIGGERS)])
	var rings_ok: bool = (g.rings as PackedFloat64Array).size() == MAX_SIZE - 1
	for v in g.rings:
		rings_ok = rings_ok and v > 0.0
	if not rings_ok:
		errors.append("%s.rings: rule 10: must be %d numbers above 0, one per size from 1 to %d (%s)"
			% [w, MAX_SIZE - 1, MAX_SIZE - 1, g.rings])
	var shares := []
	for key in GROWTH_SHARES:
		shares.append([key, g[key]])
	for key in LUMP_KEYS:
		shares.append(["lumps." + key, g.lumps[key]])
	for pair in shares:
		if not (float(pair[1]) > 0.0 and float(pair[1]) <= 1.0):
			errors.append("%s.%s: rule 10: a share must lie in (0, 1] (%s)" % [w, pair[0], pair[1]])
	var counts := []
	for key in GROWTH_COUNTS:
		counts.append([key, g[key]])
	counts.append(["remnants.cap", g.remnants.cap])
	for pair in counts:
		if int(pair[1]) < 1:
			errors.append("%s.%s: rule 10: must be 1 or more (%s)" % [w, pair[0], pair[1]])
	var positive := []
	for key in GROWTH_POSITIVE:
		positive.append([key, g[key]])
	for key in REMNANT_POSITIVE:
		positive.append(["remnants." + key, g.remnants[key]])
	for key in DISCOVERY_KEYS:
		positive.append(["discovery." + key, g.discovery[key]])
	for pair in positive:
		if not float(pair[1]) > 0.0:
			errors.append("%s.%s: rule 10: must be above 0 (%s)" % [w, pair[0], pair[1]])
	for key in GROWTH_AT_LEAST_0:
		if float(g[key]) < 0.0:
			errors.append("%s.%s: rule 10: must be 0 or more (%s)" % [w, key, g[key]])
	for key in POINTS_KEYS:
		if int(g.points[key]) < 0:
			errors.append("%s.points.%s: rule 10: must be 0 or more (%s)" % [w, key, g.points[key]])
	if int(g.chase_window_ticks) >= int(g.quiet_ticks):
		errors.append("%s.chase_window_ticks: rule 10: must be below quiet_ticks (%d >= %d)" % [w, g.chase_window_ticks, g.quiet_ticks])
	for pair in [["min_rel", REMNANT_MIN_REL], ["morsel_min_rel", MORSEL_MIN_REL]]:
		if float(g.remnants[pair[0]]) != pair[1]:
			errors.append("%s.remnants.%s: rule 10: must be %s, the ladder's threshold (D-68), not %s"
				% [w, pair[0], pair[1], g.remnants[pair[0]]])


## Rule 12: a label for every size of the ladder, and a food look for every size the build reaches,
## each one the scene can draw.
func _check_ladder(w: String, errors: PackedStringArray) -> void:
	var labels: PackedStringArray = ladder.labels
	var labels_ok := labels.size() == MAX_SIZE
	for label in labels:
		labels_ok = labels_ok and not label.is_empty()
	if not labels_ok:
		errors.append("%s.labels: rule 12: must be %d texts, one per size (%d given)" % [w, MAX_SIZE, labels.size()])
	var looks: Array = ladder.food_looks
	if looks.size() < _top():
		errors.append("%s.food_looks: rule 12: %d looks for %d sizes; every size the build reaches needs one"
			% [w, looks.size(), _top()])
	for i in looks.size():
		if not PLANT_LOOKS.has(str(looks[i].plant)):
			errors.append("%s.food_looks[%d].plant: rule 12: '%s' is not one of %s" % [w, i, looks[i].plant, ", ".join(PLANT_LOOKS)])
		if not MEAT_LOOKS.has(str(looks[i].meat)):
			errors.append("%s.food_looks[%d].meat: rule 12: '%s' is not one of %s" % [w, i, looks[i].meat, ", ".join(MEAT_LOOKS)])


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
	# S3: bands has an entry for every reachable band past band 0, each a permutation of its regions
	# with a fixed rare kind, and none for a band without region tables.
	var bands: Dictionary = a.get("bands", {})
	for band in range(1, band_of(_top()) + 1):
		if not bands.has(str(band)):
			errors.append("%s.bands.%d: missing (band %d is reachable)" % [w, band, band])
	for key in _sorted(bands.keys()):
		if not (str(key).is_valid_int() and REGIONS_BY_BAND.has(int(key)) and int(key) >= 1):
			errors.append("%s.bands.%s: a band must be 1 to %d" % [w, key, REGIONS_BY_BAND.size() - 1])
			continue
		var band_sorted := Array(bands[key].region_order)
		band_sorted.sort()
		var want := Array(regions_of(int(key)))
		want.sort()
		if band_sorted != want:
			errors.append("%s.bands.%s.region_order: must be a permutation of %s" % [w, key, ", ".join(regions_of(int(key)))])
		if str(bands[key].fixed_rare_kind).is_empty():
			errors.append("%s.bands.%s.fixed_rare_kind: must name a rare kind" % [w, key])


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


## The regions of band `band` (empty for a band with no tables).
static func regions_of(band: int) -> PackedStringArray:
	return PackedStringArray(REGIONS_BY_BAND.get(band, []))


## The transit region of band `band`: "drift" in band 0, "" where the band has none.
static func transit_of(band: int) -> String:
	return str(TRANSIT_BY_BAND.get(band, ""))


## The arrangement as band `band` uses it: band 0's is the file's own; a later band's is a copy with
## the region order and the fixed rare kind from arrangement.bands. Empty for a band not in the file.
func arrangement_of(band: int) -> Dictionary:
	if band == 0:
		return arrangement
	var entry: Variant = (arrangement.get("bands", {}) as Dictionary).get(str(band))
	if not entry is Dictionary:
		return {}
	var out := arrangement.duplicate(true)
	out.region_order = PackedStringArray(entry.region_order)
	out.fixed_rare = {"tile": arrangement.fixed_rare.tile, "kind": str(entry.fixed_rare_kind)}
	return out


## How many tm one bu is at size n: pow(band_factor, band_of(n)) / pow(growth_factor, n - 1). Since
## band_factor is growth_factor squared and a band spans two sizes, that is 1 at a band's first size
## and 1 / growth_factor at its second, written so the float64 result is exact (1.0 and 0.625).
static func bu_to_tm(n: int) -> float:
	return 1.0 if posmod(n - 1, 2) == 0 else 1.0 / GROWTH_FACTOR


## The band of size n (n >= 1): sizes 1 and 2 are band 0, 3 and 4 band 1, and so on.
static func band_of(n: int) -> int:
	return (n - 1) / 2


## How many am one tm is at size n: growth_factor^(n - 1) (1.0 at size 1, 1.6 at size 2). Built by
## multiplication, not pow(), so every platform gives the same float64 (the stream's frame rests on it).
static func tm_to_am(n: int) -> float:
	var k := 1.0
	for i in n - 1:
		k *= GROWTH_FACTOR
	return k


## Whether size n is its band's second size (2, 4, ...), where a bu is 1 / 1.6 tm and the tiles'
## at_second_size applies.
static func is_second_size(n: int) -> bool:
	return posmod(n - 1, 2) == 1


## k (s2-sim's words, D-39): the factor that turns a species' q = 1 lengths into the bu of size n's
## tile frame, tm_to_am(entry_size) / band_factor^band_of(n). Since band_factor is growth_factor
## squared, that is growth_factor^(entry_size - 1 - 2 band_of(n)), built from exact factors (1.6 up,
## 0.625 down) as Relationships.q_of is: 1 for an entry-size-1 species in band 0, 1.6 for entry size 2.
static func k_of(entry_size: int, n: int) -> float:
	var e := entry_size - 1 - 2 * band_of(n)
	var k := 1.0
	for i in absi(e):
		k *= GROWTH_FACTOR if e > 0 else 1.0 / GROWTH_FACTOR
	return k


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
