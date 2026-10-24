extends TestCase
## FuzzInvariants through growth (S2 T2.6b, build plan BP-2, gate S2G39), on FakeWorldGen at sizes 1
## and 2: a forced growth and a dev size change and back run clean tick by tick, and hand-built events
## that break invariants 12 and 13 the way only a growing world can are caught. S3 (T0.2, D-141):
## hand-built stings and strike hits that break invariant 15, morsel items that break 12 (S3G17c,
## S3G17d), a creature at a landmark checkpoint (3) and a hazard off its drift path (7).
##
## The forced growth comes far from the world's origin (so the size-2 view set holds zones the size-1
## one did not), with the cell far from the frame's origin (a dev rebase the tick before) and a
## sleeper planted on the origin's side of the cell, where a checker that reads the old size's
## positions with the new size's k (S1's reading) sees it on top of the cell. Since T3.5 a forced
## growth on the shipped content runs clean too, and meets the size-2 species there (BP-2).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const Gates := preload("res://tests/test_endless_gates.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
const SEED := 4242
## Ticks a size-1 swim runs first, so creatures sleep and wake round the cell.
const SWIM_TICKS := 240
## Ticks checked after the growth tick, through the beat's loads.
const AFTER_TICKS := 150
## Ticks checked after each dev size change.
const SET_SIZE_TICKS := 90
## Ticks the size-2 senses case runs: the hunter thinks and notices within them.
const SENSE_TICKS := 30
## tm: how far from the origin the dev rebase puts the cell (under rebase_beyond_tm, 96).
const FAR_FROM_ORIGIN := 80.0
## Absolute tm: far from the world's origin, so a stored tm read as am is far from where it is.
const FAR_ABS := Vector2(2000.0, 1000.0)
## tm: the hand-built beat shell's radius.
const HAND_SHELL_R := 0.25
## Checkers _grown hands back for hand-built copies of the growth tick.
const SPARES := 3
## The shipped-content case: what it waits on (Gates.S2_NEEDS), its body, and its ticks after the
## growth (the beat, then the size-2 sites round home spawning).
const SHIPPED_NEEDS: PackedStringArray = ["force_growth", "fuzz_growth", "size_two_content"]
const SHIPPED_BODY := "omnivore"
const SHIPPED_AFTER_TICKS := 600

var catalog: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	if catalog == null:
		catalog = PartCatalog.load_from()
		layout = PoolLayout.load_from()


## A forced growth (BP-2 4): the tick runs clean, with its sleepers' removals checked at the old size
## and its events after grew at the new one; the beat and the ticks after it run clean too.
func test_a_forced_growth_runs_clean() -> void:
	var r := _grown(FakeWorldGen.s2_species())
	var fuzz: FuzzInvariants = r.fuzz
	check_eq(fuzz.report(), "", "every invariant on every tick")
	check_eq(int(fuzz.counts.growths), 1, "one growth tick (%s)" % fuzz.counts)
	check(int(fuzz.counts.after_growth) >= 1, "events checked after grew (%s)" % fuzz.counts)
	check(int(r.removed) >= 1, "sleepers removed for the growth, checked at the old size (%d)" % r.removed)
	check(bool(r.planted_removed), "the planted sleeper among them")
	check(float(r.cell_local) >= FAR_FROM_ORIGIN - 16.0, "the cell grew %.1f tm from the origin" % r.cell_local)
	check_eq(r.sim.size(), 2, "size 2")
	for t in AFTER_TICKS:
		_step(r.sim, fuzz, "after tick %d" % t, Vector2.from_angle(0.002 * t) * 0.6)
	check_eq(fuzz.report(), "", "and through the beat")
	check(int(fuzz.counts.loads) >= 1, "chunks loaded after the growth (%s)" % fuzz.counts)


