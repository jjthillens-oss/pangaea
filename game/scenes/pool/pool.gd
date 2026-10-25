class_name PoolScene
extends Node3D
## The pool: draws a running PoolSim and steps it (M1 step 2). Each physics tick it asks the
## intent provider (SwimInput, or the dev ForageBot) for a SimIntent and calls sim.step() once.
## Each frame it draws the sim between its last two ticks. Confirmed sim events become feedback,
## sound and signals for the UI. No gameplay rule lives here.
##
## Main instances this scene, adds it to the tree and calls setup(). The HUD, pause menu and
## notices mount under %UI (CanvasLayer 10) and read `sim` directly; see the signals below.
##
## Threats (M1 step 3): CreatureLayer draws the sim's creatures, and creature events become the
## "!" marker, the tell's strike lane, flashes, the player's hurt flinch and shelter rim, "−12" hit
## labels and "Dodged!" (FeedbackFx), attack hints, and positional cues. The HUD adds the shelter
## chip, the hurt vignette and the off-screen threat arrows from the same events and the sim. A pool
## without species has no creatures and none of this.
##
## The endless sea (S1): the sim keeps positions local to a floating origin and rebases it by whole
## chunks ("rebased"). The scene follows in the same frame with no jump: WorldSpace shifts the
## containers that hold world pieces, the camera shifts its focus (never snap_to), and what is
## placed from the sim each frame needs nothing. Every Node3D here is in one of three groups
## (world_space, world_rebuilt, camera_relative; see WorldSpace).
##
## Growth (S2): in the endless sea the sim's Growth (growth(), null in the pool, D-46) fills a meter
## the HUD shows. A press of the grow action goes into the next tick's intent, for one tick and only
## when the player swims (never a bot's); the growth trigger setting goes out with the first tick
## after the build and again whenever the player changes it (V-16). Both come from main's
## SettingsService, as does reduce camera motion (V-15).
##
## The growth beat (S2, s2-view 4): the sim grows in one tick (growth_began ... grew, routed in one
## frame). At growth_began every local position is re-expressed round the old centre by 1 / factor
## (the camera, WorldSpace's containers and leaves, the creature views) and every depth layer is
## drawn at k = 1 / factor of its depth (apply_depth_k), so frame 0 looks as the last frame did;
## GrowthBeat then times the swell, the dolly back out, the chord (growth_chord, for the HUD) and the
## relations. Leftover chunks retire (chunk_unloaded {reason: "growth"}) and sink away; the new
## ones fade in. A respawn, a teleport or a dev size change ends a running beat at once. Each tick's
## events go to the session after they are routed (GameSession.after_events), which saves a tick
## that grew at once (D-75).
##
## The ghosts (S2, s2-view 6): GhostLayer ("Ghosts", camera_relative) draws the species of the next
## sizes far below, and the giants further down, from scale_view() and the camera alone, in both
## modes. Once per lineage on this computer the giants make a first pass; giant_pass_started tells
## main, which remembers it in the player memory set here before setup().

## Every sim event, after the pool's own feedback has run (see PoolSim.drain_events for types).
signal sim_event(event: Dictionary)
## A refused meal the player should be told about now, in words (RefusalHints decides).
signal refusal_hint(text: String, reason: String)
## The pool paused itself: "key" (the pause action) or "focus" (the window lost focus).
signal pause_requested(reason: String)
signal paused_changed(paused: bool)
## The cell died; the sim keeps the world running. Resolve with GameSession.respawn_after_death().
## `reason` is the killer species' death_reason ("" for starving or a dev kill).
signal died(cause: String, reason: String)
## The cell is back at its checkpoint (the sim's "respawned" event, routed before the frame is
## drawn), sheltered for `grace_s` seconds; `teleport` when the endless world moved it there behind
## the cut (S1). Main shows the respawn message here in both modes.
signal respawned(grace_s: float, teleport: bool)
## The growth beat's chord (S2, 1.9 s in): the scene now shows `size`; the HUD shows its message,
## badge and ring for it.
signal growth_chord(size: int)
## The giants' first pass for this lineage has started (D-42): main records it in the player memory.
signal giant_pass_started
## S4.3: the cell touched its kin at a calm moment (the sim's mate event). Whoever opens the editor
## calls finish_mate() when it closes; with no one connected the mate finishes at once.
signal mate_requested
## S3 (V3-16): every scene a band-up may draw is loaded and its meshes warmed.
signal preload_finished
## The cell-to-creature link (ShoreLink): the shore rose while this pool was up (not one already in the save).
signal shore_risen
## The cell swam into the shore's reach: whoever offers the crossing calls decline_shore() on "Stay in the water".
signal shore_reached

const KIN_VIEW_SCENE := "res://game/scenes/pool/player_cell_view.tscn"
const KIN_PULSE := 0.05      ## the kin's swell while the cell could mate with it
## The shore's arrow (the cell-to-creature link): pale sunlight, apart from the food arrow's amber, and its own words.
const SHORE_ARROW_COLOR := Color(1.0, 0.97, 0.82)
const SHORE_ARROW_LABEL := "Shore %d m"
const KIN_PULSE_HZ := 0.8
const STEP_COST_WINDOW := 120   ## ticks averaged for step_cost_usec()
## The idea hints' "near a smaller body": a surface gap of at most this (tm, s2-view 7.5).
const NEAR_SMALLER_TM := 2.0
const FADE_IN_S := 0.3
## The shader warm-up under the fade draws on the camera's view axis this deep (m): in the frustum
## at every zoom and inside the far plane, so it is really drawn, yet hidden behind the fluid's
## opaque Backdrop (y −40). Occlusion culling is off; turning it on would cull the hidden draw,
## nothing would compile, and this point must move.
const WARM_UP_Y := -45.0
const STARVE_PULSE_S := 1.0
## The cell's Stretch pulse while it is about to grow ("Growing…", s2-view 4.3).
const GROWING_PULSE_HZ := 1.2
## Art's decor plug-in (micro-world plan section 7): mounted as the pool's single child "Ambience"
## when the scene exists. It reads get_parent().camera and get_parent().cell_view and writes
## nothing back; tests/test_ambience_contract.gd holds it to the rest of the contract.
const AMBIENCE_SCENE := "res://game/scenes/pool/ambience/ambience.tscn"
## S3: the cradle's ring and the home beacon (D-95, D-112), preloaded with the kit (V3-16).
const CRADLE_RING_PATH := "res://assets/export/cradle_ring.glb"
const HOME_BEACON_PATH := "res://assets/export/home_beacon.glb"

## Pause when the window loses focus (Bible 19). Off for tools that render without focus.
@export var pause_on_focus_loss := true

var session: GameSession
var sim: PoolSim
## Anything with next_intent(sim: PoolSim) -> SimIntent.
var intent_provider: Object
var paused := false
var hints := RefusalHints.new()

