class_name VeilThreadsView
extends Node3D
## A stinger veil's threads (S3, docs/s3/s3-view.md 8.2): art's thread rig fitted inside the sim's
## thread capsule (CreatureBrain.thread_capsule), so what a player sees is exactly what stings, and
## a soft capsule outline round it. The threads carry the threat ink (M_VeilThreadInk) while they can
## sting the cell and fade to M_VeilThreadNeutral once it has outgrown them, and flash on a sting.
##
## The view sits under the creature view's root, which is translated only (the Pivot turns), so its
## frame is world-aligned: set_capsule() takes the capsule's ends relative to the drawn position.
## Rig takes the scaled fit (x by r, z by the length); Outline is in the same frame with no scale.

const RIG := "res://assets/export/veil_threads.glb"
const RIG_HALF_WIDTH := 0.82       ## the GLB's x extent (its record's 1.637 m across)
const FIT := 0.85                  ## the rig's half-width inside the unit capsule...
const SWAY := 0.15                 ## ...so the shader's sway (at most this at a tip) stays inside it
const OUTLINE_W_TM := 0.06
const FILL_ALPHA := 0.10
const OUTLINE_ALPHA := Vector2(0.6, 0.85)   ## (neutral, ink)
const THREAD_Y := -0.01            ## over the lane (-0.02), under the bodies
const INK_FADE_S := 1.0
const FLASH_S := 0.15
const INK_MATERIAL := "res://assets/export/M_VeilThreadInk.tres"
const NEUTRAL_MATERIAL := "res://assets/export/M_VeilThreadNeutral.tres"
const THREADS_SHADER := preload("res://game/scenes/pool/veil_threads.gdshader")
const OUTLINE_SHADER := preload("res://game/scenes/pool/capsule_outline.gdshader")
const OUTLINE_MARGIN_TM := 0.1

## Shown ink, 0 (neutral) to 1 (can sting).
var ink := 1.0
var flash_share := 0.0

var _ink_target := 1.0
var _ink_rate := 0.0
var _flash_t := -1.0
var _capsule := {}
var _rig: MeshInstance3D
var _outline: MeshInstance3D
var _rig_material := ShaderMaterial.new()
var _outline_material := ShaderMaterial.new()
var _outline_mesh := PlaneMesh.new()
static var _unit_mesh: ArrayMesh
static var _colors := {}


func _init() -> void:
	name = "Threads"
	var colors := ink_colors()
	_rig = MeshInstance3D.new()
	_rig.name = "Rig"
	_rig.mesh = unit_mesh()
	_rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig_material.shader = THREADS_SHADER
	_rig_material.set_shader_parameter("ink_color", colors.ink)
	_rig_material.set_shader_parameter("neutral_color", colors.neutral)
	_rig_material.set_shader_parameter("ink_energy", colors.ink_energy)
	_rig_material.set_shader_parameter("neutral_energy", colors.neutral_energy)
	_rig_material.set_shader_parameter("sway", SWAY)
	_rig_material.set_shader_parameter("phase", randf() * TAU)
	_rig.material_override = _rig_material
	add_child(_rig)
	_outline = MeshInstance3D.new()
	_outline.name = "Outline"
	_outline.mesh = _outline_mesh
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.render_priority = CreatureView.LANE_PRIORITY - 1
	_outline_material.set_shader_parameter("ink_color", colors.ink)
	_outline_material.set_shader_parameter("neutral_color", colors.neutral)
	_outline_material.set_shader_parameter("outline_w", OUTLINE_W_TM)
	_outline_material.set_shader_parameter("fill_alpha", FILL_ALPHA)
	_outline.material_override = _outline_material
	add_child(_outline)
	_apply()


