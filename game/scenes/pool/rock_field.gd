class_name RockField
extends Node3D
## The pool's rocks and the endless sea's shells on screen (M1 step 2; S1, docs/s1/s1-content.md
## 6.4): every shell drawn from its Blender piece at its center on the swim plane, with its yaw,
## uniform scale and tint. The circles the cell bumps into are the arena's, of the same centers;
## this node only draws them.
##
## One MultiMeshInstance3D per piece in use, named after it, holds every instance of that piece, so
## the draws stay at one per piece however many chunks are loaded (G17). Shells come and go by key:
## the pool's rocks under POOL_KEY, the endless sea's by chunk (add_chunk on chunk_loaded,
## remove_chunk on chunk_unloaded). The pool's WorldSpace shifts this node across a rebase, so
## instances are placed in its frame (WorldSpace.to_frame).
##
## A growth (S2, s2-view 4.5, the growth-container contract): apply_growth re-expresses every
## instance in place and keeps this node at position 0 and scale 1. The tick's unloaded chunks retire
## (retire_chunk): their shells keep drawing from `<asset>__retiring`, and a shell the tick loads
## again with the same id is adopted back, so it never blinks. Shells first seen during the beat draw
## from `<asset>__fresh` and come in from the veil over PREBLUR_S; once the tick has settled, the
## leftovers sink SINK_TM and fade over RETIRE_S. end_growth frees the leftovers and merges the fresh.
##
## In the sea the kit's shell pieces load at setup (load_pieces), so a shell first seen at a growth
## does not load its GLB in the growth's frame (S2G26). Each GLB loads once a run.

## The kit's own glb pattern (spine 4.4): the layer needs no kit, so pool mode needs no world content.
const ASSET_PATH := "res://assets/export/%s.glb"
## The key the pool's rocks are added under.
const POOL_KEY := &"pool"
## A tint that leaves a piece's colours as they are.
const PLAIN_TINTS: PackedStringArray = ["", "#FFFFFF"]

## GLB path -> PackedScene, kept for the run once loaded.
static var _scenes := {}

## asset -> {mesh: Mesh, offset: Transform3D (the mesh node under the GLB root), override: Material,
## tinted: bool}; null for an asset that has no GLB.
var _pieces := {}
## asset -> [{id, key, transform: Transform3D (frame, without the offset), color: Color, radius: float
## (the collider's, tm)}], in add order
var _instances := {}
## A growth: the retiring and fresh instances by asset (same entries), whether a beat is open and
## whether the tick has settled (the beat time it did, -1 before), and the beat time now.
var _retiring := {}
var _fresh := {}
var _beat := false
var _settled_t := -1.0
var _beat_t := 0.0
## The leftovers' sink (tm) and fade (s) this growth (set_retire_profile; S2's unless a band-up).
var _sink_tm := GrowthBeat.SINK_TM
var _retire_s := GrowthBeat.RETIRE_S


## Loads every shell piece of `kit` not loaded yet, as the sea is set up: loading one in a growth's
## frame took 13 to 19 ms, and a growth draws shells the cell has not seen. They are loaded on the
## main thread, not on worker threads: on Windows' software renderer (WARP) the engine stalled for
## minutes as worker-thread loads finished (the CI launch check), so the run's start takes them.
static func load_pieces(kit: PlacementKit) -> void:
	if kit == null:
		return
	for id: String in kit.assets:
		var path := ASSET_PATH % id
		if str(kit.assets[id].get("kind", "")) == "shell" and ResourceLoader.exists(path):
			_scene(path)


## The piece at `path`: kept from an earlier use, or loaded now.
static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]


## Pool mode: the layout's rocks, as shells under POOL_KEY, replacing everything.
func build_pool(layout: PoolLayout) -> void:
	clear()
	var shells := []
	for rock in layout.rocks:
		shells.append({"id": rock.id, "position": rock.center, "radius": rock.radius, "kind": "shell", "asset": rock.asset,
			"yaw_deg": rock.yaw_deg, "scale": rock.scale, "tint": ""})
	add_chunk(POOL_KEY, shells)


## Removes every shell and every MultiMesh.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_instances.clear()
	_retiring.clear()
	_fresh.clear()
	_beat = false
	_settled_t = -1.0


