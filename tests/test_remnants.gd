extends TestCase
## Remnants (S2 T2.4; game/systems/world/remnant_field.gd): a creature left by a growth keeps its
## id and pose at its next-size body (D-77), flees straight away from the cell, never attacks, takes
## no token or niche and never respawns, and leaves only where no place of the cell is near it or
## sees it (D-84, S2G11). Combat and contacts take it with the creatures (D-57); a kill drops one
## carrion item. It stands still under the dev freeze (C-V14); rebase and teleport carry it, and the
## snapshot lists it only with growth.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 6203

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _sim() -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array(), 4, true)
	sim.drain_events()
	return sim


## A dev `species_id` at `d` tm from the cell at `angle`, taken out of the field and made a remnant
## at size 2, as the growth tick does; null when the spot is not clear.
func _remnant(sim: PoolSim, d: float, angle := 0.0, species_id := "rammer") -> RemnantField.Remnant:
	var p := sim.motion.position + Vector2.from_angle(angle) * d
	if not sim.debug_spawn_creature(species_id, p, angle):
		return null
	var ev := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "debug" and e.command == "spawn_creature")
	var c := sim.creatures.find(str(ev[0].id))
	sim.creatures.take_for_growth(c)
	return sim.remnants.add_from(c, sim.species.at_size(species_id, 2), sim.tick)


static func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_a_remnant_keeps_its_creature_at_its_next_size_body() -> void:
	var sim := _sim()
	var p := sim.motion.position + Vector2(9.0, 0.0)
	check(sim.debug_spawn_creature("rammer", p, 0.7), "a dev rammer")
	var c := sim.creatures.find(str(sim.drain_events()[-1].id))
	c.motion.velocity = Vector2(0.8, -0.4)
	c.motion.prev_position = p - Vector2(0.01, 0.0)
	c.motion.prev_heading = 0.65
	c.state.health = c.state.max_health * 0.9
	c.state.energy = 7.0
	var rec := species.at_size("rammer", 2)
	var r := sim.remnants.add_from(c, rec, 77)
	check_eq([r.id, r.species_id, r.number], [c.id, c.species_id, c.number], "id, species and number")
	check_eq([r.motion.position, r.motion.heading, r.motion.prev_position, r.motion.prev_heading],
		[c.motion.position, c.motion.heading, c.motion.prev_position, c.motion.prev_heading], "its pose and previous pose")
	check_eq(r.motion.velocity, c.motion.velocity / 1.6, "velocity / 1.6")
	check(is_same(r.phenotype, rec.phenotype), "the at_size body itself (D-77)")
	check_eq(r.state.health, minf(c.state.health / 1.6, rec.phenotype.max_health), "health / 1.6 within the new max")
	check_eq(r.state.energy, 7.0 / 1.6, "energy / 1.6")
	check_eq(r.actor.reach_scale, rec.reach_scale, "its reach at the new size")
	check_eq(r.actor.position, r.motion.position, "its actor where it is")
	check_eq(r.flee_speed, rec.phenotype.speed * float(rec.flee_share), "flee speed: new speed x speeds.flee")
	check(r.brain == null and not r.scripted and not r.debug, "no brain, not scripted, not debug")
	check(r.role.is_empty() and r.site_id.is_empty(), "no niche, no site")
	check_eq(r.born_tick, 77, "born on the growth tick")
	check_eq(sim.remnants.cap, 12, "the cap from the world file")
	# Ordered (number, id); a second remnant of the same id replaces the first.
	var again := sim.remnants.add_from(c, rec, 78)
	check_eq(sim.remnants.items.size(), 1, "one remnant per id")
	check(sim.remnants.find(c.id) == again, "the newer one")
	for i in 3:
		_remnant(sim, 14.0 + 3.0 * i, PI)
	var keys := sim.remnants.items.map(func(x: RemnantField.Remnant) -> Array: return [x.number, x.id])
	var sorted := keys.duplicate()
	sorted.sort()
	check_eq(keys, sorted, "items sorted (number, id)")


func test_it_flees_straight_away_and_stands_still_under_the_freeze() -> void:
	var sim := _sim()
	var r := _remnant(sim, 4.0, 0.3)
	check(r != null, "a remnant 4 tm off")
	if r == null:
		return
	var start := r.motion.position
	var away := (start - sim.motion.position).normalized()
	for t in 60:
		sim.step(SimIntent.new())
	var moved := r.motion.position - start
	check(moved.length() > 0.5, "it swam (%.2f tm)" % moved.length())
	check(absf(moved.normalized().angle_to(away)) < 0.05, "straight away from the cell (%.3f rad)" % moved.normalized().angle_to(away))
	check(r.motion.velocity.length() <= r.flee_speed + 1e-4, "no faster than its flee speed")
	sim.debug_set_ai_frozen(true)
	var held := r.motion.position
	for t in 30:
		sim.step(SimIntent.new())
	check_eq(r.motion.position, held, "it stands still while the AI is frozen (C-V14)")


