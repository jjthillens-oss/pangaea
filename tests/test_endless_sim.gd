extends TestCase
## The endless sim end to end (S1 T2.9), on the real WorldGen with the fixture world (T1.7, T1.9):
## the save path (the absolute position in am, float64, written and restored exactly), and
## determinism: two runs of a straight swim hash the same (G13), and every key of the world's
## snapshot is in the hash (T2.9b). With growth (S2 T2.7, S2G21): every key the growth adds to the
## world block (the meter's, the remnants', the carrion's own radii and lifetimes) is in the hash,
## the prefetch is not, and two runs through a growth hash the same. S3 (T2.8, BP3-12): two runs
## through 2 to 3 and 3 to 4 hash the same, and every S3 snapshot key is absent at its default and in
## the hash.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const SEED := 4309
const TWO_RUN_TICKS := 3600
const HASH_EVERY := 600
const RICH_TICKS := 900                ## the perturbation base's swim east: sleepers, slots, site counts
## The world snapshot key each perturbation changes (the counters have one each besides).
const WORLD_PERTURBATIONS := {
	"origin_am.x by one ulp": "origin_am",
	"checkpoint heading": "checkpoint_am",
	"respawn_pending": "respawn_pending",
	"one chunk removed": "chunks",
	"one zone stream drawn once": "zone_rngs",
	"a site_counts entry": "site_counts",
	"a sleeper woken": "sleeping",
	"a slot swapped": "slots",
	"_cell_tile": "cell_tile",
	"gen_version": "gen_version",
	"size": "size",
}

## The world keys growth adds (BP-20: none without it), each with its perturbation's name.
const GROWTH_WORLD_KEYS := {"growth": "growth meter", "remnants": "remnant position", "carrion_radius": "carrion radius",
	"carrion_lifetime": "carrion lifetime"}
## Every key of Growth.snapshot(), each perturbed by _perturb_growth("growth <key>").
const GROWTH_KEYS: PackedStringArray = ["armed", "beat_until", "blocked", "blocker", "calm", "closing", "discoveries", "due",
	"energy_at_death", "full_since", "last_bite", "last_meal", "last_ram", "meter", "paid", "trigger"]
## Every key of a remnant's snapshot, each perturbed by _perturb_growth("remnant <key>").
const REMNANT_KEYS: PackedStringArray = ["born_tick", "flee_speed", "heading", "health", "id", "leaving", "number", "position",
	"prev_position", "radius", "species", "velocity"]
const GROWN_SWIM_TICKS := 240           ## the growth base's swim before its forced growth
const GROWN_AFTER_TICKS := 30           ## and after it
const GROWTH_RUN_TICKS := 720           ## each of the two runs through a growth (it grows near tick 430)
const GROWTH_HASH_EVERY := 60
const PREFETCH_WAIT_TICKS := 60    ## BP-4: the prefetch holds a chunk within this many ticks of the fill
const B1_WORLD := "res://tests/fixtures/world/world_b1_min.json"
## BP3-12 (1): the ticks after each band-1 growth at which the two runs' hashes are read.
const BAND_HASH_AT := [600, 1800, 3600]
## s3-sim 3.14 (as BP3-2 amends it), the sim snapshot's S3 keys, each with its perturbation's name.
## The chunk rows (morsel_sites, zone and site bloom in WorldChunk.to_dict) are T3's digest.
const S3_KEYS := {
	"last_strike_hit_tick": "a strike hit 3 ticks ago",
	"last_sting_tick": "a sting 3 ticks ago",
	"token_closed_until": "the token closed for 40 ticks",
	"morsel_sites": "a morsel-site entry",
	"landmark_anchor": "a landmark anchor",
	"carrion species": "a carrion item's species",
	"carrion site": "a carrion item's site",
	"brain drift_phase": "a hazard's drift phase",
	"brain drift_period": "a hazard's drift period",
	"brain bloom_offset": "a brain's bloom schedule",
}

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _endless(at := PackedFloat64Array()) -> PoolSim:
	return FakeWorldGen.real_sim(SEED, catalog, layout, species, at)


