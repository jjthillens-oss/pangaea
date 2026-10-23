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
## Threat cues (M1 step 3): "notice" (a short rising chirp), "tell_lunge" (a low rising growl) and
## "tell_puff" (an inflating hiss), each as long as the species' tell (configure_tells), "bite" (a
## snap), "ram" (a thud), "hurt" (a dull thump with a high tick), "dodged" (a light ping),
## "creature_die" (a falling tone) and "respawn" (a soft two-note chime). The creature cues play
## where they happen (play_at) through a small pool of 3D players, so a tell off screen is still
## heard; the others play flat (play).
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
const CUES: PackedStringArray = ["eat_plant", "eat_meat", "refuse", "starve_pulse", "notice", "tell_lunge",
	"tell_puff", "bite", "ram", "hurt", "dodged", "creature_die", "respawn"]
## Cues heard where they happen (play_at), through POSITIONAL_PLAYERS AudioStreamPlayer3D taken in
## turn, audible up to MAX_DISTANCE_M from the camera (plan section 14).
const POSITIONAL: PackedStringArray = ["notice", "tell_lunge", "tell_puff", "bite", "ram", "creature_die"]
const POSITIONAL_PLAYERS := 6
const MAX_DISTANCE_M := 25.0
const UNIT_SIZE_M := 12.0        ## full volume this close to the camera (the cell is 10-20 m away)
## The tell cues last as long as the tells (creatures_m1.json attack.tell_s; plan F1). This is the
## data's value, used until configure_tells() gives the loaded one.
const DEFAULT_TELL_S := 1.2

## How many times each cue was played (or would have been, on the dummy driver).
var played := {}

var _players := {}               ## cue -> AudioStreamPlayer
var _streams := {}               ## cue -> AudioStreamWAV
var _tell_s := {"tell_lunge": DEFAULT_TELL_S, "tell_puff": DEFAULT_TELL_S}
var _positional: Array[AudioStreamPlayer3D] = []
var _next_positional := 0
var _last_played_ms := {}
var _ambience: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _silent := false


func _ready() -> void:
	_silent = AudioServer.get_driver_name() == "Dummy"
	_build_streams()
	for cue in CUES:
		var player := AudioStreamPlayer.new()
		player.name = cue
		player.stream = _streams[cue]
		player.volume_db = LEVEL_DB
		player.max_polyphony = 3
		add_child(player)
		_players[cue] = player
	for i in POSITIONAL_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "positional_%d" % i
		player.volume_db = LEVEL_DB
		player.unit_size = UNIT_SIZE_M
		player.max_distance = MAX_DISTANCE_M
		add_child(player)
		_positional.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "ambience"
	_ambience.stream = _to_stream(_ambience_samples(), true)
	_ambience.volume_db = LEVEL_DB
	add_child(_ambience)
	if not _silent:
		_ambience.play()


## Sets the tell cues' lengths in seconds: {"lunge": s, "puff": s} (the species' attack tell and
## tell_s), so each growl or hiss ends as the strike starts.
func configure_tells(lengths: Dictionary) -> void:
	_build_streams()
	for tell in lengths:
		var cue := "tell_%s" % tell
		if _tell_s.has(cue) and float(lengths[tell]) > 0.0 and not is_equal_approx(float(_tell_s[cue]), float(lengths[tell])):
			_tell_s[cue] = float(lengths[tell])
			_streams[cue] = _to_stream(_samples_for(cue), false)
			if _players.has(cue):
				(_players[cue] as AudioStreamPlayer).stream = _streams[cue]


## Plays a cue unless the same one played within REPEAT_LIMIT_MS. Unknown cues are ignored.
func play(cue: String) -> void:
	var player: AudioStreamPlayer = _players.get(cue)
	if player == null or not _may_play(cue):
		return
	if not _silent:
		player.play()


## Plays a cue at a place in the world (positional, with distance and panning from the camera),
## under the same repeat rule. Cues not in POSITIONAL play flat.
func play_at(cue: String, at: Vector3) -> void:
	if not POSITIONAL.has(cue) or _positional.is_empty():
		play(cue)
		return
	if not _streams.has(cue) or not _may_play(cue):
		return
	var player := _positional[_next_positional]
	_next_positional = (_next_positional + 1) % _positional.size()
	player.stream = _streams[cue]
	player.global_position = at
	if not _silent:
		player.play()


