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
## next passes, and a sprite's own, which the engine builds from its texture and modulate) and each
## MultiMesh's instances. Decor draws only with what the contract can read: meshes, MultiMeshes,
## particles and sprites. Colour, opacity and size are read the way the decor draws them, by
## convention:
##   - a material's colours are its Color uniforms and its texture uniforms (as the material sets
##     them, else as the shader's code declares them), times a float uniform `brightness` when it
##     has one, its textures also times a Color uniform `tint` when it has one (S3: the shader draws
##     texture x tint, as a standard material draws its albedo texture times its albedo), and any
##     literal colour its shader writes to ALBEDO or EMISSION
##     (a vec3 or vec4 of numbers in the assignment, or in a constant or local variable it reads);
##     a standard material's are its albedo, emission and albedo texture (times the albedo, as it
##     draws), its albedo times each vertex colour of the mesh when vertex_color_use_as_albedo is
##     set, and a particle process material's (or a CPU emitter's) its colour and colour ramps. A
##     shader that reads COLOR counts the mesh's vertex colours too. A sprite draws its texture
##     times its modulate. For hue, a flat colour, every stop of a gradient or colour ramp and every
##     vertex colour count one by one, and an image texture (a painting) by coverage: at most
##     PAINTING_SHARE of its alpha-weighted texels with chroma PAINTING_CHROMA or more may lie near
##     a reserved hue;
##   - its opacity is the product of what it has of: the colour's or texel's alpha (a sprite's
##     modulate alpha among them), a float uniform `opacity` (or `alpha`), and its MultiMesh
##     instances' custom data w (INSTANCE_CUSTOM.w). An opaque material's opacity is 1;
##   - a shader that places its own instances (wrapping them around the camera, say) names the band
##     of world heights it draws them in as a vec2 uniform `height_range`, which then stands for
##     their heights;
##   - a particle emitter's heights are its emission shape's extents and its visibility_aabb,
##     whichever reaches further, so its visibility_aabb should hold where its particles go. A CPU
##     emitter also reaches as far as its fastest particle can travel in its lifetime, pushed by its
##     strongest acceleration and falling with gravity;
##   - an item's size is its mesh's box, a sprite's rectangle (a billboard sweeps the cube round it),
##     one instance's mesh (an instanced layer's shader draws each item at its mesh's size or
##     smaller), or one particle's draw mesh at its largest scale.
## The headless runner cannot read a MultiMesh's instance data: its dummy renderer keeps no buffer,
## so transforms read as identity, custom data and colours as (0, 0, 0, 1). There an instanced
## layer needs a `height_range`, its custom w counts as up to 1, so its top opacity belongs in
## `opacity`, and it carries its colours in uniforms, not instance colours.
## Luminance is linear, as art measures it: Color.srgb_to_linear().get_luminance().
##
## S2: the ghosts and giants (game/scenes/pool/ghost_layer.gd, s2-view 6) are decor too. They keep
## the same rules with every slot drawn at once, and share the large-billboard budget (S2G15).

const SCENE := "res://game/scenes/pool/ambience/ambience.tscn"
const AMBIENCE_DIR := "res://game/scenes/pool/ambience"
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
const SYSTEMS_DIR := "res://game/systems"
## Nothing decorative lies in this band around the swim plane (m)...
const PLANE_BAND := Vector2(-1.5, 0.5)
## ...and the foreground above it is sparse, low and small (plan section 7): at most MAX_FOREGROUND
## items, none above the band's top at 3 m (the camera sits 8.2 m over the plane at zoom 10, so an
## item there already draws about 1.6 times its size at the plane), and no single item above the
## plane LARGE_M or more in any direction, whatever draws it (a mesh, a sprite, one instance of a
## layer or one particle), since one faint sheet over the cell veils the whole middle of the frame
## however low it hangs.
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
## A painting may show a reserved hue in a few stray texels, never in a shape: at most this share
## of its alpha-weighted texels, counting those of at least PAINTING_CHROMA (after brightness).
const PAINTING_SHARE := 0.02
const PAINTING_CHROMA := 12.0
## Linear luminance caps: times opacity for transparent decor, and alone for anything under the plane.
const MAX_LUMA_ALPHA := 0.12
const MAX_LUMA_BELOW := 0.40
## Texture uniforms are read at this size.
const TEXEL_GRID := 64
## A number in shader code.
const NUMBER := "[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?"
const LookProbe := preload("res://tools/godot/look_probe.gd")
const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")


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
	elif geo is CPUParticles3D:
		# A CPU emitter's colour and ramps, read as a process material's are.
		var cpu := geo as CPUParticles3D
		var process := ParticleProcessMaterial.new()
		process.color = cpu.color
		for ramp in [["color_ramp", cpu.color_ramp], ["color_initial_ramp", cpu.color_initial_ramp]]:
			if ramp[1]:
				var texture := GradientTexture1D.new()
				texture.gradient = ramp[1]
				process.set(ramp[0], texture)
		first.append(process)
		mesh = cpu.mesh
		for s in (mesh.get_surface_count() if mesh else 0):
			first.append(mesh.surface_get_material(s))
	elif geo is SpriteBase3D:
		first.append_array(_sprite_materials(geo))
	var out: Array[Material] = []
	for m in first:
		var pass_m := m
		while pass_m != null and not out.has(pass_m) and out.size() < 32:
			out.append(pass_m)
			pass_m = pass_m.next_pass
	return out


