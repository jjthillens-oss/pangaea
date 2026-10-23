extends TestCase
## Seed, schedule, snapshot and migration invariants across domain and service boundaries.


func _brain(behavior: String, seed_value: int) -> CreatureBrain.Memory:
	var cfg := CreatureBrain.config("review", {"behavior": behavior, "leash_m": 3.0,
		"territory_margin_m": 2.0, "rest_s": [1.0, 2.0]}, {})
	return CreatureBrain.create(behavior, cfg, Vector2(2.0, 1.0), 0.0,
		{"center": Vector2(4.0, 5.0), "radius": 6.0}, seed_value, 20)


func test_brain_seconds_are_rounded_to_whole_ticks() -> void:
	check_eq(CreatureBrain.ticks(0.35), 21, "fractional seconds converted once")
	check_eq(CreatureBrain.ticks(1.2), 72, "longer duration converted")


func test_brain_creation_repeats_rng_stream_for_same_seed() -> void:
	var a := _brain(CreatureBrain.AMBUSH, 429)
	var b := _brain(CreatureBrain.AMBUSH, 429)
	var c := _brain(CreatureBrain.AMBUSH, 430)
	check_eq(a.rng.randi(), b.rng.randi(), "same seed, same first draw")
	check(a.rng.randi() != c.rng.randi(), "different seeds diverge")


func test_brain_territorial_leash_includes_margin_and_leash() -> void:
	var mem := _brain(CreatureBrain.TERRITORIAL, 4)
	var disc := CreatureBrain.leash_disc(mem)
	check_eq(disc.center, Vector2(4.0, 5.0), "uses guarded center")
	check_near(disc.radius, 11.0, 0.0001, "zone radius plus margin and leash")


func test_brain_ambush_leash_uses_home() -> void:
	var disc := CreatureBrain.leash_disc(_brain(CreatureBrain.AMBUSH, 4))
	check_eq(disc.center, Vector2(2.0, 1.0), "home center")
	check_near(disc.radius, 3.0, 0.0001, "home leash only")


func test_brain_engagement_requires_matching_nonempty_target_and_state() -> void:
	var mem := _brain(CreatureBrain.AMBUSH, 4)
	mem.target = "prey"
	mem.state = CreatureBrain.NOTICE
	check(not CreatureBrain.is_engaged_with(mem, "prey"), "notice is not engagement")
	mem.state = CreatureBrain.CHASE
	check(CreatureBrain.is_engaged_with(mem, "prey"), "chase is engaged")
	check(not CreatureBrain.is_engaged_with(mem, "other"), "different body not engaged")
	check(not CreatureBrain.is_engaged_with(mem, ""), "empty id never engaged")


func test_brain_striking_excludes_tell_and_recover() -> void:
	var mem := _brain(CreatureBrain.AMBUSH, 4)
	mem.state = CreatureBrain.ATTACK
	for phase in [CreatureBrain.TELL, CreatureBrain.RECOVER]:
		mem.phase = phase
		check(not CreatureBrain.is_striking(mem), "%s cannot hit" % phase)
	for phase in [CreatureBrain.STRIKE, CreatureBrain.GLIDE]:
		mem.phase = phase
		check(CreatureBrain.is_striking(mem), "%s can hit" % phase)


func test_brain_wake_overrides_staggered_schedule() -> void:
	var mem := _brain(CreatureBrain.AMBUSH, 4)
	mem.cfg.think_ticks = 6
	mem.state = CreatureBrain.REST
	mem.phase = CreatureBrain.LURK
	mem.wake = false
	check(not CreatureBrain.think_due(mem, 0, 1), "off-slot resting brain waits")
	mem.wake = true
	check(CreatureBrain.think_due(mem, 0, 1), "hurt wake runs immediately")


func test_migration_registry_contains_only_the_approved_v1_step() -> void:
	var steps := SaveMigrations.all()
	check_eq(steps.size(), 1, "one approved upgrade")
	check(steps.has(1), "v1 upgrade registered")


func test_migration_keeps_unrelated_old_fields() -> void:
	var old := {"schema_version": 1, "world_seed": 42, "lineage_id": "lineage_0123456789abcdef"}
	var migrated := SaveMigrations.v1_to_v2(old)
	check_eq(migrated.schema_version, 2, "schema advanced")
	check_eq(migrated.adaptation_points, 0, "new points default")
	check_eq(migrated.world_seed, 42, "seed retained")
	check_eq(migrated.lineage_id, "lineage_0123456789abcdef", "lineage retained")


func test_motion_place_resets_interpolation_and_velocity() -> void:
	var m := Locomotion.MotionState.new(Vector2(1.0, 2.0), 0.5)
	m.velocity = Vector2(3.0, 4.0)
	m.prev_position = Vector2.ZERO
	m.prev_heading = -1.0
	m.place(Vector2(-2.0, 7.0), 1.2)
	check_eq(m.position, m.prev_position, "no position interpolation from prior life")
	check_eq(m.heading, m.prev_heading, "no heading interpolation from prior life")
	check_eq(m.velocity, Vector2.ZERO, "old motion cleared")


func test_respawn_relocation_treats_missing_alive_as_live() -> void:
	var bodies := [{"id": "b", "position": Vector2(1.0, 0.0)},
		{"id": "a", "position": Vector2(0.0, 1.0), "alive": true},
		{"id": "c", "position": Vector2.ZERO, "alive": false}]
	check_eq(RespawnRules.to_relocate(Vector2.ZERO, 1.0, bodies), PackedStringArray(["a", "b"]),
		"missing alive defaults to live, ties sorted by id")


func test_lineage_survival_points_ignore_reverse_and_nonfinite_ranges() -> void:
	check_eq(Lineage.survival_points(35.0, 30.0), 0, "reversed range")
	check_eq(Lineage.survival_points(NAN, 60.0), 0, "bad start")
	check_eq(Lineage.survival_points(0.0, INF), 0, "bad end")


func test_senses_apply_safe_defaults_to_optional_body_flags() -> void:
	var viewer := {"id": "self", "species": "hunter", "position": Vector2.ZERO,
		"heading": 0.0, "radius": 0.5, "sight": 5.0, "fov": PI, "near": 0.5}
	var body := {"id": "other", "species": "grazer", "position": Vector2(2.0, 0.0),
		"velocity": Vector2.ZERO, "radius": 0.5}
	var got := CreatureSenses.perceive(viewer, [body], null)
	check_eq(got.size(), 1, "optional flags do not hide a live body")
	if got.size() == 1:
		check_eq(got[0].engageable, true, "engageable defaults true")
		check_eq(got[0].bite, false, "bite defaults false")
		check_eq(got[0].spikes, 0, "spikes default zero")


func test_food_percept_is_a_fresh_snapshot() -> void:
	var viewer := {"position": Vector2.ZERO, "heading": 0.0, "sight": 5.0, "fov": PI}
	var food := {"id": "f", "kind": "plant", "position": Vector2(2.0, 0.0), "radius": 0.2}
	var got := CreatureSenses.perceive_food(viewer, [food], PackedStringArray(["plant"]))
	check_eq(got.size(), 1, "food perceived")
	food.position = Vector2(20.0, 0.0)
	if got.size() == 1:
		check_eq(got[0].position, Vector2(2.0, 0.0), "percept keeps start-of-tick position")
