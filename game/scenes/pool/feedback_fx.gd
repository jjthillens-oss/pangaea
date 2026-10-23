class_name FeedbackFx
extends Node3D
## World-space feedback that follows confirmed sim events (M1 step 2, Bible 20): a "+8 energy · +1"
## label rising from each meal, and a "Regrowing" label over every emptied plankton zone until it
## is full again. M1 step 3 adds a "−12" label rising from every hit the cell lands or takes
## (threat pink when taken, cream when dealt) and a "Dodged!" label over the cell when a strike on
## it ends without a hit. Labels are pooled Label3D nodes; nothing here changes the sim.
##
## Meals often come in quick runs through a plankton cluster. A meal soon after and close to the
## last one adds to its label ("+16 energy · +2") instead of drawing a second one on top of it.
## Other labels are kept a line apart in the order the pool camera shows them, not by height alone:
## seen from above at an angle, a label 1 m nearer the camera shows about tan(pitch) m of height
## lower. An older label that shows below a new one stays below it (the new one starts higher if
## they would touch), and one that shows above it is pushed up a line clear of it (see _stack).
## Every frame, labels that have come closer than a line on screen, as the camera moves, are moved
## apart again (see _keep_apart). Labels only ever move up, so they never cross.

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
const HIT_LABELS := 4
const HIT_RISE_M := 0.8
const HIT_LIFE_S := 0.9
const HIT_START_Y := 0.9
const DODGED_TEXT := "Dodged!"
const DODGED_RISE_M := 0.7
const DODGED_LIFE_S := 0.8
const DODGED_START_Y := 1.1
const ZONE_LABEL_Y := 1.2
const ZONE_REFRESH_S := 0.25
const FONT_SIZE := 64
const PIXEL_SIZE := 0.005
const OUTLINE_SIZE := 14
const MEAL_COLOR := Color(1.0, 0.97, 0.86)
const ZONE_COLOR := Color(0.86, 0.97, 0.8)
const HIT_TAKEN_COLOR := Color(1.0, 0.55, 0.62)    ## a light threat pink (#D9466B lifted to read on the water)
const HIT_DEALT_COLOR := Color(0.957, 0.918, 0.824)   ## cream highlight #F4EAD2
const DODGED_COLOR := Color(0.62, 0.98, 1.0)
const OUTLINE_COLOR := Color(0.03, 0.13, 0.15, 0.9)

var _meal_labels: Array[Label3D] = []
var _meal_ages := PackedFloat32Array()
var _meal_at := PackedVector2Array()        ## plane position of each label's last meal
var _meal_energy := PackedFloat32Array()    ## energy and points each label shows
var _meal_points := PackedInt32Array()
var _meal_lift := PackedFloat32Array()      ## how far each label sits above MEAL_START_Y (stacking)
var _meal_lift_shown := PackedFloat32Array()
var _next_meal := 0
var _hit_labels: Array[Label3D] = []
var _hit_ages := PackedFloat32Array()
var _next_hit := 0
var _dodged: Label3D
var _dodged_age := DODGED_LIFE_S
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
	_hit_labels.clear()
	for i in HIT_LABELS:
		var label := _make_label(HIT_DEALT_COLOR)
		label.name = "Hit%d" % i
		_hit_labels.append(label)
	_hit_ages.resize(HIT_LABELS)
	_hit_ages.fill(HIT_LIFE_S)
	_next_hit = 0
	_dodged = _make_label(DODGED_COLOR)
	_dodged.name = "Dodged"
	_dodged.text = DODGED_TEXT
	_dodged_age = DODGED_LIFE_S
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
## label i's start but within a line of it makes label i start a line above it, and a label above
## it is pushed up until it is a line clear of label i before either rises. The older one always
## rises at least as far as the newer one, so the line stays. Labels stacked on a pushed one move
## with it (_keep_apart).
func _stack(i: int) -> void:
	var eye := _eye()
	_meal_lift[i] = 0.0
	for j in _by_height(eye, i):
		if not _sideways(i, j):
			continue
		var start := _seen(eye, _point(i, false))
		var now := _seen(eye, _point(j, true))
		if now.x < start.x:
			_meal_lift[i] += maxf(0.0, _raise_to(eye, _point(i, false), now.x + _line(now, start)))
		else:
			var base := _seen(eye, _point(j, false))
			_meal_lift[j] += maxf(0.0, _raise_to(eye, _point(j, false), start.x + _line(base, start)))
	_keep_apart(eye)
	_meal_lift_shown[i] = _meal_lift[i]


## Keeps every two labels that overlap sideways at least a line apart on screen as they are now,
## since the camera moves and nearer labels show larger: going up the screen, a label that is too
## close above a lower one moves up.
func _keep_apart(eye: Transform3D) -> void:
	var order := _by_height(eye, -1)
	for n in order.size():
		var j := order[n]
		for k in order.slice(0, n):
			if not _sideways(j, k):
				continue
			var now := _seen(eye, _point(j, true))
			var below := _seen(eye, _point(k, true))
			var want := below.x + _line(below, now)
			if now.x < want:
				_meal_lift[j] += _raise_to(eye, _point(j, true), want)


## The visible labels other than `skip`, lowest on screen first.
func _by_height(eye: Transform3D, skip: int) -> Array[int]:
	var order: Array[int] = []
	for j in _meal_labels.size():
		if j != skip and _meal_labels[j].visible:
			order.append(j)
	order.sort_custom(func(a: int, b: int) -> bool: return _seen(eye, _point(a, true)).x < _seen(eye, _point(b, true)).x)
	return order


