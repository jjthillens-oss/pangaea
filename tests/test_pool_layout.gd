extends TestCase
## The real pool layout (game/data/pool_m1.json) passes its runtime checks, each check catches
## the mistake it is for, and the test-only rules hold: rock footprints match their asset records,
## and every open point is reachable and close enough to food for a starving cell.

const ReachGrid := preload("res://tests/reach_grid.gd")
const RECORDS_DIR := "res://assets/records"
## The threat tests' open pool: one zone and a wall of five overlapping rocks (M1 step 3).
const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
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


## M1 step 3: carrion comes from kills and the three world-start carcasses, so the interim supply
## is off, and those carcasses lie outside every rammer territory (zone radius plus the rammer's
## territory margin), where a player going for them would be charged. If the owner brings the
## trickle back (OD2), the first guard changes with it.
func test_the_interim_supply_is_off_and_no_world_start_carrion_lies_in_a_rammer_territory() -> void:
	var layout := PoolLayout.load_from()
	check(not layout.carrion.interim_supply.enabled, "the interim carrion supply is off")
	var species := SpeciesCatalog.load_from()
	var guarded := {}
	for s in species.sites:
		var territory := species.territory_of(s, layout)
		if territory.is_empty():
			continue
		var r: float = territory.radius + float(species.species[s.species].territory_margin_m)
		guarded[s.territory_zone] = r
		for p in layout.carrion.initial:
			check(p.distance_to(territory.center) > r, "carrion at %s is outside the %.0f m territory of %s (%.2f m)"
				% [p, r, s.territory_zone, p.distance_to(territory.center)])
	check_eq(guarded, {"z_n": 8.0, "z_nw": 8.0, "z_ne": 8.0}, "the rammers guard the three rich north zones, 8 m each")


func test_the_threat_fixture_wall_stops_every_body_and_every_line_of_sight() -> void:
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var errors := fixture.validate()
	check(errors.is_empty(), "the fixture is a valid layout: %s" % [errors])
	check_eq(fixture.zone("z_a").center, Vector2.ZERO, "zone z_a at the center")
	check_eq(fixture.spawn, Vector2(0.0, 25.0), "the spawn 25 m south of it")
	var arena := fixture.build_arena()
	for i in arena.rocks.size() - 1:
		var a: Dictionary = arena.rocks[i]
		var b: Dictionary = arena.rocks[i + 1]
		check(a.center.distance_to(b.center) < (a.radius + b.radius) * PoolArena.SIGHT_SHRINK,
			"%s and %s overlap even at the sight shrink" % [a.id, b.id])
	for i in 81:
		var x := -4.0 + i * 0.1
		check(not arena.segment_clear(Vector2(x, 0.0), Vector2(x, 16.0)), "no sight straight across at x %.1f" % x)
		check(not arena.segment_clear(Vector2(x - 2.0, 0.0), Vector2(x + 2.0, 16.0)), "nor slanting across at x %.1f" % x)
		check(not arena.is_clear(Vector2(x, 8.0), PoolLayout.CELL_RADIUS), "no room for a body in the wall at x %.1f" % x)
	check(arena.segment_clear(Vector2(-8.0, 0.0), Vector2(-8.0, 16.0)), "beside the wall the view is open")


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


# --- the S1 extractions (docs/s1/s1-interfaces.md 3.8): the endless world checks its tiles with them ---

## A zone among shells (C-12): ZONE_CLEAR_SHARE of its points keep ZONE_CLEAR_MARGIN of open water.
## A shell slid in from the east covers more of the zone the further in it comes; 76% clear passes
## and 74% clear is refused.
func test_zone_problems_refuses_a_zone_mostly_under_shells() -> void:
	var zone := {"id": "z", "center": Vector2(3.0, -2.0), "radius": 6.0, "capacity": 40.0, "growth_rate": 0.1}
	var zones: Array[Dictionary] = [zone]
	var at_76 := _shell_at_share(zone, 0.76)
	var at_74 := _shell_at_share(zone, 0.74)
	check(not at_76.is_empty() and not at_74.is_empty(), "a shell position gives each share")
	if at_76.is_empty() or at_74.is_empty():
		return
	check_eq(PoolLayout.zone_problems(zones, at_76, INF), PackedStringArray(), "76% clear passes")
	var refused := PoolLayout.zone_problems(zones, at_74, INF)
	check(refused.size() == 1 and refused[0].begins_with("Zone 'z' has 74.") and refused[0].ends_with("of its points 0.7 m clear of shells; it needs 75%."),
		"74%% clear is refused: %s" % [refused])
	var none: Array[Dictionary] = []
	check_eq(PoolLayout.zone_problems(zones, none, INF), PackedStringArray(), "no shells, no clearance check")
	# The share is counted from the zone's centre, so it is the same wherever the tile is placed.
	var far := zone.duplicate()
	far.center = Vector2(zone.center) + Vector2(64.0, -128.0)
	var far_shell: Array[Dictionary] = [{"center": Vector2(at_74[0].center) + Vector2(64.0, -128.0), "radius": at_74[0].radius}]
	check_eq(PoolLayout.zone_clear_share(far, far_shell), PoolLayout.zone_clear_share(zone, at_74), "the same share one tile over")


