extends TestCase
## The growth's look on the creatures (S2G23, S2G40; s2-view 5 and 10.1): the two new bodies keep
## the M1 body contract, a creature is drawn at its q, its threat ink shows exactly while it can
## attack the cell and its green rim exactly while the cell can eat it, remnants go limp, morsels lie
## where their carrion items are, views removed by a growth fade where they were, and "Now food"
## goes over at most three rimmed bodies on screen.
##
## The growth beat (S2G13 F, S2G24, S2G25; s2-view 4): its curves, the camera kept at the same
## absolute place and dollied back out, every container re-expressed with nothing moving on screen,
## leftovers adopted by id or sunk away (never popped), reduce motion, the cell's settle, a clock
## that is the same at any frame rate, and "Now food" with the relations. The old food (T5.4, V-10,
## V-22): the new plankton grows in as the algae ball while the old food is drawn on, re-expressed,
## from copies that fade, and glitter sinks from where the old plankton and haze were. The lair
## mouths (V-25): re-expressed and held at k of their depth, adopted by site and post, new ones in
## from the veil after the settle, the leftovers sunk and freed. Most growth
## events are faked (tests/fakes/fake_growth_events.gd); the food's is T2's real growth tick. The
## tests use their own settings file and never save it.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const FakeGrowthEvents := preload("res://tests/fakes/fake_growth_events.gd")
const Frames := preload("res://tests/scene_frames.gd")
const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")
const SETTINGS_PATH := "user://test_growth_view/settings.cfg"
const BODIES: PackedStringArray = ["grazer", "hunter", "omnivore"]
## The new bodies and the M1 bodies whose contract (node names, material names) they keep.
const BODY_PAIRS := {"creature_lurker_body": "creature_ambush_body", "creature_elder_rammer_body": "creature_rammer_body"}
const THREAT_INK := Color("#D9466B")
const DT := 1.0 / 60.0

var _species: SpeciesCatalog
var _catalog: PartCatalog


## Records cues instead of playing them.
class CueLog extends CellAudio:
	var cues: PackedStringArray = []

	func play(cue: String) -> void:
		cues.append(cue)

	func play_at(cue: String, _at: Vector3) -> void:
		cues.append(cue)


func before_each() -> void:
	if _species == null:
		_species = SpeciesCatalog.load_from()
		_catalog = PartCatalog.load_from()
	SettingsService.set_shared(SettingsService.new(SETTINGS_PATH))


func after_each() -> void:
	SettingsService.set_shared(null)


func test_new_bodies_keep_the_m1_body_contract() -> void:
	for body in BODY_PAIRS:
		var scene: PackedScene = CreatureView.BODY_SCENES.get(body)
		check(scene != null, "%s is a body the view can draw" % body)
		var m1: PackedScene = CreatureView.BODY_SCENES[BODY_PAIRS[body]]
		if scene == null:
			continue
		var mine := _contract(scene)
		var theirs := _contract(m1)
		check_eq(mine.nodes, theirs.nodes, "%s: node names as %s" % [body, BODY_PAIRS[body]])
		check_eq(mine.materials, theirs.materials, "%s: material names as %s" % [body, BODY_PAIRS[body]])
	check("M_Threat" in _contract(CreatureView.BODY_SCENES["creature_elder_rammer_body"]).materials,
		"the elder rammer's crest is M_Threat, so its ink can fade")


func test_a_view_is_drawn_at_its_q() -> void:
	for id in _species.species_ids():
		var view := _view(id, 0.625)
		var base := _species.phenotype(id, _catalog).radius
		check_near(view.radius, base * 0.625, 1e-6, "%s: radius at q" % id)
		check(view._model.scale.is_equal_approx(Vector3.ONE * view.body_size * 0.625), "%s: model at q: %s" % [id, view._model.scale])
		view.set_q(1.0)
		check_near(view.radius, base, 1e-6, "%s: back at q 1" % id)
		check(view._model.scale.is_equal_approx(Vector3.ONE * view.body_size), "%s: model at q 1" % id)
		view.free()


func test_ink_table() -> void:
	var cell := _cell("omnivore")
	var cases := 0
	for n in [1, 2]:
		for id in _species.species_ids():
			if not _species.live_at(id, n):
				continue
			var q := _species.q_of(id, n)
			var view := _view(id, 1.0)
			view.set_q(q)
			var r := CreatureLayer.relation_of(_species, id, q, view.radius, n, cell)
			view.set_relation(r.can_attack, r.rimmed, 1.0)
			_run(view, 1.05)
			var attacks := Relationships.can_attack_player(q)
			var tag := "%s at size %d" % [id, n]
			check_eq(r.can_attack, attacks, "%s: attacks exactly at q 1" % tag)
			check_near(view.ink, 1.0 if attacks else 0.0, 1e-9, "%s: ink after the 1 s fade" % tag)
			var surfaces := _ink_surfaces(view)
			check(surfaces.has("M_Threat") or not "M_Threat" in _contract(_body_scene(id)).materials, "%s: its M_Threat crest found" % tag)
			for name in surfaces:
				var want: Color = THREAT_INK if attacks else CreatureView.INK_SURFACES[name]
				if name == "M_Threat":
					check(surfaces[name].is_equal_approx(want), "%s: M_Threat %s, want %s" % [tag, surfaces[name].to_html(), want.to_html()])
				elif not attacks:
					check(surfaces[name].is_equal_approx(want), "%s: %s neutral" % [tag, name])
			var marker: Color = view._marker.modulate
			var lane: Color = view._lane_material.get_shader_parameter("color")
			var want_mark := CreatureView.MARKER_COLOR if attacks else CreatureView.NEUTRAL_CREST
			check(Color(marker, 1.0).is_equal_approx(want_mark), "%s: the ! alike" % tag)
			check(Color(lane, 1.0).is_equal_approx(CreatureView.LANE_COLOR if attacks else CreatureView.NEUTRAL_CREST), "%s: the lane alike" % tag)
			cases += 1
			view.set_remnant(1.0, 2.0)
			view.set_relation(true, false, 0.0)
			check_near(view.ink, 0.0, 1e-9, "%s: a remnant has no ink" % tag)
			view.free()
	check(cases >= 3, "every live species at both sizes: %d cases" % cases)
	# Halfway through the fade the ink is half way; the rim comes in over 0.3 s (V-8).
	var fading := _view("rammer", 1.0)
	fading.set_relation(false, true, 1.0)
	_run(fading, 0.15)
	check_near(fading.rim, 0.5, 0.02, "the rim half in at 0.15 s")
	_run(fading, 0.35)
	check_near(fading.ink, 0.5, 0.02, "the ink fades over 1 s")
	check_near(fading.rim, 1.0, 1e-9, "the rim in by 0.3 s")
	fading.free()


