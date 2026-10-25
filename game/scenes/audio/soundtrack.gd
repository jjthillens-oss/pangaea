class_name Soundtrack
extends Node
## The music: composed CC0 instrumentals (assets/audio/music/, sources in assets/records/audio/).
##   title    one track, looped, on the title screen
##   calm     the stage's playlist, shuffled, each track followed by a short rest, while you explore
##   danger   the stage's tense track, looped, faded in fast while something hunts you; the calm
##            track keeps playing quietly under it and comes back where it was
##   editor   while an editor is open (set_editor), a gentle track of its own, looped; the stage's
##            calm track pauses under it and picks up where it was when the editor closes
## Each stage (set_stage: cell, aquatic, creature) has its own calm playlist and danger track; a
## stage change fades the old one out before the new one starts. Starving and death close a
## low-pass on the Music bus and turn the calm track down, and so does the pause menu. It lives in
## main.tscn, so the music carries on from the title into a stage; the pool's CellAudio finds it by
## GROUP and sets the mood each frame, and other stages call it through the group.
##
## On the dummy audio driver (headless runs) nothing is started; the levels are still worked out.

const GROUP := &"soundtrack"
const MUSIC_DIR := "res://assets/audio/music"
const TITLE_TRACK := "mus_magic_space.mp3"
## The cell stage's playlist and danger track (the "cell" entry of STAGES).
const CALM_TRACKS: PackedStringArray = ["mus_another_august.mp3", "mus_aquaria.ogg", "mus_drifting.ogg", "mus_nautilus.mp3"]
const DANGER_TRACK := "mus_frenzied_swimming.ogg"
## Each stage's calm playlist and danger track.
const STAGES := {
	"cell": {"calm": CALM_TRACKS, "danger": DANGER_TRACK},
	"aquatic": {"calm": ["mus_underwater_theme.mp3", "mus_underwater_world.mp3", "mus_deep_sea.mp3",
		"mus_underwater_variation.ogg"], "danger": DANGER_TRACK},
	"creature": {"calm": ["mus_beautiful_forest.ogg", "mus_fantasy_orchestral.mp3", "mus_at_home.ogg",
		"mus_new_sunrise.ogg"], "danger": "mus_determined_pursuit.ogg"},
}
const DEFAULT_STAGE := "cell"
## The editors' tracks, taken in turn each time an editor opens.
const EDITOR_TRACKS: PackedStringArray = ["mus_happy_lullaby.mp3", "mus_heavenly_loop.ogg", "mus_vaporware.mp3"]
## Each file's gain in dB, so the tracks sit near one loudness (about -16 LUFS, danger -14). The files
## are the composers' own, unchanged; the levels live here.
const TRACK_GAIN_DB := {
	"mus_magic_space.mp3": -2.5, "mus_another_august.mp3": 3.0, "mus_aquaria.ogg": -5.0, "mus_drifting.ogg": 2.0,
	"mus_nautilus.mp3": 6.0, "mus_frenzied_swimming.ogg": 3.0,
	"mus_underwater_theme.mp3": -0.5, "mus_underwater_world.mp3": -5.0, "mus_deep_sea.mp3": 5.5,
	"mus_underwater_variation.ogg": -3.0,
	"mus_beautiful_forest.ogg": -1.0, "mus_fantasy_orchestral.mp3": -0.5, "mus_at_home.ogg": 6.0,
	"mus_new_sunrise.ogg": -1.0, "mus_determined_pursuit.ogg": -1.0,
	"mus_happy_lullaby.mp3": -3.5, "mus_heavenly_loop.ogg": 6.0, "mus_vaporware.mp3": 2.5,
}
## The layers: title, calm, danger and editor, each its own player.
const LAYERS: PackedStringArray = ["title", "calm", "danger", "editor"]
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
## A layer this quiet (linear) counts as faded out.
const SILENT := 0.002

var mood := "title"
var stage := DEFAULT_STAGE
var editor := false
var size := 1
var paused := false
## The calm playlist in the order it will play (shuffled once per round).
var playlist := PackedStringArray()

var _players := {}                     ## layer -> AudioStreamPlayer
var _gain := {}                        ## layer -> current linear gain
var _file_db := {}                     ## layer -> TRACK_GAIN_DB of the file it holds
var _next := 0
var _next_editor := 0
var _stage_pending := false            ## a stage change waits for the old stage's music to fade
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
		_file_db[layer] = 0.0
	_load(_players.title, TITLE_TRACK, true)
	_load(_players.danger, STAGES[stage].danger, true)
	_players.calm.finished.connect(_on_calm_finished)
	_next_editor = _rng.randi_range(0, EDITOR_TRACKS.size() - 1)
	_shuffle()
	_apply_levels()
	_start(_players.title)


func set_mood(value: String) -> void:
	if not MOODS.has(value) or value == mood:
		return
	mood = value
	var calm: AudioStreamPlayer = _players.get("calm")
	if calm != null and mood != "title" and not calm.playing and _rest_left < 0.0 and not _stage_pending:
		_play_next_calm()
	var danger: AudioStreamPlayer = _players.get("danger")
	if danger != null and mood == "danger" and not danger.playing:
		_start(danger)