func test_an_endless_save_writes_the_absolute_position() -> void:
	var sim := _endless()
	var rebased := 0
	for t in 3000:
		sim.step(SimIntent.new(Vector2(1.0, -0.4)))
		rebased += _count(sim.drain_events(), "rebased")
	check(rebased >= 1, "the swim moved the origin (%d)" % rebased)
	sim.write_position_to_save()
	var a := sim.absolute_position_am()
	check_eq(sim.save.player.position, PlaneSpace.to_save_abs(a[0], a[1]), "to_save_abs(absolute_position_am())")
	check_eq(PlaneSpace.from_save_abs(sim.save.player.position), a, "and it reads back exactly")
	check(a[0] > 100.0, "far from the spawn (%.2f)" % a[0])
	check_eq(a, PackedFloat64Array([sim.world.origin_x_am + float(sim.motion.position.x),
		sim.world.origin_y_am + float(sim.motion.position.y)]), "the origin plus the local place, in float64")


func test_an_endless_create_restores_the_origin_from_the_save_exactly() -> void:
	var at := PackedFloat64Array([5000.123456789, -3210.987654321])
	var sim := _endless(at)
	check_eq(sim.world.origin_x_am, at[0], "origin x exactly")
	check_eq(sim.world.origin_y_am, at[1], "origin y exactly")
	check(sim.motion.position.length() < 2.0, "the cell at the clear point nearest the origin")
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "clear")
	check_near(sim.motion.heading, sim._nearest_zone_direction(sim.motion.position).angle(), 1e-6,
		"away from the spawn it faces the nearest zone")
	for key in sim.world.view_set_keys(sim.motion.position):
		check(sim.world.chunk(key) != null, "view-set chunk %s loaded" % key)
	# Written back at once, the save holds the same place (the cell is at the origin's clear point).
	sim.write_position_to_save()
	var back := PlaneSpace.from_save_abs(sim.save.player.position)
	check_near(back[0], at[0] + sim.motion.position.x, 1e-9, "x round trip")
	check_near(back[1], at[1] + sim.motion.position.y, 1e-9, "y round trip")


func test_a_new_game_at_the_spawn_faces_the_spawn_heading() -> void:
	var sim := _endless()
	var home := sim.world.content.home
	check_eq(sim.world.origin_x_am, home.spawn[0], "origin at the spawn")
	check_eq(sim.world.origin_y_am, home.spawn[1], "origin at the spawn")
	check_near(sim.motion.heading, home.spawn_heading, 1e-9, "the spawn heading")


## A save inside a shell: the origin is still the saved place, and the cell takes the nearest clear
## point (plan E).
func test_a_restored_place_inside_a_shell_moves_the_cell_not_the_origin() -> void:
	# The centre of the largest shell the home view set holds.
	var home := _endless()
	var shell := {}
	for key in home.world.loaded_keys():
		for s in home.world.chunk(key).shells:
			if s.kind == "shell" and (shell.is_empty() or float(s.r) > float(shell.r)):
				shell = s
	check(not shell.is_empty(), "a shell near home")
	if shell.is_empty():
		return
	var at := PackedFloat64Array([float(shell.x), float(shell.y)])
	var sim := _endless(at)
	check_eq(sim.world.origin_x_am, at[0], "origin x")
	check_eq(sim.world.origin_y_am, at[1], "origin y")
	check(sim.motion.position.length() >= float(shell.r) + sim.phenotype.radius - 1e-4,
		"the cell outside the shell (%.3f, r %.2f)" % [sim.motion.position.length(), float(shell.r)])
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "at a clear point")


