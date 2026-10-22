extends TestCase
## Plankton items are a view of zone stock: they never show more food than the zone holds, they
## spawn inside their zone clear of rocks, and they are the same for the same seed.

const DT := 1.0 / 60.0

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
	for i in 3000:
		var roll := rng.randf()
		if roll < 0.05 and not field.items.is_empty():
			_eat(field, region, field.items[rng.randi_range(0, field.items.size() - 1)])
		elif roll < 0.07:
			# Something else grazing the zone (creatures, later) without touching an item.
			region.take(region.zones[rng.randi_range(0, region.zones.size() - 1)].id, rng.randf_range(0.0, 20.0))
		region.tick(DT)
		field.tick(region, arena, i, i * DT)
		for z in region.zones:
			if field.count_in(z.id) > field.max_count(z):
				check(false, "tick %d: %s shows more than its maximum" % [i, z.id])
				return
	for i in 20:
		region.tick(DT)
		field.tick(region, arena, 3000 + i, (3000 + i) * DT)
	check(_counts_match(field, region), "items = min(max, floor(amount / unit)) once settled")


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
