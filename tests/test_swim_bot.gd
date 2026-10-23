extends TestCase
## The S1 dev bots (S1 spine 3.15; core 12.1 and CC-21): SwimBot's straight swimmer, camper, homing
## swimmer, Unjam and overdrive (S1 build plan B-12), HuntBot's zones in the pool and its endless
## rule and roaming, and ForageBot's endless fallback. The pool cases (Unjam's crack among them) and
## the endless rule's arithmetic run in any tree; the cases on an endless sim run once the endless
## world they read has landed (tests/test_endless_gates.gd, Gates.missing(Gates.WORLD); they read no
## invariant, so they do not wait on T2.8), and until then print what they wait on. The overdriven
## speed test and the homing swim run on T2's FakeWorldGen, whose lane along y = 9 holds no
## collider, so no content can block the speed test.
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
const REBASE_ZONE_FROM_M := 8.0       ## the rebase camper heads for a zone at least this far off
const REBASE_AFTER_TICKS := 20        ## and is on its way when the origin moves
## The homing swimmer: from FakeWorldGen's home spawn to a point this far off (am), with a rebase on
## the way after HOMING_REBASE_AFTER ticks, within HOMING_TICKS.
const HOMING_TO := Vector2(40.0, 25.0)
const HOMING_REBASE_AFTER := 120
const HOMING_TICKS := 1500
## Unjam: a row of CRACK_ROCKS rocks of radius CRACK_R across the way at x = CRACK_X, their surfaces
## CRACK_GAP apart (less than the body is wide); the cell starts CRACK_FROM west of the row and
## heads for a point as far east of it.
const CRACK_X := 10.0
const CRACK_R := 1.0
const CRACK_GAP := 0.6
const CRACK_ROCKS := 3
const CRACK_FROM := 6.0
const CRACK_Y := 0.3                  ## off the middle rock's centre, so the way round picks a side
const CRACK_TICKS := 1500
## The roaming hunter (endless): points out in the sea with rammers asleep round them, each settled
## ROAM_SETTLE_TICKS, where the nearest patrol zone lies away from the sleeper and from home.
const ROAM_SLEEPER_AT := Vector2(348.0, -1823.0)
const ROAM_HOME_AT := Vector2(-574.0, -1810.0)
const ROAM_SETTLE_TICKS := 120
## The overdriven swim (B-12): east from FakeWorldGen's home spawn (0, 9), timed from tick 300 to 900.
const FAKE_GEN := "res://tests/fakes/fake_world_gen.gd"   ## T2's permanent test generator
const OVERDRIVE_FROM_TICK := 300
const OVERDRIVE_TO_TICK := 900
const OVERDRIVE_MIN_SPEED := 5.9

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
	var gaps := Gates.missing(Gates.WORLD)
	if gaps.is_empty():
		return false
	print("test-swim-bot: %s waits on: %s" % [what, "; ".join(gaps)])
	return true


## overdrive sets the cap and fills the energy; next_intent changes nothing, for every kind of bot.
func test_overdrive_sets_the_cap_and_fills_the_energy_and_next_intent_changes_nothing() -> void:
	var sim := _pool_sim("grazer", layout.spawn, true)
	sim.debug_set_energy(1.0)
	sim.drain_events()
	check(sim.phenotype.speed < PoolLayout.MAX_SPEED, "a grazer is slower than the cap (%.2f)" % sim.phenotype.speed)
	SwimBot.overdrive(sim)
	check_eq(sim.phenotype.speed, PoolLayout.MAX_SPEED, "overdrive sets the cap")
	check_eq(sim.state.energy, sim.state.energy_capacity, "and fills the energy")
	check(sim.actor.phenotype == sim.phenotype, "the actor shares the phenotype, so its speed is the cap too")
	for bot in [SwimBot.new(Vector2(1.0, 2.0), 0.7), SwimBot.camper(CAMP_ZONE), SwimBot.camper(CAMP_ZONE, true)]:
		for i in 30:
			var before := sim.state_hash()
			var speed := sim.phenotype.speed
			var energy := sim.state.energy
			var intent: SimIntent = bot.next_intent(sim)
			check(sim.state_hash() == before and sim.phenotype.speed == speed and sim.state.energy == energy,
				"next_intent leaves the sim as it was")
			sim.step(intent)
			sim.drain_events()


