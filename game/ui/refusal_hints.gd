class_name RefusalHints
extends RefCounted
## Decides when a refused meal becomes a hint for the player, and its words (M1 step 2). The pool
## asks once per "refused" event; the HUD shows what it returns, and the head-shake and refusal
## sound play with it, so text, motion and sound always agree. Times are sim seconds.
##
##   diet ("needs a jaw" / "needs a filter mouth"): only while touching; the same reason at most
##       once per DIET_REPEAT_S
##   "mouth is not facing it": after touching it for FACING_AFTER_S, then at most once per
##       FACING_REPEAT_S (the sim repeats the refusal every 0.5 s while the contact lasts)
##   "not hungry": at most once per FULL_REPEAT_S
##   anything else: as the rules give it
##
## Attack refusals (M1 step 3, the cell's automatic bite and ram) come as "attack_refused" events,
## which the sim sends only for reasons the player can act on and at most every 0.5 s per
## creature; consider_attack() words them (ATTACK_TEXTS) and shows each at most once per
## ATTACK_REPEAT_S, so pressing against a creature does not repeat the hint and its sound.

const DIET_REPEAT_S := 4.0
const FACING_AFTER_S := 0.5
const FACING_REPEAT_S := 4.0
const FULL_REPEAT_S := 5.0
const TEXTS := {
	"needs a jaw": "Needs a jaw: your filter mouth only eats plankton",
	"needs a filter mouth": "Needs a filter mouth: your jaw only eats carrion",
	"mouth is not facing it": "Turn your mouth toward it",
	"not hungry": "Full",
}

## The cell's attack refusals worth a hint, and their words.
const ATTACK_TEXTS := {
	"jaw is not facing it": "Turn your jaw toward it",
	"no spike points at it": "Point a spike at it",
	"too big to bite": "Too big to bite",
}
const ATTACK_REPEAT_S := 2.0

var _last_shown := {}   ## reason -> sim time it was last shown
var _last_attack := {}  ## attack reason -> sim time it was last shown


## True for refusals that are about what the body can eat.
static func is_diet(reason: String) -> bool:
	return reason.begins_with("needs a")


## The hint to show now for a "refused" event at sim time `now`, or "".
func consider(event: Dictionary, now: float) -> String:
	var reason := str(event.get("reason", ""))
	var touching := bool(event.get("touching", false))
	var repeat := 0.0
	if is_diet(reason):
		if not touching:
			return ""
		repeat = DIET_REPEAT_S
	elif reason == "mouth is not facing it":
		if not touching or float(event.get("contact_s", 0.0)) < FACING_AFTER_S:
			return ""
		repeat = FACING_REPEAT_S
	elif reason == "not hungry":
		repeat = FULL_REPEAT_S
	if reason.is_empty():
		return ""
	if repeat > 0.0 and _last_shown.has(reason) and now - float(_last_shown[reason]) < repeat:
		return ""
	_last_shown[reason] = now
	return str(TEXTS.get(reason, reason))


## The hint to show now for an "attack_refused" event at sim time `now`, or "" (a reason with no
## hint, or the same one shown less than ATTACK_REPEAT_S ago).
func consider_attack(event: Dictionary, now: float) -> String:
	var reason := str(event.get("reason", ""))
	if not ATTACK_TEXTS.has(reason):
		return ""
	if _last_attack.has(reason) and now - float(_last_attack[reason]) < ATTACK_REPEAT_S:
		return ""
	_last_attack[reason] = now
	return str(ATTACK_TEXTS[reason])


## Forgets what was shown (a new run or a respawn).
func reset() -> void:
	_last_shown.clear()
	_last_attack.clear()
