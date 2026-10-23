class_name CellAudio
extends Node
## The cell stage's sound: effects for confirmed sim events, the ambience of the fluid, the
## cell's own swimming, and the mood it hands the soundtrack. The files are rendered by
## tools/audio/make_cell_audio.gd and listed in assets/records/audio/. Every effect has a visual
## equivalent, and effects play only for confirmed sim events (Bible 20).
##
## The pool calls play(cue) and play_at(cue, at) for the events it routes. This node also listens
## to the pool's sim_event signal for the cues the pool does not route itself: the cell's death,
## a strike, a cancelled tell (which stops that creature's tell sound) and, in the endless world,
## entering a region. It reads the pool's sim each frame for the swim sound and the music's mood.
##
## Effects with variants pick one at random (never the last one) and vary their pitch a little.
## Positional cues play where they happen through a small pool of 3D players, so a tell off screen
## is still heard. On the dummy audio driver (headless runs) nothing is started, since that driver
## never mixes; cues are still counted in `played`, and the mood is still worked out.

## Every cue: variants (files <cue>_<n>.wav), level in dB, pitch jitter (a share, either way) and
## whether it is heard where it happens. Tells keep their pitch: they must end as the strike starts.
const CUE_TABLE := {
	"eat_plant": {"variants": 3, "db": -5.0, "jitter": 0.05},
	"eat_meat": {"variants": 3, "db": -4.0, "jitter": 0.05},
	"refuse": {"variants": 1, "db": -9.0, "jitter": 0.02},
	"starve_pulse": {"variants": 1, "db": -3.0, "jitter": 0.0},
	"notice": {"variants": 2, "db": -4.0, "jitter": 0.04, "positional": true},
	"tell_lunge": {"variants": 1, "db": -2.0, "jitter": 0.0, "positional": true},
	"tell_puff": {"variants": 1, "db": -2.0, "jitter": 0.0, "positional": true},
	"tell_cancel": {"variants": 1, "db": -8.0, "jitter": 0.05, "positional": true},
	"strike": {"variants": 2, "db": -5.0, "jitter": 0.06, "positional": true},
	"bite": {"variants": 3, "db": -4.0, "jitter": 0.06, "positional": true},
	"ram": {"variants": 2, "db": -3.0, "jitter": 0.05, "positional": true},
	"hurt": {"variants": 2, "db": -3.0, "jitter": 0.04},
	"dodged": {"variants": 2, "db": -6.0, "jitter": 0.03},
	"creature_die": {"variants": 2, "db": -4.0, "jitter": 0.05, "positional": true},
	"player_die": {"variants": 1, "db": -3.0, "jitter": 0.0},
	"respawn": {"variants": 1, "db": -7.0, "jitter": 0.0},
	"region_enter": {"variants": 1, "db": -10.0, "jitter": 0.0},
	"region_rare": {"variants": 1, "db": -7.0, "jitter": 0.0},
	"grow_warn": {"variants": 1, "db": -7.0, "jitter": 0.0},
	"grow": {"variants": 1, "db": -4.0, "jitter": 0.0},
	"growth_ring": {"variants": 1, "db": -7.0, "jitter": 0.03},
	"now_food": {"variants": 1, "db": -7.0, "jitter": 0.0},
}
## The cues the M1 pool plays (kept from step 3's placeholder audio) and the ones added since.
const CUES: PackedStringArray = ["eat_plant", "eat_meat", "refuse", "starve_pulse", "notice", "tell_lunge",
	"tell_puff", "tell_cancel", "strike", "bite", "ram", "hurt", "dodged", "creature_die", "player_die",
	"respawn", "region_enter", "region_rare", "grow_warn", "grow", "growth_ring", "now_food"]
const SFX_DIR := "res://assets/audio/sfx"
const AMB_DIR := "res://assets/audio/ambience"
const REPEAT_LIMIT_MS := 60      ## the same cue at most once per this long
const FLAT_POLYPHONY := 3
const POSITIONAL_PLAYERS := 8
const MAX_DISTANCE_M := 30.0
const UNIT_SIZE_M := 12.0        ## full volume this close to the camera (the cell is 10-20 m away)
## Ambience: the bed under everything and one detail layer per region, crossfaded.
const REGIONS: PackedStringArray = ["sunlit", "reef", "drift"]
const DEFAULT_REGION := "sunlit"
const BED_DB := -6.0
const REGION_DB := -4.0
const REGION_FADE_S := 3.0
## The swim sound: silent at rest, this loud at full speed.
const SWIM_DB := -9.0
const SWIM_SMOOTH_S := 0.15
## Seconds the music stays tense after a creature last went for the cell.
const DANGER_HOLD_S := 6.0
const SILENT_DB := -80.0

## How many times each cue was played (or would have been, on the dummy driver).
var played := {}
## The music's mood as last worked out: "calm", "danger", "starving" or "dead".
var mood := "calm"
var region := DEFAULT_REGION

