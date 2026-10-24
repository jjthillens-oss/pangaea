extends SceneTree

const VillageModel = preload("res://village_model.gd")
var failures := 0

func _initialize() -> void:
	test_reservations_and_gathering()
	test_shelter_and_shortage()
	test_neighbor_and_identity()
	print("tribal: %d failures" % failures)
	quit(1 if failures else 0)

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func test_reservations_and_gathering() -> void:
	var m := VillageModel.new()
	check(m.assign("scout", "food"), "first worker reserves food")
	check(not m.assign("forager", "food"), "second worker cannot duplicate site")
	check(m.gather("scout"), "reserved worker gathers")
	check(m.food == 3 and m.food_site == 3, "one item moves from site to stock")
	check(m.reserved_sites.is_empty(), "gather releases reservation")
	check(not m.gather("scout"), "repeat gather without task cannot duplicate food")
	check(m.assign("forager", "food"), "released site can be reassigned")
	m.cancel("forager")
	check(m.reserved_sites.is_empty(), "cancel releases reservation")
	check(m.food == 3, "cancel cannot create food")

func test_shelter_and_shortage() -> void:
	var m := VillageModel.new()
	check(not m.build_shelter(), "shortage blocks construction")
	for i in range(2):
		check(m.assign("forager", "material") and m.gather("forager"), "material run completes")
	check(m.build_shelter(), "two materials build shelter")
	check(m.materials == 0 and m.shelter_built, "construction consumes exact materials")
	check(not m.build_shelter(), "shelter cannot be built twice")
	check(m.assign("scout", "food"), "food remains reachable")
	m.food_site = 0
	check(not m.gather("scout"), "depleted site cannot pay a worker")
	check(m.reserved_sites.is_empty(), "depletion releases claim")
	m.regenerate()
	check(m.food_site == 1, "site regenerates within capacity")

func test_neighbor_and_identity() -> void:
	var m := VillageModel.new()
	check(not m.trade_food(), "trade fails without offered material")
	m.materials = 1
	check(m.trade_food(), "neighbor accepts explicit exchange")
	check(m.food == 3 and m.materials == 0 and m.rival_food == 2, "trade conserves stocks")
	check(m.rival_relation == 1, "trade affects neighbor relationship")
	m.warn_neighbor()
	check(m.rival_relation == 0, "warning changes relation without permanent lock")
	check(
		m.rival_id == "reed-neighbors" and m.lineage_id == "shore-lineage",
		"rival and founding lineage stay identifiable"
	)
