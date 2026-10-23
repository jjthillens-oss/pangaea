extends TestCase
## The threat species data (game/data/creatures_m1.json, M1 step 3) is valid, reads into the bodies,
## brain timings and fairness tables the plan sets, and every validation rule catches the mistake it
## is for: one mutated copy of the real data per rule, each reported under that rule's name.

const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"

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
	check_eq(Array(cat.species_ids()), ["ambush_hunter", "rammer"], "two species, sorted")
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
	# lair from spawning while the cell is in z_s, so neither zone regrows fast enough to feed a cell
	# that camps there and eats what it can (test_threat_gates #33). z_s also gets a lair whose reach (leash plus body) enters it well
	# and whose hunter, at home, sees across its edge, so a cell feeding there meets it (#32).
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
