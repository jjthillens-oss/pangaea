extends SceneTree
## Renders the cell stage's sound effects and ambience into assets/audio/ and writes a record for
## each file in assets/records/audio/. The sound design lives in code: the effects in
## game/scenes/audio/audio_synth.gd, the ambience below. Nothing is recorded or sampled, so every
## sound is original. The music (assets/audio/music/, composed CC0 instrumentals) and the UI
## sounds (assets/audio/ui/, Kenney's CC0 packs) are third-party files with their own records;
## this script leaves them alone.
##
## Usage: godot --headless --path . --script res://tools/audio/make_cell_audio.gd [-- --only=a,b]
##   --only takes file ids (eat_plant_1, amb_reef) or groups (sfx, ambience, buses).
## Then run `godot --headless --path . --import` so the new files are imported. Loops get a
## .import file with a forward loop; keep it when a file is regenerated.
##
## The output is deterministic: every random draw comes from a generator seeded by the file id.

const SFX_DIR := "res://assets/audio/sfx"
const AMB_DIR := "res://assets/audio/ambience"
const RECORDS_DIR := "res://assets/records/audio"
const GENERATOR := "tools/audio/make_cell_audio.gd"
const SYNTH := "game/scenes/audio/audio_synth.gd"
const REVIEW := "production rev 1 - M1, awaiting owner listen"

## The ambience is softer and darker than the effects, so a lower rate keeps it small.
const BED_RATE := 22050
## Target loudness of each file as RMS in dBFS; the mix sets the rest (CellAudio and the buses).
const RMS_DB := {
	"amb_bed": -25.0, "amb_sunlit": -31.0, "amb_reef": -30.0, "amb_drift": -31.0, "amb_swim": -24.0,
}

