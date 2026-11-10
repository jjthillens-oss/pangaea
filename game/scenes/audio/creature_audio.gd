class_name CreatureAudio
extends StageAudio
## The creature stage's sound (StageAudio): steps by foot type, bites, eating, singing, mating, part
## finds, the field's ambience and the creature stage's music. The stage forwards its sim's events
## (CreatureWorldSim's {"kind": ...}) to on_event and calls step(foot, at) as a foot plants.

const CUES := {
	"cr_step_paw": {"variants": 3, "db": -14.0, "jitter": 0.08, "positional": true},
	"cr_step_hoof": {"variants": 3, "db": -13.0, "jitter": 0.06, "positional": true},
	"cr_step_claw": {"variants": 3, "db": -14.0, "jitter": 0.08, "positional": true},
	"cr_step_webbed": {"variants": 3, "db": -14.0, "jitter": 0.08, "positional": true},
	"cr_bite": {"variants": 3, "db": -4.0, "jitter": 0.06, "positional": true},
	"cr_hurt": {"variants": 2, "db": -3.0, "jitter": 0.04},
	"cr_die": {"variants": 1, "db": -3.0, "jitter": 0.0},
	"cr_eat_fruit": {"variants": 2, "db": -5.0, "jitter": 0.05},
	"cr_eat_meat": {"variants": 2, "db": -4.0, "jitter": 0.05},
	"cr_sing": {"variants": 3, "db": -4.0, "jitter": 0.03, "positional": true},
	"cr_befriend": {"variants": 1, "db": -5.0, "jitter": 0.0},
	"cr_snub": {"variants": 1, "db": -5.0, "jitter": 0.04, "positional": true},
	"cr_mate": {"variants": 1, "db": -4.0, "jitter": 0.0},
	"cr_part_pickup": {"variants": 1, "db": -5.0, "jitter": 0.0},
	"cr_earn": {"variants": 1, "db": -9.0, "jitter": 0.02},
	"cr_refuse": {"variants": 1, "db": -9.0, "jitter": 0.02},
}
## The step sound of each foot part; a foot not listed steps as a paw.
const FOOT_STEPS := {
	"paw": "cr_step_paw", "foot_primate": "cr_step_paw", "hand_primate": "cr_step_paw",
	"hoof": "cr_step_hoof",
	"claw": "cr_step_claw", "talon": "cr_step_claw",
	"webbed": "cr_step_webbed", "foot_frog": "cr_step_webbed", "hand_frog": "cr_step_webbed", "flipper": "cr_step_webbed",
}
const PLAYER_ID := "player"


func stage() -> String:
	return "creature"


func cue_table() -> Dictionary:
	return CUES


func bed_id() -> String:
	return "amb_meadow"


## The step cue for a foot part's type ("cpart_hoof", "hoof"...).
static func step_cue(foot: String) -> String:
	return String(FOOT_STEPS.get(foot.trim_prefix("cpart_"), "cr_step_paw"))


## A foot planted: its step, quieter for a light creature (weight 0..1, 1 the heaviest).
func step(foot: String, at: Vector3, weight: float = 0.5) -> void:
	play_at(step_cue(foot), at, lerpf(-6.0, 3.0, clampf(weight, 0.0, 1.0)))


## A new part was found.
func part_found() -> void:
	play("cr_part_pickup")


func on_event(e: Dictionary) -> void:
	var at: Variant = e.get("at")
	match String(e.get("kind", "")):
		"ate":
			if e.get("who") == PLAYER_ID:
				play("cr_eat_meat" if e.get("food") == "meat" else "cr_eat_fruit")
		"bit":
			if e.get("by") == PLAYER_ID or e.get("target") != PLAYER_ID:
				if at is Vector3:
					play_at("cr_bite", at)
				else:
					play("cr_bite")
		"hit":
			if e.get("target") == PLAYER_ID:
				threatened()
				play("cr_hurt")
		"died":
			if e.get("who") == PLAYER_ID:
				died()
				play("cr_die")
		"charmed":
			play("cr_sing")
		"befriended":
			play("cr_befriend")
		"snubbed":
			play("cr_snub")
		"evolve":
			play("cr_mate")
		"earned":
			play("cr_earn")
		"refused":
			play("cr_refuse")
		"part_found", "part_pickup":
			part_found()
