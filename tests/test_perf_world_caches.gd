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


## A kept shape answers for its own camera only: cameras that differ in one input alone (pitch,
## field of view, distance or aspect) each get their own corners, asked back to back.
func test_corners_tell_apart_cameras_that_differ_in_one_input() -> void:
	var target := Vector2(3.0, -7.0)
	var cameras: Array[Array] = [[{"pitch_deg": 50.0, "fov_deg": 40.0}, 20.0, 1.5],
		[{"pitch_deg": 60.0, "fov_deg": 40.0}, 20.0, 1.5], [{"pitch_deg": 50.0, "fov_deg": 55.0}, 20.0, 1.5],
		[{"pitch_deg": 50.0, "fov_deg": 40.0}, 30.0, 1.5], [{"pitch_deg": 50.0, "fov_deg": 40.0}, 20.0, 2.0]]
	var mismatches := 0
	for round in 2:
		for c in cameras:
			if ViewFootprint.corners(target, c[0], c[1], c[2]) != _corners_before(target, c[0], c[1], c[2]):
				mismatches += 1
	check_eq(mismatches, 0, "every camera's own corners")


# --- WorldStream._calm (a match instead of the CALM key) ---

func test_calm_agrees_with_the_calm_table_for_every_state_and_phase() -> void:
	var states: Array[String] = [CreatureBrain.REST, CreatureBrain.WANDER, CreatureBrain.FORAGE, CreatureBrain.NOTICE,
		CreatureBrain.CHASE, CreatureBrain.ATTACK, CreatureBrain.FLEE, CreatureBrain.DRIFT, ""]
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
			var expected := CreatureBrain.leash_disc(mem)
			if cfg.has("threads"):
				# A hazard's threads trail past the body the leash holds (S3, D-121).
				expected.radius = float(cfg.leash_m) + float(cfg.threads.length_m) + float(cfg.threads.radius_m)
			check_eq(species.reach_disc_for(s, territory), expected, "%s #%d" % [id, i])
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


## The wake bound starts again when what it was measured for changes: twin sims swim east past the
## creatures they leave asleep, then the wake ring grows and the view margin with it, later both
## shrink back; before every step the twin's bound restarts. The sleepers inside the grown ring wake
## at once in both, and every tick's events and every hash must be the same.
func test_the_wake_bound_starts_again_when_the_wake_ring_or_view_margin_changes() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the wake bound restart waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 505)
	var b: Variant = Gates.make_sim(Gates.RACER, 505)
	a.debug_set_hidden(true)
	b.debug_set_hidden(true)
	var wake_r := float(a.world.rings.wake)
	var margin := float(a.world.view_margin)
	var woke := {}
	var bounded_before := 0
	for t in 1500:
		if t == 900 or t == 1200:
			for sim in [a, b]:
				sim.world.rings.wake = wake_r + 25.0 if t == 900 else wake_r
				sim.world.view_margin = margin + 5.0 if t == 900 else margin
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		if t == 899 or t == 1199:
			bounded_before += 1 if not a.world._wake_bound.is_empty() else 0
		b.world._swum_from = Vector2.INF
		a.step(SimIntent.new(Vector2.RIGHT))
		b.step(SimIntent.new(Vector2.RIGHT))
		var ea: Array = a.drain_events()
		if var_to_str(ea) != var_to_str(b.drain_events()):
			check(false, "tick %d: the events differ" % t)
			return
		for e in ea:
			if e.type == "creature_woke":
				woke[t] = int(woke.get(t, 0)) + 1
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check_eq(bounded_before, 2, "the bound held sleepers before each change")
	check(int(woke.get(900, 0)) >= 1, "sleepers inside the grown ring woke at once (%s)" % woke)
	check_eq(a.world._bound_view[1], wake_r, "the bound was measured again for the ring as it is now")


## The hold pass's bound lets go the creatures measuring every awake one would: twin sims swim east
## then west, with a debug rebase, the hold ring cut to 30 tm for a while (the awake creatures beyond
## it go as the cell swims off) and then given back, and a debug teleport; before every step the twin
## forgets its hold bound only. Every tick's events and every hash must be the same.
func test_the_hold_bound_lets_go_the_same_creatures_as_measuring_every_one() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the hold bound waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 505)
	var b: Variant = Gates.make_sim(Gates.RACER, 505)
	a.debug_set_hidden(true)
	b.debug_set_hidden(true)
	var hold := float(a.world.rings.hold)
	var let_go := 0
	var held := 0
	for t in 1500:
		if t == 500:
			a.debug_rebase(Vector2i(2, -1))
			b.debug_rebase(Vector2i(2, -1))
		elif t == 700 or t == 1000:
			for sim in [a, b]:
				sim.world.rings.hold = 30.0 if t == 700 else hold
		elif t == 1200:
			a.debug_teleport(a.motion.position + Vector2(-30.0, 12.0))
			b.debug_teleport(b.motion.position + Vector2(-30.0, 12.0))
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		var before: int = a.world._hold_bound.size()
		b.world._hold_bound.clear()
		var move := Vector2.RIGHT if t < 800 else Vector2.LEFT
		a.step(SimIntent.new(move))
		b.step(SimIntent.new(move))
		held += 1 if before > 0 else 0
		var ea: Array = a.drain_events()
		if var_to_str(ea) != var_to_str(b.drain_events()):
			check(false, "tick %d: the events differ" % t)
			return
		for e in ea:
			if e.type == "creature_removed" and e.reason == "unloaded" and t >= 700 and t < 1000:
				let_go += 1
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check(held >= 1000, "the bound held creatures on most ticks (%d)" % held)
	check(let_go >= 5, "creatures were let go while the ring was cut (%d)" % let_go)


## The hold bound holds through a rebase: the hold centres, the cell's place and the path's last
## place move by the same offset, so on a step after two debug rebases (there and back) that loads
## and unloads nothing, the hold pass passes over the awake creatures held before on the same bounds
## (a bound measured again is a new one).
func test_the_hold_bound_holds_through_a_rebase() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the hold bound through a rebase waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 505)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var held := 0
	var carried := -1
	for t in 1200:
		var kept := {}
		for c in sim.creatures.awake():
			if w._hold_bound.has(c):
				kept[c] = w._hold_bound[c]
		var rebase: bool = t >= 300 and kept.size() >= 5
		if rebase:
			sim.debug_rebase(Vector2i(1, 0))
			sim.debug_rebase(Vector2i(-1, 0))
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT))
		var chunks := false
		for e in sim.drain_events():
			chunks = chunks or e.type == "chunk_loaded" or e.type == "chunk_unloaded"
		if rebase and not chunks:
			held = kept.size()
			carried = 0
			for c in kept:
				carried += 1 if is_same(kept[c], w._hold_bound.get(c)) else 0
			break
	print("test-perf-world-caches: the hold bound held %d of %d creatures through a rebase" % [carried, held])
	check(carried >= 5 and carried * 4 >= held * 3, "the creatures held before the rebase were passed over on the same bounds (%d of %d)" % [
		carried, held])


## An awake creature the hold bound holds goes on the first step that finds the cell past the hold
## ring from its hold centre: the cell swims on east, the ring set 2 tm past the distance of a creature
## left behind it.
func test_a_held_creature_goes_on_the_first_step_past_the_hold_ring() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the held creature waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 505)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var held: CreatureField.Creature = null
	var center := Vector2.ZERO
	for t in 900:
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT))
		sim.drain_events()
		for c in sim.creatures.awake():
			if w._hold_bound.has(c) and w.sites.has(c.site_id):
				var at: Vector2 = w.sites[c.site_id].reach.center
				var d: float = sim.motion.position.distance_to(at)
				if d > 10.0 and d < 30.0 and at.x < sim.motion.position.x - 5.0:
					held = c
					center = at
		if held != null:
			break
	check(held != null, "an awake creature left behind, held by the bound")
	if held == null:
		return
	var hold: float = sim.motion.position.distance_to(center) + 2.0
	w.rings.hold = hold
	var past := -1
	var gone := -1
	for t in 400:
		var d: float = sim.motion.position.distance_to(center)   # what this step's hold pass measures
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT))
		sim.drain_events()
		if past < 0 and d > hold + 0.01:
			past = t
		if gone < 0 and not sim.creatures.creatures.has(held):
			gone = t
			break
	check(past >= 3, "the cell swam past the ring a few steps on (%d)" % past)
	check_eq(gone, past, "the creature went on that step")


