extends TestCase
## The threat species data (game/data/creatures_m1.json, M1 step 3) is valid, reads into the bodies,
## brain timings and fairness tables the plan sets, and every validation rule catches the mistake it
## is for: one mutated copy of the real data per rule, each reported under that rule's name.

const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"
## The two-post fixture's reader (tests/fixtures/creatures_posts_test.json).
const Habits := preload("res://tests/test_habits.gd")

var parts: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	parts = PartCatalog.load_from()
	layout = PoolLayout.load_from()


func _data(path: String = SpeciesCatalog.DEFAULT_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Errors from validate() after `change` edits a fresh copy of the real data.
func _errors_after(change: Callable) -> PackedStringArray:
	var data := _data()
	change.call(data)
	return SpeciesCatalog.from_dict(data).validate(layout, parts)


func _site(data: Dictionary, id: String) -> Dictionary:
	for s in data.sites:
		if s.id == id:
			return s
	return {}


## The errors of one rule ("Rule N (name)").
func _rule_errors(errors: PackedStringArray, number: int) -> PackedStringArray:
	var prefix := "Rule %d (%s)" % [number, SpeciesCatalog.RULE_NAMES[number]]
	var out := PackedStringArray()
	for e in errors:
		if e.begins_with(prefix):
			out.append(e)
	return out


## The mutation breaks this rule, and only this rule, so each rule is caught on its own.
func check_only_rule(errors: PackedStringArray, number: int, fragment: String = "") -> void:
	var mine := _rule_errors(errors, number)
	check(not mine.is_empty(), "rule %d is reported: %s" % [number, errors])
	check_eq(mine.size(), errors.size(), "nothing but rule %d: %s" % [number, errors])
	if not fragment.is_empty():
		check_has_error(mine, fragment)


func test_the_real_species_data_is_valid() -> void:
	var cat := SpeciesCatalog.load_from()
	var errors := cat.validate(layout, parts)
	check(errors.is_empty(), "no errors: %s" % [errors])
	check_eq(Array(cat.species_ids()), ["ambush_hunter", "elder_rammer", "lurker", "rammer"], "four species, sorted")
	check_eq(cat.sites.size(), 7, "seven sites")
	check_eq(cat.sites_of("ambush_hunter").size(), 3, "three lairs")
	check_eq(cat.sites_of("rammer").size(), 4, "four territories")
	check_eq(cat.sites[0].id, "lair_se", "sites keep the data's order")
	check_eq(cat.sites[3].home, Vector2(-2.5, -22.0), "homes are plane points")
	check_eq(cat.niche_of("ambush_hunter").role, "ambush", "the ambush niche")
	check_eq(int(cat.niche_of("rammer").cap), 4, "the territorial niche holds four")


func test_the_species_bodies_are_the_plans_sized_bodies() -> void:
	var cat := SpeciesCatalog.load_from()
	var ambush := cat.phenotype("ambush_hunter", parts)
	check_near(ambush.radius, 0.75, 1e-9, "ambush radius")
	check_near(ambush.speed, 2.749, 0.001, "ambush speed")
	check_near(ambush.max_health, 45.0, 1e-9, "ambush health")
	check_near(ambush.bite_damage, 12.0, 1e-9, "ambush bite")
	var rammer := cat.phenotype("rammer", parts)
	check_near(rammer.radius, 0.625, 1e-9, "rammer radius")
	check_near(rammer.speed, 1.840, 0.001, "rammer speed")
	check_near(rammer.max_health, 37.5, 1e-9, "rammer health")
	check_eq(rammer.spikes.size(), 4, "rammer spikes")
	check_near(cat._worst_hit(ambush), 12.0, 1e-9, "the ambush hunter's worst hit is its bite")
	check_near(cat._worst_hit(rammer), 9.6 * 1.5, 1e-6, "the rammer's: both front spikes stacked (6 + 3.6) at the 1.5 impact cap")


func test_species_genomes_have_fixed_ids_and_are_the_same_on_every_load() -> void:
	var a := SpeciesCatalog.load_from()
	var b := SpeciesCatalog.load_from()
	for id in a.species_ids():
		var g := a.genome(id)
		check_eq(g.genome_id, "species:" + id, "%s genome id" % id)
		check_eq(g.lineage_id, "species", "%s lineage id" % id)
		check_eq(JSON.stringify(g.to_dict(), "", true, true), JSON.stringify(b.genome(id).to_dict(), "", true, true),
			"%s: the same genome from another load" % id)
		check_eq(JSON.stringify(g.to_dict()), JSON.stringify(a.genome(id).to_dict()), "%s: and from the same load" % id)
		for i in g.parts.size():
			check_eq(g.parts[i].id, "part_%d" % (i + 1), "%s part %d id" % [id, i + 1])
		# Why rule 1 checks parts itself: Genome.validate wants StableId lineage ids, which a species has not.
		check_has_error(g.validate(parts), "invalid lineage id")


func test_brain_timings_are_whole_ticks_read_once_at_load() -> void:
	var cat := SpeciesCatalog.load_from()
	# The plan's tick table (section 8): notice, tell, burst, glide, recover, blocked recover, give up,
	# memory, refractory, flee, nav timeout, settle.
	var expected := {
		"ambush_hunter": [30, 72, 21, 15, 60, 60, 300, 120, 360, 240, 1200, 180],
		"rammer": [30, 72, 54, 18, 72, 120, 480, 180, 180, 300, 480, 180],
	}
	for id in expected:
		var cfg := cat.brain_config(id)
		var a: Dictionary = cfg.attack
		var got := [cfg.notice_ticks, a.tell_ticks, a.burst_ticks, a.glide_ticks, a.recover_ticks, a.blocked_recover_ticks,
			cfg.give_up_ticks, cfg.memory_ticks, cfg.refractory_ticks, cfg.flee_ticks, cfg.nav_timeout_ticks, cfg.settle_ticks]
		check_eq(got, expected[id], "%s ticks" % id)
		check_eq(cfg.species_id, id, "%s config names its species" % id)
	check_eq(cat.brain_config("rammer").rest_ticks, [240, 480], "rammer rest 4-8 s")
	check(cat.brain_config("nobody").is_empty(), "no config for an unknown species")


func test_the_fairness_tables_and_timers_are_the_plans_numbers_in_ticks() -> void:
	var cat := SpeciesCatalog.load_from()
	# test_respawn_rules uses these tables inline; this pins them to the data.
	check_eq(cat.grace_ticks, [300, 480, 600] as Array[int], "shelter 5, 8 and 10 s")
	check_eq(cat.respawn_energy_share, [0.6, 0.8, 1.0] as Array[float], "respawn energy 60, 80 and 100%")
	check_eq(cat.streak_window_ticks, 90 * 60, "streak window 90 s")
	check_eq(cat.killer_ignore_ticks, 30 * 60, "killer ignore 30 s")
	check_eq(cat.start_grace_ticks, 5 * 60, "start and continue shelter 5 s")
	check_eq(cat.spawn_retry_ticks, 60, "spawn retry 1 s")
	check_eq(cat.fade_in_ticks, 60, "fade-in 1 s")
	check_eq(float(cat.fairness.respawn_clear_m), 12.0, "respawn clear 12 m")
	check_eq(float(cat.fairness.spawn_safe_m), 20.0, "spawn safe 20 m")
	check_eq(int(cat.fairness.max_engaged_on_player), 1, "one creature engaged at a time")


func test_every_site_reaches_only_its_leash_disc_far_from_the_checkpoint() -> void:
	var cat := SpeciesCatalog.load_from()
	check_eq(cat.reach_disc(cat.site("lair_se"), layout), {"center": Vector2(26.4, 12.6), "radius": 9.0}, "a lair: home and leash")
	check_eq(cat.reach_disc(cat.site("terr_nw"), layout), {"center": Vector2(-19.1, -11.0), "radius": 11.0},
		"a territory: the zone, 6 + 2 m margin + 3 m leash")
	check_eq(cat.territory_of(cat.site("terr_n_b"), layout), {"center": Vector2(0.0, -22.0), "radius": 6.0}, "its zone's own circle")
	check(cat.territory_of(cat.site("lair_s"), layout).is_empty(), "a lair guards no territory")
	# The measured margins (plan section 0): no reachable area within 15.5 m of the checkpoint, except
	# lair_s by z_s (moved there by the step 3 review so the zones by the spawn meet a threat) at 12.81 m.
	for s in cat.sites:
		var disc := cat.reach_disc(s, layout)
		var r := cat.phenotype(s.species, parts).radius
		var clear: float = layout.spawn.distance_to(disc.center) - disc.radius - r
		check(clear >= (12.5 if s.id == "lair_s" else 15.5), "%s keeps %.2f m from the checkpoint" % [s.id, clear])


func test_an_ambush_lair_reaches_into_z_s_and_sees_it_from_home() -> void:
	# The step 3 review (pressure): z_center and z_s, the zones by the spawn, fed a cell for ever out of
	# every creature's reach. Rule 8 keeps every reach short of z_center's useful part, and F6 keeps a
	# lair from spawning while the cell is in z_s, so z_center and z_s regrow too slowly to feed a
	# cell that camps there and eats what it touches (test_threat_gates #33). z_s also gets a lair
	# whose reach (leash plus body) enters it well and whose hunter, at home, sees across its edge, so
	# a cell feeding there meets it (#32).
	var cat := SpeciesCatalog.load_from()
	var z := layout.zone("z_s")
	var watching := PackedStringArray()
	for s in cat.sites:
		if cat.behavior_of(s.species) != "ambush":
			continue
		var disc := cat.reach_disc(s, layout)
		var p := cat.phenotype(s.species, parts)
		var from_center: float = Vector2(s.home).distance_to(z.center)
		var reach_in: float = float(z.radius) + float(disc.radius) + p.radius - from_center
		var to_edge: float = from_center - float(z.radius)
		if reach_in >= 2.0 and to_edge < p.sight:
			watching.append("%s (its reach %.2f m into z_s, its home %.2f m from the edge)" % [s.id, reach_in, to_edge])
	print("test-threats-z-s-lair: %s" % ", ".join(watching))
	check(not watching.is_empty(), "an ambush lair reaches at least 2 m into z_s and sees across its edge from home")


func test_the_test_fixture_is_the_real_species_data_with_no_sites() -> void:
	var real := _data()
	var fixture := _data(TEST_SPECIES)
	check_eq(fixture.sites, [], "no sites, so tests place every creature")
	check_eq(fixture.status, "TEST FIXTURE", "marked as a fixture")
	for key in ["sites", "status", "note"]:
		real.erase(key)
		fixture.erase(key)
	# The fixture is M1's threats: S2's relationships block and the species that enter later are left
	# out of it (a test that needs them builds its catalog from the real data).
	check(not fixture.has("relationships"), "the fixture has no relationships block")
	real.erase("relationships")
	for id in real.species.keys():
		if int(real.species[id].get("entry_size", 1)) > 1:
			check(not fixture.species.has(id), "the fixture has no %s" % id)
			real.species.erase(id)
	check_eq(JSON.stringify(fixture, "", true, true), JSON.stringify(real, "", true, true), "everything else is the real data")
	var errors := SpeciesCatalog.load_from(TEST_SPECIES).validate(layout, parts)
	check(errors.is_empty(), "and it validates: %s" % [errors])


func test_wrong_types_and_missing_files_are_reported_not_crashed_on() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.rammer.notice_s = "soon"), "'notice_s' must be a number")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.erase("tell_s")), "'tell_s' is missing")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.rammer.erase("rest_s")), "a territorial species needs it")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.niche.cap = 2.5), "'cap' must be a whole number")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.sites[0].home = [1.0]), "'home' must be two numbers")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.parts[0] = "jaw"), "not an object")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.erase("fairness")), "'fairness' is missing")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.lineage = d.species.rammer), "is the player's")
	check_has_error(SpeciesCatalog.load_from("res://tests/fixtures/no_such_species.json").validate(layout, parts), "missing or not readable")
	check_has_error(SpeciesCatalog.from_dict([1, 2]).validate(layout, parts), "not an object")
	check(SpeciesCatalog.from_dict([1, 2]).configs.is_empty(), "a broken catalog builds no brain configs")


