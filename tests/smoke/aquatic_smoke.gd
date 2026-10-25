extends SceneTree
## Aquatic stage smoke (aquatic plan section 8, PROPOSED). tools/check.sh runs it with --fixed-fps 60, so each frame
## is one sim tick. It drives the real main scene into the Aquatic stage, as --aquatic does, and prints one PASS or
## FAIL line per check. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --aquatic --slot=user://smoke/aquatic.json --seed=4250
##       First a cell lineage is founded in the slot (the hunter: a jaw and two flagella), as the cell stage writes
##       it. Main opens the Aquatic stage on it: the body is the converted darter with the jaw, the generation and
##       lineage id are the save's, and the entry card shows. A scripted swim goes from the nest down the slope and
##       eats; a fed fish by its kin mates and the editor opens; one fin step and a swap to the lunate tail (aquatic-r2:
##       its test swim is the sim's own) and Done make generation 2 with the parent recorded; Escape saves and goes
##       back to the title. The slot then holds the aquatic block (save v5)
##       beside the cell's own data, and opening the stage again brings back the same fish, generation, finds,
##       points and place (the reload check), the new tail included. aquatic-r2: the new species, shelters and the
##       fallen giant are drawn, and before mating the jaw hunter swims down and eats a glass minnow in the shallows
##       (the minnows are its first meat). The nest is its own asset showing one clutch of eggs per generation (one,
##       then two after the commit and after the reload), a hurt fish resting there heals and the HUD says so, and the
##       editor stands the fish on the reef-stone plinth.

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
	var drawn := PackedStringArray()
	for id in ["minnow_01", "cleaner_01", "glowfin_01", "fallen_giant"]:
		if stage.world.get_node_or_null(id) == null:
			drawn.append(id)
	_check(drawn.is_empty(), "the minnows, cleaners, glowfins and the fallen giant are drawn (missing: %s)" % [drawn])
	var looks := {"shelter_ledge": "landmark_shed_husk", "shelter_pillars": "rare_shell_cathedral",
			"shelter_vent_chimney": "landmark_b1_sponge_tower", "shelter_reef_west": "landmark_arch"}
	var wrong := PackedStringArray()
	for id in looks:
		var node := stage.world.get_node_or_null(id)
		if node == null or not String(node.scene_file_path).ends_with(looks[id] + ".glb"):
			wrong.append(id)
	_check(wrong.is_empty(), "every shelter is drawn with its own look (wrong: %s)" % [wrong])
	var nest := stage.world.get_node_or_null("Nest")
	_check(nest != null and String(nest.scene_file_path).ends_with("aquatic_nest.glb"), "the nest is drawn with its own asset")
	_check(_clutches(stage) == sim.history.size() + 1, "the nest shows one clutch for the first generation (%d)" % _clutches(stage))

	# Resting at the nest heals a hurt fish, and the HUD says so (aquatic-r2).
	stage.driver = func() -> AquaticSim.Intent: return AquaticSim.Intent.new()
	var hurt := float(sim.player.stats.max_health) * 0.5
	sim.player.health = hurt
	sim.player.speed = 0.0
	await _frames(AquaticSim.TICK_HZ)
	var healed := float(sim.player.health) - hurt
	_check(absf(healed - float(stage.rules.world.nest.rest_heal_per_s)) < 0.2, "a second's rest at the nest heals %.1f" % healed)
	_check(stage.hud.prompt_label.text.contains("Resting at the nest"), "the HUD says the fish is resting at the nest: '%s'" % stage.hud.prompt_label.text.replace("\n", " / "))
	sim.player.health = float(sim.player.stats.max_health)

	# Swim down the slope towards the reef, diving a little; the plankton bay is on the way for an omnivore, a
	# jaw darter finds the shoal later, so the check is that the swim moved and the zones changed.
	var start: Vector3 = sim.player.pos
	stage.driver = func() -> AquaticSim.Intent: return AquaticSim.Intent.new(1.0, 0.05, -0.4)
	await _frames(SWIM_TICKS)
	_check(sim.player.pos.distance_to(start) > 40.0, "the fish swims (%.0f m)" % sim.player.pos.distance_to(start))
	_check(sim.discovered.size() >= 2, "it finds new places on the way: %s" % [sim.discovered])
	_check(float(sim.player.health) > 0.0 or sim.deaths > 0, "the swim is survivable or returns to the nest")

	# The hunter's first meat: back in the shallows by the minnows, it swims one down and eats it (aquatic-r2).
	sim.player.pos = sim.home_of("minnow") + Vector3(0.0, 0.0, 12.0)
	sim.player.heading = 0.0
	sim.player.speed = 0.0
	sim.player.energy = float(sim.player.stats.energy_capacity) * 0.3
	var meals_before := sim.meals
	var logged := stage.event_log.size()
	stage.driver = func() -> AquaticSim.Intent: return _chase(sim, "minnow")
	var caught := false
	for i in 30 * AquaticSim.TICK_HZ:
		await process_frame
		caught = stage.event_log.slice(logged).any(func(e): return e.type == "killed" and e.species == "minnow")
		if caught:
			break
	_check(caught and sim.meals == meals_before + 1, "the jaw hunter catches and eats a glass minnow in the shallows")

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
		var plinth := (stage.editor.get("viewport") as SubViewport).get_node_or_null("Plinth")
		_check(plinth != null and String(plinth.scene_file_path).ends_with("aquatic_plinth.glb"), "the editor stands the fish on the reef-stone plinth")
		var parent_fins := int(sim.player.body.fins)
		stage.editor.call("step", "fins", 1)
		_check(int(stage.editor.get("cost")) == 2, "a fin step costs 2 points")
		stage.editor.call("set_choice", "tail", "lunate")
		_check(int(stage.editor.get("cost")) == 4, "and a swap to the lunate tail 2 more (%d)" % int(stage.editor.get("cost")))
		var shown: Dictionary = stage.editor.get("after_trial")
		var swum := AquaticSim.trial(stage.rules, stage.editor.get("body"))
		_check(not shown.is_empty() and is_equal_approx(float(shown.cruise_10s_m), float(swum.cruise_10s_m))
				and float(shown.cruise_10s_m) > float((stage.editor.get("before_trial") as Dictionary).cruise_10s_m),
				"the editor's test swim is the lunate's own: %.1f m in 10 s, further than the parent" % float(shown.get("cruise_10s_m", 0.0)))
		stage.editor.call("commit")
		await _frames(SETTLE_FRAMES)
		_check(stage.editor == null, "Done closes the editor")
		_check(int(sim.player.generation) == founded.save.genome.generation + 1, "the next generation swims")
		_check(int(sim.player.body.fins) == parent_fins + 1 and sim.history.size() == 1, "with the new fins, the parent recorded")
		_check(String(sim.player.body.tail) == "lunate", "and the lunate tail")
		_check(stage.world.get_node_or_null("Player") != null, "the new body is drawn")
		_check(_clutches(stage) == 2, "the nest shows a second clutch for the new generation (%d)" % _clutches(stage))
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
	_check(_clutches(stage) == sim.history.size() + 1 and _clutches(stage) == 2, "the nest still shows both clutches (%d)" % _clutches(stage))
	await _escape()
	_check(main.aquatic_stage == null, "Escape leaves again")


