class_name OldBandLayer
extends Node3D
## The old band below (S3, docs/s3/s3-view.md section 5, V3-3 to V3-5, V3-21; D-110): from band 1 on,
## the landmarks and rare set pieces of the band before lie sunk under the swim plane at their true
## size, dim and grey, so the sea the cell outgrew stays where it was. It is a view only: the sim
## never names it (S3G28), and it reads the world through its own WorldGen, built from the same
## content and seed.
##
## Each model of an old band (6 landmarks and 2 rare kinds in band 0) is baked once a run into one
## surface (bake_mesh: the root mesh's surfaces, no Growth_ nodes, vertex colours old_color of each
## surface's albedo) with one material, and drawn as one MultiMesh named after the model: at most
## MAX_DRAW_CALLS draw calls. A piece of band b sits at absolute am (x_bu, y_bu) x band_factor^b,
## turned by its yaw (and mirror), at uniform scale piece scale x band_factor^b / 1.6^(n - 1), its
## top at top_target_tm of its drawn height (V3-5). refresh() places the pieces of every landmark
## cell and rare block touching the view rect (VIEW_HALF_TM round the focus) plus one cell, at most
## MAX_INSTANCES per model nearest the focus first, and rewrites only the MultiMeshes whose sets
## changed. tick() refreshes every REFRESH_S outside a growth beat.
##
## A growth keeps the container contract (s2-view 4.5): apply_growth re-expresses every instance in
## place; a set_band during the beat sets new targets, and beat_frame eases each instance's y from
## where it was to its target over the beat (V3-7); end_growth snaps and refreshes. WorldSpace shifts
## this node across a rebase, so instances are placed in its frame. The MultiMesh draws no
## per-instance mirror, so the baked materials draw both sides (the mirrored rare pieces).

const SINK_TM := Vector2(-3.0, -2.0)                ## the top's depth range (V3-5)
const MAX_DRAW_CALLS := 8
const DESATURATE := 0.65
const OLD_LUMA := 0.30                              ## the baked colours' luma cap (linear)
const REFRESH_S := 0.5
const VIEW_HALF_TM := 56.0                          ## rings_tm.load: the refresh rect's half-size
const HANDOFF_SINK_S := 1.4                         ## the hand-off's sink, ease in-out (T5.2)
const FADE := Vector2(1.4, 2.0)                     ## MMIs in, hand-off pieces out (T5.2)
const MAX_INSTANCES := 32                           ## per model
const MAX_PIECES_KEPT := 4096                       ## pieces kept between refreshes (pure, so memoised)

## The band drawn for (its band - 1 is drawn) and the size.
var band := 0
var size := 1
var kit: PlacementKit
## Where the view is now (absolute am): the pool sets it each frame; tick() refreshes round it.
var focus_am := PackedFloat64Array([0.0, 0.0])

var _gen: WorldGen
var _world: WorldStream
var _mmis := {}                      ## model id -> MultiMeshInstance3D named <model>
var _drawn := {}                     ## model id -> Array of instances {id, model, abs_am, transform, color}
var _ids := {}                       ## model id -> PackedStringArray of the ids written
var _from := {}                      ## id -> the y an instance eases from during a beat
var _beat := false
var _last_refresh_t := -INF
var _handoff: Node3D
var _models := {}                    ## band -> models(band)
var _pieces := {}                    ## Vector3i(band, x, y) -> landmark_piece, Vector3i(-1 - band, x, y) -> rare_piece
var _tints := {}                     ## "model|dressing" -> the instance colour
## Scene path -> its baked ArrayMesh (one surface, its material set), kept for the run.
static var _baked := {}


func _init() -> void:
	name = "OldBand"
	_handoff = Node3D.new()
	_handoff.name = "Handoff"
	add_child(_handoff)