var _built := false
## Chunk keys drawn now (endless): chunk_loaded is idempotent per key, as the create-time events
## and the first build both bring the view set (docs/s1/s1-build-plan.md B-23).
var _loaded := {}
var _step_costs := PackedInt64Array()
var _step_cost_next := 0
var _starve_pulse_t := 0.0
## Growth (S2): a grow press waiting for the next tick, the trigger setting waiting to go out with
## it, and the settings service listened to.
var _grow_pressed := false
var _trigger_pending := ""
var _settings: SettingsService
## What the last tick's intent carried for growth: the press and the trigger ("" for none). The
## dev panel and the tests read them.
var sent_grow := false
var sent_trigger := ""
## Reduce camera motion (settings): the growth beat dissolves instead of moving the camera (V-17).
var reduce_motion := false
## Times the growth beat on screen (S2); idle outside a growth.
var growth_beat: GrowthBeat
## The ghosts of the sizes to come and the giants (S2).
var ghosts: GhostLayer
## The Lurkers' silt ribbons and lair mouths (S2, in WorldSpace).
var silt_trail: SiltTrail
var older_haze: OlderHaze
## The old band below (S3, s3-view 5): band - 1's landmarks and rare pieces sunk under the plane.
var old_band: OldBandLayer
## S3G28's test switch: false builds no old band (never in a save).
var old_band_enabled := true
## The cradle round home from band 1 and the home beacon (S3, s3-view 6); endless mode only, else null.
var cradle: CradleView
var beacon: HomeBeacon
## The shore and the arrow to it (ShoreLink), endless mode only, else null. The shore is placed from the save every
## frame, hidden until it rises and once the lineage is ashore.
var shore: ShoreView
var shore_arrow: StarvingArrow
var _shore_seen := false        ## a shore was in the save (at setup, or since it rose)
var _shore_offered := false     ## shore_reached was sent and not answered yet
var _shore_declined := false    ## "Stay in the water": no offer until the cell has swum out of reach
## S3's preload (V3-16): the paths still loading on worker threads, the scenes in, whether every one
## is in and warmed, and every mesh the warm-ups drew (the start fade's and the late one's).
var _preload_pending := PackedStringArray()
var _preloaded := {}
var _preload_done := false
var _warmed: Array[Mesh] = []
## What this computer remembers about its player (main's), read for the giants' first pass; none
## outside main, and then every lineage gets its pass.
var player_memory: UserSettings
## The depth factor drawn now (apply_depth_k), and the base depths it scales: the Backdrop's height
## and scale, and the fog of the environment they were read from (re-read if it is replaced).
var _depth_k := 1.0
var _backdrop_y := -40.0
var _backdrop_scale := Vector3.ONE
var _fog_env: Environment
var _fog_base := {}
## Sim time of this session's last growth (-INF before one): the idea hints' beat_t.
var _grew_at := -INF
## The sea tile the idea hints last asked about, at which size, and its region.
var _region_tile := Vector2i(2147483647, 2147483647)
var _region_size := 0
var _region_name := ""

## The world's edge: the dish wall the collision stops the cell at, with its lip and shelf.
@onready var rim_node: Node3D = %Rim
## The sunlit patches: soft light under each plankton zone (in the sea, of sunlit and home tiles).
@onready var zone_lights: ZoneLights = %ZoneLights
## The rocks, and in the sea every shell: one MultiMesh per piece.
@onready var rocks: RockField = %Rocks
## The sea's landmarks and rare set pieces.
@onready var landmarks: LandmarkLayer = %Landmarks
## The endless sea's column at the generation start and arrow home (world_rebuilt: placed every frame).
@onready var markers: WorldMarkers = %Markers
@onready var plankton_view: FoodView = %Plankton
@onready var carrion_view: FoodView = %Carrion
@onready var cell_view: PlayerCellView = %PlayerCell
## S4.3: the kin's view while a kin is in the sea (_show_kin), else null.
var kin_view: PlayerCellView = null
@onready var creature_layer: CreatureLayer = %Creatures
@onready var feedback: FeedbackFx = %Feedback
@onready var camera: PoolCamera = %Camera
@onready var swim_input: SwimInput = %SwimInput
@onready var audio: CellAudio = %Audio
@onready var ui: CanvasLayer = %UI
@onready var target_ring: TargetRing = %TargetRing
@onready var starving_arrow: StarvingArrow = %StarvingArrow
@onready var _fade: ColorRect = %Fade
@onready var _sun: DirectionalLight3D = $Sun
@onready var _depth_glow: DirectionalLight3D = %DepthGlow
## The fluid's far plane under the view; it follows the camera's focus (camera_relative).
@onready var backdrop: MeshInstance3D = %Backdrop
## Shifts the world's containers across a rebase.
@onready var world_space: WorldSpace = %WorldSpace
## The eat burst and the meal ghosts, in the world's frame so they ride a rebase.
@onready var world_fx: Node3D = %WorldFx
@onready var _world_env: WorldEnvironment = $WorldEnvironment


## Starts drawing the session's running sim. `provider` defaults to the player's SwimInput.
## Call it before or after the pool enters the tree.
func setup(p_session: GameSession, provider: Object = null) -> void:
	session = p_session
	sim = session.sim
	intent_provider = provider
	_built = false
	if is_node_ready():
		_build()


func _ready() -> void:
	# One set of values for both renderers today; pool_look.gd keeps a per-renderer escape hatch.
	PoolLook.apply(PoolLook.profile_for(RenderingServer.get_current_rendering_method()), _sun, _world_env)
	# The growth beat scales the fog (apply_depth_k): the pool lights its own copy, never the .tres.
	if _world_env.environment != null and not _world_env.environment.resource_path.is_empty():
		_world_env.environment = _world_env.environment.duplicate()
	_backdrop_y = backdrop.position.y
	_backdrop_scale = backdrop.scale
	swim_input.camera = camera
	if growth_beat == null:
		growth_beat = GrowthBeat.new()
		growth_beat.name = "GrowthBeat"
		add_child(growth_beat)
	if ghosts == null:
		ghosts = GhostLayer.new()
		ghosts.name = "Ghosts"
		ghosts.add_to_group(&"camera_relative")   # placed from the camera every frame (V-12)
		add_child(ghosts)
		ghosts.first_pass_started.connect(giant_pass_started.emit)
	ghosts.camera = camera
	if silt_trail == null:
		silt_trail = SiltTrail.new()
		silt_trail.name = "SiltTrail"
		add_child(silt_trail)
	if older_haze == null:
		older_haze = OlderHaze.new()
		add_child(older_haze)
	if old_band == null:
		old_band = OldBandLayer.new()
		add_child(old_band)
	_mount_ambience()
	if session != null and not _built:
		_build()


## Mounts art's ambience scene, when there is one, as the single child "Ambience". The pool calls it
## once the camera and cell view exist, so the plug-in can read them in its own _ready. Its layers
## are in view from the first frame, so their shaders compile under the start fade.
func _mount_ambience() -> void:
	if has_node("Ambience") or not ResourceLoader.exists(AMBIENCE_SCENE):
		return
	var ambience := (load(AMBIENCE_SCENE) as PackedScene).instantiate()
	ambience.name = "Ambience"
	ambience.add_to_group(&"camera_relative")   # it follows the camera itself (ambience contract)
	add_child(ambience)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	release_input()
	cell_view.set_process(not paused)
	creature_layer.set_paused(paused)
	paused_changed.emit(paused)


## Pauses and tells the UI why, so it can open the pause menu.
func request_pause(reason: String) -> void:
	if paused or sim == null:
		return
	set_paused(true)
	pause_requested.emit(reason)


## Clears every held input (pause, dialogs, focus loss, death).
func release_input() -> void:
	swim_input.release_all()
	target_ring.visible = false


## Average and largest cost of one step (intent plus sim.step) over the last STEP_COST_WINDOW
## ticks, in microseconds: {"avg", "max"}.
func step_cost_usec() -> Dictionary:
	if _step_costs.is_empty():
		return {"avg": 0.0, "max": 0}
	var total := 0
	var top := 0
	for c in _step_costs:
		total += c
		top = maxi(top, c)
	return {"avg": float(total) / _step_costs.size(), "max": top}