## What a sprite draws with, as a standard material: its texture times its modulate (the modulate's
## alpha its opacity), see-through unless it is opaque or cut out, at its own render priority. The
## engine builds the real material inside the renderer, where this runner cannot read it. An
## animated sprite gives one per frame.
func _sprite_materials(sprite: SpriteBase3D) -> Array[Material]:
	var textures: Array[Texture2D] = []
	if sprite is Sprite3D:
		textures.append((sprite as Sprite3D).texture)
	elif sprite is AnimatedSprite3D and (sprite as AnimatedSprite3D).sprite_frames:
		var frames := (sprite as AnimatedSprite3D).sprite_frames
		for animation in frames.get_animation_names():
			for i in frames.get_frame_count(animation):
				textures.append(frames.get_frame_texture(animation, i))
	var out: Array[Material] = []
	for texture in textures:
		var m := StandardMaterial3D.new()
		m.albedo_color = sprite.modulate
		m.albedo_texture = texture
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if sprite.transparent and sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED \
			else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if sprite.shaded else BaseMaterial3D.SHADING_MODE_UNSHADED
		m.render_priority = sprite.render_priority
		out.append(m)
	return out


## A shader's code with its comments removed.
func _code(shader: Shader) -> String:
	var text := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(shader.code, "", true)
	return RegEx.create_from_string("//[^\\n]*").sub(text, "", true)


## The render_mode flags of a shader, comments removed.
func _render_modes(shader: Shader) -> PackedStringArray:
	var text := _code(shader)
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


## A shader uniform's value on `m`, or the shader's default when the material leaves it unset. The
## headless renderer gives no defaults, so a default is read from the shader's code (a number, or a
## vecN of numbers), and a uniform declared without one is zero, as in GLSL. Null for a texture left
## unset.
func _param(m: ShaderMaterial, uniform_name: String) -> Variant:
	var v: Variant = m.get_shader_parameter(uniform_name)
	if v == null:
		v = RenderingServer.shader_get_parameter_default(m.shader.get_rid(), uniform_name)
	if v != null:
		return v
	var type := TYPE_NIL
	var opaque := false
	for u in m.shader.get_shader_uniform_list():
		if String(u.name) == uniform_name:
			type = u.type
			# A vec3 colour (source_color) has no alpha: it is opaque.
			opaque = u.hint == PROPERTY_HINT_COLOR_NO_ALPHA
	var declared := RegEx.create_from_string("\\buniform\\s+\\w+\\s+%s\\b[^=;]*(?:=\\s*([^;]+))?;" % uniform_name).search(_code(m.shader))
	var n: Array[float] = []
	if declared:
		# Its numbers, once names such as vec3 are gone.
		var text := RegEx.create_from_string("\\b[A-Za-z_]\\w*").sub(declared.get_string(1), " ", true)
		for value in RegEx.create_from_string(NUMBER).search_all(text):
			n.append(float(value.get_string(0)))
	# One number fills every component, as vec3(1.0) does; missing ones are zero.
	var at := func(i: int) -> float: return n[0] if n.size() == 1 else (n[i] if i < n.size() else 0.0)
	match type:
		TYPE_FLOAT, TYPE_INT:
			return at.call(0)
		TYPE_BOOL:
			return declared != null and declared.get_string(1).contains("true")
		TYPE_VECTOR2:
			return Vector2(at.call(0), at.call(1))
		TYPE_VECTOR3:
			return Vector3(at.call(0), at.call(1), at.call(2))
		TYPE_VECTOR4:
			return Vector4(at.call(0), at.call(1), at.call(2), at.call(3))
		TYPE_COLOR:
			return Color(at.call(0), at.call(1), at.call(2), 1.0 if opaque else at.call(3))
	return null


func _uniform_names(m: ShaderMaterial) -> Array[String]:
	var out: Array[String] = []
	for u in m.shader.get_shader_uniform_list():
		out.append(String(u.name))
	return out


## A material's colours (each with its alpha) as the convention above reads them, brightness applied;
## `geo` gives the mesh whose vertex colours a standard material may use.
func _colors(m: Material, geo: GeometryInstance3D = null) -> Array[Color]:
	var out: Array[Color] = []
	for color_set in _color_sets(m, geo):
		out.append_array(color_set.colors)
	return out


