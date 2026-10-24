extends TestCase
## The M1 step 2 acceptance items, proven on the simulation without a scene: each body starts and
## eats, a zone empties and regrows, a starving cell can recover, and feeding always goes through
## the resolver. ForageBot (game/dev) stands in for the player.

const ForageBot := preload("res://game/dev/forage_bot.gd")
const ReachGrid := preload("res://tests/reach_grid.gd")
const SaveFolder := preload("res://tests/save_folder.gd")
const FIXTURE := "res://tests/fixtures/pool_test_small.json"
const DT := PoolSim.DT
const SPEED_EPSILON := 0.01   ## m/s
const STEP_COST_LIMIT_US := 1000.0
const APPROACH_M := 4.0       ## a cell swimming at food starts this far away
const SHORT_CARRION_LIFETIME_S := 1.0
const LONE_CARRION_AT := Vector2(8.0, 0.0)   ## clear of the fixture zone and its plankton

var catalog: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()


func after_each() -> void:
	SaveFolder.clear()


## A new lineage at the layout spawn, as GameSession starts one.
func _sim(body: String, seed_value: int, p_layout: PoolLayout = null) -> PoolSim:
	var use := p_layout if p_layout != null else layout
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(use.spawn)
	return PoolSim.create(r.save, catalog, use)


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## Food records the debug panel and tests compare: what exists and how much is left.
func _world(sim: PoolSim) -> Dictionary:
	var ids := []
	for item in sim.plankton.items:
		ids.append(item.id)
	for item in sim.carrion.items:
		ids.append(item.id)
	var amounts := []
	for z in sim.region.zones:
		amounts.append(z.amount)
	return {"ids": ids, "amounts": amounts}


func _item(sim: PoolSim, id: String) -> Dictionary:
	for item in sim.plankton.items:
		if item.id == id:
			return item
	return {}


## The first plankton item of a zone with no other food within `room` meters, so tests that
## touch it touch nothing else.
func _lonely_plant(sim: PoolSim, zone_id: String, room: float = 2.0) -> Dictionary:
	var everything := sim.plankton.items + sim.carrion.items
	for item in sim.plankton.items:
		if item.zone != zone_id:
			continue
		var alone := true
		for other in everything:
			if other.id != item.id and other.position.distance_to(item.position) < room:
				alone = false
		if alone:
			return item
	return {}


## Puts the cell `dist` from a plankton item with the item at `relative_angle` from its heading.
func _beside(sim: PoolSim, food: Dictionary, relative_angle: float, dist: float = 0.6, heading: float = 0.0) -> bool:
	var at: Vector2 = food.position - Vector2.from_angle(heading + relative_angle) * dist
	return sim.debug_teleport(at, heading)


func test_each_body_founds_and_eats_within_twenty_seconds() -> void:
	for body in ["grazer", "hunter", "omnivore"]:
		var sim := _sim(body, 1234)
		var bot = ForageBot.new()
		var meal := {}
		for i in 20 * 60:
			var energy_before := sim.state.energy
			var points_before := sim.save.adaptation_points
			sim.step(bot.next_intent(sim))
			var ate := _events_of(sim.drain_events(), "ate")
			if ate.is_empty():
				continue
			meal = ate[0]
			check(sim.phenotype.can_eat(meal.kind), "%s ate something it can eat (%s)" % [body, meal.kind])
			check(sim.state.energy > energy_before, "%s: energy rose on that tick" % body)
			var food_points: int = layout.plankton.points if meal.kind == "plant" else layout.carrion.points
			check_eq(sim.save.adaptation_points - points_before, food_points, "%s: points rose by the food's points" % body)
			check_eq(meal.points, food_points, "%s: the event reports them" % body)
			break
		check(not meal.is_empty(), "%s ate within 20 s" % body)


