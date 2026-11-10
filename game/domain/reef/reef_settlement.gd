class_name ReefSettlement
extends RefCounted
## The reef spike's settlement rules (backlog U-03; aquatic path addendum sections E and H, M4.5; PROPOSED): one air
## bubble on the reef, modules that occupy volume (a shelter, a vent hearth and a food pen raised on a ledge), and
## workers who path in three dimensions between their doors. Pure rules: no scene, UI or file access; the tuning is
## the dictionary from game/data/reef/reef_spike.json.
##
## Deterministic at 60 ticks a second: durations are whole ticks (converted once here), workers act in id order,
## paths are breadth-first with a fixed neighbour order, and there is no random draw. Cells are [x, y, z] with +Y
## up; y = 0 is the reef rock. A cell is free when it is inside the grid, above the rock, inside the bubble and not
## inside a module.
##
## Each worker, when idle, takes the most pressing job (Bible section 9: needs before wants):
##   fetch  food is short and the pen holds some: swim to the pen's door, take a load, carry it to the hearth's store
##   stoke  the hearth's warmth is low: tend it
##   rest   the worker's energy is low: rest in the shelter
##   tend   otherwise: tend the pen so it grows stock
## A worker with no path to its job's door, or one that has not finished a job for stuck_after_s, is reported in
## `stuck` and as a "stuck" event; the spike's acceptance is that this never happens.

const TICKS_PER_SECOND := 60
## The order neighbours are tried in: level moves before climbing, so paths hug the floor where they can.
const NEIGHBOURS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var rules: Dictionary
var tick := 0
var grid := Vector3i.ZERO
var food := 0.0
var pen_stock := 0.0
var warmth := 0.0
var shortage := false
var shortages_resolved := 0
## {"id", "kind", "min": Vector3i, "size": Vector3i, "door": Vector3i}, in id order.
var modules: Array = []
## {"id", "cell": Vector3i, "energy", "job", "phase", "path": Array[Vector3i], "wait", "carry", "since_job", "jobs"},
## in id order.
var workers: Array = []
## Ids of workers that could not reach a door or went too long without finishing a job.
var stuck: PackedStringArray = []
var _events: Array = []
var _free := {}
var _doors := {}
var _step_ticks := 1
var _stuck_ticks := 1


func _init(p_rules: Dictionary) -> void:
	rules = p_rules
	grid = _cell(rules.grid)
	for m in rules.modules:
		modules.append({"id": String(m.id), "kind": String(m.kind), "min": _cell(m.min), "size": _cell(m.size),
				"door": _cell(m.door)})
	modules.sort_custom(func(a, b): return a.id < b.id)
	for m in modules:
		if m.kind != "support":
			_doors[m.kind] = m.door
	_build_free()
	for w in rules.workers:
		workers.append({"id": String(w.id), "cell": _cell(w.start), "energy": float(rules.energy.start), "job": "",
				"phase": "", "path": [], "wait": 0, "carry": 0.0, "since_job": 0, "jobs": 0})
	workers.sort_custom(func(a, b): return a.id < b.id)
	food = float(rules.food.start)
	pen_stock = float(rules.pen.start)
	warmth = float(rules.warmth.start)
	_step_ticks = _ticks(rules.move.step_s)
	_stuck_ticks = _ticks(rules.stuck_after_s)
	shortage = food < float(rules.food.shortage_below)
	if shortage:
		_emit("shortage", {"food": food})


static func _cell(a: Array) -> Vector3i:
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func _ticks(seconds: Variant) -> int:
	return maxi(1, roundi(float(seconds) * TICKS_PER_SECOND))


func _build_free() -> void:
	var centre := Vector3(_cell(rules.bubble.centre))
	var radius := float(rules.bubble.radius)
	for x in grid.x:
		for y in range(1, grid.y):
			for z in grid.z:
				var c := Vector3i(x, y, z)
				if Vector3(c).distance_to(centre) <= radius and module_at(c).is_empty():
					_free[c] = true


## The module whose volume holds `c`, or {}.
func module_at(c: Vector3i) -> Dictionary:
	for m in modules:
		var lo: Vector3i = m.min
		var hi: Vector3i = lo + (m.size as Vector3i)
		if c.x >= lo.x and c.x < hi.x and c.y >= lo.y and c.y < hi.y and c.z >= lo.z and c.z < hi.z:
			return m
	return {}


