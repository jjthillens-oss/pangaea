class_name GrowthBeat
extends Node
## The growth beat on screen (S2, s2-view 4): the two seconds after the sim's growth tick in which the
## scene shows the world re-expressed at the new size without a jump. The tick has already happened
## (growth_began ... grew, routed in one frame); this node only times how the scene catches up.
##
## Frame 0 draws what frame A drew. Every position is re-expressed by 1 / factor round the old centre
## (WorldSpace.apply_growth, PoolCamera.reexpress), so the scene would shrink on screen; instead the
## camera starts factor times nearer and every depth layer at k = 1 / factor of its depth, and the cell
## starts drawn at k of its size (the swell). Then:
##   0 to 0.7 s    the cell swells to its new size and eases to where the tick settled it
##   0.3 to 1.9 s  the camera dollies back out and k runs to 1 (dolly_k: one curve for every layer)
##   1.9 s         the chord: the HUD, the markers' thresholds and shown_size() switch to the new size
##   2.0 s         relations change (ink, rim, "Now food", remnants go limp); the containers end
##   6.0 s         the last of the beat's effects (glitter) is gone and the beat is idle
## The old food (4.6, V-10, V-22): what the food views last drew before the tick is kept (a snapshot
## at growth_began) and drawn on, re-expressed, from still copies that fade over 0.6 s: all the old
## plankton, and the carrion the tick dropped. Out of the old plankton (and any creature turned to
## haze) pale glitter sinks to -3 tm over 2 s, holds, and is gone by 6 s; the new food grows in.
## Reduce camera motion (V-17): the last frame is kept on screen as a still that dissolves over 0.8 s
## (headless, %Fade dips instead); under it k is 1 and the camera at its zoom from frame 0, and the
## swell is halved.
##
## The clock is the pool's draw time (V-1): the first advance() after begin() is t = 0, so the beat
## stops while the pool is paused and is the same at any frame rate. Everything is closed-form in t;
## no Tween runs.

const BEAT_S := 2.0
const SWELL_S := 0.7
const DOLLY := Vector2(0.3, 1.9)
const CHORD_S := 1.9
const REDUCED_DISSOLVE_S := 0.8
const MIN_FADE_S := 0.5
const PREBLUR_S := 1.0
const SINK_TM := 1.5
## 1 / factor at the build's factor 1.6; begin() takes it from the event.
const K_FROM := 0.625
## Ink fades, rims and "Now food" come, remnants go limp (V-8).
const RELATIONS_S := 2.0
const NOW_FOOD_S := 3.0
const NOW_FOOD_MAX := 3
## Leftover pieces sink and fade over this, from the settle (>= MIN_FADE_S).
const RETIRE_S := 1.2
const OLD_FOOD_FADE_S := 0.6
const GLITTER_DEPTH_TM := -3.0
const GLITTER_SINK_S := 2.0
const GLITTER_GONE_S := 6.0
const GLITTER_TINT := Color("#B8C4D6")
const GLITTER_ALPHA := Vector2(0.6, 0.25)   ## above and below -1.5 tm
const GLITTER_MAX := 400
## The glitter holds from its sink until here, then fades out by GLITTER_GONE_S.
const GLITTER_HOLD_S := 4.0
## As the glitter sinks through this band (tm) its alpha eases from GLITTER_ALPHA.x to .y, so it is
## GLITTER_ALPHA.y everywhere below -1.5 with no step; it comes in over GLITTER_IN_S over the old
## food, with no pop at frame 0.
const GLITTER_BAND := Vector2(-1.0, -1.5)
const GLITTER_IN_S := 0.15
## The haze sprites by food look and by species (T5.5 reads them from ghost_ladder.json).
const FOOD_HAZE := {"plankton": "res://assets/export/ambience/T_Haze_plankton.png",
	"algae_ball": "res://assets/export/ambience/T_Haze_algae_ball.png",
	"carrion": "res://assets/export/ambience/T_Haze_carrion.png"}
