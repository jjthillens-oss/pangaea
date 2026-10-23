extends TestCase
## The sunlit patches (game/scenes/pool/zone_lights.gd; micro-world plan C7; docs/DECISIONS.md,
## "Microscopic world look"): one disc of soft shafts of the Sun's cream light under each plankton
## zone of the layout, lying round the zone's edge with its middle clear, blended over the fluid
## without fog or depth and under every cue, as strong in either renderer, and warmed under the
## start fade like the food meshes. The look probe's sunlit gates measure what it does on screen.

const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
## Where a disc lies (m under the swim plane) and how many zone radii it spans across (PROPOSED).
const DEPTH_M := -2.5
const SPAN_PER_ZONE_RADIUS := 2.6
## The patches' alpha by renderer: some, and no more than keeps an ambush hunter over the brightest
## shaft 15 dL* clear in the look probe (about 0.045 in Forward+ and 0.17 in Compatibility).
const MAX_STRENGTH := 0.045
const MAX_STRENGTH_COMPATIBILITY := 0.17
## The shader's band of light, in zone radii from the centre: nothing inside BAND_IN (the cell and
## the food there keep their contrast), and nothing left at the disc's rim, so it shows no edge.
const MIN_BAND_IN := 0.4
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
	lights.free()


func test_each_renderer_gets_the_alpha_that_lifts_the_fluid_about_the_same() -> void:
	var forward := ZoneLights.strength_for("forward_plus")
	var compatibility := ZoneLights.strength_for(PoolLook.COMPATIBILITY_METHOD)
	check(forward > 0.0 and forward <= MAX_STRENGTH, "Forward+ alpha %.3f is above 0 and at most %.3f" % [forward, MAX_STRENGTH])
	check(compatibility > 0.0 and compatibility <= MAX_STRENGTH_COMPATIBILITY, "Compatibility alpha %.3f is above 0 and at most %.2f" % [compatibility, MAX_STRENGTH_COMPATIBILITY])
	# Compatibility blends in sRGB after the tonemap, so it needs about three to five times the alpha.
	check(compatibility >= 3.0 * forward and compatibility <= 5.0 * forward, "Compatibility's alpha is 3 to 5 times Forward+'s: %.3f against %.3f" % [compatibility, forward])
	check_eq(ZoneLights.strength_for("mobile"), forward, "any other renderer blends in linear light like Forward+")
	var lights := ZoneLights.new()
	var material := lights.mesh.material as ShaderMaterial
	check_near(float(material.get_shader_parameter("strength")), ZoneLights.strength_for(RenderingServer.get_current_rendering_method()), 1e-6, "the material takes this renderer's alpha")
	lights.free()


func test_the_light_lies_round_the_zone_in_shafts_along_the_suns_way() -> void:
	var lights := ZoneLights.new()
	var material := lights.mesh.material as ShaderMaterial
	var code := material.shader.code
	var band := {}
	for key in ["BAND_IN", "BAND_PEAK", "BAND_OUT"]:
		var m := RegEx.create_from_string("const float %s = ([0-9.]+);" % key).search(code)
		check(m != null, "zone_light.gdshader declares %s" % key)
		band[key] = float(m.get_string(1)) if m else NAN
	check(band.BAND_IN >= MIN_BAND_IN, "no light within %.2f zone radii of the centre, at least %.2f" % [band.BAND_IN, MIN_BAND_IN])
	check(band.BAND_IN < band.BAND_PEAK and band.BAND_PEAK < band.BAND_OUT, "the band rises, peaks and falls: %s" % [band])
	check(band.BAND_OUT <= SPAN_PER_ZONE_RADIUS * 0.5 + 1e-4, "the light is gone by %.2f zone radii, inside the disc's rim at %.2f" % [band.BAND_OUT, SPAN_PER_ZONE_RADIUS * 0.5])
	check_near(float(material.get_shader_parameter("span_per_radius")), SPAN_PER_ZONE_RADIUS, 1e-6, "the shader knows the disc's span")
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	var sun := (pool.get_node("Sun") as DirectionalLight3D).transform.basis.z * -1.0
	pool.free()
	var way := Vector2(sun.x, sun.z).normalized()
	check(ZoneLights.SUN_WAY.is_equal_approx(way), "the shafts lie along the Sun's way across the plane %s, got %s" % [way, ZoneLights.SUN_WAY])
	check(Vector2(material.get_shader_parameter("sun_way")).is_equal_approx(ZoneLights.SUN_WAY), "and the material takes it")
	lights.free()


func test_it_blends_light_over_the_fluid_without_fog_or_depth_under_every_cue() -> void:
	var lights := ZoneLights.new()
	var material := lights.mesh.material as ShaderMaterial
	var modes := _render_modes(material.shader)
	# Blended, not added: Compatibility loses faint added light altogether.
	for flag in ["blend_mix", "unshaded", "depth_draw_never", "shadows_disabled"]:
		check(modes.has(flag), "zone_light.gdshader is %s" % flag)
	check(not modes.has("blend_add"), "zone_light.gdshader does not add its light")
	# The light lies just under the plane; the fog would tint it toward the fluid it lights.
	check(modes.has("fog_disabled"), "zone_light.gdshader takes no fog")
	check_eq(material.render_priority, -2, "render priority")
	check(material.render_priority < CreatureView.LANE_PRIORITY, "the patches draw under the strike lane (%d)" % CreatureView.LANE_PRIORITY)
	lights.free()


func test_the_start_fade_warms_the_zone_light() -> void:
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	pool.notification(Node.NOTIFICATION_READY)
	var meshes: Array[Mesh] = pool.warm_up_meshes()
	check(meshes.has(pool.zone_lights.mesh), "the warm-up draws the zone light's mesh")
	check(not meshes.has(null), "and both food meshes: %s" % [meshes])
	check_eq(meshes.slice(0, 4), [pool.plankton_view.food_mesh(), pool.carrion_view.food_mesh(), pool.zone_lights.mesh, meshes[3]],
		"the food, the zone light and the strike lane first (the growth's looks follow; tests/test_pool_view.gd)")
	pool.free()