## Adds `shells` (chunk_loaded payload shells: {id, position, asset, yaw_deg, scale, tint}) under
## `key`. A piece without a GLB is reported and skipped.
## During a growth beat a shell retired with the same id is adopted back (the event's pose), and a
## new one is fresh until the tick settles.
func add_chunk(key: Variant, shells: Array) -> void:
	var touched := {}
	for s: Dictionary in shells:
		var asset := str(s.asset)
		var piece: Variant = _piece(asset)
		if piece == null:
			push_error("Shell '%s' uses asset '%s', which has no GLB in assets/export." % [s.get("id", ""), asset])
			continue
		var tint := str(s.get("tint", ""))
		var color := Color.WHITE if tint in PLAIN_TINTS else Color(tint)
		if color != Color.WHITE:
			_tint(asset)
		var basis := Basis(Vector3.UP, deg_to_rad(float(s.get("yaw_deg", 0.0)))) * Basis.from_scale(Vector3.ONE * float(s.get("scale", 1.0)))
		var e := {"id": str(s.id), "key": key, "transform": Transform3D(basis, WorldSpace.to_frame(self, s.position)),
			"color": color, "radius": float(s.get("radius", 0.0))}
		var fresh := false
		if _beat:
			var adopted_from := _take_retiring(e.id)
			if adopted_from != "":
				touched[_retiring_name(adopted_from)] = true
			else:
				fresh = _settled_t < 0.0
		var into := _fresh if fresh else _instances
		if not into.has(asset):
			into[asset] = []
		into[asset].append(e)
		touched[_fresh_name(asset) if fresh else asset] = true
	for name in touched:
		_write(name)


## Removes the shells added under `key`; an unknown key changes nothing.
func remove_chunk(key: Variant) -> void:
	for asset in _instances.keys():
		var list: Array = _instances[asset]
		var kept := list.filter(func(e: Dictionary) -> bool: return e.key != key)
		if kept.size() != list.size():
			_instances[asset] = kept
			_write(asset)


## Moves every instance by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	var shift := position
	position = Vector3.ZERO
	for lists in [_instances, _retiring, _fresh]:
		for asset in lists:
			for e: Dictionary in lists[asset]:
				e.transform.origin += shift
	_write_all()


## A growth (the container contract): every instance re-expressed in place round `center_old` by
## 1 / `factor`, this node back at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	for lists in [_instances, _retiring, _fresh]:
		for asset in lists:
			for e: Dictionary in lists[asset]:
				var t: Transform3D = e.transform
				e.transform = Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor))
				e.radius = float(e.radius) / factor
	_beat = true
	_settled_t = -1.0
	_beat_t = 0.0
	_write_all()


## chunk_unloaded {reason: "growth"}: the chunk's shells keep drawing, retiring, by id.
func retire_chunk(key: Variant) -> void:
	for asset in _instances.keys():
		var list: Array = _instances[asset]
		var going := list.filter(func(e: Dictionary) -> bool: return e.key == key)
		if going.is_empty():
			continue
		_instances[asset] = list.filter(func(e: Dictionary) -> bool: return e.key != key)
		if not _retiring.has(asset):
			_retiring[asset] = []
		_retiring[asset].append_array(going)
		_write(asset)
		_write(_retiring_name(asset))


## grew: the leftovers start to sink and fade from now.
func settle_growth() -> void:
	if _beat:
		_settled_t = _beat_t


## The leftovers' sink and fade for the growth that begins (GrowthBeat.begin, V3-1).
func set_retire_profile(sink_tm: float, retire_s: float) -> void:
	_sink_tm = sink_tm
	_retire_s = retire_s


## Each beat frame: the leftovers sink and fade behind the veil, the fresh come in from it.
func beat_frame(t: float, _k: float) -> void:
	if not _beat:
		return
	_beat_t = t
	var s := GrowthBeat.retire_share(t, _settled_t, _retire_s)
	var p := GrowthBeat.fresh_share(t)
	for asset in _retiring:
		var mmi := multimesh_of(_retiring_name(asset))
		if mmi != null:
			_write(_retiring_name(asset), -_sink_tm * s)
			_veil(mmi, s)
	for asset in _fresh:
		var mmi := multimesh_of(_fresh_name(asset))
		if mmi != null:
			_veil(mmi, 1.0 - p)


## The beat is over: the leftovers go and the fresh shells join the rest.
func end_growth() -> void:
	if not _beat:
		return
	var names := []
	for asset in _retiring:
		names.append(_retiring_name(asset))
	_retiring.clear()
	for asset in _fresh:
		if not _instances.has(asset):
			_instances[asset] = []
		_instances[asset].append_array(_fresh[asset])
		names.append(_fresh_name(asset))
		names.append(asset)
	_fresh.clear()
	_beat = false
	_settled_t = -1.0
	for name in names:
		_write(name)