const SPECIES_HAZE := {"ambush_hunter": "res://assets/export/ambience/T_Haze_ambush.png",
	"rammer": "res://assets/export/ambience/T_Haze_rammer.png",
	"lurker": "res://assets/export/ambience/T_Haze_lurker.png",
	"elder_rammer": "res://assets/export/ambience/T_Haze_elder_rammer.png"}
## Each haze sprite's body span by file name: the larger side of its alpha >= 0.1 box over the
## texture's side (s2-view 0.9). A sprite is drawn at its thing's diameter over this.
const HAZE_SPANS := {"T_Haze_plankton.png": 0.773, "T_Haze_algae_ball.png": 0.438, "T_Haze_carrion.png": 0.719,
	"T_Haze_ambush.png": 0.844, "T_Haze_rammer.png": 0.5, "T_Haze_lurker.png": 0.844,
	"T_Haze_elder_rammer.png": 0.438, "T_Haze_veil.png": 0.844, "T_Haze_warden.png": 0.602,
	"T_Haze_bead_cluster.png": 0.766, "T_Haze_glass_flake.png": 0.82}
const RISE := Vector2(1.0, 2.0)
const RISE_SWIM_TM_S := 3.0
const RISE_MAX_S := 6.0
## Under reduce motion the swell starts half way (half of the 0.375 swell).
const REDUCED_SWELL_FROM := 0.8125
## Headless reduce motion: %Fade's alpha at the middle of the dissolve.
const FADE_DIP_ALPHA := 0.6
## When the beat goes idle: the glitter is gone (cancel() jumps here).
const END_S := GLITTER_GONE_S
const PREBLUR_SHADER := preload("res://game/scenes/pool/preblur.gdshader")

var _pool: PoolScene
var _running := false
var _t0 := -1.0
var _t := -1.0
var _from := 1
var _to := 1
var _factor := 1.6
var _k_from := K_FROM
var _reduced := false
var _settled_to := Vector2.ZERO
var _chord_done := false
var _relations_done := false
var _ended := false
var _dip := false
var _center_old := Vector2.ZERO
## The food views as last drawn before the tick (id -> transform), and the dropped carrion's.
var _plants := {}
var _meat := {}
var _expired: Array[Transform3D] = []
## Creatures turned to haze: {look, at (the pool's space, new frame), diameter (new tm)}.
var _creature_haze: Array[Dictionary] = []
var _copies: Array[StillInstances] = []
var _glitter: Array[StillInstances] = []
## The haze sprite of each food look and species.
var haze := FOOD_HAZE.merged(SPECIES_HAZE)
static var _glitter_quad: QuadMesh
## The still of the last frame that dissolves under reduce motion (over the HUD, under nothing).
var _dissolve: TextureRect
## The beat's own effects in the world's frame (the old food copies and the glitter, T5.4): a
## WorldSpace container, so a rebase moves it and a growth re-expresses what it holds.
var fx: Fx


## Once, from the pool's build: the dissolve over the UI and the effects node in WorldSpace.
func setup(pool: PoolScene) -> void:
	_pool = pool
	if _dissolve == null:
		_dissolve = TextureRect.new()
		_dissolve.name = "BeatDissolve"
		_dissolve.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dissolve.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dissolve.stretch_mode = TextureRect.STRETCH_SCALE
		_dissolve.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_dissolve.visible = false
		pool.ui.add_child(_dissolve)
	if fx == null:
		fx = Fx.new()
		fx.name = "BeatFx"
		pool.add_child(fx)
	pool.world_space.register(fx)
	_stop()


