extends TestCase
## One save carries a lineage from the pool to the sea to the land (backlog M4-03; Bible section 4's transition
## contract and section 18's "era changes are transactions with pre-transition checkpoints"). On real files through
## PersistenceService, with the game's own services at each step (EraTransition, AquaticLineage, AquaticSim), the
## way Main's swim_out_to_sea and crawl_out_of_the_sea drive them: the lineage id, the genome, the generation, the
## discoveries and the relationships survive both crossings, a save, a reload and a death in the sea; each crossing
## keeps the era it left as a checkpoint the lineage can go back to. Files go to the per-process folder under
## user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")
const SEED := 6262
const HUE := 0.31
const POINTS := 40
const DISCOVERY := {"type": "place", "id": "giant_husk", "size": 1}
const RELATIONSHIP := {"species": "grazer", "standing": "friend"}

var slot := ""
var catalog: PartCatalog
var persistence: PersistenceService
var rules: Dictionary


func before_each() -> void:
	SaveFolder.clear()
	slot = SaveFolder.path("continuity_slot.json")
	catalog = PartCatalog.load_from()
	persistence = PersistenceService.new(catalog)
	rules = AquaticLineage.rules()


func after_each() -> void:
	SaveFolder.clear()


## What must not change from the pool to the land: the lineage, its genome, what it found and whom it knows.
static func _carried(save: SaveGame) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify({
		"lineage_id": save.lineage_id, "world_seed": save.world_seed, "genome": save.genome.to_dict(),
		"discoveries": save.discoveries, "relationships": save.relationships,
	}, "", true, true)), "", true, true)


## `v` as a save file holds it (every number a double, sorted keys), so values compare in memory and from disk.
static func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true, true)


static func _events(save: SaveGame) -> Array:
	return save.lineage_history.map(func(e): return String(e.get("event", "")))


func _load(what: String) -> SaveGame:
	var loaded := persistence.load_from(slot)
	check(loaded.ok, "%s: the slot loads: %s" % [what, loaded.errors])
	return loaded.save if loaded.ok else null


## A cell at the top of the pool with its sea edge risen, saved to the slot.
func _cell_at_the_sea_edge() -> SaveGame:
	var founded := Lineage.found(SEED, "test+dev", catalog, "omnivore")
	check(founded.ok, "a lineage is founded: %s" % [founded.errors])
	var save: SaveGame = founded.save
	save.adaptation_points = POINTS
	save.genome.appearance["hue"] = HUE
	save.discoveries.append(DISCOVERY.duplicate())
	save.relationships.append(RELATIONSHIP.duplicate())
	check(ShoreLink.raise(save, 80.0, -40.0, 4), "the sea edge rose")
	check_eq(persistence.save_to(slot, save), OK, "the cell is saved")
	return save


## The sea on the slot: the fish swims, breeds lobe fins strong enough to crawl, befriends the grazers, dies once and
## saves. Returns the sim as it was written.
func _swim_and_save() -> AquaticSim:
	var lineage := AquaticLineage.read(slot, rules, SEED)
	check(lineage.ok and lineage.writable and not lineage.returning, "the cell's lineage arrives in the sea: %s" % [lineage.get("errors")])
	var sim := AquaticSim.new(rules, int(lineage.world_seed), lineage.body, lineage)
	var crawler: Dictionary = (sim.player.body as Dictionary).duplicate()
	crawler["limbs"] = int(rules.body.crawl_limbs)
	sim.points = maxi(sim.points, AquaticBody.edit_cost(sim.player.body, crawler, rules.editor))
	check(sim.apply_offspring(crawler, AquaticBody.edit_cost(sim.player.body, crawler, rules.editor)), "a generation with lobe fins")
	check(bool(sim.player.stats.can_crawl), "that can crawl")
	sim.relations.grazer.standing = "friend"
	sim.relations.grazer.rapport = 2
	# A death in the sea: back at the nest, the lineage as it was.
	var generation := int(sim.player.generation)
	var deaths := sim.deaths
	sim.player.health = -50.0
	sim.step(AquaticSim.Intent.new())
	check_eq(sim.deaths, deaths + 1, "the fish died once")
	check(float(sim.player.health) > 0.0 and sim.player.pos.distance_to(sim.nest_pos()) < 6.0, "and is back at the nest, alive")
	check_eq(int(sim.player.generation), generation, "the same generation after the death")
	check(bool(sim.player.stats.can_crawl) and String(sim.relations.grazer.standing) == "friend", "with its lobe fins and its friends")
	check_eq(AquaticLineage.write(slot, lineage, sim), OK, "the sea's progress is saved")
	return sim


