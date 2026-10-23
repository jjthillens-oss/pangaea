extends TestCase
## The pool's scene across the endless sea's floating origin (S1 T5.3 and T5.4; G25, G17's draw
## count; docs/s1/s1-content.md 6.1 to 6.9 and 7.1). Every Node3D under the pool is covered by one
## of three groups, a rebase moves nothing on screen, and containers renormalise without moving
## anything. Pools are built outside the tree (tests/fakes/fake_world_events.gd), in pool mode or
## on T2's FakeWorldGen.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const GROUPS: Array[StringName] = [&"world_space", &"world_rebuilt", &"camera_relative"]


## Every way the pool breaks the coverage rule (s1-content.md 6.1), one line each, naming the node:
##   1. every Node3D outside UI is covered by its nearest ancestor-or-self in one of the groups;
##   2. a node in a group is in exactly one;
##   3. a top_level node is in a group itself (its parent's transform does not carry it);
##   4. the world_space group is exactly world_space.registered(), and no registered node is carried
##      by a registered ancestor (nothing is shifted twice; a top_level node is not carried).
## Rule 5 (plain containers only when every child is covered) follows from rule 1.
static func coverage_problems(pool: PoolScene) -> PackedStringArray:
	var problems := PackedStringArray()
	var ui := pool.get_node("UI")
	var in_world_space: Array[Node] = []
	for node: Node in pool.find_children("*", "Node3D", true, false):
		if ui.is_ancestor_of(node):
			continue
		var path := str(pool.get_path_to(node))
		var groups := groups_of(node)
		if groups.size() > 1:
			problems.append("%s is in %s" % [path, groups])
		if (node as Node3D).top_level and groups.is_empty():
			problems.append("%s is top_level but in no group" % path)
		if covering_group(node, pool) == &"":
			problems.append("%s is not covered" % path)
		if node.is_in_group(&"world_space"):
			in_world_space.append(node)
	var registered := pool.world_space.registered()
	for node in in_world_space:
		if not registered.has(node):
			problems.append("%s is in world_space but not registered" % pool.get_path_to(node))
	for node in registered:
		if not pool.is_ancestor_of(node):
			problems.append("%s is registered but not in the pool" % node.name)
			continue
		var carrier := registered_carrier(node, pool)
		if carrier != null:
			problems.append("%s is registered under registered %s: shifted twice" % [pool.get_path_to(node), pool.get_path_to(carrier)])
	return problems


static func groups_of(node: Node) -> Array[StringName]:
	var out: Array[StringName] = []
	for g in GROUPS:
		if node.is_in_group(g):
			out.append(g)
	return out


## The group of `node`'s nearest ancestor-or-self in one, below `pool`; &"" when none.
static func covering_group(node: Node, pool: Node) -> StringName:
	var n := node
	while n != null and n != pool:
		var groups := groups_of(n)
		if not groups.is_empty():
			return groups[0]
		n = n.get_parent()
	return &""


## The registered ancestor whose transform carries `node`, or null: the walk up stops at a top_level
## node, which its parent does not carry.
static func registered_carrier(node: Node3D, pool: Node) -> Node3D:
	var n := node
	while n != pool and not n.top_level:
		var parent := n.get_parent()
		if parent == pool or not parent is Node3D:
			return null
		if parent.is_in_group(&"world_space"):
			return parent
		n = parent
	return null


func _check_covered(pool: PoolScene, when: String) -> void:
	var problems := coverage_problems(pool)
	check(problems.is_empty(), "every Node3D is covered %s:\n        %s" % [when, "\n        ".join(problems)])


