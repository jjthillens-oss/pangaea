class_name PoolLayout
extends RefCounted
## The pool's layout and food tuning (game/data/pool_m1.json, M1 step 2): walls, spawn, plankton
## zones, rocks, carrion and camera settings. Plain data plus checks of the data itself.
## Asset records are checked by tests only, because they are not exported with the game.
## Builds the PoolArena and EcologyRegion the simulation runs on.

const DEFAULT_PATH := "res://game/data/pool_m1.json"
const SCHEMA_VERSION := 1
const CELL_RADIUS := 0.5       ## clearance the spawn needs; the radius of every M1 body
## The part catalog's speed cap. A rock thinner than two ticks at this speed could be skipped.
const MAX_SPEED := 6.0
const ZONE_WALL_MARGIN := 1.0  ## zones keep this far inside the soft wall
const CAMERA_KEYS: PackedStringArray = ["pitch_deg", "fov_deg", "distance", "zoom_min", "zoom_max",
	"zoom_step", "follow_half_life_s", "look_ahead_s", "look_ahead_max"]

## Problems found while reading (not saved). validate() reports them.
var load_problems: Array = []
var schema_version := 0
var status := ""
var pool_radius := 0.0
var soft_start := 0.0
var hard_radius := 0.0
var return_speed := PoolArena.RETURN_SPEED
var spawn := Vector2.ZERO
var spawn_heading := 0.0
## {"unit_energy", "points": int, "item_radius", "max_items_per_zone": int, "drift_amplitude",
##  "drift_period_s": Vector2(shortest, longest)}
var plankton := {}
## [{"id", "center": Vector2, "radius", "capacity", "growth_rate"}]
var zones: Array[Dictionary] = []
## {"energy", "points": int, "item_radius", "lifetime_s", "initial": Array[Vector2],
##  "interim_supply": {"enabled": bool, "interim": bool, "interval_s", "jitter_s", "max_live": int, "placement"}}
var carrion := {}
## [{"id", "asset", "center": Vector2, "yaw_deg", "scale", "radius"}]; radius = footprint x scale.
var rocks: Array[Dictionary] = []
var rock_footprint_radius_m := 1.0
## Floats keyed by CAMERA_KEYS.
var camera := {}
## {"starving_food_arrow": bool}
var assists := {}


## Never null: a missing or unreadable file gives a layout whose validate() says why.
static func load_from(path: String = DEFAULT_PATH) -> PoolLayout:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK:
		var broken := PoolLayout.new()
		broken.load_problems.append("%s: missing or not readable JSON." % path.get_file())
		return broken
	return from_dict(json.data)