func test_rule_1_checks_each_species_genome_against_the_part_catalog() -> void:
	var five_spikes := func(d: Dictionary) -> void:
		d.species.rammer.parts.append({"type": "spike", "angle": 3.0, "scale": 0.8})
	check_only_rule(_errors_after(five_spikes), 1, "5 'spike' parts; the limit is 4")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.parts[1].type = "horn"), 1, "unknown type 'horn'")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.parts[5].scale = 0.4), 1, "outside 0.50..2.00")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.parts[1].angle = 3.3), 1, "outside -PI..PI")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.body_size = 2.1), 1), "body_size 2.10")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.rammer.body_size = 0.9), 1), "body_size 0.90")
	var no_mouth := func(d: Dictionary) -> void:
		d.species.rammer.parts.remove_at(0)
	check_has_error(_rule_errors(_errors_after(no_mouth), 1), "needs at least one 'mouth' part")
	var nine_parts := func(d: Dictionary) -> void:
		for type_id in ["eye_spot", "eye_spot", "eye_spot", "cilia", "cilia", "cilia"]:
			d.species.ambush_hunter.parts.append({"type": type_id, "angle": 1.0})
	check_has_error(_rule_errors(_errors_after(nine_parts), 1), "9 parts; the limit is 8")


func test_rule_2_needs_a_jaw_to_ambush_and_a_spike_to_ram() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.kind = "ram"), 2, "needs a jaw")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.parts[0].type = "mouth_filter"), 2),
		"needs a jaw")
	var no_spikes := func(d: Dictionary) -> void:
		d.species.rammer.parts = [d.species.rammer.parts[0], d.species.rammer.parts[5]]
	check_has_error(_rule_errors(_errors_after(no_spikes), 2), "needs a spike")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.rammer.behavior = "swarm"), 2), "'swarm' is not one of")


func test_rule_3_bounds_the_strike_and_keeps_pursuit_slower_than_every_fed_body() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.burst_speed = 6.5), 3, "tunnelling bound")
	# 0.95 x 2.749 = 2.611 m/s, above 0.9 x the omnivore's 2.720 = 2.448 m/s.
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.speeds.pursue = 0.95), 3, "pursues at 2.611 m/s, above 2.448")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.speeds.wander = 1.2), 3, "speeds.wander 1.20")
	check(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.speeds.pursue = 0.89), 3).is_empty(),
		"0.89 x 2.749 = 2.446 m/s still passes, so the bound is tight")


func test_rule_4_keeps_every_tell_notice_and_recovery_readable() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.attack.tell_s = 1.1), 4, "tell_s 1.10 s is below the 1.20 s floor")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.notice_s = 0.4), 4, "notice_s 0.40 s")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.recover_s = 0.4), 4, "recover_s 0.40 s")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.attack.blocked_recover_s = 0.3), 4, "blocked_recover_s 0.30 s")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.rammer.attack.glide_s = 0.005), 4), "shorter than one tick")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.fairness.start_grace_s = 0.0), 4), "shorter than one tick")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.niche.respawn_jitter_s = 30.0), 4, "respawn_jitter_s")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.ai.think_hz = 120), 4, "ai.think_hz")


