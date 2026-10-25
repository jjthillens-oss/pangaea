class_name SocialRules
extends RefCounted
## The Social stage's interaction rules (PROPOSED, docs/stages/social-plan.md sections 4, 7 and 9): one resolver
## for the four signals (check_signal, fitting_signal, respond), the orders (check_order), the learning rule
## (inherit_learning) and names (make_name). Pure rules: no scene, file, clock or input access; every random draw
## comes from a RandomNumberGenerator the caller seeds. The sim and the HUD previews call the same checks.
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


# --- Signals: read and answer (plan section 4). ------------------------------------------------------------------
#
# A signal's outcome depends only on which signal was chosen and on what the individual shows (its needs, its
# disposition and trust, its species' organs): never on when, how fast or in what rhythm it was pressed (Bible
# section 14 rules out a rhythm minigame). check_signal() says whether it can be given at all; a refusal names what
# is missing and spends nothing. respond() is the individual's answer.

const SIGNALS: Array[String] = ["sing", "display", "share", "calm"]
const ORDERS: Array[String] = ["follow", "wait", "investigate", "retreat", "assist"]
const DISMISS := "dismiss"
const RESPONSES: Array[String] = ["fits", "ok", "unsure", "startles", "busy"]


## Whether `kind` can be given from `actor` to `target` right now: {ok, reason, range_m}. A refusal costs nothing
## (no cooldown, no fruit). The checks, in order: a known signal; the target is not hostile (individual or group);
## the actor's cooldown is over; for Share, a body that can carry and a fruit carried; within range; for Display, the
## actor stands within signals.display.view_cone_deg of where the target faces.
## actor:  {position: Vector2, cooldown_t: int, carrying: int, traits: SocialTraits.of(...)}
## target: {position: Vector2, heading: Vector2, traits, hostile_left_t: int, group_hostile: bool}
static func check_signal(kind: String, actor: Dictionary, target: Dictionary, tuning: Dictionary) -> Dictionary:
	if not SIGNALS.has(kind):
		return _refuse("Unknown signal", 0.0)
	var range_m := signal_range(kind, actor["traits"], target["traits"], tuning)
	var left := int(target.get("hostile_left_t", 0))
	if left > 0:
		var secs := ceili(float(left) / float(tuning.get("tick_hz", TICKS_PER_SECOND)))
		return _refuse("It won't listen: you hurt it (%d s)" % secs, range_m)
	if bool(target.get("group_hostile", false)):
		return _refuse("They won't listen: you hurt them too often", range_m)
	if int(actor.get("cooldown_t", 0)) > 0:
		return _refuse("Wait a moment", range_m)
	if kind == "share":
		if not bool(actor["traits"].get("can_carry", false)):
			return _refuse("Your body can't carry: it needs a mouth or a hand", range_m)
		if int(actor.get("carrying", 0)) <= 0:
			return _refuse("Nothing to share: carry a fruit first", range_m)
	var apos: Vector2 = actor["position"]
	var tpos: Vector2 = target["position"]
	if apos.distance_to(tpos) > range_m:
		return _refuse("Too far: come within %s" % metres(range_m), range_m)
	if kind == "display" and not sees(target, apos, float(tuning["signals"]["display"]["view_cone_deg"])):
		return _refuse("It can't see you: get in front of it", range_m)
	return {"ok": true, "reason": "", "range_m": range_m}


## How far `kind` reaches from an actor with `actor_traits` to a target with `target_traits`, m: Sing the actor's
## voice_m times the target's hearing_mult; Display the target's sight, capped at display.range_cap_m; Share and
## Calm their range_m.
static func signal_range(kind: String, actor_traits: Dictionary, target_traits: Dictionary, tuning: Dictionary) -> float:
	var s: Dictionary = tuning["signals"]
	match kind:
		"sing":
			return float(actor_traits["voice_m"]) * float(target_traits.get("hearing_mult", 1.0))
		"display":
			return minf(float(target_traits.get("sight_m", 0.0)), float(s["display"]["range_cap_m"]))
		"share", "calm":
			return float(s[kind]["range_m"])
	return 0.0


## Whether `target` (facing target.heading) sees the spot `at`: within cone_deg of where it faces.
static func sees(target: Dictionary, at: Vector2, cone_deg: float) -> bool:
	var to: Vector2 = at - (target["position"] as Vector2)
	if to.length_squared() < 0.0001:
		return true
	var facing: Vector2 = target.get("heading", Vector2(0.0, -1.0))
	return absf(rad_to_deg(facing.angle_to(to))) <= cone_deg + 0.001


