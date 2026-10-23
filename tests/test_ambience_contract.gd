extends TestCase
## The ambience contract (docs/micro-world-plan.md section 7 in the project files; docs/DECISIONS.md,
## "Microscopic world look"): what art's decor scene, game/scenes/pool/ambience/ambience.tscn, keeps
## to so that it never competes with a gameplay cue, never reaches into the simulation and stays in
## its budget. The pool mounts the scene as its single child "Ambience" when it exists
## (pool.gd _mount_ambience); the scene reads get_parent().camera and get_parent().cell_view and
## writes nothing back. Until the scene lands, every check but the mount's passes without looking.
##
## The scene is built as the pool builds it: mounted under a pool, then readied (the test runner has
## no scene tree, so the test sends the ready notification itself). What it then holds is checked:
## every GeometryInstance3D, every material it draws with (overrides, surface materials and their
## next passes) and each MultiMesh's instances. Colour and opacity are read the way the decor
## shaders draw them, by convention:
##   - a material's colours are its Color uniforms and its texture uniforms, times a float uniform
##     `brightness` when it has one; a standard material's are its albedo, emission and albedo
##     texture, and a particle process material's its colour and colour ramps. For hue, a flat
##     colour and every stop of a gradient or colour ramp count one by one, and an image texture
##     (a painting) by its alpha-weighted mean;
##   - its opacity is the product of what it has of: the colour's or texel's alpha, a float uniform
##     `opacity` (or `alpha`), and its MultiMesh instances' custom data w (INSTANCE_CUSTOM.w). An
##     opaque material's opacity is 1;
##   - a shader that places its own instances (wrapping them around the camera, say) names the band
##     of world heights it draws them in as a vec2 uniform `height_range`, which then stands for
##     their heights.
## The headless runner cannot read a MultiMesh's instance data: its dummy renderer keeps no buffer,
## so transforms read as identity and custom data as (0, 0, 0, 1). There an instanced layer needs a
## `height_range`, and its custom w counts as up to 1, so its top opacity belongs in `opacity`.
## Luminance is linear, as art measures it: Color.srgb_to_linear().get_luminance().

const SCENE := "res://game/scenes/pool/ambience/ambience.tscn"
const AMBIENCE_DIR := "res://game/scenes/pool/ambience"
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
const SYSTEMS_DIR := "res://game/systems"
const CREATURE_VIEW := "res://game/scenes/pool/creature_view.gd"
## The strike lane draws at this priority and every world transparent below it (plan section 3);
## creature_view.gd names it LANE_PRIORITY once the lane commit (C5) lands, and then this reads it.
const PLAN_LANE_PRIORITY := 8
## Nothing decorative lies in this band around the swim plane (m)...
const PLANE_BAND := Vector2(-1.5, 0.5)
## ...and the foreground above it is sparse and stays low: the plan's foreground band ends 3 m up.
## The camera sits 8.2 m over the plane at zoom 10, so decor much higher would fill the screen.
const MAX_FOREGROUND := 40
const FOREGROUND_TOP_M := 3.0
## Budgets (the ambience handoff): live particles, large billboards, and transparent billboards
## stacked over one point. A billboard is large from this size (m) on.
const MAX_PARTICLES := 2000
const MAX_BILLBOARDS := 12
const LARGE_M := 2.0
const MAX_STACKED := 3
const STACK_GRID_M := 1.0
## Reserved hues: food's glow and the threat pink. No decor colour comes within this many degrees of
## LAB hue of either. Below this chroma a colour is grey and has no hue to speak of.
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
const HUE_GAP := 25.0
const MIN_CHROMA := 5.0
## Linear luminance caps: times opacity for transparent decor, and alone for anything under the plane.
const MAX_LUMA_ALPHA := 0.12
const MAX_LUMA_BELOW := 0.40
## Texture uniforms are read at this size.
const TEXEL_GRID := 64
const LookProbe := preload("res://tools/godot/look_probe.gd")


## A pool whose camera and cell view are set as its ready sets them. Free it.
func _pool() -> Node:
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	pool.camera = pool.get_node("Camera")
	pool.cell_view = pool.get_node("PlayerCell")
	return pool


## Art's scene as a pool mounts it, readied, or null (and a failed check) when the pool does not
## mount it as "Ambience". Free it with its pool: ambience.get_parent().free().
func _mounted() -> Node:
	var pool := _pool()
	pool._mount_ambience()
	var ambience := pool.get_node_or_null("Ambience")
	if ambience == null:
		check(false, "the pool mounts %s as its child Ambience" % SCENE)
		pool.free()
		return null
	_ready_tree(ambience)
	return ambience