## G13 (B-12): two runs of the same straight swim east, overdriven at 6 tm/s, hash the same every
## 600 ticks, by state_hash() and by the snapshot's sha256 (spine 3.12 records both). The swim
## rebases, loads, unloads, spawns and puts creatures to sleep, so the world keys move under it.
func test_two_runs_of_a_straight_swim_give_the_same_hash() -> void:
	var runs: Array[Dictionary] = []
	for i in 2:
		var sim := _endless()
		var bot = SwimBot.new(Vector2.RIGHT)
		var run := {"hashes": [], "shas": [], "rebased": 0, "chunk_loaded": 0, "chunk_unloaded": 0, "creature_spawned": 0,
			"creature_slept": 0}
		for t in TWO_RUN_TICKS:
			SwimBot.overdrive(sim)
			sim.step(bot.next_intent(sim))
			for e in sim.drain_events():
				if run.has(e.type):
					run[e.type] += 1
			if (t + 1) % HASH_EVERY == 0:
				run.hashes.append(sim.state_hash())
				run.shas.append(JSON.stringify(sim.snapshot(), "", true, true).sha256_text())
		run["x_am"] = sim.absolute_position_am()[0]
		runs.append(run)
	print("test-endless-sim: two runs east at 6 tm/s to x %.1f am: %d rebases, %d loads, %d unloads, %d spawns, %d sleeps; last hash %d, sha %s" % [
		runs[0].x_am, runs[0].rebased, runs[0].chunk_loaded, runs[0].chunk_unloaded, runs[0].creature_spawned,
		runs[0].creature_slept, runs[0].hashes[-1], str(runs[0].shas[-1]).left(16)])
	check_eq(runs[0].hashes.size(), TWO_RUN_TICKS / HASH_EVERY, "a hash every %d ticks" % HASH_EVERY)
	check_eq(runs[1].hashes, runs[0].hashes, "the same state_hash() at every one")
	check_eq(runs[1].shas, runs[0].shas, "and the same snapshot sha256")
	check(float(runs[0].x_am) > 300.0, "it swam east (%.1f am)" % float(runs[0].x_am))
	for key in ["rebased", "chunk_loaded", "chunk_unloaded", "creature_spawned", "creature_slept"]:
		check(int(runs[0][key]) > 0, "%s happened (%d)" % [key, int(runs[0][key])])


## Every key of the world's snapshot is in the hash: on a sim swum east until it has sleepers, awake
## creatures on two think slots and site counts, one perturbation each changes state_hash(), and
## undone the hash is the base's again (so that change alone did it). A world key with no
## perturbation here fails the test.
func test_every_world_key_changes_the_state_hash() -> void:
	var sim := _rich_endless()
	var w := sim.world
	var h0 := sim.state_hash()
	check_eq(_rich_endless().state_hash(), h0, "the same build hashes the same")
	check(not w.sleeping_ids().is_empty(), "a sleeper (%s)" % w.sleeping_ids())
	check(not _two_slots(sim).is_empty(), "awake creatures on two think slots (%s)" % w._slots(sim))
	var names: Array = WORLD_PERTURBATIONS.keys()
	var covers := {}
	for what in WORLD_PERTURBATIONS:
		covers[WORLD_PERTURBATIONS[what]] = true
	for k in _sorted_keys(w.counters):
		names.append("counter %s" % k)
	covers["counters"] = true
	for what in names:
		var undo: Callable = _perturb_world(sim, what)
		check(sim.state_hash() != h0, "perturbing %s changes the hash" % what)
		undo.call()
		check_eq(sim.state_hash(), h0, "and undoing %s restores it" % what)
	check_eq(_sorted_keys(covers), _sorted_keys(w.snapshot(sim)), "every world key has its perturbation")