func test_rule_5_keeps_every_single_hit_below_half_a_starting_body() -> void:
	# A bite of 12 x 1.875 / 1.5 = 15 is half of 30 health: not allowed.
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.body_size = 1.875), 5),
		"can deal 15.00 in one hit, not below 15.00")
	var full_spikes := func(d: Dictionary) -> void:
		for i in range(1, 5):
			d.species.rammer.parts[i].scale = 1.0
	# Front spikes 7.5 + 4.5 = 12, x 1.5 = 18.
	check_only_rule(_errors_after(full_spikes), 5, "can deal 18.00 in one hit")


func test_rule_6_keeps_the_strike_window_ordered_and_the_lane_inside_the_leash() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.standoff_m = 3.2), 6, "start_max_m")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.rammer.attack.start_min_m = 0.0), 6, "0 < start_min_m")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.aim_deg = 0.0), 6, "aim_deg")
	# The lunge's lane is 3.68 m: a 3.5 m leash cannot hold it.
	var short_leash := func(d: Dictionary) -> void:
		d.species.ambush_hunter.leash_m = 3.5
	check_has_error(_rule_errors(_errors_after(short_leash), 6), "strike lane 3.68 m is longer than its leash (3.50 m)")
	# The charge's 5.67 m lane still fits a rammer's 8 m territory with a 0.5 m leash.
	check(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.rammer.leash_m = 0.5), 6).is_empty(),
		"a rammer's lane counts its territory as well as its leash")


func test_rule_7_checks_every_site_and_niche() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.niche.cap = 4), 7, "niche cap 4 above its 3 sites")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_sw").species = "kraken"), 7, "unknown species 'kraken'")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_se").home = [30.0, 0.5]), 7),
		"is not a clear place")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: _site(d, "terr_n_b").home = [-1.0, -22.5]), 7),
		"sites keep 2.0 m apart")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: _site(d, "terr_ne").territory_zone = "z_nowhere"), 7, "'z_nowhere'")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: _site(d, "terr_ne").erase("territory_zone")), 7, "territory_zone ''")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_s").id = "lair_se"), 7), "empty or repeated")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.species.rammer.niche.role = "ambush"), 7),
		"share the niche role 'ambush'")


func test_rule_8_keeps_every_reachable_disc_twelve_metres_from_the_checkpoint() -> void:
	# A lair 20 m from the checkpoint (0, 9), south of the view, with its 9 m leash reaches 20 - 9 - 0.75 = 10.25 m from it.
	check_only_rule(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_se").home = [12.0, 25.0]), 8, "reach 10.25 m from the checkpoint")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.fairness.respawn_clear_m = 17.0), 8), "site 'lair_sw'")
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.fairness.spawn_safe_m = 26.0), 8), "home is 25.27 m from the checkpoint")


func test_rule_9_keeps_rocks_off_every_leash_circle() -> void:
	# The base plan's north-west rock gap lair: rock_12 lies 0.64 m from its leash circle, where the clamp would press into it.
	check_only_rule(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_s").home = [-9.6, -16.6]), 9, "rock_12 lies 0.64 m")


func test_rule_10_leaves_room_to_pass_every_rock_inside_a_disc() -> void:
	# The base plan's lair_se: rock_14 reaches into its disc 1.16 m from the soft wall, a gap a 0.75 m body wedges in.
	check_has_error(_rule_errors(_errors_after(func(d: Dictionary) -> void: _site(d, "lair_se").home = [25.8, 14.9]), 10),
		"rock_14 leaves 1.16 m to the soft wall; it needs 2.00 m")
	check(_rule_errors(_errors_after(func(d: Dictionary) -> void: d.fairness.pinch_margin_m = 0.0), 10).is_empty(),
		"the moved sites leave room even with no margin")


func test_rule_11_keeps_every_home_out_of_view_of_the_checkpoint() -> void:
	# (24, 2) is 25.2 m away and its leash disc clears the checkpoint, but the widest view covers it.
	var in_view := func(d: Dictionary) -> void:
		_site(d, "lair_se").home = [24.0, 2.0]
	check_only_rule(_errors_after(in_view), 11, "site 'lair_se' home is in view")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.fairness.spawn_view_aspect = 4.0), 11, "site 'lair_sw'")


func test_rule_12_needs_one_shelter_and_energy_entry_per_streak_never_decreasing() -> void:
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.fairness.grace_s = [5.0, 8.0]), 12, "the same length")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.fairness.grace_s = [5.0, 4.0, 10.0]), 12, "grace_s must not decrease")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.fairness.respawn_energy_share = [0.6, 0.5, 1.0]), 12,
		"respawn_energy_share must not decrease")
	check_only_rule(_errors_after(func(d: Dictionary) -> void: d.fairness.respawn_energy_share = [0.6, 0.8, 1.2]), 12, "(0, 1]")
	var empty := func(d: Dictionary) -> void:
		d.fairness.grace_s = []
		d.fairness.respawn_energy_share = []
	check_only_rule(_errors_after(empty), 12, "at least 1")


func test_rule_13_refuses_unknown_keys_so_a_removed_tuning_knob_cannot_return() -> void:
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter.attack.homing_deg_s = 90.0),
		"Rule 13 (unknown key): species 'ambush_hunter' attack has an unknown key 'homing_deg_s'")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.rammer.tell_turn_share = 0.5),
		"Rule 13 (unknown key): species 'rammer' has an unknown key 'tell_turn_share'")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.sites[2].leash_m = 12.0), "Rule 13 (unknown key): site 'lair_s'")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.fairness.grace = [1.0]), "Rule 13 (unknown key): fairness")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.rammer.niche.max = 9), "Rule 13 (unknown key): species 'rammer' niche")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.species.rammer.parts[0].size = 2), "Rule 13 (unknown key): species 'rammer' part")
	check_has_error(_errors_after(func(d: Dictionary) -> void: d.extra = true), "Rule 13 (unknown key): the species data")


# --- the S1 extractions (docs/s1/s1-interfaces.md 3.8): the endless world checks its tiles with them ---

## territory_from and reach_disc_for, given the layout's zone, are the layout versions; and they
## follow the site and zone into any frame, which is what a tile placed far out needs.
func test_territory_from_and_reach_disc_for_equal_the_layout_versions_for_every_m1_site() -> void:
	var cat := SpeciesCatalog.load_from()
	var shift := Vector2(4096.0, -2048.0)
	for s in cat.sites:
		var zone := layout.zone(str(s.get("territory_zone", "")))
		var territory := cat.territory_from(s, zone)
		check_eq(territory, cat.territory_of(s, layout), "%s: the territory" % s.id)
		# The brain's own leash disc, built as reach_disc built it before the extraction.
		var cfg := cat.brain_config(str(s.species))
		var mem := CreatureBrain.create(cfg.behavior, cfg, s.home, float(s.heading), territory, 0, 0)
		check_eq(cat.reach_disc_for(s, territory), CreatureBrain.leash_disc(mem), "%s: the reach disc" % s.id)
		check_eq(cat.reach_disc(s, layout), cat.reach_disc_for(s, territory), "%s: reach_disc delegates" % s.id)
		var moved := s.duplicate()
		moved.home = Vector2(s.home) + shift
		var moved_zone := {} if zone.is_empty() else {"center": Vector2(zone.center) + shift, "radius": zone.radius}
		var disc := cat.reach_disc_for(moved, cat.territory_from(moved, moved_zone))
		check_eq(disc.radius, cat.reach_disc(s, layout).radius, "%s: the same radius anywhere" % s.id)
		check(Vector2(disc.center).is_equal_approx(Vector2(cat.reach_disc(s, layout).center) + shift), "%s: the centre moves with the site" % s.id)
	check(cat.territory_from(cat.site("terr_ne"), {}).is_empty(), "no zone, no territory")
	check(cat.territory_from(cat.site("lair_s"), layout.zone("z_s")).is_empty(), "an ambush site guards none, even given a zone")


