extends TestCase
## The look probe's measuring and its gates (micro-world plan C1, section 6). The probe itself runs
## windowed in both renderers (docs/TOOLCHAIN.md, "Look probe"); these checks keep its colour maths
## equal to the judge's CIELAB, its medians and its gate logic honest, and its gate sets in step
## with the plan and with today's measured look.

const LookProbe := preload("res://tools/godot/look_probe.gd")
const FOOD_HEX := "CFE86A"              ## docs/art/ART_DIRECTION.md: food-only glow...
const THREAT_HEX := "D9466B"            ## ...and threat-only pink
## Today's readings (m1-threats at ecb1eee on llvmpipe, docs/TOOLCHAIN.md "Look probe") by renderer:
## a teal floor behind a cell of about the same value, and the two renderers about 7 CIE76 apart.
const TODAY := {
	"gl_compatibility": {
		"lineup": {
			"cell": {"h": 42.1}, "cell_dL": 2.4,
			"fluid_near_cell": {"L": 42.4, "h": 206.3, "C": 22.6}, "fluid_threat_hue_gap": 164.8,
			"fluid_corners_min_L": 48.4, "glow_dL": -7.7,
			"plankton": {"h_min": 108.6, "h_max": 138.2, "max_channel": 255},
			"carrion": {"threat_hue_gap": 18.6},
			"parity": {"fluid_dE": 6.7, "cell_dE": 7.0},
		},
		"tell": {"lane": {"over_fluid_min_dL": 8.0, "over_decor_min_dL": 8.0}},
		"puff": {"lane": {"over_fluid_min_dL": 6.4, "over_decor_min_dL": 6.4}},
		"rim_north": {"skirt": {"max_step_dL": 6.8}},
		"starving": {"cell_dL": 5.8},
		"hud": {"vignette": {"h": 261.2}},
	},
	"forward_plus": {
		"lineup": {
			"cell": {"h": 41.3}, "cell_dL": 3.6,
			"fluid_near_cell": {"L": 47.5, "h": 212.8, "C": 24.3}, "fluid_threat_hue_gap": 158.3,
			"fluid_corners_min_L": 55.2, "glow_dL": -9.2,
			"plankton": {"h_min": 117.8, "h_max": 136.6, "max_channel": 255},
			"carrion": {"threat_hue_gap": 15.1},
			"parity": {"fluid_dE": 6.7, "cell_dE": 7.0},
		},
		"tell": {"lane": {"over_fluid_min_dL": 3.0, "over_decor_min_dL": 3.0}},
		"puff": {"lane": {"over_fluid_min_dL": 2.8, "over_decor_min_dL": 2.8}},
		"rim_north": {"skirt": {"max_step_dL": 3.5}},
		"starving": {"cell_dL": 3.7},
		"hud": {"vignette": {"h": 254.2}},
	},
}


func test_lab_is_the_judge_s_cielab() -> void:
	var white := LookProbe.lab(Color.WHITE)
	check_near(white.x, 100.0, 0.01, "white L*")
	check_near(white.y, 0.0, 0.02, "white a*")
	check_near(white.z, 0.0, 0.02, "white b*")
	var red := LookProbe.lab(Color("FF0000"))
	check_near(red.x, 53.23, 0.01, "red L*")
	check_near(red.y, 80.11, 0.01, "red a*")
	check_near(red.z, 67.22, 0.01, "red b*")
	check_near(LookProbe.lab(Color.BLACK).length(), 0.0, 1e-4, "black is the origin")
	check_near(LookProbe.lab(Color("808080")).x, 53.59, 0.01, "mid grey L*")
	check_near(LookProbe.hue(LookProbe.lab(Color(FOOD_HEX))), 114.35, 0.01, "the food glow's hue, inside the plankton band")
	check_near(LookProbe.hue(LookProbe.lab(Color(THREAT_HEX))), 11.09, 0.01, "the threat pink's hue (section 6: h 11)")
	check_near(LookProbe.delta_e(Color(FOOD_HEX), Color(THREAT_HEX)), 103.69, 0.01, "CIE76 between them")
	check_eq(LookProbe.delta_e(Color(FOOD_HEX), Color(FOOD_HEX)), 0.0, "a colour does not differ from itself")


