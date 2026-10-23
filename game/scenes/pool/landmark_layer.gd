class_name LandmarkLayer
extends Node3D
## The endless sea's landmarks and rare set pieces on screen (S1; docs/s1/s1-content.md 6.5 and
## docs/s1/s1-build-plan.md B-15, B-30): each anchor's Blender piece at its landmark collider, with
## the collider's yaw and scale, its dressing's tint and growth from the kit; each rare place's
## piece, mirrored then turned by its orientation, so every kit collider lands where WorldGen put
## it. Pieces come and go by chunk (add_chunk on chunk_loaded, remove_chunk on chunk_unloaded). The
## pool's WorldSpace shifts this node across a rebase, so pieces are placed in its frame.

## Growth nodes in a landmark piece are named Growth_<Name>; a dressing shows at most one.
const GROWTH_PREFIX := "Growth_"

var kit: PlacementKit

var _scenes := {}         ## asset -> PackedScene, or null when there is no GLB
var _materials := {}      ## "asset|tint|surface" -> the tinted copy of that surface's material
var _by_key := {}         ## chunk key -> Array[Node3D]
var _order: Array[Node3D] = []


## The kit gives the dressings' tints and growth nodes and the rare pieces' assets.
func setup(p_kit: PlacementKit) -> void:
	clear()
	kit = p_kit


## Frees every piece.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_by_key.clear()
	_order.clear()


## Draws the chunk's anchors (each with its "landmark" collider shell: a chunk holds at most one)
## and rare places. An anchor or place whose piece has no GLB is reported and skipped.
func add_chunk(key: Vector2i, landmark_shells: Array, anchors: Array, places: Array) -> void:
	var made: Array[Node3D] = _by_key.get(key, [] as Array[Node3D])
	for a: Dictionary in anchors:
		var shell := _shell_for(a, landmark_shells)
		var model := str(a.model)
		var piece := _instance(model)
		if piece == null:
			continue
		piece.name = str(a.id)
		var at: Vector2 = shell.position if not shell.is_empty() else a.position
		var basis := Basis(Vector3.UP, deg_to_rad(float(shell.get("yaw_deg", 0.0)))) * Basis.from_scale(Vector3.ONE * float(shell.get("scale", 1.0)))
		piece.transform = Transform3D(basis, WorldSpace.to_frame(self, at))
		_dress(piece, model, dressing_of(model, str(a.dressing)))
		_add(piece, made)
	for p: Dictionary in places:
		var asset := kit.rare_asset(0, str(p.kind)) if kit != null else ""
		var piece := _instance(asset)
		if piece == null:
			continue
		piece.name = str(p.id)
		piece.transform = Transform3D(place_basis(float(p.get("yaw_deg", 0.0)), bool(p.get("mirror", false))), WorldSpace.to_frame(self, p.position))
		_add(piece, made)
	_by_key[key] = made


## Frees the chunk's pieces; an unknown key changes nothing.
func remove_chunk(key: Vector2i) -> void:
	for piece: Node3D in _by_key.get(key, []):
		_order.erase(piece)
		remove_child(piece)
		piece.queue_free()
	_by_key.erase(key)


## Moves every piece by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for piece in _order:
		piece.position += position
	position = Vector3.ZERO


## The pieces drawn now, anchors and places, in add order.
func pieces() -> Array[Node3D]:
	return _order.duplicate()


## A rare place's turn: mirrored in x first when `mirror`, then turned by `yaw_deg` about up, as
## WorldGen.orient_point moves a kit collider (a quarter step (x, y) -> (-y, x) is a yaw of -90).
static func place_basis(yaw_deg: float, mirror: bool) -> Basis:
	var turn := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	return turn * Basis.from_scale(Vector3(-1.0, 1.0, 1.0)) if mirror else turn


## The kit's dressing `id` of `model` ({id, tint, growth, scale}); plain white with no growth when
## the kit does not list it.
func dressing_of(model: String, id: String) -> Dictionary:
	var asset: Dictionary = kit.assets.get(model, {}) if kit != null else {}
	for d: Dictionary in asset.get("dressings", []):
		if str(d.id) == id:
			return d
	return {"id": id, "tint": "#FFFFFF", "growth": "", "scale": 1.0}


## The landmark collider shell paired with anchor `a`: the nearest one (a chunk has at most one).
static func _shell_for(a: Dictionary, shells: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for s: Dictionary in shells:
		var d := Vector2(s.position).distance_squared_to(a.position)
		if d < best_d:
			best_d = d
			best = s
	return best


## A fresh instance of `asset`'s GLB scene, or null (reported) when it has none.
func _instance(asset: String) -> Node3D:
	if not _scenes.has(asset):
		var path := str(kit.assets[asset].glb) if kit != null and kit.assets.has(asset) else RockField.ASSET_PATH % asset
		_scenes[asset] = load(path) if asset != "" and ResourceLoader.exists(path) else null
	if _scenes[asset] == null:
		push_error("The endless sea has no piece for '%s'." % asset)
		return null
	return (_scenes[asset] as PackedScene).instantiate() as Node3D


## The dressing's look on a landmark piece: every Growth_* node hidden but the dressing's growth,
## and the root mesh's surfaces tinted (the linear product of albedo and tint), shared per tint.
func _dress(piece: Node3D, model: String, dressing: Dictionary) -> void:
	var growth := str(dressing.get("growth", ""))
	for n: Node in piece.find_children(GROWTH_PREFIX + "*", "Node3D", true, false):
		(n as Node3D).visible = growth != "" and n.name == growth
	var tint := Color(str(dressing.get("tint", "#FFFFFF")))
	if tint == Color.WHITE:
		return
	var root := _root_mesh(piece)
	if root == null:
		return
	for i in root.mesh.get_surface_count():
		var key := "%s|%s|%d" % [model, tint.to_html(false), i]
		if not _materials.has(key):
			var m := root.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				m = m.duplicate()
				var albedo: Color = (m as BaseMaterial3D).albedo_color
				(m as BaseMaterial3D).albedo_color = Color(albedo.srgb_to_linear() * tint.srgb_to_linear()).linear_to_srgb()
			_materials[key] = m
		root.set_surface_override_material(i, _materials[key])


## The piece's own mesh: the first MeshInstance3D that is not a growth node.
static func _root_mesh(piece: Node3D) -> MeshInstance3D:
	for n: Node in piece.find_children("*", "MeshInstance3D", true, false):
		if not str(n.name).begins_with(GROWTH_PREFIX):
			return n as MeshInstance3D
	return null


func _add(piece: Node3D, made: Array[Node3D]) -> void:
	add_child(piece)
	made.append(piece)
	_order.append(piece)
