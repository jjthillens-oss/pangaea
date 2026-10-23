class_name LandmarkLayer
extends Node3D
## The endless sea's landmarks and rare set pieces on screen (S1; docs/s1/s1-content.md 6.5 and
## docs/s1/s1-build-plan.md B-15, B-30): each anchor's Blender piece at its landmark collider, with
## the collider's yaw and scale, its dressing's tint and growth from the kit; each rare place's
## piece, mirrored then turned by its orientation, so every kit collider lands where WorldGen put
## it. Pieces come and go by chunk (add_chunk on chunk_loaded, remove_chunk on chunk_unloaded). The
## pool's WorldSpace shifts this node across a rebase, so pieces are placed in its frame.
##
## A landmark GLB took 44 to 151 ms to load (headless swim tour), one long frame on the first chunk
## that held it. So setup starts loading every landmark and rare piece of the kit on worker
## threads, and the loaded scenes are kept for the whole run, shared by every layer: a chunk takes
## its piece when it is ready, and waits only if it comes before its load is done.
##
## A growth (S2, s2-view 4.5, the growth-container contract, as RockField): apply_growth re-expresses
## every piece in place; the tick's unloaded chunks retire, their pieces kept by id and adopted back
## when the tick loads the same id again; a piece first seen during the beat is made at most
## FRESH_PER_FRAME a frame (a GLB instance is the costly part) and comes in from the veil over
## PREBLUR_S from when it is made; after the settle the leftovers sink and fade, and end_growth frees
## them.

## Growth nodes in a landmark piece are named Growth_<Name>; a dressing shows at most one.
const GROWTH_PREFIX := "Growth_"
## New pieces made a frame during a growth beat; the rest wait their turn.
const FRESH_PER_FRAME := 2

var kit: PlacementKit

## GLB path -> PackedScene, or null when there is no GLB; kept for the run.
static var _scenes := {}
## GLB paths being loaded on worker threads (ResourceLoader.load_threaded_request), not taken yet.
static var _loading := {}

var _materials := {}      ## "asset|tint|surface" -> the tinted copy of that surface's material
var _by_key := {}         ## chunk key -> Array[Node3D]
var _order: Array[Node3D] = []
## A growth: retiring pieces by id ({piece, y}: y its height when it retired), fresh pieces (piece ->
## the beat time it was made), the pieces still to make ({key, anchor | place, shells}), whether a
## beat is open, the beat time of the settle (-1 before) and the beat time now.
var _retiring := {}
var _fresh := {}
var _pending: Array[Dictionary] = []
var _beat := false
var _settled_t := -1.0
var _beat_t := 0.0


## The kit gives the dressings' tints and growth nodes and the rare pieces' assets.
func setup(p_kit: PlacementKit) -> void:
	clear()
	kit = p_kit
	request_pieces(kit)


## Starts loading the kit's landmark and rare pieces on worker threads, each GLB once a run.
static func request_pieces(p_kit: PlacementKit) -> void:
	if p_kit == null:
		return
	for id in p_kit.assets:
		var asset: Dictionary = p_kit.assets[id]
		var path := str(asset.get("glb", ""))
		if not str(asset.get("kind", "")) in ["landmark", "rare"] or _scenes.has(path) or _loading.has(path):
			continue
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			_loading[path] = true


## Whether `path`'s piece is loaded (for checks; false while it still loads on a worker thread).
static func is_loaded(path: String) -> bool:
	return _scenes.has(path) or (_loading.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED)


func _notification(what: int) -> void:
	# A load still pending when the run ends would leak: take them all as the layer goes (they are
	# kept for the run either way).
	if what == NOTIFICATION_PREDELETE:
		for path in _loading.keys():
			_scene(path)


## Frees every piece.
func clear() -> void:
	for child in get_children():
		_free_piece(child)
	_by_key.clear()
	_order.clear()
	_retiring.clear()
	_fresh.clear()
	_pending.clear()
	_beat = false
	_settled_t = -1.0


