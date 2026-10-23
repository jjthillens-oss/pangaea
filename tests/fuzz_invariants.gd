extends RefCounted
## The fuzz invariants (S1 core 8.7), checked after every tick of a swim. A test takes `before(sim)`
## before each step and hands it to `after(...)` with the step's drained events; `bad` holds every
## broken invariant (count and first case) and `counts` the non-vacuity counters.
##
## The endless world's invariants (from the cell's point of view; "in view" is inside the widest
## view's footprint grown by the spawn margin plus the object's radius, as the spawn check measures):
##
## 12  nothing appears in or vanishes from view: a creature that spawns, wakes, sleeps or leaves
##     (unloaded, evicted, stuck) is at least spawn_safe_m from the cell and out of view; every shell,
##     zone, anchor and place of a chunk that loads or unloads is out of view; a zone that joins or
##     leaves the food view is out of view; no zone gains more than one plankton item in a tick; a
##     plankton item of a zone that left the food view, and a carrion item gone with no expiry or meal
##     naming it, went out of view.
##     Block-step events (chunks, sleep, wake, eviction, "unloaded", the food view) are measured from
##     the cell before the step, M1-step events (spawns, "stuck") from the cell after it. A tick with a
##     respawn or a dev teleport is a camera cut: step 0's own events (up to and including respawned or
##     debug teleport_abs) and its fill at once are exempt (D-10, D-11, C-9), and everything after is
##     measured from the cell after the step.
## 13  every position the sim stores (the explicit list of core 8.7) is under 256 tm long.
## 16  every sleeper is at least spawn_safe_m from the cell and out of its view.
##
## Each event's positions are in the frame in force at its place in the list: a rebased changes it.

const LOCAL_BOUND := 256.0
const PLACE_RADIUS_TM := 4.0           ## core 8.7: a place's extent
const ANCHOR_RADIUS_BU := 3.0          ## core 8.7: an anchor's extent, times the band's bu-to-tm
## Reasons a creature leaves that the player must not see happen.
const HIDDEN_REMOVALS := {"unloaded": "block", "evicted": "block", "stuck": "step"}

var bad := {}      ## invariant -> {"count": int, "first": String}
var counts := {}   ## non-vacuity counters
var species: SpeciesCatalog
var layout: PoolLayout
var _quad := PackedVector2Array()   ## the widest view's footprint round (0, 0)
var _margin := 0.0                  ## look-ahead plus the spawn gap
var _safe := 0.0


func _init(p_species: SpeciesCatalog, p_layout: PoolLayout) -> void:
	species = p_species
	layout = p_layout
	var fairness := species.fairness
	_quad = ViewFootprint.corners(Vector2.ZERO, layout.camera, float(layout.camera.zoom_max), float(fairness.spawn_view_aspect))
	_margin = float(layout.camera.look_ahead_max) + float(fairness.spawn_view_margin_m)
	_safe = float(fairness.spawn_safe_m)
	for key in ["checked", "spawns", "sleeps", "wakes", "loads", "unloads", "evictions", "zone_changes", "rebases", "cuts"]:
		counts[key] = 0


## Records a broken invariant.
func fail(inv: int, what: String) -> void:
	if not bad.has(inv):
		bad[inv] = {"count": 0, "first": what}
	bad[inv].count += 1


## "inv 12: 3 (first: …)" lines, by invariant; "" when every invariant held.
func report() -> String:
	var lines := PackedStringArray()
	var invs := bad.keys()
	invs.sort()
	for inv in invs:
		lines.append("inv %d: %d (first: %s)" % [inv, bad[inv].count, bad[inv].first])
	return "\n".join(lines)


