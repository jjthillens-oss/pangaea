extends TestCase
## The cell stage's audio (M1 step 5): every file has a record and every record a file, every cue
## the game plays has its files, loops loop without a click at the seam, the mixer has the buses
## the settings menu drives, and the music's mood and the UI sounds follow their rules.

const AUDIO_DIR := "res://assets/audio"
const RECORDS_DIR := "res://assets/records/audio"
const BUS_LAYOUT := "res://default_bus_layout.tres"
const GENERATOR := "tools/audio/make_cell_audio.gd"
const BUSES := ["Master", "Music", "SFX", "Ambience"]
## A loop's last sample may differ from its first by at most this much more than a typical
## sample-to-sample step (the 99th percentile), or the seam would click.
const SEAM_SLACK := 1.25

const FAKE_POOL := """extends Node
signal sim_event(event: Dictionary)
var sim: Object = null
var paused := false
"""


func _audio_files() -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(AUDIO_DIR):
		for f in DirAccess.get_files_at("%s/%s" % [AUDIO_DIR, sub]):
			if f.get_extension() in ["wav", "ogg"]:
				out.append("assets/audio/%s/%s" % [sub, f])
	return out


func _records() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(RECORDS_DIR):
		if f.ends_with(".json"):
			var record: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [RECORDS_DIR, f]))
			check(record is Dictionary, "%s parses" % f)
			if record is Dictionary:
				out[String(record.get("id", ""))] = record
	return out


