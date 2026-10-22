class_name FeedbackFx
extends Node3D
## World-space feedback that follows confirmed sim events (M1 step 2, Bible 20): a "+8 energy · +1"
## label rising from each meal, and a "Regrowing" label over every emptied plankton zone until it
## is full again. Labels are pooled Label3D nodes; nothing here changes the sim.
##
## Meals often come in quick runs through a plankton cluster. A meal soon after and close to the
## last one adds to its label ("+16 energy · +2") instead of drawing a second one on top of it.
## Other labels are kept a line apart in the order the pool camera shows them, not by height alone:
## seen from above at an angle, a label 1 m nearer the camera shows tan(pitch) m of height lower.
## An older label that shows below a new one stays below it (the new one starts higher if they
## would touch), and one that shows above it is pushed up a line clear of it (see _stack). They
## keep that order as they rise, so they never cross. The view is treated as parallel: perspective
## and camera motion can shift labels by a small part of a line.

const MEAL_LABELS := 6
const MEAL_RISE_M := 0.9
const MEAL_LIFE_S := 1.2
const MEAL_START_Y := 0.6
const MEAL_MERGE_S := 0.6         ## a meal this soon after the last one...
const MEAL_MERGE_M := 1.5         ## ...and this close to it adds to its label
## Labels whose centres are closer than this sideways can overlap: "+120 energy · +15" is 2.7 m wide.
const MEAL_NEAR_M := 3.0
## One line on screen, measured in the labels' own camera-facing plane: the font is 88 px tall at
## FONT_SIZE, so 0.44 m at PIXEL_SIZE, plus a little room.
const MEAL_LINE_M := 0.46
const MEAL_LIFT_RATE := 18.0      ## how fast a pushed label moves up (1/s, exponential)
const ZONE_LABEL_Y := 1.2
const ZONE_REFRESH_S := 0.25
const FONT_SIZE := 64
const PIXEL_SIZE := 0.005
const OUTLINE_SIZE := 14
const MEAL_COLOR := Color(1.0, 0.97, 0.86)
const ZONE_COLOR := Color(0.86, 0.97, 0.8)
const OUTLINE_COLOR := Color(0.03, 0.13, 0.15, 0.9)

var _meal_labels: Array[Label3D] = []
var _meal_ages := PackedFloat32Array()
var _meal_at := PackedVector2Array()        ## plane position of each label's last meal
var _meal_energy := PackedFloat32Array()    ## energy and points each label shows
var _meal_points := PackedInt32Array()
var _meal_lift := PackedFloat32Array()      ## how far each label sits above MEAL_START_Y (stacking)
var _meal_lift_shown := PackedFloat32Array()
var _next_meal := 0
var _zone_labels := {}   ## zone id -> Label3D
var _zone_refresh := 0.0
var _camera: PoolCamera


## zones: PoolLayout.zones. camera: the pool camera, whose pitch sets the labels' screen order.
## Builds the label pools.
func setup(zones: Array[Dictionary], camera: PoolCamera) -> void:
	_camera = camera
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_meal_labels.clear()
	_zone_labels.clear()
	for i in MEAL_LABELS:
		var label := _make_label(MEAL_COLOR)
		label.name = "Meal%d" % i
		_meal_labels.append(label)
	_meal_ages.resize(MEAL_LABELS)
	_meal_ages.fill(MEAL_LIFE_S)
	_meal_at.resize(MEAL_LABELS)
	_meal_at.fill(Vector2.ZERO)
	_meal_energy.resize(MEAL_LABELS)
	_meal_energy.fill(0.0)
	_meal_points.resize(MEAL_LABELS)
	_meal_points.fill(0)
	_meal_lift.resize(MEAL_LABELS)
	_meal_lift.fill(0.0)
	_meal_lift_shown.resize(MEAL_LABELS)
	_meal_lift_shown.fill(0.0)
	for z in zones:
		var label := _make_label(ZONE_COLOR)
		label.name = "Regrowing_%s" % z.id
		label.position = PlaneSpace.to_world(z.center, ZONE_LABEL_Y)
		_zone_labels[z.id] = label


## A meal label for an "ate" event: energy absorbed and points earned. It adds to the last label
## when that one is younger than MEAL_MERGE_S and within MEAL_MERGE_M.
func show_meal(event: Dictionary) -> void:
	if _meal_labels.is_empty():
		return
	var at: Vector2 = event.position
	var i := posmod(_next_meal - 1, _meal_labels.size())
	if _meal_labels[i].visible and _meal_ages[i] < MEAL_MERGE_S and _meal_at[i].distance_to(at) <= MEAL_MERGE_M:
		_meal_energy[i] += float(event.get("absorbed", 0.0))
		_meal_points[i] += int(event.get("points", 0))
	else:
		i = _next_meal
		_next_meal = (_next_meal + 1) % _meal_labels.size()
		_meal_energy[i] = float(event.get("absorbed", 0.0))
		_meal_points[i] = int(event.get("points", 0))
	var label := _meal_labels[i]
	_meal_ages[i] = 0.0
	_meal_at[i] = at
	_stack(i)
	label.text = meal_text({"absorbed": _meal_energy[i], "points": _meal_points[i]})
	label.position = PlaneSpace.to_world(at, MEAL_START_Y + _meal_lift_shown[i])
	label.modulate.a = 1.0
	label.outline_modulate.a = OUTLINE_COLOR.a
	label.visible = true