## The synthesized stream of a cue, for tests.
func stream_of(cue: String) -> AudioStreamWAV:
	_build_streams()
	return _streams.get(cue)


## Length of a cue's stream in seconds.
func length_of(cue: String) -> float:
	var stream := stream_of(cue)
	return stream.data.size() / 2.0 / MIX_RATE if stream != null else 0.0


func _may_play(cue: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(cue, -REPEAT_LIMIT_MS)) < REPEAT_LIMIT_MS:
		return false
	_last_played_ms[cue] = now
	played[cue] = int(played.get(cue, 0)) + 1
	return true


func _build_streams() -> void:
	if not _streams.is_empty():
		return
	_rng.seed = NOISE_SEED
	for cue in CUES:
		_streams[cue] = _to_stream(_samples_for(cue), false)


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
		"notice":
			return _tone(0.15, 620.0, 1500.0, 0.004, 0.08, 0.3)
		"tell_lunge":
			return _growl(float(_tell_s.tell_lunge))
		"tell_puff":
			return _hiss(float(_tell_s.tell_puff))
		"bite":
			var out := _silence(0.12)
			_mix(out, _click(0.03, 0.35), 0.0)
			_mix(out, _tone(0.08, 1900.0, 900.0, 0.001, 0.015, 0.2), 0.0, 0.6)
			return _normalized(out, PEAK)
		"ram":
			var out := _silence(0.24)
			_mix(out, _tone(0.22, 95.0, 42.0, 0.003, 0.06, 0.4), 0.0)
			_mix(out, _click(0.05, 0.15), 0.0, 0.5)
			return _normalized(out, PEAK)
		"hurt":
			var out := _silence(0.2)
			_mix(out, _tone(0.16, 120.0, 70.0, 0.003, 0.04, 0.3), 0.0)
			_mix(out, _tone(0.05, 2400.0, 2200.0, 0.001, 0.012, 0.0), 0.015, 0.5)
			return _normalized(out, PEAK)
		"dodged":
			return _tone(0.3, 1320.0, 1480.0, 0.003, 0.09, 0.25)
		"creature_die":
			return _tone(0.55, 420.0, 110.0, 0.01, 0.25, 0.4)
		"respawn":
			var out := _silence(0.6)
			_mix(out, _tone(0.3, 660.0, 660.0, 0.01, 0.15, 0.2), 0.0)
			_mix(out, _tone(0.36, 880.0, 880.0, 0.01, 0.18, 0.2), 0.2)
			return _normalized(out, PEAK)
	return PackedFloat32Array()


## A low growl rising in pitch and loudness over `length_s`: a buzzy wave with a slow tremolo,
## loudest at its end, which is the strike (the lunge tell).
func _growl(length_s: float) -> PackedFloat32Array:
	var n := int(length_s * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var k := t / length_s
		phase += TAU * lerpf(70.0, 150.0, k * k) / MIX_RATE
		var buzz := sin(phase) + 0.5 * sin(2.0 * phase) + 0.3 * sin(3.0 * phase)
		var env := minf(1.0, t / 0.05) * lerpf(0.35, 1.0, k) * (0.8 + 0.2 * sin(TAU * 9.0 * t)) * minf(1.0, (length_s - t) / 0.02)
		out[i] = env * buzz
	return _normalized(out, PEAK)


## Noise brightening and swelling over `length_s`, like a body filling with water (the puff tell).
func _hiss(length_s: float) -> PackedFloat32Array:
	var n := int(length_s * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var k := t / length_s
		var white := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, lerpf(0.08, 0.6, k))
		var env := minf(1.0, t / 0.08) * lerpf(0.3, 1.0, k) * minf(1.0, (length_s - t) / 0.02)
		out[i] = env * (low + 0.3 * white * k)
	return _normalized(out, PEAK)


## A short bright noise click.
func _click(length_s: float, decay_s: float) -> PackedFloat32Array:
	var n := int(length_s * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		out[i] = _rng.randf_range(-1.0, 1.0) * exp(-t / (decay_s * length_s))
	return out


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
