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

const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")

var sim: PoolSim
var catalog: PartCatalog
## The pool's WorldSpace, or null (a layer outside a pool: nothing shifts).
var world_space: WorldSpace

var _views := {}   ## creature id -> CreatureView, live creatures only


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
			var view: CreatureView = _views.get(id)
			if view != null:
				_views.erase(id)
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
			# A death has already let its view go; this is a stuck creature taken out of sight.
			var view: CreatureView = _views.get(id)
			if view != null:
				_views.erase(id)
				remove_child(view)
				view.queue_free()
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
			var target: CreatureView = _views.get(str(event.get("target", "")))
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


## Pauses or resumes every view's own animation (flashes, fades, the wag).
func set_paused(paused: bool) -> void:
	for child in get_children():
		child.set_process(not paused)


func _add_view(c: CreatureField.Creature) -> CreatureView:
	var view: CreatureView = VIEW_SCENE.instantiate()
	view.name = c.id
	view.build(sim.species, c.species_id, catalog, c.id)
	add_child(view)
	if world_space != null:
		world_space.register(view.lane())
	view.show_motion(c.motion, 1.0)
	view.show_brain(c.brain, sim.tick, 1.0)
	_views[c.id] = view
	return view
