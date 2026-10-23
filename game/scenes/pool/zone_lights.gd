class_name ZoneLights
extends Node3D
## The sunlit patches (micro-world plan C7; docs/DECISIONS.md, "Microscopic world look"): soft
## shafts of cream light falling round each plankton zone, the starving tip's "sunlit patches" to
## find and the rammer's ground made visible. One disc per layout zone, 2.5 m under the swim plane,
## blended over the fluid in the Sun's colour and never in food's glow, with no fog, no depth and
## under every cue (zone_light.gdshader). The light lies round the zone's edge and leaves its feeding
## middle clear, so the cell and the food there keep their contrast. It reads the layout's zones and
## never the sim. The pool's WorldSpace shifts it across a rebase (S1), so the discs are placed in
## its frame (WorldSpace.to_frame).

const SHADER := preload("res://game/scenes/pool/zone_light.gdshader")
## The disc spans this many zone radii across; the shader's light reaches 1.3 zone radii out, so
## neighbouring zones (22 m apart, radius 6 m) stay separate patches.
const SPAN_PER_ZONE_RADIUS := 2.6
## Height under the swim plane (m): clear of the plane's cues, above the midground decor.
const DEPTH_M := -2.5
## The patches' alpha where their light is fullest, by renderer (PROPOSED). Forward+ blends in
## linear light before the tonemap and Compatibility in sRGB after it, so one alpha lifts the navy
## fluid about three times as much in Forward+ (at 0.1, 20.9 L* against 6.4); each renderer gets
## the alpha that lifts its brightest shaft about 9 L* (look probe: 9.2 | 9.6), which an ambush
## hunter over it still clears by 15 dL* (17.1 | 16.8).
const STRENGTH := 0.035
const STRENGTH_COMPATIBILITY := 0.15
## The Sun's light colour (pool.tscn), never the food glow #CFE86A.
const TINT := Color(0.957, 0.918, 0.824)
## The way the Sun's light runs across the plane (x, z): pool.tscn's Sun points along (0.41, -0.82,
## 0.41), so the shafts lie from north-west to south-east.
const SUN_WAY := Vector2(0.7071068, 0.7071068)
## Under every other world transparent; the strike lane draws at CreatureView.LANE_PRIORITY (8).
const RENDER_PRIORITY := -2

## One unit disc for every zone, scaled to each. The start fade's warm-up draws it too (pool.gd).
var mesh: PlaneMesh


func _init() -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("tint", TINT)
	material.set_shader_parameter("strength", strength_for(RenderingServer.get_current_rendering_method()))
	material.set_shader_parameter("span_per_radius", SPAN_PER_ZONE_RADIUS)
	material.set_shader_parameter("sun_way", SUN_WAY)
	mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material


## The patches' alpha for a renderer, by its RenderingServer.get_current_rendering_method() name.
static func strength_for(method: String) -> float:
	return STRENGTH_COMPATIBILITY if method == PoolLook.COMPATIBILITY_METHOD else STRENGTH


## Lays one disc under each of `zones` (PoolLayout.zones), replacing any from before.
func build(zones: Array[Dictionary]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for zone in zones:
		var disc := MeshInstance3D.new()
		disc.name = String(zone.id)
		disc.mesh = mesh
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var span := float(zone.radius) * SPAN_PER_ZONE_RADIUS
		disc.position = WorldSpace.to_frame(self, zone.center, DEPTH_M)
		disc.scale = Vector3(span, 1.0, span)
		add_child(disc)


## Moves every disc by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for child in get_children():
		(child as Node3D).position += position
	position = Vector3.ZERO
