extends TestCase
## The cell-to-creature link's rules on the save (game/domain/shore_link.gd): the shore is one world change
## ({"kind": "shore", "x_am", "y_am", "size"}) that rises once and never for a lineage ashore, and keeps its place
## through the file; the offer's reach (REACH_TM) and the farther line past which it opens again (REOPEN_SHARE), in
## am at the cell's size; the crossing's era, "came_ashore" event and first creature (a copy), refused once ashore,
## and undo. The first creature (CreatureRules.from_cell) is the starter quadruped with the cell's hue as its skin.
## Last, the session raises the shore (GameSession.after_events, raise_shore) on a ring paid at the build's top, on
## the shipped world, ahead of the cell on a clear point, and saves that tick. Saves go to the per-process folder
## under user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")

var slot := ""
var _swept := false


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	SaveFolder.clear()
	slot = SaveFolder.path("shore_slot.json")


func after_each() -> void:
	SaveFolder.clear()


## A founded omnivore lineage in the water, nothing saved.
func _save(seed_value := 41) -> SaveGame:
	var founded := Lineage.found(seed_value, "test+dev", PartCatalog.load_from(), "omnivore")
	check(founded.ok, "a lineage is founded: %s" % [founded.errors])
	return founded.save


## The shore entries in the save's world changes (one at most, when the rules hold).
static func _shores(save: SaveGame) -> Array:
	var out := []
	for change in save.world_changes:
		if change is Dictionary and change.get("kind") == ShoreLink.KIND:
			out.append(change)
	return out


## The save without its write time, as text: two saves of the same lineage state compare equal.
static func _state(save: SaveGame) -> String:
	var d := save.to_dict()
	d.erase("saved_at_unix")
	return JSON.stringify(d)


func test_a_shore_rises_once_and_never_for_a_lineage_ashore() -> void:
	var save := _save()
	check(ShoreLink.in_water(save), "a new lineage is in the water")
	check(ShoreLink.shore_of(save).is_empty(), "no shore before it rises")
	# Another world change before it: world_changes is a free array, and the shore is found among its entries.
	save.world_changes.append({"kind": "cairn", "x_am": 1.0, "y_am": 2.0})
	save.world_changes.append("not a dictionary")
	check(ShoreLink.shore_of(save).is_empty(), "other entries are not a shore")
	check(ShoreLink.raise(save, 12.5, -40.25, 4), "the shore rises")
	check_eq(save.world_changes.size(), 3, "one entry appended")
	check_eq(save.world_changes[2], {"kind": "shore", "x_am": 12.5, "y_am": -40.25, "size": 4}, "the shore's entry")
	check_eq(ShoreLink.shore_of(save), save.world_changes[2], "shore_of finds it")
	check_eq(save.world_changes[0], {"kind": "cairn", "x_am": 1.0, "y_am": 2.0}, "the other entry is kept")
	check(not ShoreLink.raise(save, 99.0, 99.0, 4), "a second shore is refused")
	check_eq(_shores(save).size(), 1, "still one shore")
	check_eq(ShoreLink.point_am(save), PackedFloat64Array([12.5, -40.25]), "where it first rose")
	# Through the file (JSON) the shore stays where it rose and still refuses a second; its size reads as a float.
	var again := SaveGame.from_dict(JSON.parse_string(JSON.stringify(save.to_dict(), "", true, true)))
	check_eq(ShoreLink.point_am(again), PackedFloat64Array([12.5, -40.25]), "the reloaded shore's place")
	check_eq(int(ShoreLink.shore_of(again).get("size", 0)), 4, "and the size it rose at")
	check(not ShoreLink.raise(again, 0.0, 0.0, 4), "the reloaded save refuses a second shore")
	var problems := again.validate(PartCatalog.load_from())
	check(problems.is_empty(), "a save with a shore is valid: %s" % [problems])

	var ashore := _save(42)
	ashore.era = ShoreLink.TO_ERA
	check(not ShoreLink.in_water(ashore), "a lineage ashore is not in the water")
	check(not ShoreLink.raise(ashore, 1.0, 1.0, 4), "no shore rises for it")
	check(ashore.world_changes.is_empty(), "nothing recorded")
	ashore.era = "aquatic"
	check(not ShoreLink.raise(ashore, 1.0, 1.0, 4), "nor for any era past the microscopic")


