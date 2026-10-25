extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): what a part tool would do to the creature, worked out by the stats
## service the world itself uses (CreatureStats.of; Bible 12 one stats rule, Bible 14 a preview asks the same rules
## as the action), on a copy of the body with the part added the way the editor adds one (Picking.fit_scale). A
## part's stats do not depend on where it sits, only on its type, scale and whether it is a mirrored pair, so the
## copy's anchor is left at the default. Then the card's lines in plain words. Reads no files and no scene: the
## caller passes the data. No class_name: preload it.

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")
const Stats := preload("res://game/domain/creature/creature_stats.gd")

## The stats a card compares, in order: [key, label, format, higher is better].
const STATS := [
	["bite_power", "Bite", "%d", true],
	["sight_m", "Sight", "%.0f m", true],
	["charm", "Charm", "%.1f", true],
	["speed_mps", "Speed", "%.1f m/s", true],
	["max_health", "Health", "%d", true],
]
## What each part role is for, the card's first line. A role not listed here gets ROLE_UNKNOWN.
const ROLE_WORDS := {
	"mouth": "A mouth: eats, and bites in a fight",
	"eye": "An eye: sees further",
	"weapon": "A weapon: adds to the bite",
	"detail": "A display organ: charms others when you sing and dance to befriend them",
	"foot": "A foot, for the end of a leg",
	"hand": "A hand, for the end of an arm",
}
const ROLE_UNKNOWN := "Changes the creature's look"
const NO_STAT_CHANGE := "No change to bite, sight, charm or speed: it changes the look"
const NEEDS_MOUTH := "Needs a mouth to bite with: add a mouth first"
const STRENGTH_NOTE := "Heavier bodies bite harder"
const LOCKED := "Find it in the world to use it"
const PAIR_LABEL := "as a pair"
const TITLE := "%s · %d points"
const PRICE_ONE := "%d points"
const PRICE_PAIR := "A mirrored pair %d points"
const PRICE_BOTH := "One %d points · a mirrored pair %d points"
const LEAVES := "Leaves %d of your %d points"
const SHORT := "%d points more than you have"
const REFUND := "Taking off a part you came in with gives back %d%% of its price"
const FULL := "No free part slots (%d at most)"
const SELECT_TITLE := "Select"
const SELECT_LINES := [
	"Pick and drag the dots on the creature: orange bones, blue limb joints, green parts",
	"The wheel over a selection resizes it",
]
const LIMB_TITLE := "Limb · %d points"
const LIMB_LINES := [
	"Grows a leg or an arm of three joints from the nearest vertebra",
	"Legs set the speed: Test drive shows the walk",
]
const LIMB_PRICE := "A mirrored pair %d points · one on the middle line %d"


## {now, one, pair, scale}: CreatureStats.of the body as it is, with one more `type` part, and with a mirrored pair
## of them, each at the scale the editor gives a new part on this body.
static func effects(body: RefCounted, type: String, part_rules: Dictionary, gait_table: RefCounted,
		tuning: Dictionary, body_rules: Dictionary, ref_size_m: float) -> Dictionary:
	var scale := Picking.fit_scale(body, ref_size_m, body_rules)
	var out := {"now": Stats.of(body, part_rules, gait_table, tuning), "scale": scale}
	for pair: bool in [false, true]:
		var copy: RefCounted = BodyCodec.from_dict(body.to_dict())
		copy.add_part(type, {"scale": scale, "mirror": pair})
		out["pair" if pair else "one"] = Stats.of(copy, part_rules, gait_table, tuning)
	return out


## Whether a part with this rule comes as one, as a mirrored pair, or either: "one", "pair" or "both". A part for a
## limb's end follows the limb (a mirrored limb has a twin end), so it is "both".
static func modes(rule: Dictionary) -> String:
	var hosts: Array = rule.get("hosts", [])
	if not hosts.has("spine"):
		return "both"
	match String(rule.get("centerline", "allowed")):
		"required":
			return "one"
		"forbidden":
			return "pair"
	return "both"


