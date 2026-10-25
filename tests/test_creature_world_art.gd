extends TestCase
## Contract tests for the creature stage's world art (tools/blender/make_creature_world.py, PROPOSED look;
## docs/art/creature_world_dressing.md). They read the exported GLBs, their records and their textures; no scene
## tree. The rules are the ones the game and the sim rely on without code of their own:
## - the field: walkable inside the walls at +-80 m (relief under 0.12 m); anything that is not the ground itself
##   (dressing) keeps out of the nest's 8 m and stays low (walk-through) inside the walls, because the sim has no
##   obstacles; the outer hills start outside the walls and rise high enough to make the horizon land;
## - the nest ring: a clear flat inside to 5.3 m (the nest is 6 m and creatures stand in it), resting on the ground;
## - food: every Bush*, Fruit* and MeatChunk* mesh (the world draws Bush, Fruit and MeatChunk; variants sit beside
##   them) stays within its pickup radius of the pivot and does not sink under the ground;
## - the editor room: the pad's top face at y 0 and radius 1 (the editor scales it to the body); any wall stands
##   at 7.5 units or more, outside the camera at its farthest;
## - colour: every non-food albedo (the ground, the nest, the bush's leaves, the room) keeps 25 degrees of CIELAB
##   hue from the food green (114.4) and the threat pink (11.1) once its chroma reaches 8;
## - the flora and rock kit (tools/blender/creature_flora.py): the cover pieces (grass, fern, flowers, pebbles)
##   stand under 0.45 m so they may go anywhere inside the walls; the cards draw with the shared cut-out
##   M_MeadowCards.tres (a StandardMaterial3D, so the field can merge them beside its own shader), two sheets a
##   card with up-leaning normals so both sides light like the ground; the boulders are
##   obstacle-sized and sink into the ground, so they belong outside the walls; and texel by texel (their textures
##   mix stone and moss, or leaf and petal, so a mean alone hides a clashing edge) no more than 1% of the kit's
##   chromatic texels sit within 25 degrees of the food or threat hue, while each texture's mean (what a far mip
##   shows) keeps the gap too.

const FIELD := "res://assets/export/creature_field_ground.glb"
const NEST := "res://assets/export/creature_nest_ring.glb"
const BUSH := "res://assets/export/creature_fruit_bush.glb"
const MEAT := "res://assets/export/creature_meat_chunk.glb"
const ROOM := "res://assets/export/creature_editor_room.glb"
const FIELD_RECORD := "res://assets/records/creature_field_ground.json"
const WALL_M := 80.0
const RELIEF_M := 0.12
## The field GLB's ground meshes; every other mesh in it is dressing.
const GROUND_NODES := ["CreatureField", "CreatureFieldHills"]
const HILLS_NODE := "CreatureFieldHills"
const DRESSING_CLEAR_R := 8.0     # the nest (6 m) plus its bare clearing
const LOW_INSIDE_M := 79.5        # inside this, dressing is walk-through cover
const LOW_MAX_M := 0.45           # how tall walk-through cover may stand above the ground's relief
const OBSTACLE_MIN_M := 80.5      # anything taller stands outside the walls
const HORIZON_MIN_M := 3.0        # the hills rise at least this high, so the horizon is land
const NEST_CLEAR_M := 5.3
const NEST_FLOOR_MAX := 0.02
const BUSH_REACH_M := 0.6         # FRUIT_RADIUS_M 0.5 plus a little leaf
const MEAT_REACH_M := 0.36        # MEAT_RADIUS_M 0.3 plus a little
const SINK_MAX := 0.004           # as cp._check_pivot allows a flattened underside
const PAD_R := 1.0
const WALL_INNER_MIN := 7.5
const FOOD_GREEN_H := 114.4
const THREAT_PINK_H := 11.1
const HUE_GAP := 25.0
const CHROMA_MIN := 8.0
const KIT_COVER := {"creature_grass_tuft": "GrassTuft", "creature_fern_clump": "FernClump",
	"creature_flower_clump": "FlowerClump", "creature_pebble_cluster": "PebbleCluster"}