func test_the_shore_s_point_and_distance_are_absolute_am() -> void:
	var save := _save()
	check(ShoreLink.point_am(save).is_empty(), "no point before it rises")
	check_eq(ShoreLink.distance_am(save, PackedFloat64Array([0.0, 0.0])), INF, "INF before it rises")
	# float64 throughout: an x a float32 cannot hold comes back exactly.
	var x := 5000.123456789012
	check(ShoreLink.raise(save, x, -250.0, 4), "risen")
	var p := ShoreLink.point_am(save)
	check_eq(p.size(), 2, "two numbers")
	check(p.size() == 2 and p[0] == x and p[1] == -250.0, "x and y as raised: %s" % [p])
	check_near(ShoreLink.distance_am(save, PackedFloat64Array([x + 3.0, -246.0])), 5.0, 1e-9, "a 3-4-5 triangle")
	check_eq(ShoreLink.distance_am(save, p), 0.0, "zero at the centre")
	check_eq(ShoreLink.distance_am(save, PackedFloat64Array([x])), INF, "a cell place that is not two numbers")
	check_eq(ShoreLink.distance_am(save, PackedFloat64Array()), INF, "nor an empty one")


func test_the_offer_opens_within_4_tm_and_again_only_past_6_tm() -> void:
	# At size 4 one tm is 1.6^3 am; the reach is 4 tm and the line that reopens the offer 1.5 times that.
	var k := WorldConfig.tm_to_am(4)
	check_near(k, 4.096, 1e-12, "tm_to_am(4)")
	var reach := ShoreLink.REACH_TM * k
	var reopen := ShoreLink.REACH_TM * ShoreLink.REOPEN_SHARE * k
	check_near(reach, 16.384, 1e-9, "the reach at size 4 in am")
	check_near(reopen, 24.576, 1e-9, "the reopening line at size 4 in am")
	check(ShoreLink.in_reach(0.0, 4) and ShoreLink.in_reach(reach, 4), "in reach up to 4 tm, the edge included")
	check(not ShoreLink.in_reach(reach + 1e-6, 4), "not past it")
	check(not ShoreLink.out_of_reach(reach + 1e-6, 4), "just past the reach is not yet out of it")
	check(not ShoreLink.out_of_reach(reopen, 4), "6 tm is not out (the line itself)")
	check(ShoreLink.out_of_reach(reopen + 1e-6, 4), "past 6 tm is")
	check(not ShoreLink.in_reach(20.0, 4) and not ShoreLink.out_of_reach(20.0, 4), "between the two: neither")
	# The reach is in tm at the cell's size: 16 am is in reach at size 4 and far out of it at size 1.
	check(ShoreLink.in_reach(16.0, 4), "16 am at size 4")
	check(not ShoreLink.in_reach(16.0, 1) and ShoreLink.out_of_reach(16.0, 1), "16 am at size 1 is past 6 tm")
	check(ShoreLink.in_reach(4.0, 1) and not ShoreLink.in_reach(4.001, 1), "at size 1 one tm is one am")
	check(not ShoreLink.in_reach(INF, 4) and ShoreLink.out_of_reach(INF, 4), "INF (no shore): never in reach")


