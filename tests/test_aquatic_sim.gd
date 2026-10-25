extends TestCase

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
## The Aquatic stage's rules and world (aquatic plan sections 4, 5, 8 and 9): two bodies swim the same route
## differently, every depth hazard warns before it harms, species stay in their niches, mating opens the editor and
## a commit makes the next generation, the cell lineage arrives in the body, and the sim is deterministic.

var rules: Dictionary


func before_each() -> void:
	rules = AquaticLineage.rules()


func _sim(body: Dictionary, seed_value := 7) -> AquaticSim:
	return AquaticSim.new(rules, seed_value, body)


## Swims a fixed course: straight down the route for `straight` seconds, then a hard right turn for `turn` seconds.
## Returns {"straight_m", "turn_radius_m", "depth"}.
func _course(body: Dictionary) -> Dictionary:
	var sim := _sim(body)
	sim.player.pos = Vector3(0.0, -6.0, 20.0)
	var start: Vector3 = sim.player.pos
	for i in 5 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(1.0, 0.0, 0.0))
	var straight := Vector2(sim.player.pos.x - start.x, sim.player.pos.z - start.z).length()
	var h0 := float(sim.player.heading)
	for i in AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(1.0, 1.0, 0.0))
	var turned := absf(wrapf(float(sim.player.heading) - h0, -PI, PI))
	return {"straight_m": straight, "turn_rate": turned, "speed": float(sim.player.speed)}


func test_body_rules_are_legal_for_both_variants() -> void:
	for body in [AquaticBody.DARTER, AquaticBody.HOVERER]:
		check(AquaticBody.validate(body, rules.body).is_empty(), "variant is legal: %s" % [AquaticBody.validate(body, rules.body)])
	var bad := AquaticBody.DARTER.duplicate()
	bad.fins = 9
	check_has_error(AquaticBody.validate(bad, rules.body), "Fins")
	bad = AquaticBody.DARTER.duplicate()
	bad.erase("tail")
	check_has_error(AquaticBody.validate(bad, rules.body), "no tail")


func test_two_bodies_swim_the_same_course_differently() -> void:
	var darter := _course(AquaticBody.DARTER)
	var hoverer := _course(AquaticBody.HOVERER)
	check(darter.straight_m > hoverer.straight_m * 1.3, "the darter goes further in a straight line (%.1f vs %.1f m)" % [darter.straight_m, hoverer.straight_m])
	check(hoverer.turn_rate > darter.turn_rate * 1.3, "the hoverer turns tighter at speed (%.2f vs %.2f rad in a second)" % [hoverer.turn_rate, darter.turn_rate])
	var ds := AquaticBody.stats(AquaticBody.DARTER, rules.body)
	var hs := AquaticBody.stats(AquaticBody.HOVERER, rules.body)
	check(hs.rated_depth > float(rules.world.zones[3].depth), "the hoverer can stand the deep (%.0f m)" % hs.rated_depth)
	check(ds.rated_depth < float(rules.world.zones[3].depth), "the darter cannot (%.0f m)" % ds.rated_depth)
	check(ds.top_speed > float(rules.hazards.lancer.pursue_speed), "the darter outruns the lancer (%.1f m/s)" % ds.top_speed)
	check(hs.top_speed < float(rules.hazards.lancer.pursue_speed), "the hoverer cannot, it must hide (%.1f m/s)" % hs.top_speed)
	check(hs.idle_drift >= 0.0 and ds.idle_drift < 0.0, "the hoverer holds its depth, the darter sinks when idle")


func test_the_hoverer_holds_depth_and_the_darter_sinks() -> void:
	for pair in [[AquaticBody.HOVERER, true], [AquaticBody.DARTER, false]]:
		var sim := _sim(pair[0])
		sim.player.pos = Vector3(0.0, -6.0, 0.0)
		for i in 4 * AquaticSim.TICK_HZ:
			sim.step(AquaticSim.Intent.new())
		var held := absf(float(sim.player.pos.y) + 6.0) < 0.3
		check_eq(held, pair[1], "idle depth after 4 s: %.2f" % sim.player.pos.y)


