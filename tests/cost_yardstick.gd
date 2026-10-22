extends RefCounted
## Test helper (not a test file): the cost gates' yardstick. A fixed piece of plain GDScript work
## (vector math, a dictionary and an array: about 75 us on its own in the Linux container, about
## 120 us right after a sim step has filled the caches) that a gate times right after each timed
## step, on the same thread. Load from other processes slows the step and the yardstick alike, so
## the ratio of their times holds where the microseconds do not: under steady load from three other
## test runs, or pinned to one core beside a busy loop, the 7-creature tick read 4.7 to 5.3
## yardsticks while its microseconds doubled, and a step made twice as costly read 9.4 to 10.8.
##
##     const Yardstick := preload("res://tests/cost_yardstick.gd")
##     var yard_us := Yardstick.time_once()

const POINTS := 24
const NEAR_M := 10.0

static var _sink := 0.0   ## keeps the work's result, so the work is never skipped


## Runs the work once and returns its wall time in microseconds.
static func time_once() -> int:
	var t0 := Time.get_ticks_usec()
	_sink = _work()
	return Time.get_ticks_usec() - t0


## Every pair of POINTS points on a spiral: the near ones' distances and bearings, the way the
## senses and the separation pass look at bodies.
static func _work() -> float:
	var points: Array[Vector2] = []
	for k in POINTS:
		points.append(Vector2.from_angle(k * 2.39996) * (2.0 + k * 0.75))
	var near := {}
	var total := 0.0
	for i in POINTS:
		var p := points[i]
		for j in range(i + 1, POINTS):
			var d := p.distance_to(points[j])
			if d < NEAR_M:
				total += d
				near[i * POINTS + j] = {"d": d, "bearing": p.angle_to_point(points[j])}
	return total + near.size()