func test_strike_room_problem_gives_rule_6s_message() -> void:
	var cat := SpeciesCatalog.load_from()
	for id in cat.species_ids():
		check_eq(cat.strike_room_problem(id, 6.0, "species '%s'" % id, parts), "", "%s: the M1 lane fits" % id)
	var data := _data()
	data.species.ambush_hunter.leash_m = 3.5
	var short := SpeciesCatalog.from_dict(data)
	var text := short.strike_room_problem("ambush_hunter", 6.0, "species 'ambush_hunter'", parts)
	check_eq(text, "species 'ambush_hunter' strike lane 3.68 m is longer than its leash (3.50 m).", "the leash case")
	check(short.validate(layout, parts).has("Rule 6 (strike window): " + text), "rule 6 reports exactly that text")
	# A rammer counts its smallest territory plus the margin: 5.67 m against 0.5 + 2 + territory.
	data = _data()
	data.species.rammer.leash_m = 0.5
	var rammer := SpeciesCatalog.from_dict(data)
	check_eq(rammer.strike_room_problem("rammer", 6.0, "species 'rammer'", parts), "", "an 8.5 m room holds the lane")
	check_eq(rammer.strike_room_problem("rammer", 3.0, "species 'rammer'", parts),
		"species 'rammer' strike lane 5.67 m is longer than its smallest territory plus its leash (5.50 m).", "a 3 m territory does not")
	check_eq(cat.strike_room_problem("kraken", 6.0, "x", parts), "", "an unknown species is rule 7's to report")


## Rules 9 and 10 for one disc: the same messages as the layout's, and an infinite wall drops only
## the wall gap (the endless world has no wall).
func test_check_disc_against_shells_with_an_infinite_wall_skips_only_the_wall_gap() -> void:
	var cat := SpeciesCatalog.load_from()
	var disc := {"center": Vector2.ZERO, "radius": 9.0}
	var r := 0.75
	var shells: Array[Dictionary] = [
		{"id": "on_circle", "center": Vector2(9.5, 0.0), "radius": 1.0},     # rule 9: 0.50 - 1.0 = -0.50 m from the circle
		{"id": "by_wall", "center": Vector2(0.0, 7.0), "radius": 1.0},       # rule 10: 1.00 m to a wall at 9
		{"id": "pinch_a", "center": Vector2(-3.0, 0.0), "radius": 1.0},      # rule 10: 1.00 m between pinch_a and pinch_b
		{"id": "pinch_b", "center": Vector2(-6.0, 0.0), "radius": 1.0},
	]
	var walled := PackedStringArray()
	cat.check_disc_against_shells("site 'x'", disc, r, shells, 9.0, walled)
	var open := PackedStringArray()
	cat.check_disc_against_shells("site 'x'", disc, r, shells, INF, open)
	check_has_error(walled, "Rule 9 (")
	check_has_error(walled, "site 'x': on_circle lies -0.50 m from its leash circle")
	check_has_error(walled, "site 'x': by_wall leaves 1.00 m to the soft wall; it needs 2.00 m.")
	check_has_error(walled, "site 'x': pinch_a leaves 1.00 m to pinch_b; it needs 2.00 m.")
	check_has_error(walled, "site 'x': pinch_b leaves 1.00 m to pinch_a; it needs 2.00 m.")
	var expected := PackedStringArray()
	for e in walled:
		if not e.contains("soft wall"):
			expected.append(e)
	check_eq(open, expected, "an infinite wall drops the wall gaps and nothing else")
	check(walled.size() > open.size(), "there was a wall gap to drop")
	# The layout's own rules 9 and 10 go through it: rule 9's case reports the same text.
	var data := _data()
	_site(data, "lair_s").home = [-9.6, -16.6]
	var moved := SpeciesCatalog.from_dict(data)
	var direct := PackedStringArray()
	var s := moved.site("lair_s")
	moved.check_disc_against_shells("site 'lair_s'", moved.reach_disc(s, layout), moved.phenotype(s.species, parts).radius,
		layout.rocks, layout.soft_start, direct)
	check_eq(_rule_errors(moved.validate(layout, parts), 9), _rule_errors(direct, 9), "the layout's rule 9 is this check")


# --- S2: the growth ladder (s2-sim 3.2; S2G2, S2G3, S2G29) ---

## Every relationship rule on, as spine 4.2's block.
const RELATIONSHIPS := {"rules": {"prey_share": true, "intruder_share": true, "fear": true, "no_engage_above": true,
	"outgrown_hazards": true}, "prey_share": 1.0, "intruder_max_radius_share": 1.2, "fear_radius_share": 1.25,
	"tolerance": 1e-6}


## The real data (T1.7): the relationships block and the two size-2 species built on the M1 ones
## (spine 4.2), the two-post ambush "lurker" and the two-post territorial "elder_rammer".
func _s2_data() -> Dictionary:
	return _data()


func test_the_s2_species_are_their_m1_kin_but_for_what_spine_4_2_names() -> void:
	var data := _data()
	check_eq(data.relationships, RELATIONSHIPS, "spine 4.2's relationships block, every rule on")
	var own := {
		"lurker": {"kin": "ambush_hunter", "name": "Lurker", "death_reason": "Caught by a Lurker", "entry_size": 2.0,
			"body_asset": "creature_lurker_body", "niche": {"role": "lurker", "cap": 0.0, "respawn_s": 60.0, "respawn_jitter_s": 10.0},
			"habit": {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}},
		"elder_rammer": {"kin": "rammer", "name": "elder rammer", "death_reason": "Rammed by an elder rammer", "entry_size": 2.0,
			"body_asset": "creature_elder_rammer_body", "nav_timeout_s": 16.0,
			"niche": {"role": "elder_rammer", "cap": 0.0, "respawn_s": 60.0, "respawn_jitter_s": 10.0},
			"habit": {"post_switch": "nearer_cell", "post_hysteresis_m": 2.0}},
	}
	for id in own:
		var block: Dictionary = data.species[id].duplicate(true)
		var kin: Dictionary = data.species[own[id].kin].duplicate(true)
		for key in own[id]:
			if key == "kin":
				continue
			check_eq(block[key], own[id][key], "%s.%s" % [id, key])
		check(str(block.death_tip).begins_with("Lurkers keep two lairs in the reefs." if id == "lurker" else "Elder rammers guard two feasts."),
			"%s: spine 4.2's tip first: %s" % [id, block.death_tip])
		for key in own[id].keys() + ["death_tip"]:
			block.erase(key)
			kin.erase(key)
		if id == "lurker":
			check_eq(block.senses.fov_deg, 300.0, "the Lurker's wide sight")
			block.senses.erase("fov_deg")
			kin.senses.erase("fov_deg")
		check_eq(JSON.stringify(block, "", true, true), JSON.stringify(kin, "", true, true), "every other number of %s is the %s's" % [id, own[id].kin])
	check_eq(data.sites.filter(func(s: Dictionary) -> bool: return s.species == "lurker" or s.species == "elder_rammer"), [],
		"neither has a pool site")


func _s2_errors_after(change: Callable) -> PackedStringArray:
	var data := _s2_data()
	change.call(data)
	return SpeciesCatalog.from_dict(data).validate(layout, parts)


func test_s2_species_and_the_relationships_block_validate() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	var errors := cat.validate(layout, parts)
	check(errors.is_empty(), "no errors: %s" % [errors])
	check_eq(cat.relationships_cfg(), RELATIONSHIPS, "the block as written")


func test_entry_size_defaults_to_one_and_q_is_exact_on_the_ladder() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	check_eq(cat.entry_size("ambush_hunter"), 1, "an M1 species names none: 1")
	check_eq(cat.entry_size("lurker"), 2, "the data's")
	check_eq(cat.entry_size("kraken"), 1, "an unknown species: 1")
	check_eq(cat.q_of("rammer", 1), 1.0, "at its entry size")
	check_eq(cat.q_of("rammer", 2), 0.625, "one size up")
	check_eq(cat.q_of("rammer", 3), 0.390625, "two sizes up, exactly")
	check_eq(cat.q_of("lurker", 2), 1.0, "a size-2 species at size 2")
	check_eq(cat.q_of("lurker", 3), 0.625, "and one size up")
	check_eq(cat.q_of("lurker", 1), 1.6, "seen from below (a ghost)")


