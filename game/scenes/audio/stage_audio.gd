class_name StageAudio
extends Node
## The sound of a stage after the cell: its effects, its ambience, the player's own movement sound
## and the mood it hands the soundtrack. CreatureAudio and AquaticAudio fill in the cue tables and
## turn their sim's events into cues; the files are rendered by tools/audio/make_cell_audio.gd from
## game/scenes/audio/stage_synth.gd and listed in assets/records/audio/. Every effect has a visual
## equivalent, and effects play only for confirmed sim events (Bible 20).
##
## A stage adds one as a child and calls on_event(e) for each of its sim's events, set_motion(speed)
## each frame (0 at rest, 1 at full speed) and, where the sim has no event for it, play(cue) or
## play_at(cue, at). It sets the soundtrack's stage when it enters the tree, holds the danger mood
## for DANGER_HOLD_S after a threat last went for the player, and opens the editor's music with
## set_editor(true).
##
## Effects with variants pick one at random (never the last one) and vary their pitch a little.
## On the dummy audio driver (headless runs) nothing is started; cues are still counted in `played`.

const SFX_DIR := "res://assets/audio/sfx"
const AMB_DIR := "res://assets/audio/ambience"
const REPEAT_LIMIT_MS := 60
const FLAT_POLYPHONY := 3
const POSITIONAL_PLAYERS := 8
const MAX_DISTANCE_M := 40.0
const UNIT_SIZE_M := 6.0
const BED_DB := -6.0
const MOTION_SMOOTH_S := 0.15
const DANGER_HOLD_S := 6.0
## Seconds the music stays muffled after the player died.
const DEAD_HOLD_S := 5.0
const SILENT_DB := -80.0

## How many times each cue was played (or would have been, on the dummy driver).
var played := {}
## The music's mood as last worked out: "calm", "danger" or "dead".
var mood := "calm"

var _streams := {}
var _flat := {}
var _positional: Array[AudioStreamPlayer3D] = []
var _next_positional := 0
var _last_variant := {}
var _last_played_ms := {}
var _bed: AudioStreamPlayer
var _motion: AudioStreamPlayer
var _motion_gain := 0.0
var _motion_target := 0.0
var _danger_until_ms := -1
var _dead_until_ms := -1
var _editor := false
var _rng := RandomNumberGenerator.new()
var _silent := AudioServer.get_driver_name() == "Dummy"


## The soundtrack stage this audio belongs to (Soundtrack.STAGES).
func stage() -> String:
	return ""


## Every cue: {"variants", "db", "jitter", "positional"} (variants are files <cue>_<n>.wav).
func cue_table() -> Dictionary:
	return {}


## The ambience bed's file id and the movement loop's, with the movement loop's level at full speed.
func bed_id() -> String:
	return ""


func motion_id() -> String:
	return ""


func motion_db() -> float:
	return -9.0


## Turns one of the stage's sim events into cues and moods.
func on_event(_event: Dictionary) -> void:
	pass


func _ready() -> void:
	_rng.randomize()
	_load_streams()
	for i in POSITIONAL_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "positional_%d" % i
		player.bus = &"SFX"
		player.unit_size = UNIT_SIZE_M
		player.max_distance = MAX_DISTANCE_M
		add_child(player)
		_positional.append(player)
	if not bed_id().is_empty():
		_bed = _loop_player("ambience_bed", bed_id(), BED_DB)
	if not motion_id().is_empty():
		_motion = _loop_player("motion", motion_id(), SILENT_DB)
	if not _silent:
		for player in [_bed, _motion]:
			if player != null:
				player.play()
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_stage(stage())
		soundtrack.set_mood("calm")


func _exit_tree() -> void:
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_editor(false)
		soundtrack.set_mood("title")
		soundtrack.set_paused(false)


