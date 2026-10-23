extends TestCase
## The endless sim end to end (S1 T2.9), on the real WorldGen with the fixture world (T1.7, T1.9):
## the save path (the absolute position in am, float64, written and restored exactly), and
## determinism: two runs of a straight swim hash the same (G13), and every key of the world's
## snapshot is in the hash (T2.9b).

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
