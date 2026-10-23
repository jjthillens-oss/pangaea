class_name Soundtrack
extends Node
## The music: composed CC0 instrumentals (assets/audio/music/, sources in assets/records/audio/).
##   title    one track, looped, on the title screen
##   calm     a playlist, shuffled, each track followed by a short rest, while the cell explores
##   danger   one tense track, looped, faded in fast while a creature hunts the cell; the calm
##            track keeps playing quietly under it and comes back where it was
## Starving and death close a low-pass on the Music bus and turn the calm track down, and so does
## the pause menu. It lives in main.tscn, so the music carries on from the title into the pool;
## the pool's CellAudio finds it by GROUP and sets the mood each frame.
##
## On the dummy audio driver (headless runs) nothing is started; the levels are still worked out.

const GROUP := &"soundtrack"
const MUSIC_DIR := "res://assets/audio/music"
const TITLE_TRACK := "mus_magic_space.mp3"
const CALM_TRACKS: PackedStringArray = ["mus_another_august.mp3", "mus_aquaria.ogg", "mus_drifting.ogg", "mus_nautilus.mp3"]
const DANGER_TRACK := "mus_frenzied_swimming.ogg"
## The layers: title, calm and danger, each its own player.
const LAYERS: PackedStringArray = ["title", "calm", "danger"]
const LEVEL_DB := -8.0
const OFF_DB := -80.0
## Each mood's layer levels in dB (missing layers are off) and the Music bus's low-pass cutoff.
const MOODS := {
	"title": {"layers": {"title": 0.0}, "cutoff_hz": 20000.0},
	"calm": {"layers": {"calm": 0.0}, "cutoff_hz": 20000.0},
	"danger": {"layers": {"calm": -16.0, "danger": 0.0}, "cutoff_hz": 20000.0},
	"starving": {"layers": {"calm": -4.0}, "cutoff_hz": 1100.0},
	"dead": {"layers": {"calm": -8.0}, "cutoff_hz": 550.0},
}
const PAUSED_CUTOFF_HZ := 1800.0
## Seconds of rest between calm tracks.
const REST_S := Vector2(4.0, 9.0)
## Time constants: danger comes in fast, everything else drifts.
const FAST_S := 0.35
const SLOW_S := 1.8

var mood := "title"
var size := 1
var paused := false
## The calm playlist in the order it will play (shuffled once per round).
var playlist := PackedStringArray()

var _players := {}                     ## layer -> AudioStreamPlayer
var _gain := {}                        ## layer -> current linear gain
var _next := 0
var _rest_left := -1.0
var _cutoff := 20000.0
var _rng := RandomNumberGenerator.new()
var _silent := AudioServer.get_driver_name() == "Dummy"


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for layer in LAYERS:
		var player := AudioStreamPlayer.new()
		player.name = layer.capitalize()
		player.bus = &"Music"
		add_child(player)
		_players[layer] = player
		_gain[layer] = db_to_linear(target_db(layer))
	_players.title.stream = _track(TITLE_TRACK, true)
	_players.danger.stream = _track(DANGER_TRACK, true)
	_players.calm.finished.connect(_on_calm_finished)
	_shuffle()
	_apply_levels()
	_start(_players.title)


func set_mood(value: String) -> void:
	if not MOODS.has(value) or value == mood:
		return
	mood = value
	var calm: AudioStreamPlayer = _players.get("calm")
	if calm != null and mood != "title" and not calm.playing and _rest_left < 0.0:
		_play_next_calm()
	var danger: AudioStreamPlayer = _players.get("danger")
	if danger != null and mood == "danger" and not danger.playing:
		_start(danger)


func set_size(value: int) -> void:
	size = maxi(1, value)


func set_paused(value: bool) -> void:
	paused = value


## The level a layer is heading for in the current mood.
func target_db(layer: String) -> float:
	return float(MOODS[mood].layers.get(layer, OFF_DB))


## The current level of a layer in dB, for tests and the debug panel.
func level_db(layer: String) -> float:
	return linear_to_db(maxf(float(_gain.get(layer, 0.0)), 1e-4))


## The Music bus's low-pass cutoff the mood is heading for.
func target_cutoff_hz() -> float:
	var cutoff: float = MOODS[mood].cutoff_hz
	return minf(cutoff, PAUSED_CUTOFF_HZ) if paused else cutoff


func _process(delta: float) -> void:
	for layer in LAYERS:
		var target := db_to_linear(target_db(layer))
		var tau := FAST_S if layer == "danger" and target > _gain[layer] else SLOW_S
		_gain[layer] = lerpf(_gain[layer], target, 1.0 - exp(-delta / tau))
	_apply_levels()
	# A layer faded out all the way stops, so it starts fresh next time (the calm one keeps going).
	for layer in ["title", "danger"]:
		var player: AudioStreamPlayer = _players[layer]
		if player.playing and target_db(layer) <= OFF_DB and _gain[layer] < 0.002:
			player.stop()
	if mood == "title" and not _players.title.playing:
		_start(_players.title)
	if _rest_left >= 0.0:
		_rest_left -= delta
		if _rest_left < 0.0 and mood != "title":
			_play_next_calm()
	# Glide the cutoff in octaves, so opening and closing sound even.
	var goal := log(target_cutoff_hz())
	_cutoff = exp(lerpf(log(_cutoff), goal, 1.0 - exp(-delta / (FAST_S if goal < log(_cutoff) else SLOW_S))))
	var bus := AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		for e in AudioServer.get_bus_effect_count(bus):
			var effect := AudioServer.get_bus_effect(bus, e)
			if effect is AudioEffectLowPassFilter:
				(effect as AudioEffectLowPassFilter).cutoff_hz = _cutoff


func _apply_levels() -> void:
	for layer in LAYERS:
		(_players[layer] as AudioStreamPlayer).volume_db = LEVEL_DB + maxf(OFF_DB, linear_to_db(maxf(_gain[layer], 1e-4)))


func _play_next_calm() -> void:
	_rest_left = -1.0
	if _next >= playlist.size():
		_shuffle()
	var player: AudioStreamPlayer = _players.calm
	player.stream = _track(playlist[_next], false)
	_next += 1
	_start(player)


func _on_calm_finished() -> void:
	_rest_left = _rng.randf_range(REST_S.x, REST_S.y)


## A new round of the calm playlist, never starting with the track that just ended.
func _shuffle() -> void:
	var last := playlist[playlist.size() - 1] if not playlist.is_empty() else ""
	var order := Array(CALM_TRACKS)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: String = order[i]
		order[i] = order[j]
		order[j] = swap
	if order.size() > 1 and order[0] == last:
		order.append(order.pop_front())
	playlist = PackedStringArray(order)
	_next = 0


func _start(player: AudioStreamPlayer) -> void:
	if not _silent and player.is_inside_tree():
		player.play()


func _track(file: String, loop: bool) -> AudioStream:
	var stream: AudioStream = load("%s/%s" % [MUSIC_DIR, file])
	if stream != null and "loop" in stream:
		stream.set("loop", loop)
	return stream
