extends TestCase
## S4 membrane variants (assets/records/textures/membranes.json, tools/blender/make_membranes.py).
## The ids are saved in Genome appearance.membrane, so they must stay stable; the masks are greyscale and
## stay bright enough that every player hue still reads over the deep-blue fluid.

const RECORD := "res://assets/records/textures/membranes.json"
const IDS := ["membrane_smooth_plasma", "membrane_ribbed_pellicle", "membrane_plated_wall", "membrane_bubbly_capsule"]
const DETAIL_MIN := 0.42


func _record() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	return parsed if parsed is Dictionary else {}


func test_record_lists_the_stable_ids() -> void:
	var record := _record()
	check(not record.is_empty(), "membranes record parses")
	var ids := []
	for item in record.get("items", []):
		ids.append(item.id)
	check_eq(ids, IDS, "membrane ids (saved in genomes; never rename one)")
	check(IDS.has(record.get("default", "")), "default membrane is listed")
	for key in ["owner", "provenance", "review_state", "generator_script", "usage"]:
		check(record.has(key), "membranes record has %s" % key)


func test_textures_load_tile_and_stay_bright_and_grey() -> void:
	for item in _record().get("items", []):
		check(item.get("uv_scale", 0.0) > 0.0, "%s: uv_scale" % item.id)
		var detail: Texture2D = load("res://" + item.detail)
		var normal: Texture2D = load("res://" + item.normal)
		check(detail != null and normal != null, "%s: detail and normal load" % item.id)
		if detail == null or normal == null:
			continue
		check(detail.get_width() == detail.get_height(), "%s: square tile" % item.id)
		var img := detail.get_image()
		if img.is_compressed():
			img.decompress()
		var darkest := 1.0
		var chroma := 0.0
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				var c := img.get_pixel(x, y)
				darkest = minf(darkest, c.r)
				chroma = maxf(chroma, maxf(absf(c.r - c.g), absf(c.r - c.b)))
		check(darkest >= DETAIL_MIN - 0.01, "%s: darkest detail %.3f keeps the hue readable" % [item.id, darkest])
		check(chroma <= 0.01, "%s: detail is greyscale, so it cannot shift the player's hue" % item.id)
		var cfg := ConfigFile.new()
		check(cfg.load("res://" + item.normal + ".import") == OK, "%s: normal import settings" % item.id)
		check(cfg.get_value("params", "compress/normal_map", 0) == 1, "%s: normal imports as a normal map" % item.id)