## Readies `node` as the tree would: its children first, then itself.
func _ready_tree(node: Node) -> void:
	for child in node.get_children():
		_ready_tree(child)
	node.notification(Node.NOTIFICATION_READY)


## Every node under `root` of `type`, root included.
func _nodes(root: Node, type: String) -> Array[Node]:
	var out: Array[Node] = []
	if root.is_class(type):
		out.append(root)
	for n in root.find_children("*", type, true, false):
		out.append(n)
	return out


## `node`'s transform relative to `root`, without a scene tree.
func _relative(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Every material a geometry instance draws with, next passes included.
func _materials(geo: GeometryInstance3D) -> Array[Material]:
	var first: Array[Material] = []
	if geo.material_override:
		first.append(geo.material_override)
	var mesh: Mesh = null
	if geo is MeshInstance3D:
		mesh = (geo as MeshInstance3D).mesh
		for s in (mesh.get_surface_count() if mesh else 0):
			var m := (geo as MeshInstance3D).get_surface_override_material(s)
			first.append(m if m else mesh.surface_get_material(s))
	elif geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh:
		mesh = (geo as MultiMeshInstance3D).multimesh.mesh
		for s in (mesh.get_surface_count() if mesh else 0):
			first.append(mesh.surface_get_material(s))
	elif geo is GPUParticles3D:
		first.append((geo as GPUParticles3D).process_material)
		for p in (geo as GPUParticles3D).draw_passes:
			var pass_mesh := (geo as GPUParticles3D).get_draw_pass_mesh(p)
			for s in (pass_mesh.get_surface_count() if pass_mesh else 0):
				first.append(pass_mesh.surface_get_material(s))
	elif geo is CPUParticles3D and (geo as CPUParticles3D).mesh:
		mesh = (geo as CPUParticles3D).mesh
		for s in mesh.get_surface_count():
			first.append(mesh.surface_get_material(s))
	var out: Array[Material] = []
	for m in first:
		var pass_m := m
		while pass_m != null and not out.has(pass_m) and out.size() < 32:
			out.append(pass_m)
			pass_m = pass_m.next_pass
	return out


## The render_mode flags of a shader, comments removed.
func _render_modes(shader: Shader) -> PackedStringArray:
	var text := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(shader.code, "", true)
	text = RegEx.create_from_string("//[^\\n]*").sub(text, "", true)
	var out := PackedStringArray()
	for m in RegEx.create_from_string("render_mode\\s+([^;]+);").search_all(text):
		for flag in m.get_string(1).split(","):
			out.append(flag.strip_edges())
	return out


## "add", "mix" (any other blend) or "opaque", and whether it takes the engine's fog.
func _blend_and_fog(m: Material) -> Dictionary:
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var shader := (m as ShaderMaterial).shader
		var modes := _render_modes(shader)
		var blend := "add" if modes.has("blend_add") else ("mix" if shader.code.contains("ALPHA") or _has_blend(modes) else "opaque")
		return {"blend": blend, "fog": not modes.has("fog_disabled")}
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var blend := "add" if b.blend_mode == BaseMaterial3D.BLEND_MODE_ADD else ("opaque" if b.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and b.blend_mode == BaseMaterial3D.BLEND_MODE_MIX else "mix")
		return {"blend": blend, "fog": not b.disable_fog}
	return {"blend": "opaque", "fog": true}


func _has_blend(modes: PackedStringArray) -> bool:
	for flag in modes:
		if flag.begins_with("blend_"):
			return true
	return false


## A shader uniform's value on `m`, or the shader's default when the material leaves it unset.
func _param(m: ShaderMaterial, uniform_name: String) -> Variant:
	var v: Variant = m.get_shader_parameter(uniform_name)
	return v if v != null else RenderingServer.shader_get_parameter_default(m.shader.get_rid(), uniform_name)


func _uniform_names(m: ShaderMaterial) -> Array[String]:
	var out: Array[String] = []
	for u in m.shader.get_shader_uniform_list():
		out.append(String(u.name))
	return out


## A material's colours (each with its alpha) as the convention above reads them, brightness applied.
func _colors(m: Material) -> Array[Color]:
	var out: Array[Color] = []
	for color_set in _color_sets(m):
		out.append_array(color_set.colors)
	return out


## A material's colours in sets, brightness applied: {"what", "colors", "painting"}. A flat colour,
## or a gradient's or colour ramp's stops, is a set with "painting" false; an image texture's texels
## are one with "painting" true.
func _color_sets(m: Material) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		out.append(_flat("albedo", b.albedo_color, 1.0))
		if b.emission_enabled:
			out.append(_flat("emission", Color(b.emission * b.emission_energy_multiplier, 1.0), 1.0))
		if b.albedo_texture:
			out.append(_texture_colors("albedo_texture", b.albedo_texture, 1.0))
		return out
	if m is ParticleProcessMaterial:
		var p := m as ParticleProcessMaterial
		out.append(_flat("color", p.color, 1.0))
		for ramp: Texture2D in [p.color_ramp, p.color_initial_ramp]:
			if ramp:
				out.append(_texture_colors("color ramp", ramp, 1.0))
		return out
	if not (m is ShaderMaterial and (m as ShaderMaterial).shader):
		return out
	var sm := m as ShaderMaterial
	var names := _uniform_names(sm)
	var brightness := float(_param(sm, "brightness")) if names.has("brightness") else 1.0
	for uniform_name in names:
		var v: Variant = _param(sm, uniform_name)
		if v is Color:
			out.append(_flat(uniform_name, v, brightness))
		elif v is Texture2D:
			out.append(_texture_colors(uniform_name, v, brightness))
	return out


func _flat(what: String, c: Color, brightness: float) -> Dictionary:
	var colors: Array[Color] = [Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a)]
	return {"what": what, "colors": colors, "painting": false}


