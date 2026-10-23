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