## BP-2's real-content case (T3.5): on the shipped content, a hidden omnivore swims from home, is
## grown by debug_force_growth, and swims on; every tick runs clean, and creatures of the species that
## enter at size 2 spawn round it after the growth.
func test_a_forced_growth_on_the_shipped_content_runs_clean() -> void:
	var waits := Gates.s2_missing(SHIPPED_NEEDS)
	if not waits.is_empty():
		print("test-fuzz-invariants: the shipped-content growth waits on: %s" % "; ".join(waits))
		return
	var sim: PoolSim = Gates.make_sim(SHIPPED_BODY, SEED, true)
	sim.debug_set_hidden(true)
	var fuzz := FuzzInvariants.new(sim.species, layout)
	for t in SWIM_TICKS:
		_step(sim, fuzz, "swim tick %d" % t, Vector2.from_angle(0.4 + 0.004 * t) * 0.6)
	var was := fuzz.before(sim)
	check(sim.debug_force_growth(), "the forced growth")
	_step(sim, fuzz, "growth tick", Vector2.ZERO, was)
	check_eq(sim.size(), 2, "size 2")
	var entering := Gates.species_entering_at(2)
	var met := {}
	for t in SHIPPED_AFTER_TICKS:
		for e in _step(sim, fuzz, "after tick %d" % t, Vector2.from_angle(0.4 - 0.003 * t) * 0.6):
			if e.type == "creature_spawned" and entering.has(str(e.species)):
				met[str(e.species)] = true
	print("test-fuzz-invariants: the shipped content grew; after it %s; size-2 species spawned: %s" % [fuzz.counts, met.keys()])
	check_eq(fuzz.report(), "", "every invariant on every tick")
	check_eq(int(fuzz.counts.growths), 1, "one growth tick (%s)" % fuzz.counts)
	check(int(fuzz.counts.after_growth) >= 1 and int(fuzz.counts.loads) >= 1, "events checked after grew (%s)" % fuzz.counts)
	check(not met.is_empty(), "a species that enters at size 2 spawned (of %s)" % entering)


## debug_set_size(2) then debug_set_size(1): each is a cut (BP-2 3), and the ticks after each run
## clean at their size.
func test_set_size_two_then_one_runs_clean() -> void:
	var sim := _sim(FakeWorldGen.s2_species())
	var fuzz := FuzzInvariants.new(sim.species, layout)
	for t in 60:
		_step(sim, fuzz, "swim tick %d" % t, Vector2(0.6, 0.2))
	for n in [2, 1]:
		var was := fuzz.before(sim)
		check(sim.debug_set_size(n), "size %d" % n)
		_step(sim, fuzz, "set_size %d tick" % n, Vector2.ZERO, was)
		for t in SET_SIZE_TICKS:
			_step(sim, fuzz, "size %d tick %d" % [n, t], Vector2(0.2, -0.6))
		check_eq(sim.size(), n, "at size %d" % n)
	check_eq(fuzz.report(), "", "every invariant on every tick")
	check_eq(int(fuzz.counts.set_sizes), 2, "two size changes (%s)" % fuzz.counts)
	check(int(fuzz.counts.cuts) >= 2, "each a cut (%s)" % fuzz.counts)
	check_eq(int(fuzz.counts.growths), 0, "no growth")


## Invariant 9 at size 2 reads a creature's senses at the field's size: an ambush hunter (entry size
## 1) there notices with near_m x q (q = 1 / 1.6), so the cell between that and its species block's
## near_m is a sight percept, not a near one. A checker reading the block's own senses (S1's reading)
## calls every such percept wrong.
func test_at_size_two_invariant_9_reads_the_senses_at_that_size() -> void:
	var sim := _sim(FakeWorldGen.s2_species())
	var fuzz := FuzzInvariants.new(sim.species, layout)
	var was := fuzz.before(sim)
	check(sim.debug_set_size(2), "size 2")
	_step(sim, fuzz, "set_size tick", Vector2.ZERO, was)
	sim.grace_until = sim.tick   # out of the shelter, so it may be sensed
	var rec := sim.creatures.record_of("ambush_hunter")
	var block_near := float(sim.species.species.ambush_hunter.senses.near_m)
	var near := float(rec.near_m)
	check(near < block_near, "near_m x q at size 2 (%.3f) is under the block's %.3f" % [near, block_near])
	var reach: float = rec.phenotype.radius + sim.phenotype.radius
	var d := reach + 0.5 * (near + block_near)   # sight at size 2; near by the block's own
	var at := sim.motion.position + Vector2(d, 0.0)
	check(sim.debug_spawn_creature("ambush_hunter", at, PI), "a hunter %.2f tm east, facing the cell" % d)
	var hunter: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.species_id == "ambush_hunter" and c.motion.position == at:
			hunter = c
	check(hunter != null, "spawned")
	if hunter == null:
		return
	var seen := ""
	var checks := int(fuzz.counts.memory_checks)
	for t in SENSE_TICKS:
		_step(sim, fuzz, "sense tick %d" % t)
		var memory: Dictionary = hunter.brain.seen.get(CreatureField.PLAYER_ID, {})
		if seen.is_empty() and not memory.is_empty():
			seen = str(memory.by)
	check_eq(seen, "sight", "it first sensed the cell by sight")
	check(int(fuzz.counts.memory_checks) > checks, "invariant 9 checked its memory (%d)" % (int(fuzz.counts.memory_checks) - checks))
	check_eq(fuzz.report(), "", "every invariant on every tick")