var _only := PackedStringArray()
var _written := 0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	for dir in [SFX_DIR, AMB_DIR, RECORDS_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var t0 := Time.get_ticks_msec()
	if _wanted("buses", "buses"):
		_make_buses()
	_make_sfx()
	_make_ambience()
	print("make_cell_audio: wrote %d files in %.1f s" % [_written, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func _wanted(id: String, group: String) -> bool:
	return _only.is_empty() or _only.has(id) or _only.has(group)


# --- Buses ----------------------------------------------------------------------------------

## The mixer, saved as res://default_bus_layout.tres: Music, SFX and Ambience send to Master. The
## settings menu sets their volumes by name. Music has a low-pass the soundtrack closes for moods
## and a wide hall; SFX a small wet room; Master a limiter so a pile-up never clips.
const BUS_LAYOUT := "res://default_bus_layout.tres"


func _make_buses() -> void:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	for i in AudioServer.get_bus_effect_count(0):
		AudioServer.remove_bus_effect(0, 0)
	for bus_name in ["Music", "SFX", "Ambience"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")
	var low := AudioEffectLowPassFilter.new()
	low.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(1, low)
	var hall := AudioEffectReverb.new()
	hall.room_size = 0.8
	hall.damping = 0.5
	hall.spread = 1.0
	hall.hipass = 0.15
	hall.dry = 0.9
	hall.wet = 0.28
	AudioServer.add_bus_effect(1, hall)
	var room := AudioEffectReverb.new()
	room.predelay_msec = 20.0
	room.room_size = 0.45
	room.damping = 0.65
	room.spread = 0.8
	room.hipass = 0.2
	room.dry = 1.0
	room.wet = 0.14
	AudioServer.add_bus_effect(2, room)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), BUS_LAYOUT)
	if err != OK:
		push_error("make_cell_audio: could not write %s (%s)" % [BUS_LAYOUT, error_string(err)])
	else:
		print("  %s" % BUS_LAYOUT)


# --- Effects ---------------------------------------------------------------------------------

## What each effect is for and what the player sees with it (Bible 20: every critical cue has a
## visual equivalent).
const SFX_INFO := {
	"eat_plant": ["The cell eats plankton: a soft suck, a rising pop and a glassy sparkle.", "Eat burst and the meal toast"],
	"eat_meat": ["The cell eats carrion: two wet chomps.", "Eat burst and the meal toast"],
	"refuse": ["Food the cell cannot eat: a muffled glass bonk falling a third.", "Refusal hint text and head shake"],
	"starve_pulse": ["A weak heartbeat at most once a second while starving.", "Starving banner, grey cell and food arrow"],
	"notice": ["A creature notices the cell: a startled chirp and a ping. Positional.", "The creature's eye glow and \"!\" marker"],
	"tell_lunge": ["The ambush hunter's lunge tell: a rising growl as long as the tell, loudest at the strike. Positional.", "Coil pose and the strike lane on the floor"],
	"tell_puff": ["The rammer's puff tell: water rushing in, a rubbery creak and spike clicks, as long as the tell. Positional.", "Puff pose, raised crest and the strike lane"],
	"tell_cancel": ["A creature gives up its tell: air let out. Positional.", "The creature deflates and the lane clears"],
	"strike": ["The lunge or charge itself: a whoosh of water. Positional.", "The strike stretch along the lane"],
	"bite": ["A creature bites another: a snap and a wet tear. Positional.", "Hit number on the target"],
	"ram": ["A creature rams another: a deep jelly thud. Positional.", "Hit number on the target"],
	"hurt": ["The cell is hit: a thump, a sting and a hurt squeak.", "Hurt flash, flinch, vignette and hit number"],
	"dodged": ["A strike on the cell missed: a swish and a rising sparkle.", "\"Dodged!\" text"],
	"creature_die": ["A creature dies: a membrane pop and a sinking fizz. Positional.", "The body turns to carrion"],
	"player_die": ["The cell dies: the heartbeat stops, a falling dissolve and a soft minor chord.", "The death notice"],
	"respawn": ["The lineage continues: rising glass notes and bubbles.", "The cell reappears at its checkpoint"],
	"region_enter": ["Endless world: the cell swims into a new region (a quiet sting).", "The region toast"],
	"region_rare": ["Endless world: a rare giant set piece is near (a swell and a shimmer).", "The set piece in view"],
	"grow_warn": ["Endless world: growth starts in 1.5 s (a rising shimmer).", "\"Growing…\" toast"],
	"grow": ["Endless world: the cell grows a size (a swell into a bright chord).", "The growth beat and size toast"],
	"growth_ring": ["Endless world: a growth-ring lump is eaten (a bubbly chime).", "The growth meter jump"],
	"now_food": ["Endless world: a former threat is now small enough to eat.", "\"Now food\" toast"],
}


func _make_sfx() -> void:
	for id: String in AudioSynth.SFX_VARIANTS:
		for v in int(AudioSynth.SFX_VARIANTS[id]):
			var file_id := "%s_%d" % [id, v + 1]
			if not (_wanted(file_id, "sfx") or _wanted(id, "sfx")):
				continue
			var samples := AudioSynth.render_sfx(id, v)
			var path := "%s/%s.wav" % [SFX_DIR, file_id]
			_write_wav(path, [samples], AudioSynth.SFX_RATE, false)
			var info: Array = SFX_INFO[id]
			_write_record(file_id, "sfx", path, {
				"cue": id, "variant": v + 1, "purpose": info[0], "visual_equivalent": info[1],
				"bus": "SFX", "loop": false, "sample_rate": AudioSynth.SFX_RATE, "channels": 1,
				"length_s": snappedf(samples.size() / float(AudioSynth.SFX_RATE), 0.001),
				"recipe": "%s AudioSynth._sfx(\"%s\", %d)" % [SYNTH, id, v],
			})


# --- Ambience --------------------------------------------------------------------------------

const AMB_INFO := {
	"amb_bed": ["The deep fluid: slow swells of dark noise and a faint pressure tone, under every region.", 40.0],
	"amb_sunlit": ["Sunlit water (the home pool and sunlit regions): many tiny bubbles, rising streams and a bright fizz.", 31.0],
	"amb_reef": ["Shell reefs: crackles and clicks of busy microbes, small knocks and far chirps.", 29.0],
	"amb_drift": ["Open drift: sparse large bubbles and the slow moans of far giants.", 37.0],
	"amb_swim": ["The cell's own swimming: a flagellum whir and a bubble trail, faded in with speed.", 4.0],
}


func _make_ambience() -> void:
	for id: String in AMB_INFO:
		if not _wanted(id, "ambience"):
			continue
		var length_s: float = AMB_INFO[id][1]
		var s := AudioSynth.new(BED_RATE, hash(id))
		var lr: Array
		match id:
			"amb_bed": lr = _bed(s, length_s)
			"amb_sunlit": lr = _sunlit(s, length_s)
			"amb_reef": lr = _reef(s, length_s)
			"amb_drift": lr = _drift(s, length_s)
			"amb_swim": lr = _swim(s, length_s)
		lr = _to_rms(s, lr, float(RMS_DB[id]))
		var path := "%s/%s.wav" % [AMB_DIR, id]
		_write_wav(path, lr, BED_RATE, true)
		_write_record(id, "ambience", path, {
			"purpose": AMB_INFO[id][0], "bus": "Ambience", "loop": true, "sample_rate": BED_RATE,
			"channels": 2, "length_s": length_s, "recipe": "%s _%s" % [GENERATOR, id.trim_prefix("amb_")],
		})


## Noise that loops: rendered `fade_s` longer, then its tail is blended into its head.
func _looped_noise(s: AudioSynth, length_s: float, fade_s: float, make: Callable) -> PackedFloat32Array:
	var raw: PackedFloat32Array = make.call(length_s + fade_s)
	var n := int(length_s * s.rate)
	var fade := int(fade_s * s.rate)
	var out := raw.slice(0, n)
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * sqrt(k) + raw[n + i] * sqrt(1.0 - k)
	return out


## A slow random swell between `low` and 1 that loops over `length_s`: a sum of sines with whole
## numbers of cycles in the loop.
func _swell(s: AudioSynth, length_s: float, low: float, cycles: Array) -> PackedFloat32Array:
	var out := s.silence(length_s)
	var phases := []
	for c in cycles:
		phases.append(s.rng.randf() * TAU)
	for i in out.size():
		var t := float(i) / out.size()
		var v := 0.0
		for k in cycles.size():
			v += sin(TAU * cycles[k] * t + phases[k])
		out[i] = lerpf(low, 1.0, 0.5 + 0.5 * v / cycles.size())
	return out


func _brown(s: AudioSynth, length_s: float, cutoff: float) -> PackedFloat32Array:
	var out := s.white(length_s)
	var y := 0.0
	for i in out.size():
		y = 0.995 * y + 0.06 * out[i]
		out[i] = y
	return s.lowpass(s.highpass(s.highpass(out, 40.0), 40.0), cutoff)


func _bed(s: AudioSynth, length_s: float) -> Array:
	var lr := []
	for ch in 2:
		var deep := _looped_noise(s, length_s, 2.0, func(l: float) -> PackedFloat32Array: return _brown(s, l, 260.0))
		var flow := _looped_noise(s, length_s, 2.0, func(l: float) -> PackedFloat32Array: return s.svf(s.white(l), 520.0, 520.0, 0.8))
		var swell_a := _swell(s, length_s, 0.45, [1, 3, 4])
		var swell_b := _swell(s, length_s, 0.1, [2, 5, 7])
		var out := s.silence(length_s)
		var n := out.size()
		for i in n:
			var t := float(i) / s.rate
			# A faint pressure tone, two soft sines with whole cycles in the loop.
			var tone := 0.04 * sin(TAU * 55.0 * t + ch) + 0.025 * sin(TAU * 82.5 * t) * swell_b[i]
			out[i] = deep[i] * swell_a[i] + 0.3 * flow[i] * swell_b[i] + tone
		lr.append(out)
	return lr


## Mixes a mono event into a stereo loop at `at_s` with constant-power pan (-1 left, 1 right).
func _place(s: AudioSynth, lr: Array, sound: PackedFloat32Array, at_s: float, gain: float, pan: float) -> void:
	var angle := (pan + 1.0) * PI / 4.0
	s.mix(lr[0], sound, at_s, gain * cos(angle), true)
	s.mix(lr[1], sound, at_s, gain * sin(angle), true)


func _sunlit(s: AudioSynth, length_s: float) -> Array:
	var lr := [s.silence(length_s), s.silence(length_s)]
	for k in int(length_s * 9.0):
		var f := exp(s.rng.randf_range(log(1500.0), log(6500.0)))
		_place(s, lr, s.bubble(f), s.rng.randf() * length_s, pow(s.rng.randf(), 2.0) * 0.5 + 0.05, s.rng.randf_range(-0.9, 0.9))
	# Rising streams: a run of bubbles climbing in pitch, every few seconds.
	var at := 1.0
	while at < length_s:
		var pan := s.rng.randf_range(-0.8, 0.8)
		var f := s.rng.randf_range(1200.0, 2200.0)
		for b in s.rng.randi_range(6, 11):
			_place(s, lr, s.bubble(f), at + b * s.rng.randf_range(0.05, 0.09), 0.45, pan)
			f *= s.rng.randf_range(1.04, 1.12)
		at += s.rng.randf_range(2.5, 5.5)
	for ch in 2:
		var fizz := _looped_noise(s, length_s, 1.0, func(l: float) -> PackedFloat32Array: return s.highpass(s.white(l), 3500.0))
		s.mix(lr[ch], fizz, 0.0, 0.025)
	return lr


func _reef(s: AudioSynth, length_s: float) -> Array:
	var lr := [s.silence(length_s), s.silence(length_s)]
	var click := s.shaped(s.highpass(s.white(0.006), 1800.0), 0.0002, 0.0012)
	for k in int(length_s * 22.0):
		var gain := minf(1.0, -log(maxf(1e-4, s.rng.randf())) * 0.18)
		_place(s, lr, click, s.rng.randf() * length_s, gain, s.rng.randf_range(-1.0, 1.0))
	for k in int(length_s * 4.0):
		var f := exp(s.rng.randf_range(log(700.0), log(3000.0)))
		_place(s, lr, s.bubble(f), s.rng.randf() * length_s, s.rng.randf_range(0.1, 0.4), s.rng.randf_range(-0.9, 0.9))
	# Small knocks of shell on shell.
	var at := 0.7
	while at < length_s:
		var knock := s.shaped(s.pluck(0.25, s.rng.randf_range(260.0, 620.0), 0.97, 0.7), 0.001, 0.05)
		_place(s, lr, knock, at, s.rng.randf_range(0.2, 0.4), s.rng.randf_range(-0.8, 0.8))
		at += s.rng.randf_range(1.2, 3.4)
	# Far chirps: little voiced calls, muffled by distance.
	at = 3.0
	while at < length_s:
		var f0 := s.rng.randf_range(380.0, 620.0)
		var call := s.voiced(s.buzz(0.25, f0, f0 * s.rng.randf_range(0.8, 1.5), 8, 1.2, 0.04), 800.0, 1200.0, 1900.0, 2400.0, 4.0)
		call = s.lowpass(s.shaped(call, 0.02, 0.12), 1500.0)
		_place(s, lr, call, at, 0.18, s.rng.randf_range(-0.9, 0.9))
		at += s.rng.randf_range(5.0, 9.0)
	return lr


func _drift(s: AudioSynth, length_s: float) -> Array:
	var lr := [s.silence(length_s), s.silence(length_s)]
	for k in int(length_s * 1.2):
		var f := exp(s.rng.randf_range(log(280.0), log(950.0)))
		_place(s, lr, s.lowpass(s.bubble(f), 1600.0), s.rng.randf() * length_s, s.rng.randf_range(0.2, 0.6), s.rng.randf_range(-0.9, 0.9))
	# The slow moans of far giants: a deep voiced swell, muffled and wide.
	var at := 2.0
	while at < length_s:
		var len := s.rng.randf_range(3.5, 5.0)
		var f0 := s.rng.randf_range(48.0, 70.0)
		var moan := s.voiced(s.buzz(len, f0, f0 * s.rng.randf_range(1.15, 1.4), 12, 1.0, 0.03), 250.0, 420.0, 600.0, 900.0, 3.0)
		moan = s.lowpass(moan, 650.0)
		for i in moan.size():
			moan[i] *= sin(PI * float(i) / moan.size())
		var pan := s.rng.randf_range(-0.6, 0.6)
		_place(s, lr, moan, at, 0.5, pan)
		_place(s, lr, s.lowpass(moan, 300.0), at + 0.35, 0.25, -pan)
		at += s.rng.randf_range(10.0, 15.0)
	return lr


func _swim(s: AudioSynth, length_s: float) -> Array:
	var lr := []
	for ch in 2:
		var rush := _looped_noise(s, length_s, 0.5, func(l: float) -> PackedFloat32Array: return s.svf(s.white(l), 650.0, 650.0, 1.4))
		var n := rush.size()
		for i in n:
			var t := float(i) / n
			# 9 strokes a second (36 in the loop), the right side a little behind the left.
			rush[i] *= 0.55 + 0.45 * pow(0.5 + 0.5 * sin(TAU * 36.0 * t + ch * 0.6), 2.0)
		lr.append(rush)
	for k in int(length_s * 6.0):
		var f := exp(s.rng.randf_range(log(1200.0), log(3800.0)))
		_place(s, lr, s.bubble(f), s.rng.randf() * length_s, s.rng.randf_range(0.05, 0.2), s.rng.randf_range(-0.5, 0.5))
	return lr


# --- Output ----------------------------------------------------------------------------------

## Scales a stereo pair to an RMS in dBFS, then softly limits any peak above -1 dBFS.
func _to_rms(s: AudioSynth, lr: Array, rms_db: float) -> Array:
	var sum := 0.0
	var count := 0
	for ch: PackedFloat32Array in lr:
		for v in ch:
			sum += v * v
		count += ch.size()
	var rms := sqrt(sum / maxi(1, count))
	var gain := db_to_linear(rms_db) / maxf(rms, 1e-9)
	var out := []
	for ch: PackedFloat32Array in lr:
		var scaled_ch := s.scaled(ch, gain)
		if s.peak(scaled_ch) > 0.89:
			for i in scaled_ch.size():
				var v := scaled_ch[i]
				if absf(v) > 0.7:
					scaled_ch[i] = signf(v) * (0.7 + 0.19 * tanh((absf(v) - 0.7) / 0.19))
		out.append(scaled_ch)
	return out


## Writes 16-bit PCM: one array is mono, two are left and right.
func _write_wav(path: String, channels: Array, sample_rate: int, loop: bool) -> void:
	var n: int = channels[0].size()
	var stereo := channels.size() == 2
	var data := PackedByteArray()
	data.resize(n * 2 * channels.size())
	var at := 0
	for i in n:
		for ch: PackedFloat32Array in channels:
			data.encode_s16(at, int(round(clampf(ch[i], -1.0, 1.0) * 32767.0)))
			at += 2
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = stereo
	stream.data = data
	var err := stream.save_to_wav(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("make_cell_audio: could not write %s (%s)" % [path, error_string(err)])
		return
	if loop:
		_write_loop_import(path)
	_written += 1
	print("  %s  %.2f s" % [path, float(n) / sample_rate])


## A .import that loops the whole file forward. Godot keeps an existing .import's settings.
func _write_loop_import(path: String) -> void:
	var import_path := ProjectSettings.globalize_path(path + ".import")
	if FileAccess.file_exists(import_path):
		return
	var f := FileAccess.open(import_path, FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"wav\"\ntype=\"AudioStreamWAV\"\n\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=2\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n")
	f.close()


func _write_record(id: String, kind: String, path: String, fields: Dictionary) -> void:
	var record := {
		"id": id, "owner": "Joshua Jake", "status": "PROPOSED", "review_state": REVIEW, "category": kind,
		"export_path": path.trim_prefix("res://"), "generator_script": GENERATOR, "synth_library": SYNTH,
		"license": "Original work made for Pangaea by its generator; no samples or third-party audio.",
		"third_party_sources": [],
	}
	record.merge(fields)
	var f := FileAccess.open("%s/%s.json" % [RECORDS_DIR, id], FileAccess.WRITE)
	f.store_string(JSON.stringify(record, "  ", false) + "\n")
	f.close()
