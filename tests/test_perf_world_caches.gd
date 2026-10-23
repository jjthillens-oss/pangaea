extends TestCase
## The world side's speed-ups (S1 perf, G17) keep every answer exact: each kept value or shortcut
## here is checked against the code it replaced, copied below as it was, over many inputs, and every
## value must be equal, not near.


# --- ViewFootprint.corners (the camera's shape kept per camera) ---

## ViewFootprint.corners before the shape was kept.
static func _corners_before(look_target: Vector2, camera: Dictionary, distance: float, aspect: float) -> PackedVector2Array:
	var pitch := deg_to_rad(float(camera.pitch_deg))
	var t := tan(deg_to_rad(float(camera.fov_deg)) / 2.0)
	var height := distance * sin(pitch)
	var back := distance * cos(pitch)
	var out := PackedVector2Array()
	for edge: float in [1.0, -1.0]:
		var down := sin(pitch) - edge * t * cos(pitch)
		if down <= 1e-6:
			return PackedVector2Array()
		var reach := height / down
		var y := look_target.y + back - reach * (cos(pitch) + edge * t * sin(pitch))
		var half_width := reach * t * aspect
		if edge > 0.0:
			out.append(Vector2(look_target.x - half_width, y))
			out.append(Vector2(look_target.x + half_width, y))
		else:
			out.append(Vector2(look_target.x + half_width, y))
			out.append(Vector2(look_target.x - half_width, y))
	return out


func test_corners_equal_the_old_corners_for_any_camera_target_and_screen() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7101
	var layout := PoolLayout.load_from()
	# The game's own camera at both zoom ends, then random cameras: more than the kept shapes, each
	# asked twice (the second answer comes from the kept shape), with flat pitches that see no far end.
	var cameras: Array[Array] = [[layout.camera, float(layout.camera.zoom_max), 2.4], [layout.camera, float(layout.camera.zoom_min), 16.0 / 9.0]]
	for i in 40:
		var cam := {"pitch_deg": rng.randf_range(5.0, 89.0), "fov_deg": rng.randf_range(20.0, 90.0)}
		cameras.append([cam, rng.randf_range(4.0, 60.0), rng.randf_range(1.0, 3.0)])
	var mismatches := 0
	var empty := 0
	for round in 2:
		for c in cameras:
			for j in 25:
				var target := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
				var got := ViewFootprint.corners(target, c[0], c[1], c[2])
				var want := _corners_before(target, c[0], c[1], c[2])
				if got != want:
					mismatches += 1
				if want.is_empty():
					empty += 1
	check_eq(mismatches, 0, "every corner equal to the old one")
	check(empty > 0, "some cameras saw no far end (%d)" % empty)
	check(ViewFootprint._shapes.size() <= ViewFootprint._SHAPES_MAX, "the kept shapes stay bounded")


# --- WorldStream._calm (a match instead of the CALM key) ---

func test_calm_agrees_with_the_calm_table_for_every_state_and_phase() -> void:
	var states: Array[String] = [CreatureBrain.REST, CreatureBrain.WANDER, CreatureBrain.FORAGE, CreatureBrain.NOTICE,
		CreatureBrain.CHASE, CreatureBrain.ATTACK, CreatureBrain.FLEE, ""]
	var phases: Array[String] = ["", CreatureBrain.LURK, CreatureBrain.WATCH, CreatureBrain.PATROL, CreatureBrain.RETURN_HOME,
		CreatureBrain.SEEK, CreatureBrain.EAT, CreatureBrain.WAIT, CreatureBrain.PURSUE, CreatureBrain.AIM, CreatureBrain.TELL,
		CreatureBrain.STRIKE, CreatureBrain.GLIDE, CreatureBrain.RECOVER]
	var c := CreatureField.Creature.new()
	c.brain = CreatureBrain.Memory.new()
	var calm := 0
	for state in states:
		for phase in phases:
			c.brain.state = state
			c.brain.phase = phase
			var want := WorldStream.CALM.has(state + "/" + phase)
			check_eq(WorldStream._calm(c), want, "%s/%s" % [state, phase])
			calm += 1 if want else 0
	check_eq(calm, WorldStream.CALM.size(), "every calm pair met")