## A material's colours in sets, brightness applied: {"what", "colors", "painting"}. A flat colour,
## a gradient's or colour ramp's stops, or a mesh's vertex colours, is a set with "painting" false;
## an image texture's texels are one with "painting" true. A MultiMesh's instance colours that this
## runner cannot read come as a set with "unread" true and no colours.
func _color_sets(m: Material, geo: GeometryInstance3D = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var vertex: Array[Color] = []
		if b.vertex_color_use_as_albedo:
			vertex = _vertex_colors(geo)
			out.append_array(_instance_color_sets(geo, b.albedo_color))
		if vertex.is_empty() and b.albedo_texture == null:
			out.append(_flat("albedo", b.albedo_color, 1.0))
		elif not vertex.is_empty():
			# The albedo the engine draws is the albedo colour times each vertex's colour.
			var colors: Array[Color] = []
			for c: Color in vertex:
				colors.append(b.albedo_color * c)
			out.append({"what": "albedo x vertex colour", "colors": colors, "painting": false})
		if b.emission_enabled:
			out.append(_flat("emission", Color(b.emission * b.emission_energy_multiplier, 1.0), 1.0))
		if b.albedo_texture:
			# The engine draws the texture times the albedo colour, alpha too (and the albedo alone
			# nowhere).
			out.append(_texture_colors("albedo_texture", b.albedo_texture, 1.0, b.albedo_color))
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
	var tint: Variant = _param(sm, "tint") if names.has("tint") else null
	for uniform_name in names:
		var v: Variant = _param(sm, uniform_name)
		if v is Color:
			out.append(_flat(uniform_name, v, brightness))
		elif v is Texture2D:
			out.append(_texture_colors(uniform_name, v, brightness, tint if tint is Color else Color.WHITE))
	var literal := _literal_colors(sm.shader)
	if not literal.is_empty():
		out.append({"what": "literal colour in the shader", "colors": literal, "painting": false})
	# A shader that reads COLOR draws the mesh's vertex colours (and a MultiMesh's instance colours).
	if RegEx.create_from_string("\\bCOLOR\\b").search(_code(sm.shader)) != null:
		var vertex := _vertex_colors(geo)
		if not vertex.is_empty():
			out.append({"what": "vertex colour (the shader reads COLOR)", "colors": vertex, "painting": false})
		out.append_array(_instance_color_sets(geo, Color.WHITE))
	return out


## A MultiMesh's instance colours times `tint`, as one set, when it has them: "unread" when this
## runner cannot read them (see the note at the top).
func _instance_color_sets(geo: GeometryInstance3D, tint: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (geo is MultiMeshInstance3D) or (geo as MultiMeshInstance3D).multimesh == null or not (geo as MultiMeshInstance3D).multimesh.use_colors:
		return out
	var mm := (geo as MultiMeshInstance3D).multimesh
	var colors: Array[Color] = []
	if _readable(mm):
		for i in mm.instance_count:
			colors.append(tint * mm.get_instance_color(i))
	out.append({"what": "instance colour", "colors": colors, "painting": false, "unread": not _readable(mm)})
	return out


## The distinct vertex colours of every mesh `geo` draws (none for a mesh without them).
func _vertex_colors(geo: GeometryInstance3D) -> Array[Color]:
	var meshes: Array[Mesh] = []
	if geo is MeshInstance3D and (geo as MeshInstance3D).mesh:
		meshes.append((geo as MeshInstance3D).mesh)
	elif geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh and (geo as MultiMeshInstance3D).multimesh.mesh:
		meshes.append((geo as MultiMeshInstance3D).multimesh.mesh)
	elif geo is CPUParticles3D and (geo as CPUParticles3D).mesh:
		meshes.append((geo as CPUParticles3D).mesh)
	elif geo is GPUParticles3D:
		for p in (geo as GPUParticles3D).draw_passes:
			if (geo as GPUParticles3D).get_draw_pass_mesh(p):
				meshes.append((geo as GPUParticles3D).get_draw_pass_mesh(p))
	var seen := {}
	var out: Array[Color] = []
	for mesh in meshes:
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_COLOR or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
				continue
			for c: Color in arrays[Mesh.ARRAY_COLOR]:
				var key := c.to_html()
				if not seen.has(key):
					seen[key] = true
					out.append(c)
	return out


## Literal colours a shader writes to ALBEDO or EMISSION: a vec3 or vec4 of numbers in the
## assignment, or in a constant or local variable it reads. A shader's numbers are linear, so each
## comes back as the sRGB colour it draws.
func _literal_colors(shader: Shader) -> Array[Color]:
	var out: Array[Color] = []
	if shader == null:
		return out
	var code := _code(shader)
	var number := NUMBER
	var literal := RegEx.create_from_string("\\bvec[34]\\s*\\(\\s*(%s(?:\\s*,\\s*%s)*)\\s*\\)" % [number, number])
	# Names that hold a literal colour: "const vec3 NAME = vec3(...);", "vec3 name = vec3(...);" or
	# "name = vec3(...);".
	var named := {}
	for m in RegEx.create_from_string("(?:\\bconst\\s+)?(?:\\bvec[34]\\s+)?\\b([A-Za-z_]\\w*)\\s*=\\s*([^;]+);").search_all(code):
		var value := literal.search(m.get_string(2).strip_edges())
		if value and value.get_string(0) == m.get_string(2).strip_edges():
			named[m.get_string(1)] = value.get_string(1)
	for m in RegEx.create_from_string("\\b(?:ALBEDO|EMISSION)\\s*[-+*/]?=\\s*([^;]+);").search_all(code):
		var rhs := m.get_string(1)
		var args: Array[String] = []
		for value in literal.search_all(rhs):
			args.append(value.get_string(1))
		for word in RegEx.create_from_string("\\b[A-Za-z_]\\w*\\b").search_all(rhs):
			if named.has(word.get_string(0)):
				args.append(named[word.get_string(0)])
		for text in args:
			var v := Array(text.split(",")).map(func(x: String) -> float: return float(x.strip_edges()))
			var c := Color(v[0], v[0], v[0]) if v.size() == 1 else Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
			var shown := Color(c.r, c.g, c.b).linear_to_srgb()
			out.append(Color(shown.r, shown.g, shown.b, c.a))
	return out


func _flat(what: String, c: Color, brightness: float) -> Dictionary:
	var colors: Array[Color] = [Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a)]
	return {"what": what, "colors": colors, "painting": false}


## A texture's colours, times `tint` (alpha too): a gradient's stops (a gradient texture, or a noise
## texture's colour ramp), else its texels on a TEXEL_GRID square, a painting.
func _texture_colors(what: String, texture: Texture2D, brightness: float, tint := Color.WHITE) -> Dictionary:
	var colors: Array[Color] = []
	var gradient: Gradient = null
	if texture is GradientTexture1D or texture is GradientTexture2D:
		gradient = texture.gradient
	elif texture is NoiseTexture2D:
		gradient = (texture as NoiseTexture2D).color_ramp
	if gradient:
		for c in gradient.colors:
			colors.append(Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a) * tint)
		return {"what": what, "colors": colors, "painting": false}
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		image.resize(TEXEL_GRID, TEXEL_GRID)
		for y in TEXEL_GRID:
			for x in TEXEL_GRID:
				var c := image.get_pixel(x, y)
				colors.append(Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a) * tint)
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
## points are its MultiMesh instances' origins, a particle emitter's lowest and highest reach
## (_particle_box), or its mesh's or sprite's lowest and highest point (_item_box); a material's
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
		var reach := t * _particle_box(geo)
		points.append(reach.position.y)
		points.append(reach.end.y)
	else:
		var box := t * _item_box(geo)
		points.append(box.position.y)
		points.append(box.end.y)
	return {"low": Array(points).min() if not points.is_empty() else 0.0, "high": Array(points).max() if not points.is_empty() else 0.0, "points": points, "known": true, "band": false}


