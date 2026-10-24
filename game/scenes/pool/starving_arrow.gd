class_name StarvingArrow
extends Control
## While the cell starves, an arrow from the cell toward the nearest food it can eat (M1 step 2
## assist; the layout's assists.starving_food_arrow turns it on). It stops short of the food when
## the food is on screen and sits at the screen edge when it is not. A shape and a distance label
## carry it, not colour alone. The pool tells it where to point. The label never covers the cell:
## when food is close and the arrow sits next to the cell, it moves beside the arrowhead.

const EDGE_MARGIN_PX := 72.0
const SHORT_OF_FOOD_PX := 60.0
const MIN_FROM_CELL_PX := 96.0
const SIZE_PX := 24.0
const OUTLINE_PX := 3.0
const PULSE_HZ := 1.0
const PULSE_SHARE := 0.15
const COLOR := Color(1.0, 0.83, 0.42)
const OUTLINE := Color(UiPalette.KEYLINE, 0.85)
## The label at 100% text size; it follows the Text size setting (Bible 19), as the theme does.
const FONT_SIZE := 22
const LABEL_OUTLINE_PX := 6
const LABEL_GAP_PX := 6.0
## The label keeps clear of this many cell radii, which takes in the mouth and eyes.
const CELL_CLEAR := 1.35
const LABEL_SLIDE_PX := 4.0

## Where the arrow sits and the way it points, in screen pixels.
var arrow_position := Vector2.ZERO
var arrow_direction := Vector2.RIGHT
var distance_m := 0.0
## The cell's screen position and radius, which the label keeps clear of.
var cell_position := Vector2.ZERO
var cell_radius_px := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Points from the cell's screen position along `direction` (a screen direction) toward food
## `food_distance_m` away. `food_px` is the food's screen position, or Vector2.INF when the food
## is off screen or behind the camera. `cell_radius_px` is the cell's radius on screen.
func point(cell_px: Vector2, direction: Vector2, food_px: Vector2, food_distance_m: float,
		p_cell_radius_px: float = 0.0) -> void:
	if direction.is_zero_approx():
		direction = Vector2.UP
	arrow_direction = direction.normalized()
	distance_m = food_distance_m
	cell_position = cell_px
	cell_radius_px = p_cell_radius_px
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


## "Food 3 m"
## The label's font size at the chosen text size.
static func font_size() -> int:
	return roundi(FONT_SIZE * int(SettingsService.shared().get_value("accessibility/text_scale")) / 100.0)


func label_text() -> String:
	return tr("UI_FOOD_D_M_50EC97") % roundi(distance_m)


## The distance label's box on screen. It sits behind the arrow along its axis, clear of the
## arrowhead at its largest pulse (so the label holds still), unless that would cover the cell;
## then it sits beside the arrowhead, slid forward along the arrow until it is clear of the cell.
func label_rect() -> Rect2:
	var s := SIZE_PX * (1.0 + PULSE_SHARE)
	var fwd := arrow_direction
	var box := get_theme_default_font().get_string_size(label_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size())
	var behind := s * 0.9 + absf(fwd.x) * box.x * 0.5 + absf(fwd.y) * box.y * 0.5 + LABEL_GAP_PX
	var rect := Rect2(arrow_position - fwd * behind - box * 0.5, box)
	if not _over_cell(rect):
		return rect
	var side := fwd.orthogonal()
	var beside := s * 0.6 + absf(side.x) * box.x * 0.5 + absf(side.y) * box.y * 0.5 + LABEL_GAP_PX
	rect.position = arrow_position + side * beside - box * 0.5
	for i in 64:
		if not _over_cell(rect):
			break
		rect.position += fwd * LABEL_SLIDE_PX
	return rect


func _over_cell(rect: Rect2) -> bool:
	var nearest := cell_position.clamp(rect.position, rect.end)
	return nearest.distance_to(cell_position) < cell_radius_px * CELL_CLEAR + LABEL_GAP_PX


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
	var font := get_theme_default_font()
	var text := label_text()
	var size_px := font_size()
	var outline_px := roundi(LABEL_OUTLINE_PX * size_px / float(FONT_SIZE))
	var baseline := label_rect().position + Vector2(0.0, font.get_ascent(size_px))
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, outline_px, OUTLINE)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, COLOR)
