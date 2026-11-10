extends Node
## The friend path's display sounds (PROPOSED, backlog M5-02): one short voice per display (sing, dance, charm,
## pose), a soft "no" for a wrong one and a rising chime when a creature joins the pack. The sounds are original:
## they are rendered once, on first use, from AudioSynth's blocks (no files), and play on the SFX bus. No class_name
## so CreatureWorld loads it by path. On the dummy driver (headless) nothing is rendered; `played` still counts.

const RATE := 22050
const CUES := ["sing", "dance", "charm", "pose", "missed", "befriended"]
const VOLUME_DB := -8.0

## How many times each cue was played (or would have been, on the dummy driver).
var played := {}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _silent := AudioServer.get_driver_name() == "Dummy"


func _ready() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
		p.volume_db = VOLUME_DB
		add_child(p)
		_players.append(p)


## Plays `cue`; `pitch` raises it a little for a later step of the same courtship (1.0 as written).
func play(cue: String, pitch := 1.0) -> void:
	if not CUES.has(cue):
		return
	played[cue] = int(played.get(cue, 0)) + 1
	if _silent or _players.is_empty():
		return
	if not _streams.has(cue):
		_streams[cue] = _to_stream(render(cue))
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[cue]
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()


## The samples of a cue (mono, RATE Hz), the same on every call.
static func render(cue: String) -> PackedFloat32Array:
	var s := AudioSynth.new(RATE, 7 + CUES.find(cue))
	var out := s.silence(0.75)
	match cue:
		"sing":   # two rising voiced notes
			s.mix(out, s.shaped(s.sweep(0.28, 392.0, 440.0, 0.35, 0.12), 0.03, 0.2), 0.0, 0.8)
			s.mix(out, s.shaped(s.sweep(0.36, 494.0, 587.0, 0.35, 0.12), 0.03, 0.26), 0.26, 0.8)
		"dance":   # four quick plucks, a skipping rhythm
			var notes := [330.0, 392.0, 330.0, 494.0]
			for i in notes.size():
				s.mix(out, s.pluck(0.22, notes[i], 0.992, 0.6), 0.14 * i, 0.8)
		"charm":   # a soft falling coo
			s.mix(out, s.shaped(s.sweep(0.55, 660.0, 440.0, 0.2, 0.05), 0.08, 0.4), 0.0, 0.7)
			s.mix(out, s.bell(0.5, 880.0, 0.25, 2.0, 0.8), 0.1, 0.25)
		"pose":   # one proud held bell chord
			s.mix(out, s.bell(0.7, 262.0, 0.45, 2.0, 1.2), 0.0, 0.6)
			s.mix(out, s.bell(0.7, 392.0, 0.45, 2.0, 1.0), 0.02, 0.45)
		"missed":   # a short low "uh-uh"
			s.mix(out, s.shaped(s.sweep(0.16, 220.0, 196.0, 0.4, 0.2), 0.01, 0.12), 0.0, 0.7)
			s.mix(out, s.shaped(s.sweep(0.2, 185.0, 147.0, 0.4, 0.2), 0.01, 0.16), 0.2, 0.7)
		"befriended":   # a rising three-bell chime
			var chime := [523.0, 659.0, 784.0]
			for i in chime.size():
				s.mix(out, s.bell(0.5, chime[i], 0.3, 3.0, 1.0), 0.11 * i, 0.55)
	return s.normalized(s.faded(out, 0.002, 0.05), 0.8)


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
