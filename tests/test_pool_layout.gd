extends TestCase
## The real pool layout (game/data/pool_m1.json) passes its runtime checks, each check catches
## the mistake it is for, and the test-only rules hold: rock footprints match their asset records,
## and every open point is reachable and close enough to food for a starving cell.

const ReachGrid := preload("res://tests/reach_grid.gd")
const RECORDS_DIR := "res://assets/records"
const FOOTPRINT_TOLERANCE := 0.15
## A starving cell should reach food using at most this share of the distance it can swim
## before it dies.
const STARVATION_PATH_SHARE := 0.6

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PoolLayout.DEFAULT_PATH))


## Errors from validate() after `change` edits a fresh copy of the real data.
func _errors_after(change: Callable) -> PackedStringArray:
	var data := _data()
	change.call(data)
	return PoolLayout.from_dict(data).validate()


func test_the_real_layout_is_valid() -> void:
	var layout := PoolLayout.load_from()
	var errors := layout.validate()
	check(errors.is_empty(), "no errors: %s" % [errors])
	check_eq(layout.zones.size(), 7, "seven zones")
	check_eq(layout.rocks.size(), 18, "eighteen rocks")
	check_eq(layout.carrion.initial.size(), 3, "three initial carrion")
	check(layout.carrion.interim_supply.interim, "the carrion supply is marked interim")


func test_the_layout_speed_limit_is_the_catalog_speed_cap() -> void:
	check_eq(PoolLayout.MAX_SPEED, float(catalog.caps.speed), "rock thickness is checked against the real top speed")


func test_the_arena_and_region_are_built_from_the_data() -> void:
	var layout := PoolLayout.load_from()
	var arena := layout.build_arena()
	check_eq(arena.rocks.size(), 18, "rocks")
	check_near(arena.rocks[0].radius, 1.0 * 1.2, 1e-9, "rock radius is the footprint times the scale")
	check_eq(arena.soft_start, 36.0, "soft start")
	var region := layout.build_region(5)
	check_eq(region.zones.size(), 7, "zones")
	var total := 0.0
	for z in region.zones:
		total += z.capacity
		check_eq(z.amount, z.capacity, "%s starts full" % z.id)
	check_eq(total, 488.0, "total capacity")


func test_the_spawn_faces_the_centre_zone_with_carrion_close_by() -> void:
	var layout := PoolLayout.load_from()
	var center := layout.zone("z_center")
	var to_center: Vector2 = center.center - layout.spawn
	check_near(to_center.length() - center.radius, 4.0, 0.01, "spawn is 4 m from the centre zone's edge")
	check(absf(angle_difference(layout.spawn_heading, to_center.angle())) < 0.01, "and faces it")
	var nearest := INF
	for p in layout.carrion.initial:
		nearest = minf(nearest, layout.spawn.distance_to(p))
	check_near(nearest, 5.2, 0.05, "a hunter's first carrion is about 5.2 m away")
	for rock in layout.rocks:
		check(layout.spawn.distance_to(rock.center) - rock.radius >= 3.0, "spawn is 3 m clear of %s" % rock.id)


func test_repeated_ids_are_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.rocks[1].id = d.rocks[0].id), "repeated")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.zones[1].id = d.rocks[0].id), "repeated")


func test_a_zone_near_the_soft_wall_is_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.zones[1].center = [0.0, -30.0]), "soft wall")


func test_a_zone_too_small_to_show_one_plankton_item_is_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.zones[0].capacity = 7.9), "one plankton unit")
	check(_errors_after(func(d: Dictionary) -> void: d.zones[0].capacity = 8.0).is_empty(), "room for one item is enough")


func test_a_rock_outside_the_pool_is_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.rocks[6].center = [39.5, 0.0]), "not inside the pool")


func test_a_blocked_spawn_or_carrion_is_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.spawn.position = [12.0, 0.5]), "Spawn")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.spawn.position = [0.0, 35.8]), "Spawn")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.carrion.initial[0] = [-12.0, 0.4]), "Initial carrion")