## A sleeper the bound holds is measured again once it is moved (a respawn sends the creatures near
## the checkpoint home, sleepers too): one put beside the cell wakes on the next step.
func test_a_moved_sleeper_is_measured_again_at_once() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the moved sleeper waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 501)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var held: CreatureField.Creature = null
	for t in 1200:
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT))
		sim.drain_events()
		for c in sim.creatures.creatures:
			var b: Variant = w._wake_bound.get(c)
			if c.asleep and b != null and b[1] - w._swum > 1.0:
				held = c
		if held != null:
			break
	check(held != null, "a sleeper the bound holds")
	if held == null:
		return
	held.motion.position = sim.motion.position + Vector2(0.0, 6.0)
	sim.step(SimIntent.new())
	check(not held.asleep, "put beside the cell, it wakes on the next step")


## The wake bound holds for a view that reaches past the wake ring, and starts again when any one of
## its inputs changes on its own: twin sims on a wide screen (its view reaches past the ring) swim
## east past the creatures they leave asleep and back west into them, while the wake ring, then the
## view margin, then the screen's aspect change and change back, each on its own ticks; before every
## step the twin's bound restarts. Every tick's events and every hash must be the same.
func test_the_wake_bound_holds_a_wide_view_and_starts_again_for_each_input() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the wide view's wake bound waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 505)
	var b: Variant = Gates.make_sim(Gates.RACER, 505)
	const WIDE := 3.5
	var narrow: float = a.world.view_aspect
	var wake_r := float(a.world.rings.wake)
	var margin := float(a.world.view_margin)
	for sim in [a, b]:
		sim.debug_set_hidden(true)
		sim.world.view_aspect = WIDE
	check(float(a.world._wake_view(a).far) > wake_r, "the wide view reaches past the wake ring")
	var woke := {}
	var bounded := 0
	for t in 1600:
		for sim in [a, b]:
			match t:
				700:
					sim.world.rings.wake = wake_r + 20.0
				800:
					sim.world.rings.wake = wake_r
				1000:
					sim.world.view_margin = margin + 10.0
				1100:
					sim.world.view_margin = margin
				1300:
					sim.world.view_aspect = narrow
				1400:
					sim.world.view_aspect = WIDE
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		if not a.world._wake_bound.is_empty():
			bounded += 1
		b.world._swum_from = Vector2.INF
		var move := Vector2.RIGHT if t < 600 or (t >= 1150 and t < 1300) else Vector2.LEFT
		a.step(SimIntent.new(move))
		b.step(SimIntent.new(move))
		var ea: Array = a.drain_events()
		if var_to_str(ea) != var_to_str(b.drain_events()):
			check(false, "tick %d: the events differ" % t)
			return
		for e in ea:
			if e.type == "creature_woke":
				woke[t] = int(woke.get(t, 0)) + 1
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	print("test-perf-world-caches: the wide view's wake bound held on %d of 1600 ticks; woke on %s" % [bounded, woke])
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check(bounded >= 800, "the bound held sleepers on most ticks (%d)" % bounded)


## The wake bound measures to the view where the view reaches past the wake ring: a sleeper the bound
## holds wakes on the next step once the cell is put where the view takes it in past the ring. First
## with the ring cut to 20 tm (the bound was measured to the view), then on a screen made wide while
## the sleeper is held (the bound starts again when the view's reach changes). Each time the cell
## moves less than a bound measured to the ring alone would allow, so such a bound would still hold it.
func test_a_held_sleeper_wakes_once_a_view_reaching_past_the_wake_ring_takes_it_in() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the view past the wake ring waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	for late in [false, true]:
		var what := "a screen made wide while held" if late else "the ring cut to 20 tm"
		var sim: Variant = Gates.make_sim(Gates.RACER, 501)
		sim.debug_set_hidden(true)
		var w: WorldStream = sim.world
		var aspect := 5.0 if late else w.view_aspect
		if not late:
			w.rings.wake = 20.0
		var held: CreatureField.Creature = null
		var spot := Vector2.INF
		for t in 1800:
			SwimBot.overdrive(sim)
			sim.step(SimIntent.new(Vector2.RIGHT if (t / 300) % 2 == 0 else Vector2.LEFT))
			sim.drain_events()
			for c in sim.creatures.creatures:
				spot = _spot_seeing_past_the_ring(sim, c, aspect)
				if spot.is_finite():
					held = c
					break
			if held != null:
				break
		check(held != null, "%s: a held sleeper and a place whose view takes it in past the ring" % what)
		if held == null:
			continue
		w.view_aspect = aspect
		check(sim.debug_teleport(spot), "%s: the cell is put there" % what)
		sim.step(SimIntent.new())
		check(not held.asleep, "%s: the sleeper wakes on the next step" % what)


## Where to put the cell, on the straight line from it to sleeper `c`, so that a view of `aspect`
## takes `c` in past the wake ring, with the move there shorter than a bound measured to the ring
## alone would allow: INF when the bound does not hold `c` or there is no such place.
static func _spot_seeing_past_the_ring(sim: Variant, c: CreatureField.Creature, aspect: float) -> Vector2:
	var w: WorldStream = sim.world
	var b: Variant = w._wake_bound.get(c)
	if not c.asleep or b == null or b[0] != c.motion.position or b[1] <= w._swum:
		return Vector2.INF
	var wake_r := float(w.rings.wake)
	var r := c.phenotype.radius
	# b[1] is the path swum when it was measured, plus the distance, less maxf(wake_r, reach + r) and
	# the slack: measured to the ring alone, it would be b[1] plus the difference.
	var reach := w._bound_view[0] + WorldStream.WAKE_FAR_TOLERANCE_TM + w.view_margin + 0.01
	var ring_only: float = b[1] + maxf(wake_r, reach + r) - wake_r
	var at := c.motion.position
	var toward: Vector2 = (sim.motion.position - at).normalized()
	for k in 30:
		var to: Vector2 = at + toward * (wake_r + 32.0 - k)   # nearer to `c` each time, 2 tm past the ring at the end
		var quad := ViewFootprint.corners(to, w.camera, float(w.camera.zoom_max), aspect)
		if ViewFootprint.distance_outside(quad, at) > w.view_margin + r - 1.0:
			continue
		if w._swum + sim.motion.position.distance_to(to) >= ring_only - 1.0:
			break   # the move only grows from here
		if sim.arena.is_clear(to, sim.phenotype.radius):
			return to
	return Vector2.INF


# --- WorldStream._food_view (packed zones, the trim picked lazily, the drop skipped when unchanged) ---

## WorldStream._food_view before the zones were packed.
static func _food_view_before(w: WorldStream, sim: PoolSim) -> void:
	var body := sim.motion.position
	var food := {}
	var reach := {}
	for z in sim.region.zones:
		var d := body.distance_to(z.center) - float(z.radius)
		if d <= float(w.rings.food):
			food[z.id] = true
			reach[z.id] = d
	var total := 0
	for id in food:
		total += sim.plankton.target_count(sim.region.zone(id))
	if total > int(w.caps.food_items):
		var quad := ViewFootprint.corners(body, w.camera, float(w.camera.zoom_max), w.view_aspect)
		var out: Array = []
		for id in food:
			var z := sim.region.zone(id)
			if quad.is_empty() or ViewFootprint.distance_outside(quad, z.center) > w.view_margin + float(z.radius):
				out.append(id)
		out.sort_custom(func(a: String, b: String) -> bool:
			return reach[a] > reach[b] or (reach[a] == reach[b] and a < b))
		for id in out:
			if total <= int(w.caps.food_items):
				break
			food.erase(id)
			total -= sim.plankton.target_count(sim.region.zone(id))
			if not w._trimmed.has(id):
				w._trimmed[id] = true
				w.counters.food_trimmed += 1
	for id in w._trimmed.keys():
		if food.has(id) or sim.region.zone(id).is_empty():
			w._trimmed.erase(id)
	for id in sim.plankton.active_zones.keys():
		if not food.has(id):
			sim.plankton.drop_zone(id)
	sim.plankton.active_zones = food
	sim.carrion.drop_beyond(body, float(w.rings.food))
	var fill: Array = food.keys() if w._fill_all else w._fill.keys()
	fill.sort()
	for id in fill:
		if food.has(id):
			sim.plankton.fill_zone(sim.region.zone(id), sim.region, sim.arena, sim.tick, sim.now())
	w._fill.clear()
	w._fill_all = false
	var tile := w.tile_of_local(body)
	if tile != w._cell_tile:
		w._cell_tile = tile
		var info := w.gen.tile_info(WorldConfig.band_of(w.size), tile.x, tile.y)
		w._emit(sim, {"type": "tile_entered", "tile": tile, "region": str(info.get("region", "")), "rare": str(info.get("rare", ""))})


