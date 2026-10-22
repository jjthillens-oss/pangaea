extends TestCase
## The words and numbers the menus and HUD show (M1 step 2). Body cards must show exactly the
## stats Phenotype.derive gives, the HUD must name the sim's energy, health and points as the
## rules count them, controls are named from the key bindings, and the death notice names the
## points the death rule takes. The running screens are covered by the scene smoke.

const PERF_TOUR := "res://game/dev/perf_tour.gd"

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
	check_eq(BodyText.lineage_line("hunter", "3F9A-1C07", 2), "Hunter lineage 3F9A-1C07 · Generation 2", "lineage line")


func test_the_hud_names_energy_health_and_hunger_as_the_rules_count_them() -> void:
	check_eq(Hud.energy_line(_state(62.4, 30.0)), "Energy 62 / 100", "rounded")
	check_eq(Hud.energy_line(_state(0.2, 30.0)), "Energy 1 / 100", "only a starving cell shows 0")
	check_eq(Hud.energy_line(_state(0.0, 30.0)), "Energy 0 / 100", "starving")
	check_eq(Hud.health_line(_state(0.0, 12.6)), "Health 13 / 30", "health")
	check_eq(Hud.state_name(_state(25.0, 30.0)), "Fed", "a quarter full is fed")
	check_eq(Hud.state_name(_state(24.9, 30.0)), "Hungry", "below a quarter")
	check_eq(Hud.state_name(_state(0.0, 30.0)), "Starving", "empty")
	check_eq(Hud.rested_line(ActorState.fresh(_phenotype("hunter"))), "Your cell rested: Energy 60%, Health full", "after continue")


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


func test_the_perf_tour_times_frames_by_the_wall_clock_so_a_long_stall_counts_in_full() -> void:
	var script: GDScript = load(PERF_TOUR)
	var tour: Node = script.new()
	var now := 7_000_000
	check(not tour.sample(now), "the first sample starts the warm-up")
	now += int(script.WARM_UP_S * 1e6) - 1
	tour.sample(now)
	check_eq(tour.frame_ms.size(), 0, "nothing is measured during the warm-up")
	now += 1
	tour.sample(now)
	for gap_ms in [16, 400, 17]:
		now += gap_ms * 1000
		tour.sample(now)
	check_eq(tour.frame_ms, PackedFloat32Array([16.0, 400.0, 17.0]), "each frame is the wall time since the one before")
	check_near(script.summarize(tour.frame_ms).max_frame_ms, 400.0, 1e-6, "the longest frame is the whole 400 ms stall")
	var done := false
	while not done and tour.frame_ms.size() < 10000:
		now += 100_000
		done = tour.sample(now)
	var measured_ms := 0.0
	for ms in tour.frame_ms:
		measured_ms += ms
	check(done and measured_ms >= script.DURATION_S * 1000.0 and measured_ms < script.DURATION_S * 1000.0 + 100.0,
		"the tour ends once %.0f s of wall time are measured (%.3f s)" % [script.DURATION_S, measured_ms / 1000.0])
	tour.free()
