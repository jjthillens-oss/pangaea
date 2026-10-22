extends TestCase
## Plankton items are a view of zone stock: they never show more food than the zone holds, they
## spawn inside their zone clear of rocks, and they are the same for the same seed.

const DT := 1.0 / 60.0
## One zone with a rock inside it and one zone a rock covers completely.
const ROCKY_FIXTURE := "res://tests/fixtures/pool_test_rocks.json"
## One zone: capacity 24, unit 8, growth 0.10, no rocks.
const SMALL_FIXTURE := "res://tests/fixtures/pool_test_small.json"
## Chance per tick of a meal and of a take in the random test (60 ticks a second).
const RANDOM_EAT_SHARE := 0.01
const RANDOM_TAKE_SHARE := 0.01

var layout: PoolLayout
var arena: PoolArena


func before_each() -> void:
	layout = PoolLayout.load_from()
	arena = layout.build_arena()


func _field(region: EcologyRegion) -> PlanktonField:
	var field := PlanktonField.create(layout.plankton)
	field.fill(region, arena, 0, 0.0)
	return field


## Every zone shows min(max, floor(amount / unit)) items.
func _counts_match(field: PlanktonField, region: EcologyRegion) -> bool:
	for z in region.zones:
		if field.count_in(z.id) != field.target_count(z):
			return false
	return true


## Items above stock in each zone: count minus target (negative while a zone is short).
func _excess(field: PlanktonField, region: EcologyRegion) -> Dictionary:
	var counts := {}
	for item in field.items:
		counts[item.zone] = int(counts.get(item.zone, 0)) + 1
	var out := {}
	for z in region.zones:
		out[z.id] = int(counts.get(z.id, 0)) - field.target_count(z)
	return out


## Ids of a zone's items, oldest first.
func _ids_in(field: PlanktonField, zone_id: String) -> Array:
	var ids := []
	for item in field.items:
		if item.zone == zone_id:
			ids.append(item.id)
	return ids


## The small test pool with its one zone's capacity changed (not validated).
func _small_layout(capacity: float) -> PoolLayout:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SMALL_FIXTURE))
	data.zones[0].capacity = capacity
	data.zones[0].id = "z_test"
	return PoolLayout.from_dict(data)


## Types of the zone events a field reported for one zone since the last call; clears them.
func _zone_events(field: PlanktonField, zone_id: String) -> Array:
	var out := []
	for e in field.events:
		if e.zone == zone_id:
			out.append(e.type)
	field.events.clear()
	return out


## Eats the way PoolSim does: stock first, then the item.
func _eat(field: PlanktonField, region: EcologyRegion, item: Dictionary) -> void:
	region.take(item.zone, item.energy)
	field.consume(item.id)


func test_a_new_world_shows_one_item_per_unit_of_stock() -> void:
	var region := layout.build_region(1)
	var field := _field(region)
	check_eq(field.items.size(), 61, "488 capacity at 8 per item")
	check_eq(field.count_in("z_center"), 6, "centre zone")
	check_eq(field.count_in("z_n"), 12, "a big zone shows its maximum")
	check(_counts_match(field, region), "every zone matches its stock")


func test_after_random_meals_takes_and_ticks_the_items_follow_the_stock() -> void:
	var region := layout.build_region(2)
	var field := _field(region)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var over_stock_ticks := 0
	for i in 3000:
		# Rates low enough that the zones stay stocked, so takes keep leaving items above stock.
		var roll := rng.randf()
		if roll < RANDOM_EAT_SHARE and not field.items.is_empty():
			_eat(field, region, field.items[rng.randi_range(0, field.items.size() - 1)])
		elif roll < RANDOM_EAT_SHARE + RANDOM_TAKE_SHARE:
			# Something else grazing the zone (creatures, later) without touching an item.
			region.take(region.zones[rng.randi_range(0, region.zones.size() - 1)].id, rng.randf_range(0.0, 20.0))
		var excess_before := _excess(field, region)
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		var excess := _excess(field, region)
		for z in region.zones:
			if excess[z.id] + field.target_count(z) > field.max_count(z):
				check(false, "tick %d: %s shows more than its maximum" % [i, z.id])
				return
			# A zone above its stock drops one item a tick; regrowth can only close the gap faster.
			if excess_before[z.id] > 0:
				over_stock_ticks += 1
			if excess[z.id] > maxi(0, excess_before[z.id] - 1):
				check(false, "tick %d: %s is %d items above its stock, %d before the tick"
					% [i, z.id, excess[z.id], excess_before[z.id]])
				return
	check(over_stock_ticks >= 10, "takes left zones above their stock (%d zone-ticks)" % over_stock_ticks)
	for i in 20:
		region.tick(DT)
		field.tick(region, arena, 3000 + i, (3000 + i) * DT)
	var stocked := 0
	for z in region.zones:
		stocked += field.target_count(z)
	check(stocked >= 20, "the zones still hold food at the end (%d items' worth)" % stocked)
	check(_counts_match(field, region), "items = min(max, floor(amount / unit)) once settled")