## Reads a 16-bit PCM WAV from disk: {"rate", "channels", "frames": [PackedInt32Array per channel]}.
func _read_wav(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var at := 12
	var info := {}
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		if id == "fmt ":
			info.channels = bytes.decode_u16(at + 10)
			info.rate = bytes.decode_u32(at + 12)
			info.bits = bytes.decode_u16(at + 22)
		elif id == "data":
			var channels: int = info.channels
			var frames := []
			for c in channels:
				frames.append(PackedInt32Array())
			var n := size / 2 / channels
			for i in n:
				for c in channels:
					frames[c].append(bytes.decode_s16(at + 8 + (i * channels + c) * 2))
			info.frames = frames
		at += 8 + size + (size % 2)
	return info


func test_every_audio_file_has_a_record_and_every_record_a_file() -> void:
	var files := _audio_files()
	var records := _records()
	check(files.size() >= 40, "found the audio files (%d)" % files.size())
	var by_path := {}
	for id in records:
		var record: Dictionary = records[id]
		by_path[String(record.get("export_path", ""))] = id
		check(FileAccess.file_exists("res://" + String(record.get("export_path", ""))), "%s's file exists" % id)
		check_eq(record.get("status"), "PROPOSED", "%s status" % id)
		check(String(record.get("purpose", "")) != "", "%s says what it is for" % id)
		check(String(record.get("bus", "")) in BUSES, "%s names its bus" % id)
		check(String(record.get("license", "")) != "", "%s names its license" % id)
		var sources: Array = record.get("third_party_sources", [])
		if sources.is_empty():
			check_eq(record.get("generator_script"), GENERATOR, "%s names the generator that made it" % id)
		for source: Dictionary in sources:
			check(String(source.get("license", "")).begins_with("CC0"), "%s's source is CC0" % id)
			check(String(source.get("url", "")).begins_with("https://"), "%s logs its source URL" % id)
	for path in files:
		check(by_path.has(path), "%s has a record in %s" % [path, RECORDS_DIR])


func test_every_cue_has_its_files_and_effects_name_their_visual_equivalent() -> void:
	var records := _records()
	for cue in CellAudio.CUES:
		var entry: Dictionary = CellAudio.CUE_TABLE[cue]
		check_eq(int(entry.variants), int(AudioSynth.SFX_VARIANTS[cue]), "%s variants match the synth" % cue)
		for v in int(entry.variants):
			var id := "%s_%d" % [cue, v + 1]
			check(load("%s/sfx/%s.wav" % [AUDIO_DIR, id]) is AudioStreamWAV, "%s loads" % id)
			check(records.has(id) and String(records[id].get("visual_equivalent", "")) != "", "%s names its visual equivalent (Bible 20)" % id)
	for cue in AudioSynth.SFX_VARIANTS:
		check(cue in CellAudio.CUES, "%s is a cue the game can play" % cue)


func test_loops_loop_without_a_click_and_the_music_stems_share_one_length() -> void:
	var records := _records()
	for id in records:
		var record: Dictionary = records[id]
		var path := "res://" + String(record.export_path)
		var stream: AudioStream = load(path)
		check(stream != null, "%s loads" % id)
		if stream == null or not path.ends_with(".wav"):
			continue
		var wav := stream as AudioStreamWAV
		check_eq(wav.loop_mode != AudioStreamWAV.LOOP_DISABLED, bool(record.get("loop", false)), "%s loop mode" % id)
		check_near(wav.get_length(), float(record.length_s), 0.01, "%s length" % id)
		if not bool(record.get("loop", false)):
			continue
		var info := _read_wav(path)
		for frames: PackedInt32Array in info.frames:
			var steps := PackedInt32Array()
			for i in range(0, frames.size() - 1, 11):
				steps.append(absi(frames[i + 1] - frames[i]))
			steps.sort()
			var typical := steps[int(steps.size() * 0.99)]
			var seam := absi(frames[0] - frames[frames.size() - 1])
			check(seam <= maxi(200, int(typical * SEAM_SLACK)), "%s seam %d vs a typical step %d" % [id, seam, typical])


func test_the_files_are_loud_enough_and_never_clip() -> void:
	for id in _records():
		var record: Dictionary = _records()[id]
		var path := "res://" + String(record.export_path)
		if not path.ends_with(".wav"):
			continue
		var info := _read_wav(path)
		check_eq(int(info.bits), 16, "%s is 16-bit" % id)
		check_eq(int(info.rate), int(record.sample_rate), "%s sample rate" % id)
		check_eq((info.frames as Array).size(), int(record.channels), "%s channels" % id)
		var top := 0
		for frames: PackedInt32Array in info.frames:
			for s in frames:
				top = maxi(top, absi(s))
		check(top <= 29500, "%s peaks below -0.9 dBFS (%d)" % [id, top])
		check(top >= 3000, "%s is not near silent (%d)" % [id, top])


func test_the_effects_render_the_same_every_time_and_the_tells_last_exactly() -> void:
	check_eq(AudioSynth.render_sfx("bite", 1), AudioSynth.render_sfx("bite", 1), "a render is repeatable")
	check(AudioSynth.render_sfx("bite", 0) != AudioSynth.render_sfx("bite", 1), "variants differ")
	for length_s in [0.8, 1.2, 1.75]:
		for cue in ["tell_lunge", "tell_puff"]:
			check_eq(AudioSynth.render_sfx(cue, 0, length_s).size(), int(length_s * AudioSynth.SFX_RATE), "%s at %.2f s" % [cue, length_s])


func test_the_mixer_has_the_buses_the_settings_menu_drives() -> void:
	var layout := load(BUS_LAYOUT) as AudioBusLayout
	check(layout != null, "the bus layout loads")
	check_eq(ProjectSettings.get_setting("audio/buses/default_bus_layout", BUS_LAYOUT), BUS_LAYOUT, "it is the default layout")
	var names := []
	for i in AudioServer.bus_count:
		names.append(String(AudioServer.get_bus_name(i)))
		if i > 0:
			check_eq(String(AudioServer.get_bus_send(i)), "Master", "%s sends to Master" % names[i])
			check_eq(AudioServer.get_bus_volume_db(i), 0.0, "%s starts at 0 dB (the mix is in the players)" % names[i])
	check_eq(names, BUSES, "buses")
	var music := AudioServer.get_bus_index(&"Music")
	var has_low_pass := false
	for e in AudioServer.get_bus_effect_count(music):
		has_low_pass = has_low_pass or AudioServer.get_bus_effect(music, e) is AudioEffectLowPassFilter
	check(has_low_pass, "the Music bus has the mood low-pass")


func test_the_music_follows_the_mood() -> void:
	var music := Soundtrack.new()
	check_eq(music.mood, "title", "starts on the title")
	check(music.target_db("title") >= -1.0 and music.target_db("calm") <= -79.0, "title: the title track only")
	music.set_mood("calm")
	check(music.target_db("calm") >= -1.0 and music.target_db("title") <= -79.0, "calm: the playlist")
	music.set_mood("danger")
	check(music.target_db("danger") >= -1.0, "danger brings the danger track in")
	check(music.target_db("calm") < -10.0 and music.target_db("calm") > -79.0, "the calm track waits underneath")
	music.set_mood("starving")
	check(music.target_cutoff_hz() < 2000.0, "starving muffles the music")
	music.set_mood("calm")
	check_eq(music.target_cutoff_hz(), 20000.0, "calm is open")
	music.set_paused(true)
	check(music.target_cutoff_hz() <= Soundtrack.PAUSED_CUTOFF_HZ, "the pause menu muffles it")
	music.set_mood("not a mood")
	check_eq(music.mood, "calm", "unknown moods are ignored")
	music.free()


func test_every_music_track_is_a_recorded_cc0_file() -> void:
	var records := _records()
	var tracks := Array(Soundtrack.CALM_TRACKS) + [Soundtrack.TITLE_TRACK, Soundtrack.DANGER_TRACK]
	for file: String in tracks:
		var id := file.get_basename()
		check(load("%s/%s" % [Soundtrack.MUSIC_DIR, file]) is AudioStream, "%s loads" % file)
		check(records.has(id) and records[id].get("category") == "music", "%s has a music record" % file)
		if records.has(id):
			check_eq(records[id].export_path, "assets/audio/music/" + file, "%s's record names it" % id)
	for id in records:
		if records[id].get("category") == "music":
			check(String(records[id].export_path).get_file() in tracks, "%s is used by the soundtrack" % id)


func test_menu_buttons_pick_their_sound() -> void:
	var cases := {"Start": "press", "Continue": "press", "Cancel": "back", "Back": "back", "Resume": "back",
		"Quit to desktop": "back", "Save and quit to title": "press", "Not now": "press"}
	for text in cases:
		var button := Button.new()
		button.text = text
		check_eq(UiSounds.press_sound(button), cases[text], text)
		button.free()
	var custom := Button.new()
	custom.text = "Cancel"
	custom.set_meta("ui_sound", "press")
	check_eq(UiSounds.press_sound(custom), "press", "the meta wins")
	custom.free()


func test_the_cell_audio_follows_the_events_the_pool_does_not_route() -> void:
	var script := GDScript.new()
	script.source_code = FAKE_POOL
	script.reload()
	var pool: Node = script.new()
	var audio := CellAudio.new()
	pool.add_child(audio)
	audio.attach(pool)
	pool.sim_event.emit({"type": "died", "cause": "killed"})
	check_eq(int(audio.played.get("player_die", 0)), 1, "the cell's death plays")
	audio.play_at("tell_lunge", Vector3.ZERO)
	pool.sim_event.emit({"type": "creature_tell", "id": "c1", "target": CreatureField.PLAYER_ID, "kind": "lunge", "position": Vector2.ZERO})
	pool.sim_event.emit({"type": "tell_cancelled", "id": "c1", "target": CreatureField.PLAYER_ID, "position": Vector2.ZERO})
	check_eq(int(audio.played.get("tell_cancel", 0)), 1, "a cancelled tell lets its air out")
	pool.sim_event.emit({"type": "creature_strike", "id": "c2", "target": "other", "kind": "lunge", "position": Vector2(1, 1)})
	check_eq(int(audio.played.get("strike", 0)), 1, "a strike whooshes")
	check_eq(audio.region, CellAudio.DEFAULT_REGION, "starts in sunlit water")
	pool.sim_event.emit({"type": "tile_entered", "region": "reef", "rare": ""})
	check_eq(audio.region, "reef", "entering a reef crossfades its ambience")
	check_eq(int(audio.played.get("region_enter", 0)), 1, "a new region stings")
	pool.sim_event.emit({"type": "tile_entered", "region": "reef", "rare": "rare_shell_cathedral"})
	check_eq(int(audio.played.get("region_rare", 0)), 1, "a rare set piece swells")
	audio.play("no such cue")
	check(not audio.played.has("no such cue"), "unknown cues are ignored")
	pool.free()
