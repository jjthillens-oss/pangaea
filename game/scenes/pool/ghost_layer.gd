class_name GhostLayer
extends Node3D
## The ghosts of the sizes to come (S2, s2-view 6; V-11 to V-14, V-19): faint pre-blurred paintings
## far under the swim plane, each a flat quad drawn with art's backdrop.gdshader as art's backdrops
## are, so the ambience contract's height is the quad's y.
##   near   near.count slots show the species that enter at the next two sizes. Each slot runs cycles
##          of near.cycle_s, a species per cycle, anchored on a ring north of the focus and drifting,
##          fading in and out at the cycle's ends. Each species has its own depth (near_depth), so
##          it draws design_multiple times the cell at the reference spot, and every frame a draw
##          scale makes up the rest anywhere on screen and at any zoom (V-11).
##   far    far.count giants cross the far footprint once per far.cycle_s, their body held at
##          far.screen_share of the screen height (measured through the camera every frame).
##   first  once per lineage on this computer, far slot 0 is taken over for a slow pass of
##          first_pass.duration_s (D-42, V-14); first_pass_started tells the pool, and main
##          remembers it.
##   rise   at a growth, the near ghost of a species that is now live rises to rise_depth_tm and swims
##          off toward one of its loaded sites (V-13); the growth beat picks the species and the site.
## The layer reads only its scale view (PoolScene.scale_view) and the camera, never the simulation
## (S2G15). It is camera_relative and not in WorldSpace (V-12): every frame it places each billboard
## at camera.focus + (anchor_am - focus_am) / tm_to_am, through float64 until the subtraction, so a
## rebase moves nothing and a growth re-expresses it by itself. At a growth every depth and size
## blends from the old size's (times k_from) to the new size's as k runs to 1, so frame 0 draws what
## frame A drew. It runs in pool mode too, at size 1 (V-19), and is never in the hash or a save.
##
##     ghosts.configure(GhostLayer.shipped().data, size, hash(lineage_id))
##     ghosts.apply_scale_view(pool.scale_view())   # every frame, after the camera moved

signal first_pass_started

const LADDER_PATH := "res://game/data/ghost_ladder.json"
const BACKDROP_SHADER := preload("res://game/scenes/pool/ambience/backdrop.gdshader")
const FILE_NAME := "ghost_ladder"
const TOP_KEYS: PackedStringArray = ["schema_version", "status", "brightness", "far", "near", "species", "names",
	"food_haze", "preview_at_top"]
const FAR_KEYS: PackedStringArray = ["textures", "body_rects", "depth_tm", "count", "min_cell_radius_multiple",
	"max_screen_share", "screen_share", "opacity", "cycle_s", "first_pass"]
const FIRST_PASS_KEYS: PackedStringArray = ["depth_tm", "start_s", "duration_s"]
const NEAR_KEYS: PackedStringArray = ["depth_tm", "count", "min_cell_multiple", "rise_depth_tm", "design_multiple",
	"max_draw_scale", "d_ref_tm", "opacity", "cycle_s", "fade_s", "ring_tm", "drift_tm_s"]
const SPECIES_KEYS: PackedStringArray = ["entry_size", "radius_tm", "texture", "body_rect", "plural", "haze"]
const NAME_KEYS: PackedStringArray = ["plural", "haze"]
## Sizes a ladder may name (entry_size, preview_at_top).
const SIZES := Vector2i(1, 10)
## Nothing of the layer comes nearer the swim plane than this (the ambience contract's band).
const PLANE_FLOOR_TM := -1.5
## The most slots of a kind the layer draws.
const MAX_NEAR := 8
## The cell's radius in its own size's tm: a true radius over it is the multiple of the cell.
const CELL_RADIUS_TM := 0.5
## View depth per tm below the plane, straight under the focus (sin of the camera's 55 degree pitch).
const VIEW_DROP := 0.819
## The near ring's bearing: north (-z) +- this many degrees.
const RING_SPREAD_DEG := 75.0
## A far giant crosses from -FAR_REACH_TM to +FAR_REACH_TM east of the focus, FAR_Z_TM north of it.
const FAR_REACH_TM := 45.0
const FAR_Z_TM := Vector2(-35.0, -10.0)
const FAR_FADE_S := 10.0
## The first pass runs FIRST_PASS_Z_TM north of the focus, fading in and out over FIRST_PASS_FADE_S.
const FIRST_PASS_Z_TM := -20.0
const FIRST_PASS_FADE_S := 3.0
## Fixed-point steps per frame on a far giant's size (its share is linear in it to first order).
const FAR_STEPS := 2
## At a growth a ghost of a species now live fades out over GROWTH_FADE.y from GROWTH_FADE.x (beat s).
const GROWTH_FADE := Vector2(0.3, 1.0)
## The rise (V-13): it eases up over RISE_S while moving RISE_SHARE of the way to its target (at most
## RISE_MOVE_MAX_TM, so it rises in sight), then swims there at RISE_SWIM_TM_S. It fades over RISE_FADE_S once it has left the screen, and is gone
## RISE_GONE_S after it began: by the beat's 6 s, since the beat starts it in its first frame from
## 1 s (a frame to spare).
const RISE_S := 1.0
const RISE_SHARE := 0.25
const RISE_MOVE_MAX_TM := 3.0
const RISE_SWIM_TM_S := 3.0
const RISE_FADE_S := 0.5
const RISE_GONE_S := 4.9
## A riser no near ghost shows starts this far from the focus (tm, east and south) at RISE_NEW_Y,
## fading in over RISE_FADE_S.
const RISE_NEW_AT := Vector2(6.0, 6.0)
const RISE_NEW_Y := -8.0
const NO_CYCLE := -2147483648

