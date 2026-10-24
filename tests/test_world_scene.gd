extends TestCase
## The pool's scene across the endless sea's floating origin (S1 T5.3 and T5.4; G25, G17's draw
## count; docs/s1/s1-content.md 6.1 to 6.9 and 7.1). Every Node3D under the pool is covered by one
## of three groups, a rebase moves nothing on screen, and containers renormalise without moving
## anything. Pools are built outside the tree (tests/fakes/fake_world_events.gd), in pool mode or
## on T2's FakeWorldGen. The silt trail (S2; s2-view 7.7, V-25, C-V10): a ribbon behind each move
## between two lairs of a species with a trail, fading over its trail_s, at most eight; a lair mouth
## at both posts of every live Lurker site, posed and sized for the size, gone with its chunk and
## hidden where the Lurker is not live; the pool feeding it from its events.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const FakeGrowthEvents := preload("res://tests/fakes/fake_growth_events.gd")
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


## The shipped species, for the silt trail (loaded on first use).
var _species: SpeciesCatalog

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
	check_eq(names.slice(0, 9), ["Rim", "ZoneLights", "Rocks", "Landmarks", "Feedback", "WorldFx", "SiltTrail", "OlderHaze", "OldBand"],
		"the containers register in their fixed order (the silt trail is S2's, the older haze and the old band S3's)")
	check_eq(names.size(), 9 + CellAudio.POSITIONAL_PLAYERS + 1 + pool.creature_layer.views().size(),
		"then the positional players, the growth beat's effects, then each creature's lane")
	check_eq(names[9 + CellAudio.POSITIONAL_PLAYERS], "BeatFx", "the growth beat's effects ride a rebase and a growth (S2)")
	var dissolve := pool.ui.get_node_or_null(^"BeatDissolve") as TextureRect
	check(dissolve != null and not dissolve.visible, "the reduce-motion dissolve waits, hidden, over the UI (S2)")
	check(not pool.growth_beat.running() and pool.depth_k() == 1.0, "the growth beat is idle after the build")
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
	# The silt trail's pieces (S2): a Lurker's lair mouth and its ribbon, drawn as at size 2.
	pool.silt_trail.resize(2)
	var lair := sim.motion.position + Vector2(4.0, 0.0)
	pool.apply_world_event(FakeEvents.loaded(Vector2i(56, 55), [], [], [], [],
		[FakeGrowthEvents.site("s_l", "lurker", [FakeGrowthEvents.post(lair)] as Array[Dictionary])]))
	pool.silt_trail.add_ribbon({"from": lair, "to": lair + Vector2(0.0, 6.0)}, "lurker", sim.now())
	check(pool.silt_trail.mouths().size() == 1 and pool.silt_trail.ribbons().size() == 1, "a lair mouth and a silt ribbon are drawn")
	_check_covered(pool, "after a lair mouth and a silt ribbon")
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


func test_the_kits_landmark_pieces_load_at_setup() -> void:
	LandmarkLayer._scenes.clear()   # from a clean slate: the pieces earlier tests loaded are dropped
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var kit: PlacementKit = pool.session.world.kit
	var paths := {}
	for id in kit.assets:
		if str(kit.assets[id].kind) in ["landmark", "rare"]:
			paths[str(kit.assets[id].glb)] = true
	check(paths.size() >= 5, "the kit has landmark and rare pieces (%d)" % paths.size())
	for path in paths:
		check(LandmarkLayer._scenes.get(path) is PackedScene, "setup loads %s, with no chunk asking for it" % path.get_file())
	var kept: Dictionary = LandmarkLayer._scenes.duplicate()
	pool.landmarks.setup(kit)
	check(paths.keys().all(func(path: String) -> bool: return LandmarkLayer._scenes[path] == kept[path]),
		"a second setup (a new session) loads nothing again")
	pool.apply_world_event(_rare_chunk(Vector2i(53, 53)))
	check(pool.landmarks.pieces().size() >= 2, "a chunk takes its landmark and its set piece from the loaded pieces")
	pool.free()
	for path in paths:
		check_eq(ResourceLoader.load_threaded_get_status(path), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"no worker-thread load of %s is made (they stalled the engine on WARP)" % path.get_file())