func test_rim_table() -> void:
	var cases := {"rimmed": 0, "rival": 0}
	for body in BODIES:
		var cell := _cell(body)
		for n in [1, 2]:
			for id in _species.species_ids():
				if not _species.live_at(id, n):
					continue
				var q := _species.q_of(id, n)
				var radius := _species.phenotype(id, _catalog).radius * q
				var role := Relationships.ladder_role(_species.entry_size(id), n, radius)
				var r := CreatureLayer.relation_of(_species, id, q, radius, n, cell)
				var want: bool = role in ["prey", "morsel"] and cell.can_eat("meat")
				var tag := "%s at size %d for a %s (%s)" % [id, n, body, role]
				check_eq(r.rimmed, want, tag)
				if role == "rival":
					check(not r.rimmed, "%s: a rival is never rimmed" % tag)
					cases.rival += 1
				var view := _view(id, q)
				view.set_relation(r.can_attack, r.rimmed, 0.0)
				_run(view, DT)
				check_near(view.rim, 1.0 if want else 0.0, 1e-9, "%s: the rim drawn" % tag)
				if want:
					cases.rimmed += 1
					check_near(view.rim_grow_world(), CreatureView.RIM_GROW_TM, CreatureView.RIM_GROW_TM * 0.01, "%s: 0.06 tm wide" % tag)
					check(view._body_mesh != null and view._body_mesh.material_overlay != null, "%s: the hull is on the body mesh" % tag)
				view.free()
	check(cases.rimmed > 0 and cases.rival > 0, "the grid holds rimmed bodies and rivals: %s" % cases)
	# A morsel item is rimmed for a cell with a jaw only.
	var morsel_r := Relationships.MORSEL_MIN_REL * Relationships.PLAYER_RADIUS + 0.01
	check(CreatureLayer.relation_of(_species, "rammer", 0.3, morsel_r, 2, _cell("hunter"), true).rimmed, "a morsel, for a hunter")
	check(not CreatureLayer.relation_of(_species, "rammer", 0.3, morsel_r, 2, _cell("grazer"), true).rimmed, "never for a grazer")
	check(not CreatureLayer.relation_of(_species, "rammer", 1.0, 0.625, 2, _cell("hunter"), true).can_attack, "a converted body never attacks")


func test_layer_relates_views_at_the_cells_size() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var layer := pool.creature_layer
	check(sim.phenotype.can_eat("meat"), "the fixture cell has a jaw")
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(4.0, 0.0), 0.0), "a rammer at size 1")
	layer.sync(1.0)
	var view := layer.views()[0]
	check(view.view_q == 1.0 and view.ink == 1.0 and view.rim == 0.0, "a threat at its entry size: inked, no rim")
	layer.apply_relations(2, 0.0)
	check(view.ink == 0.0 and view.rim == 1.0, "the cell at size 2: neutral and rimmed, before it is redrawn")
	layer.apply_relations(1, 0.0)
	check(view.ink == 1.0 and view.rim == 0.0, "and back")
	# A creature that appears at size 2 is drawn at its record's q there (CreatureField.record_of).
	sim.creatures.set_size(2)
	sim.world.size = 2
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-4.0, 0.0), 0.0), "a rammer at size 2")
	layer.sync(1.0)
	var small := layer.views()[layer.views().size() - 1]
	check_near(small.view_q, float(sim.creatures.record_of("rammer").q), 1e-12, "its record's q")
	check_near(small.view_q, 0.625, 1e-12, "0.625")
	check(small.ink == 0.0 and small.rim == 1.0, "drawn neutral and rimmed from its first frame")
	pool.free()


func test_a_remnant_view_flashes_and_dies_by_its_creature_id() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var layer := pool.creature_layer
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(4.0, 0.0), 0.0), "a rammer")
	FakeEvents.frame(pool)
	var view := layer.views()[0]
	var id := view.creature_id
	layer.on_event({"type": "creature_converted", "id": id, "species": "rammer", "to": "remnant",
		"position": PlaneSpace.to_plane(view.position), "radius": view.radius, "food_id": ""})
	check(layer.remnant_view(id) == view and layer.view_of(id) == null, "a remnant now")
	_run(view, DT)
	check_near(view.ink, 1.0, 1e-9, "its ink kept until the relations change (frame 0 as frame A)")
	layer.apply_relations(1, 0.0)
	check_near(view.ink, 0.0, 1e-9, "then none, even at its entry size")
	layer.on_event({"type": "hit", "id": "c_player", "target": id})
	check(view._hurt_t == 0.0, "a bite flashes it")
	layer.on_event({"type": "creature_died", "id": id})
	check(view.dying and layer.remnant_view(id) == null, "a kill plays its death")
	pool.free()


func test_remnant_goes_limp() -> void:
	var view := _view("rammer", 0.625)
	view.set_remnant(1.0, 2.0)
	_run(view, 1.9)
	check(view._limp_share() == 0.0, "not limp before 2 s")
	_run(view, 0.6)
	var share := view._limp_share()
	check(share > 0.3 and share < 0.7, "fading in at 2.5 s: %.2f" % share)
	var meshes := view._model.find_children("*", "GeometryInstance3D", true, false)
	check(not meshes.is_empty() and (meshes[0] as GeometryInstance3D).material_overlay != null, "as an overlay")
	_run(view, 0.6)
	for g: GeometryInstance3D in meshes:
		check(g.material_override == CreatureView.LIMP_MATERIAL, "then it is the material: %s" % g.name)
	view.free()


func test_now_food_label() -> void:
	var view := _view("rammer", 0.625)
	view.show_now_food(3.0)
	var label := view.now_food_label()
	check(label != null, "the label shows")
	if label != null:
		check_eq(label.text, "Now food", "its words")
		check(label.modulate.is_equal_approx(Color(CreatureView.RIM_COLOR, 0.0)), "food's green, fading in")
		check_eq(label.render_priority, CreatureView.LANE_PRIORITY + 1, "over the lane")
		check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label.font_size == 56 and label.outline_size == 12, "a billboard at 56 with a 12 outline")
		check(label.position.is_equal_approx(Vector3(0.0, 1.0, -1.6 * view.radius)), "above and north of the body")
		_run(view, 0.2)
		check_near(label.modulate.a, 1.0, 1e-6, "in over 0.2 s")
		_run(view, 2.6)
		check_near(label.modulate.a, 0.5, 0.05, "out over the last 0.4 s")
		_run(view, 0.3)
		check(view.now_food_label() == null, "gone after 3 s")
	view.free()


func test_rimmed_in_view_picks_the_three_nearest_on_screen() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var layer := pool.creature_layer
	var c := sim.motion.position
	var spots := [Vector2(3.0, 0.0), Vector2(-4.0, 1.0), Vector2(0.0, 5.0), Vector2(6.0, -2.0), Vector2(40.0, 0.0)]
	for p in spots:
		check(sim.debug_spawn_creature("rammer", c + p, 0.0), "a rammer at %s" % p)
	FakeEvents.frame(pool)
	check_eq(layer.views().size(), 5, "five drawn")
	for v in layer.views():
		v.set_relation(false, true, 0.0)
	var screen := Vector2(1920.0, 1080.0)
	var picked := layer.rimmed_in_view(pool.camera, screen, 3)
	check_eq(picked.size(), 3, "three of the five")
	var far := layer.views()[layer.views().size() - 1]
	check(not far in layer.views_in_view(pool.camera, screen), "the one far out is off screen")
	var nearest: Array[float] = []
	for v in layer.views():
		nearest.append(PlaneSpace.to_plane(v.position).distance_to(c))
	nearest.sort()
	for v in picked:
		check(PlaneSpace.to_plane(v.position).distance_to(c) <= nearest[2] + 1e-4, "only the nearest: %s" % v.creature_id)
	layer.views()[0].set_relation(false, false, 0.0)
	for v in layer.rimmed_in_view(pool.camera, screen, 3):
		check(v.rimmed(), "never an unrimmed one")
	pool.free()


func test_removed_views_fade() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(4.0, 0.0), 0.0), "a rammer")
	FakeEvents.frame(pool)
	var view := pool.creature_layer.views()[0]
	_run(view, 1.0)   # past its spawn fade-in
	check_near((view._model.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).transparency,
		0.0, 1e-9, "drawn whole")
	var c := sim.creatures.find(view.creature_id)
	sim.creatures.remove(c, "growth", sim.tick, false)
	for e in sim.drain_events():
		pool._route(e)
	check(is_instance_valid(view) and not view.is_queued_for_deletion(), "kept after creature_removed{growth}")
	check(pool.creature_layer.view_of(view.creature_id) == null, "no longer a live view")
	check(view in pool.world_space.registered(), "WorldSpace moves it while it fades")
	_run(view, 0.3)
	var meshes := view._model.find_children("*", "GeometryInstance3D", true, false)
	check_near((meshes[0] as GeometryInstance3D).transparency, 0.5, 0.05, "half faded at 0.3 s")
	check_near(view._model.position.y, 0.0, 1e-9, "with no sink")
	_run(view, 0.35)
	check(view.is_queued_for_deletion(), "gone after 0.6 s")
	# Any other reason still takes the view at once.
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-4.0, 0.0), 0.0), "another rammer")
	FakeEvents.frame(pool)
	var other := pool.creature_layer.views()[0]
	sim.creatures.remove(sim.creatures.find(other.creature_id), "stuck", sim.tick, false)
	for e in sim.drain_events():
		pool._route(e)
	check(other.is_queued_for_deletion(), "a stuck creature's view goes at once")
	pool.free()