func test_live_at_runs_from_the_entry_size_until_the_species_is_haze() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	# rel at n: the rammer 1.25 x 0.625^(n - 1), haze below 0.25 (n = 5: 0.191); the ambush hunter
	# 1.5 x 0.625^(n - 1) (n = 5: 0.229); the Lurker one size later.
	var live := {"rammer": [1, 2, 3, 4], "ambush_hunter": [1, 2, 3, 4], "lurker": [2, 3, 4, 5], "elder_rammer": [2, 3, 4, 5]}
	for id in live:
		for n in range(1, 8):
			check_eq(cat.live_at(id, n, parts), n in live[id], "%s at size %d" % [id, n])
	check(not cat.live_at("kraken", 1), "an unknown species lives nowhere")
	check_eq(str(cat.at_size("ambush_hunter", 5, parts).ladder_role), "haze", "where it ends: haze")
	check_eq(str(cat.at_size("rammer", 4, parts).ladder_role), "morsel", "a morsel still lives")


func test_habit_of_is_the_species_habit() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	check_eq(cat.habit_of("lurker"), {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}, "the Lurker's")
	check(cat.habit_of("rammer").is_empty(), "an M1 species has none")
	check(cat.habit_of("kraken").is_empty(), "nor an unknown one")


## The record at the entry size is the species' own: every field of its body, its brain config, its
## senses and carcass rings, bit for bit.
func test_at_size_at_the_entry_size_is_the_species_own_record() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	for id in cat.species_ids():
		var c := cat.entry_size(id)
		var rec := cat.at_size(id, c, parts)
		var own := cat.phenotype(id, parts)
		var p: Phenotype = rec.phenotype
		for prop in own.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				check_eq(p.get(prop.name), own.get(prop.name), "%s: %s" % [id, prop.name])
		check_eq(rec.cfg, cat.brain_config(id), "%s: the brain config" % id)
		check_eq(rec.q, 1.0, "%s: q" % id)
		check_eq(rec.reach_scale, 1.0, "%s: reach scale" % id)
		check_eq(rec.ladder_role, "threat", "%s: a threat" % id)
		check_eq(rec.rel, own.radius / 0.5, "%s: rel" % id)
		check_eq(rec.sight, own.sight, "%s: sight" % id)
		check_eq(rec.near_m, float(cat.species[id].senses.near_m), "%s: near" % id)
		check_eq(rec.fov, deg_to_rad(float(cat.species[id].senses.fov_deg)), "%s: field of view" % id)
		check_eq(rec.carcass_rings, CreatureField.CARCASS_RINGS_M, "%s: the carcass rings" % id)
		check_eq(rec.flee_share, float(cat.species[id].speeds.flee), "%s: flee share" % id)


func test_at_size_above_the_entry_scales_body_cfg_senses_and_rings_by_q() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	var rec := cat.at_size("rammer", 2, parts)
	var q := 0.625
	var p: Phenotype = rec.phenotype
	check_eq(rec.q, q, "q")
	check_eq(p.radius, 0.390625, "radius 0.625 x 0.625")
	check_eq(p.speed, cat.phenotype("rammer", parts).speed * q, "speed x q")
	check_eq(rec.cfg, CreatureBrain.scale_cfg(cat.brain_config("rammer"), q), "cfg: scale_cfg at q")
	check_eq(float(rec.cfg.leash_m), 3.0 * q, "the leash in tm at size 2")
	check_eq(rec.near_m, 0.8 * q, "near sense x q")
	check_eq(rec.sight, p.sight, "sight from the scaled body")
	check_eq(rec.carcass_rings, [0.45 * q, 0.9 * q], "carcass rings x q (D-27)")
	check_eq(rec.reach_scale, q, "the resolver's reach scale")
	check_eq(rec.rel, 0.78125, "rel")
	check_eq(rec.ladder_role, "prey", "a rammer is prey at size 2")
	check_eq(str(cat.at_size("ambush_hunter", 2, parts).ladder_role), "rival", "an ambush hunter a rival (rel 0.9375)")
	check(is_same(cat.at_size("rammer", 2, parts), rec), "memoised per (species, size)")
	check(not is_same(cat.at_size("rammer", 3, parts), rec), "another size, another record")


func test_at_size_has_no_record_below_the_entry_size() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	check(cat.at_size("lurker", 1, parts).is_empty(), "the Lurker is a ghost at size 1, with no record")
	check(cat.at_size("kraken", 1, parts).is_empty(), "nor an unknown species")


func test_the_relationships_block_reaches_every_brain_config() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	check_eq(float(cat.brain_config("ambush_hunter").prey_max_radius_share), 1.0, "rule 1: the block's prey share")
	check_eq(float(cat.brain_config("rammer").intruder_max_radius_share), 1.2, "rule 2")
	check_eq(float(cat.brain_config("rammer").fear_radius_share), 1.25, "rule 3")
	check(bool(cat.brain_config("lurker").engage_rule), "rule 4")
	check_eq(cat.brain_config("elder_rammer").post_switch, "nearer_cell", "the habit")
	var none := _data()
	none.erase("relationships")
	var off := SpeciesCatalog.from_dict(none)
	check(off.relationships_cfg().is_empty(), "no block")
	check_eq(float(off.brain_config("ambush_hunter").prey_max_radius_share), 1.6, "every rule off: M1's share")
	check(is_inf(float(off.brain_config("rammer").fear_radius_share)), "and no fear")


## D-39: reach_disc_for at k is the leash disc of a brain whose cfg is scale_cfg(cfg, k), bit for bit,
## for every M1 site, with its zone and with none.
func test_reach_disc_for_at_k_is_the_leash_disc_of_the_brain_scaled_by_k() -> void:
	var cat := SpeciesCatalog.load_from()
	for k in [1.0, 1.6, 0.625, 0.390625]:
		for s in cat.sites:
			var cfg := CreatureBrain.scale_cfg(cat.brain_config(str(s.species)), k)
			for territory in [cat.territory_of(s, layout), {}]:
				var mem := CreatureBrain.create(cfg.behavior, cfg, s.home, float(s.heading), territory, 0, 0)
				check_eq(cat.reach_disc_for(s, territory, k), CreatureBrain.leash_disc(mem),
					"%s at k %s, %s" % [s.id, k, "its zone" if not territory.is_empty() else "no zone"])
		check_eq(cat.reach_disc_for(cat.site("lair_se"), {}, k).radius, 9.0 * k, "a lair's leash x k (%s)" % k)
	var s := cat.site("terr_nw")
	check_eq(cat.reach_disc_for(s, cat.territory_of(s, layout)), cat.reach_disc_for(s, cat.territory_of(s, layout), 1.0),
		"k defaults to 1")
	check_eq(cat.reach_disc_for(s, cat.territory_of(s, layout), 1.6).radius, 6.0 + (2.0 + 3.0) * 1.6,
		"a size-2 rammer's zone keeps its radius; margin and leash x 1.6")