func test_a_diet_refusal_changes_nothing() -> void:
	var sim := _sim("hunter", 21)
	var twin := _sim("hunter", 21)
	var food := _lonely_plant(sim, "z_n")
	check(not food.is_empty() and _beside(sim, food, 0.0), "hunter placed facing plankton")
	var reasons := []
	var touching := false
	for i in 120:
		sim.step(SimIntent.new())
		twin.step(SimIntent.new())
		for e in _events_of(sim.drain_events(), "refused"):
			reasons.append(e.reason)
			touching = touching or e.touching
		twin.drain_events()
	var diet := func(r: String) -> bool: return r == "needs a filter mouth"
	check(not reasons.is_empty() and reasons.all(diet), "refused for its diet: %s" % [reasons])
	check(touching, "while touching it")
	check_eq(_world(sim), _world(twin), "zones and items are as if it never tried")
	check_eq(sim.state.energy, twin.state.energy, "energy")
	check_eq(sim.save.adaptation_points, twin.save.adaptation_points, "points")
	check(sim.actor.cooldowns.is_empty(), "no cooldown")
	check_eq(sim.stats.energy_supplied, 0.0, "nothing supplied")


## The diet refusal is reported from beyond touch range too (diet comes before reach), and that
## early report must not hold back the one that comes when the cell touches the food: diet hints
## show only while touching, so a short brush past would otherwise go unexplained. Swimming on
## and away is not news, so the usual REFUSAL_REPEAT_S spacing holds from that touch on.
func test_a_hunter_swimming_through_plankton_is_refused_while_touching_from_the_first_touch() -> void:
	var sim := _sim("hunter", 21)
	var food := _lonely_plant(sim, "z_n")
	check(not food.is_empty() and _beside(sim, food, 0.0, APPROACH_M), "hunter placed %.0f m from plankton, facing it" % APPROACH_M)
	var touch := sim.phenotype.radius + float(food.radius) + PoolSim.TOUCH_MARGIN
	var reports := []   # [sim time, touching then, event] for this food
	var first_touch_at := -1.0
	var left_at := -1.0
	for i in 2 * roundi(APPROACH_M / sim.phenotype.speed / DT) + 60:
		sim.step(SimIntent.new(Vector2.RIGHT))   # straight through it, at full throttle
		var at := (sim.tick - 1) * DT
		var touching := sim.motion.position.distance_to(_item(sim, food.id).position) <= touch
		if touching and first_touch_at < 0.0:
			first_touch_at = at
		elif not touching and first_touch_at >= 0.0 and left_at < 0.0:
			left_at = at
		for e in _events_of(sim.drain_events(), "refused"):
			if e.food_id == food.id:
				reports.append([at, touching, e])
	check(first_touch_at >= 0.0 and left_at > first_touch_at, "it swam into the plankton and out again")
	var diet := func(r: Array) -> bool: return r[2].reason == "needs a filter mouth" and r[2].touching == r[1]
	check(not reports.is_empty() and reports.all(diet), "every report is the diet refusal, touching as measured: %s" % [reports])
	check(reports.any(func(r: Array) -> bool: return r[0] < first_touch_at), "it was refused before touching it")
	check(reports.any(func(r: Array) -> bool: return r[0] == first_touch_at and r[2].touching),
		"and again on the first tick it touched it (%.3f s): %s" % [first_touch_at, reports])
	var since_touch := reports.filter(func(r: Array) -> bool: return r[0] >= first_touch_at)
	for k in range(1, since_touch.size()):
		var gap: float = since_touch[k][0] - since_touch[k - 1][0]
		check(gap >= PoolSim.REFUSAL_REPEAT_S - 1e-6, "reported again after %.2f s, left it after %.2f s" % [gap, left_at - first_touch_at])