func test_morsel_view_follows_its_item() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(5.0, 0.0), 0.0), "a rammer")
	FakeEvents.frame(pool)
	var view := pool.creature_layer.views()[0]
	var item := sim.carrion.spawn(sim.motion.position + Vector2(5.0, 0.0), "morsel", 4.0, -1, 0.2)
	pool.creature_layer.on_event({"type": "creature_converted", "id": view.creature_id, "species": "rammer",
		"to": "morsel", "position": item.position, "radius": 0.2, "food_id": item.id})
	check(pool.creature_layer.morsel_view(item.id) == view, "the view became the morsel")
	check_near(view.radius, 0.2, 1e-6, "drawn at the morsel's radius")
	var meshes := view._model.find_children("*", "GeometryInstance3D", true, false)
	check((meshes[0] as GeometryInstance3D).material_override == CreatureView.MORSEL_MATERIAL, "with M_Morsel")
	item.position += Vector2(1.5, -0.5)
	pool.creature_layer.sync(1.0)
	check(PlaneSpace.to_plane(view.position).is_equal_approx(item.position), "where its item lies")
	pool.creature_layer.on_event({"type": "ate", "kind": "meat", "food_id": item.id})
	check(view.leaving(), "eaten: it fades")
	check(pool.creature_layer.morsel_view(item.id) == null, "and is no longer a morsel")
	pool.free()


# --- the growth beat (s2-view 4; S2G13 F, S2G24, S2G25) ---

func test_k_curve() -> void:
	for t in [0.0, 0.1, 0.3]:
		check_near(GrowthBeat.dolly_k(t), 0.625, 1e-12, "k holds at 1 / factor until the dolly (t %.1f)" % t)
	for t in [1.9, 2.0, 6.0]:
		check_near(GrowthBeat.dolly_k(t), 1.0, 1e-12, "k is 1 from 1.9 s (t %.1f)" % t)
	check_near(GrowthBeat.dolly_k(1.1), 0.8125, 1e-6, "half way at the window's middle")
	# Ease-in-out cubic: a quarter of the way through the window, 1/16 of the way out (linear: 1/4).
	check_near(GrowthBeat.dolly_k(0.7), 0.625 + 0.375 / 16.0, 1e-6, "k 0.648 at 0.7 s (s2-view 4.3)")
	var last := 0.0
	var monotone := true
	for i in 241:
		var k := GrowthBeat.dolly_k(i / 120.0)
		monotone = monotone and k >= last - 1e-12
		last = k
	check(monotone, "k never turns back")
	check_near(GrowthBeat.dolly_k(1.1, 0.5), 0.75, 1e-6, "from the event's own 1 / factor")


func test_swell_curve() -> void:
	check_near(GrowthBeat.swell_at(0.0, false), 0.625, 1e-12, "the cell starts at k of its size")
	check_near(GrowthBeat.swell_at(0.7, false), 1.0, 1e-12, "and is whole at 0.7 s")
	check_near(GrowthBeat.swell_at(0.35, false), 0.625 + 0.375 * 0.875, 1e-9, "easing out")
	check_near(GrowthBeat.swell_at(0.0, true), 0.8125, 1e-12, "under reduce motion half the swell")
	check_near(GrowthBeat.swell_at(0.7, true), 1.0, 1e-12, "whole at 0.7 s too")


func test_camera_reexpress_keeps_the_absolute_camera() -> void:
	var camera := PoolCamera.new()
	camera.configure({"distance": 14.0})
	camera.snap_to(Vector3(3.0, 0.0, -2.0))
	var before := camera.transform
	var c := Vector2(5.0, 1.0)
	camera.reexpress(c, 1.6)
	var back := camera.position * 1.6 + Vector3(c.x, 0.0, c.y)
	check(back.distance_to(before.origin) < 1e-4, "re-expressed back, the camera is where it was: %s, %s" % [back, before.origin])
	check(camera.basis.is_equal_approx(before.basis), "looking the same way")
	check_near(camera.distance, 14.0, 1e-12, "the zoom asked for is kept")
	check_near(camera.shown_distance(), 14.0 / 1.6, 1e-9, "the shown distance is divided")
	check(camera.dolly_active(), "and a dolly back out waits")
	camera.free()


func test_dolly_drives_and_hands_back() -> void:
	var camera := PoolCamera.new()
	camera.configure({"distance": 14.0})
	camera.snap_to(Vector3.ZERO)
	camera.reexpress(Vector2.ZERO, 1.6)
	var from := 14.0 / 1.6
	var worst := 0.0
	var t := 0.0
	while t < 1.9 - 1e-9:
		camera.dolly_t = t
		camera.follow(Vector3.ZERO, Vector2.ZERO, DT)
		var u := clampf((t - GrowthBeat.DOLLY.x) / (GrowthBeat.DOLLY.y - GrowthBeat.DOLLY.x), 0.0, 1.0)
		worst = maxf(worst, absf(camera.shown_distance() - lerpf(from, 14.0, GrowthBeat.ease_in_out_cubic(u))))
		check(camera.dolly_active(), "the dolly runs at %.3f s" % t)
		t += DT
	check(worst < 1e-5, "the shown distance is the dolly's curve (worst %s)" % worst)
	camera.dolly_t = 1.9
	camera.follow(Vector3.ZERO, Vector2.ZERO, DT)
	check(not camera.dolly_active(), "it hands back at 1.9 s")
	check_near(camera.shown_distance(), 14.0, 1e-9, "at the zoom asked for")
	camera.zoom_by(1)
	camera.follow(Vector3.ZERO, Vector2.ZERO, DT)
	var d := camera.shown_distance()
	check(d > 14.0 and d < 16.0, "then a zoom eases as before: %.3f" % d)
	camera.free()


func test_each_container_re_expresses_without_a_screen_move() -> void:
	var pool := _growth_pool()
	# The silt trail drawn as at size 2: a lair mouth (under the plane) and a ribbon.
	var c0 := pool.sim.motion.position
	pool.silt_trail.resize(2)
	pool._route(FakeEvents.loaded(Vector2i(901, 900), [], [], [], [],
		[FakeGrowthEvents.site("s_l", "lurker", [FakeGrowthEvents.post(c0 + Vector2(-4.0, 5.0), 1.0)] as Array[Dictionary])]))
	pool.silt_trail.add_ribbon({"from": c0 + Vector2(-4.0, 5.0), "to": c0 + Vector2(3.0, 6.0)}, "lurker", pool.sim.now())
	check(pool.silt_trail.mouths().size() == 1 and pool.silt_trail.ribbons().size() == 1, "a lair mouth and a ribbon drawn")
	var lane := pool.creature_layer.views()[0].lane()
	var before := _container_pixels(pool, lane)
	check(before.size() >= 20, "at least 20 points tracked (%d)" % before.size())
	var c := pool.sim.motion.position
	pool._begin_growth(FakeGrowthEvents.began(c, 1, 2))
	var after := _container_pixels(pool, lane)
	var moved := []
	for key in before:
		if not after.has(key) or (after[key] as Vector2).distance_to(before[key]) > 0.5:
			moved.append("%s %s -> %s" % [key, before[key], after.get(key)])
	check(moved.is_empty(), "no point moves on screen:\n        %s" % "\n        ".join(moved))
	for node: Node3D in [pool.rocks, pool.landmarks, pool.zone_lights, pool.feedback, pool.silt_trail, pool.growth_beat.fx]:
		check(node.position.is_zero_approx() and node.scale.is_equal_approx(Vector3.ONE),
			"%s sits at the origin at scale 1: %s, %s" % [node.name, node.position, node.scale])
	check(lane.scale.is_equal_approx(Vector3.ONE / 1.6), "a leaf is itself divided: %s" % lane.scale)
	var burst: Node3D = pool.world_fx.get_node("EatFx")
	check(pool.world_fx.transform == Transform3D.IDENTITY and burst.scale.is_equal_approx(Vector3.ONE),
		"WorldFx is baked (V-5): the eat burst re-expressed but still cell-sized")
	pool.free()