## Where a particle emitter's particles can be, in its own space: its emission shape's extents
## (box, sphere or ring, offset and scaled as the shape is) merged with its visibility_aabb, so a
## tall emission box or a loose visibility box counts in full. An emitter with neither is a point.
## A CPU emitter's particles also go as far as the fastest of them travels in its lifetime, pushed
## by its strongest acceleration, and fall with its gravity (its visibility_aabb, when set, counts
## too).
func _particle_box(geo: GeometryInstance3D) -> AABB:
	var shape: Variant = null
	var box := AABB()
	var bounded := false
	if geo is GPUParticles3D:
		box = (geo as GPUParticles3D).visibility_aabb
		bounded = true
		shape = (geo as GPUParticles3D).process_material as ParticleProcessMaterial
	elif geo is CPUParticles3D:
		shape = geo
		box = (geo as CPUParticles3D).visibility_aabb
		bounded = box.has_volume()
	if shape == null:
		return box
	var extent := Vector3.ZERO
	match int(shape.emission_shape):
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			extent = shape.emission_box_extents
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			extent = Vector3.ONE * float(shape.emission_sphere_radius)
		ParticleProcessMaterial.EMISSION_SHAPE_RING:
			# A ring around its axis: its radius across and half its height along it, either way up.
			extent = Vector3.ONE * maxf(float(shape.emission_ring_radius), float(shape.emission_ring_height) * 0.5)
	var offset := Vector3.ZERO
	if geo is GPUParticles3D:
		offset = shape.emission_shape_offset
		extent *= (shape.emission_shape_scale as Vector3).abs()
	var emitted := AABB(offset - extent, extent * 2.0)
	if geo is CPUParticles3D:
		var cpu := geo as CPUParticles3D
		var life := cpu.lifetime
		var accel := 0.0
		for a in [cpu.linear_accel_min, cpu.linear_accel_max, cpu.radial_accel_min, cpu.radial_accel_max, cpu.tangential_accel_min, cpu.tangential_accel_max]:
			accel = maxf(accel, absf(a))
		var speed := maxf(absf(cpu.initial_velocity_min), absf(cpu.initial_velocity_max))
		emitted = emitted.grow(speed * life + 0.5 * accel * life * life)
		# Gravity carries every particle the same way, at most this far by the end of its life.
		emitted = emitted.merge(AABB(emitted.position + cpu.gravity * 0.5 * life * life, emitted.size))
	return box.merge(emitted) if bounded else emitted


