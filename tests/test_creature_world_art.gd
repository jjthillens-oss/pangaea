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
##   hue from the food green (114.4) and the threat pink (11.1) once its chroma reaches 8.

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