## Every depth layer at k (s2-view 4.2): the Backdrop's depth and size, the fog's heights and
## densities, the zone patches' and lair mouths' depth, the zone labels and the markers; back at k 1
## exactly.
func test_depth_layers_follow_k() -> void:
	var pool := _growth_pool()
	pool.silt_trail.resize(2)
	pool._route(FakeEvents.loaded(Vector2i(901, 900), [], [], [], [], FakeGrowthEvents.lair_sites(pool.sim.motion.position)))
	var mouth: Node3D = pool.silt_trail.mouths()[0] if not pool.silt_trail.mouths().is_empty() else null
	check(mouth != null, "a lair mouth")
	var env := pool._world_env.environment
	var base := {"y": pool.backdrop.position.y, "h": env.fog_height, "hd": env.fog_height_density, "d": env.fog_density}
	var column_h := pool.markers.column().scale.y
	pool.apply_depth_k(0.625)
	check_near(pool.backdrop.position.y, base.y * 0.625, 1e-6, "the Backdrop at k of its depth (-25 new tm is -40 old)")
	check(pool.backdrop.scale.is_equal_approx(Vector3.ONE * 0.625), "and of its size")
	check_near(env.fog_height, base.h * 0.625, 1e-6, "the fog's height times k")
	check_near(env.fog_height_density, base.hd / 0.625, 1e-6, "its height density over k")
	check_near(env.fog_density, base.d / 0.625, 1e-9, "its density over k")
	var disc := pool.zone_lights.disc_of("z_gv")
	check(disc != null and is_equal_approx(disc.position.y, ZoneLights.DEPTH_M * 0.625), "a patch at k of its depth")
	var label := pool.feedback.zone_label("z_gv")
	check(label != null and label.scale.is_equal_approx(Vector3.ONE * 0.625), "a zone label at k of its size")
	check_near(pool.markers.column().scale.y, column_h * 0.625, 1e-6, "the column at k")
	check(mouth != null and is_equal_approx(mouth.position.y, -1.6 * 0.625), "a lair mouth at k of its depth")
	pool.apply_depth_k(1.0)
	check(pool.backdrop.position.y == base.y and env.fog_height == base.h and env.fog_height_density == base.hd,
		"back at k 1: the base values exactly")
	check(disc.position.y == ZoneLights.DEPTH_M and label.scale == Vector3.ONE and pool.markers.column().scale.y == column_h,
		"and the patches, labels and column")
	check(mouth != null and is_equal_approx(mouth.position.y, -1.6), "and the lair mouths")
	var shared: Environment = load("res://game/scenes/pool/pool_environment.tres")
	check(env != shared and env.resource_path.is_empty(), "the pool scales its own copy of the environment")
	pool.apply_depth_k(0.5)
	check_near(shared.fog_height, base.h, 1e-12, "never the shared one")
	pool.free()


func test_adopt_by_id() -> void:
	var pool := _growth_pool()
	var c := pool.sim.motion.position
	var key := Vector2i(900, 900)
	pool._route(FakeGrowthEvents.began(c, 1, 2))
	pool._route(FakeEvents.unloaded(key, "growth"))
	check(pool.rocks.retiring_of("rock_a").size() == 4, "the chunk's four shells retire")
	check(pool.landmarks.retiring().size() == 1, "and its landmark")
	check(pool.zone_lights.retiring().size() == 1 and pool.feedback.retiring().size() == 1, "and its zone's patch and label")
	# The same things come back under a new-size key, at re-expressed poses.
	var e := _chunk_event(c, Vector2i(500, 500), 1.6, true)
	pool._route(e)
	check(pool.rocks.retiring_of("rock_a").is_empty(), "no shell left retiring")
	check(pool.rocks.fresh_of("rock_a").is_empty(), "and none fresh")
	check(pool.landmarks.retiring().is_empty() and pool.zone_lights.retiring().is_empty() and pool.feedback.retiring().is_empty(),
		"the landmark, patch and label are adopted")
	for s: Dictionary in e.shells:
		if s.kind != "shell":
			continue
		var found := pool.rocks.instances_of("rock_a").filter(func(i: Dictionary) -> bool: return i.id == s.id)
		check(found.size() == 1, "%s is live once" % s.id)
		if found.size() == 1:
			var at: Vector3 = pool.rocks.transform * (found[0].transform as Transform3D).origin
			check(PlaneSpace.to_plane(at).distance_to(s.position) < 1e-4, "%s at the event's pose: %s, %s" % [s.id, at, s.position])
			check_near((found[0].transform as Transform3D).basis.get_scale().x, float(s.scale), 1e-4, "%s at the event's scale" % s.id)
	var piece: Node3D = pool.landmarks.pieces().filter(func(p: Node3D) -> bool: return p.name.contains("a_gv"))[0]
	check(PlaneSpace.to_plane(Frames.in_pool(pool, piece)).distance_to((e.anchors[0] as Dictionary).position) < 1e-4, "the landmark at its pose")
	pool.free()


## A growth from 2 to 3: every mouth re-expressed in place and held at k of its depth, a site the new
## chunk keeps adopted at the event's pose, the others sunk away after the settle and freed.
func test_lair_mouths_are_adopted_or_sink_through_a_growth() -> void:
	var trail := _silt_trail(2)
	var center := Vector2(1.0, -2.0)
	trail.add_chunk(Vector2i(0, 0), FakeGrowthEvents.lair_sites(Vector2.ZERO, 1.0))
	trail.position = Vector3(0.5, 0.0, -0.25)   # a rebase moved the container since
	var before := {}
	for piece in trail.mouths():
		before[piece] = trail.transform * piece.position
	trail.apply_growth(center, 1.6)
	check(trail.position == Vector3.ZERO, "the container back at the origin")
	trail.set_depth_k(GrowthBeat.K_FROM)
	for piece: Node3D in before:
		var want := WorldSpace.reexpress_point(before[piece], center, 1.6)
		check(piece.position.distance_to(want) < 1e-5, "%s re-expressed in place: %s, %s" % [piece.name, piece.position, want])
		check(piece.scale.is_equal_approx(Vector3.ONE * 0.75 / 1.6), "and its size")
	trail.size = 3
	trail.retire_chunk(Vector2i(0, 0))
	check_eq(trail.retiring().keys(), ["s_a_post0", "s_a_post1", "s_b_post0", "s_b_post1"], "the chunk's mouths retire")
	var a0: Node3D = trail.retiring().s_a_post0
	var b0: Node3D = trail.retiring().s_b_post0
	var b0_y := b0.position.y
	# The new chunk holds site a again, at its posts re-expressed; site b has gone.
	var kept := FakeGrowthEvents.lair_sites(center, 1.6).slice(0, 1)
	trail.add_chunk(Vector2i(0, 0), kept)
	check_eq(trail.retiring().keys(), ["s_b_post0", "s_b_post1"], "site a adopted")
	check(trail.mouths().has(a0), "the same piece, not a new one")
	var post: Dictionary = kept[0].posts[0]
	check(PlaneSpace.to_plane(a0.position).distance_to(post.position) < 1e-5, "at the event's pose")
	check_near(a0.position.y, SiltTrail.MOUTH_Y_TM * GrowthBeat.K_FROM, 1e-6, "at k of its depth: where it was")
	check(a0.scale.is_equal_approx(Vector3.ONE * 0.75 / 1.6), "sized for size 3")
	check_near(_piece_transparency(a0), 0.0, 1e-6, "drawn whole")
	trail.beat_frame(0.5, 0.8)
	check_near(b0.position.y, b0_y, 1e-6, "the leftovers wait for the settle")
	check_near(_piece_transparency(b0), 0.0, 1e-6, "drawn whole until then")
	trail.settle_growth()
	trail.beat_frame(0.5 + GrowthBeat.RETIRE_S * 0.5, 0.9)
	check(_piece_transparency(b0) > 0.0 and _piece_transparency(b0) < 1.0, "then fade (%.2f)" % _piece_transparency(b0))
	trail.beat_frame(0.5 + GrowthBeat.RETIRE_S, 1.0)
	check_near(b0.position.y, b0_y - GrowthBeat.SINK_TM, 1e-6, "and sink 1.5 tm")
	check_near(_piece_transparency(b0), 1.0, 1e-6, "out of sight")
	trail.end_growth()
	check(trail.retiring().is_empty() and b0.get_parent() == null, "end_growth frees them")
	trail.set_depth_k(1.0)
	check_near(a0.position.y, SiltTrail.MOUTH_Y_TM, 1e-6, "the kept mouth at its own depth after the beat")
	trail.free()


