extends TestCase
## The creature editor's colour rules (game/domain/creature/colour_rules.gd, IB-33 first slice): hex text to a
## colour and back, the refusals for text that is not a colour, and the saturation and value clamp with its limits
## from body_rules.json ("skin_colour").

const ColourRules := preload("res://game/domain/creature/colour_rules.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")


func test_the_valid_forms_parse_to_the_same_colour() -> void:
	for text in ["#4FC08A", "4fc08a", "  #4fC08a  ", "4FC08A"]:
		var r: Dictionary = ColourRules.parse_hex(text)
		check(r["ok"] and r["error"] == "", "'%s' parses" % text)
		check_eq([r["color"].r8, r["color"].g8, r["color"].b8], [0x4f, 0xc0, 0x8a], "'%s' channels" % text)
	for text in ["#abc", "ABC", " aBc "]:
		var r: Dictionary = ColourRules.parse_hex(text)
		check(r["ok"], "'%s' parses" % text)
		check_eq([r["color"].r8, r["color"].g8, r["color"].b8], [0xaa, 0xbb, 0xcc], "'%s' doubles each digit" % text)


func test_text_that_is_not_a_colour_is_refused_with_a_reason() -> void:
	for text in ["", "   ", "#", "12", "#1234", "#12345", "#1234567", "#12345678", "gggggg", "#12 345", "red", "##abc",
			"0x4fc0"]:
		var r: Dictionary = ColourRules.parse_hex(text)
		check(not r["ok"] and String(r["error"]) != "", "'%s' is refused with a reason" % text)


func test_format_is_upper_case_and_round_trips() -> void:
	check_eq(ColourRules.format_hex(Color8(0x4f, 0xc0, 0x8a)), "#4FC08A", "upper case with a hash")
	check_eq(ColourRules.format_hex(Color(0, 0, 0, 0.3)), "#000000", "alpha is dropped")
	for text in ["#000000", "#FFFFFF", "#5CA8DC", "#010203", "#FE7F80"]:
		check_eq(ColourRules.format_hex(ColourRules.parse_hex(text)["color"]), text, "%s round trips" % text)


func test_the_limits_come_from_the_body_rules() -> void:
	var limits: Dictionary = ColourRules.limits_of(CreatureData.rules())
	for field in ["saturation", "value"]:
		var pair: Array = limits[field]
		check(pair.size() == 2 and int(pair[0]) >= 0 and int(pair[0]) < int(pair[1]) and int(pair[1]) <= 1000,
				"%s is a per mille [min, max] (%s)" % [field, pair])
	check_eq(ColourRules.limits_of({}), ColourRules.DEFAULT_LIMITS, "no table: the defaults")
	check_eq(ColourRules.limits_of({"skin_colour": {"saturation": [900, 100], "value": "x"}}), ColourRules.DEFAULT_LIMITS,
			"an unusable table: the defaults")
	check_eq(ColourRules.limits_of({"skin_colour": {"saturation": [100, 500]}})["saturation"], [100, 500], "a table is read")


func test_the_clamp_holds_saturation_and_value_and_keeps_the_hue() -> void:
	var limits := {"saturation": [0, 850], "value": [180, 950]}
	var tol := 0.012   # one 8-bit step of a channel
	for text in ["#FF0000", "#00FF00", "#0000FF", "#FF00FF", "#FFFFFF", "#000000", "#010000", "#FFFF00"]:
		var typed: Color = ColourRules.parse_hex(text)["color"]
		var held: Color = ColourRules.clamp_colour(typed, limits)
		check(held.s <= 0.85 + tol, "%s: saturation %.3f is held" % [text, held.s])
		check(held.v >= 0.18 - tol and held.v <= 0.95 + tol, "%s: value %.3f is held" % [text, held.v])
		check_eq(held.a, 1.0, "%s: opaque" % text)
		if typed.s > 0.5 and typed.v > 0.5:
			check(absf(held.h - typed.h) < 0.01, "%s: the hue stays (%.3f, was %.3f)" % [text, held.h, typed.h])
		check_eq(ColourRules.format_hex(ColourRules.clamp_colour(held, limits)), ColourRules.format_hex(held),
				"%s: clamping twice changes nothing more" % text)
	check_eq(ColourRules.format_hex(ColourRules.clamp_colour(Color8(255, 0, 0), limits)), "#F22424", "pure red, by hand")


func test_a_colour_inside_the_limits_is_unchanged() -> void:
	var limits: Dictionary = ColourRules.limits_of(CreatureData.rules())
	for text in ["#5CA8DC", "#4FC08A", "#D9A441", "#D2604E", "#A86FD6", "#E6E1C8", "#5F6B7A", "#2E4A6B"]:
		check_eq(ColourRules.format_hex(ColourRules.clamp_colour(ColourRules.parse_hex(text)["color"], limits)), text,
				"the swatch %s passes the clamp as it is" % text)


func test_resolve_reports_the_clamp_and_the_refusal() -> void:
	var r: Dictionary = ColourRules.resolve_hex(" 4fc08a ", CreatureData.rules())
	check(r["ok"] and r["hex"] == "#4FC08A" and not r["clamped"], "a colour inside the limits: %s" % r)
	r = ColourRules.resolve_hex("#f00", CreatureData.rules())
	check(r["ok"] and r["clamped"] and r["hex"] != "#FF0000", "pure red is pulled in: %s" % r)
	check_eq(ColourRules.format_hex(r["color"]), r["hex"], "hex names the colour")
	r = ColourRules.resolve_hex("nope", CreatureData.rules())
	check(not r["ok"] and r["error"] != "" and r["hex"] == "", "a refusal carries its reason")
