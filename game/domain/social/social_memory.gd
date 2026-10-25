class_name SocialMemory
extends RefCounted
## What an individual remembers of the player, and the group's reputation (PROPOSED, docs/stages/social-plan.md
## section 5; Bible section 8: relationships persist, but a single accident never becomes permanent war). Pure static
## functions on plain arrays and dictionaries; no scene, file or clock access (the tick is passed in).
##
## A memory is an Array of entries {kind, tick, scale}. Each kind has a weight and a lifetime (tuning memory.kinds,
## life_t in ticks after SocialRules.with_ticks): an entry's weight fades linearly from weight * scale to nothing over
## its lifetime and then drops out. At most memory.cap entries are kept; when one more arrives the weakest goes (the
## smallest faded weight by size, good or bad), then the oldest, ties broken by kind.
##
## Trust = disposition base + the faded weights + reputation * reputation.weight, clamped to trust.min .. trust.max.
## Reputation belongs to a group (the band, the loner). Each event moves it by reputation.rate times the event's
## weight, never by more than reputation.step_cap, and it does not fade. A group refuses everything only at
## reputation.hostile_at. An individual turns hostile for hostile.lasts_t after hostile.bites bites within
## hostile.window_t, and listens again afterwards: nothing is "for life".

const BITTEN := "bitten"


static func entry(kind: String, tick: int, scale: float = 1.0) -> Dictionary:
	return {"kind": kind, "tick": tick, "scale": scale}


## `memory` with a new entry of `kind` at `tick`, expired entries pruned, and at most memory.cap entries kept. The
## input array is left unchanged. An unknown kind is ignored.
static func add(memory: Array, kind: String, tick: int, tuning: Dictionary, scale: float = 1.0) -> Array:
	var out := prune(memory, tick, tuning)
	if not (tuning["memory"]["kinds"] as Dictionary).has(kind):
		return out
	out.append(entry(kind, tick, scale))
	var cap := int(tuning["memory"]["cap"])
	while out.size() > cap:
		out.remove_at(_weakest(out, tick, tuning))
	return out


## The index of the entry to forget first: the smallest faded weight by size, then the oldest, then by kind.
static func _weakest(memory: Array, tick: int, tuning: Dictionary) -> int:
	var best := 0
	for i in range(1, memory.size()):
		var a: Dictionary = memory[i]
		var b: Dictionary = memory[best]
		var wa := absf(weight_at(a, tick, tuning))
		var wb := absf(weight_at(b, tick, tuning))
		if wa < wb or (is_equal_approx(wa, wb) and (int(a["tick"]) < int(b["tick"])
				or (int(a["tick"]) == int(b["tick"]) and String(a["kind"]) < String(b["kind"])))):
			best = i
	return best


## The entry's weight at `tick`: weight * scale, fading linearly to 0 over the kind's lifetime; 0 once it is over,
## for an unknown kind, or before the entry was made.
static func weight_at(e: Dictionary, tick: int, tuning: Dictionary) -> float:
	var kinds: Dictionary = tuning["memory"]["kinds"]
	if not kinds.has(e["kind"]):
		return 0.0
	var k: Dictionary = kinds[e["kind"]]
	var life := int(k["life_t"])
	var age := tick - int(e["tick"])
	if life <= 0 or age < 0 or age >= life:
		return 0.0
	return float(k["weight"]) * float(e.get("scale", 1.0)) * (1.0 - float(age) / float(life))


## The entries still alive at `tick` (in their order).
static func prune(memory: Array, tick: int, tuning: Dictionary) -> Array:
	var out := []
	var kinds: Dictionary = tuning["memory"]["kinds"]
	for e in memory:
		if kinds.has(e["kind"]) and tick - int(e["tick"]) < int(kinds[e["kind"]]["life_t"]):
			out.append(e)
	return out


## The sum of the faded weights at `tick`.
static func feeling(memory: Array, tick: int, tuning: Dictionary) -> float:
	var total := 0.0
	for e in memory:
		total += weight_at(e, tick, tuning)
	return total


## Trust at `tick`: base (the disposition's, trust.base) + the faded weights + reputation * reputation.weight,
## clamped to trust.min .. trust.max.
static func trust(memory: Array, tick: int, base: float, reputation: float, tuning: Dictionary) -> float:
	var t: Dictionary = tuning["trust"]
	var raw := base + feeling(memory, tick, tuning) + reputation * float(tuning["reputation"]["weight"])
	return clampf(raw, float(t["min"]), float(t["max"]))


## The tick until which the individual stays hostile when it has been bitten hostile.bites times within
## hostile.window_t up to `tick`: tick + hostile.lasts_t; otherwise 0. Call it after adding a bite and keep the
## larger of this and any hostility it already has.
static func hostile_after(memory: Array, tick: int, tuning: Dictionary) -> int:
	var h: Dictionary = tuning["hostile"]
	var bites := 0
	for e in memory:
		var age := tick - int(e["tick"])
		if String(e["kind"]) == BITTEN and age >= 0 and age < int(h["window_t"]):
			bites += 1
	return tick + int(h["lasts_t"]) if bites >= int(h["bites"]) else 0


## Reputation after one event of `weight` (a memory kind's weight times its scale): moved by reputation.rate times
## the weight, at most reputation.step_cap either way, and kept within reputation.min .. reputation.max.
static func reputation_after(reputation: float, weight: float, tuning: Dictionary) -> float:
	var r: Dictionary = tuning["reputation"]
	var step := clampf(weight * float(r["rate"]), -float(r["step_cap"]), float(r["step_cap"]))
	return clampf(reputation + step, float(r["min"]), float(r["max"]))


## The weight one event of `kind` carries into reputation_after (weight * scale; 0 for an unknown kind).
static func event_weight(kind: String, tuning: Dictionary, scale: float = 1.0) -> float:
	var kinds: Dictionary = tuning["memory"]["kinds"]
	return float(kinds[kind]["weight"]) * scale if kinds.has(kind) else 0.0


## Whether a group with this reputation refuses everything (at or below reputation.hostile_at).
static func group_hostile(reputation: float, tuning: Dictionary) -> bool:
	return reputation <= float(tuning["reputation"]["hostile_at"])
