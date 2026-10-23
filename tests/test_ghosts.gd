extends TestCase
## The ghosts of the sizes to come and the giants (S2G14 F, S2G15, S2G29; s2-view 6 and 10.2):
## ghost_ladder.json loads and refuses bad data by name, agrees with the species catalog and the
## paintings, puts each near ghost where it draws at least 1.4 cells and each giant inside the D-53
## band at every zoom, never enters the swim plane's band (a riser at most at its edge), keeps the
## pale-decor numbers, reads nothing of the simulation, re-expresses at a growth without a jump,
## rises toward a newly live species' site, makes the giants' first pass once per lineage, and runs
## in pool mode at size 1. Most cases drive a GhostLayer alone beside a PoolCamera with views built
## by hand (as PoolScene.scale_view builds them); the rise and the growth ride T2's real growth tick.
## The tests use their own settings file and never save it.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const Frames := preload("res://tests/scene_frames.gd")
const Contract := preload("res://tests/test_ambience_contract.gd")
const LookProbe := preload("res://tools/godot/look_probe.gd")
const SETTINGS_PATH := "user://test_ghosts/settings.cfg"
const SEED := 7
## Lineages for test_rise: the ghosts hash from the lineage id, so each gives other slots and riser.
const RISE_LINEAGES: PackedStringArray = ["lineage_7a1c0e5d93b2f468", "lineage_e0ba3bffbce8bd8d"]
const NEAR_AHEAD := {1: ["lurker", "elder_rammer", "veil", "warden"], 2: ["veil", "warden", "deep_lurker", "elder_warden"]}
## s2-view 0.9's table: (species, size) -> [depth, base draw scale].
const DEPTHS := {["lurker", 1]: [-11.2, 1.0], ["elder_rammer", 1]: [-8.0, 1.065], ["veil", 1]: [-14.0, 1.0],
	["warden", 1]: [-14.0, 1.0], ["veil", 2]: [-13.1, 1.0], ["warden", 2]: [-8.0, 1.023],
	["deep_lurker", 2]: [-14.0, 1.0], ["elder_warden", 2]: [-14.0, 1.0]}
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}


func before_each() -> void:
	SettingsService.set_shared(SettingsService.new(SETTINGS_PATH))


func after_each() -> void:
	SettingsService.set_shared(null)


static func _ladder() -> Dictionary:
	return GhostLayer.shipped().data


## A PoolCamera at `zoom` over the origin and a GhostLayer on the shipped ladder at `size` under one
## parent, as the pool holds them, outside the tree. Free it with rig.free().
func _rig(size: int, zoom := 14.0) -> Node3D:
	var rig := Node3D.new()
	var camera := PoolCamera.new()
	camera.fov = 45.0
	camera.configure({"distance": zoom})
	camera.snap_to(Vector3.ZERO)
	camera.name = "Camera"
	rig.add_child(camera)
	var layer := GhostLayer.new()
	layer.name = "Ghosts"
	layer.camera = camera
	rig.add_child(layer)
	layer.configure(_ladder(), size, SEED)
	return rig


## The scale view PoolScene.scale_view gives for a world whose origin is (0, 0) am: the focus's
## absolute point is its local one times tm_to_am.
static func _view(camera: PoolCamera, size: int, time_s: float, k := 1.0) -> Dictionary:
	var tm := WorldConfig.tm_to_am(size)
	return {"size": size, "band": 0, "region": "", "tile": Vector2i.ZERO, "depth_k": k, "size_k": k,
		"focus_am": PackedFloat64Array([camera.focus.x * tm, camera.focus.z * tm]), "tm_to_am": tm, "time_s": time_s}


static func _rect_of(layer: GhostLayer, node: Node3D) -> Array:
	var species := layer.species_of(node)
	if species != "":
		return _ladder().species[species].body_rect
	var far: Dictionary = _ladder().far
	return far.body_rects[str(far.textures[int(str(node.name).trim_prefix("Far"))]).get_file().get_basename()]