func test_a_reading_names_the_colour_and_its_lab_to_a_tenth() -> void:
	var p := LookProbe.reading(Color("A2543E"))
	check_eq(p.hex, "#A2543E", "the colour as hex")
	check_near(p.L, 44.8, 1e-4, "L*")
	check_near(p.a, 30.2, 1e-4, "a*")
	check_near(p.b, 27.3, 1e-4, "b*")
	check_near(p.C, 40.7, 1e-4, "chroma")
	check_near(p.h, 42.1, 1e-4, "hue: today's coral cell, inside section 6's 30 to 50")
	check_near(LookProbe.reading(Color("246E74")).h, 206.3, 1e-4, "today's teal fluid is far from the micro look's 268 to 288")


func test_hue_gaps_wrap_round_the_circle() -> void:
	check_eq(LookProbe.hue_gap(350.0, 10.0), 20.0, "across 0, one way")
	check_eq(LookProbe.hue_gap(10.0, 350.0), 20.0, "and the other")
	check_eq(LookProbe.hue_gap(0.0, 180.0), 180.0, "opposite hues")
	check_eq(LookProbe.hue_gap(42.0, 42.0), 0.0, "the same hue")
	check_near(LookProbe.hue_gap(30.1, LookProbe.hue(LookProbe.lab(Color(THREAT_HEX)))), 19.01, 0.01, "today's darkest carrion and the threat pink")
	check_near(LookProbe.hue(Vector3(50.0, 0.0, -10.0)), 270.0, 1e-4, "hues run 0 to 360, never negative")


func test_a_median_is_per_channel_over_the_pixels_it_picks() -> void:
	var img := Image.create(5, 5, false, Image.FORMAT_RGB8)
	img.fill(Color8(10, 20, 30))
	img.set_pixel(0, 0, Color8(255, 0, 0))
	img.set_pixel(4, 4, Color8(0, 255, 0))
	img.set_pixel(2, 2, Color8(200, 100, 50))
	var all := LookProbe.median_of(img, Rect2i(0, 0, 5, 5))
	check_eq(all.count, 25, "every pixel of the rect")
	check_eq(all.color.to_html(false), Color8(10, 20, 30).to_html(false), "a few odd pixels do not move the median")
	check_eq(all.max_channel, 255, "the highest channel is any pixel's, not the median's")
	var disc := LookProbe.median_of(img, Rect2i(0, 0, 5, 5), 1, Vector2(2, 2), 1.0)
	check_eq(disc.count, 5, "a radius keeps the pixels within it of the centre")
	check_eq(disc.max_channel, 200, "the corners' 255 lie outside the disc")
	var strided := LookProbe.median_of(img, Rect2i(0, 0, 5, 5), 2)
	check_eq(strided.count, 9, "a stride of 2 takes every other pixel and row")
	var clipped := LookProbe.median_of(img, Rect2i(3, 3, 10, 10))
	check_eq(clipped.count, 4, "a rect is clipped to the image")
	var outside := LookProbe.median_of(img, Rect2i(20, 20, 3, 3))
	check_eq(outside.count, 0, "no pixel outside the image")
	check_eq(outside.max_channel, 0, "and no channel")


func test_contrast_is_the_wcag_ratio_and_a_colour_list_has_a_per_channel_median() -> void:
	check_near(LookProbe.contrast(Color.WHITE, Color.BLACK), 21.0, 1e-4, "black on white")
	check_near(LookProbe.contrast(Color.BLACK, Color.WHITE), 21.0, 1e-4, "either way round")
	check_near(LookProbe.contrast(Color("777777"), Color.WHITE), 4.48, 0.01, "mid grey on white, WCAG's 4.5:1 line")
	check_near(LookProbe.contrast(Color("1D5084"), Color("1D5084")), 1.0, 1e-6, "a colour against itself")
	var colors := PackedColorArray([Color8(10, 200, 30), Color8(20, 100, 60), Color8(250, 0, 90)])
	check_eq(LookProbe.median_color(colors).to_html(false), Color8(20, 100, 60).to_html(false), "each channel's middle value")
	check_eq(LookProbe.median_color(PackedColorArray()), Color.BLACK, "none: black")