## A sleeper the growth removes in view fails 12 (it is checked, not exempt, before grew), and so does
## carrion the growth expires in view and a remnant that leaves in view; the same out of view, or for
## a reason the player may see, does not.
func test_a_sleeper_removed_in_view_for_the_growth_fails_12() -> void:
	var sim := _sim(FakeWorldGen.s2_species())
	for t in 30:
		sim.step(SimIntent.new(Vector2(0.6, 0.0)))
	sim.drain_events()
	var near := sim.motion.position + Vector2(6.0, 0.0)
	var far := sim.motion.position + Vector2(200.0, 0.0)
	var cases := {   # name -> [the event, in a growth tick, fails 12]
		"sleeper in view": [_removed(near, "growth"), true, true],
		"sleeper out of view": [_removed(far, "growth"), true, false],
		"eaten in view": [_removed(near, "eaten"), true, false],
		"carrion in view": [{"type": "carrion_expired", "food_id": "c_hand", "position": near, "reason": "growth"}, true, true],
		"carrion out of view": [{"type": "carrion_expired", "food_id": "c_hand", "position": far, "reason": "growth"}, true, false],
		"carrion faded in view": [{"type": "carrion_expired", "food_id": "c_hand", "position": near, "reason": "expired"}, true, false],
		"remnant left in view": [_removed(near, "remnant_left"), false, true],
		"remnant left out of view": [_removed(far, "remnant_left"), false, false],
	}
	for name: String in cases:
		var c: Array = cases[name]
		var fuzz := FuzzInvariants.new(sim.species, layout)
		var was := fuzz.before(sim)
		var events: Array[Dictionary] = [c[0]]
		if c[1]:
			events = _growth_events(sim, [c[0]])
		fuzz.after(sim, events, sim.tick, name, was)
		check_eq(fuzz.bad.has(12), c[2], "%s: %s" % [name, fuzz.report()])
		if c[2] and fuzz.bad.has(12):
			check(str(fuzz.bad[12].first).contains("c_hand"), "the failure names it: %s" % fuzz.bad[12].first)


## At size 2 a distance is in size 2's tm (BP-2 2): far from the world's origin, a creature evicted
## inside the view in tm (outside it in am) fails 12, and so does a chunk unloading with its shell in
## view (a chunk's stored tm times its size's k).
func test_at_size_two_a_distance_is_in_that_sizes_tm() -> void:
	var sim := _sim(FakeWorldGen.s2_species(), PackedFloat64Array([FAR_ABS.x, FAR_ABS.y]))
	var fuzz := FuzzInvariants.new(sim.species, layout)
	var was := fuzz.before(sim)
	check(sim.debug_set_size(2), "size 2")
	_step(sim, fuzz, "set_size tick", Vector2.ZERO, was)
	for t in 30:
		_step(sim, fuzz, "size 2 tick %d" % t)
	check_eq(fuzz.report(), "", "clean at size 2")
	var edge := _edge(fuzz, 0.0)
	var inside := 0.5 * (edge + float(sim.species.fairness.spawn_safe_m))   # between spawn_safe_m and the view's edge
	check(inside > float(sim.species.fairness.spawn_safe_m) and not fuzz._in_view(Vector2(inside * WorldConfig.tm_to_am(2), 0.0), 0.0),
		"%.2f tm: past spawn_safe_m, in view in tm and out of it in am" % inside)
	var ev := FuzzInvariants.new(sim.species, layout)
	var was_ev := ev.before(sim)
	ev.after(sim, [{"type": "creature_removed", "id": "c_hand", "species": "rammer", "position": sim.motion.position + Vector2(inside, 0.0),
		"reason": "evicted"}] as Array[Dictionary], sim.tick, "evicted", was_ev)
	check(ev.bad.has(12) and str(ev.bad[12].first).contains("c_hand"), "the eviction in view fails 12: %s" % ev.report())
	var w := sim.world
	var key := Vector2i.MAX
	var shell := {}
	var best := INF
	for k: Vector2i in w.loaded_keys():   # the loaded shell nearest the cell
		for s: Dictionary in w.chunk(k).shells:
			var d := w.local_of_tm(float(s.x), float(s.y)).distance_to(sim.motion.position)
			if d < best:
				best = d
				key = k
				shell = s
	var at := w.local_of_tm(float(shell.x), float(shell.y))
	check(fuzz._in_view(at - sim.motion.position, float(shell.r)), "a loaded shell in view (%.1f tm)" % best)
	var un := FuzzInvariants.new(sim.species, layout)
	var was_un := un.before(sim)
	un.after(sim, [{"type": "chunk_unloaded", "key": key}] as Array[Dictionary], sim.tick, "unloaded", was_un)
	check(un.bad.has(12) and str(un.bad[12].first).contains(str(shell.id)), "the unload with its shell in view fails 12: %s" % un.report())


