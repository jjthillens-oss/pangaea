class_name CompanionBrain
extends RefCounted
## A Social-stage individual's brain (PROPOSED, docs/stages/social-plan.md sections 5 to 8; Bible sections 8 and
## 13). It decides from percepts alone: it never sees the sim, another body's id or a position, only directions and
## distances the sim says it can sense. Pure rules: no scene, file, clock or input access and no randomness of its
## own (the sim hands it one seeded draw a decision as `noise`). tests/test_social_purity.gd scans this file.
##
## Percepts (every direction is a unit Vector2 on the ground, x along +X and y along +Z; {} means none):
##   leader:     {dir, dist} of the one this companion follows (band members only; {} when it has fainted, or for a
##               non-member)
##   order:      {name, target_dir, target_dist, ticks_left, mode} the order it is carrying out, or {}. ticks_left
##               is the time the order has left (-1: no limit); mode is "fight" or "gather" for assist.
##   threat:     {dir, dist} of a predator in sight, or {}
##   foe:        {dir, dist} of what the leader is fighting, in sight, or {}
##   food:       {dir, dist, reserved_ok} of the nearest ripe bush it may pick, or {}
##   home:       {dir, dist, radius} of where it goes without a leader (its home site, or the nest)
##   nest:       {dir, dist, radius} of the band's nest (where fruit is delivered)
##   attention:  {dir, dist, response} while it answers a signal ("welcomes", "listens", "unsure", "backs"), or {}
##   visitor:    {dir, dist} of a stranger nearby it can see (non-members only), or {}
##   carrying, fear (0..1), hunger (0..1), role, disposition, heading, bite_reach, noise (-1..1), elapsed_t (ticks
##   since its last decision, default 1)
## The decision: {state, heading: Vector2, throttle: 0..1, bite: bool, report: {} or {kind, ...}}. States: idle,
## forage, follow, wait, investigate, retreat, assist, flee, socialize, recover, return. Reports, once per order:
## "arrived" (at the spot or the nest), "cannot" {reason} (an investigation without progress for orders.stuck_t or out
## of time), "lost" (the leader is further than band.lost_m), "done" (an order ran out of time).
## Every order ends: by its own end state, its timeout, or when the leader is gone (then it goes home and waits).

const STATES: Array[String] = ["idle", "forage", "follow", "wait", "investigate", "retreat", "assist", "flee",
		"socialize", "recover", "return"]
const WALK := 0.45
const IDLE_WANDER := 0.15
## Getting this much closer to the spot counts as progress for an investigation.
const PROGRESS_M := 0.25
## A welcomed individual steps up to this distance and stops.
const CLOSE_M := 2.0
## A wary non-member keeps a stranger at least this far away; a curious one turns to face it within VISIT_M.
const WARY_KEEP_M := 5.0
const VISIT_M := 9.0
const CANNOT_REACH := "can't reach that spot"


static func fresh_memory(heading: Vector2) -> Dictionary:
	return {"state": "idle", "heading": heading, "order": "", "phase": "", "best_m": -1.0, "stuck_t": 0,
			"reported": false}