## A growth from 1 to 2: the Lurker's mouths are new; made once the tick settles, in from the veil.
func test_new_lair_mouths_come_in_after_the_settle() -> void:
	var trail := _silt_trail(1)
	var center := Vector2(1.0, -2.0)
	trail.add_chunk(Vector2i(0, 0), FakeGrowthEvents.lair_sites(Vector2.ZERO, 1.0))
	trail.apply_growth(center, 1.6)
	trail.size = 2
	trail.retire_chunk(Vector2i(0, 0))
	check(trail.retiring().is_empty(), "nothing to retire at size 1")
	trail.add_chunk(Vector2i(0, 0), FakeGrowthEvents.lair_sites(center, 1.6))
	check(trail.mouths().is_empty(), "a mouth first seen in the beat waits")
	trail.beat_frame(0.2, 0.7)
	check(trail.mouths().is_empty(), "until the tick settles")
	trail.settle_growth()
	trail.beat_frame(0.3, 0.7)
	var mouths := trail.mouths()
	check_eq(mouths.size(), 4, "then all four are made")
	check(mouths.all(func(p: Node3D) -> bool: return _piece_transparency(p) > 0.9), "behind the veil")
	trail.beat_frame(0.3 + GrowthBeat.PREBLUR_S, 0.9)
	check(mouths.all(func(p: Node3D) -> bool: return _piece_transparency(p) < 1e-6), "in from it after PREBLUR_S")
	trail.end_growth()
	check_eq(trail.mouths().size(), 4, "kept after the beat")
	trail.free()



func test_no_pop_on_growth() -> void:
	var pool := _growth_pool()
	var c := pool.sim.motion.position
	check(pool.sim.debug_spawn_creature("rammer", c + Vector2(-5.0, 3.0), 0.0), "a sleeper-to-be")
	var dropped := pool.sim.carrion.spawn(c + Vector2(4.0, -6.0), "initial")
	Frames.frame(pool)
	var leaving := pool.creature_layer.views()[pool.creature_layer.views().size() - 1]
	for i in 60:
		leaving._process(DT)
	pool._route(FakeGrowthEvents.began(c, 1, 2))
	pool._route({"type": "carrion_expired", "food_id": dropped.id, "position": dropped.position, "reason": "growth"})
	pool._route(FakeEvents.unloaded(Vector2i(900, 900), "growth"))
	# The new chunk lacks one shell, the landmark and the zone: they must sink away, not vanish.
	var e := _chunk_event(c, Vector2i(500, 500), 1.6, false)
	pool._route(e)
	pool._route({"type": "creature_removed", "id": leaving.creature_id, "reason": "growth"})
	pool.sim.creatures.remove(pool.sim.creatures.find(leaving.creature_id), "growth", pool.sim.tick, false)
	pool.sim.drain_events()
	var haze := []
	for i in 30:
		haze.append({"kind": "plant", "look": "plankton", "position": c + Vector2(cos(i), sin(i)) * 3.0})
	pool._route(FakeGrowthEvents.grew(Vector2.ZERO, haze))
	Frames.frame(pool, false)
	var retiring_mmi := pool.rocks.multimesh_of("rock_a__retiring")
	var fresh_mmi := pool.rocks.multimesh_of("rock_a__fresh")
	check(retiring_mmi != null and retiring_mmi.transparency < 1e-6, "frame 0: the leftover shell drawn whole")
	check(fresh_mmi != null and is_equal_approx(fresh_mmi.transparency, 1.0), "frame 0: the new shell not yet in")
	var copies := pool.growth_beat.old_food()
	check_eq(copies.map(func(m: StillInstances) -> String: return m.name), ["OldPlankton", "OldCarrion"], "the old food is copied")
	check(copies.all(func(m: StillInstances) -> bool: return m.transparency == 0.0), "frame 0: drawn whole")
	check_eq(copies[1].transforms.size(), 1, "the dropped carrion in its copy")
	var glitter: StillInstances = pool.growth_beat.glitter()[0]
	check_eq(glitter.transforms.size(), 30, "a glitter sprite per haze entry")
	var deepest := 0.0
	var gone_piece: Node3D = pool.landmarks.retiring().values()[0] if not pool.landmarks.retiring().is_empty() else null
	check(gone_piece != null, "the landmark retires")
	var gone_disc: MeshInstance3D = pool.zone_lights.retiring().values()[0] if not pool.zone_lights.retiring().is_empty() else null
	var gone_label: Label3D = pool.feedback.retiring().values()[0] if not pool.feedback.retiring().is_empty() else null
	var piece_y := gone_piece.position.y if gone_piece != null else 0.0
	check(gone_disc != null and gone_label != null, "the patch and the label retire")
	var t := 0.0
	var at_045 := false
	var by_end := false
	while t < 2.2:
		Frames.frame(pool)
		t = pool.growth_beat.t()
		if not at_045 and t >= 0.45:
			at_045 = true
			check(is_instance_valid(retiring_mmi) and retiring_mmi.transparency < 1.0, "0.45 s: the shell still drawn (%.2f)" % retiring_mmi.transparency)
			check(is_instance_valid(gone_piece) and _piece_transparency(gone_piece) < 1.0, "0.45 s: the landmark still drawn")
			check(is_instance_valid(gone_disc) and gone_disc.transparency < 1.0, "0.45 s: the patch still drawn")
			check(is_instance_valid(gone_label) and gone_label.modulate.a > 0.0, "0.45 s: the label still drawn")
			check(is_instance_valid(leaving) and not leaving.is_queued_for_deletion(), "0.45 s: the creature still drawn")
			check(fresh_mmi.transparency < 1.0 and fresh_mmi.transparency > 0.0, "the new shell coming in (%.2f)" % fresh_mmi.transparency)
			check(copies.all(func(m: StillInstances) -> bool: return not is_instance_valid(m) or m.transparency > 0.0),
				"the old food fading")
			check(_glitter_alpha(glitter) > 0.0, "the glitter drawn")
		if is_instance_valid(glitter) and glitter.position.y < -1.5:
			deepest = minf(deepest, glitter.position.y)
			check(_glitter_alpha(glitter) <= GrowthBeat.GLITTER_ALPHA.y + 1e-6,
				"below -1.5 tm the glitter's alpha is at most 0.25 (%.3f at %.2f tm)" % [_glitter_alpha(glitter), glitter.position.y])
		if not by_end and t >= GrowthBeat.RETIRE_S + 0.1:
			by_end = true
			check(not is_instance_valid(retiring_mmi) or retiring_mmi.transparency >= 1.0 - 1e-6, "1.3 s: the shell gone")
			check(not is_instance_valid(gone_piece) or _piece_transparency(gone_piece) >= 1.0 - 1e-6, "1.3 s: the landmark gone")
			check(is_instance_valid(gone_piece) and is_equal_approx(gone_piece.position.y, piece_y - GrowthBeat.SINK_TM),
				"having sunk 1.5 tm")
			check(not is_instance_valid(gone_disc) or gone_disc.transparency >= 1.0 - 1e-6, "1.3 s: the patch gone")
			check(not is_instance_valid(gone_label) or gone_label.modulate.a <= 1e-6, "1.3 s: the label gone")
			check(not is_instance_valid(leaving) or leaving.is_queued_for_deletion(), "1.3 s: the creature gone")
			check(pool.growth_beat.old_food().is_empty(), "1.3 s: the old food's copies gone")
	check(at_045 and by_end, "the beat ran past both checks")
	check(deepest < -2.5, "the glitter sank (%.2f tm)" % deepest)
	check(pool.rocks.multimesh_of("rock_a__retiring") == null and pool.rocks.multimesh_of("rock_a__fresh") == null,
		"after the beat: no retiring or fresh lists left")
	check(pool.landmarks.retiring().is_empty() and pool.zone_lights.retiring().is_empty() and pool.feedback.retiring().is_empty(),
		"and nothing else retiring")
	pool.free()