func is_free(c: Vector3i) -> bool:
	return _free.has(c)


## What is wrong with the layout, as sentences: a module outside the grid or the bubble, two that overlap, a door that
## is not a free cell beside its module, or a worker that starts in a wall. Empty when the settlement can be built.
func layout_problems() -> PackedStringArray:
	var out := PackedStringArray()
	var centre := Vector3(_cell(rules.bubble.centre))
	var radius := float(rules.bubble.radius)
	for i in modules.size():
		var m: Dictionary = modules[i]
		var lo: Vector3i = m.min
		var hi: Vector3i = lo + (m.size as Vector3i) - Vector3i.ONE
		for corner in [lo, hi, Vector3i(lo.x, hi.y, hi.z), Vector3i(hi.x, lo.y, lo.z), Vector3i(hi.x, hi.y, lo.z),
				Vector3i(lo.x, lo.y, hi.z), Vector3i(hi.x, lo.y, hi.z), Vector3i(lo.x, hi.y, lo.z)]:
			var c: Vector3i = corner
			if c.x < 0 or c.y < 1 or c.z < 0 or c.x >= grid.x or c.y >= grid.y or c.z >= grid.z \
					or Vector3(c).distance_to(centre) > radius:
				out.append("%s reaches outside the bubble at %s." % [m.id, c])
				break
		for j in range(i + 1, modules.size()):
			var o: Dictionary = modules[j]
			var olo: Vector3i = o.min
			var ohi: Vector3i = olo + (o.size as Vector3i) - Vector3i.ONE
			if lo.x <= ohi.x and olo.x <= hi.x and lo.y <= ohi.y and olo.y <= hi.y and lo.z <= ohi.z and olo.z <= hi.z:
				out.append("%s and %s overlap." % [m.id, o.id])
		var door: Vector3i = m.door
		var beside := false
		for n in NEIGHBOURS:
			if module_at(door + n).get("id", "") == m.id:
				beside = true
		if not is_free(door) or not beside:
			out.append("%s's door at %s is not a free cell beside it." % [m.id, door])
	for w in workers:
		if not is_free(w.cell):
			out.append("%s starts inside a wall at %s." % [w.id, w.cell])
	return out