## What `after` needs from before the step. Endless: the frame, the cell, the loaded chunks, the food
## view, every plankton and carrion item and every creature's radius.
func before(sim: PoolSim) -> Dictionary:
	if sim.world == null:
		return {}
	var w := sim.world
	var chunks := {}
	for key in w.loaded_keys():
		chunks[key] = w.chunk(key)
	var zones := {}
	for z in sim.region.zones:
		zones[z.id] = {"center": z.center, "radius": float(z.radius)}
	var plankton := {}
	for item in sim.plankton.items:
		plankton[item.id] = {"zone": item.zone, "position": item.position}
	var carrion := {}
	for item in sim.carrion.items:
		carrion[item.id] = item.position
	var radii := {}
	if sim.creatures != null:
		for c in sim.creatures.creatures:
			radii[c.id] = c.phenotype.radius
	return {"origin": PackedFloat64Array([w.origin_x_am, w.origin_y_am]), "cell": sim.motion.position, "dead": sim.dead,
		"chunks": chunks, "active": sim.plankton.active_zones.duplicate(), "zones": zones, "plankton": plankton,
		"carrion": carrion, "radii": radii}


## Checks the tick that `events` came from (`t` its number, `where` names it in a failure) against
## `was`, what `before` returned before it.
func after(sim: PoolSim, events: Array[Dictionary], t: int, where: String, was: Dictionary) -> void:
	if sim.world == null or was.is_empty():
		return
	_check_12(sim, events, t, where, was)
	_check_13(sim, where)
	_check_16(sim, where)


# --- 12 ---

func _check_12(sim: PoolSim, events: Array[Dictionary], _t: int, where: String, was: Dictionary) -> void:
	var w := sim.world
	var k := w._tm_to_am
	var now_origin := PackedFloat64Array([w.origin_x_am, w.origin_y_am])
	var cell_after := _abs(sim.motion.position, now_origin, k)
	# The cut: everything up to the last respawned or teleport_abs is step 0's own (exempt).
	var cut_at := -1
	for i in events.size():
		var e := events[i]
		if e.type == "respawned" or (e.type == "debug" and str(e.get("command", "")) == "teleport_abs"):
			cut_at = i
	var cut := cut_at >= 0
	if cut:
		counts.cuts += 1
	var cell_block := cell_after if cut else _abs(was.cell, was.origin, k)
	var frame: PackedFloat64Array = was.origin
	var gone_carrion := {}
	for i in events.size():
		var e := events[i]
		if e.type == "rebased":
			frame = PackedFloat64Array([float(e.origin_am[0]), float(e.origin_am[1])])
			counts.rebases += 1
			continue
		if e.type == "carrion_expired" or e.type == "ate" or e.type == "creature_ate":
			gone_carrion[str(e.get("food_id", ""))] = true
		if i <= cut_at:
			continue
		var tag := "%s: %s" % [where, e.type]
		match e.type:
			"creature_spawned":
				if bool(e.get("debug", false)):
					continue
				counts.spawns += 1
				_creature_hidden(sim, e, _abs(e.position, frame, k), cell_after, was, tag)
			"creature_removed":
				var when := str(HIDDEN_REMOVALS.get(str(e.reason), ""))
				if when.is_empty():
					continue
				if e.reason == "evicted":
					counts.evictions += 1
				_creature_hidden(sim, e, _abs(e.position, frame, k), cell_block if when == "block" else cell_after, was,
					"%s (%s)" % [tag, e.reason])
			"creature_slept", "creature_woke":
				counts["sleeps" if e.type == "creature_slept" else "wakes"] += 1
				_creature_hidden(sim, e, _abs(e.position, frame, k), cell_block, was, tag)
			"chunk_loaded":
				counts.loads += 1
				for s in e.shells:
					_out_of_view(_abs(s.position, frame, k), float(s.radius), cell_block, "%s %s shell %s" % [tag, e.key, s.id])
				for z in e.zones:
					_out_of_view(_abs(z.center, frame, k), float(z.radius), cell_block, "%s %s zone %s" % [tag, e.key, z.id])
				for a in e.anchors:
					_out_of_view(_abs(a.position, frame, k), _anchor_r(w), cell_block, "%s %s anchor %s" % [tag, e.key, a.id])
				for p in e.places:
					_out_of_view(_abs(p.position, frame, k), PLACE_RADIUS_TM, cell_block, "%s %s place %s" % [tag, e.key, p.id])
			"chunk_unloaded":
				counts.unloads += 1
				var ch: WorldChunk = was.chunks.get(e.key, null)
				if ch == null:
					fail(12, "%s %s: not loaded before the tick" % [tag, e.key])
					continue
				for s in ch.shells:
					_out_of_view(_tm(s.x, s.y), float(s.r), cell_block, "%s %s shell %s" % [tag, e.key, s.id])
				for z in ch.zones:
					_out_of_view(_tm(z.x, z.y), float(z.radius), cell_block, "%s %s zone %s" % [tag, e.key, z.id])
				for a in ch.anchors:
					_out_of_view(_tm(a.x, a.y), _anchor_r(w), cell_block, "%s %s anchor %s" % [tag, e.key, a.id])
				for p in ch.places:
					_out_of_view(_tm(p.x, p.y), PLACE_RADIUS_TM, cell_block, "%s %s place %s" % [tag, e.key, p.id])
	if cut:
		_check_food_gone(sim, where, was, gone_carrion, cell_block, k)
		return
	# The food view: zones that joined or left it, and how fast each zone grows.
	var active := sim.plankton.active_zones
	for id in active:
		if not was.active.has(id):
			counts.zone_changes += 1
			var z := sim.region.zone(id)
			_out_of_view(_abs(z.center, now_origin, k), float(z.radius), cell_block, "%s: zone %s joined the food view" % [where, id])
	for id in was.active:
		if not active.has(id):
			counts.zone_changes += 1
			var z: Dictionary = was.zones.get(id, {})
			if not z.is_empty():
				_out_of_view(_abs(z.center, was.origin, k), float(z.radius), cell_block, "%s: zone %s left the food view" % [where, id])
	var had := {}
	for id in was.plankton:
		var zone := str(was.plankton[id].zone)
		had[zone] = int(had.get(zone, 0)) + 1
	var has := {}
	for item in sim.plankton.items:
		has[item.zone] = int(has.get(item.zone, 0)) + 1
	for zone in has:
		if int(has[zone]) - int(had.get(zone, 0)) > 1:
			fail(12, "%s: zone %s gained %d plankton items" % [where, zone, int(has[zone]) - int(had.get(zone, 0))])
	_check_food_gone(sim, where, was, gone_carrion, cell_block, k)


