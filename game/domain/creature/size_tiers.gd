extends RefCounted
## Body size tiers (IB-30 "Body scale range", Bible sections 7 and 12; PROPOSED): size is a trait with costs and
## payoffs. A body's existing overall scale, BodyDescription.reference_length_mm, is sorted into the tiers of tuning
## "size_tiers" (data/creature/creature_stage.json), and the tier gives multipliers for top speed, bite reach, energy
## use and turning. A large body reaches farther, spends more and turns slower; a small one is cheaper and nimbler
## with a shorter reach. The middle tier is all ones, so a body inside it keeps its numbers exactly.
## Nothing is persisted: the tier is derived from the body every time. Pure rules: no scene or file access.
## Loaded by path; no class_name.

const FACTORS: Array[String] = ["speed", "bite_reach", "energy_use", "turn"]
const NEUTRAL := {"id": "", "speed": 1.0, "bite_reach": 1.0, "energy_use": 1.0, "turn": 1.0}


## The tier of a body `length_mm` long: {id, speed, bite_reach, energy_use, turn}. `tuning` is the "size_tiers"
## block, {tiers: [{id, min_mm, speed, bite_reach, energy_use, turn}, ...]}; a body belongs to the tier with the
## largest min_mm it reaches (min_mm is inclusive; whole millimetres, so the thresholds are exact, and the order of
## the list does not matter: equal min_mm ties go to the smaller id). An empty block, or a body below every min_mm,
## gives NEUTRAL.
static func of_length(length_mm: int, tuning: Dictionary) -> Dictionary:
	var best := {}
	for t: Dictionary in tuning.get("tiers", []):
		var at := int(t["min_mm"])
		if length_mm < at:
			continue
		if best.is_empty() or at > int(best["min_mm"]) or (at == int(best["min_mm"]) and str(t["id"]) < str(best["id"])):
			best = t
	if best.is_empty():
		return NEUTRAL.duplicate()
	var out := {"id": str(best["id"])}
	for k in FACTORS:
		out[k] = float(best.get(k, 1.0))
	return out


## The tier of a body description (its reference_length_mm).
static func of_body(body: RefCounted, tuning: Dictionary) -> Dictionary:
	return of_length(int(body.reference_length_mm), tuning)
