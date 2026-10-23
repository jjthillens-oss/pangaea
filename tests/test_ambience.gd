extends TestCase
## The pool's ambience (game/scenes/pool/ambience/, docs/DECISIONS.md "The cell stage reads as a
## microscopic world"): decor only. It must never reach into the simulation or its random streams,
## and it keeps to engineering's ambience contract (/mnt/project-files/pangaea/docs/micro-world-plan.md
## section 7): budgets, depth bands clear of the swim plane, no food or threat hues, and pale decor
## too faint to lift the fluid behind the gameplay cues.

const AMBIENCE_DIR := "res://game/scenes/pool/ambience/"
## The pool mounts the scene from this path when it exists (micro-world plan C6).
const SCENE := "res://game/scenes/pool/ambience/ambience.tscn"
const MAX_PARTICLES := 2000
const MAX_BACKDROPS := 12
const MAX_FOREGROUND := 40
## The strike lane draws at this priority; decor stays below it (creature_view.gd LANE_PRIORITY).
const LANE_PRIORITY := 8
## Nothing decorative inside this band around the swim plane, m.
const PLANE_BAND := Vector2(-1.5, 0.5)
const BACKGROUND_BAND := Vector2(-35.0, -12.0)
## Reserved colours: the food glow and the threat pink. Decor keeps this many degrees of LAB hue away.
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
const MIN_LAB_HUE_GAP_DEG := 25.0
## Linear luminance caps: luminance times opacity for any alpha decor, and luminance alone below the plane.
const MAX_LUMA_ALPHA := 0.12
const MAX_LUMA_BELOW := 0.40


func _sources() -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(AMBIENCE_DIR):
		if file.ends_with(".gd") or file.ends_with(".gdshader") or file.ends_with(".tscn"):
			out[file] = FileAccess.get_file_as_string(AMBIENCE_DIR + file)
	return out


