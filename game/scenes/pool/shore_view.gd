class_name ShoreView
extends Node3D
## The shore (the cell-to-creature link, ShoreLink): art's shore piece (assets/records/shore_piece.json,
## docs/art/shore_piece.md). A sand landing that rises out of the deep toward its crest in the north, wholly below
## the swim band (it has no collider), with giant grains half sunk along its brink; a shaft of shallow-water light
## standing on it ("Swim into its light"); and a light ring on the swim plane at the offer's reach
## (ShoreLink.REACH_TM), so the place to crawl out reads from far off and the spot where the offer opens reads up
## close. Authored at cell size 4 in tm, the pivot on the shore point. The pool places it from the save every frame
## (place()), in the plane's local frame: it is world_rebuilt, so a rebase needs nothing more.

const SCENE := "res://assets/export/shore_piece.glb"
## The light's engine material (additive, unshaded, fog-free), mapped onto Shaft and Reach in the .glb.import.
const LIGHT_MATERIAL := "res://assets/export/M_ShoreLight.tres"
## The nodes that draw with it.
const LIGHT_NODES: Array[StringName] = [&"Shaft", &"Reach"]
## The reach ring's mid radius as authored (the record's reach_radius_m); the view scales it to ShoreLink.REACH_TM.
const AUTHORED_REACH_M := 4.0
const PULSE_HZ := 0.5
const PULSE_SHARE := 0.25
## M_ShoreLight's gains are the light's look in Forward+. Compatibility tonemaps each additive layer before it blends
## (docs/TOOLCHAIN.md), so the dim shaft and the bright ring drift apart there: the view scales them by this (x the
## shaft, y the ring), as ZoneLights.strength_for() does for its patches. Measured with tools/godot/shore_shots.gd.
const RENDERER_GAIN_COMPATIBILITY := Vector2(1.0, 1.0)

var _model: Node3D
## This view's own copy of M_ShoreLight: pulse() sets its strength, never the shared file's.
var _light: ShaderMaterial
var _t := 0.0


func _init() -> void:
	name = "Shore"
	visible = false
	_model = (load(SCENE) as PackedScene).instantiate() as Node3D
	_model.name = "Model"
	for n: Node in _model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = (load(LIGHT_MATERIAL) as ShaderMaterial).duplicate() as ShaderMaterial
	_light.set_shader_parameter(&"renderer_gain", renderer_gain_for(RenderingServer.get_current_rendering_method()))
	for part in LIGHT_NODES:
		(_model.find_child(String(part), true, false) as GeometryInstance3D).material_override = _light
	var reach := _model.find_child("Reach", true, false) as Node3D
	var k := ShoreLink.REACH_TM / AUTHORED_REACH_M
	reach.scale = Vector3(k, 1.0, k)
	add_child(_model)


## The light's gains for a renderer (x the shaft, y the ring), by its RenderingServer.get_current_rendering_method()
## name.
static func renderer_gain_for(method: String) -> Vector2:
	return RENDERER_GAIN_COMPATIBILITY if method == PoolLook.COMPATIBILITY_METHOD else Vector2.ONE


## The piece's meshes, for the pool's shader warm-up under the start fade (endless mode only).
static func warm_up_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	var root := (load(SCENE) as PackedScene).instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (n as MeshInstance3D).mesh
		if mesh != null and not out.has(mesh):
			out.append(mesh)
	root.free()
	return out


## Stands the shore at `local` (the plane's local frame, tm) and shows it.
func place(local: Vector2) -> void:
	position = PlaneSpace.to_world(local, 0.0)
	visible = true


## Advances the pulse by `delta` seconds (the pool passes 0 while paused).
func pulse(delta: float) -> void:
	_t += delta
	_light.set_shader_parameter(&"strength", 1.0 + PULSE_SHARE * sin(TAU * PULSE_HZ * _t))


## The light's current strength (this view's copy of M_ShoreLight).
func light_strength() -> float:
	return float(_light.get_shader_parameter(&"strength"))
