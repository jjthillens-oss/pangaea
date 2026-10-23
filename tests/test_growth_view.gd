extends TestCase
## The growth's look on the creatures (S2G23, S2G40; s2-view 5 and 10.1): the two new bodies keep
## the M1 body contract, a creature is drawn at its q, its threat ink shows exactly while it can
## attack the cell and its green rim exactly while the cell can eat it, remnants go limp, morsels lie
## where their carrion items are, views removed by a growth fade where they were, and "Now food"
## goes over at most three rimmed bodies on screen.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")
const BODIES: PackedStringArray = ["grazer", "hunter", "omnivore"]
## The new bodies and the M1 bodies whose contract (node names, material names) they keep.
const BODY_PAIRS := {"creature_lurker_body": "creature_ambush_body", "creature_elder_rammer_body": "creature_rammer_body"}
const THREAT_INK := Color("#D9466B")
const DT := 1.0 / 60.0

var _species: SpeciesCatalog
var _catalog: PartCatalog


func before_each() -> void:
	if _species == null:
		_species = SpeciesCatalog.load_from()
		_catalog = PartCatalog.load_from()


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


# --- helpers ---

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
