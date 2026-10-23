extends TestCase
## End-to-end hash checks, including threat brains and the independent food RNG streams.

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _sim(seed_value: int) -> PoolSim:
	var founded := Lineage.found(seed_value, "test+review", catalog, "omnivore")
	founded.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	return PoolSim.create(founded.save, catalog, layout, species)


func _intent(tick: int) -> SimIntent:
	var heading := float((tick / 75) % 4) * PI / 2.0
	return SimIntent.new(Vector2.from_angle(heading) * 0.45)


func test_fixed_seed_replays_to_identical_600_tick_hash() -> void:
	var first := _sim(4401)
	var second := _sim(4401)
	var start := first.state_hash()
	for tick in 600:
		first.step(_intent(tick))
		second.step(_intent(tick))
	check_eq(first.tick, 600, "all 600 ticks completed")
	check(first.state_hash() != start, "the world actually changed")
	check_eq(first.state_hash(), second.state_hash(), "same seed and inputs reproduce final hash")
	check_eq(JSON.stringify(first.snapshot(), "", true, true), JSON.stringify(second.snapshot(), "", true, true),
		"final snapshots also match, beyond a possible hash collision")


func test_identical_intents_never_diverge_at_any_tick() -> void:
	var first := _sim(4402)
	var second := _sim(4402)
	var bad_tick := -1
	for tick in 600:
		var input := _intent(tick)
		first.step(input)
		second.step(input)
		if first.state_hash() != second.state_hash():
			bad_tick = tick
			break
	check_eq(bad_tick, -1, "zero divergence over 600 equal-intent threat and ecology ticks")
	check_eq(first.tick, 600, "test reached the final tick")


func test_snapshot_hash_ignores_dictionary_insertion_order() -> void:
	var first := _sim(4403)
	var second := _sim(4403)
	first.actor.cooldowns = {"bite": 5, "ram": 9}
	second.actor.cooldowns = {"ram": 9, "bite": 5}
	check_eq(first.state_hash(), second.state_hash(), "equivalent cooldown tables hash identically")
	for tick in 120:
		first.step(_intent(tick))
		second.step(_intent(tick))
	check_eq(first.state_hash(), second.state_hash(), "insertion order does not alter subsequent state")
