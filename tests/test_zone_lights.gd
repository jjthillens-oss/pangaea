extends TestCase
## The sunlit patches (game/scenes/pool/zone_lights.gd; micro-world plan C7; docs/DECISIONS.md,
## "Microscopic world look"): one soft disc of the Sun's cream light under each plankton zone of the
## layout, added to the fluid without fog or depth and under every cue, and warmed under the start
## fade like the food meshes.

const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
## Where a disc lies (m under the swim plane) and how many zone radii it spans across (PROPOSED).
const DEPTH_M := -2.5
const SPAN_PER_ZONE_RADIUS := 2.6
## The light at a disc's centre, as a share of the Sun's colour: some, and no more than keeps the
## look probe's fluid gate near a cell in a zone in Forward+ (L* at most 36: about 0.007).
const MAX_STRENGTH := 0.007
## Food's glow, which no other light takes: the patches keep at least this CIE76 distance from it.
const FOOD_GLOW := Color("#CFE86A")
const MIN_FOOD_DELTA_E := 30.0
const LookProbe := preload("res://tools/godot/look_probe.gd")


## The render_mode flags of a shader, comments removed.
func _render_modes(shader: Shader) -> PackedStringArray:
	var text := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(shader.code, "", true)
	text = RegEx.create_from_string("//[^\\n]*").sub(text, "", true)
	var out := PackedStringArray()
	for m in RegEx.create_from_string("render_mode\\s+([^;]+);").search_all(text):
		for flag in m.get_string(1).split(","):
			out.append(flag.strip_edges())
	return out


func test_one_disc_under_each_zone_centred_on_it() -> void:
	var layout := PoolLayout.load_from()
	check(not layout.zones.is_empty(), "the layout has zones")
	var lights := ZoneLights.new()
	lights.build(layout.zones)
	lights.build(layout.zones)
	check_eq(lights.get_child_count(), layout.zones.size(), "one disc per zone, after a rebuild too")
	for zone in layout.zones:
		var disc := lights.get_node_or_null(String(zone.id)) as MeshInstance3D
		if disc == null:
			check(false, "zone %s has a disc" % zone.id)
			continue
		var centre := PlaneSpace.to_world(zone.center, DEPTH_M)
		check(disc.position.is_equal_approx(centre), "%s's disc is centred under it at y %.1f: %s, want %s" % [zone.id, DEPTH_M, disc.position, centre])
		var span := float(zone.radius) * SPAN_PER_ZONE_RADIUS
		var size := (disc.mesh as PlaneMesh).size
		check_near(disc.scale.x * size.x, span, 1e-3, "%s's disc spans %.1f zone radii across (x)" % [zone.id, SPAN_PER_ZONE_RADIUS])
		check_near(disc.scale.z * size.y, span, 1e-3, "%s's disc spans %.1f zone radii across (z)" % [zone.id, SPAN_PER_ZONE_RADIUS])
		check(disc.basis.y.normalized().is_equal_approx(Vector3.UP), "%s's disc lies level" % zone.id)
		check_eq(disc.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s's disc casts no shadow" % zone.id)
		check(disc.mesh == lights.mesh, "%s's disc draws the shared mesh the warm-up compiles" % zone.id)
	lights.free()


func test_the_light_is_the_suns_cream_never_foods_glow() -> void:
	var lights := ZoneLights.new()
	var material := lights.mesh.material as ShaderMaterial
	var tint: Color = material.get_shader_parameter("tint")
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	var sun := pool.get_node("Sun") as DirectionalLight3D
	check(tint.is_equal_approx(sun.light_color), "the patches take the Sun's colour %s, got %s" % [sun.light_color, tint])
	pool.free()
	var delta_e := (LookProbe.lab(tint) - LookProbe.lab(FOOD_GLOW)).length()
	check(delta_e >= MIN_FOOD_DELTA_E, "the tint is %.1f CIE76 from food's glow, at least %.0f" % [delta_e, MIN_FOOD_DELTA_E])
	var strength := float(material.get_shader_parameter("strength"))
	check(strength > 0.0 and strength <= MAX_STRENGTH, "strength %.4f is above 0 and at most %.3f" % [strength, MAX_STRENGTH])
	lights.free()


func test_it_adds_light_without_fog_or_depth_under_every_cue() -> void:
	var lights := ZoneLights.new()
	var material := lights.mesh.material as ShaderMaterial
	var modes := _render_modes(material.shader)
	for flag in ["blend_add", "unshaded", "depth_draw_never", "shadows_disabled"]:
		check(modes.has(flag), "zone_light.gdshader is %s" % flag)
	# Additive with the engine's fog would paint a bright, hard-edged quad over the fluid.
	check(modes.has("fog_disabled"), "zone_light.gdshader adds light, so it takes no fog")
	check_eq(material.render_priority, -2, "render priority")
	check(material.render_priority < CreatureView.LANE_PRIORITY, "the patches draw under the strike lane (%d)" % CreatureView.LANE_PRIORITY)
	lights.free()


func test_the_start_fade_warms_the_zone_light() -> void:
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	pool.notification(Node.NOTIFICATION_READY)
	var meshes: Array[Mesh] = pool.warm_up_meshes()
	check(meshes.has(pool.zone_lights.mesh), "the warm-up draws the zone light's mesh")
	check(not meshes.has(null), "and both food meshes: %s" % [meshes])
	check_eq(meshes.size(), 4, "warm-up meshes (the strike lane's too; tests/test_pool_view.gd)")
	pool.free()
