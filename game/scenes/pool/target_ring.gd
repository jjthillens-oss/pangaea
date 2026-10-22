class_name TargetRing
extends Control
## A ring on the point the cell swims toward while the swim button is held (M1 step 2). Drawn in
## screen space over the pool; the pool tells it where.

const RADIUS_PX := 20.0
const WIDTH_PX := 3.0
const OUTLINE_PX := 2.0
const PULSE_HZ := 1.5
const PULSE_SHARE := 0.12
const COLOR := Color(1.0, 0.97, 0.86, 0.95)
const OUTLINE := Color(0.03, 0.13, 0.15, 0.8)

var _at := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_at(screen_position: Vector2) -> void:
	_at = screen_position
	if not visible:
		_t = 0.0
		visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r := RADIUS_PX * (1.0 + PULSE_SHARE * sin(_t * TAU * PULSE_HZ))
	draw_arc(_at, r, 0.0, TAU, 48, OUTLINE, WIDTH_PX + 2.0 * OUTLINE_PX, true)
	draw_arc(_at, r, 0.0, TAU, 48, COLOR, WIDTH_PX, true)
	draw_circle(_at, 3.0, COLOR)
