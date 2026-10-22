extends TestCase
## The words and numbers the menus and HUD show (M1 step 2). Body cards must show exactly the
## stats Phenotype.derive gives, the HUD must name the sim's energy, health and points as the
## rules count them, controls are named from the key bindings, and the death notice names the
## points the death rule took, the killer, its tip and whether the death was saved. The running
## screens are covered by the scene smoke.

const PERF_TOUR := "res://game/dev/perf_tour.gd"
const THEME := "res://game/ui/theme/pangaea_theme.tres"
const PERF_STALL_MS := 100           ## a real stall, far longer than the one-tick delta it comes with

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


## The lines `text` wraps into at `width`, as a Label with AUTOWRAP_WORD_SMART breaks them.
func _wrapped(text: String, font: Font, size: int, width: float) -> PackedStringArray:
	var para := TextParagraph.new()
	para.break_flags = Hud.WRAP_FLAGS
	para.add_string(text, font, size)
	para.width = width
	var lines := PackedStringArray()
	for i in para.get_line_count():
		var r := para.get_line_range(i)
		lines.append(text.substr(r.x, r.y - r.x))
	return lines


func test_top_center_texts_wrap_at_spaces_into_even_lines_within_the_width_they_are_given() -> void:
	var theme: Theme = load(THEME)
	var font := theme.get_font(&"font", &"Label")
	var size := theme.get_font_size(&"font_size", &"Label")
	var short := "Back at the start: 2 adaptation points lost."
	var w := Hud.wrap_width(short, font, size, 800.0)
	check(w < 800.0 and _wrapped(short, font, size, w).size() == 1, "a short message keeps its own width (%.0f px)" % w)
	var failed := "Not saved yet: Could not save to user://saves/slot_1.json: Can't open file."
	var plain := _wrapped(failed, font, size, 870.0)
	check(plain.size() == 2 and plain[1].split(" ").size() == 1, "at 870 px a plain wrap leaves one word on the last line: %s" % plain)
	w = Hud.wrap_width(failed, font, size, 870.0)
	var lines := _wrapped(failed, font, size, w)
	check(w <= 870.0 and lines.size() == 2, "a failed save wraps onto two lines within 870 px (%.0f px: %s)" % [w, lines])
	check(lines.size() == 2 and lines[1].split(" ").size() > 1, "the last line is more than one word: %s" % lines)
	check(lines.size() == 2 and lines[0].contains("user://saves/slot_1.json:"), "the save path is whole on one line: %s" % lines)
	var large := theme.get_font_size(&"font_size", &"LargeLabel")
	var banner := Hud.wrap_width(Hud.STARVING_TEXT, font, large, 800.0)
	check(banner < 800.0 and _wrapped(Hud.STARVING_TEXT, font, large, banner).size() == 2,
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
		"The lineage continues from the start of generation 1. You lost a quarter of your unspent adaptation points (−2).\n"
		+ GameSession.STARVED_TIP, "starved: the loss is already applied, and the starving tip follows")
	check_eq(Main.death_title("starved"), "Out of energy", "the title does not repeat the body")
	check_eq(Main.save_status_text({"ok": false, "error": "Could not save to x: disk full."}), "Could not save to x: disk full.", "errors as given")
	check(Main.save_status_text({"ok": true, "error": ""}).begins_with("Saved "), "a save names its time")


func test_a_kill_notice_names_the_killer_the_saved_loss_and_the_species_tip() -> void:
	var species := SpeciesCatalog.load_from()
	var reason := str(species.species.ambush_hunter.death_reason)
	var tip := str(species.species.ambush_hunter.death_tip)
	check_eq(reason, "Caught by an ambush hunter", "the ambush hunter's death reason")
	check_eq(Main.death_title("killed", reason), "Caught by an ambush hunter", "a kill's title is its reason")
	check_eq(Main.death_title("killed"), "Your cell died", "a kill with no reason (a dev kill)")
	check_eq(Main.death_title("starved", reason), "Out of energy", "starving is never a kill")
	check_eq(Main.death_title("drowned"), "Your cell died", "anything else")
	var saved := {"attempted": true, "ok": true, "error": ""}
	var text := Main.death_text("killed", 3, tip, saved, 1)
	var lines := text.split("\n")
	check_eq(lines.size(), 2, "one sentence line and a tip line: %s" % text)
	check(lines[0].contains("(−3)") and lines[0].contains("generation 1") and lines[0].ends_with("Saved."),
		"the loss, the generation and 'Saved.': %s" % lines[0])
	check(lines[0].contains("You lost") and not text.contains("You lose"), "the loss is told as already taken")
	check_eq(lines[1], tip, "the species tip on its own line")
	check(tip.contains("sideways, out of its line"), "the tip names the dodge the tests prove: %s" % tip)
	check(Main.death_text("killed", 3, tip, saved, 2).contains("generation 2"), "the generation is the save's")


func test_the_death_notice_says_whether_the_death_was_saved() -> void:
	var failed := {"attempted": true, "ok": false, "error": "Could not save to user://saves/slot_1.json: Can't open file."}
	var text := Main.death_text("killed", 3, "", failed)
	check(text.ends_with("(−3). Could not save to user://saves/slot_1.json: Can't open file.") and not text.contains("Saved."),
		"a failed save says so with its reason: %s" % text)
	check_eq(Main.death_save_line({"attempted": true, "ok": false, "error": "disk full"}), "Could not save: disk full",
		"an error without its own lead-in")
	var fallback := Main.death_text("killed", 3, "", {"attempted": false, "ok": false, "error": ""})
	check(not fallback.contains("Saved.") and not fallback.contains("Could not save") and fallback.ends_with("(−3)."),
		"no save tried (the OD1 fallback) says nothing about saving: %s" % fallback)
	check_eq(Main.death_save_line({}), "", "no save result")