## S2G26: a growth draws shells and lair mouths the cell has not seen yet, so their GLBs load when the
## sea is set up, and none loads in the growth's frame. They load on the main thread: worker-thread
## loads stalled the engine on Windows' software renderer as they finished.
func test_the_kits_shell_pieces_and_the_lair_mouth_load_at_setup() -> void:
	RockField._scenes.clear()   # from a clean slate: the pieces earlier tests loaded are dropped
	SiltTrail._mouth_scene = null
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var kit: PlacementKit = pool.session.world.kit
	var shells := PackedStringArray()
	for id: String in kit.assets:
		if str(kit.assets[id].kind) == "shell":
			shells.append(id)
	check(shells.size() >= 5, "the kit has shell pieces (%d)" % shells.size())
	for id in shells:
		check(RockField._scenes.get(RockField.ASSET_PATH % id) is PackedScene, "setup loads %s, in view or not" % id)
	check(SiltTrail._mouth_scene != null, "and the lair mouth, though no Lurker lives at size 1")
	var kept: Dictionary = RockField._scenes.duplicate()
	var mouth := SiltTrail._mouth_scene
	var shells_in := []
	for i in shells.size():
		shells_in.append({"id": "shell_%d" % i, "position": Vector2(3.0 * i, 0.0), "radius": 1.0, "kind": "shell",
			"asset": shells[i], "yaw_deg": 0.0, "scale": 1.0, "tint": ""})
	pool.rocks.add_chunk(Vector2i(77, 77), shells_in)
	for id in shells:
		check(pool.rocks.multimesh_of(id) != null, "a chunk draws %s" % id)
	pool.silt_trail.resize(2)
	pool.silt_trail.add_chunk(Vector2i(78, 78), FakeGrowthEvents.lair_sites(Vector2.ZERO, 1.0))
	check(not pool.silt_trail.mouths().is_empty(), "and the first mouths")
	check(RockField._scenes == kept and SiltTrail._mouth_scene == mouth, "from the pieces setup loaded, with no load of their own")
	pool.free()
	var again := FakeEvents.open_pool(FakeEvents.endless_session())
	check(RockField._scenes == kept and SiltTrail._mouth_scene == mouth, "and a new sea's setup loads nothing again")
	again.free()
	for id in shells:
		check_eq(ResourceLoader.load_threaded_get_status(RockField.ASSET_PATH % id), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"no worker-thread load of %s is made" % id)
	check_eq(ResourceLoader.load_threaded_get_status(SiltTrail.MOUTH_GLB), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"nor of the mouth")


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


## A "Regrowing" label never covers the cell on screen (S1 review: it sat over the cell while the
## cell waited in the zone it had emptied). Swept through the zone's middle from six ways at about
## 4 m/s, a shown label always clears the cell; far from the cell it stands over the zone's centre.
func test_a_regrowing_label_keeps_off_the_cell_on_screen() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session(FakeEvents.SEED, "grazer"))
	var sim := pool.sim
	var fx := pool.feedback
	check(sim.debug_empty_zone("z_center"), "z_center emptied")
	FakeEvents.frame(pool)
	check(sim.plankton.is_regrowing("z_center"), "and regrowing after a step")
	var label := fx.zone_label("z_center")
	var center: Vector2 = sim.region.zone("z_center").center
	var radius := sim.phenotype.radius
	var dt := 1.0 / 60.0
	fx.update_zones(sim.region, sim.plankton, FeedbackFx.ZONE_REFRESH_S, center + Vector2(30.0, 30.0), radius)
	check(label.visible and is_equal_approx(label.modulate.a, 1.0) and is_equal_approx(label.position.y, FeedbackFx.ZONE_LABEL_Y),
		"with the cell away it shows over the zone's centre (alpha %.2f, y %.2f)" % [label.modulate.a, label.position.y])
	var worst := INF
	var shown := 0
	var hidden := 0
	for way: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1.0, 1.0).normalized(), Vector2(-1.0, 0.5).normalized()]:
		for side: float in [0.0, 0.6, -1.2]:
			for step in 241:
				var cell_at := center + way.orthogonal() * side + way * lerpf(-8.0, 8.0, step / 240.0)
				pool.camera.snap_to(PlaneSpace.to_world(cell_at))
				fx.update_zones(sim.region, sim.plankton, dt, cell_at, radius)
				if not label.visible or label.modulate.a <= 0.0:
					hidden += 1
					continue
				shown += 1
				worst = minf(worst, _clear_of_cell_px(pool.camera, label, cell_at, radius))
	check(worst >= -0.5, "a shown label always clears the cell and its mouth (closest %.1f px)" % worst)
	check(shown > 3 * hidden, "and it shows most of the time (%d frames shown, %d hidden)" % [shown, hidden])
	# The running pool passes its cell: a cell waiting in the zone's middle, as a forager does.
	check(sim.debug_teleport(center + Vector2(0.0, -0.6), -PI / 2.0), "the cell moves into the zone's middle, just north of its centre")
	for i in 30:
		FakeEvents.frame(pool)
	check(label.visible and label.modulate.a > 0.0, "the label shows there")
	check(_clear_of_cell_px(pool.camera, label, PlaneSpace.to_plane(pool.cell_view.position), radius) >= -0.5,
		"clear of the cell the pool draws (%.1f px)" % _clear_of_cell_px(pool.camera, label, PlaneSpace.to_plane(pool.cell_view.position), radius))
	pool.free()


