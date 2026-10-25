class_name HunterBrain
extends RefCounted
## The Social stage's predator (a prowler; PROPOSED, docs/stages/social-plan.md section 8; Bible sections 7 and 13:
## a readable tell before it commits, bounded pursuit, disengagement). It decides from percepts alone: no sim, no
## ids, no positions. Pure rules: no scene, file, clock or input access and no randomness of its own.
## tests/test_social_purity.gd scans this file.
##
## Percepts (unit Vector2 directions on the ground, x along +X and y along +Z; {} means none):
##   target:   {dir, dist, group_near, in_nest} of the prey it sees (the sim applies its sight and the scout's
##             noticed bonus); group_near counts the target's group within hunter.group_radius_m of it; in_nest is
##             true while the target stands inside the nest
##   waypoint: {dir, dist} of its current patrol point
##   lair:     {dir, dist, radius}
##   nest:     {dir, dist, radius} of the band's nest, which it never steps into
##   nerve:    what it has left (bites cost it nerve; the sim refills it after a "rested" report)
##   heading, elapsed_t (ticks since its last decision, default 1)
## The cycle: patrol -> investigate (it stops side-on for hunter.investigate_t: the tell) -> pursue (at most
## hunter.pursue_t, only while it sees the target, fewer than hunter.deterred_by_group stand by it, and the target
## is outside the nest) -> strike (within strike_reach_m, then strike_cooldown_t) -> disengage (after the pursuit
## time, at nerve 0, when the target reaches the nest, is lost, or the group stands together; it backs off towards
## its lair for disengage_t and ignores prey) -> rest at the lair for rest_t -> patrol.
## The decision: {state, heading, throttle, strike: bool, advance: bool (move on to the next waypoint),
## report: {} or {kind: "investigating"|"pursuing"|"disengaged" {why}|"rested"}}.

const STATES: Array[String] = ["patrol", "investigate", "pursue", "strike", "disengage", "rest"]
const PATROL_THROTTLE := 0.4
## How far ahead of the nest's edge it starts to steer around it.
const NEST_LOOK_M := 2.5


static func fresh_memory(heading: Vector2) -> Dictionary:
	return {"state": "patrol", "timer": 0, "cooldown": 0, "heading": heading}


