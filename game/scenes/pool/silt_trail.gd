class_name SiltTrail
extends Node3D
## The Lurkers' signs on the sea floor (S2, s2-view 7.7): a silt ribbon behind each move between
## its two lairs, and a lair mouth at both posts of every Lurker site, so a player who has met one
## lair can read the other.
##
## Silt ribbons: on creature_post_move {id, post, from, to} of a species whose habit has trail_s,
## a strip of T_SiltTrail from `from` to `to`, RIBBON_WIDTH_TM wide just under the strike lane
## (y RIBBON_Y, drawn before it), the texture repeating along its length, at RIBBON_ALPHA fading to
## nothing over trail_s of sim time. At most MAX_RIBBONS; a new one past that takes the oldest's
## place.
##
## Lair mouths: on chunk_loaded, one marker_lair_mouth.glb per post of each site of MOUTH_SPECIES
## that is live at the size (SpeciesCatalog.live_at), at the post, MOUTH_Y_TM below the plane, its
## opening (+X) along the post's heading, at MOUTH_SCALE x 1.6^(2 - n) (art authored it at the
## Lurker's size-2 radius). They go with their chunk.
##
## WorldSpace shifts this node across a rebase, so everything is placed in its frame. At a growth
## it keeps the container contract (s2-view 4.5, as LandmarkLayer): apply_growth re-expresses every
## ribbon and mouth in place, and set_depth_k holds the mouths at MOUTH_Y_TM x k through the beat (as
## ZoneLights holds its discs), so they keep their old depth on screen at frame 0; the tick's
## unloaded chunks retire, their mouths kept by site and post and adopted back when the same one
## loads again; a mouth first seen during the beat comes in from the veil once the tick settles; the
## leftovers sink and fade, and end_growth frees them.

const RIBBON_WIDTH_TM := 0.5
const RIBBON_Y := -0.03
const RIBBON_ALPHA := 0.55
const MAX_RIBBONS := 8
## The texture is 256 x 64 px: across RIBBON_WIDTH_TM, one repeat is this long.
const TILE_TM := 2.0
## Drawn before the strike lane (CreatureView.LANE_PRIORITY) and the zone patches' lights over it.
const RIBBON_PRIORITY := CreatureView.LANE_PRIORITY - 2
const SILT_TEXTURE := preload("res://assets/export/ambience/T_SiltTrail.png")
const MOUTH_GLB := "res://assets/export/marker_lair_mouth.glb"
const MOUTH_SPECIES := "lurker"
const MOUTH_Y_TM := -1.6
const MOUTH_SCALE := 0.75

## The creatures' species (habits and live_at); none in a test that gives none.
var species: SpeciesCatalog
## The size the sea is drawn at: which sites are live and how large their mouths are.
var size := 1

static var _mouth_scene: PackedScene
## Whether the mouth's GLB is loading on a worker thread (request_mouth) and not taken yet.
static var _mouth_loading := false

var _ribbons: Array[Dictionary] = []    ## {node, born_s, fade_s}, oldest first
var _mouths := {}                       ## chunk key -> Array[Node3D]
var _sites := {}                        ## chunk key -> its chunk_loaded sites, for resize()
## A growth: retiring mouths by name ({piece, y}), fresh ones (piece -> the beat time it was made),
## the mouths still to make ({key, name, post}), whether a beat is open, the beat time of the settle
## (-1 before) and the beat time now.
var _retiring := {}
var _fresh := {}
var _pending: Array[Dictionary] = []
var _beat := false
var _settled_t := -1.0
var _beat_t := 0.0
var _depth_k := 1.0


## Starts loading the lair mouth on a worker thread, once a run: the first mouths come with a growth,
## and loading the GLB in the growth's frame took about 6 ms (S2G26).
static func request_mouth() -> void:
	if _mouth_scene != null or _mouth_loading or not ResourceLoader.exists(MOUTH_GLB):
		return
	_mouth_loading = ResourceLoader.load_threaded_request(MOUTH_GLB) == OK


func _notification(what: int) -> void:
	# A load still pending when the run ends would leak: take it as a trail goes.
	if what == NOTIFICATION_PREDELETE and _mouth_loading:
		_take_mouth()


static func _take_mouth() -> void:
	_mouth_loading = false
	_mouth_scene = ResourceLoader.load_threaded_get(MOUTH_GLB) as PackedScene


## Starts empty on `p_species` at `p_size`.
func setup(p_species: SpeciesCatalog, p_size: int) -> void:
	clear()
	species = p_species
	size = p_size


## The sea drawn at size `n` at once, with no beat (the dev set_size): the ribbons go, and the
## mouths are made again for n from their chunks' sites.
func resize(n: int) -> void:
	var sites := _sites.duplicate()
	setup(species, n)
	for key: Vector2i in sites:
		add_chunk(key, sites[key])