func _build() -> void:
	_built = true
	if intent_provider == null:
		intent_provider = swim_input
	hints.reset()
	cell_view.attach_fx(world_fx)
	for node: Node3D in [rim_node, zone_lights, rocks, landmarks, feedback, world_fx, silt_trail, older_haze, old_band]:
		world_space.register(node)
	for player in audio.get_children():
		if player is AudioStreamPlayer3D:
			world_space.register(player)
	_loaded.clear()
	growth_beat.setup(self)
	apply_depth_k(1.0)
	if is_endless():
		# The sea's ground comes from chunk events; the chunks already loaded are drawn now from
		# the stream itself, and their queued create-time events change nothing (idempotent).
		rim_node.visible = false   # the dish wall is the pool's edge; the sea has none
		rocks.clear()
		RockField.load_pieces(session.world.kit)   # S2G26: no GLB loads in a growth's frame
		SiltTrail.load_mouth()
		landmarks.setup(session.world.kit)
		silt_trail.setup(sim.species, sim_size())
		var ladder: Dictionary = GhostLayer.shipped()
		older_haze.setup(ladder.data if ladder.problems.is_empty() else {}, session.world.config.ladder.get("food_looks", []), sim.world.world_seed)
		older_haze.set_size(sim_size())
		zone_lights.build([])
		feedback.setup([], camera)
		for key in sim.world.loaded_keys():
			apply_world_event(WorldSpace.chunk_loaded_event(sim.world, sim.world.chunk(key)))
		older_haze.refresh(sim.world, sim.motion.position)
		_start_preload(s3_preload_paths())   # V3-16
		if old_band_enabled:
			old_band.setup(session.world, sim.species, sim.world.world_seed, session.world.kit)
			old_band.attach(sim.world)
			old_band.focus_am = sim.world.abs_of_local(sim.motion.position)
			old_band.set_band(WorldConfig.band_of(sim_size()), sim_size())
		_build_cradle()
		_build_shore()
	else:
		rim_node.visible = true
		rocks.build_pool(session.layout)
		landmarks.clear()
		silt_trail.setup(sim.species, sim_size())
		older_haze.setup({}, [], 0)
		old_band.set_band(0, 1)
		zone_lights.build(session.layout.zones)
		feedback.setup(session.layout.zones, camera)
	_hide_kin()
	cell_view.build(sim.save.genome, sim.phenotype)
	cell_view.place(sim.motion)
	cell_view.set_dead(sim.dead)
	creature_layer.attach(sim, world_space)
	apply_food_looks(sim_size())
	_configure_ghosts()
	markers.setup(sim, session.world.kit if is_endless() else null)
	_update_markers()
	if sim.species != null:
		audio.configure_tells(tell_lengths(sim.species))
	camera.configure(session.layout.camera)
	camera.snap_to(cell_view.position)
	_follow_camera()
	_draw_food(1.0)
	_listen_to_settings()
	_fade_in()


## The ghosts on the shipped ladder at the sim's size, hashed from the lineage (none when the ladder
## has problems); the glitter takes its haze sprites from the same ladder. A lineage this computer
## has not seen pass gets the giants' first pass 30 to 60 s into the session (D-42, V-14).
func _configure_ghosts() -> void:
	var ladder: Dictionary = GhostLayer.shipped()
	var data: Dictionary = ladder.data if ladder.problems.is_empty() else {}
	var lineage: String = sim.save.lineage_id if sim.save != null else ""
	ghosts.configure(data, sim_size(), hash(lineage))
	growth_beat.haze = GrowthBeat.FOOD_HAZE.merged(GrowthBeat.SPECIES_HAZE).merged(GhostLayer.haze_paths(data), true)
	if data.is_empty() or (player_memory != null and player_memory.giant_pass_lineages.has(lineage)):
		return
	var start: Array = data.far.first_pass.start_s
	var u := float(hash(lineage) & 0xFFFF) / 65536.0
	ghosts.schedule_first_pass(sim.now() + lerpf(float(start[0]), float(start[1]), u))


## What the idea hints read (S2, s2-view 7.5; the HUD asks every IDEA_CONTEXT_S): the size, whether
## the cell has a jaw or eats only meat, starves, how full its ring is, whether it is in the home
## tile (the sea only) and how long it has lived; whether a rimmed body is in view, whether a smaller
## creature or remnant lies within NEAR_SMALLER_TM of its surface, and the sim time since this
## session's last growth began (-1 before one); whether a veil whose threads can sting is in view (S3).
func hint_context() -> Dictionary:
	var p := sim.phenotype
	var n := sim_size()
	return {"size": n, "has_jaw": p.can_eat("meat"), "meat_only": p.diets == PackedStringArray(["meat"]),
		"starving": sim.state.is_starving(), "meter_share": GrowthHud.share_of(growth(), n),
		"in_home_tile": is_endless() and _tile_region() == "home", "alive_s": sim.alive_s,
		"rimmed_in_view": camera != null and not creature_layer.rimmed_in_view(camera, view_size(), 1).is_empty(),
		"near_smaller": _near_smaller(), "beat_t": sim.now() - _grew_at if _grew_at > -INF else -1.0,
		"veil_in_view": camera != null and creature_layer.inked_veils_in_view(camera, view_size()) > 0}


## What the idea hints need to know about a sim event: {smaller, rimmed} for the body a "hit" struck
## or the morsel an "ate" took (q under 1 or a remnant, and rimmed), both false otherwise.
func hint_facts(event: Dictionary) -> Dictionary:
	var view: CreatureView = null
	match str(event.get("type", "")):
		"hit":
			var id := str(event.get("target", ""))
			view = creature_layer.view_of(id)
			if view == null:
				view = creature_layer.remnant_view(id)
		"ate":
			view = creature_layer.morsel_view(str(event.get("food_id", "")))
	if view == null:
		return {"smaller": false, "rimmed": false}
	return {"smaller": view.remnant or view.morsel_id != "" or view.view_q < 1.0, "rimmed": view.rimmed()}


## A creature or remnant smaller than the cell (q under 1) within NEAR_SMALLER_TM of its surface.
func _near_smaller() -> bool:
	if camera == null:
		return false
	var cell := sim.motion.position
	var r := sim.phenotype.radius
	for view in creature_layer.views_in_view(camera, view_size()):
		if view.morsel_id != "" or not (view.remnant or view.view_q < 1.0):
			continue
		if PlaneSpace.to_plane(view.position).distance_to(cell) - r - view.radius <= NEAR_SMALLER_TM:
			return true
	return false


## The region of the sea tile the cell is in (WorldGen.tile_info), read again only when the tile
## changes.
func _tile_region() -> String:
	var w := sim.world
	var t := w.tile_of_local(sim.motion.position)
	if t != _region_tile or w.size != _region_size:
		_region_tile = t
		_region_size = w.size
		_region_name = str(w.gen.tile_info(WorldConfig.band_of(w.size), t.x, t.y).get("region", ""))
	return _region_name


## True in the endless sea (the sim streams a world), false in the M1 pool.
func is_endless() -> bool:
	return sim != null and sim.world != null


## The sim's Growth (S2), or null: always null in the M1 pool (D-46). Only read here.
func growth() -> Object:
	return sim.growth if sim != null else null


## The cell's size in the sim: the world's in the sea, 1 in the pool.
func sim_size() -> int:
	return sim.world.size if is_endless() else 1


## The size the scene shows now (the HUD, the markers): the old size through a growth beat until
## its chord (V-7), else the sim's.
func shown_size() -> int:
	return growth_beat.shown_size() if growth_beat != null and growth_beat.running() else sim_size()