## Switches to a stage's music (STAGES). Music already playing fades out first.
func set_stage(value: String) -> void:
	if not STAGES.has(value) or value == stage:
		return
	stage = value
	if _players.is_empty():
		return
	if _players.calm.playing or _players.danger.playing or _rest_left >= 0.0:
		_stage_pending = true
	else:
		_apply_stage()


## Opens or closes an editor's music.
func set_editor(value: bool) -> void:
	if value == editor:
		return
	editor = value
	var player: AudioStreamPlayer = _players.get("editor")
	if editor and player != null and not player.playing:
		_load(player, EDITOR_TRACKS[_next_editor % EDITOR_TRACKS.size()], true)
		_next_editor += 1
		_start(player)


## The calm playlist of the current stage.
func calm_tracks() -> PackedStringArray:
	return PackedStringArray(STAGES[stage].calm)


func set_size(value: int) -> void:
	size = maxi(1, value)


func set_paused(value: bool) -> void:
	paused = value


## The level a layer is heading for in the current mood.
func target_db(layer: String) -> float:
	if editor:
		return 0.0 if layer == "editor" else OFF_DB
	if _stage_pending and layer in ["calm", "danger"]:
		return OFF_DB
	return float(MOODS[mood].layers.get(layer, OFF_DB))


## The current level of a layer in dB, for tests and the debug panel.
func level_db(layer: String) -> float:
	return linear_to_db(maxf(float(_gain.get(layer, 0.0)), 1e-4))


## The Music bus's low-pass cutoff the mood is heading for.
func target_cutoff_hz() -> float:
	if editor:
		return 20000.0
	var cutoff: float = MOODS[mood].cutoff_hz
	return minf(cutoff, PAUSED_CUTOFF_HZ) if paused else cutoff


func _process(delta: float) -> void:
	for layer in LAYERS:
		var target := db_to_linear(target_db(layer))
		var tau := FAST_S if (layer == "danger" and target > _gain[layer]) or _stage_pending or (editor and layer != "editor") else SLOW_S
		_gain[layer] = lerpf(_gain[layer], target, 1.0 - exp(-delta / tau))
	_apply_levels()
	# A layer faded out all the way stops, so it starts fresh next time (the calm one keeps going).
	for layer in ["title", "danger", "editor"]:
		var player: AudioStreamPlayer = _players[layer]
		if player.playing and target_db(layer) <= OFF_DB and _gain[layer] < SILENT:
			player.stop()
	# The calm track holds its place under an editor.
	_players.calm.stream_paused = editor and _gain.calm < SILENT
	if _stage_pending and _gain.calm < SILENT and _gain.danger < SILENT:
		_apply_stage()
	if mood == "title" and not _players.title.playing:
		_start(_players.title)
	if _rest_left >= 0.0:
		_rest_left -= delta
		if _rest_left < 0.0 and mood != "title" and not _stage_pending:
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
		(_players[layer] as AudioStreamPlayer).volume_db = LEVEL_DB + float(_file_db[layer]) + maxf(OFF_DB, linear_to_db(maxf(_gain[layer], 1e-4)))


func _play_next_calm() -> void:
	_rest_left = -1.0
	if _next >= playlist.size():
		_shuffle()
	var player: AudioStreamPlayer = _players.calm
	_load(player, playlist[_next], false)
	_next += 1
	_start(player)


func _on_calm_finished() -> void:
	_rest_left = _rng.randf_range(REST_S.x, REST_S.y)


## A new round of the calm playlist, never starting with the track that just ended.
func _shuffle() -> void:
	var last := playlist[playlist.size() - 1] if not playlist.is_empty() else ""
	var order := Array(calm_tracks())
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: String = order[i]
		order[i] = order[j]
		order[j] = swap
	if order.size() > 1 and order[0] == last:
		order.append(order.pop_front())
	playlist = PackedStringArray(order)
	_next = 0


## The stage's music from the top: its danger track and a new round of its playlist.
func _apply_stage() -> void:
	_stage_pending = false
	_players.calm.stop()
	_players.danger.stop()
	_rest_left = -1.0
	_load(_players.danger, STAGES[stage].danger, true)
	playlist = PackedStringArray()
	_shuffle()
	if mood != "title":
		_play_next_calm()
	if mood == "danger":
		_start(_players.danger)


func _load(player: AudioStreamPlayer, file: String, loop: bool) -> void:
	player.stream = _track(file, loop)
	for layer in _players:
		if _players[layer] == player:
			_file_db[layer] = float(TRACK_GAIN_DB.get(file, 0.0))


func _start(player: AudioStreamPlayer) -> void:
	if not _silent and player.is_inside_tree():
		player.play()


func _track(file: String, loop: bool) -> AudioStream:
	var stream: AudioStream = load("%s/%s" % [MUSIC_DIR, file])
	if stream != null and "loop" in stream:
		stream.set("loop", loop)
	return stream