## A chunk_loaded after grew (the beat's) with a shell in view at the new size fails 12, and one just
## out of view at the new size (in view at the old) passes; the same load before grew is the
## re-expression's own and exempt.
func test_a_beat_load_after_grew_with_a_shell_in_view_fails_12() -> void:
	var r := _grown(FakeWorldGen.s2_species())
	var sim: PoolSim = r.sim
	var events: Array[Dictionary] = r.events
	check_eq((r.fuzz as FuzzInvariants).report(), "", "the real growth tick is clean")
	var at_grew := -1
	for i in events.size():
		if events[i].type == "grew":
			at_grew = i
	check(at_grew > 0, "the tick grew")
	# Just inside the view in size 2's tm (outside it in size 1's), and just outside it.
	var edge := _edge(r.fuzz, HAND_SHELL_R)
	var cases := [["after grew, in view", at_grew + 1, 0.8 * edge, true], ["after grew, out of view", at_grew + 1, 1.25 * edge, false],
		["before grew, in view", at_grew, 0.8 * edge, false]]
	for i in cases.size():
		var c: Array = cases[i]
		var load := {"type": "chunk_loaded", "key": Vector2i(99, 99), "zones": [], "anchors": [], "places": [], "sites": [],
			"scale": 1.0, "shells": [{"id": "s_hand", "position": sim.motion.position + Vector2(float(c[2]), 0.0), "radius": HAND_SHELL_R}]}
		var hand: Array[Dictionary] = events.duplicate()
		hand.insert(int(c[1]), load)
		var fuzz: FuzzInvariants = r.spares[i][0]
		fuzz.after(sim, hand, sim.tick - 1, c[0], r.spares[i][1])
		if c[3]:
			check(fuzz.bad.has(12) and str(fuzz.bad[12].first).contains("s_hand"), "%s: fails 12 (%s)" % [c[0], fuzz.report()])
		else:
			check(not fuzz.bad.has(12), "%s: passes (%s)" % [c[0], fuzz.report()])


## Invariant 13 covers the remnants (each position the cell's own are checked by), the two-post
## brains' posts and the site records' posts: one moved to 300 tm fails it. And a remnant that leaves
## is hidden by its own radius (12).
func test_a_remnant_or_a_post_at_300_tm_fails_13() -> void:
	var r := _grown(FakeWorldGen.ladder_species(), true)
	var sim: PoolSim = r.sim
	check(not sim.remnants.items.is_empty(), "a remnant")
	var far := Vector2(300.0, 0.0)
	var fuzz := FuzzInvariants.new(sim.species, layout)
	fuzz.after(sim, [] as Array[Dictionary], sim.tick, "as it is", fuzz.before(sim))
	check(not fuzz.bad.has(13), "clean as it is: %s" % fuzz.report())
	var rem: RemnantField.Remnant = sim.remnants.items[0]
	var site := ""
	for id: String in sim.world.sites:
		if (sim.world.sites[id] as Dictionary).has("posts"):
			site = id
			break
	check(not site.is_empty(), "a two-post site")
	var post_brain: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.brain != null and not c.brain.posts.is_empty():
			post_brain = c
	if post_brain == null and not site.is_empty():
		post_brain = sim.creatures.spawn_site(sim.world.sites[site], sim.tick)   # its site's creature, awake
	check(post_brain != null, "a two-post brain")
	var moves := {
		"remnant %s position" % rem.id: func() -> void: rem.motion.position = far,
		"remnant %s prev_position" % rem.id: func() -> void: rem.motion.prev_position = far,
		"remnant %s actor" % rem.id: func() -> void: rem.actor.position = far,
		"site %s post 1 home" % site: func() -> void: sim.world.sites[site].posts[1].home = far,
	}
	if post_brain != null:
		moves["%s post 1 home" % post_brain.id] = func() -> void: post_brain.brain.posts[1].home = far
		moves["%s leash_center" % post_brain.id] = func() -> void: post_brain.brain.leash_center = far
	# A remnant that leaves is measured with its own radius: just outside the view for a point, inside
	# it for the remnant's disc.
	var leave_at := sim.motion.position + Vector2(_edge(fuzz, 0.0) + 0.5 * rem.phenotype.radius, 0.0)
	for id: String in [rem.id, "c_hand"]:
		var lf := FuzzInvariants.new(sim.species, layout)
		var was_lf := lf.before(sim)
		lf.after(sim, [{"type": "creature_removed", "id": id, "species": rem.species_id, "position": leave_at, "reason": "remnant_left"}
			] as Array[Dictionary], sim.tick, "left", was_lf)
		check_eq(lf.bad.has(12), id == rem.id, "%s leaving at the view's edge: %s" % [id, lf.report()])
	for what: String in moves:
		var keep := _snapshot_13(sim, rem, site, post_brain)
		(moves[what] as Callable).call()
		var f := FuzzInvariants.new(sim.species, layout)
		f.after(sim, [] as Array[Dictionary], sim.tick, what, f.before(sim))
		check(f.bad.has(13) and str(f.bad[13].first).contains(what), "%s at 300 tm fails 13: %s" % [what, f.report()])
		_restore_13(sim, rem, site, post_brain, keep)