func test_crossing_moves_the_lineage_ashore_with_a_copy_of_its_first_creature() -> void:
	var save := _save()
	save.genome.generation = 3
	save.adaptation_points = 64
	save.discoveries.append({"type": "place", "id": "giant_husk", "size": 1})
	check(ShoreLink.raise(save, 10.0, -30.0, 4), "the shore rose")
	var lineage := save.lineage_id
	var genome := JSON.stringify(save.genome.to_dict())
	var history := save.lineage_history.size()
	var creature := CreatureRules.from_cell(save.genome)
	var before := ShoreLink.cross(save, creature)
	check_eq(before, {"era": "microscopic", "history_size": history, "creature": {}}, "what it replaced")
	check_eq(save.era, "terrestrial", "the era")
	check(not ShoreLink.in_water(save), "out of the water")
	check_eq(save.lineage_history.size(), history + 1, "one lineage event")
	var event := {"generation": 3, "genome_id": save.genome.genome_id, "event": "came_ashore"}
	check_eq(save.lineage_history[-1], event, "came_ashore with the genome's generation and id")
	check_eq(save.lineage_history[-1], ShoreLink.event_of(save), "event_of's")
	check_eq(save.lineage_history[0].event, "founded", "the founding kept")
	check_eq(save.creature, creature, "the first creature")
	# A deep copy: changing the caller's dictionary (its body too) leaves the save's alone.
	var skin := String(save.creature.body.get("skin_color", ""))
	creature["name"] = "Changed"
	(creature["body"] as Dictionary)["skin_color"] = "#000000"
	check_eq(save.creature.name, CreatureRules.DEFAULT_NAME, "the save's name is its own")
	check_eq(save.creature.body.get("skin_color"), skin, "and so is its body")
	check_eq(save.lineage_id, lineage, "the lineage id carries over")
	check_eq(JSON.stringify(save.genome.to_dict()), genome, "the genome")
	check_eq(save.adaptation_points, 64, "the points")
	check_eq(save.discoveries, [{"type": "place", "id": "giant_husk", "size": 1}], "the discoveries")
	check_eq(save.world_seed, 41, "the world seed")
	check_eq(_shores(save).size(), 1, "the shore stays in the world changes")
	var state := _state(save)
	check_eq(ShoreLink.cross(save, CreatureRules.new_creature()), {}, "a lineage ashore cannot cross again")
	check_eq(_state(save), state, "and nothing changed")


func test_undo_puts_back_the_era_the_history_and_the_creature() -> void:
	var save := _save()
	# A creature from the creature stage's preview, which ran on the lineage slot in the water.
	var preview := CreatureRules.new_creature()
	preview["name"] = "Preview"
	save.creature = preview
	check(ShoreLink.raise(save, 1.0, 2.0, 4), "the shore rose")
	var state := _state(save)
	var before := ShoreLink.cross(save, CreatureRules.from_cell(save.genome))
	check(not before.is_empty() and save.era == "terrestrial", "crossed")
	ShoreLink.undo(save, before)
	check_eq(save.era, "microscopic", "the era")
	check_eq(save.lineage_history.size(), 1, "the history's length: the founding alone")
	check_eq(save.creature, preview, "the creature it had")
	check_eq(_state(save), state, "the whole save as it was")
	ShoreLink.undo(save, {})
	check_eq(_state(save), state, "undoing nothing changes nothing")
	check(not ShoreLink.cross(save, CreatureRules.from_cell(save.genome)).is_empty(), "and it can cross again")
	check_eq(save.lineage_history.size(), 2, "with one came_ashore")


func test_the_first_creature_is_the_starter_in_the_cell_s_hue() -> void:
	var save := _save()
	var rules := CreatureRules.new()
	var fresh := CreatureRules.new_creature()
	check(not (fresh.body as Dictionary).has("skin_color"), "the starter body has no skin colour of its own")
	for hue in [0.0, 0.3, 0.45, 0.99, 1]:
		save.genome.appearance["hue"] = hue
		var c := CreatureRules.from_cell(save.genome)
		var skin := Color.from_hsv(fmod(float(hue), 1.0), 0.55, 0.8)
		check(CreatureRules.cell_skin(float(hue)).is_equal_approx(skin), "hue %s: from_hsv(hue, 0.55, 0.8)" % hue)
		var expected := fresh.duplicate(true)
		(expected.body as Dictionary)["skin_color"] = "#" + skin.to_html(false)
		check_eq(c, expected, "hue %s: new_creature with the skin colour" % hue)
		var text := String(c.body.get("skin_color", ""))
		check(text.length() == 7 and text.begins_with("#") and Color.html_is_valid(text), "hue %s: #rrggbb" % hue)
		var read := Color.html(text)
		check(absf(read.s - 0.55) < 0.01 and absf(read.v - 0.8) < 0.01, "hue %s: softened, %s" % [hue, text])
		check(absf(read.h - fmod(float(hue), 1.0)) < 0.01, "hue %s: the cell's hue, read back %.3f" % [hue, read.h])
		check_eq(rules.validate(c), PackedStringArray(), "hue %s: the body rules pass" % hue)
	check_eq(CreatureRules.cell_skin(0.0).to_html(false), "cc5c5c", "hue 0: a soft red")
	check(CreatureRules.cell_skin(1.3).is_equal_approx(CreatureRules.cell_skin(0.3)), "a hue past 1 wraps")
	check(CreatureRules.cell_skin(-0.7).is_equal_approx(CreatureRules.cell_skin(0.3)), "and one below 0")


