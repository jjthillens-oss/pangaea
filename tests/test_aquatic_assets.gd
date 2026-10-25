extends TestCase
## The Aquatic stage's own Blender assets in the game (aquatic-r2, docs/stages/aquatic-plan.md): the spawning nest fits
## its sloping site, sits on the sea floor and leaves the spawn clear, carries six clutches the world shows one per
## generation, and the fin and tail editor stands on its own reef-stone plinth instead of the creature editor's pad.
## The asset files themselves (record, .blend, textures) are checked by tests/test_assets.gd like every asset.

const AquaticWorld := preload("res://game/scenes/aquatic/aquatic_world.gd")
const AquaticEditor := preload("res://game/ui/aquatic_editor.gd")
const SEAFLOOR := "res://assets/export/aquatic_seafloor.glb"
const RECORDS := ["res://assets/records/aquatic_nest.json", "res://assets/records/aquatic_plinth.json"]
## The nest's contract (tools/blender/make_aquatic_world.py, PROPOSED): its footprint, the spawn's clearance, where
## the clutches lie on the dish.
const FOOTPRINT_R := 4.6
const SPAWN_CLEAR_M := 0.8
const CLUTCH_R := [1.0, 2.2]

var rules: Dictionary
var sim: AquaticSim
## The sea floor's triangles round the nest, in world space: [a, b, c].
var _floor: Array = []


func before_each() -> void:
	rules = AquaticLineage.rules()
	sim = AquaticSim.new(rules, 7, AquaticBody.DARTER)


func _nest() -> Node3D:
	var packed := load(AquaticWorld.NEST) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	AquaticWorld.place_nest(node, sim)
	return node


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out


## Transform of `node` relative to `root`, computed without a scene tree.
func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Each mesh's vertices: {name: [local (the scene root's space), world]}.
func _vertices(root: Node3D) -> Dictionary:
	var out := {}
	for mi in _mesh_instances(root):
		var to_root := _relative(mi, root)
		var local := PackedVector3Array()
		var world := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				local.append(to_root * v)
				world.append(root.transform * to_root * v)
		out[String(mi.name)] = [local, world]
	return out


## Loads the sea floor's triangles within `reach` m (in x and z) of `centre`.
func _load_floor(centre: Vector3, reach: float) -> void:
	_floor.clear()
	var root := (load(SEAFLOOR) as PackedScene).instantiate() as Node3D
	for mi in _mesh_instances(root):
		var xf := root.transform * _relative(mi, root)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var a: Vector3 = xf * verts[idx[i]]
				if absf(a.x - centre.x) > reach + 4.0 or absf(a.z - centre.z) > reach + 4.0:
					continue
				_floor.append([a, xf * verts[idx[i + 1]], xf * verts[idx[i + 2]]])
	root.free()


## The drawn sea floor's height under (x, z), or NAN when no loaded triangle covers it.
func _floor_y(x: float, z: float) -> float:
	for t in _floor:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-9:
			continue
		var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
		var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
		var l3 := 1.0 - l1 - l2
		if l1 >= -1e-6 and l2 >= -1e-6 and l3 >= -1e-6:
			return l1 * a.y + l2 * b.y + l3 * c.y
	return NAN


func test_the_nest_fits_its_site_and_leaves_the_spawn_clear() -> void:
	var nest := _nest()
	check(nest != null, "the nest scene loads")
	if nest == null:
		return
	var verts := _vertices(nest)
	for part in ["NestMound", "NestRim", "NestPolyps", "Beacon", "BeaconDetail"]:
		check(verts.has(part), "the nest has its %s" % part)
	var c := sim.nest_pos()
	var widest := 0.0
	var nearest := INF
	for part in verts:
		for p: Vector3 in verts[part][1]:
			widest = maxf(widest, Vector2(p.x - c.x, p.z - c.z).length())
			nearest = minf(nearest, minf(p.distance_to(sim.player.pos), p.distance_to(sim.kin.pos)))
	check(widest <= FOOTPRINT_R + 0.05 and widest <= float(rules.world.nest.radius),
			"the nest stays within its %.1f m footprint, inside the nest's %.0f m radius (%.2f m)" % [FOOTPRINT_R, float(rules.world.nest.radius), widest])
	check(nearest >= SPAWN_CLEAR_M, "nothing of the nest comes within %.1f m of the fish's spawn or its kin (%.2f m)" % [SPAWN_CLEAR_M, nearest])
	var beacon_top := -INF
	for part in ["Beacon", "BeaconDetail"]:     # the pillar, and its polyps and fronds (a child piece)
		for p: Vector3 in verts.get(part, [[], []])[1]:
			beacon_top = maxf(beacon_top, p.y - sim.floor_at(p.x, p.z))
	check(beacon_top >= 4.0 and beacon_top <= 6.2, "the beacon stands 4 to 6 m over the floor, a landmark (%.1f m)" % beacon_top)
	nest.free()


