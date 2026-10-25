class_name CreatureStats
extends RefCounted
## Anatomy to play numbers (PROPOSED, creature-stage-plan.md section 5): what a body description can do in the world.
## Speed and cadence come from the gait planner's leg length (domain/creature/body_mechanics.gd, the Froude table);
## bite power from the mouth-role parts and their scale; sight from the eye-role parts; health from the
## body's volume. Tuning numbers come from data/creature/creature_stage.json. Pure rules: no scene or file access.
##
## Size follows physics (owner direction, 2026-10-24: a bigger creature is slower, size and parts set strength):
## - Speed: the gait's top speed grows with leg length (Froude), but a heavy body cannot reach it: above
##   tuning size.ref_kg the top speed is scaled by (1 - e^-x) / (1 - e^-1), x = (mass / ref_kg)^-size.power, the
##   saturation term of the allometric speed law (Hirt et al. 2017: big animals run out of time to accelerate). So
##   the speed curve rises with size, peaks near ref_kg and falls for giants. speed_factor is that multiplier.
## - Strength: muscle force grows with its cross-section, mass^(2/3): bite power is scaled by
##   (mass / strength.ref_kg)^strength.mass_power. strength_factor is that multiplier.

const BodyField := preload("res://game/domain/creature/body_field.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")

## The part_rules "role" (from each cpart_ record) that makes a part a mouth or an eye.
const MOUTH_ROLE := "mouth"
const EYE_ROLE := "eye"
## Weapon-role parts (claws, horns, spikes, tusks) add to the attack (PROPOSED): tuning weapon.per_part per part at
## scale 1, scale^weapon.scale_power, the largest weapon.cap of them counting. A creature attacks with its mouth, so
## a mouthless body gains nothing from them.
const WEAPON_ROLE := "weapon"
## Display organs (Bible section 12, communication organs: signal modality and range): the detail-role parts a
## creature shows off with when it sings and dances to befriend another (PROPOSED).
const DISPLAY_ROLE := "detail"
## A mouth bites this far past the head's skin per metre of its scale (PROPOSED).
const REACH_PER_MOUTH_SCALE_M := 0.25
## A body without a mouth still touches food within this reach past its head.
const TOUCH_REACH_M := 0.15


## Returns {mass_kg, max_health, bite_power, bite_reach_m, sight_m, speed_mps, cadence_hz, speed_factor,
## strength_factor, charm, has_mouth, has_legs,
## leg_length_m, mouths, eyes, weapons, body_length_m, body_radius_m}. speed_mps is the top ground speed the gait planner
## allows (the run band's Froude number on the shortest leg) times speed_factor; the walk is 0.3 of it, as the lab's
## drives.
## `part_rules` is consulted for which types exist and their role; a part of an unknown type counts for nothing.
static func of(body: RefCounted, part_rules: Dictionary, gait_table: RefCounted, tuning: Dictionary) -> Dictionary:
	var mass := mass_kg(body, float(tuning["mass"]["kg_per_m3"]))
	var speed_k := speed_factor(mass, tuning)
	var strength_k := strength_factor(mass, tuning)
	var mouth_types := types_with_role(part_rules, MOUTH_ROLE)
	var mouths := count_parts(body, mouth_types, part_rules)
	var eyes := count_parts(body, types_with_role(part_rules, EYE_ROLE), part_rules)
	var bite: Dictionary = tuning["bite"]
	var bite_power := 0.0
	var mouth_scale := 0.0
	if mouths > 0:
		bite_power = float(bite["base"])
		for p in body.parts:
			if mouth_types.has(p["type"]):
				var s := float(p["scale"]) / 1000.0
				bite_power += float(bite["per_mouth"]) * pow(s, float(bite["scale_power"]))
				mouth_scale = maxf(mouth_scale, s)
		bite_power += weapon_power(body, part_rules, tuning)
		bite_power *= strength_k
	var head_radius: float = body.radius_m(0)
	var reach := head_radius + (REACH_PER_MOUTH_SCALE_M * mouth_scale if mouths > 0 else TOUCH_REACH_M)
	var sight: Dictionary = tuning["sight"]
	var sight_m := minf(float(sight["base_m"]) + float(sight["per_eye_m"]) * eyes, float(sight["max_m"]))
	var gait := GaitBody.from_description(body)
	var has_legs: bool = not (gait["body"]["legs"] as Array).is_empty()
	var speed := 0.0
	var cadence := 0.0
	var leg_length := 0.0
	if has_legs:
		var mech = BodyMechanics.create("stats", gait["body"], gait_table)
		speed = mech.v_top * speed_k
		leg_length = mech.hip_height / gait_table.stance_height_ratio
		var period: float = gait_table.rel_stride(gait_table.fr_top()) * mech.gait_height / mech.v_top
		cadence = 1.0 / period if period > 0.0 else 0.0
	var box: AABB = body.bounds_m()
	var charm := 1.0
	var social: Dictionary = tuning.get("social", {})
	if not social.is_empty():
		# Diminishing returns (Bible section 12): only the first display_cap display organs add charm.
		var displays := mini(count_parts(body, types_with_role(part_rules, DISPLAY_ROLE), part_rules), int(social["display_cap"]))
		charm = float(social["base_charm"]) + float(social["per_display_part"]) * displays
	return {
		"mass_kg": mass,
		"max_health": mass * float(tuning["health"]["per_kg"]),
		"bite_power": bite_power,
		"bite_reach_m": reach,
		"sight_m": sight_m,
		"speed_mps": speed,
		"cadence_hz": cadence,
		"speed_factor": speed_k,
		"strength_factor": strength_k,
		"charm": charm,
		"has_mouth": mouths > 0,
		"has_legs": has_legs,
		"leg_length_m": leg_length,
		"mouths": mouths,
		"eyes": eyes,
		"weapons": count_parts(body, types_with_role(part_rules, WEAPON_ROLE), part_rules),
		"body_length_m": box.size.z,
		"body_radius_m": body.max_radius_m(),
	}