func test_a_genome_without_a_numeric_hue_gives_the_plain_starter() -> void:
	var save := _save()
	var fresh := CreatureRules.new_creature()
	save.genome.appearance = {"pattern": "plain"}
	check_eq(CreatureRules.from_cell(save.genome), fresh, "no hue")
	for hue in ["0.3", null, [0.3], true]:
		save.genome.appearance["hue"] = hue
		check_eq(CreatureRules.from_cell(save.genome), fresh, "a hue of %s" % [hue])
	check_eq(CreatureRules.from_cell(null), fresh, "no genome")
	check_eq(CreatureRules.new().validate(fresh), PackedStringArray(), "which passes the body rules")


# --- The session raises the shore (GameSession.after_events and raise_shore) ---


## A new endless omnivore lineage on the shipped world (growth on, its top the build's), saved to the slot.
func _shipped(seed_value: int) -> GameSession:
	var world := WorldConfig.DEFAULT_PATH
	var session := GameSession.new(slot, PoolLayout.DEFAULT_PATH, SpeciesCatalog.DEFAULT_PATH, world)
	var started := session.start_new("omnivore", seed_value)
	check(started.ok and started.saved, "an endless lineage starts and is saved: %s" % [started.errors])
	check(session.sim == null or session.sim.growth != null, "growth runs on the shipped world")
	return session


func test_the_first_ring_paid_at_the_top_raises_the_shore_ahead_and_saves_it() -> void:
	var session := _shipped(4401)
	if session.sim == null or session.sim.growth == null:
		return
	var sim := session.sim
	var top := sim.world.max_size
	check(sim.debug_set_size(top), "the cell at the top, size %d" % top)
	check(session.save_now().ok and not session.dirty, "saved at the top")
	# The real payout: a full ring at the top pays at once (D-32) and the tick's events hold ring_paid.
	sim.drain_events()
	sim.growth.add(sim, sim.growth.ring(top), "test", "shore_test")
	var events := sim.drain_events()
	var paid := events.filter(func(e: Dictionary) -> bool: return e.get("type") == "ring_paid")
	check_eq(paid.size(), 1, "the ring was paid: %s" % [events])
	check(ShoreLink.shore_of(sim.save).is_empty(), "no shore before the scene hands the events over")
	var saved := session.after_events(events)
	check(saved.get("ok", false), "the tick that raised the shore is saved: %s" % [saved])
	check_eq(session.last_save, saved, "as save_now saves")
	check(not session.dirty, "nothing unsaved after it")
	var shore := ShoreLink.shore_of(sim.save)
	check(not shore.is_empty(), "the shore rose")
	if shore.is_empty():
		return
	check_eq(shore.get("size"), top, "at the size it rose at")
	var p := ShoreLink.point_am(sim.save)
	# Where it stands, in local tm round the cell: ahead (up the screen) and in open water for twice the radius.
	var local := sim.world.local_of_abs(p[0], p[1])
	var cell := sim.motion.position
	var ahead := (local - cell).dot(ShoreLink.RISE_DIRECTION)
	check(ahead >= ShoreLink.RISE_AHEAD_TM * 0.5, "%.2f tm ahead (shore %s, cell %s)" % [ahead, local, cell])
	check(sim.arena.is_clear(local, sim.phenotype.radius * 2.0), "on a clear point for twice the cell's radius")
	var d_tm := ShoreLink.distance_am(sim.save, sim.absolute_position_am()) / WorldConfig.tm_to_am(top)
	check(d_tm >= ShoreLink.RISE_AHEAD_TM * 0.5, "%.2f tm from the cell" % d_tm)
	check(not ShoreLink.in_reach(d_tm * WorldConfig.tm_to_am(top), top), "out of reach: the offer waits")
	# The file holds it, as Continue reads it.
	var loaded := session.persistence.load_from(slot)
	check(loaded.ok, "the slot loads: %s" % [loaded.errors])
	if loaded.ok:
		var q := ShoreLink.point_am(loaded.save)
		check(q.size() == 2 and absf(q[0] - p[0]) < 1e-9 and absf(q[1] - p[1]) < 1e-9, "the file's shore: %s" % [q])
		check_eq(int(ShoreLink.shore_of(loaded.save).get("size", 0)), top, "and its size")
	# A second ring paid raises none and writes nothing.
	var text := FileAccess.get_file_as_string(slot)
	sim.growth.add(sim, sim.growth.ring(top), "test", "shore_test_2")
	check_eq(session.after_events(sim.drain_events()), {}, "a second ring paid saves nothing")
	check_eq(session.after_events([{"type": "ring_paid", "size": top}]), {}, "nor does a third")
	check_eq(_shores(sim.save).size(), 1, "still one shore")
	check_eq(ShoreLink.point_am(sim.save), p, "where it first rose")
	check_eq(FileAccess.get_file_as_string(slot), text, "the file as it was")
	check(not session.raise_shore(), "raise_shore refuses a second")