func test_a_zone_eaten_empty_regrows_while_the_cell_waits_nearby() -> void:
	var fixture := PoolLayout.load_from(FIXTURE)
	check(fixture.validate().is_empty(), "fixture is valid: %s" % [fixture.validate()])
	var sim := _sim("grazer", 31, fixture)
	var zone: Dictionary = fixture.zones[0]
	sim.debug_set_energy(5.0)
	var bot = ForageBot.new()
	var plant_supplied := 0.0
	var empty_tick := -1
	for i in 60 * 60:
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			if e.type == "ate" and e.kind == "plant":
				plant_supplied += e.supplied
			elif e.type == "zone_empty":
				empty_tick = sim.tick
		if empty_tick >= 0:
			break
	check(empty_tick >= 0, "the bot emptied the zone and zone_empty fired")
	check_eq(sim.stats.plankton_eaten, 3, "three items eaten")
	if empty_tick < 0:
		return
	bot.park_at = zone.center + Vector2(0.0, 6.0)
	sim.debug_set_energy(80.0)   # waiting 90 s must not starve the cell
	var first_back := -1
	var regrown := -1
	for i in 100 * 60:
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			if e.type == "ate" and e.kind == "plant":
				plant_supplied += e.supplied
			elif e.type == "zone_regrown":
				regrown = sim.tick
		if first_back < 0 and not sim.plankton.items.is_empty():
			first_back = sim.tick
		for item in sim.plankton.items:
			if item.position.distance_to(zone.center) > zone.radius + 1e-6:
				check(false, "tick %d: %s outside the zone" % [sim.tick, item.id])
				return
		if regrown >= 0:
			break
	check(sim.motion.position.distance_to(bot.park_at) < 1.0, "the cell waited 6 m away")
	var first_s := (first_back - empty_tick) * DT
	var all_s := (regrown - empty_tick) * DT
	check(first_back > 0 and first_s <= 30.0, "first item back after %.1f s" % first_s)
	check(regrown > 0 and all_s <= 90.0, "all items back after %.1f s" % all_s)
	check_eq(sim.plankton.count_in(zone.id), 3, "three items again")
	check_eq(sim.stats.plankton_eaten, 3, "the waiting cell ate nothing")
	check_near(sim.stats.plant_taken, plant_supplied, 1e-9, "plant_taken is the plankton energy supplied")


func test_a_starving_cell_swims_at_half_speed_and_recovers_by_eating() -> void:
	var grid := ReachGrid.new(layout, PoolLayout.CELL_RADIUS)
	var to_food := grid.distances_from(grid.zone_points())
	var start := Vector2.INF
	for i in grid.open.size():
		if grid.open[i] == 1 and absf(to_food[i] - 12.0) < 0.25:
			start = grid.point(i)
			break
	var sim := _sim("grazer", 41)
	check(sim.debug_teleport(start), "grazer placed 12 m from a zone at %s" % start)
	sim.debug_set_energy(0.0)
	var bot = ForageBot.new()
	var fastest_starving := 0.0
	var ate_at := -1
	var meal_tick := []
	for i in 25 * 60:
		sim.step(bot.next_intent(sim))
		var events := sim.drain_events()
		if not _events_of(events, "ate").is_empty():
			ate_at = i
			meal_tick = events.map(func(e: Dictionary) -> String: return e.type)
			break
		fastest_starving = maxf(fastest_starving, sim.display_velocity().length())
	check(ate_at >= 0 and not sim.dead, "ate before dying (after %.1f s)" % (ate_at * DT))
	check(meal_tick.find("starving_ended") > meal_tick.find("ate"), "the meal ends starving on its tick: %s" % [meal_tick])
	check(fastest_starving <= sim.phenotype.speed * ActorState.STARVING_SPEED + SPEED_EPSILON,
		"starving top speed %.3f m/s, half of %.3f" % [fastest_starving, sim.phenotype.speed])
	check(fastest_starving > sim.phenotype.speed * ActorState.STARVING_SPEED * 0.9, "it did swim at that speed")
	check(not sim.state.is_starving(), "no longer starving")
	check_eq(sim.state.speed_multiplier(), 1.0, "full speed allowed again")
	var fastest_fed := 0.0
	for i in 5 * 60:
		sim.step(bot.next_intent(sim))
		fastest_fed = maxf(fastest_fed, sim.display_velocity().length())
	check(fastest_fed > sim.phenotype.speed * ActorState.STARVING_SPEED + 0.2,
		"and it swims faster than half speed (%.2f m/s)" % fastest_fed)


func test_a_starving_hunter_recovers_from_the_worst_point_in_the_pool() -> void:
	var grid := ReachGrid.new(layout, PoolLayout.CELL_RADIUS)
	var to_food := grid.distances_from(grid.zone_points())
	var worst := -1
	for i in grid.open.size():
		if grid.open[i] == 1 and (worst < 0 or to_food[i] > to_food[worst]):
			worst = i
	for seed_value in [1, 2, 3]:
		var sim := _sim("hunter", seed_value)
		check(sim.debug_teleport(grid.point(worst)), "hunter placed at %s" % grid.point(worst))
		sim.debug_set_energy(0.0)
		var bot = ForageBot.new()
		var ate := false
		for i in 25 * 60:
			sim.step(bot.next_intent(sim))
			ate = not _events_of(sim.drain_events(), "ate").is_empty()
			if ate or sim.dead:
				break
		check(ate and not sim.dead, "seed %d: the hunter found carrion before dying" % seed_value)
		check(not sim.state.is_starving(), "seed %d: no longer starving" % seed_value)


