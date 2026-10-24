extends RefCounted

# Isolated, proposed handoff rules. No production save or creature editor dependencies.
const SHORE_X := 300.0
const EDITOR_X := 520.0

var lineage_id := "founding-lineage"
var ancestral_feeding := "filter"
var stage := "aquatic"
var x := 80.0
var stamina := 100.0
var support := 0.45
var editor_open := false
var shoreline_seen := false

func crawl(direction: float, seconds: float) -> void:
	if editor_open or seconds <= 0.0:
		return
	var delta := clampf(direction, -1.0, 1.0) * seconds * (35.0 + support * 45.0)
	if delta > 0.0:
		var wet_distance := maxf(0.0, SHORE_X - x)
		var land_distance := maxf(0.0, delta - wet_distance)
		var allowed_land := minf(land_distance, stamina / (2.0 - support))
		delta = minf(delta, wet_distance) + allowed_land
		stamina = maxf(0.0, stamina - allowed_land * (2.0 - support))
	x = clampf(x + delta, 0.0, EDITOR_X)
	shoreline_seen = shoreline_seen or x >= SHORE_X

func rest(seconds: float) -> void:
	if seconds > 0.0 and not editor_open:
		stamina = minf(100.0, stamina + seconds * 12.0)

func can_open_editor() -> bool:
	return stage == "aquatic" and x >= EDITOR_X and support >= 0.5

func open_editor() -> bool:
	if not can_open_editor():
		return false
	editor_open = true
	return true

func choose_land_support(new_support: float) -> bool:
	if not editor_open or new_support < 0.5 or new_support > 1.0:
		return false
	support = new_support
	stage = "terrestrial"
	editor_open = false
	return true
