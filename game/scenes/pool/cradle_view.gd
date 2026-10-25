class_name CradleView
extends Node3D
## The cradle (S3, docs/s3/s3-view.md 6, V3-6, V3-7, V3-9; D-95): from band 1 the old pool lies under
## home, shrunk to a dish. Four things round the absolute origin:
##   Ring     art's cradle_ring.glb, its materials dimmed, uniform scale pool_ring.radius_bu /
##            RING_RECORD_RADIUS_BU x bu_to_tm(n), its top at RING_TOP_TM;
##   Dish     the M1 pool's rocks and ring shells (WorldGen.old_pool_pieces, band-0 bu = am) at their
##            true size, baked like the old band (one MultiMesh per asset), tops at DISH_TOP_TM;
##   Glitter  GLITTER_COUNT plankton-haze billboards on a ring of glitter_radius_bu, at GLITTER_Y_TM;
##   Caption  "Your lineage began here" at the ring's north edge, shown within CAPTION_RANGE_TM of home
##            and faded over the last CAPTION_FADE_TM.
## Every place is laid out for a size (layout); the node shows that layout. It is a registered
## container: a growth re-expresses what is shown, then each piece eases to the new size's layout over
## the beat (V3-7). A band-up shows the new layout at once and fades it in over FADE_IN.

const RING_SCENE := "res://assets/export/cradle_ring.glb"
const RING_RECORD_RADIUS_BU := 14.0625      ## assets/records/cradle_ring.json radius_bu (test-checked)
const RING_TOP_TM := -2.0
const DISH_TOP_TM := -2.5
const GLITTER_Y_TM := -1.8
const GLITTER_COUNT := 48
const GLITTER_SIDE_TM := 0.35
const GLITTER_OPACITY := 0.25
const GLITTER_BRIGHTNESS := 0.7
const GLITTER_TINT := Color("#B8C4D6")
const GLITTER_JITTER := 0.03                ## radians either way round the ring
const GLITTER_IMAGE := "res://assets/export/ambience/T_Haze_plankton.png"
const GLITTER_SHADER := preload("res://game/scenes/pool/glitter_ring.gdshader")
const CAPTION_Y_TM := 1.2
const CAPTION_RANGE_TM := 40.0
const CAPTION_FADE_TM := 5.0
const CAPTION_COLOR := Color("#F4EAD2")
const CAPTION_GAP_BU := 1.5                 ## beyond the glitter ring
const DIM := 0.5                            ## linear albedo factor for the ring (and the beacon)
const FADE_IN := Vector2(0.5, 2.0)          ## a band-up's fade-in (beat seconds)
const SEAM_R_AM := 48.0                     ## the home block's seam ring: 36 + 12 am

## The size laid out.
var size := 1
var cradle: CradleBlock

var _world: WorldStream
var _old_pool: Array[Dictionary] = []
var _record_r := RING_RECORD_RADIUS_BU
var _ring: Node3D
var _ring_top := 0.0                        ## the ring model's AABB top (model units)
var _dish := {}                             ## asset -> MultiMeshInstance3D named Dish_<asset>
var _dish_pieces := {}                      ## asset -> Array of old-pool pieces
var _glitter: MultiMeshInstance3D
var _glitter_material := ShaderMaterial.new()
var _caption: Label3D
var _shown := {}                            ## the layout drawn now
var _to := {}                               ## the size's layout
var _from := {}                             ## a growth's frame-0 layout, while the beat eases from it
var _beat := false
var _fading := false                        ## a band-up's fade-in runs
var _fade := 1.0                            ## the fade-in's share shown
var _caption_alpha := 0.0                   ## the caption's alpha by distance alone
var _outside := PackedStringArray()


func _init() -> void:
	name = "Cradle"
	visible = false


