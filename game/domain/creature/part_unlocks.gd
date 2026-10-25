extends RefCounted
## Creature part unlocks (PROPOSED; owner direction 2026-10-24, "Spore but better": parts are found in the world and
## then appear in the editor, as Spore's creature stage does). A new lineage starts with the starter parts
## (creature_stage.json "pickups" "starter_parts"); every other part type is locked until the creature walks over its
## pickup in the world. A find is a lineage event (Bible section 18: the lineage history records discoveries), so it
## lives in the save's lineage_history as {"event": "found_part", "part": type, "creature_generation": n,
## "source": "world" or "preset"}: no new save key and no schema change. A part already on the body is always usable,
## and a preset's parts count as found once its body is committed (source "preset").
## Pure rules: no scene or file access.

const EVENT := "found_part"
const SOURCE_WORLD := "world"
const SOURCE_PRESET := "preset"


## The part types found so far, sorted, from a lineage history (entries that are not finds are skipped).
static func found(history: Array) -> Array:
	var seen := {}
	for entry in history:
		if entry is Dictionary and entry.get("event") == EVENT and entry.get("part") is String:
			seen[String(entry["part"])] = true
	var out := seen.keys()
	out.sort()
	return out


## The part types of a codec body dictionary, sorted and once each.
static func body_types(body: Dictionary) -> Array:
	var seen := {}
	for p in body.get("parts", []):
		if p is Dictionary and p.get("type") is String:
			seen[String(p["type"])] = true
	var out := seen.keys()
	out.sort()
	return out


## The locked part types: every type in `all_types` that is not a starter, not found in `history` and not on `body`.
## Sorted.
static func locked(all_types: Array, starters: Array, history: Array, body: Dictionary) -> Array:
	var open := {}
	for t in starters:
		open[String(t)] = true
	for t in found(history):
		open[t] = true
	for t in body_types(body):
		open[t] = true
	var out := []
	for t in all_types:
		if not open.has(String(t)):
			out.append(String(t))
	out.sort()
	return out


## The lineage event for finding `type` (see the header).
static func event(type: String, creature_generation: int, source: String = SOURCE_WORLD) -> Dictionary:
	return {"event": EVENT, "part": type, "creature_generation": creature_generation, "source": source}


## The events a committed body adds: one preset find for each part type on it that is still locked.
static func commit_events(body: Dictionary, locked_types: Array, creature_generation: int) -> Array:
	var out := []
	for t in body_types(body):
		if locked_types.has(t):
			out.append(event(t, creature_generation, SOURCE_PRESET))
	return out


## Up to `count` of the `locked_types` for one visit's pickups, drawn from `rng` without repeats (the list is taken in
## sorted order, so the draw depends only on the seed).
static func draw(locked_types: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var pool := locked_types.duplicate()
	pool.sort()
	var out := []
	while out.size() < count and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out
