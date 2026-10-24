class_name EcologyRegion
extends RefCounted
## Food supply for one habitat (Bible section 13). Each plankton zone has a carrying capacity and
## regrows logistically, with a small floor so an emptied zone always recovers. Niches cap how
## many creatures of a role live here, so spawning follows the habitat, not the player.
## Seeded: the same seed gives the same placements.
##
## The endless world (S1) adds and removes zones as the ground streams in and out. There a zone
## draws its spawn points from its own stream (`streams`, seeded from the world seed and its id), so
## where its plankton appears does not depend on the route that loaded it. The pool never fills
## `streams`, so every zone draws `rng` exactly as before.
##
## S3's bloom (D-104, D-128): an elder Warden's two meadows carry `bloom` {slot, offset_ticks,
## cycle_ticks}, and their regrowth runs at BLOOM_HIGH while their slot blooms and BLOOM_LOW while the
## other does (bloom_multiplier), 1.0 over a whole cycle. Every other zone regrows exactly as before.

## Extra regrowth per second, as a share of capacity times the zone's growth rate. It keeps an
## emptied zone recovering (pure logistic growth would stay at zero).
const REGROW_FLOOR := 0.05
## A bloom meadow's regrowth multiplier while its slot blooms, and while the other slot does.
const BLOOM_HIGH := 1.5
const BLOOM_LOW := 0.5

## [{"id", "center": Vector2, "radius", "capacity", "growth_rate", "amount"}], and "bloom" for a meadow
## that has one.
var zones: Array[Dictionary] = []
## role -> {"cap": int, "count": int}
var niches: Dictionary = {}
var rng := RandomNumberGenerator.new()
## zone id -> RandomNumberGenerator: the zone's own spawn-point stream (endless mode only).
var streams := {}
var _by_id := {}    ## zone id -> the zone's dictionary (the same object as in `zones`)
## The same dictionaries as `zones`, split by whether they bloom, so tick() runs the plain ones by
## today's expression and only the meadows pay for the multiplier.
var _plain: Array[Dictionary] = []
var _bloom: Array[Dictionary] = []


static func create(seed: int) -> EcologyRegion:
	var region := EcologyRegion.new()
	region.rng.seed = seed
	return region


## Returns false (and adds nothing) for a repeated id or a zone that could never hold or regrow food.
## `bloom` ({slot, offset_ticks, cycle_ticks}, S3) makes the zone a bloom meadow.
func add_zone(id: String, center: Vector2, radius: float, capacity: float, growth_rate: float, bloom := {}) -> bool:
	if not zone(id).is_empty() or not center.is_finite():
		return false
	for value in [radius, capacity, growth_rate]:
		if not (is_finite(value) and value > 0.0):
			return false
	var z := {"id": id, "center": center, "radius": radius, "capacity": capacity, "growth_rate": growth_rate, "amount": capacity}
	if not bloom.is_empty():
		z["bloom"] = bloom.duplicate()
	_add(z)
	return true


func _add(z: Dictionary) -> void:
	zones.append(z)
	_by_id[z.id] = z
	if z.has("bloom"):
		_bloom.append(z)
	else:
		_plain.append(z)


## Takes a zone out (its ground unloaded), keeping the others in order, and drops its stream. False
## for an unknown id.
func remove_zone(id: String) -> bool:
	if not _by_id.has(id):
		return false
	var z: Dictionary = _by_id[id]
	zones.erase(z)
	if z.has("bloom"):
		_bloom.erase(z)
	else:
		_plain.erase(z)
	_by_id.erase(id)
	streams.erase(id)
	return true


## Every zone out at once, with its stream (the endless growth tick): the tables go to the caller
## (zones, by id, streams), to let go of when it likes, and fresh ones take their place.
func take_all_zones() -> Array:
	var old := [zones, _by_id, streams]
	var fresh: Array[Dictionary] = []
	zones = fresh
	_by_id = {}
	streams = {}
	_plain = [] as Array[Dictionary]
	_bloom = [] as Array[Dictionary]
	return old


func zone(id: String) -> Dictionary:
	return _by_id.get(id, {})


## add_zone with the zone's dictionary `z` made ahead (the endless world's prefetch), as add_zone makes
## it but its centre, set here; `z` goes in itself (a bloom meadow when it has "bloom"). The same
## refusals (a known id, a centre not finite), which leave `z` as it was; its other values were
## checked when it was made.
func add_zone_prepared(z: Dictionary, center: Vector2) -> bool:
	if _by_id.has(z.id) or not center.is_finite():
		return false
	z.center = center
	_add(z)
	return true


## Regrows every zone by dt; a bloom meadow's regrowth by its multiplier at the sim's `tick`.
func tick(dt: float, tick: int = 0) -> void:
	for z in _plain:
		var cap: float = z.capacity
		var amount: float = z.amount
		if amount == cap:
			continue   # full: the update below would write cap again (its growth is 0 and minf keeps cap)
		var rate: float = z.growth_rate
		var logistic: float = rate * amount * (1.0 - amount / cap)
		z.amount = minf(cap, amount + (logistic + cap * REGROW_FLOOR * rate) * dt)
	for z in _bloom:
		var cap: float = z.capacity
		var amount: float = z.amount
		if amount == cap:
			continue
		var rate: float = z.growth_rate
		var logistic: float = rate * amount * (1.0 - amount / cap)
		z.amount = minf(cap, amount + (logistic + cap * REGROW_FLOOR * rate) * bloom_multiplier(z.bloom, tick) * dt)


## A bloom meadow's regrowth multiplier at `tick` (D-104): BLOOM_HIGH while floor((tick + offset) /
## (cycle / 2)) is even for slot 0, odd for slot 1, else BLOOM_LOW; 1.0 for {}. The brain's
## CreatureBrain.bloom_post is the same expression, so the Warden and its meadows agree.
static func bloom_multiplier(bloom: Dictionary, tick: int) -> float:
	if bloom.is_empty():
		return 1.0
	var half := int(bloom.cycle_ticks) / 2
	var blooming := posmod(floori(float(tick + int(bloom.offset_ticks)) / float(half)), 2)
	return BLOOM_HIGH if blooming == int(bloom.slot) else BLOOM_LOW


## Takes up to `amount` from a zone. Returns what was actually taken (never below zero).
func take(zone_id: String, amount: float) -> float:
	var z := zone(zone_id)
	if z.is_empty() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var taken := minf(amount, z.amount)
	z.amount -= taken
	return taken


## A spawn point inside the zone, deterministic for the region's seed (or the zone's own stream).
## Returns Vector2.INF for an unknown zone, without using up a random draw.
func random_point_in(zone_id: String) -> Vector2:
	var z := zone(zone_id)
	if z.is_empty():
		return Vector2.INF
	var r: RandomNumberGenerator = streams.get(zone_id, rng)
	var angle := r.randf() * TAU
	var dist := sqrt(r.randf()) * float(z.radius)
	return z.center + Vector2.from_angle(angle) * dist


func set_niche(role: String, cap: int) -> void:
	niches[role] = {"cap": cap, "count": int(niches.get(role, {}).get("count", 0))}


## Reserves a slot for a creature of this role. False when the niche is full or unknown.
func try_spawn(role: String) -> bool:
	if not niches.has(role) or niches[role].count >= niches[role].cap:
		return false
	niches[role].count += 1
	return true


func on_creature_removed(role: String) -> void:
	if niches.has(role):
		niches[role].count = maxi(0, niches[role].count - 1)
