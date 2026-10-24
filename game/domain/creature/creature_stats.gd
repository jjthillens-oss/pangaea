class_name CreatureStats
extends RefCounted
## Anatomy to play numbers (PROPOSED, creature-stage-plan.md section 5): what a body description can do in the world.
## Speed and cadence come from the gait planner's leg length (domain/creature/body_mechanics.gd, the Froude table);
## bite power from the mouth parts (maw, mandibles, beak) and their scale; sight from the eye parts; health from the
## body's volume. Tuning numbers come from data/creature/creature_stage.json. Pure rules: no scene or file access.

const BodyField := preload("res://game/domain/creature/body_field.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")

const MOUTH_TYPES: PackedStringArray = ["maw", "mandibles", "beak"]
const EYE_TYPES: PackedStringArray = ["eye", "compound_eye", "eye_stalk"]
## A mouth bites this far past the head's skin per metre of its scale (PROPOSED).
const REACH_PER_MOUTH_SCALE_M := 0.25
## A body without a mouth still touches food within this reach past its head.
const TOUCH_REACH_M := 0.15


## Returns {mass_kg, max_health, bite_power, bite_reach_m, sight_m, speed_mps, cadence_hz, has_mouth, has_legs,
## leg_length_m, mouths, eyes, body_length_m, body_radius_m}. speed_mps is the top ground speed the gait planner
## allows (the run band's Froude number on the shortest leg); the walk is 0.3 of it, as the lab's drives.
## `part_rules` is only consulted for which types exist; a part of an unknown type counts for nothing.
static func of(body: RefCounted, part_rules: Dictionary, gait_table: RefCounted, tuning: Dictionary) -> Dictionary:
	var mass := mass_kg(body, float(tuning["mass"]["kg_per_m3"]))
	var mouths := count_parts(body, MOUTH_TYPES, part_rules)
	var eyes := count_parts(body, EYE_TYPES, part_rules)
	var bite: Dictionary = tuning["bite"]
	var bite_power := 0.0
	var mouth_scale := 0.0
	if mouths > 0:
		bite_power = float(bite["base"])
		for p in body.parts:
			if MOUTH_TYPES.has(p["type"]) and part_rules.has(p["type"]):
				var s := float(p["scale"]) / 1000.0
				bite_power += float(bite["per_mouth"]) * pow(s, float(bite["scale_power"]))
				mouth_scale = maxf(mouth_scale, s)
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
		speed = mech.v_top
		leg_length = mech.hip_height / gait_table.stance_height_ratio
		var period: float = gait_table.rel_stride(gait_table.fr_top()) * mech.hip_height / mech.v_top
		cadence = 1.0 / period if period > 0.0 else 0.0
	var box: AABB = body.bounds_m()
	return {
		"mass_kg": mass,
		"max_health": mass * float(tuning["health"]["per_kg"]),
		"bite_power": bite_power,
		"bite_reach_m": reach,
		"sight_m": sight_m,
		"speed_mps": speed,
		"cadence_hz": cadence,
		"has_mouth": mouths > 0,
		"has_legs": has_legs,
		"leg_length_m": leg_length,
		"mouths": mouths,
		"eyes": eyes,
		"body_length_m": box.size.z,
		"body_radius_m": body.max_radius_m(),
	}


## Mass from the capsule volumes of the body field (each capsule as a cone frustum), at `kg_per_m3`.
static func mass_kg(body: RefCounted, kg_per_m3: float) -> float:
	var field = BodyField.from_description(body)
	var volume := 0.0
	for k in field.capsule_count():
		var h: float = field.a[k].distance_to(field.b[k])
		var ra: float = field.ra[k]
		var rb: float = field.rb[k]
		volume += PI / 3.0 * h * (ra * ra + ra * rb + rb * rb)
	return volume * kg_per_m3


## How many parts of the given types the body wears, a mirrored part counting twice. Unknown types count for nothing.
static func count_parts(body: RefCounted, types: PackedStringArray, part_rules: Dictionary) -> int:
	var n := 0
	for p in body.parts:
		if types.has(p["type"]) and part_rules.has(p["type"]):
			n += 2 if p["mirror"] else 1
	return n
