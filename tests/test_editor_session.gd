extends TestCase

var catalog: PartCatalog
var genome: Genome
var mouth_id: String
var tail_id: String


func before_each() -> void:
	catalog = PartCatalog.load_from()
	genome = Genome.create(StableId.generate("lineage"))
	mouth_id = genome.add_part("mouth_filter", 0.0)
	tail_id = genome.add_part("flagellum", PI)


func _session(points: int = 30) -> EditorSession:
	return EditorSession.new(genome, catalog, points)


func _snapshot(g: Genome) -> String:
	return JSON.stringify(g.to_dict())


func test_edits_change_the_working_copy_only() -> void:
	var before := _snapshot(genome)
	var s := _session()
	check(s.add_part("cilia", 1.0).ok, "added")
	check_eq(s.working.parts.size(), 3, "working copy has it")
	check_eq(_snapshot(genome), before, "original untouched")


func test_undo_and_redo() -> void:
	var s := _session()
	var start := _snapshot(s.working)
	s.add_part("cilia", 1.0)
	var with_cilia := _snapshot(s.working)
	s.move_part(tail_id, 2.8)
	check(s.undo(), "undo move")
	check_eq(_snapshot(s.working), with_cilia, "move undone")
	check(s.undo(), "undo add")
	check_eq(_snapshot(s.working), start, "back to start")
	check(not s.undo(), "nothing more to undo")
	check(s.redo(), "redo add")
	check_eq(_snapshot(s.working), with_cilia, "add redone")
	s.add_part("eye_spot", 0.5)
	check(not s.redo(), "a new edit clears redo")


func test_move_and_scale_are_free() -> void:
	var s := _session()
	check(s.move_part(tail_id, 3.0).ok, "moved")
	check(s.scale_part(tail_id, 1.5).ok, "scaled")
	check_near(float(s.working.parts[1]["angle"]), 3.0, 0.0001, "angle stored")
	check_near(float(s.working.parts[1]["scale"]), 1.5, 0.0001, "scale stored")
	check_eq(s.cost(), 0, "no cost")


func test_mirror_adds_a_copy_on_the_other_side() -> void:
	var s := _session()
	var r := s.add_part("cilia", 1.2, 0.8)
	var m := s.mirror_part(r.part_id)
	check(m.ok, "mirrored: %s" % m.reason)
	var copy: Dictionary = s.working.parts[-1]
	check_eq(copy.type, "cilia", "same type")
	check_near(float(copy.angle), -1.2, 0.0001, "opposite side")
	check_near(float(copy.scale), 0.8, 0.0001, "same size")
	check_eq(s.mirror_part(mouth_id).reason, "part sits on the center line", "front part")
	check_eq(s.mirror_part(tail_id).reason, "part sits on the center line", "rear part")


func test_cost_charges_additions_and_refunds_removals() -> void:
	var s := _session()
	s.add_part("flagellum", 2.6)
	check_eq(s.cost(), 15, "a flagellum costs 15")
	s.remove_part(tail_id)
	check_eq(s.cost(), 0, "removing the old one refunds it")
	s.remove_part(s.working.parts[-1].id)
	check_eq(s.cost(), -15, "a net removal is a refund")


func test_refused_edits_change_nothing() -> void:
	var s := _session()
	var before := _snapshot(s.working)
	check_eq(s.add_part("shell_plate", 1.0).reason, "shell_plate is not available yet", "locked part")
	check_eq(s.add_part("mouth_filter", 0.5).reason, "limit of 1 reached", "per-type limit")
	check_eq(s.add_part("eye_spot", 0.5, 3.0).reason, "size out of range", "too big")
	check_eq(s.scale_part(tail_id, 0.1).reason, "size out of range", "too small")
	check_eq(s.move_part("part_404", 1.0).reason, "no such part", "missing part")
	check_eq(_snapshot(s.working), before, "unchanged")
	check(not s.undo(), "refusals leave nothing to undo")


func test_part_slots_run_out() -> void:
	var s := _session(999)
	for i in 6:
		s.add_part(["cilia", "eye_spot", "spike"][i % 3], -2.0 + i * 0.6)
	check_eq(s.working.parts.size(), 8, "full")
	check_eq(s.add_part("spike", 0.1).reason, "no free part slots", "slot limit")


func test_preview_matches_commit_without_committing() -> void:
	var s := _session()
	s.add_part("flagellum", 2.6)
	var p := s.preview()
	check_eq(p.cost, 15, "cost")
	check(p.affordable, "affordable")
	check(p.errors.is_empty(), "valid")
	check(p.phenotype.speed > p.current.speed, "preview shows the faster body")
	var result := s.commit()
	check(result.ok, "commit: %s" % [result.errors])
	check_near(Phenotype.derive(result.genome, catalog).speed, p.phenotype.speed, 0.0001, "preview equals result")


func test_commit_makes_the_next_generation() -> void:
	var s := _session(30)
	s.add_part("eye_spot", 0.6)
	var result := s.commit()
	check(result.ok, "ok")
	var child: Genome = result.genome
	check(child.genome_id != genome.genome_id and StableId.is_valid(child.genome_id, "genome"), "new id")
	check_eq(child.parent_genome_id, genome.genome_id, "parent")
	check_eq(child.lineage_id, genome.lineage_id, "same lineage")
	check_eq(child.generation, genome.generation + 1, "generation")
	check_eq(result.points_left, 20, "points spent")
	check_eq(genome.parts.size(), 2, "parent untouched")


func test_failed_commit_keeps_the_original_and_points() -> void:
	var before := _snapshot(genome)
	var s := _session(10)
	s.add_part("flagellum", 2.6)
	var broke := s.commit()
	check(not broke.ok, "too expensive")
	check_has_error(broke.errors, "Needs 15 adaptation points, you have 10")
	check_eq(broke.points_left, 10, "points kept")
	check(broke.genome == null, "no offspring")
	var s2 := _session(30)
	s2.remove_part(mouth_id)
	var invalid := s2.commit()
	check(not invalid.ok, "no mouth")
	check_has_error(invalid.errors, "mouth")
	check_eq(_snapshot(genome), before, "original untouched")
