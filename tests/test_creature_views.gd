extends TestCase
## S3's creature views (docs/s3/s3-view.md 8; S3G32 F part): the four band-1 bodies, their eyes and
## their ink at sizes 3 and 4, the veil's threads (fitted in the sim's capsule, inked, flashed) and the
## morsel sites' items (s3-view 9.1: drawn once, by the layer).

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")
const SETTINGS_PATH := "user://test_creature_views/settings.cfg"
const THREAT_INK := Color("#D9466B")
const DT := 1.0 / 60.0
## Species, the body family whose pose nodes it carries, and its body material (C3V-13).
const S3_BODIES := {
	"veil": ["ambush", "res://assets/export/M_VeilBody.tres"],
	"warden": ["territorial", "res://assets/export/M_WardenBody.tres"],
	"deep_lurker": ["ambush", "res://assets/export/M_DeepLurkerBody.tres"],
	"elder_warden": ["territorial", "res://assets/export/M_ElderWardenBody.tres"],
}

var _species: SpeciesCatalog
var _catalog: PartCatalog


func before_each() -> void:
	if _species == null:
		_species = SpeciesCatalog.load_from()
		_catalog = PartCatalog.load_from()
	SettingsService.set_shared(SettingsService.new(SETTINGS_PATH))


func after_each() -> void:
	SettingsService.set_shared(null)


func test_four_bodies_and_their_contracts() -> void:
	for id in S3_BODIES:
		var asset := str(_species.species[id].body_asset)
		check(CreatureView.BODY_SCENES.has(asset), "%s: %s is a body the view can draw" % [id, asset])
		var view := _view(id, 1.0)
		var body := view._model.get_node_or_null(^"Body")
		check(body != null, "%s: the body is built" % id)
		if body == null:
			view.free()
			continue
		var family: String = S3_BODIES[id][0]
		if family == "territorial":
			check(view._hood != null, "%s: the hood a territorial puff raises" % id)
			check(view._brow == null, "%s: no ambush brow" % id)
		else:
			check(view._brow != null, "%s: the brow an ambush coil lowers" % id)
			check(view._hood == null, "%s: no rammer hood" % id)
		var mesh := body.get_node_or_null(CreatureView.BODY_MESH_PATH) as MeshInstance3D
		check(mesh != null, "%s: the body mesh" % id)
		if mesh != null:
			var material := mesh.get_active_material(0)
			check_eq(material.resource_path if material != null else "", S3_BODIES[id][1], "%s: its own body material" % id)
		view.free()


func test_eye_rest_per_body() -> void:
	var deep := _view("deep_lurker", 1.0)
	check(deep._eye_material != null, "the Deep lurker's eyes glow")
	check_near(deep._eye_material.emission_energy_multiplier, CreatureView.EYE_GLOW_IDLE / 0.7, 1e-6,
		"the Deep lurker idles at 0.2 over its rest 0.7")
	deep.free()
	var ambush := _view("ambush_hunter", 1.0)
	check_near(ambush._eye_material.emission_energy_multiplier, CreatureView.EYE_GLOW_IDLE / 0.4, 1e-6,
		"the ambush hunter keeps M1's rest 0.4")
	ambush.free()
	var veil := _view("veil", 1.0)
	check(veil._eye_material == null, "the veil's eyes are not emissive, so nothing drives them")
	veil._apply_pose(CreatureView.pose(CreatureBrain.AMBUSH, "attack/tell", 1.0))
	veil.free()


func test_ink_at_sizes_3_and_4() -> void:
	var cell := _cell("omnivore")
	var want := {
		"warden": {3: true, 4: false},
		"elder_warden": {4: true},
		"deep_lurker": {4: true},
		"lurker": {3: false, 4: false},
		"elder_rammer": {3: false, 4: false},
	}
	for id in want:
		for n: int in want[id]:
			check(_species.live_at(id, n), "%s lives at size %d" % [id, n])
			var q := _species.q_of(id, n)
			var view := _view(id, 1.0)
			view.set_q(q)
			var r := CreatureLayer.relation_of(_species, id, q, view.radius, n, cell)
			view.set_relation(r.can_attack, r.rimmed, 1.0)
			_run(view, 1.05)
			var attacks: bool = want[id][n]
			var tag := "%s at size %d" % [id, n]
			check_eq(r.can_attack, attacks, "%s: attacks" % tag)
			check_near(view.ink, 1.0 if attacks else 0.0, 1e-9, "%s: ink after the 1 s fade" % tag)
			var crest := _crest(view)
			if crest != null:
				var colour := THREAT_INK if attacks else CreatureView.NEUTRAL_CREST
				check(crest.albedo_color.is_equal_approx(colour), "%s: M_Threat %s, want %s" % [
					tag, crest.albedo_color.to_html(), colour.to_html()])
			elif id in ["warden", "elder_warden"]:
				check(false, "%s: the Warden's crest is M_Threat" % tag)
			view.free()