# --- helpers ---

## An endless sim on the fake generator with growth on (size 2 is the build top) and a site in every
## 2 x 2 chunks, its start events drained; at home, or at `at` (absolute tm).
func _sim(species: SpeciesCatalog, at := PackedFloat64Array()) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, at, 2, true)
	sim.drain_events()
	return sim


## One step with `move`, checked by `fuzz` (`was`, when given, is what it took before something done
## between the steps). Returns the step's events.
func _step(sim: PoolSim, fuzz: FuzzInvariants, where: String, move := Vector2.ZERO, was := {}) -> Array[Dictionary]:
	if was.is_empty():
		was = fuzz.before(sim)
	var t := sim.tick
	sim.step(SimIntent.new(move))
	var events := sim.drain_events()
	fuzz.after(sim, events, t, where, was)
	return events


## A size-1 swim of SWIM_TICKS ticks from FAR_ABS, a dev rebase that leaves the cell about
## FAR_FROM_ORIGIN tm from the origin, a sleeper planted (_plant), then a forced growth, every tick
## checked. With `prey`, a rammer (prey at size 2, so a remnant) beside the cell first, the creatures
## frozen. Returns the sim, its checker, the growth tick's events, the removals it checked (and
## whether the planted sleeper was one), how far from the origin the cell grew, and SPARES more
## checkers (with what each took before the growth tick) for hand-built copies of that tick.
func _grown(species: SpeciesCatalog, prey := false) -> Dictionary:
	var sim := _sim(species, PackedFloat64Array([FAR_ABS.x, FAR_ABS.y]))
	var fuzz := FuzzInvariants.new(species, layout)
	for t in SWIM_TICKS:
		_step(sim, fuzz, "swim tick %d" % t, Vector2.from_angle(0.7 + 0.003 * t) * 0.6)
	if prey:
		sim.debug_set_ai_frozen(true)
		check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-7.0, 3.0), 0.0), "a rammer beside the cell")
		sim.drain_events()
	var was := fuzz.before(sim)
	check(sim.debug_rebase(_back(sim.motion.position)), "the dev rebase")
	_step(sim, fuzz, "rebase tick", Vector2.ZERO, was)
	var cell_local := sim.motion.position.length()
	var planted := _plant(sim, fuzz)
	var spares := []
	for i in SPARES:
		var spare := FuzzInvariants.new(species, layout)
		spares.append([spare, spare.before(sim)])
	was = fuzz.before(sim)
	check(sim.debug_force_growth(), "the forced growth")
	var events := _step(sim, fuzz, "growth tick", Vector2.ZERO, was)
	var removed := 0
	var planted_removed := false
	for e in events:
		if e.type == "creature_removed" and str(e.reason) == "growth":
			removed += 1
			planted_removed = planted_removed or str(e.id) == planted
	return {"sim": sim, "fuzz": fuzz, "events": events, "removed": removed, "planted_removed": planted_removed,
		"cell_local": cell_local, "spares": spares}


## Plants a sleeping rammer where reading its place with size 2's k (am = origin + p x 1.6, against
## the cell's true am) puts it on the cell: at -(1 - 1 / 1.6) of the cell's local position, out of
## view and past spawn_safe_m as a sleeper must be (a little further out when that spot is not
## clear). Returns its id.
func _plant(sim: PoolSim, fuzz: FuzzInvariants) -> String:
	var shift := -sim.motion.position * (1.0 - 1.0 / WorldConfig.tm_to_am(2))
	for stretch: float in [1.0, 1.1, 1.2, 1.3]:
		var rel := shift * stretch
		if fuzz._in_view(rel, 2.0) or rel.length() < float(sim.species.fairness.spawn_safe_m):
			continue
		if sim.debug_spawn_creature("rammer", sim.motion.position + rel, 0.0):
			var id := ""
			for e in sim.drain_events():
				if e.type == "debug":
					id = str(e.id)
			sim.creatures.sleep(sim.creatures.find(id), sim.tick)
			sim.drain_events()
			return id
	check(false, "a sleeper planted %.1f tm from the cell" % shift.length())
	return ""


