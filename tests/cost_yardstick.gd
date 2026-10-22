extends RefCounted
## Test helper (not a test file): the cost gates' yardstick. A fixed piece of plain GDScript work
## (vector math over every pair of POINTS points, three times over, into a packed array: about
## 100 us in the Linux container) that a gate times right after each timed step, on the same thread.
## Time-slicing by other processes lands on the step and the yardstick in proportion to their
## length, so the ratio of their times holds where the microseconds do not: pinned to one core
## beside a busy loop, the microseconds doubled while the 7-creature tick read 5.0 yardsticks and the
## 24-creature tick 15.8, as at load 5 to 6 (4.7 to 4.8, 15.2), and a step made twice as costly
## read 9.4 to 10.1 and 28.1 to 31.9. Heavy load can still move the ratio: see the flake policy in
## docs/DECISIONS.md, M1 step 3 review fixes.
## It allocates nothing. The first version built a dictionary each time, and its time grew with
## the heap and with the cost of the step before it: a step made twice as costly read only 1.5 to
## 1.6 times the yardsticks on the 24-creature gate (23.3 against 14.6 at load 5.5).
##
##     const Yardstick := preload("res://tests/cost_yardstick.gd")
##     var yard_us := Yardstick.time_once()

const POINTS := 24
const NEAR_M := 10.0
const PASSES := 3

static var _points := _spiral()
static var _near := _pair_slots()
static var _sink := 0.0   ## keeps the work's result, so the work is never skipped


## Runs the work once and returns its wall time in microseconds.
static func time_once() -> int:
	var t0 := Time.get_ticks_usec()
	var total := 0.0
	for _pass in PASSES:
		total += _work()
	_sink = total
	return Time.get_ticks_usec() - t0


## The middle value of `values` (the higher middle one for an even count).
static func median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[floori(sorted.size() / 2.0)]


## Every pair of the points: the near ones' distances and bearings, the way the senses and the
## separation pass look at bodies.
static func _work() -> float:
	var total := 0.0
	var count := 0
	for i in POINTS:
		var p := _points[i]
		for j in range(i + 1, POINTS):
			var d := p.distance_to(_points[j])
			if d < NEAR_M:
				total += d + p.angle_to_point(_points[j])
				_near[i * POINTS + j] = d
				count += 1
	return total + count


## POINTS points on a spiral.
static func _spiral() -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in POINTS:
		points.append(Vector2.from_angle(k * 2.39996) * (2.0 + k * 0.75))
	return points


## A slot for every pair's distance.
static func _pair_slots() -> PackedFloat32Array:
	var slots := PackedFloat32Array()
	slots.resize(POINTS * POINTS)
	return slots