## The starving arrow points at the nearest food the body can eat (by distance, then id). At the
## spawn the nearest food of all is carrion, so a grazer must be sent past it to plankton.
func test_the_starving_arrow_food_is_the_nearest_the_body_can_eat() -> void:
	for body in ["grazer", "hunter", "omnivore"]:
		var sim := _sim(body, 1234)
		var at := sim.motion.position
		var by_distance := sim.plankton.items + sim.carrion.items
		by_distance.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := at.distance_to(a.position)
			var db := at.distance_to(b.position)
			return da < db if da != db else str(a.id) < str(b.id))
		check_eq(by_distance[0].kind, "meat", "%s: the nearest food at the spawn is carrion" % body)
		var edible := by_distance.filter(func(item: Dictionary) -> bool: return sim.phenotype.can_eat(item.kind))
		var food := sim.nearest_edible()
		check_eq(food.get("id", ""), edible[0].id, "%s: the nearest edible food" % body)
		check(sim.phenotype.can_eat(food.get("kind", "")), "%s: can eat it (%s)" % [body, food.get("kind", "")])
		check_eq(food.get("position", Vector2.INF), edible[0].position, "%s: and where it is" % body)
	var no_carrion := PoolLayout.load_from(FIXTURE)
	check(no_carrion.carrion.initial.is_empty() and not no_carrion.carrion.interim_supply.enabled, "a pool with no carrion")
	check_eq(_sim("hunter", 1234, no_carrion).nearest_edible(), {}, "a hunter there has nothing to aim at")


func test_a_cell_that_starves_dies_once_stays_still_and_respawns_at_the_start() -> void:
	var sim := _sim("grazer", 51)
	var died := 0
	for i in 100 * 60:
		sim.step(SimIntent.new())
		died += _events_of(sim.drain_events(), "died").size()
		if sim.dead:
			break
	check(sim.dead, "with no input the cell starves to death")
	for i in 120:
		sim.step(SimIntent.new(Vector2.RIGHT))
		died += _events_of(sim.drain_events(), "died").size()
	check_eq(died, 1, "died fires exactly once")
	check_eq(sim.display_velocity(), Vector2.ZERO, "a dead cell does not move")
	var points := sim.save.adaptation_points
	sim.respawn_player()
	check(not sim.dead, "alive again")
	check_eq(sim.motion.position, layout.spawn, "at the spawn")
	check_eq(sim.motion.heading, layout.spawn_heading, "facing the start heading")
	check_near(sim.state.energy, sim.state.energy_capacity * 0.6, 1e-9, "fresh energy")
	check_eq(sim.state.health, sim.state.max_health, "full health")
	check_eq(sim.alive_s, 0.0, "alive timer reset")
	check_eq(sim.save.adaptation_points, points, "the sim alone does not apply the death rule")
	check_eq(_events_of(sim.drain_events(), "respawned").size(), 1, "respawned reported")


## A dead cell skips feeding (tick order): food in front of it stays put and earns nothing while
## the death notice is up.
func test_a_cell_that_dies_facing_food_eats_none_of_it() -> void:
	var sims: Array[PoolSim] = []
	for i in 2:
		var sim := _sim("grazer", 51)
		var food := _lonely_plant(sim, "z_n")
		check(not food.is_empty() and _beside(sim, food, 0.0), "grazer placed facing plankton")
		sim.debug_set_energy(0.0)
		sim.drain_events()
		sims.append(sim)
	var living := sims[0]
	living.step(SimIntent.new())
	check_eq(_events_of(living.drain_events(), "ate").size(), 1, "a starving cell placed there eats on the first tick")
	var dying := sims[1]
	var food_id: String = _lonely_plant(dying, "z_n").id
	dying.state.health = ActorState.STARVATION_DAMAGE * DT   # one tick of starving left
	var points := dying.save.adaptation_points
	dying.step(SimIntent.new())
	check(dying.dead, "it died on the first tick")
	var meals := _events_of(dying.drain_events(), "ate").size()
	for i in 60:
		dying.step(SimIntent.new())
		meals += _events_of(dying.drain_events(), "ate").size()
	check_eq(meals, 0, "a dead cell eats nothing")
	check(not _item(dying, food_id).is_empty(), "the food is still there")
	check_eq(dying.stats.plankton_eaten, 0, "nothing counted as eaten")
	check_eq(dying.state.energy, 0.0, "no energy gained")
	check_eq(dying.save.adaptation_points, points, "no points earned")