func test_the_median_difference_of_two_frames() -> void:
	var a := Image.create(4, 4, false, Image.FORMAT_RGB8)
	a.fill(Color8(40, 110, 116))
	var b := a.duplicate() as Image
	check_eq(LookProbe.median_delta_e(a, b, Rect2i(0, 0, 4, 4)), 0.0, "the same frame twice")
	b.fill(Color8(36, 110, 116))
	b.set_pixel(0, 0, Color.WHITE)
	var expected := snappedf(LookProbe.delta_e(Color8(40, 110, 116), Color8(36, 110, 116)), 0.1)
	check(expected > 0.0, "the two teals differ")
	check_eq(LookProbe.median_delta_e(a, b, Rect2i(0, 0, 4, 4)), expected, "one white pixel does not move the median")
	check(is_nan(LookProbe.median_delta_e(a, b, Rect2i(10, 10, 2, 2))), "no pixel: no number, so a parity gate on it fails")


func test_a_path_reads_nested_readings() -> void:
	var today: Dictionary = TODAY.gl_compatibility
	check_eq(LookProbe.value_at(today, "lineup.cell.h"), 42.1, "a nested number")
	check_eq(LookProbe.value_at(today, "starving.cell_dL"), 5.8, "one level down")
	check(LookProbe.value_at(today, "lineup.cell.L") == null, "a missing key")
	check(LookProbe.value_at(today, "lineup.cell_dL.x") == null, "a path through a number")
	check(LookProbe.value_at(today, "rim_south.cell_dL") == null, "a scene that did not run")


func test_a_gate_passes_inside_its_range_fails_outside_or_without_a_number_and_skips_what_did_not_run() -> void:
	var readings := {"lineup": {"x": 5.0, "n": 3, "nan": NAN, "text": "5"}}
	var gates := [
		{"id": "inside", "path": "lineup.x", "min": 4.0, "max": 6.0},
		{"id": "at_min", "path": "lineup.x", "min": 5.0},
		{"id": "at_max", "path": "lineup.x", "max": 5.0},
		{"id": "below", "path": "lineup.x", "min": 5.5},
		{"id": "above", "path": "lineup.n", "max": 2.0},
		{"id": "missing", "path": "lineup.y", "min": 0.0},
		{"id": "not_a_number", "path": "lineup.nan", "min": 0.0},
		{"id": "text", "path": "lineup.text", "min": 0.0},
		{"id": "not_run", "path": "tell.lane.over_fluid_min_dL", "min": 15.0},
		{"id": "parity", "path": "lineup.x", "max": 2.0, "parity": true},
	]
	var expected := ["pass", "pass", "pass", "fail", "fail", "fail", "fail", "fail", "skip", "skip"]
	var results := LookProbe.evaluate(gates, readings, false)
	check_eq(results.size(), gates.size(), "one result per gate")
	for i in results.size():
		check_eq(results[i].status, expected[i], "gate %s" % gates[i].id)
		check_eq(results[i].id, gates[i].id, "the result keeps the gate's fields")
	check_eq(results[0].value, 5.0, "and the value it read")
	check(not gates[0].has("status"), "the gate itself is left as it was")
	var with_parity := LookProbe.evaluate(gates, readings, true)
	check_eq(with_parity[9].status, "fail", "with --parity the parity gate is checked: 5 is above 2")


func test_every_gate_reads_a_scene_the_probe_stages() -> void:
	for look: String in LookProbe.GATES:
		var ids := {}
		for gate: Dictionary in LookProbe.GATES[look]:
			check(LookProbe.SCENES.has(gate.path.get_slice(".", 0)), "%s/%s reads scene %s" % [look, gate.get("id"), gate.path])
			check(gate.has("min") or gate.has("max"), "%s/%s has a range" % [look, gate.get("id")])
			check(not str(gate.get("what", "")).is_empty(), "%s/%s says what it checks" % [look, gate.get("id")])
			check(not ids.has(gate.id), "%s/%s is named once" % [look, gate.id])
			ids[gate.id] = true
	check(LookProbe.GATES.has("micro") and LookProbe.GATES.has("baseline"), "the micro look's gates and today's")