## S2G21: with growth on, every key growth adds to the world block changes state_hash(): each key
## of the meter's snapshot, each key of a remnant's, a carrion item's own radius and its own
## lifetime; undone, the hash is the base's again. The lists are the snapshot's keys exactly, so a
## key the snapshot drops (or adds without a perturbation here) fails the test.
func test_every_growth_key_changes_the_state_hash() -> void:
	var sim := _grown_endless()
	var w := sim.world
	var h0 := sim.state_hash()
	check_eq(_grown_endless().state_hash(), h0, "the same build hashes the same")
	check_eq(sim.size(), 2, "the base grew")
	check(not sim.remnants.items.is_empty(), "a remnant")
	check(not sim.carrion.items.is_empty(), "a carrion item")
	var snap := w.snapshot(sim)
	check_eq(_sorted_keys(snap.growth), Array(GROWTH_KEYS), "the meter's snapshot keys")
	check_eq(_sorted_keys(snap.remnants[0]), Array(REMNANT_KEYS), "a remnant's snapshot keys")
	var covers := {"counters": true}
	for what in WORLD_PERTURBATIONS:
		covers[WORLD_PERTURBATIONS[what]] = true
	covers.merge(GROWTH_WORLD_KEYS)
	check_eq(_sorted_keys(covers), _sorted_keys(snap), "every world key with growth on has its perturbation")
	var names: Array = GROWTH_WORLD_KEYS.values()
	for key in GROWTH_KEYS:
		names.append("growth %s" % key)
	for key in REMNANT_KEYS:
		names.append("remnant %s" % key)
	for what: String in names:
		var undo: Callable = _perturb_growth(sim, what)
		check(sim.state_hash() != h0, "perturbing %s changes the hash" % what)
		undo.call()
		check_eq(sim.state_hash(), h0, "and undoing %s restores it" % what)


## BP-4: the next size's prefetch is a cache, not state: while it holds chunks the snapshot has no
## key for it (world block or meter), and emptying it leaves the hash as it was.
func test_the_snapshot_has_no_prefetch_key() -> void:
	var sim := FakeWorldGen.real_sim(SEED, catalog, layout, species, PackedFloat64Array(), true)
	var w := sim.world
	check(sim.debug_fill_meter(0.95), "the ring nearly full (prefetch_share 0.9)")
	for t in PREFETCH_WAIT_TICKS:   # the first ticks load and generate ahead; the prefetch waits for a quiet one
		sim.step(SimIntent.new(Vector2(0.4, 0.0)))
		if not w._next_chunks.is_empty():
			break
	sim.drain_events()
	check(not w._next_chunks.is_empty(), "the prefetch holds %d chunks" % w._next_chunks.size())
	var snap := w.snapshot(sim)
	var keys: Array = snap.keys() + (snap.growth as Dictionary).keys()
	for key: String in keys:
		check(not key.contains("prefetch") and not key.contains("next"), "no prefetch key (%s)" % key)
	var h := sim.state_hash()
	w._clear_next()
	check(w._next_chunks.is_empty(), "the prefetch emptied")
	check_eq(sim.state_hash(), h, "the same hash without it")


## S2G21: two runs of the same swim through a growth (the ring filled by the dev command, the calm
## window grows it) hash the same every GROWTH_HASH_EVERY ticks, by state_hash() and by the
## snapshot's sha256, and grow on the same tick.
func test_two_runs_through_a_growth_give_the_same_hash() -> void:
	var runs: Array[Dictionary] = []
	for i in 2:
		var sim := FakeWorldGen.real_sim(SEED, catalog, layout, species, PackedFloat64Array(), true)
		var bot = SwimBot.new(Vector2.RIGHT)
		var run := {"hashes": [], "shas": [], "grew_at": -1}
		for t in GROWTH_RUN_TICKS:
			if t == 120:
				check(sim.debug_fill_meter(1.0), "the ring full")
			sim.step(bot.next_intent(sim) if run.grew_at < 0 else SimIntent.new(Vector2(0.3, 0.2)))
			for e in sim.drain_events():
				if e.type == "grew":
					run.grew_at = t
			if (t + 1) % GROWTH_HASH_EVERY == 0:
				run.hashes.append(sim.state_hash())
				run.shas.append(JSON.stringify(sim.snapshot(), "", true, true).sha256_text())
		run["size"] = sim.size()
		runs.append(run)
	print("test-endless-sim: two runs through a growth: grew at tick %d, size %d; last hash %d" % [runs[0].grew_at, runs[0].size,
		runs[0].hashes[-1]])
	check(int(runs[0].grew_at) > 120, "the first run grew (tick %d)" % runs[0].grew_at)
	check_eq(runs[1].grew_at, runs[0].grew_at, "on the same tick")
	check_eq(runs[1].hashes, runs[0].hashes, "the same state_hash() every %d ticks" % GROWTH_HASH_EVERY)
	check_eq(runs[1].shas, runs[0].shas, "and the same snapshot sha256")


