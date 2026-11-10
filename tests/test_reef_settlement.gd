extends TestCase
## The reef spike's settlement rules (game/domain/reef/reef_settlement.gd; backlog U-03, PROPOSED): the layout in
## game/data/reef/reef_spike.json is buildable (three modules and a ledge inside one bubble, doors free); paths are
## three-dimensional, stay in free cells and move one cell at a time; the food shortage the settlement starts with
## is resolved by the workers; ten minutes of play leave no worker stuck and every worker busy; two runs are
## identical; and a walled-in door is reported as stuck instead of being walked through.

const RULES_PATH := "res://game/data/reef/reef_spike.json"
const TEN_MINUTES := 10 * 60 * ReefSettlement.TICKS_PER_SECOND

var rules: Dictionary


func before_each() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))


func _run(sim: ReefSettlement, ticks: int) -> Array:
	var events: Array = []
	for i in ticks:
		sim.step()
		events.append_array(sim.take_events())
	return events


func test_the_layout_is_one_bubble_with_three_modules_and_free_doors() -> void:
	var sim := ReefSettlement.new(rules)
	check_eq(Array(sim.layout_problems()), [], "the spike's layout is buildable")
	var kinds: Array = sim.modules.map(func(m): return String(m.kind))
	for kind in ["shelter", "hearth", "pen"]:
		check_eq(kinds.count(kind), 1, "one %s" % kind)
	check_eq(sim.workers.size(), 3, "three workers")
	check(not sim.is_free(Vector3i(7, 0, 7)), "the reef rock is not free")
	check(not sim.is_free(Vector3i(0, 8, 0)), "nor is the water outside the bubble")
	var crowded: Dictionary = rules.duplicate(true)
	crowded.modules[1].min = crowded.modules[0].min
	check(not ReefSettlement.new(crowded).layout_problems().is_empty(), "overlapping modules are refused")


func test_paths_are_three_dimensional_and_stay_in_free_cells() -> void:
	var sim := ReefSettlement.new(rules)
	var pen: Vector3i = sim._doors["pen"]
	var hearth: Vector3i = sim._doors["hearth"]
	check(pen.y > hearth.y, "the pen's door is above the hearth's")
	var p := sim.path(hearth, pen)
	check(not p.is_empty() and p.back() == pen, "there is a way from the hearth up to the pen")
	var at := hearth
	var climbs := 0
	for c in p:
		var step: Vector3i = c - at
		check(absi(step.x) + absi(step.y) + absi(step.z) == 1, "one cell at a time (%s to %s)" % [at, c])
		check(sim.is_free(c), "%s is free" % c)
		climbs += absi(step.y)
		at = c
	check(climbs >= pen.y - hearth.y, "the path climbs (%d cells up or down)" % climbs)
	check_eq(sim.path(hearth, pen), p, "the same question gets the same path")
	check_eq(sim.path(hearth, hearth), [], "no path to where it already is")


func test_the_starting_food_shortage_is_resolved_by_the_workers() -> void:
	var sim := ReefSettlement.new(rules)
	check(sim.shortage, "the settlement starts short of food")
	var events := _run(sim, 3 * 60 * ReefSettlement.TICKS_PER_SECOND)
	var resolved := events.filter(func(e): return e.type == "shortage_resolved")
	check(resolved.size() >= 1, "the shortage is resolved within three minutes")
	check(events.any(func(e): return e.type == "job_done" and e.job == "fetch"), "by carrying food from the pen")
	check(sim.food >= float(rules.food.shortage_below), "food is above the shortage line (%.1f)" % sim.food)


func test_slow_ten_minutes_leave_no_worker_stuck() -> void:
	var sim := ReefSettlement.new(rules)
	var events := _run(sim, TEN_MINUTES)
	check_eq(Array(sim.stuck), [], "no worker is stuck after ten minutes")
	check(events.all(func(e): return e.type != "stuck"), "and none ever was")
	var jobs := {}
	for e in events:
		if e.type == "job_done":
			jobs[e.job] = int(jobs.get(e.job, 0)) + 1
	for job in ["fetch", "stoke", "rest", "tend"]:
		check(int(jobs.get(job, 0)) > 0, "the workers %s (%d times)" % [job, int(jobs.get(job, 0))])
	for w in sim.workers:
		check(int(w.jobs) >= 10, "%s finished %d jobs" % [w.id, int(w.jobs)])
		check(sim.is_free(w.cell), "%s is in a free cell" % w.id)
	check(sim.food > 0.0 and sim.warmth > 0.0, "the settlement still has food (%.1f) and warmth (%.1f)" % [sim.food, sim.warmth])
	check(not sim.shortage or sim.shortages_resolved >= 1, "shortages do not last")
	var again := ReefSettlement.new(rules)
	_run(again, TEN_MINUTES)
	check_eq(JSON.stringify(again.snapshot()), JSON.stringify(sim.snapshot()), "two runs are identical")


func test_a_walled_in_door_is_reported_as_stuck() -> void:
	var walled: Dictionary = rules.duplicate(true)
	# A slab over the whole bubble at the pen door's height cuts the pen off from the floor.
	walled.modules.append({"id": "slab", "kind": "support", "min": [0, 3, 0], "size": [15, 1, 15], "door": [0, 2, 0]})
	var sim := ReefSettlement.new(walled)
	var events := _run(sim, 60 * ReefSettlement.TICKS_PER_SECOND)
	check(events.any(func(e): return e.type == "stuck"), "a worker sent to an unreachable door says so")
	check(not sim.stuck.is_empty(), "and is listed as stuck")
	for w in sim.workers:
		check(sim.is_free(w.cell), "%s never walked through the slab" % w.id)