const KIT_CARDS := ["creature_grass_tuft", "creature_fern_clump", "creature_flower_clump"]
const KIT_BOULDERS := {"creature_boulder_a": 1.0, "creature_boulder_b": 1.8, "creature_boulder_c": 3.0}
const MEADOW_TRES := "res://assets/export/M_MeadowCards.tres"
const MEADOW_ATLAS := "res://assets/export/creature_flora/T_MeadowCards.png"
const COVER_REACH_M := 0.6        # a cover piece's footprint radius
const COVER_SINK_M := 0.05        # card bottoms sink a little, so roots meet the ground on gentle relief
const CLASH_MAX := 0.01           # the share of a kit texture's chromatic texels allowed near a reserved hue


func _load(path: String) -> Node3D:
	var packed: PackedScene = load(path)
	check(packed != null, "%s loads" % path)
	return packed.instantiate() if packed else null


## Transform of `node` relative to `root`, computed without a scene tree.
func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _mesh_instances(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
		stack.append_array(n.get_children())
	return out


## The node's vertices in the root's space (Godot: +Y up).
func _vertices(mi: MeshInstance3D, root: Node3D) -> PackedVector3Array:
	var t := _relative(mi, root)
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(t * v)
	return out


func _named(root: Node3D, node_name: String) -> MeshInstance3D:
	for mi in _mesh_instances(root):
		if mi.name == node_name:
			return mi
	return null


func test_the_field_is_walkable_inside_the_walls_and_its_record_says_so() -> void:
	var root := _load(FIELD)
	var field := _named(root, "CreatureField")
	check(field != null, "the field GLB has the CreatureField mesh")
	if field == null:
		root.free()
		return
	var highest := 0.0
	for v in _vertices(field, root):
		if maxf(absf(v.x), absf(v.z)) <= WALL_M - 1.0:
			highest = maxf(highest, absf(v.y))
	check(highest <= RELIEF_M + 0.002, "relief inside the walls stays under %.2f m (%.3f)" % [RELIEF_M, highest])
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIELD_RECORD))
	var walkable: Dictionary = record.get("walkable", {})
	check_near(float(walkable.get("wall_m", 0.0)), WALL_M, 0.001, "the record's wall")
	check_near(float(walkable.get("relief_max_m", 0.0)), RELIEF_M, 0.001, "the record's relief")
	root.free()