func test_a_zone_grazed_below_its_items_drops_its_newest_item_each_tick() -> void:
	var region := layout.build_region(1)
	var field := _field(region)
	var before := _ids_in(field, "z_center")
	check_eq(before.size(), 6, "a full centre zone shows six items")
	# Something else grazing takes 20 of the 48 energy without touching an item: 28 shows three.
	region.take("z_center", 20.0)
	var z := region.zone("z_center")
	for i in 4:
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		check_eq(field.target_count(z), 3, "tick %d: the stock still shows three items" % i)
		check_eq(field.count_in("z_center"), maxi(3, 5 - i), "tick %d: one item fewer until it matches" % i)
	check_eq(_ids_in(field, "z_center"), before.slice(0, 3), "the three oldest items stay")


func test_eating_never_leaves_more_items_than_stock() -> void:
	var region := layout.build_region(3)
	var field := _field(region)
	var rng := RandomNumberGenerator.new()
	rng.seed = 405
	for i in 2000:
		if rng.randf() < 0.1 and not field.items.is_empty():
			_eat(field, region, field.items[rng.randi_range(0, field.items.size() - 1)])
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		if not _counts_match(field, region):
			check(false, "tick %d: items differ from floor(amount / unit)" % i)
			return
		for z in region.zones:
			if z.amount < 0.0 or z.amount > z.capacity:
				check(false, "tick %d: %s amount %.3f outside 0..capacity" % [i, z.id, z.amount])
				return


func test_items_spawn_inside_their_zone_and_clear_of_rocks() -> void:
	var region := layout.build_region(4)
	var field := _field(region)
	for z in region.zones:
		region.take(z.id, z.capacity)
	for i in 4000:
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		for item in field.items:
			var z := region.zone(item.zone)
			if item.position.distance_to(z.center) > z.radius + 1e-6 or not arena.is_clear(item.position, field.item_radius):
				check(false, "tick %d: %s at %s is outside %s or touching a rock" % [i, item.id, item.position, z.id])
				return
	check(field.items.size() > 30, "zones regrew (%d items)" % field.items.size())


func test_items_never_spawn_on_or_drift_into_a_rock_inside_their_zone() -> void:
	var rocky := PoolLayout.load_from(ROCKY_FIXTURE)
	check(rocky.validate().is_empty(), "the fixture is a valid layout: %s" % [rocky.validate()])
	var rocky_arena := rocky.build_arena()
	var region := rocky.build_region(11)
	var field := PlanktonField.create(rocky.plankton)
	field.fill(region, rocky_arena, 0, 0.0)
	var anchor_clearance := field.item_radius + field.drift_reach()
	for i in 2400:
		# Eating the oldest item three times a second keeps the zone spawning new ones.
		if i % 20 == 0 and not field.items.is_empty():
			_eat(field, region, field.items[0])
		region.tick(DT)
		field.tick(region, rocky_arena, i, i * DT)
		for item in field.items:
			var z := region.zone(item.zone)
			if not rocky_arena.is_clear(item.anchor, anchor_clearance):
				check(false, "tick %d: %s anchored at %s is within its drift of a rock" % [i, item.id, item.anchor])
				return
			if item.position.distance_to(z.center) > z.radius + 1e-6 or not rocky_arena.is_clear(item.position, field.item_radius):
				check(false, "tick %d: %s at %s is outside %s or touching a rock" % [i, item.id, item.position, z.id])
				return
	check(field.next_number - 1 >= 100, "the zone kept spawning around its rock (%d items)" % (field.next_number - 1))
	check_eq(field.count_in("z_covered"), 0, "a zone a rock covers shows no items")


func test_the_same_seed_gives_the_same_positions() -> void:
	var positions := []
	for seed_value in [7, 7, 8]:
		var region := layout.build_region(seed_value)
		var field := _field(region)
		for z in region.zones:
			region.take(z.id, z.capacity * 0.5)
		for i in 900:
			region.tick(DT)
			field.tick(region, arena, i, i * DT)
		var p := []
		for item in field.items:
			p.append([item.id, item.position])
		positions.append(p)
	check_eq(positions[0], positions[1], "same seed, same items and positions")
	check(positions[0] != positions[2], "a different seed gives different positions")


func test_drift_stays_within_its_amplitude() -> void:
	var region := layout.build_region(5)
	var field := _field(region)
	var moved := 0.0
	for i in 1200:
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		for item in field.items:
			var offset: Vector2 = item.position - item.anchor
			moved = maxf(moved, offset.length())
			if absf(offset.x) > field.drift_amplitude + 1e-6 or absf(offset.y) > field.drift_amplitude + 1e-6:
				check(false, "tick %d: %s drifted %s" % [i, item.id, offset])
				return
	check(moved > field.drift_amplitude * 0.5, "items do drift (%.3f m)" % moved)
	check(moved <= field.drift_reach() + 1e-6, "never beyond the drift reach")


