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
##       parent recorded; Escape saves and goes back to the title. The slot then holds the aquatic block (save v5)
##       beside the cell's own data, and opening the stage again brings back the same fish, generation, finds,
##       points and place (the reload check).

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
	var left: Dictionary = sim.to_save()
	var left_points := sim.points
	await _escape()
	_check(main.start_screen != null and main.aquatic_stage == null, "Escape goes back to the title")

	# The save: the cell's data untouched, the aquatic block as the fish left the water.
	var before: Dictionary = JSON.parse_string(saved_text)
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot))
	_check(after is Dictionary and int(after.schema_version) == SaveGame.SCHEMA_VERSION, "the slot is a v%d save" % SaveGame.SCHEMA_VERSION)
	if not after is Dictionary:
		return
	for key in ["lineage_id", "world_seed", "genome", "growth", "checkpoint", "era", "creature"]:
		_check(JSON.stringify(after[key], "", true) == JSON.stringify(before[key], "", true), "the cell's %s is kept" % key)
	var block: Dictionary = after.aquatic
	_check(int(block.get("generation", 0)) == int(left.generation) and int(after.adaptation_points) == left_points,
			"the aquatic block holds generation %d and %d points" % [int(left.generation), left_points])
	var loaded := persistence.load_from(slot)
	_check(loaded.ok, "the written slot loads: %s" % [loaded.get("errors")])

	# The reload check: the stage opens again where it was left.
	stage = main.open_aquatic_stage()
	await _frames(SETTLE_FRAMES)
	sim = stage.sim
	_check(bool(stage.lineage.get("returning", false)), "the stage knows this line has swum before")
	_check(JSON.stringify(sim.player.body, "", true) == JSON.stringify(left.body, "", true), "the same body")
	_check(int(sim.player.generation) == int(left.generation) and sim.history.size() == (left.history as Array).size(),
			"the same generation and history")
	_check(sim.points == left_points and sim.meals == int(left.meals), "the same points and meals")
	_check(Array(sim.discovered) == Array(left.discovered), "the same places found: %s" % [sim.discovered])
	var was := Vector3(float(left.position[0]), float(left.position[1]), float(left.position[2]))
	_check(sim.player.pos.distance_to(was) < 0.01, "back where it left the water (%.2f m off)" % sim.player.pos.distance_to(was))

	# The shore (plan sections 7 and 7a): a fish with crawl-strong lobe fins is offered land; staying is recorded.
	var crawler: Dictionary = sim.player.body.duplicate()
	crawler["limbs"] = int(stage.rules.body.crawl_limbs)
	sim.points = 20
	_check(sim.apply_offspring(crawler, 0), "a generation with crawling lobe fins")
	var shore: Array = stage.rules.world.shore.pos
	sim.player.pos = Vector3(float(shore[0]), float(shore[1]), float(shore[2]) - 1.0)
	await _frames(SETTLE_FRAMES)
	_check(stage.shore_offer != null, "the shore offers land")
	if stage.shore_offer != null:
		(stage.shore_offer.find_child("Stay", true, false) as Button).pressed.emit()
		await _frames(SETTLE_FRAMES)
	_check(stage.shore_offer == null, "Stay in the sea closes the offer")
	var stayed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot))
	_check(stayed is Dictionary and (stayed.lineage_history as Array).any(func(e): return e.get("event") == "stayed_in_the_sea"),
			"the lineage records that it stayed in the sea")
	await _escape()
	_check(main.aquatic_stage == null, "Escape leaves again")


func _escape() -> void:
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(SETTLE_FRAMES)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