static func decide(percepts: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var h: Dictionary = tuning["hunter"]
	var elapsed := int(percepts.get("elapsed_t", 1))
	memory["cooldown"] = maxi(0, int(memory.get("cooldown", 0)) - elapsed)
	var out := _choose(percepts, memory, h, tuning, elapsed)
	var nest: Dictionary = percepts.get("nest", {})
	if not nest.is_empty():
		out["heading"] = keep_out_of_nest(out["heading"], nest, float(h["nest_margin_m"]))
	memory["state"] = out["state"]
	var heading: Vector2 = out["heading"]
	if heading.length_squared() > 0.0:
		memory["heading"] = heading
	return out


static func _choose(p: Dictionary, memory: Dictionary, h: Dictionary, tuning: Dictionary, elapsed: int) -> Dictionary:
	var target: Dictionary = p.get("target", {})
	var heading: Vector2 = p.get("heading", memory.get("heading", Vector2(0.0, -1.0)))
	var state := String(memory.get("state", "patrol"))
	match state:
		"investigate":
			memory["timer"] = int(memory["timer"]) - elapsed
			if target.is_empty() or bool(target.get("in_nest", false)):
				return _patrol(p, memory, tuning)
			if int(memory["timer"]) > 0:
				# The tell: it stops and turns side-on to what it watches.
				return _act("investigate", (target["dir"] as Vector2).orthogonal(), 0.0)
			if _deterred(target, h):
				return _disengage(memory, h, p, "group")
			memory["timer"] = int(h["pursue_t"])
			var out := _pursue(target, memory, h)
			out["report"] = {"kind": "pursuing"}
			return out
		"pursue", "strike":
			memory["timer"] = int(memory["timer"]) - elapsed
			var why := ""
			if int(p.get("nerve", h["nerve"])) <= 0:
				why = "nerve"
			elif target.is_empty():
				why = "lost"
			elif bool(target.get("in_nest", false)):
				why = "nest"
			elif _deterred(target, h):
				why = "group"
			elif int(memory["timer"]) <= 0:
				why = "time"
			if why != "":
				return _disengage(memory, h, p, why)
			return _pursue(target, memory, h)
		"disengage":
			memory["timer"] = int(memory["timer"]) - elapsed
			if int(memory["timer"]) <= 0:
				memory["state"] = "rest"
				memory["timer"] = int(h["rest_t"])
				return _rest(p, memory, h, elapsed, false)
			return _act("disengage", _lair_dir(p, heading), 1.0)
		"rest":
			return _rest(p, memory, h, elapsed, true)
	# patrol
	if not target.is_empty() and not bool(target.get("in_nest", false)):
		memory["timer"] = int(h["investigate_t"])
		var tell := _act("investigate", (target["dir"] as Vector2).orthogonal(), 0.0)
		tell["report"] = {"kind": "investigating"}
		return tell
	return _patrol(p, memory, tuning)


static func _patrol(p: Dictionary, _memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var wp: Dictionary = p.get("waypoint", {})
	var heading: Vector2 = p.get("heading", Vector2(0.0, -1.0))
	if wp.is_empty():
		return _act("patrol", heading, 0.0)
	var out := _act("patrol", wp["dir"], PATROL_THROTTLE)
	out["advance"] = float(wp["dist"]) <= float(tuning["orders"]["arrive_m"])
	return out


static func _pursue(target: Dictionary, memory: Dictionary, h: Dictionary) -> Dictionary:
	var out := _act("pursue", target["dir"], 1.0)
	if float(target["dist"]) <= float(h["strike_reach_m"]) and int(memory["cooldown"]) == 0:
		out["state"] = "strike"
		out["strike"] = true
		memory["cooldown"] = int(h["strike_cooldown_t"])
	return out


static func _disengage(memory: Dictionary, h: Dictionary, p: Dictionary, why: String) -> Dictionary:
	memory["timer"] = int(h["disengage_t"])
	var heading: Vector2 = p.get("heading", Vector2(0.0, -1.0))
	var out := _act("disengage", _lair_dir(p, heading), 1.0)
	out["report"] = {"kind": "disengaged", "why": why}
	return out


## Rest: walk back to the lair, then stand there for hunter.rest_t; then patrol again (and report "rested").
static func _rest(p: Dictionary, memory: Dictionary, h: Dictionary, elapsed: int, count: bool) -> Dictionary:
	var lair: Dictionary = p.get("lair", {})
	var heading: Vector2 = p.get("heading", Vector2(0.0, -1.0))
	if not lair.is_empty() and float(lair["dist"]) > float(lair.get("radius", 1.0)):
		return _act("rest", lair["dir"], PATROL_THROTTLE)
	if count:
		memory["timer"] = int(memory["timer"]) - elapsed
	if int(memory["timer"]) <= 0:
		memory["state"] = "patrol"
		var out := _act("patrol", heading, 0.0)
		out["report"] = {"kind": "rested"}
		return out
	return _act("rest", heading, 0.0)


static func _deterred(target: Dictionary, h: Dictionary) -> bool:
	return int(target.get("group_near", 0)) >= int(h["deterred_by_group"])


static func _lair_dir(p: Dictionary, fallback: Vector2) -> Vector2:
	var lair: Dictionary = p.get("lair", {})
	return lair["dir"] if not lair.is_empty() else fallback


## `heading` changed so that it never takes the hunter into the nest: within nest radius + margin + NEST_LOOK_M the
## part of the heading towards the nest's centre is removed (it slides round the edge), and inside radius + margin
## it heads straight out.
static func keep_out_of_nest(heading: Vector2, nest: Dictionary, margin: float) -> Vector2:
	var to_nest: Vector2 = nest["dir"]
	var dist := float(nest["dist"])
	var edge := float(nest["radius"]) + margin
	if dist <= edge:
		return -to_nest
	if dist > edge + NEST_LOOK_M:
		return heading
	var inward := heading.dot(to_nest)
	if inward <= 0.0:
		return heading
	var slide := heading - to_nest * inward
	if slide.length_squared() < 0.0001:
		slide = to_nest.orthogonal()
	return slide.normalized()


static func _act(state: String, heading: Vector2, throttle: float) -> Dictionary:
	var dir := heading.normalized() if heading.length_squared() > 0.0 else Vector2(0.0, -1.0)
	return {"state": state, "heading": dir, "throttle": throttle, "strike": false, "advance": false, "report": {}}