## Twin sims: at 400 random places round home, with random zone stocks, item caps (most of them
## trimming) and whole fills, one runs the food view and the other the old one. The zones shown
## (in their order), the trimmed set and count, the items and the events must stay equal; a rebase
## and a swim between the rounds move the zones under the kept index.
func test_the_food_view_equals_the_old_one_at_random_places_stocks_and_caps() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the food view waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 502)
	var b: Variant = Gates.make_sim(Gates.RACER, 502)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7103
	var trimmed := 0
	var shown := 0
	var ties := 0
	for round in 4:
		for i in 100:
			var p := Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
			if i % 4 == 3:
				# Midway between two zones of one radius: equal distances, so the tie goes to the lower id.
				var zs: Array = a.region.zones
				var z1: Dictionary = zs[rng.randi_range(0, zs.size() - 1)]
				var z2: Dictionary = zs[rng.randi_range(0, zs.size() - 1)]
				if z1.id != z2.id and float(z1.radius) == float(z2.radius):
					p = (z1.center + z2.center) / 2.0
			var cap := rng.randi_range(0, 60) if rng.randf() < 0.8 else 1000
			var fill_all := rng.randf() < 0.1
			var amounts := []
			for z in a.region.zones:
				amounts.append(rng.randf_range(0.0, float(z.capacity)))
			for sim in [a, b]:
				sim.motion.position = p
				sim.world.caps.food_items = cap
				sim.world._fill_all = fill_all
				for k in sim.region.zones.size():
					sim.region.zones[k].amount = amounts[k]
			a.world._food_view(a)
			_food_view_before(b.world, b)
			var wa: WorldStream = a.world
			var wb: WorldStream = b.world
			if var_to_str(a.plankton.active_zones) != var_to_str(b.plankton.active_zones) or wa._trimmed != wb._trimmed \
					or wa.counters != wb.counters or var_to_str(a.plankton.items) != var_to_str(b.plankton.items) \
					or var_to_str(a.drain_events()) != var_to_str(b.drain_events()):
				check(false, "round %d, place %d (%s, cap %d): the food views differ" % [round, i, p, cap])
				return
			shown += a.plankton.active_zones.size()
			ties += 1 if _has_tie(a.world, a.motion.position) else 0
		trimmed = int(a.world.counters.food_trimmed)
		for sim in [a, b]:
			sim.motion.position = Vector2(0.0, 9.0)
			sim.world.caps.food_items = 1000
			sim.debug_rebase(Vector2i(1, -1) if round % 2 == 0 else Vector2i(-1, 1))
			for t in 30:
				SwimBot.overdrive(sim)
				sim.step(SimIntent.new(Vector2.RIGHT))
			sim.drain_events()
		check_eq(a.state_hash(), b.state_hash(), "round %d: the twins agree" % round)
	print("test-perf-world-caches: the food view: %d zones shown over 400 places, %d trimmed, %d places with a tie" % [shown, trimmed, ties])
	check(trimmed >= 50, "zones were trimmed (%d)" % trimmed)
	check(ties >= 10, "places with two food zones at one distance (%d)" % ties)
	check(shown >= 400, "zones were shown (%d)" % shown)


## The food view's bound (the zones within the food ring kept while the body moves less than any
## zone's distance from the ring) and its kept food set (the one given last time, while the same zones
## are shown) show what measuring every zone shows: twin sims swim east and back overdriven, with a
## rebase, a teleport and a low item cap for a while (zones trimmed), and before every step the twin's
## bound and kept set are dropped. Every tick's food zones (in order), trimmed set, events and hash
## must be the same.
func test_the_food_bound_shows_the_same_zones_as_measuring_every_one() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the food bound waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var a: Variant = Gates.make_sim(Gates.RACER, 503)
	var b: Variant = Gates.make_sim(Gates.RACER, 503)
	var held := 0
	var kept := 0
	var changed := 0
	var last := ""
	for t in 1800:
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		if t == 500:
			a.debug_rebase(Vector2i(-2, 1))
			b.debug_rebase(Vector2i(-2, 1))
		elif t == 1100:
			a.debug_teleport(a.motion.position + Vector2(-30.0, 12.0))
			b.debug_teleport(b.motion.position + Vector2(-30.0, 12.0))
		var cap := 12 if t >= 700 and t < 900 else 1000
		a.world.caps.food_items = cap
		b.world.caps.food_items = cap
		var move := Vector2.RIGHT if (t / 450) % 2 == 0 else Vector2.LEFT
		var bound_before: PackedFloat64Array = a.world._food_bound
		var given_before: Dictionary = a.plankton.active_zones
		b.world._food_bound = PackedFloat64Array()
		b.world._shown_food = {}
		a.step(SimIntent.new(move))
		b.step(SimIntent.new(move))
		if not bound_before.is_empty() and a.world._food_bound == bound_before:
			held += 1
		if is_same(a.plankton.active_zones, given_before):
			kept += 1
		var za := var_to_str(a.plankton.active_zones)
		if za != var_to_str(b.plankton.active_zones) or a.world._trimmed != b.world._trimmed \
				or a.world.counters != b.world.counters or var_to_str(a.drain_events()) != var_to_str(b.drain_events()):
			check(false, "tick %d: the food views differ" % t)
			return
		changed += 1 if za != last else 0
		last = za
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	print("test-perf-world-caches: the food bound held on %d of 1800 ticks, the food set was kept on %d; the food zones changed on %d" % [
		held, kept, changed])
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check(held >= 900, "the bound held on most ticks (%d)" % held)
	check(kept >= 900, "the food set was kept on most ticks (%d)" % kept)
	check(changed >= 20, "the food zones changed as the cell swam (%d)" % changed)
	check(int(a.world.counters.food_trimmed) > 0, "zones were trimmed (%d)" % int(a.world.counters.food_trimmed))


## The food set kept from the last food view is given again only while the index places it was built
## for hold the same zones: the region's zones are put in another order (so the index is built again)
## in which zones near another place take the index places of the zones shown, and the body moves
## there. The same places are shown, and the food set must be the zones now near the body. The food
## ring is cut to 8 tm so that the two places' zones are apart.
func test_the_kept_food_set_is_built_again_when_its_index_places_hold_other_zones() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the kept food set waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 506)
	var w: WorldStream = sim.world
	w.rings.food = 8.0
	w.caps.food_items = 1000
	var zones: Array[Dictionary] = sim.region.zones
	var p: Vector2 = sim.motion.position
	var near_p := _zones_within(zones, p, 8.0)
	var q := Vector2.INF
	var near_q := []
	for i in 441:   # a place 4 tm apart on a grid round p with as many zones near it, none of p's
		var at := p + Vector2(float(i % 21 - 10), float(i / 21 - 10)) * 4.0
		var near := _zones_within(zones, at, 8.0)
		if near.size() == near_p.size() and near.all(func(k: int) -> bool: return not near_p.has(k)):
			q = at
			near_q = near
			break
	check(not near_p.is_empty() and q.is_finite(), "zones near the body (%s) and as many near another place" % [near_p])
	if near_p.is_empty() or not q.is_finite():
		return
	w._food_view(sim)
	check_eq(w._shown_at, PackedInt32Array(near_p), "the zones near the body are shown")
	for j in near_p.size():
		var z: Dictionary = zones[near_p[j]]
		zones[near_p[j]] = zones[near_q[j]]
		zones[near_q[j]] = z
	w._zones_version += 1   # as every change to the region's zones does
	sim.motion.position = q
	w._food_view(sim)
	check_eq(w._shown_at, PackedInt32Array(near_p), "the same index places are shown")
	var want := []
	for k in near_p:
		want.append(zones[k].id)
	var got: Array = sim.plankton.active_zones.keys()
	want.sort()
	got.sort()
	check_eq(got, want, "and the food set is the zones near the body now")


## The places in `zones` of the zones whose nearest point lies within `ring` of `p`, ascending.
static func _zones_within(zones: Array[Dictionary], p: Vector2, ring: float) -> Array:
	var out := []
	for k in zones.size():
		if p.distance_to(zones[k].center) - float(zones[k].radius) <= ring:
			out.append(k)
	return out


## Whether two food zones lie at the same distance from `p`.
static func _has_tie(w: WorldStream, p: Vector2) -> bool:
	var seen := {}
	for i in w._zone_ids.size():
		var d := p.distance_to(w._zone_c[i]) - w._zone_r[i]
		if d <= float(w.rings.food):
			if seen.has(d):
				return true
			seen[d] = true
	return false


# --- WorldStream's kept counts: niche roles and home chunks of the site table, the zone index ---