## An item's own box, before its node's transform: a mesh's; a sprite's rectangle (_sprite_box);
## one instance's mesh, at the largest scale its transform gives when this runner can read it; one
## particle's draw meshes at the largest scale its emitter gives them. Empty for anything else.
func _item_box(geo: GeometryInstance3D) -> AABB:
	var box := AABB()
	var scale := 1.0
	if geo is MeshInstance3D:
		box = (geo as MeshInstance3D).mesh.get_aabb() if (geo as MeshInstance3D).mesh else AABB()
	elif geo is SpriteBase3D:
		box = _sprite_box(geo)
	elif geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh and (geo as MultiMeshInstance3D).multimesh.mesh:
		var mm := (geo as MultiMeshInstance3D).multimesh
		box = mm.mesh.get_aabb()
		if _readable(mm) and mm.instance_count > 0:
			scale = 0.0
			for i in mm.instance_count:
				var s := mm.get_instance_transform(i).basis.get_scale().abs()
				scale = maxf(scale, maxf(s.x, maxf(s.y, s.z)))
	elif geo is GPUParticles3D:
		var gp := geo as GPUParticles3D
		var first := true
		for p in gp.draw_passes:
			var pass_mesh := gp.get_draw_pass_mesh(p)
			if pass_mesh:
				box = pass_mesh.get_aabb() if first else box.merge(pass_mesh.get_aabb())
				first = false
		var process := gp.process_material as ParticleProcessMaterial
		if process:
			var curve := process.scale_curve
			var top := 1.0
			if curve is CurveTexture:
				top = _curve_top((curve as CurveTexture).curve)
			elif curve is CurveXYZTexture:
				var xyz := curve as CurveXYZTexture
				top = maxf(_curve_top(xyz.curve_x), maxf(_curve_top(xyz.curve_y), _curve_top(xyz.curve_z)))
			scale = maxf(absf(process.scale_min), absf(process.scale_max)) * top
	elif geo is CPUParticles3D and (geo as CPUParticles3D).mesh:
		var cpu := geo as CPUParticles3D
		box = cpu.mesh.get_aabb()
		var top := _curve_top(cpu.scale_amount_curve)
		if cpu.split_scale:
			top = maxf(_curve_top(cpu.scale_curve_x), maxf(_curve_top(cpu.scale_curve_y), _curve_top(cpu.scale_curve_z)))
		scale = maxf(absf(cpu.scale_amount_min), absf(cpu.scale_amount_max)) * top
	return AABB(box.position * scale, box.size * scale)


## The largest value a curve reaches, sampled across its domain, or 1 when there is none.
func _curve_top(curve: Curve) -> float:
	if curve == null:
		return 1.0
	var top := 0.0
	for i in 33:
		top = maxf(top, absf(curve.sample(lerpf(curve.min_domain, curve.max_domain, i / 32.0))))
	return top


## A sprite's rectangle in its own space, in metres, laid on its axis as SpriteBase3D lays it: X
## across along -z and up along y, Y across along x and up along -z, Z across along x and up along y.
## A billboard turns to the camera, so it takes the engine's cube round its origin out to the
## rectangle's furthest edge.
func _sprite_box(sprite: SpriteBase3D) -> AABB:
	var rect := sprite.get_item_rect()
	var r := Rect2(rect.position * sprite.pixel_size, rect.size * sprite.pixel_size)
	if sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		var reach := maxf(maxf(absf(r.position.x), absf(r.end.x)), maxf(absf(r.position.y), absf(r.end.y)))
		return AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	match sprite.axis:
		Vector3.AXIS_X:
			return AABB(Vector3(0.0, r.position.y, -r.end.x), Vector3(0.0, r.size.y, r.size.x))
		Vector3.AXIS_Y:
			return AABB(Vector3(r.position.x, 0.0, -r.end.y), Vector3(r.size.x, 0.0, r.size.y))
	return AABB(Vector3(r.position.x, r.position.y, 0.0), Vector3(r.size.x, r.size.y, 0.0))


## An item's largest size in any direction as it draws (_item_box, scaled as its node is).
func _item_size(geo: GeometryInstance3D, root: Node) -> float:
	var size := _item_box(geo).size * _relative(geo, root).basis.get_scale().abs()
	return maxf(size.x, maxf(size.y, size.z))