func test_two_post_disc_for_is_the_union_of_its_posts_discs() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	var lurker := {"id": "lk", "species": "lurker", "home": Vector2(-9.0, 6.0), "heading": 0.6}
	var post_b := {"home": Vector2(-1.0, 10.5), "heading": 2.4}
	var k := 1.6
	var disc := cat.two_post_disc_for(lurker, {}, post_b, {}, k)
	var a := cat.reach_disc_for(lurker, {}, k)
	var b := cat.reach_disc_for({"species": "lurker", "home": post_b.home, "heading": post_b.heading}, {}, k)
	check_eq(disc.posts, [a, b], "each post's own disc")
	check_eq({"center": disc.center, "radius": disc.radius}, CreatureBrain.union_disc(a, b), "their union (D-82)")
	var d := Vector2(-9.0, 6.0).distance_to(Vector2(-1.0, 10.5))
	check_near(float(disc.radius), (d + 2.0 * 9.0 * k) / 2.0, 1e-5, "two equal discs: half the span")
	for p in disc.posts:
		check(Vector2(p.center).distance_to(disc.center) + float(p.radius) <= float(disc.radius) + 1e-4, "it holds each post's disc")
	var elder := {"id": "er", "species": "elder_rammer", "home": Vector2(6.0, -4.0), "heading": 3.1}
	var za := {"center": Vector2(6.0, -4.0), "radius": 3.0}
	var zb := {"center": Vector2(14.0, 6.0), "radius": 2.0}
	var two := cat.two_post_disc_for(elder, za, {"home": Vector2(14.0, 6.0), "heading": 1.2}, zb, k)
	check_eq(two.posts[0].radius, 3.0 + 5.0 * k, "a territorial post: its zone, margin and leash")
	check_eq(two.posts[1].center, Vector2(14.0, 6.0), "the second post's zone")
	check(cat.two_post_disc_for({"species": "kraken", "home": Vector2.ZERO, "heading": 0.0}, {}, post_b, {}).is_empty(),
		"an unknown species has none")


func test_rule_15_a_species_one_size_past_its_entry_cannot_attack_the_cell() -> void:
	# The Lurker: 0.75 x 0.625 x 1.0 = 0.46875 < 0.5; at body_size 1.64, 0.82 x 0.625 = 0.5125 is not.
	check_only_rule(_s2_errors_after(func(d: Dictionary) -> void: d.species.lurker.body_size = 1.64), 15, "species 'lurker'")
	# Within the tolerance below 0.5 is still "can attack": radius 0.7999992 x 0.625 = 0.4999995.
	check_only_rule(_s2_errors_after(func(d: Dictionary) -> void: d.species.lurker.body_size = 1.5999984), 15, "0.499999")
	# The elder rammer: 0.625 x 0.625 x 1.2 = 0.46875; at 1.34, 0.67 x 0.625 x 1.2 = 0.5025 (rule 5 also
	# refuses that body: its spikes would hit too hard).
	check_has_error(_rule_errors(_s2_errors_after(func(d: Dictionary) -> void: d.species.elder_rammer.body_size = 1.34), 15),
		"species 'elder_rammer' one size past its entry reaches radius 0.418750 x intruder_max_radius_share 1.20")
	check_only_rule(_s2_errors_after(func(d: Dictionary) -> void: d.relationships.intruder_max_radius_share = 1.3), 15,
		"species 'elder_rammer'")
	check_only_rule(_s2_errors_after(func(d: Dictionary) -> void: d.erase("relationships")), 15, "needs the relationships block")
	# A size-1 species is never outgrown in this sense: the M1 ones pass with any shares.
	check(_rule_errors(_s2_errors_after(func(d: Dictionary) -> void: d.relationships.prey_share = 1.9), 15).size() == 1,
		"only the Lurker answers to the prey share")


## S2G29: every new block refuses unknown and missing keys and wrong kinds, and its values.
func test_the_s2_keys_refuse_unknown_missing_and_wrong_values() -> void:
	var cases := [
		[func(d: Dictionary) -> void: d.relationships.speed_share = 1.0, "Rule 13 (unknown key): relationships has an unknown key 'speed_share'"],
		[func(d: Dictionary) -> void: d.relationships.rules.size_share = true, "Rule 13 (unknown key): relationships rules has an unknown key"],
		[func(d: Dictionary) -> void: d.relationships.rules.erase("fear"), "relationships rules: 'fear' is missing"],
		[func(d: Dictionary) -> void: d.relationships.rules.fear = 1, "'fear' must be true or false"],
		[func(d: Dictionary) -> void: d.relationships.erase("tolerance"), "relationships: 'tolerance' is missing"],
		[func(d: Dictionary) -> void: d.relationships.prey_share = "one", "'prey_share' must be a number"],
		[func(d: Dictionary) -> void: d.relationships = [1], "'relationships' must be an object"],
		[func(d: Dictionary) -> void: d.relationships.fear_radius_share = 0.0, "relationships: fear_radius_share must be above 0"],
		[func(d: Dictionary) -> void: d.relationships.tolerance = 0.01, "relationships: tolerance 0.01 is not in"],
		[func(d: Dictionary) -> void: d.species.lurker.entry_size = 2.5, "'entry_size' must be a whole number"],
		[func(d: Dictionary) -> void: d.species.lurker.entry_size = 0, "entry_size 0 is outside 1..10"],
		[func(d: Dictionary) -> void: d.species.lurker.entry_size = 11, "entry_size 11 is outside 1..10"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.lair_s = 3.0, "Rule 13 (unknown key): species 'lurker' habit"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.erase("post_switch"), "species 'lurker' habit: 'post_switch' is missing"],
		[func(d: Dictionary) -> void: d.species.lurker.habit = "lairs", "'habit' must be an object"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.post_switch = "wander", "habit.post_switch 'wander' is not one of"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.post_switch = "nearer_cell", "'nearer_cell' needs behavior 'territorial'"],
		[func(d: Dictionary) -> void: d.species.elder_rammer.habit.post_switch = "out_of_sight", "'out_of_sight' needs behavior 'ambush'"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.erase("post_rest_s"), "'out_of_sight' needs post_rest_s above 0"],
		[func(d: Dictionary) -> void: d.species.elder_rammer.habit.post_hysteresis_m = 0.0, "'nearer_cell' needs post_hysteresis_m above 0"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.post_rest_s = 0.001, "habit.post_rest_s 0.0010 s is shorter than one tick"],
		[func(d: Dictionary) -> void: d.species.lurker.habit.trail_s = 0.0, "habit.trail_s must be above 0"],
	]
	for c in cases:
		check_has_error(_s2_errors_after(c[0]), c[1])


func test_strike_room_problem_at_a_size_uses_the_record_at_that_size() -> void:
	var cat := SpeciesCatalog.from_dict(_s2_data())
	for id in cat.species_ids():
		for n in range(cat.entry_size(id), cat.entry_size(id) + 3):
			check_eq(cat.strike_room_problem(id, 6.0 * cat.q_of(id, n), "x", parts, n), "", "%s at size %d: the lane fits" % [id, n])
	var data := _data()
	data.species.ambush_hunter.leash_m = 3.6
	var short := SpeciesCatalog.from_dict(data)
	check_eq(short.strike_room_problem("ambush_hunter", 6.0, "x", parts, 1), "x strike lane 3.68 m is longer than its leash (3.60 m).",
		"at the entry size it is rule 6's own check")
	check_eq(short.strike_room_problem("ambush_hunter", 6.0, "x", parts, 1), short.strike_room_problem("ambush_hunter", 6.0, "x", parts),
		"the same text as with no size")
	# At size 2 the lunge's lane is (2.129 travel + 0.75 radius + 0.3 reach) x 0.625 + 0.5 for the cell,
	# whose radius is 0.5 tm at every size: 2.49 tm. The leash is 3.6 x 0.625 = 2.25 tm.
	check_eq(short.strike_room_problem("ambush_hunter", 6.0, "x", parts, 2), "x strike lane 2.49 m is longer than its leash (2.25 m).",
		"at size 2: the scaled lane against the scaled leash")


# --- two-post sites at q = 1 (S2G4) ---

