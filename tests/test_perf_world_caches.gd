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
