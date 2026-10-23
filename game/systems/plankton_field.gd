class_name PlanktonField
extends RefCounted
## Plankton items the cell can touch, as a view of EcologyRegion stock (M1 step 2). A zone's
## amount is the only authority on how much plankton exists: the zone shows one item per
## unit_energy it holds (up to max_items_per_zone). Each tick a zone below that spawns one item
## and a zone above it removes its newest item.
##
## Items drift around an anchor. The drift is simulated, not just drawn, because reach depends on
## it. Spawn points come from the region's seeded RNG; drift phases come from the item number, so
## the field draws no random numbers of its own.
##
## In the endless world (S1) only the zones near the cell show plankton: `active_zones` names them
## (WorldStream's food view sets it every tick), the others keep their stock but show no items.

const SPAWN_TRIES := 8
const COUNT_EPSILON := 1e-6           ## 23.9999999 energy still shows three 8-energy items
const GOLDEN_ANGLE := 2.399963229728653
const GOLDEN_RATIO_FRACTION := 0.6180339887498949
## An emptied zone can report "empty" again once back to half capacity (and to at least one unit).
const REGROWN_LATCH_SHARE := 0.5

var unit_energy := 8.0
var points := 1
var item_radius := 0.18
var max_items_per_zone := 12
var drift_amplitude := 0.35           ## m on each axis
var drift_period := Vector2(7.0, 13.0)  ## shortest and longest drift period, s
## Insertion-ordered: [{"id", "zone", "kind": "plant", "position", "radius", "energy", "points",
## "anchor", "phase": Vector2, "omega": Vector2, "born_tick"}]. Read it freely; change it only through
## this field's functions (they keep the packed copies, the id index and the zone counts below with
## it). A list changed from outside is taken in again on the next tick, read or find when its size no
## longer matches; a same-size change goes unseen.
var items: Array[Dictionary] = []
var next_number := 1
## zone_empty / zone_regrown events since PoolSim last took them: {"type", "zone"}
var events: Array[Dictionary] = []
## Endless mode: only the zones in `active_zones` spawn, fill or report; the pool shows every zone.
var endless := false
var active_zones := {}                ## zone id -> true (endless mode)
var _empty_latched := {}
var _regrowing := {}
var _zone_counts := {}                ## zone id -> how many of `items` it shows (kept with every change)
## Each item's drift phase and rates, in `items` order: the drift loop's packed copy (they never change).
var _phase := PackedVector2Array()
var _omega := PackedVector2Array()
var _radii := PackedFloat64Array()    ## each item's radius, in `items` order (packed_radii)
var _by_id := {}                      ## item id -> the item (ids are unique: "pk_" and next_number)


## config: the layout's "plankton" block.
static func create(config: Dictionary) -> PlanktonField:
	var field := PlanktonField.new()
	field.unit_energy = config.unit_energy
	field.points = config.points
	field.item_radius = config.item_radius
	field.max_items_per_zone = config.max_items_per_zone
	field.drift_amplitude = config.drift_amplitude
	field.drift_period = config.drift_period_s
	return field


## How far an anchor keeps from every collider: the item and its whole drift.
func anchor_clearance() -> float:
	return item_radius + drift_reach()


## Furthest an item gets from its anchor (each axis swings by drift_amplitude).
func drift_reach() -> float:
	return drift_amplitude * sqrt(2.0)


## How many items a zone shows at its current amount.
func target_count(zone: Dictionary) -> int:
	return mini(max_items_per_zone, floori(float(zone.amount) / unit_energy + COUNT_EPSILON))


## How many items a full zone shows.
func max_count(zone: Dictionary) -> int:
	return mini(max_items_per_zone, floori(float(zone.capacity) / unit_energy + COUNT_EPSILON))


func count_in(zone_id: String) -> int:
	return _zone_counts.get(zone_id, 0)


## True from a zone's "zone_empty" until it is full of items again.
func is_regrowing(zone_id: String) -> bool:
	return _regrowing.has(zone_id)


## Fills every zone up to its count at once (a new world starts full).
func fill(region: EcologyRegion, arena: PoolArena, tick_number: int, now: float) -> void:
	for zone in region.zones:
		if endless and not active_zones.has(zone.id):
			continue
		fill_zone(zone, region, arena, tick_number, now)


## Fills one zone up to its count at once (endless mode: a zone that must not grow in view).
func fill_zone(zone: Dictionary, region: EcologyRegion, arena: PoolArena, tick_number: int, now: float) -> void:
	for i in target_count(zone) - count_in(zone.id):
		_try_spawn(zone, region, arena, tick_number, now)


func tick(region: EcologyRegion, arena: PoolArena, tick_number: int, now: float) -> void:
	if _phase.size() != items.size():
		_repack()   # only if something outside this file changed `items`
	var active := active_zones
	var most := max_items_per_zone
	var unit := unit_energy
	for zone in region.zones:
		var id: String = zone.id
		if endless and not active.has(id):
			continue
		var have: int = _zone_counts.get(id, 0)   # only this zone's own spawn or removal changes it
		var want := mini(most, floori(float(zone.amount) / unit + COUNT_EPSILON))   # target_count written out
		if have < want and _try_spawn(zone, region, arena, tick_number, now):
			have += 1
		elif have > want:
			_remove_newest(id)
			have -= 1
		if have == 0 or _empty_latched.has(id) or _regrowing.has(id):
			_update_flags(zone, have)   # otherwise it changes nothing
	var amp := drift_amplitude
	var i := 0
	for item in items:
		var phase := _phase[i]   # _drifted written out
		var omega := _omega[i]
		item.position = item.anchor + amp * Vector2(sin(now * omega.x + phase.x), cos(now * omega.y + phase.y))
		i += 1