## The world positions of `node`'s Node3D children (the container is a direct child of the pool).
static func child_points(node: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for child in node.get_children():
		if child is Node3D:
			out.append(node.transform * (child as Node3D).position)
	return out


func test_every_node3d_is_covered_in_pool_mode() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	_check_covered(pool, "after the build")
	var registered := pool.world_space.registered()
	var names := []
	for node in registered:
		names.append(str(pool.get_path_to(node)))
	check_eq(names.slice(0, 6), ["Rim", "ZoneLights", "Rocks", "Landmarks", "Feedback", "WorldFx"], "the containers register in their fixed order")
	check_eq(names.size(), 6 + PlaceholderAudio.POSITIONAL_PLAYERS + pool.creature_layer.views().size(),
		"then the positional players, then each creature's lane")
	check(pool.cell_view.get_node_or_null("EatFx") == null and pool.world_fx.get_node_or_null("EatFx") is CPUParticles3D,
		"the eat burst has moved to WorldFx")
	check((pool.world_fx.get_node("EatFx") as CPUParticles3D).local_coords, "with local particle coordinates")
	FakeEvents.frame(pool)
	var sim := pool.sim
	var at := sim.motion.position
	pool.feedback.show_meal({"type": "ate", "position": at + Vector2(1.0, 0.0), "absorbed": 8.0, "points": 1})
	pool.feedback.show_hit({"type": "hit", "target": CreatureField.PLAYER_ID, "attacker": "c1", "position": at, "dealt": 12.0})
	pool.feedback.show_dodged(at)
	var views := pool.creature_layer.views()
	check(not views.is_empty(), "the M1 pool has creatures")
	if not views.is_empty():
		# Straight to the layer: the pool's own route would also play the cue, whose positional
		# player sets a global position, which needs the tree.
		pool.creature_layer.on_event({"type": "creature_tell", "id": str(views[0].name), "target": CreatureField.PLAYER_ID,
			"kind": "lunge", "lane": {"origin": at + Vector2(6.0, 0.0), "heading": PI, "length": 5.0, "half_width": 0.6}})
		check(views[0].lane().visible, "a tell shows its lane")
	pool.cell_view._burst(PlaneSpace.to_world(at, 0.3), Color.WHITE)
	pool.cell_view._ghost(pool.plankton_view.food_mesh(), PlaneSpace.to_world(at + Vector2(0.5, 0.0)), PlaneSpace.to_world(at))
	check(pool.world_fx.get_child_count() >= 2, "the ghost flies under WorldFx")
	_check_covered(pool, "after a meal, a hit, a dodge, a tell, a positional cue, a burst and a ghost")
	pool.free()


func test_every_node3d_is_covered_in_endless_mode() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	check(pool.is_endless(), "the pool streams the endless sea")
	_check_covered(pool, "after the build")
	var sim := pool.sim
	pool.apply_world_event(_rare_chunk(Vector2i(55, 55)))
	check(not pool.landmarks.pieces().is_empty(), "a landmark and a set piece are drawn")
	_check_covered(pool, "after a chunk with a landmark, an anchor and a place")
	check(sim.debug_rebase(Vector2i(1, 0)), "a dev rebase")
	FakeEvents.frame(pool)
	_check_covered(pool, "after a rebase")
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(8.0, 0.0), 0.0), "a rammer comes into view")
	FakeEvents.frame(pool)
	var before := pool.creature_layer.views().size()
	check(before >= 1, "and is drawn")
	check(sim.debug_kill_nearest_creature(), "it is killed")
	for event in sim.drain_events():   # to the layer only, as above (no positional cue)
		pool.creature_layer.on_event(event)
	var dying: Array[Node] = pool.creature_layer.get_children().filter(func(v: Node) -> bool: return (v as CreatureView).dying)
	check_eq(dying.size(), 1, "its view is dying")
	if dying.size() == 1:
		check(pool.world_space.registered().has(dying[0]), "and registered: it is no longer synced")
	_check_covered(pool, "after a creature dies")
	pool.free()


