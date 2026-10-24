class_name CreatureLevels
extends RefCounted
## Stat levels earned by doing (PROPOSED; owner direction 2026-10-24: "you can level up your strengths ... an
## incremental system", on top of stats that follow the body's physics). Four stats, each with its own experience:
##   speed     from distance walked or run
##   strength  from bites that land
##   toughness from hits taken
##   senses    from rivals first spotted (once per rival per life)
## Level n needs xp_base * n * (n + 1) / 2 experience, up to max_level; each level adds per_level to the stat's
## multiplier (1.5x at level 10 with the PROPOSED numbers), so the body's physics still dominates: a level-10 giant
## is still slower than a light sprinter. Numbers live in creature_stage.json under "levels". Pure rules: no scene
## or file access.

const STATS: PackedStringArray = ["speed", "strength", "toughness", "senses"]


## The level `xp` experience reaches.
static func level_of(xp: int, levels: Dictionary) -> int:
	var base := int(levels["xp_base"])
	var top := int(levels["max_level"])
	var n := 0
	while n < top and xp >= base * (n + 1) * (n + 2) / 2:
		n += 1
	return n


## The experience level `n` needs.
static func xp_for_level(n: int, levels: Dictionary) -> int:
	return int(levels["xp_base"]) * n * (n + 1) / 2


## A stat's multiplier at level `n`.
static func multiplier(n: int, levels: Dictionary) -> float:
	return 1.0 + float(levels["per_level"]) * clampi(n, 0, int(levels["max_level"]))


## {stat: level} from {stat: xp}; a missing stat is level 0.
static func levels_of(xp: Dictionary, levels: Dictionary) -> Dictionary:
	var out := {}
	for s in STATS:
		out[s] = level_of(int(xp.get(s, 0)), levels)
	return out


## CreatureStats.of's dictionary with the levels applied: speed (speed_mps and speed_factor), strength (bite_power),
## toughness (max_health), senses (sight_m, still within the tuning's sight cap). A copy; the input is untouched.
static func apply(stats: Dictionary, xp: Dictionary, tuning: Dictionary) -> Dictionary:
	var levels: Dictionary = tuning.get("levels", {})
	var out := stats.duplicate()
	if levels.is_empty():
		return out
	var lv := levels_of(xp, levels)
	var m_speed := multiplier(lv["speed"], levels)
	out["speed_mps"] = float(stats["speed_mps"]) * m_speed
	out["speed_factor"] = float(stats.get("speed_factor", 1.0)) * m_speed
	out["bite_power"] = float(stats["bite_power"]) * multiplier(lv["strength"], levels)
	out["max_health"] = float(stats["max_health"]) * multiplier(lv["toughness"], levels)
	out["sight_m"] = minf(float(stats["sight_m"]) * multiplier(lv["senses"], levels), float(tuning["sight"]["max_m"]))
	out["levels"] = lv
	return out


## Problems with a saved experience dictionary: {stat: whole number >= 0} over STATS only.
static func problems(xp: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not xp is Dictionary:
		out.append("Creature experience must be an object.")
		return out
	for k in xp:
		if not STATS.has(String(k)):
			out.append("Unknown creature stat '%s'." % k)
		elif not (xp[k] is int or (xp[k] is float and float(xp[k]) == floorf(float(xp[k])))) or int(xp[k]) < 0:
			out.append("Creature %s experience must be a whole number, at least 0." % k)
	return out