static func decide(percepts: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var order: Dictionary = percepts.get("order", {})
	var order_name := String(order.get("name", ""))
	if order_name != String(memory.get("order", "")):
		memory["order"] = order_name
		memory["phase"] = "go"
		memory["best_m"] = -1.0
		memory["stuck_t"] = 0
		memory["reported"] = false
	var out := _choose(percepts, memory, tuning)
	memory["state"] = out["state"]
	var h: Vector2 = out["heading"]
	if h.length_squared() > 0.0:
		memory["heading"] = h
	return out


static func _choose(p: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var order: Dictionary = p.get("order", {})
	var name := String(order.get("name", ""))
	var threat: Dictionary = p.get("threat", {})
	var fighting := name == "assist" and String(order.get("mode", "")) == "fight" and fights(String(p.get("role", "")), tuning)
	if not threat.is_empty() and not fighting and float(p.get("fear", 0.0)) >= flee_fear(String(p.get("role", "")), tuning):
		return _act("flee", -(threat["dir"] as Vector2), 1.0)
	if name != "" and name != "investigate" and int(order.get("ticks_left", -1)) == 0:
		# Out of time: it says so once and goes back to the leader (or home without one).
		var over := _come_back(p, tuning)
		if not memory["reported"]:
			memory["reported"] = true
			over["report"] = {"kind": "done"}
		return over
	match name:
		"follow":
			return _follow(p, memory, tuning)
		"wait":
			return _hold_at(p, order, "wait", tuning)
		"retreat":
			var r := _hold_at(p, order, "retreat", tuning)
			if r["state"] == "wait" and not memory["reported"]:
				memory["reported"] = true
				r["report"] = {"kind": "arrived"}
			return r
		"investigate":
			return _investigate(p, order, memory, tuning)
		"assist":
			return _assist(p, order, memory, tuning)
	var attention: Dictionary = p.get("attention", {})
	if not attention.is_empty():
		return _answer(attention)
	if not (p.get("leader", {}) as Dictionary).is_empty():
		return _follow(p, memory, tuning)
	return _live_at_home(p, tuning)


## Follow: keep within band.follow_m of the leader; past band.lost_m it says "lost" and goes home.
static func _follow(p: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var leader: Dictionary = p.get("leader", {})
	if leader.is_empty():
		return _go_home(p, tuning)
	var band: Dictionary = tuning["band"]
	var dist := float(leader["dist"])
	var dir: Vector2 = leader["dir"]
	if dist > float(band["lost_m"]):
		var out := _go_home(p, tuning)
		if not memory["reported"]:
			memory["reported"] = true
			out["report"] = {"kind": "lost"}
		return out
	var follow_m := float(band["follow_m"])
	if dist > follow_m:
		return _act("follow", dir, 1.0 if dist > follow_m + float(band["spacing_m"]) else 0.6)
	return _act("follow", dir, 0.0)


## Walk to the order's spot and stand there (wait, retreat).
static func _hold_at(p: Dictionary, order: Dictionary, moving_state: String, tuning: Dictionary) -> Dictionary:
	var arrive := float(tuning["orders"]["arrive_m"])
	if order.has("target_dir") and float(order.get("target_dist", 0.0)) > arrive:
		return _act(moving_state, order["target_dir"], 1.0 if moving_state == "retreat" else WALK)
	return _act("wait", p.get("heading", Vector2(0.0, -1.0)), 0.0)


## Investigate: go to the spot; report "arrived" there, or "cannot" without progress for orders.stuck_t or when the
## order runs out; then go back to the leader (or home without one).
static func _investigate(p: Dictionary, order: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	if memory["phase"] == "go":
		var orders: Dictionary = tuning["orders"]
		var dist := float(order.get("target_dist", 0.0))
		var report := {}
		if dist <= float(orders["arrive_m"]):
			report = {"kind": "arrived"}
		elif int(order.get("ticks_left", -1)) == 0:
			report = {"kind": "cannot", "reason": CANNOT_REACH}
		else:
			var best := float(memory["best_m"])
			if best < 0.0 or dist < best - PROGRESS_M:
				memory["best_m"] = dist
				memory["stuck_t"] = 0
			else:
				memory["stuck_t"] = int(memory["stuck_t"]) + int(p.get("elapsed_t", 1))
			if int(memory["stuck_t"]) >= int(orders["stuck_t"]):
				report = {"kind": "cannot", "reason": CANNOT_REACH}
		if report.is_empty():
			return _act("investigate", order["target_dir"], 1.0)
		memory["phase"] = "back"
		memory["reported"] = true
		var back := _come_back(p, tuning)
		back["report"] = report
		return back
	return _come_back(p, tuning)


static func _come_back(p: Dictionary, tuning: Dictionary) -> Dictionary:
	var leader: Dictionary = p.get("leader", {})
	if leader.is_empty():
		return _go_home(p, tuning)
	if float(leader["dist"]) > float(tuning["band"]["follow_m"]):
		return _act("return", leader["dir"], 1.0)
	return _act("follow", leader["dir"], 0.0)


## Assist: a fighter on a fight goes for the foe and bites within reach; everyone else gathers fruit for the nest.
static func _assist(p: Dictionary, order: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var foe: Dictionary = p.get("foe", {})
	if String(order.get("mode", "")) == "fight" and fights(String(p.get("role", "")), tuning) and not foe.is_empty():
		var out := _act("assist", foe["dir"], 1.0)
		var reach := float(p.get("bite_reach", 0.0))
		out["bite"] = reach > 0.0 and float(foe["dist"]) <= reach
		return out
	return _gather(p, memory, tuning)


## Gather: carry fruit to the nest; otherwise walk to a bush it may pick (and stand at it while picking).
static func _gather(p: Dictionary, memory: Dictionary, tuning: Dictionary) -> Dictionary:
	var arrive := float(tuning["orders"]["arrive_m"])
	if int(p.get("carrying", 0)) > 0:
		var nest: Dictionary = p.get("nest", {})
		if not nest.is_empty() and float(nest["dist"]) > float(nest.get("radius", arrive)) * 0.5:
			return _act("forage", nest["dir"], 1.0)
		return _act("forage", p.get("heading", Vector2(0.0, -1.0)), 0.0)
	var food: Dictionary = p.get("food", {})
	if not food.is_empty() and bool(food.get("reserved_ok", true)):
		return _act("forage", food["dir"], 0.0 if float(food["dist"]) <= arrive else 1.0)
	return _follow(p, memory, tuning)


## Answer a signal with movement that backs up the caption: closer when welcomed, still when listening, back when
## startled.
static func _answer(attention: Dictionary) -> Dictionary:
	var dir: Vector2 = attention["dir"]
	match String(attention.get("response", "")):
		"welcomes":
			return _act("socialize", dir, WALK if float(attention["dist"]) > CLOSE_M else 0.0)
		"backs":
			return _act("socialize", -dir, WALK)
	return _act("socialize", dir, 0.0)


## Without a leader (fainted, dismissed, or never joined): back to its home and wait there.
static func _go_home(p: Dictionary, tuning: Dictionary) -> Dictionary:
	var home: Dictionary = p.get("home", {})
	if not home.is_empty() and float(home["dist"]) > float(home.get("radius", tuning["orders"]["arrive_m"])):
		return _act("return", home["dir"], WALK)
	return _act("wait", p.get("heading", Vector2(0.0, -1.0)), 0.0)


## A non-member's own life at home: flee is handled above; eat when hungry, keep a stranger at the distance its
## disposition wants, settle down when frightened, otherwise idle about its home.
static func _live_at_home(p: Dictionary, tuning: Dictionary) -> Dictionary:
	var home: Dictionary = p.get("home", {})
	var heading: Vector2 = p.get("heading", Vector2(0.0, -1.0))
	var food: Dictionary = p.get("food", {})
	if float(p.get("hunger", 0.0)) >= float(tuning["fit"]["hungry_at"]) and not food.is_empty() \
			and bool(food.get("reserved_ok", true)):
		return _act("forage", food["dir"], 0.0 if float(food["dist"]) <= float(tuning["orders"]["arrive_m"]) else WALK)
	var visitor: Dictionary = p.get("visitor", {})
	if not visitor.is_empty():
		var vdir: Vector2 = visitor["dir"]
		var vdist := float(visitor["dist"])
		if String(p.get("disposition", "")) == "wary" and vdist < WARY_KEEP_M:
			return _act("socialize", (-vdir).rotated(PI / 4.0), WALK)
		if String(p.get("disposition", "")) == "curious" and vdist < VISIT_M:
			return _act("socialize", vdir, 0.0)
	if float(p.get("fear", 0.0)) >= float(tuning["fit"]["frightened_at"]):
		return _act("recover", heading, 0.0)
	if not home.is_empty() and float(home["dist"]) > float(home.get("radius", tuning["orders"]["arrive_m"])):
		return _act("return", home["dir"], WALK)
	return _act("idle", heading.rotated(float(p.get("noise", 0.0)) * 0.3), IDLE_WANDER)


static func _act(state: String, heading: Vector2, throttle: float) -> Dictionary:
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2(0.0, -1.0)
	return {"state": state, "heading": h, "throttle": throttle, "bite": false, "report": {}}


## Whether a body of this role fights (roles.costs.<role>.fights, default yes).
static func fights(role: String, tuning: Dictionary) -> bool:
	return bool((tuning["roles"]["costs"] as Dictionary).get(role, {}).get("fights", true))


## The fear at which it runs from a threat in sight: roles.costs.<role>.flee_fear, else fit.busy_fear_at.
static func flee_fear(role: String, tuning: Dictionary) -> float:
	var cost: Dictionary = (tuning["roles"]["costs"] as Dictionary).get(role, {})
	return float(cost.get("flee_fear", tuning["fit"]["busy_fear_at"]))