## A billboard's body on screen (px): its centre, its width across its middle and its height.
static func _body_px(camera: Camera3D, node: Node3D, rect: Array) -> Dictionary:
	var side := node.basis.get_scale().x
	var p := node.position
	var at := func(u: float, v: float) -> Vector2: return Frames.project(camera, p + Vector3((u - 0.5) * side, 0.0, (v - 0.5) * side))
	var mid_v := (float(rect[1]) + float(rect[3])) * 0.5
	var ys: Array[float] = []
	for corner in [[rect[0], rect[1]], [rect[2], rect[1]], [rect[0], rect[3]], [rect[2], rect[3]]]:
		ys.append((at.call(float(corner[0]), float(corner[1])) as Vector2).y)
	return {"centre": Frames.project(camera, p), "width": (at.call(float(rect[0]), mid_v) as Vector2).distance_to(at.call(float(rect[2]), mid_v)),
		"height": ys.max() - ys.min(), "side_px": Frames.project(camera, p).distance_to(Frames.project(camera, p + Vector3(side * 0.5, 0.0, 0.0)))}


## The cell's drawn diameter (px): a 0.5 tm radius at the focus, across.
static func _cell_px(camera: PoolCamera) -> float:
	return Frames.project(camera, camera.focus - Vector3(0.5, 0.0, 0.0)).distance_to(Frames.project(camera, camera.focus + Vector3(0.5, 0.0, 0.0)))


static func _on_screen(px: Vector2) -> bool:
	return px.x >= 0.0 and px.x <= Frames.SCREEN.x and px.y >= 0.0 and px.y <= Frames.SCREEN.y


func test_ladder_loads_and_refuses_bad_data() -> void:
	var shipped := GhostLayer.load_ladder()
	check_eq(shipped.problems, PackedStringArray(), "the shipped ladder loads with no problems")
	check(GhostLayer.load_ladder("res://tests/no_such_ladder.json").problems.size() == 1, "a missing file is a problem")
	var cases := [
		["ghost_ladder.colour: unknown key", func(d: Dictionary) -> void: d["colour"] = "#D9466B"],
		["ghost_ladder.species.lurker.colour: unknown key", func(d: Dictionary) -> void: d.species.lurker["colour"] = "#D9466B"],
		["ghost_ladder.names.rammer.look: unknown key", func(d: Dictionary) -> void: d.names.rammer["look"] = "x"],
		["ghost_ladder.species.veil.body_rect: missing", func(d: Dictionary) -> void: d.species.veil.erase("body_rect")],
		["ghost_ladder.far.cycle_s: missing", func(d: Dictionary) -> void: d.far.erase("cycle_s")],
		["ghost_ladder.far.body_rects.T_Backdrop_colony: missing", func(d: Dictionary) -> void: d.far.body_rects.erase("T_Backdrop_colony")],
		["ghost_ladder.species.lurker.entry_size: must be 2 to 10", func(d: Dictionary) -> void: d.species.lurker.entry_size = 1.0],
		["ghost_ladder.species.veil.entry_size: must be 2 to 10", func(d: Dictionary) -> void: d.species.veil.entry_size = 11.0],
		["ghost_ladder.species.warden.radius_tm: must be above 0", func(d: Dictionary) -> void: d.species.warden.radius_tm = 0.0],
		["ghost_ladder.species.lurker.body_rect: must be", func(d: Dictionary) -> void: d.species.lurker.body_rect = [0.9, 0.1, 0.5, 0.8]],
		["ghost_ladder.species.lurker.texture: no file at", func(d: Dictionary) -> void: d.species.lurker.texture = "res://assets/export/ambience/T_Ghost_none.png"],
		["ghost_ladder.food_haze.plankton: no file at", func(d: Dictionary) -> void: d.food_haze.plankton = "res://nowhere.png"],
		["ghost_ladder.far.textures.1: no texture at", func(d: Dictionary) -> void: d.far.textures[1] = "res://nowhere.png"],
		["ghost_ladder.near.depth_tm: must lie at or below -1.5", func(d: Dictionary) -> void: d.near.depth_tm = [-14.0, -1.0]],
		["ghost_ladder.far.depth_tm: must lie at or below -1.5", func(d: Dictionary) -> void: d.far.depth_tm = [-35.0, 0.0]],
		["ghost_ladder.near.rise_depth_tm: must be at or below -1.5", func(d: Dictionary) -> void: d.near.rise_depth_tm = -1.0],
		["ghost_ladder.far.screen_share: must be above 0 and at most max_screen_share", func(d: Dictionary) -> void: d.far.screen_share = 0.36],
		["ghost_ladder.preview_at_top.0: must be a size 1 to 10", func(d: Dictionary) -> void: d.preview_at_top["0"] = "a lurker"],
		["ghost_ladder.preview_at_top.11: must be a size 1 to 10", func(d: Dictionary) -> void: d.preview_at_top["11"] = "a lurker"],
		["ghost_ladder.far.count: must be the number of textures", func(d: Dictionary) -> void: d.far.count = 4.0],
	]
	for c in cases:
		var data: Dictionary = (shipped.data as Dictionary).duplicate(true)
		(c[1] as Callable).call(data)
		check_has_error(GhostLayer.check_ladder(data), c[0])
	# A layer on no ladder (the pool gives it none when the file has problems) draws nothing.
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	layer.configure({}, 1, SEED)
	layer.apply_scale_view(_view(layer.camera, 1, 12.0))
	check(layer.billboards().is_empty(), "no ladder, no ghosts")
	rig.free()