func test_an_emptied_zone_reports_empty_once_and_regrown_when_full_again() -> void:
	var region := layout.build_region(6)
	var field := _field(region)
	for item in field.items.duplicate():
		if item.zone == "z_center":
			_eat(field, region, item)
	region.take("z_center", 100.0)
	var empty_at := -1
	var regrown_at := -1
	var empties := 0
	for i in 120 * 60:
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		for e in field.events:
			if e.zone != "z_center":
				continue
			if e.type == "zone_empty":
				empties += 1
				empty_at = i
			elif e.type == "zone_regrown":
				regrown_at = i
		field.events.clear()
		check(field.is_regrowing("z_center") == (empty_at >= 0 and regrown_at < 0), "regrowing flag at tick %d" % i)
		if regrown_at >= 0:
			break
	check_eq(empties, 1, "one zone_empty")
	check_eq(empty_at, 0, "reported on the first tick")
	check(regrown_at > 0, "zone_regrown fires")
	check_eq(field.count_in("z_center"), 6, "all six items back")
	# Plan: first item about 15 s, all six about 56 s after the centre zone is emptied.
	check(regrown_at * DT > 40.0 and regrown_at * DT < 75.0, "regrown after %.1f s" % (regrown_at * DT))
	# Emptied again after it regrew: reported again.
	for item in field.items.duplicate():
		if item.zone == "z_center":
			_eat(field, region, item)
	region.take("z_center", 100.0)
	region.tick(DT)
	field.tick(region, arena, regrown_at + 1, (regrown_at + 1) * DT)
	check_eq(_zone_events(field, "z_center"), ["zone_empty"], "the second emptying is reported at once")
	check(field.is_regrowing("z_center"), "and the zone is regrowing again")


func test_a_zone_with_room_for_one_item_reports_empty_once_each_time_it_is_emptied() -> void:
	var small := _small_layout(12.0)
	check(small.validate().is_empty(), "capacity 12 is a valid zone: %s" % [small.validate()])
	var arena_small := small.build_arena()
	var region := small.build_region(21)
	var field := PlanktonField.create(small.plankton)
	field.fill(region, arena_small, 0, 0.0)
	var reports := []
	var tick := 0
	for emptying in 2:
		check_eq(field.count_in("z_test"), 1, "emptying %d: the zone shows its one item" % emptying)
		for item in field.items.duplicate():
			_eat(field, region, item)
		region.take("z_test", 100.0)
		var counts := {"zone_empty": 0, "zone_regrown": 0}
		# The item comes back after about 35 s at this growth rate.
		for i in 60 * 60:
			region.tick(DT)
			field.tick(region, arena_small, tick, tick * DT)
			tick += 1
			for type in _zone_events(field, "z_test"):
				counts[type] += 1
			if field.count_in("z_test") == 1 and not field.is_regrowing("z_test"):
				break
		reports.append([counts.zone_empty, counts.zone_regrown])
	check_eq(reports, [[1, 1], [1, 1]], "[zone_empty, zone_regrown] reports for each emptying")


func test_a_zone_drained_again_before_half_capacity_reports_empty_only_once() -> void:
	var small := _small_layout(24.0)
	var arena_small := small.build_arena()
	var region := small.build_region(22)
	var field := PlanktonField.create(small.plankton)
	field.fill(region, arena_small, 0, 0.0)
	var z := region.zone("z_test")
	var events := []
	var drains := 0
	for item in field.items.duplicate():
		_eat(field, region, item)
	region.take("z_test", 100.0)
	for i in 90 * 60:
		region.tick(DT)
		field.tick(region, arena_small, i, i * DT)
		events.append_array(_zone_events(field, "z_test"))
		# Eat the first item back (below half capacity), then everything once it is past half.
		var past_half: bool = z.amount >= z.capacity * PlanktonField.REGROWN_LATCH_SHARE
		if field.count_in("z_test") > 0 and (drains == 0 or past_half):
			check_eq(past_half, drains == 1, "drain %d happens %s half capacity" % [drains, "past" if drains == 1 else "below"])
			for item in field.items.duplicate():
				_eat(field, region, item)
			drains += 1
			if drains == 2:
				region.tick(DT)
				field.tick(region, arena_small, i + 1, (i + 1) * DT)
				events.append_array(_zone_events(field, "z_test"))
				break
	check_eq(drains, 2, "both drains happened")
	check_eq(events, ["zone_empty", "zone_empty"], "no second report below half capacity, a new one past it")
	check(field.is_regrowing("z_test"), "regrowing after the second report")


func test_carrion_spawns_never_draw_from_the_region_rng() -> void:
	var region := layout.build_region(9)
	var field := _field(region)
	var carrion := CarrionField.create(layout.carrion, 10)
	carrion.place_initial(arena)
	var before := region.rng.state
	for i in 60 * 60:
		carrion.tick(DT, i * DT, region, arena)
	check_eq(region.rng.state, before, "region RNG untouched")
	var interim := 0
	for e in carrion.events:
		if e.type == "carrion_spawned" and e.source == "interim":
			interim += 1
	check(interim >= 3, "the interim supply did spawn (%d)" % interim)
	check(field.items.size() == 61, "plankton untouched")
