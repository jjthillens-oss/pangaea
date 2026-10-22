class_name PoolAmbience
extends Node3D
## The microscopic world's decor (docs/DECISIONS.md, "The cell stage reads as a microscopic world"):
## specks and bubbles drifting in the depths and a few above the plane, swarms of microbes under
## the swim plane that part around the cell, and huge out-of-focus organisms far below.
##
## Presentation only: it reads the camera and the player cell's position, never the simulation,
## and draws from its own random numbers, so the pool sim stays deterministic. Nothing here
## collides. Colours keep clear of the food green and the threat pink, and nothing decorative sits
## on the swim plane (/mnt/project-files/pangaea/docs/ambience-handoff.md). All numbers are PROPOSED.

const DRIFT_SHADER := preload("res://game/scenes/pool/ambience/drift.gdshader")
const BACKDROP_SHADER := preload("res://game/scenes/pool/ambience/backdrop.gdshader")
const BACKDROP_DIR := "res://assets/export/ambience/"
const SEED := 0x5EED_A1B1

## Wrap box across and along the plane, m: wider than the furthest zoom's view (20 m away at
## 55 degrees and 45 degrees of FOV sees about 36 m across a 16:9 frame).
const BOX := Vector2(48.0, 40.0)

## Kinds, as drift.gdshader draws them.
enum Kind { SPECK, BUBBLE, ROD, SPIRILLUM, SPORE }

## Each drifting layer: how many quads, which kinds (weighted), their size and opacity ranges,
## the vertical band they wrap in, and how they move. Bands follow the ambience contract
## (/mnt/project-files/pangaea/docs/micro-world-plan.md section 7): nothing within -1.5 to +0.5 m
## of the swim plane, a sparse foreground above it, the rest below where the height fog takes it.
## Each tint's linear luminance times the layer's top opacity stays at or under MAX_LUMA_ALPHA, so
## pale decor never lifts the fluid behind the cell or the strike lanes; the shader never draws a
## quad brighter than its tint. Totals stay under the 2,000-particle budget.
const MAX_LUMA_ALPHA := 0.12
const LAYERS := {
	"Foreground": {
		"count": 40, "kinds": {Kind.SPECK: 0.7, Kind.BUBBLE: 0.3}, "size": Vector2(0.02, 0.06), "alpha": Vector2(0.05, 0.12),
		"height": Vector2(0.6, 2.8), "drift": Vector3(0.05, 0.01, -0.03), "wobble": 0.2,
		"tints": ["#B7C4E6", "#A9B6E0", "#D2B98A"],
	},
	"Specks": {
		"count": 900, "kinds": {Kind.SPECK: 1.0}, "size": Vector2(0.03, 0.09), "alpha": Vector2(0.1, 0.28),
		"height": Vector2(-30.0, -3.0), "drift": Vector3(0.05, 0.02, -0.03), "wobble": 0.3,
		"tints": ["#96A8CC", "#A294CC", "#C2A47C"],
	},
	"Bubbles": {
		"count": 120, "kinds": {Kind.BUBBLE: 1.0}, "size": Vector2(0.1, 0.34), "alpha": Vector2(0.14, 0.3),
		"height": Vector2(-10.0, -3.0), "drift": Vector3(0.02, 0.18, -0.01), "wobble": 0.15,
		"tints": ["#96A8CC", "#96A8CC", "#96A8CC"],
	},
	# Swarms in the midground. They part around the cell from below as it swims over them.
	"Microbes": {
		"count": 480, "kinds": {Kind.ROD: 0.6, Kind.SPIRILLUM: 0.2, Kind.SPORE: 0.2}, "size": Vector2(0.4, 0.7),
		"alpha": Vector2(0.22, 0.32), "height": Vector2(-7.0, -3.0), "drift": Vector3(0.06, 0.0, 0.04), "wobble": 0.6,
		"tints": ["#8FA6C8", "#9A86D0", "#C09048"], "clusters": 18, "scatter": 2.6, "scatter_depth": 8.0,
	},
}

## Huge organisms far below the plane, pre-blurred in their textures (no depth of field). Their
## colour is scaled by BACKDROP_BRIGHTNESS so the brightest texel stays at or under linear
## luminance 0.40, and their opacity keeps luminance times alpha under MAX_LUMA_ALPHA.
const BACKDROP_COUNT := 10
const BACKDROP_DEPTH := Vector2(-22.0, -12.0)
const BACKDROP_SIZE := Vector2(10.0, 24.0)
const BACKDROP_BOX := Vector2(90.0, 80.0)
const BACKDROP_BRIGHTNESS := 0.38
const BACKDROP_OPACITY := Vector2(0.2, 0.28)

var _rng := RandomNumberGenerator.new()
var _materials: Array[ShaderMaterial] = []
var _backdrops: Array[MeshInstance3D] = []
var _player: Node3D
var _camera: Camera3D


func _ready() -> void:
	_rng.seed = SEED
	for layer_name: String in LAYERS:
		add_child(_drift_layer(layer_name, LAYERS[layer_name]))
	_build_backdrops()
	# The pool mounts this scene and exposes its camera and cell view (micro-world plan C6).
	var pool := get_parent()
	if pool != null:
		_player = pool.get("cell_view") as Node3D
		_camera = pool.get("camera") as Camera3D


func _process(delta: float) -> void:
	var camera := _camera if _camera != null else get_viewport().get_camera_3d()
	if camera == null:
		return
	var focus := _focus_of(camera)
	var player := _player.global_position if _player != null and _player.is_visible_in_tree() else Vector3(0.0, -100.0, 0.0)
	for material in _materials:
		material.set_shader_parameter("focus", focus)
		material.set_shader_parameter("player", player)
	_recycle_backdrops(focus, delta)


