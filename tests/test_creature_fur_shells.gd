extends TestCase
## The fur shell API between the creature skin shader (assets/export/shaders/creature_skin.gdshader, art-owned) and
## the rig that chains its shell passes (SpineRig.use_skin_shader and set_skin_param in
## game/scenes/creature/spine_rig.gd): the uniforms the shells need exist with defaults that leave the other
## coverings unchanged, covering 1 chains SpineRig.FUR_SHELLS passes with shell_layer 1..N, other coverings and
## fur_shells 0 chain none, and set_skin_param reaches every pass without touching shell_layer.
## (docs/art/creature_art_contract.md section 2.4a; PROPOSED look, tested here as an interface.)

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const SHADER_PATH := "res://assets/export/shaders/creature_skin.gdshader"


func make_rig():
	var rules := CreatureData.rules()
	var desc = Fixtures.body("s1_quadruped")
	var skin := SkinCpu.build_within(desc, int(rules["gameplay_divisions"]), int(rules["gameplay_triangle_budget"]))
	var rig = SpineRig.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(rig)
	rig.setup(desc, skin, Color.WHITE)
	return rig


## The chain of materials on the body: the skin pass first, then each next_pass.
func passes(rig) -> Array:
	var out := []
	var m := rig.mesh_instance.material_override as ShaderMaterial
	while m != null:
		out.append(m)
		m = m.next_pass as ShaderMaterial
	return out


## A uniform's default as the shader's code declares it ("uniform <type> <name> [: hints] = <value>;"), read from the
## text because the headless renderer does not report shader defaults. Null when there is no default.
func default_of(shader: Shader, uniform_name: String) -> Variant:
	var re := RegEx.create_from_string("uniform\\s+\\w+\\s+%s\\b[^=;]*=\\s*([^;]+);" % uniform_name)
	var found := re.search(shader.code)
	return str_to_var(found.get_string(1).strip_edges()) if found else null


func test_the_shader_declares_the_fur_shell_uniforms() -> void:
	var shader := load(SHADER_PATH) as Shader
	check(shader != null, "the creature skin shader loads")
	var names := []
	for u in shader.get_shader_uniform_list():
		names.append(u["name"])
	# The headless renderer still parses the shader: a parse error leaves it with no uniforms (and a SHADER ERROR).
	check(names.size() > 20, "the shader parses (%d uniforms)" % names.size())
	for name in ["covering", "covering_strength", "shell_layer", "shell_count", "fur_height_m", "fur_shag", "fur_length", "fur_density"]:
		check(name in names, "the shader declares %s" % name)
	# Defaults: covering 0 is the unchanged look, the skin pass is layer 0, the shell height is a few centimetres
	# (the shells only show at the silhouette), and the shaggy locks are on by default but can be turned off.
	check_eq(int(default_of(shader, "covering")), 0, "covering defaults to 0, the unchanged look")
	check_eq(int(default_of(shader, "shell_layer")), 0, "shell_layer defaults to 0, the skin itself")
	var height := float(default_of(shader, "fur_height_m"))
	check(height >= 0.02 and height <= 0.06, "fur_height_m defaults to a few centimetres (%.3f m)" % height)
	var shag := float(default_of(shader, "fur_shag"))
	check(shag > 0.0 and shag <= 1.0, "fur_shag defaults inside 0..1 and on (%.2f)" % shag)


func test_fur_chains_one_pass_per_shell() -> void:
	var rig = make_rig()
	check(rig.use_skin_shader({"covering": 1}), "the skin shader is found")
	var chain := passes(rig)
	check_eq(chain.size(), 1 + SpineRig.FUR_SHELLS, "the skin pass plus FUR_SHELLS shell passes")
	var first = chain[0].get_shader_parameter("shell_layer")
	check_eq(int(first) if first != null else 0, 0, "the first pass is the skin itself")
	for i in range(1, chain.size()):
		var m: ShaderMaterial = chain[i]
		check_eq(int(m.get_shader_parameter("shell_layer")), i, "pass %d is shell layer %d" % [i, i])
		check_eq(int(m.get_shader_parameter("shell_count")), SpineRig.FUR_SHELLS, "pass %d knows the shell count" % i)
		check_eq(int(m.get_shader_parameter("covering")), 1, "pass %d is fur" % i)
		check(m.shader == chain[0].shader, "pass %d uses the same shader" % i)
	rig.free()


func test_shell_count_follows_fur_shells() -> void:
	var rig = make_rig()
	rig.use_skin_shader({"covering": 1, "fur_shells": 3})
	var chain := passes(rig)
	check_eq(chain.size(), 4, "fur_shells 3: the skin pass plus three shells")
	check_eq(int(chain[3].get_shader_parameter("shell_count")), 3, "the outer shell knows there are three")
	rig.use_skin_shader({"covering": 1, "fur_shells": 0})
	check_eq(passes(rig).size(), 1, "fur_shells 0 (the cheap mode) chains no shells")
	rig.free()


func test_other_coverings_chain_no_shells() -> void:
	var rig = make_rig()
	for covering in [0, 2, 3]:
		rig.use_skin_shader({"covering": covering})
		check_eq(passes(rig).size(), 1, "covering %d: the skin pass only" % covering)
	rig.use_skin_shader()
	check_eq(passes(rig).size(), 1, "no params: the skin pass only")
	rig.free()


func test_set_skin_param_reaches_every_pass_but_not_shell_layer() -> void:
	var rig = make_rig()
	rig.use_skin_shader({"covering": 1})
	rig.set_skin_param("fur_length", 0.8)
	rig.set_skin_param("fur_shag", 0.25)
	rig.set_skin_param("shell_layer", 99)
	var chain := passes(rig)
	for i in chain.size():
		var m: ShaderMaterial = chain[i]
		check(is_equal_approx(float(m.get_shader_parameter("fur_length")), 0.8), "pass %d got fur_length" % i)
		check(is_equal_approx(float(m.get_shader_parameter("fur_shag")), 0.25), "pass %d got fur_shag" % i)
		var layer = m.get_shader_parameter("shell_layer")
		check_eq(int(layer) if layer != null else 0, i, "pass %d keeps its shell_layer" % i)
	rig.free()
