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

## Extra regrowth per second, as a share of capacity times the zone's growth rate. It keeps an
## emptied zone recovering (pure logistic growth would stay at zero).
const REGROW_FLOOR := 0.05

## [{"id", "center": Vector2, "radius", "capacity", "growth_rate", "amount"}]
var zones: Array[Dictionary] = []
## role -> {"cap": int, "count": int}
var niches: Dictionary = {}
var rng := RandomNumberGenerator.new()
## zone id -> RandomNumberGenerator: the zone's own spawn-point stream (endless mode only).
var streams := {}
var _by_id := {}    ## zone id -> the zone's dictionary (the same object as in `zones`)


static func create(seed: int) -> EcologyRegion:
	var region := EcologyRegion.new()
	region.rng.seed = seed
	return region


## Returns false (and adds nothing) for a repeated id or a zone that could never hold or regrow food.
func add_zone(id: String, center: Vector2, radius: float, capacity: float, growth_rate: float) -> bool:
	if not zone(id).is_empty() or not center.is_finite():
		return false
	for value in [radius, capacity, growth_rate]:
		if not (is_finite(value) and value > 0.0):
			return false
	var z := {"id": id, "center": center, "radius": radius, "capacity": capacity, "growth_rate": growth_rate, "amount": capacity}
	zones.append(z)
	_by_id[id] = z
	return true


## Takes a zone out (its ground unloaded), keeping the others in order, and drops its stream. False
## for an unknown id.
func remove_zone(id: String) -> bool:
	if not _by_id.has(id):
		return false
	zones.erase(_by_id[id])
	_by_id.erase(id)
	streams.erase(id)
	return true


func zone(id: String) -> Dictionary:
	return _by_id.get(id, {})


func tick(dt: float) -> void:
	for z in zones:
		var cap: float = z.capacity
		var amount: float = z.amount
		if amount == cap:
			continue   # full: the update below would write cap again (its growth is 0 and minf keeps cap)
		var rate: float = z.growth_rate
		var logistic: float = rate * amount * (1.0 - amount / cap)
		z.amount = minf(cap, amount + (logistic + cap * REGROW_FLOOR * rate) * dt)


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