## Fits the rig inside the capsule from `a` to `b` (view-local, on the swim plane) of radius `r`,
## and the outline round it.
func set_capsule(a: Vector3, b: Vector3, r: float) -> void:
	_capsule = {"a": a, "b": b, "r": r}
	var along := b - a
	var length := along.length()
	var z := along / length if length > 1e-6 else Vector3.BACK
	var x := Vector3.UP.cross(z)
	_rig.transform = Transform3D(Basis(x * r, Vector3.UP, z * maxf(length, 1e-6)), a)
	_outline.transform = Transform3D(Basis(x, Vector3.UP, z), a)
	_outline_mesh.size = Vector2(2.0 * (r + OUTLINE_MARGIN_TM), length + 2.0 * (r + OUTLINE_MARGIN_TM))
	_outline_mesh.center_offset = Vector3(0.0, 0.0, length * 0.5)
	_outline.set_instance_shader_parameter("length_tm", length)
	_outline.set_instance_shader_parameter("radius_tm", r)


## The capsule as last set: {a, b, r} (view-local), or {}.
func capsule() -> Dictionary:
	return _capsule


## The threat ink while the threads can sting the cell (q = 1), the neutral once they cannot, fading
## over `fade_s` (0: at once).
func set_ink(can_sting: bool, fade_s := 0.0) -> void:
	_ink_target = 1.0 if can_sting else 0.0
	_ink_rate = 1.0 / fade_s if fade_s > 0.0 else 0.0
	if fade_s <= 0.0:
		ink = _ink_target
	_apply()


## A sting landed: the threads flash bright for FLASH_S.
func flash() -> void:
	_flash_t = 0.0
	flash_share = 1.0
	_apply()


## Advances the ink fade and the flash (the creature view's _process calls it).
func step(delta: float) -> void:
	var changed := false
	if ink != _ink_target:
		ink = _ink_target if _ink_rate <= 0.0 else move_toward(ink, _ink_target, _ink_rate * delta)
		changed = true
	if _flash_t >= 0.0:
		_flash_t += delta
		flash_share = clampf(1.0 - _flash_t / FLASH_S, 0.0, 1.0)
		if _flash_t >= FLASH_S:
			_flash_t = -1.0
			flash_share = 0.0
		changed = true
	if changed:
		_apply()


## The thread colour shown now (albedo), for tests.
func shown_color() -> Color:
	var c := ink_colors()
	return (c.neutral as Color).lerp(c.ink, ink)


func rig_material() -> ShaderMaterial:
	return _rig_material


func outline_material() -> ShaderMaterial:
	return _outline_material


func _apply() -> void:
	_rig_material.set_shader_parameter("ink", ink)
	_rig_material.set_shader_parameter("flash", flash_share)
	_outline_material.set_shader_parameter("ink", ink)
	_outline_material.set_shader_parameter("outline_alpha", lerpf(OUTLINE_ALPHA.x, OUTLINE_ALPHA.y, ink))


## The rig remapped into the unit capsule (V3-12): each vertex's x over RIG_HALF_WIDTH times FIT,
## y 0, z its COLOR red (0 at the rim, 1 at a tip). Built once.
static func unit_mesh() -> ArrayMesh:
	if _unit_mesh != null:
		return _unit_mesh
	var root: Node3D = (load(RIG) as PackedScene).instantiate()
	var source: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays: Array = source.mesh.surface_get_arrays(0)
	root.free()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in vertices.size():
		vertices[i] = Vector3(vertices[i].x / RIG_HALF_WIDTH * FIT, 0.0, colors[i].r)
		normals[i] = Vector3.UP
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	_unit_mesh = ArrayMesh.new()
	_unit_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _unit_mesh


## {ink, neutral, ink_energy, neutral_energy}, read from art's two thread materials.
static func ink_colors() -> Dictionary:
	if _colors.is_empty():
		var a := load(INK_MATERIAL) as StandardMaterial3D
		var b := load(NEUTRAL_MATERIAL) as StandardMaterial3D
		_colors = {"ink": a.albedo_color, "neutral": b.albedo_color,
			"ink_energy": a.emission_energy_multiplier, "neutral_energy": b.emission_energy_multiplier}
	return _colors
