extends TestCase
## The endless sim end to end (S1 T2.9), on the real WorldGen with the fixture world (T1.7, T1.9):
## the save path (the absolute position in am, float64, written and restored exactly), and
## determinism: two runs of a straight swim hash the same (G13), and every key of the world's
## snapshot is in the hash (T2.9b). With growth (S2 T2.7, S2G21): every key the growth adds to the
## world block (the meter's, the remnants', the carrion's own radii and lifetimes) is in the hash,
## the prefetch is not, and two runs through a growth hash the same.

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
	for t in 8:
		sim.step(SimIntent.new(Vector2(0.4, 0.0)))
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