## S2G11: over a long run beside the cell a remnant never attacks, never takes the token, holds no
## niche and, once gone, never comes back.
func test_it_never_attacks_takes_the_token_holds_a_niche_or_respawns() -> void:
	var sim := _sim()
	var niches := sim.region.niches.duplicate(true)
	var r := _remnant(sim, 1.5, 0.0)
	check(r != null, "a remnant beside the cell")
	if r == null:
		return
	check_eq(sim.region.niches, niches, "it holds no niche slot")
	var id := r.id
	var gone_at := -1
	var bad := []
	for t in 2400:
		sim.step(SimIntent.new(Vector2.from_angle(0.0) if t % 120 < 60 else Vector2.ZERO))
		for e in sim.drain_events():
			if e.type == "hit" and e.attacker == id:
				bad.append("tick %d: it hit %s" % [t, e.target])
			if e.type in ["creature_tell", "creature_strike"] and e.id == id:
				bad.append("tick %d: %s" % [t, e.type])
			if e.type == "creature_spawned" and e.id == id:
				bad.append("tick %d: it came back" % t)
			if e.type == "creature_removed" and e.id == id:
				gone_at = t
		if sim.creatures.engaged_on_player.has(id):
			bad.append("tick %d: it holds the token" % t)
		if gone_at >= 0 and (sim.creatures.find(id) != null or sim.remnants.find(id) != null):
			bad.append("tick %d: it is back" % t)
	check(bad.is_empty(), "%s" % [bad.slice(0, 3)])
	check(gone_at >= 0, "it left")


## D-84: it leaves only when every place of the cell is at least spawn_safe_m away and does not see
## it (the zoom-max footprint grown by the look-ahead, the spawn margin and its radius); its life and
## the default view only set `leaving`.
func test_it_leaves_only_out_of_reach_and_out_of_every_view() -> void:
	var sim := _sim()
	var r := _remnant(sim, 8.0, PI / 2.0)
	check(r != null, "a remnant")
	if r == null:
		return
	var cam: Dictionary = layout.camera
	var fair := species.fairness
	var cell := sim.motion.position
	var margin := float(cam.look_ahead_max) + float(fair.spawn_view_margin_m) + r.phenotype.radius
	var places: Array[Vector2] = [cell]
	# A spot beyond spawn_safe_m that the zoom-max view still holds, and one it does not.
	var seen := Vector2.INF
	var unseen := Vector2.INF
	for i in 72:
		var dir := Vector2.from_angle(TAU * i / 72.0)
		var p := cell + dir * (float(fair.spawn_safe_m) + 2.0)
		var inside := ViewFootprint.contains(cell, p, cam, float(cam.zoom_max), float(fair.spawn_view_aspect), margin)
		if inside and not seen.is_finite():
			seen = p
		if not inside and not unseen.is_finite():
			unseen = p
	check(seen.is_finite() and unseen.is_finite(), "both spots exist")
	r.motion.position = cell + Vector2(float(fair.spawn_safe_m) - 1.0, 0.0)
	check(not RemnantField.may_leave(sim, r, places), "inside spawn_safe_m it stays")
	r.motion.position = seen
	check(not RemnantField.may_leave(sim, r, places), "in the zoom-max view beyond spawn_safe_m it stays")
	r.motion.position = unseen
	check(RemnantField.may_leave(sim, r, places), "out of reach and out of view it may leave")
	var two: Array[Vector2] = [cell, unseen + Vector2(3.0, 0.0)]
	check(not RemnantField.may_leave(sim, r, two), "any place near it keeps it")
	# Its life alone does nothing: an old remnant in view stays, `leaving` set.
	r.motion.position = seen
	r.born_tick = sim.tick - sim.remnants.life_ticks - 1
	r.flee_speed = 0.0
	sim.step(SimIntent.new())
	check(sim.remnants.find(r.id) != null, "past its life_s, in view: still here")
	check(r.leaving, "leaving is set")
	r.motion.position = unseen + (unseen - cell).normalized() * 30.0
	sim.step(SimIntent.new())
	check(sim.remnants.find(r.id) == null, "out of reach and view: gone")
	var removed := _of(sim.drain_events(), "creature_removed")
	check(removed.size() == 1 and removed[0].reason == "remnant_left" and removed[0].id == r.id, "creature_removed remnant_left")


