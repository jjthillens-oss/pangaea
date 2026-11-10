extends RefCounted
## Which landform pieces a habitat is composed from, and where (PROPOSED, IB-32 authored terrain variety; Bible
## sections 15 and 16). compose() turns a world seed and the rules in game/data/creature/landform_rules.json into a
## list of placements: every kind at least once, circular footprints that do not overlap, all inside the field and
## clear of the nest. Nothing in the game uses this yet: the landform art, the scene placement and the section 15
## runtime placement boundary are not approved. Pure rules: no scene or file access; every draw comes from a
## stream seeded by the world seed, and every sort breaks ties by id.

## Mixed into the world seed so this stream differs from the other streams the same seed feeds.
const STREAM_SALT := 0x1B32
const SEED_MASK := 0x7FFFFFFFFFFFFFFF


## The problems in `rules`, empty when they can be composed from.
static func validate(rules: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["field_half_size_m", "edge_margin_m", "nest_keep_out_m", "gap_m", "max_attempts", "tries_per_piece"]:
		if not _is_number(rules.get(key)):
			errors.append("%s must be a number" % key)
		elif float(rules[key]) < 0.0:
			errors.append("%s must not be negative" % key)
	var nest: Variant = rules.get("nest_pos")
	if not (nest is Array and nest.size() == 2 and _is_number(nest[0]) and _is_number(nest[1])):
		errors.append("nest_pos must be an [x, y] pair")
	var kinds: Variant = rules.get("kinds")
	if not (kinds is Dictionary) or (kinds as Dictionary).is_empty():
		errors.append("kinds must be a dictionary with at least one landform kind")
		return errors
	if not errors.is_empty():
		return errors
	if float(rules.field_half_size_m) <= 0.0:
		errors.append("field_half_size_m must be positive")
	if int(rules.max_attempts) < 1 or int(rules.tries_per_piece) < 1:
		errors.append("max_attempts and tries_per_piece must be at least 1")
	var room := float(rules.field_half_size_m) - float(rules.edge_margin_m)
	for kind: String in _sorted_keys(kinds):
		var entry: Variant = kinds[kind]
		if not (entry is Dictionary):
			errors.append("kind %s must be a dictionary" % kind)
			continue
		if not _is_number(entry.get("radius_m")) or float(entry.radius_m) <= 0.0:
			errors.append("kind %s: radius_m must be a positive number" % kind)
		elif float(entry.radius_m) > room:
			errors.append("kind %s: radius_m does not fit inside the field" % kind)
		if not _is_number(entry.get("turn_step_deg")) or float(entry.turn_step_deg) <= 0.0 \
				or float(entry.turn_step_deg) > 360.0:
			errors.append("kind %s: turn_step_deg must be in (0, 360]" % kind)
		var count: Variant = entry.get("count")
		if not (count is Array and count.size() == 2 and _is_number(count[0]) and _is_number(count[1])):
			errors.append("kind %s: count must be a [min, max] pair" % kind)
		elif int(count[0]) < 1 or int(count[1]) < int(count[0]):
			errors.append("kind %s: count needs 1 <= min <= max" % kind)
	return errors


## The habitat's landform placements for `world_seed`, sorted by id: each is
## {id, kind, pos: [x, y], turn_deg, radius_m}, with pos on the ground plane in metres from the field's centre.
## The same seed and rules always give the same list. Empty when the rules are invalid, or when no attempt could
## place every kind's minimum (the rules leave too little room).
static func compose(world_seed: int, rules: Dictionary) -> Array:
	if not validate(rules).is_empty():
		return []
	for attempt in int(rules.max_attempts):
		var rng := RandomNumberGenerator.new()
		rng.seed = _stream_seed(world_seed, attempt)
		var placed := _attempt(rng, rules)
		if not placed.is_empty():
			placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
			return placed
	return []


## A short text that is equal for equal layouts, for comparing two seeds: each placement's id, position (to the
## centimetre) and turn, in the given order.
static func signature(placements: Array) -> String:
	var parts := PackedStringArray()
	for p: Dictionary in placements:
		parts.append("%s@%.2f,%.2f/%d" % [p.id, float(p.pos[0]), float(p.pos[1]), int(round(float(p.turn_deg)))])
	return ";".join(parts)


## The first problem with `placements` under `rules` ("" when they keep every promise compose() makes).
static func first_fault(placements: Array, rules: Dictionary) -> String:
	var room := float(rules.field_half_size_m) - float(rules.edge_margin_m)
	var nest := Vector2(float(rules.nest_pos[0]), float(rules.nest_pos[1]))
	var seen := {}
	var last_id := ""
	for i in placements.size():
		var p: Dictionary = placements[i]
		var pos := Vector2(float(p.pos[0]), float(p.pos[1]))
		var radius := float(p.radius_m)
		if i > 0 and String(p.id) <= last_id:
			return "%s is out of id order" % p.id
		last_id = String(p.id)
		seen[p.kind] = true
		if absf(pos.x) + radius > room + 0.001 or absf(pos.y) + radius > room + 0.001:
			return "%s leaves the field" % p.id
		if pos.distance_to(nest) < float(rules.nest_keep_out_m) + radius - 0.001:
			return "%s is inside the nest keep-out" % p.id
		for j in i:
			var q: Dictionary = placements[j]
			var gap := pos.distance_to(Vector2(float(q.pos[0]), float(q.pos[1]))) - radius - float(q.radius_m)
			if gap < float(rules.gap_m) - 0.001:
				return "%s overlaps %s" % [p.id, q.id]
	for kind: String in _sorted_keys(rules.kinds):
		if not seen.has(kind):
			return "kind %s is missing" % kind
	return ""


## One try at a whole layout from `rng`: [] when a kind's minimum could not be placed. Optional pieces (those
## past a kind's minimum) that find no room are left out.
static func _attempt(rng: RandomNumberGenerator, rules: Dictionary) -> Array:
	var kinds: Dictionary = rules.kinds
	var wanted := []
	for kind: String in _sorted_keys(kinds):
		var entry: Dictionary = kinds[kind]
		var count := rng.randi_range(int(entry.count[0]), int(entry.count[1]))
		for n in count:
			wanted.append({"id": "%s_%d" % [kind, n + 1], "kind": kind, "radius_m": float(entry.radius_m),
				"needed": n < int(entry.count[0])})
	# The largest footprints go down first, while there is room; ties by id.
	wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.radius_m != b.radius_m:
			return a.radius_m > b.radius_m
		return String(a.id) < String(b.id))
	var room := float(rules.field_half_size_m) - float(rules.edge_margin_m)
	var nest := Vector2(float(rules.nest_pos[0]), float(rules.nest_pos[1]))
	var keep_out := float(rules.nest_keep_out_m)
	var gap := float(rules.gap_m)
	var placed := []
	for want: Dictionary in wanted:
		var radius: float = want.radius_m
		var step := float(kinds[want.kind].turn_step_deg)
		var found := false
		for _try in int(rules.tries_per_piece):
			var pos := Vector2(rng.randf_range(-room + radius, room - radius), rng.randf_range(-room + radius, room - radius))
			var turn := fmod(step * rng.randi_range(0, maxi(0, int(ceil(360.0 / step)) - 1)), 360.0)
			if pos.distance_to(nest) < keep_out + radius:
				continue
			var clear := true
			for p: Dictionary in placed:
				if pos.distance_to(Vector2(p.pos[0], p.pos[1])) < radius + float(p.radius_m) + gap:
					clear = false
					break
			if not clear:
				continue
			placed.append({"id": want.id, "kind": want.kind, "pos": [pos.x, pos.y], "turn_deg": turn, "radius_m": radius})
			found = true
			break
		if not found and want.needed:
			return []
	return placed


static func _stream_seed(world_seed: int, attempt: int) -> int:
	var h := (world_seed ^ STREAM_SALT) & SEED_MASK
	h = (h * 6364136223846793005 + 1442695040888963407 + attempt * 7919) & SEED_MASK
	return h ^ (h >> 29)


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


static func _is_number(v: Variant) -> bool:
	return v is int or v is float