## The cradle and the home beacon (S3, s3-view 6.1 and 6.5): made once, in WorldSpace, laid out for
## the size now. The beacon's GLB loads here, under the start fade.
func _build_cradle() -> void:
	cradle = CradleView.new()
	add_child(cradle)
	var old_pool: Array[Dictionary] = []
	if sim.world.gen != null:
		old_pool = sim.world.gen.old_pool_pieces()
	cradle.setup(session.world.cradle_of(1), old_pool, CradleView.RING_RECORD_RADIUS_BU)
	cradle.attach(sim.world)
	world_space.register(cradle)
	cradle.set_size(sim_size())
	beacon = HomeBeacon.new()
	add_child(beacon)
	world_space.register(beacon)
	beacon.place(sim.world, sim_size())


## The shore and its arrow (the cell-to-creature link): made once, hidden until the shore is in the save.
func _build_shore() -> void:
	if shore == null:
		shore = ShoreView.new()
		shore.add_to_group(&"world_rebuilt")   # placed from the save every frame: a rebase needs nothing
		add_child(shore)
	if shore_arrow == null:
		shore_arrow = StarvingArrow.new()
		shore_arrow.name = "ShoreArrow"
		shore_arrow.color = SHORE_ARROW_COLOR
		shore_arrow.label_format = SHORE_ARROW_LABEL
		shore_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.add_child(shore_arrow)
		ui.move_child(shore_arrow, starving_arrow.get_index())
	_shore_seen = not ShoreLink.point_am(sim.save).is_empty()
	_shore_offered = false
	# A run that starts in the reach (Back to the water, or a save made there) waits for the cell to swim out and
	# back, as after "Stay in the water", so the offer never greets a player who has just come back.
	_shore_declined = _shore_seen and ShoreLink.in_reach(
			ShoreLink.distance_am(sim.save, sim.absolute_position_am()), sim_size())


## Places the shore from the save, points its arrow and sends shore_risen and shore_reached (see there). The offer
## waits while paused, dead or in a growth beat, and opens again after a decline only once the cell has swum out.
func _update_shore(delta: float) -> void:
	if shore == null:
		return
	var p := ShoreLink.point_am(sim.save)
	if p.is_empty() or not ShoreLink.in_water(sim.save):
		shore.visible = false
		shore_arrow.visible = false
		return
	if not _shore_seen:
		_shore_seen = true
		shore_risen.emit()
	var local := sim.world.local_of_abs(p[0], p[1])
	shore.place(local)
	shore.pulse(0.0 if paused else delta)
	var n := sim_size()
	var d := ShoreLink.distance_am(sim.save, sim.absolute_position_am())
	var reach := ShoreLink.in_reach(d, n)
	_point_shore_arrow(local, reach)
	if paused or sim.dead or sim.respawn_pending or growth_beat.running():
		return
	if _shore_declined and ShoreLink.out_of_reach(d, n):
		_shore_declined = false
	if reach and not _shore_declined and not _shore_offered:
		_shore_offered = true
		shore_reached.emit()


## The answer to shore_reached was "Stay in the water".
func decline_shore() -> void:
	_shore_offered = false
	_shore_declined = true


func _point_shore_arrow(local: Vector2, reach: bool) -> void:
	if reach or paused:
		shore_arrow.visible = false
		return
	var cell_at := cell_view.position
	var shore_at := PlaneSpace.to_world(local, 0.0)
	var cell_px := camera.unproject_position(cell_at)
	var cell_radius_px := camera.unproject_position(cell_at + Vector3.RIGHT * sim.phenotype.radius).distance_to(cell_px)
	var toward := cell_at + (shore_at - cell_at).normalized()
	var shore_px := Vector2.INF
	if not camera.is_position_behind(shore_at):
		var q := camera.unproject_position(shore_at)
		if shore_arrow.get_rect().has_point(q):
			shore_px = q
	shore_arrow.point(cell_px, camera.unproject_position(toward) - cell_px, shore_px, cell_at.distance_to(shore_at),
			cell_radius_px)


## The containers that follow the growth beat's contract (apply_growth, retire_chunk, settle_growth,
## beat_frame, end_growth).
func growth_containers() -> Array:
	var out: Array = [rocks, landmarks, zone_lights, feedback, silt_trail, older_haze, old_band]
	if cradle != null:
		out.append(cradle)
	return out


## Every depth layer at k of its depth (the growth beat; 1 otherwise), s2-view 4.2: the Backdrop's
## height and size, the fog (heights times k, densities over k, so the attenuation over a path
## that is k times as long in tm stays), the zone patches' and lair mouths' depth, the zone labels
## and the markers.
## At k = 1 / factor, the first frame after a growth draws every layer where the last one did.
func apply_depth_k(k: float) -> void:
	# Exactly: the last step of the dolly is within is_equal_approx of 1, and must still land on 1.
	if k == _depth_k and _fog_env == _world_env.environment:
		return
	_depth_k = k
	backdrop.position.y = _backdrop_y * k
	backdrop.scale = _backdrop_scale * k
	var env := _world_env.environment
	if env != null:
		if env != _fog_env:
			_fog_env = env
			_fog_base = {"fog_height": env.fog_height, "fog_height_density": env.fog_height_density,
				"fog_density": env.fog_density}
		env.fog_height = _fog_base.fog_height * k
		env.fog_height_density = _fog_base.fog_height_density / k
		env.fog_density = _fog_base.fog_density / k
	zone_lights.set_depth_k(k)
	feedback.set_depth_k(k)
	silt_trail.set_depth_k(k)
	markers.set_size_k(k)
	plankton_view.depth_k = k
	carrion_view.depth_k = k


## The depth factor drawn now (1 outside a growth beat).
func depth_k() -> float:
	return _depth_k


## What the scale-aware layers draw from (s2-view 4.2): {size, band, region, tile, depth_k, size_k,
## focus_am, tm_to_am, time_s}. Art's ambience gets it each frame (apply_scale_view, when it has one).
func scale_view() -> Dictionary:
	var focus := Vector2(camera.focus.x, camera.focus.z)
	var endless := is_endless()
	return {"size": sim_size(), "band": 0, "region": sim.region if sim != null else "",
		"tile": sim.world.tile_of_local(focus) if endless else Vector2i.ZERO,
		"depth_k": _depth_k, "size_k": _depth_k,
		"focus_am": sim.world.abs_of_local(focus) if endless else PackedFloat64Array([focus.x, focus.y]),
		"tm_to_am": WorldConfig.tm_to_am(sim_size()) if endless else 1.0,
		"time_s": _draw_time(1.0 if paused else Engine.get_physics_interpolation_fraction()) if sim != null else 0.0}


## The fade over the whole view (the start fade; the growth beat's headless reduce-motion dip).
func fade_rect() -> ColorRect:
	return _fade


## The growth beat's chord: the HUD switches to `size`, and the soundtrack follows.
func on_growth_chord(size: int) -> void:
	if audio.has_method(&"set_size"):
		audio.call(&"set_size", size)
	growth_chord.emit(size)


## The growth beat's relations moment (RELATIONS_S): ink, rims and remnants turn for `size` over
## `fade_s` (0 when a beat is cut short); a full beat also puts "Now food" over the nearest rimmed
## views in sight, with its cue.
func on_growth_relations(size: int, fade_s: float) -> void:
	creature_layer.apply_relations(size, fade_s)
	if fade_s <= 0.0:
		return
	var now_food := creature_layer.rimmed_in_view(camera, view_size(), GrowthBeat.NOW_FOOD_MAX)
	for view in now_food:
		view.show_now_food(GrowthBeat.NOW_FOOD_S)
	if not now_food.is_empty():
		audio.play("now_food")