func test_pressure_warns_before_it_drains() -> void:
	var sim := _sim(AquaticBody.DARTER)
	var rated := float(sim.player.stats.rated_depth)
	sim.player.pos = Vector3(0.0, -(rated + 6.0), -230.0)
	var hp := float(sim.player.health)
	var warned_at := -1
	var first_harm := -1
	for i in 8 * AquaticSim.TICK_HZ:
		sim.player.pos.y = -(rated + 6.0)
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type == "pressure_warning" and warned_at < 0:
				warned_at = sim.tick
		if first_harm < 0 and float(sim.player.health) < hp:
			first_harm = sim.tick
	check(warned_at > 0, "the pressure warning fired")
	check(first_harm - warned_at >= int(round(float(rules.hazards.pressure.warn) * AquaticSim.TICK_HZ)),
			"no harm until the warning ran (%d ticks)" % (first_harm - warned_at))
	# Rising clears it at once.
	sim.player.pos.y = -(rated - 5.0)
	sim.step(AquaticSim.Intent.new())
	check_eq(sim.pressure_ticks, 0, "rising above the rated depth clears the pressure")


func test_the_lancer_investigates_then_pursues_and_gives_up_at_a_shelter() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var home := AquaticSim._v(rules.hazards.lancer.home)
	sim.lancer.pos = home
	sim.player.pos = home + Vector3(0.0, 2.0, 8.0)
	var order: Array = []
	var hp := float(sim.player.health)
	var harm_before_pursuit := false
	for i in 12 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type in ["lancer_investigate", "lancer_pursue", "struck", "lancer_gave_up"]:
				order.append(e.type)
		if float(sim.player.health) < hp and not "lancer_pursue" in order:
			harm_before_pursuit = true
		if order.has("lancer_gave_up"):
			break
	check(order.size() >= 3 and order[0] == "lancer_investigate" and order[1] == "lancer_pursue", "it investigates, then pursues: %s" % [order])
	check(not harm_before_pursuit, "no strike before the pursuit")
	check(order.has("lancer_gave_up"), "it disengages")
	# Hidden in a shelter, it gives up without a strike.
	sim = _sim(AquaticBody.HOVERER)
	var cave: Dictionary = rules.world.shelters[2]
	sim.lancer.pos = AquaticSim._v(cave.pos) + Vector3(0.0, 2.0, -9.0)
	sim.player.pos = AquaticSim._v(cave.pos) + Vector3(0.0, 1.0, 0.0)
	sim.lancer.state = "pursue"
	sim.lancer.until = sim.tick + 300
	sim.step(AquaticSim.Intent.new())
	check_eq(String(sim.lancer.state), "disengage", "a sheltered fish is left alone")


func test_the_drifter_warns_before_its_sweep() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var hp := float(sim.player.health)
	var warned_at := -1
	var hit_at := -1
	for i in 20 * AquaticSim.TICK_HZ:
		# Sit right in its path, slightly ahead of it.
		sim.player.pos = sim.drifter.pos + Vector3(2.0, 0.0, 0.0)
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type == "drifter_warning" and warned_at < 0:
				warned_at = sim.tick
			if e.type == "struck" and e.by == "drifter" and hit_at < 0:
				hit_at = sim.tick
		if hit_at > 0:
			break
	check(warned_at > 0 and hit_at > 0, "the drifter warned and then swept (%d, %d)" % [warned_at, hit_at])
	check(hit_at - warned_at >= int(round(float(rules.hazards.drifter.warn) * AquaticSim.TICK_HZ)), "its warning ran first")
	check(float(sim.player.health) > 0.0 or sim.deaths == 0, "one sweep does not kill a healthy fish")
	check(float(sim.player.health) < hp, "the sweep hurts")


func test_species_stay_in_their_niches() -> void:
	var sim := _sim(AquaticBody.DARTER, 11)
	for i in 90 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(0.6, 0.3 if (i / 600) % 2 == 0 else -0.3, 0.0))
	for a in sim.animals:
		var cfg: Dictionary = rules.species[a.species]
		check(a.pos.distance_to(a.home) < float(cfg.wander) + float(cfg.get("follow_leash", 0.0)) + 12.0,
				"%s stays near its home (%.1f m)" % [a.id, a.pos.distance_to(a.home)])
		check_eq(String(sim.zone_at(a.home).id), String(cfg.zone), "%s's home is in its zone" % a.id)


func test_befriending_the_grazers_takes_spaced_signals() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var g: Dictionary = sim.animals[0]
	var points := sim.points
	for k in 3:
		sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
		var intent := AquaticSim.Intent.new()
		intent.signal_call = true
		sim.step(intent)
		sim.step(intent)   # a second call at once does not count
		for i in AquaticSim.TICK_HZ:
			sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
			sim.step(AquaticSim.Intent.new())
	check_eq(String(sim.relations.grazer.standing), "friend", "three spaced signals befriend the grazers")
	check(sim.points >= points + int(rules.world.points.friend), "a friendship earns points")
	# A bite makes them foes.
	sim.player.pos = g.pos + Vector3(0.0, 0.0, 1.0)
	sim.player.heading = AquaticSim.forward_of(0.0).signed_angle_to(g.pos - sim.player.pos, Vector3.UP)
	var bite := AquaticSim.Intent.new()
	bite.bite = true
	sim.step(bite)
	check_eq(String(sim.relations.grazer.standing), "foe", "a bite is remembered")