## How far zone label `label` (a child of the pool's Feedback at the origin) shows from the cell at
## `cell_at` on a 1920x1080 screen through `camera`, beyond FeedbackFx.ZONE_CELL_CLEAR of its radius.
func _clear_of_cell_px(camera: Camera3D, label: Label3D, cell_at: Vector2, radius: float) -> float:
	var project := func(p: Vector3) -> Vector2:
		var view := camera.transform.affine_inverse() * p
		var clip := Projection.create_perspective(camera.fov, 16.0 / 9.0, camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
		return Vector2(clip.x / clip.w + 1.0, 1.0 - clip.y / clip.w) * Vector2(960.0, 540.0)
	var font: Font = ThemeDB.fallback_font
	var text := Vector2(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x,
		font.get_height(label.font_size)) * label.pixel_size
	var at: Vector2 = project.call(label.position)
	var half := Vector2((project.call(label.position + camera.basis.x * text.x * 0.5) as Vector2).distance_to(at),
		(project.call(label.position + camera.basis.y * text.y * 0.5) as Vector2).distance_to(at))
	var cell := PlaneSpace.to_world(cell_at)
	var c: Vector2 = project.call(cell)
	var reach := (project.call(cell + camera.basis.x * radius * FeedbackFx.ZONE_CELL_CLEAR) as Vector2).distance_to(c)
	return c.clamp(at - half, at + half).distance_to(c) - reach


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
	sim.creatures.sleep(c, sim.tick)
	for e in sim.drain_events():
		pool._route(e)
	check(not view.visible, "creature_slept hides the view")
	var at := view.position
	c.motion.place(c.motion.position + Vector2(3.0, 0.0), c.motion.heading)
	pool.creature_layer.sync(1.0)
	check(not view.visible and view.position == at, "sync neither shows nor moves a sleeper")
	check(not pool.creature_layer.views().has(view), "a sleeper is not among the live views")
	var woke_at := c.motion.position + Vector2(0.0, 5.0)
	c.motion.place(woke_at, c.motion.heading)
	sim.creatures.wake(c, sim.tick)
	for e in sim.drain_events():
		pool._route(e)
	check(view.visible, "creature_woke shows it")
	check(view.position.is_equal_approx(PlaneSpace.to_world(woke_at)), "where it woke, in the same frame: %s" % view.position)
	# One that is asleep when its spawn is drawn gets no view until it wakes.
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-10.0, 0.0), 0.0), "a second rammer")
	var sleeper: CreatureField.Creature = sim.creatures.creatures.back()
	sim.creatures.sleep(sleeper, sim.tick)
	for e in sim.drain_events():
		pool._route(e)
	check(pool.creature_layer.view_of(sleeper.id) == null, "a creature asleep when its spawn is drawn is not drawn")
	sim.creatures.wake(sleeper, sim.tick)
	for e in sim.drain_events():
		pool._route(e)
	var woken := pool.creature_layer.view_of(sleeper.id)
	check(woken != null and woken.visible, "and is drawn once it wakes")
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


