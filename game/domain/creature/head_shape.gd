extends RefCounted
## Head shape (PROPOSED; IMPLEMENTED in the editor): five dials on the head end of the spine, stored as a small block
## in the body's extra dictionary under "head_shape" ({snout, width, height, jaw, brow}, per mille, written as
## whole-number floats like the look keys, since JSON reads every number back as one). The codec keeps the block as
## an unknown key, so the save schema does not change, and a body without it has the plain round head.
##
## The dials do not move vertebrae: BodyField adds a few capsules around vertebra 0 (the head end) and scales the
## first spine capsule's head radius, so the skin, the anchors (which march to the skin on the field), picking and
## the bounds all follow. Width and height (600..1600) stretch the head sideways or upwards with a bar capsule across
## it; snout (1000..2000) pushes a tapering capsule forward along the head direction; jaw (0..1000) hangs a capsule
## under the head and along the snout; brow (0..1000) lays a ridge across the forehead. The ranges are in
## data/creature/body_rules.json ("head_shape").
## Pure rules: no scene or file access.

const KEY := "head_shape"
const FIELDS: Array[String] = ["snout", "width", "height", "jaw", "brow"]
const DEFAULTS := {"snout": 1000, "width": 1000, "height": 1000, "jaw": 0, "brow": 0}
## Used when body_rules has no "head_shape" table (tests that build rules by hand).
const DEFAULT_RANGES := {"snout": [1000, 2000], "width": [600, 1600], "height": [600, 1600], "jaw": [0, 1000],
		"brow": [0, 1000]}

## Shape tuning, in head radii (the first vertebra's radius times the core scale).
## The snout reaches SNOUT_REACH x (snout - 1) forward from the head centre; its radius tapers from SNOUT_BASE to SNOUT_TIP.
const SNOUT_REACH := 1.6
const SNOUT_BASE := 0.8
const SNOUT_TIP := 0.55
const SNOUT_DROP := 0.12   ## the tip sits this far (per unit of reach) below the head axis
## The jaw hangs JAW_DROP + JAW_DROP_DEPTH x jaw below the centre, with radius JAW_R + JAW_R_DEPTH x jaw.
const JAW_DROP := 0.35
const JAW_DROP_DEPTH := 0.35
const JAW_R := 0.45
const JAW_R_DEPTH := 0.2
## The brow sits forward and up of the centre, pushed out by BROW_OUT x brow, with radius BROW_R + BROW_R_DEPTH x brow.
const BROW_AT := 0.8
const BROW_OUT := 0.35
const BROW_R := 0.25
const BROW_R_DEPTH := 0.15
## The ridge spans this much of the head's half width on each side.
const BROW_SPAN := 0.55


