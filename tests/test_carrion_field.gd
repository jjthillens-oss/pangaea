extends TestCase
## Carrion enters only through spawn(): the interim supply is seeded and capped, items rot at
## their lifetime, and step 3 kills can already drop carrion through the same call.

const DT := 1.0 / 60.0
## One zone with a rock inside it and one zone a rock covers completely; the supply runs every second.
const ROCKY_FIXTURE := "res://tests/fixtures/pool_test_rocks.json"
## Well below the 13 to 15 items the pool data's supply reaches on its own, so this cap has
## arrivals to hold back.
const HELD_BACK_MAX_LIVE := 8
const UNCAPPED_MAX_LIVE := 1 << 20

var layout: PoolLayout
var arena: PoolArena
var region: EcologyRegion


func before_each() -> void:
	layout = PoolLayout.load_from()
	arena = layout.build_arena()
	region = layout.build_region(1)


func _run(field: CarrionField, seconds: float, on_tick: Callable = Callable()) -> void:
	for i in roundi(seconds / DT):
		field.tick(DT, i * DT, region, arena)
		if on_tick.is_valid():
			on_tick.call(i)


## [time, position] of each interim spawn over `seconds`.
func _interim_spawns(seed_value: int, seconds: float) -> Array:
	var field := CarrionField.create(layout.carrion, seed_value)
	var out := []
	var collect := func(i: int) -> void:
		for e in field.events:
			if e.type == "carrion_spawned" and e.source == "interim":
				out.append([i, e.position])
		field.events.clear()
	_run(field, seconds, collect)
	return out


## The most carrion live at once over `seconds`, initial items included.
func _peak_live(data: Dictionary, seed_value: int, seconds: float) -> int:
	var field := CarrionField.create(data, seed_value)
	field.place_initial(arena)
	var most := [0]
	_run(field, seconds, func(_i: int) -> void: most[0] = maxi(most[0], field.items.size()))
	return most[0]


func test_the_interim_supply_is_deterministic_per_seed() -> void:
	var a := _interim_spawns(31, 300.0)
	var b := _interim_spawns(31, 300.0)
	var c := _interim_spawns(32, 300.0)
	check(a.size() >= 10, "spawns over five minutes (%d)" % a.size())
	check_eq(a, b, "same seed, same times and places")
	check(a != c, "another seed differs")


func test_interim_carrion_lands_clear_inside_a_zone() -> void:
	for spawn in _interim_spawns(33, 600.0):
		var p: Vector2 = spawn[1]
		var inside := false
		for z in layout.zones:
			inside = inside or p.distance_to(z.center) <= z.radius + 1e-6
		check(inside and arena.is_clear(p, layout.carrion.item_radius), "%s is clear and inside a zone" % p)


func test_interim_carrion_never_lands_on_a_rock_inside_a_zone() -> void:
	var rocky := PoolLayout.load_from(ROCKY_FIXTURE)
	var rocky_arena := rocky.build_arena()
	var rocky_region := rocky.build_region(1)
	var open_zone := rocky.zone("z_rock")
	var field := CarrionField.create(rocky.carrion, 38)
	var spawned := 0
	for i in roundi(120.0 / DT):
		field.tick(DT, i * DT, rocky_region, rocky_arena)
		for e in field.events:
			if e.type != "carrion_spawned":
				continue
			spawned += 1
			var p: Vector2 = e.position
			# The other zone is all rock, so every spawn must land in the open part of z_rock.
			if p.distance_to(open_zone.center) > open_zone.radius + 1e-6 or not rocky_arena.is_clear(p, field.item_radius):
				check(false, "spawn %d at %s is on a rock or outside the open zone" % [spawned, p])
				return
		field.events.clear()
		# Eaten at once, so max_live never holds the supply back.
		for item in field.items.duplicate():
			field.consume(item.id)
	check(spawned >= 60, "the supply kept spawning around the rocks (%d)" % spawned)


