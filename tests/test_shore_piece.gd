extends TestCase
## The shore piece (assets/records/shore_piece.json, docs/art/shore_piece.md) and the view that draws it
## (game/scenes/pool/shore_view.gd, the pool's sea edge, where the cell swims out to the open sea): the record keeps
## ShoreLink's reach, nothing solid enters the swim band (the shore has no collider), the reach ring lies on the plane
## at REACH_TM, the light is additive, unlit and fog-free with no reserved hue and its glow lies on the sand, the view
## keeps its API, pulses its own copy of the light and brings a newly risen shore up out of the deep, the sand stays
## at its tuned in-game exposure and clear of the food and threat hues, and only the endless start fade warms the
## piece.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const RECORD := "res://assets/records/shore_piece.json"
const ALBEDO := "res://assets/export/shore_piece_T_ShorePiece_Albedo.png"
const PRODUCTION_REVIEW := "production rev 1 - M1, awaiting owner look review"
const BUDGET_CAP := 6000
const TEXTURE_CAP := 2048
## The ambience contract's decor-free band around the swim plane (tests/test_ambience.gd PLANE_BAND).
const PLANE_BAND := Vector2(-1.5, 0.5)
## The reach ring's half width as authored (3.7 to 4.3 m).
const RING_HALF_WIDTH := 0.3
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
const MIN_LAB_HUE_GAP_DEG := 25.0
## Texels below this LAB chroma read as grey and carry no hue to confuse.
const HUE_CHROMA := 12.0
const MAX_NEAR_SHARE := 0.02
## The rule for anything under the plane (test_s2_assets): linear luminance at most 0.40. Checked at the 99th
## percentile, so a bright minority cannot hide under a dim median.
const MAX_LUMINANCE := 0.40
## The tuned exposure (make_shore_piece.py ALBEDO_GAIN 0.27): the sand reads L* 36 to 48 behind the size-4 cell in
## the pool (docs/art/shore_piece.md, Gate 4). The baked albedo measures p99 0.084 and median 0.019; the unscaled
## bake (median about 0.12) read L* 65 to 78, brighter than the cell, and must fail here.
const MAX_P99_LUMINANCE := 0.12
const MAX_MEDIAN_LUMINANCE := 0.05


func _record() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	return data if data is Dictionary else {}


func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	return Vector3(116.0 * _f(y) - 16.0, 500.0 * (_f(x) - _f(y)), 200.0 * (_f(y) - _f(z)))


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## The smallest LAB hue gap (degrees) from either reserved colour.
func _reserved_gap(lab: Vector3) -> float:
	var hue := rad_to_deg(atan2(lab.z, lab.y))
	var gap := 180.0
	for name: String in RESERVED:
		var r := _lab(RESERVED[name])
		gap = minf(gap, absf(fposmod(hue - rad_to_deg(atan2(r.z, r.y)) + 180.0, 360.0) - 180.0))
	return gap


## Every MeshInstance3D under `root` by name.
func _meshes(root: Node) -> Dictionary:
	var out := {}
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out[String(n.name)] = n
	return out


func _max_y(mesh: Mesh) -> float:
	var top := -INF
	for s in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, v.y)
	return top