## The size of the view drawn (the project's window size outside the tree).
func view_size() -> Vector2:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


## The largest size this build reaches (world_cell.json sizes.max_in_build; 1 in the pool).
func max_size() -> int:
	return session.world.config.max_size_in_build if is_endless() else 1


## Queues the growth trigger ("auto" or "press") into the next tick's intent. Nothing goes out
## without a Growth.
func send_trigger(trigger: String) -> void:
	_trigger_pending = trigger if growth() != null else ""


func set_reduce_motion(on: bool) -> void:
	reduce_motion = on


## Reads the growth trigger and reduce camera motion from the shared settings now, and again on
## every change (V-15, V-16): the trigger then goes out with the next tick.
func _listen_to_settings() -> void:
	var settings := SettingsService.shared()
	if _settings != settings:
		if _settings != null and _settings.changed.is_connected(_on_setting_changed):
			_settings.changed.disconnect(_on_setting_changed)
		_settings = settings
		_settings.changed.connect(_on_setting_changed)
	_grow_pressed = false
	send_trigger(settings.growth_trigger())
	set_reduce_motion(settings.reduce_camera_motion())


func _on_setting_changed(id: String) -> void:
	if id == "gameplay/growth_trigger":
		send_trigger(_settings.growth_trigger())
	elif id == "accessibility/reduce_camera_motion":
		set_reduce_motion(_settings.reduce_camera_motion())


## The chunk keys drawn now, sorted (endless; empty in the pool).
func loaded_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in _loaded:
		out.append(key)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## A scene event of the endless world (spine 3.12), routed from the sim or, in tests, built by hand.
##   chunk_loaded: the chunk's shells (kind "shell"), landmarks and rare places, its zones' labels,
##     and patches under the zones of sunlit and home tiles; nothing when the key is drawn already.
##   chunk_unloaded: all of that goes; an unknown key changes nothing. At a growth (reason "growth",
##     while the beat runs) it retires instead: drawn by id until the beat sinks it away, unless the
##     same id comes back in the new chunks (adopted).
##   rebased {offset_tm}: every local position dropped by the offset, so the camera's focus and
##     every WorldSpace container drop with it in this frame, far containers renormalise, and the
##     camera-relative nodes follow the shifted focus. Never snap_to: the follow lag carries on (G10).
##   tile_entered: nothing here; the HUD names the region.
func apply_world_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"chunk_loaded":
			var key: Vector2i = e.key
			if _loaded.has(key):
				return
			var shells: Array = e.get("shells", [])
			rocks.add_chunk(key, shells.filter(func(s: Dictionary) -> bool: return s.kind == "shell"))
			landmarks.add_chunk(key, shells.filter(func(s: Dictionary) -> bool: return s.kind == "landmark"),
				e.get("anchors", []), e.get("places", []))
			var zones: Array = e.get("zones", [])
			zone_lights.add_chunk(key, zones)   # ZoneLights picks the patches and blooms (V3-10)
			feedback.add_zone_labels(key, zones)
			silt_trail.add_chunk(key, e.get("sites", []))
			_loaded[key] = true
		"chunk_unloaded":
			var key: Vector2i = e.key
			if not _loaded.has(key):
				return
			if str(e.get("reason", "")) == "growth" and growth_beat != null and growth_beat.running():
				for c in growth_containers():
					c.retire_chunk(key)
			else:
				rocks.remove_chunk(key)
				landmarks.remove_chunk(key)
				zone_lights.remove_chunk(key)
				feedback.remove_zone_labels(key)
				silt_trail.remove_chunk(key)
			_loaded.erase(key)
		"rebased":
			var o: Vector2 = e.offset_tm
			camera.shift_focus(-Vector3(o.x, 0.0, o.y))
			world_space.apply_rebase(o)
			world_space.renormalize_far()
			_renormalize_fx()
			_shift_ambience(o)
			_follow_camera()
			_update_markers()


## WorldFx renormalises as the other containers do (WorldSpace.renormalize_far), but only while no
## meal ghost is in flight: a ghost tweens its position in WorldFx's frame and would jump. The eat
## burst's particles are local to it, so moving it with its container moves nothing on screen.
func _renormalize_fx() -> void:
	if Vector2(world_fx.position.x, world_fx.position.z).length() <= WorldSpace.RENORMALIZE_TM:
		return
	_bake_fx()


## Moves WorldFx's own transform into its children's positions and WorldFx back to the identity,
## when no meal ghost is in flight (false otherwise). A growth leaves WorldFx re-expressed as a leaf
## (V-5); its scale is then dropped rather than baked into the children, since the eat burst is sized
## for the cell, which a growth leaves the same size in tm.
func _bake_fx() -> bool:
	if world_fx.transform == Transform3D.IDENTITY:
		return true
	if world_fx.get_children().any(func(c: Node) -> bool: return c is MeshInstance3D):
		return false
	for child in world_fx.get_children():
		var n := child as Node3D
		if n != null:
			n.position = world_fx.transform * n.position
	world_fx.transform = Transform3D.IDENTITY
	return true


## Art's ambience wraps world-placed specks and backdrops round the camera's focus, so it follows
## the camera by itself; across a rebase its layers move with the world, so the wrap sees nothing
## change and no speck jumps. A layer whose shader wraps it in a box (its "box" uniform, x and z)
## draws the same moved by whole boxes, so it is kept within half a box of the origin, where its
## culling box stays round the view. Particles under it must use local coordinates (ambience
## contract).
func _shift_ambience(offset: Vector2) -> void:
	var ambience := get_node_or_null("Ambience")
	if ambience == null:
		return
	for child in ambience.get_children():
		var node := child as Node3D
		if node == null:
			continue
		node.position -= Vector3(offset.x, 0.0, offset.y)
		var box := wrap_box(node)
		if box != Vector2.ZERO:
			node.position.x = fposmod(node.position.x + box.x * 0.5, box.x) - box.x * 0.5
			node.position.z = fposmod(node.position.z + box.y * 0.5, box.y) - box.y * 0.5


## The box an ambience layer's shader wraps it in round the focus (its "box" uniform), or ZERO.
static func wrap_box(node: Node3D) -> Vector2:
	var material := (node as GeometryInstance3D).material_override as ShaderMaterial if node is GeometryInstance3D else null
	var box: Variant = material.get_shader_parameter("box") if material != null else null
	return box if box is Vector2 and box.x > 0.0 and box.y > 0.0 else Vector2.ZERO


## The Backdrop and the lights stay under the camera's focus in x and z, each keeping its height and
## turn, so the fluid's far plane covers the view wherever the cell swims.
func _follow_camera() -> void:
	for node: Node3D in [backdrop, _sun, _depth_glow]:
		node.position.x = camera.focus.x
		node.position.z = camera.focus.z


## The column and the arrow home stand where the sim says, beside the cell as it is drawn now, at
## the size shown.
func _update_markers() -> void:
	markers.update(sim, PlaneSpace.to_plane(cell_view.position), shown_size())