func test_the_outer_hills_stand_outside_the_walls_and_make_the_horizon_land() -> void:
	var root := _load(FIELD)
	var hills := _named(root, HILLS_NODE)
	check(hills != null, "the field GLB has the %s mesh" % HILLS_NODE)
	if hills == null:
		root.free()
		return
	var nearest := INF
	var top := -INF
	var reach := 0.0
	for v in _vertices(hills, root):
		var d := maxf(absf(v.x), absf(v.z))
		nearest = minf(nearest, d)
		reach = maxf(reach, d)
		top = maxf(top, v.y)
	check(nearest >= OBSTACLE_MIN_M, "the hills start outside the walls (nearest %.1f m)" % nearest)
	check(top >= HORIZON_MIN_M, "the hills rise to %.1f m or more (%.2f)" % [HORIZON_MIN_M, top])
	check(reach >= 150.0, "the hills reach 150 m or more (%.0f)" % reach)
	check(hills.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the hills cast no shadow (the import option)")
	root.free()


func test_field_dressing_keeps_out_of_the_nest_and_is_walk_through_inside_the_walls() -> void:
	var root := _load(FIELD)
	var dressing := 0
	for mi in _mesh_instances(root):
		if String(mi.name) in GROUND_NODES:
			continue
		dressing += 1
		var in_clearing := 0
		var too_tall := 0
		for v in _vertices(mi, root):
			if Vector2(v.x, v.z).length() < DRESSING_CLEAR_R:
				in_clearing += 1
			if maxf(absf(v.x), absf(v.z)) < OBSTACLE_MIN_M and v.y > LOW_MAX_M + RELIEF_M:
				too_tall += 1
		check(in_clearing == 0, "%s keeps out of the nest's %.0f m (%d vertices inside)" % [mi.name, DRESSING_CLEAR_R, in_clearing])
		check(too_tall == 0, "%s stands under %.2f m inside +-%.1f m: rocks and trees stay outside the walls until the sim has obstacles (%d vertices)" % [mi.name, LOW_MAX_M, OBSTACLE_MIN_M, too_tall])
	print("    field dressing meshes: %d" % dressing)
	root.free()


func test_the_nest_ring_is_clear_inside_and_rests_on_the_ground() -> void:
	var root := _load(NEST)
	var inside_high := -INF
	var lowest := INF
	for mi in _mesh_instances(root):
		for v in _vertices(mi, root):
			lowest = minf(lowest, v.y)
			if Vector2(v.x, v.z).length() < NEST_CLEAR_M:
				inside_high = maxf(inside_high, v.y)
	check(inside_high <= NEST_FLOOR_MAX, "nothing stands inside %.1f m (highest %.3f m)" % [NEST_CLEAR_M, inside_high])
	check(lowest >= -0.06 and lowest <= NEST_FLOOR_MAX, "the ring rests on the ground (lowest %.3f m)" % lowest)
	root.free()


## Every mesh whose name starts with one of `prefixes` stays within `reach` of the pivot and above the ground.
func _check_food(path: String, required: Array, prefixes: Array, reach: float) -> void:
	var root := _load(path)
	for node_name in required:
		check(_named(root, node_name) != null, "%s has the %s mesh the world draws" % [path.get_file(), node_name])
	var seen := 0
	for mi in _mesh_instances(root):
		var matched := false
		for p in prefixes:
			matched = matched or String(mi.name).begins_with(p)
		if not matched:
			continue
		seen += 1
		var far := 0.0
		var lowest := INF
		for v in _vertices(mi, root):
			far = maxf(far, Vector2(v.x, v.z).length())
			lowest = minf(lowest, v.y)
		check(far <= reach, "%s stays within %.2f m of the pivot (%.3f)" % [mi.name, reach, far])
		check(lowest >= -SINK_MAX, "%s does not sink under the ground (%.4f)" % [mi.name, lowest])
	check(seen >= required.size(), "%s: %d food meshes checked" % [path.get_file(), seen])
	root.free()


func test_bush_and_fruit_meshes_stay_inside_the_fruit_radius() -> void:
	_check_food(BUSH, ["Bush", "Fruit"], ["Bush", "Fruit"], BUSH_REACH_M)


func test_meat_meshes_stay_inside_the_meat_radius() -> void:
	_check_food(MEAT, ["MeatChunk"], ["MeatChunk"], MEAT_REACH_M)


func test_the_editor_pad_keeps_its_top_face_and_radius_and_walls_stand_clear() -> void:
	var root := _load(ROOM)
	var pad := _named(root, "CreatureEditorRoom")
	check(pad != null, "the room GLB has the CreatureEditorRoom pad")
	if pad == null:
		root.free()
		return
	var radius := 0.0
	var centre_top := -INF
	for v in _vertices(pad, root):
		var r := Vector2(v.x, v.z).length()
		radius = maxf(radius, r)
		if r < 0.25:
			centre_top = maxf(centre_top, v.y)
	check_near(radius, PAD_R, 0.005, "the pad's radius")
	check(absf(centre_top) <= 0.002, "the pad's top face is at y 0 round the pivot (%.4f)" % centre_top)
	for mi in _mesh_instances(root):
		if not ("Wall" in String(mi.name)):
			continue
		var inner := INF
		for v in _vertices(mi, root):
			inner = minf(inner, Vector2(v.x, v.z).length())
		check(inner >= WALL_INNER_MIN, "%s stands %.1f units or more from the pad's centre (%.2f)" % [mi.name, WALL_INNER_MIN, inner])
	root.free()


# --- Colour ---------------------------------------------------------------------------------------------------

static func _to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## CIE L, C, h (D65) of a linear RGB colour.
static func lch(lin: Vector3) -> Vector3:
	var x := (0.4124564 * lin.x + 0.3575761 * lin.y + 0.1804375 * lin.z) / 0.95047
	var y := 0.2126729 * lin.x + 0.7151522 * lin.y + 0.0721750 * lin.z
	var z := (0.0193339 * lin.x + 0.1191920 * lin.y + 0.9503041 * lin.z) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else t / 0.128418 + 4.0 / 29.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	var a := 500.0 * (fx - fy)
	var b := 200.0 * (fy - fz)
	return Vector3(116.0 * fy - 16.0, sqrt(a * a + b * b), fposmod(rad_to_deg(atan2(b, a)), 360.0))


static func hue_gap(h: float, ref: float) -> float:
	var d := absf(h - ref)
	return minf(d, 360.0 - d)


## The mean linear colour of an image (a grid of samples; texels with alpha under 0.5 are cut away and skipped).
func _mean_linear(texture: Texture2D) -> Vector3:
	var img := Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path))
	check(img != null and not img.is_empty(), "%s reads" % texture.resource_path)
	if img == null or img.is_empty():
		return Vector3.ONE
	var sum := Vector3.ZERO
	var count := 0
	var step := maxi(1, img.get_width() / 128)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			sum += Vector3(_to_linear(c.r), _to_linear(c.g), _to_linear(c.b))
			count += 1
	return sum / maxi(1, count)


