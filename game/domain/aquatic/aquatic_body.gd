class_name AquaticBody
extends RefCounted
## An aquatic body and its swim stats (aquatic plan sections 4 and 8, PROPOSED). The body is plain data:
##   {"length", "girth": 1..3, "tail": one of the rules' "tails" (fluke, ribbon, lunate, paddle, whip), "tail_size": 1..3,
##    "fins": 0..3, "dorsal": 0..2, "bladder": 0..3, "sense": "eyes" | "barbels" | "lure",
##    "mouth": "filter" | "jaw" | "both", "hue": 0..1}
## and every stat comes from it through the tuning in game/data/aquatic/aquatic_rules.json ("body"), so play, the
## editor's preview and the bots read one answer (Bible §12). Pure rules: no scene, UI or file access.
## Each tail reads its own row of every per-tail table (thrust, turn_speed_penalty "<tail>_per_size", tail_drag,
## tail_burst, tail_cost), so a tail is a tradeoff across pick-up, top speed, burst, turning and swim cost, never a
## plain upgrade (Bible §2: a single part must not solve every problem).
## to_description() builds the creature stage's body description for the generated skin, so the fish is drawn by
## the same skin and Blender-authored parts as the creature stage.

const KEYS: PackedStringArray = ["length", "girth", "tail", "tail_size", "fins", "dorsal", "bladder", "sense", "mouth", "hue"]
const INT_KEYS: PackedStringArray = ["length", "girth", "tail_size", "fins", "dorsal", "bladder"]
const BodyDescription := preload("res://game/domain/creature/body_description.gd")

## The two starting variants (plan section 8): the darter is built for straight-line speed, the hoverer for
## turning, holding depth and going deep. The cell lineage picks between them (from_genome), and the editor moves
## between and past them.
const DARTER := {"length": 3, "girth": 1, "tail": "fluke", "tail_size": 3, "fins": 1, "dorsal": 1, "bladder": 0,
		"sense": "eyes", "mouth": "both", "hue": 0.55}
const HOVERER := {"length": 1, "girth": 2, "tail": "ribbon", "tail_size": 1, "fins": 3, "dorsal": 1, "bladder": 2,
		"sense": "eyes", "mouth": "both", "hue": 0.55}