func test_below_the_top_ashore_dead_or_in_the_pool_a_ring_paid_raises_nothing() -> void:
	var session := _shipped(4402)
	if session.sim == null or session.sim.growth == null:
		return
	var sim := session.sim
	var top := sim.world.max_size
	check(sim.debug_set_size(top - 1), "the cell at size %d, below the top" % (top - 1))
	check(session.save_now().ok, "saved")
	var text := FileAccess.get_file_as_string(slot)
	check_eq(session.after_events([{"type": "ring_paid", "size": top - 1}]), {}, "a ring paid below the top")
	check(not session.raise_shore(), "raise_shore refuses below the top")
	check(sim.save.world_changes.is_empty(), "no shore")
	check_eq(FileAccess.get_file_as_string(slot), text, "nothing written")
	# At the top, a lineage already ashore raises none.
	check(sim.debug_set_size(top), "at the top")
	sim.save.era = ShoreLink.TO_ERA
	check_eq(session.after_events([{"type": "ring_paid", "size": top}]), {}, "a lineage ashore")
	check(sim.save.world_changes.is_empty(), "no shore for it")
	sim.save.era = ShoreLink.FROM_ERA
	# Nor while the cell is dead (its death not yet resolved).
	sim.debug_hurt_player(1.0e6)
	check(sim.dead, "dead")
	check_eq(session.after_events([{"type": "ring_paid", "size": top}]), {}, "a dead cell")
	check(sim.save.world_changes.is_empty(), "no shore while it is dead")
	# The M1 pool has no world and no top.
	var pool := GameSession.new(SaveFolder.path("pool_slot.json"))
	check(pool.start_new("grazer", 4403).ok, "a pool lineage")
	check_eq(pool.after_events([{"type": "ring_paid", "size": 1}]), {}, "a ring paid in the pool")
	check(not pool.raise_shore() and pool.sim.save.world_changes.is_empty(), "raises nothing")
	check(not GameSession.new(slot).raise_shore(), "nor does a session with no run")


