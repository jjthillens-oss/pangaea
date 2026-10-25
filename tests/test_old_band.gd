extends TestCase
## The old band below (S3G28, S3G29; docs/s3/s3-view.md section 5 and 5.1, V3-3 to V3-5, V3-21): the
## sim never names it, and hashes and save bytes are the same with it on or off; every band-0 anchor
## and rare place lies where its size-2 chunk put it (absolute am by id, its yaw, mirror and model),
## at its true size, its top sunk between -3 and -2 tm; the baked colours are old (dim, grey) and
## clear of the food and threat hues; at most 8 draw calls; nothing at band 0; and a refresh's cost
## is reported. The layer cases run an OldBandLayer alone on the shipped world's stream.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const LookProbe := preload("res://tools/godot/look_probe.gd")
const WorldChecks := preload("res://tests/world_checks.gd")
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
const HUE_GAP := 25.0
const MIN_CHROMA := 5.0
const SEED := 4242
const SIM_DIRS: PackedStringArray = ["res://game/systems", "res://game/domain"]
const SIM_NAMES: PackedStringArray = ["OldBandLayer", "old_band", "old_band_layer"]


## The shipped world with its build top at 4 (until I-3 flips the shipped file), loaded once.
var _top4: WorldContent


## The founded lineage every session starts from (its ids are random, so the S3G28 case's two runs
## share one).
var _founded := {}


## A new omnivore lineage at the home spawn of the shipped world at top 4, growth on. Nothing is saved
## but by the S3G28 case.
func _session() -> GameSession:
	var session := GameSession.new(FakeEvents.SLOT)
	if _top4 == null:
		_top4 = WorldContent.load_from(WorldChecks.shipped_world_at(4), session.layout, session.species)
	_top4.config.switches["growth"] = true
	session.world = _top4
	if _founded.is_empty():
		var founded := Lineage.found(SEED, "test+dev", session.catalog, "omnivore")
		founded.save.player["position"] = PlaneSpace.to_save_abs(_top4.home.spawn[0], _top4.home.spawn[1])
		_founded = founded.save.to_dict()
	var save := SaveGame.from_dict(_founded.duplicate(true))
	session.sim = PoolSim.create(save, session.catalog, session.layout, session.species, _top4)
	return session


## An old band on `session`'s world at size `n`, its view round `focus_am`.
func _layer(session: GameSession, n: int, focus_am: PackedFloat64Array) -> OldBandLayer:
	var sim := session.sim
	if sim.world.size != n:
		check(sim.debug_set_size(n), "the dev's size %d" % n)
	var layer := OldBandLayer.new()
	layer.setup(session.world, session.species, sim.world.world_seed, session.world.kit)
	layer.attach(sim.world)
	layer.focus_am = focus_am
	layer.set_band(WorldConfig.band_of(n), n)
	return layer


func _by_id(layer: OldBandLayer) -> Dictionary:
	var out := {}
	for inst in layer.instances():
		out[inst.id] = inst
	return out


## A rare place and a landmark of band 0 near the home, as absolute am focus points.
func _focus_points(session: GameSession) -> Array[PackedFloat64Array]:
	var gen := session.sim.world.gen
	var out: Array[PackedFloat64Array] = []
	for by in range(-1, 2):
		for bx in range(-1, 2):
			var p := gen.rare_piece(0, bx, by)
			if not p.is_empty() and out.is_empty():
				out.append(PackedFloat64Array([p.x_bu, p.y_bu]))
	for ly in range(-2, 3):
		for lx in range(-2, 3):
			var a := gen.landmark_piece(0, lx, ly)
			if not a.is_empty() and out.size() < 2 and absi(lx) + absi(ly) > 0:
				out.append(PackedFloat64Array([a.x_bu, a.y_bu]))
	return out


# --- S3G28: never in the sim ---