func test_the_record_matches_the_shore_rules() -> void:
	var record := _record()
	check_eq(record.get("id"), "shore_piece", "the record's id")
	check_eq(record.get("kind"), "shore", "the record's kind")
	check_near(float(record.get("reach_radius_m", 0.0)), ShoreLink.REACH_TM, 1e-6, "the record's reach is ShoreLink.REACH_TM")
	check_near(ShoreView.AUTHORED_REACH_M, float(record.get("reach_radius_m", 0.0)), 1e-6, "ShoreView knows the authored reach")
	check_eq(record.get("engine_material"), ShoreView.LIGHT_MATERIAL, "the light's engine material")
	check_eq(record.get("review_state"), PRODUCTION_REVIEW, "the record is production art")
	check_eq(record.get("light_nodes"), ["Shaft", "Reach", "Glow"], "the light nodes")
	var nodes: Array = []
	for n in ShoreView.LIGHT_NODES:
		nodes.append(String(n))
	check_eq(nodes, record.get("light_nodes"), "ShoreView draws the record's light nodes")
	var budget := int(record.get("triangle_budget", 0))
	check(budget > 0 and budget <= BUDGET_CAP, "triangle budget %d is at most %d" % [budget, BUDGET_CAP])
	check(int(record.get("triangles", BUDGET_CAP + 1)) <= budget, "%d triangles, budget %d" % [int(record.get("triangles", -1)), budget])
	check(float(record.get("sand_top_m", 0.0)) <= PLANE_BAND.x, "the recorded sand top %.3f is under the swim band" % float(record.get("sand_top_m", 0.0)))
	var textures: Array = record.get("textures", [])
	check_eq(textures.size(), 3, "albedo, ORM and normal")
	for t: Dictionary in textures:
		var size: Array = t.get("size", [0, 0])
		check(int(size[0]) <= TEXTURE_CAP and int(size[1]) <= TEXTURE_CAP, "%s is %s, at most %d" % [t.get("name"), size, TEXTURE_CAP])


func test_nothing_solid_enters_the_swim_band() -> void:
	var root := (load(ShoreView.SCENE) as PackedScene).instantiate()
	var meshes := _meshes(root)
	check(meshes.has("ShoreBank"), "the piece has its bank")
	for name: String in meshes:
		if StringName(name) in ShoreView.LIGHT_NODES:
			continue
		var mi: MeshInstance3D = meshes[name]
		var top := _max_y(mi.mesh) + mi.position.y
		check(top <= PLANE_BAND.x, "%s reaches %.3f m, at most %.1f (the shore has no collider)" % [name, top, PLANE_BAND.x])
	root.free()


func test_the_reach_ring_lies_on_the_plane_at_the_reach() -> void:
	var view := ShoreView.new()
	var reach := view.find_child("Reach", true, false) as MeshInstance3D
	check(reach != null, "the view has its reach ring")
	if reach != null:
		var box: AABB = reach.transform * reach.get_aabb()
		var want := 2.0 * (ShoreLink.REACH_TM + RING_HALF_WIDTH)
		check_near(box.size.x, want, 0.35, "the ring's width across x")
		check_near(box.size.z, want, 0.35, "the ring's width across z")
		check_near(box.position.y, 0.0, 0.1, "the ring lies on the swim plane")
		check_near(box.get_center().x, 0.0, 0.05, "the ring is centred on the shore point (x)")
		check_near(box.get_center().z, 0.0, 0.05, "the ring is centred on the shore point (z)")
	view.free()


func test_the_glow_lies_on_the_sand_in_the_shafts_foot() -> void:
	var root := (load(ShoreView.SCENE) as PackedScene).instantiate()
	var meshes := _meshes(root)
	var glow: MeshInstance3D = meshes.get("Glow")
	var shaft: MeshInstance3D = meshes.get("Shaft")
	var bank: MeshInstance3D = meshes.get("ShoreBank")
	check(glow != null and shaft != null and bank != null, "the piece has its glow, shaft and bank")
	if glow != null and shaft != null and bank != null:
		var g: AABB = glow.transform * glow.get_aabb()
		var foot: AABB = shaft.transform * shaft.get_aabb()
		check(g.end.y <= PLANE_BAND.x, "the glow tops out at %.3f m, under the swim band" % g.end.y)
		check(g.position.y >= (bank.transform * bank.get_aabb()).position.y, "the glow lies on the bank")
		check_near(g.size.x, foot.size.x, 0.05, "the glow fills the shaft's foot across x")
		check_near(g.size.z, foot.size.z, 0.05, "the glow fills the shaft's foot across z")
		check_near(foot.position.y, g.position.y, 0.05, "the shaft's foot stands on the sand with the glow")
	root.free()