## The growth base: the real fixture world with growth on, a GROWN_SWIM_TICKS swim east, a rammer
## (prey at size 2) beside the cell and a carrion item before it, the creatures frozen, then a
## forced growth and GROWN_AFTER_TICKS ticks: a remnant, carrion of its own radius, a meter at size 2.
func _grown_endless() -> PoolSim:
	var sim := FakeWorldGen.real_sim(SEED, catalog, layout, species, PackedFloat64Array(), true)
	var bot = SwimBot.new(Vector2.RIGHT)
	for t in GROWN_SWIM_TICKS:
		sim.step(bot.next_intent(sim))
	sim.debug_set_ai_frozen(true)
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-6.0, 3.0), 0.0), "a rammer beside the cell")
	sim.carrion.spawn(sim.motion.position + Vector2(2.0, -3.0), "test", 20.0)
	check(sim.debug_force_growth(), "the forced growth")
	for t in GROWN_AFTER_TICKS:
		sim.step(SimIntent.new())
	sim.drain_events()
	return sim


## Applies `what` (a growth world key's, a meter key's or a remnant key's perturbation) to `sim`
## and returns the Callable that undoes it.
func _perturb_growth(sim: PoolSim, what: String) -> Callable:
	var g := sim.growth
	var r: RemnantField.Remnant = sim.remnants.items[0] if not sim.remnants.items.is_empty() else null
	var item: Dictionary = sim.carrion.items[0] if not sim.carrion.items.is_empty() else {}
	match what:
		"growth meter":
			var m := g.meter
			g.meter = m + 0.5
			return func() -> void: g.meter = m
		"growth trigger":
			var v := g.trigger
			g.trigger = "press" if v != "press" else "auto"
			return func() -> void: g.trigger = v
		"growth armed":
			g.armed = not g.armed
			return func() -> void: g.armed = not g.armed
		"growth due":
			g.due = not g.due
			return func() -> void: g.due = not g.due
		"growth calm":
			g.calm_ticks += 1
			return func() -> void: g.calm_ticks -= 1
		"growth full_since":
			g.full_since += 1
			return func() -> void: g.full_since -= 1
		"growth blocked":
			g.blocked_ticks += 1
			return func() -> void: g.blocked_ticks -= 1
		"growth blocker":
			var v := g.blocker
			g.blocker = "eating" if v != "eating" else "hunted"
			return func() -> void: g.blocker = v
		"growth beat_until":
			g.beat_until += 1
			return func() -> void: g.beat_until -= 1
		"growth last_meal":
			g.last_meal += 1
			return func() -> void: g.last_meal -= 1
		"growth last_bite":
			g.last_bite += 1
			return func() -> void: g.last_bite -= 1
		"growth last_ram":
			g.last_ram += 1
			return func() -> void: g.last_ram -= 1
		"growth closing":
			g.closing.append([sim.tick, {"c_x": 1.0}])
			return func() -> void: g.closing.pop_back()
		"growth paid":
			(g.paid.food as Array).append("x_look")
			return func() -> void: (g.paid.food as Array).pop_back()
		"growth discoveries":
			g.discoveries.append({"type": "place", "id": "x_place", "size": 2})
			return func() -> void: g.discoveries.pop_back()
		"growth energy_at_death":
			var v := g.energy_at_death
			g.energy_at_death = v + 1.0
			return func() -> void: g.energy_at_death = v
		"carrion radius":
			var v := float(item.radius)
			item.radius = v + 0.1
			return func() -> void: item.radius = v
		"carrion lifetime":
			var v := float(item.lifetime)
			item.lifetime = v + 1.0
			return func() -> void: item.lifetime = v
		"remnant position":
			var v := r.motion.position
			r.motion.position = v + Vector2(0.5, 0.0)
			return func() -> void: r.motion.position = v
		"remnant prev_position":
			var v := r.motion.prev_position
			r.motion.prev_position = v + Vector2(0.5, 0.0)
			return func() -> void: r.motion.prev_position = v
		"remnant velocity":
			var v := r.motion.velocity
			r.motion.velocity = v + Vector2(0.5, 0.0)
			return func() -> void: r.motion.velocity = v
		"remnant heading":
			var v := r.motion.heading
			r.motion.heading = v + 0.1
			return func() -> void: r.motion.heading = v
		"remnant radius":
			var v := r.phenotype.radius
			r.phenotype.radius = v + 0.1
			return func() -> void: r.phenotype.radius = v
		"remnant health":
			var v := r.state.health
			r.state.health = v * 0.5
			return func() -> void: r.state.health = v
		"remnant flee_speed":
			var v := r.flee_speed
			r.flee_speed = v + 0.5
			return func() -> void: r.flee_speed = v
		"remnant born_tick":
			r.born_tick += 1
			return func() -> void: r.born_tick -= 1
		"remnant leaving":
			r.leaving = not r.leaving
			return func() -> void: r.leaving = not r.leaving
		"remnant number":
			r.number += 1
			return func() -> void: r.number -= 1
		"remnant id":
			var v := r.id
			r.id = v + "x"
			return func() -> void: r.id = v
		"remnant species":
			var v := r.species_id
			r.species_id = v + "x"
			return func() -> void: r.species_id = v
	check(false, "no perturbation named %s" % what)
	return func() -> void: pass


