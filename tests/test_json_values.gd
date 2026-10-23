extends TestCase
## Save field readers reject damaged types and copy containers before callers mutate them.


func test_whole_numbers_accept_integral_json_floats_only() -> void:
	var problems: Array = []
	check_eq(JsonValues.whole({"n": 7}, "n", problems), 7, "integer")
	check_eq(JsonValues.whole({"n": 7.0}, "n", problems), 7, "integral JSON float")
	check(problems.is_empty(), "valid numbers do not report damage")
	for bad in [7.5, "7", null, true, NAN, INF]:
		var errors: Array = []
		check_eq(JsonValues.whole({"n": bad}, "n", errors), 0, "invalid number is neutral")
		check_eq(errors, ["Field 'n' must be a whole number."], "invalid number is reported")
	var missing: Array = []
	check_eq(JsonValues.whole({}, "n", missing), 0, "missing number is neutral")
	check_eq(missing.size(), 1, "missing number is reported")


func test_text_reader_reports_wrong_and_missing_types() -> void:
	var problems: Array = []
	check_eq(JsonValues.text({"name": "Grazer"}, "name", problems), "Grazer", "text kept")
	check(problems.is_empty(), "valid text has no problem")
	check_eq(JsonValues.text({"name": 12}, "name", problems), "", "wrong type is neutral")
	check_eq(JsonValues.text({}, "name", problems), "", "missing text is neutral")
	check_eq(problems.size(), 2, "both failures are reported")


func test_array_and_object_readers_make_deep_copies() -> void:
	var source := {"items": [{"traits": [1, 2]}], "actor": {"parts": [{"id": "eye"}]}}
	var problems: Array = []
	var items := JsonValues.array(source, "items", problems)
	var actor := JsonValues.dict(source, "actor", problems)
	items[0]["traits"][0] = 99
	actor["parts"][0]["id"] = "spike"
	check_eq(source["items"][0]["traits"][0], 1, "array's nested value stays untouched")
	check_eq(source["actor"]["parts"][0]["id"], "eye", "object's nested value stays untouched")
	check(problems.is_empty(), "valid containers have no problems")
	check_eq(JsonValues.array({"items": {}}, "items", problems), [], "wrong array type is neutral")
	check_eq(JsonValues.dict({"actor": []}, "actor", problems), {}, "wrong object type is neutral")
	check_eq(problems.size(), 2, "wrong container types are reported")