func test_reduce_motion() -> void:
	var pool := _growth_pool()
	pool.set_reduce_motion(true)
	pool._route(FakeGrowthEvents.began(pool.sim.motion.position, 1, 2))
	pool._route(FakeGrowthEvents.grew(Vector2.ZERO))
	Frames.frame(pool, false)
	var beat := pool.growth_beat
	check(beat.reduced(), "the beat knows the setting")
	check_near(pool.camera.shown_distance(), pool.camera.distance, 1e-9, "frame 0: the camera at its zoom (no dolly)")
	check(not pool.camera.dolly_active(), "and none runs")
	check_near(pool.depth_k(), 1.0, 1e-12, "k is 1")
	check_near(beat.swell(), 0.8125, 1e-9, "the swell starts half way")
	check_near(beat.stretch(), 0.5, 1e-9, "Stretch is halved")
	var fade := pool.fade_rect()
	check(fade.visible, "headless, %Fade dips instead of a still")
	while beat.t() < 0.4 - 1e-9:
		Frames.frame(pool)
	check_near(fade.modulate.a, GrowthBeat.FADE_DIP_ALPHA, 0.02, "to 0.6 at 0.4 s")
	while beat.t() < 0.85:
		Frames.frame(pool)
	check(not fade.visible, "and gone after 0.8 s")
	# With a window the last frame is kept as a still that dissolves over 0.8 s.
	beat.cancel()
	pool._route(FakeGrowthEvents.began(pool.sim.motion.position, 1, 2))
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	beat._show_still(img)
	Frames.frame(pool, false)
	check_near(beat.dissolve_alpha(), 1.0, 1e-9, "the still covers frame 0")
	while beat.t() < 0.4 - 1e-9:
		Frames.frame(pool)
	check_near(beat.dissolve_alpha(), 0.5, 0.02, "half dissolved at 0.4 s")
	while beat.t() < 0.85:
		Frames.frame(pool)
	check(beat.dissolve_alpha() == 0.0, "gone after 0.8 s")
	pool.free()


func test_cell_offset_reaches_the_settled_point() -> void:
	var pool := _growth_pool()
	var settled := Vector2(1.5, -0.75)
	pool._route(FakeGrowthEvents.began(pool.sim.motion.position, 1, 2))
	pool._route(FakeGrowthEvents.grew(settled))
	Frames.frame(pool, false)
	check(pool.cell_view.growth_pose().offset.is_equal_approx(-settled), "frame 0: drawn at the old point (%s)" % pool.cell_view.growth_pose().offset)
	check_near(pool.cell_view.growth_pose().swell, 0.625, 1e-9, "at k of its size")
	while pool.growth_beat.t() < GrowthBeat.SWELL_S:
		Frames.frame(pool)
	check(pool.cell_view.growth_pose().offset.is_zero_approx(), "at the settled point from 0.7 s")
	check_near(pool.cell_view.growth_pose().swell, 1.0, 1e-9, "whole")
	check_near(pool.cell_view.growth_pose().stretch, 0.0, 1e-9, "unstretched")
	pool.free()


func test_beat_is_frame_rate_independent() -> void:
	var seen := []
	for fps: float in [30.0, 144.0]:
		var pool := _growth_pool()
		var c := pool.sim.motion.position
		pool._route(FakeGrowthEvents.began(c, 1, 2))
		pool._route(FakeGrowthEvents.grew(Vector2(1.0, 0.0), [{"kind": "plant", "look": "plankton", "position": c + Vector2.ONE}]))
		var start := 100.0
		var dt: float = 1.0 / fps
		var frames: int = roundi(fps)
		for i in frames + 1:
			pool.growth_beat.advance(start + i * dt)
			pool.camera.follow(pool.camera.focus, Vector2.ZERO, dt)
		seen.append({"t": pool.growth_beat.t(), "k": pool.depth_k(), "swell": pool.growth_beat.swell(),
			"distance": pool.camera.shown_distance(), "offset": pool.growth_beat.cell_offset(),
			"glitter_y": pool.growth_beat.glitter()[0].position.y})
		pool.free()
	check_near(seen[0].t, 1.0, 1e-9, "both at beat second 1.0")
	check(seen[0].glitter_y < -2.0, "the glitter well on its way down (%.3f tm)" % seen[0].glitter_y)
	for key in ["t", "k", "swell", "distance", "glitter_y"]:
		check_near(seen[0][key], seen[1][key], 1e-4, "%s agrees at 30 and 144 fps" % key)
	check((seen[0].offset as Vector2).distance_to(seen[1].offset) < 1e-4, "the offset agrees")


