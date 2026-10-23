extends TestCase
## Boundary and transaction contracts omitted from the original feature tests.


func _catalog() -> PartCatalog:
	return PartCatalog.load_from()


func _actor(id: String, parts: Array, at := Vector2.ZERO) -> InteractionResolver.Actor:
	var g := Genome.create(StableId.generate("lineage"))
	for part in parts:
		g.add_part(part[0], part[1])
	return InteractionResolver.Actor.new(id, at, 0.0, Phenotype.derive(g, _catalog()))


func _food(energy: float) -> Dictionary:
	return {"id": "f", "kind": "plant", "position": Vector2(0.7, 0.0), "radius": 0.1, "energy": energy, "points": 2}


func _region(seed_value := 7) -> EcologyRegion:
	var r := EcologyRegion.create(seed_value)
	r.add_zone("a", Vector2(2.0, 3.0), 4.0, 100.0, 0.2)
	return r


func _editor() -> EditorSession:
	var g := Genome.create(StableId.generate("lineage"))
	g.add_part("mouth_filter", 0.0)
	g.add_part("flagellum", PI)
	return EditorSession.new(g, _catalog(), 30)


func test_feed_exactly_half_room_is_allowed() -> void:
	var a := _actor("a", [["mouth_filter", 0.0]])
	check(InteractionResolver.feed(a, _food(12.0), 0.0, 6.0).allowed, "half of food energy is enough room")


func test_feed_below_half_room_preserves_cooldown() -> void:
	var a := _actor("a", [["mouth_filter", 0.0]])
	var refused := InteractionResolver.feed(a, _food(12.0), 0.0, 5.99)
	check_eq(refused.reason, "not hungry", "reason")
	check(a.cooldowns.is_empty(), "refusal does not reserve feed cooldown")
	check(InteractionResolver.feed(a, _food(12.0), 0.0, 6.0).allowed, "a later eligible feed succeeds immediately")


func test_bite_defense_above_cap_still_leaves_damage() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	prey.phenotype.defense = 10.0
	var r := InteractionResolver.bite(hunter, prey, 0.0)
	check(r.allowed, "bite lands")
	check_near(r.effect.damage, hunter.phenotype.bite_damage * 0.05, 0.0001, "defense capped at 95%")


func test_negative_defense_does_not_amplify_bite() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	prey.phenotype.defense = -4.0
	var r := InteractionResolver.bite(hunter, prey, 0.0)
	check_near(r.effect.damage, hunter.phenotype.bite_damage, 0.0001, "defense clamped at zero")


func test_unknown_ecology_zone_takes_nothing_from_known_zone() -> void:
	var r := _region()
	check_eq(r.take("missing", 40.0), 0.0, "unknown zone")
	check_near(r.zone("a").amount, 100.0, 0.0001, "known zone remains full")


func test_ecology_regrowth_step_is_independent_of_zone_insertion_order() -> void:
	var a := _region()
	a.add_zone("b", Vector2(-3.0, 1.0), 3.0, 50.0, 0.5)
	var b := EcologyRegion.create(7)
	b.add_zone("b", Vector2(-3.0, 1.0), 3.0, 50.0, 0.5)
	b.add_zone("a", Vector2(2.0, 3.0), 4.0, 100.0, 0.2)
	a.take("a", 70.0)
	b.take("a", 70.0)
	a.take("b", 20.0)
	b.take("b", 20.0)
	a.tick(0.25)
	b.tick(0.25)
	check_near(a.zone("a").amount, b.zone("a").amount, 0.0001, "a independent of insertion order")
	check_near(a.zone("b").amount, b.zone("b").amount, 0.0001, "b independent of insertion order")


func test_reducing_niche_cap_keeps_existing_population_but_blocks_new_spawn() -> void:
	var r := _region()
	r.set_niche("grazer", 3)
	check(r.try_spawn("grazer") and r.try_spawn("grazer"), "two occupants")
	r.set_niche("grazer", 1)
	check_eq(r.niches["grazer"].count, 2, "existing occupants retained")
	check(not r.try_spawn("grazer"), "lower cap blocks further spawn")


func test_extra_niche_removals_never_make_count_negative() -> void:
	var r := _region()
	r.set_niche("grazer", 1)
	r.on_creature_removed("grazer")
	r.on_creature_removed("grazer")
	check_eq(r.niches["grazer"].count, 0, "count stays at zero")
	check(r.try_spawn("grazer"), "the slot can still be reserved")


func test_editor_appearance_change_is_undoable() -> void:
	var s := _editor()
	var before := s.working.appearance.duplicate(true)
	check(s.set_appearance("color", "blue").ok, "appearance edit")
	check(s.undo(), "undo")
	check_eq(s.working.appearance, before, "old appearance restored")
	check(s.redo(), "redo")
	check_eq(s.working.appearance["color"], "blue", "new appearance restored")


func test_editor_angles_are_wrapped_into_one_turn() -> void:
	var s := _editor()
	var added := s.add_part("cilia", TAU + 0.4)
	check(added.ok, "part added")
	check_near(s.working.parts[-1].angle, 0.4, 0.0001, "angle normalized")


func test_refused_editor_edit_keeps_redo_history() -> void:
	var s := _editor()
	s.add_part("cilia", 0.5)
	check(s.undo(), "undo creates redo")
	check(not s.add_part("unknown_part", 0.3).ok, "invalid edit refused")
	check(s.redo(), "failed edit does not discard redo")
	check_eq(s.working.count_of("cilia"), 1, "redone part present")


func test_editor_preview_does_not_create_a_new_genome() -> void:
	var s := _editor()
	var before := JSON.stringify(s.working.to_dict())
	var a := s.preview()
	var b := s.preview()
	check_eq(JSON.stringify(s.working.to_dict()), before, "working copy unchanged")
	check_eq(a.cost, b.cost, "repeated previews agree")