## Plankton of zones no longer in the food view, and carrion gone with no expiry or meal, went out
## of view.
func _check_food_gone(sim: PoolSim, where: String, was: Dictionary, gone_carrion: Dictionary,
		cell_block: PackedFloat64Array, k: float) -> void:
	var now_plankton := {}
	for item in sim.plankton.items:
		now_plankton[item.id] = true
	for id in was.plankton:
		var zone := str(was.plankton[id].zone)
		if not now_plankton.has(id) and not sim.plankton.active_zones.has(zone):
			_out_of_view(_abs(was.plankton[id].position, was.origin, k), sim.plankton.item_radius, cell_block,
				"%s: plankton %s of zone %s dropped" % [where, id, zone])
	var now_carrion := {}
	for item in sim.carrion.items:
		now_carrion[item.id] = true
	for id in was.carrion:
		if not now_carrion.has(id) and not gone_carrion.has(id):
			_out_of_view(_abs(was.carrion[id], was.origin, k), sim.carrion.item_radius, cell_block,
				"%s: carrion %s dropped" % [where, id])


## A creature event's body: at least spawn_safe_m from the measuring point and out of view.
func _creature_hidden(sim: PoolSim, e: Dictionary, at: PackedFloat64Array, m: PackedFloat64Array, was: Dictionary,
		tag: String) -> void:
	counts.checked += 1
	var r := float(was.radii.get(e.id, 0.0))
	if sim.creatures != null:
		var c := sim.creatures.find(str(e.id))
		if c != null:
			r = c.phenotype.radius
	var rel := _rel(at, m)
	if rel.length() < _safe:
		fail(12, "%s %s %.2f tm from the cell" % [tag, e.id, rel.length()])
	elif _in_view(rel, r):
		fail(12, "%s %s in view at %s from the cell" % [tag, e.id, rel])