## The five dials as ints: the stored value where it is a whole number, DEFAULTS where missing or not one.
static func of(extra: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var block: Variant = extra.get(KEY)
	if not block is Dictionary:
		return out
	for key in FIELDS:
		var v: Variant = (block as Dictionary).get(key)
		if v is int or (v is float and is_finite(v) and v == floorf(v)):
			out[key] = int(v)
	return out


## `shape` (any of the five keys) written as a fresh block into `extra`, as whole-number floats. A neutral shape
## removes the block, so an untouched body encodes as before.
static func store(extra: Dictionary, shape: Dictionary) -> void:
	var full := of({KEY: shape})
	if is_neutral(full):
		extra.erase(KEY)
		return
	var block := {}
	for key in FIELDS:
		block[key] = float(full[key])
	extra[KEY] = block


static func is_neutral(shape: Dictionary) -> bool:
	for key in FIELDS:
		if int(shape.get(key, DEFAULTS[key])) != int(DEFAULTS[key]):
			return false
	return true


## key -> [min, max] per mille, from body_rules' "head_shape" table or DEFAULT_RANGES.
static func ranges(rules: Dictionary) -> Dictionary:
	var out := DEFAULT_RANGES.duplicate(true)
	var table: Variant = rules.get(KEY)
	if table is Dictionary:
		for key in FIELDS:
			var r: Variant = (table as Dictionary).get(key)
			if r is Array and (r as Array).size() == 2:
				out[key] = [int(r[0]), int(r[1])]
	return out


## Problems with the stored block, as readable reasons (empty when valid or absent).
static func validate(extra: Dictionary, rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not extra.has(KEY):
		return out
	var block: Variant = extra[KEY]
	if not block is Dictionary:
		out.append("head_shape is not an object")
		return out
	var lim := ranges(rules)
	for key in (block as Dictionary):
		if not FIELDS.has(String(key)):
			out.append("head_shape has an unknown dial %s" % String(key))
	for key in FIELDS:
		var v: Variant = (block as Dictionary).get(key, DEFAULTS[key])
		if not (v is int or (v is float and is_finite(v) and v == floorf(v))):
			out.append("head %s is not a whole number" % key)
			continue
		if int(v) < int(lim[key][0]) or int(v) > int(lim[key][1]):
			out.append("head %s %d is outside %d..%d" % [key, int(v), int(lim[key][0]), int(lim[key][1])])
	return out


## The head's geometry for `desc` (body space, metres): {core: scale for the first spine capsule's head radius,
## capsules: [[a, b, ra, rb], ...]} to add around vertebra 0. A neutral or missing shape, or a spine shorter than two
## vertebrae, gives {core: 1.0, capsules: []}. Values outside the ranges are clamped to DEFAULT_RANGES here (the
## editor refuses them; a hand-edited save still draws).
static func geometry(desc: RefCounted) -> Dictionary:
	var shape := of(desc.extra)
	if desc.vertebrae.size() < 2 or is_neutral(shape):
		return {"core": 1.0, "capsules": []}
	var w := _dial(shape, "width")
	var h := _dial(shape, "height")
	var s := _dial(shape, "snout")
	var jaw := _dial(shape, "jaw")
	var brow := _dial(shape, "brow")
	var c: Vector3 = desc.position_m(0)
	var r0: float = desc.radius_m(0)
	var f: Vector3 = (c - desc.position_m(1)).normalized()
	if f.length_squared() == 0.0:
		f = Vector3.FORWARD
	var ref := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var up := (ref - f * ref.dot(f)).normalized()
	var right := f.cross(up).normalized()
	var core := minf(w, h)
	var rc := core * r0
	var caps := []
	# Width and height: a bar across the head along the longer axis, as thick as the shorter.
	if w > h:
		var half := (w - h) * r0
		caps.append([c - right * half, c + right * half, rc, rc])
	elif h > w:
		var half := (h - w) * r0
		caps.append([c - up * (0.5 * half), c + up * (1.5 * half), rc, rc])
	var reach := SNOUT_REACH * (s - 1.0) * rc
	if reach > 0.0:
		var tip := c + f * reach - up * (SNOUT_DROP * reach)
		caps.append([c, tip, SNOUT_BASE * rc, SNOUT_TIP * rc])
	if jaw > 0.0:
		var drop := (JAW_DROP + JAW_DROP_DEPTH * jaw) * rc
		var jr := (JAW_R + JAW_R_DEPTH * jaw) * rc
		var front := c + f * (0.45 * rc + 0.8 * reach) - up * (drop * 0.75 + SNOUT_DROP * reach)
		caps.append([c - up * drop - f * (0.2 * rc), front, jr, jr * 0.85])
	if brow > 0.0:
		var at := c + (f + up).normalized() * ((BROW_AT + BROW_OUT * brow) * 0.7 * rc)
		var span := BROW_SPAN * w * r0
		var br := (BROW_R + BROW_R_DEPTH * brow) * rc
		caps.append([at - right * span, at + right * span, br, br])
	return {"core": core, "capsules": caps}


static func _dial(shape: Dictionary, key: String) -> float:
	var lim: Array = DEFAULT_RANGES[key]
	return clampf(float(shape[key]), float(lim[0]), float(lim[1])) / 1000.0