## `text` with its comments blanked: from a # (GDScript) or // (shader) outside a string to the end of
## its line. Strings and everything else stay.
static func _code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var quote := ""
		var cut := line.length()
		var i := 0
		while i < line.length():
			var ch := line[i]
			if quote != "":
				if ch == "\\":
					i += 1
				elif ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
			elif ch == "#" or (ch == "/" and i + 1 < line.length() and line[i + 1] == "/"):
				cut = i
				break
			i += 1
		out.append(line.substr(0, cut))
	return "\n".join(out)


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
	check_eq(_code_only("var a := PoolSim.DT  # PoolSim\n## Growth\nvar c := Color(\"#fff\") # x"),
		"var a := PoolSim.DT  \n\nvar c := Color(\"#fff\") ", "comments go, code and strings stay")
	var global_random := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(")
	for path: String in sources:
		var text: String = sources[path]
		# Code only: a comment may name a sim class (S2's Growth is also a plain word) without using it.
		var code := _code_only(text) if path.get_extension() in ["gd", "gdshader"] else text
		for name in banned:
			var word := RegEx.create_from_string("(?<![\\w])%s(?![\\w])" % name.replace("/", "\\/").replace(".", "\\."))
			check(word.search(code) == null, "%s mentions %s" % [path, name])
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
	# The strike lane draws at LANE_PRIORITY, and every world transparent below it (plan section 3).
	var lane := CreatureView.LANE_PRIORITY
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
	for type in ["WorldEnvironment", "Camera3D", "FogVolume", "Light3D", "ReflectionProbe", "VoxelGI", "LightmapGI", "Decal"]:
		check(_nodes(ambience, type).is_empty(), "the ambience has no %s" % type)
	# Decor draws only with what the contract can read (Label3D and CSG shapes are not), and a sprite
	# keeps to the world: a fixed-size one has no size there, one without the depth test draws over
	# the cell.
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		var readable := geo is MeshInstance3D or geo is MultiMeshInstance3D or geo is GPUParticles3D or geo is CPUParticles3D or geo is SpriteBase3D
		check(readable, "%s is a %s, which the contract cannot read: decor draws with meshes, MultiMeshes, particles or sprites" % [geo.name, geo.get_class()])
		if geo is SpriteBase3D:
			check(not (geo as SpriteBase3D).fixed_size, "%s draws at a fixed size on screen" % geo.name)
			check(not (geo as SpriteBase3D).no_depth_test, "%s draws without the depth test, over the cell" % geo.name)
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


func test_foreground_items_are_small() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	# Every item above the plane, whatever draws it: a mesh, a sprite, each instance of a layer, each
	# particle. Instances this runner cannot place count as above it.
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		var h := _heights(geo, ambience)
		if h.known and h.high < PLANE_BAND.y:
			continue
		var size := _item_size(geo, ambience)
		check(size < LARGE_M, "%s is above the swim plane (its top at %.2f m) and its items are %.2f m across: a foreground item stays under %.1f m in any direction, since one faint sheet over the cell veils the middle of the frame" \
			% [geo.name, h.high, size, LARGE_M])
	ambience.get_parent().free()


func test_the_ambience_keeps_to_its_budget() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	var particles := 0
	var large := 0
	var billboards: Array[GeometryInstance3D] = []
	for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
		var items := 1
		if geo is MultiMeshInstance3D and (geo as MultiMeshInstance3D).multimesh:
			var mm := (geo as MultiMeshInstance3D).multimesh
			items = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			particles += items
		elif geo is GPUParticles3D:
			items = (geo as GPUParticles3D).amount
			particles += items
		elif geo is CPUParticles3D:
			items = (geo as CPUParticles3D).amount
			particles += items
		# A large billboard: a mesh or a sprite, or each instance or particle, LARGE_M or more in any
		# direction.
		if _item_size(geo, ambience) >= LARGE_M:
			large += items
			if geo is MeshInstance3D or geo is SpriteBase3D:
				billboards.append(geo)
	check(particles <= MAX_PARTICLES, "%d live particles, at most %d" % [particles, MAX_PARTICLES])
	check(large <= MAX_BILLBOARDS, "%d large billboards, at most %d" % [large, MAX_BILLBOARDS])
	# Transparent billboards stacked over one point of the plan, on a grid over their footprints.
	var stacked := 0
	var flat: Array[Dictionary] = []
	for geo in billboards:
		var see_through := false
		for m in _materials(geo):
			see_through = see_through or _blend_and_fog(m).blend != "opaque"
		if see_through:
			var t := _relative(geo, ambience)
			flat.append({"inverse": t.affine_inverse(), "y": t.origin.y, "box": _item_box(geo), "world": t * _item_box(geo)})
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


## S2 (S2G15, s2-view 6): the ghosts and giants are decor under the same budget. With every slot of
## the layer drawn at once (six near ghosts, three giants and a riser) beside art's own large
## billboards, there are at most MAX_BILLBOARDS.
func test_ghosts_and_ambience_share_the_billboard_budget() -> void:
	var pool := _pool()
	pool._mount_ambience()
	var ambience := pool.get_node_or_null("Ambience")
	var large := 0
	if ambience != null:
		_ready_tree(ambience)
		for geo: GeometryInstance3D in _nodes(ambience, "GeometryInstance3D"):
			if _item_size(geo, ambience) >= LARGE_M:
				var mm := (geo as MultiMeshInstance3D).multimesh if geo is MultiMeshInstance3D else null
				large += (mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count) if mm != null else 1
	var ghosts := _all_ghosts(pool)
	var drawn := ghosts.billboards()
	check_eq(drawn.size(), 10, "every ghost slot draws: six near, three far and the riser")
	for geo: GeometryInstance3D in drawn:
		check(_item_size(geo, ghosts) >= LARGE_M, "%s is a large billboard (%.2f m)" % [geo.name, _item_size(geo, ghosts)])
		large += 1
	check(large <= MAX_BILLBOARDS, "%d large billboards with the ghosts, at most %d" % [large, MAX_BILLBOARDS])
	pool.free()


## S2 (S2G15): the ghosts keep the decor rules. Every one drawn at once keeps out of the plane band
## (the riser at most at its edge), casts no shadow, draws under the strike lane, fades with the fog,
## keeps clear of the food and threat hues and is too faint to lift the fluid.
func test_the_ghosts_keep_the_decor_rules() -> void:
	var pool := _pool()
	var ghosts := _all_ghosts(pool)
	var drawn := ghosts.billboards()
	check(not drawn.is_empty(), "the ghosts draw")
	for geo: GeometryInstance3D in drawn:
		var h := _heights(geo, ghosts)
		check(h.high <= PLANE_BAND.x + 1e-4, "%s keeps under %.1f m (its top at %.2f m)" % [geo.name, PLANE_BAND.x, h.high])
		check_eq(geo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % geo.name)
		for m in _materials(geo):
			check(m.render_priority < CreatureView.LANE_PRIORITY, "%s draws under the lane" % geo.name)
			check(_blend_and_fog(m).fog, "%s keeps the engine's fog" % geo.name)
	_check_hues(drawn)
	_check_pale(drawn, ghosts)
	pool.free()


## A GhostLayer under `pool` on the shipped ladder at size 1 with every slot drawn: the near slots
## and the giants staged in view, and two seconds into a rise of a species no near slot shows, so it
## draws as its own billboard at its height.
func _all_ghosts(pool: Node) -> GhostLayer:
	var camera: PoolCamera = pool.camera
	camera.configure({})
	camera.snap_to(Vector3.ZERO)
	var ghosts := GhostLayer.new()
	ghosts.camera = camera
	pool.add_child(ghosts)
	ghosts.configure(GhostLayer.shipped().data, 1, 7)
	var near := []
	for i in 6:
		near.append({"species": ["elder_rammer", "veil", "warden"][i % 3], "offset": Vector2(-12.0 + 5.0 * i, -6.0 - 3.0 * i)})
	ghosts.stage(near, [{"offset": Vector2(-20.0, -25.0)}, {"offset": Vector2(5.0, -30.0)}, {"offset": Vector2(25.0, -20.0)}])
	ghosts.apply_scale_view(_ghost_view(camera, 0.0))
	ghosts.rise("lurker", Vector2(0.0, -12.0))
	for t in [0.5, 1.0, 1.5, 2.0]:
		ghosts.apply_scale_view(_ghost_view(camera, t))
	return ghosts


static func _ghost_view(camera: PoolCamera, time_s: float) -> Dictionary:
	return {"size": 1, "band": 0, "region": "", "tile": Vector2i.ZERO, "depth_k": 1.0, "size_k": 1.0,
		"focus_am": PackedFloat64Array([camera.focus.x, camera.focus.z]), "tm_to_am": 1.0, "time_s": time_s}


func test_decor_keeps_clear_of_the_food_and_threat_hues() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	_check_hues(_nodes(ambience, "GeometryInstance3D"))
	ambience.get_parent().free()


## S3's veil threads (s3-view 8.2; S3G32 F part): inked, they are exactly the threat colour, since they
## are what stings; neutral, once the cell has outgrown them, they keep HUE_GAP from food and threat.
func test_veil_thread_colours_are_the_threat_ink_or_clear_of_both() -> void:
	var colors := VeilThreadsView.ink_colors()
	var ink: Color = colors.ink
	check_eq(ink.to_html(false), RESERVED.threat.to_html(false), "inked threads are the threat colour")
	var neutral := LookProbe.lab(colors.neutral)
	var chroma := Vector2(neutral.y, neutral.z).length()
	if chroma >= MIN_CHROMA:
		for reserved: String in RESERVED:
			var gap := LookProbe.hue_gap(LookProbe.hue(neutral), LookProbe.hue(LookProbe.lab(RESERVED[reserved])))
			check(gap >= HUE_GAP, "neutral threads %s are %.0f degrees of LAB hue from the %s colour, at least %.0f" % [
				(colors.neutral as Color).to_html(false), gap, reserved, HUE_GAP])
	var threads := VeilThreadsView.new()
	for m: ShaderMaterial in [threads.rig_material(), threads.outline_material()]:
		check(m.get_shader_parameter("ink_color") == ink and m.get_shader_parameter("neutral_color") == colors.neutral,
			"%s draws art's two thread colours" % m.shader.resource_path.get_file())
	threads.free()


## S3's haze of older sizes (s3-view 9.3, V3-14; S3G32 F part) keeps the decor rules at sizes 3 and 4:
## its band, which its material names, lies within (-3.4, -2.6) under the plane band and holds every
## item; it casts no shadow, draws under the lane, fades with the fog, keeps clear of the food and
## threat hues and is too faint to lift the fluid.
func test_older_haze_rows() -> void:
	var session := FakeEvents.endless_session()
	for n in [3, 4]:
		var haze := OlderHaze.new()
		haze.setup(GhostLayer.shipped().data, WorldConfig.load_from().ladder.food_looks, 7)
		haze.set_size(n)
		haze.refresh(session.sim.world, session.sim.motion.position)
		var geo := haze.items()
		check(geo != null and geo.multimesh.instance_count > 0, "size %d: the haze draws" % n)
		if geo == null:
			haze.free()
			continue
		var h := _heights(geo, haze)
		check(h.band and h.low >= OlderHaze.HEIGHT_RANGE.x - 1e-4 and h.high <= OlderHaze.HEIGHT_RANGE.y + 1e-4 and h.high < PLANE_BAND.x,
			"size %d: its band (%.2f, %.2f) within (%.1f, %.1f), under %.1f" % [n, h.low, h.high, OlderHaze.HEIGHT_RANGE.x, OlderHaze.HEIGHT_RANGE.y, PLANE_BAND.x])
		var outside := 0
		for t: Transform3D in geo.transforms:
			if t.origin.y < OlderHaze.HEIGHT_RANGE.x - 1e-4 or t.origin.y > OlderHaze.HEIGHT_RANGE.y + 1e-4:
				outside += 1
		check(outside == 0, "size %d: every item within its band (%d outside)" % [n, outside])
		check_eq(geo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "size %d: no shadow" % n)
		for m in _materials(geo):
			check(m.render_priority < CreatureView.LANE_PRIORITY, "size %d: draws under the lane" % n)
			check(_blend_and_fog(m).fog, "size %d: keeps the engine's fog" % n)
		_check_hues([geo])
		_check_pale([geo], haze)
		haze.free()


## Every colour `geos` draw keeps HUE_GAP from the reserved hues: flat colours one by one, a painting
## by coverage.
func _check_hues(geos: Array) -> void:
	for geo: GeometryInstance3D in geos:
		for m in _materials(geo):
			var named: Array = []
			for color_set: Dictionary in _color_sets(m, geo):
				if color_set.get("unread", false):
					check(false, "%s: this runner cannot read its MultiMesh instance colours, so its colours belong in uniforms" % geo.name)
					continue
				if not color_set.painting:
					# A flat colour, every stop of a ramp however many it has, and every vertex colour
					# counts as it is.
					for c: Color in color_set.colors:
						named.append(["%s %s" % [color_set.what, c.to_html(false)], c])
					continue
				# A painting counts by coverage: a few stray texels near a reserved hue pass, a shape
				# in it does not.
				var total := 0.0
				var near := {}
				for c: Color in color_set.colors:
					total += c.a
					var texel := LookProbe.lab(Color(c.r, c.g, c.b))
					if c.a <= 0.0 or Vector2(texel.y, texel.z).length() < PAINTING_CHROMA:
						continue
					for reserved: String in RESERVED:
						if LookProbe.hue_gap(LookProbe.hue(texel), LookProbe.hue(LookProbe.lab(RESERVED[reserved]))) < HUE_GAP:
							near[reserved] = float(near.get(reserved, 0.0)) + c.a
				for reserved: String in near:
					var share: float = near[reserved] / maxf(total, 1e-6)
					check(share <= PAINTING_SHARE, "%s %s: %.1f%% of its painting (alpha-weighted, C* %.0f or more) lies within %.0f degrees of the %s hue, at most %.0f%%" \
						% [geo.name, color_set.what, share * 100.0, PAINTING_CHROMA, HUE_GAP, reserved, PAINTING_SHARE * 100.0])
			for entry in named:
				var lab := LookProbe.lab(entry[1])
				if Vector2(lab.y, lab.z).length() < MIN_CHROMA:
					continue
				for reserved: String in RESERVED:
					var gap := LookProbe.hue_gap(LookProbe.hue(lab), LookProbe.hue(LookProbe.lab(RESERVED[reserved])))
					check(gap >= HUE_GAP, "%s colour %s is %.0f degrees of LAB hue from the %s colour, at least %.0f" % [geo.name, entry[0], gap, reserved, HUE_GAP])


func test_pale_decor_is_too_faint_to_lift_the_fluid_or_cut_the_lane() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var ambience := _mounted()
	if ambience == null:
		return
	_check_pale(_nodes(ambience, "GeometryInstance3D"), ambience)
	ambience.get_parent().free()


## Everything transparent among `geos` (under `root`) keeps luminance x opacity at most MAX_LUMA_ALPHA,
## and what is under the plane keeps its luminance at most MAX_LUMA_BELOW.
func _check_pale(geos: Array, root: Node) -> void:
	for geo: GeometryInstance3D in geos:
		var below: bool = _heights(geo, root).high < 0.0
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
			for c in _colors(m, geo):
				top = maxf(top, _luma(c))
				top_lit = maxf(top_lit, _luma(c) * (1.0 if opaque else c.a * opacity))
			if not opaque:
				check(top_lit <= MAX_LUMA_ALPHA + 1e-4, "%s: luminance x opacity %.3f, at most %.2f%s" % [geo.name, top_lit, MAX_LUMA_ALPHA, note])
			if below:
				check(top <= MAX_LUMA_BELOW + 1e-4, "%s under the plane: luminance %.3f, at most %.2f" % [geo.name, top, MAX_LUMA_BELOW])


## S1 (the endless sea): a rebase moves every local position by -offset, the camera's focus with
## it. The ambience follows the camera itself, so its layers must look the same relative to the view
## after the pool's rebase as before: the pool moves each layer with the world (a layer wrapped in a
## "box" uniform may land a whole box away, which draws the same), and particles under it must use
## local coordinates or those already in the water would stay behind.
func test_the_ambience_follows_the_camera_across_a_rebase() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var ambience := pool.get_node_or_null("Ambience") as Node3D
	if ambience == null:
		check(false, "the endless pool mounts %s as its child Ambience" % SCENE)
		pool.free()
		return
	FakeEvents.ready_tree(ambience)
	check(ambience.is_in_group(&"camera_relative"), "the ambience root is camera_relative")
	var layers: Array[Node3D] = []
	var before: Array[Vector3] = []
	for child in ambience.get_children():
		if child is Node3D:
			layers.append(child)
			before.append(ambience.transform * (child as Node3D).position - pool.camera.position)
	check(not layers.is_empty(), "the ambience has layers to follow")
	pool.apply_world_event(FakeEvents.rebased(Vector2(32.0, 0.0)))
	for i in layers.size():
		var moved := ambience.transform * layers[i].position - pool.camera.position - before[i]
		var box := PoolScene.wrap_box(layers[i])
		if box != Vector2.ZERO:
			moved.x = moved.x - box.x * roundf(moved.x / box.x)
			moved.z = moved.z - box.y * roundf(moved.z / box.y)
		check(moved.length() <= 1e-3, "%s keeps its place relative to the camera across the rebase (moved %s)" % [layers[i].name, moved])
	for p in _nodes(ambience, "CPUParticles3D") + _nodes(ambience, "GPUParticles3D"):
		check(bool(p.get("local_coords")), "%s keeps its particles in local coordinates, so they ride the rebase" % p.name)
	pool.free()