func _out_of_view(at: PackedFloat64Array, r: float, m: PackedFloat64Array, tag: String) -> void:
	counts.checked += 1
	var rel := _rel(at, m)
	if _in_view(rel, r):
		fail(12, "%s in view at %s from the cell" % [tag, rel])


# --- 13 ---

func _check_13(sim: PoolSim, where: String) -> void:
	var far := {"length": 0.0, "what": ""}
	_far(far, sim.motion.position, "cell position")
	_far(far, sim.motion.prev_position, "cell prev_position")
	_far(far, sim.actor.position, "cell actor")
	if sim.creatures != null:
		for c in sim.creatures.creatures:
			_far(far, c.motion.position, "%s position" % c.id)
			_far(far, c.motion.prev_position, "%s prev_position" % c.id)
			_far(far, c.actor.position, "%s actor" % c.id)
			var b := c.brain
			if b == null:
				continue
			for id in b.seen:
				_far(far, b.seen[id].position, "%s seen %s" % [c.id, id])
			if not b.lane.is_empty():
				_far(far, b.lane.origin, "%s lane origin" % c.id)
			_far(far, b.goal, "%s goal" % c.id)
			if not b.progress.is_empty():
				_far(far, b.progress.position, "%s progress" % c.id)
			_far(far, b.flee_from, "%s flee_from" % c.id)
			_far(far, b.home, "%s home" % c.id)
			_far(far, b.territory_center, "%s territory_center" % c.id)
	for item in sim.plankton.items:
		_far(far, item.position, "plankton %s" % item.id)
		_far(far, item.anchor, "plankton %s anchor" % item.id)
	for item in sim.carrion.items:
		_far(far, item.position, "carrion %s" % item.id)
	for z in sim.region.zones:
		_far(far, z.center, "zone %s" % z.id)
	for id in sim.world.sites:
		var s: Dictionary = sim.world.sites[id]
		_far(far, s.home, "site %s home" % id)
		if not s.territory.is_empty():
			_far(far, s.territory.center, "site %s territory" % id)
		_far(far, s.reach.center, "site %s reach" % id)
	if sim.arena is ChunkArena:
		for p in (sim.arena as ChunkArena)._centers:
			_far(far, p, "a collider")
	if float(far.length) >= LOCAL_BOUND:
		fail(13, "%s: %s at %.1f tm" % [where, far.what, far.length])


func _far(far: Dictionary, p: Vector2, what: String) -> void:
	if p.is_finite() and p.length() > float(far.length):
		far.length = p.length()
		far.what = what


# --- 16 ---

func _check_16(sim: PoolSim, where: String) -> void:
	if sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if not c.asleep:
			continue
		var rel := c.motion.position - sim.motion.position
		if rel.length() < _safe:
			fail(16, "%s: sleeper %s %.2f tm from the cell" % [where, c.id, rel.length()])
		elif _in_view(rel, c.phenotype.radius):
			fail(16, "%s: sleeper %s in view at %s" % [where, c.id, rel])


# --- frames ---

## A local position in the frame `origin` (am) as absolute tm, in float64.
static func _abs(p: Vector2, origin: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return PackedFloat64Array([origin[0] / k + float(p.x), origin[1] / k + float(p.y)])


static func _tm(x: Variant, y: Variant) -> PackedFloat64Array:
	return PackedFloat64Array([float(x), float(y)])


static func _rel(at: PackedFloat64Array, m: PackedFloat64Array) -> Vector2:
	return Vector2(at[0] - m[0], at[1] - m[1])


func _in_view(rel: Vector2, r: float) -> bool:
	return _quad.is_empty() or ViewFootprint.distance_outside(_quad, rel) <= _margin + r


static func _anchor_r(w: WorldStream) -> float:
	return ANCHOR_RADIUS_BU * WorldConfig.bu_to_tm(w.size)
