extends TestCase
## S4.6, the Bible's acceptance for the mating loop (docs/s4/s4-plan.md; Bible sections 5, 18 and 24) on
## the shipped endless sea: two generations born through a kin and the editor, a refused edit that
## changes nothing, a save and continue that bring the evolved body back, and deaths that keep it.

const SaveFolder := preload("res://tests/save_folder.gd")
const SEED := 4401

var slot := ""


func before_each() -> void:
	SaveFolder.clear()
	slot = SaveFolder.path("s4_slot.json")


func after_each() -> void:
	SaveFolder.clear()


func _session() -> GameSession:
	return GameSession.new(slot, PoolLayout.DEFAULT_PATH, SpeciesCatalog.DEFAULT_PATH, WorldConfig.DEFAULT_PATH)


static func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## Steps with `move` until an event of `type` or `max_ticks`. Returns that event, or {}.
func _until(sim: PoolSim, type: String, max_ticks: int, toward_kin := false) -> Dictionary:
	for i in max_ticks:
		var intent := SimIntent.new()
		if toward_kin and sim.kin.present:
			intent.move = (sim.kin.motion.position - sim.motion.position).normalized() * 0.6
		sim.step(intent)
		var found := _of(sim.drain_events(), type)
		if not found.is_empty():
			return found[0]
	return {}


## Readies the cell, waits for its kin, swims into it and builds the next generation with `edit`.
## Returns Lineage.reproduce's result ({} when no mate was reported).
func _mate(session: GameSession, edit: Callable) -> Dictionary:
	var sim := session.sim
	check(sim.debug_ready_to_mate(), "ready")
	if _until(sim, "kin_arrived", CreatureBrain.ticks(Kin.CALL_S) + 2).is_empty():
		return {}
	if _until(sim, "mate", CreatureBrain.ticks(20.0), true).is_empty():
		return {}
	var editor := EditorSession.new(sim.save.genome, session.catalog, sim.save.adaptation_points)
	edit.call(editor)
	var result := Lineage.reproduce(sim.save, editor, sim.state)
	if result.ok:
		sim.apply_offspring()
	sim.kin.finish(sim)
	return result


func test_two_generations_a_refusal_a_continue_and_deaths_keep_the_body() -> void:
	var session := _session()
	var started := session.start_new("grazer", SEED)
	check(started.ok and started.saved, "started: %s" % [started.errors])
	if not started.ok:
		return
	var sim := session.sim
	check(sim.kin != null, "the shipped sea grows, so kin come")
	sim.debug_set_hidden(true)   # no hunter breaks the calm while the test swims to its kin
	var catalog := session.catalog
	var founder := sim.save.genome.genome_id
	var speed := sim.phenotype.speed

	# Generation 2: a second tail at the side.
	var first := _mate(session, func(e: EditorSession) -> void:
		check(e.add_part("flagellum", 2.4).ok, "a second tail"))
	check(not first.is_empty() and first.ok, "generation 2 born: %s" % [first])
	if first.is_empty() or not first.ok:
		return
	check_eq(sim.save.genome.generation, 2, "generation 2")
	check(sim.phenotype.speed > speed, "and faster (%.2f > %.2f)" % [sim.phenotype.speed, speed])
	check(session.save_now().ok, "saved")

	# A refused edit changes nothing: a part the points cannot pay for.
	var genome_id := sim.save.genome.genome_id
	var points := sim.save.adaptation_points
	var refused := EditorSession.new(sim.save.genome, catalog, 0)
	refused.add_part("spike", 0.4)
	check(not Lineage.reproduce(sim.save, refused, sim.state).ok, "an edit it cannot pay for is refused")
	check(sim.save.genome.genome_id == genome_id and sim.save.adaptation_points == points, "and changes nothing")

	# Generation 3: the new tail upgraded to level 2.
	var tail := str(sim.save.genome.parts[-1].id)
	var second := _mate(session, func(e: EditorSession) -> void:
		check(e.upgrade_part(tail).ok, "the tail upgraded"))
	check(not second.is_empty() and second.ok, "generation 3 born: %s" % [second])
	if second.is_empty() or not second.ok:
		return
	check_eq(sim.save.genome.generation, 3, "generation 3")
	check(session.save_now().ok, "saved")
	# Through JSON a part's whole numbers come back as floats, so compare with the genome as loading reads it.
	var saved_genome := JSON.stringify(Genome.from_dict(JSON.parse_string(JSON.stringify(sim.save.genome.to_dict()))).to_dict())
	var saved_points := sim.save.adaptation_points

	# Continue: the evolved body, its points and its history come back.
	var again := _session()
	var r := again.continue_run()
	check(r.ok, "continued: %s" % [r.errors])
	if not r.ok:
		return
	var loaded := again.sim.save
	check_eq(JSON.stringify(loaded.genome.to_dict()), saved_genome, "the same genome")
	check_eq(Genome.level_of(loaded.genome.parts[-1]), 2, "with its level 2 tail")
	check_eq(loaded.adaptation_points, saved_points, "and points")
	var born := loaded.lineage_history.filter(func(h: Dictionary) -> bool: return h.event == "born")
	check_eq(born.size(), 2, "two births in the history")
	check_eq(str(born[0].parent_genome_id), founder, "the first from the founder")
	check(again.sim.phenotype.speed > speed, "the loaded body swims as the evolved one")

	# Deaths keep the body and cost a quarter of the unspent points, each time (main resolves a death
	# when the pool reports it, then respawns).
	again.save_on_death = false
	for i in 2:
		var before_points := again.sim.save.adaptation_points
		var body := again.sim.save.genome.genome_id
		again.sim.debug_hurt_player(again.sim.state.max_health + 1.0)
		check(again.sim.dead, "death %d" % (i + 1))
		check_eq(again.respawn_after_death(), before_points / 4, "a quarter of the points taken")
		check(not _until(again.sim, "respawned", 600).is_empty(), "back")
		check_eq(again.sim.save.genome.genome_id, body, "death %d keeps the body" % (i + 1))
		check_eq(again.sim.save.adaptation_points, before_points - before_points / 4,
			"and costs a quarter of %d points" % before_points)
