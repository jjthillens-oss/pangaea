class_name HudIcon
extends Control
## A small drawn icon, so a cue never rests on colour alone and needs no font glyph (M1 step 2):
## "diamond" marks adaptation points, "warning" marks the starving banner. M1 step 3 adds the
## threat glyphs of the off-screen arrows, "jaw" (an ambush hunter: mandibles) and "star" (a rammer:
## spikes), and "ring" for the shelter chip. draw_shape() draws any of them on another canvas item,
## so ThreatIndicators draws the same glyphs.

## The star's points and how deep its notches cut (share of the outer radius).
const STAR_POINTS := 6
const STAR_INNER := 0.45
const JAW_STEPS := 10               ## points along each edge of a mandible

@export_enum("diamond", "warning", "jaw", "star", "ring") var shape := "diamond"
@export var color := Color(1.0, 0.83, 0.42)
@export var outline := Color(0.03, 0.11, 0.13, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_shape(self, shape, Rect2(Vector2.ZERO, size), color, outline)


## Draws `p_shape` filling `rect` on `canvas` (inside its _draw).
static func draw_shape(canvas: CanvasItem, p_shape: String, rect: Rect2, fill: Color, line: Color) -> void:
	var s := rect.size
	var o := rect.position
	match p_shape:
		"diamond":
			var points := PackedVector2Array([o + Vector2(s.x * 0.5, 0.0), o + Vector2(s.x, s.y * 0.5),
				o + Vector2(s.x * 0.5, s.y), o + Vector2(0.0, s.y * 0.5)])
			_outlined(canvas, points, fill, line)
		"warning":
			var points := PackedVector2Array([o + Vector2(s.x * 0.5, 0.0), o + s, o + Vector2(0.0, s.y)])
			_outlined(canvas, points, fill, line)
			# An exclamation mark: a bar and a dot.
			var w := maxf(2.0, s.x * 0.11)
			canvas.draw_rect(Rect2(o + Vector2(s.x * 0.5 - w * 0.5, s.y * 0.32), Vector2(w, s.y * 0.36)), line)
			canvas.draw_rect(Rect2(o + Vector2(s.x * 0.5 - w * 0.5, s.y * 0.76), Vector2(w, w)), line)
		"jaw":
			# A pair of mandibles closing at the front (top), each with a tooth on its inner edge,
			# like the ambush hunter's pincers.
			for side in [-1.0, 1.0]:
				var base_out := Vector2(0.5 + side * 0.40, 0.94)
				var base_in := Vector2(0.5 + side * 0.13, 0.94)
				var tip := Vector2(0.5 + side * 0.05, 0.06)
				var bend_out := Vector2(0.5 + side * 0.66, 0.34)
				var bend_in := Vector2(0.5 + side * 0.30, 0.5)
				var points := PackedVector2Array()
				for i in JAW_STEPS + 1:
					points.append(o + _bezier(base_out, bend_out, tip, float(i) / JAW_STEPS) * s)
				for i in range(JAW_STEPS - 1, -1, -1):
					points.append(o + _bezier(base_in, bend_in, tip, float(i) / JAW_STEPS) * s)
				_outlined(canvas, points, fill, line)
				var tooth := _bezier(base_in, bend_in, tip, 0.48) - Vector2(side * 0.13, -0.02)
				_outlined(canvas, PackedVector2Array([o + _bezier(base_in, bend_in, tip, 0.35) * s,
					o + _bezier(base_in, bend_in, tip, 0.6) * s, o + tooth * s]), fill, line)
		"star":
			var c := o + s * 0.5
			var r := minf(s.x, s.y) * 0.5
			var points := PackedVector2Array()
			for i in STAR_POINTS * 2:
				var a := -PI * 0.5 + PI * i / STAR_POINTS
				points.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * STAR_INNER))
			_outlined(canvas, points, fill, line)
		"ring":
			var c := o + s * 0.5
			var r := minf(s.x, s.y) * 0.5
			var w := maxf(2.0, r * 0.3)
			canvas.draw_arc(c, r - w * 0.5, 0.0, TAU, 32, line, w + 2.0, true)
			canvas.draw_arc(c, r - w * 0.5, 0.0, TAU, 32, fill, w, true)


## The point `t` of the way along the quadratic curve from `a` to `b` bent toward `c`.
static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


static func _outlined(canvas: CanvasItem, points: PackedVector2Array, fill: Color, line: Color) -> void:
	canvas.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, line, 2.0, true)