## Whether a loud signal (Sing, Display) is a signal of that kind.
static func is_loud(kind: String, tuning: Dictionary) -> bool:
	return bool((tuning["signals"] as Dictionary).get(kind, {}).get("loud", false))


## Whether the individual shows wariness: a wary disposition while its trust is below fit.wary_until_trust.
static func is_wary(target: Dictionary, tuning: Dictionary) -> bool:
	return String(target.get("disposition", "")) == "wary" \
			and float(target.get("trust", 0.0)) < float(tuning["fit"]["wary_until_trust"])


## The signal that fits what the individual shows, one fixed rule in order: hungry (hunger at fit.hungry_at or
## more) -> share; wary or frightened (fear at fit.frightened_at or more) -> calm; a display-rich species (at least
## fit.display_rich_at display organs) -> display; otherwise sing.
## target: {hunger, fear, disposition, trust, traits}
static func fitting_signal(target: Dictionary, tuning: Dictionary) -> String:
	var fit: Dictionary = tuning["fit"]
	if float(target.get("hunger", 0.0)) >= float(fit["hungry_at"]):
		return "share"
	if is_wary(target, tuning) or float(target.get("fear", 0.0)) >= float(fit["frightened_at"]):
		return "calm"
	if int((target.get("traits", {}) as Dictionary).get("display_count", 0)) >= int(fit["display_rich_at"]):
		return "display"
	return "sing"


## The mood word on the individual's tag, which shows what the fitting signal answers: hostile, scared, hungry, wary,
## at ease (trusting, or a band member), or its disposition (curious, warm).
## target: as fitting_signal, plus hostile_left_t, group_hostile and member.
static func mood(target: Dictionary, tuning: Dictionary) -> String:
	var fit: Dictionary = tuning["fit"]
	if int(target.get("hostile_left_t", 0)) > 0 or bool(target.get("group_hostile", false)):
		return "hostile"
	if float(target.get("fear", 0.0)) >= float(fit["frightened_at"]):
		return "scared"
	if float(target.get("hunger", 0.0)) >= float(fit["hungry_at"]):
		return "hungry"
	if is_wary(target, tuning):
		return "wary"
	if bool(target.get("member", false)) or float(target.get("trust", 0.0)) >= float(tuning["trust"]["join_at"]):
		return "at ease"
	var disposition := String(target.get("disposition", ""))
	return disposition if disposition == "curious" or disposition == "warm" else "at ease"


## The individual's answer to `kind`, given its `trust` now: {response, words, memory_kind, scale, gift_taken}.
## In order: busy (target.busy, or fear at fit.busy_fear_at or more) -> no memory; the fitting signal -> "fits",
## a strong friendly memory (responses.by_signal) scaled by `strength` (the actor's display strength for Display, 1
## otherwise); a loud signal to a wary or frightened individual -> "startles"; trust below 0 -> "unsure"; else "ok".
## There is no timing input: the same choice and the same individual always give the same answer.
static func respond(kind: String, target: Dictionary, trust: float, tuning: Dictionary, strength: float = 1.0) -> Dictionary:
	var t := target.duplicate()
	t["trust"] = trust
	var fit: Dictionary = tuning["fit"]
	var r: Dictionary = tuning["responses"]
	var response := "ok"
	if bool(t.get("busy", false)) or float(t.get("fear", 0.0)) >= float(fit["busy_fear_at"]):
		response = "busy"
	elif kind == fitting_signal(t, tuning):
		response = "fits"
	elif is_loud(kind, tuning) and (is_wary(t, tuning) or float(t.get("fear", 0.0)) >= float(fit["frightened_at"])):
		response = "startles"
	elif trust < 0.0:
		response = "unsure"
	var memory_kind := String(r[response]["memory"])
	if memory_kind == "by_signal":
		memory_kind = String(r["by_signal"][kind])
	return {"response": response, "words": String(r[response]["words"]), "memory_kind": memory_kind,
			"scale": strength if response == "fits" else 1.0, "gift_taken": kind == "share" and response != "busy"}


## Trust in words for the band cards: trusting (at trust.join_at or more), friendly (0 or more), unsure.
static func trust_word(trust: float, tuning: Dictionary) -> String:
	if trust >= float(tuning["trust"]["join_at"]):
		return "trusting"
	return "friendly" if trust >= 0.0 else "unsure"


# --- Orders (plan section 7). --------------------------------------------------------------------------------------

