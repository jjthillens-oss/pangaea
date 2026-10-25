extends RefCounted
## Loads the Social stage slice's data (PROPOSED, docs/stages/social-plan.md section 14): its tuning from
## game/data/social/social_slice.json, converted once to whole ticks (SocialRules.with_ticks), and the creature data
## the sim builds its bodies from, read through the creature stage's own loader (read-only; the creature stage owns
## it). Not domain code: it reads files. SocialSim only takes the dictionaries this returns.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")

const SLICE_PATH := "res://game/data/social/social_slice.json"
const CREATURE_TUNING_PATH := "res://game/data/creature/creature_stage.json"


## The slice's tuning as written (seconds).
static func raw_tuning() -> Dictionary:
	return CreatureData.read_json(SLICE_PATH)


## The slice's tuning with every duration also in whole ticks ("<name>_t" next to "<name>_s") and "tick_hz".
static func tuning() -> Dictionary:
	return SocialRules.with_ticks(raw_tuning())


## What SocialSim builds bodies from: {body_rules, part_rules, editor_costs, gait_table, creature_tuning (the creature
## stage's numbers, for CreatureStats), presets: preset name -> the codec's body dictionary}.
static func creature_data() -> Dictionary:
	var presets := {}
	for n in CreatureData.preset_names():
		presets[String(n)] = CreatureData.preset(n)["body"]
	return {"body_rules": CreatureData.rules(), "part_rules": CreatureData.part_rules(),
			"editor_costs": CreatureData.editor_costs(), "gait_table": CreatureData.gait_table(),
			"creature_tuning": CreatureData.read_json(CREATURE_TUNING_PATH), "presets": presets}