func test_the_light_adds_unshaded_without_fog() -> void:
	var m := load(ShoreView.LIGHT_MATERIAL) as ShaderMaterial
	check(m != null and m.shader != null, "M_ShoreLight is a ShaderMaterial")
	if m == null or m.shader == null:
		return
	var code := m.shader.code
	var modes := RegEx.create_from_string("render_mode\\s+([^;]+);").search(code)
	check(modes != null, "the shader names its render modes")
	var have := PackedStringArray()
	if modes != null:
		for part in modes.get_string(1).split(","):
			have.append(part.strip_edges())
	for mode in ["blend_add", "unshaded", "fog_disabled", "depth_draw_never", "shadows_disabled"]:
		check(mode in have, "M_ShoreLight is %s (render_mode %s)" % [mode, ", ".join(have)])
	var tint := m.get_shader_parameter(&"tint") as Color
	check(_reserved_gap(_lab(tint)) >= MIN_LAB_HUE_GAP_DEG, "the light's tint %s keeps %.0f deg from the reserved hues" % [tint.to_html(false), MIN_LAB_HUE_GAP_DEG])
	var root := (load(ShoreView.SCENE) as PackedScene).instantiate()
	var meshes := _meshes(root)
	for part in ShoreView.LIGHT_NODES:
		var mi: MeshInstance3D = meshes.get(String(part))
		check(mi != null and mi.mesh.surface_get_material(0).resource_path == ShoreView.LIGHT_MATERIAL,
			"%s imports with M_ShoreLight (the .glb.import mapping)" % part)
	root.free()


func test_the_light_takes_its_gains_per_renderer() -> void:
	check_eq(ShoreView.renderer_gain_for("forward_plus"), Vector2.ONE, "Forward+ draws M_ShoreLight as authored")
	check_eq(ShoreView.renderer_gain_for(PoolLook.COMPATIBILITY_METHOD), ShoreView.RENDERER_GAIN_COMPATIBILITY,
		"Compatibility scales the shaft and the ring by their own factors")
	var view := ShoreView.new()
	var shaft := view.find_child("Shaft", true, false) as GeometryInstance3D
	var want := ShoreView.renderer_gain_for(RenderingServer.get_current_rendering_method())
	check_eq((shaft.material_override as ShaderMaterial).get_shader_parameter(&"renderer_gain"), want,
		"the view's light takes the running renderer's gains")
	check_eq((load(ShoreView.LIGHT_MATERIAL) as ShaderMaterial).get_shader_parameter(&"renderer_gain"), Vector2.ONE,
		"M_ShoreLight.tres keeps the Forward+ look")
	view.free()