func test_ladder_matches_the_species_catalog() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/creatures_m1.json")).species
	var ladder := _ladder()
	var both := 0
	for id: String in ladder.species:
		if not catalog.has(id):
			continue
		both += 1
		check_eq(int(ladder.species[id].entry_size), int(catalog[id].get("entry_size", 1)), "%s enters at the catalog's size" % id)
		check_near(float(ladder.species[id].radius_tm), float(catalog[id].body_size) * 0.5, 1e-9, "%s's radius is half its body size" % id)
	check(both >= 2, "the Lurker and the elder rammer are in both (%d)" % both)
	for id: String in ladder.names:
		check(catalog.has(id), "%s, named for its haze, is a species" % id)


func test_body_rects_match_the_pngs() -> void:
	var ladder := _ladder()
	var rects := {}
	for id: String in ladder.species:
		rects[ladder.species[id].texture] = ladder.species[id].body_rect
	for path: String in ladder.far.textures:
		rects[path] = ladder.far.body_rects[path.get_file().get_basename()]
	for path: String in rects:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			check(false, "%s loads" % path)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var data := img.get_data()
		var w := img.get_width()
		var h := img.get_height()
		var lo := Vector2i(w, h)
		var hi := Vector2i(-1, -1)
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] >= 26:   # alpha >= 0.1
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		var measured := [float(lo.x), float(lo.y), float(hi.x + 1), float(hi.y + 1)]
		var rect: Array = rects[path]
		for i in 4:
			var scale := w if i % 2 == 0 else h
			check(absf(float(rect[i]) * scale - measured[i]) <= 2.0, "%s rect[%d] %.3f within 2 px of %.3f" % [path.get_file(), i, rect[i], measured[i] / scale])


func test_near_depths_reach_the_design_multiple() -> void:
	var ladder := _ladder()
	var near: Dictionary = ladder.near
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	for n in [1, 2]:
		check_eq(Array(layer.near_species(n)), NEAR_AHEAD[n], "the near ghosts at size %d, in ladder order" % n)
		for id in NEAR_AHEAD[n]:
			var depth := GhostLayer.near_depth(ladder, id, n)
			var base := GhostLayer.near_base_scale(ladder, id, n)
			var rel := GhostLayer.true_radius(ladder, id, n) / GhostLayer.CELL_RADIUS_TM
			var multiple := GhostLayer.true_multiple(rel, depth, float(near.d_ref_tm))
			check(depth >= float(near.depth_tm[0]) and depth <= float(near.depth_tm[1]), "%s at %d: depth %.2f in the near band" % [id, n, depth])
			check(multiple >= float(near.design_multiple) - 1e-6 or (depth == float(near.depth_tm[1]) and multiple * base >= float(near.design_multiple) - 1e-6),
				"%s at size %d draws %.2f cells at %.2f tm (base %.3f), at least %.2f" % [id, n, multiple, depth, base, near.design_multiple])
			var table: Array = DEPTHS[[id, n]]
			check_near(depth, table[0], 0.06, "%s at %d: the 0.9 table's depth" % [id, n])
			check_near(base, table[1], 0.002, "%s at %d: the 0.9 table's base scale" % [id, n])
	rig.free()