## Draws the chunk's anchors (each with its "landmark" collider shell: a chunk holds at most one)
## and rare places. An anchor or place whose piece has no GLB is reported and skipped.
## During a growth beat a piece retired with the same id is adopted back at the event's pose, and a
## new one waits to be made fresh until the tick settles.
func add_chunk(key: Vector2i, landmark_shells: Array, anchors: Array, places: Array) -> void:
	var made: Array[Node3D] = _by_key.get(key, [] as Array[Node3D])
	_by_key[key] = made
	for a: Dictionary in anchors:
		_add_entry(key, {"anchor": a, "shells": landmark_shells})
	for p: Dictionary in places:
		_add_entry(key, {"place": p})


func _add_entry(key: Vector2i, entry: Dictionary) -> void:
	var data: Dictionary = entry.get("anchor", entry.get("place", {}))
	var id := str(data.get("id", ""))
	if _beat and _retiring.has(id):
		var piece: Node3D = _retiring[id].piece
		_retiring.erase(id)
		piece.transform = _pose(entry)
		_veil_piece(piece, 0.0)
		_order.append(piece)
		(_by_key[key] as Array[Node3D]).append(piece)
		return
	if _beat and _settled_t < 0.0:
		entry["key"] = key
		_pending.append(entry)
		return
	_make(key, entry)


## Makes the piece of an anchor ({anchor, shells}) or a rare place ({place}) under `key`, or nothing
## (reported) when it has no GLB.
func _make(key: Vector2i, entry: Dictionary) -> Node3D:
	var piece: Node3D
	if entry.has("anchor"):
		var a: Dictionary = entry.anchor
		var model := str(a.model)
		piece = _instance(model)
		if piece == null:
			return null
		piece.name = str(a.id)
		_dress(piece, model, dressing_of(model, str(a.dressing)))
	else:
		var p: Dictionary = entry.place
		piece = _instance(kit.rare_asset(0, str(p.kind)) if kit != null else "")
		if piece == null:
			return null
		piece.name = str(p.id)
	piece.transform = _pose(entry)
	if not _by_key.has(key):
		_by_key[key] = [] as Array[Node3D]
	_add(piece, _by_key[key])
	return piece


## Where an anchor's piece stands (its landmark collider's centre, yaw and scale) or a rare place's
## (mirrored, then turned), in this node's frame.
func _pose(entry: Dictionary) -> Transform3D:
	if entry.has("anchor"):
		var a: Dictionary = entry.anchor
		var shell := _shell_for(a, entry.get("shells", []))
		var at: Vector2 = shell.position if not shell.is_empty() else a.position
		var basis := Basis(Vector3.UP, deg_to_rad(float(shell.get("yaw_deg", 0.0)))) * Basis.from_scale(Vector3.ONE * float(shell.get("scale", 1.0)))
		return Transform3D(basis, WorldSpace.to_frame(self, at))
	var p: Dictionary = entry.place
	return Transform3D(place_basis(float(p.get("yaw_deg", 0.0)), bool(p.get("mirror", false))), WorldSpace.to_frame(self, p.position))


## Frees the chunk's pieces; an unknown key changes nothing.
func remove_chunk(key: Vector2i) -> void:
	for piece: Node3D in _by_key.get(key, []):
		_order.erase(piece)
		_fresh.erase(piece)
		_free_piece(piece)
	_by_key.erase(key)
	_pending.assign(_pending.filter(func(e: Dictionary) -> bool: return e.key != key))


## Moves every piece by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for piece in _all_pieces():
		piece.position += position
	for id in _retiring:
		_retiring[id].y += position.y
	position = Vector3.ZERO


## A growth (the container contract): every piece re-expressed in place round `center_old` by
## 1 / `factor`, this node back at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	for piece in _all_pieces():
		var t := piece.transform
		piece.transform = Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor))
	for id in _retiring:
		_retiring[id].y = (_retiring[id].piece as Node3D).position.y
	_beat = true
	_settled_t = -1.0
	_beat_t = 0.0


