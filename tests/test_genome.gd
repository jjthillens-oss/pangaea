extends TestCase

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _valid_genome() -> Genome:
	var genome := Genome.create(StableId.generate("lineage"))
	genome.add_part("mouth_filter", 0.0)
	genome.add_part("flagellum", PI)
	return genome


func test_catalog_loads_from_data_file() -> void:
	check(catalog != null, "catalog should load")
	check(catalog.has_part("mouth_jaw"), "catalog should list mouth_jaw")
	check_eq(catalog.max_count_of("flagellum"), 3, "flagellum max")
	check(catalog.required_categories.has("mouth"), "mouth should be required")


func test_valid_starting_body_passes() -> void:
	check_eq(_valid_genome().validate(catalog).size(), 0, "error count")


func test_body_without_mouth_is_rejected() -> void:
	var genome := Genome.create(StableId.generate("lineage"))
	genome.add_part("flagellum", PI)
	check_has_error(genome.validate(catalog), "'mouth'")


func test_unknown_part_type_is_rejected() -> void:
	var genome := _valid_genome()
	genome.add_part("laser_eye", 0.5)
	check_has_error(genome.validate(catalog), "unknown type 'laser_eye'")


func test_per_type_limit_is_enforced() -> void:
	var genome := _valid_genome()
	genome.add_part("mouth_filter", 0.3)
	check_has_error(genome.validate(catalog), "Too many 'mouth_filter'")


func test_total_part_limit_is_enforced() -> void:
	var genome := _valid_genome()
	for i in catalog.max_parts:
		genome.add_part("spike" if i < 4 else "eye_spot", 0.1 * i)
	check_has_error(genome.validate(catalog), "Too many parts")


func test_angle_and_scale_bounds() -> void:
	var genome := _valid_genome()
	genome.add_part("spike", 4.0)
	genome.add_part("eye_spot", 0.2, 5.0)
	var errors := genome.validate(catalog)
	check_has_error(errors, "angle outside")
	check_has_error(errors, "scale outside")


func test_part_ids_stay_stable_after_removal() -> void:
	var genome := _valid_genome()
	var spike := genome.add_part("spike", 1.0)
	check(genome.remove_part("part_1"), "removing part_1")
	var eye := genome.add_part("eye_spot", 0.5)
	check_eq(spike, "part_3", "spike id")
	check_eq(eye, "part_4", "new parts never reuse an id")


func test_dict_round_trip_preserves_everything() -> void:
	var genome := _valid_genome()
	genome.appearance = {"hue": 0.1, "pattern": "spots"}
	var copy := Genome.from_dict(JSON.parse_string(JSON.stringify(genome.to_dict())))
	check_eq(JSON.stringify(copy.to_dict()), JSON.stringify(genome.to_dict()), "round trip")


func test_loading_keeps_invalid_parts_for_validation_to_report() -> void:
	var data := _valid_genome().to_dict()
	data["parts"].append({"id": "part_9", "type": "retired_part", "angle": 0.0, "scale": 1.0})
	var loaded := Genome.from_dict(data)
	check_eq(loaded.parts.size(), 3, "no part is silently dropped")
	check_has_error(loaded.validate(catalog), "retired_part")
