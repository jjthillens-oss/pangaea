extends TestCase

var catalog: PartCatalog
var save: SaveGame


func before_each() -> void:
	catalog = PartCatalog.load_from()
	save = SaveGame.new_run(99, "test+dev")
	save.genome.add_part("mouth_filter", 0.0)
	save.genome.add_part("flagellum", PI)
	save.adaptation_points = 40


func _state(energy: float) -> ActorState:
	var s := ActorState.fresh(Phenotype.derive(save.genome, catalog))
	s.energy = energy
	return s


func test_reproduction_needs_energy_and_life() -> void:
	check_eq(Lineage.can_reproduce(_state(50.0)).reason, "needs 20 more energy", "hungry")
	check(Lineage.can_reproduce(_state(70.0)).ok, "70% of capacity is enough")
	var dead := _state(100.0)
	dead.health = 0.0
	check_eq(Lineage.can_reproduce(dead).reason, "not alive", "dead")


func test_reproduce_records_the_new_generation() -> void:
	var parent_id := save.genome.genome_id
	var lineage_id := save.lineage_id
	var history_before := save.lineage_history.size()
	save.adaptation_points = 30 + catalog.cost_of("eye_spot")
	var session := EditorSession.new(save.genome, catalog, save.adaptation_points)
	session.add_part("eye_spot", 0.7)
	var r := Lineage.reproduce(save, session, _state(80.0))
	check(r.ok, "ok: %s" % [r.errors])
	check_eq(save.genome.generation, 2, "generation 2")
	check_eq(save.genome.parent_genome_id, parent_id, "parent recorded")
	check_eq(save.adaptation_points, 30, "points spent")
	var entry: Dictionary = save.lineage_history[-1]
	check_eq(entry.event, "born", "history event")
	check_eq(entry.genome_id, save.genome.genome_id, "history genome")
	check_eq(entry.parent_genome_id, parent_id, "history parent")
	check_eq(entry.generation, 2, "history generation")
	check_eq(save.lineage_history.size(), history_before + 1, "one entry added, none removed")
	check_eq(save.lineage_history[0].event, "founded", "founding kept")
	check_eq(save.lineage_id, lineage_id, "same lineage")
	check(save.validate(catalog).is_empty(), "save still valid: %s" % [save.validate(catalog)])


func test_failed_reproduction_changes_nothing() -> void:
	var before := JSON.stringify(save.to_dict())
	var session := EditorSession.new(save.genome, catalog, save.adaptation_points)
	session.add_part("spike", 0.0)
	session.add_part("spike", 0.4)
	session.add_part("spike", -0.4)
	var r := Lineage.reproduce(save, session, _state(80.0))
	check(not r.ok, "45 points needed, 40 available")
	check_eq(JSON.stringify(save.to_dict()), before, "save untouched")
	var other := EditorSession.new(Genome.create(save.lineage_id), catalog, 40)
	check_has_error(Lineage.reproduce(save, other, _state(80.0)).errors, "different genome")
	var cheap := EditorSession.new(save.genome, catalog, save.adaptation_points)
	cheap.add_part("eye_spot", 0.7)
	check_has_error(Lineage.reproduce(save, cheap, _state(20.0)).errors, "more energy")
	var dead := _state(100.0)
	dead.health = 0.0
	check_has_error(Lineage.reproduce(save, cheap, dead).errors, "not alive")
	check_eq(JSON.stringify(save.to_dict()), before, "still untouched")


func test_a_session_opened_before_a_death_cannot_undo_the_penalty() -> void:
	var session := EditorSession.new(save.genome, catalog, save.adaptation_points)
	session.add_part("eye_spot", 0.7)
	Lineage.apply_death(save, "eaten")
	var r := Lineage.reproduce(save, session, _state(80.0))
	check_has_error(r.errors, "out of date")
	check_eq(save.adaptation_points, 30, "penalty stands")
	check_eq(save.genome.generation, 1, "no new generation")
	var inflated := EditorSession.new(save.genome, catalog, 500)
	check_has_error(Lineage.reproduce(save, inflated, _state(80.0)).errors, "out of date")


func test_death_costs_a_quarter_of_unspent_points_and_is_recorded() -> void:
	var genome_id := save.genome.genome_id
	var history_before := save.lineage_history.size()
	check_eq(Lineage.apply_death(save, "eaten"), 10, "lost 10 of 40")
	check_eq(save.adaptation_points, 30, "30 left")
	check_eq(save.genome.genome_id, genome_id, "body kept: back to this generation's start")
	var entry: Dictionary = save.lineage_history[-1]
	check_eq(entry.event, "died", "event")
	check_eq(entry.cause, "eaten", "cause")
	check_eq(entry.points_lost, 10, "points lost")
	check_eq(save.lineage_history.size(), history_before + 1, "history kept and extended")
	check_eq(save.lineage_history[0].event, "founded", "founding kept")
	save.adaptation_points = 3
	check_eq(Lineage.apply_death(save, "starved"), 0, "rounds down: small totals are spared")