## The shortest path of free cells from `from` to `to`, without `from` and with `to`; empty when they are the same
## cell or there is no way. Breadth-first in NEIGHBOURS order, so the same question always gets the same path.
func path(from: Vector3i, to: Vector3i) -> Array:
	if from == to or not is_free(from) or not is_free(to):
		return []
	var came := {from: from}
	var queue: Array[Vector3i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == to:
			break
		for n in NEIGHBOURS:
			var next := c + n
			if _free.has(next) and not came.has(next):
				came[next] = c
				queue.append(next)
	if not came.has(to):
		return []
	var out: Array = []
	var at := to
	while at != from:
		out.append(at)
		at = came[at]
	out.reverse()
	return out


func step() -> void:
	tick += 1
	var dt := 1.0 / TICKS_PER_SECOND
	food = maxf(0.0, food - float(rules.food.eat_per_worker_per_s) * workers.size() * dt)
	warmth = maxf(0.0, warmth - float(rules.warmth.decay_per_s) * dt)
	pen_stock = minf(float(rules.pen.cap), pen_stock + float(rules.pen.grow_per_s) * dt)
	for w in workers:
		w.energy = maxf(0.0, float(w.energy) - float(rules.energy.drain_per_s) * dt)
		w.since_job = int(w.since_job) + 1
		if String(w.job) == "":
			_take_job(w)
		_work(w)
		if int(w.since_job) > _stuck_ticks and not String(w.id) in stuck:
			_mark_stuck(w, "no job finished in %d s" % int(rules.stuck_after_s))
	if shortage and food >= float(rules.food.ok_at):
		shortage = false
		shortages_resolved += 1
		_emit("shortage_resolved", {"food": food})
	elif not shortage and food < float(rules.food.shortage_below):
		shortage = true
		_emit("shortage", {"food": food})


## How many workers are on `job` now.
func _on_job(job: String) -> int:
	var n := 0
	for w in workers:
		if String(w.job) == job:
			n += 1
	return n


func _take_job(w: Dictionary) -> void:
	var job := "tend"
	# Food on its way counts, so the whole settlement does not swim for the pen at once.
	var coming := _on_job("fetch") * float(rules.food.carry)
	if float(w.energy) < float(rules.energy.low_below):
		job = "rest"
	elif food + coming < float(rules.food.ok_at) and pen_stock >= 1.0 and (shortage or food < float(rules.food.shortage_below)):
		job = "fetch"
	elif warmth < float(rules.warmth.low_below) and _on_job("stoke") == 0:
		job = "stoke"
	w.job = job
	var door: Vector3i = _doors[{"fetch": "pen", "tend": "pen", "stoke": "hearth", "rest": "shelter"}[job]]
	_head_for(w, door, "go")


func _head_for(w: Dictionary, door: Vector3i, phase: String) -> void:
	w.phase = phase
	w.wait = _step_ticks
	w.path = path(w.cell, door)
	if (w.path as Array).is_empty() and w.cell != door:
		_mark_stuck(w, "no path from %s to %s" % [w.cell, door])
		w.job = ""
		w.phase = ""


func _work(w: Dictionary) -> void:
	match String(w.phase):
		"go", "carry":
			if not (w.path as Array).is_empty():
				w.wait = int(w.wait) - 1
				if int(w.wait) <= 0:
					w.cell = (w.path as Array).pop_front()
					w.wait = _step_ticks
				return
			_arrive(w)
		"work":
			w.wait = int(w.wait) - 1
			if int(w.wait) <= 0:
				_finish(w)


func _arrive(w: Dictionary) -> void:
	if String(w.phase) == "carry":
		food = minf(float(rules.food.cap), food + float(w.carry))
		w.carry = 0.0
		_done(w)
		return
	match String(w.job):
		"fetch":
			w.carry = minf(float(rules.food.carry), pen_stock)
			pen_stock -= float(w.carry)
			_head_for(w, _doors["hearth"], "carry")
		"stoke":
			w.phase = "work"
			w.wait = _ticks(rules.warmth.stoke_s)
		"rest":
			w.phase = "work"
			w.wait = _ticks(rules.energy.rest_s)
		_:
			w.phase = "work"
			w.wait = _ticks(rules.pen.tend_s)


func _finish(w: Dictionary) -> void:
	match String(w.job):
		"stoke":
			warmth = minf(float(rules.warmth.cap), warmth + float(rules.warmth.stoke_gain))
		"rest":
			w.energy = minf(float(rules.energy.cap), float(w.energy) + float(rules.energy.rest_gain))
		_:
			pen_stock = minf(float(rules.pen.cap), pen_stock + float(rules.pen.tend_gain))
	_done(w)


func _done(w: Dictionary) -> void:
	_emit("job_done", {"worker": w.id, "job": w.job})
	w.jobs = int(w.jobs) + 1
	w.since_job = 0
	w.job = ""
	w.phase = ""


func _mark_stuck(w: Dictionary, why: String) -> void:
	if not String(w.id) in stuck:
		stuck.append(String(w.id))
	_emit("stuck", {"worker": w.id, "why": why})


func _emit(type: String, data := {}) -> void:
	var e := {"type": type, "tick": tick}
	e.merge(data)
	_events.append(e)


## The events since the last call, oldest first.
func take_events() -> Array:
	var out := _events
	_events = []
	return out


## The whole state as plain data (cells as [x, y, z]), for views, tests and hashing.
func snapshot() -> Dictionary:
	var ws: Array = []
	for w in workers:
		var c: Vector3i = w.cell
		ws.append({"id": w.id, "cell": [c.x, c.y, c.z], "energy": w.energy, "job": w.job, "phase": w.phase,
				"carry": w.carry, "jobs": w.jobs})
	return {"tick": tick, "food": food, "pen_stock": pen_stock, "warmth": warmth, "shortage": shortage,
			"shortages_resolved": shortages_resolved, "workers": ws, "stuck": Array(stuck)}