func test_never_named_by_sim_code() -> void:
	var files := PackedStringArray()
	for dir in SIM_DIRS:
		_gd_files(dir, files)
	check(files.size() > 20, "the sim's sources are found (%d)" % files.size())
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for name in SIM_NAMES:
			check(not text.contains(name), "%s names %s: the old band is a view only (S3G28)" % [path, name])


func _gd_files(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_gd_files(dir.path_join(sub), out)


func test_hash_and_save_equal_with_layer_on_and_off() -> void:
	var on := _run(true)
	var off := _run(false)
	check(on.grew, "the forced growth crossed the band (2 to 3) with the layer on")
	check(on.drawn > 0, "and the old band drew band 0 under size 3 (%d draw calls)" % on.drawn)
	check_eq(off.drawn, 0, "with the switch off nothing is drawn")
	check_eq(on.hashes, off.hashes, "the sim's hashes at ticks 120, 300 and 600 are equal on and off (S3G28)")
	check(not on.save.is_empty() and on.save == off.save, "the save's bytes are equal on and off (its wall-clock stamp aside)")


## The pool on the shipped world at size 2, the old band on or off: the ring forced full and due,
## 600 ticks with a still cell; the sim's hash at 120, 300 and 600 and the save written after.
func _run(enabled: bool) -> Dictionary:
	var session := _session()
	var pool: PoolScene = FakeEvents.POOL_SCENE.instantiate()
	pool.pause_on_focus_loss = false
	pool.old_band_enabled = enabled
	pool.setup(session, FakeEvents.Still.new())
	FakeEvents.ready_tree(pool)
	var sim := pool.sim
	check(sim.debug_set_size(2), "the dev's size 2")
	FakeEvents.frame(pool)
	check(sim.debug_force_growth(), "a forced growth")
	var hashes := {}
	for t in range(1, 601):
		FakeEvents.frame(pool)
		if t in [120, 300, 600]:
			hashes[t] = str(sim.state_hash())
	var out := {"hashes": hashes, "grew": sim.world.size == 3, "drawn": pool.old_band.draw_calls(), "save": PackedByteArray()}
	if session.save_now().ok:
		var text := FileAccess.get_file_as_string(session.slot)
		var stamp := RegEx.create_from_string("\"saved_at_unix\":\\s*\\d+")
		out.save = stamp.sub(text, "\"saved_at_unix\": 0", true).to_utf8_buffer()
	pool.free()
	return out


# --- S3G29: where, how big, how deep and how dim ---

func test_positions_equal_the_old_chunks() -> void:
	var session := _session()
	var sim := session.sim
	var seen := {"anchor": 0, "place": 0}
	for focus in _focus_points(session):
		check(sim.debug_set_size(2), "the dev's size 2")
		var k2 := WorldConfig.tm_to_am(2)
		var centre := Vector2i(floori(focus[0] / k2 / 32.0), floori(focus[1] / k2 / 32.0))
		var olds: Array[Dictionary] = []
		for cy in range(centre.y - 1, centre.y + 2):
			for cx in range(centre.x - 1, centre.x + 2):
				var chunk := sim.world.gen.chunk(2, cx, cy)
				for a in chunk.anchors:
					var shell := {}
					for s in chunk.shells:
						if s.kind == "landmark" and (shell.is_empty() or Vector2(s.x - a.x, s.y - a.y).length() < Vector2(shell.x - a.x, shell.y - a.y).length()):
							shell = s
					olds.append({"id": a.id, "model": a.model, "x": a.x * k2, "y": a.y * k2, "yaw_deg": float(shell.get("yaw_deg", 0.0)), "mirror": false})
					seen.anchor += 1
				for p in chunk.places:
					olds.append({"id": p.id, "model": session.world.kit.rare_asset(0, p.kind), "x": p.x * k2, "y": p.y * k2,
						"yaw_deg": float(p.get("yaw_deg", 0.0)), "mirror": bool(p.get("mirror", false))})
					seen.place += 1
		for n in [3, 4]:
			var layer := _layer(session, n, focus)
			var drawn := _by_id(layer)
			for old in olds:
				var inst: Dictionary = drawn.get(old.id, {})
				check(not inst.is_empty(), "size %d: %s is drawn (matched by id, V3-21)" % [n, old.id])
				if inst.is_empty():
					continue
				check(absf(inst.abs_am[0] - old.x) <= 1e-9 and absf(inst.abs_am[1] - old.y) <= 1e-9,
					"size %d: %s at (%.9f, %.9f) am where its chunk put it (%.9f, %.9f)" % [n, old.id, inst.abs_am[0], inst.abs_am[1], old.x, old.y])
				var want := sim.world.local_of_abs(old.x, old.y)
				var t: Transform3D = inst.transform
				var at := Vector2(t.origin.x + layer.position.x, t.origin.z + layer.position.z)
				check(at.distance_to(want) <= 1e-4, "size %d: %s drawn at %s, local_of_abs %s" % [n, old.id, at, want])
				check_eq(inst.model, old.model, "size %d: %s's model" % [n, old.id])
				var mirrored := t.basis.determinant() < 0.0
				check_eq(mirrored, old.mirror, "size %d: %s's mirror" % [n, old.id])
				var x_axis := t.basis.x * (-1.0 if mirrored else 1.0)
				var yaw := rad_to_deg(atan2(-x_axis.z, x_axis.x))
				check(absf(angle_difference(deg_to_rad(yaw), deg_to_rad(old.yaw_deg))) <= 1e-4,
					"size %d: %s's yaw %.4f, its chunk's %.4f" % [n, old.id, yaw, old.yaw_deg])
			layer.free()
	check(seen.anchor > 0 and seen.place > 0, "the regions hold anchors (%d) and places (%d)" % [seen.anchor, seen.place])


func test_scale_is_true_size() -> void:
	var session := _session()
	var focus: PackedFloat64Array = session.world.home.spawn
	for n in [3, 4]:
		var layer := _layer(session, n, focus)
		var kit := session.world.kit
		var shrink := WorldConfig.tm_to_am(n)
		check(not layer.instances().is_empty(), "size %d: pieces are drawn round the home" % n)
		for inst in layer.instances():
			var scale := 1.0
			if kit.assets[inst.model].kind == "landmark":
				scale = _dressing_scale(session, inst.id)
			var want := scale / shrink
			var got: Vector3 = (inst.transform as Transform3D).basis.get_scale().abs()
			check(absf(got.x - want) <= 1e-6 and absf(got.y - want) <= 1e-6 and absf(got.z - want) <= 1e-6,
				"size %d: %s at scale %s, its true size %.6f (dressing scale / %.3f)" % [n, inst.id, got, want, shrink])
		layer.free()


## The dressing scale of landmark piece `id` ("a_0_<lx>_<ly>").
func _dressing_scale(session: GameSession, id: String) -> float:
	var parts := id.split("_")
	var p := session.sim.world.gen.landmark_piece(0, int(parts[2]), int(parts[3]))
	return float(p.scale)


func test_tops_are_sunk_two_to_three() -> void:
	var session := _session()
	var focus: PackedFloat64Array = session.world.home.spawn
	for n in [3, 4]:
		var layer := _layer(session, n, focus)
		for inst in layer.instances():
			var t: Transform3D = inst.transform
			var aabb := layer.multimesh_of(inst.model).multimesh.mesh.get_aabb()
			var s := t.basis.get_scale().abs().y
			var top := t.origin.y + aabb.end.y * s
			var bottom := t.origin.y + aabb.position.y * s
			check(top >= OldBandLayer.SINK_TM.x - 1e-6 and top <= OldBandLayer.SINK_TM.y + 1e-6, "size %d: %s's top at %.3f tm, in [-3, -2]" % [n, inst.id, top])
			check(bottom < top, "size %d: %s's bottom %.3f under its top" % [n, inst.id, bottom])
			check(absf(top - OldBandLayer.top_target_tm(aabb.size.y * s)) <= 1e-5, "size %d: %s's top is its height's target (V3-5)" % [n, inst.id])
		layer.free()


func test_baked_colours_are_old_and_clear_of_reserved_hues() -> void:
	var kit := PlacementKit.load_from()
	var models := 0
	for id: String in kit.assets:
		var a: Dictionary = kit.assets[id]
		if not (str(a.kind) in ["landmark", "rare"]) or int(a.band) != 0:
			continue
		models += 1
		var scene := LandmarkLayer._scene(str(a.glb))
		var sources := _surface_albedos(scene)
		var mesh := OldBandLayer.bake_mesh(scene)
		check_eq(mesh.get_surface_count(), 1, "%s bakes to one surface" % id)
		var baked := {}
		for c: Color in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			baked[c.to_html()] = c
		# Every stored vertex colour (8 bits a channel) is the old colour of one of the surfaces'
		# albedos, and is itself old.
		for key in baked:
			var c: Color = baked[key]
			var src := Color.TRANSPARENT
			for s: Color in sources:
				var want := OldBandLayer.old_color(s)
				if absf(want.r - c.r) <= 1.01 / 255.0 and absf(want.g - c.g) <= 1.01 / 255.0 and absf(want.b - c.b) <= 1.01 / 255.0:
					src = s
			check(src.a > 0.0, "%s: vertex colour %s is the old colour of a surface's albedo" % [id, key])
			if src.a > 0.0:
				_check_old(c, src, "%s vertex colour %s (of %s)" % [id, key, src.to_html(false)])
		check(baked.size() >= 1 and baked.size() <= sources.size(), "%s: one baked colour per source surface at most (%d)" % [id, baked.size()])
		var m := mesh.surface_get_material(0) as StandardMaterial3D
		check(m != null and m.vertex_color_use_as_albedo and m.vertex_color_is_srgb and m.albedo_texture != null,
			"%s: one material, vertex colour as albedo (sRGB), the model's detail texture" % id)
		for d: Dictionary in a.get("dressings", []):
			var tint := Color(str(d.tint))
			_check_old(OldBandLayer.old_color(tint), tint, "%s dressing %s" % [id, d.id])
	check_eq(models, 8, "band 0's 6 landmarks and 2 rare kinds")


## The albedos of `scene`'s non-growth mesh surfaces.
func _surface_albedos(scene: PackedScene) -> Array[Color]:
	var root := scene.instantiate()
	var out: Array[Color] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		if str(n.name).begins_with(LandmarkLayer.GROWTH_PREFIX):
			continue
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			out.append((mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color.WHITE)
	root.free()
	return out


## `c` (the old colour of `src`) is dim, grey and clear of the reserved hues.
func _check_old(c: Color, src: Color, what: String) -> void:
	check(OldBandLayer.luma_of(c.srgb_to_linear()) <= OldBandLayer.OLD_LUMA + 1e-4, "%s: linear luma %.4f at most 0.30" % [what, OldBandLayer.luma_of(c.srgb_to_linear())])
	var lab := LookProbe.lab(c)
	var chroma := Vector2(lab.y, lab.z).length()
	var src_lab := LookProbe.lab(src)
	var src_chroma := Vector2(src_lab.y, src_lab.z).length()
	check(chroma <= 0.35 * src_chroma + 2.0, "%s: chroma %.1f at most 0.35 x its source's %.1f + 2" % [what, chroma, src_chroma])
	if chroma >= MIN_CHROMA:
		for reserved: String in RESERVED:
			var gap := LookProbe.hue_gap(LookProbe.hue(lab), LookProbe.hue(LookProbe.lab(RESERVED[reserved])))
			check(gap >= HUE_GAP, "%s: %.0f degrees of LAB hue from the %s colour, at least %.0f" % [what, gap, reserved, HUE_GAP])


func test_draw_calls_at_most_eight() -> void:
	var session := _session()
	var layer := _layer(session, 3, session.world.home.spawn)
	layer.refresh(Rect2(-4000.0, -4000.0, 8000.0, 8000.0))
	var models := {}
	for inst in layer.instances():
		models[inst.model] = true
	check_eq(models.size(), 8, "a wide rect holds every band-0 model and both rare kinds")
	check(layer.draw_calls() <= OldBandLayer.MAX_DRAW_CALLS, "%d draw calls, at most %d" % [layer.draw_calls(), OldBandLayer.MAX_DRAW_CALLS])
	for model in models:
		var mmi := layer.multimesh_of(model)
		check_eq(mmi.multimesh.mesh.get_surface_count(), 1, "%s: one MultiMesh of one surface" % model)
		check(mmi.multimesh.instance_count <= OldBandLayer.MAX_INSTANCES, "%s: at most %d instances" % [model, OldBandLayer.MAX_INSTANCES])
	check(layer.ready_to_draw(), "every band-0 model is baked")
	layer.free()


func test_band_zero_draws_nothing() -> void:
	var session := _session()
	var layer := _layer(session, 3, session.world.home.spawn)
	check(layer.draw_calls() > 0, "size 3 draws the old band")
	for n in [1, 2]:
		check(session.sim.debug_set_size(n), "the dev's size %d" % n)
		layer.set_band(0, n)
		check_eq(layer.draw_calls(), 0, "size %d: no draw calls" % n)
		check(layer.instances().is_empty(), "size %d: no instances" % n)
		for child in layer.get_children():
			if child is MultiMeshInstance3D:
				check(not (child as MultiMeshInstance3D).visible, "size %d: %s is hidden" % [n, child.name])
		layer.tick(10.0 * n)
		check_eq(layer.draw_calls(), 0, "size %d: a tick draws nothing" % n)
	layer.free()


func test_the_pool_mounts_the_old_band() -> void:
	var pool := FakeEvents.open_pool(_session())
	check(pool.world_space.registered().has(pool.old_band), "the old band moves with WorldSpace")
	check(pool.growth_containers().has(pool.old_band), "and keeps the growth containers' contract")
	check_eq(pool.old_band.draw_calls(), 0, "nothing under size 1")
	check(pool.sim.debug_set_size(3), "the dev's size 3")
	FakeEvents.frame(pool)
	check(pool.old_band.draw_calls() > 0, "size 3 draws band 0 below at once (debug set_size)")
	check(pool.sim.debug_set_size(1), "the dev's size 1")
	FakeEvents.frame(pool)
	check_eq(pool.old_band.draw_calls(), 0, "and size 1 nothing")
	pool.free()
	var off: PoolScene = FakeEvents.POOL_SCENE.instantiate()
	off.pause_on_focus_loss = false
	off.old_band_enabled = false
	off.setup(_session(), FakeEvents.Still.new())
	FakeEvents.ready_tree(off)
	check(off.sim.debug_set_size(3), "the dev's size 3, the switch off")
	FakeEvents.frame(off)
	check_eq(off.old_band.draw_calls(), 0, "the switch off skips setup: nothing drawn")
	off.free()


func test_refresh_cost() -> void:
	var session := _session()
	var focus: PackedFloat64Array = session.world.home.spawn
	var layer := _layer(session, 3, focus)
	var k := WorldConfig.tm_to_am(3)
	var times: Array[float] = []
	for i in 100:
		var at := PackedFloat64Array([focus[0] + 2.0 * k * i, focus[1] + 1.0 * k * i])
		var t0 := Time.get_ticks_usec()
		layer.refresh(OldBandLayer.view_rect(at, 3))
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var median := times[times.size() / 2]
	print("    old band refresh: median %.3f ms, max %.3f ms over 100 (moving 2.2 tm each)" % [median, times.back()])
	check(median <= 1.0, "a refresh's median %.3f ms is at most 1.0 ms" % median)
	layer.free()