## chunk_unloaded {reason: "growth"}: the chunk's pieces keep drawing, retiring, by id.
func retire_chunk(key: Vector2i) -> void:
	for piece: Node3D in _by_key.get(key, []):
		_order.erase(piece)
		_fresh.erase(piece)
		_retiring[str(piece.name)] = {"piece": piece, "y": piece.position.y}
	_by_key.erase(key)


## grew: the leftovers start to sink and fade from now.
func settle_growth() -> void:
	if _beat:
		_settled_t = _beat_t


## Each beat frame: up to FRESH_PER_FRAME waiting pieces are made, the fresh come in from the veil
## and the leftovers sink and fade.
func beat_frame(t: float, _k: float) -> void:
	_beat_t = t
	if _beat:
		for i in mini(FRESH_PER_FRAME, _pending.size()):
			var entry: Dictionary = _pending.pop_front()
			var piece := _make(entry.key, entry)
			if piece != null:
				_fresh[piece] = t
				_veil_piece(piece, 1.0)
		var s := GrowthBeat.retire_share(t, _settled_t)
		for id in _retiring:
			var r: Dictionary = _retiring[id]
			(r.piece as Node3D).position.y = float(r.y) - GrowthBeat.SINK_TM * s
			_veil_piece(r.piece, s)
	for piece: Node3D in _fresh.keys():
		var p := GrowthBeat.fresh_share(t - float(_fresh[piece]))
		_veil_piece(piece, 1.0 - p)
		if p >= 1.0:
			_fresh.erase(piece)


## The beat is over: the leftovers go and every piece still waiting is made at once; the fresh keep
## coming in over their own PREBLUR_S.
func end_growth() -> void:
	if not _beat:
		return
	for id in _retiring:
		_free_piece(_retiring[id].piece)
	_retiring.clear()
	while not _pending.is_empty():
		var entry: Dictionary = _pending.pop_front()
		_make(entry.key, entry)
	_beat = false
	_settled_t = -1.0


## The retiring pieces by id (tests).
func retiring() -> Dictionary:
	var out := {}
	for id in _retiring:
		out[id] = _retiring[id].piece
	return out


## The fresh pieces still coming in, and how many wait to be made (tests).
func fresh_pieces() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for piece in _fresh:
		out.append(piece)
	return out


func pending_count() -> int:
	return _pending.size()


func _all_pieces() -> Array[Node3D]:
	var out := _order.duplicate()
	for id in _retiring:
		out.append(_retiring[id].piece)
	return out


## Takes a piece out and frees it, its veil off first: a mesh must not keep a veil that is freed
## with its piece (the renderer reads the instance's materials once more as it goes).
func _free_piece(piece: Node3D) -> void:
	_veil_piece(piece, 0.0)
	remove_child(piece)
	piece.queue_free()


## A piece behind the veil by `amount` (0 clear, 1 gone): every mesh's transparency and the veil pass.
func _veil_piece(piece: Node3D, amount: float) -> void:
	var veil: ShaderMaterial = piece.get_meta(&"veil") if piece.has_meta(&"veil") else null
	if veil == null and amount > 0.0:
		veil = GrowthBeat.preblur(amount)
		piece.set_meta(&"veil", veil)
	if veil != null:
		veil.set_shader_parameter("amount", amount)
	for n: Node in piece.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.transparency = amount
		g.material_overlay = veil if amount > 0.0 else null


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
	var path := str(kit.assets[asset].glb) if kit != null and kit.assets.has(asset) else RockField.ASSET_PATH % asset
	var scene := _scene(path) if asset != "" else null
	if scene == null:
		push_error("The endless sea has no piece for '%s'." % asset)
		return null
	return scene.instantiate() as Node3D


## The piece at `path`: taken from its worker-thread load (waiting for it if it is not done), or
## loaded now if none was started; null when there is no GLB.
static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		if _loading.has(path):
			_loading.erase(path)
			_scenes[path] = ResourceLoader.load_threaded_get(path) as PackedScene
		else:
			_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


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