func test_the_view_keeps_its_api() -> void:
	var authored := float((load(ShoreView.LIGHT_MATERIAL) as ShaderMaterial).get_shader_parameter(&"strength"))
	var view := ShoreView.new()
	check_eq(view.name, &"Shore", "the view's name")
	check(not view.visible, "the view starts hidden")
	view.place(Vector2(3, -7))
	check(view.position.is_equal_approx(Vector3(3, 0, -7)), "place() stands it at the plane's local point, got %s" % view.position)
	check(view.visible, "place() shows it")
	view.pulse(0.5)
	check(absf(view.light_strength() - authored) > 0.1, "pulse() changes the view's strength (%.3f)" % view.light_strength())
	var shared := float((load(ShoreView.LIGHT_MATERIAL) as ShaderMaterial).get_shader_parameter(&"strength"))
	check_near(shared, authored, 1e-6, "pulse() leaves M_ShoreLight.tres as authored")
	for n: Node in view.find_children("*", "GeometryInstance3D", true, false):
		check_eq((n as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % n.name)
	var shaft := view.find_child("Shaft", true, false) as GeometryInstance3D
	var reach := view.find_child("Reach", true, false) as GeometryInstance3D
	var glow := view.find_child("Glow", true, false) as GeometryInstance3D
	check(shaft != null and reach != null and glow != null, "the view has its shaft, ring and glow")
	if shaft != null and reach != null and glow != null:
		check(shaft.material_override != null and shaft.material_override == reach.material_override
				and glow.material_override == shaft.material_override, "Shaft, Reach and Glow share one light")
		check(shaft.material_override != load(ShoreView.LIGHT_MATERIAL), "the light is the view's own copy")
	view.free()


func test_a_shore_that_rises_in_play_comes_up_out_of_the_deep() -> void:
	var view := ShoreView.new()
	var model := view.find_child("Model", false, false) as Node3D
	check(model != null, "the view holds its model")
	if model == null:
		view.free()
		return
	check_near(model.position.y, 0.0, 1e-6, "a new view (a save loaded with the shore up) stands at rest")
	check(not view.rising(), "a new view is not rising")
	view.rise()
	view.place(Vector2(2, -5))
	check(view.visible, "place() shows a rising shore")
	check_near(model.position.y, -ShoreView.RISE_DEPTH_M, 1e-4, "it starts RISE_DEPTH_M down")
	check_near(view.light_strength(), 0.0, 1e-6, "its light starts off")
	view.pulse(ShoreView.RISE_S * 0.5)
	var mid := model.position.y
	check(mid > -ShoreView.RISE_DEPTH_M and mid < 0.0, "half way through it is on its way up (%.2f m)" % mid)
	check(view.rising(), "it is still rising")
	view.pulse(0.0)
	check_near(model.position.y, mid, 1e-6, "a paused pool (pulse 0) holds the rise")
	view.pulse(ShoreView.RISE_S)
	check_near(model.position.y, 0.0, 1e-6, "after RISE_S it is at rest")
	check(not view.rising(), "the rise is over")
	check(view.light_strength() > 0.5, "its light is on (%.2f)" % view.light_strength())
	view.free()


func test_the_sand_keeps_dim_and_clear_of_reserved_hues() -> void:
	var image := (load(ALBEDO) as Texture2D).get_image()
	image.clear_mipmaps()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var lums := PackedFloat32Array()
	var hued := 0
	var near := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			lums.append(c.srgb_to_linear().get_luminance())
			var lab := _lab(c)
			if Vector2(lab.y, lab.z).length() < HUE_CHROMA:
				continue
			hued += 1
			if _reserved_gap(lab) < MIN_LAB_HUE_GAP_DEG:
				near += 1
	lums.sort()
	var median := lums[lums.size() / 2]
	var p99 := lums[int(lums.size() * 0.99)]
	check(p99 <= MAX_LUMINANCE, "the sand's p99 linear luminance %.3f is at most %.2f (under the plane)" % [p99, MAX_LUMINANCE])
	check(p99 <= MAX_P99_LUMINANCE, "the sand's p99 linear luminance %.3f is at most %.2f (the tuned exposure)" % [p99, MAX_P99_LUMINANCE])
	check(median <= MAX_MEDIAN_LUMINANCE, "the sand's median linear luminance %.3f is at most %.2f (the tuned exposure)" % [median, MAX_MEDIAN_LUMINANCE])
	var share := float(near) / maxf(1.0, float(hued))
	check(share <= MAX_NEAR_SHARE, "%.2f%% of hued texels sit within %.0f deg of food or threat" % [share * 100.0, MIN_LAB_HUE_GAP_DEG])


func test_the_endless_start_fade_warms_the_shore() -> void:
	var scene := load(ShoreView.SCENE)   # held, so every instance shares the cached meshes
	var shore := ShoreView.warm_up_meshes()
	check_eq(shore.size(), 4, "the bank, the shaft, the ring and the glow")
	var endless := FakeEvents.open_pool(FakeEvents.endless_session())
	var warmed := endless.warm_up_meshes()
	for mesh in shore:
		check(warmed.has(mesh), "the endless start fade warms %s" % mesh.resource_name)
	endless.free()
	var m1 := FakeEvents.open_pool(FakeEvents.pool_session())
	var m1_warmed := m1.warm_up_meshes()
	for mesh in shore:
		check(not m1_warmed.has(mesh), "the M1 pool does not warm %s" % mesh.resource_name)
	m1.free()
	scene = null