func test_the_supply_never_exceeds_max_live() -> void:
	var max_live: int = layout.carrion.interim_supply.max_live
	var most := _peak_live(layout.carrion, 34, 1200.0)
	check(most <= max_live, "at most %d live, saw %d" % [max_live, most])
	check_eq(most, max_live, "and it does fill up to the cap")
	# The data's cap is about as many as the supply reaches anyway, so it holds back little or
	# nothing. A lower cap must hold back arrivals that the same supply makes without one.
	var uncapped: Dictionary = layout.carrion.duplicate(true)
	uncapped.interim_supply.max_live = UNCAPPED_MAX_LIVE
	var uncapped_most := _peak_live(uncapped, 34, 300.0)
	check(uncapped_most > HELD_BACK_MAX_LIVE, "without a cap the same supply reaches %d live" % uncapped_most)
	var held: Dictionary = layout.carrion.duplicate(true)
	held.interim_supply.max_live = HELD_BACK_MAX_LIVE
	var held_most := _peak_live(held, 34, 300.0)
	check(held_most <= HELD_BACK_MAX_LIVE, "at most %d live under the lower cap, saw %d" % [HELD_BACK_MAX_LIVE, held_most])
	check_eq(held_most, HELD_BACK_MAX_LIVE, "and it fills up to the lower cap")


func test_carrion_rots_at_its_lifetime() -> void:
	var data := _data_with_supply(false)
	var field := CarrionField.create(data, 35)
	var item := field.spawn(Vector2(1.0, 1.0), "test")
	field.events.clear()
	var lifetime_ticks := roundi(float(data.lifetime_s) / DT)
	for i in lifetime_ticks - 1:
		field.tick(DT, i * DT, region, arena)
	check_eq(field.items.size(), 1, "still there one tick before its lifetime")
	check_near(field.items[0].age, data.lifetime_s - DT, 1e-6, "age counts sim time")
	field.tick(DT, lifetime_ticks * DT, region, arena)
	check(field.items.is_empty(), "gone at its lifetime")
	check_eq(field.events.size(), 1, "one event")
	if field.events.size() == 1:
		check_eq(field.events[0].type, "carrion_expired", "expired")
		check_eq(field.events[0].food_id, item.id, "for that item")


func test_a_disabled_supply_spawns_nothing() -> void:
	var field := CarrionField.create(_data_with_supply(false), 36)
	_run(field, 600.0)
	check(field.items.is_empty(), "no carrion")
	check(field.events.is_empty(), "no events")
	check(not is_finite(field.next_supply_at), "no arrival scheduled")


func test_a_kill_drops_carrion_a_hunter_can_eat() -> void:
	var field := CarrionField.create(_data_with_supply(false), 37)
	var item := field.spawn(Vector2(2.0, 0.0), "kill", 16.0)
	check_eq(item.source, "kill", "source")
	check_eq(item.kind, "meat", "meat")
	check_near(item.energy, 16.0, 1e-9, "the victim's energy")
	check_eq(item.points, 2, "points at the carrion rate (3 per 24 energy)")
	check_eq(field.events[0].type, "carrion_spawned", "reported")
	var catalog := PartCatalog.load_from()
	var hunter := Lineage.found(1, "test+dev", catalog, "hunter")
	var actor := InteractionResolver.Actor.new("h", Vector2(1.3, 0.0), 0.0, Phenotype.derive(hunter.save.genome, catalog))
	var r := InteractionResolver.feed(actor, field.items_near(actor.position, 1.5)[0], 0.0)
	check(r.allowed, "a hunter eats it: %s" % r.reason)
	check(field.consume(item.id), "consumed")
	check(not field.consume(item.id), "only once")
	check(field.spawn(Vector2.INF, "kill").is_empty(), "no carrion at an invalid place")
	check(field.spawn(Vector2.ZERO, "kill", 0.0).is_empty(), "no empty carrion")
	check_eq(field.spawn(Vector2.ZERO, "kill", 30.0, 5).points, 5, "explicit points are kept")


func _data_with_supply(enabled: bool) -> Dictionary:
	var data := layout.carrion.duplicate(true)
	data.interim_supply.enabled = enabled
	return data