func test_the_rim_hides_in_endless_mode_only() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	check(pool.rim_node.visible, "the dish wall shows in the pool")
	check(not pool.is_endless(), "pool mode")
	pool.free()
	pool = FakeEvents.open_pool(FakeEvents.endless_session())
	check(not pool.rim_node.visible, "and is hidden in the endless sea")
	pool.free()


func test_the_backdrop_and_lights_follow_the_camera_focus() -> void:
	for endless in [false, true]:
		var session := FakeEvents.endless_session() if endless else FakeEvents.pool_session()
		var pool := FakeEvents.open_pool(session, FakeEvents.Straight.new(Vector2(1.0, 0.0)))
		var nodes: Array[Node3D] = [pool.backdrop, pool._sun, pool._depth_glow]
		var fixed := []
		for node in nodes:
			fixed.append([node.position.y, node.basis])
		for i in 120:
			FakeEvents.frame(pool)
		var mode := "endless" if endless else "pool"
		check(pool.camera.focus.x > 1.0, "%s: the camera follows the cell east (focus x %.2f)" % [mode, pool.camera.focus.x])
		_check_under_focus(pool, nodes, fixed, "%s, after a swim east" % mode)
		if endless:
			var focus := pool.camera.focus
			pool.apply_world_event(FakeEvents.rebased(Vector2(32.0, 0.0)))
			check(pool.camera.focus.is_equal_approx(focus - Vector3(32.0, 0.0, 0.0)), "a rebase shifts the focus by the offset")
			_check_under_focus(pool, nodes, fixed, "endless, at once after a rebase")
		pool.free()


func _check_under_focus(pool: PoolScene, nodes: Array[Node3D], fixed: Array, when: String) -> void:
	for i in nodes.size():
		var node := nodes[i]
		check(absf(node.position.x - pool.camera.focus.x) <= 1e-6 and absf(node.position.z - pool.camera.focus.z) <= 1e-6,
			"%s: %s sits under the focus %s at %s" % [when, node.name, pool.camera.focus, node.position])
		check(node.position.y == fixed[i][0] and node.basis == fixed[i][1], "%s: %s keeps its height and turn" % [when, node.name])


func test_containers_renormalise_without_moving_anything() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	FakeEvents.frame(pool)
	var at := pool.sim.motion.position
	pool.feedback.show_meal({"type": "ate", "position": at, "absorbed": 8.0, "points": 1})
	pool.feedback.show_hit({"type": "hit", "target": CreatureField.PLAYER_ID, "attacker": "c1", "position": at, "dealt": 3.0})
	pool.cell_view._burst(PlaneSpace.to_world(at, 0.3), Color.WHITE)
	pool.apply_world_event(_rare_chunk(Vector2i(51, 51)))   # a key the view set does not hold
	var containers: Array[Node3D] = [pool.zone_lights, pool.landmarks, pool.feedback, pool.world_fx]
	var before := {}
	for c in containers:
		check(c.get_child_count() > 0, "%s holds something to move" % c.name)
		before[c] = _from_focus(pool, child_points(c))
	var shells_before := _from_focus(pool, shell_points(pool))
	check(not shells_before.is_empty(), "the shell layer holds shells")
	var meal_before := _meal_point(pool)
	var offset := Vector2(32.0, 0.0)
	for i in 20:   # 640 tm in all, past RENORMALIZE_TM (512)
		pool.apply_world_event(FakeEvents.rebased(offset))
	for c in containers:
		var after := _from_focus(pool, child_points(c))
		var worst := 0.0
		for j in after.size():
			worst = maxf(worst, after[j].distance_to(before[c][j]))
		check(worst <= 1e-4, "%s: every child keeps its place on screen (worst %.6f)" % [c.name, worst])
		var r := Vector2(c.position.x, c.position.z).length()
		check(r <= WorldSpace.RENORMALIZE_TM, "%s renormalised: %.1f tm from the origin, not 640" % [c.name, r])
	var shells_after := _from_focus(pool, shell_points(pool))
	var worst_shell := 0.0
	for j in shells_after.size():
		worst_shell = maxf(worst_shell, shells_after[j].distance_to(shells_before[j]))
	check(shells_after.size() == shells_before.size() and worst_shell <= 1e-4, "every shell instance keeps its place on screen (worst %.6f)" % worst_shell)
	check(Vector2(pool.rocks.position.x, pool.rocks.position.z).length() <= WorldSpace.RENORMALIZE_TM, "and the shell layer renormalised")
	check(_meal_point(pool).distance_to(meal_before - Vector3(640.0, 0.0, 0.0)) <= 1e-3,
		"the meal label's anchor (_meal_at) moved with its container: %s, %s" % [_meal_point(pool), meal_before])
	pool.free()


