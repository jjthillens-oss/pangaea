extends RefCounted
## Colour rules for the creature editor's exact colour entry (IB-33 first slice, PROPOSED): a hex string to a
## colour and back, and the clamp that holds a typed colour inside the Bible section 15 saturation discipline.
## The limits are per mille [min, max] pairs for HSV saturation and value, read from data/creature/body_rules.json
## ("skin_colour"); the numbers are PROPOSED. Colours are handled as whole 8-bit channels, so the same text always
## gives the same stored "rrggbb". Pure rules: no scene or file access.

const KEY := "skin_colour"
## Used when body_rules has no "skin_colour" table (tests that build rules by hand).
const DEFAULT_LIMITS := {"saturation": [0, 850], "value": [180, 950]}
const HEX_DIGITS := "0123456789abcdef"


## The saturation and value limits in `rules` (per mille [min, max]), DEFAULT_LIMITS where one is missing or unusable.
static func limits_of(rules: Dictionary) -> Dictionary:
	var out := DEFAULT_LIMITS.duplicate(true)
	var table: Variant = rules.get(KEY)
	if table is Dictionary:
		for field in out:
			var pair: Variant = (table as Dictionary).get(field)
			if pair is Array and (pair as Array).size() == 2 and int(pair[0]) >= 0 and int(pair[1]) <= 1000 \
					and int(pair[0]) <= int(pair[1]):
				out[field] = [int(pair[0]), int(pair[1])]
	return out


## Reads "#RRGGBB", "RRGGBB", "#RGB" or "RGB" (any case, spaces around it ignored). Returns {ok, color, error}:
## `error` is a short line for the player when `ok` is false.
static func parse_hex(text: String) -> Dictionary:
	var s := text.strip_edges().to_lower()
	if s.begins_with("#"):
		s = s.substr(1)
	if s == "":
		return {"ok": false, "color": Color.BLACK, "error": "Type a colour like #4FC08A"}
	if s.length() != 3 and s.length() != 6:
		return {"ok": false, "color": Color.BLACK, "error": "Use 3 or 6 hex digits, like #4FC08A"}
	var digits := PackedInt32Array()
	for i in s.length():
		var d := HEX_DIGITS.find(s[i])
		if d < 0:
			return {"ok": false, "color": Color.BLACK, "error": "Only 0-9 and A-F, like #4FC08A"}
		digits.append(d)
	var rgb := [0, 0, 0]
	for i in 3:
		rgb[i] = digits[i] * 17 if digits.size() == 3 else digits[2 * i] * 16 + digits[2 * i + 1]
	return {"ok": true, "color": Color8(rgb[0], rgb[1], rgb[2]), "error": ""}


## `color` as "#RRGGBB" (upper case, alpha dropped).
static func format_hex(color: Color) -> String:
	return "#%02X%02X%02X" % [color.r8, color.g8, color.b8]


## `color` with its HSV saturation and value held inside `limits` (limits_of), on whole 8-bit channels and opaque.
## A colour already inside the limits comes back unchanged.
static func clamp_colour(color: Color, limits: Dictionary = DEFAULT_LIMITS) -> Color:
	var c := Color8(color.r8, color.g8, color.b8)
	var sat: Array = limits.get("saturation", DEFAULT_LIMITS["saturation"])
	var val: Array = limits.get("value", DEFAULT_LIMITS["value"])
	var s := clampf(c.s, float(sat[0]) / 1000.0, float(sat[1]) / 1000.0)
	var v := clampf(c.v, float(val[0]) / 1000.0, float(val[1]) / 1000.0)
	if is_equal_approx(s, c.s) and is_equal_approx(v, c.v):
		return c
	var out := Color.from_hsv(c.h, s, v)
	return Color8(out.r8, out.g8, out.b8)


## A typed hex through the discipline: {ok, color, hex, clamped, error}. `color` is the clamped colour, `hex` its
## text, `clamped` whether the clamp changed what was typed.
static func resolve_hex(text: String, rules: Dictionary = {}) -> Dictionary:
	var parsed := parse_hex(text)
	if not parsed["ok"]:
		return {"ok": false, "color": Color.BLACK, "hex": "", "clamped": false, "error": parsed["error"]}
	var typed: Color = parsed["color"]
	var held := clamp_colour(typed, limits_of(rules))
	return {"ok": true, "color": held, "hex": format_hex(held), "clamped": format_hex(held) != format_hex(typed),
			"error": ""}