## Ecology runs before feeding (tick order), so carrion that rots on a tick is gone before the
## cell can bite it on that tick.
func test_carrion_that_rots_on_a_tick_cannot_be_eaten_on_that_tick() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data.carrion.lifetime_s = SHORT_CARRION_LIFETIME_S
	data.carrion.initial = [[LONE_CARRION_AT.x, LONE_CARRION_AT.y]]
	var short_lived := PoolLayout.from_dict(data)
	check(short_lived.validate().is_empty(), "a valid pool with one short-lived carrion")
	# The tick it rots on, seen from a cell that leaves it alone.
	var watch := _sim("hunter", 63, short_lived)
	var rot_tick := -1
	for i in roundi(SHORT_CARRION_LIFETIME_S / DT) + 60:
		watch.step(SimIntent.new())
		if not _events_of(watch.drain_events(), "carrion_expired").is_empty():
			rot_tick = i
			break
	check(rot_tick > 0, "it rots on tick %d" % rot_tick)
	for hungry_on in [rot_tick - 1, rot_tick]:
		var sim := _sim("hunter", 63, short_lived)
		var food: Dictionary = sim.carrion.items[0] if sim.carrion.items.size() == 1 else {}
		check(not food.is_empty() and _beside(sim, food, 0.0), "hunter placed facing the carrion")
		for i in hungry_on:
			sim.debug_set_energy(sim.state.energy_capacity)   # full: it refuses the carrion
			sim.step(SimIntent.new())
		sim.debug_set_energy(sim.state.energy_capacity * 0.5)
		sim.drain_events()
		sim.step(SimIntent.new())
		var events := sim.drain_events()
		var ate := _events_of(events, "ate")
		if hungry_on < rot_tick:
			check(ate.size() == 1 and ate[0].food_id == food.id, "hungry the tick before it rots, it eats it: %s" % [events])
		else:
			check(ate.is_empty(), "hungry on the tick it rots, it eats nothing: %s" % [events])
			check_eq(_events_of(events, "carrion_expired").size(), 1, "it rotted on that tick")


## Starving events follow every change of the starving state as it happens, so a consumer driven
## by them alone agrees with is_starving(), across a death and respawn too.
func test_starving_events_alternate_across_a_death_and_respawn() -> void:
	var sim := _sim("grazer", 51)
	var starving_events := func() -> Array:
		return sim.drain_events().map(func(e: Dictionary) -> String: return e.type) \
			.filter(func(t: String) -> bool: return t.begins_with("starving_"))
	sim.respawn_player()
	check_eq(starving_events.call(), [], "respawning a fed cell reports no change")
	sim.debug_set_energy(0.0)
	check_eq(starving_events.call(), ["starving_started"], "emptying its energy starts it at once")
	var seen := []
	for i in 100 * 60:
		sim.step(SimIntent.new())
		seen.append_array(starving_events.call())
		if sim.dead:
			break
	check(sim.dead and seen.is_empty(), "it starved to death with no other change reported: %s" % [seen])
	sim.respawn_player()
	check(not sim.state.is_starving(), "respawned fed")
	check_eq(starving_events.call(), ["starving_ended"], "respawning ends it")
	for i in 30:
		sim.step(SimIntent.new())
	check_eq(starving_events.call(), [], "nothing more while fed")
	sim.debug_set_energy(0.0)
	check_eq(starving_events.call(), ["starving_started"], "starving again starts it again")


