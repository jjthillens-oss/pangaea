extends TestCase
## The kit's dressing tints against the look rule (S1, G21's tint half; docs/s1/s1-build-plan.md
## B-26). A landmark's dressing multiplies every surface of its root mesh by its tint in linear space
## (LandmarkLayer's override, docs/s1/s1-content.md 6.5), so every product of a surface colour and a
## tint keeps the rule tests/test_kit_assets.gd holds the untinted colours to: no colour within 25
## degrees of LAB hue of the food glow or the threat pink, unless it is grey (HSV saturation 0.05 or
## less). Growth children, pieces without dressings and the marker cream are checked untinted. The
## albedo textures are greyscale detail (the records' packing), so a surface's hue is its colour's.
##
## No product breaks the rule (AWAITING is empty). Five did under the old amber tint #F3E3C6 (four
## landmarks' surface 1 at 7.6 degrees from food, the shed husk's surface 0 at 18.0 from threat);
## art PR #63 moved every landmark's amber to #EAE5C7, the tint this test proposed. The ledger stays
## so a product that breaks the rule waiting on the owner's call can be recorded, not hidden: the
## test fails if any other product breaks the rule, or if one recorded here is fixed and not struck.

const LookProbe := preload("res://tools/godot/look_probe.gd")
const FOOD_HEX := "CFE86A"
const THREAT_HEX := "D9466B"
const HUE_GAP := 25.0
## At or under this HSV saturation a colour is grey and has no hue to keep away (test_kit_assets).
const GREY_SATURATION := 0.05
## The markers' cream (s1-build-plan section 3, content question 3), kept apart from the UI cream.
const MARKER_CREAM := "F4E8DA"
## A greyscale texture's channels differ by at most this (8-bit rounding of the bake).
const TEXTURE_GREY := 2.0 / 255.0
const TEXTURE_SAMPLES := 16
## The M1 home rocks: white material colour, their look in a coloured texture, plain dressing only;
## they keep tests/test_assets.gd's rock contract, as tests/test_kit_assets.gd says.
const HOME_ROCKS: PackedStringArray = ["rock_a", "rock_b", "rock_c"]
## Root meshes not named after their id: the lair mouth's is "LairMouth" (art PR #26, pinned by
## tests/test_kit_assets.gd's LAIR_NODE).
const ROOT_NODES := {"marker_lair_mouth": "LairMouth"}
## "asset/dressing/node/surface" -> what it measured: the products that break the rule today.
const AWAITING := {}

var kit: PlacementKit


func before_each() -> void:
	if kit == null:
		kit = PlacementKit.load_from()


static func _pascal(id: String) -> String:
	var out := ""
	for part in id.split("_"):
		out += part.capitalize().replace(" ", "")
	return out


## A surface colour under a dressing tint, as LandmarkLayer computes its override.
static func tinted(albedo: Color, tint: Color) -> Color:
	return Color(albedo.srgb_to_linear() * tint.srgb_to_linear()).linear_to_srgb()


## "" when `c` keeps the look rule, else what breaks it.
static func look_problem(c: Color) -> String:
	if c.s <= GREY_SATURATION:
		return ""
	var h := LookProbe.hue(LookProbe.lab(c))
	var food := LookProbe.hue_gap(h, LookProbe.hue(LookProbe.lab(Color(FOOD_HEX))))
	var threat := LookProbe.hue_gap(h, LookProbe.hue(LookProbe.lab(Color(THREAT_HEX))))
	if food < HUE_GAP:
		return "#%s, h %.1f, %.1f from food" % [c.to_html(false).to_upper(), h, food]
	if threat < HUE_GAP:
		return "#%s, h %.1f, %.1f from threat" % [c.to_html(false).to_upper(), h, threat]
	return ""


## Every (node, surface, material) of a piece's meshes, the root mesh's first.
static func _surfaces(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh := (n as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat != null:
					out.append({"node": str(n.name), "surface": s, "material": mat})
	return out


func test_every_albedo_and_tint_product_keeps_clear_of_food_and_threat() -> void:
	var found := {}
	var checked := 0
	for id in WorldConfig._sorted(kit.assets.keys()):
		var a: Dictionary = kit.assets[id]
		var scene: Node3D = (load(a.glb) as PackedScene).instantiate()
		var dressings: Array = a.dressings if not a.dressings.is_empty() else [{"id": "untinted", "tint": "#FFFFFF"}]
		var root := str(ROOT_NODES.get(id, _pascal(id)))
		check(scene.find_child(root, true, false) != null or id.begins_with("rock_"), "%s: its root mesh %s" % [id, root])
		for surface in _surfaces(scene):
			var albedo: Color = surface.material.albedo_color
			var growth := str(surface.node).begins_with("Growth_")
			for d in dressings:
				# Growth meshes are not tinted; check them once.
				if growth and d != dressings[0]:
					continue
				var c := albedo if growth else tinted(albedo, Color(str(d.tint)))
				checked += 1
				var problem := look_problem(c)
				if not problem.is_empty():
					found["%s/%s/%s/%d" % [id, "untinted" if growth else str(d.id), surface.node, surface.surface]] = problem
		scene.free()
	check(checked >= 60, "every surface under every dressing (%d)" % checked)
	var keys := WorldConfig._sorted(found.keys())
	check_eq(keys, WorldConfig._sorted(AWAITING.keys()), "the products that break the look rule: %s" % [found])
	for k in keys:
		if AWAITING.has(k):
			check_eq(found[k], AWAITING[k], "%s measures as recorded" % k)
	print("test-kit-tints: %d products checked; awaiting the owner's call: %s" % [checked, found])


func test_the_marker_cream_keeps_clear_of_food_and_threat() -> void:
	check_eq(look_problem(Color(MARKER_CREAM)), "", "the marker cream #%s" % MARKER_CREAM)
	for id in ["marker_checkpoint_column", "marker_origin_arrow"]:
		var scene: Node3D = (load(kit.assets[id].glb) as PackedScene).instantiate()
		for surface in _surfaces(scene):
			check_eq(look_problem(surface.material.albedo_color), "", "%s %s surface %d" % [id, surface.node, surface.surface])
		scene.free()


## The products above read hue from the material colour alone; that holds while every albedo texture
## is grey detail. A tinted texture would carry a hue of its own, and this fails.
func test_the_albedo_textures_are_grey_detail() -> void:
	var seen := {}
	for id in WorldConfig._sorted(kit.assets.keys()):
		if HOME_ROCKS.has(id):
			continue
		var scene: Node3D = (load(kit.assets[id].glb) as PackedScene).instantiate()
		for surface in _surfaces(scene):
			var tex: Texture2D = surface.material.albedo_texture
			if tex == null or seen.has(tex.resource_path):
				continue
			seen[tex.resource_path] = true
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			var worst := 0.0
			for j in TEXTURE_SAMPLES:
				for i in TEXTURE_SAMPLES:
					var c := img.get_pixel((i * img.get_width()) / TEXTURE_SAMPLES, (j * img.get_height()) / TEXTURE_SAMPLES)
					worst = maxf(worst, maxf(absf(c.r - c.g), absf(c.g - c.b)))
			check(worst <= TEXTURE_GREY, "%s: %s is grey (channels differ by %.3f)" % [id, tex.resource_path.get_file(), worst])
		scene.free()
	check(seen.size() >= 15, "every piece's albedo texture (%d)" % seen.size())
