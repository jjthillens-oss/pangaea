class_name OlderHaze
extends Node3D
## The haze of older sizes (S3, docs/s3/s3-view.md V3-14 and 9.3; D-106): from FROM_SIZE the plant
## food of the size before lies far under the swim plane as a faint glitter of its haze sprite
## (T_Haze_algae_ball at 3, T_Haze_glass_flake at 4), so the sea keeps the scale the cell outgrew.
## One MultiMesh: PER_CHUNK billboards in each 32 tm chunk on a jittered GRID x GRID grid, over the
## focus chunk and the eight round it (216, under MAX), each at a height in HEIGHT_RANGE and a quad
## the older food's drawn diameter over its sprite's span (GrowthBeat.HAZE_SPANS). Every place comes
## from WorldHash (seed, size, chunk, index), so the same sea shows the same haze.
##
## refresh() rebuilds only when the focus moves into another chunk. WorldSpace shifts this node
## across a rebase, so the instances are placed in its frame. At a growth it keeps the container
## contract (s2-view 4.5): apply_growth re-expresses the drawn set in place, and end_growth rebuilds
## for the new size and fades it in over FADE_S; a growth to FROM_SIZE fades the first set in from
## FIRST_FADE_FROM_S of the beat, as the beat's glitter of the same food sinks to that depth.

const PER_CHUNK := 24
const MAX := 400                    ## 3 x 3 chunks x 24 = 216
const CHUNK_TM := 32.0
const GRID := 5
const JITTER := 0.7                 ## the share of its grid cell an item moves over (0.15 in from each side)
const HEIGHT_RANGE := Vector2(-3.4, -2.6)
const TINT := Color("#B8C4D6")
const BRIGHTNESS := 0.7
const OPACITY := 0.25
const FROM_SIZE := 3
const FADE_S := 1.0
const FIRST_FADE_FROM_S := 2.0
const SHADER := preload("res://game/scenes/pool/older_haze.gdshader")

## The size the haze is drawn for.
var size := 1

var _food_haze := {}                ## plant look -> haze texture path (ghost_ladder.json food_haze)
var _food_looks: Array = []         ## world_cell.json ladder.food_looks
var _seed := 0
var _key: Variant = null            ## the focus chunk drawn (Vector2i), or null
var _items: StillInstances
var _material := ShaderMaterial.new()
var _look := ""                     ## the plant look drawn ("" hidden)
var _side := 0.0                    ## a quad's side (tm)
var _fade := 1.0                    ## the share of OPACITY shown
var _fade_t := -1.0                 ## seconds into a fade in, -1 when none runs
var _last_t := -1.0                 ## step()'s last draw time
var _beat := false
var _beat_to := 0
var _world: WorldStream             ## the stream and focus last refreshed from
var _focus := Vector2.ZERO
static var _quad: QuadMesh


func _init() -> void:
	name = "OlderHaze"
	_material.shader = SHADER
	_material.set_shader_parameter("tint", TINT)
	_material.set_shader_parameter("brightness", BRIGHTNESS)
	_material.set_shader_parameter("height_range", HEIGHT_RANGE)
	_apply_opacity()
	visible = false


## The ladder's food hazes, the world's food looks and its seed; nothing drawn until set_size.
func setup(ladder: Dictionary, food_looks: Array, world_seed: int) -> void:
	_food_haze = ladder.get("food_haze", {})
	_food_looks = food_looks
	_seed = world_seed
	set_size(1)


## The haze for size `n` at once (no fade): hidden below FROM_SIZE or without a look for it, else the
## size before's plant food. The next refresh() places it.
func set_size(n: int) -> void:
	size = n
	_clear()
	_look = ""
	_fade = 1.0
	_fade_t = -1.0
	if n >= FROM_SIZE and n - 2 < _food_looks.size():
		var plant := str((_food_looks[n - 2] as Dictionary).get("plant", ""))
		var path := str(_food_haze.get(plant, ""))
		if not path.is_empty() and ResourceLoader.exists(path) and FoodView.LOOKS.has(plant):
			_look = plant
			_material.set_shader_parameter("image", load(path) as Texture2D)
			_side = side_of(plant, path)
	visible = not _look.is_empty()
	_apply_opacity()


## A quad's side for the haze of `plant` drawn with the sprite at `path`: its food's diameter at the
## size after (WorldConfig.GROWTH_FACTOR smaller) over the sprite's span.
static func side_of(plant: String, path: String) -> float:
	var radius := float(FoodView.LOOKS[plant].radius)
	return 2.0 * radius / WorldConfig.GROWTH_FACTOR / float(GrowthBeat.HAZE_SPANS.get(path.get_file(), 1.0))


## Rebuilds the haze round `focus_local` when its focus chunk has changed (nothing while a growth beat
## runs: end_growth places the new size's).
func refresh(world: WorldStream, focus_local: Vector2) -> void:
	_world = world
	_focus = focus_local
	if world == null or _look.is_empty() or _beat:
		return
	var key := focus_chunk(world, focus_local)
	if _key != null and _key == key:
		return
	_build(world, key)