## The world's content, species and seed (its own WorldGen, D-110) and the kit's models. Nothing is
## drawn until attach and set_band, nor ever for content without tiles (a test's fixture world).
func setup(content: WorldContent, species: SpeciesCatalog, world_seed: int, p_kit: PlacementKit) -> void:
	_gen = WorldGen.create(content, species, world_seed) if content != null and content.tiles != null else null
	kit = p_kit
	_models.clear()
	_pieces.clear()
	_tints.clear()


## The live frame: local_of_abs places the pieces (read only).
func attach(world: WorldStream) -> void:
	_world = world


## Draws band - 1's pieces at `p_size` (band 0 draws nothing); the models of that band not baked yet
## bake now. During a growth beat the instances already drawn ease to their new places (V3-7).
func set_band(p_band: int, p_size: int) -> void:
	band = p_band
	size = p_size
	_ids.clear()
	var old := band - 1
	if old < 0 or _gen == null or _world == null or kit == null:
		_clear_drawn()
		return
	for model in models(old):
		_mesh_of(model)
	refresh(view_rect(focus_am, size))


## Places the old band's pieces of every landmark cell and rare block touching `view_rect_am` plus
## one landmark cell (V3-4), at most MAX_INSTANCES per model nearest its centre.
func refresh(view_rect_am: Rect2) -> void:
	var old := band - 1
	if old < 0 or _gen == null or _world == null or kit == null:
		_clear_drawn()
		return
	var f := band_factor(old)
	var rect_bu := Rect2(view_rect_am.position / f, view_rect_am.size / f)
	var tile := WorldConfig.TILE_BU
	var pieces: Array[Dictionary] = []
	if _pieces.size() > MAX_PIECES_KEPT:
		_pieces.clear()
	for c in WorldGen.landmark_cells_touching(rect_bu.grow(WorldConfig.LANDMARK_CELL_TILES * tile), WorldConfig.LANDMARK_CELL_TILES, tile):
		var key := Vector3i(old, c.x, c.y)
		if not _pieces.has(key):
			_pieces[key] = _gen.landmark_piece(old, c.x, c.y)
		if not _pieces[key].is_empty():
			pieces.append(_pieces[key])
	for b in WorldGen.rare_blocks_touching(rect_bu.grow(WorldConfig.RARE_BLOCK_TILES * tile), WorldConfig.RARE_BLOCK_TILES,
			WorldConfig.RARE_BLOCK_FIRST_TILE, tile):
		var key := Vector3i(-1 - old, b.x, b.y)
		if not _pieces.has(key):
			_pieces[key] = _gen.rare_piece(old, b.x, b.y)
		if not _pieces[key].is_empty():
			pieces.append(_pieces[key])
	var centre := view_rect_am.get_center()
	var by_model := {}
	for p in pieces:
		var inst := _instance_of(p, old, f)
		if inst.is_empty():
			continue
		inst["d"] = Vector2(inst.abs_am[0] - centre.x, inst.abs_am[1] - centre.y).length_squared()
		if not by_model.has(inst.model):
			by_model[inst.model] = []
		by_model[inst.model].append(inst)
	var wanted := models(old)
	for model in wanted:
		var list: Array = by_model.get(model, [])
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d or (a.d == b.d and a.id < b.id))
		if list.size() > MAX_INSTANCES:
			list.resize(MAX_INSTANCES)
		_write(model, list)
	for model in _mmis:
		if not wanted.has(model):
			_write(model, [])


## The view rect round `p_focus_am` at size `n`: VIEW_HALF_TM each way, in am.
static func view_rect(p_focus_am: PackedFloat64Array, n: int) -> Rect2:
	var h := VIEW_HALF_TM * WorldConfig.tm_to_am(n)
	return Rect2(p_focus_am[0] - h, p_focus_am[1] - h, 2.0 * h, 2.0 * h)


## band_factor^b, by multiplication (as WorldConfig.tm_to_am).
static func band_factor(b: int) -> float:
	var k := 1.0
	for i in b:
		k *= WorldConfig.BAND_FACTOR
	return k