func test_threads_fit_the_capsule() -> void:
	var vertices: PackedVector3Array = VeilThreadsView.unit_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size() > 0, "the rig's vertices")
	var widest := 0.0
	var swayed := 0.0
	var z_span := Vector2(INF, -INF)
	for v in vertices:
		widest = maxf(widest, absf(v.x))
		# The shader sways x by up to SWAY times COLOR.r, which the remap made z.
		swayed = maxf(swayed, absf(v.x) + VeilThreadsView.SWAY * v.z)
		z_span = Vector2(minf(z_span.x, v.z), maxf(z_span.y, v.z))
	check(widest <= VeilThreadsView.FIT + 1e-6, "|x| %.4f <= FIT" % widest)
	check(z_span.x >= -1e-6 and z_span.y <= 1.0 + 1e-6, "z in [0, 1]: [%.4f, %.4f]" % [z_span.x, z_span.y])
	check(swayed <= 1.0 + 1e-6, "with the full sway |x| %.4f <= 1" % swayed)
	var rng := RandomNumberGenerator.new()
	rng.seed = 32
	var threads := VeilThreadsView.new()
	var worst := -INF
	for i in 50:
		var a := Vector3(rng.randf_range(-3.0, 3.0), VeilThreadsView.THREAD_Y, rng.randf_range(-3.0, 3.0))
		var along := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 3.0)
		var b := a + Vector3(along.x, 0.0, along.y)
		var r := rng.randf_range(0.05, 1.2)
		threads.set_capsule(a, b, r)
		var rig := (threads.get_node(^"Rig") as Node3D).transform
		for v in vertices:
			for sway in [-VeilThreadsView.SWAY, VeilThreadsView.SWAY]:
				var w := rig * Vector3(v.x + sway * v.z, 0.0, v.z)
				var d := Geometry3D.get_closest_point_to_segment(w, a, b).distance_to(w)
				worst = maxf(worst, d - r)
	check(worst <= 1e-4, "every swayed vertex of 50 capsules inside its radius (worst %.5f over)" % worst)
	threads.free()


func test_thread_ink_and_neutral() -> void:
	var colors := VeilThreadsView.ink_colors()
	var ink_albedo := (load(VeilThreadsView.INK_MATERIAL) as StandardMaterial3D).albedo_color
	var neutral_albedo := (load(VeilThreadsView.NEUTRAL_MATERIAL) as StandardMaterial3D).albedo_color
	check(colors.ink == ink_albedo and colors.neutral == neutral_albedo, "the colours are art's two materials")
	var threads := VeilThreadsView.new()
	threads.set_ink(true)
	check(_thread_color(threads.rig_material()).is_equal_approx(ink_albedo), "inked threads: M_VeilThreadInk")
	check(_thread_color(threads.outline_material()).is_equal_approx(ink_albedo), "and the outline")
	threads.set_ink(false, VeilThreadsView.INK_FADE_S)
	threads.step(0.5)
	check(not _thread_color(threads.rig_material()).is_equal_approx(neutral_albedo), "half way: still fading")
	threads.step(0.5)
	check(_thread_color(threads.rig_material()).is_equal_approx(neutral_albedo), "after 1 s: M_VeilThreadNeutral")
	check(_thread_color(threads.outline_material()).is_equal_approx(neutral_albedo), "and the outline")
	check(threads.shown_color().is_equal_approx(neutral_albedo), "shown_color agrees")
	threads.free()
	# S3G32 (spine): a veil's threads ink at its entry size, q = 1, and never below it.
	var cell := _cell("omnivore")
	for n: int in [3, 4]:
		var q := _species.q_of("veil", n)
		var view := _view("veil", q)
		check(view.threads != null, "a veil has threads")
		var r := CreatureLayer.relation_of(_species, "veil", q, view.radius, n, cell)
		view.set_relation(r.can_attack, r.rimmed, 1.0)
		_run(view, 1.05)
		var stings := n == 3
		check_eq(q == 1.0, stings, "the veil is at its entry size only at 3 (q %.3f at %d)" % [q, n])
		check_near(view.threads.ink, 1.0 if stings else 0.0, 1e-9, "threads at size %d after the fade" % n)
		check(view.rim == 0.0, "no rim on a veil at size %d" % n)
		view.free()
	var warden := _view("warden", 1.0)
	check(warden.threads == null, "only hazards have threads")
	warden.free()


