class_name FeedbackFx
extends Node3D
## World-space feedback that follows confirmed sim events (M1 step 2, Bible 20): a "+8 energy · +1"
## label rising from each meal, and a "Regrowing" label over every emptied plankton zone until it
## is full again. Labels are pooled Label3D nodes; nothing here changes the sim.

const MEAL_LABELS := 6
const MEAL_RISE_M := 0.9
const MEAL_LIFE_S := 1.2
const MEAL_START_Y := 0.6
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
var _next_meal := 0
var _zone_labels := {}   ## zone id -> Label3D
var _zone_refresh := 0.0


## zones: PoolLayout.zones. Builds the label pools.
func setup(zones: Array[Dictionary]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_meal_labels.clear()
	_meal_ages.clear()
	_zone_labels.clear()
	for i in MEAL_LABELS:
		var label := _make_label(MEAL_COLOR)
		label.name = "Meal%d" % i
		_meal_labels.append(label)
		_meal_ages.append(MEAL_LIFE_S)
	for z in zones:
		var label := _make_label(ZONE_COLOR)
		label.name = "Regrowing_%s" % z.id
		label.position = PlaneSpace.to_world(z.center, ZONE_LABEL_Y)
		_zone_labels[z.id] = label


## A meal label for an "ate" event: energy absorbed and points earned.
func show_meal(event: Dictionary) -> void:
	if _meal_labels.is_empty():
		return
	var label := _meal_labels[_next_meal]
	_meal_ages[_next_meal] = 0.0
	_next_meal = (_next_meal + 1) % _meal_labels.size()
	label.text = meal_text(event)
	label.position = PlaneSpace.to_world(event.position, MEAL_START_Y)
	label.modulate.a = 1.0
	label.outline_modulate.a = OUTLINE_COLOR.a
	label.visible = true


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
		label.position.y = MEAL_START_Y + MEAL_RISE_M * ease(k, 0.4)
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
