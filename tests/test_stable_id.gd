extends TestCase
## IDs are independent of scene and file paths, and validation checks their full shape.


func test_generated_ids_are_well_formed_and_distinct() -> void:
	var seen := {}
	for _i in range(32):
		var id := StableId.generate("lineage")
		check(StableId.is_valid(id, "lineage"), "generated ID validates: %s" % id)
		check(not seen.has(id), "generated IDs do not repeat: %s" % id)
		seen[id] = true


func test_validation_rejects_wrong_prefix_length_and_non_hex_body() -> void:
	var good := "genome_0123456789abcdef"
	check(StableId.is_valid(good, "genome"), "a 16-digit hex body is valid")
	for bad in ["", "genome", "genome_0123456789abcde", "genome_0123456789abcdef0",
			"genome_0123456789abcdeg", "lineage_0123456789abcdef"]:
		check(not StableId.is_valid(bad, "genome"), "invalid ID refused: %s" % bad)