## Draw calls now: the surfaces of the visible MultiMeshes that have instances.
func draw_calls() -> int:
	var n := 0
	for model in _mmis:
		var mmi: MultiMeshInstance3D = _mmis[model]
		if mmi.visible and mmi.multimesh.instance_count > 0:
			n += mmi.multimesh.mesh.get_surface_count()
	return n


## The drawn instances, for tests: {id, model, abs_am, transform} (the target transform, in this
## node's frame).
func instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for model in _drawn:
		for inst: Dictionary in _drawn[model]:
			out.append({"id": inst.id, "model": inst.model, "abs_am": inst.abs_am, "transform": inst.transform, "color": inst.color})
	return out


## The MultiMesh of `model`, or null before it is first drawn (tests).
func multimesh_of(model: String) -> MultiMeshInstance3D:
	return _mmis.get(model)


## True when every model of every old band is baked.
func ready_to_draw() -> bool:
	if kit == null:
		return false
	for b in old_bands():
		for model in models(b):
			if not _baked.has(_path_of(model)):
				return false
	return true


## The kit's bands that can lie under another: every band but the last.
func old_bands() -> PackedInt32Array:
	var all := kit.bands() if kit != null else PackedInt32Array()
	return all.slice(0, maxi(all.size() - 1, 0))


## The landmark models and rare kinds of band `b`, sorted by id.
func models(b: int) -> PackedStringArray:
	if _models.has(b):
		return _models[b]
	var out := PackedStringArray()
	if kit == null:
		return out
	var ids := kit.assets.keys()
	ids.sort()
	for id: String in ids:
		var a: Dictionary = kit.assets[id]
		if str(a.get("kind", "")) in ["landmark", "rare"] and int(a.get("band", -1)) == b and not str(a.get("glb", "")).is_empty():
			out.append(id)
	_models[b] = out
	return out


## Bakes one model not baked yet, if any (one a frame from tick, so a start at band 0 never waits).
func bake_next() -> bool:
	for b in old_bands():
		for model in models(b):
			if not _baked.has(_path_of(model)):
				_mesh_of(model)
				return true
	return false


## Each frame (the pool's _process): one model baked while any is not, and a refresh every
## REFRESH_S outside a growth beat.
func tick(draw_time_s: float) -> void:
	bake_next()
	if _beat or band < 1:
		return
	if draw_time_s - _last_refresh_t >= REFRESH_S or draw_time_s < _last_refresh_t:
		_last_refresh_t = draw_time_s
		refresh(view_rect(focus_am, size))


## A piece's top depth for a drawn height `h_tm` (V3-5): -2 for pieces up to 1 tm, down to -3 from
## 3 tm.
static func top_target_tm(h_tm: float) -> float:
	return -2.0 - clampf((h_tm - 1.0) / 2.0, 0.0, 1.0)


## `c` as the old band draws it (V3-3), in linear light: desaturated `desaturate` toward its own
## luma, then scaled down to luma `luma` when above it. sRGB in, sRGB out; alpha kept.
static func old_color(c: Color, desaturate := DESATURATE, luma := OLD_LUMA) -> Color:
	var lin := c.srgb_to_linear()
	var y := luma_of(lin)
	var d := Color(lerpf(lin.r, y, desaturate), lerpf(lin.g, y, desaturate), lerpf(lin.b, y, desaturate), c.a)
	var yd := luma_of(d)
	if yd > luma and yd > 0.0:
		var k := luma / yd
		d = Color(d.r * k, d.g * k, d.b * k, c.a)
	return d.linear_to_srgb()


## Rec. 709 luma of a linear colour.
static func luma_of(lin: Color) -> float:
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