## The number of drifting quads, for the budget test.
func particle_count() -> int:
	var total := 0
	for child in get_children():
		if child is MultiMeshInstance3D:
			total += (child as MultiMeshInstance3D).multimesh.instance_count
	return total


func backdrop_count() -> int:
	return _backdrops.size()


func _focus_of(camera: Camera3D) -> Vector3:
	var value: Variant = camera.get("focus")
	if value is Vector3:
		return value
	# Any other camera: where its view meets the swim plane.
	var forward := -camera.global_basis.z
	if forward.y < -0.01:
		return camera.global_position + forward * (-camera.global_position.y / forward.y)
	return Vector3(camera.global_position.x, 0.0, camera.global_position.z)


func _drift_layer(layer_name: String, spec: Dictionary) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = spec.count
	var height: Vector2 = spec.height
	var centres: Array[Vector3] = []
	for i in int(spec.get("clusters", 0)):
		centres.append(Vector3(_rng.randf_range(-0.5, 0.5) * BOX.x, _rng.randf_range(height.x, height.y), _rng.randf_range(-0.5, 0.5) * BOX.y))
	for i in mm.instance_count:
		var p: Vector3
		if centres.is_empty():
			p = Vector3(_rng.randf_range(-0.5, 0.5) * BOX.x, _rng.randf_range(height.x, height.y), _rng.randf_range(-0.5, 0.5) * BOX.y)
		else:
			# Swarms: most microbes gather in loose clusters, a few roam alone.
			var c := centres[i % centres.size()]
			p = c + Vector3(_rng.randfn(0.0, 0.8), _rng.randfn(0.0, 0.4), _rng.randfn(0.0, 0.8)) if _rng.randf() < 0.85 \
				else Vector3(_rng.randf_range(-0.5, 0.5) * BOX.x, c.y, _rng.randf_range(-0.5, 0.5) * BOX.y)
			p.y = clampf(p.y, height.x, height.y)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		var size: Vector2 = spec.size
		var alpha: Vector2 = spec.alpha
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(size.x, size.y), _pick_kind(spec.kinds), _rng.randf_range(alpha.x, alpha.y)))
	var material := ShaderMaterial.new()
	material.shader = DRIFT_SHADER
	material.set_shader_parameter("box", BOX)
	material.set_shader_parameter("height_range", height)
	material.set_shader_parameter("drift", spec.drift)
	material.set_shader_parameter("wobble", spec.wobble)
	material.set_shader_parameter("scatter_radius", spec.get("scatter", 0.0))
	material.set_shader_parameter("scatter_depth", spec.get("scatter_depth", 3.0))
	var tints: Array = spec.tints
	material.set_shader_parameter("tint_a", Color(tints[0]))
	material.set_shader_parameter("tint_b", Color(tints[1]))
	material.set_shader_parameter("tint_c", Color(tints[2]))
	_materials.append(material)
	var node := MultiMeshInstance3D.new()
	node.name = layer_name
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves every quad, so the node is never culled.
	node.custom_aabb = AABB(Vector3(-1e4, -1e3, -1e4), Vector3(2e4, 2e3, 2e4))
	return node


func _pick_kind(kinds: Dictionary) -> float:
	var total := 0.0
	for k in kinds:
		total += kinds[k]
	var roll := _rng.randf() * total
	for k in kinds:
		roll -= kinds[k]
		if roll <= 0.0:
			return float(k)
	return float(kinds.keys()[0])


func _build_backdrops() -> void:
	var textures: Array[Texture2D] = []
	if DirAccess.dir_exists_absolute(BACKDROP_DIR):
		for file in DirAccess.get_files_at(BACKDROP_DIR):
			if file.ends_with(".png"):
				textures.append(load(BACKDROP_DIR + file))
	if textures.is_empty():
		return
	for i in BACKDROP_COUNT:
		var quad := QuadMesh.new()
		var size := _rng.randf_range(BACKDROP_SIZE.x, BACKDROP_SIZE.y)
		quad.size = Vector2(size, size)
		quad.orientation = PlaneMesh.FACE_Y
		var material := ShaderMaterial.new()
		material.shader = BACKDROP_SHADER
		material.set_shader_parameter("image", textures[i % textures.size()])
		material.set_shader_parameter("opacity", _rng.randf_range(BACKDROP_OPACITY.x, BACKDROP_OPACITY.y))
		material.set_shader_parameter("brightness", BACKDROP_BRIGHTNESS)
		var node := MeshInstance3D.new()
		node.name = "Backdrop%d" % i
		node.mesh = quad
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(_rng.randf_range(-0.5, 0.5) * BACKDROP_BOX.x, _rng.randf_range(BACKDROP_DEPTH.x, BACKDROP_DEPTH.y),
			_rng.randf_range(-0.5, 0.5) * BACKDROP_BOX.y)
		node.rotation.y = _rng.randf() * TAU
		node.set_meta("drift", Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15)))
		node.set_meta("spin", _rng.randf_range(-0.02, 0.02))
		add_child(node)
		_backdrops.append(node)


## Backdrops drift and turn slowly, and wrap around the camera's focus like the drifting layers.
func _recycle_backdrops(focus: Vector3, delta: float) -> void:
	for node in _backdrops:
		var p := node.position + (node.get_meta("drift") as Vector3) * delta
		p.x = focus.x - BACKDROP_BOX.x * 0.5 + fposmod(p.x - (focus.x - BACKDROP_BOX.x * 0.5), BACKDROP_BOX.x)
		p.z = focus.z - BACKDROP_BOX.y * 0.5 + fposmod(p.z - (focus.z - BACKDROP_BOX.y * 0.5), BACKDROP_BOX.y)
		node.position = p
		node.rotation.y += float(node.get_meta("spin")) * delta
