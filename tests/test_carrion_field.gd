extends TestCase
## Carrion enters only through spawn(): the interim supply is seeded and capped, items rot at
## their lifetime, and step 3 kills can already drop carrion through the same call. The real data
## turns the supply off since step 3 (carrion comes from kills); the block stays so turning it back
## on is a data change, and the supply tests switch it on (_supply_on()).

const DT := 1.0 / 60.0
## One zone with a rock inside it and one zone a rock covers completely; the supply runs every second.
const ROCKY_FIXTURE := "res://tests/fixtures/pool_test_rocks.json"

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
	var field := CarrionField.create(_supply_on(), seed_value)
	var out := []
	var collect := func(i: int) -> void:
		for e in field.events:
			if e.type == "carrion_spawned" and e.source == "interim":
				out.append([i, e.position])
		field.events.clear()
	_run(field, seconds, collect)
	return out


func test_the_interim_supply_is_deterministic_per_seed() -> void:
	var a := _interim_spawns(31, 300.0)
	var b := _interim_spawns(31, 300.0)
	var c := _interim_spawns(32, 300.0)
	check(a.size() >= 10, "spawns over five minutes (%d)" % a.size())
	check_eq(a, b, "same seed, same times and places")
	check(a != c, "another seed differs")


func test_interim_carrion_lands_clear_inside_a_zone() -> void:
	var spawns := _interim_spawns(33, 600.0)
	check(spawns.size() >= 10, "the supply ran (%d spawns)" % spawns.size())
	for spawn in spawns:
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
	var field := CarrionField.create(_supply_on(), 34)
	field.place_initial(arena)
	var max_live: int = layout.carrion.interim_supply.max_live
	var most := [0]
	_run(field, 1200.0, func(_i: int) -> void: most[0] = maxi(most[0], field.items.size()))
	check(most[0] <= max_live, "at most %d live, saw %d" % [max_live, most[0]])
	check_eq(most[0], max_live, "and it does fill up to the cap")


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


## The real carrion data with the interim supply switched back on.
func _supply_on() -> Dictionary:
	return _data_with_supply(true)


# --- the endless world's carrion ring (S1 T2.3) ---

func test_drop_beyond_removes_only_far_items_without_events() -> void:
	var field := CarrionField.create(_data_with_supply(false), 38)
	var near := field.spawn(Vector2(3.0, 4.0), "test")        # 5 m
	var edge := field.spawn(Vector2(0.0, -52.0), "test")      # exactly at the ring
	var far := field.spawn(Vector2(52.01, 0.0), "test")
	var farther := field.spawn(Vector2(-80.0, 30.0), "test")
	field.events.clear()
	check_eq(field.drop_beyond(Vector2.ZERO, 52.0), 2, "two dropped")
	var ids := []
	for item in field.items:
		ids.append(item.id)
	check_eq(ids, [near.id, edge.id], "the near ones stay, in order")
	check(field.events.is_empty(), "no events")
	check(not ids.has(far.id) and not ids.has(farther.id), "the far ones are gone")
	check_eq(field.drop_beyond(Vector2.ZERO, 52.0), 0, "nothing more to drop")


func test_drop_all_empties_the_field_without_events() -> void:
	var field := CarrionField.create(_data_with_supply(false), 39)
	for i in 4:
		field.spawn(Vector2(i, 0.0), "test")
	field.events.clear()
	var next := field.next_number
	check_eq(field.drop_all(), 4, "four dropped")
	check(field.items.is_empty(), "empty")
	check(field.events.is_empty(), "no events")
	check_eq(field.next_number, next, "ids keep counting (never reused)")


# --- S2 (T2.2): per-item radius and lifetime, find ---

func test_an_item_may_have_its_own_radius_and_lifetime() -> void:
	var field := CarrionField.create(layout.carrion, 1)
	var plain := field.spawn(Vector2(1.0, 2.0), "kill")
	check_eq(plain.radius, field.item_radius, "the field's radius by default")
	check_eq(plain.lifetime, field.lifetime, "the field's lifetime by default")
	var morsel := field.spawn(Vector2(3.0, 2.0), "morsel", 18.75, -1, 0.1875, 45.0)
	check_eq(morsel.radius, 0.1875, "its own radius")
	check_eq(morsel.lifetime, 45.0, "its own lifetime")
	check_eq(morsel.points, floori(18.75 / field.energy * field.points + 1e-6), "points by the spawn rule")
	_run(field, 45.0 - DT)
	check(not field.find(morsel.id).is_empty(), "alive just before its own lifetime")
	_run(field, 2.0 * DT)
	check(field.find(morsel.id).is_empty(), "gone at its own lifetime")
	check(not field.find(plain.id).is_empty(), "the plain item keeps the field's")


func test_find_gives_the_item_or_nothing() -> void:
	var field := CarrionField.create(layout.carrion, 1)
	var a := field.spawn(Vector2(1.0, 2.0), "kill")
	var b := field.spawn(Vector2(4.0, 2.0), "kill", 12.0)
	check(is_same(field.find(b.id), b), "the item itself")
	check(is_same(field.find(a.id), a), "the first too")
	check_eq(field.find("cr_999"), {}, "{} for an unknown id")
	field.consume(a.id)
	check_eq(field.find(a.id), {}, "{} once eaten")


# --- S3: morsel sites' items (S3G17's carrion part) ---

func test_a_morsel_sites_item_carries_its_species_and_site_and_can_be_expired() -> void:
	var field := CarrionField.create(layout.carrion, 1)
	var plain := field.spawn(Vector2(1.0, 2.0), "kill")
	check(not plain.has("species") and not plain.has("site"), "a kill's item has neither")
	check(not field.events[0].has("species"), "nor does its event")
	var m := field.spawn(Vector2(3.0, 2.0), "morsel_site", 18.75, -1, 0.1875, 45.0, {"species": "warden", "site": "m_7"})
	check_eq([m.species, m.site], ["warden", "m_7"], "the item carries both")
	check_eq([field.events[1].species, field.events[1].site], ["warden", "m_7"], "and so does carrion_spawned")
	field.events.clear()
	var gone := field.expire(m.id, "unloaded")
	check(is_same(gone, m), "expire returns the item")
	check(field.find(m.id).is_empty(), "and takes it out")
	check_eq(field.events, [{"type": "carrion_expired", "food_id": m.id, "position": Vector2(3.0, 2.0), "reason": "unloaded"}],
		"with its reason")
	field.events.clear()
	check_eq(field.expire(m.id, "unloaded"), {}, "an absent item gives {}")
	check(field.events.is_empty(), "and no event")
	check_eq(field.items.size(), 1, "the kill's item stays")