func test_a_post_move_leaves_a_ribbon_that_fades() -> void:
	var trail := _silt_trail(2)
	trail.add_ribbon(FakeGrowthEvents.post_move(Vector2(1.0, 2.0), Vector2(7.0, 10.0)), "lurker", 10.0)
	check_eq(trail.ribbons().size(), 1, "a ribbon for the Lurker's move")
	var ribbon := trail.ribbons()[0]
	var t := ribbon.transform
	check(PlaneSpace.to_plane(t.origin).distance_to(Vector2(4.0, 6.0)) < 1e-5, "centred between the posts: %s" % t.origin)
	check_near(t.origin.y, SiltTrail.RIBBON_Y, 1e-9, "just under the plane")
	check(SiltTrail.RIBBON_Y < CreatureView.LANE_Y, "and under the strike lane")
	var along := PlaneSpace.to_plane(t.basis.x)
	check_near(along.length(), 10.0, 1e-4, "as long as the move")
	check(along.normalized().distance_to(Vector2(0.6, 0.8)) < 1e-5, "along it: %s" % along)
	check_near(t.basis.z.length(), 0.5, 1e-5, "0.5 tm wide")
	check(absf(PlaneSpace.to_plane(t.basis.z).normalized().dot(along.normalized())) < 1e-5, "across it")
	var m := ribbon.material_override as StandardMaterial3D
	check(m != null and m.albedo_texture == SiltTrail.SILT_TEXTURE and m.texture_repeat, "T_SiltTrail, repeating")
	check_near(m.uv1_scale.x, 10.0 / SiltTrail.TILE_TM, 1e-6, "along its length")
	check_near(m.albedo_color.a, 0.55, 1e-6, "at 0.55")
	check(m.render_priority < CreatureView.LANE_PRIORITY, "drawn before the lane")
	check_eq(ribbon.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "casting no shadow")
	check_near(float(_species.habit_of("lurker").trail_s), 20.0, 1e-9, "the Lurker's trail lasts 20 s")
	trail.step(20.0)
	check_near(m.albedo_color.a, 0.275, 1e-6, "half faded half way")
	trail.step(29.9)
	check_eq(trail.ribbons().size(), 1, "still there just before 20 s")
	trail.step(30.0)
	check(trail.ribbons().is_empty(), "gone at 20 s")
	trail.add_ribbon(FakeGrowthEvents.post_move(Vector2.ZERO, Vector2(5.0, 0.0)), "rammer", 31.0)
	check(trail.ribbons().is_empty(), "a species without a trail leaves none")
	trail.add_ribbon(FakeGrowthEvents.post_move(Vector2.ONE, Vector2.ONE), "lurker", 31.0)
	check(trail.ribbons().is_empty(), "nor a move that goes nowhere")
	for i in 9:
		trail.add_ribbon(FakeGrowthEvents.post_move(Vector2(i, 0.0), Vector2(i, 5.0)), "lurker", 40.0 + i)
	var xs := trail.ribbons().map(func(r: MeshInstance3D) -> float: return roundf(r.position.x))
	check_eq(xs, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0], "at most eight: the oldest goes first")
	trail.free()


