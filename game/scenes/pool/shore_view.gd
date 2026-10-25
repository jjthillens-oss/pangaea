class_name ShoreView
extends Node3D
## The shore (the cell-to-creature link, ShoreLink): a shaft of warm light standing on the sea floor where the
## shore rose, with a sand-coloured disc on the swim plane as wide as its reach, so the place to crawl out reads
## from far off and the spot where the offer opens reads up close. Drawn with primitive meshes until art makes the
## shore piece (docs/DECISIONS.md "Cell to creature link"). The pool places it from the save every frame
## (place()), in the plane's local frame: it is world_rebuilt, so a rebase needs nothing more.

## The shaft's colour: sunlight through shallow water, apart from the cream markers and the cyan cell.
const LIGHT := Color(1.0, 0.86, 0.55)
const SAND := Color(0.93, 0.8, 0.55)
## Shaft heights (m), as the checkpoint column's: from under the floor to COLUMN_TOP above the swim plane.
const BOTTOM_Y := -1.5
const TOP_Y := 4.5
const LIGHT_ALPHA := 0.22
const SAND_ALPHA := 0.3
const PULSE_HZ := 0.5
const PULSE_SHARE := 0.25

var _shaft: MeshInstance3D
var _disc: MeshInstance3D
var _shaft_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D
var _t := 0.0


func _init() -> void:
	name = "Shore"
	visible = false
	var reach := ShoreLink.REACH_TM
	var shaft := CylinderMesh.new()
	shaft.top_radius = reach * 0.55
	shaft.bottom_radius = reach * 0.8
	shaft.height = TOP_Y - BOTTOM_Y
	shaft.cap_top = false
	shaft.cap_bottom = false
	_shaft_mat = _glow(LIGHT, LIGHT_ALPHA)
	_shaft = MeshInstance3D.new()
	_shaft.name = "Shaft"
	_shaft.mesh = shaft
	_shaft.material_override = _shaft_mat
	_shaft.position.y = (TOP_Y + BOTTOM_Y) * 0.5
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shaft)
	var disc := CylinderMesh.new()
	disc.top_radius = reach
	disc.bottom_radius = reach
	disc.height = 0.02
	_disc_mat = _glow(SAND, SAND_ALPHA)
	_disc = MeshInstance3D.new()
	_disc.name = "Reach"
	_disc.mesh = disc
	_disc.material_override = _disc_mat
	_disc.position.y = -0.05
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


static func _glow(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, alpha)
	return m


## Stands the shore at `local` (the plane's local frame, tm) and shows it.
func place(local: Vector2) -> void:
	position = PlaneSpace.to_world(local, 0.0)
	visible = true


## Advances the pulse by `delta` seconds (the pool passes 0 while paused).
func pulse(delta: float) -> void:
	_t += delta
	var k := 1.0 + PULSE_SHARE * sin(TAU * PULSE_HZ * _t)
	_shaft_mat.albedo_color.a = LIGHT_ALPHA * k
	_disc_mat.albedo_color.a = SAND_ALPHA * k