## Builds the ring, the dish, the glitter and the caption for `p_cradle` (band 1's block; null draws
## nothing) and `old_pool` (WorldGen.old_pool_pieces). Nothing is placed until attach and set_size.
func setup(p_cradle: CradleBlock, old_pool: Array[Dictionary], ring_record_radius_bu: float) -> void:
	cradle = p_cradle
	_old_pool = old_pool
	_record_r = ring_record_radius_bu
	if cradle == null:
		return
	if ResourceLoader.exists(RING_SCENE):
		_ring = (load(RING_SCENE) as PackedScene).instantiate() as Node3D
		_ring.name = "Ring"
		dim_materials(_ring, DIM)
		for n: Node in _ring.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring_top = aabb_under(_ring).end.y
		add_child(_ring)
	_outside = PackedStringArray()
	for p in old_pool:
		if Vector2(float(p.x_bu), float(p.y_bu)).length() + float(p.r_bu) > SEAM_R_AM:
			_outside.append(str(p.id))
		var asset := str(p.asset)
		var mesh := OldBandLayer.baked(RockField.ASSET_PATH % asset)
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		if not _dish.has(asset):
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Dish_" + asset
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.multimesh = MultiMesh.new()
			mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			mmi.multimesh.mesh = mesh
			add_child(mmi)
			_dish[asset] = mmi
			_dish_pieces[asset] = []
		(_dish_pieces[asset] as Array).append(p)
	if not _outside.is_empty():
		push_warning("CradleView: old-pool pieces outside the seam ring: %s" % ", ".join(_outside))
	_glitter_material.shader = GLITTER_SHADER
	_glitter_material.set_shader_parameter("image", load(GLITTER_IMAGE) as Texture2D)
	_glitter_material.set_shader_parameter("tint", GLITTER_TINT)
	_glitter_material.set_shader_parameter("brightness", GLITTER_BRIGHTNESS)
	_glitter_material.set_shader_parameter("height_range", Vector2(GLITTER_Y_TM, GLITTER_Y_TM))
	_glitter = MultiMeshInstance3D.new()
	_glitter.name = "Glitter"
	_glitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glitter.material_override = _glitter_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = OlderHaze.quad()
	mm.instance_count = GLITTER_COUNT
	for i in GLITTER_COUNT:
		mm.set_instance_custom_data(i, Color(glitter_phase(i), 0.0, 0.0, 0.0))
	_glitter.multimesh = mm
	add_child(_glitter)
	_caption = Label3D.new()
	_caption.name = "Caption"
	_caption.text = str(cradle.pool_ring.get("caption", ""))
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.no_depth_test = true
	_caption.font_size = FeedbackFx.FONT_SIZE
	_caption.pixel_size = FeedbackFx.PIXEL_SIZE
	_caption.outline_size = FeedbackFx.OUTLINE_SIZE
	_caption.modulate = CAPTION_COLOR
	_caption.outline_modulate = FeedbackFx.OUTLINE_COLOR
	_caption.render_priority = CreatureView.LANE_PRIORITY - 1
	_caption.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_caption.visible = false
	add_child(_caption)
	_apply_fade()


func attach(world: WorldStream) -> void:
	_world = world


## Lays the cradle out for size `n`: shown from band 1 only. Inside a growth's beat the pieces ease
## to it from where the growth left them (beat_frame), or, on a band-up, fade in where they belong.
func set_size(n: int) -> void:
	size = n
	visible = cradle != null and _world != null and WorldConfig.band_of(n) >= 1
	if not visible:
		_shown = {}
		_from = {}
		return
	_to = layout(n)
	if _beat and not _from.is_empty():
		return
	if _beat:
		_fading = true
		_fade = 0.0
		_apply_fade()
	_show(_to)


## Where every piece goes at size `n` in this node's frame now: {ring: Transform3D, caption:
## Transform3D, glitter: Array[Transform3D], dish: {asset: Array[Transform3D]}}.
func layout(n: int) -> Dictionary:
	var center := _world.local_of_abs(0.0, 0.0)
	var b := WorldConfig.bu_to_tm(n)
	var s := float(cradle.pool_ring.radius_bu) / _record_r * b
	var out := {"ring": Transform3D(Basis.from_scale(Vector3.ONE * s), WorldSpace.to_frame(self, center, RING_TOP_TM - _ring_top * s))}
	var g := float(cradle.pool_ring.glitter_radius_bu)
	out.caption = Transform3D(Basis.IDENTITY, WorldSpace.to_frame(self, center + Vector2(0.0, -(g + CAPTION_GAP_BU) * b), CAPTION_Y_TM))
	var glitter: Array[Transform3D] = []
	var side := Basis.from_scale(Vector3.ONE * GLITTER_SIDE_TM)
	for i in GLITTER_COUNT:
		var a := glitter_angle(i)
		glitter.append(Transform3D(side, WorldSpace.to_frame(self, center + Vector2(cos(a), sin(a)) * g * b, GLITTER_Y_TM)))
	out.glitter = glitter
	var dish := {}
	var to_tm := 1.0 / WorldConfig.tm_to_am(n)
	for asset: String in _dish_pieces:
		var top := ((_dish[asset] as MultiMeshInstance3D).multimesh.mesh as Mesh).get_aabb().end.y
		var list: Array[Transform3D] = []
		for p: Dictionary in _dish_pieces[asset]:
			var ps := float(p.scale) * to_tm
			var local := _world.local_of_abs(float(p.x_bu), float(p.y_bu))
			list.append(Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.yaw_deg))) * Basis.from_scale(Vector3.ONE * ps),
				WorldSpace.to_frame(self, local, DISH_TOP_TM - top * ps)))
		dish[asset] = list
	out.dish = dish
	return out