## Steers at the nearest live animal of `species`, biting when in reach.
func _chase(sim: AquaticSim, species: String) -> AquaticSim.Intent:
	var target: Dictionary = {}
	for a in sim.animals:
		if a.alive and a.species == species and (target.is_empty()
				or a.pos.distance_to(sim.player.pos) < target.pos.distance_to(sim.player.pos)):
			target = a
	if target.is_empty():
		return AquaticSim.Intent.new()
	var to: Vector3 = target.pos - sim.player.pos
	var off := wrapf(atan2(-to.x, -to.z) - float(sim.player.heading), -PI, PI)
	var intent := AquaticSim.Intent.new(1.0 if absf(off) < 1.0 else 0.3, clampf(-off * 3.0, -1.0, 1.0), clampf(to.y * 0.8, -1.0, 1.0))
	intent.bite = to.length() <= float(sim.player.stats.radius) + 1.6
	return intent


func _escape() -> void:
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(SETTLE_FRAMES)


## The clutches of eggs the stage's nest shows.
func _clutches(stage: Node) -> int:
	var nest: Node = stage.world.get_node_or_null("Nest")
	var shown := 0
	for i in 6:
		var clutch := nest.get_node_or_null("Clutch_%d" % (i + 1)) as Node3D if nest != null else null
		if clutch != null and clutch.visible:
			shown += 1
	return shown


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
