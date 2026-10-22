class_name PlaceholderAudio
extends Node
## Placeholder sounds synthesized at startup, with no files (M1 step 2). Each is listed in
## assets/records/placeholders/inventory.json and goes in M1 step 5. Every cue has a visual
## equivalent, and cues play only for confirmed sim events (Bible 20).
##
## Cues: "eat_plant" (rising blip), "eat_meat" (two low chomps), "refuse" (dull two-tone),
## "starve_pulse" (a low double thump; the pool plays it at most once a second), and a 4 s
## filtered-noise ambience loop that starts by itself.
##
## On the dummy audio driver (headless runs) nothing is started: that driver never mixes, so
## playbacks would never finish. Cues are still counted in `played`, so checks can see them.

const MIX_RATE := 22050
const LEVEL_DB := -14.0
const REPEAT_LIMIT_MS := 60      ## the same cue at most once per this long
const PEAK := 0.8
const AMBIENCE_PEAK := 0.3
const AMBIENCE_S := 4.0
const AMBIENCE_FADE_S := 0.25    ## the loop's tail is blended into its head so it never clicks
const NOISE_SEED := 20261022
const CUES: PackedStringArray = ["eat_plant", "eat_meat", "refuse", "starve_pulse"]

## How many times each cue was played (or would have been, on the dummy driver).
var played := {}

var _players := {}               ## cue -> AudioStreamPlayer
var _last_played_ms := {}
var _ambience: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _silent := false


func _ready() -> void:
	_silent = AudioServer.get_driver_name() == "Dummy"
	_rng.seed = NOISE_SEED
	for cue in CUES:
		var player := AudioStreamPlayer.new()
		player.name = cue
		player.stream = _to_stream(_samples_for(cue), false)
		player.volume_db = LEVEL_DB
		player.max_polyphony = 3
		add_child(player)
		_players[cue] = player
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "ambience"
	_ambience.stream = _to_stream(_ambience_samples(), true)
	_ambience.volume_db = LEVEL_DB
	add_child(_ambience)
	if not _silent:
		_ambience.play()


## Plays a cue unless the same one played within REPEAT_LIMIT_MS. Unknown cues are ignored.
func play(cue: String) -> void:
	var player: AudioStreamPlayer = _players.get(cue)
	if player == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(cue, -REPEAT_LIMIT_MS)) < REPEAT_LIMIT_MS:
		return
	_last_played_ms[cue] = now
	played[cue] = int(played.get(cue, 0)) + 1
	if not _silent:
		player.play()


## The synthesized stream of a cue, for tests.
func stream_of(cue: String) -> AudioStreamWAV:
	var player: AudioStreamPlayer = _players.get(cue)
	return player.stream if player != null else null


func _samples_for(cue: String) -> PackedFloat32Array:
	match cue:
		"eat_plant":
			return _tone(0.14, 520.0, 1040.0, 0.004, 0.05, 0.25)
		"eat_meat":
			var out := _silence(0.22)
			_mix(out, _chomp(0.075), 0.0)
			_mix(out, _chomp(0.075), 0.11)
			return _normalized(out, PEAK)
		"refuse":
			var out := _silence(0.22)
			_mix(out, _tone(0.09, 330.0, 320.0, 0.006, 0.05, 0.6), 0.0)
			_mix(out, _tone(0.11, 247.0, 240.0, 0.006, 0.06, 0.6), 0.1)
			return _normalized(out, PEAK)
		"starve_pulse":
			var out := _silence(0.34)
			_mix(out, _tone(0.12, 72.0, 52.0, 0.004, 0.05, 0.1), 0.0)
			_mix(out, _tone(0.12, 66.0, 48.0, 0.004, 0.05, 0.1), 0.16, 0.7)
			return _normalized(out, PEAK)
	return PackedFloat32Array()


## A sine sweep from `f0` to `f1` Hz with a quick attack, an exponential decay of time constant
## `decay_s` and a share of second harmonic for body.
func _tone(length_s: float, f0: float, f1: float, attack_s: float, decay_s: float, harmonic: float) -> PackedFloat32Array:
	var n := int(length_s * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := f0 * pow(f1 / f0, t / length_s)
		phase += TAU * f / MIX_RATE
		var env := minf(1.0, t / attack_s) * exp(-t / decay_s) * (1.0 - t / length_s)
		out[i] = env * (sin(phase) + harmonic * sin(2.0 * phase))
	return _normalized(out, PEAK)


## A short low thump with a burst of filtered noise.
func _chomp(length_s: float) -> PackedFloat32Array:
	var n := int(length_s * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var noise := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		phase += TAU * lerpf(120.0, 70.0, t / length_s) / MIX_RATE
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.25)
		var env := minf(1.0, t / 0.003) * exp(-t / 0.025)
		out[i] = env * (sin(phase) + 0.8 * noise)
	return out


## Low rumbling noise, looped seamlessly.
func _ambience_samples() -> PackedFloat32Array:
	var n := int(AMBIENCE_S * MIX_RATE)
	var fade := int(AMBIENCE_FADE_S * MIX_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var low := 0.0
	var lower := 0.0
	for i in raw.size():
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.03)
		lower = lerpf(lower, low, 0.05)
		var t := float(i) / MIX_RATE
		raw[i] = lower * (0.8 + 0.2 * sin(TAU * t / AMBIENCE_S))
	var out := raw.slice(0, n)
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * k + raw[n + i] * (1.0 - k)
	return _normalized(out, AMBIENCE_PEAK)


func _silence(length_s: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(length_s * MIX_RATE))
	out.fill(0.0)
	return out


func _mix(into: PackedFloat32Array, sound: PackedFloat32Array, at_s: float, gain: float = 1.0) -> void:
	var start := int(at_s * MIX_RATE)
	for i in mini(sound.size(), into.size() - start):
		into[start + i] += sound[i] * gain


func _normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0
	for s in samples:
		top = maxf(top, absf(s))
	if top <= 0.0:
		return samples
	var out := samples.duplicate()
	for i in out.size():
		out[i] = out[i] * peak / top
	return out


func _to_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