func test_the_micro_gates_are_section_6() -> void:
	var by_id := {}
	for gate: Dictionary in LookProbe.GATES.micro:
		by_id[gate.id] = gate
	var ranges := {
		"cell_hue": [30.0, 50.0], "cell_contrast": [15.0, null], "fluid_value": [26.0, 36.0],
		"fluid_hue": [268.0, 288.0], "fluid_chroma": [25.0, null], "fluid_threat_gap": [90.0, null], "fluid_corners": [15.0, null],
		"lane_fluid_tell": [15.0, null], "lane_decor_tell": [15.0, null], "lane_fluid_puff": [15.0, null],
		"lane_decor_puff": [15.0, null], "plankton_hue_low": [110.0, null], "plankton_hue_high": [null, 145.0],
		"plankton_clip": [null, 254.0], "carrion_hue": [15.0, null], "vignette_hue": [15.0, 45.0], "marker_outline": [3.0, null],
		"starving_contrast": [10.0, null], "parity_fluid": [null, 2.0], "parity_cell": [null, 2.0],
		"ambush_contrast": [15.0, null], "lane_on_patch": [2.0, null], "patch_visible": [5.0, null],
		"patch_shafts": [null, 0.5], "patch_ambush": [15.0, null], "sunlit_cell": [15.0, null], "shelter_rim": [5.0, null],
	}
	for id: String in ranges:
		check(by_id.has(id), "section 6 has %s" % id)
		if not by_id.has(id):
			continue
		check_eq(by_id[id].get("min"), ranges[id][0], "%s min" % id)
		check_eq(by_id[id].get("max"), ranges[id][1], "%s max" % id)
	check(by_id.parity_fluid.get("parity", false) and by_id.parity_cell.get("parity", false), "the parity gates need --parity")
	check_eq(LookProbe.LANE_POINTS_NEEDED, 3, "the lane outline at 3 points")


func test_today_s_look_passes_its_baseline_gates_in_both_renderers_and_fails_the_micro_look_s() -> void:
	for renderer: String in TODAY:
		var baseline := LookProbe.evaluate(LookProbe.GATES.baseline, TODAY[renderer], true)
		for g: Dictionary in baseline:
			check_eq(g.status, "pass", "%s passes baseline %s (%s)" % [renderer, g.id, g.value])
		var failed := {}
		for g: Dictionary in LookProbe.evaluate(LookProbe.GATES.micro, TODAY[renderer], true):
			if g.status == "fail":
				failed[g.id] = true
		for id in ["cell_contrast", "fluid_value", "fluid_hue", "fluid_chroma", "depth_glow", "lane_fluid_tell",
				"lane_decor_puff", "plankton_clip", "vignette_hue", "starving_contrast", "parity_fluid", "parity_cell"]:
			check(failed.has(id), "%s fails the micro look's %s" % [renderer, id])
		check(not failed.has("cell_hue") and not failed.has("carrion_hue") and not failed.has("fluid_threat_gap"),
			"%s keeps the coral cell, the carrion hue and the teal's distance from the threat pink" % renderer)
	check_eq(LookProbe.GATES.baseline.size(), 18, "every baseline gate has a reading here")


