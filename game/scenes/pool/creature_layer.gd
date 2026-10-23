class_name CreatureLayer
extends Node3D
## The pool's creatures on screen (M1 step 3): one CreatureView per live creature in the sim's
## CreatureField, built when the pool attaches (the starting population, shown at once) and on each
## creature_spawned (faded in over the species data's fade_in_s), and let go on creature_died (it
## shrinks and frees itself) or creature_removed. Each frame sync() draws every view between the
## sim's last two ticks and poses it from its brain. It only draws; PoolScene routes the events.
##
## A pool without species (the step 2 pool) has no CreatureField, and the layer stays empty.
##
## Across a rebase (S1) the live views need nothing, since sync() places them from the sim each
## frame; the two things that keep a place of their own are registered with the pool's WorldSpace:
## each view's strike lane (top_level, set in local coordinates when shown) and each dying view,
## which is no longer synced. A sleeper (Creature.asleep, at least 44 tm out) is not drawn: its view
## hides on creature_slept and shows on creature_woke, placed where it woke with no slide.
##
## Growth (S2, s2-view 5): every view is drawn at its species' q at the cell's size, inked while it
## can attack the cell and rimmed while the cell can eat it (apply_relations). At a growth a view
## converts with its creature: a remnant (drawn from sim.remnants each frame, limp from
## LIMP_DELAY_S), a morsel (drawn where its carrion item lies, fading out when it is eaten or rots)
## or haze (it fades out). A creature removed by the growth or a remnant that swims off fades out
## where it was; one removed for any other reason goes at once.

## The moment after a growth's start when relations change and remnants go limp (GrowthBeat's
## RELATIONS_S) and how long the limp look takes to fade in.
const LIMP_DELAY_S := 2.0
const LIMP_FADE_S := 1.0
## A view leaving with its creature at a growth (removed, haze, a morsel eaten) fades this long.
const LEAVE_S := 0.6
## creature_removed reasons whose view fades out instead of going at once.
const FADING_REMOVALS: PackedStringArray = ["growth", "remnant_left"]

const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")

var sim: PoolSim
var catalog: PartCatalog
## The pool's WorldSpace, or null (a layer outside a pool: nothing shifts).
var world_space: WorldSpace

var _views := {}   ## creature id -> CreatureView, live creatures only
var _remnant_views := {}   ## remnant id -> CreatureView (S2)
var _morsel_views := {}    ## carrion item id -> CreatureView (S2)


## Starts drawing `p_sim`'s creatures: a view for each one alive now, placed at its current tick.
## `p_world_space` shifts the lanes and dying views across a rebase.
func attach(p_sim: PoolSim, p_world_space: WorldSpace = null) -> void:
	clear()
	sim = p_sim
	world_space = p_world_space
	catalog = sim.catalog
	if sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if not c.asleep:
			_add_view(c)


## Frees every view, dying ones included.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_views.clear()
	_remnant_views.clear()
	_morsel_views.clear()


## The cell's size now (the world's; 1 in the pool).
func size() -> int:
	return sim.world.size if sim != null and sim.world != null else 1


## A remnant's view (S2), or null.
func remnant_view(id: String) -> CreatureView:
	return _remnant_views.get(id)


## A morsel's view by its carrion item id (S2), or null.
func morsel_view(food_id: String) -> CreatureView:
	return _morsel_views.get(food_id)


## What a creature of `species_id` drawn at `q` is to the cell of size n: {"can_attack", "rimmed"}.
## It can attack only at its entry size (Relationships.can_attack_player); the cell can eat it when
## it is prey or a morsel at this size and the cell has a jaw (D-52). A remnant or a morsel never
## attacks.
static func relation_of(species: SpeciesCatalog, species_id: String, q: float, radius: float, n: int,
		cell: Phenotype, converted := false) -> Dictionary:
	var role := Relationships.ladder_role(species.entry_size(species_id), n, radius)
	return {"can_attack": Relationships.can_attack_player(q) and not converted,
		"rimmed": role in ["prey", "morsel"] and cell.can_eat("meat")}


## A growth re-expressed the world round `center_old` by 1 / `factor` (growth_began): every view
## is drawn factor times smaller where it was, so a view the tick removes or converts leaves from
## the right place; the live ones are placed from the sim again on the next sync.
func apply_growth(center_old: Vector2, factor: float) -> void:
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if is_instance_valid(view):
				view.set_q(view.view_q / factor)
				view.position = WorldSpace.reexpress_point(view.position, center_old, factor)


