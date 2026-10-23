class_name UiSounds
extends Node
## Click sounds for every menu, with no code in the menus themselves: every BaseButton that enters
## the tree plays "press" when pressed (or "back" when it closes or cancels something) and "hover"
## when the mouse enters it or the keyboard or a gamepad moves focus to it. Sliders tick as they
## move. A control with the meta "silent_ui" set to true stays quiet, and the meta "ui_sound" set
## to "press" or "back" picks its press sound. The sounds are Kenney's CC0 interface packs
## (assets/records/audio/ui_*.json). They play on the SFX bus, also while the game is paused.

const SOUNDS := {
	"hover": {"file": "res://assets/audio/ui/ui_hover.ogg", "db": -16.0},
	"press": {"file": "res://assets/audio/ui/ui_press.ogg", "db": -9.0},
	"back": {"file": "res://assets/audio/ui/ui_back.ogg", "db": -9.0},
}
## Buttons whose text starts with one of these play "back" (case is ignored).
const BACK_WORDS: PackedStringArray = ["back", "cancel", "resume", "close", "no", "quit", "don't"]
const REPEAT_LIMIT_MS := 45
const HOOKED := &"_ui_sounds_hooked"
const SLIDER_LIMIT_MS := 70

## How many times each sound was played (or would have been, on the dummy driver).
var played := {}

var _players := {}
var _last_ms := {}
var _keyboard_focus := false
var _silent := AudioServer.get_driver_name() == "Dummy"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.name = id
		player.bus = &"SFX"
		player.stream = load(SOUNDS[id].file)
		player.volume_db = SOUNDS[id].db
		player.max_polyphony = 2
		add_child(player)
		_players[id] = player
	get_tree().node_added.connect(_on_node_added)
	_hook_all(get_tree().root)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_keyboard_focus = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_focus = false


## Plays a UI sound by id ("hover", "press" or "back"), at most once per REPEAT_LIMIT_MS.
func play(id: String, limit_ms: int = REPEAT_LIMIT_MS) -> void:
	var player: AudioStreamPlayer = _players.get(id)
	if player == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -limit_ms)) < limit_ms:
		return
	_last_ms[id] = now
	played[id] = int(played.get(id, 0)) + 1
	if not _silent and player.is_inside_tree():
		player.play()


## The press sound a button makes: its "ui_sound" meta, else "back" for words like Cancel.
static func press_sound(button: BaseButton) -> String:
	if button.has_meta("ui_sound"):
		return String(button.get_meta("ui_sound"))
	var text := ""
	if button is Button:
		text = (button as Button).text.strip_edges().to_lower()
	for word in BACK_WORDS:
		if text == word or text.begins_with(word + " "):
			return "back"
	return "press"


func _hook_all(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_all(child)


func _on_node_added(node: Node) -> void:
	if not (node is BaseButton or node is Slider) or bool(node.get_meta("silent_ui", false)):
		return
	if node.has_meta(HOOKED):
		return
	node.set_meta(HOOKED, true)
	if node is BaseButton:
		var button := node as BaseButton
		button.pressed.connect(_on_pressed.bind(button))
		button.mouse_entered.connect(_on_hover.bind(button, false))
		button.focus_entered.connect(_on_hover.bind(button, true))
	elif node is Slider:
		(node as Slider).value_changed.connect(_on_slider)


func _on_pressed(button: BaseButton) -> void:
	play(press_sound(button))


func _on_hover(button: BaseButton, from_focus: bool) -> void:
	if button.disabled or (from_focus and not _keyboard_focus):
		return
	play("hover")


func _on_slider(_value: float) -> void:
	play("hover", SLIDER_LIMIT_MS)