## V-11: twelve spots (rings of 6, 14 and 22 tm at four bearings north of the focus) with each ahead
## species, at zoom 10, 14 and 20 and sizes 1 and 2: every ghost centred on screen draws its body at
## least min_cell_multiple times the cell across.
func test_near_ghosts_draw_at_least_1_4_cells() -> void:
	var least := float(_ladder().near.min_cell_multiple)
	var spots: Array[Vector2] = []
	for r in [6.0, 14.0, 22.0]:
		for deg in [-165.0, -115.0, -65.0, -15.0]:
			spots.append(Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r)
	var seen := 0
	var worst := INF
	var worst_what := ""
	for n in [1, 2]:
		for zoom in [10.0, 14.0, 20.0]:
			var rig := _rig(n, zoom)
			var layer: GhostLayer = rig.get_node("Ghosts")
			var camera: PoolCamera = layer.camera
			var cell := _cell_px(camera)
			var placements := []
			for id in NEAR_AHEAD[n]:
				for spot in spots:
					placements.append({"species": id, "offset": spot})
			for first in range(0, placements.size(), 6):
				layer.stage(placements.slice(first, first + 6), [])
				layer.apply_scale_view(_view(camera, n, 3.0))
				for node in layer.billboards():
					var body := _body_px(camera, node, _rect_of(layer, node))
					if not _on_screen(body.centre):
						continue
					seen += 1
					var multiple: float = body.width / cell
					if multiple < worst:
						worst = multiple
						worst_what = "%s at %s, size %d, zoom %.0f" % [layer.species_of(node), node.position, n, zoom]
			rig.free()
	check(seen >= 100, "ghosts on screen measured: %d" % seen)
	check(worst >= least, "every near ghost draws at least %.1f cells across (worst %.3f: %s)" % [least, worst, worst_what])


## D-53: each giant at three spots and three zooms, after three frames, draws its body between five
## cell radii and a third of the screen high.
func test_far_giants_stay_in_band() -> void:
	var far: Dictionary = _ladder().far
	var spots := [[Vector2(-25.0, -20.0), -35.0], [Vector2(0.0, -30.0), -30.0], [Vector2(28.0, -15.0), -25.0]]
	for zoom in [10.0, 14.0, 20.0]:
		var rig := _rig(1, zoom)
		var layer: GhostLayer = rig.get_node("Ghosts")
		var camera: PoolCamera = layer.camera
		var cell_radius := _cell_px(camera) * 0.5
		for shift in 3:
			var staged := []
			for i in 3:
				var spot: Array = spots[(i + shift) % 3]
				staged.append({"offset": spot[0], "depth": spot[1]})
			layer.stage([], staged)
			for f in 3:
				layer.apply_scale_view(_view(camera, 1, 5.0 + f / 60.0))
			var drawn := 0
			for node in layer.billboards():
				if not str(node.name).begins_with("Far"):
					continue
				drawn += 1
				var body := _body_px(camera, node, _rect_of(layer, node))
				var share: float = body.height / Frames.SCREEN.y
				check(body.height >= float(far.min_cell_radius_multiple) * cell_radius, "%s at zoom %.0f: %.1f px high, at least five cell radii (%.1f px)" % [node.name, zoom, body.height, 5.0 * cell_radius])
				check(share <= float(far.max_screen_share), "%s at zoom %.0f: %.3f of the screen high, at most a third" % [node.name, zoom, share])
				check_near(share, float(far.screen_share), 0.003, "%s at zoom %.0f keeps its share" % [node.name, zoom])
			check_eq(drawn, 3, "three giants drawn")
		rig.free()


## S2G15: a 120 s swim with a growth at 50 s and a rise at 51 s, ten frames a second: every
## billboard stays at or below -1.5 tm; the near ghosts at or below the near band's top (times k
## during the beat), the giants at or below the far band's top (times k), and only the riser comes up
## to -1.5.
func test_ghosts_never_enter_the_plane_band() -> void:
	var ladder := _ladder()
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	var camera: PoolCamera = layer.camera
	var grown := -1.0
	var rose := false
	var worst := {"plane": -INF, "near": -INF, "far": -INF}
	var riser_top := -INF
	var drawn := 0
	for f in 1200:
		var t := f / 10.0
		var size := 1
		var k := 1.0
		if grown < 0.0 and t >= 50.0:
			grown = t
			camera.reexpress(Vector2.ZERO, 1.6)
			layer.begin_growth(1, 2)
		if grown >= 0.0:
			size = 2
			k = GrowthBeat.dolly_k(t - grown)
		if grown >= 0.0 and not rose and t - grown >= GrowthBeat.RISE_S:
			rose = true
			layer.rise("lurker", Vector2(camera.focus.x + 8.0, camera.focus.z - 20.0))
		camera.shift_focus(Vector3(cos(t * 0.05), 0.0, sin(t * 0.05)) * 0.15)
		layer.apply_scale_view(_view(camera, size, t, k))
		for node in layer.billboards():
			drawn += 1
			var y := node.position.y
			worst.plane = maxf(worst.plane, y - GhostLayer.PLANE_FLOOR_TM)
			if node == layer.riser():
				riser_top = maxf(riser_top, y)
			elif str(node.name).begins_with("Near"):
				worst.near = maxf(worst.near, y - float(ladder.near.depth_tm[1]) * k)
			elif str(node.name).begins_with("Far"):
				worst.far = maxf(worst.far, y - float(ladder.far.depth_tm[1]) * k)
	check(drawn > 5000, "ghosts drawn over the run: %d" % drawn)
	check(worst.plane <= 1e-6, "nothing comes above -1.5 tm (worst %.4f over)" % worst.plane)
	check(worst.near <= 1e-6, "the near ghosts keep under the near band's top (worst %.4f over)" % worst.near)
	check(worst.far <= 1e-6, "the giants keep under the far band's top (worst %.4f over)" % worst.far)
	check_near(riser_top, float(ladder.near.rise_depth_tm), 0.01, "the riser came up to -1.5 tm and no higher")
	rig.free()


