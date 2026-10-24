extends RefCounted
## The rival creatures' brain (PROPOSED, creature-stage-plan.md section 5). It decides from percepts alone, as the
## cell stage's CreatureBrain does: it never sees the sim, the other bodies' ids or the nest's tables, only what the
## sim tells it it can sense. Pure rules: no scene or file access, no randomness of its own (the sim hands it one
## seeded draw a tick as `noise`). tests/test_sim_purity.gd scans this file for sim access.
##
## Percepts (every direction is a unit Vector2 on the ground, x along +X and y along +Z; {} means nothing sensed):
##   food:      {dir, dist} of the nearest ripe fruit or meat in sight
##   creature:  {dir, dist, mass_ratio} of the nearest other creature in sight (their mass over mine)
##   fullness:  0..1 (0 starving, 1 full)
##   nest:      {dir, dist} of the nest (rivals keep to the field around it)
##   heading:   own forward direction
##   bite_reach: how far own mouth reaches, m (0 without a mouth)
##   noise:     a seeded draw in -1..1, for wandering
##   leader:    {dir, dist} of the creature this one has befriended and follows (allies only; {} otherwise)
##   foe:       {dir, dist} of the creature the leader is fighting, when in sight (allies only)
## Memory is the brain's own dictionary, returned updated: {mode, wander: Vector2, hold: int}.
## The decision: {mode: "wander"|"graze"|"flee"|"hunt"|"follow"|"assist", heading: Vector2, throttle: 0..1,
## bite: bool}. An ally (a leader percept) helps its leader fight, keeps up with it past `follow_m`, and otherwise
## lives as any rival does; the sim never shows an ally its leader or the leader's other allies as a creature.

const WANDER_THROTTLE := 0.3
const GRAZE_THROTTLE := 0.5
const WANDER_TURN_RAD := 0.04
## Past this distance from the nest a wanderer turns back towards it.
const RANGE_M := 60.0
## A wanderer that gets bored keeps its heading at least this many decisions.
const WANDER_HOLD := 90
## A grazer is interested in food only when it has room for it.
const GRAZE_BELOW := 0.9


static func fresh_memory(start_heading: Vector2) -> Dictionary:
	return {"mode": "wander", "wander": start_heading, "hold": 0}


## `tuning` is the "rivals" block of creature_stage.json: flee_mass_ratio, hunt_mass_ratio, hungry_below; and
## follow_m for allies (the "social" block's).
static func decide(percepts: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var leader: Dictionary = percepts.get("leader", {})
	if not leader.is_empty():
		var foe: Dictionary = percepts.get("foe", {})
		var reach := float(percepts.get("bite_reach", 0.0))
		var out := {}
		if not foe.is_empty() and reach > 0.0:
			out = {"mode": "assist", "heading": foe["dir"], "throttle": 1.0, "bite": float(foe["dist"]) <= reach}
		elif float(leader["dist"]) > float(tuning.get("follow_m", 5.0)):
			out = {"mode": "follow", "heading": leader["dir"], "throttle": 1.0, "bite": false}
		if not out.is_empty():
			memory["mode"] = out["mode"]
			return out
	var creature: Dictionary = percepts.get("creature", {})
	var food: Dictionary = percepts.get("food", {})
	var fullness := float(percepts.get("fullness", 1.0))
	var heading: Vector2 = percepts.get("heading", Vector2(0.0, -1.0))
	var hungry := fullness < float(tuning["hungry_below"])
	var out := {"mode": "wander", "heading": heading, "throttle": WANDER_THROTTLE, "bite": false}
	if not creature.is_empty() and float(creature["mass_ratio"]) >= float(tuning["flee_mass_ratio"]):
		out["mode"] = "flee"
		out["heading"] = -(creature["dir"] as Vector2)
		out["throttle"] = 1.0
	elif not creature.is_empty() and hungry and float(creature["mass_ratio"]) <= float(tuning["hunt_mass_ratio"]) \
			and float(percepts.get("bite_reach", 0.0)) > 0.0:
		out["mode"] = "hunt"
		out["heading"] = creature["dir"]
		out["throttle"] = 1.0
		out["bite"] = float(creature["dist"]) <= float(percepts.get("bite_reach", 0.0))
	elif not food.is_empty() and fullness < GRAZE_BELOW:
		out["mode"] = "graze"
		out["heading"] = food["dir"]
		out["throttle"] = GRAZE_THROTTLE if not hungry else 0.8
	else:
		var wander: Vector2 = memory.get("wander", heading)
		var hold := int(memory.get("hold", 0)) - 1
		wander = wander.rotated(WANDER_TURN_RAD * float(percepts.get("noise", 0.0)))
		var nest: Dictionary = percepts.get("nest", {})
		if not nest.is_empty() and float(nest["dist"]) > RANGE_M and hold <= 0:
			wander = nest["dir"]
			hold = WANDER_HOLD
		if wander.length_squared() < 1e-12:
			wander = heading
		memory["wander"] = wander.normalized()
		memory["hold"] = maxi(hold, 0)
		out["heading"] = memory["wander"]
	memory["mode"] = out["mode"]
	return out