## The perturbation base: the swim east at the cell's own speed for RICH_TICKS.
func _rich_endless() -> PoolSim:
	var sim := _endless()
	var bot = SwimBot.new(Vector2.RIGHT)
	for t in RICH_TICKS:
		sim.step(bot.next_intent(sim))
		sim.drain_events()
	return sim


## Two awake creatures on different think slots, or [].
static func _two_slots(sim: PoolSim) -> Array:
	var awake := sim.creatures.awake()
	for a in awake:
		for b in awake:
			if a.think_slot != b.think_slot:
				return [a, b]
	return []


## Applies `what` to `sim` and returns the Callable that undoes it.
func _perturb_world(sim: PoolSim, what: String) -> Callable:
	var w := sim.world
	if what.begins_with("counter "):
		var k := what.trim_prefix("counter ")
		w.counters[k] = int(w.counters[k]) + 1
		return func() -> void: w.counters[k] = int(w.counters[k]) - 1
	match what:
		"origin_am.x by one ulp":
			var x := w.origin_x_am
			w.origin_x_am = _one_ulp_on(x)
			check(w.origin_x_am != x, "origin x moved by one ulp (%s)" % x)
			return func() -> void: w.origin_x_am = x
		"checkpoint heading":
			var h := w.checkpoint_am[2]
			w.checkpoint_am[2] = h + 1e-5
			return func() -> void: w.checkpoint_am[2] = h
		"respawn_pending":
			sim.respawn_pending = true
			return func() -> void: sim.respawn_pending = false
		"one chunk removed":
			var key: Vector2i = w._keys[0]
			w._keys.remove_at(0)
			return func() -> void: w._insert_key(key)
		"one zone stream drawn once":
			var id: String = _sorted_keys(sim.region.streams)[0]
			var stream: RandomNumberGenerator = sim.region.streams[id]
			var state := stream.state
			stream.randi()
			return func() -> void: stream.state = state
		"a site_counts entry":
			var id: String = _sorted_keys(w.site_counts)[0]
			w.site_counts[id] = int(w.site_counts[id]) + 1
			return func() -> void: w.site_counts[id] = int(w.site_counts[id]) - 1
		"a sleeper woken":
			var c := sim.creatures.find(w.sleeping_ids()[0])
			c.asleep = false
			return func() -> void: c.asleep = true
		"a slot swapped":
			var pair := _two_slots(sim)
			var a: CreatureField.Creature = pair[0]
			var b: CreatureField.Creature = pair[1]
			var slot := a.think_slot
			a.think_slot = b.think_slot
			b.think_slot = slot
			return func() -> void:
				b.think_slot = a.think_slot
				a.think_slot = slot
		"_cell_tile":
			w._cell_tile += Vector2i(1, 0)
			return func() -> void: w._cell_tile -= Vector2i(1, 0)
		"gen_version":
			w.gen_version += 1
			return func() -> void: w.gen_version -= 1
		"size":
			w.size += 1
			return func() -> void: w.size -= 1
	check(false, "no perturbation named %s" % what)
	return func() -> void: pass