## The body's problems against the rules (empty when legal): a missing key, a number out of range, an unknown choice.
static func validate(body: Dictionary, rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ranges: Dictionary = rules.get("ranges", {})
	for key in KEYS:
		if not body.has(key):
			out.append("The body has no %s." % key)
	if not out.is_empty():
		return out
	for key in INT_KEYS:
		var v: Variant = body[key]
		var r: Array = ranges.get(key, [0, 0])
		if not (v is int or (v is float and v == floorf(v))) or int(v) < int(r[0]) or int(v) > int(r[1]):
			out.append("%s must be a whole number from %d to %d." % [key.capitalize(), int(r[0]), int(r[1])])
	if not String(body.tail) in rules.get("tails", []):
		out.append("Unknown tail '%s'." % body.tail)
	if not String(body.sense) in rules.get("senses", []):
		out.append("Unknown sense '%s'." % body.sense)
	if not String(body.mouth) in rules.get("mouths", []):
		out.append("Unknown mouth '%s'." % body.mouth)
	return out


## The swim stats of a legal body. Speeds m/s, accelerations m/s², turn rad/s, energy per second.
static func stats(body: Dictionary, rules: Dictionary) -> Dictionary:
	var length := int(body.length) - 1
	var girth := int(body.girth) - 1
	var tail_size := int(body.tail_size)
	var fins := int(body.fins)
	var dorsal := int(body.dorsal)
	var bladder := int(body.bladder)
	var tail := String(body.tail)
	var sense := String(body.sense)
	var m: Dictionary = rules.mass
	var mass: float = m.base + m.per_length * length + m.per_girth * girth + m.per_tail * tail_size + m.per_fin * fins
	var t: Dictionary = rules.thrust[tail]
	var thrust: float = float(t.base) + float(t.per_size) * tail_size
	var d: Dictionary = rules.drag
	var drag: float = maxf(0.2, d.base + d.per_fin * fins + d.per_dorsal * dorsal + d.per_girth * girth
			+ d.per_length * length + float(rules.get("tail_drag", {}).get(tail, 0.0)))
	var accel := thrust / mass
	var tr: Dictionary = rules.turn
	var turn: float = maxf(0.4, tr.base + tr.per_fin * fins + tr.per_dorsal * dorsal + tr.per_length * length)
	var tp: Dictionary = rules.turn_speed_penalty
	var penalty: float = float(tp[tail + "_per_size"]) * tail_size + tp.per_length * length
	var burst_share: float = float(rules.burst.thrust_share) * float(rules.get("tail_burst", {}).get(tail, 1.0))
	var tm: Dictionary = rules.trim
	var drift: Array = rules.idle_drift
	var rd: Dictionary = rules.rated_depth
	var sight_rules: Dictionary = rules.sight
	var up: Dictionary = rules.upkeep
	var top := accel / drag
	return {
		"mass": mass,
		"accel": accel,
		"drag": drag,
		"top_speed": top,
		## The thrust multiplier a burst gives this tail (the sim's burst uses it, so the editor's "Burst" is the water's).
		"burst_share": burst_share,
		"burst_speed": top * burst_share,
		"turn_rate": turn,
		"turn_penalty": penalty,
		## Radius of the tightest turn at top speed (v / yaw rate at v), the editor's "turn" reading.
		"turn_radius": top / (turn / (1.0 + top * penalty)),
		"trim": tm.base + tm.per_fin * fins + tm.per_bladder * bladder,
		"idle_drift": float(drift[clampi(bladder, 0, drift.size() - 1)]),
		"rated_depth": rd.base + rd.per_girth * girth + rd.per_bladder * bladder,
		"sight": sight_rules.base + float(sight_rules.get(sense, 0.0)),
		"dark_sense": sense in rules.get("dark_sense", []),
		"lure": sense == "lure",
		"upkeep": up.base + up.per_length * length + up.per_girth * girth + float(up.get(sense, 0.0)),
		"thrust_cost": float(rules.thrust_cost.per_tail) * tail_size * float(rules.get("tail_cost", {}).get(tail, 1.0)),
		"energy_capacity": rules.energy_capacity.base + rules.energy_capacity.per_girth * girth,
		"max_health": rules.max_health.base + rules.max_health.per_girth * girth,
		"bite": float(rules.bite.get(String(body.mouth), 0.0)),
		"eats_plants": String(body.mouth) != "jaw",
		"eats_meat": String(body.mouth) != "filter",
		"spines": dorsal >= int(rules.spines.min_dorsal),
		"bite_back": float(rules.spines.bite_back) if dorsal >= int(rules.spines.min_dorsal) else 0.0,
		"radius": 0.35 + 0.12 * girth,
		"length_m": 1.0 + 0.35 * length,
	}


## The yaw rate (rad/s) a body turns at while swimming at `speed`: fastest from still, slower as speed rises, and a
## big fluke or a long body slows it most.
static func yaw_rate(stats_of_body: Dictionary, speed: float) -> float:
	return float(stats_of_body.turn_rate) / (1.0 + maxf(0.0, speed) * float(stats_of_body.turn_penalty))


## The first aquatic body of a cell lineage (plan section 4, PROPOSED conversion; owner decision 1). `parts` are the
## genome's parts ({"type", ...}), `hue` its appearance hue. Flagella become the tail, cilia the fins, eye spots the
## eyes, shell plates a deeper body, spikes the dorsal spines; the mouths set the diet. A lineage with more cilia
## than flagella starts from the hoverer's shape, otherwise from the darter's. Returns {"body", "notes"}: notes are
## the lines the entry card shows, one per conversion, so nothing changes silently.
static func from_genome(parts: Array, hue: float, conversion: Dictionary) -> Dictionary:
	var counts := {}
	for p in parts:
		var type := String((p as Dictionary).get("type", ""))
		counts[type] = int(counts.get(type, 0)) + 1
	var flagella := int(counts.get("flagellum", 0))
	var cilia := int(counts.get("cilia", 0))
	var body: Dictionary = (HOVERER if cilia > flagella else DARTER).duplicate()
	var notes := PackedStringArray()
	if cilia > flagella:
		notes.append("More cilia than flagella: your line keeps a short, finned body that turns and hovers.")
	else:
		notes.append("Your flagella drove you fast: your line keeps a long body with a strong tail.")
	if flagella > 0:
		body.tail_size = int(_pick(conversion.flagellum_tail_size, flagella))
		notes.append("%d flagell%s became a tail of strength %d." % [flagella, "um" if flagella == 1 else "a", body.tail_size])
	if cilia > 0:
		body.fins = int(_pick(conversion.cilia_fins, cilia))
		notes.append("%d cili%s became fins of size %d." % [cilia, "um" if cilia == 1 else "a", body.fins])
	if counts.has("eye_spot"):
		body.sense = String(conversion.eye_spot_sense)
		notes.append("Your eye spots became eyes.")
	if counts.has("shell_plate"):
		body.girth = int(_pick(conversion.shell_plate_girth, int(counts.shell_plate)))
		notes.append("Your shell plates became a deeper, tougher body.")
	if counts.has("spike"):
		body.dorsal = int(_pick(conversion.spike_dorsal, int(counts.spike)))
		notes.append("Your spikes became dorsal spines that sting a biter.")
	var filter := counts.has("mouth_filter")
	var jaw := counts.has("mouth_jaw")
	body.mouth = "both" if filter and jaw else ("jaw" if jaw else "filter")
	notes.append({"both": "Both mouths: you still eat plants and meat.", "jaw": "Your jaw: you hunt meat.",
			"filter": "Your filter mouth: you graze plankton and algae."}[body.mouth])
	body.hue = clampf(hue, 0.0, 1.0)
	return {"body": body, "notes": notes}


## The points an edit from `before` to `after` costs: each step of a number by its step cost, each swap by its cost.
## The mouth and hue are inherited and cannot change in the editor (plan section 6).
static func edit_cost(before: Dictionary, after: Dictionary, editor_rules: Dictionary) -> int:
	var cost := 0
	var step: Dictionary = editor_rules.step_cost
	for key in step:
		cost += absi(int(after[key]) - int(before[key])) * int(step[key])
	var swap: Dictionary = editor_rules.swap_cost
	if String(after.tail) != String(before.tail):
		cost += int(swap.tail)
	if String(after.sense) != String(before.sense):
		cost += int(swap.sense)
	return cost


## The creature stage's body description of a fish (drawn by SpineRig with its parts): a spine of seven vertebrae
## along -Z, longer with length and fatter with girth, and its parts: the tail at the spine's end, a pair of
## pectoral fins, the dorsal fin, eyes, the sense part and the mouth. Only part types already recorded are used.
static func to_description(body: Dictionary, scale_m := 1.0) -> RefCounted:
	var desc = BodyDescription.create()
	var length := int(body.get("length", 2))
	var girth := int(body.get("girth", 1))
	desc.reference_length_mm = int(round(1000.0 * scale_m))
	var half := 260 + 70 * length
	var profile := [0.55, 0.85, 1.0, 0.95, 0.75, 0.5, 0.3]
	var r0 := 70 + 32 * girth
	for i in profile.size():
		var t := float(i) / float(profile.size() - 1)
		var z := int(round(-half + 2.0 * half * t))
		desc.add_vertebra(Vector3i(0, 0, z), maxi(18, int(round(r0 * profile[i]))))
	var tail_type := "tail_fluke" if String(body.get("tail", "fluke")) == "fluke" else "fin"
	desc.add_part(tail_type, _anchor(1000, 0, 0 if tail_type == "tail_fluke" else 0, 550 + 180 * int(body.get("tail_size", 1)), false, 0, 0 if tail_type == "tail_fluke" else 90))
	var fins := int(body.get("fins", 1))
	if fins > 0:
		desc.add_part("fin", _anchor(300, 250, 0, 380 + 200 * fins, true, -30, 0))
	var dorsal := int(body.get("dorsal", 0))
	if dorsal > 0:
		desc.add_part("fin", _anchor(420, 0, 0, 380 + 260 * dorsal, false, 0, 90))
	desc.add_part("eye_round", _anchor(110, 180, 0, 520 + 40 * girth, true, 0, 0))
	match String(body.get("sense", "eyes")):
		"barbels":
			desc.add_part("barbels", _anchor(0, 500, 30, 700, false, 0, 0))
		"lure":
			desc.add_part("lure", _anchor(80, 0, 0, 900, false, 0, 0))
	var mouth := "maw" if String(body.get("mouth", "both")) == "filter" else "jaw"
	desc.add_part(mouth, _anchor(0, 500, 0, 650 + 50 * girth, false, 0, 0))
	return desc


static func _anchor(u: int, ring: int, elev: int, scale: int, mirror: bool, turn: int, roll: int) -> Dictionary:
	return {"host": "spine", "u": u, "ring": ring, "elev": elev, "height": 0, "turn": turn, "tilt": 0, "roll": roll,
			"scale": scale, "handles": [], "mirror": mirror}


static func _pick(table: Array, count: int) -> Variant:
	return table[clampi(count - 1, 0, table.size() - 1)]