func test_death_through_the_session_costs_a_quarter_of_the_points_and_is_recorded() -> void:
	var session := GameSession.new(SaveFolder.path("death_slot.json"))
	check(session.start_new("grazer", 52).ok, "started")
	Lineage.earn(session.sim.save, 11)
	var points := session.sim.save.adaptation_points
	check_eq(session.respawn_after_death(), 0, "no death, no penalty")
	session.sim.debug_set_energy(0.0)
	for i in 25 * 60:
		session.sim.step(SimIntent.new())
		if session.sim.dead:
			break
	check(session.sim.dead, "starved")
	check(session.dirty, "a death is an unsaved change")
	check(not session.save_now().ok, "no saving while dead")
	points = session.sim.save.adaptation_points
	var lost := session.respawn_after_death()
	check_eq(lost, floori(points * Lineage.DEATH_POINT_LOSS), "loses a quarter, rounded down")
	check_eq(session.sim.save.adaptation_points, points - lost, "points")
	var last: Dictionary = session.sim.save.lineage_history[-1]
	check_eq(last.event, "died", "history records the death")
	check_eq(last.cause, "starved", "and the cause")
	check(not session.sim.dead and session.sim.motion.position == layout.spawn, "back at the start")
	check(session.save_now().ok, "saving works again")


func test_the_same_seed_and_intents_give_the_same_world() -> void:
	var a := _sim("omnivore", 77)
	var b := _sim("omnivore", 77)
	var c := _sim("omnivore", 78)
	var bot = ForageBot.new()
	for i in 1800:
		# One script of intents (recorded from the bot driving `a`) for all three.
		var intent: SimIntent = bot.next_intent(a)
		a.step(intent)
		b.step(intent)
		c.step(intent)
		if i % 600 == 599:
			check_eq(a.state_hash(), b.state_hash(), "tick %d: same state" % i)
	check(a.stats.plankton_eaten + a.stats.carrion_eaten > 0, "the run included meals")
	var pa := []
	var pc := []
	for item in a.plankton.items:
		pa.append(item.position)
	for item in c.plankton.items:
		pc.append(item.position)
	check(pa != pc, "seed 78 puts plankton elsewhere")
	check(a.state_hash() != c.state_hash(), "and hashes differently")


func test_a_mouth_on_the_side_eats_only_food_on_that_side() -> void:
	# The fixture pool holding a single plankton item that does not drift, so nothing else is
	# ever in reach and the item stays where the cell stopped facing it.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data.zones[0].capacity = layout.plankton.unit_energy
	data.plankton.drift_amplitude = 0.0
	var one_item := PoolLayout.from_dict(data)
	check(one_item.validate().is_empty(), "a valid one-item pool")
	var save := SaveGame.new_run(61, "test+dev")
	save.genome.add_part("mouth_filter", PI / 2.0)
	save.genome.add_part("flagellum", PI)
	check(save.validate(catalog).is_empty(), "a valid custom body")
	save.player["position"] = PlaneSpace.to_save(one_item.spawn)
	var sim := PoolSim.create(save, catalog, one_item)
	check_eq(sim.plankton.items.size(), 1, "one item")
	if sim.plankton.items.size() != 1:
		return
	var food: Dictionary = sim.plankton.items[0]
	var start: Vector2 = food.position + Vector2(0.0, 2.5)
	sim.debug_teleport(start, (food.position - start).angle())
	# Each refusal's touching and contact_s are checked against the distance measured here, and
	# the refusals go through RefusalHints as the pool scene passes them.
	var touch := sim.phenotype.radius + float(food.radius) + PoolSim.TOUCH_MARGIN
	var touch_since := -1.0
	var hints := RefusalHints.new()
	var refusals := []
	var shown := []
	var meals := 0
	for i in 4 * 60:
		var target: Vector2 = _item(sim, food.id).position
		var to := target - sim.motion.position
		# Slow down to stop just short of it, mouth side or not.
		sim.step(SimIntent.new(to.normalized() * clampf((to.length() - 0.55) / 1.5, 0.0, 1.0)))
		var at := (sim.tick - 1) * DT
		var touching := sim.motion.position.distance_to(_item(sim, food.id).position) <= touch
		if not touching:
			touch_since = -1.0
		elif touch_since < 0.0:
			touch_since = at
		for e in sim.drain_events():
			if e.type == "refused":
				var contact := at - touch_since if touching else 0.0
				check(e.touching == touching and absf(e.contact_s - contact) < 1e-6,
					"%.3f s: reported touching %s for %.3f s, measured %s for %.3f s" % [at, e.touching, e.contact_s, touching, contact])
				refusals.append(e)
				shown.append(hints.consider(e, at))
			elif e.type == "ate":
				meals += 1
	check_eq(meals, 0, "swimming straight at it gives no meal")
	var last: Dictionary = refusals[-1] if not refusals.is_empty() else {}
	check_eq(last.get("reason", ""), "mouth is not facing it", "the last refusal")
	check(refusals.any(func(e: Dictionary) -> bool: return not e.touching), "in reach before touching it")
	var first_touch := refusals.find_custom(func(e: Dictionary) -> bool: return e.touching)
	check(first_touch >= 0 and shown[first_touch] == "", "while touching it, with no hint at first: %s" % [shown])
	check(refusals.any(func(e: Dictionary) -> bool: return e.touching and e.contact_s >= RefusalHints.FACING_AFTER_S),
		"and still touching it %.1f s later" % RefusalHints.FACING_AFTER_S)
	check(shown.has(RefusalHints.TEXTS["mouth is not facing it"]), "then the player is told to turn: %s" % [shown])
	check(_beside(sim, _item(sim, food.id), PI / 2.0), "placed with the food on its right")
	var ate := {}
	for i in 30:
		sim.step(SimIntent.new())
		var events := _events_of(sim.drain_events(), "ate")
		if not events.is_empty():
			ate = events[0]
			break
	check_eq(ate.get("food_id", ""), food.id, "it eats the food on its right")


