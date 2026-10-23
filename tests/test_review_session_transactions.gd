extends TestCase
## Cross-service checks using only per-process save files. Continue follows the approved D6/D16
## contract: lineage and checkpoint persist; volatile world, condition and creatures restart.

const SaveFolder := preload("res://tests/save_folder.gd")

var slot := ""
var original_slots_folder := ""


func before_each() -> void:
	SaveFolder.clear()
	slot = SaveFolder.path("lineage.json")
	original_slots_folder = SaveSlots.folder


func after_each() -> void:
	SaveSlots.folder = original_slots_folder
	SaveFolder.clear()


func test_save_death_respawn_continue_keeps_lineage_and_checkpoint() -> void:
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 782).ok, "new lineage starts")
	var lineage: String = session.sim.save.lineage_id
	var checkpoint: Vector2 = session.sim.checkpoint().position
	Lineage.earn(session.sim.save, 20)
	check(session.save_now().ok, "earned points saved before death")
	check(session.sim.debug_hurt_player(10000.0), "forced fatal injury")
	check(session.sim.dead, "death reached the session")
	var resolved := session.resolve_death()
	check(resolved.saved.ok, "death transaction saved")
	check_eq(session.respawn_after_death(), int(resolved.lost), "respawn applies the recorded loss")
	check(session.save_now().ok, "post-respawn checkpoint saved")
	var continued := GameSession.new(slot)
	check(continued.continue_run().ok, "lineage continues")
	check_eq(continued.sim.save.lineage_id, lineage, "lineage identity kept")
	check_eq(continued.sim.save.adaptation_points, 20 - int(resolved.lost), "post-death points kept")
	check_eq(continued.sim.save.lineage_history[-1].event, "died", "death in saved history")
	check(continued.sim.motion.position.distance_to(checkpoint) < 0.001, "continued from checkpoint")


func test_continue_rebuilds_the_same_seeded_world_at_saved_checkpoint() -> void:
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 783).ok, "new lineage starts")
	var new_world := session.sim.snapshot()
	var expected_creatures := session.sim.creatures.snapshot()
	var again := GameSession.new(slot)
	check(again.continue_run().ok, "save can be continued")
	var loaded_world := again.sim.snapshot()
	check_eq(loaded_world.zones, new_world.zones, "seeded food zones rebuilt")
	check_eq(loaded_world.plankton, new_world.plankton, "seeded plankton placement rebuilt")
	check_eq(again.sim.creatures.snapshot(), expected_creatures, "species sites rebuilt")
	check_eq(again.sim.save.world_seed, 783, "world seed preserved")


func test_failed_save_below_file_as_folder_preserves_prior_good_slot() -> void:
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 784).ok, "previous good save exists")
	var before := FileAccess.get_file_as_string(slot)
	var blocker := SaveFolder.path("not_a_folder")
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	check(f != null, "blocker file opened")
	if f == null:
		return
	f.store_string("file, not directory")
	f.close()
	var impossible := SaveFolder.path("not_a_folder/new_slot.json")
	var failed := GameSession.new(impossible).start_new("grazer", 785)
	check(failed.ok and not failed.saved, "run exists in memory but disk write failed")
	check(not failed.errors.is_empty(), "failure has a readable message")
	check_eq(FileAccess.get_file_as_string(slot), before, "previous slot is byte-for-byte unchanged")
	check(not FileAccess.file_exists(impossible + ".tmp"), "no temp file left behind")


func test_save_slots_peek_all_is_ordered_and_read_only() -> void:
	SaveSlots.folder = SaveFolder.dir()
	check(GameSession.new(SaveSlots.path(2)).start_new("hunter", 786).ok, "slot 2 saved")
	var before := FileAccess.get_file_as_string(SaveSlots.path(2))
	var cards := SaveSlots.peek_all()
	check_eq(cards.size(), SaveSlots.COUNT, "all three slot cards")
	for i in cards.size():
		check_eq(cards[i].slot, i + 1, "ascending slot number")
		check_eq(cards[i].path, SaveSlots.path(i + 1), "card points at its own slot")
	check(cards[1].get("exists", false), "middle card sees its lineage")
	check_eq(FileAccess.get_file_as_string(SaveSlots.path(2)), before, "peek wrote nothing")