## growth_began {from, to, center_old, factor}: the beat starts; its frame 0 is the next advance().
## Under reduce motion the last drawn frame is kept first, before anything moves (4.7).
func begin(event: Dictionary, reduce_motion: bool) -> void:
	if _running:
		cancel()
	_from = int(event.get("from", 1))
	_to = int(event.get("to", _from + 1))
	_factor = maxf(float(event.get("factor", 1.0 / K_FROM)), 1e-6)
	_k_from = 1.0 / _factor
	_reduced = reduce_motion
	_settled_to = Vector2.ZERO
	_t0 = -1.0
	_t = 0.0
	_chord_done = false
	_relations_done = false
	_ended = false
	_dip = false
	var center: Variant = event.get("center_old", Vector2.ZERO)
	_center_old = center if center is Vector2 else Vector2.ZERO
	_plants = _pool.plankton_view.snapshot()
	_meat = _pool.carrion_view.snapshot()
	_expired.clear()
	_creature_haze.clear()
	_running = true
	if _reduced:
		_show_still(_snapshot())


## grew {settled_to, haze, remnants, morsels, checkpoint_am}: the containers' leftovers start to
## sink, the cell eases from where it was to where the tick settled it, the old food is drawn on
## from its copies, and the glitter starts from `haze` (its old plankton, old-frame points).
func apply_grew(event: Dictionary) -> void:
	if not _running:
		return
	var settled: Variant = event.get("settled_to", Vector2.ZERO)
	_settled_to = settled if settled is Vector2 else Vector2.ZERO
	for c in _pool.growth_containers():
		c.settle_growth()
	var plants: Array[Transform3D] = []
	plants.assign(_plants.values())
	_add_copy(_pool.plankton_view.retired_copy(plants, _center_old, _factor), "OldPlankton")
	_add_copy(_pool.carrion_view.retired_copy(_expired, _center_old, _factor), "OldCarrion")
	var by_look := {}
	for h: Dictionary in _nearest_plants(event.get("haze", [])):
		var look := str(h.look)
		if not by_look.has(look):
			by_look[look] = []
		var r := float(FoodView.LOOKS[look].radius) if FoodView.LOOKS.has(look) else 0.0
		by_look[look].append({"at": _reexpressed(h.position), "diameter": 2.0 * r / _factor})
	for look in by_look:
		_add_glitter("Glitter" if by_look.size() == 1 else "Glitter_" + str(look), haze.get(look, ""), by_look[look])
	var by_species := {}
	for h in _creature_haze:
		if not by_species.has(h.look):
			by_species[h.look] = []
		by_species[h.look].append(h)
	for look in by_species:
		_add_glitter("Glitter_" + str(look), haze.get(look, ""), by_species[look])
	_step_food()


## The beat's own events: carrion the tick dropped (carrion_expired {growth}) joins the old carrion's
## copy as it was last drawn; a creature turned to haze (creature_converted {haze}) leaves glitter
## where it was, its old drawn diameter (twice its new radius, in new tm) across.
func on_event(event: Dictionary) -> void:
	if not _running:
		return
	match str(event.get("type", "")):
		"carrion_expired":
			var t: Variant = _meat.get(event.get("food_id", ""))
			if t is Transform3D:
				_expired.append(t)
		"creature_converted":
			if event.get("to") == "haze" and event.get("position") is Vector2:
				_creature_haze.append({"look": str(event.get("species", "")), "at": _reexpressed(event.position),
					"diameter": 2.0 * float(event.get("radius", 0.0))})


## Once per frame from PoolScene._process, after the events and before the cell is drawn.
func advance(draw_time_s: float) -> void:
	if not _running:
		return
	if _t0 < 0.0:
		_t0 = draw_time_s
	_t = maxf(draw_time_s - _t0, 0.0)
	_step()


## Beat seconds since frame 0; -1 when idle.
func t() -> float:
	return _t if _running else -1.0


func active() -> bool:
	return _running and _t < BEAT_S


func running() -> bool:
	return _running


func reduced() -> bool:
	return _running and _reduced