## An overdriven straight swim (B-12) averages at least 5.9 tm/s over ticks 300 to 900, on T2's
## FakeWorldGen (its lane along y = 9 holds no collider), with RACER; as it is, RACER is slower.
func test_an_overdriven_straight_swim_averages_at_least_5_9_tm_s() -> void:
	var what := Gates.missing(Gates.SIM)
	if not FileAccess.file_exists(FAKE_GEN):
		what.append("tests/fakes/fake_world_gen.gd (T2.1)")
	if not what.is_empty():
		print("test-swim-bot: the overdriven swim waits on: %s" % "; ".join(what))
		return
	var speeds := {}
	for overdriven in [true, false]:
		var sim: Variant = _fake_racer()
		var bot = SwimBot.new(Vector2.RIGHT)
		var from := PackedFloat64Array()
		for i in OVERDRIVE_TO_TICK:
			if overdriven:
				SwimBot.overdrive(sim)
			if i == OVERDRIVE_FROM_TICK:
				from = sim.absolute_position_am()
			sim.step(bot.next_intent(sim))
			sim.drain_events()
		var to: PackedFloat64Array = sim.absolute_position_am()
		speeds[overdriven] = (to[0] - from[0]) / ((OVERDRIVE_TO_TICK - OVERDRIVE_FROM_TICK) / 60.0)
		if overdriven:
			check(absf(to[1] - from[1]) < 0.01, "it swam straight east (%.3f tm off its line)" % absf(to[1] - from[1]))
	print("test-swim-bot: from tick %d to %d the overdriven racer averaged %.3f tm/s, as it is %.3f" % [
		OVERDRIVE_FROM_TICK, OVERDRIVE_TO_TICK, speeds[true], speeds[false]])
	check(float(speeds[true]) >= OVERDRIVE_MIN_SPEED, "overdriven: %.3f tm/s (at least %.1f)" % [speeds[true], OVERDRIVE_MIN_SPEED])
	check(float(speeds[false]) < OVERDRIVE_MIN_SPEED - 1.0, "as it is the racer is slower (%.3f tm/s)" % speeds[false])