## Glitter item `i`'s angle round the ring: evenly spaced, nudged by up to GLITTER_JITTER.
static func glitter_angle(i: int) -> float:
	var u := WorldHash.unit(WorldHash.mix32(WorldHash.hash_ints(PackedInt64Array([i])), 1))
	return i * TAU / GLITTER_COUNT + GLITTER_JITTER * (2.0 * u - 1.0)


## Glitter item `i`'s twinkle phase in [0, 1).
static func glitter_phase(i: int) -> float:
	return WorldHash.unit(WorldHash.mix32(WorldHash.hash_ints(PackedInt64Array([i])), 2))


## The caption's alpha for the focus at absolute `focus_am`, `tm_to_am` am a tm: full within
## CAPTION_RANGE_TM - CAPTION_FADE_TM of home, none beyond CAPTION_RANGE_TM; times the band-up fade.
func update_caption(focus_am: PackedFloat64Array, tm_to_am: float) -> void:
	var d := Vector2(focus_am[0], focus_am[1]).length() / tm_to_am
	_caption_alpha = clampf((CAPTION_RANGE_TM - d) / CAPTION_FADE_TM, 0.0, 1.0)
	_apply_caption()


## The ring's uniform scale now.
func ring_scale() -> float:
	return _ring.transform.basis.get_scale().x if _ring != null else 0.0


func ring() -> Node3D:
	return _ring


func caption() -> Label3D:
	return _caption


func glitter() -> MultiMeshInstance3D:
	return _glitter


## The dish's MultiMeshes by asset (tests).
func dish() -> Dictionary:
	return _dish


## Each dish piece drawn now: {id, asset, piece, transform} in this node's frame (tests; the
## headless renderer keeps no MultiMesh instance data to read back).
func dish_instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _shown.is_empty():
		return out
	for asset: String in _dish_pieces:
		var pieces: Array = _dish_pieces[asset]
		var list: Array = _shown.dish[asset]
		for i in pieces.size():
			out.append({"id": str(pieces[i].id), "asset": asset, "piece": pieces[i], "transform": list[i]})
	return out


## The glitter's transforms drawn now, in this node's frame (tests).
func glitter_transforms() -> Array:
	return [] if _shown.is_empty() else _shown.glitter


## The old-pool pieces outside the seam ring (drawn all the same).
func outside_pieces() -> PackedStringArray:
	return _outside


## The share of the band-up fade-in shown (1 outside one).
func fade() -> float:
	return _fade


## Every surface of every MeshInstance3D under `root` gets its own copy of its material with the
## albedo dimmed by `dim` in linear light (alpha kept).
static func dim_materials(root: Node, dim: float) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m == null:
				continue
			var d := m.duplicate() as BaseMaterial3D
			var lin := m.albedo_color.srgb_to_linear()
			d.albedo_color = Color(lin.r * dim, lin.g * dim, lin.b * dim, lin.a).linear_to_srgb()
			d.albedo_color.a = m.albedo_color.a
			mi.set_surface_override_material(i, d)