## Every shell instance's place in the pool's space, asset by asset in add order.
static func shell_points(pool: PoolScene) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var assets := pool.rocks.assets_in_use()
	assets.sort()
	for asset in assets:
		for e in pool.rocks.instances_of(asset):
			out.append(pool.rocks.transform * (e.transform as Transform3D).origin)
	return out


## Each point less the camera's focus: where it sits relative to the view.
static func _from_focus(pool: PoolScene, points: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		out.append(p - pool.camera.focus)
	return out


## The newest meal label's anchor in the pool's space.
static func _meal_point(pool: PoolScene) -> Vector3:
	var i := posmod(pool.feedback._next_meal - 1, FeedbackFx.MEAL_LABELS)
	return pool.feedback.transform * pool.feedback._point(i, false)


func test_labels_and_effects_land_where_their_events_happen_after_a_rebase() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	FakeEvents.frame(pool)
	for i in 3:   # 96 tm: the containers sit off the origin, short of renormalising
		pool.apply_world_event(FakeEvents.rebased(Vector2(32.0, 0.0)))
	check(pool.feedback.position.is_equal_approx(Vector3(-96.0, 0.0, 0.0)), "Feedback has moved with the world")
	var p := Vector2(3.0, -2.0)
	pool.feedback.show_meal({"type": "ate", "position": p, "absorbed": 8.0, "points": 1})
	pool.feedback.show_hit({"type": "hit", "target": CreatureField.PLAYER_ID, "attacker": "c1", "position": p + Vector2(5.0, 0.0), "dealt": 3.0})
	pool.feedback.show_dodged(p + Vector2(-5.0, 0.0))
	var meal := pool.feedback.meal_labels()
	check_eq(meal.size(), 1, "one meal label")
	if meal.size() == 1:
		_check_at(pool.feedback.transform * meal[0].position, p, "the meal label")
	_check_at(pool.feedback.transform * pool.feedback.hit_labels()[0].position, p + Vector2(5.0, 0.0), "the hit label")
	_check_at(pool.feedback.transform * pool.feedback.dodged_label().position, p + Vector2(-5.0, 0.0), "the Dodged! label")
	pool.cell_view._burst(PlaneSpace.to_world(p, 0.3), Color.WHITE)
	var fx := pool.world_fx.get_node("EatFx") as Node3D
	_check_at(pool.world_fx.transform * fx.position, p, "the eat burst")
	pool.cell_view._ghost(pool.plankton_view.food_mesh(), PlaneSpace.to_world(p + Vector2(0.0, 4.0)), PlaneSpace.to_world(p))
	var ghost := pool.world_fx.get_child(pool.world_fx.get_child_count() - 1) as Node3D
	_check_at(pool.world_fx.transform * ghost.position, p + Vector2(0.0, 4.0), "a meal ghost's start")
	pool.free()


func _check_at(world: Vector3, p: Vector2, what: String) -> void:
	check(absf(world.x - p.x) <= 1e-4 and absf(world.z - p.y) <= 1e-4, "%s stands over its event at %s: %s" % [what, p, world])


## A chunk with two shells, a frosted great shell (anchor and its landmark collider), the giant
## husk (a place and a set-piece collider) and a sunlit and a reef zone, near local (0, 0).
static func _rare_chunk(key: Vector2i) -> Dictionary:
	var shells := [
		FakeEvents.shell("s_a_%d" % key.x, Vector2(6.0, 3.0), 1.0, "shell_bell", 30.0, 0.9),
		FakeEvents.shell("s_b_%d" % key.x, Vector2(-8.0, 5.0), 0.8, "shell_diatom_disc"),
		FakeEvents.shell("lm_%d" % key.x, Vector2(12.0, -6.0), 2.0, "landmark_great_shell", 90.0, 0.95, "#D6E0F5", "landmark"),
		FakeEvents.shell("sp_%d" % key.x, Vector2(-14.0, -10.0), 1.1, "rare_giant_husk", 0.0, 1.0, "", "set_piece"),
	]
	return FakeEvents.loaded(key, shells,
		[FakeEvents.zone("z_sun_%d" % key.x, Vector2(2.0, 12.0), 4.0, "sunlit"), FakeEvents.zone("z_reef_%d" % key.x, Vector2(-6.0, 14.0), 4.0, "reef")],
		[FakeEvents.anchor("a_%d" % key.x, Vector2(12.0, -6.0), "landmark_great_shell", "frosted")],
		[FakeEvents.place("p_%d" % key.x, "giant_husk", Vector2(-14.0, -10.0))])


func test_pool_rocks_draw_where_the_old_rock_field_did() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	var layout := pool.session.layout
	var assets := {}
	for rock in layout.rocks:
		assets[rock.asset] = int(assets.get(rock.asset, 0)) + 1
		var found := {}
		for e in pool.rocks.instances_of(rock.asset):
			if e.id == rock.id:
				found = e
		check(not found.is_empty(), "%s is drawn" % rock.id)
		if found.is_empty():
			continue
		# The old RockField's node: rotation.y = yaw, uniform scale, at the rock's center.
		var old := Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(rock.yaw_deg), 0.0)).scaled(Vector3.ONE * float(rock.scale)),
			PlaneSpace.to_world(rock.center))
		var t: Transform3D = found.transform
		var basis_err := (t.basis.x - old.basis.x).length() + (t.basis.y - old.basis.y).length() + (t.basis.z - old.basis.z).length()
		check(basis_err <= 1e-5 and t.origin.distance_to(old.origin) <= 1e-5, "%s keeps today's transform: %s, %s" % [rock.id, t, old])
		check_eq(found.color, Color.WHITE, "%s keeps its own colours" % rock.id)
	var meshes := pool.rocks.find_children("*", "MultiMeshInstance3D", false, false)
	check_eq(meshes.size(), assets.size(), "one MultiMesh per rock asset used")
	for asset in assets:
		var mmi := pool.rocks.multimesh_of(asset)
		check(mmi != null and mmi.multimesh.instance_count == assets[asset], "%s: %d instances" % [asset, assets[asset]])
	pool.free()


