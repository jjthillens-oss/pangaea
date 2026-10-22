class_name BodyCard
extends Button
## One starting body on the new-lineage picker (M1 step 2): its name, a one-line role, its diet
## and the stats Phenotype.derive gives it, all worded by BodyText. It is a toggle button in the
## picker's group; a "Selected" label marks the chosen card as well as its border.

const WIDTH := 380.0

var body := ""
var phenotype: Phenotype

@onready var _margin: MarginContainer = %Margin
@onready var _name: Label = %Name
@onready var _selected: Label = %Selected
@onready var _role: Label = %Role
@onready var _diet: Label = %Diet
@onready var _stats: GridContainer = %Stats


func _ready() -> void:
	toggle_mode = true
	for node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggled.connect(func(on: bool): _selected.visible = on)
	_selected.visible = button_pressed


func setup(p_body: String, p_phenotype: Phenotype) -> void:
	body = p_body
	phenotype = p_phenotype
	name = "Card_" + body
	_name.text = BodyText.body_name(body)
	_role.text = BodyText.role(body)
	_diet.text = BodyText.diet(phenotype)
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for row in BodyText.stat_rows(phenotype):
		var stat_name := Label.new()
		stat_name.text = row[0]
		stat_name.theme_type_variation = &"SmallLabel"
		stat_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var value := Label.new()
		value.text = row[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stats.add_child(stat_name)
		_stats.add_child(value)
	custom_minimum_size = Vector2(WIDTH, _margin.get_combined_minimum_size().y)


## The stat values as shown, in BodyText.stat_rows order.
func stat_values() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(1, _stats.get_child_count(), 2):
		out.append((_stats.get_child(i) as Label).text)
	return out


func stat_names() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(0, _stats.get_child_count(), 2):
		out.append((_stats.get_child(i) as Label).text)
	return out


func diet_text() -> String:
	return _diet.text


func role_text() -> String:
	return _role.text