## tm: the first distance along +x from the cell at which a disc of radius `r` is out of view.
static func _edge(fuzz: FuzzInvariants, r: float) -> float:
	var x := 0.0
	while fuzz._in_view(Vector2(x, 0.0), r):
		x += 0.125
	return x


## Whole chunks to rebase by so the cell at local `p` ends near FAR_FROM_ORIGIN tm from the origin.
static func _back(p: Vector2) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var by := Vector2i(dx, dy)
			var d := absf((p - Vector2(by) * 32.0).length() - FAR_FROM_ORIGIN)
			if d < best_d:
				best_d = d
				best = by
	return best


static func _removed(at: Vector2, reason: String) -> Dictionary:
	return {"type": "creature_removed", "id": "c_hand", "species": "rammer", "position": at, "reason": reason}


## A growth tick's frame round `inner` (hand-built): growth_began at the cell, then `inner`, then grew
## to size 2 with the cell at the new origin.
static func _growth_events(sim: PoolSim, inner: Array) -> Array[Dictionary]:
	var a := sim.world.abs_of_local(sim.motion.position)
	var out: Array[Dictionary] = [{"type": "growth_began", "from": 1, "to": 2, "center_old": sim.motion.position,
		"center_am": [a[0], a[1]], "factor": WorldConfig.GROWTH_FACTOR}]
	for e: Dictionary in inner:
		out.append(e)
	out.append({"type": "grew", "from": 1, "to": 2, "center": Vector2.ZERO, "settled_from": Vector2.ZERO, "morsels": [],
		"remnants": []})
	return out


func _snapshot_13(sim: PoolSim, rem: RemnantField.Remnant, site: String, c: CreatureField.Creature) -> Array:
	var out := [rem.motion.position, rem.motion.prev_position, rem.actor.position, sim.world.sites[site].posts[1].home]
	if c != null:
		out.append_array([c.brain.posts[1].home, c.brain.leash_center])
	return out


func _restore_13(sim: PoolSim, rem: RemnantField.Remnant, site: String, c: CreatureField.Creature, keep: Array) -> void:
	rem.motion.position = keep[0]
	rem.motion.prev_position = keep[1]
	rem.actor.position = keep[2]
	sim.world.sites[site].posts[1].home = keep[3]
	if c != null:
		c.brain.posts[1].home = keep[4]
		c.brain.leash_center = keep[5]


# --- S3 (T0.2): invariant 15, 12's morsel clauses, 3 at a landmark checkpoint, 7's hazard form ---

const B1_WORLD := "res://tests/fixtures/world/world_b1_min.json"

var _shipped: SpeciesCatalog


## The band-1 fixture world (sizes to 4) on the fake generator, the shipped species, growth on, a
## site per 2 x 2 chunks, at `size`; its events drained.
func _b1(size: int) -> PoolSim:
	if _shipped == null:
		_shipped = SpeciesCatalog.load_from()
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, _shipped, FakeWorldGen.fixture_content(B1_WORLD),
		PackedFloat64Array(), 2, true)
	check(sim.debug_set_size(size), "size %d" % size)
	sim.drain_events()
	return sim


static func _sting(engaged := [], damage := 5.0) -> Dictionary:
	return {"type": "hit", "attacker": "c_veil", "target": CreatureField.PLAYER_ID, "kind": "sting", "damage": damage,
		"engaged": engaged}


static func _strike_hit() -> Dictionary:
	return {"type": "hit", "attacker": "c_ram", "target": CreatureField.PLAYER_ID, "kind": "ram", "damage": 5.0}


## Invariant 15 over `ticks` (tick -> the events of that tick, in tick order) on a new checker: whether
## it broke, and the report.
func _fifteen(sim: PoolSim, ticks: Dictionary) -> Array:
	var fz := FuzzInvariants.new(sim.species, layout)
	var order := ticks.keys()
	order.sort()
	for t: int in order:
		var events: Array[Dictionary] = []
		events.assign(ticks[t])
		fz.check_15(sim, events, t, "tick %d" % t)
	return [fz.bad.has(15), fz.report()]