func test_chunk_events_add_and_remove_shell_instances() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	pool.rocks.clear()   # only this test's chunks
	var one := []
	for i in 5:
		one.append(FakeEvents.shell("a%d" % i, Vector2(40.0 + i, 5.0), 1.0, "shell_bell" if i < 3 else "shell_girdle_drum",
			15.0 * i, 0.8 + 0.1 * i, "#D6E0F5" if i == 4 else "#FFFFFF"))
	var two := []
	for i in 3:
		two.append(FakeEvents.shell("b%d" % i, Vector2(70.0 + i, -3.0), 1.0, "shell_bell"))
	pool._loaded.clear()
	pool.apply_world_event(FakeEvents.loaded(Vector2i(1, 0), one))
	pool.apply_world_event(FakeEvents.loaded(Vector2i(2, 0), two))
	check_eq(pool.rocks.instances_of("shell_bell").size(), 6, "3 + 3 bells")
	check_eq(pool.rocks.instances_of("shell_girdle_drum").size(), 2, "2 drums")
	var drums := pool.rocks.instances_of("shell_girdle_drum")
	if drums.size() == 2:
		var e: Dictionary = drums[1]
		var want := Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)) * Basis.from_scale(Vector3.ONE * 1.2),
			WorldSpace.to_frame(pool.rocks, Vector2(44.0, 5.0)))
		check((e.transform as Transform3D).is_equal_approx(want), "at to_frame(position) with its yaw and scale: %s" % e.transform)
		check_eq(e.color, Color("#D6E0F5"), "with its tint")
		check_eq(drums[0].color, Color.WHITE, "and #FFFFFF draws untinted")
	pool.apply_world_event(FakeEvents.loaded(Vector2i(1, 0), one))
	check_eq(pool.rocks.instances_of("shell_bell").size(), 6, "a repeated chunk_loaded changes nothing")
	pool.apply_world_event(FakeEvents.unloaded(Vector2i(1, 0)))
	check_eq(pool.rocks.instances_of("shell_bell").size(), 3, "unloading (1, 0) leaves (2, 0)'s bells")
	check(pool.rocks.instances_of("shell_bell").all(func(e: Dictionary) -> bool: return e.key == Vector2i(2, 0)), "only (2, 0)'s")
	check(pool.rocks.multimesh_of("shell_girdle_drum") == null, "a piece with no instances left has no MultiMesh")
	pool.apply_world_event(FakeEvents.unloaded(Vector2i(9, 9)))
	check_eq(pool.rocks.instances_of("shell_bell").size(), 3, "an unknown key is ignored")
	check_eq(pool.rocks.find_children("*", "MultiMeshInstance3D", false, false).size(), pool.rocks.assets_in_use().size(),
		"one MultiMesh per piece in use")
	pool.free()


