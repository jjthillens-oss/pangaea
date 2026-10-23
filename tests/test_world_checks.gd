extends TestCase
## The endless world's heavy checks (tests/world_checks.gd; docs/s1/s1-interfaces.md 4.2,
## docs/s1/s1-core.md 6.7, docs/s1/s1-build-plan.md B-13 and B-29): each refuses the case it is for
## and passes its control.

const WorldChecks := preload("res://tests/world_checks.gd")
const ReachGrid := preload("res://tests/reach_grid.gd")
const BOUNDS := Rect2(-16.0, -16.0, 32.0, 32.0)
## A ring of 8 pillars r 0.9 on a 3.4 bu circle, as the shell cathedral's: the gaps between them
## (0.80 bu) are narrower than a cell, so the nave inside (r <= 2.5) is a sealed pocket.
const POCKET := Vector2(6.0, -5.0)


## The pillars round POCKET, as ChunkArena circles.
static func _pillars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in 8:
		out.append({"id": "p%d" % k, "center": POCKET + Vector2.from_angle(k * TAU / 8.0) * 3.4, "radius": 0.9})
	return out


## Zones that leave no open point of BOUNDS outside the pocket more than a few tm from food.
static func _zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in [Vector2(-8.0, -8.0), Vector2(-8.0, 8.0), Vector2(8.0, 8.0), Vector2(-1.0, 0.0), Vector2(12.0, -12.0)]:
		out.append({"id": "z%d" % out.size(), "center": c, "radius": 4.0})
	return out


## B-29: the reach rule measures the sea the border reaches; an empty sealed pocket is legal.
func test_an_empty_sealed_pocket_passes_the_reach_rule() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var grid = ReachGrid.over(arena, _zones(), BOUNDS, PoolLayout.CELL_RADIUS)
	var inside: int = grid.index_near(POCKET)
	var from_border: PackedFloat32Array = grid.distances_from(grid.border_points())
	check(grid.open[inside] == 1 and not is_finite(from_border[inside]), "the nave is open water the border cannot reach")
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3), PackedStringArray(), "the pocket is empty, so the sea passes")


## A pocket holding food is a problem: a cell outside can never reach it.
func test_a_sealed_pocket_holding_a_zone_fails() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var zones := _zones()
	zones.append({"id": "nave", "center": POCKET, "radius": 1.0})
	var problems := WorldChecks.reach_problems(arena, zones, BOUNDS, 16.3)
	check_eq(problems.size(), 1, "one problem: %s" % [problems])
	check(problems.size() == 1 and problems[0].begins_with("reach: ") and problems[0].ends_with("zone points around (6.0, -5.0) lie in a sealed pocket"),
		"the food in the pocket, named by its centre: %s" % [problems])


## must_reach (site homes, the spawn): a point in the pocket or under a collider fails; one in the
## open sea passes.
func test_a_must_reach_point_in_a_sealed_pocket_fails() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var outside: Array[Vector2] = [Vector2(-10.0, 10.0), Vector2(0.0, 0.0)]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, outside), PackedStringArray(), "homes in the sea pass")
	var inside: Array[Vector2] = [Vector2(-10.0, 10.0), POCKET]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, inside),
		PackedStringArray(["reach: (6.0, -5.0) must be reached but lies in a sealed pocket or under a collider"]), "a home in the nave")
	var under: Array[Vector2] = [POCKET + Vector2(3.4, 0.0)]
	check_eq(WorldChecks.reach_problems(arena, _zones(), BOUNDS, 16.3, under),
		PackedStringArray(["reach: (9.4, -5.0) must be reached but lies in a sealed pocket or under a collider"]), "a home under a pillar")


## The border-connected sea still has to reach food within the budget and stay one sea.
func test_the_sea_outside_still_meets_the_budget_and_stays_connected() -> void:
	var arena := ChunkArena.from_shells(_pillars())
	var far: Array[Dictionary] = [{"id": "z", "center": Vector2(-12.0, -12.0), "radius": 3.0}]
	var problems := WorldChecks.reach_problems(arena, far, BOUNDS, 16.3)
	check(problems.size() == 1 and problems[0].contains("tm from food; the budget is 16.3 tm"), "one zone in a corner is too far: %s" % [problems])
	# A wall of touching shells across the bounds cuts the sea in two; each half has food.
	var wall: Array[Dictionary] = []
	for k in 17:
		wall.append({"id": "w%d" % k, "center": Vector2(-16.0 + 2.0 * k, 3.0), "radius": 1.0})
	var split := WorldChecks.reach_problems(ChunkArena.from_shells(wall), _zones(), BOUNDS, 16.3)
	check(split.size() == 1 and split[0].contains("are cut off from"), "the far half is cut off: %s" % [split])


## B-13: zone_points() buckets zones on an 8 bu grid and finds exactly the points the plain loop over
## every zone finds, in the same order, for zones that straddle buckets on both sides of 0.
func test_bucketed_zone_points_equal_the_plain_loop() -> void:
	var zones: Array[Dictionary] = []
	for k in 40:
		var c := Vector2(-31.0 + fposmod(k * 7.3, 62.0), -31.0 + fposmod(k * 11.9, 62.0))
		zones.append({"id": "z%d" % k, "center": c, "radius": 2.0 + fposmod(k * 1.7, 6.0)})
	var arena := ChunkArena.from_shells(_pillars())
	var grid = ReachGrid.over(arena, zones, Rect2(-32.0, -32.0, 64.0, 64.0), PoolLayout.CELL_RADIUS)
	var plain := PackedInt32Array()
	for i in grid.open.size():
		if grid.open[i] == 0:
			continue
		for z in zones:
			if grid.point(i).distance_to(z.center) <= z.radius:
				plain.append(i)
				break
	check(plain.size() > 1000, "the zones cover %d points" % plain.size())
	check_eq(grid.zone_points(), plain, "the same points in the same order")