## The depth factor of every depth layer now: 1 when idle or under reduce motion.
func k() -> float:
	if not _running or _reduced:
		return 1.0
	return dolly_k(_t, _k_from)


## The size the scene shows: the old one until the chord (V-7), then the sim's.
func shown_size() -> int:
	return _from if _running and _t < CHORD_S else _pool.sim_size()


## The cell's Pivot factor now (1 when idle).
func swell() -> float:
	return swell_at(_t, _reduced, _k_from) if _running else 1.0


## Where the cell is drawn from the sim's position now (tm): the settle shown, not jumped (V-6).
func cell_offset() -> Vector2:
	if not _running:
		return Vector2.ZERO
	return (1.0 - ease_out_cubic(clampf(_t / SWELL_S, 0.0, 1.0))) * (Vector2.ZERO - _settled_to)


## The Stretch blend shape's weight from the beat (0 when idle): 1 at frame 0 easing to 0 by the end
## of the swell, half under reduce motion.
func stretch() -> float:
	if not _running:
		return 0.0
	var s := 1.0 - ease_out_cubic(clampf(_t / SWELL_S, 0.0, 1.0))
	return s * 0.5 if _reduced else s


## The dissolve's alpha now (0 when none shows), for tests.
func dissolve_alpha() -> float:
	return _dissolve.modulate.a if _dissolve != null and _dissolve.visible else 0.0


## The old food's still copies now (they go once faded), for tests.
func old_food() -> Array[StillInstances]:
	_copies.assign(_copies.filter(func(c: StillInstances) -> bool: return is_instance_valid(c)))
	return _copies


## The glitter now (one StillInstances per haze sprite), for tests.
func glitter() -> Array[StillInstances]:
	_glitter.assign(_glitter.filter(func(g: StillInstances) -> bool: return is_instance_valid(g)))
	return _glitter


## Jumps to the end state at once (snap_to, a respawn, a dev size change): the chord and the
## relations happen now with no fade, the containers end, and every beat effect goes.
func cancel() -> void:
	if not _running:
		return
	_t = END_S
	_step(true)