static func from_dict(data: Variant) -> PoolLayout:
	var layout := PoolLayout.new()
	var problems := layout.load_problems
	if not data is Dictionary:
		problems.append("Layout is not an object.")
		return layout
	layout.schema_version = int(_number(data, "schema_version", "layout", problems))
	layout.status = str(data.get("status", ""))
	var pool := _section(data, "pool", problems)
	layout.pool_radius = _number(pool, "radius", "pool", problems)
	layout.soft_start = _number(pool, "soft_start", "pool", problems)
	layout.hard_radius = _number(pool, "hard_radius", "pool", problems)
	layout.return_speed = _number(pool, "return_speed", "pool", problems)
	var spawn_data := _section(data, "spawn", problems)
	layout.spawn = _point(spawn_data.get("position"), "spawn position", problems)
	layout.spawn_heading = _number(spawn_data, "heading", "spawn", problems)

	var pk := _section(data, "plankton", problems)
	var periods = pk.get("drift_period_s")
	layout.plankton = {
		"unit_energy": _number(pk, "unit_energy", "plankton", problems),
		"points": int(_number(pk, "points", "plankton", problems)),
		"item_radius": _number(pk, "item_radius", "plankton", problems),
		"max_items_per_zone": int(_number(pk, "max_items_per_zone", "plankton", problems)),
		"drift_amplitude": _number(pk, "drift_amplitude", "plankton", problems),
		"drift_period_s": _point(periods, "plankton drift_period_s", problems),
	}

	for raw in _list(data, "zones", problems):
		var z: Dictionary = raw if raw is Dictionary else {}
		var where := "zone '%s'" % str(z.get("id", "?"))
		layout.zones.append({
			"id": str(z.get("id", "")),
			"center": _point(z.get("center"), where + " center", problems),
			"radius": _number(z, "radius", where, problems),
			"capacity": _number(z, "capacity", where, problems),
			"growth_rate": _number(z, "growth_rate", where, problems),
		})

	var cr := _section(data, "carrion", problems)
	var initial: Array[Vector2] = []
	for raw in _list(cr, "initial", problems):
		initial.append(_point(raw, "initial carrion", problems))
	var supply := _section(cr, "interim_supply", problems)
	layout.carrion = {
		"energy": _number(cr, "energy", "carrion", problems),
		"points": int(_number(cr, "points", "carrion", problems)),
		"item_radius": _number(cr, "item_radius", "carrion", problems),
		"lifetime_s": _number(cr, "lifetime_s", "carrion", problems),
		"initial": initial,
		"interim_supply": {
			"enabled": _flag(supply, "enabled", "interim_supply", problems),
			"interim": _flag(supply, "interim", "interim_supply", problems),
			"interval_s": _number(supply, "interval_s", "interim_supply", problems),
			"jitter_s": _number(supply, "jitter_s", "interim_supply", problems),
			"max_live": int(_number(supply, "max_live", "interim_supply", problems)),
			"placement": str(supply.get("placement", "")),
		},
	}

	layout.rock_footprint_radius_m = _number(data, "rock_footprint_radius_m", "layout", problems)
	for raw in _list(data, "rocks", problems):
		var r: Dictionary = raw if raw is Dictionary else {}
		var where := "rock '%s'" % str(r.get("id", "?"))
		var scale := _number(r, "scale", where, problems)
		layout.rocks.append({
			"id": str(r.get("id", "")),
			"asset": str(r.get("asset", "")),
			"center": _point(r.get("center"), where + " center", problems),
			"yaw_deg": _number(r, "yaw_deg", where, problems),
			"scale": scale,
			"radius": layout.rock_footprint_radius_m * scale,
		})

	var cam := _section(data, "camera", problems)
	for key in CAMERA_KEYS:
		layout.camera[key] = _number(cam, key, "camera", problems)
	var assist_data := _section(data, "assists", problems)
	layout.assists = {"starving_food_arrow": _flag(assist_data, "starving_food_arrow", "assists", problems)}
	return layout