## Frees every ribbon and mouth.
func clear() -> void:
	for child in get_children():
		_free_piece(child)
	_ribbons.clear()
	_mouths.clear()
	_sites.clear()
	_retiring.clear()
	_fresh.clear()
	_pending.clear()
	_beat = false
	_settled_t = -1.0


# --- silt ribbons ---

## creature_post_move {from, to} of a creature of `species_id` at sim time `now_s`: a ribbon when the
## species leaves a trail (habit.trail_s), else nothing.
func add_ribbon(event: Dictionary, species_id: String, now_s: float) -> void:
	var fade_s := float(species.habit_of(species_id).get("trail_s", 0.0)) if species != null else 0.0
	if fade_s <= 0.0:
		return
	var from: Vector2 = event.get("from", Vector2.ZERO)
	var to: Vector2 = event.get("to", Vector2.ZERO)
	var length := from.distance_to(to)
	if length <= 1e-3:
		return
	if _ribbons.size() >= MAX_RIBBONS:
		_free_piece(_ribbons.pop_front().node)
	var node := MeshInstance3D.new()
	node.name = "Ribbon%d" % get_child_count()
	node.mesh = GhostLayer.quad()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = SILT_TEXTURE
	m.texture_repeat = true
	m.uv1_scale = Vector3(length / TILE_TM, 1.0, 1.0)
	m.albedo_color = Color(1.0, 1.0, 1.0, RIBBON_ALPHA)
	m.render_priority = RIBBON_PRIORITY
	node.material_override = m
	var d := to - from
	var basis := Basis(Vector3.UP, -atan2(d.y, d.x)) * Basis.from_scale(Vector3(length, 1.0, RIBBON_WIDTH_TM))
	node.transform = Transform3D(basis, WorldSpace.to_frame(self, (from + to) * 0.5, RIBBON_Y))
	add_child(node)
	_ribbons.append({"node": node, "born_s": now_s, "fade_s": fade_s})


## Each frame at sim time `now_s`: every ribbon fades, and one faded out goes.
func step(now_s: float) -> void:
	for r in _ribbons.duplicate():
		var a := RIBBON_ALPHA * (1.0 - clampf((now_s - float(r.born_s)) / float(r.fade_s), 0.0, 1.0))
		if a <= 0.0:
			_ribbons.erase(r)
			_free_piece(r.node)
			continue
		((r.node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = a


## The ribbons drawn now, oldest first (for checks).
func ribbons() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for r in _ribbons:
		out.append(r.node)
	return out


# --- lair mouths ---

## chunk_loaded's sites [{id, species, posts: [{position, heading}]}]: a mouth at every post of each
## live MOUTH_SPECIES site. During a growth beat a mouth retired with the same site and post is
## adopted back at the event's pose, and a new one waits to be made until the tick settles.
func add_chunk(key: Vector2i, sites: Array) -> void:
	if not _mouths.has(key):
		_mouths[key] = [] as Array[Node3D]
	_sites[key] = sites
	if species != null and not species.live_at(MOUTH_SPECIES, size):
		return
	for site: Dictionary in sites:
		if str(site.get("species", "")) != MOUTH_SPECIES:
			continue
		var posts: Array = site.get("posts", [])
		for i in posts.size():
			var mouth_name := "%s_post%d" % [site.id, i]
			if _beat and _retiring.has(mouth_name):
				var piece: Node3D = _retiring[mouth_name].piece
				_retiring.erase(mouth_name)
				piece.transform = _mouth_pose(posts[i])
				_veil_piece(piece, 0.0)
				(_mouths[key] as Array[Node3D]).append(piece)
			elif _beat and _settled_t < 0.0:
				_pending.append({"key": key, "name": mouth_name, "post": posts[i]})
			else:
				_make(key, mouth_name, posts[i])


## Frees the chunk's mouths; an unknown key changes nothing.
func remove_chunk(key: Vector2i) -> void:
	for piece: Node3D in _mouths.get(key, []):
		_fresh.erase(piece)
		_free_piece(piece)
	_mouths.erase(key)
	_sites.erase(key)
	_pending.assign(_pending.filter(func(e: Dictionary) -> bool: return e.key != key))


## The mouths drawn now, in chunk and add order (for checks).
func mouths() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for key in _mouths:
		out.append_array(_mouths[key])
	return out


## The mouth's pose at a post {position, heading}: MOUTH_Y_TM down, +X along the heading, scaled for
## the size.
func _mouth_pose(post: Dictionary) -> Transform3D:
	var s := MOUTH_SCALE * pow(Relationships.GROWTH_FACTOR, 2 - size)
	var basis := Basis(Vector3.UP, -float(post.get("heading", 0.0))) * Basis.from_scale(Vector3.ONE * s)
	return Transform3D(basis, WorldSpace.to_frame(self, post.get("position", Vector2.ZERO), MOUTH_Y_TM * _depth_k))


func _make(key: Vector2i, mouth_name: String, post: Dictionary) -> Node3D:
	if _mouth_scene == null and _mouth_loading:
		_take_mouth()
	if _mouth_scene == null:
		_mouth_scene = load(MOUTH_GLB) as PackedScene if ResourceLoader.exists(MOUTH_GLB) else null
	if _mouth_scene == null:
		push_error("The lair mouth has no piece at %s." % MOUTH_GLB)
		return null
	var piece := _mouth_scene.instantiate() as Node3D
	piece.name = mouth_name
	piece.transform = _mouth_pose(post)
	for n: Node in piece.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	if not _mouths.has(key):
		_mouths[key] = [] as Array[Node3D]
	(_mouths[key] as Array[Node3D]).append(piece)
	return piece


# --- the container contract ---

## Every live mouth at MOUTH_Y_TM x k (1 when no beat runs); the retiring ones sink from where they were.
func set_depth_k(k: float) -> void:
	_depth_k = k
	for piece in mouths():
		piece.position.y = MOUTH_Y_TM * k


## Moves every piece by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for child in get_children():
		(child as Node3D).position += position
	for mouth_name in _retiring:
		_retiring[mouth_name].y += position.y
	position = Vector3.ZERO


## A growth: every ribbon and mouth re-expressed in place round `center_old` by 1 / `factor`, this
## node back at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	for child in get_children():
		var piece := child as Node3D
		var t := piece.transform
		piece.transform = Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor))
	for mouth_name in _retiring:
		_retiring[mouth_name].y = (_retiring[mouth_name].piece as Node3D).position.y
	_beat = true
	_settled_t = -1.0
	_beat_t = 0.0