## The camera the billboards are placed and measured for (the pool's).
var camera: PoolCamera
var _ladder := {}
var _size := 1
var _seed := 0
## Near and far slots: {node, cycle, species, anchor (am), at_s, velocity (am/s), opacity, y, side,
## alpha, ...}; see _start_near and _start_far.
var _near: Array[Dictionary] = []
var _far: Array[Dictionary] = []
var _riser_node: MeshInstance3D
## The rise running now: {species, node, slot, from (am), toward (am), y0, opacity, fade_in, t0, seen,
## fade_t}; empty when none.
var _riser := {}
## The growth being shown: {from, to, k_from, t0}; empty when none.
var _growth := {}
var _pass_at := -1.0
var _pass := {}
var _passed := false
var _staging := false
var _view := {}
## The camera as last read: its transform in this layer's space and its projection.
var _eye := Transform3D.IDENTITY
var _eye_inverse := Transform3D.IDENTITY
var _lens := Projection.IDENTITY
static var _quad: QuadMesh
static var _shipped := {}


# --- the ladder ---

## The shipped ladder, read once: {data, problems}.
static func shipped() -> Dictionary:
	if _shipped.is_empty():
		_shipped = load_ladder()
	return _shipped


## Reads and checks a ladder file (S2G29): {data, problems}. With problems the layer draws nothing.
static func load_ladder(path := LADDER_PATH) -> Dictionary:
	var data: Variant = null
	if FileAccess.file_exists(path):
		data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {"data": {}, "problems": PackedStringArray(["%s: missing or not readable JSON" % path.get_file()])}
	return {"data": data, "problems": check_ladder(data)}


## Every problem of a parsed ladder, each naming its JSON path: unknown and missing keys at every
## level, entry sizes 2 to 10, radii above 0, body rects with 0 <= u0 < u1 <= 1 (and v), every
## texture present, depths at or below -1.5, the share within its maximum, preview sizes 1 to 10.
static func check_ladder(data: Dictionary) -> PackedStringArray:
	var w := FILE_NAME
	var problems := WorldConfig.schema_problems(w, data, TOP_KEYS)
	if data.has("schema_version") and not (data.schema_version is float and int(data.schema_version) == 1):
		problems.append("%s.schema_version: must be 1" % w)
	if data.has("status") and not WorldConfig.STATUSES.has(data.status):
		problems.append("%s.status: must be one of %s" % [w, ", ".join(WorldConfig.STATUSES)])
	var brightness := WorldConfig.number_at(w, data, "brightness", problems)
	if data.has("brightness") and (brightness <= 0.0 or brightness > 1.0):
		problems.append("%s.brightness: must be above 0 and at most 1" % w)
	_check_far(w + ".far", data.get("far"), problems)
	_check_near(w + ".near", data.get("near"), problems)
	var species: Variant = data.get("species")
	if data.has("species") and not species is Dictionary:
		problems.append("%s.species: must be an object" % w)
	elif species is Dictionary:
		for id: String in species:
			_check_species("%s.species.%s" % [w, id], species[id], problems)
	var names: Variant = data.get("names")
	if data.has("names") and not names is Dictionary:
		problems.append("%s.names: must be an object" % w)
	elif names is Dictionary:
		for id: String in names:
			var where := "%s.names.%s" % [w, id]
			problems.append_array(WorldConfig.schema_problems(where, names[id], NAME_KEYS))
			if names[id] is Dictionary:
				WorldConfig.text_at(where, names[id], "plural", problems)
				_check_file(where, names[id], "haze", problems)
	var food: Variant = data.get("food_haze")
	if data.has("food_haze") and not food is Dictionary:
		problems.append("%s.food_haze: must be an object" % w)
	elif food is Dictionary:
		for look: String in food:
			_check_file(w + ".food_haze", food, look, problems)
	var preview: Variant = data.get("preview_at_top")
	if data.has("preview_at_top") and not preview is Dictionary:
		problems.append("%s.preview_at_top: must be an object" % w)
	elif preview is Dictionary:
		for key: String in preview:
			if not (key.is_valid_int() and int(key) >= SIZES.x and int(key) <= SIZES.y):
				problems.append("%s.preview_at_top.%s: must be a size %d to %d" % [w, key, SIZES.x, SIZES.y])
			WorldConfig.text_at(w + ".preview_at_top", preview, key, problems)
	return problems


static func _check_far(where: String, far: Variant, problems: PackedStringArray) -> void:
	problems.append_array(WorldConfig.schema_problems(where, far, FAR_KEYS))
	if not far is Dictionary:
		return
	var textures: Variant = far.get("textures")
	if far.has("textures") and not (textures is Array and not textures.is_empty()):
		problems.append("%s.textures: must be a list of textures" % where)
	elif textures is Array:
		var rects: Variant = far.get("body_rects", {})
		for i in textures.size():
			var path: Variant = textures[i]
			if not (path is String and ResourceLoader.exists(path)):
				problems.append("%s.textures.%d: no texture at %s" % [where, i, path])
			elif rects is Dictionary and not rects.has(path.get_file().get_basename()):
				problems.append("%s.body_rects.%s: missing" % [where, path.get_file().get_basename()])
	var rects: Variant = far.get("body_rects")
	if far.has("body_rects") and not rects is Dictionary:
		problems.append("%s.body_rects: must be an object" % where)
	elif rects is Dictionary:
		for id: String in rects:
			_check_rect("%s.body_rects.%s" % [where, id], rects[id], problems)
	_check_depths(where, far, "depth_tm", problems)
	var count := WorldConfig.number_at(where, far, "count", problems, true)
	if textures is Array and far.has("count") and int(count) != textures.size():
		problems.append("%s.count: must be the number of textures (%d)" % [where, textures.size()])
	WorldConfig.number_at(where, far, "min_cell_radius_multiple", problems)
	var top := WorldConfig.number_at(where, far, "max_screen_share", problems)
	var share := WorldConfig.number_at(where, far, "screen_share", problems)
	if far.has("screen_share") and (share <= 0.0 or (far.has("max_screen_share") and share > top)):
		problems.append("%s.screen_share: must be above 0 and at most max_screen_share (%s)" % [where, top])
	_check_unit(where, far, "opacity", problems)
	_check_positive(where, far, "cycle_s", problems)
	var first: Variant = far.get("first_pass")
	if far.has("first_pass"):
		problems.append_array(WorldConfig.schema_problems(where + ".first_pass", first, FIRST_PASS_KEYS))
	if first is Dictionary:
		var depth := WorldConfig.number_at(where + ".first_pass", first, "depth_tm", problems)
		if first.has("depth_tm") and depth > PLANE_FLOOR_TM:
			problems.append("%s.first_pass.depth_tm: must be at or below %s" % [where, PLANE_FLOOR_TM])
		var start := WorldConfig.pair_at(where + ".first_pass", first, "start_s", problems)
		if start.size() == 2 and not (start[0] >= 0.0 and start[0] <= start[1]):
			problems.append("%s.first_pass.start_s: must run from 0 or later, low to high" % where)
		_check_positive(where + ".first_pass", first, "duration_s", problems)


