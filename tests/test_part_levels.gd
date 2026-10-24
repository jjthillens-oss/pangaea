extends TestCase
## S4.5, part levels (docs/s4/s4-plan.md): a part upgraded in the editor is stronger, a little
## heavier and dearer to run, costs points to raise, and is saved on the genome. Level 1 is the part
## as catalogued, so genomes without levels derive, cost and save exactly as before.

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _body(level := 1) -> Genome:
	var genome := Genome.create(StableId.generate("lineage"))
	genome.add_part("mouth_filter", 0.0)
	genome.add_part("flagellum", PI, 1.0, level)
	return genome


func test_the_catalog_prices_each_level() -> void:
	check_eq(catalog.max_level, 3, "three levels")
	check(catalog.can_level("flagellum") and catalog.can_level("spike"), "parts with a benefit level up")
	check(not catalog.can_level("mouth_filter"), "a filter mouth has no benefit to raise")
	check_eq(catalog.effect_share(1), 1.0, "level 1 is the part as catalogued")
	check_eq(catalog.cost_share(1), 1.0, "and costs as catalogued")
	check_eq(catalog.upgrade_cost("flagellum", 1), catalog.cost_of("flagellum"), "level 2 costs the part again")
	check_eq(catalog.upgrade_cost("flagellum", 2), roundi(catalog.cost_of("flagellum") * 1.5), "level 3 half as much again")
	check_eq(catalog.value_of("flagellum", 3), catalog.cost_of("flagellum") * 7 / 2, "a level 3 tail is worth 3.5 tails")
	var bare := PartCatalog.from_dict({"parts": {"flagellum": {"cost": 10, "effects": {"speed": 1.0}}}})
	check(bare.max_level == 1 and not bare.can_level("flagellum"), "a catalog without levels has level 1 only")


func test_a_level_raises_the_benefit_and_a_little_of_the_cost() -> void:
	var one := Phenotype.derive(_body(1), catalog)
	var two := Phenotype.derive(_body(2), catalog)
	var three := Phenotype.derive(_body(3), catalog)
	var base := catalog.base("speed")
	var tail: float = catalog.parts["flagellum"].effects.speed
	check_near(two.speed * two.mass - base, tail * catalog.effect_share(2), 1e-6, "level 2 swims with 1.4 tails")
	check_near(three.mass - one.mass, catalog.parts["flagellum"].effects.mass * (catalog.cost_share(3) - 1.0), 1e-6,
		"and is heavier")
	check(three.upkeep > two.upkeep and two.upkeep > one.upkeep, "dearer to run each level")
	check(three.speed > two.speed and two.speed > one.speed, "but faster each level")
	var spiky := Genome.create(StableId.generate("lineage"))
	spiky.add_part("mouth_filter", 0.0)
	spiky.add_part("spike", 0.3, 1.0, 3)
	var p := Phenotype.derive(spiky, catalog)
	check_near(float(p.spikes[0].damage), catalog.parts["spike"].effects.ram_damage * catalog.effect_share(3), 1e-6,
		"a spike's own damage rises with its level")


func test_level_one_is_exactly_the_body_without_levels() -> void:
	var plain := _body()
	check(not plain.parts[1].has("level"), "a level 1 part is stored without a level")
	var marked := Genome.from_dict(plain.to_dict())
	marked.parts[1]["level"] = 1
	check_eq(Phenotype.derive(marked, catalog).to_dict(), Phenotype.derive(plain, catalog).to_dict(),
		"an explicit level 1 derives the same numbers")
	check(marked.validate(catalog).is_empty(), "and is valid")
	# The stronger copy ranks first, whatever order the parts were added in.
	var a := Genome.create(StableId.generate("lineage"))
	a.add_part("mouth_filter", 0.0)
	a.add_part("flagellum", 2.8)
	a.add_part("flagellum", -2.8, 1.0, 2)
	var b := Genome.create(StableId.generate("lineage"))
	b.add_part("mouth_filter", 0.0)
	b.add_part("flagellum", -2.8, 1.0, 2)
	b.add_part("flagellum", 2.8)
	check_eq(Phenotype.derive(a, catalog).speed, Phenotype.derive(b, catalog).speed, "order does not matter")