## Places label i, which starts rising at _meal_at[i], among the visible labels it could overlap
## sideways, comparing heights as the pool camera shows them. Going up the screen: a label below
## label i's start but within a line of it makes label i start a line above it; a label above it
## is pushed up until it is a line clear of label i before either rises (the older one always
## rises at least as far, so the line stays); and a pushed label carries up the labels stacked on
## it as far as it must to keep their gap. Labels only ever move up, so none passes another.
func _stack(i: int) -> void:
	var pitch := deg_to_rad(_camera.pitch_degrees())
	var shown := cos(pitch)   # a world height shows on screen at this share of its size
	var others: Array[int] = []
	for j in _meal_labels.size():
		if j != i and _meal_labels[j].visible:
			others.append(j)
	others.sort_custom(func(a: int, b: int) -> bool: return _screen_y(a, pitch, true) < _screen_y(b, pitch, true))
	_meal_lift[i] = 0.0
	var start := _screen_y(i, pitch, false)
	var push := {}   # label -> world height it moves up
	for j in others:
		var y := _screen_y(j, pitch, true)
		var base := _screen_y(j, pitch, false)
		var move := 0.0
		for k in push:
			if _sideways(j, k):
				var room := minf(base - _screen_y(k, pitch, false), y - _screen_y(k, pitch, true)) - MEAL_LINE_M
				move = maxf(move, push[k] - room / shown)
		if _sideways(j, i):
			var top := start + _meal_lift[i] * shown
			if y < top:
				_meal_lift[i] = maxf(_meal_lift[i], (y + MEAL_LINE_M - start) / shown)
			else:
				move = maxf(move, (top + MEAL_LINE_M - base) / shown)
		if move > 0.0:
			push[j] = move
	for j in push:
		_meal_lift[j] += push[j]
	_meal_lift_shown[i] = _meal_lift[i]


## How high label i shows on screen, in meters of its camera-facing plane (plane +y is toward the
## camera, so lower on screen), with or without what it has risen so far.
func _screen_y(i: int, pitch: float, risen: bool) -> float:
	var height := MEAL_START_Y + _meal_lift[i] + (_rise(_meal_ages[i]) if risen else 0.0)
	return height * cos(pitch) - _meal_at[i].y * sin(pitch)


## Whether labels i and j are close enough sideways to overlap; screen right is plane +x.
func _sideways(i: int, j: int) -> bool:
	return absf(_meal_at[i].x - _meal_at[j].x) < MEAL_NEAR_M


## How far a meal label has risen at `age`; fast at first, then slower.
static func _rise(age: float) -> float:
	return MEAL_RISE_M * ease(clampf(age / MEAL_LIFE_S, 0.0, 1.0), 0.4)


## "+8 energy · +1", or "+8 energy" when the meal earned no points.
static func meal_text(event: Dictionary) -> String:
	var text := "+%d energy" % roundi(float(event.get("absorbed", 0.0)))
	var points := int(event.get("points", 0))
	if points > 0:
		text += " · +%d" % points
	return text


## Shows "Regrowing" with the zone's stock over each zone that was emptied and is not full again.
func update_zones(region: EcologyRegion, plankton: PlanktonField, delta: float) -> void:
	_zone_refresh -= delta
	if _zone_refresh > 0.0:
		return
	_zone_refresh = ZONE_REFRESH_S
	for z in region.zones:
		var label: Label3D = _zone_labels.get(z.id)
		if label == null:
			continue
		label.visible = plankton.is_regrowing(z.id)
		if label.visible:
			label.text = "Regrowing %d%%" % floori(100.0 * z.amount / maxf(z.capacity, 1e-6))


## The meal labels on screen now, oldest first (for checks).
func meal_labels() -> Array[Label3D]:
	var order: Array[int] = []
	for i in _meal_labels.size():
		if _meal_labels[i].visible:
			order.append(i)
	order.sort_custom(func(a: int, b: int): return _meal_ages[a] > _meal_ages[b])
	var out: Array[Label3D] = []
	for i in order:
		out.append(_meal_labels[i])
	return out


## Label of a zone, for tests and the smoke check.
func zone_label(zone_id: String) -> Label3D:
	return _zone_labels.get(zone_id)


func _process(delta: float) -> void:
	for i in _meal_labels.size():
		if _meal_ages[i] >= MEAL_LIFE_S:
			continue
		_meal_ages[i] += delta
		var k := clampf(_meal_ages[i] / MEAL_LIFE_S, 0.0, 1.0)
		var label := _meal_labels[i]
		_meal_lift_shown[i] = lerpf(_meal_lift_shown[i], _meal_lift[i], minf(delta * MEAL_LIFT_RATE, 1.0))
		label.position.y = MEAL_START_Y + _meal_lift_shown[i] + _rise(_meal_ages[i])
		label.modulate.a = 1.0 - k * k
		label.outline_modulate.a = OUTLINE_COLOR.a * label.modulate.a
		if k >= 1.0:
			label.visible = false


func _make_label(color: Color) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.outline_size = OUTLINE_SIZE
	label.modulate = color
	label.outline_modulate = OUTLINE_COLOR
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visible = false
	add_child(label)
	return label