## The top-speed multiplier for a body of `mass` kg: 1 up to size.ref_kg, then falling (see the header). Without a
## "size" tuning block, 1.
static func speed_factor(mass: float, tuning: Dictionary) -> float:
	var size: Dictionary = tuning.get("size", {})
	if size.is_empty() or mass <= float(size["ref_kg"]):
		return 1.0
	var x := pow(mass / float(size["ref_kg"]), -float(size["power"]))
	return (1.0 - exp(-x)) / (1.0 - exp(-1.0))


## The bite multiplier for a body of `mass` kg: (mass / strength.ref_kg)^strength.mass_power, kept within
## strength.min..strength.max. Without a "strength" tuning block, 1.
static func strength_factor(mass: float, tuning: Dictionary) -> float:
	var st: Dictionary = tuning.get("strength", {})
	if st.is_empty() or mass <= 0.0:
		return 1.0
	return clampf(pow(mass / float(st["ref_kg"]), float(st["mass_power"])), float(st["min"]), float(st["max"]))


## Mass from the capsule volumes of the body field (each capsule as a cone frustum), at `kg_per_m3`. The head
## shape dials are cosmetic and leave it unchanged (BodyField.body_volume_m3).
static func mass_kg(body: RefCounted, kg_per_m3: float) -> float:
	return BodyField.from_description(body).body_volume_m3() * kg_per_m3


## The attack the weapon-role parts add before strength (see WEAPON_ROLE). Without a "weapon" tuning block, 0.
static func weapon_power(body: RefCounted, part_rules: Dictionary, tuning: Dictionary) -> float:
	var w: Dictionary = tuning.get("weapon", {})
	if w.is_empty():
		return 0.0
	var types := types_with_role(part_rules, WEAPON_ROLE)
	var gains: Array[float] = []
	for p in body.parts:
		if types.has(p["type"]):
			var g := float(w["per_part"]) * pow(float(p["scale"]) / 1000.0, float(w["scale_power"]))
			gains.append(g)
			if p["mirror"]:
				gains.append(g)
	gains.sort()
	gains.reverse()
	var total := 0.0
	for i in mini(gains.size(), int(w["cap"])):
		total += gains[i]
	return total


## The part types whose rules carry `role`, sorted.
static func types_with_role(part_rules: Dictionary, role: String) -> PackedStringArray:
	var out := PackedStringArray()
	for type in part_rules:
		if str(part_rules[type].get("role", "")) == role:
			out.append(type)
	out.sort()
	return out


## How many parts of the given types the body wears, a mirrored part counting twice. Unknown types count for nothing.
static func count_parts(body: RefCounted, types: PackedStringArray, part_rules: Dictionary) -> int:
	var n := 0
	for p in body.parts:
		if types.has(p["type"]) and part_rules.has(p["type"]):
			n += 2 if p["mirror"] else 1
	return n
