class_name HudIcon
extends Control
## A small drawn icon, so a cue never rests on colour alone and needs no font glyph (M1 step 2):
## "diamond" marks adaptation points, "warning" marks the starving banner.

@export_enum("diamond", "warning") var shape := "diamond"
@export var color := Color(1.0, 0.83, 0.42)
@export var outline := Color(0.03, 0.11, 0.13, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := size
	match shape:
		"diamond":
			var points := PackedVector2Array([Vector2(s.x * 0.5, 0.0), Vector2(s.x, s.y * 0.5),
				Vector2(s.x * 0.5, s.y), Vector2(0.0, s.y * 0.5)])
			draw_colored_polygon(points, color)
			points.append(points[0])
			draw_polyline(points, outline, 2.0, true)
		"warning":
			var points := PackedVector2Array([Vector2(s.x * 0.5, 0.0), Vector2(s.x, s.y), Vector2(0.0, s.y)])
			draw_colored_polygon(points, color)
			points.append(points[0])
			draw_polyline(points, outline, 2.0, true)
			# An exclamation mark: a bar and a dot.
			var w := maxf(2.0, s.x * 0.11)
			draw_rect(Rect2(s.x * 0.5 - w * 0.5, s.y * 0.32, w, s.y * 0.36), outline)
			draw_rect(Rect2(s.x * 0.5 - w * 0.5, s.y * 0.76, w, w), outline)
