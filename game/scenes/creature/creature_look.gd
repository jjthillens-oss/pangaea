extends RefCounted
## The creature skin's look as the editor and the world share it (PROPOSED): the swatch and the three skin-shader
## pattern choices ride in the body dictionary's extra keys ("skin_color" as "rrggbb", "pattern_seed",
## "coat_pattern" and "detail_pattern" as ints), which the codec keeps as unknown keys (tests/test_creature_body.gd),
## so the editor, the store and the world all draw the same skin. Not domain code: it is the presentation's
## convention, read by scenes only.

const SKIN_COLOR_KEY := "skin_color"
const PATTERN_KEYS: Array[String] = ["pattern_seed", "coat_pattern", "detail_pattern"]
## The player's pattern until the editor offers a choice: the lab's look (seed 3, dorsal stripe, cross bands).
const DEFAULT_PATTERN := {"pattern_seed": 3, "coat_pattern": 2, "detail_pattern": 1}
## The shader's ranges (assets/export/shaders/creature_skin.gdshader): a stored value outside them is ignored.
const PATTERN_RANGE := {"pattern_seed": [0, 1 << 30], "coat_pattern": [0, 3], "detail_pattern": [0, 4]}


## The three pattern ints `extra` carries, DEFAULT_PATTERN where one is missing or out of range.
static func pattern_of(extra: Dictionary) -> Dictionary:
	var out := DEFAULT_PATTERN.duplicate()
	for key in PATTERN_KEYS:
		var v: Variant = extra.get(key)
		if (v is int or v is float) and int(v) >= int(PATTERN_RANGE[key][0]) and int(v) <= int(PATTERN_RANGE[key][1]):
			out[key] = int(v)
	return out


## Writes `pattern`'s three ints into `extra` beside the swatch.
static func store_pattern(extra: Dictionary, pattern: Dictionary) -> void:
	var p := pattern_of(pattern)
	for key in PATTERN_KEYS:
		extra[key] = p[key]


## A rival's pattern from its index in the field: every rival gets its own seed, coat and detail.
static func rival_pattern(index: int) -> Dictionary:
	return {"pattern_seed": index, "coat_pattern": 1 + index % 3, "detail_pattern": [2, 1, 3, 0][index % 4]}


## The skin shader's parameters for `color` and `pattern` (SpineRig.use_skin_shader).
static func shader_params(color: Color, pattern: Dictionary) -> Dictionary:
	var out := pattern_of(pattern)
	out["color_base"] = color
	return out