func test_lair_mouths_stand_at_the_live_posts() -> void:
	check(not _species.live_at("lurker", 1) and _species.live_at("lurker", 2), "the Lurker is live from size 2")
	var key := Vector2i(3, 4)
	var sites := FakeGrowthEvents.lair_sites(Vector2.ZERO, 1.0)
	var trail := _silt_trail(1)
	trail.add_chunk(key, sites)
	check(trail.mouths().is_empty(), "no mouths at size 1, where no Lurker lives")
	for n in [2, 3]:
		trail.resize(n)
		var mouths := trail.mouths()
		if not _species.live_at("lurker", n):
			check(mouths.is_empty(), "none at size %d" % n)
			continue
		check_eq(mouths.map(func(p: Node3D) -> String: return str(p.name)), ["s_a_post0", "s_a_post1", "s_b_post0", "s_b_post1"],
			"a mouth at each post of each Lurker site and none for the rammer's (size %d)" % n)
		for i in mouths.size():
			var post: Dictionary = sites[i / 2].posts[i % 2]
			var t := mouths[i].transform
			check(PlaneSpace.to_plane(t.origin).distance_to(post.position) < 1e-5, "%s at its post" % mouths[i].name)
			check_near(t.origin.y, -1.6, 1e-6, "1.6 tm down")
			var s := t.basis.get_scale()
			check(s.is_equal_approx(Vector3.ONE * 0.75 * pow(1.6, 2 - n)), "%s at 0.75 x 1.6^(2 - %d): %s" % [mouths[i].name, n, s])
			var opening := PlaneSpace.to_plane(t.basis.x).normalized()
			check(opening.distance_to(Vector2.from_angle(float(post.heading))) < 1e-4, "%s opens along its heading" % mouths[i].name)
		check(mouths.all(func(p: Node3D) -> bool: return p.find_children("*", "GeometryInstance3D", true, false).all(
			func(g: GeometryInstance3D) -> bool: return g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)),
			"casting no shadow")
	trail.remove_chunk(key)
	check(trail.mouths().is_empty(), "gone with their chunk")
	trail.add_chunk(key, sites)
	check_eq(trail.mouths().size(), 4, "back with it")
	trail.resize(1)
	check(trail.mouths().is_empty(), "hidden at a size the Lurker is not live at")
	trail.resize(2)
	check_eq(trail.mouths().size(), 4, "and shown again from the chunk's sites")
	trail.free()


## The pool's events: chunk sites become mouths at a live size, a Lurker's post move a ribbon, an
## unload takes the mouths, and the dev's size jump redraws the trail for the new size.
func test_the_pool_feeds_the_silt_trail() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true))
	check(pool.world_space.registered().has(pool.silt_trail), "the trail moves with WorldSpace")
	check(pool.growth_containers().has(pool.silt_trail), "and keeps the growth containers' contract")
	check(pool.sim.debug_set_size(2), "the dev's size 2")
	FakeEvents.frame(pool)
	check_eq(pool.silt_trail.size, 2, "the trail drawn at size 2")
	var c := pool.sim.motion.position
	var key := Vector2i(900, 900)
	var sites := FakeGrowthEvents.lair_sites(c, 1.0)
	pool._route(FakeEvents.loaded(key, [], [], [], [], sites))
	check_eq(pool.silt_trail.mouths().size(), 4, "the chunk's Lurker sites get their mouths")
	check(pool.sim.debug_spawn_creature("lurker", c + Vector2(6.0, 0.0), 0.0), "a Lurker")
	var lurker: CreatureField.Creature = pool.sim.creatures.creatures[pool.sim.creatures.creatures.size() - 1]
	check_eq(lurker.species_id, "lurker", "spawned")
	var move := FakeGrowthEvents.post_move(c + Vector2(3.0, 0.0), c + Vector2(-3.0, 2.0))
	move.id = lurker.id
	pool._route(move)
	check_eq(pool.silt_trail.ribbons().size(), 1, "its post move leaves a ribbon")
	move.id = "nobody"
	pool._route(move)
	check_eq(pool.silt_trail.ribbons().size(), 1, "a creature the sim no longer has leaves none")
	pool._route(FakeEvents.unloaded(key))
	check(pool.silt_trail.mouths().is_empty(), "the unload takes the mouths")
	pool._route(FakeEvents.loaded(key, [], [], [], [], sites))
	check(pool.sim.debug_set_size(1), "the dev's size 1")
	FakeEvents.frame(pool)
	check(pool.silt_trail.mouths().is_empty() and pool.silt_trail.ribbons().is_empty(), "no mouths or ribbons at size 1")
	pool.free()


## A silt trail on the shipped species at `size`, outside the tree.
func _silt_trail(size: int) -> SiltTrail:
	if _species == null:
		_species = SpeciesCatalog.load_from()
	var trail := SiltTrail.new()
	trail.setup(_species, size)
	return trail


# --- S3: the cradle and the home beacon (s3-view 6.6; S3G37) ---