## growth_began (s2-view 4.1): the beat starts (under reduce motion it keeps the last frame first),
## then every local position is re-expressed round the old centre by 1 / factor at once, with the
## depth layers at k = 1 / factor, so nothing moves on screen.
func _begin_growth(e: Dictionary) -> void:
	growth_beat.begin(e, reduce_motion)
	var center: Vector2 = e.get("center_old", Vector2.ZERO)
	var factor := float(e.get("factor", 1.0 / GrowthBeat.K_FROM))
	camera.reexpress(center, factor)
	if growth_beat.reduced():
		camera.end_dolly()
	older_haze.begin_growth(int(e.get("to", 2)))
	world_space.apply_growth(center, factor)
	if is_endless():
		# S3 (s3-view 4.1): the old band's new targets, eased to over the beat (V3-7); at a band-up its
		# instances start hidden and the landmarks of the band left behind are handed to it (V3-2).
		var from := int(e.get("from", 1))
		var to := int(e.get("to", sim_size()))
		old_band.focus_am = _focus_am()
		old_band.set_band(WorldConfig.band_of(to), to)
		if GrowthBeat.is_band_up(from, to):
			old_band.begin_band_up(WorldConfig.band_of(from), GrowthBeat.BEAT_S)
			old_band.adopt(landmarks.release_band(WorldConfig.band_of(from)))
		if cradle != null:
			cradle.set_size(to)   # eased to over the beat, or faded in at a band-up (s3-view 4.2)
	_bake_fx()
	creature_layer.apply_growth(center, factor)
	ghosts.begin_growth(int(e.get("from", 1)), int(e.get("to", 2)))
	silt_trail.size = int(e.get("to", sim_size()))   # before the tick's chunks come
	_grew_at = sim.now()
	markers.hold_column_until(GrowthBeat.RELATIONS_S)
	apply_depth_k(growth_beat.k())
	_follow_camera()


## The older sizes' haze round the cell (S3, V3-14): it rebuilds only when the cell's chunk changes.
func _refresh_older_haze() -> void:
	if is_endless():
		older_haze.refresh(sim.world, sim.motion.position)


## The camera's focus in absolute am (the scale view's focus_am).
func _focus_am() -> PackedFloat64Array:
	return sim.world.abs_of_local(Vector2(camera.focus.x, camera.focus.z))


## The old band round the camera's focus now (a respawn, a teleport; s3-view 5).
func _refresh_old_band() -> void:
	if is_endless():
		old_band.focus_am = _focus_am()
		old_band.refresh(OldBandLayer.view_rect(old_band.focus_am, old_band.size))


## Ends a running growth beat at once, before the camera snaps (a respawn, a teleport, a dev size).
func _cancel_growth() -> void:
	growth_beat.cancel()
	apply_depth_k(1.0)


## The Stretch shape's weight now: the beat's, or while the ring waits to grow ("Growing…") a slow
## pulse (none under reduce flashing).
func _stretch_now(time_s: float) -> float:
	if growth_beat.running():
		return growth_beat.stretch()
	var growth := growth()
	if growth == null or GrowthHud.state_of(growth, sim_size(), max_size()) != "growing":
		return 0.0
	if _settings != null and _settings.reduce_flashing():
		return 0.0
	return 0.5 + 0.5 * sin(TAU * GROWING_PULSE_HZ * time_s)


## A short fade from the fluid's mid-tone hides the first frames, while the eat burst and the
## warm-up meshes draw once out of sight (warm_up_point), so their shaders are ready before play.
func _fade_in() -> void:
	_fade.visible = true
	_fade.modulate.a = 1.0
	# A pool built outside the tree (the scene tests) sits at the origin: the camera's own transform.
	var hidden := warm_up_point(camera.global_transform if camera.is_inside_tree() else camera.transform)
	var meshes := warm_up_meshes()
	_warmed.append_array(meshes)
	cell_view.warm_up(meshes, hidden)
	var tween := _fade.create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_IN_S)
	tween.tween_callback(_fade.hide)


## What the start fade draws out of sight besides the eat burst: both food meshes, which first show
## at a meal, the zone light, whose patches may first come into view later, and a strike lane, which
## first shows at a tell. S2 (V-20): every food look (the algae ball first shows at size 2), the new
## bodies, M_Morsel, M_RemnantLimp and the rim hull, the beat's pre-blur veil and glitter, and a ghost.
func warm_up_meshes() -> Array[Mesh]:
	var out := [plankton_view.food_mesh(), carrion_view.food_mesh(), zone_lights.mesh, zone_lights.bloom_mesh, CreatureView.warm_up_lane_mesh()] as Array[Mesh]
	for look in FoodView.LOOKS:
		var mesh := FoodView.look_mesh(look)
		if not out.has(mesh):
			out.append(mesh)
	out.append_array(CreatureView.warm_up_growth_meshes())
	out.append_array(GrowthBeat.warm_up_meshes())
	out.append(GhostLayer.warm_up_mesh())
	# S3 (T4.6, s3-view 13): the band-1 foods, the new bodies, threads and morsels, the older haze.
	for mesh in FoodView.warm_up_meshes():
		if not out.has(mesh):
			out.append(mesh)
	out.append_array(CreatureLayer.warm_up_meshes())
	out.append_array(OlderHaze.warm_up_meshes())
	out.append_array(OldBandLayer.warm_up_meshes())
	out.append_array(CradleView.warm_up_meshes())
	if is_endless():
		out.append_array(ShoreView.warm_up_meshes())
	return out


## The food views wear the looks of `size` (world_cell.json ladder.food_looks: the algae ball at size
## 2); the pool's are the plankton and carrion.
func apply_food_looks(size: int) -> void:
	var looks: Array = session.world.config.ladder.get("food_looks", []) if is_endless() else []
	var at: Dictionary = looks[size - 1] if size >= 1 and size <= looks.size() else {}
	plankton_view.set_look(str(at.get("plant", FoodView.KIND_LOOKS.plant)))
	carrion_view.set_look(str(at.get("meat", FoodView.KIND_LOOKS.meat)))


## Where the shader warm-up draws for a camera at `view` (its global transform): its view axis at
## WARM_UP_Y. It does not rely on anything lying under the cell, only on the opaque Backdrop lying
## between the point and the camera.
static func warm_up_point(view: Transform3D) -> Vector3:
	var forward := -view.basis.z
	return view.origin + forward * ((view.origin.y - WARM_UP_Y) / -forward.y)


func _physics_process(_delta: float) -> void:
	if paused or sim == null or not _built:
		return
	var t0 := Time.get_ticks_usec()
	var intent: SimIntent = intent_provider.next_intent(sim)
	_add_growth_intent(intent)
	sim.step(intent)
	_record_cost(Time.get_ticks_usec() - t0)
	_route_events()


func _process(delta: float) -> void:
	if sim == null or not _built:
		return
	# Events from between ticks (a respawn, a dev teleport) are routed before this frame is drawn,
	# so the camera never shows one frame at the old place when no tick runs this frame.
	_route_events()
	# While paused the sim is still, so draw its current tick instead of a moving fraction.
	var fraction := 1.0 if paused else Engine.get_physics_interpolation_fraction()
	# The growth beat's clock is the drawn moment's sim time (V-1): it stops while paused.
	var draw_t := _draw_time(fraction)
	_poll_preload()
	growth_beat.advance(draw_t)
	cell_view.set_growth_pose(growth_beat.swell(), growth_beat.cell_offset(), _stretch_now(draw_t))
	cell_view.set_ripeness(GrowthHud.share_of(growth(), sim_size()) if growth() != null else 0.0)
	markers.beat_t = growth_beat.t()
	silt_trail.step(draw_t)
	older_haze.step(draw_t)
	_refresh_older_haze()
	if is_endless():
		old_band.focus_am = _focus_am()
		old_band.tick(draw_t)
		if cradle != null:
			cradle.update_caption(old_band.focus_am, WorldConfig.tm_to_am(sim_size()))
		zone_lights.update_bloom(sim.tick, fraction)   # V3-11: the drawn tick's bloom phase
	if world_fx.scale != Vector3.ONE:
		_bake_fx()   # a meal ghost was in flight at the growth: once it has landed
	cell_view.show_motion(sim.motion, fraction)
	cell_view.set_sheltered(sim.is_sheltered())
	_draw_kin(fraction, draw_t)
	creature_layer.sync(fraction)
	camera.follow(cell_view.position, Vector2.ZERO if paused else sim.display_velocity(), delta)
	_follow_camera()
	_update_markers()
	_draw_food(fraction)
	_apply_scale_view()
	feedback.update_zones(sim.region, sim.plankton, delta, PlaneSpace.to_plane(cell_view.position), sim.phenotype.radius)
	_update_starving(delta)
	_update_shore(delta)
	_update_target_ring()