func test_the_nest_sits_on_the_sea_floor() -> void:
	var nest := _nest()
	if nest == null:
		check(false, "the nest scene loads")
		return
	var c := sim.nest_pos()
	_load_floor(c, FOOTPRINT_R + 1.0)
	var verts := _vertices(nest)
	var mound: Array = verts.get("NestMound", [PackedVector3Array(), PackedVector3Array()])
	var foot := 0
	var foot_off := 0.0
	var skirt_gap := -INF
	var dish_clear := INF
	var missing := 0
	for i in (mound[0] as PackedVector3Array).size():
		var lp: Vector3 = mound[0][i]
		var wp: Vector3 = mound[1][i]
		var fy := _floor_y(wp.x, wp.z)
		if is_nan(fy):
			missing += 1
			continue
		var r := Vector2(lp.x, lp.z).length()
		if r >= 4.4 and r <= 4.52 and lp.y > -0.05 and lp.y < 0.15:
			foot += 1
			foot_off = maxf(foot_off, absf(wp.y - fy))
		if lp.y < -0.5:
			skirt_gap = maxf(skirt_gap, wp.y - fy)
		if r <= 2.6 and lp.y > 0.0:
			dish_clear = minf(dish_clear, wp.y - fy)
	check(missing == 0, "the sea floor is drawn under the whole nest (%d vertices off it)" % missing)
	check(foot >= 48 and foot_off <= 0.2, "the mound's foot meets the drawn sea floor all round, within 0.2 m (%d vertices, worst %.3f m)" % [foot, foot_off])
	check(skirt_gap <= -0.25, "its skirt runs at least 0.25 m under the floor, so no gap shows on the slope (highest %.3f m)" % skirt_gap)
	check(dish_clear >= 0.03, "the floor never shows through the dish where the eggs lie (closest %.3f m)" % dish_clear)
	var egg_clear := INF
	for i in 6:
		for wp: Vector3 in verts.get("Clutch_%d" % (i + 1), [[], []])[1]:
			egg_clear = minf(egg_clear, wp.y - _floor_y(wp.x, wp.z))
	check(egg_clear >= 0.05, "every egg lies above the sea floor, on the dish (closest %.3f m)" % egg_clear)
	# The beacon stands upright on the tilted nest, and its base reaches under the mound all round its foot.
	var beacon := nest.get_node_or_null("Beacon") as Node3D
	check(beacon != null, "the nest has its Beacon node")
	if beacon != null:
		var up := (nest.basis * beacon.basis).y.normalized()
		check(up.dot(Vector3.UP) > 0.9999, "the beacon stands upright on the slope (up %s)" % up)
		var foot_at: Vector3 = nest.transform * beacon.position
		var lowest := INF
		for wp: Vector3 in verts.Beacon[1]:
			lowest = minf(lowest, wp.y)
		var under := INF
		for wp: Vector3 in mound[1]:
			if Vector2(wp.x - foot_at.x, wp.z - foot_at.z).length() <= 0.6:
				under = minf(under, wp.y)
		check(under < INF and lowest < under, "the beacon's base reaches under the mound round its foot (%.3f m under)" % (under - lowest))
	var tilt := nest.basis.y.normalized()
	var rise := (sim.floor_at(c.x, c.z + 2.0) - sim.floor_at(c.x, c.z - 2.0)) / 4.0
	check(absf(tilt.angle_to(Vector3(0.0, 1.0, -rise).normalized())) < 1e-4, "the nest is tilted to the slope at its site")
	nest.free()