## The shipped world (build top 4) in a pool at size `n` by the dev's size command, a frame drawn.
static func _s3_pool(n: int) -> PoolScene:
	var pool := FakeEvents.open_pool(FakeEvents.shipped_session_at_top(4))
	if n != 1:
		pool.sim.debug_set_size(n)
	FakeEvents.frame(pool)
	return pool


## Every surface `root` draws has its own material, the model's albedo dimmed by `dim` in linear light.
func _check_dimmed(root: Node, dim: float, what: String) -> void:
	var surfaces := 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var own := mi.get_surface_override_material(i) as BaseMaterial3D
			var model := mi.mesh.surface_get_material(i) as BaseMaterial3D
			check(own != null and own != model, "%s surface %d: its own material" % [what, i])
			if own == null or model == null:
				continue
			surfaces += 1
			var want := model.albedo_color.srgb_to_linear() * dim
			var got := own.albedo_color.srgb_to_linear()
			check(absf(got.r - want.r) + absf(got.g - want.g) + absf(got.b - want.b) < 3e-3,
				"%s %s: albedo %s dimmed x %.1f from %s" % [what, model.resource_name, own.albedo_color.to_html(false), dim, model.albedo_color.to_html(false)])
	check(surfaces > 0, "%s draws" % what)


## A node's merged mesh box in the pool's space.
static func _pool_box(node: Node3D, pool: Node) -> AABB:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != pool and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t * CradleView.aabb_under(node)


func test_cradle_ring_at_pool_radius() -> void:
	for n in [3, 4]:
		var pool := _s3_pool(n)
		var cradle := pool.cradle
		var radius := float(cradle.cradle.pool_ring.radius_bu)
		check_near(cradle.ring_scale() * CradleView.RING_RECORD_RADIUS_BU, radius * WorldConfig.bu_to_tm(n), 1e-6,
			"size %d: the ring's scale x its record radius is the old pool's radius, %.4f bu x %.3f" % [n, radius, WorldConfig.bu_to_tm(n)])
		var box := _pool_box(cradle.ring(), pool)
		check_near(box.end.y, CradleView.RING_TOP_TM, 1e-4, "size %d: its top" % n)
		check(box.position.y < box.end.y, "size %d: its base below its top" % n)
		var home := PlaneSpace.to_world(pool.sim.world.local_of_abs(0.0, 0.0), 0.0)
		check(Vector2(box.get_center().x - home.x, box.get_center().z - home.z).length() < 0.05, "size %d: round home" % n)
		_check_dimmed(cradle.ring(), CradleView.DIM, "the ring")
		pool.free()


func test_ring_record_radius_matches_the_record() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/records/cradle_ring.json"))
	check_eq(CradleView.RING_RECORD_RADIUS_BU, float(record.radius_bu), "RING_RECORD_RADIUS_BU is the record's radius_bu")


func test_cradle_visible_at_band_one_only() -> void:
	var pool := _s3_pool(1)
	check(pool.cradle != null and pool.beacon != null, "the endless pool makes the cradle and the beacon")
	for n in [1, 2, 3, 4]:
		pool.cradle.set_size(n)
		check_eq(pool.cradle.visible, n >= 3, "size %d: the cradle %s" % [n, "shows" if n >= 3 else "is hidden"])
	pool.free()
	var m1 := FakeEvents.open_pool(FakeEvents.pool_session())
	check(m1.cradle == null and m1.beacon == null, "the M1 pool makes neither")
	m1.free()


func test_caption_text_and_range() -> void:
	var pool := _s3_pool(3)
	var cradle := pool.cradle
	var caption := cradle.caption()
	check_eq(caption.text, "Your lineage began here", "the caption")
	var tm_to_am := WorldConfig.tm_to_am(3)
	for row in [[30.0, 1.0], [37.5, 0.5], [40.0, 0.0], [60.0, 0.0]]:
		cradle.update_caption(PackedFloat64Array([0.0, float(row[0]) * tm_to_am]), tm_to_am)
		check_near(caption.modulate.a, float(row[1]), 1e-6, "alpha at %.1f tm from home" % row[0])
		check_eq(caption.visible, float(row[1]) > 0.0, "shown at %.1f tm: %s" % [row[0], float(row[1]) > 0.0])
	check(caption.render_priority < CreatureView.LANE_PRIORITY, "it draws under the strike lane")
	var g := float(cradle.cradle.pool_ring.glitter_radius_bu)
	var home := pool.sim.world.local_of_abs(0.0, 0.0)
	var at := cradle.transform * caption.position
	check(Vector3(at.x, at.y, at.z).distance_to(PlaneSpace.to_world(home + Vector2(0.0, -(g + CradleView.CAPTION_GAP_BU)), CradleView.CAPTION_Y_TM)) < 1e-3,
		"at the ring's north edge, %.1f tm up" % CradleView.CAPTION_Y_TM)
	pool.free()