## Sets every view's ink and rim for the cell at size n, fading over `fade_s` (0: at once).
func apply_relations(n: int, fade_s: float) -> void:
	if sim == null or sim.species == null:
		return
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if is_instance_valid(view) and not view.leaving():
				_relate(view, n, fade_s)


## A view's relation at size n, from its species' q at n (so it holds before the view is redrawn at
## that size); a morsel's from the radius its carrion item has.
func _relate(view: CreatureView, n: int, fade_s: float) -> void:
	var morsel := view.morsel_id != ""
	var q := view.view_q if morsel else sim.species.q_of(view.species_id, n)
	var r := relation_of(sim.species, view.species_id, q, view.radius if morsel else view.radius_at(q), n,
		sim.phenotype, view.remnant or morsel)
	view.set_relation(r.can_attack, r.rimmed, fade_s)


## The rimmed views (live, remnants and morsels) whose centres lie on a `screen`-sized view of
## `camera`, nearest the cell first, at most `max_count`.
func rimmed_in_view(camera: Camera3D, screen: Vector2, max_count: int) -> Array[CreatureView]:
	var found: Array[CreatureView] = []
	for view in views_in_view(camera, screen):
		if view.rimmed():
			found.append(view)
	var cell := PlaneSpace.to_world(sim.motion.position) if sim != null else Vector3.ZERO
	found.sort_custom(func(a: CreatureView, b: CreatureView) -> bool:
		return a.position.distance_squared_to(cell) < b.position.distance_squared_to(cell))
	return found.slice(0, max_count)


## Every drawn view (live, remnants and morsels, none leaving) whose centre lies on a `screen`-sized
## view of `camera`.
func views_in_view(camera: Camera3D, screen: Vector2) -> Array[CreatureView]:
	var out: Array[CreatureView] = []
	var eye := camera.global_transform if camera.is_inside_tree() else camera.transform
	var to_view := eye.affine_inverse()
	var project := Projection.create_perspective(camera.fov, screen.aspect(), camera.near, camera.far)
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if not is_instance_valid(view) or not view.visible or view.leaving() or view.dying:
				continue
			var v := to_view * view.position
			if v.z >= 0.0:
				continue
			var clip := project * Vector4(v.x, v.y, v.z, 1.0)
			var ndc := Vector2(clip.x, clip.y) / clip.w
			if absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0:
				out.append(view)
	return out


## The live creature's view, or null.
func view_of(id: String) -> CreatureView:
	return _views.get(id)


## Live views of awake creatures in creature order (dying views and sleepers are not counted).
func views() -> Array[CreatureView]:
	var out: Array[CreatureView] = []
	if sim == null or sim.creatures == null:
		return out
	for c in sim.creatures.creatures:
		if _views.has(c.id) and not c.asleep:
			out.append(_views[c.id])
	return out