static func _check_near(where: String, near: Variant, problems: PackedStringArray) -> void:
	problems.append_array(WorldConfig.schema_problems(where, near, NEAR_KEYS))
	if not near is Dictionary:
		return
	_check_depths(where, near, "depth_tm", problems)
	var count := WorldConfig.number_at(where, near, "count", problems, true)
	if near.has("count") and (count < 1.0 or count > MAX_NEAR):
		problems.append("%s.count: must be 1 to %d" % [where, MAX_NEAR])
	_check_positive(where, near, "min_cell_multiple", problems)
	var rise := WorldConfig.number_at(where, near, "rise_depth_tm", problems)
	if near.has("rise_depth_tm") and rise > PLANE_FLOOR_TM:
		problems.append("%s.rise_depth_tm: must be at or below %s" % [where, PLANE_FLOOR_TM])
	var design := WorldConfig.number_at(where, near, "design_multiple", problems)
	if near.has("design_multiple") and near.has("min_cell_multiple") and design < float(near.min_cell_multiple):
		problems.append("%s.design_multiple: must be at least min_cell_multiple" % where)
	var top := WorldConfig.number_at(where, near, "max_draw_scale", problems)
	if near.has("max_draw_scale") and top < 1.0:
		problems.append("%s.max_draw_scale: must be at least 1" % where)
	_check_positive(where, near, "d_ref_tm", problems)
	var opacity := WorldConfig.pair_at(where, near, "opacity", problems)
	if opacity.size() == 2 and not (opacity[0] > 0.0 and opacity[0] <= opacity[1] and opacity[1] <= 1.0):
		problems.append("%s.opacity: must be two values in (0, 1], low to high" % where)
	_check_positive(where, near, "cycle_s", problems)
	var fade := WorldConfig.number_at(where, near, "fade_s", problems)
	if near.has("fade_s") and near.has("cycle_s") and (fade < 0.0 or 2.0 * fade > float(near.cycle_s)):
		problems.append("%s.fade_s: must fit twice in cycle_s" % where)
	var ring := WorldConfig.pair_at(where, near, "ring_tm", problems)
	if ring.size() == 2 and not (ring[0] > 0.0 and ring[0] <= ring[1]):
		problems.append("%s.ring_tm: must be two radii above 0, low to high" % where)
	var drift := WorldConfig.number_at(where, near, "drift_tm_s", problems)
	if near.has("drift_tm_s") and drift < 0.0:
		problems.append("%s.drift_tm_s: must be 0 or more" % where)


static func _check_species(where: String, entry: Variant, problems: PackedStringArray) -> void:
	problems.append_array(WorldConfig.schema_problems(where, entry, SPECIES_KEYS))
	if not entry is Dictionary:
		return
	var size := WorldConfig.number_at(where, entry, "entry_size", problems, true)
	if entry.has("entry_size") and (size < 2.0 or size > SIZES.y):
		problems.append("%s.entry_size: must be 2 to %d" % [where, SIZES.y])
	var radius := WorldConfig.number_at(where, entry, "radius_tm", problems)
	if entry.has("radius_tm") and radius <= 0.0:
		problems.append("%s.radius_tm: must be above 0" % where)
	_check_file(where, entry, "texture", problems)
	if entry.has("body_rect"):
		_check_rect(where + ".body_rect", entry.body_rect, problems)
	WorldConfig.text_at(where, entry, "plural", problems)
	_check_file(where, entry, "haze", problems)


## A body rect [u0, v0, u1, v1]: the alpha >= 0.1 box of its texture, 0 <= u0 < u1 <= 1 and the same
## for v.
static func _check_rect(where: String, rect: Variant, problems: PackedStringArray) -> void:
	var ok: bool = rect is Array and rect.size() == 4
	if ok:
		for v in rect:
			ok = ok and (v is float or v is int) and is_finite(v)
	if ok:
		ok = rect[0] >= 0.0 and rect[0] < rect[2] and rect[2] <= 1.0 and rect[1] >= 0.0 and rect[1] < rect[3] and rect[3] <= 1.0
	if not ok:
		problems.append("%s: must be [u0, v0, u1, v1] with 0 <= u0 < u1 <= 1 and 0 <= v0 < v1 <= 1" % where)