## On the saturated case's dense world (sites load and unload all the way), every 30 ticks the
## stream's kept counts equal the ones counted afresh from the table and the region, and the zone
## index, kept through the loads and unloads, equals the region's zones and their absolute centres.
func test_slow_the_kept_site_counts_and_zone_index_match_the_table_on_a_dense_swim() -> void:
	var cost: GDScript = load("res://tests/test_endless_cost.gd")
	var fake: GDScript = load("res://tests/fakes/fake_world_gen.gd")
	if fake == null or not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the kept counts wait on the endless world")
		return
	var d := Gates.data()
	var content: Variant = fake.call("fixture_content")
	var r := Lineage.found(2802, Gates.BUILD_ID, d.catalog, "hunter")
	Gates.make_racer(r.save.genome, d.catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
	var sim: PoolSim = PoolSim._create_endless(r.save, d.catalog, d.layout, d.species, content, cost.DenseGen.new(content, d.species, 2802))
	sim.debug_set_hidden(true)
	var w := sim.world
	var unloads := 0
	var kept := 0
	var bad := []
	for t in 1500:
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT if t < 1200 else Vector2(-0.6, 0.8)))
		for e in sim.drain_events():
			unloads += 1 if e.type == "chunk_unloaded" else 0
		if t % 30 != 29:
			continue
		var roles := {}
		var homes := {}
		for id in w.sites:
			var role := str(d.species.niche_of(str(w.sites[id].species)).role)
			roles[role] = int(roles.get(role, 0)) + 1
			var key: Vector2i = w.sites[id].home_chunk
			if not homes.has(key):
				homes[key] = {}
			homes[key][id] = true
		if roles != w._role_sites or w._site_role.size() != w.sites.size():
			bad.append("tick %d: roles %s, kept %s" % [t, roles, w._role_sites])
		if homes != w._home_sites or w._home_count != w.sites.size():
			bad.append("tick %d: the home chunks differ" % t)
		kept += 1 if w._zones_indexed == w._zones_version else 0
		w._index_zones(sim.region)
		var ids := PackedStringArray()
		var centres := PackedVector2Array()
		var radii := PackedFloat64Array()
		var absolute := PackedFloat64Array()
		var same := w._zone_refs.size() == sim.region.zones.size()
		for i in sim.region.zones.size():
			var z: Dictionary = sim.region.zones[i]
			ids.append(z.id)
			centres.append(z.center)
			radii.append(float(z.radius))
			var a: PackedFloat64Array = w._zone_abs[z.id]
			absolute.append_array(a)
			same = same and is_same(w._zone_refs[i], z) and w._zone_ax[i] == a[0] and w._zone_ay[i] == a[1]
		if ids != w._zone_ids or centres != w._zone_c or radii != w._zone_r or not same:
			bad.append("tick %d: the zone index differs" % t)
	check(bad.is_empty(), "the kept counts match (%s)" % [bad.slice(0, 3)])
	check(kept >= 40, "the zone index was kept through loads and unloads, not rebuilt (%d of 50 checks)" % kept)
	check(unloads >= 10, "chunks unloaded on the way (%d)" % unloads)
	check(w.sites.size() >= 100, "a dense table (%d sites)" % w.sites.size())


# --- what the unloads let go (WorldStream._let_go, freed on the quiet ticks after them) ---

## An unloaded chunk outlives its tick and every tick that loads, unloads or rebases, and the quiet
## ticks after free what the unloads let go, never more than RELEASE_PER_TICK pieces a tick: a swim
## east with a debug rebase there and back before every third step while something waits, then still
## steps until nothing does. A teleport frees all that waits at once.
func test_an_unload_lets_go_its_chunk_on_the_quiet_ticks_after_it() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: what an unload lets go waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 505)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var gone: Array[WeakRef] = []   # the unloaded chunks
	var outlived := 0
	var held := 0                   # busy ticks that began with something waiting
	var bad := []
	for t in 2000:
		var still := t >= 1200
		if still and w._let_go.is_empty():
			break
		var chunks := {}
		for key in w.loaded_keys():
			chunks[key] = weakref(w.chunk(key))
		var rebase := not w._let_go.is_empty() and t % 3 == 2
		if rebase:
			sim.debug_rebase(Vector2i(1, 0))
			sim.debug_rebase(Vector2i(-1, 0))
		var before := w._let_go.size()
		if not still:
			SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.ZERO if still else Vector2.RIGHT))
		var busy := rebase
		for e in sim.drain_events():
			busy = busy or e.type == "chunk_loaded" or e.type == "chunk_unloaded" or e.type == "rebased"
			if e.type == "chunk_unloaded" and chunks.has(e.key):
				var ref: WeakRef = chunks[e.key]
				gone.append(ref)
				outlived += 1 if ref.get_ref() != null else 0
		var after := w._let_go.size()
		if busy and after < before:
			bad.append("tick %d freed %d pieces on a busy tick" % [t, before - after])
		elif after < before - WorldStream.RELEASE_PER_TICK:
			bad.append("tick %d freed %d pieces" % [t, before - after])
		held += 1 if busy and before > 0 else 0
	var freed := 0
	for ref in gone:
		freed += 1 if ref.get_ref() == null else 0
	print("test-perf-world-caches: %d chunks unloaded, %d outlived their tick, %d freed after; %d busy ticks with pieces waiting" % [
		gone.size(), outlived, freed, held])
	check(bad.is_empty(), "no tick freed what it should not (%s)" % [bad.slice(0, 3)])
	check(gone.size() >= 10 and outlived == gone.size(), "every unloaded chunk outlived its tick (%d of %d)" % [outlived, gone.size()])
	check(w._let_go.is_empty() and freed == gone.size(), "the quiet ticks freed them all (%d of %d, %d pieces left)" % [
		freed, gone.size(), w._let_go.size()])
	check(held >= 10, "busy ticks came while pieces waited (%d)" % held)
	var last: Array[WeakRef] = []
	for t in 600:
		var chunks := {}
		for key in w.loaded_keys():
			chunks[key] = weakref(w.chunk(key))
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.UP))
		for e in sim.drain_events():
			if e.type == "chunk_unloaded" and chunks.has(e.key):
				last.append(chunks[e.key])
		if not last.is_empty():
			break
	check(not last.is_empty() and last[0].get_ref() != null, "a chunk unloaded on the swim north waits")
	w.teleport(sim, w.checkpoint_am[0], w.checkpoint_am[1])
	check(w._let_go.is_empty() and last[0].get_ref() == null, "a teleport frees all that waits at once")


# --- WorldStream's look-ahead generation (chunks generated on quiet ticks, handed out once) ---

static func _chunk_text(ch: WorldChunk) -> String:
	return var_to_str([ch.key, ch.size, ch.shells, ch.zones, ch.sites, ch.anchors, ch.places])


## Every chunk a swim loads equals the generator's chunk built at that moment, most of them come
## from the look-ahead (each once: never a chunk object loaded twice), and a teleport forgets them.
func test_chunks_generated_ahead_equal_the_generators_and_go_once() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the look-ahead waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 503)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var ahead := 0
	var loads := 0
	var objects := {}
	var bad := []
	for t in 1500:
		var kept: Dictionary = w._ahead.duplicate()
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT if t < 1000 else Vector2.DOWN))
		for e in sim.drain_events():
			if e.type != "chunk_loaded":
				continue
			loads += 1
			var ch := w.chunk(e.key)
			if kept.get(Vector3i(e.key.x, e.key.y, w.size)) == ch:
				ahead += 1
			if objects.has(ch.get_instance_id()):
				bad.append("tick %d: chunk %s loaded twice" % [t, e.key])
			objects[ch.get_instance_id()] = true
			if _chunk_text(ch) != _chunk_text(w.gen.chunk(w.size, e.key.x, e.key.y)):
				bad.append("tick %d: chunk %s differs from the generator's" % [t, e.key])
	check(bad.is_empty(), "%s" % [bad.slice(0, 3)])
	check(loads >= 20 and ahead * 4 >= loads * 3, "most loads came from the look-ahead (%d of %d)" % [ahead, loads])
	check(not w._ahead.is_empty(), "chunks kept ahead at the end")
	sim.debug_teleport_abs(5000.0, -3000.0)
	check(w._ahead.is_empty(), "a teleport forgets them")


## Chunks generated ahead are forgotten when the stream's generator is swapped for another or the
## same one is bound again to another seed (WorldGen.setup): the next load is the new binding's
## chunk, never one made before.
func test_chunks_generated_ahead_are_forgotten_with_their_generators_binding() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the look-ahead binding waits on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 504)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	for round in 2:
		for t in 300:
			SwimBot.overdrive(sim)
			sim.step(SimIntent.new(Vector2.RIGHT))
			sim.drain_events()
		check(not w._ahead.is_empty(), "round %d: chunks kept ahead" % round)
		if w._ahead.is_empty():
			return
		var k: Vector3i = w._ahead.keys()[0]
		var old_text := _chunk_text(w._ahead[k])
		var seed := int(w.gen.world_seed) + 7919
		if round == 0:
			w.gen.setup(w.gen.content, w.gen.species, seed)   # the same generator, bound again
		else:
			var other := WorldGen.create(w.gen.content, w.gen.species, seed)
			w.gen = other   # another generator
		var want := _chunk_text(w.gen.chunk(k.z, k.x, k.y))
		check(want != old_text, "round %d: the new binding's chunk differs" % round)
		check_eq(_chunk_text(w._generated(Vector2i(k.x, k.y))), want, "round %d: the load is the new binding's chunk" % round)
		check(w._ahead.is_empty(), "round %d: the kept chunks are forgotten" % round)


