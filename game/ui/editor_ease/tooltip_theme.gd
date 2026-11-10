extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): the editors' tooltips in the game's glass, not in Godot's default
## tooltip look. A small Theme holding only TooltipPanel (the GlassPanel stylebox, as opaque as the part card) and
## TooltipLabel's colour, set on the editors' own containers; every other look still comes from pangaea_theme.tres
## above them, which this does not edit. The font size is left to that theme, so a tooltip follows the text-size
## setting. No class_name; preload it.

const GAME_THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const PartCard := preload("res://game/ui/editor_ease/part_card.gd")
## A tooltip's padding, left and right, and top and bottom: less than the glass panels', for one or two lines.
const PAD := Vector2(12, 8)

static var _theme: Theme


## The shared tooltip theme, made once.
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	var glass := GAME_THEME.get_stylebox(&"panel", &"GlassPanel").duplicate() as StyleBox
	if glass is StyleBoxFlat:
		glass.bg_color.a = maxf(glass.bg_color.a, PartCard.OPACITY)
	glass.content_margin_left = PAD.x
	glass.content_margin_right = PAD.x
	glass.content_margin_top = PAD.y
	glass.content_margin_bottom = PAD.y
	_theme.set_stylebox(&"panel", &"TooltipPanel", glass)
	_theme.set_color(&"font_color", &"TooltipLabel", GAME_THEME.get_color(&"font_color", &"Label"))
	return _theme


## Gives `node` the tooltip theme, unless it has a theme of its own (that one is left alone).
static func apply(node: Control) -> void:
	if node != null and node.theme == null:
		node.theme = get_theme()