## A veil overlay for a piece fading in or sinking away (preblur.gdshader), `amount` 0 to 1.
static func preblur(amount: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PREBLUR_SHADER
	m.set_shader_parameter("amount", amount)
	return m


## How far the leftovers have sunk and faded at beat time t, 0 to 1, from the settle at `settled_t`
## (before the settle, 0).
static func retire_share(t_s: float, settled_t: float) -> float:
	if settled_t < 0.0:
		return 0.0
	return smoothstep(0.0, 1.0, (t_s - settled_t) / RETIRE_S)


## How far a fresh piece has come in at beat time t, 0 to 1.
static func fresh_share(t_s: float) -> float:
	return clampf(t_s / PREBLUR_S, 0.0, 1.0)


static func dolly_k(t_s: float, k_from := K_FROM) -> float:
	if t_s <= DOLLY.x:
		return k_from
	if t_s >= DOLLY.y:
		return 1.0
	return lerpf(k_from, 1.0, ease_in_out_cubic((t_s - DOLLY.x) / (DOLLY.y - DOLLY.x)))


## The cell's swell at beat time t: k_from (half way under reduce motion) easing out to 1 over SWELL_S.
static func swell_at(t_s: float, reduce_motion: bool, k_from := K_FROM) -> float:
	var from := (1.0 + k_from) * 0.5 if reduce_motion else k_from
	return lerpf(from, 1.0, ease_out_cubic(clampf(t_s / SWELL_S, 0.0, 1.0)))


## The glitter's height (tm) at beat time t: from the plane down to GLITTER_DEPTH_TM, easing out.
static func glitter_y(t_s: float) -> float:
	return GLITTER_DEPTH_TM * ease_out_cubic(clampf(t_s / GLITTER_SINK_S, 0.0, 1.0))


## The glitter's alpha at beat time t (V-22): GLITTER_ALPHA.x near the plane, .y from -1.5 tm down,
## in over GLITTER_IN_S and out from GLITTER_HOLD_S to GLITTER_GONE_S.
static func glitter_alpha(t_s: float) -> float:
	var sunk := clampf((glitter_y(t_s) - GLITTER_BAND.x) / (GLITTER_BAND.y - GLITTER_BAND.x), 0.0, 1.0)
	var come := clampf(t_s / GLITTER_IN_S, 0.0, 1.0)
	var go := clampf((GLITTER_GONE_S - t_s) / (GLITTER_GONE_S - GLITTER_HOLD_S), 0.0, 1.0)
	return lerpf(GLITTER_ALPHA.x, GLITTER_ALPHA.y, sunk) * come * go


## The glitter's look: the haze sprite `texture` facing the camera, unshaded, tinted GLITTER_TINT.
static func glitter_material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = texture
	m.albedo_color = GLITTER_TINT
	return m


## The quad every glitter sprite draws (1 tm across before its scale).
static func glitter_quad() -> QuadMesh:
	if _glitter_quad == null:
		_glitter_quad = QuadMesh.new()
		_glitter_quad.size = Vector2.ONE
	return _glitter_quad


## What the start fade draws once so the beat's shaders are ready (V-20): the pre-blur veil (on a copy
## of a recorded mesh, as it lies over the shells and landmarks in play) and the glitter (the first
## food look's sprite).
static func warm_up_meshes() -> Array[Mesh]:
	var veil := FoodView.look_mesh("plankton").duplicate() as Mesh
	for i in veil.get_surface_count():
		veil.surface_set_material(i, preblur(0.5))
	var sprite := QuadMesh.new()
	sprite.material = glitter_material(load(FOOD_HAZE.plankton) as Texture2D)
	return [veil, sprite] as Array[Mesh]


static func ease_in_out_cubic(u: float) -> float:
	return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0


static func ease_out_cubic(u: float) -> float:
	return 1.0 - pow(1.0 - u, 3.0)


func _step(cancelled := false) -> void:
	var k := k()
	_pool.camera.dolly_t = _t
	if cancelled:
		_pool.camera.end_dolly()
	_pool.apply_depth_k(k)
	for c in _pool.growth_containers():
		c.beat_frame(_t, k)
	_step_food()
	_show_dissolve()
	if not _chord_done and _t >= CHORD_S:
		_chord_done = true
		_pool.on_growth_chord(_to)
	if not _relations_done and _t >= RELATIONS_S:
		_relations_done = true
		_pool.on_growth_relations(_to, 0.0 if cancelled else 1.0)
	if not _ended and _t >= BEAT_S:
		_ended = true
		for c in _pool.growth_containers():
			c.end_growth()
	if _t >= END_S:
		_stop()


## The old food's copies fade over OLD_FOOD_FADE_S, then go; the glitter sinks and fades.
func _step_food() -> void:
	if not _copies.is_empty():
		var fade := clampf(_t / OLD_FOOD_FADE_S, 0.0, 1.0)
		for copy in old_food():
			if fade >= 1.0:
				fx.remove_child(copy)
				copy.queue_free()
			else:
				copy.transparency = fade
		if fade >= 1.0:
			_copies.clear()
	if not _glitter.is_empty():
		var y := glitter_y(_t)
		var a := glitter_alpha(_t)
		for g in glitter():
			g.position.y = y
			(g.material_override as StandardMaterial3D).albedo_color.a = a


## Up to GLITTER_MAX of the plant `haze` entries, nearest the cell (its old point) first.
func _nearest_plants(entries: Array) -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	for h in entries:
		if h is Dictionary and h.get("kind") == "plant" and h.get("position") is Vector2:
			plants.append(h)
	if plants.size() > GLITTER_MAX:
		var c := _center_old
		plants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return c.distance_squared_to(a.position) < c.distance_squared_to(b.position))
		plants.resize(GLITTER_MAX)
	return plants