## Items whose centers lie within `reach` of `p`, in insertion order.
func items_near(p: Vector2, reach: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach_sq := reach * reach
	for item in items:
		if p.distance_squared_to(item.position) <= reach_sq:
			out.append(item)
	return out


## Every item's radius, packed in `items` order (a copy), for the senses' food snapshot: what
## reading them off the items gives (an item's radius never changes).
func packed_radii() -> PackedFloat64Array:
	if _radii.size() != items.size():
		_repack()   # only if something outside this file changed `items`
	return _radii.duplicate()


## The item with this id, or {}: what a scan of `items` finds.
func find(id: String) -> Dictionary:
	if _by_id.size() != items.size():
		_repack()   # only if something outside this file changed `items`
	return _by_id.get(id, {})


## Removes an eaten item. The caller has already taken its energy from the zone.
func consume(id: String) -> bool:
	for i in items.size():
		if items[i].id == id:
			_zone_counts[items[i].zone] -= 1
			_by_id.erase(id)
			items.remove_at(i)
			_phase.remove_at(i)
			_omega.remove_at(i)
			_radii.remove_at(i)
			return true
	return false


## Removes every item of a zone (dev command; the caller empties the zone's stock).
func clear_zone(zone_id: String) -> void:
	if int(_zone_counts.get(zone_id, 0)) > 0:
		items = items.filter(func(item: Dictionary) -> bool: return item.zone != zone_id)
		_repack()
	_zone_counts.erase(zone_id)


## Endless mode: a zone left the food view (or its ground unloaded). Its items go without events
## (they are out of view) and its empty/regrown flags are forgotten; its stock is the region's.
func drop_zone(zone_id: String) -> void:
	clear_zone(zone_id)
	_empty_latched.erase(zone_id)
	_regrowing.erase(zone_id)


func _try_spawn(zone: Dictionary, region: EcologyRegion, arena: PoolArena, tick_number: int, now: float) -> bool:
	# Anchors sit far enough inside the zone that the drift never carries an item out of it.
	var radius: float = zone.radius
	var inset := maxf(0.0, radius - drift_reach()) / radius
	for i in SPAWN_TRIES:
		var anchor: Vector2 = zone.center + (region.random_point_in(zone.id) - zone.center) * inset
		if arena.is_clear(anchor, anchor_clearance()):
			_add(zone.id, anchor, tick_number, now)
			return true
	return false


func _add(zone_id: String, anchor: Vector2, tick_number: int, now: float) -> void:
	var n := next_number
	next_number += 1
	# Golden-ratio steps spread phases and periods evenly without a random draw.
	var period_x := lerpf(drift_period.x, drift_period.y, fposmod(n * GOLDEN_RATIO_FRACTION, 1.0))
	var period_y := lerpf(drift_period.x, drift_period.y, fposmod(n * GOLDEN_RATIO_FRACTION * 2.0 + 0.5, 1.0))
	var item := {
		"id": "pk_%d" % n,
		"zone": zone_id,
		"kind": "plant",
		"position": anchor,
		"radius": item_radius,
		"energy": unit_energy,
		"points": points,
		"anchor": anchor,
		"phase": Vector2(fposmod(n * GOLDEN_ANGLE, TAU), fposmod(n * GOLDEN_ANGLE * 2.0, TAU)),
		"omega": Vector2(TAU / period_x, TAU / period_y),
		"born_tick": tick_number,
	}
	item.position = _drifted(item, now)
	items.append(item)
	_phase.append(item.phase)
	_omega.append(item.omega)
	_radii.append(item.radius)
	_by_id[item.id] = item
	_zone_counts[zone_id] = int(_zone_counts.get(zone_id, 0)) + 1


## The packed copies (drift phases and rates, radii), the id index and the zone counts, from the
## items.
func _repack() -> void:
	_phase.resize(items.size())
	_omega.resize(items.size())
	_radii.resize(items.size())
	_by_id.clear()
	_zone_counts.clear()
	for i in items.size():
		var item := items[i]
		_phase[i] = item.phase
		_omega[i] = item.omega
		_radii[i] = item.radius
		_by_id[item.id] = item
		_zone_counts[item.zone] = int(_zone_counts.get(item.zone, 0)) + 1


func _drifted(item: Dictionary, now: float) -> Vector2:
	var phase: Vector2 = item.phase
	var omega: Vector2 = item.omega
	return item.anchor + drift_amplitude * Vector2(sin(now * omega.x + phase.x), cos(now * omega.y + phase.y))


func _remove_newest(zone_id: String) -> void:
	for i in range(items.size() - 1, -1, -1):
		if items[i].zone == zone_id:
			_zone_counts[zone_id] -= 1
			_by_id.erase(items[i].id)
			items.remove_at(i)
			_phase.remove_at(i)
			_omega.remove_at(i)
			_radii.remove_at(i)
			return


## "zone_empty" when a zone has no items and less than one unit of stock; latched until the zone
## is back to half capacity. Never below one unit: half of a zone with room for one item is still
## too little to show it, and re-arming there would report "empty" again every other tick.
## "zone_regrown" when an emptied zone shows all its items again.
func _update_flags(zone: Dictionary, have: int) -> void:
	var id: String = zone.id
	if not _empty_latched.has(id):
		if have == 0 and zone.amount < unit_energy:
			_empty_latched[id] = true
			_regrowing[id] = true
			events.append({"type": "zone_empty", "zone": id})
	elif zone.amount >= maxf(unit_energy, zone.capacity * REGROWN_LATCH_SHARE):
		_empty_latched.erase(id)
	if _regrowing.has(id) and have >= max_count(zone):
		_regrowing.erase(id)
		events.append({"type": "zone_regrown", "zone": id})
