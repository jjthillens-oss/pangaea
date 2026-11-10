class_name AquaticAudio
extends StageAudio
## The Aquatic stage's sound (StageAudio): swimming and bursts, the pressure warning, the lancer
## and the drifter, bites, eating, signals and mating, the open sea's ambience and the Aquatic
## stage's music. The stage forwards its sim's events (AquaticSim's {"type": ...}) to on_event, calls
## set_motion(speed share) each frame and burst() when a burst starts.

const CUES := {
	"aq_burst": {"variants": 2, "db": -6.0, "jitter": 0.05},
	"aq_pressure_warn": {"variants": 1, "db": -4.0, "jitter": 0.0},
	"aq_pressure_clear": {"variants": 1, "db": -8.0, "jitter": 0.0},
	"aq_lancer_notice": {"variants": 1, "db": -4.0, "jitter": 0.02, "positional": true},
	"aq_lancer_pursue": {"variants": 1, "db": -3.0, "jitter": 0.02, "positional": true},
	"aq_lancer_gave_up": {"variants": 1, "db": -7.0, "jitter": 0.03, "positional": true},
	"aq_drifter_warn": {"variants": 1, "db": -5.0, "jitter": 0.02, "positional": true},
	"aq_bite": {"variants": 2, "db": -4.0, "jitter": 0.06, "positional": true},
	"aq_hurt": {"variants": 2, "db": -3.0, "jitter": 0.04},
	"aq_die": {"variants": 1, "db": -3.0, "jitter": 0.0},
	"aq_eat": {"variants": 2, "db": -5.0, "jitter": 0.05},
	"aq_signal": {"variants": 2, "db": -5.0, "jitter": 0.03},
	"aq_signal_answered": {"variants": 1, "db": -5.0, "jitter": 0.0},
	"aq_mate": {"variants": 1, "db": -4.0, "jitter": 0.0},
	"aq_found": {"variants": 1, "db": -8.0, "jitter": 0.0},
	"aq_refuse": {"variants": 1, "db": -9.0, "jitter": 0.02},
}
## Seconds between pressure warnings while the fish stays too deep.
const PRESSURE_REPEAT_S := 2.5

var _pressure_until_ms := -1


func stage() -> String:
	return "aquatic"


func cue_table() -> Dictionary:
	return CUES


func bed_id() -> String:
	return "amb_open_water"


func motion_id() -> String:
	return "amb_fin_swim"


func motion_db() -> float:
	return -8.0


## A burst of speed started.
func burst() -> void:
	play("aq_burst")


func on_event(e: Dictionary) -> void:
	var at: Variant = e.get("at")
	match String(e.get("type", "")):
		"ate":
			play("aq_eat")
		"pressure_warning":
			var now := Time.get_ticks_msec()
			if now >= _pressure_until_ms:
				_pressure_until_ms = now + int(PRESSURE_REPEAT_S * 1000.0)
				play("aq_pressure_warn")
		"pressure_clear":
			_pressure_until_ms = -1
			play("aq_pressure_clear")
		"lancer_investigate":
			_at("aq_lancer_notice", at)
		"lancer_pursue":
			threatened()
			_at("aq_lancer_pursue", at)
		"lancer_gave_up":
			safe()
			_at("aq_lancer_gave_up", at)
		"drifter_warning":
			threatened()
			_at("aq_drifter_warn", at)
		"struck", "stung":
			threatened()
			play("aq_hurt")
		"died":
			died()
			play("aq_die")
		"bit", "killed":
			_at("aq_bite", at)
		"bite_missed", "bite_weak", "signal_unheard", "signal_too_fast", "mate_not_ready":
			play("aq_refuse")
		"signal_answered":
			play("aq_signal_answered")
		"mate":
			play("aq_mate")
		"found":
			play("aq_found")


## The fish signalled (the stage calls this on the press; the answer comes as an event).
func signal_sent() -> void:
	play("aq_signal")


func _at(cue: String, at: Variant) -> void:
	if at is Vector3:
		play_at(cue, at)
	else:
		play(cue)
