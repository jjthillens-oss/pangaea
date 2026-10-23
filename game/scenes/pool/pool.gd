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

const STEP_COST_WINDOW := 120   ## ticks averaged for step_cost_usec()
const FADE_IN_S := 0.3
## The shader warm-up under the fade draws on the camera's view axis this deep (m): in the frustum
## at every zoom and inside the far plane, so it is really drawn, yet hidden behind the fluid's
## opaque Backdrop (y −40). Occlusion culling is off; turning it on would cull the hidden draw,
## nothing would compile, and this point must move.
const WARM_UP_Y := -45.0
const STARVE_PULSE_S := 1.0
## Art's decor plug-in (micro-world plan section 7): mounted as the pool's single child "Ambience"
## when the scene exists. It reads get_parent().camera and get_parent().cell_view and writes
## nothing back; tests/test_ambience_contract.gd holds it to the rest of the contract.
const AMBIENCE_SCENE := "res://game/scenes/pool/ambience/ambience.tscn"

## Pause when the window loses focus (Bible 19). Off for tools that render without focus.
@export var pause_on_focus_loss := true

var session: GameSession
var sim: PoolSim
## Anything with next_intent(sim: PoolSim) -> SimIntent.
var intent_provider: Object
var paused := false
var hints := RefusalHints.new()

var _built := false
var _step_costs := PackedInt64Array()
var _step_cost_next := 0
var _starve_pulse_t := 0.0

## The world's edge: the dish wall the collision stops the cell at, with its lip and shelf.
@onready var rim_node: Node3D = %Rim
## The sunlit patches: soft light under each plankton zone.
@onready var zone_lights: ZoneLights = %ZoneLights
@onready var rocks: RockField = %Rocks
@onready var plankton_view: FoodView = %Plankton
@onready var carrion_view: FoodView = %Carrion
@onready var cell_view: PlayerCellView = %PlayerCell
@onready var creature_layer: CreatureLayer = %Creatures
@onready var feedback: FeedbackFx = %Feedback
@onready var camera: PoolCamera = %Camera
@onready var swim_input: SwimInput = %SwimInput
@onready var audio: PlaceholderAudio = %Audio
@onready var ui: CanvasLayer = %UI
@onready var target_ring: TargetRing = %TargetRing
@onready var starving_arrow: StarvingArrow = %StarvingArrow
@onready var _fade: ColorRect = %Fade
@onready var _sun: DirectionalLight3D = $Sun
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
	swim_input.camera = camera
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
	rocks.build(session.layout)
	zone_lights.build(session.layout.zones)
	cell_view.build(sim.save.genome, sim.phenotype)
	cell_view.place(sim.motion)
	cell_view.set_dead(sim.dead)
	creature_layer.attach(sim)
	if sim.species != null:
		audio.configure_tells(tell_lengths(sim.species))
	feedback.setup(session.layout.zones, camera)
	camera.configure(session.layout.camera)
	camera.snap_to(cell_view.position)
	_draw_food(1.0)
	_fade_in()


## A short fade from the fluid's mid-tone hides the first frames, while the eat burst and the
## warm-up meshes draw once out of sight (warm_up_point), so their shaders are ready before play.
func _fade_in() -> void:
	_fade.visible = true
	_fade.modulate.a = 1.0
	# A pool built outside the tree (the scene tests) sits at the origin: the camera's own transform.
	var hidden := warm_up_point(camera.global_transform if camera.is_inside_tree() else camera.transform)
	cell_view.warm_up(warm_up_meshes(), hidden)
	var tween := _fade.create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_IN_S)
	tween.tween_callback(_fade.hide)


## What the start fade draws out of sight besides the eat burst: both food meshes, which first show
## at a meal, the zone light, whose patches may first come into view later, and a strike lane, which
## first shows at a tell.
func warm_up_meshes() -> Array[Mesh]:
	return [plankton_view.food_mesh(), carrion_view.food_mesh(), zone_lights.mesh, CreatureView.warm_up_lane_mesh()] as Array[Mesh]


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
	sim.step(intent_provider.next_intent(sim))
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
	cell_view.show_motion(sim.motion, fraction)
	cell_view.set_sheltered(sim.is_sheltered())
	creature_layer.sync(fraction)
	camera.follow(cell_view.position, Vector2.ZERO if paused else sim.display_velocity(), delta)
	_draw_food(fraction)
	feedback.update_zones(sim.region, sim.plankton, delta)
	_update_starving(delta)
	_update_target_ring()


func _unhandled_input(event: InputEvent) -> void:
	if paused or sim == null:
		return
	if event.is_action_pressed("pause"):
		request_pause("key")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_in"):
		camera.zoom_by(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_out"):
		camera.zoom_by(1)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss:
		request_pause("focus")


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
	for event in sim.drain_events():
		_route(event)


func _route(event: Dictionary) -> void:
	match event.type:
		"ate":
			var kind: String = event.kind
			var view := plankton_view if kind == "plant" else carrion_view
			cell_view.gulp()
			cell_view.swallow(PlaneSpace.to_world(event.position), kind, view.food_mesh())
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
			cell_view.set_dead(false)
			cell_view.place(sim.motion)
			camera.snap_to(cell_view.position)
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
		"debug":
			if event.get("command") == "teleport":
				cell_view.place(sim.motion)
				camera.snap_to(cell_view.position)
	creature_layer.on_event(event)
	sim_event.emit(event)


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