## S2G15: each ghost painting and giant at the ladder's brightness: under PAINTING_SHARE of its
## alpha-weighted strong texels near the food or threat hue, its luminance x alpha x top opacity at
## most 0.12, and its brightest texel at most 0.40.
func test_ghost_colours() -> void:
	var ladder := _ladder()
	var brightness := float(ladder.brightness)
	var paintings := {}
	for id: String in ladder.species:
		paintings[ladder.species[id].texture] = float(ladder.near.opacity[1])
	for path: String in ladder.far.textures:
		paintings[path] = float(ladder.far.opacity)
	for path: String in paintings:
		var img := (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(Contract.TEXEL_GRID, Contract.TEXEL_GRID)
		var total := 0.0
		var near := {}
		var top := 0.0
		var top_lit := 0.0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var shown := Color(c.r * brightness, c.g * brightness, c.b * brightness, c.a)
				var luma := Color(shown.r, shown.g, shown.b).srgb_to_linear().get_luminance()
				top = maxf(top, luma)
				top_lit = maxf(top_lit, luma * c.a * float(paintings[path]))
				total += c.a
				var lab := LookProbe.lab(Color(shown.r, shown.g, shown.b))
				if c.a <= 0.0 or Vector2(lab.y, lab.z).length() < Contract.PAINTING_CHROMA:
					continue
				for reserved: String in RESERVED:
					if LookProbe.hue_gap(LookProbe.hue(lab), LookProbe.hue(LookProbe.lab(RESERVED[reserved]))) < Contract.HUE_GAP:
						near[reserved] = float(near.get(reserved, 0.0)) + c.a
		for reserved: String in near:
			check(near[reserved] / maxf(total, 1e-6) <= Contract.PAINTING_SHARE, "%s: %.1f%% of it near the %s hue" % [path.get_file(), 100.0 * near[reserved] / total, reserved])
		check(top_lit <= Contract.MAX_LUMA_ALPHA + 1e-4, "%s: luminance x alpha x opacity %.3f, at most 0.12" % [path.get_file(), top_lit])
		check(top <= Contract.MAX_LUMA_BELOW + 1e-4, "%s: luminance %.3f at most 0.40" % [path.get_file(), top])
	# The billboards draw the ladder's brightness and never more than its top opacity.
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	for f in 20:
		layer.apply_scale_view(_view(layer.camera, 1, 20.0 + f))
		for node: MeshInstance3D in layer.billboards():
			var m := node.material_override as ShaderMaterial
			check_near(float(m.get_shader_parameter("brightness")), brightness, 1e-6, "%s at the ladder's brightness" % node.name)
			check(float(m.get_shader_parameter("opacity")) <= float(ladder.near.opacity[1]) + 1e-6, "%s at most the top opacity" % node.name)
	rig.free()


func test_ghost_layer_reads_no_sim() -> void:
	var code := Contract._code_only(FileAccess.get_file_as_string("res://game/scenes/pool/ghost_layer.gd"))
	for word in ["PoolSim", "sim.", "CreatureField", "WorldStream", "SpeciesCatalog", "RemnantField", "PoolScene", "GameSession", "get_parent"]:
		check(not code.contains(word), "ghost_layer.gd never names %s: it reads its view and the camera" % word)


## A growth re-expresses the ghosts by itself (V-12): with the camera re-expressed, the layer told
## begin_growth and the view at the new size with k at 1 / factor, every billboard draws at frame 0
## where it drew at frame A, centre and size.
func test_growth_re_expresses_ghosts() -> void:
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	var camera: PoolCamera = layer.camera
	camera.shift_focus(Vector3(7.0, 0.0, -3.0))
	for f in 3:
		layer.apply_scale_view(_view(camera, 1, 12.0))
	var before := {}
	for node in layer.billboards():
		before[node.name] = _body_px(camera, node, _rect_of(layer, node))
	check(before.size() >= 6, "ghosts drawn at frame A: %d" % before.size())
	camera.reexpress(Vector2.ZERO, 1.6)
	layer.begin_growth(1, 2)
	layer.apply_scale_view(_view(camera, 2, 12.0, GrowthBeat.K_FROM))
	var worst := 0.0
	var worst_what := ""
	for node in layer.billboards():
		if not before.has(node.name):
			check(false, "%s appears at frame 0" % node.name)
			continue
		var a: Dictionary = before[node.name]
		var b := _body_px(camera, node, _rect_of(layer, node))
		for d in [(a.centre as Vector2).distance_to(b.centre), absf(a.side_px - b.side_px)]:
			if d > worst:
				worst = d
				worst_what = str(node.name)
	check_eq(layer.billboards().size(), before.size(), "the same ghosts at frame 0")
	check(worst <= 0.5, "every ghost keeps its centre and size within 0.5 px (worst %.4f: %s)" % [worst, worst_what])
	# By the end of the dolly each draws at the new size's own depth.
	for t in [12.5, 13.0, 14.0]:
		layer.apply_scale_view(_view(camera, 2, t, GrowthBeat.dolly_k(t - 12.0)))
	for node in layer.billboards():
		var id := layer.species_of(node)
		if id != "" and NEAR_AHEAD[2].has(id):
			check_near(node.position.y, minf(GhostLayer.near_depth(_ladder(), id, 2), float(_ladder().near.depth_tm[1])), 1e-4, "%s at its size-2 depth" % id)
	rig.free()


## A growth to 2 hands the species live from 2 to the rise (V-13): at the layer's time 12 s Near0
## shows the Lurker, Near1 and Near4 the elder rammer. The first ghost of each such species waits at
## its opacity for the rise, the other fades from 0.3 s and is gone by 1.3 s; the riser is the
## waiting Lurker itself, and the elder rammer that waited fades once the rise has begun.
func test_a_growth_hands_the_live_species_to_the_rise() -> void:
	var rig := _rig(1)
	var layer: GhostLayer = rig.get_node("Ghosts")
	var camera: PoolCamera = layer.camera
	for f in 3:
		layer.apply_scale_view(_view(camera, 1, 12.0))
	var shown := {}
	for node in layer.billboards():
		shown[str(node.name)] = layer.species_of(node)
	check_eq([shown.get("Near0"), shown.get("Near1"), shown.get("Near4")], ["lurker", "elder_rammer", "elder_rammer"], "the slots at 12 s")
	var opacity := func(name: String) -> float:
		var node: MeshInstance3D = layer.get_node(name)
		return float((node.material_override as ShaderMaterial).get_shader_parameter("opacity")) if node.visible else 0.0
	var waiting_a := [opacity.call("Near0"), opacity.call("Near1")]
	camera.reexpress(Vector2.ZERO, 1.6)
	layer.begin_growth(1, 2)
	var t := 0.0
	while t < 0.95:
		layer.apply_scale_view(_view(camera, 2, 12.0 + t, GrowthBeat.dolly_k(t)))
		t += 1.0 / 60.0
	check_near(opacity.call("Near0"), waiting_a[0], 1e-6, "the Lurker waits at its opacity")
	check_near(opacity.call("Near1"), waiting_a[1], 1e-6, "and so does the first elder rammer")
	check(opacity.call("Near4") < 0.4 * float(_ladder().near.opacity[1]), "the second elder rammer fades from 0.3 s")
	layer.rise("lurker", Vector2(camera.focus.x, camera.focus.z - 30.0))
	check(layer.riser() == layer.get_node("Near0"), "the waiting Lurker is the riser")
	while t < 2.2:
		layer.apply_scale_view(_view(camera, 2, 12.0 + t, GrowthBeat.dolly_k(t)))
		if t >= 1.35:
			check(not (layer.get_node("Near4") as Node3D).visible, "the second elder rammer is gone by 1.3 s")
		t += 1.0 / 60.0
	check(not (layer.get_node("Near1") as Node3D).visible, "the elder rammer that waited fades once the rise begins")
	check(layer.riser() != null and layer.riser().visible, "while the riser still shows")
	rig.free()


## V-13 on T2's real growth tick (size 1 to 2 with the Lurker and elder rammer sites FakeWorldGen
## places at size 2), for each of RISE_LINEAGES (the ghosts hash from the lineage, which a session
## otherwise founds afresh): frame 0 keeps every ghost on its pixel but for a tick of drift; at 1 s
## the ghost of the species whose loaded post is nearest the cell rises, is at -1.5 tm by 2 s while
## in sight and never above it, closes on that post every frame it shows, and is gone by 6 s.
func test_rise() -> void:
	var at_2_seen := 0
	for lineage in RISE_LINEAGES:
		at_2_seen += _rise_with(lineage)
	check(at_2_seen > 0, "a riser was still in sight at 2 s")


## One growth with the rise for `lineage`; 1 when its riser was in sight at 2 s, else 0.
func _rise_with(lineage: String) -> int:
	var session := FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true)
	session.sim.save.lineage_id = lineage
	var pool := FakeEvents.open_pool(session)
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	for i in 40:
		Frames.frame(pool)
	var before := {}
	for node in pool.ghosts.billboards():
		before[node.name] = _body_px(pool.camera, node, _rect_of(pool.ghosts, node))
	check(before.size() >= 6, "%s: ghosts drawn at frame A: %d" % [lineage, before.size()])
	var g := sim.growth
	g.meter = g.ring(sim.size())
	g.full_since = sim.tick
	g.due = true
	Frames.frame(pool)
	check_eq(sim.size(), 2, "the tick grew the world")
	var worst := 0.0
	for node in pool.ghosts.billboards():
		if before.has(node.name):
			var a: Dictionary = before[node.name]
			var b := _body_px(pool.camera, node, _rect_of(pool.ghosts, node))
			worst = maxf(worst, maxf((a.centre as Vector2).distance_to(b.centre), absf(a.side_px - b.side_px)))
	check(worst <= 1.5, "%s: frame 0: every ghost within a tick's drift of its pixel (worst %.3f px)" % [lineage, worst])
	var riser: MeshInstance3D = null
	var target := Vector2.ZERO
	var top := -INF
	var at_2 := INF
	var gaps := PackedFloat64Array()
	while pool.growth_beat.running():
		Frames.frame(pool)
		var t := pool.growth_beat.t()
		if t < GrowthBeat.RISE_S:
			check(pool.ghosts.riser() == null, "no rise before 1 s")
			continue
		if riser == null and pool.ghosts.riser() != null:
			riser = pool.ghosts.riser()
			var nearest := _nearest_post(pool, pool.ghosts.entering(2))
			check(not nearest.is_empty(), "a Lurker or elder rammer post is loaded")
			target = nearest.get("at", Vector2.ZERO)
			check_eq(pool.ghosts.species_of(riser), nearest.get("species", ""), "the riser shows the species of the nearest post")
		if riser == null or not riser.visible:
			continue
		top = maxf(top, riser.position.y)
		if at_2 == INF and t >= 2.0:
			at_2 = riser.position.y
		gaps.append(Vector2(riser.position.x, riser.position.z).distance_to(target))
	check(riser != null, "%s: a ghost rose" % lineage)
	check(top <= -1.5 + 1e-6, "%s: the riser never comes above -1.5 tm (%.4f)" % [lineage, top])
	if at_2 != INF:
		check_near(at_2, -1.5, 0.01, "%s: the riser is at -1.5 tm at 2 s" % lineage)
	var closing := gaps.size() >= 2 and gaps[gaps.size() - 1] < gaps[0] - 0.5
	for i in range(1, gaps.size()):
		closing = closing and gaps[i] <= gaps[i - 1] + 1e-3
	check(closing, "%s: it closes on the post every frame it shows (%d frames, %.2f to %.2f tm)"
		% [lineage, gaps.size(), gaps[0] if not gaps.is_empty() else -1.0, gaps[gaps.size() - 1] if not gaps.is_empty() else -1.0])
	check(pool.ghosts.riser() == null and (riser == null or not riser.visible), "%s: gone by 6 s" % lineage)
	pool.free()
	return 1 if at_2 != INF else 0


