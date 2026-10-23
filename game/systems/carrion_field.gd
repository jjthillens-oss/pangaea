class_name CarrionField
extends RefCounted
## Carrion: meat that lies still on the pool floor until it is eaten or rots away (M1 step 2).
## spawn() is the only way carrion enters the world; step 3 kills will call it with the victim's
## position and energy.
##
## Until then an interim supply (marked `interim` in the data) drops carrion at clear points inside
## plankton zones every interval_s +/- jitter_s, while fewer than max_live items exist. It uses its
## own seeded RNG, never the region's, and takes no player input of any kind.

const SPAWN_TRIES := 8
const AGE_EPSILON := 1e-6

var energy := 24.0
var points := 3
var item_radius := 0.3
var lifetime := 90.0
var initial: Array[Vector2] = []
## {"enabled", "interim", "interval_s", "jitter_s", "max_live", "placement"}
var supply := {}
## Insertion-ordered: [{"id", "kind": "meat", "position", "radius", "energy", "points", "age",
## "lifetime", "source"}]
var items: Array[Dictionary] = []
var next_number := 1
## Sim time of the next interim arrival; INF while the supply is off.
var next_supply_at := INF
var rng := RandomNumberGenerator.new()
## carrion_spawned / carrion_expired events since PoolSim last took them.
var events: Array[Dictionary] = []


## config: the layout's "carrion" block. `seed_value` seeds the supply's own RNG.
static func create(config: Dictionary, seed_value: int) -> CarrionField:
	var field := CarrionField.new()
	field.energy = config.energy
	field.points = config.points
	field.item_radius = config.item_radius
	field.lifetime = config.lifetime_s
	field.initial = config.initial.duplicate()
	field.supply = config.interim_supply.duplicate()
	field.rng.seed = seed_value
	if field.supply.enabled:
		field.next_supply_at = field._next_interval()
	return field


## Places the layout's fixed starting carrion.
func place_initial(arena: PoolArena) -> void:
	for p in initial:
		if arena.is_clear(p, item_radius):
			spawn(p, "initial")


## Adds a carrion item. Energy defaults to the data's value; points default to the data's rate
## (points per energy), so a smaller carcass is worth fewer points. Returns the item, or {} when
## the position or energy is not usable.
func spawn(position: Vector2, source: String, p_energy: float = NAN, p_points: int = -1) -> Dictionary:
	var e := energy if is_nan(p_energy) else p_energy
	if not position.is_finite() or not is_finite(e) or e <= 0.0:
		return {}
	var pts := p_points if p_points >= 0 else floori(e / energy * points + 1e-6)
	var item := {
		"id": "cr_%d" % next_number,
		"kind": "meat",
		"position": position,
		"radius": item_radius,
		"energy": e,
		"points": pts,
		"age": 0.0,
		"lifetime": lifetime,
		"source": source,
	}
	next_number += 1
	items.append(item)
	events.append({"type": "carrion_spawned", "source": source, "food_id": item.id, "position": position})
	return item


## Ages and expires items, then runs the interim supply. `now` is sim time.
func tick(dt: float, now: float, region: EcologyRegion, arena: PoolArena) -> void:
	var kept: Array[Dictionary] = []
	for item in items:
		item.age += dt
		if item.age >= item.lifetime - AGE_EPSILON:
			events.append({"type": "carrion_expired", "food_id": item.id, "position": item.position})
		else:
			kept.append(item)
	items = kept
	if supply.enabled and now >= next_supply_at:
		if items.size() < supply.max_live:
			var p := _supply_point(region, arena)
			if p.is_finite():
				spawn(p, "interim")
		next_supply_at = now + _next_interval()


## Items whose centers lie within `reach` of `p`, in insertion order.
func items_near(p: Vector2, reach: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reach_sq := reach * reach
	for item in items:
		if p.distance_squared_to(item.position) <= reach_sq:
			out.append(item)
	return out


func consume(id: String) -> bool:
	for i in items.size():
		if items[i].id == id:
			items.remove_at(i)
			return true
	return false


## Endless mode: drops every item farther than `r` from `p`, for good and without events (it is
## out of view: WorldStream's food ring lies beyond the camera's reach). Returns how many went.
func drop_beyond(p: Vector2, r: float) -> int:
	var before := items.size()
	var r_sq := r * r
	items = items.filter(func(item: Dictionary) -> bool: return p.distance_squared_to(item.position) <= r_sq)
	return before - items.size()


## Endless mode: drops every item without events (a far respawn, behind the camera cut). Returns
## how many went.
func drop_all() -> int:
	var before := items.size()
	items.clear()
	return before


func _next_interval() -> float:
	return float(supply.interval_s) + rng.randf_range(-float(supply.jitter_s), float(supply.jitter_s))


## A clear point inside a zone chosen by capacity, from this field's RNG only. Vector2.INF when
## every try is blocked.
func _supply_point(region: EcologyRegion, arena: PoolArena) -> Vector2:
	var total := 0.0
	for z in region.zones:
		total += float(z.capacity)
	if region.zones.is_empty() or total <= 0.0:
		return Vector2.INF
	var pick := rng.randf() * total
	var zone: Dictionary = region.zones[-1]
	for z in region.zones:
		pick -= float(z.capacity)
		if pick < 0.0:
			zone = z
			break
	for i in SPAWN_TRIES:
		var p: Vector2 = zone.center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(zone.radius)
		if arena.is_clear(p, item_radius):
			return p
	return Vector2.INF
