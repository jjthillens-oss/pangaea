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
	_running = true
	if _reduced:
		_show_still(_snapshot())


## grew {settled_to, haze, remnants, morsels, checkpoint_am}: the containers' leftovers start to
## sink, and the cell eases from where it was to where the tick settled it.
func apply_grew(event: Dictionary) -> void:
	if not _running:
		return
	var settled: Variant = event.get("settled_to", Vector2.ZERO)
	_settled_to = settled if settled is Vector2 else Vector2.ZERO
	for c in _pool.growth_containers():
		c.settle_growth()


## The beat's own events: an old carrion item or a creature turned to haze joins its effects (T5.4).
func on_event(_event: Dictionary) -> void:
	pass


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
