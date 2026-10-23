extends TestCase
## Boundary and ordering checks for the three field services.

var layout: PoolLayout
var parts: PartCatalog
var species: SpeciesCatalog


func before_each() -> void:
	layout = PoolLayout.load_from()
	parts = PartCatalog.load_from()
	species = SpeciesCatalog.load_from()


func _creatures(p_species: SpeciesCatalog = null) -> CreatureField:
	return CreatureField.create(p_species if p_species != null else species, parts, layout, layout.build_region(9), 91)


func _creature_ids(field: CreatureField) -> Array:
	var ids := []
	for c in field.creatures:
		ids.append(c.id)
	return ids


func test_creature_niche_refuses_cap_plus_one_without_advancing_id() -> void:
	var field := _creatures()
	var cap: int = species.niche_of("ambush_hunter").cap
	for i in cap:
		check(field.spawn_at("ambush_hunter", Vector2(25.0 + i * 3.0, 0.0), 0.0) != null,
			"spawn %d fills the niche" % i)
	var before := field.next_number
	check(field.spawn_at("ambush_hunter", Vector2(40.0, 0.0), 0.0) == null, "cap + 1 refused")
	check_eq(field.creatures.size(), cap, "no extra creature")
	check_eq(field.next_number, before, "refusal spends no id")
	check_eq(field.region.niches.ambush.count, cap, "count remains at cap")


func test_creature_removal_frees_exactly_one_niche_place() -> void:
	var field := _creatures()
	var cap: int = species.niche_of("ambush_hunter").cap
	for i in cap:
		field.spawn_at("ambush_hunter", Vector2(25.0 + i * 3.0, 0.0), 0.0)
	var victim: CreatureField.Creature = field.creatures[1]
	var original_id := victim.id
	field.remove(victim, "test", 0, false)
	check_eq(field.region.niches.ambush.count, cap - 1, "one niche released")
	var replacement := field.spawn_at("ambush_hunter", Vector2(42.0, 0.0), 0.0)
	check(replacement != null, "replacement can use free place")
	check_eq(field.region.niches.ambush.count, cap, "full again")
	check(not _creature_ids(field).has(original_id), "removed id stays removed")
	check_eq(_creature_ids(field), ["c_1", "c_3", "c_4"], "survivors keep id order")


func test_equal_tick_spawn_queue_uses_site_id_tiebreaker() -> void:
	var field := _creatures()
	field._enqueue("terr_ne", "rammer", 120)
	field._enqueue("lair_sw", "ambush_hunter", 120)
	field._enqueue("lair_se", "ambush_hunter", 120)
	field._enqueue("terr_n_a", "rammer", 119)
	var sites := []
	for entry in field.queue:
		sites.append(entry.site)
	check_eq(sites, ["terr_n_a", "lair_se", "lair_sw", "terr_ne"],
		"earlier tick first, then stable site id")


func test_species_dictionary_insertion_order_does_not_change_site_spawn_ids() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	var reversed: Dictionary = source.duplicate(true)
	var keys: Array = reversed.species.keys()
	keys.reverse()
	var species_blocks := {}
	for key in keys:
		species_blocks[key] = reversed.species[key]
	reversed.species = species_blocks
	var first := _creatures(SpeciesCatalog.from_dict(source))
	var second := _creatures(SpeciesCatalog.from_dict(reversed))
	var arena := layout.build_arena()
	first.populate(arena, layout.spawn, 0)
	second.populate(arena, layout.spawn, 0)
	check_eq(first.snapshot(), second.snapshot(), "same site data, same field despite dictionary order")
	check_eq(_creature_ids(first), _creature_ids(second), "spawn ids stable")


func test_plankton_cap_boundary_does_not_admit_one_extra_item() -> void:
	var field := PlanktonField.create(layout.plankton)
	var cap := field.max_items_per_zone
	var zone := {"id": "test", "capacity": (cap + 1) * field.unit_energy,
		"amount": cap * field.unit_energy}
	check_eq(field.target_count(zone), cap, "exact cap")
	zone.amount += field.unit_energy
	check_eq(field.target_count(zone), cap, "cap + 1 unit still capped")
	check_eq(field.max_count(zone), cap, "full-zone cap is also enforced")


func test_carrion_removal_keeps_survivor_ids_in_creation_order() -> void:
	var field := CarrionField.create(layout.carrion, 5)
	var a := field.spawn(Vector2(1.0, 0.0), "test")
	var b := field.spawn(Vector2(2.0, 0.0), "test")
	var c := field.spawn(Vector2(3.0, 0.0), "test")
	check(field.consume(b.id), "middle item consumed")
	check(not field.consume(b.id), "id cannot be consumed twice")
	var ids := []
	for item in field.items:
		ids.append(item.id)
	check_eq(ids, [a.id, c.id], "survivors retain stable id order")
	check_eq(field.spawn(Vector2(4.0, 0.0), "test").id, "cr_4", "new id is monotonic")


func test_plankton_consumption_keeps_survivor_order_and_monotonic_ids() -> void:
	var field := PlanktonField.create(layout.plankton)
	var region := layout.build_region(19)
	field.fill(region, layout.build_arena(), 0, 0.0)
	var first: String = field.items[0].id
	var middle: String = field.items[1].id
	var third: String = field.items[2].id
	var next := field.next_number
	check(field.consume(middle), "middle item consumed")
	check(not field.consume(middle), "cannot consume twice")
	check_eq([field.items[0].id, field.items[1].id], [first, third], "survivors not reordered")
	check_eq(field.next_number, next, "removal does not recycle ids")


func test_carrion_supply_respects_exact_cap_and_refills_one_vacancy() -> void:
	var cfg := layout.carrion.duplicate(true)
	var no_initial: Array[Vector2] = []
	cfg.initial = no_initial
	cfg.interim_supply.enabled = true
	cfg.interim_supply.max_live = 2
	cfg.interim_supply.interval_s = 1.0
	cfg.interim_supply.jitter_s = 0.0
	var field := CarrionField.create(cfg, 23)
	field.spawn(Vector2(1.0, 0.0), "test")
	field.spawn(Vector2(2.0, 0.0), "test")
	field.next_supply_at = 0.0
	field.tick(PoolSim.DT, 0.0, layout.build_region(23), layout.build_arena())
	check_eq(field.items.size(), 2, "no cap + 1 interim item")
	check(field.consume("cr_1"), "one place freed")
	field.next_supply_at = 1.0
	field.tick(PoolSim.DT, 1.0, layout.build_region(23), layout.build_arena())
	check_eq(field.items.size(), 2, "exactly one replacement reaches cap")
	check_eq(field.items[-1].source, "interim", "replacement came from the supply")


func test_carrion_expiration_keeps_younger_survivor_id() -> void:
	var cfg := layout.carrion.duplicate(true)
	cfg.interim_supply.enabled = false
	var field := CarrionField.create(cfg, 29)
	var old := field.spawn(Vector2(1.0, 0.0), "test")
	var young := field.spawn(Vector2(2.0, 0.0), "test")
	old.age = field.lifetime - 0.5 * PoolSim.DT
	young.age = 0.0
	field.tick(PoolSim.DT, 1.0, layout.build_region(29), layout.build_arena())
	check_eq(field.items.size(), 1, "expired item removed")
	check_eq(field.items[0].id, young.id, "younger id remains")
	check_eq(field.events[-1].food_id, old.id, "expiry names old id")