## The look-ahead's binding holds every input of WorldGen.chunk but the key and the size: chunks
## generated ahead are forgotten when the generator is bound to other content or other species (its
## version comes with its content), and when another generator bound the same takes its place. Each
## round swims until a kept chunk is one the new binding builds otherwise, changes that one input,
## and the next load of that chunk must be the new binding's.
func test_chunks_generated_ahead_are_forgotten_when_any_input_of_their_binding_changes() -> void:
	if not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: the look-ahead binding's inputs wait on: %s" % "; ".join(Gates.missing(Gates.WORLD)))
		return
	var sim: Variant = Gates.make_sim(Gates.RACER, 504)
	sim.debug_set_hidden(true)
	var w: WorldStream = sim.world
	var g: WorldGen = w.gen
	var content := g.content
	var species := g.species
	var seed := g.world_seed
	var other_content := WorldContent.load_from(Gates.content_path(), content.layout, species)
	var order: PackedStringArray = other_content.config.arrangement.region_order
	other_content.config.arrangement.region_order = PackedStringArray([order[1], order[2], order[0]])   # every region moves
	var other_species := SpeciesCatalog.load_from()
	for id in other_species.configs:
		var cfg: Dictionary = other_species.configs[id]
		if cfg.has("leash_m"):
			cfg.leash_m = float(cfg.leash_m) + 3.0   # every reach disc grows
	for change in ["content", "species", "generator"]:
		var probe: WorldGen   # bound as the stream's generator will be
		match change:
			"content":
				probe = WorldGen.create(other_content, species, seed)
			"species":
				probe = WorldGen.create(content, other_species, seed)
			"generator":
				probe = (load("res://tests/fakes/fake_world_gen.gd") as GDScript).new(content, species, seed)
		var k := Vector3i.MAX   # a kept chunk the new binding builds otherwise
		var want := ""
		for t in 1200:
			SwimBot.overdrive(sim)
			sim.step(SimIntent.new(Vector2.RIGHT if t < 600 else Vector2.DOWN))
			sim.drain_events()
			if t % 50 == 49:
				for key: Vector3i in w._ahead:
					want = _chunk_text(probe.chunk(key.z, key.x, key.y))
					if want != _chunk_text(w._ahead[key]):
						k = key
						break
				if k != Vector3i.MAX:
					break
		check(k != Vector3i.MAX, "%s: a kept chunk the new binding builds otherwise" % change)
		if k == Vector3i.MAX:
			return
		match change:
			"content":
				g.setup(other_content, species, seed)
			"species":
				g.setup(content, other_species, seed)
			"generator":
				w.gen = probe
		check_eq(_chunk_text(w._generated(Vector2i(k.x, k.y))), want, "%s: the load is the new binding's chunk" % change)
		check(w._ahead.is_empty(), "%s: the kept chunks are forgotten" % change)
		w.gen = g
		g.setup(content, species, seed)   # back to the world's own binding for the next round


# --- Site records and creatures made ahead (for the chunks generated ahead, on quiet ticks) ---

## Every script variable of `o`, the objects in it dumped the same way: a RandomNumberGenerator as its
## seed and state, a phenotype (its species' own, shared) as its instance id.
static func _dump(o: Object) -> Variant:
	if o == null:
		return null
	if o is RandomNumberGenerator:
		return [o.seed, o.state]
	if o is Phenotype:
		return o.get_instance_id()
	var out := {}
	for p in o.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = o.get(p.name)
			out[p.name] = _dump(v) if v is Object else v
	return out