func test_the_cell_bites_a_remnant_to_death_and_it_drops_one_carrion_item() -> void:
	var sim := _sim()
	var r := _remnant(sim, sim.phenotype.radius + 0.3, sim.motion.heading)
	check(r != null, "a remnant just ahead")
	if r == null:
		return
	r.flee_speed = 0.0
	r.state.health = 0.01
	var kills := int(sim.stats.kills)
	var died: Array[Dictionary] = []
	var all: Array[Dictionary] = []
	for t in 30:
		sim.step(SimIntent.new())
		var ev := sim.drain_events()
		all.append_array(ev)
		died.append_array(_of(ev, "creature_died"))
		if not died.is_empty():
			break
	check_eq(died.size(), 1, "it died")
	if died.is_empty():
		return
	var d := died[0]
	check_eq([d.id, d.species, d.cause, d.by], [r.id, r.species_id, "killed", CreatureField.PLAYER_ID], "creature_died")
	check_eq((d.carcass as Array).size(), 1, "one carcass item")
	var item := sim.carrion.find(str(d.carcass[0]))
	check(not item.is_empty(), "in the carrion field")
	if not item.is_empty():
		check_eq(item.radius, minf(r.phenotype.radius, PoolSim.MAX_FOOD_RADIUS), "radius min(r, MAX_FOOD_RADIUS)")
		check_eq(item.energy, sim.carrion.energy * r.phenotype.radius / Relationships.PLAYER_RADIUS, "energy by its radius")
	check(sim.remnants.find(r.id) == null, "it left the remnants")
	var removed := _of(all, "creature_removed")
	check(removed.size() == 1 and removed[0].reason == "killed", "creature_removed killed")
	check_eq(int(sim.stats.kills), kills + 1, "a kill")


func test_contacts_push_a_remnant_and_the_growth_checks_see_it() -> void:
	var sim := _sim()
	sim.debug_set_ai_frozen(true)
	var r := _remnant(sim, sim.phenotype.radius, 0.0)
	check(r != null, "a remnant overlapping the cell")
	if r == null:
		return
	check_eq(sim.growth.blocker_of(sim, false), "hunted", "a touching remnant hunts (no growth beside it)")
	sim.step(SimIntent.new())
	var gap := sim.motion.position.distance_to(r.motion.position)
	check(gap >= sim.phenotype.radius + r.phenotype.radius - 1e-3, "contacts pushed it clear (%.4f)" % gap)
	r.motion.position = sim.motion.position + Vector2(10.0, 0.0)
	var g := sim.growth
	var window := int(g.cfg.chase_window_ticks)
	var hit := false
	for t in window + 5:
		r.motion.position -= Vector2((float(g.cfg.chase_close_tm) + 0.3) / window, 0.0)
		sim.step(SimIntent.new())
		hit = hit or g.blocker_of(sim, false) == "chasing"
	check(hit, "closing on a remnant is chasing (it always flees)")


func test_rebase_and_teleport_carry_remnants_and_the_snapshot_lists_them() -> void:
	var sim := _sim()
	var r := _remnant(sim, 6.0, 1.0)
	check(r != null, "a remnant")
	if r == null:
		return
	var at := r.motion.position
	var prev := r.motion.prev_position
	sim.world.rebase(sim, Vector2(32.0, -32.0))
	check_eq(r.motion.position, at - Vector2(32.0, -32.0), "rebase shifts it")
	check_eq(r.motion.prev_position, prev - Vector2(32.0, -32.0), "and its previous position")
	check_eq(r.actor.position, r.motion.position, "and its actor")
	var snap: Array = sim.snapshot().world.remnants
	check_eq(snap.size(), 1, "the snapshot lists it")
	var keys: Array = snap[0].keys()
	keys.sort()
	check_eq(keys, ["born_tick", "flee_speed", "heading", "health", "id", "leaving", "number", "position",
		"prev_position", "radius", "species", "velocity"], "with spine 3.12's keys")
	check(not JSON.stringify(snap).contains("("), "and no vectors")
	sim.drain_events()
	var a := sim.absolute_position_am()
	sim.world.teleport(sim, a[0] + 5000.0, a[1])
	check(sim.remnants.items.is_empty(), "a teleport takes every remnant")
	var removed := _of(sim.drain_events(), "creature_removed").filter(func(e: Dictionary) -> bool: return e.id == r.id)
	check(removed.size() == 1 and removed[0].reason == "unloaded", "as unloaded")
	var off := FakeWorldGen.endless_sim(SEED, catalog, layout, species)
	check(off.remnants == null and not off.snapshot().world.has("remnants"), "growth off: no remnants (BP-20)")
