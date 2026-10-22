class_name EcologyRegion
extends RefCounted
## Food supply for one habitat (Bible section 13). Each plankton zone has a carrying capacity and
## regrows logistically, with a small floor so an emptied zone always recovers. Niches cap how
## many creatures of a role live here, so spawning follows the habitat, not the player.
## Seeded: the same seed gives the same placements.

## Extra regrowth per second, as a share of capacity times the zone's growth rate. It keeps an
## emptied zone recovering (pure logistic growth would stay at zero).
const REGROW_FLOOR := 0.05

## [{"id", "center": Vector2, "radius", "capacity", "growth_rate", "amount"}]
var zones: Array[Dictionary] = []
## role -> {"cap": int, "count": int}
var niches: Dictionary = {}
var rng := RandomNumberGenerator.new()


static func create(seed: int) -> EcologyRegion:
	var region := EcologyRegion.new()
	region.rng.seed = seed
	return region


## Returns false (and adds nothing) for a repeated id or a zone that could never hold or regrow food.
func add_zone(id: String, center: Vector2, radius: float, capacity: float, growth_rate: float) -> bool:
	if not zone(id).is_empty() or not (radius > 0.0 and capacity > 0.0 and growth_rate > 0.0):
		return false
	zones.append({"id": id, "center": center, "radius": radius, "capacity": capacity, "growth_rate": growth_rate, "amount": capacity})
	return true


func zone(id: String) -> Dictionary:
	for z in zones:
		if z.id == id:
			return z
	return {}


func tick(dt: float) -> void:
	for z in zones:
		var cap: float = z.capacity
		var logistic: float = z.growth_rate * z.amount * (1.0 - z.amount / cap)
		z.amount = minf(cap, z.amount + (logistic + cap * REGROW_FLOOR * z.growth_rate) * dt)


## Takes up to `amount` from a zone. Returns what was actually taken (never below zero).
func take(zone_id: String, amount: float) -> float:
	var z := zone(zone_id)
	if z.is_empty() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var taken := minf(amount, z.amount)
	z.amount -= taken
	return taken


## A spawn point inside the zone, deterministic for the region's seed.
## Returns Vector2.INF for an unknown zone, without using up a random draw.
func random_point_in(zone_id: String) -> Vector2:
	var z := zone(zone_id)
	if z.is_empty():
		return Vector2.INF
	var angle := rng.randf() * TAU
	var dist := sqrt(rng.randf()) * float(z.radius)
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
