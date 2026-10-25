extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): where the chosen tool's part will go, in one line, from the part's
## rule (part_rules: hosts and centerline) and the editor's own snap numbers (EditorPicking.MIDDLE_SNAP, the
## middle-line snap; LIMB_END_FROM_U, a limb's end), so the words cannot drift from what a click does (Bible 14).
## The spot itself is not shown before the click: GitHub issue D asks the editor for a hover preview. No class_name:
## preload it.

const Picking := preload("res://game/domain/creature/editor_picking.gd")

const BODY := "Click the head or body"
const MIDDLE_ALLOWED := "within %d° of the middle line it snaps on as one; further out you get a mirrored pair"
const MIDDLE_REQUIRED := "it always sits on the middle line, as one, never a pair"
const MIDDLE_FORBIDDEN := "it always goes to one side, as a mirrored pair"
const LIMB_END_ONLY := "Goes on the end of a limb: click anywhere on a limb"
const LIMB_AND_END := "Goes on a limb: click near its tip (the last %d%%) for the end, or along it"
const LIMB_ONLY := "Goes on a limb: click a limb"
const LIMB_END_TOO := "or click a limb (near its tip, the last %d%%, it goes on the end)"
const LIMB_TOO := "or click a limb to put it on the limb"
const LIMB_TWIN := "a mirrored limb gets a pair"
const ON_PARTS := "It can also sit on another part"
const LIMB_TOOL := "Click the body: a limb grows from the nearest vertebra; off the middle line it comes as a mirrored pair; drag to pull its tip"


## The hint for a part with this rule ({hosts, centerline}).
static func creature(rule: Dictionary) -> String:
	var hosts: Array = rule.get("hosts", [])
	var sentences := PackedStringArray()
	if hosts.has("spine"):
		var clauses := PackedStringArray([BODY])
		match String(rule.get("centerline", "allowed")):
			"required":
				clauses.append(MIDDLE_REQUIRED)
			"forbidden":
				clauses.append(MIDDLE_FORBIDDEN)
			_:
				clauses.append(MIDDLE_ALLOWED % snap_degrees())
		var first := ": ".join(clauses)
		if hosts.has("limb_end"):
			first += "; " + LIMB_END_TOO % end_percent()
		elif hosts.has("limb"):
			first += "; " + LIMB_TOO
		sentences.append(first)
	elif hosts.has("limb_end") and hosts.has("limb"):
		sentences.append(LIMB_AND_END % end_percent() + "; " + LIMB_TWIN)
	elif hosts.has("limb_end"):
		sentences.append(LIMB_END_ONLY + "; " + LIMB_TWIN)
	elif hosts.has("limb"):
		sentences.append(LIMB_ONLY + "; " + LIMB_TWIN)
	if hosts.has("part"):
		sentences.append(ON_PARTS)
	return ". ".join(sentences)


## The limb tool's hint.
static func limb_tool() -> String:
	return LIMB_TOOL


## How much of a limb counts as its end, in percent: the part past LIMB_END_FROM_U per mille.
static func end_percent() -> int:
	return roundi((1000 - Picking.LIMB_END_FROM_U) / 10.0)


## The middle-line snap as whole degrees: MIDDLE_SNAP per mille of a turn.
static func snap_degrees() -> int:
	return roundi(Picking.MIDDLE_SNAP * 360.0 / 1000.0)