## An old-frame plane point `p` in the pool's space now (re-expressed round the old centre, y 0).
func _reexpressed(p: Vector2) -> Vector3:
	return WorldSpace.reexpress_point(PlaneSpace.to_world(p), _center_old, _factor)


## `copy` (a FoodView.retired_copy, the pool's space) under BeatFx, fading from whole.
func _add_copy(copy: StillInstances, copy_name: String) -> void:
	if copy.transforms.is_empty():
		copy.free()
		return
	copy.name = copy_name
	copy.position = -fx.position
	fx.add_child(copy)
	_copies.append(copy)


## One glitter MultiMeshInstance3D of the haze sprite at `path`: an instance per {at, diameter}.
func _add_glitter(glitter_name: String, path: String, sprites: Array) -> void:
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture == null or sprites.is_empty():
		return
	var span := float(HAZE_SPANS.get(path.get_file(), 1.0))
	var sprites_at: Array[Transform3D] = []
	for sprite in sprites:
		var at: Vector3 = sprite.at
		sprites_at.append(Transform3D(Basis.from_scale(Vector3.ONE * (float(sprite.diameter) / span)), Vector3(at.x, 0.0, at.z)))
	var g := StillInstances.make(glitter_quad(), sprites_at)
	g.name = glitter_name
	g.material_override = glitter_material(texture)
	g.position = Vector3(-fx.position.x, glitter_y(_t), -fx.position.z)
	fx.add_child(g)
	_glitter.append(g)


func _show_dissolve() -> void:
	if _dissolve.visible:
		var a := 1.0 - _t / REDUCED_DISSOLVE_S
		_dissolve.modulate.a = clampf(a, 0.0, 1.0)
		if a <= 0.0:
			_dissolve.visible = false
			_dissolve.texture = null
	if _dip:
		var fade := _pool.fade_rect()
		if _t < REDUCED_DISSOLVE_S:
			fade.visible = true
			fade.modulate.a = FADE_DIP_ALPHA * sin(PI * _t / REDUCED_DISSOLVE_S)
		else:
			fade.modulate.a = 0.0
			fade.visible = false
			_dip = false


func _stop() -> void:
	_running = false
	_t0 = -1.0
	_t = -1.0
	_dip = false
	if _dissolve != null:
		_dissolve.visible = false
		_dissolve.texture = null
	if fx != null:
		for child in fx.get_children():
			fx.remove_child(child)
			child.queue_free()
	_copies.clear()
	_glitter.clear()
	_plants = {}
	_meat = {}
	_expired.clear()
	_creature_haze.clear()


## Keeps `still` (the last drawn frame) over the whole view, HUD included, to dissolve over
## REDUCED_DISSOLVE_S; with none (headless) %Fade dips instead.
func _show_still(still: Image) -> void:
	if still != null:
		_dissolve.texture = ImageTexture.create_from_image(still)
		_dissolve.modulate.a = 1.0
		_dissolve.visible = true
		_dip = false
	else:
		_dip = true


## The last drawn frame, or null headless or outside the tree.
func _snapshot() -> Image:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return null
	var img := get_viewport().get_texture().get_image()
	return img if img != null and not img.is_empty() else null


## BeatFx: holds the beat's effects in the world's frame. As the other containers it re-expresses
## its children in place at a growth and stays at scale 1 (WorldSpace.apply_growth).
class Fx extends Node3D:
	func apply_growth(center_old: Vector2, factor: float) -> void:
		var shift := position
		position = Vector3.ZERO
		for child in get_children():
			var n := child as Node3D
			if n != null:
				n.transform = Transform3D(n.basis.scaled(Vector3.ONE / factor),
					WorldSpace.reexpress_point(n.position + shift, center_old, factor))

	func renormalize() -> void:
		for child in get_children():
			(child as Node3D).position += position
		position = Vector3.ZERO