func test_a_full_cell_refuses_food_and_eats_again_with_room_for_half() -> void:
	var sim := _sim("grazer", 71)
	var food := _lonely_plant(sim, "z_ne")
	check(not food.is_empty() and _beside(sim, food, 0.0), "placed facing plankton")
	sim.debug_set_energy(sim.state.energy_capacity)
	var world := _world(sim)
	var points := sim.save.adaptation_points
	var reasons := []
	for i in 30:
		sim.step(SimIntent.new())
		for e in _events_of(sim.drain_events(), "refused"):
			reasons.append(e.reason)
	var full := func(r: String) -> bool: return r == "not hungry"
	check(not reasons.is_empty() and reasons.all(full), "refused as full: %s" % [reasons])
	check_eq(_world(sim), world, "zones and items unchanged")
	check_eq(sim.save.adaptation_points, points, "points unchanged")
	check(sim.actor.cooldowns.is_empty(), "no cooldown")
	check_eq(sim.stats.energy_supplied, 0.0, "nothing supplied")
	sim.debug_set_energy(sim.state.energy_capacity - layout.plankton.unit_energy * InteractionResolver.FEED_MIN_ROOM_SHARE)
	sim.step(SimIntent.new())
	var ate := _events_of(sim.drain_events(), "ate")
	check_eq(ate.size(), 1, "with room for half the food it eats")
	if ate.size() == 1:
		check_eq(ate[0].food_id, food.id, "that food")
		check(ate[0].absorbed < ate[0].supplied, "absorbing only what fits")


func test_refusals_are_reported_sparingly_and_never_for_quiet_reasons() -> void:
	# A minute of foraging, then 10 s held full on the nearest plankton, so food it will not eat
	# touches it whatever the zones' regrowth left near it.
	var sim := _sim("omnivore", 85)
	var bot = ForageBot.new()
	var last_at := {}
	var reported := 0
	for i in 70 * 60:
		if i >= 60 * 60:
			sim.debug_set_energy(sim.state.energy_capacity)
			if i == 60 * 60:
				var items: Array = sim.plankton.items.duplicate()
				items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return a.position.distance_to(sim.motion.position) < b.position.distance_to(sim.motion.position))
				bot.park_at = items[0].position
		sim.step(bot.next_intent(sim))
		var refused := _events_of(sim.drain_events(), "refused")
		check(refused.size() <= 1, "tick %d: at most one refusal per tick" % i)
		for e in refused:
			reported += 1
			check(not PoolSim.QUIET_REASONS.has(e.reason), "'%s' is never reported" % e.reason)
			# The same refusal waits REFUSAL_REPEAT_S, except the one when the cell starts touching the
			# food after one before contact (PoolSim._note_refusal), so touching is part of the key.
			var key := "%s|%s|%s" % [e.food_id, e.reason, e.touching]
			if last_at.has(key):
				var gap: float = (i - int(last_at[key])) * DT
				check(gap >= PoolSim.REFUSAL_REPEAT_S - 1e-6, "%s repeated after %.2f s" % [key, gap])
			last_at[key] = i
	check(reported > 0, "a full omnivore met some refusals (%d)" % reported)