## chunk_unloaded {reason: "growth"}: the chunk's mouths keep drawing, retiring, by name.
func retire_chunk(key: Vector2i) -> void:
	for piece: Node3D in _mouths.get(key, []):
		_fresh.erase(piece)
		_retiring[str(piece.name)] = {"piece": piece, "y": piece.position.y}
	_mouths.erase(key)
	_sites.erase(key)


## grew: the leftovers start to sink and fade from now (the pool set the new size at growth_began,
## before the tick's chunks came).
func settle_growth() -> void:
	if _beat:
		_settled_t = _beat_t


## Each beat frame: the waiting mouths are made once the tick settles and come in from the veil;
## the leftovers sink and fade.
func beat_frame(t: float, _k: float) -> void:
	_beat_t = t
	if _beat:
		if _settled_t >= 0.0:
			while not _pending.is_empty():
				var entry: Dictionary = _pending.pop_front()
				var piece := _make(entry.key, entry.name, entry.post)
				if piece != null:
					_fresh[piece] = t
					_veil_piece(piece, 1.0)
		var s := GrowthBeat.retire_share(t, _settled_t)
		for mouth_name in _retiring:
			var r: Dictionary = _retiring[mouth_name]
			(r.piece as Node3D).position.y = float(r.y) - GrowthBeat.SINK_TM * s
			_veil_piece(r.piece, s)
	for piece: Node3D in _fresh.keys():
		var p := GrowthBeat.fresh_share(t - float(_fresh[piece]))
		_veil_piece(piece, 1.0 - p)
		if p >= 1.0:
			_fresh.erase(piece)


## The beat is over: the leftovers go and every mouth still waiting is made at once.
func end_growth() -> void:
	if not _beat:
		return
	for mouth_name in _retiring:
		_free_piece(_retiring[mouth_name].piece)
	_retiring.clear()
	while not _pending.is_empty():
		var entry: Dictionary = _pending.pop_front()
		_make(entry.key, entry.name, entry.post)
	for piece: Node3D in _fresh.keys():
		_veil_piece(piece, 0.0)
	_fresh.clear()
	_beat = false
	_settled_t = -1.0


## The retiring mouths by name (tests).
func retiring() -> Dictionary:
	var out := {}
	for mouth_name in _retiring:
		out[mouth_name] = _retiring[mouth_name].piece
	return out


## Takes a piece out and frees it, its veil off first (as LandmarkLayer does).
func _free_piece(piece: Node) -> void:
	if piece is Node3D:
		_veil_piece(piece, 0.0)
	remove_child(piece)
	piece.queue_free()


## A mouth behind the veil by `amount` (0 clear, 1 gone): every mesh's transparency and the veil pass.
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