## Whether `companion` takes `order`: {ok, reason, ack, mode}. Every order is acknowledged (ack, in words) or refused
## with a reason. Refusals: not in the band; hostile; Assist during a fight by a role that does not fight ("no fighter,
## I'll gather", with mode "gather" as what it does instead); Investigate by a frightened companion (fear at
## orders.scared_fear or more, trust below orders.scared_trust_below) when the spot is within orders.near_hunter_m of
## the hunter. mode is "fight" or "gather" for Assist.
## companion: {role, fear, trust, hostile: bool, member: bool, home_name}
## context:   {in_fight: bool, spot_hunter_m: float (the spot's distance from the hunter; absent when unknown)}
static func check_order(order: String, companion: Dictionary, context: Dictionary, tuning: Dictionary) -> Dictionary:
	if not ORDERS.has(order) and order != DISMISS:
		return {"ok": false, "reason": "doesn't know that order", "ack": "", "mode": ""}
	if not bool(companion.get("member", false)):
		return {"ok": false, "reason": "is not in your band", "ack": "", "mode": ""}
	if bool(companion.get("hostile", false)) and order != DISMISS:
		return {"ok": false, "reason": "won't listen: you hurt it", "ack": "", "mode": ""}
	var o: Dictionary = tuning["orders"]
	var role := String(companion.get("role", ""))
	var fights := bool((tuning["roles"]["costs"] as Dictionary).get(role, {}).get("fights", true))
	match order:
		"follow":
			return _ack("follows you")
		"wait":
			return _ack("waits here")
		"retreat":
			return _ack("heads home")
		DISMISS:
			return _ack("goes back to the %s" % String(companion.get("home_name", "den")))
		"investigate":
			var near := float(context.get("spot_hunter_m", INF)) <= float(o["near_hunter_m"])
			if near and float(companion.get("fear", 0.0)) >= float(o["scared_fear"]) \
					and float(companion.get("trust", 0.0)) < float(o["scared_trust_below"]):
				return {"ok": false, "reason": "too scared: the hunter is near", "ack": "", "mode": ""}
			return _ack("goes to look")
	# assist
	if bool(context.get("in_fight", false)):
		if not fights:
			return {"ok": false, "reason": "no fighter, I'll gather", "ack": "", "mode": "gather"}
		var fight := _ack("with you")
		fight["mode"] = "fight"
		return fight
	var gather := _ack("gathers food")
	gather["mode"] = "gather"
	return gather


# --- Learning and names (plan sections 5 and 9). ------------------------------------------------------------------

## The routes an offspring inherits from its parent's `parent_learned` {route: {uses, inherited, idle}} (IB-19), one
## explicit rule: a route the parent used at least learning.inherit_at_uses times passes on fresh (inherited, idle 0);
## an inherited route passes on while it was used at all this generation, else its idle count grows by one, and at
## learning.forget_after_generations idle generations it is forgotten. Anything else is not inherited. Routes come
## out in name order.
static func inherit_learning(parent_learned: Dictionary, tuning: Dictionary) -> Dictionary:
	var l: Dictionary = tuning["learning"]
	var keys := parent_learned.keys()
	keys.sort()
	var out := {}
	for route in keys:
		var r: Dictionary = parent_learned[route]
		var uses := int(r.get("uses", 0))
		if uses >= int(l["inherit_at_uses"]):
			out[route] = {"uses": 0, "inherited": true, "idle": 0}
		elif bool(r.get("inherited", false)):
			var idle := 0 if uses > 0 else int(r.get("idle", 0)) + 1
			if idle < int(l["forget_after_generations"]):
				out[route] = {"uses": 0, "inherited": true, "idle": idle}
	return out


## A name of names.parts[0]..names.parts[-1] syllables drawn from `rng` (the world seed's name stream), the first
## letter capitalised.
static func make_name(rng: RandomNumberGenerator, syllables: Array, parts: Array) -> String:
	var n := rng.randi_range(int(parts[0]), int(parts[parts.size() - 1]))
	var out := ""
	for i in n:
		out += String(syllables[rng.randi_range(0, syllables.size() - 1)])
	return out.substr(0, 1).to_upper() + out.substr(1)


## A distance in words: "6 m", "2.5 m".
static func metres(m: float) -> String:
	if absf(m - roundf(m)) < 0.05:
		return "%d m" % roundi(m)
	return "%.1f m" % m


static func _refuse(reason: String, range_m: float) -> Dictionary:
	return {"ok": false, "reason": reason, "range_m": range_m}


static func _ack(words: String) -> Dictionary:
	return {"ok": true, "reason": "", "ack": words, "mode": ""}
