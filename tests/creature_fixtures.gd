extends RefCounted
## Test-only bodies and scripted drives for tests/test_creature_*.gd: the creature lab's spine test bodies and gait
## test bodies (tests/fixtures/creature/), its lab_drives.gd inputs, and the starter bodies through the game's
## loader. Loaded by path; no class_name.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")

const FIXTURES := "res://tests/fixtures/creature"
## The spine lab's test bodies (no limbs), in spine_bodies.json.
const SPINE_BODY_NAMES: Array[String] = ["bean", "worm", "fish", "snake", "tadpole", "arch", "large"]
## The gait lab's test bodies (leg tables, not descriptions), in test_bodies.json.
const GAIT_BODY_NAMES: Array[String] = ["quad_short", "quad_long", "hexapod"]
const DRIVE_NAMES: Array[String] = ["demo", "walk", "trot", "run", "turn_in_place", "reversal", "random"]


## A body description: a starter body ("s1_" prefix) through creature_data.gd, otherwise a spine test body.
static func body(body_name: String) -> RefCounted:
	if body_name.begins_with(CreatureData.STARTER_PREFIX):
		return CreatureData.body(body_name)
	return BodyCodec.from_dict(CreatureData.read_json(FIXTURES + "/spine_bodies.json")["bodies"][body_name])


static func starter_names() -> Array[String]:
	return CreatureData.starter_bodies()


## A gait test body's mechanics (domain/creature/body_mechanics.gd).
static func gait_body(body_name: String, gait_table: RefCounted = null) -> RefCounted:
	var bodies: Dictionary = CreatureData.read_json(FIXTURES + "/test_bodies.json")["bodies"]
	return BodyMechanics.create(body_name, bodies[body_name], gait_table if gait_table else CreatureData.gait_table())


static func planner(body_name: String, start_position := Vector3.ZERO, start_yaw := 0.0) -> RefCounted:
	return GaitPlanner.create(gait_body(body_name), start_position, start_yaw)


## Scripted inputs (throttle, turn) at time t, as the lab's lab_drives.gd: throttle 0.3 is a walk, 0.6 a trot and
## 1.0 a run on every body, because the table is in Froude units.
static func drive(program: String, t: float, seed_value := 1) -> Vector2:
	match program:
		"demo":
			if t < 2.5:
				return Vector2(0.3, 0.0)
			if t < 5.0:
				return Vector2(0.6, 0.0)
			if t < 7.0:
				return Vector2(1.0, 0.0)
			if t < 8.5:
				return Vector2(0.6, 0.7)
			return Vector2.ZERO
		"walk":
			return Vector2(0.3, 0.0)
		"trot":
			return Vector2(0.6, 0.0)
		"run":
			return Vector2(1.0, 0.0)
		"turn_in_place":
			return Vector2(0.0, 1.0)
		"reversal":
			return Vector2(0.6, 0.0) if t < 3.0 else Vector2(0.6, 1.0)
		"random":
			# A new random input every half second, the same for the same seed.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([seed_value, int(floor(t * 2.0))])
			var throttle := rng.randf_range(-0.4, 1.0)
			var turn := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.6 else 0.0
			return Vector2(throttle, turn)
	return Vector2.ZERO
