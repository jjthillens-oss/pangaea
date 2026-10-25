extends RefCounted
## The creature skin's look as the editor and the world share it (PROPOSED): the swatch and the three skin-shader
## pattern choices ride in the body dictionary's extra keys ("skin_color" as "rrggbb", "pattern_seed",
## "coat_pattern" and "detail_pattern" as whole numbers), which the codec keeps as unknown keys
## (tests/test_creature_body.gd), so the editor, the store and the world all draw the same skin. They are written as
## floats: JSON reads every number back as one, and the store's write check compares the body's encoding before and
## after the round trip (PersistenceService.save_to), so an int would come back as 3.0 and fail it. Not domain code: it is the presentation's
## convention, read by scenes only.
## The skin covering (PROPOSED, owner ask 2026-10-24: "monkeys ... fur etc. frogs more frog like") rides beside them as
## "skin_covering", a whole number 0..3 (smooth, fur, scales, wet) the shader reads as its "covering" uniform. A look
## dictionary (look_of) is the pattern plus that key; a shader without the uniform ignores it.

const SKIN_COLOR_KEY := "skin_color"
const PATTERN_KEYS: Array[String] = ["pattern_seed", "coat_pattern", "detail_pattern"]
## The player's pattern until the editor offers a choice: the lab's look (seed 3, dorsal stripe, cross bands).
const DEFAULT_PATTERN := {"pattern_seed": 3, "coat_pattern": 2, "detail_pattern": 1}
## The shader's ranges (assets/export/shaders/creature_skin.gdshader): a stored value outside them is ignored.
const PATTERN_RANGE := {"pattern_seed": [0, 1 << 30], "coat_pattern": [0, 3], "detail_pattern": [0, 4]}
const COVERING_KEY := "skin_covering"
## The covering choices in the shader's order (its "covering" uniform); 0, smooth, is the default.
const COVERINGS: Array[String] = ["Smooth", "Fur", "Scales", "Wet"]


## The three pattern ints `extra` carries, DEFAULT_PATTERN where one is missing or out of range.
static func pattern_of(extra: Dictionary) -> Dictionary:
	var out := DEFAULT_PATTERN.duplicate()
	for key in PATTERN_KEYS:
		var v: Variant = extra.get(key)
		if (v is int or (v is float and is_finite(v) and v == floorf(v))) and int(v) >= int(PATTERN_RANGE[key][0]) \
				and int(v) <= int(PATTERN_RANGE[key][1]):
			out[key] = int(v)
	return out


## Writes `pattern`'s three values into `extra` beside the swatch, as whole-number floats (see above).
static func store_pattern(extra: Dictionary, pattern: Dictionary) -> void:
	var p := pattern_of(pattern)
	for key in PATTERN_KEYS:
		extra[key] = float(p[key])


## The covering `extra` carries (an index into COVERINGS), 0 where it is missing or out of range.
static func covering_of(extra: Dictionary) -> int:
	var v: Variant = extra.get(COVERING_KEY)
	if (v is int or (v is float and is_finite(v) and v == floorf(v))) and int(v) >= 0 and int(v) < COVERINGS.size():
		return int(v)
	return 0


## Writes `covering` into `extra` as a whole-number float (see above).
static func store_covering(extra: Dictionary, covering: int) -> void:
	extra[COVERING_KEY] = float(covering_of({COVERING_KEY: covering}))


## The whole look `extra` carries: the three pattern ints and the covering.
static func look_of(extra: Dictionary) -> Dictionary:
	var out := pattern_of(extra)
	out[COVERING_KEY] = covering_of(extra)
	return out


## A rival's look from its index in the field: every rival gets its own seed, coat and detail; its covering is the
## one its body carries (a preset's "skin_covering"), smooth without one.
static func rival_pattern(index: int, extra: Dictionary = {}) -> Dictionary:
	return {"pattern_seed": index, "coat_pattern": 1 + index % 3, "detail_pattern": [2, 1, 3, 0][index % 4],
			COVERING_KEY: covering_of(extra)}


## The skin shader's parameters for `color` and the look `pattern` (SpineRig.use_skin_shader): the pattern ints and
## "covering" from its "skin_covering".
static func shader_params(color: Color, pattern: Dictionary) -> Dictionary:
	var out := pattern_of(pattern)
	out["covering"] = covering_of(pattern)
	out["color_base"] = color
	return out