## A texture's colours: a gradient's stops (a gradient texture, or a noise texture's colour ramp),
## else its texels on a TEXEL_GRID square, a painting.
func _texture_colors(what: String, texture: Texture2D, brightness: float) -> Dictionary:
	var colors: Array[Color] = []
	var gradient: Gradient = null
	if texture is GradientTexture1D or texture is GradientTexture2D:
		gradient = texture.gradient
	elif texture is NoiseTexture2D:
		gradient = (texture as NoiseTexture2D).color_ramp
	if gradient:
		for c in gradient.colors:
			colors.append(Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a))
		return {"what": what, "colors": colors, "painting": false}
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		image.resize(TEXEL_GRID, TEXEL_GRID)
		for y in TEXEL_GRID:
			for x in TEXEL_GRID:
				var c := image.get_pixel(x, y)
				colors.append(Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a))
	return {"what": what, "colors": colors, "painting": true}


## The largest opacity a material's own uniforms give it (opacity or alpha), or 1.
func _uniform_opacity(m: Material) -> float:
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var names := _uniform_names(m)
		for key in ["opacity", "alpha"]:
			if names.has(key):
				return float(_param(m, key))
	return 1.0


## Whether this runner can read a MultiMesh's instance data (see the note at the top).
func _readable(mm: MultiMesh) -> bool:
	return mm.instance_count == 0 or not mm.buffer.is_empty()


## The largest instance opacity of a MultiMesh that carries it in custom data w, or 1 (also when
## the instance data cannot be read here).
func _instance_opacity(geo: GeometryInstance3D) -> float:
	if not (geo is MultiMeshInstance3D) or (geo as MultiMeshInstance3D).multimesh == null:
		return 1.0
	var mm := (geo as MultiMeshInstance3D).multimesh
	if not mm.use_custom_data or not _readable(mm):
		return 1.0
	var top := 0.0
	for i in mm.instance_count:
		top = maxf(top, mm.get_instance_custom_data(i).a)
	return top


func _luma(c: Color) -> float:
	return Color(c.r, c.g, c.b).srgb_to_linear().get_luminance()


