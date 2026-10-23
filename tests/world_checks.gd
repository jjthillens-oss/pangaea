extends RefCounted
## Test helper (not a test file): the endless world's heavy checks (docs/s1/s1-interfaces.md 4.2,
## docs/s1/s1-core.md 6.7). The validators keep to cheap per-file rules; these walk grids, every
## orientation and every seam, and T4 runs them on the real content.
##
##     const WorldChecks := preload("res://tests/world_checks.gd")
##     WorldChecks.reach_problems(arena, zones, bounds, WorldChecks.starving_budget(catalog))

const ReachGrid := preload("res://tests/reach_grid.gd")
## A starving cell should reach food using at most this share of the distance it can swim before it
## dies (tests/test_pool_layout.gd, the pool's own starvation rule).
const STARVATION_PATH_SHARE := 0.6


## The starving budget in tm: the shortest distance any starting body swims at starving speed before
## starvation kills it, times STARVATION_PATH_SHARE (16.3 today), computed as the pool's test does.
static func starving_budget(catalog: PartCatalog) -> float:
	var budget := INF
	for body in catalog.starting_bodies:
		var r := Lineage.found(1, "test+dev", catalog, body)
		var p := Phenotype.derive(r.save.genome, catalog)
		var starving_s := p.max_health / ActorState.STARVATION_DAMAGE
		budget = minf(budget, p.speed * ActorState.STARVING_SPEED * starving_s * STARVATION_PATH_SHARE)
	return budget


## Every open point of `bounds` (a cell fits there, on a 0.5 tm grid over `arena`) walks to the edge
## of one of `zones` within budget_tm, and the open points that reach food form one connected sea.
## One problem per failure, each naming where: points walled off from food (their centre), the
## worst point over the budget, points cut off from the rest.
static func reach_problems(arena: PoolArena, zones: Array[Dictionary], bounds: Rect2, budget_tm: float) -> PackedStringArray:
	var grid = ReachGrid.over(arena, zones, bounds, PoolLayout.CELL_RADIUS)
	var to_food: PackedFloat32Array = grid.distances_from(grid.zone_points())
	var problems := PackedStringArray()
	var walled := 0
	var walled_sum := Vector2.ZERO
	var worst := -1.0
	var worst_at := Vector2.ZERO
	var start := -1
	for i in grid.open.size():
		if grid.open[i] == 0:
			continue
		if not is_finite(to_food[i]):
			walled += 1
			walled_sum += grid.point(i)
			continue
		if start < 0:
			start = i
		if to_food[i] > worst:
			worst = to_food[i]
			worst_at = grid.point(i)
	if walled > 0:
		problems.append("reach: %d open points around %s cannot reach food" % [walled, walled_sum / walled])
	if worst > budget_tm:
		problems.append("reach: %s is %.1f tm from food; the budget is %.1f tm" % [worst_at, worst, budget_tm])
	if start >= 0:
		var from_start: PackedFloat32Array = grid.distances_from(PackedInt32Array([start]))
		var cut := 0
		var cut_at := Vector2.ZERO
		for i in grid.open.size():
			if grid.open[i] == 1 and is_finite(to_food[i]) and not is_finite(from_start[i]):
				if cut == 0:
					cut_at = grid.point(i)
				cut += 1
		if cut > 0:
			problems.append("reach: %d open points from %s are cut off from %s" % [cut, cut_at, grid.point(start)])
	return problems


## The worst walking distance to food over `bounds` (for printing measured margins), and where.
static func worst_reach(arena: PoolArena, zones: Array[Dictionary], bounds: Rect2) -> Dictionary:
	var grid = ReachGrid.over(arena, zones, bounds, PoolLayout.CELL_RADIUS)
	var to_food: PackedFloat32Array = grid.distances_from(grid.zone_points())
	var worst := -1.0
	var at := Vector2.ZERO
	for i in grid.open.size():
		if grid.open[i] == 1 and to_food[i] > worst:
			worst = to_food[i]
			at = grid.point(i)
	return {"worst": worst, "at": at}