## The merged AABB of every MeshInstance3D under `root`, in `root`'s frame.
static func aabb_under(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := OldBandLayer._under(root, mi) * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## What the start fade draws once so the glitter's shader is ready: one sprite in its material.
static func warm_up_meshes() -> Array[Mesh]:
	var sprite := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = GLITTER_SHADER
	m.set_shader_parameter("image", load(GLITTER_IMAGE) as Texture2D)
	sprite.material = m
	return [sprite] as Array[Mesh]


# --- the container contract ---

## Moves every piece by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	var shift := position
	position = Vector3.ZERO
	_shown = _moved(_shown, func(t: Transform3D) -> Transform3D: return Transform3D(t.basis, t.origin + shift))
	_to = _moved(_to, func(t: Transform3D) -> Transform3D: return Transform3D(t.basis, t.origin + shift))
	_from = _moved(_from, func(t: Transform3D) -> Transform3D: return Transform3D(t.basis, t.origin + shift))
	_show(_shown)


## A growth: what is shown re-expressed in place round `center_old` by 1 / `factor`, this node back
## at the origin; a beat opens (set_size then gives the layout to ease to).
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	_beat = true
	if _shown.is_empty():
		_from = {}
		return
	_from = _moved(_shown, func(t: Transform3D) -> Transform3D:
		return Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor)))
	_to = _from
	_show(_from)


## The cradle is not made of chunks: nothing retires.
func retire_chunk(_chunk: Vector2i) -> void:
	pass


func settle_growth() -> void:
	pass


## Each beat frame: the pieces ease from the growth's frame 0 to the size's layout; a band-up fades
## the cradle in over FADE_IN.
func beat_frame(t: float, _k: float) -> void:
	if not _beat:
		return
	if not _from.is_empty() and not _to.is_empty():
		_show(_lerp(_from, _to, GrowthBeat.ease_in_out_cubic(clampf(t / GrowthBeat.BEAT_S, 0.0, 1.0))))
	if _fading:
		_fade = clampf((t - FADE_IN.x) / (FADE_IN.y - FADE_IN.x), 0.0, 1.0)
		_apply_fade()


## The beat is over (or cancelled): the size's layout, fully shown.
func end_growth() -> void:
	if not _beat:
		return
	_beat = false
	_from = {}
	_fading = false
	_fade = 1.0
	_apply_fade()
	if visible and not _to.is_empty():
		_show(_to)


# --- drawing ---

func _show(l: Dictionary) -> void:
	_shown = l
	if l.is_empty():
		return
	if _ring != null:
		_ring.transform = l.ring
	_caption.transform = l.caption
	var mm := _glitter.multimesh
	for i in GLITTER_COUNT:
		mm.set_instance_transform(i, (l.glitter as Array)[i])
	for asset: String in l.dish:
		var list: Array = l.dish[asset]
		var dmm := (_dish[asset] as MultiMeshInstance3D).multimesh
		dmm.instance_count = list.size()
		for i in list.size():
			dmm.set_instance_transform(i, list[i])


func _apply_fade() -> void:
	if _ring != null:
		for n: Node in _ring.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).transparency = 1.0 - _fade
	for asset: String in _dish:
		(_dish[asset] as GeometryInstance3D).transparency = 1.0 - _fade
	_glitter_material.set_shader_parameter("opacity", GLITTER_OPACITY * _fade)
	_apply_caption()


func _apply_caption() -> void:
	if _caption == null:
		return
	var a := _caption_alpha * _fade
	_caption.modulate.a = a
	_caption.outline_modulate.a = FeedbackFx.OUTLINE_COLOR.a * a
	_caption.visible = a > 0.0


static func _moved(l: Dictionary, f: Callable) -> Dictionary:
	if l.is_empty():
		return {}
	var glitter: Array[Transform3D] = []
	for t: Transform3D in l.glitter:
		glitter.append(f.call(t))
	var dish := {}
	for asset: String in l.dish:
		var list: Array[Transform3D] = []
		for t: Transform3D in l.dish[asset]:
			list.append(f.call(t))
		dish[asset] = list
	return {"ring": f.call(l.ring), "caption": f.call(l.caption), "glitter": glitter, "dish": dish}


static func _lerp(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var glitter: Array[Transform3D] = []
	for i in (a.glitter as Array).size():
		glitter.append((a.glitter[i] as Transform3D).interpolate_with(b.glitter[i], u))
	var dish := {}
	for asset: String in a.dish:
		var list: Array[Transform3D] = []
		for i in (a.dish[asset] as Array).size():
			list.append((a.dish[asset][i] as Transform3D).interpolate_with(b.dish[asset][i], u))
		dish[asset] = list
	return {"ring": (a.ring as Transform3D).interpolate_with(b.ring, u), "caption": (a.caption as Transform3D).interpolate_with(b.caption, u),
		"glitter": glitter, "dish": dish}