## One surface of `scene` (V3-3): every MeshInstance3D not named Growth_*, each vertex placed by the
## mesh's transform under the scene root, normals by its basis, UV kept and COLOR the old_color of
## its surface's albedo (rounded down to 8 bits a channel), in one material: opaque, vertex colour as albedo (sRGB), the root mesh's
## albedo texture (the model's greyscale detail), rough, drawn both sides.
static func bake_mesh(scene: PackedScene, desaturate := DESATURATE, luma := OLD_LUMA) -> ArrayMesh:
	var root := scene.instantiate() as Node3D
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var texture: Texture2D = null
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if str(mi.name).begins_with(LandmarkLayer.GROWTH_PREFIX) or mi.mesh == null:
			continue
		var xf := _under(root, mi)
		var nb := xf.basis.inverse().transposed()
		for i in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mi.mesh.surface_get_arrays(i)
			var mat := mi.get_active_material(i)
			var albedo := Color.WHITE
			if mat is BaseMaterial3D:
				albedo = (mat as BaseMaterial3D).albedo_color
				if texture == null:
					texture = (mat as BaseMaterial3D).albedo_texture
			# The mesh stores 8 bits a channel: rounded down, the stored colour keeps under the cap.
			var c := old_color(albedo, desaturate, luma)
			var col := Color(floorf(c.r * 255.0) / 255.0, floorf(c.g * 255.0) / 255.0, floorf(c.b * 255.0) / 255.0, 1.0)
			var base := verts.size()
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			for k in v.size():
				verts.append(xf * v[k])
				normals.append((nb * nn[k]).normalized() if k < nn.size() else Vector3.UP)
				uvs.append(uv[k] if k < uv.size() else Vector2.ZERO)
				colors.append(col)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if not idx.is_empty():
				for k in idx:
					indices.append(base + k)
			else:
				for k in v.size():
					indices.append(base + k)
	root.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material(texture))
	return mesh


## The old band's material on `texture` (V3-3).
static func material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = texture
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## What the start fade draws once so the old band's shader is ready: its material (with a texture,
## as every baked one has) on a probe quad.
static func warm_up_meshes() -> Array[Mesh]:
	var probe := QuadMesh.new()
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	probe.material = material(ImageTexture.create_from_image(image))
	return [probe] as Array[Mesh]


# --- the container contract ---

## Moves every instance by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for model in _drawn:
		for inst: Dictionary in _drawn[model]:
			var t: Transform3D = inst.transform
			inst.transform = Transform3D(t.basis, t.origin + position)
		_rewrite(model)
	for id in _from:
		_from[id] += position.y
	for piece in _handoff.get_children():
		(piece as Node3D).position += position
	position = Vector3.ZERO


## A growth: every instance re-expressed in place round `center_old` by 1 / `factor`, this node back
## at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	for model in _drawn:
		for inst: Dictionary in _drawn[model]:
			var t: Transform3D = inst.transform
			inst.transform = Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor))
		_rewrite(model)
	_from.clear()
	_beat = true


## The old band is not made of chunks: nothing retires.
func retire_chunk(_chunk: Vector2i) -> void:
	pass


func settle_growth() -> void:
	pass


## Each beat frame: every instance that was drawn before the growth eases its y to its target.
func beat_frame(t: float, _k: float) -> void:
	if _from.is_empty():
		return
	var u := GrowthBeat.ease_in_out_cubic(clampf(t / GrowthBeat.BEAT_S, 0.0, 1.0))
	for model in _drawn:
		var list: Array = _drawn[model]
		var mm := (_mmis[model] as MultiMeshInstance3D).multimesh
		for i in list.size():
			var inst: Dictionary = list[i]
			if _from.has(inst.id):
				var t0: Transform3D = inst.transform
				mm.set_instance_transform(i, Transform3D(t0.basis, Vector3(t0.origin.x, lerpf(float(_from[inst.id]), t0.origin.y, u), t0.origin.z)))


## The beat is over: every instance at its target and the set refreshed.
func end_growth() -> void:
	if not _beat:
		return
	_beat = false
	_from.clear()
	for model in _drawn:
		_rewrite(model)
	if band >= 1:
		refresh(view_rect(focus_am, size))


# --- placing ---

