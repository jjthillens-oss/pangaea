class_name SocialRules
extends RefCounted
## The Social stage's interaction rules (PROPOSED, docs/stages/social-plan.md sections 4, 7 and 9). Pure rules: no
## scene, file, clock or input access; every random draw comes from a RandomNumberGenerator the caller seeds.
##
## Durations: the tuning file states them in seconds (keys ending "_s"); with_ticks() converts each of them once, at
## load, to whole ticks under the same key ending "_t" (rates such as "_per_s" are left alone), and every rule here
## and in SocialMemory, CompanionBrain and HunterBrain reads only the "_t" keys.

const TICKS_PER_SECOND := 60


## Seconds to whole ticks: rounded, and never 0 for a positive duration.
static func to_ticks(seconds: float, hz: int = TICKS_PER_SECOND) -> int:
	if seconds <= 0.0:
		return 0
	return maxi(1, roundi(seconds * hz))


## A deep copy of `tuning` with a whole-tick "<name>_t" next to every duration "<name>_s" (in nested dictionaries
## and in dictionaries inside arrays), and "tick_hz" at the top.
static func with_ticks(tuning: Dictionary, hz: int = TICKS_PER_SECOND) -> Dictionary:
	var out: Dictionary = tuning.duplicate(true)
	_add_ticks(out, hz)
	out["tick_hz"] = hz
	return out


static func _add_ticks(d: Dictionary, hz: int) -> void:
	for key in d.keys():
		var v: Variant = d[key]
		if v is Dictionary:
			_add_ticks(v, hz)
		elif v is Array:
			for item in v:
				if item is Dictionary:
					_add_ticks(item, hz)
		elif (v is float or v is int) and String(key).ends_with("_s") and not String(key).ends_with("_per_s"):
			d[String(key).trim_suffix("_s") + "_t"] = to_ticks(float(v), hz)
