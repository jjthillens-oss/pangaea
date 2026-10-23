class_name Soundtrack
extends Node
## The adaptive music. Four stems of one 48 s loop (assets/audio/music/, rendered by
## tools/audio/make_cell_audio.gd) play in sync, and the mood sets how loud each one is:
##   pad      the chord bed, always on
##   motif    the theme on glass bells: title and calm
##   counter  an arpeggio added as the cell grows (size 2 and up)
##   pulse    the danger layer, faded in fast while a creature hunts the cell
## Starving and death also close a low-pass on the Music bus, and so does the pause menu.
## It lives in main.tscn, so the music carries on from the title into the pool; the pool's
## CellAudio finds it by GROUP and sets the mood each frame.
##
## On the dummy audio driver (headless runs) nothing is started; the levels are still worked out.

const GROUP := &"soundtrack"
const MUSIC_DIR := "res://assets/audio/music"
const STEMS: PackedStringArray = ["pad", "motif", "counter", "pulse"]
const LEVEL_DB := -9.0
const OFF_DB := -80.0
## Each mood's stem levels in dB (missing stems are off) and the Music bus's low-pass cutoff.
const MOODS := {
	"title": {"stems": {"pad": 0.0, "motif": -2.0}, "cutoff_hz": 20000.0},
	"calm": {"stems": {"pad": 0.0, "motif": 0.0}, "cutoff_hz": 20000.0},
	"danger": {"stems": {"pad": -2.0, "motif": -14.0, "pulse": 0.0}, "cutoff_hz": 20000.0},
	"starving": {"stems": {"pad": -3.0, "motif": -15.0}, "cutoff_hz": 1100.0},
	"dead": {"stems": {"pad": -5.0}, "cutoff_hz": 550.0},
}
## The counter stem's level in calm from size 2 up.
const COUNTER_DB := -2.0
const PAUSED_CUTOFF_HZ := 1800.0
## Time constants: danger comes in fast, everything else drifts.
const FAST_S := 0.35
const SLOW_S := 1.6

var mood := "title"
var size := 1
var paused := false

var _player: AudioStreamPlayer
var _music: AudioStreamSynchronized
var _gain := PackedFloat32Array()      ## each stem's current linear gain
var _cutoff := 20000.0
var _silent := AudioServer.get_driver_name() == "Dummy"


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamSynchronized.new()
	_music.stream_count = STEMS.size()
	_gain.resize(STEMS.size())
	for i in STEMS.size():
		_music.set_sync_stream(i, load("%s/mus_%s.wav" % [MUSIC_DIR, STEMS[i]]))
		_gain[i] = db_to_linear(target_db(STEMS[i]))
		_music.set_sync_stream_volume(i, target_db(STEMS[i]))
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = &"Music"
	_player.stream = _music
	_player.volume_db = LEVEL_DB
	add_child(_player)
	if not _silent:
		_player.play()


func set_mood(value: String) -> void:
	if MOODS.has(value):
		mood = value


func set_size(value: int) -> void:
	size = maxi(1, value)


func set_paused(value: bool) -> void:
	paused = value


## The level a stem is heading for in the current mood and size.
func target_db(stem: String) -> float:
	var stems: Dictionary = MOODS[mood].stems
	if stem == "counter" and size >= 2 and (mood == "calm" or mood == "title"):
		return COUNTER_DB
	return float(stems.get(stem, OFF_DB))


## The current level of a stem in dB, for tests and the debug panel.
func level_db(stem: String) -> float:
	var i := STEMS.find(stem)
	return linear_to_db(maxf(_gain[i], 1e-4)) if i >= 0 else OFF_DB


## The Music bus's low-pass cutoff the mood is heading for.
func target_cutoff_hz() -> float:
	var cutoff: float = MOODS[mood].cutoff_hz
	return minf(cutoff, PAUSED_CUTOFF_HZ) if paused else cutoff


func _process(delta: float) -> void:
	for i in STEMS.size():
		var target := db_to_linear(target_db(STEMS[i]))
		var tau := FAST_S if STEMS[i] == "pulse" and target > _gain[i] else SLOW_S
		_gain[i] = lerpf(_gain[i], target, 1.0 - exp(-delta / tau))
		_music.set_sync_stream_volume(i, maxf(OFF_DB, linear_to_db(maxf(_gain[i], 1e-4))))
	# Glide the cutoff in octaves, so opening and closing sound even.
	var goal := log(target_cutoff_hz())
	_cutoff = exp(lerpf(log(_cutoff), goal, 1.0 - exp(-delta / (FAST_S if goal < log(_cutoff) else SLOW_S))))
	var bus := AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		for e in AudioServer.get_bus_effect_count(bus):
			var effect := AudioServer.get_bus_effect(bus, e)
			if effect is AudioEffectLowPassFilter:
				(effect as AudioEffectLowPassFilter).cutoff_hz = _cutoff