func test_survival_points_come_from_stepped_time_and_reset_on_respawn() -> void:
	var sim := _sim("grazer", 81)
	var earned := []
	for i in 61 * 60:
		sim.step(SimIntent.new())
		earned.append_array(_events_of(sim.drain_events(), "earned"))
	check_eq(sim.save.adaptation_points, 2, "61 s alive gives 2 points")
	check_eq(earned.size(), 2, "two earned events")
	check(earned.all(func(e: Dictionary) -> bool: return e.reason == "survival" and e.points == 1), "for survival")
	check_eq(sim.stats.points_survival, 2, "counted as survival points")
	check_near(sim.alive_s, 61.0, 1e-9, "alive time is sim time")
	# Reading the sim as a scene does every frame is not time passing.
	var alive := sim.alive_s
	var before := sim.snapshot()
	for i in 60:
		sim.drain_events()
		sim.snapshot()
		sim.nearest_edible()
	check_eq(sim.alive_s, alive, "time that is not stepped is not alive time")
	check_eq(sim.snapshot(), before, "and earns nothing and changes nothing")
	sim.respawn_player()
	check_eq(sim.alive_s, 0.0, "timer reset on respawn")
	for i in 29 * 60:
		sim.step(SimIntent.new())
	check_eq(sim.save.adaptation_points, 2, "29 s after respawn: nothing yet")
	for i in 60:
		sim.step(SimIntent.new())
	check_eq(sim.save.adaptation_points, 3, "30 s after respawn: one more")


func test_a_tick_costs_well_under_a_millisecond() -> void:
	var sim := _sim("omnivore", 91)
	var bot = ForageBot.new()
	var spent := 0
	for i in 3600:
		var intent: SimIntent = bot.next_intent(sim)
		var t0 := Time.get_ticks_usec()
		sim.step(intent)
		spent += Time.get_ticks_usec() - t0
		sim.drain_events()
	var average := spent / 3600.0
	print("test-step-cost: %.1f us per tick over 3600 ticks" % average)
	check(average <= STEP_COST_LIMIT_US, "average %.1f us per tick" % average)


# --- S3: what the stings add to the pool (D-126, D-127; S3G12d) ---

## S3G12d: the pool writes neither sting-rule tick to its snapshot, even after a strike hit, so the
## M1 goldens hold; the endless world does.
func test_a_pool_snapshot_never_carries_the_sting_rule_ticks() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	data.sites = []
	var r := Lineage.found(7, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, SpeciesCatalog.from_dict(data))
	sim.last_strike_hit_tick = 40   # as a strike hit on the cell leaves it
	sim.last_sting_tick = 41
	sim.creatures.token_closed_until = 0
	var snap := sim.snapshot()
	check(not snap.has("last_strike_hit_tick") and not snap.has("last_sting_tick"), "the pool writes neither")
	check(not snap.has("token_closed_until"), "nor an unset token closure")
	sim.creatures.token_closed_until = 161
	check_eq(sim.snapshot().get("token_closed_until", -1), 161, "a closure is written when set")


## D-127: use_entry_record is a test seam: no file under game/ calls it.
func test_no_game_file_calls_the_entry_record_seam() -> void:
	var callers := []
	var dirs := ["res://game"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir + "/" + sub)
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir + "/" + f)
			for line in text.split("\n"):
				if line.contains("use_entry_record(") and not line.begins_with("func use_entry_record("):
					callers.append("%s/%s: %s" % [dir, f, line.strip_edges()])
	check_eq(callers, [], "no caller under game/")
