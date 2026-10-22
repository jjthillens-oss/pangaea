extends TestCase
## The words and numbers the menus and HUD show (M1 step 2). Body cards must show exactly the
## stats Phenotype.derive gives, the HUD must name the sim's energy, health and points as the
## rules count them, controls are named from the key bindings, and the death notice names the
## points the death rule takes. The running screens are covered by the scene smoke.

const PERF_TOUR := "res://game/dev/perf_tour.gd"
const THEME := "res://game/ui/theme/pangaea_theme.tres"

var catalog := PartCatalog.load_from()


func _phenotype(body: String) -> Phenotype:
	return Phenotype.derive(Lineage.found(7, "test+dev", catalog, body).save.genome, catalog)


func _state(energy: float, health: float) -> ActorState:
	var s := ActorState.fresh(_phenotype("grazer"))
	s.energy = energy
	s.health = health
	return s


func test_body_cards_show_the_derived_stats_of_each_starting_body() -> void:
	var expected := {
		"grazer": ["2.9 m/s", "143°/s", "0.90 energy/s", "9 m", "100"],
		"hunter": ["3.3 m/s", "143°/s", "1.15 energy/s", "6 m", "100"],
		"omnivore": ["2.7 m/s", "143°/s", "0.95 energy/s", "6 m", "100"],
	}
	for body in BodyText.ORDER:
		var p := _phenotype(body)
		var rows := BodyText.stat_rows(p)
		var values := PackedStringArray()
		for row in rows:
			values.append(row[1])
		check_eq(values, PackedStringArray(expected[body]), body)
		check_eq(rows[0][1], "%.1f m/s" % p.speed, "%s speed is the phenotype's" % body)
		check_eq(rows[2][1], "%.2f energy/s" % p.upkeep, "%s upkeep is the phenotype's" % body)
	var names := PackedStringArray()
	for row in BodyText.stat_rows(_phenotype("grazer")):
		names.append(row[0])
	check_eq(names, PackedStringArray(["Speed", "Turning", "Upkeep", "Sight", "Max energy"]), "stat names")


func test_each_body_has_a_name_a_role_and_a_diet_from_its_mouths() -> void:
	check_eq(BodyText.ORDER, PackedStringArray(catalog.starting_bodies.keys()), "a card for every starting body")
	check_eq(BodyText.diet(_phenotype("grazer")), "Eats plankton", "grazer")
	check_eq(BodyText.diet(_phenotype("hunter")), "Eats carrion", "hunter")
	check_eq(BodyText.diet(_phenotype("omnivore")), "Eats both", "omnivore")
	for body in BodyText.ORDER:
		check(not BodyText.role(body).is_empty(), "%s has a role line" % body)
	check_eq(BodyText.body_name(""), "Evolved cell", "an edited body")
	check_eq(BodyText.lineage_line("hunter", "3F9A-1C07", 2), "Hunter lineage 3F9A-1C07 · Generation\u00a02",
		"lineage line, with a no-break space before the generation number")


func test_the_hud_names_energy_health_and_hunger_as_the_rules_count_them() -> void:
	check_eq(Hud.energy_line(_state(62.4, 30.0)), "Energy 62 / 100", "rounded")
	check_eq(Hud.energy_line(_state(0.2, 30.0)), "Energy 1 / 100", "only a starving cell shows 0")
	check_eq(Hud.energy_line(_state(0.0, 30.0)), "Energy 0 / 100", "starving")
	check_eq(Hud.health_line(_state(0.0, 12.6)), "Health 13 / 30", "health")
	check_eq(Hud.state_name(_state(25.0, 30.0)), "Fed", "a quarter full is fed")
	check_eq(Hud.state_name(_state(24.9, 30.0)), "Hungry", "below a quarter")
	check_eq(Hud.state_name(_state(0.0, 30.0)), "Starving", "empty")
	check_eq(Hud.rested_line(ActorState.fresh(_phenotype("hunter"))), "Your cell rested: Energy 60%, Health full", "after continue")