## Rules 9 and 10 for the fixture's site `site` against `rocks`, on each post's disc and the union.
func _two_post_errors(cat: SpeciesCatalog, site: Dictionary, rocks: Array[Dictionary], wall_r: float) -> PackedStringArray:
	var two := cat.two_post_disc_for(site, site.territory, site.post_b, site.post_b.territory)
	var errors := PackedStringArray()
	cat.check_two_post_discs("site '%s'" % site.id, two, cat.phenotype(site.species, parts).radius, rocks, wall_r, errors)
	return errors


func test_the_two_post_fixture_keeps_rules_6_9_and_10_on_each_post_and_their_union() -> void:
	var cat := SpeciesCatalog.load_from()
	var fx := Habits.posts_fixture()
	check_eq(fx.sites.size(), 2, "a Lurker and an elder rammer")
	for site: Dictionary in fx.sites:
		var id: String = site.species
		check(not cat.habit_of(id).is_empty(), "%s keeps a habit" % id)
		check_eq(_two_post_errors(cat, site, fx.rocks, fx.soft_start), PackedStringArray(), "%s: rules 9 and 10 hold" % site.id)
		# Rule 6 at q = 1: the strike lane fits each post's room (its leash, or its zone and leash).
		for t: Dictionary in [site.territory, site.post_b.territory]:
			var smallest := float(t.get("radius", 0.0))
			check_eq(cat.strike_room_problem(id, smallest, "site '%s'" % site.id, parts), "", "%s: the lane fits the post" % site.id)
		# D-61's spacing at q = 1, and the elder rammer's move within 0.8 of its navigation timeout.
		var apart: float = Vector2(site.home).distance_to(site.post_b.home)
		var p := cat.phenotype(id, parts)
		if id == "lurker":
			check(apart >= 4.0 and apart <= 6.0, "the Lurker's posts are 4 to 6 m apart (%.2f)" % apart)
		else:
			check(apart >= 6.0 and apart <= 10.5, "the elder rammer's posts are 6 to 10.5 m apart (%.2f)" % apart)
			var travel := apart / (p.speed * float(cat.species[id].speeds.wander))
			check(travel <= 0.8 * float(cat.species[id].nav_timeout_s), "its move takes %.1f s, under 0.8 x %.0f s" % [travel, cat.species[id].nav_timeout_s])
			check(Vector2(site.territory.center).distance_to(site.post_b.territory.center) > 2.0 * float(site.territory.radius),
				"its two zones do not overlap")


func test_a_shell_near_the_union_circle_or_pinching_inside_the_union_is_caught_though_both_posts_are_clear() -> void:
	var cat := SpeciesCatalog.load_from()
	var fx := Habits.posts_fixture()
	for site: Dictionary in fx.sites:
		var two := cat.two_post_disc_for(site, site.territory, site.post_b, site.post_b.territory)
		var center: Vector2 = two.center
		var a: Vector2 = two.posts[0].center
		var side := (Vector2(two.posts[1].center) - a).orthogonal().normalized()
		var along := (Vector2(two.posts[1].center) - a).normalized()
		# Rule 9: a shell on the union circle, square to the posts' line, is far from both post circles.
		var on_circle: Array[Dictionary] = [{"id": "edge", "center": center + side * float(two.radius), "radius": 0.5}]
		var errors := _two_post_errors(cat, site, on_circle, INF)
		check_eq(errors.size(), 1, "%s: one problem: %s" % [site.id, errors])
		check_has_error(errors, "Rule 9 (leash band): site '%s' the union: edge" % site.id)
		# Rule 9 on one post's circle where it lies deep inside the other post's disc and the union.
		for i in 2:
			var c: Vector2 = two.posts[i].center
			var toward: Vector2 = (Vector2(two.posts[1 - i].center) - c).normalized()
			var inner: Array[Dictionary] = [{"id": "inner", "center": c + toward * float(two.posts[i].radius), "radius": 0.3}]
			errors = _two_post_errors(cat, site, inner, INF)
			check_eq(errors.size(), 1, "%s: one problem: %s" % [site.id, errors])
			check_has_error(errors, "Rule 9 (leash band): site '%s' post %s: inner" % [site.id, "a" if i == 0 else "b"])
		# Rule 10: two shells inside the union, out of both posts' reach, with a gap no body passes.
		if site.species == "elder_rammer":
			var deep := center + side * 13.0
			var pinch: Array[Dictionary] = [{"id": "p1", "center": deep - along * 0.9, "radius": 0.4},
				{"id": "p2", "center": deep + along * 0.9, "radius": 0.4}]
			errors = _two_post_errors(cat, site, pinch, INF)
			check_eq(errors.size(), 2, "%s: the pinch, both ways: %s" % [site.id, errors])
			check_has_error(errors, "Rule 10 (pinch): site '%s' the union: p1 leaves 1.00 m to p2" % site.id)


# --- S3: the hazard behavior (s3-sim 3.2; S3G9, S3G9b, S3G9c, S3G9d) ---

const HAZARD_SPECIES := "res://tests/fixtures/creatures_hazard_test.json"


## Errors from validate() after `change` edits a fresh copy of the hazard fixture.
func _hazard_errors_after(change: Callable) -> PackedStringArray:
	var data := _data(HAZARD_SPECIES)
	change.call(data.species.hazard_test)
	return SpeciesCatalog.from_dict(data).validate(layout, parts)


func test_the_hazard_fixture_is_valid_and_reads_its_drift_and_threads() -> void:
	var cat := SpeciesCatalog.load_from(HAZARD_SPECIES)
	var errors := cat.validate(layout, parts)
	check(errors.is_empty(), "no errors: %s" % [errors])
	check_eq(cat.behavior_of("hazard_test"), "hazard", "a hazard")
	check_eq(float(cat.hazard_of("hazard_test").threads.damage), 5.0, "hazard_of is the data block")
	check_eq(cat.hazard_of("rammer"), {}, "no hazard block for a rammer")
	check_eq(cat.hazard_cooldown_ticks(), 75, "1.25 s of cooldown")
	check_eq(SpeciesCatalog.load_from().hazard_cooldown_ticks(), 0, "none without a hazard")
	var cfg := cat.brain_config("hazard_test")
	check_eq(cfg.drift, {"radius_m": 3.0, "period_ticks": [2220, 3180]}, "the drift in ticks (D-124)")
	check_eq(cfg.threads, {"count": 4, "length_m": 2.4, "radius_m": 0.35, "damage": 5.0, "cooldown_ticks": 75,
		"knockback": 1.5}, "the threads in ticks")
	check(not cat.brain_config("rammer").has("drift") and not cat.brain_config("rammer").has("threads"),
		"other species carry no hazard keys")
	var half: Dictionary = CreatureBrain.scale_cfg(cfg, 0.625)
	check_eq(float(half.threads.length_m), 2.4 * 0.625, "thread lengths scale")
	check_eq(float(half.threads.damage), 5.0, "damage is kept")
	check_eq(half.drift.period_ticks, [2220, 3180], "periods are kept")


func test_each_rule_14_clause_catches_its_mistake_alone() -> void:
	var cases := [
		["(a) a fast flee", func(b: Dictionary) -> void: b.speeds.flee = 0.6, "speeds.flee gives"],
		["(b) a sting at the two-hit limit", func(b: Dictionary) -> void: b.hazard.threads.damage = 7.5, "stings 7.50 x 2"],
		["(c) six threads", func(b: Dictionary) -> void: b.hazard.threads.count = 6, "count 6 is outside 3..5"],
		["(d) the spine's leash 7.0", func(b: Dictionary) -> void: b.leash_m = 7.0, "leash_m 7.000 is outside 4.743..5.243"],
		["(d) a leash inside the corner", func(b: Dictionary) -> void: b.leash_m = 4.7, "leash_m 4.700 is outside"],
		["(e) a metabolism", func(b: Dictionary) -> void: b.metabolism_share = 0.1, "metabolism_share must be 0"],
		["(f) a fast drift", func(b: Dictionary) -> void: b.hazard.drift.period_s = [20.0, 20.0], "drifts at up to 1.3329"],
		["a zero thread length", func(b: Dictionary) -> void: b.hazard.threads.length_m = 0.0, "threads.length_m must be above 0"],
		["a zero drift radius", func(b: Dictionary) -> void: b.hazard.drift.radius_m = 0.0, "drift.radius_m must be above 0"],
	]
	for c in cases:
		var errors := _hazard_errors_after(c[1])
		check_only_rule(errors, 14, c[2])


