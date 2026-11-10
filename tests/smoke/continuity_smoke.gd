extends SceneTree
## Continuity smoke (backlog M4-03, the headless forerunner of M4-04's Windows acceptance run; Bible sections 4, 18
## and 22). tools/check.sh runs it with --fixed-fps 60. It drives the real main scene along the whole chain on one
## slot, in one process, and prints one PASS or FAIL line per check. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --slot=user://smoke/continuity.json --seed=4252
##       A cell lineage at the top of the pool, its sea edge risen, is saved in the slot. Continue opens the pool;
##       "Swim out to sea" opens the Aquatic stage on the same lineage. The fish breeds crawl-strong lobe fins, swims
##       into the shore and takes "Crawl onto land": the creature stage opens and the slot is terrestrial, with the
##       same lineage id, genome, discoveries and relationships, and both checkpoints kept. Back at the title,
##       Continue opens the land again; the way back leads to the sea (the same fish, still able to crawl) and from
##       there to the pool (the same cell).

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SMOKE_DIR := "user://smoke"
const SETTLE_FRAMES := 3

var main: Main
var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Continuity smoke, build %s" % BuildInfo.build_id())
	await _run()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


## What must not change along the chain, as the slot's file holds it.
static func _carried(data: Dictionary) -> String:
	return JSON.stringify({"lineage_id": data.get("lineage_id"), "world_seed": data.get("world_seed"),
			"genome": data.get("genome"), "discoveries": data.get("discoveries"),
			"relationships": data.get("relationships")}, "", true, true)


static func _slot_data(slot: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot))
	return data if data is Dictionary else {}


func _run() -> void:
	var slot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
	_check(slot.begins_with(SMOKE_DIR + "/"), "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, slot])
	if not slot.begins_with(SMOKE_DIR + "/"):
		return
	DirAccess.make_dir_recursive_absolute(SMOKE_DIR)
	EraTransition.forget(slot)
	for f in [slot, slot + PersistenceService.BACKUP_SUFFIX, slot + PersistenceService.TEMP_SUFFIX]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var catalog := PartCatalog.load_from()
	var founded := Lineage.found(4252, BuildInfo.build_id(), catalog, "omnivore")
	var persistence := PersistenceService.new(catalog)
	var cell: SaveGame = founded.save
	cell.adaptation_points = 30
	cell.discoveries.append({"type": "place", "id": "giant_husk", "size": 1})
	cell.relationships.append({"species": "grazer", "standing": "friend"})
	_check(founded.ok and ShoreLink.raise(cell, 0.0, -200.0, 4) and persistence.save_to(slot, cell) == OK,
			"a cell lineage with its sea edge risen is saved in the slot")
	var carried := _carried(_slot_data(slot))

	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(SETTLE_FRAMES)
	main.crawl_time_scale = 0.0
	_check(bool(main.continue_run().ok) and main.pool != null, "Continue opens the pool")
	await _frames(SETTLE_FRAMES)

	# The pool to the sea.
	var to_sea := main.cross_to_sea()
	await _frames(SETTLE_FRAMES)
	_check(bool(to_sea.ok), "Swim out to sea crosses: %s" % [to_sea.get("errors")])
	var stage := main.aquatic_stage
	_check(stage != null and main.screen == stage, "the Aquatic stage opens")
	if stage == null:
		return
	var data := _slot_data(slot)
	_check(String(data.get("era")) == "aquatic" and _carried(data) == carried, "the slot is in the sea with the same lineage")
	_check(EraTransition.has_checkpoint(slot, "aquatic"), "the pool is kept as a checkpoint")
	if stage.hud.card.visible:
		stage.hud.card.visible = false

	# The sea to the land.
	var sim := stage.sim
	var crawler: Dictionary = (sim.player.body as Dictionary).duplicate()
	crawler["limbs"] = int(stage.rules.body.crawl_limbs)
	sim.points = 20
	_check(sim.apply_offspring(crawler, 0), "the fish breeds crawl-strong lobe fins")
	var generation := int(sim.player.generation)
	var shore: Array = stage.rules.world.shore.pos
	sim.player.pos = Vector3(float(shore[0]), float(shore[1]), float(shore[2]) - 1.0)
	await _frames(SETTLE_FRAMES)
	_check(stage.shore_offer != null, "the shore offers land")
	if stage.shore_offer == null:
		return
	(stage.shore_offer.find_child("Crawl", true, false) as Button).pressed.emit()
	await _frames(SETTLE_FRAMES * 3)
	_check(main.aquatic_stage == null and main.creature_stage != null and main.screen == main.creature_stage,
			"Crawl onto land opens the creature stage")
	data = _slot_data(slot)
	_check(String(data.get("era")) == "terrestrial" and _carried(data) == carried,
			"the slot is ashore with the same lineage, genome, discoveries and relationships")
	var events: Array = (data.get("lineage_history", []) as Array).map(func(e): return e.get("event"))
	_check(events.find("entered_the_sea") >= 0 and events.back() == "came_ashore", "the history reads pool, sea, land: %s" % [events])
	_check(not (data.get("creature", {}) as Dictionary).is_empty() and not (data.get("aquatic", {}) as Dictionary).is_empty(),
			"with a land creature, and the sea's record kept")
	_check(EraTransition.has_checkpoint(slot, "aquatic") and EraTransition.has_checkpoint(slot, "terrestrial"), "both checkpoints are kept")

	# Exit to the title and Continue: the land again.
	main.show_start()
	await _frames(SETTLE_FRAMES)
	_check(bool(main.continue_run().ok) and main.creature_stage != null and main.screen == main.creature_stage,
			"from the title, Continue opens the land")
	await _frames(SETTLE_FRAMES)

	# The way back: the sea with the same fish, then the pool with the same cell.
	main.show_start()
	await _frames(SETTLE_FRAMES)
	_check(bool(main.back_to_water().ok), "the way back from the land")
	await _frames(SETTLE_FRAMES)
	stage = main.aquatic_stage
	_check(stage != null and main.screen == stage, "leads to the sea")
	if stage != null:
		_check(int(stage.sim.player.generation) == generation and bool(stage.sim.player.stats.can_crawl),
				"with the same fish, still able to crawl")
	data = _slot_data(slot)
	_check(String(data.get("era")) == "aquatic" and _carried(data) == carried, "the slot is in the sea with the same lineage")
	main.show_start()
	await _frames(SETTLE_FRAMES)
	_check(bool(main.back_to_water().ok), "the way back from the sea")
	await _frames(SETTLE_FRAMES)
	_check(main.pool != null and main.aquatic_stage == null, "leads to the pool")
	data = _slot_data(slot)
	_check(String(data.get("era")) == "microscopic" and _carried(data) == carried, "the slot is in the pool with the same lineage")
	main.show_start()
	await _frames(SETTLE_FRAMES)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