func test_mating_opens_the_editor_and_a_commit_makes_the_next_generation() -> void:
	var sim := _sim(AquaticBody.DARTER)
	sim.player.pos = sim.kin.pos + Vector3(1.0, 0.0, 0.0)
	sim.player.energy = 10.0
	var press := AquaticSim.Intent.new()
	press.interact = true
	sim.step(press)
	check(sim.take_events().any(func(e): return e.type == "mate_not_ready"), "too hungry to mate")
	sim.player.energy = float(sim.player.stats.energy_capacity)
	sim.player.pos = sim.kin.pos + Vector3(1.0, 0.0, 0.0)
	sim.step(press)
	check(sim.take_events().any(func(e): return e.type == "mate"), "fed, by the kin: the editor opens")
	var child := AquaticBody.DARTER.duplicate()
	child.fins = 2
	var cost := AquaticBody.edit_cost(AquaticBody.DARTER, child, rules.editor)
	check_eq(cost, int(rules.editor.step_cost.fins), "one fin step costs its step")
	sim.points = cost
	check(sim.apply_offspring(child, cost), "the commit is taken")
	check_eq(int(sim.player.generation), 2, "the next generation")
	check_eq(sim.history.size(), 1, "the parent is recorded")
	check_eq(sim.points, 0, "the points are spent")
	check(not sim.apply_offspring(child, 99), "a commit the points cannot pay for is refused")


func test_the_cell_lineage_arrives_in_the_body() -> void:
	var conv: Dictionary = rules.conversion
	var hunter := AquaticBody.from_genome([{"type": "mouth_jaw"}, {"type": "flagellum"}, {"type": "flagellum"}], 0.12, conv)
	check_eq(String(hunter.body.mouth), "jaw", "a jaw cell hunts")
	check_eq(int(hunter.body.tail_size), 2, "two flagella make a tail of strength 2")
	check_eq(int(hunter.body.length), 3, "a flagellum lineage starts as a darter")
	check_near(float(hunter.body.hue), 0.12, 1e-6, "the cell's colour carries over")
	var grazer := AquaticBody.from_genome([{"type": "mouth_filter"}, {"type": "cilia"}, {"type": "cilia"}, {"type": "eye_spot"}], 0.4, conv)
	check_eq(String(grazer.body.mouth), "filter", "a filter cell grazes")
	check_eq(int(grazer.body.fins), 2, "two cilia make fins of size 2")
	check_eq(int(grazer.body.length), 1, "a cilia lineage starts as a hoverer")
	check(grazer.notes.size() >= 3, "each conversion is explained")
	for made in [hunter, grazer]:
		check(AquaticBody.validate(made.body, rules.body).is_empty(), "the converted body is legal")
	var read := AquaticLineage.read("", rules, 5)
	check(read.ok and read.source == "new" and not read.writable, "no slot: a fresh lineage, never written")
	check(not String(read.lineage_id).is_empty(), "with a lineage id")


func test_fish_bodies_are_legal_creature_descriptions() -> void:
	var body_rules: Dictionary = CreatureData.rules()
	var part_rules: Dictionary = CreatureData.part_rules()
	for tail in ["fluke", "ribbon"]:
		for sense in ["eyes", "barbels", "lure"]:
			for mouth in ["filter", "jaw"]:
				for corner in [AquaticBody.DARTER, AquaticBody.HOVERER]:
					var body: Dictionary = corner.duplicate()
					body.tail = tail
					body.sense = sense
					body.mouth = mouth
					var desc = AquaticBody.to_description(body)
					var problems: PackedStringArray = desc.validate_parts(body_rules, part_rules)
					check(problems.is_empty(), "%s %s %s: %s" % [tail, sense, mouth, problems])


func test_the_world_is_deterministic() -> void:
	var a := _sim(AquaticBody.HOVERER, 42)
	var b := _sim(AquaticBody.HOVERER, 42)
	for i in 20 * AquaticSim.TICK_HZ:
		var intent := AquaticSim.Intent.new(1.0, sin(i * 0.01), -0.3)
		a.step(intent)
		b.step(intent)
	check_eq(a.state_hash(), b.state_hash(), "same seed and intents, same world")
	check(_sim(AquaticBody.HOVERER, 43).state_hash() != _sim(AquaticBody.HOVERER, 42).state_hash(), "another seed, another world")