## Problems with the data itself; empty when the layout is usable. `max_speed` is the fastest a
## body can swim (the catalog's cap).
func validate(max_speed: float = MAX_SPEED) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	if schema_version != SCHEMA_VERSION:
		errors.append("Layout schema %d is not the supported %d." % [schema_version, SCHEMA_VERSION])
	if not (pool_radius > 0.0 and soft_start > 0.0 and soft_start < hard_radius and hard_radius <= pool_radius):
		errors.append("Pool needs 0 < soft_start < hard_radius <= radius.")
		return errors
	if return_speed < 0.0:
		errors.append("Pool return_speed must not be negative.")

	var unit: float = plankton.unit_energy
	if not (unit > 0.0 and plankton.item_radius > 0.0 and plankton.max_items_per_zone >= 1 and plankton.points >= 0):
		errors.append("Plankton needs a positive unit_energy, item_radius and max_items_per_zone.")
	var periods: Vector2 = plankton.drift_period_s
	if plankton.drift_amplitude < 0.0 or not (periods.x > 0.0 and periods.x <= periods.y):
		errors.append("Plankton drift needs amplitude >= 0 and periods 0 < shortest <= longest.")
	for kind in [plankton, carrion]:
		if kind.item_radius > PoolSim.MAX_FOOD_RADIUS:
			errors.append("Food item radius %.2f is above PoolSim.MAX_FOOD_RADIUS %.2f."
				% [kind.item_radius, PoolSim.MAX_FOOD_RADIUS])

	var ids := {}
	if zones.is_empty():
		errors.append("The pool needs at least one plankton zone.")
	for z in zones:
		if not _new_id(z.id, ids):
			errors.append("Zone id '%s' is missing or repeated." % z.id)
		if not (z.radius > 0.0 and z.capacity > 0.0 and z.growth_rate > 0.0):
			errors.append("Zone '%s' needs a positive radius, capacity and growth rate." % z.id)
		elif z.center.length() + z.radius > soft_start - ZONE_WALL_MARGIN:
			errors.append("Zone '%s' reaches within %.1f m of the soft wall." % [z.id, ZONE_WALL_MARGIN])
	var tunnel_limit := 2.0 * max_speed * PoolSim.DT
	for r in rocks:
		if not _new_id(r.id, ids):
			errors.append("Rock id '%s' is missing or repeated." % r.id)
		if r.asset.is_empty():
			errors.append("Rock '%s' names no asset." % r.id)
		if not (r.radius > tunnel_limit):
			errors.append("Rock '%s' radius %.2f m is not above %.2f m (two ticks at top speed)."
				% [r.id, r.radius, tunnel_limit])
		if r.center.length() + r.radius > pool_radius:
			errors.append("Rock '%s' is not inside the pool." % r.id)

	if not (carrion.energy > 0.0 and carrion.item_radius > 0.0 and carrion.lifetime_s > 0.0 and carrion.points >= 0):
		errors.append("Carrion needs a positive energy, item_radius and lifetime.")
	var supply: Dictionary = carrion.interim_supply
	if not (supply.interval_s > 0.0 and supply.jitter_s >= 0.0 and supply.jitter_s < supply.interval_s and supply.max_live >= 0):
		errors.append("Interim carrion needs interval_s > jitter_s >= 0 and max_live >= 0.")
	if supply.placement != "in_zone":
		errors.append("Interim carrion placement '%s' is not supported (only 'in_zone')." % supply.placement)

	var arena := build_arena()
	if not is_finite(spawn_heading) or not arena.is_clear(spawn, CELL_RADIUS):
		errors.append("Spawn %s is not a clear place inside the soft wall." % spawn)
	for p in carrion.initial:
		if not arena.is_clear(p, carrion.item_radius):
			errors.append("Initial carrion at %s is not clear." % p)
	for key in CAMERA_KEYS:
		if not (camera[key] > 0.0):
			errors.append("Camera '%s' must be positive." % key)
	if not (camera.zoom_min <= camera.distance and camera.distance <= camera.zoom_max):
		errors.append("Camera distance must lie between zoom_min and zoom_max.")
	return errors


func build_arena() -> PoolArena:
	var arena := PoolArena.create(pool_radius, soft_start, hard_radius, return_speed)
	for r in rocks:
		arena.add_rock(r.id, r.center, r.radius)
	return arena


func build_region(seed_value: int) -> EcologyRegion:
	var region := EcologyRegion.create(seed_value)
	for z in zones:
		region.add_zone(z.id, z.center, z.radius, z.capacity, z.growth_rate)
	return region


func zone(id: String) -> Dictionary:
	for z in zones:
		if z.id == id:
			return z
	return {}


## False for an empty id or one already in `seen`; records it either way.
static func _new_id(id: String, seen: Dictionary) -> bool:
	var fresh := not id.is_empty() and not seen.has(id)
	seen[id] = true
	return fresh


static func _section(data: Dictionary, key: String, problems: Array) -> Dictionary:
	var value = data.get(key)
	if value is Dictionary:
		return value
	problems.append("'%s' must be an object." % key)
	return {}


static func _list(data: Dictionary, key: String, problems: Array) -> Array:
	var value = data.get(key)
	if value is Array:
		return value
	problems.append("'%s' must be a list." % key)
	return []


static func _number(data: Dictionary, key: String, where: String, problems: Array) -> float:
	var value = data.get(key)
	if (value is float or value is int) and is_finite(value):
		return float(value)
	problems.append("%s: '%s' must be a number." % [where, key])
	return 0.0


static func _flag(data: Dictionary, key: String, where: String, problems: Array) -> bool:
	var value = data.get(key)
	if value is bool:
		return value
	problems.append("%s: '%s' must be true or false." % [where, key])
	return false


## [x, y] as a Vector2.
static func _point(value: Variant, where: String, problems: Array) -> Vector2:
	if value is Array and value.size() == 2:
		var ok := true
		for v in value:
			ok = ok and (v is float or v is int) and is_finite(v)
		if ok:
			return Vector2(float(value[0]), float(value[1]))
	problems.append("%s must be two numbers." % where)
	return Vector2.ZERO
