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


func _meat(position: Vector2) -> Dictionary:
	return {"id": "meat_1", "kind": "meat", "position": position, "radius": 0.1, "energy": 20.0, "points": 2}


## Asserts the call was refused with `reason`, has no effect, and left the actor's cooldowns alone.
func _check_refused(actor: InteractionResolver.Actor, call: Callable, reason: String) -> void:
	var cooldowns := actor.cooldowns.duplicate()
	var r: Dictionary = call.call()
	check(not r.allowed, "refused: %s" % reason)
	check_eq(r.reason, reason, "reason")
	check(r.effect.is_empty(), "%s: a refusal has no effect" % reason)
	check_eq(actor.cooldowns, cooldowns, "%s: cooldowns untouched" % reason)


func test_grazer_eats_plankton_in_front() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var r := InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	if not r.allowed:
		return
	check_eq(r.effect.get("consume"), "food_1", "consumes the food")
	check_near(r.effect.get("energy", 0.0), 12.0, 0.0001, "energy")
	check_eq(r.effect.get("points"), 1, "adaptation points")


func test_feed_refusals_name_what_is_missing_and_change_nothing() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var hunter := _actor("b", [["mouth_jaw", 0.0]])
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, _meat(Vector2(0.7, 0.0)), 0.0), "needs a jaw")
	_check_refused(hunter, InteractionResolver.feed.bind(hunter, _plant(Vector2(0.7, 0.0)), 0.0), "needs a filter mouth")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, _plant(Vector2(2.0, 0.0)), 0.0), "out of reach")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, _plant(Vector2(-0.7, 0.0)), 0.0), "mouth is not facing it")
	check(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 0.0).allowed, "a valid feed right after the refusals")


func test_only_the_matching_mouth_counts() -> void:
	# Omnivore: filter mouth on the left (+Y), jaw on the right (-Y).
	var omni := _actor("o", [["mouth_filter", PI / 2.0], ["mouth_jaw", -PI / 2.0]])
	_check_refused(omni, InteractionResolver.feed.bind(omni, _meat(Vector2(0.0, 0.7)), 0.0), "mouth is not facing it")
	_check_refused(omni, InteractionResolver.feed.bind(omni, _plant(Vector2(0.0, -0.7)), 0.0), "mouth is not facing it")
	check(InteractionResolver.feed(omni, _meat(Vector2(0.0, -0.7)), 0.0).allowed, "jaw side eats meat")
	check(InteractionResolver.feed(omni, _plant(Vector2(0.0, 0.7)), 1.0).allowed, "filter side eats plants")
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(0.0, 1.0))
	_check_refused(omni, InteractionResolver.bite.bind(omni, prey, 2.0), "jaw is not facing it")


func test_facing_follows_heading() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]], Vector2.ZERO, PI)
	check(InteractionResolver.feed(grazer, _plant(Vector2(-0.7, 0.0)), 0.0).allowed, "turned around, food behind the origin is in front")
	var side := _actor("b", [["mouth_filter", PI / 2.0]])
	check(InteractionResolver.feed(side, _plant(Vector2(0.0, 0.7)), 0.0).allowed, "a side mouth eats from the side")
	check(not InteractionResolver.feed(side, _plant(Vector2(0.7, 0.0)), 0.0).allowed, "but not from the front")


func test_facing_works_across_the_back_seam() -> void:
	# A rear spike at PI must hit targets just either side of straight behind (-PI/PI wrap).
	var rear := _actor("r", [["mouth_filter", 0.0], ["spike", PI]])
	var above := _actor("t1", [["mouth_filter", 0.0]], Vector2(-1.0, 0.05))
	var below := _actor("t2", [["mouth_filter", 0.0]], Vector2(-1.0, -0.05))
	check(InteractionResolver.ram(rear, above, 2.0, 0.0).allowed, "just above the seam")
	check(InteractionResolver.ram(rear, below, 2.0, 0.0).allowed, "just below the seam")


func test_feed_cooldown() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	check(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 1.0).allowed, "first")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, _plant(Vector2(0.7, 0.0)), 1.1), "still swallowing")
	check(InteractionResolver.feed(grazer, _plant(Vector2(0.7, 0.0)), 1.0 + InteractionResolver.FEED_COOLDOWN).allowed, "ready again")