func test_dish_is_the_old_pool_at_true_size() -> void:
	var pool := _s3_pool(3)
	var cradle := pool.cradle
	var pieces := pool.sim.world.gen.old_pool_pieces()
	var drawn := cradle.dish_instances()
	check_eq(pieces.size(), 26, "the old pool: 18 rocks and 8 ring shells")
	check_eq(drawn.size(), pieces.size(), "every piece drawn")
	check(cradle.outside_pieces().is_empty(), "every piece inside the seam ring")
	check(cradle.dish().size() <= 11, "at most 3 rock and 8 shell MultiMeshes (%d)" % cradle.dish().size())
	var to_tm := 1.0 / WorldConfig.tm_to_am(3)
	for d: Dictionary in drawn:
		var p: Dictionary = d.piece
		var t: Transform3D = cradle.transform * (d.transform as Transform3D)
		var want := PlaneSpace.to_world(pool.sim.world.local_of_abs(float(p.x_bu), float(p.y_bu)), 0.0)
		check(Vector2(t.origin.x - want.x, t.origin.z - want.z).length() < 1e-4, "%s at its absolute place" % d.id)
		check_near(t.basis.get_scale().x, float(p.scale) * to_tm, 1e-5, "%s at its true size" % d.id)
		var mesh := (cradle.dish()[d.asset] as MultiMeshInstance3D).multimesh.mesh
		check_near(t.origin.y + mesh.get_aabb().end.y * t.basis.get_scale().y, CradleView.DISH_TOP_TM, 1e-4, "%s: its top" % d.id)
	pool.free()


func test_beacon_top_per_size() -> void:
	var pool := _s3_pool(1)
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	var top1 := _pool_box(pool.beacon, pool).end.y
	check_near(top1, HomeBeacon.TOP_BU, 0.005, "size 1: the beacon's top is the record's")
	_check_dimmed(pool.beacon, HomeBeacon.DIM, "the beacon")
	for n in [2, 3, 4]:
		check(sim.debug_force_growth(), "a growth to %d" % n)
		FakeEvents.frame(pool)
		check_eq(pool.sim_size(), n, "size %d" % n)
		check_near(_pool_box(pool.beacon, pool).end.y, top1 / WorldConfig.tm_to_am(n), 1e-3, "size %d: top / 1.6^%d" % [n, n - 1])
		var home := PlaneSpace.to_world(sim.world.local_of_abs(0.0, 0.0), 0.0)
		check(Vector2(pool.beacon.position.x - home.x, pool.beacon.position.z - home.z).length() < 1e-3, "size %d: under home" % n)
	pool.free()
	for n in [3, 4]:
		var dev := _s3_pool(n)
		check_near(_pool_box(dev.beacon, dev).end.y, HomeBeacon.top_tm(n), 0.005, "the dev's size %d: placed at its top" % n)
		dev.free()


func test_new_nodes_are_grouped() -> void:
	# At the build's size: a dev size leaves the replaced creature views queued for deletion, which
	# outside a tree keeps their lanes registered (in a game the tree unregisters them at once).
	var pool := _s3_pool(1)
	var registered := pool.world_space.registered()
	for node: Node3D in [pool.old_band, pool.cradle, pool.older_haze]:
		check(registered.has(node) and node.has_method(&"apply_growth"), "%s: a registered container" % node.name)
		check(pool.growth_containers().has(node), "%s: a growth container" % node.name)
	check(registered.has(pool.beacon) and not pool.beacon.has_method(&"apply_growth"), "the beacon: a registered leaf")
	_check_covered(pool, "with the cradle and the beacon")
	pool.free()