func test_a_landmark_shows_its_model_yaw_scale_tint_and_growth() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var kit: PlacementKit = pool.session.world.kit
	var frosted := pool.landmarks.dressing_of("landmark_great_shell", "frosted")
	check(str(frosted.growth) == "Growth_Needles" and Color(frosted.tint) == Color("#D6E0F5"), "the kit's frosted dressing: %s" % frosted)
	pool.apply_world_event(_rare_chunk(Vector2i(53, 53)))
	var piece: Node3D = null
	for p in pool.landmarks.pieces():
		if p.name == "a_53":
			piece = p
	check(piece != null, "the piece is named after the anchor")
	if piece != null:
		var want := Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3.ONE * 0.95)
		check(piece.basis.is_equal_approx(want), "turned 90 degrees and scaled 0.95 as its collider: %s" % piece.basis)
		check(piece.position.is_equal_approx(WorldSpace.to_frame(pool.landmarks, Vector2(12.0, -6.0))), "at its collider")
		var root := LandmarkLayer._root_mesh(piece)
		var tint := Color("#D6E0F5")
		for i in root.mesh.get_surface_count():
			var base := root.mesh.surface_get_material(i) as BaseMaterial3D
			var over := root.get_surface_override_material(i) as BaseMaterial3D
			var product := Color(base.albedo_color.srgb_to_linear() * tint.srgb_to_linear()).linear_to_srgb()
			check(over != null and Vector4(over.albedo_color.r, over.albedo_color.g, over.albedo_color.b, over.albedo_color.a).distance_to(
				Vector4(product.r, product.g, product.b, product.a)) <= 1e-3, "surface %d takes the linear product of albedo and tint" % i)
		check((piece.find_child("Growth_Needles", true, false) as Node3D).visible, "its growth shows")
		check(not (piece.find_child("Growth_Beads", true, false) as Node3D).visible, "and no other")
	var plain := FakeEvents.loaded(Vector2i(4, 4), [FakeEvents.shell("lm_p", Vector2(30.0, 0.0), 2.0, "landmark_ring", 0.0, 1.0, "#FFFFFF", "landmark")],
		[], [FakeEvents.anchor("a_plain", Vector2(30.0, 0.0), "landmark_ring", "plain")])
	pool.apply_world_event(plain)
	var ring: Node3D = null
	for p in pool.landmarks.pieces():
		if p.name == "a_plain":
			ring = p
	check(ring != null, "a plain landmark is drawn")
	if ring != null:
		var growth := ring.find_children("Growth_*", "Node3D", true, false)
		check(not growth.is_empty() and growth.all(func(n: Node) -> bool: return not (n as Node3D).visible), "with every growth hidden")
	check(pool.rocks.instances_of("landmark_great_shell").is_empty() and pool.rocks.instances_of("rare_giant_husk").is_empty(),
		"landmark and set-piece colliders make no shell instances")
	check(kit != null, "the endless pool has the kit")
	pool.free()


