class_name ZoneLights
extends Node3D
## The sunlit patches (micro-world plan C7; docs/DECISIONS.md, "Microscopic world look"): a soft pool
## of cream light under each plankton zone, so the starving tip's "sunlit patches" are there to
## find, and the rammer's ground has a visible middle. Light only: one disc per layout zone, 2.5 m
## under the swim plane, added to the fluid in the Sun's colour and never in food's glow, with no
## fog, no depth and under every cue (zone_light.gdshader). It reads the layout's zones and never
## the sim.

const SHADER := preload("res://game/scenes/pool/zone_light.gdshader")
## The disc spans this many zone radii across (plan B's prototype). Its light is full out to 0.46
## zone radii, half at 0.88 (about the zone's edge) and gone at 1.3, so neighbouring zones (22 m
## apart, radius 6 m) stay separate patches.
const SPAN_PER_ZONE_RADIUS := 2.6
## Height under the swim plane (m): clear of the plane's cues, above the midground decor.
const DEPTH_M := -2.5
## The share of the Sun's colour added at a disc's centre (PROPOSED). The plan's 0.05 to 0.08 was
## judged in Compatibility only; Forward+ adds about five times as much light from the same additive
## disc, and at 0.05 the fluid around the cell in a zone rose from L* 34 to 46, leaving the coral
## cell 7.7 L* above it. The look probe's fluid gate (L* at most 36 near the cell) allows about
## 0.007 there: 0.006 lifts the zone's middle 1.7 L* in Forward+ and about 0.4 in Compatibility.
const STRENGTH := 0.006
## The Sun's light colour (pool.tscn), never the food glow #CFE86A.
const TINT := Color(0.957, 0.918, 0.824)
## Under every other world transparent; the strike lane draws at 8 (creature_view.gd).
const RENDER_PRIORITY := -2

## One unit disc for every zone, scaled to each. The start fade's warm-up draws it too (pool.gd).
var mesh: PlaneMesh


func _init() -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("tint", TINT)
	material.set_shader_parameter("strength", STRENGTH)
	mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material


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
		disc.position = PlaneSpace.to_world(zone.center, DEPTH_M)
		disc.scale = Vector3(span, 1.0, span)
		add_child(disc)
