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
	var session := EditorSession.new(save.genome, catalog, save.adaptation_points)
	session.add_part("eye_spot", 0.7)
	var r := Lineage.reproduce(save, session)
	check(r.ok, "ok: %s" % [r.errors])
	check_eq(save.genome.generation, 2, "generation 2")
	check_eq(save.genome.parent_genome_id, parent_id, "parent recorded")
	check_eq(save.adaptation_points, 30, "points spent")
	var entry: Dictionary = save.lineage_history[-1]
	check_eq(entry.event, "born", "history event")
	check_eq(entry.genome_id, save.genome.genome_id, "history genome")
	check_eq(entry.parent_genome_id, parent_id, "history parent")
	check_eq(entry.generation, 2, "history generation")
	check(save.validate(catalog).is_empty(), "save still valid: %s" % [save.validate(catalog)])


func test_failed_reproduction_changes_nothing() -> void:
	var before := JSON.stringify(save.to_dict())
	var session := EditorSession.new(save.genome, catalog, save.adaptation_points)
	session.add_part("spike", 0.0)
	session.add_part("spike", 0.4)
	session.add_part("spike", -0.4)
	var r := Lineage.reproduce(save, session)
	check(not r.ok, "45 points needed, 40 available")
	check_eq(JSON.stringify(save.to_dict()), before, "save untouched")
	var other := EditorSession.new(Genome.create(save.lineage_id), catalog, 40)
	check_has_error(Lineage.reproduce(save, other).errors, "different genome")


func test_death_costs_a_quarter_of_unspent_points_and_is_recorded() -> void:
	var genome_id := save.genome.genome_id
	check_eq(Lineage.apply_death(save, "eaten"), 10, "lost 10 of 40")
	check_eq(save.adaptation_points, 30, "30 left")
	check_eq(save.genome.genome_id, genome_id, "body kept: back to this generation's start")
	var entry: Dictionary = save.lineage_history[-1]
	check_eq(entry.event, "died", "event")
	check_eq(entry.cause, "eaten", "cause")
	check_eq(entry.points_lost, 10, "points lost")
	save.adaptation_points = 3
	check_eq(Lineage.apply_death(save, "starved"), 0, "rounds down: small totals are spared")


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
	var grazer := Phenotype.derive(Lineage.found(1, "t", catalog, "grazer").save.genome, catalog)
	var hunter := Phenotype.derive(Lineage.found(1, "t", catalog, "hunter").save.genome, catalog)
	check(hunter.speed > grazer.speed, "hunter is faster")
	check(hunter.upkeep > grazer.upkeep, "and burns more energy")
	check(grazer.sight > hunter.sight, "grazer sees further")