## `x` with the lowest bit of its float64 pattern flipped: one ulp away.
static func _one_ulp_on(x: float) -> float:
	var bytes := PackedFloat64Array([x]).to_byte_array()
	bytes.encode_s64(0, bytes.decode_s64(0) ^ 1)
	return bytes.decode_double(0)


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type).size()


# --- S3 (T2.8, BP3-12) ---

## The band-1 fixture world (sizes to 4) on the fake generator with growth on, at `size`, a site per
## 2 x 2 chunks, after 60 still ticks with a carrion item, a veil (a hazard) and a rammer beside the
## cell; its events drained.
func _b1(size: int) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, FakeWorldGen.fixture_content(B1_WORLD),
		PackedFloat64Array(), 2, true)
	check(sim.debug_set_size(size), "size %d" % size)
	var at := sim.motion.position
	sim.carrion.spawn(at + Vector2(2.0, -3.0), "test", 5.0)
	check(sim.debug_spawn_creature("veil", at + Vector2(9.0, 0.0), PI), "a veil")
	check(sim.debug_spawn_creature("rammer", at + Vector2(-9.0, 3.0), 0.0), "a rammer")
	for t in 60:
		sim.step(SimIntent.new())
	sim.drain_events()
	return sim


## BP3-12 (2, 3): at size 3 (a hazard live, no morsel site), each S3 key of 3.14 is absent from the
## snapshot at its default; set, it changes state_hash(), and undone the hash is the base's again.
func test_every_s3_key_is_absent_at_its_default_and_changes_the_state_hash() -> void:
	var sim := _b1(3)
	var h0 := sim.state_hash()
	check_eq(_b1(3).state_hash(), h0, "the same build hashes the same")
	check(sim.creatures.hazard_live, "a hazard is live at 3")
	var snap := sim.snapshot()
	for key in ["last_strike_hit_tick", "last_sting_tick", "token_closed_until"]:
		check(not snap.has(key), "no %s at its default" % key)
	for key in ["morsel_sites", "landmark_anchor"]:
		check(not (snap.world as Dictionary).has(key), "no world %s at its default" % key)
	check(not snap.carrion.is_empty(), "a carrion item")
	for item: Dictionary in snap.carrion:
		check(not item.has("species") and not item.has("site"), "a plain item has no species or site")
	var hazard: CreatureField.Creature = null
	var plain: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.brain.behavior == CreatureBrain.HAZARD:
			hazard = c if hazard == null else hazard
		elif plain == null:
			plain = c
	check(hazard != null and plain != null, "a hazard and a creature that is not one")
	if hazard == null or plain == null:
		return
	for c in sim.creatures.creatures:
		var b: Dictionary = c.brain.to_dict()
		check_eq(b.has("drift_phase") and b.has("drift_period"), c.brain.behavior == CreatureBrain.HAZARD,
			"%s: drift keys only on a hazard" % c.id)
		check(not b.has("bloom_offset") and not b.has("bloom_cycle"), "%s: no bloom keys without a schedule" % c.id)
	for what: String in S3_KEYS:
		var undo := _perturb_s3(sim, what, hazard, plain)
		check(sim.state_hash() != h0, "%s (%s) changes the hash" % [what, S3_KEYS[what]])
		undo.call()
		check_eq(sim.state_hash(), h0, "and undoing %s restores it" % what)