## On T2's real growth tick (S2G24, V-10): frame 0 draws the new plankton as algae balls at almost
## nothing, the carrion kept by the tick at its new radius (0.625 of what it was, the same on screen),
## and every old plankton item from a copy exactly where frame A drew it; the copy fades by 0.6 s,
## and the glitter sinks out of the old plankton and is gone by 6 s.
func test_new_plankton_grows_in() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true))
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	var kept := sim.carrion.spawn(sim.motion.position + Vector2(3.0, 1.0), "rammer")
	for i in 40:
		Frames.frame(pool)
	check_eq(pool.plankton_view.look, "plankton", "size 1: plankton")
	var plants_a := pool.plankton_view.snapshot()
	var meat_a: Transform3D = pool.carrion_view.snapshot()[kept.id]
	check(plants_a.size() >= 5, "frame A draws the plankton round the cell (%d)" % plants_a.size())
	var meat_px_a := Frames.project(pool.camera, meat_a.origin)
	var pixels_a := []
	for t: Transform3D in plants_a.values():
		pixels_a.append(Frames.project(pool.camera, t.origin))
	var g := sim.growth
	g.meter = g.ring(sim.size())
	g.full_since = sim.tick
	g.due = true
	Frames.frame(pool)
	check_eq(sim.size(), 2, "the tick grew the world")
	check(pool.plankton_view.look == "algae_ball" and pool.plankton_view.multimesh.mesh == FoodView.look_mesh("algae_ball"),
		"frame 0: the plants are algae balls")
	var plants_0 := pool.plankton_view.snapshot()
	check(not plants_0.is_empty(), "the new zones are filled")
	var biggest := 0.0
	for t: Transform3D in plants_0.values():
		biggest = maxf(biggest, t.basis.get_scale().x)
	check(biggest <= 0.05, "every new plant item draws at scale <= 0.05 at frame 0 (%.3f)" % biggest)
	var meat_0: Transform3D = pool.carrion_view.snapshot()[kept.id]
	check_near(meat_0.basis.get_scale().x / meat_a.basis.get_scale().x, 0.625, 1e-4, "the kept carrion draws at 0.625")
	var moved := Frames.project(pool.camera, meat_0.origin).distance_to(meat_px_a)
	check(moved <= 0.5, "and where frame A drew it on screen (%.3f px)" % moved)
	var copy: StillInstances = pool.growth_beat.old_food()[0]
	check_eq(copy.transforms.size(), plants_a.size(), "every old plant item is in the copy")
	var worst := 0.0
	var base := Frames.in_pool(pool, copy)
	for i in copy.transforms.size():
		worst = maxf(worst, Frames.project(pool.camera, base + copy.transforms[i].origin).distance_to(pixels_a[i]))
	check(worst <= 0.5, "frame 0: the old plankton is on screen where frame A drew it (%.3f px)" % worst)
	var glitter: StillInstances = pool.growth_beat.glitter()[0]
	check_eq(glitter.transforms.size(), mini(plants_a.size(), GrowthBeat.GLITTER_MAX), "a glitter sprite per old plant item")
	check_near(_glitter_alpha(glitter), 0.0, 1e-9, "the glitter comes in from nothing")
	var t0: float = pool.growth_beat._t0
	pool.growth_beat.advance(t0 + 0.3)
	check(is_instance_valid(copy) and copy.transparency > 0.0 and copy.transparency < 1.0, "0.3 s: the copy fading")
	pool.growth_beat.advance(t0 + GrowthBeat.OLD_FOOD_FADE_S)
	check(pool.growth_beat.old_food().is_empty(), "0.6 s: the copy gone")
	pool.growth_beat.advance(t0 + GrowthBeat.GLITTER_SINK_S)
	check_near(glitter.position.y, GrowthBeat.GLITTER_DEPTH_TM, 1e-6, "2.0 s: the glitter at -3 tm")
	check_near(_glitter_alpha(glitter), GrowthBeat.GLITTER_ALPHA.y, 1e-6, "at 0.25")
	pool.growth_beat.advance(t0 + 5.0)
	check(_glitter_alpha(glitter) > 0.0 and _glitter_alpha(glitter) < GrowthBeat.GLITTER_ALPHA.y, "5.0 s: fading")
	pool.growth_beat.advance(t0 + GrowthBeat.GLITTER_GONE_S)
	check(pool.growth_beat.glitter().is_empty() and pool.growth_beat.fx.get_child_count() == 0, "6.0 s: gone")
	check(not pool.growth_beat.running(), "and the beat is idle")
	pool.free()


## The glitter (V-22): a sprite per plant haze entry, the nearest GLITTER_MAX to the cell, the old
## item's drawn diameter across (in new tm, over its sprite's span), and one per creature turned to
## haze in its species' sprite; each where the thing was on screen.
func test_haze_leaves_glitter_where_it_was() -> void:
	var pool := _growth_pool()
	var c := pool.sim.motion.position
	var view := pool.creature_layer.views()[0]
	var body := PlaneSpace.to_plane(view.position)
	var near := [c + Vector2(2.0, 1.0), c + Vector2(-3.0, 4.0), c + Vector2(0.5, -6.0)]
	var haze := []
	for p in near:
		haze.append({"kind": "plant", "look": "plankton", "position": p})
	for i in GrowthBeat.GLITTER_MAX:
		haze.append({"kind": "plant", "look": "plankton", "position": c + Vector2.from_angle(i) * 20.0})
	for i in 30:
		haze.append({"kind": "plant", "look": "plankton", "position": c + Vector2.from_angle(i) * 45.0})
	haze.append({"kind": "creature", "look": "rammer", "position": body})
	var was := {}
	for p in near + [body]:
		was[p] = Frames.project(pool.camera, PlaneSpace.to_world(p))
	pool._route(FakeGrowthEvents.began(c, 1, 2))
	pool._route(FakeGrowthEvents.converted(view.creature_id, "rammer", "haze", body, 0.4))
	pool._route(FakeGrowthEvents.grew(Vector2.ZERO, haze))
	var by_name := {}
	for g in pool.growth_beat.glitter():
		by_name[String(g.name)] = g
	check_eq(by_name.keys(), ["Glitter", "Glitter_rammer"], "the plants' glitter and the haze creature's")
	var plants: StillInstances = by_name.Glitter
	check_eq(plants.transforms.size(), GrowthBeat.GLITTER_MAX, "at most 400 plant sprites")
	var farthest := 0.0
	for t in plants.transforms:
		farthest = maxf(farthest, Vector2(t.origin.x, t.origin.z).length())
	check(farthest < 30.0 / 1.6, "the nearest ones (%.1f tm out at most)" % farthest)
	check_near(plants.transforms[0].basis.get_scale().x, 2.0 * 0.18 / 1.6 / 0.773, 1e-5, "a plankton's old diameter across")
	var creature: StillInstances = by_name.Glitter_rammer
	check_near(creature.transforms[0].basis.get_scale().x, 2.0 * 0.4 / 0.5, 1e-5, "the rammer's old diameter across")
	var base := Frames.in_pool(pool, plants)
	for i in near.size():
		var px := Frames.project(pool.camera, base + plants.transforms[i].origin)
		check(px.distance_to(was[near[i]]) < 0.5, "plant %d where it was on screen (%.3f px)" % [i, px.distance_to(was[near[i]])])
	var at := Frames.project(pool.camera, Frames.in_pool(pool, creature) + creature.transforms[0].origin)
	check(at.distance_to(was[body]) < 0.5, "the rammer's where it was (%.3f px)" % at.distance_to(was[body]))
	pool.free()


## The glitter sizes each sprite by its body span (s2-view 0.9): each HAZE_SPANS value is its PNG's
## alpha >= 0.1 box, larger side over the texture's, to a pixel; every haze sprite named is there.
func test_haze_spans_match_the_sprites() -> void:
	var named := {}
	for path in GrowthBeat.FOOD_HAZE.values() + GrowthBeat.SPECIES_HAZE.values():
		named[path.get_file()] = true
		check(ResourceLoader.exists(path), "%s exists" % path)
	for file in named:
		check(GrowthBeat.HAZE_SPANS.has(file), "%s has a span" % file)
	for file: String in GrowthBeat.HAZE_SPANS:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/export/ambience/" + file))
		if img == null:
			check(false, "%s loads" % file)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var data := img.get_data()
		var w := img.get_width()
		var lo := Vector2i(w, img.get_height())
		var hi := Vector2i(-1, -1)
		for y in img.get_height():
			for x in w:
				if data[(y * w + x) * 4 + 3] >= 26:   # alpha >= 0.1
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		var span := maxf(float(hi.x + 1 - lo.x) / w, float(hi.y + 1 - lo.y) / img.get_height())
		check(absf(span - float(GrowthBeat.HAZE_SPANS[file])) <= 1.0 / w, "%s spans %.3f (table %.3f)" % [file, span, GrowthBeat.HAZE_SPANS[file]])