# --- SpeciesCatalog.reach_disc_for (the leash disc without a brain) ---

func test_reach_disc_for_equals_the_brains_own_leash_disc() -> void:
	var species := SpeciesCatalog.load_from()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7102
	var checked := 0
	var behaviors := {}
	for id in species.species_ids():
		var cfg := species.brain_config(id)
		if cfg.is_empty():
			check_eq(species.reach_disc_for({"species": id, "home": Vector2.ZERO, "heading": 0.0}, {}), {}, "%s: no brain, no disc" % id)
			continue
		behaviors[str(cfg.behavior)] = true
		for i in 30:
			var s := {"species": id, "home": Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0)),
				"heading": rng.randf_range(-PI, PI)}
			var territory := {}
			if i % 3 == 1:
				territory = {"center": Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0)), "radius": rng.randf_range(2.0, 9.0)}
			elif i % 3 == 2:
				territory = species.territory_from(s, {"center": s.home + Vector2(1.5, -0.5), "radius": 4.0})
			var mem := CreatureBrain.create(cfg.behavior, cfg, s.home, float(s.heading), territory, 0, 0)
			check_eq(species.reach_disc_for(s, territory), CreatureBrain.leash_disc(mem), "%s #%d" % [id, i])
			checked += 1
	check(behaviors.has(CreatureBrain.TERRITORIAL) and behaviors.has(CreatureBrain.AMBUSH), "both behaviors checked (%s)" % [behaviors.keys()])
	check(checked >= 60, "%d discs checked" % checked)


# --- WorldStream's wake bound (a sleeper measured again only once the cell may have come near) ---

const Gates := preload("res://tests/test_endless_gates.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")

## Two sims of the same seed swim the same route, east and back west past the creatures they left
## asleep, overdriven and seen, with a debug rebase, a death (two places, then the respawn's jump)
## and a debug teleport on the way. Before every step the twin's bound restarts, so it measures every
## sleeper every tick as the stream did before. Every tick's events and every hash must be the same.
func test_slow_the_wake_bound_wakes_the_same_sleepers_as_measuring_every_one() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the wake bound waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 501)
	var b: Variant = Gates.make_sim(Gates.RACER, 501)
	var counts := {"creature_woke": 0, "creature_slept": 0, "rebased": 0, "died": 0}
	var bounded := 0
	var dead_since := -1
	for t in 2400:
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		if a.dead:
			if dead_since < 0:
				dead_since = t
			elif t - dead_since >= Gates.DEATH_NOTICE_TICKS and not a.respawn_pending:
				a.respawn_player()
				b.respawn_player()
				dead_since = -1
		if t == 1000:
			a.debug_rebase(Vector2i(-2, 1))
			b.debug_rebase(Vector2i(-2, 1))
		elif t == 1400:
			a.debug_hurt_player(1e6)
			b.debug_hurt_player(1e6)
		elif t == 2000:
			a.debug_teleport(a.motion.position + Vector2(-30.0, 12.0))
			b.debug_teleport(b.motion.position + Vector2(-30.0, 12.0))
		var move := Vector2.RIGHT if (t / 600) % 2 == 0 else Vector2.LEFT
		b.world._swum_from = Vector2.INF
		a.step(SimIntent.new(move))
		b.step(SimIntent.new(move))
		var ea: Array = a.drain_events()
		var eb: Array = b.drain_events()
		if var_to_str(ea) != var_to_str(eb):
			check(false, "tick %d: the events differ" % t)
			return
		for e in ea:
			if counts.has(e.type):
				counts[e.type] += 1
		if not a.world._wake_bound.is_empty():
			bounded += 1
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	print("test-perf-world-caches: the wake bound held on %d of 2400 ticks; %s" % [bounded, counts])
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check(counts.creature_woke >= 3 and counts.creature_slept >= 3, "sleepers slept and woke (%s)" % counts)
	check(bounded >= 1000, "the bound skipped sleepers on most ticks (%d)" % bounded)
	check(counts.died == 1 and a.tick > 1400 + Gates.DEATH_NOTICE_TICKS and not a.dead, "the cell died and came back")