func test_sting_flashes_threads() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var layer := pool.creature_layer
	sim.creatures.set_size(3)
	sim.world.size = 3
	check(sim.debug_spawn_creature("veil", sim.motion.position + Vector2(5.0, 0.0), PI), "a veil at size 3")
	layer.sync(1.0)
	var veil: CreatureView = null
	for view in layer.views():
		if view.species_id == "veil":
			veil = view
	check(veil != null and veil.threads != null, "drawn with threads")
	if veil == null or veil.threads == null:
		pool.free()
		return
	var cap := veil.threads.capsule()
	var cfg: Dictionary = sim.creatures.find(veil.creature_id).brain.cfg.threads
	check(not cap.is_empty(), "show_brain set the capsule")
	if not cap.is_empty():
		check_near((cap.b - cap.a).length(), float(cfg.length_m), 1e-5, "its length is the sim's")
		check_near(float(cap.r), float(cfg.radius_m), 1e-9, "its radius is the sim's")
		check_near(Vector2(cap.a.x, cap.a.z).length(), veil.radius, 1e-5, "it starts at the body's rim")
		check_near(float(cap.a.y), VeilThreadsView.THREAD_Y, 1e-9, "on the thread plane")
	layer.on_event({"type": "hit", "attacker": veil.creature_id, "target": CreatureField.PLAYER_ID, "kind": "bite"})
	check_eq(veil.threads.flash_share, 0.0, "a hit of another kind does not flash the threads")
	layer.on_event({"type": "hit", "attacker": veil.creature_id, "target": CreatureField.PLAYER_ID, "kind": "sting"})
	check_eq(veil.threads.flash_share, 1.0, "a sting flashes them at once")
	check_near(float(veil.threads.rig_material().get_shader_parameter("flash")), 1.0, 1e-9, "in the shader")
	_run(veil, VeilThreadsView.FLASH_S * 0.5)
	check(veil.threads.flash_share > 0.0 and veil.threads.flash_share < 1.0, "fading")
	_run(veil, VeilThreadsView.FLASH_S * 0.5 + DT)
	check_eq(veil.threads.flash_share, 0.0, "and gone after %.2f s" % VeilThreadsView.FLASH_S)
	pool.free()


func test_veil_has_no_lane_or_marker() -> void:
	var view := _view("veil", 1.0)
	view.show_lane({"origin": Vector2.ZERO, "heading": 0.0, "length": 3.0, "half_width": 0.5})
	check(not view._lane_on and not view._lane.visible, "no strike lane")
	view.show_marker()
	_run(view, DT)
	check(not view._marker.visible, "no notice mark")
	view.free()


func test_morsel_site_items_drawn_once() -> void:
	var pool := _site_pool("omnivore")
	var sim := pool.sim
	var a := _site_item(sim, "ambush_hunter", Vector2(3.0, 0.0))
	var b := _site_item(sim, "rammer", Vector2(-3.0, 1.0))
	FakeEvents.frame(pool)
	var ids := pool.creature_layer.morsel_site_ids()
	check(a.id in ids and b.id in ids and ids.size() == 2, "both items drawn by the layer: %s" % [ids])
	for species in ["ambush_hunter", "rammer"]:
		var mmi := pool.creature_layer.get_node_or_null("MorselSites/" + species) as MultiMeshInstance3D
		check(mmi != null and mmi.multimesh.instance_count == 1, "one %s instance in MorselSites" % species)
		if mmi != null:
			check(mmi.multimesh.mesh == pool.creature_layer.morsel_mesh(species), "its baked body")
			check(mmi.material_override == CreatureLayer.MORSEL_MATERIAL, "in M_Morsel")
	check(pool.creature_layer.morsel_mesh("rammer").get_surface_count() == 1, "the body and parts in one surface")
	pool.carrion_view.sync(sim.carrion.items, sim.now())
	check_eq(pool.carrion_view.shown_count(), _plain_carrion(sim), "the FoodView draws none of them")
	check(pool.creature_layer.morsel_mesh_for(a.id) == pool.creature_layer.morsel_mesh("ambush_hunter"),
		"the swallow ghost's mesh is the body")
	check(pool.creature_layer.morsel_mesh_for("cr_none") == null, "and null for any other item")
	pool.free()