## Plays a cue flat, unless the same one played within REPEAT_LIMIT_MS. Unknown cues are ignored.
func play(cue: String) -> void:
	_load_streams()
	if not _streams.has(cue) or not _may_play(cue):
		return
	var player: AudioStreamPlayer = _flat.get(cue)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = cue
		player.bus = &"SFX"
		player.volume_db = float(cue_table()[cue].db)
		player.max_polyphony = FLAT_POLYPHONY
		add_child(player)
		_flat[cue] = player
	player.stream = _pick(cue)
	player.pitch_scale = _pitch(cue)
	if not _silent and player.is_inside_tree():
		player.play()


## Plays a cue where it happens in the world. Cues that are not positional play flat.
func play_at(cue: String, at: Vector3, gain_db: float = 0.0) -> void:
	_load_streams()
	if not _streams.has(cue):
		return
	if not cue_table()[cue].get("positional", false) or _positional.is_empty():
		play(cue)
		return
	if not _may_play(cue):
		return
	var player := _positional[_next_positional]
	_next_positional = (_next_positional + 1) % _positional.size()
	player.stream = _pick(cue)
	player.volume_db = float(cue_table()[cue].db) + gain_db
	player.pitch_scale = _pitch(cue)
	if player.is_inside_tree():
		player.global_position = at
	if not _silent and player.is_inside_tree():
		player.play()


## The player's speed as a share of its top speed (0 at rest), for the movement loop.
func set_motion(share: float) -> void:
	_motion_target = clampf(share, 0.0, 1.0)


## The editor opened or closed: its music comes in over the stage's.
func set_editor(open: bool) -> void:
	_editor = open
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_editor(open)


## Holds the danger mood for DANGER_HOLD_S from now.
func threatened() -> void:
	_danger_until_ms = Time.get_ticks_msec() + int(DANGER_HOLD_S * 1000.0)


## Ends the danger mood now (the threat gave up).
func safe() -> void:
	_danger_until_ms = -1


## The player died: the music is muffled for DEAD_HOLD_S.
func died() -> void:
	_danger_until_ms = -1
	_dead_until_ms = Time.get_ticks_msec() + int(DEAD_HOLD_S * 1000.0)


func _process(delta: float) -> void:
	_motion_gain = lerpf(_motion_gain, _motion_target if not _editor else 0.0, 1.0 - exp(-delta / MOTION_SMOOTH_S))
	if _motion != null:
		_motion.volume_db = motion_db() + linear_to_db(maxf(_motion_gain, 1e-4))
	var now := Time.get_ticks_msec()
	if now < _dead_until_ms:
		mood = "dead"
	elif now < _danger_until_ms:
		mood = "danger"
	else:
		mood = "calm"
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_mood(mood)


func _soundtrack() -> Soundtrack:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Soundtrack.GROUP) as Soundtrack


func _may_play(cue: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played_ms.get(cue, -REPEAT_LIMIT_MS)) < REPEAT_LIMIT_MS:
		return false
	_last_played_ms[cue] = now
	played[cue] = int(played.get(cue, 0)) + 1
	return true


func _pick(cue: String) -> AudioStream:
	var options: Array = _streams[cue]
	var k := 0
	if options.size() > 1:
		k = _rng.randi_range(0, options.size() - 2)
		if k >= int(_last_variant.get(cue, -1)):
			k += 1
	_last_variant[cue] = k
	return options[k]


func _pitch(cue: String) -> float:
	var jitter := float(cue_table()[cue].get("jitter", 0.0))
	return 1.0 + _rng.randf_range(-jitter, jitter) if jitter > 0.0 else 1.0


func _loop_player(node_name: String, file_id: String, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"Ambience"
	player.stream = load("%s/%s.wav" % [AMB_DIR, file_id])
	player.volume_db = db
	add_child(player)
	return player


func _load_streams() -> void:
	if not _streams.is_empty():
		return
	var table := cue_table()
	for cue in table:
		var variants := []
		for v in int(table[cue].variants):
			variants.append(load("%s/%s_%d.wav" % [SFX_DIR, cue, v + 1]))
		_streams[cue] = variants