func test_the_death_preview_names_the_points_apply_death_takes() -> void:
	for points in [0, 1, 3, 4, 7, 40, 41, 1001]:
		save.adaptation_points = points
		var shown := Lineage.death_loss(points)
		check_eq(Lineage.apply_death(save, "starved"), shown, "with %d points" % points)
		check_eq(save.adaptation_points, points - shown, "what is left with %d points" % points)


func test_each_starting_body_founds_a_valid_lineage() -> void:
	check_eq(catalog.starting_bodies.keys(), ["grazer", "hunter", "omnivore"], "the three approved bodies")
	var diets := {"grazer": ["plant"], "hunter": ["meat"], "omnivore": ["plant", "meat"]}
	for body in diets:
		var r := Lineage.found(5, "test+dev", catalog, body)
		check(r.ok, "%s founds: %s" % [body, r.errors])
		if not r.ok:
			continue
		var p := Phenotype.derive(r.save.genome, catalog)
		check_eq(Array(p.diets), diets[body], "%s diet" % body)
		check_eq(r.save.adaptation_points, 0, "%s starts with no points" % body)
	check_has_error(Lineage.found(5, "test+dev", catalog, "dragon").errors, "Unknown starting body")


func test_hunter_is_faster_but_hungrier_than_grazer() -> void:
	var g := Lineage.found(1, "t", catalog, "grazer")
	var h := Lineage.found(1, "t", catalog, "hunter")
	check(g.ok and h.ok, "both found")
	if not (g.ok and h.ok):
		return
	var grazer := Phenotype.derive(g.save.genome, catalog)
	var hunter := Phenotype.derive(h.save.genome, catalog)
	check(hunter.speed > grazer.speed, "hunter is faster")
	check(hunter.upkeep > grazer.upkeep, "and burns more energy")
	check(grazer.sight > hunter.sight, "grazer sees further")


func test_points_are_earned_by_eating_and_surviving_not_by_energy() -> void:
	var grazer := InteractionResolver.Actor.new("a", Vector2.ZERO, 0.0, Phenotype.derive(save.genome, catalog))
	var food := {"id": "f", "kind": "plant", "position": Vector2(0.7, 0.0), "radius": 0.1, "energy": 12.0, "points": 2}
	var fed := InteractionResolver.feed(grazer, food, 0.0)
	check(fed.allowed, "fed")
	check_eq(Lineage.earn(save, fed.effect.get("points", 0)), 2, "eating earns the food's points")
	check_eq(save.adaptation_points, 42, "added to the save")
	check_eq(Lineage.survival_points(0.0, Lineage.SURVIVAL_INTERVAL - 0.1), 0, "not yet")
	check_eq(Lineage.survival_points(Lineage.SURVIVAL_INTERVAL - 0.1, Lineage.SURVIVAL_INTERVAL + 0.1), 1, "crossing an interval earns one")
	check_eq(Lineage.survival_points(0.0, Lineage.SURVIVAL_INTERVAL * 3.5), 3, "three intervals")
	check_eq(Lineage.survival_points(10.0, 5.0), 0, "time going backwards earns nothing")
	check_eq(Lineage.survival_points(0.0, NAN), 0, "NaN earns nothing")
	check_eq(Lineage.earn(save, -5), 0, "negative earns nothing")
	check_eq(save.adaptation_points, 42, "unchanged")


func test_starting_body_of_names_each_body_until_it_is_edited() -> void:
	for body in catalog.starting_bodies:
		var r := Lineage.found(5, "test+dev", catalog, body)
		check(r.ok, "%s founds" % body)
		if not r.ok:
			continue
		var genome: Genome = r.save.genome
		check_eq(Lineage.starting_body_of(genome, catalog), body, "%s recognized" % body)
		genome.parts.reverse()
		check_eq(Lineage.starting_body_of(genome, catalog), body, "%s recognized in any part order" % body)
		var moved := Genome.from_dict(genome.to_dict())
		moved.parts[0]["angle"] = float(moved.parts[0]["angle"]) + 0.1
		check_eq(Lineage.starting_body_of(moved, catalog), "", "%s with a moved part is no longer a starting body" % body)
		var grown := Genome.from_dict(genome.to_dict())
		grown.add_part("eye_spot", -1.0)
		check_eq(Lineage.starting_body_of(grown, catalog), "", "%s with an extra part is no longer a starting body" % body)
		var scaled := Genome.from_dict(genome.to_dict())
		scaled.parts[0]["scale"] = 1.5
		check_eq(Lineage.starting_body_of(scaled, catalog), "", "%s with a resized part is no longer a starting body" % body)
	check_eq(Lineage.starting_body_of(save.genome, catalog), "", "the test body is not a starting body")