func _unhandled_input(event: InputEvent) -> void:
	if paused or sim == null:
		return
	if event.is_action_pressed("pause"):
		request_pause("key")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out"):
		# The growth beat's dolly owns the distance until it hands back (V-3).
		if not camera.dolly_active():
			camera.zoom_by(-1 if event.is_action_pressed("zoom_in") else 1)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("grow") and growth() != null:
		# A held key repeats as echo events, which is_action_pressed ignores: one press, one tick.
		_grow_pressed = true
		if is_inside_tree():
			get_viewport().set_input_as_handled()


## Puts the growth inputs into this tick's intent (V-16): a grow press only when the player swims
## (a bot presses for itself), for this tick alone, and a queued trigger once.
func _add_growth_intent(intent: SimIntent) -> void:
	sent_grow = _grow_pressed and intent_provider == swim_input
	sent_trigger = _trigger_pending
	_grow_pressed = false
	_trigger_pending = ""
	if sent_grow:
		intent.grow = true
	if sent_trigger != "":
		intent.trigger = sent_trigger


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss:
		request_pause("focus")
	elif what == NOTIFICATION_PREDELETE:
		_drain_preload()


## Each tell's length in seconds by tell kind, {"lunge": 1.2, "puff": 1.2}, from the species data,
## so the tell cues end as the strikes start.
static func tell_lengths(species: SpeciesCatalog) -> Dictionary:
	var out := {}
	for id in species.species_ids():
		var attack: Dictionary = species.species[id].get("attack", {})
		if attack.has("tell") and attack.has("tell_s"):
			out[str(attack.tell)] = float(attack.tell_s)
	return out


## Sim time of the drawn moment: the previous tick plus `fraction` of one tick.
func _draw_time(fraction: float) -> float:
	return sim.now() - (1.0 - fraction) * PoolSim.DT


func _draw_food(fraction: float) -> void:
	var t := _draw_time(fraction)
	plankton_view.sync(sim.plankton.items, t)
	carrion_view.sync(sim.carrion.items, t)


func _route_events() -> void:
	var events := sim.drain_events()
	for event in events:
		_route(event)
	if session != null:
		session.after_events(events)


func _route(event: Dictionary) -> void:
	match event.type:
		"ate":
			var kind: String = event.kind
			var view := plankton_view if kind == "plant" else carrion_view
			cell_view.gulp()
			# A morsel site's item (S3) is swallowed as the body it was drawn as.
			var morsel := creature_layer.morsel_mesh_for(str(event.get("food_id", ""))) if kind == "meat" else null
			cell_view.swallow(PlaneSpace.to_world(event.position), kind, morsel if morsel != null else view.food_mesh())
			feedback.show_meal(event)
			audio.play("eat_plant" if kind == "plant" else "eat_meat")
		"refused":
			var text := hints.consider(event, sim.now())
			if not text.is_empty():
				if RefusalHints.is_diet(event.reason):
					cell_view.head_shake()
				if event.reason != "not hungry":
					audio.play("refuse")
				refusal_hint.emit(text, event.reason)
		"died":
			cell_view.set_dead(true)
			release_input()
			died.emit(str(event.get("cause", "")), str(event.get("reason", "")))
		"respawned":
			_cancel_growth()
			cell_view.set_growth_pose(1.0, Vector2.ZERO, 0.0)
			cell_view.set_dead(false)
			cell_view.place(sim.motion)
			camera.snap_to(cell_view.position)
			_refresh_older_haze()
			_refresh_old_band()
			hints.reset()
			audio.play("respawn")
			respawned.emit(float(event.get("grace_s", 0.0)), bool(event.get("teleport", false)))
		"creature_noticed":
			if event.get("target") == CreatureField.PLAYER_ID:
				audio.play_at("notice", _world(event.position))
		"creature_tell":
			audio.play_at("tell_" + str(event.get("kind", "")), _world(event.position))
		"attack_refused":
			var text := hints.consider_attack(event, sim.now())
			if not text.is_empty():
				audio.play("refuse")
				refusal_hint.emit(text, str(event.reason))
		"dodged":
			feedback.show_dodged(sim.motion.position)
			audio.play("dodged")
		"hit":
			feedback.show_hit(event)
			if event.get("target") == CreatureField.PLAYER_ID:
				cell_view.hurt()
				audio.play("hurt")
			else:
				audio.play_at("bite" if event.get("kind") == "bite" else "ram", _world(event.position))
		"creature_died":
			audio.play_at("creature_die", _world(event.position))
		"creature_post_move":
			var mover: CreatureField.Creature = sim.creatures.find(str(event.get("id", ""))) if sim.creatures != null else null
			if mover != null:
				silt_trail.add_ribbon(event, mover.species_id, sim.now())
		"chunk_loaded", "chunk_unloaded", "rebased":
			apply_world_event(event)
		"kin_arrived":
			_show_kin()
		"kin_left":
			_hide_kin()
		"mate":
			audio.play("growth_ring")
			if mate_requested.get_connections().is_empty():
				finish_mate()
			else:
				mate_requested.emit()
		"growth_began":
			_begin_growth(event)
		"grew":
			growth_beat.apply_grew(event)
			apply_food_looks(sim_size())
			audio.play("grow")
		"carrion_expired":
			if event.get("reason") == "growth":
				growth_beat.on_event(event)
		"creature_converted":
			if event.get("to") == "haze":
				growth_beat.on_event(event)
		"debug":
			# A dev rebase needs nothing more: its "rebased" event came first and shifted the view.
			if event.get("command") == "teleport" or event.get("command") == "teleport_abs":
				_cancel_growth()
				cell_view.set_growth_pose(1.0, Vector2.ZERO, 0.0)
				cell_view.place(sim.motion)
				camera.snap_to(cell_view.position)
				_refresh_older_haze()
				_refresh_old_band()
			elif event.get("command") == "set_size":
				# No beat (C-V9): the scene jumps to the new size at once.
				_cancel_growth()
				cell_view.set_growth_pose(1.0, Vector2.ZERO, 0.0)
				cell_view.place(sim.motion)
				camera.snap_to(cell_view.position)
				creature_layer.attach(sim, world_space)
				creature_layer.apply_relations(sim_size(), 0.0)
				apply_food_looks(sim_size())
				silt_trail.resize(sim_size())
				older_haze.set_size(sim_size())
				_refresh_older_haze()
				old_band.focus_am = _focus_am()
				old_band.set_band(WorldConfig.band_of(sim_size()), sim_size())
				if cradle != null:
					cradle.set_size(sim_size())
					beacon.place(sim.world, sim_size())
				if audio.has_method(&"set_size"):
					audio.call(&"set_size", sim_size())
	creature_layer.on_event(event)
	sim_event.emit(event)