## The loaded post nearest the cell of one of `species`, as the beat picks it: {species, at}, or {}.
static func _nearest_post(pool: PoolScene, species: PackedStringArray) -> Dictionary:
	var cell := PlaneSpace.to_plane(pool.cell_view.position)
	var out := {}
	for key in pool.sim.world.loaded_keys():
		for site: Dictionary in pool.sim.world.chunk(key).sites:
			if not species.has(str(site.species)):
				continue
			for post: Dictionary in site.get("posts", [site]):
				var p := pool.sim.world.local_of_tm(float(post.x), float(post.y))
				if out.is_empty() or p.distance_to(cell) < (out.at as Vector2).distance_to(cell):
					out = {"species": str(site.species), "at": p}
	return out


func test_first_pass_once_per_lineage() -> void:
	var session := FakeEvents.pool_session()
	var lineage := session.sim.save.lineage_id
	var memory := UserSettings.new()
	var pool := _pool_with_memory(session, memory)
	var u := float(hash(lineage) & 0xFFFF) / 65536.0
	var at := pool.ghosts.first_pass_at()
	check_near(at, session.sim.now() + 30.0 + 30.0 * u, 1e-6, "the pass is set 30 + 30u s into the session")
	var told := [0]
	pool.giant_pass_started.connect(func() -> void: told[0] += 1)
	var view := pool.scale_view()
	for t in [at - 0.05, at + 0.05, at + 10.0, at + 25.0, at + 200.0]:
		view.time_s = t
		pool.ghosts.apply_scale_view(view)
		if t == at - 0.05:
			check_eq(told[0], 0, "not before its time")
		elif t == at + 0.05:
			check_eq(told[0], 1, "told as the pass starts")
		elif t == at + 10.0:
			var giant: Node3D = pool.ghosts.get_node("Far0")
			check(giant.visible, "far slot 0 makes the pass")
			check_near(giant.position.y, float(_ladder().far.first_pass.depth_tm), 1e-4, "at the pass's depth")
	check_eq(told[0], 1, "once")
	# Main remembers the lineage when told, once.
	var main := Main.new()
	main.flags = RunFlags.from_args(PackedStringArray())
	main.memory_writable = false
	main.player_memory = memory
	main.session = session
	main._on_giant_pass_started()
	main._on_giant_pass_started()
	check_eq(memory.giant_pass_lineages, PackedStringArray([lineage]), "main remembers the lineage")
	main.free()
	pool.free()
	# A lineage this computer remembers gets no pass.
	var again := _pool_with_memory(session, memory)
	check_eq(again.ghosts.first_pass_at(), -1.0, "no pass for a remembered lineage")
	var told_again := [0]
	again.giant_pass_started.connect(func() -> void: told_again[0] += 1)
	var later := again.scale_view()
	later.time_s = 500.0
	again.ghosts.apply_scale_view(later)
	check_eq(told_again[0], 0, "nothing told")
	again.free()