func test_a_set_piece_draws_over_its_colliders_at_every_orientation() -> void:
	var kit := PlacementKit.load_from()
	var colliders: Array = kit.assets["rare_giant_husk"].colliders
	check(not colliders.is_empty(), "the giant husk has colliders")
	for o in 8:
		var basis := LandmarkLayer.place_basis(WorldGen.orient_yaw_deg(0.0, o), (o >> 2) == 1)
		for c: Dictionary in colliders:
			var cx: float = c.center[0]
			var cy: float = c.center[1]
			var drawn := basis * Vector3(cx, 0.0, cy)
			var placed := WorldGen.orient_point(cx, cy, o)
			check(drawn.distance_to(PlaneSpace.to_world(Vector2(placed[0], placed[1]))) <= 1e-6,
				"o %d: the collider (%.2f, %.2f) is drawn at %s, placed at %s" % [o, cx, cy, drawn, placed])
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	pool.apply_world_event(FakeEvents.loaded(Vector2i(6, 6), [], [], [], [FakeEvents.place("p_m", "giant_husk", Vector2(20.0, 20.0), -90.0, true)]))
	var piece: Node3D = pool.landmarks.pieces().back() if not pool.landmarks.pieces().is_empty() else null
	check(piece != null and piece.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(-90.0)) * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))),
		"a place with yaw -90 and mirror gets exactly that basis")
	pool.free()


func test_zone_labels_and_patches_follow_chunk_events() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var key := Vector2i(7, 7)
	var regions := ["sunlit", "home", "reef", "drift"]
	var zones := []
	for i in regions.size():
		zones.append(FakeEvents.zone("zq_%s" % regions[i], Vector2(10.0 * i, 3.0), 4.0, regions[i]))
	pool.apply_world_event(FakeEvents.loaded(key, [], zones))
	for z in zones:
		var label := pool.feedback.zone_label(z.id)
		check(label != null and label.position.is_equal_approx(WorldSpace.to_frame(pool.feedback, z.center, FeedbackFx.ZONE_LABEL_Y)),
			"%s has a Regrowing label over its centre" % z.id)
		var patch := pool.zone_lights.get_node_or_null(NodePath(z.id))
		check((patch != null) == (z.region in ["sunlit", "home"]), "%s (%s) has a patch only on sunlit and home tiles" % [z.id, z.region])
	pool.apply_world_event(FakeEvents.unloaded(key))
	for z in zones:
		check(pool.feedback.zone_label(z.id) == null, "unloading frees %s's label" % z.id)
		var patch := pool.zone_lights.get_node_or_null(NodePath(z.id))
		check(patch == null or patch.is_queued_for_deletion(), "and its patch")
	pool.free()


