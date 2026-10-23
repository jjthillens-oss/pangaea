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

## The kit's own glb pattern (spine 4.4): the layer needs no kit, so pool mode needs no world content.
const ASSET_PATH := "res://assets/export/%s.glb"
## The key the pool's rocks are added under.
const POOL_KEY := &"pool"
## A tint that leaves a piece's colours as they are.
const PLAIN_TINTS: PackedStringArray = ["", "#FFFFFF"]

## asset -> {mesh: Mesh, offset: Transform3D (the mesh node under the GLB root), override: Material,
## tinted: bool}; null for an asset that has no GLB.
var _pieces := {}
## asset -> [{id, key, transform: Transform3D (frame, without the offset), color: Color, radius: float
## (the collider's, tm)}], in add order
var _instances := {}


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


## Adds `shells` (chunk_loaded payload shells: {id, position, asset, yaw_deg, scale, tint}) under
## `key`. A piece without a GLB is reported and skipped.
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
		if not _instances.has(asset):
			_instances[asset] = []
		_instances[asset].append({"id": str(s.id), "key": key, "transform": Transform3D(basis, WorldSpace.to_frame(self, s.position)),
			"color": color, "radius": float(s.get("radius", 0.0))})
		touched[asset] = true
	for asset in touched:
		_write(asset)


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
	for asset in _instances:
		for e: Dictionary in _instances[asset]:
			e.transform.origin += shift
		_write(asset)


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


## Rewrites `asset`'s MultiMesh from its list: the count, then each transform (with the mesh's own
## offset under its GLB root) and colour, and a culling box round every instance's mesh.
func _write(asset: String) -> void:
	var list: Array = _instances.get(asset, [])
	var mmi := multimesh_of(asset)
	if list.is_empty():
		_instances.erase(asset)
		if mmi != null:
			remove_child(mmi)
			mmi.queue_free()
		return
	var piece: Dictionary = _pieces[asset]
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = asset
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
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, list[i].color)
		box = t * local_box if i == 0 else box.merge(t * local_box)
	mmi.custom_aabb = box


## The cached piece of `asset`, loaded from its GLB on first use; null when there is none.
func _piece(asset: String) -> Variant:
	if _pieces.has(asset):
		return _pieces[asset]
	var path := ASSET_PATH % asset
	var piece: Variant = null
	if ResourceLoader.exists(path):
		var root: Node3D = (load(path) as PackedScene).instantiate()
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