## The point RISE_AHEAD_TM ahead may be in a collider: the shore then stands on the first clear point the rule C1
## spiral finds round it (PoolSim.clear_point_on, twice the cell's radius), still well ahead of the cell.
func test_a_shore_whose_point_ahead_is_blocked_rises_on_the_spiral_s_clear_point() -> void:
	var session := _shipped(4404)
	if session.sim == null or session.sim.growth == null:
		return
	var sim := session.sim
	var top := sim.world.max_size
	check(sim.debug_set_size(top), "the cell at the top, size %d" % top)
	var r := sim.phenotype.radius
	var rise := ShoreLink.RISE_DIRECTION * ShoreLink.RISE_AHEAD_TM
	# A point inside a collider, among the loaded chunks round the cell, with open water RISE_AHEAD_TM behind it.
	var blocked := Vector2.INF
	for y in range(-24, 25):
		for x in range(-24, 25):
			var q := sim.motion.position + Vector2(x, y)
			if not sim.arena.is_clear(q, 0.05) and sim.arena.is_clear(q - rise, r * 1.5):
				blocked = q
				break
		if blocked.is_finite():
			break
	check(blocked.is_finite(), "a collider near the cell")
	if not blocked.is_finite():
		return
	check(sim.debug_teleport(blocked - rise), "the cell %.0f tm behind it" % ShoreLink.RISE_AHEAD_TM)
	check(session.raise_shore(), "the shore rises")
	var p := ShoreLink.point_am(sim.save)
	if p.is_empty():
		return
	var local := sim.world.local_of_abs(p[0], p[1])
	var expected := PoolSim.clear_point_on(sim.arena, blocked, r * 2.0)
	check(local.distance_to(expected) < 1e-4, "on the spiral's clear point: %s, expected %s" % [local, expected])
	check(local.distance_to(blocked) > 0.1, "not in the collider")
	check(sim.arena.is_clear(local, r * 2.0), "clear for twice the cell's radius")
	var ahead := (local - sim.motion.position).dot(ShoreLink.RISE_DIRECTION)
	check(ahead >= ShoreLink.RISE_AHEAD_TM * 0.5, "%.2f tm ahead of the cell" % ahead)


## A landmark's checkpoint_moved comes before a ring_paid in the same tick (the world steps before growth): the
## shore still rises, and the tick is saved once.
func test_a_ring_paid_after_a_checkpoint_move_in_the_same_tick_still_raises_the_shore() -> void:
	var session := _shipped(4405)
	if session.sim == null or session.sim.growth == null:
		return
	var sim := session.sim
	var top := sim.world.max_size
	check(sim.debug_set_size(top), "the cell at the top, size %d" % top)
	var saved := session.after_events([{"type": "checkpoint_moved", "reason": "landmark"}, {"type": "ring_paid", "size": top}])
	check(saved.get("ok", false), "the tick is saved: %s" % [saved])
	check(not ShoreLink.shore_of(sim.save).is_empty(), "the shore rose")
	var loaded := session.persistence.load_from(slot)
	check(loaded.ok and not ShoreLink.shore_of(loaded.save).is_empty(), "and the file holds it")


## GameSession.cross_ashore: the cell saved at the shore, the checkpoint, the lineage ashore, and the session counts
## it saved (a quit during the crawl asks nothing). Without a shore nothing changes and the reason comes back.
func test_crossing_ashore_through_the_session_leaves_nothing_unsaved() -> void:
	var session := _shipped(4406)
	if session.sim == null or session.sim.growth == null:
		return
	var sim := session.sim
	var top := sim.world.max_size
	check(sim.debug_set_size(top), "the cell at the top, size %d" % top)
	var refused := session.cross_ashore()
	check(not refused.ok and not refused.errors.is_empty(), "refused without a shore: %s" % [refused.errors])
	check_eq(sim.save.era, ShoreLink.FROM_ERA, "still in the water")
	check(session.raise_shore(), "the shore rises")
	var points := sim.save.adaptation_points
	var result := session.cross_ashore()
	check(result.ok, "the lineage crosses: %s" % [result.errors])
	check_eq(sim.save.era, ShoreLink.TO_ERA, "ashore in the sim's save")
	check(not session.dirty, "nothing unsaved after the crossing")
	var loaded := session.persistence.load_from(slot)
	check(loaded.ok and loaded.save.era == ShoreLink.TO_ERA and loaded.save.adaptation_points == points,
		"the slot is ashore with the same points")
	var cp := session.persistence.load_from(EraTransition.checkpoint_path(slot))
	check(cp.ok and cp.save.era == ShoreLink.FROM_ERA, "the checkpoint holds the cell in the water")
