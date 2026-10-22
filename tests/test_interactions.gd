extends TestCase

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _phenotype(parts: Array) -> Phenotype:
	var genome := Genome.create(StableId.generate("lineage"))
	for p in parts:
		genome.add_part(p[0], p[1])
	return Phenotype.derive(genome, catalog)


func _actor(id: String, parts: Array, position := Vector2.ZERO, heading := 0.0) -> InteractionResolver.Actor:
	return InteractionResolver.Actor.new(id, position, heading, _phenotype(parts))


func _plant(position: Vector2) -> Dictionary:
	return {"id": "food_1", "kind": "plant", "position": position, "radius": 0.1, "energy": 12.0, "points": 1}


func test_grazer_eats_plankton_in_front() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var r := InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	check_eq(r.effect.get("consume"), "food_1", "consumes the food")
	check_near(r.effect.get("energy", 0.0), 12.0, 0.0001, "energy")
	check_eq(r.effect.get("points"), 1, "adaptation points")


func test_feed_refusals_name_what_is_missing() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var hunter := _actor("b", [["mouth_jaw", 0.0]])
	var meat := {"id": "meat_1", "kind": "meat", "position": Vector2(0.7, 0.0), "radius": 0.1, "energy": 20.0}
	check_eq(InteractionResolver.feed(grazer, meat, 0.0).reason, "needs a jaw", "grazer and meat")
	check_eq(InteractionResolver.feed(hunter, _plant(Vector2(0.7, 0.0)), 0.0).reason, "needs a filter mouth", "hunter and plants")
	check_eq(InteractionResolver.feed(grazer, _plant(Vector2(2.0, 0.0)), 0.0).reason, "out of reach", "too far")
	check_eq(InteractionResolver.feed(grazer, _plant(Vector2(-0.7, 0.0)), 0.0).reason, "mouth is not facing it", "behind")
	check(InteractionResolver.feed(grazer, _plant(Vector2(-0.7, 0.0)), 0.0).effect.is_empty(), "a refusal has no effect")


func test_facing_follows_heading() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]], Vector2.ZERO, PI)
	check(InteractionResolver.feed(grazer, _plant(Vector2(-0.7, 0.0)), 0.0).allowed, "turned around, food behind the origin is in front")
	var side := _actor("b", [["mouth_filter", PI / 2.0]])
	check(InteractionResolver.feed(side, _plant(Vector2(0.0, 0.7)), 0.0).allowed, "a side mouth eats from the side")
	check(not InteractionResolver.feed(side, _plant(Vector2(0.7, 0.0)), 0.0).allowed, "but not from the front")


func test_feed_cooldown_and_refusals_do_not_start_it() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	check(not InteractionResolver.feed(grazer, _plant(Vector2(3.0, 0.0)), 1.0).allowed, "refused first")
	check(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 1.0).allowed, "a refusal starts no cooldown")
	check_eq(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 1.1).reason, "still swallowing", "cooldown")
	check(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 1.0 + InteractionResolver.FEED_COOLDOWN).allowed, "ready again")


func test_bite_damages_through_defense() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var r := InteractionResolver.bite(hunter, prey, 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	check_near(r.effect.damage, 8.0, 0.0001, "full bite")
	prey.phenotype.defense = 0.25
	var r2 := InteractionResolver.bite(hunter, prey, 5.0)
	check_near(r2.effect.damage, 6.0, 0.0001, "defense blocks a quarter")


func test_bite_refusals() -> void:
	var grazer := _actor("g", [["mouth_filter", 0.0]])
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	check_eq(InteractionResolver.bite(grazer, prey, 0.0).reason, "needs a jaw", "no jaw")
	prey.position = Vector2(-1.0, 0.0)
	check_eq(InteractionResolver.bite(hunter, prey, 0.0).reason, "jaw is not facing it", "behind")
	prey.position = Vector2(3.0, 0.0)
	check_eq(InteractionResolver.bite(hunter, prey, 0.0).reason, "out of reach", "far")
	prey.position = Vector2(1.0, 0.0)
	prey.phenotype.radius = 0.9
	check_eq(InteractionResolver.bite(hunter, prey, 0.0).reason, "too big to bite", "large prey")


func test_bite_cooldown_is_per_target() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var a := _actor("a", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var b := _actor("b", [["mouth_filter", 0.0]], Vector2(1.0, 0.1))
	check(InteractionResolver.bite(hunter, a, 0.0).allowed, "first bite")
	check_eq(InteractionResolver.bite(hunter, a, 0.1).reason, "jaw is recovering", "same target")
	check(InteractionResolver.bite(hunter, b, 0.1).allowed, "another target")


func test_ram_needs_a_spike_pointing_at_the_target() -> void:
	var plain := _actor("x", [["mouth_filter", 0.0]])
	var rear := _actor("r", [["mouth_filter", 0.0], ["spike", PI]])
	var target := _actor("t", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	check_eq(InteractionResolver.ram(plain, target, 2.0, 0.0).reason, "needs a spike", "no spike")
	check_eq(InteractionResolver.ram(rear, target, 2.0, 0.0).reason, "no spike points at it", "rear spike")


func test_ram_damage_scales_with_spikes_and_closing_speed() -> void:
	var one := _actor("a", [["mouth_filter", 0.0], ["spike", 0.0]])
	var target := _actor("t", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var r := InteractionResolver.ram(one, target, one.phenotype.speed, 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	check_near(r.effect.damage, 6.0, 0.0001, "one spike at full speed")
	var slow := InteractionResolver.ram(one, target, 0.0, 1.0)
	check_near(slow.effect.damage, 6.0 * 0.25, 0.0001, "a gentle bump does a quarter")
	var two := _actor("b", [["mouth_filter", 0.0], ["spike", 0.1], ["spike", -0.1]])
	var r2 := InteractionResolver.ram(two, target, two.phenotype.speed, 0.0)
	check_eq(r2.effect.spikes, 2, "both spikes hit")
	check_near(r2.effect.damage, 6.0 + 3.6, 0.0001, "second spike adds with diminishing returns")
	check_eq(InteractionResolver.ram(two, target, 3.0, 0.2).reason, "spikes are recovering", "cooldown")