func test_shelter_and_respawn_texts_count_whole_seconds() -> void:
	check_eq(Hud.grace_text(5), "Sheltered 5", "the shelter chip")
	check_eq(Hud.grace_text(1), "Sheltered 1", "its last second")
	check_eq(Main.respawn_text(5), "Back at the generation start · sheltered for 5 s.", "the continue toast")
	check_eq(Main.respawn_text(0), "Back at the generation start.", "no shelter, as in a pool without creatures")
	check_eq(Hud.shelter_seconds(null), 0, "no run")


func test_quitting_asks_first_only_about_what_would_be_lost() -> void:
	var alive := Main.quit_prompt(false, false)
	check_eq(alive.title, "Save first?", "alive")
	check_eq(_ids(alive.choices), PackedStringArray(["save_quit", "quit", "cancel"]), "alive choices")
	check_eq(alive.focus, "save_quit", "alive focus")
	var failed := Main.quit_prompt(true, true)
	check_eq(failed.body, "Your cell's death could not be saved. Quit anyway?", "a failed death save")
	check_eq(_ids(failed.choices), PackedStringArray(["quit", "cancel"]), "no save choice: the save just failed")
	check_eq(failed.focus, "cancel", "Cancel is focused")
	var fallback := Main.quit_prompt(true, false)
	check_eq(fallback.title, "Save first?", "dead, not saved (the OD1 fallback): step 2's dialog")
	check(str(fallback.body).contains("Saving is off until you continue"), "it says why there is no save: %s" % fallback.body)
	check_eq(_ids(fallback.choices), PackedStringArray(["quit", "cancel"]), "no save while dead")


func test_attack_refusals_become_hints_in_words_at_most_every_two_seconds() -> void:
	var hints := RefusalHints.new()
	var jaw := {"type": "attack_refused", "target": "c_1", "kind": "bite", "reason": "jaw is not facing it"}
	check_eq(hints.consider_attack(jaw, 1.0), "Turn your jaw toward it", "jaw")
	check_eq(hints.consider_attack(jaw, 2.9), "", "not again within two seconds")
	check_eq(hints.consider_attack(jaw, 3.0), "Turn your jaw toward it", "again after two seconds")
	check_eq(hints.consider_attack({"reason": "no spike points at it"}, 3.1), "Point a spike at it", "spikes, on their own clock")
	check_eq(hints.consider_attack({"reason": "too big to bite"}, 3.2), "Too big to bite", "too big")
	for quiet in ["out of reach", "jaw is recovering", "spikes are recovering", "not moving toward it", "needs a jaw", "needs a spike"]:
		check_eq(hints.consider_attack({"reason": quiet}, 10.0), "", "'%s' gets no hint" % quiet)
		check(PoolSim.ATTACK_QUIET_REASONS.has(quiet), "and the sim never sends '%s'" % quiet)
	for reason: String in RefusalHints.ATTACK_TEXTS:
		check(not PoolSim.ATTACK_QUIET_REASONS.has(reason), "the sim sends '%s'" % reason)
	hints.reset()
	check_eq(hints.consider_attack(jaw, 3.5), "Turn your jaw toward it", "reset forgets")


func test_the_health_bar_shows_whenever_the_cell_is_hurt_or_starving() -> void:
	check(not Hud.shows_health(_state(60.0, 30.0)), "fed and whole: no bar")
	check(Hud.shows_health(_state(60.0, 29.5)), "any damage shows it")
	check(Hud.shows_health(_state(60.0, 18.0)), "a bite shows it")
	check(Hud.shows_health(_state(0.0, 30.0)), "starving shows it")


func test_the_hurt_vignette_pulses_once_and_never_past_its_peak() -> void:
	check_near(Hud.vignette_strength(0.0), Hud.VIGNETTE_PEAK, 1e-6, "at its peak when the hit lands")
	check(Hud.VIGNETTE_PEAK <= 0.35 + 1e-6, "the peak is at most 0.35 (comfort)")
	check_near(Hud.vignette_strength(Hud.VIGNETTE_FALL_S * 0.5), Hud.VIGNETTE_PEAK * 0.5, 1e-6, "half way down")
	check_eq(Hud.vignette_strength(Hud.VIGNETTE_FALL_S), 0.0, "gone after 0.4 s")
	check_eq(Hud.vignette_strength(-0.1), 0.0, "nothing before the hit")
	var top := 0.0
	for i in 60:
		top = maxf(top, Hud.vignette_strength(i / 60.0))
	check(top <= Hud.VIGNETTE_PEAK + 1e-6, "never above the peak (%.3f)" % top)
	check(Hud.VIGNETTE_MIN_GAP_S >= Hud.VIGNETTE_FALL_S, "a pulse ends before the next may start")


func _ids(choices: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for c in choices:
		out.append(str(c[0]))
	return out


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


func test_each_perf_tour_frame_reads_the_wall_clock_not_the_process_delta() -> void:
	var script: GDScript = load(PERF_TOUR)
	var tour: Node = script.new()
	tour.sample(Time.get_ticks_usec() - int(script.WARM_UP_S * 1e6))   # a warm-up that is already over
	tour._running = true
	tour._process(1.0 / 60.0)
	OS.delay_msec(PERF_STALL_MS)
	tour._process(1.0 / 60.0)
	check(tour.frame_ms.size() == 1 and tour.frame_ms[0] >= PERF_STALL_MS,
		"a %d ms stall counts in full although the delta says one tick (%s)" % [PERF_STALL_MS, tour.frame_ms])
	tour.free()