func test_the_ambience_never_references_the_simulation() -> void:
	var sources := _sources()
	check(not sources.is_empty(), "the ambience has sources")
	var any_random := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\(")
	for file: String in sources:
		var text: String = sources[file]
		for banned in ["game/systems", "PoolSim", "SimRandom", ".sim", "sim."]:
			check(not text.contains(banned), "%s mentions %s" % [file, banned])
		# Its random numbers come from its own generator, never the global one.
		check(any_random.search(text) == null, "%s draws from the global random generator" % file)


func _luma(c: Color) -> float:
	return c.srgb_to_linear().get_luminance()


## CIE LAB hue in degrees (D65) of an sRGB colour.
func _lab_hue(c: Color) -> float:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var a: float = 500.0 * (f.call(x) - f.call(y))
	var b: float = 200.0 * (f.call(y) - f.call(z))
	return fposmod(rad_to_deg(atan2(b, a)), 360.0)


func _hue_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func _check_clear_of_reserved(what: String, c: Color) -> void:
	for reserved: String in RESERVED:
		var gap := _hue_gap(_lab_hue(c), _lab_hue(RESERVED[reserved]))
		check(gap >= MIN_LAB_HUE_GAP_DEG, "%s is %.0f degrees of LAB hue from the %s colour" % [what, gap, reserved])


## Each backdrop texture, downsampled, as [colour, alpha] texels.
func _backdrop_texels() -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(PoolAmbience.BACKDROP_DIR):
		if not file.ends_with(".png"):
			continue
		var image := (load(PoolAmbience.BACKDROP_DIR + file) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(64, 64)
		var texels := []
		for y in 64:
			for x in 64:
				texels.append(image.get_pixel(x, y))
		out[file] = texels
	return out


func test_the_scene_sits_at_the_pools_mount_point() -> void:
	check(ResourceLoader.exists(SCENE), "the ambience scene is at %s" % SCENE)
	var node := (load(SCENE) as PackedScene).instantiate()
	check_eq(String(node.name), "Ambience", "its root is the Ambience node")
	node.free()


func test_the_ambience_stays_inside_its_budgets() -> void:
	var node: PoolAmbience = (load(SCENE) as PackedScene).instantiate()
	node._ready()
	check(node.particle_count() > 0 and node.particle_count() <= MAX_PARTICLES,
		"%d drifting quads, at most %d" % [node.particle_count(), MAX_PARTICLES])
	# The S2 ghost layer draws the far giants, so the ambience draws no backdrops (s2-view 11.1).
	check_eq(node.backdrop_count(), 0, "no drifting backdrops; the ghost layer owns the far layer")
	for child in node.get_children():
		if child is GeometryInstance3D:
			var geo := child as GeometryInstance3D
			# Nothing it draws casts a shadow, or draws over the strike lanes.
			check_eq(geo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % child.name)
			check(geo.material_override.render_priority < LANE_PRIORITY, "%s draws under the lanes" % child.name)
	node.free()


func test_shaders_keep_engine_fog_unless_additive() -> void:
	# blend_mix decor fades into the fluid with the engine's fog; additive decor must turn fog off.
	var sources := _sources()
	for file: String in sources:
		if file.ends_with(".gdshader") and sources[file].contains("blend_add"):
			check(sources[file].contains("fog_disabled"), "%s is additive and fog_disabled" % file)
		if file.ends_with(".gdshader"):
			check(not sources[file].contains("fog_disabled") or sources[file].contains("blend_add"), "%s keeps engine fog" % file)


func test_decor_keeps_clear_of_the_swim_plane() -> void:
	for layer: String in PoolAmbience.LAYERS:
		var spec: Dictionary = PoolAmbience.LAYERS[layer]
		var height: Vector2 = spec.height
		check(height.y <= PLANE_BAND.x or height.x >= PLANE_BAND.y,
			"%s wraps in %.1f..%.1f m, clear of %.1f..%.1f" % [layer, height.x, height.y, PLANE_BAND.x, PLANE_BAND.y])
		if height.x >= PLANE_BAND.y:
			check(spec.count <= MAX_FOREGROUND, "%s above the plane has %d quads, at most %d" % [layer, spec.count, MAX_FOREGROUND])
	var depth := PoolAmbience.BACKDROP_DEPTH
	check(depth.x >= BACKGROUND_BAND.x and depth.y <= BACKGROUND_BAND.y, "backdrops lie in the background band")


func test_decor_keeps_clear_of_the_food_and_threat_colours() -> void:
	for layer: String in PoolAmbience.LAYERS:
		for hex: String in PoolAmbience.LAYERS[layer].tints:
			_check_clear_of_reserved("%s tint %s" % [layer, hex], Color(hex))
	var texels := _backdrop_texels()
	check(not texels.is_empty(), "the backdrop textures are there")
	for file: String in texels:
		# The texture's alpha-weighted mean colour.
		var sum := Color(0, 0, 0, 0)
		for t: Color in texels[file]:
			sum += Color(t.r * t.a, t.g * t.a, t.b * t.a, t.a)
		_check_clear_of_reserved(file, Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a))


func test_pale_decor_is_too_faint_to_lift_the_fluid() -> void:
	for layer: String in PoolAmbience.LAYERS:
		var spec: Dictionary = PoolAmbience.LAYERS[layer]
		for hex: String in spec.tints:
			var luma := _luma(Color(hex))
			check(luma * spec.alpha.y <= MAX_LUMA_ALPHA + 1e-4,
				"%s tint %s: luminance %.2f x opacity %.2f is over %.2f" % [layer, hex, luma, spec.alpha.y, MAX_LUMA_ALPHA])
			if spec.height.y < 0.0:
				check(luma <= MAX_LUMA_BELOW, "%s tint %s below the plane has luminance %.2f" % [layer, hex, luma])
	var texels := _backdrop_texels()
	for file: String in texels:
		var top := 0.0
		var top_alpha := 0.0
		for t: Color in texels[file]:
			if t.a > 0.02:
				var luma := _luma(Color(t.r, t.g, t.b)) * PoolAmbience.BACKDROP_BRIGHTNESS
				top = maxf(top, luma)
				top_alpha = maxf(top_alpha, luma * t.a * PoolAmbience.BACKDROP_OPACITY.y)
		check(top <= MAX_LUMA_BELOW, "%s: brightest texel luminance %.2f" % [file, top])
		check(top_alpha <= MAX_LUMA_ALPHA, "%s: luminance x opacity %.2f" % [file, top_alpha])


func test_apply_scale_view_scales_bands_and_sizes_and_is_identity_at_one() -> void:
	var node: PoolAmbience = (load(SCENE) as PackedScene).instantiate()
	node._ready()
	var before := {}
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			before[child.name] = (child as MultiMeshInstance3D).material_override.get_shader_parameter("height_range")
	node.apply_scale_view({"depth_k": 1.0, "size_k": 1.0})
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var m := (child as MultiMeshInstance3D).material_override as ShaderMaterial
			check_eq(m.get_shader_parameter("height_range"), before[child.name], "%s: k = 1 leaves the band" % child.name)
	node.apply_scale_view({"depth_k": 0.625, "size_k": 0.625})
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			var m := (child as MultiMeshInstance3D).material_override as ShaderMaterial
			check_eq(m.get_shader_parameter("height_range"), (before[child.name] as Vector2) * 0.625, "%s: band scales by depth_k" % child.name)
			check_eq(m.get_shader_parameter("size_k"), 0.625, "%s: sizes scale by size_k" % child.name)
	node.free()