## S3G14b (BP3-4): (c) reads the sting's own `engaged`, the token holders when it landed. With "c7"
## on the token before the step, a sting with engaged [] passes and the same sting with ["c7"] fails.
func test_invariant_15_c_reads_the_stings_engaged() -> void:
	var sim := _b1(3)
	sim.creatures.engaged_on_player = PackedStringArray(["c7"])
	check_eq(_fifteen(sim, {100: [_sting([])]})[0], false, "engaged [] passes")
	var got := _fifteen(sim, {100: [_sting(["c7"])]})
	check(got[0] and str(got[1]).contains("(c)"), "engaged [c7] fails (c): %s" % got[1])
	sim.creatures.engaged_on_player = PackedStringArray()


## D-141 (a): with the veil's 1.25 s cooldown at most 2 stings land in any 120 ticks; stings a cooldown
## apart pass, a scripted train of 3 in a window fails, and so does a sting at the damage limit.
func test_invariant_15_a_a_sting_train_or_a_heavy_sting_fails() -> void:
	var sim := _b1(3)
	var cd := CreatureBrain.ticks(float(_shipped.species.veil.hazard.threads.cooldown_s))
	var fz := FuzzInvariants.new(sim.species, layout)
	check_eq([cd, fz._sting_cap], [75, 2], "a 75-tick cooldown: 2 in a window")
	check_eq(_fifteen(sim, {0: [_sting()], cd: [_sting()], 2 * cd: [_sting()], 3 * cd: [_sting()]})[0], false,
		"a sting each cooldown passes")
	var got := _fifteen(sim, {0: [_sting()], 40: [_sting()], 80: [_sting()]})
	check(got[0] and str(got[1]).contains("3 stings"), "three in 81 ticks fail (a): %s" % got[1])
	var limit := fz._damage_limit(sim)
	check(limit > 5.0, "the veil's 5 is under the limit (%.2f)" % limit)
	got = _fifteen(sim, {0: [_sting([], limit)]})
	check(got[0] and str(got[1]).contains("dealt"), "a sting at the limit fails (a): %s" % got[1])


## D-141 (b): a sting 100 ticks after a strike hit fails, and a strike hit 100 ticks after a sting;
## 120 ticks apart passes. A debug set_size clears the windows (BP3-20); a respawn does not.
func test_invariant_15_b_a_sting_near_a_strike_hit_fails() -> void:
	var sim := _b1(3)
	var got := _fifteen(sim, {0: [_strike_hit()], 100: [_sting()]})
	check(got[0] and str(got[1]).contains("after a strike hit"), "a sting 100 ticks after a strike hit fails: %s" % got[1])
	got = _fifteen(sim, {0: [_sting()], 100: [_strike_hit()]})
	check(got[0] and str(got[1]).contains("after a sting"), "a strike hit 100 ticks after a sting fails: %s" % got[1])
	check_eq(_fifteen(sim, {0: [_strike_hit()], 120: [_sting()]})[0], false, "120 ticks apart passes")
	check_eq(_fifteen(sim, {0: [_strike_hit()], 100: [{"type": "debug", "command": "set_size", "to": 3}, _sting()]})[0],
		false, "a set_size cut between them passes")
	check_eq(_fifteen(sim, {0: [_strike_hit()], 100: [{"type": "respawned"}, _sting()]})[0], true, "a respawn is no cut")


## S3G17c: at size 4 a morsel site's item spawning in view or within spawn_safe_m of the cell fails 12,
## one out of view passes, and so does any other carrion in view (a kill's); an item expiring
## "unloaded" in view fails 12 too.
func test_a_morsel_item_appearing_or_unloading_in_view_fails_12() -> void:
	var sim := _b1(4)
	sim.step(SimIntent.new())
	sim.drain_events()
	var near := sim.motion.position + Vector2(5.0, 0.0)
	var far := sim.motion.position + Vector2(200.0, 0.0)
	var cases := {   # name -> [the event, fails 12]
		"a morsel in view": [{"type": "carrion_spawned", "source": "morsel_site", "food_id": "c_hand", "position": near}, true],
		"a morsel out of view": [{"type": "carrion_spawned", "source": "morsel_site", "food_id": "c_hand", "position": far}, false],
		"a kill's carrion in view": [{"type": "carrion_spawned", "source": "creature_death", "food_id": "c_hand", "position": near}, false],
		"unloaded in view": [{"type": "carrion_expired", "food_id": "c_hand", "position": near, "reason": "unloaded"}, true],
		"unloaded out of view": [{"type": "carrion_expired", "food_id": "c_hand", "position": far, "reason": "unloaded"}, false],
	}
	for name: String in cases:
		var c: Array = cases[name]
		var fuzz := FuzzInvariants.new(sim.species, layout)
		var was := fuzz.before(sim)
		var events: Array[Dictionary] = [c[0]]
		fuzz.after(sim, events, sim.tick, name, was)
		check_eq(fuzz.bad.has(12), c[1], "%s: %s" % [name, fuzz.report()])
		if c[1] and fuzz.bad.has(12):
			check(str(fuzz.bad[12].first).contains("c_hand"), "the failure names it: %s" % fuzz.bad[12].first)