## One shell east of the zone whose clear share lies within 0.005 of `share`; [] when none is found.
static func _shell_at_share(zone: Dictionary, share: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 400:
		var shell := {"center": Vector2(zone.center) + Vector2(12.0 - i * 0.02, 0.0), "radius": 3.0}
		var one: Array[Dictionary] = [shell]
		if absf(PoolLayout.zone_clear_share(zone, one) - share) < 0.005:
			out.append(shell)
			return out
	return out


func test_zone_problems_without_circles_gives_the_m1_messages() -> void:
	var none: Array[Dictionary] = []
	var cases := [
		func(d: Dictionary) -> void: d.zones[0].radius = 0.0,
		func(d: Dictionary) -> void: d.zones[1].growth_rate = -1.0,
		func(d: Dictionary) -> void: d.zones[2].center = [0.0, 30.0],
	]
	for change in cases:
		var data := _data()
		change.call(data)
		var layout := PoolLayout.from_dict(data)
		var mine := PoolLayout.zone_problems(layout.zones, none, layout.soft_start)
		check_eq(mine.size(), 1, "one zone problem: %s" % [mine])
		var zone_errors := PackedStringArray()
		for e in layout.validate():
			if e.begins_with("Zone '") and not e.contains("plankton unit"):
				zone_errors.append(e)
		check_eq(mine, zone_errors, "the same text validate() gives")
	var near_wall := _data()
	near_wall.zones[2].center = [0.0, 30.0]
	var layout := PoolLayout.from_dict(near_wall)
	check_eq(PoolLayout.zone_problems(layout.zones, none, INF), PackedStringArray(), "no wall, no wall margin")


func test_tunnel_problems_gives_the_rock_loops_message() -> void:
	var data := _data()
	data.rock_footprint_radius_m = 0.15
	var layout := PoolLayout.from_dict(data)
	var mine := PoolLayout.tunnel_problems(layout.rocks, PoolLayout.MAX_SPEED, 1.0)
	var theirs := PackedStringArray()
	for e in layout.validate():
		if e.contains("two ticks at top speed"):
			theirs.append(e)
	check(not mine.is_empty(), "thin rocks are refused")
	check_eq(mine, theirs, "the same text, in the same order, as the rock loop")
	var real := PoolLayout.load_from()
	check_eq(PoolLayout.tunnel_problems(real.rocks), PackedStringArray(), "the M1 rocks are thick enough")
	var one: Array[Dictionary] = [{"id": "s", "center": Vector2.ZERO, "radius": 0.6}]
	check_eq(PoolLayout.tunnel_problems(one, PoolLayout.MAX_SPEED, 0.625), PackedStringArray(), "0.375 m clears 0.20 m")
	check_eq(PoolLayout.tunnel_problems(one, PoolLayout.MAX_SPEED, 0.3),
		PackedStringArray(["Rock 's' radius 0.18 m is not above 0.20 m (two ticks at top speed)."]), "a scaled radius is the one checked")


func test_reach_grid_over_equals_the_layout_constructor() -> void:
	var layout := PoolLayout.load_from()
	var grid = ReachGrid.new(layout, PoolLayout.CELL_RADIUS)
	var half := ceili(layout.soft_start / ReachGrid.STEP)
	var bounds := Rect2(-half * ReachGrid.STEP, -half * ReachGrid.STEP, 2 * half * ReachGrid.STEP, 2 * half * ReachGrid.STEP)
	var over = ReachGrid.over(layout.build_arena(), layout.zones, bounds, PoolLayout.CELL_RADIUS)
	check_eq(over.size, grid.size, "points per row")
	check_eq(over.rows, grid.rows, "rows")
	check_eq(grid.rows, grid.size, "the pool's grid is square")
	check_eq(over.origin, grid.origin, "origin")
	check(over.open == grid.open, "every cell is equal (%d open)" % grid.open_count())
	check(over.zone_points() == grid.zone_points(), "the same zone points")
	# A grid over a non-square rectangle indexes rows by its own width.
	var strip = ReachGrid.over(layout.build_arena(), layout.zones, Rect2(-10.0, 2.0, 20.0, 5.0), PoolLayout.CELL_RADIUS)
	check_eq([strip.size, strip.rows], [41, 11], "41 x 11 points")
	check_eq(strip.point(strip.index_near(Vector2(9.9, 6.9))), Vector2(10.0, 7.0), "the far corner")
	var d: PackedFloat32Array = strip.distances_from(PackedInt32Array([strip.index_near(Vector2(-10.0, 2.0))]))
	check(is_finite(d[strip.index_near(Vector2(10.0, 7.0))]) == (strip.open[strip.index_near(Vector2(10.0, 7.0))] == 1), "walks the whole strip")
