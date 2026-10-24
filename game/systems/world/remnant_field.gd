class_name RemnantField
extends RefCounted
## The remnants (S2, plan B.4 step 2): awake creatures that are rivals or prey at the cell's new size
## stay in the world for a while at that size and flee straight away from the cell. A remnant is a
## CreatureField.Creature with no brain (D-57), so combat, contacts and hits take it through the same
## code as a creature (PoolSim._combat_bodies); it never attacks, never takes the token, never
## respawns and holds no niche. It has no senses, no think and no metabolism: a tick only steers it
## away from the cell and moves it (S2G17: at most 25 us each). It leaves ("remnant_left") once no
## place of the cell is near it or sees it (D-84); `leaving` (its life or out of the default view)
## is for the snapshot and the scene and has no sim effect. Pure sim state: PoolSim owns one in the
## endless world with growth on.
##
## Positions are current-frame tm, like the creatures'.

## A creature as a remnant: its brain is null, scripted and debug false, role and site "".
class Remnant extends CreatureField.Creature:
	var flee_speed := 0.0               ## tm/s: its new speed x its species' speeds.flee (D-77)
	var leaving := false


var items: Array[Remnant] = []          ## sorted (number, id)
## Taken by PoolSim._take_field_events, like the other fields' events.
var events: Array[Dictionary] = []
var cap := 12                           ## the most a growth keeps (D-78: the rest go to haze)
var life_ticks := 1800                  ## growth.remnants.life_s in ticks (`leaving` only)


static func create(growth_cfg: Dictionary) -> RemnantField:
	var f := RemnantField.new()
	f.cap = int(growth_cfg.remnants.cap)
	f.life_ticks = CreatureBrain.ticks(growth_cfg.remnants.life_s)
	return f


## The remnant of awake creature `c` at the new size, `rec` its species' SpeciesCatalog.at_size
## record there (D-77): the same id, species and number; its position, heading and previous pose kept
## (the growth tick re-expresses them), velocity / 1.6; health min(health / 1.6, the new max), energy
## / 1.6; the record's body and reach; an idle drive. An existing remnant with that id is replaced.
func add_from(c: CreatureField.Creature, rec: Dictionary, p_tick: int) -> Remnant:
	var f := WorldConfig.GROWTH_FACTOR
	var p: Phenotype = rec.phenotype
	var r := Remnant.new()
	r.id = c.id
	r.species_id = c.species_id
	r.number = c.number
	r.phenotype = p
	r.state = ActorState.fresh(p)
	r.state.health = minf(c.state.health / f, p.max_health)
	r.state.energy = c.state.energy / f
	var m := Locomotion.MotionState.new(c.motion.position, c.motion.heading)
	m.prev_position = c.motion.prev_position
	m.prev_heading = c.motion.prev_heading
	m.velocity = c.motion.velocity / f
	r.motion = m
	r.actor = InteractionResolver.Actor.new(r.id, m.position, m.heading, p)
	r.actor.reach_scale = float(rec.reach_scale)
	r.drive = CreatureField.idle_drive(m.heading)
	r.born_tick = p_tick
	r.flee_speed = p.speed * float(rec.flee_share)
	var old := find(r.id)
	if old != null:
		items.erase(old)
	var at := 0
	while at < items.size() and (items[at].number < r.number or (items[at].number == r.number and items[at].id < r.id)):
		at += 1
	items.insert(at, r)
	return r


## Once a tick, after the creatures move (D-58): each remnant steers straight away from the cell at
## its flee speed and moves through the arena as a creature does (PoolSim.move_body: sliding along
## rocks, held at the mouth of a crack narrower than it); then those D-84 lets go leave, in order.
## Nothing moves while the dev freeze holds (C-V14).
func tick(sim: PoolSim) -> void:
	if items.is_empty() or sim.dev_ai_frozen:
		return
	var cell := sim.motion.position
	var cam: Dictionary = sim.layout.camera
	var aspect := float(sim.species.fairness.spawn_view_aspect)
	var view := ViewFootprint.corners(cell, cam, float(cam.distance), aspect)   # one view for them all
	for r in items:
		var m := r.motion
		var away := m.position - cell
		var dir := away.normalized() if away.length() > 1e-6 else Vector2.from_angle(m.heading)
		Locomotion.steer(m, dir, r.phenotype, r.flee_speed / r.phenotype.speed, PoolSim.DT)
		sim.move_body(m, r.phenotype.radius)
		r.leaving = sim.tick - r.born_tick >= life_ticks \
			or not ViewFootprint.quad_contains(view, m.position, r.phenotype.radius)
	var places := sim._player_places()
	var quads := leave_views(sim, places)
	var gone: Array[Remnant] = []
	for r in items:
		if may_leave(sim, r, places, quads):
			gone.append(r)
	for r in gone:
		remove(r, "remnant_left", sim.tick)


## D-84: from every place, `r` is at least spawn_safe_m away and outside the zoom-max view footprint
## grown by the look-ahead, the spawn view margin and its radius (the spawn rule's test, so a remnant
## never leaves where a creature could not appear).
## `quads`, when given, is leave_views(sim, places): the views made once for every remnant of a tick.
static func may_leave(sim: PoolSim, r: Remnant, places: Array[Vector2], quads: Array = []) -> bool:
	var fairness := sim.species.fairness
	var cam: Dictionary = sim.layout.camera
	var at := r.motion.position
	var margin := float(cam.look_ahead_max) + float(fairness.spawn_view_margin_m) + r.phenotype.radius
	if quads.is_empty():
		quads = leave_views(sim, places)
	for i in places.size():
		if at.distance_to(places[i]) < float(fairness.spawn_safe_m):
			return false
		if ViewFootprint.quad_contains(quads[i], at, margin):
			return false
	return true


## may_leave's zoom-max view from each place (ViewFootprint.corners), in the places' order.
static func leave_views(sim: PoolSim, places: Array[Vector2]) -> Array:
	var cam: Dictionary = sim.layout.camera
	var aspect := float(sim.species.fairness.spawn_view_aspect)
	var out := []
	for place in places:
		out.append(ViewFootprint.corners(place, cam, float(cam.zoom_max), aspect))
	return out


func find(id: String) -> Remnant:
	for r in items:
		if r.id == id:
			return r
	return null


## Takes `r` out: creature_removed {id, species, reason, position}. Reasons: "remnant_left", "killed"
## (after PoolSim reported the death), "unloaded" (a teleport).
func remove(r: Remnant, reason: String, _tick: int) -> void:
	var at := items.find(r)
	if at < 0:
		return
	items.remove_at(at)
	events.append({"type": "creature_removed", "id": r.id, "species": r.species_id, "reason": reason,
		"position": r.motion.position})


## The remnants for the endless snapshot (spine 3.12), in (number, id) order, with no vectors.
func snapshot() -> Array:
	var out := []
	for r in items:
		var m := r.motion
		out.append({"id": r.id, "species": r.species_id, "number": r.number,
			"position": [m.position.x, m.position.y], "prev_position": [m.prev_position.x, m.prev_position.y],
			"velocity": [m.velocity.x, m.velocity.y], "heading": m.heading, "radius": r.phenotype.radius,
			"health": r.state.health, "flee_speed": r.flee_speed, "born_tick": r.born_tick, "leaving": r.leaving})
	return out