## The stat rows that change, as PartCard lines ["stat", label, before, after, better]: the one-part change, and the
## pair's under it where a pair is possible.
static func stat_lines(fx: Dictionary, mode: String) -> Array:
	var out: Array = []
	for spec: Array in STATS:
		var key := String(spec[0])
		var before := float(fx["now"].get(key, 0.0))
		var shown := PackedStringArray()
		for which in (["one"] if mode == "one" else (["pair"] if mode == "pair" else ["one", "pair"])):
			var after := float(fx[which].get(key, 0.0))
			var b_text := String(spec[2]) % before
			var a_text := String(spec[2]) % after
			if b_text == a_text:
				continue
			var label := String(spec[1])
			if which == "pair":
				label = PAIR_LABEL if shown.has("one") else "%s, %s" % [spec[1], PAIR_LABEL]
			out.append(["stat", label, b_text, a_text, (after > before) == bool(spec[3])])
			shown.append(which)
	return out


## The card for a part tool: {title, lines} (PartCard.show_lines). `info` carries {price, pair_price, refund_rate,
## points, cost (this visit's so far), locked, parts, part_count_max, sight_max_m, display_cap, weapon_cap}; a key
## it lacks leaves its line out. `where` is the placement line ("" for none).
static func card(type: String, rule: Dictionary, fx: Dictionary, info: Dictionary, where := "") -> Dictionary:
	var label := type.capitalize()
	var price := int(info.get("price", 0))
	var mode := modes(rule)
	var role := String(rule.get("role", ""))
	var lines: Array = []
	if bool(info.get("locked", false)):
		lines.append([LOCKED, "worse"])
	lines.append([String(ROLE_WORDS.get(role, ROLE_UNKNOWN)), ""])
	var rows := stat_lines(fx, mode)
	lines.append_array(rows)
	var now: Dictionary = fx["now"]
	if role == Stats.WEAPON_ROLE and not bool(now.get("has_mouth", false)):
		lines.append([NEEDS_MOUTH, "note"])
	elif rows.is_empty():
		lines.append([NO_STAT_CHANGE, "note"])
	if role == Stats.MOUTH_ROLE and not rows.is_empty():
		lines.append([STRENGTH_NOTE, "note"])
	if role == Stats.EYE_ROLE and info.has("sight_max_m") and float(fx["pair"].get("sight_m", 0.0)) >= float(info["sight_max_m"]):
		lines.append(["Sight stops at %.0f m" % float(info["sight_max_m"]), "note"])
	if role == Stats.DISPLAY_ROLE and info.has("display_cap"):
		lines.append(["Charm counts when you sing to befriend; only the first %d display organs count" % int(info["display_cap"]), "note"])
	if role == Stats.WEAPON_ROLE and info.has("weapon_cap") and bool(now.get("has_mouth", false)):
		lines.append(["Only your %d largest weapons count" % int(info["weapon_cap"]), "note"])
	match mode:
		"one":
			lines.append([PRICE_ONE % price, ""])
		"pair":
			lines.append([PRICE_PAIR % (2 * price), ""])
		_:
			lines.append([PRICE_BOTH % [price, 2 * price], ""])
	if info.has("points") and info.has("cost"):
		var left := int(info["points"]) - int(info["cost"]) - (2 * price if mode == "pair" else price)
		lines.append([LEAVES % [left, int(info["points"])] if left >= 0 else SHORT % -left, "note" if left >= 0 else "worse"])
	if info.has("parts") and info.has("part_count_max") and int(info["parts"]) >= int(info["part_count_max"]):
		lines.append([FULL % int(info["part_count_max"]), "worse"])
	if not where.is_empty():
		lines.append([where, "note"])
	if info.has("refund_rate"):
		lines.append([REFUND % roundi(float(info["refund_rate"]) * 100.0), "note"])
	return {"title": TITLE % [label, price], "lines": lines}


## The limb tool's card: a pair of three-joint limbs costs `pair_price` (the palette's price), one half of it.
static func limb_card(pair_price: int, where := "") -> Dictionary:
	var lines: Array = []
	for line in LIMB_LINES:
		lines.append([line, ""])
	lines.append([LIMB_PRICE % [pair_price, pair_price / 2], ""])
	if not where.is_empty():
		lines.append([where, "note"])
	return {"title": LIMB_TITLE % pair_price, "lines": lines}


static func select_card() -> Dictionary:
	var lines: Array = []
	for line in SELECT_LINES:
		lines.append([line, ""])
	return {"title": SELECT_TITLE, "lines": lines}