## Heights (y, in the pool's space) a geometry instance takes up: {"low", "high", "points"}. The
## points are its MultiMesh instances' origins, or its mesh's lowest and highest point; a material's
## `height_range` gives the band instead ("band" true), with one point per instance at its foot.
## "known" is false for instances this runner cannot read when nothing names their band.
func _heights(geo: GeometryInstance3D, root: Node) -> Dictionary:
	var t := _relative(geo, root)
	var points := PackedFloat32Array()
	for m in _materials(geo):
		if m is ShaderMaterial and (m as ShaderMaterial).shader and _uniform_names(m).has("height_range"):
			var band: Vector2 = _param(m, "height_range")
			var count := (geo as MultiMeshInstance3D).multimesh.instance_count if geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh else 1
			points.resize(count)
			points.fill(band.x)
			return {"low": band.x, "high": band.y, "points": points, "known": true, "band": true}
	if geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh:
		var mm := (geo as MultiMeshInstance3D).multimesh
		if not _readable(mm):
			return {"low": 0.0, "high": 0.0, "points": points, "known": false, "band": false}
		for i in mm.instance_count:
			points.append((t * mm.get_instance_transform(i)).origin.y)
	elif geo is GPUParticles3D or geo is CPUParticles3D:
		points.append(t.origin.y)
	else:
		var box := t * geo.get_aabb()
		points.append(box.position.y)
		points.append(box.end.y)
	return {"low": Array(points).min() if not points.is_empty() else 0.0, "high": Array(points).max() if not points.is_empty() else 0.0, "points": points, "known": true, "band": false}


func _lane_priority() -> int:
	var script: GDScript = load(CREATURE_VIEW)
	return int(script.get_script_constant_map().get("LANE_PRIORITY", PLAN_LANE_PRIORITY))