func _check_hue(what: String, lin: Vector3) -> void:
	var c := lch(lin)
	print("    %s: L %.1f C %.1f h %.1f" % [what, c.x, c.y, c.z])
	if c.y < CHROMA_MIN:
		return
	check(hue_gap(c.z, FOOD_GREEN_H) >= HUE_GAP and hue_gap(c.z, THREAT_PINK_H) >= HUE_GAP,
		"%s keeps %.0f degrees of hue from the food green and the threat pink (L %.1f C %.1f h %.1f)" % [what, HUE_GAP, c.x, c.y, c.z])


## The mean albedo of each surface of `path`'s meshes, except the food ones (names starting with one of `skip`): a
## standard material's albedo
## texture times its colour; the field's ShaderMaterial's turf and earth tiles, and the turf under its dry and lush
## variations.
func _check_albedos(path: String, skip: Array) -> int:
	var root := _load(path)
	var checked := 0
	for mi in _mesh_instances(root):
		var food := false
		for p in skip:
			food = food or String(mi.name).begins_with(p)
		if food:
			continue
		for s in mi.mesh.get_surface_count():
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var what := "%s %s surface %d" % [path.get_file(), mi.name, s]
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var tint := Vector3(_to_linear(sm.albedo_color.r), _to_linear(sm.albedo_color.g), _to_linear(sm.albedo_color.b))
				var tex := _mean_linear(sm.albedo_texture) if sm.albedo_texture != null else Vector3.ONE
				_check_hue(what, tex * tint)
				checked += 1
			elif mat is ShaderMaterial:
				var shm := mat as ShaderMaterial
				var turf := Vector3.ONE
				for param in ["turf_albedo", "earth_albedo"]:
					var t: Texture2D = shm.get_shader_parameter(param)
					check(t != null, "%s sets %s" % [what, param])
					if t != null:
						var mean := _mean_linear(t)
						_check_hue("%s %s" % [what, param], mean)
						if param == "turf_albedo":
							turf = mean
						checked += 1
				var dry: Variant = shm.get_shader_parameter("dry_color")
				var lush: Variant = shm.get_shader_parameter("lush_tint")
				check(dry is Color and lush is Vector3, "%s sets dry_color and lush_tint" % what)
				if dry is Color and lush is Vector3:
					var d := dry as Color
					var dry_lin := Vector3(_to_linear(d.r), _to_linear(d.g), _to_linear(d.b))
					for k in 5:
						var amount := (k + 1) / 5.0
						_check_hue("%s turf %.0f%% dry" % [what, amount * 100.0], turf.lerp(dry_lin, amount))
					_check_hue("%s turf lush" % what, turf * (lush as Vector3))
					checked += 1
	root.free()
	return checked


func test_ground_flora_nest_and_room_colours_keep_the_hue_gaps() -> void:
	check(hue_gap(lch(Vector3(_to_linear(0x42 / 255.0), _to_linear(0x5B / 255.0), _to_linear(0x44 / 255.0))).z, 145.0) < 1.5,
		"the LCh conversion reads rev 1's turf #425B44 as hue 145")
	var n := 0
	n += _check_albedos(FIELD, [])
	n += _check_albedos(NEST, [])
	n += _check_albedos(BUSH, ["Fruit"])
	n += _check_albedos(ROOM, [])
	check(n >= 6, "albedos checked (%d)" % n)