## S3 (V3-16, s3-view 13): the scenes a band-up may draw, sorted: every kit shell, landmark and rare
## GLB of the bands this build reaches, the cradle ring and the home beacon. None in the pool.
func s3_preload_paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_endless() or session.world.kit == null:
		return out
	var kit := session.world.kit
	var top := WorldConfig.band_of(max_size())
	for id: String in kit.assets:
		var a: Dictionary = kit.assets[id]
		var path := str(a.get("glb", ""))
		if str(a.get("kind", "")) in ["shell", "landmark", "rare"] and int(a.get("band", -1)) >= 0 and int(a.get("band", -1)) <= top \
				and not path.is_empty() and ResourceLoader.exists(path):
			out.append(path)
	for path in [CRADLE_RING_PATH, HOME_BEACON_PATH]:
		if ResourceLoader.exists(path):
			out.append(path)
	out.sort()
	return out


## Starts loading `paths` on a worker thread (load() elsewhere then hits the cache). One thread per
## scene, no sub-threads: with sub-threads a GLB's loads outlive the pool and Godot 4.7 aborts at exit.
func _start_preload(paths: PackedStringArray) -> void:
	_preload_pending = PackedStringArray()
	_preloaded.clear()
	_preload_done = paths.is_empty()
	for path in paths:
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_preload_pending.append(path)
		else:
			_preloaded[path] = load(path)
	if not _preload_done and _preload_pending.is_empty():
		_finish_preload()


## Each frame until the preload is done: the scenes that have landed are kept; when every one is in,
## the late warm-up.
func _poll_preload() -> void:
	if _preload_done:
		return
	for path in _preload_pending.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_preload_pending.remove_at(_preload_pending.find(path))
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_preloaded[path] = ResourceLoader.load_threaded_get(path)
		else:
			push_warning("The preload of %s failed; it loads when first drawn." % path)
	if _preload_pending.is_empty():
		_finish_preload()


## Test hook: the preload finished now, every scene loaded on this thread.
func preload_now() -> void:
	if _preload_done:
		return
	for path in _preload_pending:
		_preloaded[path] = ResourceLoader.load_threaded_get(path)
	_preload_pending = PackedStringArray()
	_finish_preload()


func preload_done() -> bool:
	return _preload_done


## A pool freed mid-preload collects its threaded loads first, so no worker holds a request nobody
## takes (the loader would keep it past the pool and abort at exit).
func _drain_preload() -> void:
	for path in _preload_pending:
		ResourceLoader.load_threaded_get(path)
	_preload_pending = PackedStringArray()


## Every mesh the warm-ups drew so far (tests).
func warmed_meshes() -> Array[Mesh]:
	return _warmed


func _finish_preload() -> void:
	_preload_done = true
	_warm_up_late()
	preload_finished.emit()


## The late warm-up: every mesh of the preloaded scenes drawn once out of sight, as the start fade
## draws its own, so a band-up's first frame compiles nothing.
func _warm_up_late() -> void:
	var meshes: Array[Mesh] = []
	for path in _preloaded:
		var scene := _preloaded[path] as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := (n as MeshInstance3D).mesh
			if mesh != null and not meshes.has(mesh):
				meshes.append(mesh)
		root.free()
	_warmed.append_array(meshes)
	cell_view.warm_up(meshes, warm_up_point(camera.global_transform if camera.is_inside_tree() else camera.transform))


## The ghosts and art's ambience (when it can) read the scale view each frame (s2-view 4.2, 6, 11.2).
func _apply_scale_view() -> void:
	var view := scale_view()
	ghosts.apply_scale_view(view)
	var ambience := get_node_or_null(^"Ambience")
	if ambience != null and ambience.has_method(&"apply_scale_view"):
		ambience.call(&"apply_scale_view", view)


## S4.3: the kin is drawn as a second cell from the cell's own genome, pulsing softly while the cell
## could mate with it. It is world_rebuilt like the cell: placed from the sim every frame.
func _show_kin() -> void:
	_hide_kin()
	kin_view = (load(KIN_VIEW_SCENE) as PackedScene).instantiate() as PlayerCellView
	kin_view.name = "Kin"
	add_child(kin_view)
	kin_view.add_to_group(&"world_rebuilt")
	kin_view.build(sim.save.genome, sim.phenotype)
	kin_view.place(sim.kin.motion)


func _hide_kin() -> void:
	if kin_view != null:
		kin_view.queue_free()
		kin_view = null


func _draw_kin(fraction: float, draw_t: float) -> void:
	if kin_view == null:
		return
	if sim.kin == null or not sim.kin.present:
		_hide_kin()
		return
	kin_view.show_motion(sim.kin.motion, fraction)
	var pulse := KIN_PULSE * sin(TAU * KIN_PULSE_HZ * draw_t) if Kin.is_ready(sim) and not sim.kin.waiting else 0.0
	kin_view.set_growth_pose(1.0 + pulse, Vector2.ZERO, 0.0)


## The editor opened by mate_requested has closed: the kin goes. With `born`, the cell has taken
## its new body (PoolSim.apply_offspring), and the view draws it.
func finish_mate(born := false) -> void:
	if sim == null:
		return
	if born:
		cell_view.build(sim.save.genome, sim.phenotype)
		cell_view.place(sim.motion)
	if sim.kin != null:
		sim.kin.finish(sim)


func _world(p: Variant) -> Vector3:
	return PlaneSpace.to_world(p) if p is Vector2 else cell_view.position


## Grey cell, pulse sound and the food arrow while starving.
func _update_starving(delta: float) -> void:
	var starving := sim.state.is_starving() and not sim.dead
	cell_view.set_starving(starving)
	if starving and not paused:
		_starve_pulse_t -= delta
		if _starve_pulse_t <= 0.0:
			_starve_pulse_t = STARVE_PULSE_S
			audio.play("starve_pulse")
	elif not starving:
		_starve_pulse_t = 0.0
	var food := sim.nearest_edible() if starving and bool(sim.layout.assists.get("starving_food_arrow", false)) else {}
	if food.is_empty():
		starving_arrow.visible = false
		return
	var cell_at := cell_view.position
	var food_at := PlaneSpace.to_world(food.position)
	var cell_px := camera.unproject_position(cell_at)
	var cell_radius_px := camera.unproject_position(cell_at + Vector3.RIGHT * sim.phenotype.radius).distance_to(cell_px)
	# One meter toward the food is always in front of the camera, so it gives the screen direction.
	var toward := cell_at + (food_at - cell_at).normalized()
	var direction := camera.unproject_position(toward) - cell_px
	var food_px := Vector2.INF
	if not camera.is_position_behind(food_at):
		var p := camera.unproject_position(food_at)
		if starving_arrow.get_rect().has_point(p):
			food_px = p
	starving_arrow.point(cell_px, direction, food_px, cell_at.distance_to(food_at), cell_radius_px)


func _update_target_ring() -> void:
	var target: Variant = swim_input.pointer_target if intent_provider == swim_input else null
	if paused or not target is Vector2:
		target_ring.visible = false
		return
	target_ring.show_at(camera.unproject_position(PlaneSpace.to_world(target)))


func _record_cost(usec: int) -> void:
	if _step_costs.size() < STEP_COST_WINDOW:
		_step_costs.append(usec)
	else:
		_step_costs[_step_cost_next] = usec
	_step_cost_next = (_step_cost_next + 1) % STEP_COST_WINDOW