func test_food_regrows_and_the_diet_decides_what_is_eaten() -> void:
	var sim := _sim(AquaticBody.DARTER)
	var plankton: Dictionary = sim.food[0]
	sim.player.energy = 10.0
	sim.player.pos = plankton.pos
	sim.step(AquaticSim.Intent.new())
	check(not plankton.alive, "an omnivore eats plankton")
	for i in int(round(float(rules.world.food.plankton.regrow) * AquaticSim.TICK_HZ)) + 1:
		sim.player.pos = Vector3(0.0, -5.0, 25.0)
		sim.step(AquaticSim.Intent.new())
	check(plankton.alive, "it regrows")
	var hunter := AquaticBody.DARTER.duplicate()
	hunter.mouth = "jaw"
	sim = _sim(hunter)
	sim.player.pos = sim.food[0].pos
	sim.step(AquaticSim.Intent.new())
	check(sim.food[0].alive, "a jaw does not filter plankton")


## Save v5 (plan decision 2): what the sim keeps comes back as it was, the world is rebuilt from the seed, and the
## lineage is written only to a slot it can read.
func test_the_saved_block_restores_the_fish_and_keeps_the_save_rules() -> void:
	var sim := _sim(AquaticBody.DARTER)
	sim.player.pos = Vector3(4.0, -20.0, -60.0)
	sim.player.heading = 0.75
	sim.player.energy = 30.0
	sim.player.health = 9.0
	sim.meals = 5
	sim.discovered.append("kelp_arch")
	sim.relations.grazer.standing = "friend"
	sim.relations.grazer.rapport = 3
	check(sim.apply_offspring(AquaticBody.HOVERER, 0), "a new generation")
	# A place in the water (the floor rises here), with its zone found, as a swim there would leave it.
	sim.player.pos = sim._clamp_to_water(Vector3(4.0, -12.0, -60.0))
	sim._discover(String(sim.zone_at(sim.player.pos).id))
	var block := sim.to_save()
	var save := SaveGame.new_run(7, "test")
	save.aquatic = block
	check(SaveGame.validate_aquatic(block, func(b): return AquaticBody.validate(b, rules.body)).is_empty(),
		"the block passes the save's checks: %s" % [SaveGame.validate_aquatic(block)])
	var again := SaveGame.from_dict(JSON.parse_string(JSON.stringify(save.to_dict())))
	var back := AquaticSim.new(rules, 7, again.aquatic.body, {"aquatic": again.aquatic, "points": 4})
	check_eq(JSON.stringify(back.to_save(), "", true), JSON.stringify(block, "", true), "the same block after a round trip")
	check_eq(back.points, 4, "points are the save's")
	check_eq(back.snapshot().food, _sim(AquaticBody.DARTER).snapshot().food, "the food comes from the seed")
	var dead := block.duplicate(true)
	dead.health = 0.0
	var fresh := AquaticSim.new(rules, 7, dead.body, {"aquatic": dead})
	check(fresh.player.pos.distance_to(fresh.nest_pos()) < 5.0 and float(fresh.player.health) > 0.0,
		"a fish saved with no health starts again at the nest")


func test_the_lineage_is_written_only_to_a_slot_it_can_read() -> void:
	var dir := "user://test_saves/aquatic_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var slot := dir + "/slot.json"
	for f in [slot, slot + ".bak", slot + ".tmp"]:
		DirAccess.remove_absolute(f)
	var lineage := AquaticLineage.read(slot, rules, 11)
	check(lineage.ok and lineage.writable and not lineage.returning, "an empty slot founds a lineage it can write")
	var sim := AquaticSim.new(rules, 11, lineage.body, lineage)
	sim.points = 9
	check_eq(AquaticLineage.write(slot, lineage, sim), OK, "written")
	var again := AquaticLineage.read(slot, rules, 99)
	check(again.returning and again.lineage_id == lineage.lineage_id, "read back as a line that has swum")
	check_eq(int(again.points), 9, "with its points, no starting floor")
	check_eq(int(again.world_seed), 11, "and the save's seed")
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	DirAccess.remove_absolute(slot + ".bak")
	var broken := AquaticLineage.read(slot, rules, 11)
	check(not broken.writable and not broken.errors.is_empty(), "a slot that will not load is not writable")
	check(AquaticLineage.write(slot, broken, AquaticSim.new(rules, 11, broken.body, broken)) != OK, "and is never written")
	check_eq(FileAccess.get_file_as_string(slot), "not json", "the broken file is left as it is")
	for f in [slot, slot + ".bak", slot + ".tmp"]:
		DirAccess.remove_absolute(f)