func test_the_hazard_schema_refuses_what_a_hazard_has_not() -> void:
	var refused := {"attack": SpeciesCatalog.load_from().species.ambush_hunter.attack, "prey_max_radius_share": 1.6,
		"intruder_min_radius": 0.3, "forage_radius_m": 18.0, "forage_timeout_s": 30.0, "forage_retry_s": 20.0,
		"territory_margin_m": 2.0, "territory_exit_m": 1.0, "rest_s": [4.0, 8.0]}
	for key in refused:
		var data := _data(HAZARD_SPECIES)
		data.species.hazard_test[key] = refused[key]
		var cat := SpeciesCatalog.from_dict(data)
		check_has_error(PackedStringArray(cat.load_problems), "species 'hazard_test': a hazard species has no '%s'." % key)
	var data := _data(HAZARD_SPECIES)
	data.species.hazard_test.erase("hazard")
	check_has_error(PackedStringArray(SpeciesCatalog.from_dict(data).load_problems),
		"species 'hazard_test': 'hazard' is missing (a hazard species needs it).")
	data = _data(HAZARD_SPECIES)
	data.species.hazard_test.hazard.threads.erase("cooldown_s")
	check_has_error(PackedStringArray(SpeciesCatalog.from_dict(data).load_problems),
		"species 'hazard_test' hazard threads: 'cooldown_s' is missing.")
	data = _data(HAZARD_SPECIES)
	data.species.hazard_test.hazard.drift["speed"] = 1.0
	check_has_error(PackedStringArray(SpeciesCatalog.from_dict(data).load_problems),
		"species 'hazard_test' hazard drift has an unknown key 'speed'")
	# The other behaviors still need their attack, notice and give-up, and no hazard block.
	for key in ["attack", "notice_s", "give_up_s"]:
		data = _data()
		data.species.rammer.erase(key)
		check_has_error(PackedStringArray(SpeciesCatalog.from_dict(data).load_problems),
			"species 'rammer': '%s' is missing (a territorial species needs it)." % key)
	data = _data(HAZARD_SPECIES)
	data.species.ambush_hunter["hazard"] = data.species.hazard_test.hazard
	check_has_error(PackedStringArray(SpeciesCatalog.from_dict(data).load_problems),
		"species 'ambush_hunter': only a hazard species has a 'hazard' block.")
	# metabolism_share 0 is a hazard's only.
	var errors := _errors_after(func(d: Dictionary) -> void: d.species.lurker.metabolism_share = 0.0)
	check_eq(errors.size(), 1, "one problem: %s" % [errors])
	check_has_error(errors, "species 'lurker': metabolism_share must be a share in (0, 1].")


func test_radius_at_is_at_sizes_radius_bit_for_bit() -> void:
	var n_checked := 0
	for path in [SpeciesCatalog.DEFAULT_PATH, HAZARD_SPECIES]:
		var cat := SpeciesCatalog.load_from(path)
		for id in cat.species_ids():
			for n in range(cat.entry_size(id), 5):
				var record := cat.at_size(id, n, parts)
				check(cat.radius_at(id, n) == (record.phenotype as Phenotype).radius,
					"%s at %d: %.15f == %.15f" % [id, n, cat.radius_at(id, n), (record.phenotype as Phenotype).radius])
				n_checked += 1
	check(n_checked >= 20, "every species at every size to 4 (%d)" % n_checked)
	var veil := SpeciesCatalog.load_from(HAZARD_SPECIES)
	check_eq(veil.radius_at("hazard_test", 1), 0.8, "0.5 x 1.6")
	check_eq(veil.radius_at("hazard_test", 4), 0.8 * 0.625 * 0.625 * 0.625, "q = 0.625^3")


func test_a_hazards_reach_disc_is_its_leash_plus_a_thread() -> void:
	var cat := SpeciesCatalog.load_from(HAZARD_SPECIES)
	var s := {"id": "v", "species": "hazard_test", "home": Vector2(3.0, -2.0), "heading": 0.0}
	var disc := cat.reach_disc_for(s, {})
	check_eq(disc.center, Vector2(3.0, -2.0), "round its home")
	check_eq(float(disc.radius), 4.75 + 2.4 + 0.35, "leash + length + thread radius = 7.5 (D-121)")
	var k := 1.6
	check_eq(float(cat.reach_disc_for(s, {}, k).radius), 4.75 * k + 2.4 * k + 0.35 * k, "each length times k")
	var ambush := cat.reach_disc_for({"id": "a", "species": "ambush_hunter", "home": Vector2.ZERO, "heading": 0.0}, {})
	check_eq(float(ambush.radius), 9.0, "an ambush hunter's is its leash alone")
	check_eq(cat.strike_room_problem("hazard_test", 6.0, "x", parts), "", "a hazard has no strike lane")


func test_rule_15_outgrows_a_hazard_by_its_threads() -> void:
	var errors := _hazard_errors_after(func(b: Dictionary) -> void: b.entry_size = 3)
	check(errors.is_empty(), "a size-3 hazard stings nothing one size past it: %s" % [errors])
	var data := _data(HAZARD_SPECIES)
	data.species.hazard_test.entry_size = 3
	data.erase("relationships")
	for id in ["lurker", "elder_rammer"]:
		data.species.erase(id)
	data.sites = data.sites.filter(func(s: Dictionary) -> bool: return s.species != "lurker" and s.species != "elder_rammer")
	errors = SpeciesCatalog.from_dict(data).validate(layout, parts)
	check_only_rule(errors, 15, "species 'hazard_test' has entry_size 3, which needs the relationships block.")


func test_the_s3_habit_keys() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: d.species.ambush_hunter["habit"] = {"channel": true})
	check(errors.is_empty(), "an ambush channel habit: %s" % [errors])
	errors = _errors_after(func(d: Dictionary) -> void: d.species.rammer["habit"] = {"channel": true})
	check_eq(Array(errors), ["species 'rammer': habit.channel needs behavior 'ambush'."], "channel on a rammer")
	errors = _errors_after(func(d: Dictionary) -> void:
		d.species.elder_rammer.habit = {"post_switch": "bloom", "bloom_cycle_s": 90.0})
	check(errors.is_empty(), "a bloom habit: %s" % [errors])
	errors = _errors_after(func(d: Dictionary) -> void:
		d.species.elder_rammer.habit = {"post_switch": "bloom", "bloom_cycle_s": 90.01})
	check_eq(Array(errors), ["species 'elder_rammer': habit 'bloom' needs bloom_cycle_s above 0, an even number of ticks."],
		"5,401 ticks is odd")
	errors = _errors_after(func(d: Dictionary) -> void: d.species.elder_rammer.habit = {"post_switch": "bloom"})
	check_has_error(errors, "habit 'bloom' needs bloom_cycle_s above 0")
	errors = _errors_after(func(d: Dictionary) -> void: d.species.lurker.habit["bloom_cycle_s"] = 90.0)
	check_eq(Array(errors), ["species 'lurker': habit.bloom_cycle_s needs post_switch 'bloom'."], "a cycle with no bloom")
	errors = _errors_after(func(d: Dictionary) -> void:
		d.species.lurker.habit = {"post_switch": "bloom", "bloom_cycle_s": 90.0})
	check_eq(Array(errors), ["species 'lurker': habit.post_switch 'bloom' needs behavior 'territorial'."], "bloom on an ambush")