# --- The flora and rock kit ----------------------------------------------------------------------------------

func _glb(id: String) -> String:
	return "res://assets/export/%s.glb" % id


func test_kit_cover_is_low_walk_through_and_on_the_ground() -> void:
	for id: String in KIT_COVER:
		var root := _load(_glb(id))
		if root == null:
			continue
		check(_named(root, KIT_COVER[id]) != null, "%s has its %s mesh" % [id, KIT_COVER[id]])
		var top := -INF
		var lowest := INF
		var reach := 0.0
		for mi in _mesh_instances(root):
			for v in _vertices(mi, root):
				top = maxf(top, v.y)
				lowest = minf(lowest, v.y)
				reach = maxf(reach, Vector2(v.x, v.z).length())
		check(top <= LOW_MAX_M, "%s stands under %.2f m, walk-through cover (%.3f)" % [id, LOW_MAX_M, top])
		check(lowest >= -COVER_SINK_M and lowest <= 0.0, "%s sits on the ground, sunk no more than %.2f m (%.3f)" % [id, COVER_SINK_M, lowest])
		check(reach <= COVER_REACH_M, "%s keeps within %.1f m of its pivot (%.3f)" % [id, COVER_REACH_M, reach])
		root.free()


func test_meadow_cards_draw_with_the_shared_cut_out_material() -> void:
	var shared: Material = load(MEADOW_TRES)
	check(shared is StandardMaterial3D, "M_MeadowCards.tres is a StandardMaterial3D (the field may merge the cards beside its shader)")
	if not (shared is StandardMaterial3D):
		return
	var sm := shared as StandardMaterial3D
	check(sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(sm.alpha_scissor_threshold, 0.5),
		"the cards are cut out at 0.5 (alpha scissor, %d; not alpha blending)" % sm.transparency)
	check(sm.cull_mode == BaseMaterial3D.CULL_BACK, "back faces are culled (each card is two sheets, one per side)")
	check(sm.albedo_texture != null and sm.albedo_texture.resource_path == MEADOW_ATLAS, "the cards read the authored atlas")
	check(sm.vertex_color_use_as_albedo and sm.vertex_color_is_srgb, "the cards take their COLOR_0 jitter as sRGB")
	for id: String in KIT_CARDS:
		var root := _load(_glb(id))
		if root == null:
			continue
		for mi in _mesh_instances(root):
			check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s casts no shadow (cover)" % [id, mi.name])
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				check(mat != null and mat.resource_path == MEADOW_TRES, "%s %s surface %d draws with M_MeadowCards.tres" % [id, mi.name, s])
				var arrays := mi.mesh.surface_get_arrays(s)
				var colours: Variant = arrays[Mesh.ARRAY_COLOR]
				check(colours is PackedColorArray and (colours as PackedColorArray).size() > 0, "%s %s carries its jitter colours" % [id, mi.name])
				# Two sheets back to back: every triangle has a twin facing the other way within 2 mm of it, and each
				# sheet's normal leans up, so both sides light like the ground.
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var centres: Array[Vector3] = []
				var facing: Array[Vector3] = []
				for t in range(0, index.size(), 3):
					var a := verts[index[t]]
					var b := verts[index[t + 1]]
					var c := verts[index[t + 2]]
					centres.append((a + b + c) / 3.0)
					facing.append((b - a).cross(c - a).normalized())
				var lonely := 0
				for i in centres.size():
					var twin := false
					for j in centres.size():
						if j != i and centres[i].distance_to(centres[j]) < 0.002 and facing[i].dot(facing[j]) < -0.99:
							twin = true
							break
					lonely += 0 if twin else 1
				check(lonely == 0, "%s %s: every card is two sheets back to back (%d triangles without a twin)" % [id, mi.name, lonely])
				var down := 0
				for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
					if n.y <= 0.0:
						down += 1
				check(down == 0, "%s %s: every card normal leans up (%d do not)" % [id, mi.name, down])
		root.free()