## S3G17d: after every step morsel_claims() equals the morsel-site entries holding an item: a size-4
## run with its morsel sites loaded is clean, and a claim count off by one fails 12.
func test_a_morsel_claim_count_that_drifts_fails_12() -> void:
	var sim := _b1(4)
	var fuzz := FuzzInvariants.new(sim.species, layout)
	for t in WorldStream.MORSEL_PASS_TICKS * 2:
		_step(sim, fuzz, "size 4 tick %d" % t)
	check(not sim.world._morsel_loaded.is_empty(), "morsel sites loaded (%d)" % sim.world._morsel_loaded.size())
	check_eq(fuzz.report(), "", "clean")
	sim.world._claims += 1
	var was := fuzz.before(sim)
	fuzz.after(sim, [] as Array[Dictionary], sim.tick, "drifted", was)
	check(fuzz.bad.has(12) and str(fuzz.bad[12].first).contains("S3G17d"), "a drifted count fails 12: %s" % fuzz.report())
	sim.world._claims -= 1


## D-141's invariant 3: a rammer (q < 1 at 4) within respawn_clear_m of the checkpoint fails 3, unless
## the run's last checkpoint change was a landmark's; a growth ends that.
func test_at_a_landmark_checkpoint_invariant_3_counts_only_q_one() -> void:
	var sim := _b1(4)
	sim.debug_set_ai_frozen(true)
	check(sim.debug_spawn_creature("rammer", sim.checkpoint().position + Vector2(2.0, 0.0), 0.0), "a rammer by the checkpoint")
	var c: CreatureField.Creature = sim.creatures.creatures.back()
	c.debug = false   # a data creature (invariant 3 skips dev spawns)
	sim.drain_events()
	check(sim.species.q_of("rammer", 4) < 1.0, "the rammer is below the cell at 4")
	var cases := [   # [name, events, fails 3]
		["no landmark", [], true],
		["a landmark checkpoint", [{"type": "checkpoint_moved", "reason": "landmark", "anchor": "a_f_lm"}], false],
	]
	for case: Array in cases:
		var fuzz := FuzzInvariants.new(sim.species, layout)
		var was := fuzz.before(sim)
		var events: Array[Dictionary] = []
		events.assign(case[1])
		fuzz.after(sim, events, sim.tick, case[0], was)
		check_eq(fuzz.bad.has(3), case[2], "%s: %s" % [case[0], fuzz.report()])
	var fuzz := FuzzInvariants.new(sim.species, layout)
	var events: Array[Dictionary] = [{"type": "checkpoint_moved", "reason": "landmark", "anchor": "a_f_lm"}]
	fuzz.after(sim, events, sim.tick, "landmark", fuzz.before(sim))
	fuzz.after(sim, _growth_events(sim, []), sim.tick, "then a growth", fuzz.before(sim))
	check(fuzz.bad.has(3), "a growth ends the landmark form: %s" % fuzz.report())
	c.debug = true


## D-141's invariant 7 hazard form: a veil left to drift stays within 1.0 x q tm of its drift goal
## once it has drifted DRIFT_SETTLE_TICKS (checked on every tick after), and one pushed 5 tm off fails.
func test_a_drifting_hazard_keeps_to_its_path_and_one_pushed_off_fails_7() -> void:
	var sim := _b1(3)
	check(sim.debug_spawn_creature("veil", sim.motion.position + Vector2(14.0, 0.0), 0.0), "a veil")
	var c: CreatureField.Creature = sim.creatures.creatures.back()
	sim.drain_events()
	var fuzz := FuzzInvariants.new(sim.species, layout)
	for t in FuzzInvariants.DRIFT_SETTLE_TICKS + 120:
		_step(sim, fuzz, "drift tick %d" % t)
	check(int(fuzz.counts.drift_checks) >= 60, "drift checked on %d ticks" % fuzz.counts.drift_checks)
	check(not fuzz.bad.has(7), "on its path: %s" % fuzz.report())
	check_eq(c.brain.state, CreatureBrain.DRIFT, "still drifting")
	var was := fuzz.before(sim)
	var t := sim.tick
	sim.step(SimIntent.new())
	c.motion.position += Vector2(5.0, 0.0)
	fuzz.after(sim, sim.drain_events(), t, "pushed", was)
	check(fuzz.bad.has(7) and str(fuzz.bad[7].first).contains("drift goal"), "pushed 5 tm off fails 7: %s" % fuzz.report())

