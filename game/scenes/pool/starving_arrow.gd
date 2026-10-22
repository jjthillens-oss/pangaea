class_name StarvingArrow
extends Control
## While the cell starves, an arrow from the cell toward the nearest food it can eat (M1 step 2
## assist; the layout's assists.starving_food_arrow turns it on). It stops short of the food when
## the food is on screen and sits at the screen edge when it is not. A shape and a distance label
## carry it, not colour alone. The pool tells it where to point.

const EDGE_MARGIN_PX := 72.0
const SHORT_OF_FOOD_PX := 60.0
const MIN_FROM_CELL_PX := 96.0
const SIZE_PX := 24.0
const OUTLINE_PX := 3.0
const PULSE_HZ := 1.0
const PULSE_SHARE := 0.15
const COLOR := Color(1.0, 0.83, 0.42)
const OUTLINE := Color(0.03, 0.13, 0.15, 0.85)
const FONT_SIZE := 22
const LABEL_GAP_PX := 6.0

## Where the arrow sits and the way it points, in screen pixels.
var arrow_position := Vector2.ZERO
var arrow_direction := Vector2.RIGHT
var distance_m := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Points from the cell's screen position along `direction` (a screen direction) toward food
## `food_distance_m` away. `food_px` is the food's screen position, or Vector2.INF when the food
## is off screen or behind the camera.
func point(cell_px: Vector2, direction: Vector2, food_px: Vector2, food_distance_m: float) -> void:
	if direction.is_zero_approx():
		direction = Vector2.UP
	arrow_direction = direction.normalized()
	distance_m = food_distance_m
	var reach := _to_edge(cell_px, arrow_direction)
	if food_px.is_finite():
		reach = minf(reach, cell_px.distance_to(food_px) - SHORT_OF_FOOD_PX)
	arrow_position = cell_px + arrow_direction * maxf(reach, MIN_FROM_CELL_PX)
	if not visible:
		_t = 0.0
		visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


## Distance from `from` along `dir` to the screen rectangle inset by EDGE_MARGIN_PX.
func _to_edge(from: Vector2, dir: Vector2) -> float:
	var rect := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN_PX)
	var best := INF
	for axis in 2:
		if absf(dir[axis]) < 1e-6:
			continue
		var bound: float = rect.end[axis] if dir[axis] > 0.0 else rect.position[axis]
		best = minf(best, (bound - from[axis]) / dir[axis])
	return maxf(best, 0.0) if is_finite(best) else 0.0


func _draw() -> void:
	var s := SIZE_PX * (1.0 + PULSE_SHARE * sin(_t * TAU * PULSE_HZ))
	var fwd := arrow_direction
	var side := fwd.orthogonal()
	# A long, narrow arrowhead with a notched back, so its direction reads at a glance.
	var points := PackedVector2Array([arrow_position + fwd * s,
		arrow_position - fwd * s * 0.9 + side * s * 0.6,
		arrow_position - fwd * s * 0.4,
		arrow_position - fwd * s * 0.9 - side * s * 0.6])
	var outline := points.duplicate()
	outline.append(points[0])
	draw_colored_polygon(points, COLOR)
	draw_polyline(outline, OUTLINE, OUTLINE_PX, true)
	# The distance sits behind the arrow along its axis, clear of the arrowhead.
	var font := get_theme_default_font()
	var text := "Food %d m" % roundi(distance_m)
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var behind := s * 0.9 + absf(fwd.x) * box.x * 0.5 + absf(fwd.y) * box.y * 0.5 + LABEL_GAP_PX
	var center := arrow_position - fwd * behind
	var baseline := center + Vector2(-box.x * 0.5, font.get_ascent(FONT_SIZE) - box.y * 0.5)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 6, OUTLINE)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR)
