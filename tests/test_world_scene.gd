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
	check_eq(names.slice(0, 5), ["Rim", "ZoneLights", "Rocks", "Feedback", "WorldFx"], "the containers register in their fixed order")
	check_eq(names.size(), 5 + PlaceholderAudio.POSITIONAL_PLAYERS + pool.creature_layer.views().size(),
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
	var containers: Array[Node3D] = [pool.zone_lights, pool.rocks, pool.feedback, pool.world_fx]
	var before := {}
	for c in containers:
		check(c.get_child_count() > 0, "%s holds something to move" % c.name)
		before[c] = _from_focus(pool, child_points(c))
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
	check(_meal_point(pool).distance_to(meal_before - Vector3(640.0, 0.0, 0.0)) <= 1e-3,
		"the meal label's anchor (_meal_at) moved with its container: %s, %s" % [_meal_point(pool), meal_before])
	pool.free()


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