func test_one_save_carries_the_lineage_from_the_pool_to_the_sea_to_the_land() -> void:
	var cell := _cell_at_the_sea_edge()
	var carried := _carried(cell)
	var generation := cell.genome.generation

	# The pool to the sea.
	var to_sea := EraTransition.cross(cell, slot, persistence)
	check(to_sea.ok, "the cell swims out to sea: %s" % [to_sea.errors])
	var sea := _load("in the sea")
	if sea == null:
		return
	check_eq(sea.era, "aquatic", "the slot's era is the sea")
	check_eq(_carried(sea), carried, "the lineage, genome, discoveries and relationships crossed unchanged")
	check_eq(_events(sea).back(), "entered_the_sea", "the crossing is the lineage's last event")
	check(EraTransition.has_checkpoint(slot, "aquatic"), "the pool is kept as a checkpoint")

	# Swim, breed, die, save; then a reload, as Continue does it.
	var sim := _swim_and_save()
	var block := sim.to_save()
	sea = _load("after swimming")
	if sea == null:
		return
	check_eq(sea.era, "aquatic", "still in the sea")
	check_eq(_carried(sea), carried, "the sea's save keeps what the cell carried")
	check_eq(sea.genome.generation, generation, "the cell's genome keeps its generation")
	var back := AquaticLineage.read(slot, rules, SEED)
	check(back.ok and back.returning, "the reload is a lineage that has swum")
	var again := AquaticSim.new(rules, int(back.world_seed), back.body, back)
	check_eq(_norm(again.to_save()), _norm(block),
			"the reloaded sea is the sea that was saved")
	check_eq(int(again.player.generation), int(sim.player.generation), "the fish's generation is back")
	check(bool(again.player.stats.can_crawl), "the reloaded fish can still crawl")
	check_eq(String(again.relations.grazer.standing), "friend", "the grazers are still friends")

	# The sea to the land, as Main.crawl_out_of_the_sea does it: from the slot, with the fish as the first creature.
	var fish: Dictionary = sea.aquatic.body
	var to_land := EraTransition.cross(sea, slot, persistence, {"creature": AquaticLineage.to_creature(fish, sea.genome)})
	check(to_land.ok, "the fish crawls ashore: %s" % [to_land.errors])
	var land := _load("ashore")
	if land == null:
		return
	check_eq(land.era, "terrestrial", "the slot's era is the land")
	check_eq(_carried(land), carried, "the lineage, genome, discoveries and relationships came ashore unchanged")
	check_eq(land.adaptation_points, sim.points, "with the points the sea left it")
	var events := _events(land)
	check(events.back() == "came_ashore" and events.find("entered_the_sea") < events.find("came_ashore"),
			"the history reads pool, sea, land: %s" % [events])
	check(not land.creature.is_empty() and CreatureRules.new().body_problems(land.creature.body).is_empty(), "a legal first land creature")
	check_eq(String(land.creature.body.skin_color), "#" + CreatureRules.cell_skin(float(fish.hue)).to_html(false), "in the fish's colour")
	check_eq(_norm(land.aquatic), _norm(block),
			"the sea's record is kept on the land's save")
	check_eq(land.world_changes.size(), cell.world_changes.size(), "the pool's sea edge is still on the save")

	# A second reload gives the same save: nothing is rebuilt or lost by loading.
	var land_again := _load("ashore, loaded again")
	if land_again != null:
		check_eq(_norm(land_again.to_dict()), _norm(land.to_dict()), "the same save on every load")
	# No way on from the land yet, and the refusal writes nothing.
	var further := EraTransition.cross(land, slot, persistence)
	check(not further.ok and land.era == "terrestrial", "the land has no way on yet")


func test_each_crossing_keeps_a_way_back_for_the_same_lineage() -> void:
	var cell := _cell_at_the_sea_edge()
	var carried := _carried(cell)
	check(EraTransition.cross(cell, slot, persistence).ok, "to the sea")
	var sim := _swim_and_save()
	var sea := _load("in the sea")
	if sea == null:
		return
	check(EraTransition.cross(sea, slot, persistence, {"creature": AquaticLineage.to_creature(sea.aquatic.body, sea.genome)}).ok, "to the land")
	check(EraTransition.has_checkpoint(slot, "aquatic") and EraTransition.has_checkpoint(slot, "terrestrial"), "both checkpoints are kept")

	# Back to the sea: the fish as it left the water.
	var to_sea := EraTransition.restore(slot, persistence, "terrestrial", cell.lineage_id)
	check(to_sea.ok, "back to the water: %s" % [to_sea.errors])
	var back := _load("back in the sea")
	if back == null:
		return
	check_eq(back.era, "aquatic", "the slot is in the sea again")
	check_eq(_carried(back), carried, "the same lineage")
	check(back.creature.is_empty() or _events(back).find("came_ashore") < 0, "as it was before it came ashore")
	var lineage := AquaticLineage.read(slot, rules, SEED)
	check(lineage.ok and lineage.returning and int(lineage.generation) == int(sim.player.generation), "with its fish and generation")
	check(bool(AquaticBody.stats(lineage.body, rules.body).can_crawl), "that can still crawl, so the shore offers land again")

	# And back to the pool: the cell at the sea's edge.
	var to_pool := EraTransition.restore(slot, persistence, "aquatic", cell.lineage_id)
	check(to_pool.ok, "back to the pool: %s" % [to_pool.errors])
	var pool := _load("back in the pool")
	if pool == null:
		return
	check_eq(pool.era, "microscopic", "the slot is in the pool again")
	check_eq(_carried(pool), carried, "the same lineage")
	check(pool.aquatic.is_empty() and not ShoreLink.shore_of(pool).is_empty(), "a cell with its sea edge still risen")
	# Another lineage's checkpoint is never restored over this one.
	var other := EraTransition.restore(slot, persistence, "terrestrial", "lineage_someone_else")
	check(not other.ok, "another lineage cannot take the checkpoint")