func test_a_rock_thin_enough_to_tunnel_through_is_refused() -> void:
	# Two ticks at 6 m/s is 0.2 m.
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.rocks[0].scale = 0.19), "two ticks at top speed")
	check(_errors_after(func(d: Dictionary) -> void: d.rocks[0].scale = 0.21).is_empty(), "just thicker is fine")


func test_food_bigger_than_the_sim_reach_search_is_refused() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.carrion.item_radius = 0.5), "MAX_FOOD_RADIUS")


func test_wrong_types_and_missing_files_are_reported_not_crashed_on() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.zones[0].capacity = "lots"), "'capacity' must be a number")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.erase("pool")), "'pool' must be an object")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.spawn.position = [1.0]), "spawn position must be two numbers")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.carrion.interim_supply.enabled = 1),
		"'enabled' must be true or false")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.carrion.interim_supply.placement = "near_player"), "placement")
	check_has_error(PoolLayout.load_from("res://tests/fixtures/no_such_pool.json").validate(), "missing or not readable")
	check_has_error(PoolLayout.from_dict([1, 2]).validate(), "not an object")


## Test-only: rock assets come from assets/records, which are not exported, so the runtime cannot
## check them. Every rock asset the layout names must have a record whose footprint matches the
## layout's collision footprint.
func test_rock_footprints_match_their_asset_records() -> void:
	var layout := PoolLayout.load_from()
	var assets := {}
	for rock in layout.rocks:
		assets[rock.asset] = true
	check_eq(assets.size(), 3, "the layout uses three rock assets")
	for asset in assets:
		var path := "%s/%s.json" % [RECORDS_DIR, asset]
		check(FileAccess.file_exists(path), "%s has an asset record" % asset)
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(data is Dictionary, "%s record is a JSON object" % asset)
		var record: Dictionary = data if data is Dictionary else {}
		check(record.has("footprint_radius_m"), "%s record has footprint_radius_m" % asset)
		var footprint := float(record.get("footprint_radius_m", -1.0))
		check(absf(footprint - layout.rock_footprint_radius_m) <= layout.rock_footprint_radius_m * FOOTPRINT_TOLERANCE,
			"%s footprint %.2f m vs layout %.2f m" % [asset, footprint, layout.rock_footprint_radius_m])


## The starvation reachability rule: from anywhere a cell can be, food is close enough to reach
## at starving speed before health runs out, with a margin. If this fails, move or resize zones;
## never weaken the test.
func test_every_open_point_is_reachable_and_close_enough_to_a_zone_to_survive_starving() -> void:
	var layout := PoolLayout.load_from()
	var budget := INF
	for body in catalog.starting_bodies:
		var r := Lineage.found(1, "test+dev", catalog, body)
		var p := Phenotype.derive(r.save.genome, catalog)
		var starving_s := p.max_health / ActorState.STARVATION_DAMAGE
		budget = minf(budget, p.speed * ActorState.STARVING_SPEED * starving_s * STARVATION_PATH_SHARE)
	check(budget > 15.0 and budget < 17.0, "the budget is about 16.3 m today (%.2f)" % budget)
	var grid := ReachGrid.new(layout, PoolLayout.CELL_RADIUS)
	var from_spawn := grid.distances_from(PackedInt32Array([grid.index_near(layout.spawn)]))
	var to_food := grid.distances_from(grid.zone_points())
	var unreached := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for i in grid.open.size():
		if grid.open[i] == 0:
			continue
		if not is_finite(from_spawn[i]):
			unreached += 1
		if to_food[i] > worst:
			worst = to_food[i]
			worst_at = grid.point(i)
	check(grid.open_count() > 10000, "the grid covers the pool (%d open points)" % grid.open_count())
	check_eq(unreached, 0, "open points the spawn cannot reach")
	check(worst <= budget, "worst path to a zone %.1f m at %s, budget %.1f m" % [worst, worst_at, budget])