var _streams := {}               ## cue -> Array[AudioStreamWAV], one per variant
var _flat := {}                  ## cue -> AudioStreamPlayer
var _positional: Array[AudioStreamPlayer3D] = []
var _next_positional := 0
var _tell_players := {}          ## creature id -> the AudioStreamPlayer3D playing its tell
var _pending_tell: AudioStreamPlayer3D   ## the tell play_at just started, until its event names the creature
var _last_variant := {}
var _last_played_ms := {}
var _bed: AudioStreamPlayer
var _regions := {}               ## region -> AudioStreamPlayer
var _swim: AudioStreamPlayer
var _swim_gain := 0.0
var _danger_until_ms := -1
var _size := 1
var _rng := RandomNumberGenerator.new()
var _silent := AudioServer.get_driver_name() == "Dummy"
var _pool: Node


func _ready() -> void:
	_rng.randomize()
	_load_streams()
	for cue in CUES:
		if CUE_TABLE[cue].get("positional", false):
			continue
		var player := AudioStreamPlayer.new()
		player.name = cue
		player.bus = &"SFX"
		player.volume_db = CUE_TABLE[cue].db
		player.max_polyphony = FLAT_POLYPHONY
		add_child(player)
		_flat[cue] = player
	for i in POSITIONAL_PLAYERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "positional_%d" % i
		player.bus = &"SFX"
		player.unit_size = UNIT_SIZE_M
		player.max_distance = MAX_DISTANCE_M
		add_child(player)
		_positional.append(player)
	_bed = _loop_player("ambience_bed", "amb_bed", BED_DB)
	for r in REGIONS:
		_regions[r] = _loop_player("ambience_" + r, "amb_" + r, REGION_DB if r == region else SILENT_DB)
	_swim = _loop_player("swim", "amb_swim", SILENT_DB)
	if not _silent:
		_bed.play()
		_regions[region].play()
		_swim.play()
	attach(get_parent())


## Follows a pool: its sim_event signal, and its `sim` and `paused` each frame. _ready attaches
## the parent.
func attach(pool: Node) -> void:
	_pool = pool
	if pool != null and pool.has_signal("sim_event") and not pool.sim_event.is_connected(_on_sim_event):
		pool.sim_event.connect(_on_sim_event)


func _exit_tree() -> void:
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_mood("title")
		soundtrack.set_paused(false)


## Sets the tell cues' lengths in seconds: {"lunge": s, "puff": s} (the species' attack tell and
## tell_s). A length other than the rendered file's is rendered again here, so each growl or hiss
## ends as the strike starts.
func configure_tells(lengths: Dictionary) -> void:
	_load_streams()
	for tell in lengths:
		var cue := "tell_%s" % tell
		var length_s := float(lengths[tell])
		if not _streams.has(cue) or length_s <= 0.0 or absf(length_of(cue) - length_s) < 0.002:
			continue
		_streams[cue] = [_to_stream(AudioSynth.render_sfx(cue, 0, length_s))]
		if _flat.has(cue):
			(_flat[cue] as AudioStreamPlayer).stream = _streams[cue][0]


## Plays a cue unless the same one played within REPEAT_LIMIT_MS. Unknown cues are ignored.
## Positional cues played this way are heard flat, at the cell.
func play(cue: String) -> void:
	_load_streams()
	if not _streams.has(cue) or not _may_play(cue):
		return
	var player: AudioStreamPlayer = _flat.get(cue)
	if player == null:
		player = _flat_for_positional(cue)
	player.stream = _pick(cue)
	player.pitch_scale = _pitch(cue)
	if not _silent and player.is_inside_tree():
		player.play()


## Plays a cue at a place in the world (positional, with distance and panning from the camera),
## under the same repeat rule. Cues that are not positional play flat.
func play_at(cue: String, at: Vector3) -> void:
	_load_streams()
	if not _streams.has(cue):
		return
	if not CUE_TABLE[cue].get("positional", false) or _positional.is_empty():
		play(cue)
		return
	if not _may_play(cue):
		return
	var player := _positional[_next_positional]
	_next_positional = (_next_positional + 1) % _positional.size()
	for id in _tell_players.keys():
		if _tell_players[id] == player:
			_tell_players.erase(id)
	player.stream = _pick(cue)
	player.volume_db = CUE_TABLE[cue].db
	player.pitch_scale = _pitch(cue)
	player.global_position = at
	_pending_tell = player if cue == "tell_lunge" or cue == "tell_puff" else null
	if not _silent and player.is_inside_tree():
		player.play()


## The music's layers grow with the cell (1 to 4 in M1's endless world).
func set_size(size: int) -> void:
	_size = maxi(1, size)
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_size(_size)