func _perturb_s3(sim: PoolSim, what: String, hazard: CreatureField.Creature, plain: CreatureField.Creature) -> Callable:
	var w := sim.world
	var item: Dictionary = sim.carrion.items[0]
	match what:
		"last_strike_hit_tick":
			sim.last_strike_hit_tick = sim.tick - 3
			return func() -> void: sim.last_strike_hit_tick = -CreatureBrain.NEVER
		"last_sting_tick":
			sim.last_sting_tick = sim.tick - 3
			return func() -> void: sim.last_sting_tick = -CreatureBrain.NEVER
		"token_closed_until":
			sim.creatures.token_closed_until = sim.tick + 40
			return func() -> void: sim.creatures.token_closed_until = 0
		"morsel_sites":
			w.adopt_morsel("m_test", "")
			return func() -> void: w._drop_entry("m_test")
		"landmark_anchor":
			w.landmark_anchor = "a_test"
			return func() -> void: w.landmark_anchor = ""
		"carrion species":
			item["species"] = "rammer"
			return func() -> void: item.erase("species")
		"carrion site":
			item["site"] = "m_test"
			return func() -> void: item.erase("site")
		"brain drift_phase":
			var v: Vector2i = hazard.brain.drift_phase
			hazard.brain.drift_phase = v + Vector2i(1, 0)
			return func() -> void: hazard.brain.drift_phase = v
		"brain drift_period":
			var v: Vector2i = hazard.brain.drift_period
			hazard.brain.drift_period = v + Vector2i(0, 1)
			return func() -> void: hazard.brain.drift_period = v
		"brain bloom_offset":
			CreatureBrain.set_bloom(plain.brain, 17, 5400)
			return func() -> void: CreatureBrain.set_bloom(plain.brain, 0, 0)
	check(false, "no perturbation for %s" % what)
	return func() -> void: pass


## BP3-12 (1): two runs from one seed on the band-1 fixture world, each swimming east from size 2,
## grown to 3 and then to 4 by the dev command, hash the same BAND_HASH_AT ticks after each growth
## (by state_hash() and the snapshot's sha256) and grow on the same ticks.
func test_slow_two_runs_through_both_band_one_growths_give_the_same_hash() -> void:
	var runs: Array[Dictionary] = []
	for i in 2:
		var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, FakeWorldGen.fixture_content(B1_WORLD),
			PackedFloat64Array(), 4, true)
		check(sim.debug_set_size(2), "size 2")
		var bot = SwimBot.new(Vector2.RIGHT)
		var run := {"hashes": [], "shas": [], "grew_at": []}
		var since := -1
		var t := 0
		while t < 2 * (BAND_HASH_AT[-1] + 200):
			if since < 0 and sim.size() < 4 and (run.grew_at.size() == 0 or t - int(run.grew_at[-1]) > BAND_HASH_AT[-1]):
				check(sim.debug_force_growth(), "run %d: the forced growth to %d" % [i, sim.size() + 1])
				since = 0
			sim.step(bot.next_intent(sim))
			for e in sim.drain_events():
				if e.type == "grew":
					run.grew_at.append(t)
			if run.grew_at.size() > 0 and t - int(run.grew_at[-1]) + 1 in BAND_HASH_AT:
				run.hashes.append(sim.state_hash())
				run.shas.append(JSON.stringify(sim.snapshot(), "", true, true).sha256_text())
			if since >= 0 and run.grew_at.size() > 0 and int(run.grew_at[-1]) >= t - 1:
				since = -1
			t += 1
			if run.grew_at.size() == 2 and t - int(run.grew_at[-1]) > BAND_HASH_AT[-1]:
				break
		run["size"] = sim.size()
		runs.append(run)
	print("test-endless-sim: two runs through 2 to 3 to 4: grew at %s, size %d; last hash %d" % [runs[0].grew_at,
		runs[0].size, runs[0].hashes[-1] if not runs[0].hashes.is_empty() else 0])
	check_eq([runs[0].size, runs[0].grew_at.size(), runs[0].hashes.size()], [4, 2, 6], "both growths, three hashes after each")
	check_eq(runs[1].grew_at, runs[0].grew_at, "on the same ticks")
	check_eq(runs[1].hashes, runs[0].hashes, "the same state_hash() %s ticks after each growth" % [BAND_HASH_AT])
	check_eq(runs[1].shas, runs[0].shas, "and the same snapshot sha256")