func test_morsel_site_rim_with_a_jaw() -> void:
	for body in ["omnivore", "grazer"]:
		var pool := _site_pool(body)
		_site_item(pool.sim, "rammer", Vector2(3.0, 0.0))
		FakeEvents.frame(pool)
		var rim := pool.creature_layer.get_node_or_null("MorselSites/rammer__rim") as MultiMeshInstance3D
		var drawn := rim != null and rim.multimesh.instance_count == 1
		check_eq(drawn, pool.sim.phenotype.can_eat("meat"), "%s: a rim only with a jaw for meat" % body)
		if drawn:
			check((rim.material_override as ShaderMaterial).shader == CreatureLayer.MORSEL_RIM_SHADER, "the morsel rim")
		pool.free()


func test_morsel_site_leaves_softly() -> void:
	var pool := _site_pool("omnivore")
	var sim := pool.sim
	var layer := pool.creature_layer
	var rotten := _site_item(sim, "rammer", Vector2(3.0, 0.0))
	var eaten := _site_item(sim, "rammer", Vector2(-3.0, 0.0))
	for i in 60:
		FakeEvents.frame(pool)
	check_near(layer.morsel_site_transform(rotten.id).basis.x.length(), float(rotten.radius) / sim.species.phenotype("rammer", _catalog).radius, 1e-5,
		"grown in to its radius over its body's")
	sim.carrion.expire(str(rotten.id), "rot")
	FakeEvents.frame(pool)
	var gone_at := sim.now()
	while sim.now() - gone_at < 0.45:
		FakeEvents.frame(pool)
	check(str(rotten.id) in layer.morsel_site_ids(), "a rotted item is still drawn at 0.45 s")
	check(layer.morsel_site_transform(rotten.id).basis.x.length() < 0.48 * 0.35, "shrinking")
	while sim.now() - gone_at < 0.7:
		FakeEvents.frame(pool)
	check(not str(rotten.id) in layer.morsel_site_ids(), "and gone at 0.7 s")
	sim.carrion.expire(str(eaten.id), "eaten")
	layer.on_event({"type": "ate", "kind": "meat", "food_id": eaten.id, "position": eaten.position})
	check(not str(eaten.id) in layer.morsel_site_ids(), "an eaten one goes at once")
	FakeEvents.frame(pool)
	check(layer.morsel_site_ids().is_empty(), "and stays gone")
	pool.free()


## An endless pool at size 4 with a cell of founder `body` and no creatures in the way.
func _site_pool(body: String) -> PoolScene:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	pool.sim.creatures.set_size(4)
	pool.sim.world.size = 4
	pool.sim.phenotype = _cell(body)
	return pool


## A morsel-site carrion item of `species` at `offset` from the cell, as the stream spawns one.
func _site_item(sim: PoolSim, species: String, offset: Vector2) -> Dictionary:
	var item := sim.carrion.spawn(sim.motion.position + offset, CreatureLayer.MORSEL_SOURCE, 10.0, -1, 0.3, 600.0,
		{"species": species, "site": "m_test_%s" % sim.carrion.next_number})
	check(not item.is_empty(), "a %s morsel-site item" % species)
	return item


## The carrion items the FoodView should draw: all but morsels (V-24) and morsel sites' (V3-13).
static func _plain_carrion(sim: PoolSim) -> int:
	var n := 0
	for item in sim.carrion.items:
		if not str(item.get("source", "")) in ["morsel", CreatureLayer.MORSEL_SOURCE]:
			n += 1
	return n


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


## The colour a thread material shows: mix(neutral, ink, ink), as its shader does.
static func _thread_color(material: ShaderMaterial) -> Color:
	var neutral: Color = material.get_shader_parameter("neutral_color")
	return neutral.lerp(material.get_shader_parameter("ink_color"), float(material.get_shader_parameter("ink")))


## The view's own M_Threat material, or null.
static func _crest(view: CreatureView) -> BaseMaterial3D:
	for slot in view._ink_slots:
		if (slot.material as BaseMaterial3D).resource_name == "M_Threat":
			return slot.material
	return null