func test_now_food_comes_with_the_relations() -> void:
	var pool := _growth_pool()
	var audio := CueLog.new()
	pool.audio = audio
	var c := pool.sim.motion.position
	for p in [Vector2(3.0, 0.0), Vector2(-4.0, 1.0), Vector2(0.0, 5.0), Vector2(6.0, -2.0)]:
		check(pool.sim.debug_spawn_creature("rammer", c + p, 0.0), "a rammer at %s" % p)
	Frames.frame(pool)
	pool._route(FakeGrowthEvents.began(c, 1, 2))
	pool._route(FakeGrowthEvents.grew(Vector2.ZERO))
	var labels := func() -> int:
		return pool.creature_layer.views().filter(func(v: CreatureView) -> bool: return v.now_food_label() != null).size()
	while true:
		Frames.frame(pool)
		if pool.growth_beat.t() >= GrowthBeat.RELATIONS_S:
			break
		check(labels.call() == 0, "no label before 2.0 s (%.2f s)" % pool.growth_beat.t())
	var rimmed := pool.creature_layer.views().filter(func(v: CreatureView) -> bool: return v.rimmed()).size()
	check(rimmed >= 4, "the rammers are rimmed at size 2 (%d)" % rimmed)
	check_eq(labels.call(), GrowthBeat.NOW_FOOD_MAX, "then three labels")
	for v in pool.creature_layer.views():
		check(v.now_food_label() == null or v.rimmed(), "only over rimmed views")
	check_eq(audio.cues.count("now_food"), 1, "the cue once")
	while pool.growth_beat.t() < 5.0:
		Frames.frame(pool)
	check(labels.call() == 0, "gone at 5.0 s")
	check_eq(audio.cues.count("now_food"), 1, "still once")
	pool.free()
	audio.free()


func test_a_respawn_ends_the_beat_at_once() -> void:
	var pool := _growth_pool()
	pool._route(FakeGrowthEvents.began(pool.sim.motion.position, 1, 2))
	pool._route(FakeGrowthEvents.grew(Vector2(1.0, 1.0)))
	for i in 20:
		Frames.frame(pool)
	check(pool.growth_beat.running() and pool.camera.dolly_active(), "mid-beat")
	pool._route({"type": "respawned", "grace_s": 3.0, "teleport": false})
	check(not pool.growth_beat.running(), "a respawn ends it")
	check_near(pool.depth_k(), 1.0, 1e-12, "k back to 1")
	check(not pool.camera.dolly_active() and is_equal_approx(pool.camera.shown_distance(), pool.camera.distance), "the camera at its zoom")
	check(pool.cell_view.growth_pose().offset.is_zero_approx() and pool.cell_view.growth_pose().swell == 1.0, "the cell whole, where the sim says")
	check(pool.rocks.multimesh_of("rock_a__retiring") == null, "nothing left retiring")
	pool.free()


# --- helpers ---

## An endless pool with a still cell, quiet cues, a rammer beside the cell and a chunk (900, 900) in
## view holding two shells, a landmark and a sunlit zone, so every container has something to draw.
## A glitter's alpha now.
static func _glitter_alpha(glitter: StillInstances) -> float:
	return (glitter.material_override as StandardMaterial3D).albedo_color.a


func _growth_pool() -> PoolScene:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(7.0, -4.0), PI), "a rammer")
	pool.creature_layer.sync(1.0)
	pool._route(_chunk_event(sim.motion.position, Vector2i(900, 900), 1.0, true))
	return pool


## The test chunk round `c`: four shells (sv1 to sv4), a landmark (its collider and anchor) and a sunlit
## zone, re-expressed round `c` by 1 / `factor` (1: as first loaded). `all` false leaves out sv2, the
## landmark and the zone, and adds a new shell sv_new.
static func _chunk_event(c: Vector2, key: Vector2i, factor: float, all: bool) -> Dictionary:
	var at := func(offset: Vector2) -> Vector2:
		return c + offset if factor == 1.0 else offset / factor
	var s := 1.0 / factor
	var shells := [FakeEvents.shell("sv1", at.call(Vector2(5.0, 3.0)), 0.6 * s, "rock_a", 30.0, 1.2 * s),
		FakeEvents.shell("sv3", at.call(Vector2(-3.0, -5.0)), 0.6 * s, "rock_a", 120.0, 0.8 * s),
		FakeEvents.shell("sv4", at.call(Vector2(1.0, 7.0)), 0.6 * s, "rock_a", 200.0, s)]
	var zones := []
	var anchors := []
	if all:
		shells.append(FakeEvents.shell("sv2", at.call(Vector2(-6.0, -2.0)), 0.6 * s, "rock_a", 0.0, s))
		shells.append(FakeEvents.shell("lm_gv", at.call(Vector2(10.0, -5.0)), 2.0 * s, "landmark_great_shell", 90.0, 0.95 * s, "#D6E0F5", "landmark"))
		anchors.append(FakeEvents.anchor("a_gv", at.call(Vector2(10.0, -5.0)), "landmark_great_shell", "frosted"))
		zones.append(FakeEvents.zone("z_gv", at.call(Vector2(3.0, 6.0)), 4.0 * s, "sunlit"))
	else:
		shells.append(FakeEvents.shell("sv_new", at.call(Vector2(-2.0, 4.0)), 0.6 * s, "rock_a", 0.0, s))
	return FakeEvents.loaded(key, shells, zones, anchors)


## The pixels of every point the containers draw (shells, landmark pieces, patches, labels, the
## beat's effects, the Backdrop) and of `leaf`; the cell, the creatures, the column and the ghosts
## are placed from the sim (the ghosts from its frame) each frame, which a faked growth does not
## move (tests/test_ghosts.gd checks the ghosts across a growth).
func _container_pixels(pool: PoolScene, leaf: Node3D) -> Dictionary:
	var out := {}
	var points := Frames.tracked_points(pool)
	points["leaf"] = Frames.in_pool(pool, leaf)
	points["eat burst"] = Frames.in_pool(pool, pool.world_fx.get_node("EatFx"))
	for key: String in points:
		if key == "cell" or key == "column" or key.begins_with("creature ") or key.begins_with("ghost "):
			continue
		out[key] = Frames.project(pool.camera, points[key])
	return out


## How far a landmark piece is veiled (its first mesh's transparency).
static func _piece_transparency(piece: Node3D) -> float:
	var meshes := piece.find_children("*", "GeometryInstance3D", true, false)
	return (meshes[0] as GeometryInstance3D).transparency if not meshes.is_empty() else 1.0


## A view of `id` at `q`, outside the tree, built as the layer builds one.
func _view(id: String, q: float) -> CreatureView:
	var view: CreatureView = VIEW_SCENE.instantiate()
	FakeEvents.ready_tree(view)
	view.build(_species, id, _catalog, "c_" + id, q)
	return view


## Runs the view's own animation for `seconds` at 60 fps.
func _run(view: CreatureView, seconds: float) -> void:
	for i in roundi(seconds / DT):
		view._process(DT)


func _cell(body: String) -> Phenotype:
	var founded := Lineage.found(7, "test", _catalog, body)
	return Phenotype.derive(founded.save.genome, _catalog)


func _body_scene(id: String) -> PackedScene:
	return CreatureView.BODY_SCENES.get(str(_species.species[id].get("body_asset", "")))


## The colours of the view's threat-coloured surfaces now: material name -> albedo.
func _ink_surfaces(view: CreatureView) -> Dictionary:
	var out := {}
	for slot in view._ink_slots:
		var material: BaseMaterial3D = slot.material
		out[material.resource_name] = material.albedo_color
	return out


## A body scene's node names and material names, each sorted.
func _contract(scene: PackedScene) -> Dictionary:
	var root := scene.instantiate()
	var nodes := PackedStringArray()
	var materials := PackedStringArray()
	for node in root.find_children("*", "", true, false):
		nodes.append(str(node.name))
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			for i in mesh_node.mesh.get_surface_count():
				var material := mesh_node.mesh.surface_get_material(i)
				if material != null and not material.resource_name in materials:
					materials.append(material.resource_name)
	root.free()
	nodes.sort()
	materials.sort()
	return {"nodes": nodes, "materials": materials}


## A silt trail on the shipped species at `size`, outside the tree.
func _silt_trail(size: int) -> SiltTrail:
	var trail := SiltTrail.new()
	trail.setup(_species, size)
	return trail