## On a dense swim every site record a load puts in the table equals _site_record's for it then, and
## every site creature spawned equals, field for field, the one spawn_site makes from its record at
## its spawn tick; most of each come from what was made ahead. A rebase between the making and the
## load or the spawn moves the sites: the load derives the record again, and the spawn makes its own
## creature (the one made ahead was made for the old frame).
func test_slow_records_and_creatures_made_ahead_equal_those_made_at_the_load_and_the_spawn() -> void:
	var cost: GDScript = load("res://tests/test_endless_cost.gd")
	var fake: GDScript = load("res://tests/fakes/fake_world_gen.gd")
	if fake == null or not Gates.missing(Gates.WORLD).is_empty():
		print("test-perf-world-caches: what is made ahead waits on the endless world")
		return
	var d := Gates.data()
	var content: Variant = fake.call("fixture_content")
	var r := Lineage.found(2802, Gates.BUILD_ID, d.catalog, "hunter")
	Gates.make_racer(r.save.genome, d.catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
	var sim: PoolSim = PoolSim._create_endless(r.save, d.catalog, d.layout, d.species, content, cost.DenseGen.new(content, d.species, 2802))
	sim.debug_set_hidden(true)
	sim.drain_events()   # the creatures placed with the world have moved since
	var w := sim.world
	var field := sim.creatures
	var records := 0   # records a load took from those made ahead
	var made := 0      # creatures a spawn took from those made ahead
	var stale := 0     # made ahead for the old frame
	var spawns := 0
	var bad := []
	for t in 1500:
		var ahead_recs := {}
		for k in w._ahead_sites:
			for id in w._ahead_sites[k]:
				ahead_recs[id] = w._ahead_sites[k][id]
		var before := {}
		for id in field._prepared:
			before[id] = field._prepared[id][1]
		if t == 700:
			sim.debug_rebase(Vector2i(-3, 0))   # and the stream rebases back on the next step
		SwimBot.overdrive(sim)
		sim.step(SimIntent.new(Vector2.RIGHT))
		for e in sim.drain_events():
			if e.type == "chunk_loaded":
				for id in w._home_sites.get(e.key, {}):
					var rec: Dictionary = w.sites[id]
					records += 1 if is_same(ahead_recs.get(id), rec) else 0
					if var_to_str(rec) != var_to_str(w._site_record(rec.abs, e.key)):
						bad.append("tick %d: site %s's record differs from a new one" % [t, id])
			elif e.type == "creature_spawned" and not e.debug:
				var c := field.find(e.id)
				spawns += 1
				if before.has(c.site_id):
					if is_same(before[c.site_id], c):
						made += 1
					else:
						stale += 1
				var fresh := field._site_creature(w.sites[c.site_id], c.spawn_count, c.role)
				fresh.born_tick = c.born_tick
				CreatureBrain.start(fresh.brain, c.born_tick)
				fresh.asleep = c.asleep
				fresh.think_slot = c.think_slot
				if var_to_str(_dump(fresh)) != var_to_str(_dump(c)):
					bad.append("tick %d: %s differs from the one made at its spawn" % [t, c.id])
	check(bad.is_empty(), "%s" % [bad.slice(0, 3)])
	check(records >= 100, "loads took the records made ahead (%d)" % records)
	check(made >= 10 and spawns >= 50, "spawns took the creatures made ahead (%d of %d)" % [made, spawns])
	check(stale >= 1, "some were made for the frame before a rebase and made again at the spawn (%d)" % stale)
	print("test-perf-world-caches: made ahead: %d records loaded, %d of %d spawns, %d made again after a rebase" % [
		records, made, spawns, stale])


# --- WorldHash with mul32 and rotl32 written out ---

## WorldHash's functions before mul32, rotl32 and the round were written out in place.
class HashBefore:
	const MASK := 0xFFFFFFFF
	const SEED0 := 0x9747B28C

	static func mul32(a: int, b: int) -> int:
		return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK

	static func rotl32(x: int, r: int) -> int:
		return ((x << r) | (x >> (32 - r))) & MASK

	static func fmix32(h: int) -> int:
		h &= MASK
		h ^= h >> 16
		h = mul32(h, 0x85EBCA6B)
		h ^= h >> 13
		h = mul32(h, 0xC2B2AE35)
		h ^= h >> 16
		return h

	static func hash_ints(values: PackedInt64Array) -> int:
		var h := SEED0
		for v in values:
			h = _block(h, v & MASK)
			h = _block(h, (v >> 32) & MASK)
		h ^= (8 * values.size()) & MASK
		return fmix32(h)

	static func str32(s: String) -> int:
		var h := 0x811C9DC5
		for byte in s.to_utf8_buffer():
			h = mul32(h ^ byte, 0x01000193)
		return h

	static func mix32(a: int, b: int) -> int:
		return hash_ints(PackedInt64Array([a, b]))

	static func key(seed: int, gen_version: int, band: int, tx: int, ty: int, purpose: String) -> int:
		return hash_ints(PackedInt64Array([seed, gen_version, band, tx, ty, str32(purpose)]))

	static func _block(h: int, word: int) -> int:
		var k := mul32(word, 0xCC9E2D51)
		k = rotl32(k, 15)
		k = mul32(k, 0x1B873593)
		h ^= k
		h = rotl32(h, 13)
		return (mul32(h, 5) + 0xE6546B64) & MASK


## A random int of any size: whole 64-bit patterns (negative half the time), the edges, words with
## every bit set, and small ints of either sign, as the generator hashes them.
static func _any_int(rng: RandomNumberGenerator) -> int:
	match rng.randi_range(0, 5):
		0:
			return (rng.randi() << 32) | rng.randi()
		1:
			return [0, 1, -1, 0xFFFFFFFF, 0x100000000, 9223372036854775807, -9223372036854775807 - 1, 0x7FFFFFFF,
				-0x80000000][rng.randi_range(0, 8)]
		2:
			return rng.randi()
		3:
			return -rng.randi()
		_:
			return rng.randi_range(-5000, 5000)


func test_world_hash_equals_the_old_functions_on_random_values_and_strings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7106
	var bad := []
	for i in 4000:
		var values := PackedInt64Array()
		for j in rng.randi_range(0, 8):
			values.append(_any_int(rng))
		var a := _any_int(rng)
		var b := _any_int(rng)
		var h := rng.randi() if i % 2 == 0 else _any_int(rng)
		var text := ""
		for j in rng.randi_range(0, 12):
			text += String.chr([rng.randi_range(32, 126), rng.randi_range(0xA0, 0x7FF), rng.randi_range(0x800, 0xD7FF),
				rng.randi_range(0x10000, 0x10FFFF)][rng.randi_range(0, 3) if j % 3 == 0 else 0])
		if WorldHash.hash_ints(values) != HashBefore.hash_ints(values):
			bad.append("hash_ints(%s)" % values)
		if WorldHash.mix32(a, b) != HashBefore.mix32(a, b):
			bad.append("mix32(%d, %d)" % [a, b])
		if WorldHash.fmix32(h) != HashBefore.fmix32(h):
			bad.append("fmix32(%d)" % h)
		if WorldHash.str32(text) != HashBefore.str32(text):
			bad.append("str32(%s)" % text.c_escape())
		if WorldHash.key(a, i % 3, b % 7, values[0] if not values.is_empty() else 0, i, text) != \
				HashBefore.key(a, i % 3, b % 7, values[0] if not values.is_empty() else 0, i, text):
			bad.append("key(%d, ..., %s)" % [a, text.c_escape()])
	check(bad.is_empty(), "%d differ: %s" % [bad.size(), bad.slice(0, 3)])


# --- ChunkArena._may_reach (a collider clear of a chunk is not counted into its near grid) ---

const ArenaTests := preload("res://tests/test_chunk_arena.gd")
## Distances past the reach (r + GRID_BODY_R + GRID_SLACK) a band collider is placed at: either side
## of the reach and of GRID_SLACK, and (added to it) either side of _may_reach's margin.
const BAND_OFFSETS: Array[float] = [-0.02, -0.01, -1e-3, -1e-6, -1e-9, 0.0, 1e-9, 1e-6, 1e-5, 6e-5, 7e-5,
	1e-4, 1e-3, 0.01, 0.02]


## _may_reach's margin past the reach near chunk `key` (1e-6 tm per tm of coordinate).
static func _margin_near(key: Vector2i) -> float:
	return 1e-6 * (1.0 + 32.0 * (absi(key.x) + absi(key.y)))


## A collider in a neighbour of chunk `key`, off one of its sides (or corners) by the reach plus an
## offset (half the time plus _may_reach's margin too), at a random place along that side.
static func _band_collider(rng: RandomNumberGenerator, key: Vector2i, id: String) -> Dictionary:
	var chunk := 32.0
	var r := rng.randf_range(0.6, ChunkArena.MAX_COLLIDER_R)
	var off: float = BAND_OFFSETS[rng.randi_range(0, BAND_OFFSETS.size() - 1)] if rng.randf() < 0.7 \
			else rng.randf_range(-0.03, 0.03)
	if rng.randf() < 0.5:
		off += _margin_near(key)
	var d := r + PoolArena.GRID_BODY_R + PoolArena.GRID_SLACK + off
	var side := Vector2i([-1, 0, 1][rng.randi_range(0, 2)], [-1, 0, 1][rng.randi_range(0, 2)])
	if side == Vector2i.ZERO:
		side = Vector2i(1, 0)
	var dx := d
	var dy := d
	if side.x != 0 and side.y != 0:
		var a := rng.randf_range(0.0, PI / 2.0)
		dx = d * cos(a)
		dy = d * sin(a)
	var x := key.x * chunk + rng.randf_range(0.0, chunk)
	var y := key.y * chunk + rng.randf_range(0.0, chunk)
	if side.x < 0:
		x = key.x * chunk - dx
	elif side.x > 0:
		x = (key.x + 1) * chunk + dx
	if side.y < 0:
		y = key.y * chunk - dy
	elif side.y > 0:
		y = (key.y + 1) * chunk + dy
	return {"id": id, "x": x, "y": y, "r": r, "off": off}


func test_a_collider_judged_clear_of_a_chunk_marks_none_of_its_cells_at_the_reach_edge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4408
	for base: Vector2i in [Vector2i(0, 0), Vector2i(3125, -3125)]:   # home, and 100 km out
		var arena := ChunkArena.create_endless()
		arena.add_chunk(base, [])
		var skipped_near := 0
		var reached_near := 0
		for i in 6000:
			var c := _band_collider(rng, base, "b%d" % i)
			arena._grids[base].fill(0)
			arena._count(base, c, 1)
			var marked: int = arena._grids[base].size() - arena._grids[base].count(0)
			if not arena._may_reach(base, c):
				if marked > 0:
					check(false, "%s: a collider %s past the reach was skipped but marks %d cells" % [base, c.off, marked])
					return
				if c.off < _margin_near(base) + 1e-3:
					skipped_near += 1
			elif marked > 0 and c.off > -1e-3:
				reached_near += 1
		check(skipped_near > 100 and reached_near > 100,
			"%s: the band was exercised (%d skipped within 1e-3 tm of the margin, %d marked within 1e-3 tm of the reach)"
			% [base, skipped_near, reached_near])


func test_grids_with_colliders_at_the_reach_edge_equal_a_full_re_mark_through_loads_and_unloads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	for base: Vector2i in [Vector2i(0, 0), Vector2i(3125, -3125)]:
		for round in 8:
			var arena := ChunkArena.create_endless()
			# The middle chunk's own colliders lie off its neighbours' sides by the reach and a band.
			var lists := {}
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var key := base + Vector2i(dx, dy)
					var list: Array[Dictionary] = []
					for i in rng.randi_range(2, 8):
						var around := key + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
						var c := _band_collider(rng, around, "k%d_%d_%d_%d" % [dx, dy, round, i])
						if floori(c.x / 32.0) == key.x and floori(c.y / 32.0) == key.y:
							c.erase("off")
							list.append(c)
					lists[key] = list
			var order: Array = lists.keys()
			for i in range(order.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Vector2i = order[i]
				order[i] = order[j]
				order[j] = t
			for key: Vector2i in order:
				arena.add_chunk(key, lists[key])
				if not _grids_match(arena, "%s round %d: after loading %s" % [base, round, key]):
					return
			for key: Vector2i in order.slice(0, 5):
				arena.remove_chunk(key)
				if not _grids_match(arena, "%s round %d: after unloading %s" % [base, round, key]):
					return
	check(true, "every grid equals a full re-mark")


func _grids_match(arena: ChunkArena, what: String) -> bool:
	for k in arena.chunk_keys():
		if arena._grids[k] != ArenaTests._re_mark(arena, k):
			check(false, "%s, the grid of %s differs from a full re-mark" % [what, k])
			return false
	return true


# --- ChunkArena.route_point_kept (the colliders a seek's route can meet, kept between calls) ---

## Callers seek goals beside colliders (where a route's last blocker can lie past the goal) from a
## few tm off, creeping or jumping, while chunks load and unload and the origin moves under them
## (with them half the time): every kept route must be route_point's, and on every 8th call every
## collider that passes the blocking test from where the caller is (nearest or not) must be kept.
func test_a_kept_route_equals_route_point_through_moves_loads_and_rebases() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	var arena := ChunkArena.create_endless()
	for ky in range(-2, 2):
		for kx in range(-2, 2):
			var list: Array[Dictionary] = []
			for i in rng.randi_range(4, 10):
				list.append(ArenaTests._collider(rng, Vector2i(kx, ky), "r%d_%d_%d" % [kx, ky, i]))
			arena.add_chunk(Vector2i(kx, ky), list)
	var keeps: Array[ChunkArena.RouteKeep] = []
	var froms: Array[Vector2] = []
	var tos: Array[Vector2] = []
	for i in 8:
		keeps.append(ChunkArena.RouteKeep.new())
		froms.append(Vector2.ZERO)
		tos.append(Vector2.ZERO)
		_new_goal(rng, arena, i, froms, tos)
	var calls := 0
	var held := 0
	var blocked_held := 0
	var blockers := 0
	var origin := Vector2.ZERO
	for step in 40000:
		var i := rng.randi_range(0, keeps.size() - 1)
		var roll := rng.randf()
		if roll < 0.002:
			# A chunk unloads or loads again (the epoch moves).
			var key := Vector2i(rng.randi_range(-2, 1), rng.randi_range(-2, 1))
			if arena.has_chunk(key):
				arena.remove_chunk(key)
			else:
				var list: Array[Dictionary] = []
				for j in rng.randi_range(4, 10):
					list.append(ArenaTests._collider(rng, key, "s%d_%d" % [step, j]))
				arena.add_chunk(key, list)
		elif roll < 0.003:
			# A rebase by whole chunks: the callers move with it, or (half the time) stay where they are
			# in local terms while the colliders move under them.
			var by := Vector2(32.0 * rng.randi_range(-1, 1), 32.0 * rng.randi_range(-1, 1))
			origin += by
			arena.set_origin(origin.x, origin.y)
			if rng.randf() < 0.5:
				for j in keeps.size():
					froms[j] -= by
					tos[j] -= by
		elif roll < 0.01:
			_new_goal(rng, arena, i, froms, tos)
		elif roll < 0.02:
			froms[i] += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))   # a jump past the keep
		else:
			froms[i] += Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)) + (tos[i] - froms[i]).limit_length(0.05)
		var body_r := [0.5, 0.9, 1.4][i % 3] as float
		var side := [0, 1, -1][(i / 3) % 3] as int
		var key_before := keeps[i].key
		var got := arena.route_point_kept(froms[i], tos[i], body_r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side, keeps[i])
		var want := arena.route_point(froms[i], tos[i], body_r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side)
		calls += 1
		if got != want:
			check(false, "step %d: the kept route %s differs from route_point's %s" % [step, got, want])
			return
		if step % 8 == 0:
			var missing := _blockers_not_kept(arena, froms[i], tos[i], body_r, keeps[i])
			blockers += _blockers_not_kept(arena, froms[i], tos[i], body_r, null).size()
			if not missing.is_empty():
				check(false, "step %d: colliders %s could block but are not kept" % [step, missing])
				return
		if keeps[i].key == key_before:
			held += 1
			if want != tos[i]:
				blocked_held += 1
	print("test-perf-world-caches: the kept route held on %d of %d calls, %d of them blocked; %d blockers checked kept" % [
		held, calls, blocked_held, blockers])
	check(held > calls / 2, "the keep held on most calls (%d of %d)" % [held, calls])
	check(blocked_held > 1000, "kept routes went round a collider (%d)" % blocked_held)
	check(blockers > 2000, "blockers were checked (%d)" % blockers)