func test_boulders_are_obstacle_sized_and_sink_into_the_ground() -> void:
	for id: String in KIT_BOULDERS:
		var root := _load(_glb(id))
		if root == null:
			continue
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for mi in _mesh_instances(root):
			for v in _vertices(mi, root):
				lo = lo.min(v)
				hi = hi.max(v)
		var size: float = KIT_BOULDERS[id]
		var longest := maxf(hi.x - lo.x, hi.z - lo.z)
		check(absf(longest - size) <= 0.15 * size, "%s is about %.1f m across (%.2f)" % [id, size, longest])
		check(hi.y > LOW_MAX_M, "%s stands taller than walk-through cover (%.2f), so it belongs outside the walls" % [id, hi.y])
		check(lo.y < -0.03, "%s sinks its base under the ground, so it never hovers on the berm (%.3f)" % [id, lo.y])
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/records/%s.json" % id))
		check(String(record.get("placement", "")).contains("OUTSIDE the walls"), "%s's record keeps it outside the walls" % id)
		var deps: Array = record.get("dependencies", [])
		check(deps.size() == 1 and String((deps[0] as Dictionary).get("source_url", "")).ends_with("rock_boulder_dry"), "%s logs the CC0 rock scan it uses" % id)
		root.free()


## The share of `img`'s opaque, chromatic texels (every `step`-th) whose hue, times `tint` (linear), lies within the
## hue gap of the food green or the threat pink.
func _clash_share(img: Image, tint: Vector3, step: int) -> float:
	var chromatic := 0
	var clash := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lch_c := lch(Vector3(_to_linear(c.r) * tint.x, _to_linear(c.g) * tint.y, _to_linear(c.b) * tint.z))
			if lch_c.y < CHROMA_MIN:
				continue
			chromatic += 1
			if hue_gap(lch_c.z, FOOD_GREEN_H) < HUE_GAP or hue_gap(lch_c.z, THREAT_PINK_H) < HUE_GAP:
				clash += 1
	return float(clash) / maxf(1.0, chromatic)


func test_kit_colours_keep_the_hue_gaps_texel_by_texel() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(MEADOW_ATLAS))
	check(atlas != null and not atlas.is_empty(), "the meadow atlas reads")
	if atlas != null and not atlas.is_empty():
		var share := _clash_share(atlas, Vector3.ONE, 2)
		print("    meadow atlas: %.2f%% of chromatic texels near a reserved hue" % (share * 100.0))
		check(share <= CLASH_MAX, "the meadow atlas keeps the hue gaps (%.2f%% of chromatic texels clash)" % (share * 100.0))
		_check_hue("the meadow atlas's mean (a far mip)", _mean_linear(load(MEADOW_ATLAS)))
	var rocks := ["creature_pebble_cluster"]
	rocks.append_array(KIT_BOULDERS.keys())
	for id: String in rocks:
		var root := _load(_glb(id))
		if root == null:
			continue
		for mi in _mesh_instances(root):
			for s in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(s) as StandardMaterial3D
				check(sm != null and sm.albedo_texture != null, "%s %s surface %d has a baked albedo" % [id, mi.name, s])
				if sm == null or sm.albedo_texture == null:
					continue
				var tint := Vector3(_to_linear(sm.albedo_color.r), _to_linear(sm.albedo_color.g), _to_linear(sm.albedo_color.b))
				var img := Image.load_from_file(ProjectSettings.globalize_path(sm.albedo_texture.resource_path))
				check(img != null and not img.is_empty(), "%s reads" % sm.albedo_texture.resource_path)
				if img == null or img.is_empty():
					continue
				var share := _clash_share(img, tint, 4)
				print("    %s %s: %.2f%% of chromatic texels near a reserved hue" % [id, mi.name, share * 100.0])
				check(share <= CLASH_MAX, "%s %s keeps the hue gaps texel by texel (%.2f%% clash)" % [id, mi.name, share * 100.0])
				# And as a whole: far off, the mips blend stone and moss into their mean.
				_check_hue("%s %s mean (a far mip)" % [id, mi.name], _mean_linear(sm.albedo_texture) * tint)
		root.free()
