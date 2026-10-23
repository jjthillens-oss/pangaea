extends TestCase
## The sim's cost shortcuts (S1 perf, G17) give exactly what the plain code gives: each test pins one
## shortcut against the work it replaces, on inputs that reach its edge cases.

const ForageBot := preload("res://game/dev/forage_bot.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const FIXTURE_WORLD := "res://tests/fixtures/world/world_min.json"
const BUILD_ID := "test+dev"
const HOME := Vector2(0.0, 9.0)
const DEATH_NOTICE_TICKS := 90

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## An omnivore at home on the fixture world, with its starting events drained.
func _forager(seed_value: int) -> PoolSim:
	var r := Lineage.found(seed_value, BUILD_ID, catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(HOME)
	var sim := PoolSim.create(r.save, catalog, layout, species, WorldContent.load_from(FIXTURE_WORLD, layout, species))
	sim.drain_events()
	return sim


## The endless queue's binary search puts every entry where the pool's scan does: before the first
## entry that is not less by (at_tick, site), ties and repeats included.
func test_the_endless_queue_insert_matches_the_scan() -> void:
	var fast := CreatureField.new()
	fast.endless = true
	var scan := CreatureField.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var sites := ["a", "b", "b2", "c_1", "c_10", "c_2", "z"]
	for i in 400:
		var site: String = sites[rng.randi_range(0, sites.size() - 1)]
		var at := rng.randi_range(0, 12)
		var species_id := "s%d" % i   # tells repeats of (at_tick, site) apart
		fast._enqueue(site, species_id, at)
		scan._enqueue(site, species_id, at)
		if fast.queue != scan.queue:
			check_eq(fast.queue, scan.queue, "insert %d (%s at %d)" % [i, site, at])
			return
		if i % 50 == 49:
			var taken := rng.randi_range(0, 10)   # the due front
			fast.queue = fast.queue.slice(taken)
			scan.queue = scan.queue.slice(taken)
	check_eq(fast.queue.size(), scan.queue.size(), "both queues hold the same entries")


## take_events reads only the awake brains unless a sleeper may hold events: after every step no brain,
## asleep or awake, still holds one. An omnivore swims east overdriven, leaving the creatures it
## passed asleep (some in a chase), comes back and forages, eating, chased, dying and respawning, with
## the hide switch flipped now and then (every brain forgets the cell).
func test_no_brain_keeps_events_past_a_step() -> void:
	var sim := _forager(5101)
	var east = SwimBot.new(Vector2.RIGHT)
	var west = SwimBot.new(Vector2.LEFT)
	var forage = ForageBot.new()
	var dead_since := -1
	var counts := {"creature_slept": 0, "creature_woke": 0, "creature_removed": 0, "respawned": 0}
	var left := 0
	for t in 3000:
		if t % 300 == 150:
			sim.debug_set_hidden(not sim.dev_hidden)
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS and not sim.respawn_pending:
				sim.respawn_player()
				dead_since = -1
		var bot = east if t < 900 else (west if t < 1800 else forage)
		if t < 1800:
			SwimBot.overdrive(sim)
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			if counts.has(e.type):
				counts[e.type] += 1
		for c in sim.creatures.creatures:
			if c.brain != null and not c.brain.events.is_empty():
				left += 1
	check_eq(left, 0, "brain events left after a step")
	for type in ["creature_slept", "creature_woke", "creature_removed"]:
		check(int(counts[type]) > 0, "some %s (%s)" % [type, counts])


## The hooks every brain gets reach sleepers too, and what a sleeper's brain says then comes out with
## the next events: debug creatures (which the stream never wakes) put to sleep engaged, then hiding
## the cell, a removal, the cell's death and its respawn at the checkpoint.
func test_a_sleepers_events_from_a_hook_come_out_at_once() -> void:
	var sim := _forager(5102)
	check(sim.debug_spawn_creature("ambush_hunter", Vector2(30.0, -30.0), 0.0), "a hunter")
	check(sim.debug_spawn_creature("rammer", Vector2(-30.0, -30.0), 0.0), "a rammer")
	var field := sim.creatures
	var a: CreatureField.Creature = field.creatures[field.creatures.size() - 2]
	var b: CreatureField.Creature = field.creatures[field.creatures.size() - 1]
	CreatureBrain._notice(a.brain, CreatureField.PLAYER_ID, "sight", sim.tick)
	CreatureBrain._notice(b.brain, a.id, "sight", sim.tick)
	field.sleep(b, sim.tick)   # first: a sleeping creature is forgotten by every awake brain
	field.sleep(a, sim.tick)
	sim.drain_events()
	sim.step(SimIntent.new())
	sim.drain_events()
	check(a.asleep and b.asleep, "both still asleep")
	sim.debug_set_hidden(true)
	check_eq(_gave_up(sim.drain_events()), [[a.id, CreatureField.PLAYER_ID]], "hidden: the sleeping hunter gives up the cell")
	sim.debug_set_hidden(false)
	field.remove(a, "killed", sim.tick, false)
	check_eq(_gave_up(sim.drain_events()), [[b.id, a.id]], "removed: the sleeping rammer gives up the hunter")
	CreatureBrain._notice(b.brain, CreatureField.PLAYER_ID, "sight", sim.tick)
	sim.drain_events()
	check(sim.debug_hurt_player(1e9), "the cell dies")
	check_eq(_gave_up(sim.drain_events()), [[b.id, CreatureField.PLAYER_ID]], "death: the sleeping rammer gives up the cell")
	# A sleeper in a tell at the cell: forgetting the cell at the respawn cancels it.
	b.brain.target = CreatureField.PLAYER_ID
	b.brain.state = CreatureBrain.ATTACK
	b.brain.phase = CreatureBrain.TELL
	sim.respawn_player()
	sim.step(SimIntent.new())
	check_eq(_cancelled(sim.drain_events()), [b.id], "respawn: the sleeper's tell is cancelled")
	check(b.asleep and b.brain.events.is_empty(), "it sleeps on, its brain holding nothing")


static func _gave_up(events: Array[Dictionary]) -> Array:
	var out := []
	for e in events:
		if e.type == "creature_gave_up":
			out.append([e.id, e.target])
	return out


static func _cancelled(events: Array[Dictionary]) -> Array:
	var out := []
	for e in events:
		if e.type == "creature_recovered" and e.outcome == "cancelled":
			out.append(e.id)
	return out
