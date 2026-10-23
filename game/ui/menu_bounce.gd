class_name MenuBounce
extends RefCounted
## The title screens' playful touch (UI pass, "alive like Spore, in Pangaea's style"): menu buttons
## that swell with a little overshoot when focused or hovered and squash when pressed, rounded pill
## shapes for the title menu, and views that slide and fade in with their buttons arriving one
## after another. With Reduce camera motion on, the swell has no overshoot and nothing slides.
## It only changes how controls look; focus, signals and layout are left alone.

const GROW := 1.06
const GROW_S := 0.22
const SQUASH := 0.94
const SQUASH_S := 0.08
const PILL_RADIUS := 30
const SLIDE_PX := 48.0
const SLIDE_S := 0.32
const STAGGER_S := 0.05
const STYLES := [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]


static func _calm() -> bool:
	return SettingsService.shared().reduce_camera_motion()


## Makes `control` swell on focus and hover, and squash on press when it is a button.
static func attach(control: Control, grow: float = GROW) -> void:
	control.set_meta(&"bounce_grow", grow)
	control.resized.connect(func(): control.pivot_offset = control.size * 0.5)
	control.pivot_offset = control.size * 0.5
	control.focus_entered.connect(_settle.bind(control))
	control.focus_exited.connect(_settle.bind(control))
	control.mouse_entered.connect(func():
		control.set_meta(&"bounce_hover", true)
		_settle(control))
	control.mouse_exited.connect(func():
		control.set_meta(&"bounce_hover", false)
		_settle(control))
	if control is BaseButton:
		(control as BaseButton).button_down.connect(_squash.bind(control))
		(control as BaseButton).button_up.connect(_settle.bind(control))


## The scale `control` should rest at now: swollen while focused or hovered, else 1.
static func rest_scale(control: Control) -> float:
	var lit := control.has_focus() or bool(control.get_meta(&"bounce_hover", false))
	if control is BaseButton and (control as BaseButton).disabled:
		lit = false
	return float(control.get_meta(&"bounce_grow", GROW)) if lit else 1.0


static func _settle(control: Control) -> void:
	_tween_scale(control, rest_scale(control), GROW_S, Tween.TRANS_SINE if _calm() else Tween.TRANS_BACK)


static func _squash(control: Control) -> void:
	_tween_scale(control, SQUASH, SQUASH_S, Tween.TRANS_SINE)


static func _tween_scale(control: Control, to: float, seconds: float, trans: Tween.TransitionType) -> void:
	if not control.is_inside_tree():
		control.scale = Vector2.ONE * to
		return
	if control.has_meta(&"bounce_tween"):
		var old: Tween = control.get_meta(&"bounce_tween")
		if old != null and old.is_valid():
			old.kill()
	var tween := control.create_tween().set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * to, seconds)
	control.set_meta(&"bounce_tween", tween)


## Rounds a button's styles into a pill (as overrides; the shared theme is untouched).
static func pill(button: Button) -> void:
	for style_name in STYLES:
		var style := button.get_theme_stylebox(style_name)
		if not style is StyleBoxFlat:
			continue
		var rounded := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		var extra := maxf(rounded.expand_margin_left, 0.0)
		rounded.set_corner_radius_all(PILL_RADIUS + int(extra))
		button.add_theme_stylebox_override(style_name, rounded)


## Slides `view` in from `offset` while it fades up, then its `items` fade in one after another.
## The view must fill its parent (its resting position is 0, 0).
static func arrive(view: Control, items: Array = [], offset: Vector2 = Vector2(-SLIDE_PX, 0.0)) -> void:
	if not view.is_inside_tree():
		return
	var calm := _calm()
	var tween := view.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	view.modulate.a = 0.0
	tween.tween_property(view, "modulate:a", 1.0, SLIDE_S)
	if not calm:
		view.position = offset
		tween.tween_property(view, "position", Vector2.ZERO, SLIDE_S)
	for i in items.size():
		var item: CanvasItem = items[i]
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, SLIDE_S).set_delay(0.08 + STAGGER_S * i)