## S2's growth set (s2-view 12.3): every reading the spec names, with its bound, on the S2 scenes
## the probe stages with the omnivore.
func test_the_growth_gates_are_s2_view_12_3() -> void:
	var by_path := {}
	for gate: Dictionary in LookProbe.GATES.growth:
		by_path[gate.path] = gate
	var want := {
		"hatch.median_dE": [null, 2.0],
		"lineup_s1.ink.ambush_hunter": [1.0, 1.0], "lineup_s1.ink.rammer": [1.0, 1.0],
		"lineup_s2.ink.rammer": [0.0, 0.0], "lineup_s2.ink.ambush_hunter": [0.0, 0.0],
		"lineup_s2.ink.lurker": [1.0, 1.0], "lineup_s2.ink.elder_rammer": [1.0, 1.0],
		"lineup_s2.rim.rammer": [1.0, 1.0], "lineup_s2.rim.ambush_hunter": [0.0, 0.0],
	}
	for n in [1, 2]:
		for species: String in LookProbe.LINEUP_NEAR[n]:
			want["lineup_s%d.near.%s.cell_multiple" % [n, species]] = [1.4, null]
		for i in LookProbe.LINEUP_FAR_SPOTS.size():
			want["lineup_s%d.far.%d.cell_radius_multiple" % [n, i]] = [5.0, null]
			want["lineup_s%d.far.%d.screen_share" % [n, i]] = [null, 0.3333]
	check_eq(by_path.size(), want.size(), "one gate per reading (%d)" % want.size())
	for path: String in want:
		check(by_path.has(path), "the growth set reads %s" % path)
		if by_path.has(path):
			check_eq(by_path[path].get("min"), want[path][0], "%s min" % path)
			check_eq(by_path[path].get("max"), want[path][1], "%s max" % path)
	check_eq(LookProbe.LOOK_WORLDS.growth, "endless", "measured in the endless sea")
	check_eq(str(LookProbe.GROWTH_SCENES), str(["lineup_s1", "lineup_s2", "hatch"]), "its scenes")
	for scene in LookProbe.GROWTH_SCENES:
		check(LookProbe.ENDLESS_SCENES.has(scene), "%s is an endless scene" % scene)
		check_eq(LookProbe.body_for(scene), "omnivore", "%s starts an omnivore, so the rim shows" % scene)
	check_eq(LookProbe.body_for("lineup"), LookProbe.BODY, "the other scenes keep the grazer")
	check_eq(str(LookProbe.LINEUP_NEAR[1]), str(["lurker", "elder_rammer", "veil", "warden"]), "size 1's near ghosts")
	check_eq(str(LookProbe.LINEUP_NEAR[2]), str(["veil", "warden", "deep_lurker", "elder_warden"]), "size 2's")


## Ink and rim are read as the share (or count) of pixels near a hue with enough chroma.
func test_a_hue_share_counts_the_pixels_near_a_hue_with_enough_chroma() -> void:
	var pink := Color(THREAT_HEX)
	var grey := Color(0.6, 0.6, 0.62)
	var colors := PackedColorArray([pink, pink, Color(FOOD_HEX), grey])
	var share := LookProbe.hue_share(colors, THREAT_HEX, 15.0, 30.0)
	check_eq(share, {"count": 2, "of": 4, "share": 0.5}, "two of four are the threat pink")
	check_eq(LookProbe.hue_share(colors, FOOD_HEX, 15.0, 5.0).count, 1, "one is the food green")
	check_eq(LookProbe.hue_share(PackedColorArray([pink.lerp(grey, 0.85)]), THREAT_HEX, 15.0, 30.0).count, 0,
		"a pink washed nearly grey is not ink")
	# A pink washed with a neutral grey keeps its hue within the window and loses the chroma: only the
	# chroma floor turns it away.
	var washed := pink.lerp(Color(0.6, 0.6, 0.6), 0.6)
	var w := LookProbe.lab(washed)
	check(LookProbe.hue_gap(LookProbe.hue(w), LookProbe.hue(LookProbe.lab(pink))) < 15.0, "the washed pink keeps its hue")
	check(Vector2(w.y, w.z).length() < 30.0, "but has under 30 of chroma")
	check_eq(LookProbe.hue_share(PackedColorArray([washed]), THREAT_HEX, 15.0, 0.0).count, 1, "with no chroma floor it counts")
	check_eq(LookProbe.hue_share(PackedColorArray([washed]), THREAT_HEX, 15.0, 30.0).count, 0, "with the floor it does not")
	check_eq(LookProbe.hue_share(PackedColorArray(), THREAT_HEX, 15.0, 30.0), {"count": 0, "of": 0, "share": 0.0}, "no pixels")
	var turned := LookProbe.lab(pink)
	check(LookProbe.hue_gap(LookProbe.hue(turned), LookProbe.hue(LookProbe.lab(Color("#D96B46")))) > 15.0,
		"an orange of the same value is outside 15 degrees")
	check_eq(LookProbe.hue_share(PackedColorArray([Color("#D96B46")]), THREAT_HEX, 15.0, 30.0).count, 0, "so it is not ink")
