class_name ShoreView
extends Node3D
## The pool's sea edge (ShoreLink's first link, microscopic to aquatic): art's shore piece
## (assets/records/shore_piece.json, docs/art/shore_piece.md). A sandbar at the pool's mouth that rises out of the
## deep toward its crest in the north, wholly below the swim band (it has no collider), with giant grains half sunk
## along its brink; a shaft of shallow-water light standing on it and pooling on the sand ("Swim into its light");
## and a light ring on the swim plane at the offer's reach (ShoreLink.REACH_TM), so the way out to sea reads from
## far off and the spot where the offer opens reads up close. Authored at cell size 4 in tm, the pivot on the shore
## point. The pool places it from the save every frame (place()), in the plane's local frame: it is world_rebuilt,
## so a rebase needs nothing more. When the shore rises during play (rise()), the piece comes up out of the deep
## over RISE_S instead of appearing under the cell at once.

const SCENE := "res://assets/export/shore_piece.glb"
## The light's engine material (additive, unshaded, fog-free), mapped onto Shaft, Reach and Glow in the .glb.import.
const LIGHT_MATERIAL := "res://assets/export/M_ShoreLight.tres"
## The nodes that draw with it.
const LIGHT_NODES: Array[StringName] = [&"Shaft", &"Reach", &"Glow"]
## The reach ring's mid radius as authored (the record's reach_radius_m); the view scales it to ShoreLink.REACH_TM.
const AUTHORED_REACH_M := 4.0
const PULSE_HZ := 0.5
const PULSE_SHARE := 0.25
## rise(): the piece starts this far down (m), its top (-1.6) then under the pool's opaque Backdrop (y -40), so
## nothing of it shows; it comes up over RISE_S seconds of play, easing in and out (the crest breaks through the
## Backdrop's fog after about a third of a second), and its light comes on as it arrives. A bank that started any
## shallower would pop in as a pale fogged silhouette, since the fog is paler than the Backdrop.
const RISE_DEPTH_M := 40.0
const RISE_S := 3.0
## M_ShoreLight's gains are the light's look in Forward+. Compatibility tonemaps each additive layer before it blends
## (docs/TOOLCHAIN.md), so the dim shaft and the bright ring drift apart there: the view scales them by this (x the
## shaft and the glow, y the ring), as ZoneLights.strength_for() does for its patches. Measured at the pulse's top at the reach
## edge and on the shore point (docs/art/shore_piece.md, Gate 4): the shaft matches within 4 L*, the ring reads about
## 3 L* brighter in Compatibility.
const RENDERER_GAIN_COMPATIBILITY := Vector2(1.0, 0.9)

var _model: Node3D
## This view's own copy of M_ShoreLight: pulse() sets its strength, never the shared file's.
var _light: ShaderMaterial
var _t := 0.0
## rise()'s progress, 0 to 1 (1: at rest, where a new view and a loaded save start).
var _rise := 1.0


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


## The shore rose during play (the pool's shore_risen): the piece drops to RISE_DEPTH_M and pulse() brings it up.
func rise() -> void:
	_rise = 0.0
	pulse(0.0)


## Advances the pulse, and a rise, by `delta` seconds (the pool passes 0 while paused).
func pulse(delta: float) -> void:
	_t += delta
	if _rise < 1.0:
		_rise = minf(1.0, _rise + delta / RISE_S)
		_apply_rise()
	_light.set_shader_parameter(&"strength", rise_share() * rise_share() * (1.0 + PULSE_SHARE * sin(TAU * PULSE_HZ * _t)))


## How far up the piece has come, 0 (just risen, RISE_DEPTH_M down) to 1 (at rest), eased in and out.
func rise_share() -> float:
	return smoothstep(0.0, 1.0, _rise)


## Whether a rise is still under way.
func rising() -> bool:
	return _rise < 1.0


func _apply_rise() -> void:
	_model.position.y = -RISE_DEPTH_M * (1.0 - rise_share())


## The light's current strength (this view's copy of M_ShoreLight).
func light_strength() -> float:
	return float(_light.get_shader_parameter(&"strength"))