## RACER, the fastest legal body, saved at FakeWorldGen's home spawn, in an endless sim on that
## generator with no creatures.
func _fake_racer() -> Variant:
	var Fake: GDScript = load(FAKE_GEN)
	var content: Variant = Fake.call("fixture_content")
	var r := Lineage.found(SEED, "test+dev", catalog, "hunter")
	Gates.make_racer(r.save.genome, catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(content.home.spawn[0], content.home.spawn[1])
	var sim: Variant = (load(Gates.POOL_SIM_PATH) as GDScript).callv("_create_endless",
		[r.save, catalog, layout, null, content, Fake.new(content, null, SEED)])
	sim.drain_events()
	return sim


## A homing swimmer reaches its absolute point through a rebase, and asks for no move once there.
func test_a_homing_swimmer_reaches_its_absolute_point_through_a_rebase() -> void:
	var what := Gates.missing(Gates.WORLD)
	if not FileAccess.file_exists(FAKE_GEN):
		what.append("tests/fakes/fake_world_gen.gd (T2.1)")
	if not what.is_empty():
		print("test-swim-bot: the homing swim waits on: %s" % "; ".join(what))
		return
	var sim: Variant = _fake_racer()
	var start: PackedFloat64Array = sim.absolute_position_am()
	var goal := PackedFloat64Array([start[0] + HOMING_TO.x, start[1] + HOMING_TO.y])
	var bot = SwimBot.toward(goal)
	var arrived := -1
	for i in HOMING_TICKS:
		if i == HOMING_REBASE_AFTER:
			check(sim.debug_rebase(Vector2i(1, 1)), "rebased on the way")
			sim.drain_events()
		var before: int = sim.state_hash()
		var intent: SimIntent = bot.next_intent(sim)
		check(sim.state_hash() == before, "next_intent leaves the sim as it was")
		if Gates.abs_distance(sim.absolute_position_am(), goal) <= SwimBot.ARRIVE_M:
			check_eq(intent.move, Vector2.ZERO, "within ARRIVE_M it asks for no move")
			arrived = i
			break
		sim.step(intent)
		sim.drain_events()
	check(arrived >= 0, "it arrived within %.1f tm of its point (%.2f tm off)" % [SwimBot.ARRIVE_M,
		Gates.abs_distance(sim.absolute_position_am(), goal)])
	print("test-swim-bot: the homing swimmer arrived %.0f tm off in %.1f s, through a rebase" % [HOMING_TO.length(), arrived / 60.0])


## A row of rocks with cracks narrower than the body: route_point alone wedges the cell in a crack;
## SwimBot.Unjam steps it aside along the row until it passes the end, and it arrives.
func test_unjam_frees_a_cell_wedged_in_a_crack_between_rocks() -> void:
	var goal := Vector2(CRACK_X + CRACK_FROM, CRACK_Y)
	var reached := {}
	var wedges := 0
	for unjam in [false, true]:
		var sim := _pool_sim("grazer", layout.spawn)
		sim.arena = PoolArena.create(layout.pool_radius, layout.soft_start, layout.hard_radius)
		var step := 2.0 * CRACK_R + CRACK_GAP
		for k in CRACK_ROCKS:
			sim.arena.add_rock("crack_%d" % k, Vector2(CRACK_X, (k - (CRACK_ROCKS - 1) / 2.0) * step), CRACK_R)
		check(2.0 * sim.phenotype.radius > CRACK_GAP, "the cracks (%.2f) are narrower than the body (%.2f)" % [
			CRACK_GAP, 2.0 * sim.phenotype.radius])
		check(sim.debug_teleport(Vector2(CRACK_X - CRACK_FROM, CRACK_Y), 0.0), "placed west of the row")
		sim.drain_events()
		var helper = SwimBot.Unjam.new()
		reached[unjam] = -1
		for i in CRACK_TICKS:
			if i % 300 == 0:
				sim.debug_set_energy(sim.state.energy_capacity)
			var pos := sim.motion.position
			if pos.distance_to(goal) <= 1.0:
				reached[unjam] = i
				break
			var aim: Vector2 = helper.aim(sim, goal) if unjam else sim.arena.route_point(pos, goal, sim.phenotype.radius)
			sim.step(SimIntent.new((aim - pos).normalized() if aim.distance_to(pos) > 1e-6 else Vector2.ZERO))
			sim.drain_events()
		wedges = helper.wedges
	check_eq(int(reached[false]), -1, "route_point alone stays wedged in a crack (the row is a real trap)")
	check(int(reached[true]) >= 0, "with Unjam the cell gets round the row")
	check(wedges >= 1, "it stepped aside (%d times)" % wedges)
	print("test-swim-bot: in the crack route_point alone never arrived; with Unjam it stepped aside %d times and arrived in %.1f s" % [
		wedges, int(reached[true]) / 60.0])


## overdrive is for tests and soak gates only: no game script but swim_bot.gd itself, and no smoke,
## names it.
func test_overdrive_is_never_called_from_game_code_or_a_smoke() -> void:
	var files := _scripts("res://game")
	files.append_array(_scripts("res://tests/smoke"))
	var own := (load("res://game/dev/swim_bot.gd") as GDScript).resource_path
	check(files.has(own), "the scan covers game/dev/swim_bot.gd")
	check(files.size() > 40, "the scan covers the game's scripts (%d)" % files.size())
	for path in files:
		if path != own:
			check(not FileAccess.get_file_as_string(path).contains("overdrive("), "%s does not call overdrive" % path)


## Every .gd under `dir`, subfolders included.
static func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


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


## A camper on its way when the origin moves keeps heading for the zone, now at a new local centre.
func test_a_camper_finds_its_zone_after_a_rebase() -> void:
	if _waits("the camper after a rebase"):
		return
	var sim: Variant = Gates.make_sim("omnivore", SEED)
	sim.debug_set_hidden(true)
	var z := {}
	var best := INF
	for zone in sim.region.zones:   # the nearest zone at least REBASE_ZONE_FROM_M away, ties by id
		var d: float = sim.motion.position.distance_to(zone.center)
		if d >= REBASE_ZONE_FROM_M and (d < best or (d == best and str(zone.id) < str(z.id))):
			best = d
			z = zone
	check(not z.is_empty(), "a zone at least %.0f m away is loaded" % REBASE_ZONE_FROM_M)
	if z.is_empty():
		return
	var id := str(z.id)
	var bot = SwimBot.camper(id)
	for i in REBASE_AFTER_TICKS:
		Gates.tick(sim, bot.next_intent(sim))
	var before: Vector2 = sim.region.zone(id).center
	check(sim.debug_rebase(Vector2i(2, 0)), "rebased by two chunks")
	sim.drain_events()
	var moved: Vector2 = sim.region.zone(id).center
	check(moved.is_equal_approx(before - Vector2(64.0, 0.0)), "the zone's local centre moved with the origin")
	var aim: Vector2 = moved - sim.motion.position
	var first: SimIntent = bot.next_intent(sim)
	check(aim.length() > float(z.radius) * 0.5 and first.move.angle_to(aim) < 0.5,
		"it steers toward the zone's new local centre (%.2f rad off)" % absf(first.move.angle_to(aim)))
	var arrived := false
	for i in CAMP_ARRIVE_TICKS:
		Gates.tick(sim, bot.next_intent(sim))
		if sim.motion.position.distance_to(sim.region.zone(id).center) <= float(z.radius) * 0.5:
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


## Endless, between hunting and patrolling: with no rammer awake it swims for the nearest sleeping
## one, and with no rammer alive in the loaded ground it heads home, not to its patrol zones.
func test_hunt_bot_in_endless_mode_wakes_sleeping_rammers_and_heads_home_with_none() -> void:
	if _waits("HuntBot roaming"):
		return
	var sim: Variant = _settled_hunter(ROAM_SLEEPER_AT)
	for c in sim.creatures.awake().duplicate():
		sim.creatures.remove(c, "evicted", sim.tick, false)
	sim.drain_events()
	var sleeper: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.asleep and c.brain.behavior == CreatureBrain.TERRITORIAL and (sleeper == null
				or sim.motion.position.distance_to(c.motion.position) < sim.motion.position.distance_to(sleeper.motion.position)):
			sleeper = c
	check(sleeper != null, "a rammer sleeps round (%.0f, %.0f)" % [ROAM_SLEEPER_AT.x, ROAM_SLEEPER_AT.y])
	if sleeper == null:
		return
	var to_sleeper: Vector2 = (sleeper.motion.position - sim.motion.position).normalized()
	var bot = HuntBot.new()
	check(_to_patrol(sim, bot).dot(to_sleeper) < 0.9, "the patrol zone lies elsewhere, so the check tells them apart")
	var move: Vector2 = bot.next_intent(sim, []).move
	print("test-swim-bot: roaming hunter: %.2f toward the sleeping rammer (the patrol zone %.2f)" % [
		move.dot(to_sleeper), _to_patrol(sim, bot).dot(to_sleeper)])
	check(move.dot(to_sleeper) > 0.95, "it swims for the nearest sleeping rammer")
	sim = _settled_hunter(ROAM_HOME_AT)
	for c in sim.creatures.creatures.duplicate():
		sim.creatures.remove(c, "evicted", sim.tick, false)
	sim.drain_events()
	var home: Vector2 = (sim.world.local_of_abs(0.0, 0.0) - sim.motion.position).normalized()
	bot = HuntBot.new()
	check(_to_patrol(sim, bot).dot(home) < 0.9, "territories wait to respawn, away from home, so the check tells them apart")
	move = bot.next_intent(sim, []).move
	print("test-swim-bot: roaming hunter with no rammer: %.2f toward home (the patrol zone %.2f)" % [
		move.dot(home), _to_patrol(sim, bot).dot(home)])
	check(move.dot(home) > 0.95, "with no rammer alive it heads home")


## A hidden hunter teleported to `at` (am) and left still for ROAM_SETTLE_TICKS, so the sites round it
## spawn.
func _settled_hunter(at: Vector2) -> Variant:
	var sim: Variant = Gates.make_sim("hunter", SEED)
	sim.debug_set_hidden(true)
	check(Gates.teleport(sim, PackedFloat64Array([at.x, at.y])), "placed at (%.0f, %.0f)" % [at.x, at.y])
	for i in ROAM_SETTLE_TICKS:
		Gates.tick(sim, SimIntent.new())
	return sim


## The way to the hunter's nearest patrol zone, or ZERO with none.
static func _to_patrol(sim: Variant, bot: Variant) -> Vector2:
	var patrol: PackedStringArray = bot.patrol_zone_ids(sim)
	if patrol.is_empty():
		return Vector2.ZERO
	return (sim.region.zone(patrol[0]).center - sim.motion.position).normalized()


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