func test_bite_damages_through_defense() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var r := InteractionResolver.bite(hunter, prey, 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	if not r.allowed:
		return
	check_near(r.effect.damage, 8.0, 0.0001, "full bite")
	prey.phenotype.defense = 0.25
	var r2 := InteractionResolver.bite(hunter, prey, 5.0)
	check_near(r2.effect.get("damage", -1.0), 6.0, 0.0001, "defense blocks a quarter")
	var state := ActorState.fresh(prey.phenotype)
	state.take_damage(r2.effect.get("damage", 0.0))
	check_near(state.health, 30.0 - 6.0, 0.0001, "defense applied once on the way to health")


func test_bite_refusals_change_nothing() -> void:
	var grazer := _actor("g", [["mouth_filter", 0.0]])
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var prey := _actor("p", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	_check_refused(grazer, InteractionResolver.bite.bind(grazer, prey, 0.0), "needs a jaw")
	_check_refused(hunter, InteractionResolver.bite.bind(hunter, hunter, 0.0), "cannot bite itself")
	prey.position = Vector2(-1.0, 0.0)
	_check_refused(hunter, InteractionResolver.bite.bind(hunter, prey, 0.0), "jaw is not facing it")
	prey.position = Vector2(3.0, 0.0)
	_check_refused(hunter, InteractionResolver.bite.bind(hunter, prey, 0.0), "out of reach")
	prey.position = Vector2(1.0, 0.0)
	prey.phenotype.radius = 0.9
	_check_refused(hunter, InteractionResolver.bite.bind(hunter, prey, 0.0), "too big to bite")


func test_bite_cooldown_is_per_target() -> void:
	var hunter := _actor("h", [["mouth_jaw", 0.0]])
	var a := _actor("a", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var b := _actor("b", [["mouth_filter", 0.0]], Vector2(1.0, 0.1))
	check(InteractionResolver.bite(hunter, a, 0.0).allowed, "first bite")
	_check_refused(hunter, InteractionResolver.bite.bind(hunter, a, 0.1), "jaw is recovering")
	check(InteractionResolver.bite(hunter, b, 0.1).allowed, "another target")


func test_ram_refusals_change_nothing() -> void:
	var plain := _actor("x", [["mouth_filter", 0.0]])
	var rear := _actor("r", [["mouth_filter", 0.0], ["spike", PI]])
	var front := _actor("f", [["mouth_filter", 0.0], ["spike", 0.0]])
	var target := _actor("t", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	_check_refused(plain, InteractionResolver.ram.bind(plain, target, 2.0, 0.0), "needs a spike")
	_check_refused(rear, InteractionResolver.ram.bind(rear, target, 2.0, 0.0), "no spike points at it")
	_check_refused(front, InteractionResolver.ram.bind(front, front, 2.0, 0.0), "cannot ram itself")
	_check_refused(front, InteractionResolver.ram.bind(front, target, -3.0, 0.0), "not moving toward it")
	_check_refused(front, InteractionResolver.ram.bind(front, target, 0.0, 0.0), "not moving toward it")
	_check_refused(front, InteractionResolver.ram.bind(front, target, NAN, 0.0), "not moving toward it")
	target.position = Vector2(3.0, 0.0)
	_check_refused(front, InteractionResolver.ram.bind(front, target, 2.0, 0.0), "out of reach")


func test_ram_damage_scales_with_facing_spikes_and_closing_speed() -> void:
	var one := _actor("a", [["mouth_filter", 0.0], ["spike", 0.0]])
	var target := _actor("t", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var r := InteractionResolver.ram(one, target, one.phenotype.speed, 0.0)
	check(r.allowed, "allowed: %s" % r.reason)
	check_near(r.effect.get("damage", -1.0), 6.0, 0.0001, "one spike at full speed")
	var slow := InteractionResolver.ram(one, target, 0.1, 1.0)
	check_near(slow.effect.get("damage", -1.0), 6.0 * 0.25, 0.0001, "a gentle bump does a quarter")
	var two := _actor("b", [["mouth_filter", 0.0], ["spike", 0.1], ["spike", -0.1]])
	var r2 := InteractionResolver.ram(two, target, two.phenotype.speed, 0.0)
	check_eq(r2.effect.get("spikes"), 2, "both spikes hit")
	check_near(r2.effect.get("damage", -1.0), 6.0 + 3.6, 0.0001, "second spike adds with diminishing returns")


func test_a_spike_that_misses_does_not_weaken_one_that_hits() -> void:
	var target := _actor("t", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var front := _actor("a", [["mouth_filter", 0.0], ["spike", 0.0]])
	# Rear spike added first, so a ranking by part order would put it ahead of the front one.
	var both := _actor("b", [["mouth_filter", 0.0], ["spike", PI], ["spike", 0.0]])
	var alone := InteractionResolver.ram(front, target, 10.0, 0.0)
	var with_rear := InteractionResolver.ram(both, target, 10.0, 0.0)
	check_eq(with_rear.effect.get("spikes"), 1, "only the front spike hits")
	check_near(alone.effect.get("damage", -1.0), 6.0 * 1.5, 0.0001, "front spike alone at top impact")
	check_near(with_rear.effect.get("damage", -1.0), 6.0 * 1.5, 0.0001, "front spike keeps its full damage")
	var big := _actor("c", [["mouth_filter", 0.0], ["spike", PI], ["spike", 0.0]])
	for spike in big.phenotype.spikes:
		if is_zero_approx(spike.angle):
			spike.damage = 12.0
	check_near(InteractionResolver.ram(big, target, 10.0, 0.0).effect.get("damage", -1.0), 12.0 * 1.5, 0.0001, "a spike's own size counts")


func test_ram_cooldown_is_per_target_and_defense_applies() -> void:
	var rammer := _actor("r", [["mouth_filter", 0.0], ["spike", 0.0]])
	var a := _actor("a", [["mouth_filter", 0.0]], Vector2(1.0, 0.0))
	var b := _actor("b", [["mouth_filter", 0.0]], Vector2(1.0, 0.1))
	b.phenotype.defense = 0.25
	var speed := rammer.phenotype.speed
	check(InteractionResolver.ram(rammer, a, speed, 0.0).allowed, "first ram")
	_check_refused(rammer, InteractionResolver.ram.bind(rammer, a, speed, 0.2), "spikes are recovering")
	var rb := InteractionResolver.ram(rammer, b, speed, 0.2)
	check(rb.allowed, "another target")
	check_near(rb.effect.get("damage", -1.0), 6.0 * 0.75, 0.0001, "defense blocks a quarter")


func test_a_cell_without_room_for_half_the_food_is_not_hungry() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var food := _plant(Vector2(0.7, 0.0))
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, food, 0.0, 0.0), "not hungry")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, food, 0.0, 5.99), "not hungry")
	var r := InteractionResolver.feed(grazer, food, 0.0, 6.0)
	check(r.allowed, "room for exactly half the food's energy is enough: %s" % r.reason)
	check_near(r.effect.get("energy", 0.0), 12.0, 0.0001, "the effect is still the whole food")


func test_feed_refusals_come_in_a_fixed_order() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var far_behind_meat := _meat(Vector2(-3.0, 0.0))
	var far_behind := _plant(Vector2(-3.0, 0.0))
	var near_behind := _plant(Vector2(-0.7, 0.0))
	var in_front := _plant(Vector2(0.7, 0.0))
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, far_behind_meat, 0.0, 0.0), "needs a jaw")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, far_behind, 0.0, 0.0), "out of reach")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, near_behind, 0.0, 0.0), "mouth is not facing it")
	check(InteractionResolver.feed(grazer, in_front, 1.0).allowed, "a meal starts the cooldown")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, in_front, 1.1, 0.0), "not hungry")
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, in_front, 1.1, 100.0), "still swallowing")


func test_a_full_stomach_refusal_starts_no_cooldown() -> void:
	var grazer := _actor("a", [["mouth_filter", 0.0]])
	var food := _plant(Vector2(0.7, 0.0))
	_check_refused(grazer, InteractionResolver.feed.bind(grazer, food, 2.0, 1.0), "not hungry")
	check(grazer.cooldowns.is_empty(), "no cooldown recorded")
	check(InteractionResolver.feed(grazer, food, 2.0, 50.0).allowed, "eats in the same instant once there is room")
