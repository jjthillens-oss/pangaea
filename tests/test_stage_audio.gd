extends TestCase
## The creature and Aquatic stages' audio: every effect StageSynth makes is a cue one stage plays,
## with its files and records, and each stage turns its sim's events into the right cues and moods.

const SFX_DIR := "res://assets/audio/sfx"
const AMB_DIR := "res://assets/audio/ambience"
const RECORDS_DIR := "res://assets/records/audio"


func test_every_stage_effect_is_a_cue_with_its_files_and_records() -> void:
	var tables := {"cr_": CreatureAudio.CUES, "aq_": AquaticAudio.CUES}
	for id: String in StageSynth.SFX:
		var table: Dictionary = tables[id.substr(0, 3)]
		check(table.has(id), "%s is a cue its stage plays" % id)
		if not table.has(id):
			continue
		check_eq(int(table[id].variants), int(StageSynth.SFX[id].variants), "%s variants match the synth" % id)
		for v in int(table[id].variants):
			var file_id := "%s_%d" % [id, v + 1]
			check(load("%s/%s.wav" % [SFX_DIR, file_id]) is AudioStreamWAV, "%s loads" % file_id)
			var record: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [RECORDS_DIR, file_id]))
			check(record is Dictionary and String(record.get("visual_equivalent", "")) != "", "%s names its visual equivalent (Bible 20)" % file_id)
	for prefix in tables:
		for cue in tables[prefix]:
			check(StageSynth.SFX.has(cue), "%s is made by the synth" % cue)
	for id in ["amb_meadow", "amb_open_water", "amb_fin_swim"]:
		check(load("%s/%s.wav" % [AMB_DIR, id]) is AudioStreamWAV, "%s loads" % id)


func test_the_effects_render_the_same_every_time() -> void:
	check_eq(StageSynth.render("cr_sing", 1), StageSynth.render("cr_sing", 1), "a render is repeatable")
	check(StageSynth.render("cr_sing", 0) != StageSynth.render("cr_sing", 1), "variants differ")


func test_each_foot_type_has_its_step() -> void:
	check_eq(CreatureAudio.step_cue("cpart_hoof"), "cr_step_hoof", "hoof")
	check_eq(CreatureAudio.step_cue("claw"), "cr_step_claw", "claw")
	check_eq(CreatureAudio.step_cue("cpart_foot_frog"), "cr_step_webbed", "frog foot")
	check_eq(CreatureAudio.step_cue("cpart_foot_primate"), "cr_step_paw", "primate foot")
	check_eq(CreatureAudio.step_cue("something new"), "cr_step_paw", "anything else steps as a paw")


func test_the_creature_stage_turns_its_events_into_cues() -> void:
	var audio := CreatureAudio.new()
	audio.on_event({"kind": "ate", "who": "player", "food": "meat"})
	audio.on_event({"kind": "ate", "who": "r1", "food": "fruit"})
	check_eq(int(audio.played.get("cr_eat_meat", 0)), 1, "the player's meal crunches")
	check(not audio.played.has("cr_eat_fruit"), "a rival's meal is not the player's")
	audio.on_event({"kind": "charmed", "who": "r1"})
	check_eq(int(audio.played.get("cr_sing", 0)), 1, "a song is sung")
	audio.on_event({"kind": "hit", "target": "player", "by": "r2"})
	check_eq(int(audio.played.get("cr_hurt", 0)), 1, "a hit hurts")
	audio._process(0.016)
	check_eq(audio.mood, "danger", "a hit brings danger")
	audio.on_event({"kind": "died", "who": "player", "cause": "killed"})
	audio._process(0.016)
	check_eq(audio.mood, "dead", "death muffles the music")
	audio.on_event({"kind": "evolve", "points": 3})
	check_eq(int(audio.played.get("cr_mate", 0)), 1, "mating plays its duet")
	audio.part_found()
	check_eq(int(audio.played.get("cr_part_pickup", 0)), 1, "a part find sparkles")
	audio.on_event({"kind": "no such event"})
	audio.free()


func test_the_aquatic_stage_turns_its_events_into_cues() -> void:
	var audio := AquaticAudio.new()
	audio.on_event({"type": "pressure_warning", "rated": 40.0})
	audio.on_event({"type": "pressure_warning", "rated": 40.0})
	check_eq(int(audio.played.get("aq_pressure_warn", 0)), 1, "the pressure warning repeats only every few seconds")
	audio.on_event({"type": "lancer_pursue"})
	audio._process(0.016)
	check_eq(audio.mood, "danger", "the lancer's chase brings danger")
	audio.on_event({"type": "lancer_gave_up", "why": "lost"})
	audio._process(0.016)
	check_eq(audio.mood, "calm", "and its giving up ends it")
	audio.burst()
	check_eq(int(audio.played.get("aq_burst", 0)), 1, "a burst whooshes")
	audio.on_event({"type": "signal_answered", "species": "grazer"})
	check_eq(int(audio.played.get("aq_signal_answered", 0)), 1, "an answered signal chimes")
	audio.free()