func test_the_nest_has_six_clutches_shown_one_per_generation() -> void:
	var nest := _nest()
	if nest == null:
		check(false, "the nest scene loads")
		return
	for i in AquaticWorld.NEST_CLUTCHES:
		var clutch := nest.get_node_or_null("Clutch_%d" % (i + 1)) as MeshInstance3D
		check(clutch != null and clutch.mesh != null, "the nest has Clutch_%d" % (i + 1))
		if clutch != null:
			var r := Vector2(clutch.position.x, clutch.position.z).length()
			check(r >= CLUTCH_R[0] - 0.01 and r <= CLUTCH_R[1] + 0.01, "Clutch_%d lies on the dish (r %.2f m)" % [i + 1, r])
			var box := clutch.mesh.get_aabb()
			check(box.size.x <= 1.3 and box.size.z <= 1.3 and box.size.y <= 0.3, "Clutch_%d is a small clutch of eggs (%s)" % [i + 1, box.size])
	var first := nest.get_node_or_null("Clutch_1") as Node3D
	check(first != null and first.position.z < 0.0, "the first clutch lies on the spawn's side, in its first frame")
	check_eq(AquaticWorld.clutches_for(0), 1, "a first generation sees its own clutch")
	check_eq(AquaticWorld.clutches_for(1), 2, "one more for each generation born")
	check_eq(AquaticWorld.clutches_for(5), 6, "six at the sixth")
	check_eq(AquaticWorld.clutches_for(12), 6, "and never more than the nest has")
	nest.free()


func test_the_editor_stands_on_the_aquatic_reef_stone_plinth() -> void:
	check_eq(AquaticEditor.PLINTH, "res://assets/export/aquatic_plinth.glb", "the editor's plinth")
	var packed := load(AquaticEditor.PLINTH) as PackedScene
	check(packed != null, "the plinth loads")
	if packed == null:
		return
	var root := packed.instantiate() as Node3D
	var widest := 0.0
	var highest := -INF
	for part in (_vertices(root) as Dictionary).values():
		for p: Vector3 in part[0]:
			widest = maxf(widest, Vector2(p.x, p.z).length())
			highest = maxf(highest, p.y)
	check(widest >= 0.98 and widest <= 1.001, "the plinth is a unit-radius pad (%.3f)" % widest)
	check(highest <= 0.12, "only the rim's polyps and sponges stand on it, low (%.3f m)" % highest)
	# The top face, probed from above at the centre and round r = 0.7 (decimation leaves the flat face few vertices).
	_floor.clear()
	for mi in _mesh_instances(root):
		var xf := _relative(mi, root)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var a: Vector3 = xf * verts[idx[i]]
				var b: Vector3 = xf * verts[idx[i + 1]]
				var c: Vector3 = xf * verts[idx[i + 2]]
				if a.y > -0.05 and b.y > -0.05 and c.y > -0.05:
					_floor.append([a, b, c])
	var off := 0.0
	var probes := [Vector2.ZERO]
	for k in 8:
		probes.append(Vector2.from_angle(k * TAU / 8.0) * 0.7)
	for q: Vector2 in probes:
		var y := _floor_y(q.x, q.y)
		off = maxf(off, INF if is_nan(y) else absf(y))
	check(off < 0.006, "its top face is the pivot, y = 0, at the centre and round r 0.7 (worst %.4f m)" % off)
	_floor.clear()
	root.free()
	# The aquatic stage no longer draws the creature stage's art, which the creature-world-art job is rebuilding.
	for path in ["res://game/ui/aquatic_editor.gd", "res://game/scenes/aquatic/aquatic_world.gd"]:
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("creature_editor_room") and not text.contains("creature_nest_ring"),
				"%s draws no creature-stage room or nest" % path.get_file())


func test_the_aquatic_assets_are_recorded_with_their_gate_report() -> void:
	for path in RECORDS:
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(record is Dictionary, "%s reads" % path)
		if not record is Dictionary:
			continue
		check_eq(record.get("status"), "PROPOSED", "%s is PROPOSED until the owner reviews the look" % record.get("id"))
		check_eq(record.get("generator_script"), "tools/blender/make_aquatic_world.py", "%s generator" % record.get("id"))
		check(FileAccess.file_exists("res://" + String(record.get("gate_report", ""))), "%s names its gate report" % record.get("id"))
		check(int(record.get("triangles", 1 << 30)) <= int(record.get("triangle_budget", 0)), "%s is within its budget" % record.get("id"))
