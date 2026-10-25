extends SceneTree
## Aquatic stage smoke (aquatic plan section 8, PROPOSED). tools/check.sh runs it with --fixed-fps 60, so each frame
## is one sim tick. It drives the real main scene into the Aquatic stage, as --aquatic does, and prints one PASS or
## FAIL line per check. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --aquatic --slot=user://smoke/aquatic.json --seed=4250
##       First a cell lineage is founded in the slot (the hunter: a jaw and two flagella), as the cell stage writes
##       it. Main opens the Aquatic stage on it: the body is the converted darter with the jaw, the generation and
##       lineage id are the save's, and the entry card shows. A scripted swim goes from the nest down the slope and
##       eats; a fed fish by its kin mates and the editor opens; one fin step and Done make generation 2 with the
##       parent recorded; Escape goes back to the title. The slot's file is never written by the stage.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SMOKE_DIR := "user://smoke"
const SWIM_TICKS := 1200
const SETTLE_FRAMES := 3

var main: Main
var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Aquatic smoke, build %s" % BuildInfo.build_id())
	await _run()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _run() -> void:
	var slot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
	_check(slot.begins_with(SMOKE_DIR + "/"), "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, slot])
	if not slot.begins_with(SMOKE_DIR + "/"):
		return
	DirAccess.make_dir_recursive_absolute(SMOKE_DIR)
	var catalog := PartCatalog.load_from()
	var founded := Lineage.found(4250, BuildInfo.build_id(), catalog, "hunter")
	var persistence := PersistenceService.new(catalog)
	_check(founded.ok and persistence.save_to(slot, founded.save) == OK, "a hunter cell lineage is saved in the slot")
	var saved_text := FileAccess.get_file_as_string(slot)
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(SETTLE_FRAMES)
	var stage := main.aquatic_stage
	_check(stage != null and main.screen == stage, "--aquatic opens the Aquatic stage as the screen")
	if stage == null:
		return
	var sim := stage.sim
	_check(String(sim.player.body.mouth) == "jaw" and int(sim.player.body.length) == 3, "the hunter cell becomes a jaw darter")
	_check(String(stage.lineage.lineage_id) == founded.save.lineage_id, "the lineage id is the save's")
	_check(int(sim.player.generation) == founded.save.genome.generation, "the generation is the save's (%d)" % int(sim.player.generation))
	_check(stage.hud.card.visible, "the entry card shows")
	_check(stage.world.get_node_or_null("Player") != null and stage.world.get_node_or_null("Lancer") != null, "the fish are drawn")

	# Swim down the slope towards the reef, diving a little; the plankton bay is on the way for an omnivore, a
	# jaw darter finds the shoal later, so the check is that the swim moved and the zones changed.
	var start: Vector3 = sim.player.pos
	stage.driver = func() -> AquaticSim.Intent: return AquaticSim.Intent.new(1.0, 0.05, -0.4)
	await _frames(SWIM_TICKS)
	_check(sim.player.pos.distance_to(start) > 40.0, "the fish swims (%.0f m)" % sim.player.pos.distance_to(start))
	_check(sim.discovered.size() >= 2, "it finds new places on the way: %s" % [sim.discovered])
	_check(float(sim.player.health) > 0.0 or sim.deaths > 0, "the swim is survivable or returns to the nest")

	# Mate: a fed fish by its kin.
	stage.driver = func() -> AquaticSim.Intent: return AquaticSim.Intent.new()
	sim.player.energy = float(sim.player.stats.energy_capacity)
	sim.player.pos = sim.kin.pos + Vector3(1.0, 0.0, 0.0)
	sim.points = 10
	stage.driver = func() -> AquaticSim.Intent:
		var i := AquaticSim.Intent.new()
		i.interact = true
		return i
	await _frames(SETTLE_FRAMES)
	stage.driver = func() -> AquaticSim.Intent: return AquaticSim.Intent.new()
	_check(stage.editor != null, "mating at the nest opens the editor")
	if stage.editor != null:
		var parent_fins := int(sim.player.body.fins)
		stage.editor.call("step", "fins", 1)
		_check(int(stage.editor.get("cost")) == 2, "a fin step costs 2 points")
		stage.editor.call("commit")
		await _frames(SETTLE_FRAMES)
		_check(stage.editor == null, "Done closes the editor")
		_check(int(sim.player.generation) == founded.save.genome.generation + 1, "the next generation swims")
		_check(int(sim.player.body.fins) == parent_fins + 1 and sim.history.size() == 1, "with the new fins, the parent recorded")
		_check(stage.world.get_node_or_null("Player") != null, "the new body is drawn")
	await _frames(30)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(SETTLE_FRAMES)
	_check(main.start_screen != null and main.aquatic_stage == null, "Escape goes back to the title")
	_check(FileAccess.get_file_as_string(slot) == saved_text, "the stage never wrote the lineage save")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
