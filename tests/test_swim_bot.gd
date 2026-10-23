extends TestCase
## The S1 dev bots (S1 spine 3.15; core 12.1 and C-21): SwimBot's straight swimmer and camper,
## HuntBot's zones in the pool and its endless rule, and ForageBot's endless fallback. The pool cases
## and the endless rule's arithmetic run now; the cases on an endless sim run once the endless world
## has landed (tests/test_endless_gates.gd, Gates.missing()), and until then print what they wait on.
## test_the_gates_wait_only_on_what_has_not_landed keeps that wait honest.

const Gates := preload("res://tests/test_endless_gates.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")

const SEED := 4321
const CAMP_ZONE := "z_center"
const CAMP_FROM_M := 12.0
const CAMP_ARRIVE_TICKS := 1200
const CAMP_HOLD_TICKS := 600
const GREEDY_TICKS := 3600
const GREEDY_HUNGER := 0.3            ## the greedy camper is kept hungry: energy set to this share
const GREEDY_HUNGER_EVERY := 300      ## every this many ticks, so it keeps eating

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## A new `body` lineage in the pool at `at` (no creatures unless `with_species`).
func _pool_sim(body: String, at: Vector2, with_species := false) -> PoolSim:
	var r := Lineage.found(SEED, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(at)
	var sim := PoolSim.create(r.save, catalog, layout, species if with_species else null)
	sim.drain_events()
	return sim


func _waits(what: String) -> bool:
	var gaps := Gates.missing()
	if gaps.is_empty():
		return false
	print("test-swim-bot: %s waits on: %s" % [what, "; ".join(gaps)])
	return true


func test_a_straight_swim_bot_always_asks_for_the_same_direction() -> void:
	var bot = SwimBot.new(Vector2(3.0, 4.0), 0.5)
	var full = SwimBot.new(Vector2.LEFT)
	var want := Vector2(3.0, 4.0).normalized() * 0.5
	check(want.is_equal_approx(Vector2(0.3, 0.4)), "the expected move")
	var sim := _pool_sim("omnivore", layout.spawn)
	var start := sim.motion.position
	var same := 0
	for i in 100:
		var intent: SimIntent = bot.next_intent(sim)
		same += 1 if intent.move == want and full.next_intent(sim).move == Vector2.LEFT else 0
		sim.step(intent)
		sim.drain_events()
	check_eq(same, 100, "the pool: dir.normalized() * throttle on every tick")
	check(sim.motion.position.distance_to(start) > 0.5, "the cell swam")
	if _waits("the endless straight swim"):
		return
	var endless: Variant = Gates.make_sim("omnivore", SEED)
	same = 0
	for i in 100:
		var intent: SimIntent = bot.next_intent(endless)
		same += 1 if intent.move == want else 0
		Gates.tick(endless, intent)
	check_eq(same, 100, "the endless sim: dir.normalized() * throttle on every tick")


## The first clear point CAMP_FROM_M from the zone's centre, trying 8 directions from east.
func _clear_start(center: Vector2) -> Vector2:
	var arena := layout.build_arena()
	for k in 8:
		var p := center + Vector2.from_angle(k * PI / 4.0) * CAMP_FROM_M
		if arena.is_clear(p, 0.6):
			return p
	return Vector2.INF


func test_a_camper_steers_to_its_zone_and_holds_still_inside_half_its_radius() -> void:
	var z := layout.zone(CAMP_ZONE)
	var start := _clear_start(z.center)
	check(start.is_finite(), "a clear start %.0f m from %s" % [CAMP_FROM_M, CAMP_ZONE])
	var sim := _pool_sim("omnivore", start)
	var bot = SwimBot.camper(CAMP_ZONE)
	var half := float(z.radius) * 0.5
	var arrived := -1
	for i in CAMP_ARRIVE_TICKS:
		sim.step(bot.next_intent(sim))
		sim.drain_events()
		if sim.motion.position.distance_to(z.center) <= half:
			arrived = i
			break
	check(arrived >= 0, "it arrived inside half the radius (%.2f m) from %.0f m out" % [half, CAMP_FROM_M])
	var moving_inside := 0
	var inside := 0
	for i in CAMP_HOLD_TICKS:
		var intent: SimIntent = bot.next_intent(sim)
		if sim.motion.position.distance_to(z.center) <= half:
			inside += 1
			moving_inside += 0 if intent.move == Vector2.ZERO else 1
		sim.step(intent)
		sim.drain_events()
	check_eq(moving_inside, 0, "inside half the radius it asks for no move")
	check(inside >= CAMP_HOLD_TICKS * 0.9, "it held there (%d of %d ticks)" % [inside, CAMP_HOLD_TICKS])
	print("test-swim-bot: the camper arrived in %.1f s and held %d of %d ticks inside %.2f m" % [arrived / 60.0, inside, CAMP_HOLD_TICKS, half])


func test_a_greedy_camper_eats_only_its_zones_food() -> void:
	var z := layout.zone(CAMP_ZONE)
	var sim := _pool_sim("omnivore", z.center)
	var bot = SwimBot.camper(CAMP_ZONE, true)
	var meals := 0
	var elsewhere := 0
	var farthest := 0.0
	for i in GREEDY_TICKS:
		if i % GREEDY_HUNGER_EVERY == 0:
			sim.debug_set_energy(sim.state.energy_capacity * GREEDY_HUNGER)
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			if e.type == "ate":
				meals += 1
				elsewhere += 0 if Vector2(e.position).distance_to(z.center) <= float(z.radius) else 1
		farthest = maxf(farthest, sim.motion.position.distance_to(z.center))
	print("test-swim-bot: the greedy camper ate %d times, %d elsewhere, at most %.2f m from the centre" % [meals, elsewhere, farthest])
	check(meals >= 3, "it ate (%d meals)" % meals)
	check_eq(elsewhere, 0, "every meal lay in the zone (its plankton, or carrion inside it)")
	check(farthest <= float(z.radius) + 1.0, "it never left the zone (%.2f m from the centre)" % farthest)


func test_a_camper_finds_its_zone_after_a_rebase() -> void:
	if _waits("the camper after a rebase"):
		return
	var sim: Variant = Gates.make_sim("omnivore", SEED)
	sim.debug_set_hidden(true)
	var z := Gates.zone_at(sim, PackedFloat64Array([layout.zone(CAMP_ZONE).center.x, layout.zone(CAMP_ZONE).center.y]))
	check(not z.is_empty(), "the home block's %s is loaded" % CAMP_ZONE)
	if z.is_empty():
		return
	var before: Vector2 = z.center
	check(sim.debug_rebase(Vector2i(2, 0)), "rebased by two chunks")
	sim.drain_events()
	var moved: Vector2 = sim.region.zone(str(z.id)).center
	check(moved.is_equal_approx(before - Vector2(64.0, 0.0)), "the zone's local centre moved with the origin")
	var bot = SwimBot.camper(str(z.id))
	var first: SimIntent = bot.next_intent(sim)
	var aim: Vector2 = moved - sim.motion.position
	check(first.move.dot(aim) > 0.0, "it steers toward the zone's new local centre")
	var arrived := false
	for i in CAMP_ARRIVE_TICKS:
		Gates.tick(sim, bot.next_intent(sim))
		if sim.motion.position.distance_to(sim.region.zone(str(z.id)).center) <= float(z.radius) * 0.5:
			arrived = true
			break
	check(arrived, "it arrived after the rebase")


func test_hunt_bot_keeps_its_m1_zones_in_pool_mode() -> void:
	var sim := _pool_sim("hunter", layout.spawn, true)
	var bot = HuntBot.new()
	check_eq(bot.retreat_zone_id(sim), "z_center", "retreat zone")
	check_eq(bot.patrol_zone_ids(sim), PackedStringArray(["z_n", "z_ne", "z_nw"]), "patrol zones, in order")


## The endless rule's arithmetic on the M1 pool's own zones and sites: the unguarded zone is
## z_center, the territorial zones are n, ne and nw, nearest first (another order than PATROL's,
## which is why the pool keeps its constants, C-21).
func test_hunt_bot_endless_rule_picks_the_m1_pools_unguarded_and_territorial_zones() -> void:
	var reach: Array = []
	var territories: Array = []
	for s in species.sites:
		reach.append(species.reach_disc(s, layout))
		var t := species.territory_of(s, layout)
		if not t.is_empty():
			territories.append(t)
	check_eq(HuntBot.endless_retreat_zone(layout.spawn, layout.zones, reach), "z_center", "retreat")
	var patrol: PackedStringArray = HuntBot.endless_patrol_zones(layout.spawn, layout.zones, territories)
	var sorted := Array(patrol)
	sorted.sort()
	check_eq(sorted, ["z_n", "z_ne", "z_nw"], "the territorial zones")
	for i in range(1, patrol.size()):
		var a := layout.spawn.distance_to(layout.zone(patrol[i - 1]).center)
		var b := layout.spawn.distance_to(layout.zone(patrol[i]).center)
		check(a < b or (a == b and patrol[i - 1] < patrol[i]), "nearest first, ties by id: %s" % patrol)
	print("test-swim-bot: from the spawn the endless rule retreats to z_center and patrols %s (PATROL is %s)" % [patrol, HuntBot.PATROL])


func test_hunt_bot_endless_rule_ties_counts_and_live_sites() -> void:
	var zones := [
		{"id": "b", "center": Vector2(10, 0), "radius": 4.0}, {"id": "a", "center": Vector2(-10, 0), "radius": 4.0},
		{"id": "c", "center": Vector2(0, 20), "radius": 4.0}, {"id": "d", "center": Vector2(0, 30), "radius": 4.0},
		{"id": "e", "center": Vector2(0, -5), "radius": 4.0},
	]
	var everywhere := [{"center": Vector2.ZERO, "radius": 100.0}]
	check_eq(HuntBot.endless_patrol_zones(Vector2.ZERO, zones, everywhere), PackedStringArray(["e", "a", "b"]),
		"the 3 nearest, ties by id")
	check_eq(HuntBot.endless_patrol_zones(Vector2.ZERO, zones, everywhere, 5), PackedStringArray(["e", "a", "b", "c", "d"]), "all 5")
	check_eq(HuntBot.endless_patrol_zones(Vector2.ZERO, zones, []), PackedStringArray(), "no territory, no patrol")
	var guard_e := [{"center": Vector2(0, -5), "radius": 1.0}]
	check_eq(HuntBot.endless_retreat_zone(Vector2.ZERO, zones, guard_e), "a", "the nearest unguarded, ties by id")
	check_eq(HuntBot.endless_retreat_zone(Vector2.ZERO, zones, everywhere), "", "every zone guarded")
	var edge := [{"center": Vector2(0, -5), "radius": 0.0}]
	check_eq(HuntBot.endless_retreat_zone(Vector2.ZERO, zones, edge), "e", "a centre on a disc's edge is not covered")
	var world := _SizedWorld.new()
	check(HuntBot._live({"sizes": [1, 2]}, world), "a site live at sizes 1 and 2 is live at size 1")
	check(HuntBot._live({"sizes": [1.0]}, world), "sizes read from JSON as floats")
	check(not HuntBot._live({"sizes": [2]}, world), "a size-2 site is not live at size 1")
	check(not HuntBot._live({}, world), "a site with no sizes is not live")


class _SizedWorld extends RefCounted:
	var size := 1


func test_hunt_bot_in_endless_mode_retreats_to_an_unguarded_zone_and_patrols_territories() -> void:
	if _waits("HuntBot on the endless world"):
		return
	var sim: Variant = Gates.make_sim("hunter", SEED)
	var bot = HuntBot.new()
	var reach: Array = HuntBot.live_site_discs(sim, "reach")
	var territories: Array = HuntBot.live_site_discs(sim, "territory")
	check(not territories.is_empty(), "at home the M1 rammers' territories are loaded")
	var retreat: String = bot.retreat_zone_id(sim)
	check(not retreat.is_empty(), "a retreat zone")
	if not retreat.is_empty():
		check(not Gates.covered(sim.region.zone(retreat).center, reach), "no live reach disc covers %s" % retreat)
	var patrol: PackedStringArray = bot.patrol_zone_ids(sim)
	check(patrol.size() >= 1 and patrol.size() <= 3, "1 to 3 patrol zones: %s" % patrol)
	var last := -1.0
	for id in patrol:
		var c: Vector2 = sim.region.zone(id).center
		check(Gates.covered(c, territories) or _on_edge(c, territories), "%s lies in a territory" % id)
		var d: float = sim.motion.position.distance_to(c)
		check(d >= last, "nearest first")
		last = d
	print("test-swim-bot: endless HuntBot at home: retreat %s, patrol %s" % [retreat, patrol])


static func _on_edge(p: Vector2, discs: Array) -> bool:
	for disc in discs:
		if is_equal_approx(p.distance_to(disc.center), float(disc.radius)):
			return true
	return false


func test_forage_bot_falls_back_to_the_cell_in_endless_mode() -> void:
	if _waits("ForageBot's endless fallback"):
		return
	var sim: Variant = Gates.make_sim("grazer", SEED)
	for item in sim.plankton.items.duplicate():
		sim.plankton.consume(item.id)
	for item in sim.carrion.items.duplicate():
		sim.carrion.consume(item.id)
	for z in sim.region.zones.duplicate():
		sim.region.remove_zone(z.id)
	check(sim.region.zones.is_empty(), "no food zone is loaded")
	var intent: SimIntent = ForageBot.new().next_intent(sim)
	check_eq(intent.move, Vector2.ZERO, "with nothing to eat and no zone it waits where it is")