func test_the_genome_keeps_levels_and_refuses_bad_ones() -> void:
	var save := SaveGame.new_run(7, "test+dev")
	save.genome = _body(3)
	var back := SaveGame.from_dict(JSON.parse_string(JSON.stringify(save.to_dict())))
	check_eq(Genome.level_of(back.genome.parts[1]), 3, "a level survives a save")
	check(back.genome.validate(catalog).is_empty(), "and loads valid: %s" % [back.genome.validate(catalog)])
	for bad: Variant in [4, 0, 1.5, "2"]:
		var g := _body()
		g.parts[1]["level"] = bad
		check(not g.validate(catalog).is_empty(), "level %s is refused" % [bad])
	var filter := _body()
	filter.parts[0]["level"] = 2
	check(not filter.validate(catalog).is_empty(), "a part that cannot level cannot be level 2")


func test_the_editor_session_charges_for_upgrades() -> void:
	var genome := _body()
	var tail := str(genome.parts[1].id)
	var session := EditorSession.new(genome, catalog, 500)
	var result := session.upgrade_part(tail)
	check(result.ok and result.cost == catalog.cost_of("flagellum"), "an upgrade: %s" % [result])
	check_eq(session.cost(), catalog.upgrade_cost("flagellum", 1), "costs its price")
	check(session.upgrade_part(tail).ok, "to level 3")
	check_eq(session.upgrade_part(tail).reason, "already at level 3", "and no further")
	check_eq(session.cost(), catalog.value_of("flagellum", 3) - catalog.cost_of("flagellum"), "both upgrades paid")
	check_eq(session.upgrade_part(str(genome.parts[0].id)).reason, "this part does not level up", "not a filter")
	var mirrored := session.mirror_part(str(session.working.parts[1].id))
	check(not mirrored.ok, "a tail on the centre line does not mirror (%s)" % [mirrored])
	session.move_part(tail, 2.8)
	check(session.mirror_part(tail).ok, "moved off the line, it mirrors")
	check_eq(Genome.level_of(session.working.parts[-1]), 3, "the mirror copy keeps the level")
	check_eq(session.cost(), 2 * catalog.value_of("flagellum", 3) - catalog.cost_of("flagellum"), "and costs it")
	session.undo()
	session.undo()
	session.undo()
	check_eq(Genome.level_of(session.working.parts[1]), 2, "undo steps a level back")
	# Selling an upgraded part refunds what it cost.
	var upgraded := _body(2)
	var sell := EditorSession.new(upgraded, catalog, 0)
	sell.remove_part(str(upgraded.parts[1].id))
	check_eq(sell.cost(), -floori(catalog.value_of("flagellum", 2) * catalog.refund_rate), "the part and its upgrade")
	check(EditorSession.new(_body(), catalog, 0).add_part("flagellum", 1.0, 1.0, 4).reason == "no such level",
		"a new part cannot start above the top level")


func test_the_cell_editor_upgrades_the_selected_part() -> void:
	var save := SaveGame.new_run(99, "test+dev")
	save.genome = _body()
	save.adaptation_points = 200
	var editor := CellEditor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	var s := ActorState.fresh(Phenotype.derive(save.genome, catalog))
	s.energy = s.energy_capacity
	editor.open(save, catalog, s)
	var upgrade := editor.find_child("Upgrade", true, false) as Button
	check(upgrade.disabled, "nothing selected, nothing to upgrade")
	editor.selected = str(save.genome.parts[1].id)
	editor._refresh()
	check(not upgrade.disabled and upgrade.text.contains(str(catalog.upgrade_cost("flagellum", 1))), "priced: %s" % upgrade.text)
	var before: float = editor.session.preview().phenotype.speed
	check(editor.upgrade_selected().ok, "upgraded")
	check(editor.session.preview().phenotype.speed > before, "faster")
	var lines := {}
	for line in editor.stat_lines():
		lines[line[0]] = line
	check_eq(lines["Speed"][3], true, "the speed line shows it")
	var mated := editor.commit()
	check(mated.ok, "mated: %s" % [mated.errors])
	check_eq(Genome.level_of(save.genome.parts[1]), 2, "the child has the level 2 tail")
	check_eq(save.adaptation_points, 200 - catalog.upgrade_cost("flagellum", 1), "paid")
	editor.free()