## The pool camera in this node's space. Outside the tree (tests) it is the camera's own transform:
## both nodes are children of the pool.
func _eye() -> Transform3D:
	if is_inside_tree() and _camera.is_inside_tree():
		return global_transform.affine_inverse() * _camera.global_transform
	return _camera.transform


## Where label i's anchor is, at its stacked height, with or without what it has risen so far.
func _point(i: int, risen: bool) -> Vector3:
	return PlaneSpace.to_world(_meal_at[i], MEAL_START_Y + _meal_lift[i] + (_rise(_meal_ages[i]) if risen else 0.0))


## Where point p shows through the camera `eye`: x is how high on screen, as the tangent of its
## angle above the view axis, and y is its depth along that axis.
static func _seen(eye: Transform3D, p: Vector3) -> Vector2:
	var d := p - eye.origin
	var depth := -d.dot(eye.basis.z)
	return Vector2(d.dot(eye.basis.y) / depth, depth)


## How far point p must move up (world height) to show at height `up` (as _seen's x).
static func _raise_to(eye: Transform3D, p: Vector3, up: float) -> float:
	var d := p - eye.origin
	return (up * -d.dot(eye.basis.z) - d.dot(eye.basis.y)) / (eye.basis.y.y + up * eye.basis.z.y)


## One line between two labels as _seen sees them, in _seen's units of height: half a line at
## each label's depth.
static func _line(a: Vector2, b: Vector2) -> float:
	return MEAL_LINE_M * 0.5 * (1.0 / a.y + 1.0 / b.y)


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


## A "−12" label rising from the target of a "hit" event the cell is part of: pink when the cell
## took it, cream when it dealt it. Hits between creatures show nothing.
func show_hit(event: Dictionary) -> void:
	var taken: bool = event.get("target") == CreatureField.PLAYER_ID
	if _hit_labels.is_empty() or not (taken or event.get("attacker") == CreatureField.PLAYER_ID):
		return
	var i := _next_hit
	_next_hit = (_next_hit + 1) % _hit_labels.size()
	var label := _hit_labels[i]
	var color := HIT_TAKEN_COLOR if taken else HIT_DEALT_COLOR
	label.text = hit_text(event)
	label.modulate = color
	label.outline_modulate.a = OUTLINE_COLOR.a
	var at: Variant = event.get("position")
	label.position = PlaneSpace.to_world(at if at is Vector2 else Vector2.ZERO, HIT_START_Y)
	label.visible = true
	_hit_ages[i] = 0.0


## "−12": the health a hit took, rounded; a scratch that took any health shows at least 1.
static func hit_text(event: Dictionary) -> String:
	var dealt := float(event.get("dealt", event.get("damage", 0.0)))
	var shown := roundi(dealt)
	if shown == 0 and dealt > 0.0:
		shown = 1
	return "−%d" % shown


## "Dodged!" rising over the cell at `at` for DODGED_LIFE_S.
func show_dodged(at: Vector2) -> void:
	if _dodged == null:
		return
	_dodged_age = 0.0
	_dodged.position = PlaneSpace.to_world(at, DODGED_START_Y)
	_dodged.modulate.a = 1.0
	_dodged.outline_modulate.a = OUTLINE_COLOR.a
	_dodged.visible = true


## The hit labels on screen now (for checks).
func hit_labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for label in _hit_labels:
		if label.visible:
			out.append(label)
	return out


## The "Dodged!" label (for checks); visible while it shows.
func dodged_label() -> Label3D:
	return _dodged


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
		if _meal_labels[i].visible:
			_meal_ages[i] = minf(_meal_ages[i] + delta, MEAL_LIFE_S)
	if _camera != null:
		_keep_apart(_eye())
	for i in _meal_labels.size():
		var label := _meal_labels[i]
		if not label.visible:
			continue
		var k := _meal_ages[i] / MEAL_LIFE_S
		_meal_lift_shown[i] = lerpf(_meal_lift_shown[i], _meal_lift[i], minf(delta * MEAL_LIFT_RATE, 1.0))
		label.position.y = MEAL_START_Y + _meal_lift_shown[i] + _rise(_meal_ages[i])
		label.modulate.a = 1.0 - k * k
		label.outline_modulate.a = OUTLINE_COLOR.a * label.modulate.a
		if k >= 1.0:
			label.visible = false
	for i in _hit_labels.size():
		if _hit_ages[i] >= HIT_LIFE_S:
			continue
		_hit_ages[i] += delta
		_rise_label(_hit_labels[i], _hit_ages[i] / HIT_LIFE_S, HIT_START_Y, HIT_RISE_M)
	if _dodged != null and _dodged_age < DODGED_LIFE_S:
		_dodged_age += delta
		_rise_label(_dodged, _dodged_age / DODGED_LIFE_S, DODGED_START_Y, DODGED_RISE_M)


## Moves a floating label `k` (0..1) of its way up from `start_y` by `rise`, fading it out; hides it
## at the end.
func _rise_label(label: Label3D, k: float, start_y: float, rise: float) -> void:
	k = clampf(k, 0.0, 1.0)
	label.position.y = start_y + rise * ease(k, 0.4)
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