## A hunter's stand-off point and a fleeing body's way out move with it: with both ends of every
## route creeping (and now and then jumping) while chunks load and unload and the origin moves, every
## kept route is route_point's, and on every 8th call every collider that could block is kept.
func test_a_kept_route_equals_route_point_while_its_goal_creeps_too() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var arena := ChunkArena.create_endless()
	for ky in range(-2, 2):
		for kx in range(-2, 2):
			var list: Array[Dictionary] = []
			for i in rng.randi_range(4, 10):
				list.append(ArenaTests._collider(rng, Vector2i(kx, ky), "r%d_%d_%d" % [kx, ky, i]))
			arena.add_chunk(Vector2i(kx, ky), list)
	var keeps: Array[ChunkArena.RouteKeep] = []
	var froms: Array[Vector2] = []
	var tos: Array[Vector2] = []
	for i in 8:
		keeps.append(ChunkArena.RouteKeep.new())
		froms.append(Vector2.ZERO)
		tos.append(Vector2.ZERO)
		_new_goal(rng, arena, i, froms, tos)
	var calls := 0
	var held := 0
	var blocked_held := 0
	var origin := Vector2.ZERO
	for step in 30000:
		var i := rng.randi_range(0, keeps.size() - 1)
		var roll := rng.randf()
		if roll < 0.002:
			var key := Vector2i(rng.randi_range(-2, 1), rng.randi_range(-2, 1))
			if arena.has_chunk(key):
				arena.remove_chunk(key)
			else:
				var list: Array[Dictionary] = []
				for j in rng.randi_range(4, 10):
					list.append(ArenaTests._collider(rng, key, "s%d_%d" % [step, j]))
				arena.add_chunk(key, list)
		elif roll < 0.003:
			var by := Vector2(32.0 * rng.randi_range(-1, 1), 32.0 * rng.randi_range(-1, 1))
			origin += by
			arena.set_origin(origin.x, origin.y)
			if rng.randf() < 0.5:
				for j in keeps.size():
					froms[j] -= by
					tos[j] -= by
		elif roll < 0.01:
			_new_goal(rng, arena, i, froms, tos)
		elif roll < 0.02:
			tos[i] += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))   # a goal jumping past the keep
		else:
			# Both ends creep, the goal about as fast as the caller (a stand-off point on a moving body).
			froms[i] += Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)) + (tos[i] - froms[i]).limit_length(0.05)
			tos[i] += Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		var body_r := [0.5, 0.9, 1.4][i % 3] as float
		var side := [0, 1, -1][(i / 3) % 3] as int
		var key_before := keeps[i].key
		var got := arena.route_point_kept(froms[i], tos[i], body_r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side, keeps[i])
		var want := arena.route_point(froms[i], tos[i], body_r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side)
		calls += 1
		if got != want:
			check(false, "step %d: the kept route %s differs from route_point's %s" % [step, got, want])
			return
		if step % 8 == 0:
			var missing := _blockers_not_kept(arena, froms[i], tos[i], body_r, keeps[i])
			if not missing.is_empty():
				check(false, "step %d: colliders %s could block but are not kept" % [step, missing])
				return
		if keeps[i].key == key_before:
			held += 1
			if want != tos[i]:
				blocked_held += 1
	print("test-perf-world-caches: with the goal creeping, the kept route held on %d of %d calls, %d of them blocked" % [
		held, calls, blocked_held])
	check(held > calls / 2, "the keep held on most calls (%d of %d)" % [held, calls])
	check(blocked_held > 500, "kept routes went round a collider (%d)" % blocked_held)


## The two margins of a keep, each at the place only it covers: a collider past the goal that blocks
## though its centre lies 2 r + body_r + clearance - 1.6 tm off the segment (the 2 r), and one the
## caller comes to block by moving 0.99 tm without the keep being picked again (ROUTE_KEEP_TM).
func test_a_kept_route_keeps_a_blocker_past_the_goal_and_one_the_caller_moves_into() -> void:
	var body_r := 0.5
	var clearance := PoolArena.ROUTE_CLEARANCE
	var shells: Array[Dictionary] = [{"id": "past", "center": Vector2(15.9, 14.55), "radius": 4.0}]
	var arena := ChunkArena.from_shells(shells)
	var keep := ChunkArena.RouteKeep.new()
	var from := Vector2(2.0, 10.0)
	var to := Vector2(12.0, 10.0)
	var want := arena.route_point(from, to, body_r, clearance, PoolArena.ROUTE_MARGIN, 0)
	check(want != to, "the collider past the goal blocks")
	check_eq(arena.route_point_kept(from, to, body_r, clearance, PoolArena.ROUTE_MARGIN, 0, keep), want, "and is kept")
	shells = [{"id": "beside", "center": Vector2(3.0, 3.9), "radius": 0.6}]
	arena = ChunkArena.from_shells(shells)
	keep = ChunkArena.RouteKeep.new()
	from = Vector2(2.0, 2.0)
	to = Vector2(12.0, 2.0)
	check_eq(arena.route_point_kept(from, to, body_r, clearance, PoolArena.ROUTE_MARGIN, 0, keep), to, "nothing blocks at first")
	var key := keep.key
	from = Vector2(2.0, 2.99)
	want = arena.route_point(from, to, body_r, clearance, PoolArena.ROUTE_MARGIN, 0)
	check(want != to, "the collider beside the route blocks once the caller has moved 0.99 tm")
	check_eq(arena.route_point_kept(from, to, body_r, clearance, PoolArena.ROUTE_MARGIN, 0, keep), want, "and was kept")
	check_eq(keep.key, key, "by the keep picked before the move")