## Every source file of the ambience, by path.
func _sources(dir: String, out: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "gdshader", "tscn", "tres"]:
			out[dir + "/" + f] = FileAccess.get_file_as_string(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		_sources(dir + "/" + sub, out)


func test_the_pool_mounts_the_ambience_once_as_its_single_child_named_ambience() -> void:
	check_eq(PoolScene.AMBIENCE_SCENE, SCENE, "the pool mounts the contract's scene")
	var pool := _pool()
	# Mounted twice, as a second ready would: a second copy would be renamed, so count both ways.
	pool._mount_ambience()
	pool._mount_ambience()
	var mounted := 0
	for child in pool.get_children():
		mounted += 1 if child.name == "Ambience" or child.scene_file_path == SCENE else 0
	var exists := ResourceLoader.exists(SCENE)
	check_eq(mounted, 1 if exists else 0, "ambience children with%s the scene" % ("" if exists else "out"))
	var ambience := pool.get_node_or_null("Ambience")
	if exists and ambience != null:
		check_eq(ambience.scene_file_path, SCENE, "the Ambience child is the art scene")
		check(ambience.find_children("*", "", true, false).all(func(n: Node) -> bool: return n.name != "Ambience"), "and holds no second Ambience")
	pool.free()


func test_the_ambience_reads_the_pool_and_writes_nothing_back() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	var camera: Camera3D = pool.get_node("Camera")
	var cell: Node3D = pool.get_node("PlayerCell")
	pool.camera = camera
	pool.cell_view = cell
	var keys := ["camera", "cell_view", "sim", "session", "intent_provider", "paused"]
	var before := {}
	for key in keys:
		before[key] = pool.get(key)
	var camera_before := [camera.transform, camera.fov, camera.near, camera.far, camera.current]
	var cell_before := [cell.transform, cell.visible]
	var children_before := pool.get_child_count()
	pool._mount_ambience()
	var ambience := pool.get_node_or_null("Ambience")
	if ambience == null:
		check(false, "the pool mounts %s as its child Ambience" % SCENE)
		pool.free()
		return
	_ready_tree(ambience)
	for key in keys:
		check(pool.get(key) == before[key], "the pool's %s is unchanged" % key)
	check([camera.transform, camera.fov, camera.near, camera.far, camera.current] == camera_before, "the camera is unchanged")
	check([cell.transform, cell.visible] == cell_before, "the cell view is unchanged")
	check_eq(pool.get_child_count(), children_before + 1, "the ambience adds only itself to the pool")
	pool.free()


func test_the_ambience_never_reaches_into_the_simulation() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var sources := {}
	_sources(AMBIENCE_DIR, sources)
	check(not sources.is_empty(), "the ambience has sources")
	# Every class the simulation's scripts declare, PoolSim among them.
	var banned := ["res://game/systems"]
	var systems := {}
	_sources(SYSTEMS_DIR, systems)
	for path: String in systems:
		var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(systems[path])
		if m:
			banned.append(m.get_string(1))
	check(banned.has("PoolSim"), "the banned names include PoolSim: %s" % [banned])
	var global_random := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(")
	for path: String in sources:
		var text: String = sources[path]
		for name in banned:
			var word := RegEx.create_from_string("(?<![\\w])%s(?![\\w])" % name.replace("/", "\\/").replace(".", "\\."))
			check(word.search(text) == null, "%s mentions %s" % [path, name])
		# Random numbers come from its own generator, never the global one the sim must not share.
		check(global_random.search(text) == null, "%s draws from the global random generator" % path)
		if text.contains(".randf") or text.contains(".randi"):
			check(text.contains("RandomNumberGenerator.new()"), "%s draws from a RandomNumberGenerator of its own" % path)


func test_nothing_it_draws_casts_a_shadow_or_draws_over_the_strike_lane() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	var lane := _lane_priority()
	var geos := _nodes(ambience, "GeometryInstance3D")
	check(not geos.is_empty(), "the ambience draws something")
	for geo: GeometryInstance3D in geos:
		check_eq(geo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % geo.name)
		for m in _materials(geo):
			check(m.render_priority < lane, "%s draws at priority %d, under the lane's %d" % [geo.name, m.render_priority, lane])
	ambience.get_parent().free()


func test_additive_decor_takes_no_fog_and_the_rest_fades_with_it() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		for m in _materials(geo):
			if m is ParticleProcessMaterial:
				continue
			var look := _blend_and_fog(m)
			if look.blend == "add":
				check(not look.fog, "%s adds light, so it takes no fog (it would paint a bright hard quad)" % geo.name)
			else:
				check(look.fog, "%s keeps the engine's fog, so it fades into the Backdrop exactly" % geo.name)
	ambience.get_parent().free()


func test_nothing_costly_or_banned() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	for type in ["WorldEnvironment", "Camera3D", "FogVolume", "Light3D", "ReflectionProbe", "VoxelGI", "LightmapGI"]:
		check(_nodes(ambience, type).is_empty(), "the ambience has no %s" % type)
	ambience.get_parent().free()
	var sources := {}
	_sources(AMBIENCE_DIR, sources)
	for path: String in sources:
		for word in ["CameraAttributes", "Environment.new", "dof_blur", "volumetric_fog", "fog_aerial_perspective", "WorldEnvironment"]:
			check(not (sources[path] as String).contains(word), "%s uses %s (depth of field, volumetric fog, aerial perspective and camera attributes are banned)" % [path, word])


func test_decor_stays_clear_of_the_swim_plane() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	var above := 0
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		var h := _heights(geo, ambience)
		if not h.known:
			check(false, "%s: this runner cannot read its instances, so its material names their band in a height_range uniform" % geo.name)
			continue
		var inside := 0
		var over := 0
		for y in h.points:
			inside += 1 if y > PLANE_BAND.x and y < PLANE_BAND.y else 0
			over += 1 if y >= PLANE_BAND.y else 0
		if not (geo is MultiMeshInstance3D) or h.band:
			inside += 1 if h.low < PLANE_BAND.y and h.high > PLANE_BAND.x else 0
		# Items above the plane: every MultiMesh instance and every particle counts, a mesh once.
		if geo is MultiMeshInstance3D:
			above += over
		elif over > 0:
			above += (geo as GPUParticles3D).amount if geo is GPUParticles3D else ((geo as CPUParticles3D).amount if geo is CPUParticles3D else 1)
		check(inside == 0, "%s keeps out of %.1f to %.1f m around the swim plane (%d inside; it spans %.2f to %.2f m)" % [geo.name, PLANE_BAND.x, PLANE_BAND.y, inside, h.low, h.high])
		# The top of its band, its highest instance, or its mesh's top.
		check(h.high <= FOREGROUND_TOP_M, "%s stays at most %.1f m above the swim plane (it reaches %.2f m)" % [geo.name, FOREGROUND_TOP_M, h.high])
	check(above <= MAX_FOREGROUND, "%d decor items above the plane, at most %d" % [above, MAX_FOREGROUND])
	ambience.get_parent().free()


func test_the_ambience_keeps_to_its_budget() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	var particles := 0
	var billboards: Array[GeometryInstance3D] = []
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		if geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh:
			var mm := (geo as MultiMeshInstance3D).multimesh
			particles += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif geo is GPUParticles3D:
			particles += (geo as GPUParticles3D).amount
		elif geo is CPUParticles3D:
			particles += (geo as CPUParticles3D).amount
		elif geo is MeshInstance3D and (geo as MeshInstance3D).mesh:
			var size := (geo as MeshInstance3D).mesh.get_aabb().size * (geo as Node3D).basis.get_scale()
			if maxf(size.x, maxf(size.y, size.z)) >= LARGE_M:
				billboards.append(geo)
	check(particles <= MAX_PARTICLES, "%d live particles, at most %d" % [particles, MAX_PARTICLES])
	check(billboards.size() <= MAX_BILLBOARDS, "%d large billboards, at most %d" % [billboards.size(), MAX_BILLBOARDS])
	# Transparent billboards stacked over one point of the plan, on a grid over their footprints.
	var stacked := 0
	var flat: Array[Dictionary] = []
	for geo in billboards:
		var see_through := false
		for m in _materials(geo):
			see_through = see_through or _blend_and_fog(m).blend != "opaque"
		if see_through:
			var t := _relative(geo, ambience)
			flat.append({"inverse": t.affine_inverse(), "y": t.origin.y, "box": (geo as MeshInstance3D).mesh.get_aabb(), "world": t * (geo as MeshInstance3D).mesh.get_aabb()})
	var area := AABB()
	for i in flat.size():
		area = flat[i].world if i == 0 else area.merge(flat[i].world)
	if not flat.is_empty():
		for gx in range(int(floor(area.position.x)), int(ceil(area.end.x)) + 1, int(STACK_GRID_M)):
			for gz in range(int(floor(area.position.z)), int(ceil(area.end.z)) + 1, int(STACK_GRID_M)):
				var over := 0
				for b in flat:
					var local: Vector3 = (b.inverse as Transform3D) * Vector3(gx, b.y, gz)
					var box: AABB = b.box
					over += 1 if local.x >= box.position.x and local.x <= box.end.x and local.z >= box.position.z and local.z <= box.end.z else 0
				stacked = maxi(stacked, over)
	check(stacked <= MAX_STACKED, "at most %d transparent billboards over one point, got %d" % [MAX_STACKED, stacked])
	ambience.get_parent().free()


func test_decor_keeps_clear_of_the_food_and_threat_hues() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		for m in _materials(geo):
			var named: Array = []
			for color_set: Dictionary in _color_sets(m):
				if not color_set.painting:
					# A flat colour, and every stop of a ramp however many it has, counts as it is.
					for c: Color in color_set.colors:
						named.append(["%s %s" % [color_set.what, c.to_html(false)], c])
					continue
				# A painting counts by its alpha-weighted mean.
				var sum := Color(0, 0, 0, 0)
				for c: Color in color_set.colors:
					sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
				if sum.a > 0.0:
					named.append(["%s's mean" % color_set.what, Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a)])
			for entry in named:
				var lab := LookProbe.lab(entry[1])
				if Vector2(lab.y, lab.z).length() < MIN_CHROMA:
					continue
				for reserved: String in RESERVED:
					var gap := LookProbe.hue_gap(LookProbe.hue(lab), LookProbe.hue(LookProbe.lab(RESERVED[reserved])))
					check(gap >= HUE_GAP, "%s colour %s is %.0f degrees of LAB hue from the %s colour, at least %.0f" % [geo.name, entry[0], gap, reserved, HUE_GAP])
	ambience.get_parent().free()


func test_pale_decor_is_too_faint_to_lift_the_fluid_or_cut_the_lane() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		var below: bool = _heights(geo, ambience).high < 0.0
		var instance := _instance_opacity(geo)
		var unread := geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh != null and (geo as MultiMeshInstance3D).multimesh.use_custom_data \
			and not _readable((geo as MultiMeshInstance3D).multimesh)
		var note := " (its instances' custom w cannot be read here and counts as up to 1: carry the top opacity in an opacity uniform)" if unread else ""
		for m in _materials(geo):
			if m is ParticleProcessMaterial:
				continue
			var opaque: bool = _blend_and_fog(m).blend == "opaque"
			var opacity := _uniform_opacity(m) * instance
			var top := 0.0
			var top_lit := 0.0
			for c in _colors(m):
				top = maxf(top, _luma(c))
				top_lit = maxf(top_lit, _luma(c) * (1.0 if opaque else c.a * opacity))
			if not opaque:
				check(top_lit <= MAX_LUMA_ALPHA + 1e-4, "%s: luminance x opacity %.3f, at most %.2f%s" % [geo.name, top_lit, MAX_LUMA_ALPHA, note])
			if below:
				check(top <= MAX_LUMA_BELOW + 1e-4, "%s under the plane: luminance %.3f, at most %.2f" % [geo.name, top, MAX_LUMA_BELOW])
	ambience.get_parent().free()