func test_top_center_texts_wrap_at_spaces_within_the_width_they_are_given() -> void:
	var theme: Theme = load(THEME)
	var font := theme.get_font(&"font", &"Label")
	var size := theme.get_font_size(&"font_size", &"Label")
	var short := "Back at the start: 2 adaptation points lost."
	var w := Hud.wrap_width(short, font, size, 800.0)
	check(w < 800.0 and w >= font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
		"a short message keeps its own width (%.0f px)" % w)
	var failed := "Not saved yet: Could not save to user://saves/slot_1.json: Can't open file."
	check(font.get_string_size(failed, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 800.0, "a failed save's message is too wide for one line")
	w = Hud.wrap_width(failed, font, size, 800.0)
	var para := TextParagraph.new()
	para.break_flags = Hud.WRAP_FLAGS
	para.add_string(failed, font, size)
	para.width = w
	var lines := PackedStringArray()
	for i in para.get_line_count():
		var r := para.get_line_range(i)
		lines.append(failed.substr(r.x, r.y - r.x))
	check(w <= 800.0 and lines.size() == 2, "it wraps onto two lines within 800 px (%.0f px: %s)" % [w, lines])
	check(Hud.breaks_at_spaces(para, failed) and lines.size() == 2 and lines[0].contains("user://saves/slot_1.json:"),
		"between words, with the save path whole on one line: %s" % lines)
	check(lines.size() == 2 and lines[1].split(" ").size() > 1, "the last line is more than one word: %s" % lines)
	var large := theme.get_font_size(&"font_size", &"LargeLabel")
	var banner := Hud.wrap_width(Hud.STARVING_TEXT, font, large, 800.0)
	check(banner < 800.0 and banner >= font.get_string_size(Hud.STARVING_TEXT.get_slice("\n", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, large).x,
		"the starving banner keeps its two lines as written (%.0f px)" % banner)


func test_points_and_meal_toasts_name_what_was_earned() -> void:
	check_eq(Hud.points_line(1), "1 adaptation point", "singular")
	check_eq(Hud.points_line(7), "7 adaptation points", "plural")
	check_eq(Hud.meal_toast({"absorbed": 8.0, "points": 1}), "+8 energy · +1 point", "plankton")
	check_eq(Hud.meal_toast({"absorbed": 24.0, "points": 3}), "+24 energy · +3 points", "carrion")
	check_eq(Hud.meal_toast({"absorbed": 4.4, "points": 0}), "+4 energy", "a meal that earned nothing")
	check_eq(Hud.survival_toast(1, 30.0), "+1 point · survived 30 s", "survival")


func test_controls_are_named_from_the_key_bindings() -> void:
	var lines := Hud.controls_lines()
	check_eq(lines[0], "Swim: W A S D or arrow keys", "swim keys")
	check_eq(lines[1], "Swim to the cursor: hold Left mouse", "pointer swim")
	check_eq(lines[3], "Pause: Escape or P", "pause")
	check_eq(lines[4], "Full screen: F11", "full screen")
	for line in lines:
		check(not line.contains("Physical"), "plain key names in '%s'" % line)
	check(Hud.first_meal_line(_phenotype("grazer")).contains("filter mouth"), "a grazer is told about its filter mouth")
	check(Hud.first_meal_line(_phenotype("hunter")).contains("jaw"), "a hunter is told about its jaw")


func test_the_death_notice_names_the_points_the_death_rule_takes() -> void:
	check_eq(Main.death_text("starved", Lineage.death_loss(9)),
		"Your cell starved. The lineage continues. You lose a quarter of your unspent adaptation points (−2).", "starved")
	check_eq(Main.death_title("starved"), "Out of energy", "the title does not repeat the body")
	check_eq(Main.save_status_text({"ok": false, "error": "Could not save to x: disk full."}), "Could not save to x: disk full.", "errors as given")
	check(Main.save_status_text({"ok": true, "error": ""}).begins_with("Saved "), "a save names its time")


func test_save_times_show_as_a_local_date_and_minute() -> void:
	var text := StartScreen.local_time_text(1761136920)
	check(RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}$").search(text) != null, "format of '%s'" % text)


func test_the_perf_tour_reports_the_average_and_the_slowest_one_percent() -> void:
	var tour: GDScript = load(PERF_TOUR)
	var frames := PackedFloat32Array()
	for i in 198:
		frames.append(10.0)
	frames.append(40.0)
	frames.append(20.0)
	var report: Dictionary = tour.summarize(frames)
	check_eq(report.frames, 200, "frames")
	check_near(report.avg_frame_ms, 10.2, 1e-4, "average frame")
	check_near(report.low_1pct_fps, 1000.0 / 30.0, 1e-3, "1% low over the two slowest frames")
	check_near(report.max_frame_ms, 40.0, 1e-6, "longest frame")
	check_eq(tour.summarize(PackedFloat32Array()).frames, 0, "no frames")