## B-7: a keep is carried over a chunk loaded or unloaded clear of the box its pick searched (its
## indices moved by the change, the epoch brought up to date) and picked again for a chunk that
## touches the box. Each time it holds what a fresh pick from the same place holds, and the route is
## route_point's.
func test_a_kept_route_is_carried_over_a_far_chunk_change_and_picked_again_for_a_near_one() -> void:
	var body_r := 0.5
	var clearance := PoolArena.ROUTE_CLEARANCE
	var margin := PoolArena.ROUTE_MARGIN
	var shells: Array[Dictionary] = [{"id": "a", "center": Vector2(7.0, 10.5), "radius": 1.0},
		{"id": "b", "center": Vector2(25.0, 25.0), "radius": 1.0}]
	var arena := ChunkArena.from_shells(shells)
	var keep := ChunkArena.RouteKeep.new()
	var from := Vector2(2.0, 10.0)
	var to := Vector2(12.0, 10.0)
	var want := arena.route_point(from, to, body_r, clearance, margin, 0)
	check(want != to, "collider a blocks the route")
	check_eq(arena.route_point_kept(from, to, body_r, clearance, margin, 0, keep), want, "the kept route is route_point's")
	var first_near := keep.near.duplicate()   # packed arrays are shared by reference
	check(not first_near.is_empty(), "the keep holds collider a")
	# Far: chunk (-5, -5) sorts before (0, 0), so every index of a moves on by its two colliders.
	var far: Array[Dictionary] = [{"id": "f1", "x": -150.0, "y": -150.0, "r": 1.0}, {"id": "f2", "x": -140.0, "y": -145.0, "r": 1.0}]
	arena.add_chunk(Vector2i(-5, -5), far)
	check_eq(arena.route_point_kept(from, to, body_r, clearance, margin, 0, keep), arena.route_point(from, to, body_r, clearance, margin, 0),
		"after a far load the route is route_point's")
	check_eq(int(keep.key[0]), arena.epoch, "the keep is brought up to date")
	var fresh := ChunkArena.RouteKeep.new()
	arena._keep_route(from, to, body_r, clearance, fresh)
	check_eq(keep.near, fresh.near, "carried: what a fresh pick holds")
	check_eq(keep.near[0], first_near[0] + 2, "a's index moved on by the two colliders before it")
	arena.remove_chunk(Vector2i(-5, -5))
	check_eq(arena.route_point_kept(from, to, body_r, clearance, margin, 0, keep), want, "after a far unload the route is route_point's")
	check_eq(keep.near, first_near, "and the keep holds a at its old index again")
	# Near: chunk (-1, 0) touches the box; its collider lies within reach of the segment.
	var near: Array[Dictionary] = [{"id": "n", "x": -0.5, "y": 10.0, "r": 1.0}]
	arena.add_chunk(Vector2i(-1, 0), near)
	check_eq(arena.route_point_kept(from, to, body_r, clearance, margin, 0, keep), arena.route_point(from, to, body_r, clearance, margin, 0),
		"after a near load the route is route_point's")
	fresh = ChunkArena.RouteKeep.new()
	arena._keep_route(from, to, body_r, clearance, fresh)
	check_eq(keep.near, fresh.near, "picked again: the new collider is in it")
	check_eq(keep.near.size(), first_near.size() + 1, "one more collider than before")


## A keep is picked again when one input of its key changes on its own: the goal (to past a collider
## the old route never came near), where the caller is (a move of some 20 tm, well past ROUTE_KEEP_TM,
## to beside one) or the body's radius (a wider body reaches one the narrow body's pick left out).
## Each time the kept route must be route_point's, which goes round that collider.
func test_a_kept_route_is_picked_again_for_a_new_goal_a_far_move_or_a_wider_body() -> void:
	var clearance := PoolArena.ROUTE_CLEARANCE
	var margin := PoolArena.ROUTE_MARGIN
	var cases: Array[Dictionary] = [
		{"what": "a new goal", "rock": Vector2(22.0, 10.0), "r": 1.0,
			"from": Vector2(2.0, 10.0), "to": Vector2(12.0, 10.0), "body_r": 0.5,
			"from_2": Vector2(2.0, 10.0), "to_2": Vector2(28.0, 10.0), "body_r_2": 0.5},
		{"what": "a far move", "rock": Vector2(6.0, 16.0), "r": 1.0,
			"from": Vector2(16.0, 2.0), "to": Vector2(16.0, 16.0), "body_r": 0.5,
			"from_2": Vector2(2.0, 16.0), "to_2": Vector2(16.0, 16.0), "body_r_2": 0.5},
		{"what": "a wider body", "rock": Vector2(7.0, 13.0 + clearance), "r": 0.5,
			"from": Vector2(2.0, 10.0), "to": Vector2(12.0, 10.0), "body_r": 0.5,
			"from_2": Vector2(2.0, 10.0), "to_2": Vector2(12.0, 10.0), "body_r_2": 3.0},
	]
	for c in cases:
		var shells: Array[Dictionary] = [{"id": "rock", "center": c.rock, "radius": c.r}]
		var arena := ChunkArena.from_shells(shells)
		var keep := ChunkArena.RouteKeep.new()
		check_eq(arena.route_point_kept(c.from, c.to, c.body_r, clearance, margin, 0, keep), c.to,
			"%s: nothing blocks the first route" % c.what)
		check(keep.near.is_empty(), "%s: and its pick leaves the collider out" % c.what)
		var want := arena.route_point(c.from_2, c.to_2, c.body_r_2, clearance, margin, 0)
		check(want != c.to_2, "%s: the collider blocks the second route" % c.what)
		check_eq(arena.route_point_kept(c.from_2, c.to_2, c.body_r_2, clearance, margin, 0, keep), want,
			"%s: and the keep, picked again, goes round it" % c.what)


## A keep holds through a rebase that moves its caller with the colliders (the same absolute places),
## and is picked again for a caller the rebase leaves where it was in local terms: a collider the old
## pick never looked at (36 tm off) is then across its route, and the kept route goes round it.
func test_a_kept_route_holds_through_a_rebase_that_moves_its_caller_and_not_one_that_leaves_it() -> void:
	var clearance := PoolArena.ROUTE_CLEARANCE
	var margin := PoolArena.ROUTE_MARGIN
	var shells: Array[Dictionary] = [{"id": "rock", "center": Vector2(38.0, 10.0), "radius": 1.0}]
	var arena := ChunkArena.from_shells(shells)
	var keep := ChunkArena.RouteKeep.new()
	var from := Vector2(2.0, 10.0)
	var to := Vector2(12.0, 10.0)
	check_eq(arena.route_point_kept(from, to, 0.5, clearance, margin, 0, keep), to, "nothing blocks at first")
	check(keep.near.is_empty(), "and the pick leaves the collider out")
	var key := keep.key
	var by := Vector2(32.0, 0.0)
	arena.set_origin(by.x, by.y)   # the collider is now at local (6, 10)
	check_eq(arena.route_point_kept(from - by, to - by, 0.5, clearance, margin, 0, keep), to - by,
		"a caller the rebase moved still has nothing in its way")
	check_eq(keep.key, key, "and keeps its pick")
	var want := arena.route_point(from, to, 0.5, clearance, margin, 0)
	check(want != to, "a caller the rebase left where it was has the collider across its route")
	check_eq(arena.route_point_kept(from, to, 0.5, clearance, margin, 0, keep), want, "and the keep, picked again, goes round it")
	check(keep.key != key, "picked again")


## Every collider that passes route_point's blocking test from `from` to `to` (its loop's arithmetic,
## over every collider) and is not in `keep` (all of them when `keep` is null).
static func _blockers_not_kept(arena: ChunkArena, from: Vector2, to: Vector2, body_r: float, keep: ChunkArena.RouteKeep) -> Array:
	var out := []
	var to_target := to - from
	var length := to_target.length()
	if length < 1e-6:
		return out
	var dir := to_target / length
	for k in arena._centers.size():
		var c: Vector2 = arena._centers[k] - from
		var along := c.dot(dir)
		var rock_r := arena._radii[k]
		if along <= 0.0 or along >= length + rock_r:
			continue
		var off := c - dir * along
		if off.length() < rock_r + body_r + PoolArena.ROUTE_CLEARANCE and (keep == null or not keep.near.has(k)):
			out.append(k)
	return out


## Caller `i`'s next goal: beside a random collider (up to 2 r + 2.5 tm from its centre, so the
## route's blocker may lie past it) or, one time in four, anywhere; it starts 2 to 25 tm away.
static func _new_goal(rng: RandomNumberGenerator, arena: ChunkArena, i: int, froms: Array[Vector2], tos: Array[Vector2]) -> void:
	var to := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
	if rng.randf() < 0.75 and not arena._centers.is_empty():
		var k := rng.randi_range(0, arena._centers.size() - 1)
		to = arena._centers[k] + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.0, 2.0 * arena._radii[k] + 2.5)
	tos[i] = to
	froms[i] = to + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(2.0, 25.0)