## The 32 tm chunk (absolute tm at the stream's size) holding `focus_local`.
static func focus_chunk(world: WorldStream, focus_local: Vector2) -> Vector2i:
	var am := world.abs_of_local(focus_local)
	var tm_to_am := WorldConfig.tm_to_am(world.size)
	return Vector2i(floori(am[0] / tm_to_am / CHUNK_TM), floori(am[1] / tm_to_am / CHUNK_TM))


## Item `i` of chunk (cx, cy) at size `n`: its absolute tm place (x, y) and height (z).
static func item(world_seed: int, n: int, cx: int, cy: int, i: int) -> Vector3:
	var h := WorldHash.hash_ints(PackedInt64Array([world_seed, n, cx, cy, i]))
	var u := WorldHash.unit(WorldHash.mix32(h, 1))
	var v := WorldHash.unit(WorldHash.mix32(h, 2))
	var w := WorldHash.unit(WorldHash.mix32(h, 3))
	var cell := CHUNK_TM / GRID
	var lo := (1.0 - JITTER) * 0.5
	return Vector3(cx * CHUNK_TM + (i % GRID + lo + JITTER * u) * cell, cy * CHUNK_TM + (floori(i / float(GRID)) + lo + JITTER * v) * cell,
		lerpf(HEIGHT_RANGE.x, HEIGHT_RANGE.y, w))


func instance_count() -> int:
	return _items.multimesh.instance_count if _items != null else 0


## The drawn items, for tests: a StillInstances in this node's frame, or null.
func items() -> StillInstances:
	return _items


## The plant look drawn ("" when hidden).
func look() -> String:
	return _look


func material() -> ShaderMaterial:
	return _material


## The opacity drawn now (OPACITY once any fade is over).
func opacity() -> float:
	return OPACITY * _fade


## Advances a fade in by the drawn sim time `draw_t` (the pool's _process): it stops while paused.
func step(draw_t: float) -> void:
	var delta := maxf(draw_t - _last_t, 0.0) if _last_t >= 0.0 else 0.0
	_last_t = draw_t
	if _fade_t < 0.0:
		return
	_fade_t += delta
	_fade = clampf(_fade_t / FADE_S, 0.0, 1.0)
	if _fade >= 1.0:
		_fade_t = -1.0
	_apply_opacity()


## What the start fade draws once so the haze's shader is ready (T4.6): one sprite of the first
## older food.
static func warm_up_meshes() -> Array[Mesh]:
	var sprite := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("image", load(GrowthBeat.FOOD_HAZE.algae_ball) as Texture2D)
	sprite.material = m
	return [sprite] as Array[Mesh]


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


# --- the container contract ---

## A growth to size `to` opens (the pool calls it before apply_growth).
func begin_growth(to: int) -> void:
	_beat_to = to


## Moves the items by this node's position and the node back to the origin: nothing moves on screen
## (WorldSpace.renormalize_far).
func renormalize() -> void:
	if _items != null:
		_items.position += position
	position = Vector3.ZERO


## A growth: the drawn set re-expressed in place round `center_old` by 1 / `factor`, this node back
## at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	if _items != null:
		var t := _items.transform
		_items.transform = Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin + shift, center_old, factor))
	_beat = true


## The haze is not made of chunks: nothing retires.
func retire_chunk(_chunk: Vector2i) -> void:
	pass


func settle_growth() -> void:
	pass


## Each beat frame: a growth to FROM_SIZE fades the first set in from FIRST_FADE_FROM_S.
func beat_frame(t: float, _k: float) -> void:
	if _beat and _beat_to == FROM_SIZE and size != _beat_to and t >= FIRST_FADE_FROM_S:
		_show_size(_beat_to)


## The beat is over: the new size's set, faded in over FADE_S unless it already is.
func end_growth() -> void:
	if not _beat:
		return
	_beat = false
	if _beat_to > 0 and size != _beat_to:
		_show_size(_beat_to)
	_beat_to = 0


func _show_size(n: int) -> void:
	var beat := _beat
	set_size(n)
	_beat = false
	refresh(_world, _focus)
	_beat = beat
	if not _look.is_empty():
		_fade = 0.0
		_fade_t = 0.0
		_apply_opacity()


func _build(world: WorldStream, key: Vector2i) -> void:
	_clear()
	_key = key
	var basis := Basis.from_scale(Vector3.ONE * _side)
	var transforms: Array[Transform3D] = []
	for cy in range(key.y - 1, key.y + 2):
		for cx in range(key.x - 1, key.x + 2):
			for i in PER_CHUNK:
				var at := item(_seed, size, cx, cy, i)
				transforms.append(Transform3D(basis, WorldSpace.to_frame(self, world.local_of_tm(at.x, at.y), at.z)))
	_items = StillInstances.make(quad(), transforms)
	_items.name = "Items"
	_items.material_override = _material
	add_child(_items)


func _clear() -> void:
	_key = null
	if _items != null:
		remove_child(_items)
		_items.free()
		_items = null


func _apply_opacity() -> void:
	_material.set_shader_parameter("opacity", OPACITY * _fade)