## The retiring instances of `asset` (tests): [{id, key, transform, color, radius}].
func retiring_of(asset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _retiring.get(asset, []):
		out.append(e)
	return out


## The fresh instances of `asset` (tests).
func fresh_of(asset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _fresh.get(asset, []):
		out.append(e)
	return out


## Takes the retiring shell `id` out of its list: the asset it was in, or "" when none retires.
func _take_retiring(id: String) -> String:
	for asset in _retiring:
		var list: Array = _retiring[asset]
		for i in list.size():
			if list[i].id == id:
				list.remove_at(i)
				return asset
	return ""


func _veil(mmi: MultiMeshInstance3D, amount: float) -> void:
	mmi.transparency = amount
	var m := mmi.material_overlay as ShaderMaterial
	if m == null:
		m = GrowthBeat.preblur(amount)
		mmi.material_overlay = m
	m.set_shader_parameter("amount", amount)


static func _retiring_name(asset: String) -> String:
	return asset + "__retiring"


static func _fresh_name(asset: String) -> String:
	return asset + "__fresh"


func _write_all() -> void:
	for asset in _instances.keys():
		_write(asset)
	for asset in _retiring.keys():
		_write(_retiring_name(asset))
	for asset in _fresh.keys():
		_write(_fresh_name(asset))


## The instances of `asset`, in add order: [{id, key, transform (in this node's frame), color, radius}].
func instances_of(asset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _instances.get(asset, []):
		out.append(e)
	return out


## The MultiMeshInstance3D drawing `asset`, or null when it has no instances.
func multimesh_of(asset: String) -> MultiMeshInstance3D:
	return get_node_or_null(NodePath(asset)) as MultiMeshInstance3D


## The pieces with instances now.
func assets_in_use() -> PackedStringArray:
	var out := PackedStringArray()
	for asset in _instances:
		if not (_instances[asset] as Array).is_empty():
			out.append(asset)
	return out


## Rewrites the MultiMesh `name` (an asset, or its __retiring or __fresh list) from its list: the
## count, then each transform (with the mesh's own offset under its GLB root, dropped by `sink` m)
## and colour, and a culling box round every instance's mesh.
func _write(name: String, sink := 0.0) -> void:
	var lists := _instances
	var asset := name
	if name.ends_with("__retiring"):
		lists = _retiring
		asset = name.trim_suffix("__retiring")
	elif name.ends_with("__fresh"):
		lists = _fresh
		asset = name.trim_suffix("__fresh")
	var list: Array = lists.get(asset, [])
	var mmi := multimesh_of(name)
	if list.is_empty():
		lists.erase(asset)
		if mmi != null:
			remove_child(mmi)
			mmi.queue_free()
		return
	var piece: Dictionary = _pieces[asset]
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = name
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = piece.mesh
		mmi.multimesh = mm
		mmi.material_override = piece.override
		add_child(mmi)
	var mm := mmi.multimesh
	mm.mesh = piece.mesh
	mm.instance_count = list.size()
	var offset: Transform3D = piece.offset
	var local_box: AABB = (piece.mesh as Mesh).get_aabb()
	var box := AABB()
	for i in list.size():
		var t: Transform3D = list[i].transform * offset
		t.origin.y += sink
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, list[i].color)
		box = t * local_box if i == 0 else box.merge(t * local_box)
	mmi.custom_aabb = box


## The cached piece of `asset`, from its GLB on first use (_scene); null when there is none.
func _piece(asset: String) -> Variant:
	if _pieces.has(asset):
		return _pieces[asset]
	var path := ASSET_PATH % asset
	var piece: Variant = null
	if ResourceLoader.exists(path):
		var root: Node3D = _scene(path).instantiate()
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var mi := meshes[0] as MeshInstance3D
			var offset := Transform3D.IDENTITY
			var n: Node = mi
			while n != root:
				offset = (n as Node3D).transform * offset
				n = n.get_parent()
			piece = {"mesh": mi.mesh, "offset": offset, "override": mi.material_override, "tinted": false}
		root.free()
	_pieces[asset] = piece
	return piece


## The first tinted instance of `asset`: its mesh is copied once with each surface material set to
## take the instance colour as albedo (sRGB), so the shader's product is linear(albedo) x
## linear(tint). Plain pieces keep their own materials.
func _tint(asset: String) -> void:
	var piece: Dictionary = _pieces[asset]
	if piece.tinted:
		return
	piece.tinted = true
	var mesh := (piece.mesh as Mesh).duplicate() as Mesh
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m != null:
			m = m.duplicate() as BaseMaterial3D
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			mesh.surface_set_material(i, m)
	piece.mesh = mesh