## The instance of piece `p` of old band `old` (f = band_factor(old)) at the size drawn, or {} when its
## model has no mesh.
func _instance_of(p: Dictionary, old: int, f: float) -> Dictionary:
	var rare := p.has("kind")
	var model := str(p.get("asset", "")) if rare else str(p.model)
	if rare and not kit.assets.has(model):
		model = kit.rare_asset(old, str(p.kind))
	var mesh := _mesh_of(model)
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	var am := PackedFloat64Array([float(p.x_bu) * f, float(p.y_bu) * f])
	var local := _world.local_of_abs(am[0], am[1])
	var s := (1.0 if rare else float(p.scale)) * f / WorldConfig.tm_to_am(size)
	var aabb := mesh.get_aabb()
	var y := top_target_tm(aabb.size.y * s) - aabb.end.y * s
	var turn := LandmarkLayer.place_basis(float(p.yaw_deg), bool(p.get("mirror", false))) if rare \
		else Basis(Vector3.UP, deg_to_rad(float(p.yaw_deg)))
	var color := Color.WHITE if rare else _tint(model, str(p.dressing))
	return {"id": str(p.id), "model": model, "abs_am": am, "color": color,
		"transform": Transform3D(turn * Basis.from_scale(Vector3.ONE * s), WorldSpace.to_frame(self, local, y))}


## The instance colour of `model`'s dressing `id`: the old colour of its tint.
func _tint(model: String, id: String) -> Color:
	var key := model + "|" + id
	if not _tints.has(key):
		var tint := "#FFFFFF"
		for d: Dictionary in kit.assets.get(model, {}).get("dressings", []):
			if str(d.id) == id:
				tint = str(d.get("tint", tint))
		_tints[key] = old_color(Color(tint))
	return _tints[key]


## Draws `list` as `model`'s instances. The MultiMesh is rewritten only when its ids changed; during
## a beat an instance drawn before keeps its place and eases from it (beat_frame).
func _write(model: String, list: Array) -> void:
	var ids := PackedStringArray()
	for inst: Dictionary in list:
		ids.append(inst.id)
	if _beat:
		for inst: Dictionary in _drawn.get(model, []):
			if ids.has(inst.id) and not _from.has(inst.id):
				_from[inst.id] = (inst.transform as Transform3D).origin.y
	_drawn[model] = list
	if _ids.has(model) and _ids[model] == ids and not _beat:
		return
	_ids[model] = ids
	_rewrite(model)


## Writes `model`'s drawn instances into its MultiMesh (made on first use), each at its target, or at
## its eased-from y while a beat runs.
func _rewrite(model: String) -> void:
	var list: Array = _drawn.get(model, [])
	if not _mmis.has(model):
		if list.is_empty():
			return
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh_of(model)
		mmi.multimesh = mm
		add_child(mmi)
		_mmis[model] = mmi
	var mmi: MultiMeshInstance3D = _mmis[model]
	var mm := mmi.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		var inst: Dictionary = list[i]
		var t: Transform3D = inst.transform
		if _beat and _from.has(inst.id):
			t.origin.y = float(_from[inst.id])
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, inst.color)
	mmi.visible = not list.is_empty()


func _clear_drawn() -> void:
	for model in _mmis:
		_drawn[model] = []
		_ids.erase(model)
		_rewrite(model)
	_drawn.clear()
	_from.clear()


## `model`'s baked mesh, baked now when it is not yet (null without a GLB).
func _mesh_of(model: String) -> ArrayMesh:
	var path := _path_of(model)
	if path.is_empty():
		return null
	if not _baked.has(path):
		var scene := LandmarkLayer._scene(path)
		_baked[path] = bake_mesh(scene) if scene != null else null
	return _baked[path]


func _path_of(model: String) -> String:
	return str(kit.assets.get(model, {}).get("glb", "")) if kit != null else ""


## `node`'s transform under `root` (the parents' transforms composed, the root's own left out).
static func _under(root: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