func _pool_with_memory(session: GameSession, memory: UserSettings) -> PoolScene:
	var pool: PoolScene = FakeEvents.POOL_SCENE.instantiate()
	pool.pause_on_focus_loss = false
	pool.player_memory = memory
	pool.setup(session, FakeEvents.Still.new())
	FakeEvents.ready_tree(pool)
	return pool


func test_pool_mode_has_ghosts_at_size_1() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	FakeEvents.frame(pool)
	var ghosts := pool.ghosts
	check(ghosts != null and ghosts.name == "Ghosts" and ghosts.get_parent() == pool, "the pool's child Ghosts")
	check(ghosts.is_in_group(&"camera_relative") and not pool.world_space.registered().has(ghosts), "camera_relative, not in WorldSpace (V-12)")
	var far := 0
	var near := 0
	for node in ghosts.billboards():
		if str(node.name).begins_with("Far"):
			far += 1
		elif str(node.name).begins_with("Near"):
			near += 1
			check(NEAR_AHEAD[1].has(ghosts.species_of(node)), "%s shows a species of size 1's list (%s)" % [node.name, ghosts.species_of(node)])
	check_eq(far, 3, "three giants")
	check(near >= 4, "near ghosts drawn: %d" % near)
	check(pool.growth_beat.haze.has("veil") and pool.growth_beat.haze.veil == _ladder().species.veil.haze, "the glitter's haze comes from the ladder")
	pool.free()
	# A ladder with problems: the pool gives the layer none, and nothing draws.
	var broken: Dictionary = _ladder().duplicate(true)
	broken["colour"] = "red"
	GhostLayer._shipped = {"data": broken, "problems": GhostLayer.check_ladder(broken)}
	var bare := FakeEvents.open_pool(FakeEvents.pool_session())
	GhostLayer._shipped = {}
	FakeEvents.frame(bare)
	check(bare.ghosts.billboards().is_empty(), "a broken ladder draws no ghosts")
	bare.free()