## Crossfades the ambience to a region's detail layer ("sunlit", "reef" or "drift").
func set_region(name_: String) -> void:
	if not name_ in REGIONS or name_ == region:
		return
	var outgoing: AudioStreamPlayer = _regions.get(region)
	var incoming: AudioStreamPlayer = _regions.get(name_)
	region = name_
	if outgoing == null or incoming == null or not is_inside_tree():
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(outgoing, "volume_db", SILENT_DB, REGION_FADE_S)
	tween.tween_property(incoming, "volume_db", REGION_DB, REGION_FADE_S)
	if not _silent:
		if not incoming.playing:
			incoming.play()
		tween.chain().tween_callback(outgoing.stop)


## The rendered stream of a cue's first variant, for tests.
func stream_of(cue: String) -> AudioStreamWAV:
	_load_streams()
	return _streams[cue][0] if _streams.has(cue) else null


## Length of a cue's first variant in seconds.
func length_of(cue: String) -> float:
	var stream := stream_of(cue)
	return stream.get_length() if stream != null else 0.0


func _process(delta: float) -> void:
	var sim: Object = _pool.get("sim") if _pool != null else null
	if sim == null:
		return
	var paused := bool(_pool.get("paused"))
	var dead := bool(sim.get("dead"))
	# The swim sound follows the cell's speed.
	var target := 0.0
	if not paused and not dead and sim.get("motion") != null and sim.get("phenotype") != null:
		var top: float = maxf(0.1, sim.phenotype.speed)
		target = clampf(sim.motion.velocity.length() / top, 0.0, 1.0)
	_swim_gain = lerpf(_swim_gain, target, 1.0 - exp(-delta / SWIM_SMOOTH_S))
	_swim.volume_db = SWIM_DB + linear_to_db(maxf(_swim_gain, 1e-4))
	# The music's mood.
	if dead:
		mood = "dead"
	elif Time.get_ticks_msec() < _danger_until_ms:
		mood = "danger"
	elif sim.get("state") != null and sim.state.is_starving():
		mood = "starving"
	else:
		mood = "calm"
	var soundtrack := _soundtrack()
	if soundtrack != null:
		soundtrack.set_mood(mood)
		soundtrack.set_paused(paused)


func _on_sim_event(event: Dictionary) -> void:
	var player_id := CreatureField.PLAYER_ID
	match String(event.get("type", "")):
		"died":
			_danger_until_ms = -1
			play("player_die")
		"creature_noticed", "creature_strike":
			if event.get("target") == player_id:
				_danger_until_ms = Time.get_ticks_msec() + int(DANGER_HOLD_S * 1000.0)
			if event.type == "creature_strike":
				_tell_players.erase(event.get("id"))
				play_at("strike", _where(event))
		"creature_tell":
			if event.get("target") == player_id:
				_danger_until_ms = Time.get_ticks_msec() + int(DANGER_HOLD_S * 1000.0)
			# The pool played the tell just before this signal; remember whose it is.
			if _pending_tell != null:
				_tell_players[event.get("id")] = _pending_tell
			_pending_tell = null
		"tell_cancelled":
			var tell: AudioStreamPlayer3D = _tell_players.get(event.get("id"))
			_tell_players.erase(event.get("id"))
			if tell != null and tell.playing and is_inside_tree():
				var tween := create_tween()
				tween.tween_property(tell, "volume_db", SILENT_DB, 0.12)
				tween.tween_callback(tell.stop)
			play_at("tell_cancel", _where(event))
		"hit":
			if event.get("target") == player_id:
				_danger_until_ms = Time.get_ticks_msec() + int(DANGER_HOLD_S * 1000.0)
		"tile_entered":
			var name_ := String(event.get("region", ""))
			if not String(event.get("rare", "")).is_empty():
				play("region_rare")
			elif name_ in REGIONS and name_ != region:
				play("region_enter")
			set_region(name_)


func _where(event: Dictionary) -> Vector3:
	var p: Variant = event.get("position")
	return PlaneSpace.to_world(p) if p is Vector2 else Vector3.ZERO


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


## A variant other than the last one played (when there is more than one).
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
	var jitter: float = CUE_TABLE[cue].jitter
	return 1.0 + _rng.randf_range(-jitter, jitter) if jitter > 0.0 else 1.0


## A flat player for a positional cue played with play(): made the first time it is needed.
func _flat_for_positional(cue: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = cue
	player.bus = &"SFX"
	player.volume_db = CUE_TABLE[cue].db
	player.max_polyphony = FLAT_POLYPHONY
	add_child(player)
	_flat[cue] = player
	return player


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
	for cue in CUES:
		var variants := []
		for v in int(CUE_TABLE[cue].variants):
			variants.append(load("%s/%s_%d.wav" % [SFX_DIR, cue, v + 1]))
		_streams[cue] = variants


func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AudioSynth.SFX_RATE
	stream.data = data
	return stream