## Reacts to one sim event (PoolScene._route calls it for every event).
func on_event(event: Dictionary) -> void:
	if sim == null or sim.creatures == null:
		return
	var id := str(event.get("id", ""))
	match str(event.get("type", "")):
		"creature_spawned":
			var c := sim.creatures.find(id)
			if c != null and not c.asleep and not _views.has(id):   # a sleeper is drawn when it wakes
				var view := _add_view(c)
				view.fade_in(sim.species.fade_in_ticks * PoolSim.DT)
		"creature_died":
			# A remnant dies with its creature's id (D-28), so its view dies the same way.
			var view: CreatureView = _views.get(id, _remnant_views.get(id))
			if view != null:
				_views.erase(id)
				_remnant_views.erase(id)
				view.die()
				if world_space != null:
					world_space.register(view)   # no longer synced; it leaves when it frees itself
		"creature_slept":
			var view: CreatureView = _views.get(id)
			if view != null:
				view.hide_lane()
				view.visible = false
		"creature_woke":
			var c := sim.creatures.find(id)
			if c != null:
				var view: CreatureView = _views.get(id)
				if view == null:
					view = _add_view(c)
				view.visible = true
				view.show_motion(c.motion, 1.0)   # where it woke, at once: no slide from where it slept
				view.show_brain(c.brain, sim.tick, 1.0)
		"creature_removed":
			# A death has already let its view go; this is a stuck creature taken out of sight, or
			# (S2) a sleeper or remnant leaving at a growth, which fades where it was.
			var view: CreatureView = _views.get(id, _remnant_views.get(id))
			if view != null:
				_views.erase(id)
				_remnant_views.erase(id)
				if str(event.get("reason", "")) in FADING_REMOVALS and view.visible:
					_let_go(view)
				else:
					remove_child(view)
					view.queue_free()
		"creature_converted":
			var view: CreatureView = _views.get(id)
			if view == null:
				return
			_views.erase(id)
			match str(event.get("to", "")):
				"remnant":
					_remnant_views[id] = view
					view.set_remnant(LIMP_FADE_S, LIMP_DELAY_S)
				"morsel":
					var food_id := str(event.get("food_id", ""))
					_morsel_views[food_id] = view
					view.set_morsel(food_id, float(event.get("radius", view.radius)))
				_:
					_let_go(view)
		"ate", "carrion_expired":
			var morsel: CreatureView = _morsel_views.get(str(event.get("food_id", "")))
			if morsel != null:
				_morsel_views.erase(morsel.morsel_id)
				_let_go(morsel)
		"creature_noticed":
			if event.get("target") == CreatureField.PLAYER_ID and _views.has(id):
				_views[id].show_marker()
		"creature_tell":
			if event.get("target") == CreatureField.PLAYER_ID and _views.has(id):
				_views[id].show_lane(event.lane)
		"tell_cancelled":
			if _views.has(id):
				_views[id].hide_lane()
		"creature_recovered":
			if _views.has(id):
				_views[id].hide_lane(CreatureView.LANE_FADE_S)
		"hit":
			var target_id := str(event.get("target", ""))
			var target: CreatureView = _views.get(target_id, _remnant_views.get(target_id))
			if target != null:
				target.hurt()


## Draws every live creature `fraction` of the way from the sim's previous tick to its current one
## (PoolScene's draw fraction), posed from its brain. A creature without a view (its spawn event
## was taken before the layer attached) gets one at once.
func sync(fraction: float) -> void:
	if sim == null or sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if c.asleep:
			continue
		var view: CreatureView = _views.get(c.id)
		if view == null:
			view = _add_view(c)
		view.show_motion(c.motion, fraction)
		view.show_brain(c.brain, sim.tick, fraction)
	_sync_converted(fraction)


## Pauses or resumes every view's own animation (flashes, fades, the wag).
func set_paused(paused: bool) -> void:
	for child in get_children():
		child.set_process(not paused)


func _add_view(c: CreatureField.Creature) -> CreatureView:
	var view: CreatureView = VIEW_SCENE.instantiate()
	view.name = c.id
	view.build(sim.species, c.species_id, catalog, c.id, float(sim.creatures.record_of(c.species_id).get("q", 1.0)))
	add_child(view)
	if world_space != null:
		world_space.register(view.lane())
	view.show_motion(c.motion, 1.0)
	view.show_brain(c.brain, sim.tick, 1.0)
	_views[c.id] = view
	_relate(view, size(), 0.0)
	return view


## Draws the remnants from the sim (S2: they swim off, brainless, in a still pose) and the morsels
## where their carrion items lie.
func _sync_converted(fraction: float) -> void:
	var remnants: Variant = sim.get(&"remnants")
	if remnants != null:
		for r in remnants.items:
			var view: CreatureView = _remnant_views.get(r.id)
			if view != null:
				view.show_motion(r.motion, fraction)
	for food_id in _morsel_views.keys():
		var item := sim.carrion.find(food_id) if sim.carrion != null else {}
		var view: CreatureView = _morsel_views[food_id]
		if item.is_empty():
			# Taken some way the layer heard no event for (a creature ate it): it goes all the same.
			_morsel_views.erase(food_id)
			_let_go(view)
		else:
			view.position = PlaneSpace.to_world(item.position)


## A view no longer drawn from the sim fades out where it is; WorldSpace moves it until it frees itself.
func _let_go(view: CreatureView) -> void:
	view.fade_out(LEAVE_S)
	if world_space != null:
		world_space.register(view)