func test_sleepers_hide_and_wakers_show_where_they_woke() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(10.0, 0.0), 0.0), "a rammer")
	FakeEvents.frame(pool)
	var c: CreatureField.Creature = sim.creatures.creatures.back()
	var view := pool.creature_layer.view_of(c.id)
	check(view != null and view.visible, "drawn while awake")
	# T2's sleep: the creature is flagged and its event says so (until T2.6, set here by hand).
	c.asleep = true
	pool.creature_layer.on_event({"type": "creature_slept", "id": c.id})
	check(not view.visible, "creature_slept hides the view")
	var at := view.position
	c.motion.place(c.motion.position + Vector2(3.0, 0.0), c.motion.heading)
	pool.creature_layer.sync(1.0)
	check(not view.visible and view.position == at, "sync neither shows nor moves a sleeper")
	check(not pool.creature_layer.views().has(view), "a sleeper is not among the live views")
	var woke_at := c.motion.position + Vector2(0.0, 5.0)
	c.motion.place(woke_at, c.motion.heading)
	c.asleep = false
	pool.creature_layer.on_event({"type": "creature_woke", "id": c.id})
	check(view.visible, "creature_woke shows it")
	check(view.position.is_equal_approx(PlaneSpace.to_world(woke_at)), "where it woke, in the same frame: %s" % view.position)
	pool.free()


func test_the_initial_view_set_matches_the_streamed_events() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var world := pool.sim.world
	check_eq(pool.loaded_keys(), world.loaded_keys(), "the first build draws exactly the loaded chunks (B-23)")
	FakeEvents.frame(pool)   # the queued create-time events route: nothing changes
	check_eq(pool.loaded_keys(), world.loaded_keys(), "and the create-time events change nothing")
	var sim := pool.sim
	# The origin moves first, so local and absolute positions differ.
	check(sim.debug_rebase(Vector2i(-2, 1)), "a dev rebase")
	for e in sim.drain_events():
		pool._route(e)
	var bot := FakeEvents.Straight.new(Vector2.RIGHT)
	var seen := {}
	for t in 1200:
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			pool._route(e)
			if e.type == "chunk_loaded" and seen.is_empty():
				seen = e
				var built := FakeEvents.from_chunk(world, world.chunk(e.key))
				check(_deep_equal(built, e), "in its tick the scene's builder matches the stream's event for %s" % e.key)
		if not seen.is_empty():
			break
	check(not seen.is_empty(), "a swim east loads a chunk")
	check_eq(pool.loaded_keys(), world.loaded_keys(), "and the drawn chunks follow the stream")
	pool.free()


## Equal dictionaries and arrays, with Vector2 positions within 1e-9.
static func _deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _deep_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_equal(a[i], b[i]):
				return false
		return true
	if a is Vector2 and b is Vector2:
		return (a as Vector2).distance_to(b) <= 1e-9
	return typeof(a) == typeof(b) and a == b


func test_draws_stay_at_one_multimesh_per_shell_asset() -> void:
	# A full view set of busy chunks: every chunk holds every shell piece. The real world's 4-seed
	# version waits for WorldGen's chunks and the tiles (T1.9, T4.3).
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var pieces := ["shell_diatom_disc", "shell_radiolarian_lens", "shell_girdle_drum", "shell_fluted_tower", "shell_bell",
		"rock_a", "rock_b", "rock_c"]
	for cx in 6:
		for cy in 6:
			var shells := []
			for i in pieces.size():
				shells.append(FakeEvents.shell("d_%d_%d_%d" % [cx, cy, i], Vector2(32.0 * cx + 3.0 * i, 32.0 * cy), 1.0, pieces[i]))
			pool.apply_world_event(FakeEvents.loaded(Vector2i(100 + cx, cy), shells))
	var meshes := pool.rocks.find_children("*", "MultiMeshInstance3D", false, false)
	check_eq(meshes.size(), pieces.size(), "one MultiMesh per shell piece, not per chunk")
	check_eq(pool.rocks.get_child_count(), meshes.size(), "and nothing else in Rocks")
	pool.free()
