extends TestCase
## The creature world HUD's dock and goal card (game/ui/creature_world_hud.gd, the hud job's glass look) against a
## stub world that only answers sim.player() and sim.points: the display-only ability chips are named by their bound
## keys and follow a rebind, Evolve lights only at the nest, Bite dims while it recharges and is left out without a
## mouth, nothing in the HUD takes the mouse or focus, the goal line follows the nest, and the controls line times
## out and comes back when the bindings change.

const HUD_SCENE := "res://game/ui/creature_world_hud.tscn"
const THEME := "res://game/ui/theme/pangaea_theme.tres"
const DT := 1.0 / 60.0


## A world with just the sim the HUD reads.
class StubSim:
	extends RefCounted
	var points := 150
	var p := {"health": 20.0, "max_health": 30.0, "has_mouth": true, "at_nest": false, "cooldown": 0}

	func player() -> Dictionary:
		return p


class StubWorld:
	extends Node3D
	var sim := StubSim.new()


var _nodes: Array[Node] = []
var _saved_bite: Array[InputEvent] = []


func before_each() -> void:
	_saved_bite = InputMap.action_get_events(&"creature_bite")


func after_each() -> void:
	InputMap.action_erase_events(&"creature_bite")
	for event in _saved_bite:
		InputMap.action_add_event(&"creature_bite", event)
	InputPrompts.generation += 1
	for node in _nodes:
		if is_instance_valid(node):
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()


## The HUD bound to a stub world: [hud, world].
func make(has_mouth := true) -> Array:
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	var world := StubWorld.new()
	world.sim.p["has_mouth"] = has_mouth
	_nodes.append_array([hud, world])
	hud.bind(world)
	return [hud, world]


func _chips(hud: Control) -> Array:
	return (hud.get_node("%Abilities") as Node).get_children().filter(func(c: Node): return not c.is_queued_for_deletion())


func test_the_chips_name_the_bound_keys_and_follow_a_rebind() -> void:
	var hud: Control = make()[0]
	var chips := _chips(hud)
	check_eq(chips.map(func(c: Button): return String(c.name)), ["Bite", "Sing", "Evolve"], "one chip per ability")
	for pair in [[&"creature_bite", "Bite"], [&"creature_social", "Sing"], [&"creature_evolve", "Evolve"]]:
		var chip: Button = hud._chips[pair[0]]
		check_eq(chip.text, "%s  %s" % [InputPrompts.names_for(pair[0])[0], pair[1]], "the %s chip names its key" % pair[1])
		check_eq(chip.theme_type_variation, &"HudChip", "the %s chip uses the HUD chip look" % pair[1])
		check(chip.toggle_mode and chip.focus_mode == Control.FOCUS_NONE, "the %s chip is a display-only toggle" % pair[1])
	var theme: Theme = load(THEME)
	check_eq(theme.get_type_variation_base(&"HudChip"), &"DockButton", "HudChip is a DockButton")
	var dimmed := theme.get_stylebox(&"disabled", &"HudChip") as StyleBoxFlat
	check(dimmed != null and dimmed.border_width_top >= 1 and dimmed.border_color.a >= 0.5,
		"a recharging chip keeps a visible rim (%s)" % dimmed)
	# Rebind the bite to G: the chip and the controls line follow on the next frame, with no stale chip left.
	InputMap.action_erase_events(&"creature_bite")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	InputMap.action_add_event(&"creature_bite", key)
	InputPrompts.generation += 1
	hud._process(DT)
	var bite: Button = hud._chips[&"creature_bite"]
	check_eq(bite.text, "G  Bite", "the rebound chip")
	check("G  Bite" in hud._hint_text.text, "the rebound controls line (%s)" % hud._hint_text.text)
	check_eq(_chips(hud).size(), 3, "no stale chips after the rebuild")


func test_evolve_lights_only_at_the_nest_and_bite_dims_while_it_recharges() -> void:
	var made := make()
	var hud: Control = made[0]
	var sim: StubSim = (made[1] as StubWorld).sim
	var evolve: Button = hud._chips[&"creature_evolve"]
	var bite: Button = hud._chips[&"creature_bite"]
	var sing: Button = hud._chips[&"creature_social"]
	check(not evolve.button_pressed, "away from the nest Evolve is unlit")
	check_eq(hud._goal_text.text, "Goal: evolve at the nest", "the goal away from the nest")
	check(not bite.disabled and not sing.disabled, "Bite and Sing ready")
	sim.p["at_nest"] = true
	sim.p["cooldown"] = 20
	hud.refresh()
	check(evolve.button_pressed, "at the nest Evolve lights")
	check_eq(hud._goal_text.text, "At the nest: %s to evolve" % InputPrompts.names_for(&"creature_evolve")[0], "the goal at the nest")
	check(bite.disabled, "Bite dims while it recharges")
	check(not sing.disabled, "Sing never dims (the sim does not give its cooldown)")
	sim.p["cooldown"] = 0
	sim.p["at_nest"] = false
	hud.refresh()
	check(not bite.disabled and not evolve.button_pressed, "Bite ready again and Evolve unlit off the nest")
	hud._process(DT)
	check_eq(hud._health_text.text, "Health 20 / 30", "the dock's health")
	check_near(hud._health_bar.value / hud._health_bar.max_value, 20.0 / 30.0, 1e-6, "the dock's health bar")


func test_without_a_mouth_there_is_no_bite_chip() -> void:
	var hud: Control = make(false)[0]
	check(not hud._chips.has(&"creature_bite"), "no Bite chip")
	check_eq(_chips(hud).size(), 2, "Sing and Evolve only")
	check(not "Bite" in hud._hint_text.text, "the controls line has no bite (%s)" % hud._hint_text.text)


func test_nothing_in_the_hud_takes_the_mouse_or_focus() -> void:
	var hud: Control = make()[0]
	check_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the HUD ignores the mouse")
	for control: Control in hud.find_children("*", "Control", true, false):
		check_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % hud.get_path_to(control))
		check(control.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % hud.get_path_to(control))


func test_the_controls_line_times_out_and_comes_back_when_the_bindings_change() -> void:
	var hud: Control = make()[0]
	var panel: Control = hud.get_node("%HintPanel")
	check(panel.visible, "the controls line shows when the world opens")
	var t := 0.0
	var keys_s: float = hud.get_script().KEYS_HINT_S
	while t < keys_s - 1.0:
		hud._process(0.1)
		t += 0.1
	check(panel.visible, "still up %.0f s in" % t)
	while t < keys_s + 0.2:
		hud._process(0.1)
		t += 0.1
	check(not panel.visible, "gone after %.0f s" % keys_s)
	check("Bite" in hud._hint_text.text and "Evolve" in hud._hint_text.text, "its words stay (%s)" % hud._hint_text.text)
	check(hud.get_node("%Dock").visible, "the dock stays")
	InputPrompts.generation += 1
	hud._process(DT)
	check(panel.visible and is_equal_approx(panel.modulate.a, 1.0), "back when the bindings or the device change")