static func _check_depths(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> void:
	var depths := WorldConfig.pair_at(where, data, key, problems)
	if depths.size() == 2 and not (depths[0] <= depths[1] and depths[1] <= PLANE_FLOOR_TM):
		problems.append("%s.%s: must lie at or below %s, deep to shallow" % [where, key, PLANE_FLOOR_TM])


static func _check_file(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> void:
	var path := WorldConfig.text_at(where, data, key, problems)
	if data.has(key) and data[key] is String and not ResourceLoader.exists(path):
		problems.append("%s.%s: no file at %s" % [where, key, path])


static func _check_positive(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> void:
	var value := WorldConfig.number_at(where, data, key, problems)
	if data.has(key) and value <= 0.0:
		problems.append("%s.%s: must be above 0" % [where, key])


static func _check_unit(where: String, data: Dictionary, key: String, problems: PackedStringArray) -> void:
	var value := WorldConfig.number_at(where, data, key, problems)
	if data.has(key) and (value <= 0.0 or value > 1.0):
		problems.append("%s.%s: must be above 0 and at most 1" % [where, key])


## The haze sprite of every food look and every species the ladder names: look or species -> path.
static func haze_paths(ladder: Dictionary) -> Dictionary:
	var out := {}
	for look: String in ladder.get("food_haze", {}):
		out[look] = ladder.food_haze[look]
	for group in ["species", "names"]:
		for id: String in ladder.get(group, {}):
			out[id] = ladder[group][id].haze
	return out


## A species' true radius at size n (tm of size n): its radius at its entry size, times the growth
## factor for each size it is ahead.
static func true_radius(ladder: Dictionary, species_id: String, n: int) -> float:
	var entry: Dictionary = ladder.species[species_id]
	return float(entry.radius_tm) * WorldConfig.tm_to_am(int(entry.entry_size)) / WorldConfig.tm_to_am(n)


## How many cells across a body `rel_true` cells across draws, at `depth` straight under the focus with
## the camera d_ref away: rel x D / (D + 0.819 h), h the depth below the plane.
static func true_multiple(rel_true: float, depth: float, d_ref := 14.0) -> float:
	return rel_true * d_ref / (d_ref + VIEW_DROP * -depth)


## A near ghost's depth at size n (s2-view 0.9): the deepest in near.depth_tm where it draws at least
## design_multiple times the cell at true scale; the shallowest end when none reaches it.
static func near_depth(ladder: Dictionary, species_id: String, n: int) -> float:
	var near: Dictionary = ladder.near
	var rel := true_radius(ladder, species_id, n) / CELL_RADIUS_TM
	var d_ref := float(near.d_ref_tm)
	var h := (rel * d_ref / float(near.design_multiple) - d_ref) / VIEW_DROP
	return clampf(-h, float(near.depth_tm[0]), float(near.depth_tm[1]))


## The least draw scale of a near ghost at size n: what lifts its multiple at its depth to
## design_multiple, 1 when the depth alone reaches it.
static func near_base_scale(ladder: Dictionary, species_id: String, n: int) -> float:
	var rel := true_radius(ladder, species_id, n) / CELL_RADIUS_TM
	var multiple := true_multiple(rel, near_depth(ladder, species_id, n), float(ladder.near.d_ref_tm))
	return maxf(1.0, float(ladder.near.design_multiple) / multiple)


## The quad every ghost draws: 1 tm across, flat (FACE_Y), its texture's top to the north.
static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_quad.size = Vector2.ONE
	return _quad


## What the start fade draws once so the ghosts' shader is ready (V-20): the quad with a ghost on it.
static func warm_up_mesh() -> Mesh:
	var mesh := quad().duplicate() as QuadMesh
	var ladder: Dictionary = shipped().data
	var path := str(ladder.species.values()[0].texture) if not ladder.is_empty() else ""
	mesh.material = _material(load(path) as Texture2D if ResourceLoader.exists(path) else null, 0.38)
	return mesh


static func _material(texture: Texture2D, brightness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BACKDROP_SHADER
	m.set_shader_parameter("image", texture)
	m.set_shader_parameter("opacity", 0.0)
	m.set_shader_parameter("brightness", brightness)
	return m


# --- the layer ---

## Starts the layer on `ladder` (empty: draws nothing) at `size`, its cycles hashed from `seed_value`
## (the lineage's), with no growth, rise or pass.
func configure(ladder: Dictionary, size: int, seed_value: int) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_near.clear()
	_far.clear()
	_riser = {}
	_growth = {}
	_pass = {}
	_pass_at = -1.0
	_passed = false
	_staging = false
	_view = {}
	_riser_node = null
	_ladder = ladder
	_size = size
	_seed = seed_value
	if ladder.is_empty():
		return
	var brightness := float(ladder.brightness)
	for i in int(ladder.near.count):
		_near.append({"node": _billboard("Near%d" % i, brightness), "cycle": NO_CYCLE, "species": "", "alpha": 0.0})
	var textures: Array = ladder.far.textures
	for i in int(ladder.far.count):
		var node := _billboard("Far%d" % i, brightness)
		var path := str(textures[i])
		(node.material_override as ShaderMaterial).set_shader_parameter("image", load(path))
		_far.append({"node": node, "cycle": NO_CYCLE, "rect": ladder.far.body_rects[path.get_file().get_basename()],
			"side": 0.0, "alpha": 0.0})
	_riser_node = _billboard("Riser", brightness)


## The ladder the layer draws ({} when it draws nothing): the ladder strip reads its names from it.
func ladder() -> Dictionary:
	return _ladder


## The size whose ghosts the layer draws now (the new size from a growth's begin_growth).
func shown_size() -> int:
	return _size


## The ladder species that enter at the next two sizes, in the ladder's order: what the near ghosts of
## `size` show.
func near_species(size: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _ladder.get("species", {}):
		var entry := int(_ladder.species[id].entry_size)
		if entry == size + 1 or entry == size + 2:
			out.append(id)
	return out


## The ladder species that become live at `size` (the rise's candidates), in the ladder's order.
func entering(size: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _ladder.get("species", {}):
		if int(_ladder.species[id].entry_size) == size:
			out.append(id)
	return out


## Every billboard drawn now.
func billboards() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).visible:
			out.append(child)
	return out


## The rise's billboard now, or null.
func riser() -> MeshInstance3D:
	return _riser.get("node") if not _riser.is_empty() else null


## The species a near billboard or the riser shows now; "" for a giant or a hidden one.
func species_of(node: Node) -> String:
	if not _riser.is_empty() and node == _riser.node:
		return str(_riser.species)
	for slot in _near:
		if slot.node == node and node.visible:
			return str(slot.species)
	return ""


## When the giants' first pass starts (session time), or -1 when none is to come.
func first_pass_at() -> float:
	return -1.0 if _passed else _pass_at


## Fixed placements for the look probe and tests instead of the cycles: near [{species, offset
## (Vector2, tm from the focus), depth (optional)}] into the near slots in order, far [{offset, depth}]
## into the far slots (each keeps its own texture). Staged ghosts hold their place in the world at
## their full opacity from the next frame, and slots left out hide. stage([], []) cycles again.
func stage(near: Array, far: Array) -> void:
	_staging = not (near.is_empty() and far.is_empty())
	for i in _near.size():
		_near[i].cycle = NO_CYCLE
		_near[i].staged = near[i] if i < near.size() else {}
		_near[i].erase("riser")
	for i in _far.size():
		_far[i].cycle = NO_CYCLE
		_far[i].staged = far[i] if i < far.size() else {}
		_far[i].side = 0.0


## The giants' first pass starts at session time `at_s` (D-42, V-14): far slot 0 crosses once.
func schedule_first_pass(at_s: float) -> void:
	_pass_at = at_s
	_pass = {}
	_passed = false


## growth_began: every depth and size blends from `from_size`'s (times k_from) to `to_size`'s as k
## runs to 1. A ghost of a species now live fades out over GROWTH_FADE from 0.3 s, except the first
## of each such species, which waits for the rise (it may be the riser) and then fades.
func begin_growth(from_size: int, to_size: int) -> void:
	if _ladder.is_empty():
		return
	_growth = {"from": from_size, "to": to_size, "t0": -1.0,
		"k_from": WorldConfig.tm_to_am(from_size) / WorldConfig.tm_to_am(to_size)}
	var waiting := {}
	for slot in _near:
		slot.erase("leave_t")
		slot.erase("may_rise")
		if slot.species == "" or not _ladder.species.has(slot.species) or int(_ladder.species[slot.species].entry_size) > to_size:
			continue
		if slot.alpha > 0.0 and not waiting.has(slot.species):
			waiting[slot.species] = true
			slot.may_rise = true
			slot.leave_t = INF
		else:
			slot.leave_t = -1.0   # set at the beat's first frame
	_size = to_size


## The rise (V-13), at 1.0 s of the beat: the near ghost showing `species_id` (else a new one south-east
## of the focus) rises to rise_depth_tm while moving a quarter of the way toward `toward` (local tm,
## the current frame), then swims there; it fades once it has left the screen, and by RISE_GONE_S.
func rise(species_id: String, toward: Vector2) -> void:
	if _ladder.is_empty() or not _ladder.species.has(species_id) or _view.is_empty() or camera == null:
		return
	_end_rise()
	var now := float(_view.time_s)
	var pick := -1
	for i in _near.size():
		if _near[i].species == species_id and _near[i].alpha > 0.0 and (pick < 0 or _near[i].has("may_rise")):
			pick = i
	_riser = {"species": species_id, "toward": _am_of(toward), "t0": -1.0, "seen": false, "fade_t": -1.0, "slot": pick}
	if pick >= 0:
		var slot := _near[pick]
		slot.riser = true
		_riser.merge({"node": slot.node, "from": _am_at(slot, now), "y0": float(slot.y), "opacity": float(slot.alpha),
			"fade_in": false})
	else:
		var opacity: Array = _ladder.near.opacity
		_riser.merge({"node": _riser_node, "from": _am_of(_focus() + RISE_NEW_AT), "y0": RISE_NEW_Y,
			"opacity": (float(opacity[0]) + float(opacity[1])) * 0.5, "fade_in": true})
		_set_texture(_riser_node, species_id)
	# The other ghosts that waited for the rise fade out now.
	for slot in _near:
		if slot.get("may_rise", false) and not slot.get("riser", false):
			slot.leave_t = now
		slot.erase("may_rise")


## Every frame, after the camera moved: places, sizes and fades every billboard from `view`
## (PoolScene.scale_view: size, tile, depth_k, focus_am, tm_to_am, time_s) and the camera.
func apply_scale_view(view: Dictionary) -> void:
	if _ladder.is_empty() or camera == null:
		return
	_view = view
	var now := float(view.get("time_s", 0.0))
	var size := int(view.get("size", _size))
	if size != _size and _growth.is_empty():
		_resize(size)
	_size = size
	if not _growth.is_empty() and float(_growth.t0) < 0.0:
		_growth.t0 = now
		for slot in _near:
			if float(slot.get("leave_t", 0.0)) < 0.0:
				slot.leave_t = now + GROWTH_FADE.x
	_read_camera()
	var k := float(view.get("depth_k", 1.0))
	for i in _near.size():
		_step_near(i, now, k)
	for i in _far.size():
		_step_far(i, now, k)
	_step_rise(now, k)
	if not _growth.is_empty() and _growth_u(k) >= 1.0 and now - float(_growth.t0) >= GROWTH_FADE.x + GROWTH_FADE.y:
		for slot in _near:
			if slot.get("may_rise", false):
				slot.leave_t = now   # no rise came (a cut beat): it fades now
			slot.erase("may_rise")
		_growth = {}


## A size change with no beat (a dev size): ghosts no longer ahead leave at once.
func _resize(size: int) -> void:
	var ahead := near_species(size)
	for slot in _near:
		if not ahead.has(slot.species):
			slot.hold = true
			_hide(slot)


func _step_near(i: int, now: float, k: float) -> void:
	var slot := _near[i]
	if slot.get("riser", false):
		return
	var alpha := 0.0
	var staged: Dictionary = slot.get("staged", {})
	if _staging:
		if staged.is_empty() or not _ladder.species.has(str(staged.get("species", ""))):
			_hide(slot)
			return
		if slot.cycle == NO_CYCLE:
			slot.cycle = 0
			slot.species = str(staged.species)
			slot.anchor = _am_of(_focus() + (staged.offset as Vector2))
			slot.at_s = now
			slot.velocity = Vector2.ZERO
			var opacity: Array = _ladder.near.opacity
			slot.opacity = (float(opacity[0]) + float(opacity[1])) * 0.5
			_set_texture(slot.node, slot.species)
		alpha = slot.opacity
	else:
		var cycle := float(_ladder.near.cycle_s)
		var at := _cycle_at(i, _near.size(), cycle, now)
		var phase: float = at[1]
		if at[0] != slot.cycle:
			_start_near(slot, i, at[0], now)
		if slot.species == "" or slot.get("hold", false):
			_hide(slot)
			return
		var fade := float(_ladder.near.fade_s)
		alpha = slot.opacity * clampf(phase / fade, 0.0, 1.0) * clampf((cycle - phase) / fade, 0.0, 1.0)
	var leave_t := float(slot.get("leave_t", -1.0))
	if leave_t >= 0.0 and leave_t < INF:
		var gone := clampf((now - leave_t) / GROWTH_FADE.y, 0.0, 1.0)
		alpha *= 1.0 - gone
		if gone >= 1.0:
			slot.erase("leave_t")
			slot.hold = not _staging
			_hide(slot)
			return
	var y := _near_depth_now(slot.species, k)
	if _staging and staged.has("depth"):
		y = float(staged.depth)
	y = minf(y, float(_ladder.near.depth_tm[1]) * k)
	var p := _local_of(_am_at(slot, now), y)
	_draw(slot, p, _near_side(slot.species, p, k), alpha)


## Cycle j of near slot i: the next of the ahead species, anchored on the ring north of the focus now
## (radius and bearing hashed from the seed, size, tile, slot and cycle) and drifting.
func _start_near(slot: Dictionary, i: int, j: int, now: float) -> void:
	slot.cycle = j
	slot.hold = false
	slot.erase("leave_t")
	slot.erase("may_rise")
	var ahead := near_species(_size)
	slot.species = ahead[posmod(i + j, ahead.size())] if not ahead.is_empty() else ""
	if slot.species == "":
		return
	var near: Dictionary = _ladder.near
	var key := [_seed, _size, _view.get("tile", Vector2i.ZERO), i, j]
	var r := lerpf(float(near.ring_tm[0]), float(near.ring_tm[1]), _unit(key, 0))
	var bearing := deg_to_rad(-90.0 + RING_SPREAD_DEG * (2.0 * _unit(key, 1) - 1.0))
	var drift := TAU * _unit(key, 2)
	var tm := float(_view.tm_to_am)
	slot.anchor = _am_of(_focus() + Vector2(cos(bearing), sin(bearing)) * r)
	slot.at_s = now
	slot.velocity = Vector2(cos(drift), sin(drift)) * float(near.drift_tm_s) * tm
	slot.opacity = lerpf(float(near.opacity[0]), float(near.opacity[1]), _unit(key, 3))
	_set_texture(slot.node, slot.species)


func _step_far(i: int, now: float, k: float) -> void:
	var slot := _far[i]
	var far: Dictionary = _ladder.far
	var cycle := float(far.cycle_s)
	var at := _cycle_at(i, _far.size(), cycle, now)
	var alpha := 0.0
	var depth := 0.0
	if i == 0 and _step_pass(slot, now, at[0]):
		var first: Dictionary = far.first_pass
		var t := now - float(_pass.t0)
		var duration := float(first.duration_s)
		alpha = float(far.opacity) * clampf(t / FIRST_PASS_FADE_S, 0.0, 1.0) * clampf((duration - t) / FIRST_PASS_FADE_S, 0.0, 1.0)
		depth = float(first.depth_tm)
	elif _staging:
		var staged: Dictionary = slot.get("staged", {})
		if staged.is_empty():
			_hide(slot)
			return
		if slot.cycle == NO_CYCLE:
			slot.cycle = 0
			slot.anchor = _am_of(_focus() + (staged.offset as Vector2))
			slot.at_s = now
			slot.velocity = Vector2.ZERO
			slot.depth = float(staged.get("depth", (float(far.depth_tm[0]) + float(far.depth_tm[1])) * 0.5))
		alpha = float(far.opacity)
		depth = float(slot.depth)
	else:
		var phase: float = at[1]
		if at[0] != slot.cycle:
			_start_far(slot, i, at[0], now, phase)
		if slot.get("hold", false):
			_hide(slot)
			return
		alpha = float(far.opacity) * clampf(phase / FAR_FADE_S, 0.0, 1.0) * clampf((cycle - phase) / FAR_FADE_S, 0.0, 1.0)
		depth = float(slot.depth)
	var p := _local_of(_am_at(slot, now), depth * k)
	_draw(slot, p, _far_side(slot, p), alpha)


## Cycle j of far slot i: from FAR_REACH_TM west of the focus at its start to as far east at its end,
## at a hashed z and depth; seen first part way through, it is placed where its crossing has got to.
func _start_far(slot: Dictionary, i: int, j: int, now: float, phase: float) -> void:
	slot.cycle = j
	slot.hold = false
	var far: Dictionary = _ladder.far
	var key := [_seed, i, j, "far"]
	var z := lerpf(FAR_Z_TM.x, FAR_Z_TM.y, _unit(key, 0))
	slot.depth = lerpf(float(far.depth_tm[0]), float(far.depth_tm[1]), _unit(key, 1))
	var tm := float(_view.tm_to_am)
	slot.anchor = _am_of(_focus() + Vector2(-FAR_REACH_TM, z))
	slot.at_s = now - phase
	slot.velocity = Vector2(2.0 * FAR_REACH_TM / float(far.cycle_s), 0.0) * tm


## Far slot 0 during the first pass: true while the pass draws it. The pass starts (and is told) at its
## time; when it is over the slot waits out its cycle `j` and shows again at the next.
func _step_pass(slot: Dictionary, now: float, j: int) -> bool:
	if _pass.is_empty():
		if _passed or _pass_at < 0.0 or now < _pass_at:
			return false
		_passed = true
		var first: Dictionary = _ladder.far.first_pass
		var tm := float(_view.tm_to_am)
		_pass = {"t0": now}
		slot.anchor = _am_of(_focus() + Vector2(-FAR_REACH_TM, FIRST_PASS_Z_TM))
		slot.at_s = now
		slot.velocity = Vector2(2.0 * FAR_REACH_TM / float(first.duration_s), 0.0) * tm
		first_pass_started.emit()
		return true
	if now - float(_pass.t0) < float(_ladder.far.first_pass.duration_s):
		return true
	_pass = {}
	slot.hold = true
	slot.cycle = j
	return false


func _step_rise(now: float, k: float) -> void:
	if _riser.is_empty():
		return
	if float(_riser.t0) < 0.0:
		_riser.t0 = now
	var t := now - float(_riser.t0)
	var e := ease_out_cubic(clampf(t / RISE_S, 0.0, 1.0))
	var from: PackedFloat64Array = _riser.from
	var toward: PackedFloat64Array = _riser.toward
	var dx := toward[0] - from[0]
	var dy := toward[1] - from[1]
	var length := sqrt(dx * dx + dy * dy)
	var tm := float(_view.tm_to_am)
	var rise_share := minf(RISE_SHARE, RISE_MOVE_MAX_TM * tm / length) if length > 0.0 else 0.0
	var share := rise_share * e
	if t > RISE_S:
		var swum := RISE_SWIM_TM_S * tm * (t - RISE_S)
		share = minf(1.0, rise_share + (swum / length if length > 0.0 else 1.0))
	var at := PackedFloat64Array([from[0] + dx * share, from[1] + dy * share])
	var top := float(_ladder.near.rise_depth_tm)
	var y := minf(lerpf(float(_riser.y0), top, e), top)
	var p := _local_of(at, y)
	var on_screen := _on_screen(p)
	_riser.seen = _riser.seen or on_screen
	if float(_riser.fade_t) < 0.0 and ((_riser.seen and not on_screen) or t >= RISE_GONE_S - RISE_FADE_S):
		_riser.fade_t = now
	var alpha := float(_riser.opacity)
	if _riser.fade_in:
		alpha *= clampf(t / RISE_FADE_S, 0.0, 1.0)
	if float(_riser.fade_t) >= 0.0:
		alpha *= 1.0 - clampf((now - float(_riser.fade_t)) / RISE_FADE_S, 0.0, 1.0)
	if alpha <= 0.0 and t > 0.0:
		_end_rise()
		return
	var slot := {"node": _riser.node}
	_draw(slot, p, _near_side(str(_riser.species), p, k), alpha)


## Ends the rise: its billboard hides, and a near slot it came from waits for its next cycle.
func _end_rise() -> void:
	if _riser.is_empty():
		return
	(_riser.node as MeshInstance3D).visible = false
	var pick := int(_riser.slot)
	if pick >= 0 and pick < _near.size():
		var slot := _near[pick]
		slot.erase("riser")
		slot.erase("leave_t")
		if not _staging:
			slot.hold = true
			slot.cycle = _cycle_at(pick, _near.size(), float(_ladder.near.cycle_s), float(_view.get("time_s", 0.0)))[0]
		_hide(slot)
	_riser = {}


## A near ghost's depth now: its size's, or during a growth the blend from the old size's (times
## k_from) to the new size's as k runs to 1.
func _near_depth_now(species_id: String, k: float) -> float:
	var y := near_depth(_ladder, species_id, _size)
	if not _growth.is_empty():
		var old := near_depth(_ladder, species_id, int(_growth.from)) * float(_growth.k_from)
		y = lerpf(old, y, _growth_u(k))
	return y


## A near ghost's quad side at `p` now (V-11): its true diameter times a draw scale that keeps it at
## least design_multiple times the cell for its view depth and the cell's, at least its base and at
## most max_draw_scale, over its body's span; blended across a growth as its depth is.
func _near_side(species_id: String, p: Vector3, k: float) -> float:
	var z_g := _view_depth(p)
	var z_c := camera.shown_distance()
	var side := _rule_side(species_id, _size, z_g, z_c)
	if not _growth.is_empty():
		var old := _rule_side(species_id, int(_growth.from), z_g, z_c) * float(_growth.k_from)
		side = lerpf(old, side, _growth_u(k))
	return side


func _rule_side(species_id: String, n: int, z_g: float, z_c: float) -> float:
	var near: Dictionary = _ladder.near
	var r := true_radius(_ladder, species_id, n)
	var rel := r / CELL_RADIUS_TM
	var want := float(near.design_multiple) * z_g / (rel * maxf(z_c, 1e-3))
	var scale := minf(maxf(want, near_base_scale(_ladder, species_id, n)), float(near.max_draw_scale))
	var rect: Array = _ladder.species[species_id].body_rect
	var span := maxf(float(rect[2]) - float(rect[0]), float(rect[3]) - float(rect[1]))
	return 2.0 * r * scale / span


## A far giant's quad side at `p`: stepped each frame toward the side whose body takes screen_share of
## the screen's height, measured through the camera.
func _far_side(slot: Dictionary, p: Vector3) -> float:
	var target := float(_ladder.far.screen_share)
	var rect: Array = slot.rect
	var side := float(slot.side)
	if side <= 0.0:
		side = target * 0.8284 * _view_depth(p) / ((float(rect[3]) - float(rect[1])) * VIEW_DROP)
	for step in FAR_STEPS:
		var share := body_share(p, side, rect)
		if share <= 1e-6:
			break
		side *= target / share
	slot.side = side
	return side


## The screen-height share of the body rect `rect` of a flat quad `side` across centred at `p` (this
## layer's space): its corners through the camera, their vertical extent over the screen's height.
## 0 when a corner is behind the camera.
func body_share(p: Vector3, side: float, rect: Array) -> float:
	var lo := INF
	var hi := -INF
	for corner in [Vector2(rect[0], rect[1]), Vector2(rect[2], rect[1]), Vector2(rect[0], rect[3]), Vector2(rect[2], rect[3])]:
		var c := _clip(p + Vector3((corner.x - 0.5) * side, 0.0, (corner.y - 0.5) * side))
		if c.w <= 1e-6:
			return 0.0
		lo = minf(lo, c.y / c.w)
		hi = maxf(hi, c.y / c.w)
	return (hi - lo) * 0.5


func _draw(slot: Dictionary, p: Vector3, side: float, alpha: float) -> void:
	var node: MeshInstance3D = slot.node
	slot.alpha = alpha
	slot.y = p.y
	slot.side = side
	node.visible = alpha > 0.0
	if not node.visible:
		return
	node.transform = Transform3D(Basis.from_scale(Vector3.ONE * side), p)
	(node.material_override as ShaderMaterial).set_shader_parameter("opacity", alpha)


func _hide(slot: Dictionary) -> void:
	slot.alpha = 0.0
	(slot.node as MeshInstance3D).visible = false


func _billboard(node_name: String, brightness: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = quad()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _material(null, brightness)
	node.visible = false
	add_child(node)
	return node


func _set_texture(node: MeshInstance3D, species_id: String) -> void:
	var path := str(_ladder.species[species_id].texture)
	(node.material_override as ShaderMaterial).set_shader_parameter("image", load(path))


## Slot i of `count` at time `now`: [its cycle index, seconds into that cycle]. The slots are spread
## evenly over the cycle, half a step in, so each starts part way through and in sight.
static func _cycle_at(i: int, count: int, cycle_s: float, now: float) -> Array:
	var u := now + (i + 0.5) * cycle_s / count
	var j := floori(u / cycle_s)
	return [j, u - j * cycle_s]


func _growth_u(k: float) -> float:
	if _growth.is_empty():
		return 1.0
	var kf := float(_growth.k_from)
	return clampf((k - kf) / (1.0 - kf), 0.0, 1.0) if kf < 1.0 else 1.0


# --- frames ---

## The focus on the plane (local tm), as the view's focus_am is.
func _focus() -> Vector2:
	return Vector2(camera.focus.x, camera.focus.z)


## The absolute point (am) of a local plane point now, through float64.
func _am_of(p: Vector2) -> PackedFloat64Array:
	var focus_am: PackedFloat64Array = _view.focus_am
	var tm := float(_view.tm_to_am)
	var f := _focus()
	return PackedFloat64Array([focus_am[0] + (float(p.x) - f.x) * tm, focus_am[1] + (float(p.y) - f.y) * tm])


## A slot's absolute point (am) at time `now`: its anchor plus its drift since it was anchored.
func _am_at(slot: Dictionary, now: float) -> PackedFloat64Array:
	var anchor: PackedFloat64Array = slot.anchor
	var v: Vector2 = slot.velocity
	var dt := now - float(slot.at_s)
	return PackedFloat64Array([anchor[0] + v.x * dt, anchor[1] + v.y * dt])


## This layer's point for an absolute point (am) at height `y`: focus + (am - focus_am) / tm_to_am,
## the subtraction in float64.
func _local_of(am: PackedFloat64Array, y: float) -> Vector3:
	var focus_am: PackedFloat64Array = _view.focus_am
	var tm := float(_view.tm_to_am)
	return Vector3(camera.focus.x + (am[0] - focus_am[0]) / tm, y, camera.focus.z + (am[1] - focus_am[1]) / tm)


func _read_camera() -> void:
	_eye = camera.transform
	if camera.is_inside_tree() and is_inside_tree():
		_eye = global_transform.affine_inverse() * camera.global_transform
	_eye_inverse = _eye.affine_inverse()
	_lens = Projection.create_perspective(camera.fov, _aspect(), camera.near, camera.far)


func _aspect() -> float:
	if is_inside_tree():
		var size := get_viewport().get_visible_rect().size
		if size.y > 0.0:
			return size.aspect()
	return float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)) \
		/ float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


func _clip(p: Vector3) -> Vector4:
	var v := _eye_inverse * p
	return _lens * Vector4(v.x, v.y, v.z, 1.0)


func _view_depth(p: Vector3) -> float:
	return -(_eye_inverse * p).z


func _on_screen(p: Vector3) -> bool:
	var c := _clip(p)
	return c.w > 0.0 and absf(c.x / c.w) <= 1.0 and absf(c.y / c.w) <= 1.0


## A unit value in [0, 1) hashed from `key` and `salt`.
static func _unit(key: Array, salt: int) -> float:
	return float(str(key + [salt]).hash() & 0xFFFFFF) / 16777216.0


static func ease_out_cubic(u: float) -> float:
	return 1.0 - pow(1.0 - u, 3.0)
