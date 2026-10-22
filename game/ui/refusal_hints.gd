class_name RefusalHints
extends RefCounted
## Decides when a refused meal becomes a hint for the player, and its words (M1 step 2). The pool
## asks once per "refused" event; the HUD shows what it returns, and the head-shake and refusal
## sound play with it, so text, motion and sound always agree. Times are sim seconds.
##
##   diet ("needs a jaw" / "needs a filter mouth"): only while touching; the same reason at most
##       once per DIET_REPEAT_S
##   "mouth is not facing it": after touching it for FACING_AFTER_S
##   "not hungry": at most once per FULL_REPEAT_S
##   anything else: as the rules give it

const DIET_REPEAT_S := 4.0
const FACING_AFTER_S := 0.5
const FULL_REPEAT_S := 5.0
const TEXTS := {
	"needs a jaw": "Needs a jaw: your filter mouth only eats plankton",
	"needs a filter mouth": "Needs a filter mouth: your jaw only eats carrion",
	"mouth is not facing it": "Turn your mouth toward it",
	"not hungry": "Full",
}

var _last_shown := {}   ## reason -> sim time it was last shown


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
	elif reason == "not hungry":
		repeat = FULL_REPEAT_S
	if reason.is_empty():
		return ""
	if repeat > 0.0 and _last_shown.has(reason) and now - float(_last_shown[reason]) < repeat:
		return ""
	_last_shown[reason] = now
	return str(TEXTS.get(reason, reason))


## Forgets what was shown (a new run or a respawn).
func reset() -> void:
	_last_shown.clear()
