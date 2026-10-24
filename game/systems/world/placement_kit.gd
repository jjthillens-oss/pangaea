class_name PlacementKit
extends RefCounted
## The kit of Blender pieces the endless world places (game/data/placement_kit.json, S1;
## docs/s1/s1-interfaces.md section 4.4): shells by footprint class, landmarks by group, rare set
## pieces by kind, and the two markers. Plain data plus checks of the data itself.
##
## Tile data holds only a shell slot's radius; the kit says which pieces may fill it (D-6): every
## pickable shell whose scale range covers the slot radius over its footprint radius. A piece is
## drawn at scale slot_r / footprint_radius_m, so the collision circle never changes with the look.
##
## Asset records are not exported with the game (as PoolLayout notes), so where the records
## directory is absent (an export) the record halves of rules 9 and 10 are left to the tests.
##
## S3 (docs/s3/s3-interfaces.md 5.2 and 6.2, s3-build-plan.md 7.3): band-1 pieces. A piece's band is
## 0 to MAX_KIT_BAND (markers -1), landmark.groups gives each band's models per group
## {"0": [2, 2, 1, 1], "1": [...]}, and rules 5, 6 and 11 hold within each band. The file is written
## by tools/kit/write_kit.py from the asset records.

const DEFAULT_PATH := "res://game/data/placement_kit.json"
const FILE_NAME := "placement_kit"
const RECORDS_DIR := "res://assets/records"
const TOP_KEYS: PackedStringArray = ["schema_version", "status", "note", "footprint_classes", "landmark", "assets"]
const LANDMARK_KEYS: PackedStringArray = ["anchor_radius_bu", "collide_radius_bu", "groups"]
const KINDS: PackedStringArray = ["shell", "landmark", "rare", "marker"]
const COMMON_KEYS: PackedStringArray = ["id", "kind", "band", "glb", "record", "scale", "yaw_rule", "dressings",
	"placeholder", "approved"]
## The keys each kind adds to COMMON_KEYS.
const KIND_KEYS := {
	"shell": ["footprint_class", "footprint_radius_m", "pickable"],
	"landmark": ["group", "footprint_radius_m"],
	"rare": ["rare_kind", "colliders"],
	"marker": [],
}
const DRESSING_KEYS: PackedStringArray = ["id", "tint", "growth", "scale"]
const COLLIDER_KEYS: PackedStringArray = ["center", "radius"]
## Rule 2: the classes the S1 tiles are authored against, in bu at the band's first size. Each is
## [lo, hi), the last [lo, hi]; a radius on an inner boundary belongs to the upper class.
const CLASSES := {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]}
const YAW_RULES := {"shell": ["free", "slot"], "landmark": ["free", "steps_90"], "rare": ["fixed"], "marker": ["fixed"]}
const MARKERS: PackedStringArray = ["marker_checkpoint_column", "marker_origin_arrow"]
## Rule 12: the M1 rocks, placed only by the home block's fixed M1 rocks.
const M1_ROCKS: PackedStringArray = ["rock_a", "rock_b", "rock_c"]
const M1_ROCK_SCALE := [0.8, 1.5]
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const MAX_SCALE_SPAN := 2.0     ## hi / lo
const LANDMARK_SCALE := [0.9, 1.1]
const LANDMARK_DRESSINGS := 3
const GROUPS := 4
const MAX_KIT_BAND := 1
const MIN_PICKABLE_PER_CLASS := 2
const MIN_COLLIDER_R := 0.6
## A scale ratio within this of a range's end counts as inside it: data written on a class edge (the
## spine's own example, 0.6 / 0.75 = 0.7999999999999999 against 0.8) covers that edge. Float64
## arithmetic is the same everywhere, so the answer never differs between machines.
const FIT_EPSILON := 1e-9
const ID_PATTERN := "^[a-z][a-z0-9_]{2,40}$"
const TINT_PATTERN := "^#[0-9A-F]{6}$"
const GROWTH_PATTERN := "^Growth_[A-Za-z]+$"
const PLACEHOLDER_STATE := "blockout"

## Problems found while reading (unknown or missing keys, wrong kinds). validate() reports them first.
var load_problems := PackedStringArray()
## "fp_s" -> [lo, hi] bu (half-open; the last closed)
var classes := {}
var anchor_radius_bu := 3.0
var collide_radius_bu := 2.0
## Models per landmark group, [2, 2, 1, 1] for band 0 (landmark_groups_by_band[0]).
var landmark_groups: Array[int] = []
## {int band -> Array[int]}: each band's models per landmark group, from landmark.groups.
var landmark_groups_by_band := {}
## id -> record dict: the entry as read, with "band", "group" as ints, "scale" as [lo, hi] floats,
## "dressings" as [{id, tint, growth, scale}] and "colliders" as [{center: PackedFloat64Array, radius}].
var assets := {}
# Every entry in file order, duplicates included (rule 1 reports them).
var _entries: Array[Dictionary] = []


## Never null: a missing or unreadable file gives a kit whose validate() says why.
static func load_from(path: String = DEFAULT_PATH) -> PlacementKit:
	var data: Variant = WorldConfig.read_json(path)
	if data == null:
		var broken := PlacementKit.new()
		broken.load_problems.append("%s: missing or not readable JSON" % path.get_file())
		return broken
	return from_dict(data)


static func from_dict(data: Variant) -> PlacementKit:
	var kit := PlacementKit.new()
	var problems := kit.load_problems
	var w := FILE_NAME
	problems.append_array(WorldConfig.schema_problems(w, data, TOP_KEYS))
	if not data is Dictionary:
		return kit
	WorldConfig.header_check(w, data, problems)
	var raw_classes: Variant = data.get("footprint_classes")
	if raw_classes is Dictionary:
		for name in WorldConfig._sorted(raw_classes.keys()):
			var pair := WorldConfig.pair_at(w + ".footprint_classes", raw_classes, name, problems)
			if pair.size() == 2:
				kit.classes[str(name)] = [pair[0], pair[1]]
	elif data.has("footprint_classes"):
		problems.append("%s.footprint_classes: must be an object" % w)
	var landmark := WorldConfig.object_at(w, data, "landmark", LANDMARK_KEYS, problems)
	kit.anchor_radius_bu = WorldConfig.number_at(w + ".landmark", landmark, "anchor_radius_bu", problems)
	kit.collide_radius_bu = WorldConfig.number_at(w + ".landmark", landmark, "collide_radius_bu", problems)
	var raw_groups: Variant = landmark.get("groups", {})
	if raw_groups is Dictionary:
		for band in WorldConfig._sorted(raw_groups.keys()):
			var gw := "%s.landmark.groups.%s" % [w, band]
			if not str(band).is_valid_int():
				problems.append("%s: a band must be a whole number" % gw)
				continue
			var counts: Array[int] = []
			var groups := WorldConfig.list_at(w + ".landmark.groups", raw_groups, band, problems)
			for i in groups.size():
				counts.append(int(WorldConfig.number_at(gw, {str(i): groups[i]}, str(i), problems, true)))
			kit.landmark_groups_by_band[int(band)] = counts
	else:
		problems.append("%s.landmark.groups: must be an object of bands, {\"0\": [2, 2, 1, 1]}" % w)
	kit.landmark_groups.assign(kit.landmark_groups_by_band.get(0, []))
	var raw_assets := WorldConfig.list_at(w, data, "assets", problems)
	for i in raw_assets.size():
		var entry := _read_asset("%s.assets[%d]" % [w, i], raw_assets[i], problems)
		if entry.is_empty():
			continue
		kit._entries.append(entry)
		if not kit.assets.has(entry.id):
			kit.assets[entry.id] = entry
	return kit


## One asset entry, typed; {} when it is not an object or its kind is unknown.
static func _read_asset(w: String, raw: Variant, problems: PackedStringArray) -> Dictionary:
	if not raw is Dictionary:
		problems.append("%s: must be an object" % w)
		return {}
	var kind: Variant = raw.get("kind")
	if not (kind is String and KINDS.has(kind)):
		problems.append("%s.kind: must be one of %s" % [w, ", ".join(KINDS)])
		return {}
	var keys := PackedStringArray(COMMON_KEYS)
	keys.append_array(PackedStringArray(KIND_KEYS[kind]))
	problems.append_array(WorldConfig.schema_problems(w, raw, keys))
	var scale := WorldConfig.pair_at(w, raw, "scale", problems)
	var entry := {
		"id": WorldConfig.text_at(w, raw, "id", problems),
		"kind": kind,
		"band": int(WorldConfig.number_at(w, raw, "band", problems, true)),
		"glb": WorldConfig.text_at(w, raw, "glb", problems),
		"record": WorldConfig.text_at(w, raw, "record", problems),
		"scale": [scale[0], scale[1]] if scale.size() == 2 else [0.0, 0.0],
		"yaw_rule": WorldConfig.text_at(w, raw, "yaw_rule", problems),
		"placeholder": WorldConfig.flag_at(w, raw, "placeholder", problems),
		"approved": WorldConfig.flag_at(w, raw, "approved", problems),
		"where": w,
	}
	var dressings: Array[Dictionary] = []
	var raw_dressings := WorldConfig.list_at(w, raw, "dressings", problems)
	for j in raw_dressings.size():
		var dw := "%s.dressings[%d]" % [w, j]
		problems.append_array(WorldConfig.schema_problems(dw, raw_dressings[j], DRESSING_KEYS))
		var d: Dictionary = raw_dressings[j] if raw_dressings[j] is Dictionary else {}
		dressings.append({"id": WorldConfig.text_at(dw, d, "id", problems), "tint": WorldConfig.text_at(dw, d, "tint", problems),
			"growth": WorldConfig.text_at(dw, d, "growth", problems), "scale": WorldConfig.number_at(dw, d, "scale", problems)})
	entry["dressings"] = dressings
	match kind:
		"shell":
			entry["footprint_class"] = WorldConfig.text_at(w, raw, "footprint_class", problems)
			entry["footprint_radius_m"] = WorldConfig.number_at(w, raw, "footprint_radius_m", problems)
			entry["pickable"] = WorldConfig.flag_at(w, raw, "pickable", problems)
		"landmark":
			entry["group"] = int(WorldConfig.number_at(w, raw, "group", problems, true))
			entry["footprint_radius_m"] = WorldConfig.number_at(w, raw, "footprint_radius_m", problems)
		"rare":
			entry["rare_kind"] = WorldConfig.text_at(w, raw, "rare_kind", problems)
			var colliders: Array[Dictionary] = []
			var raw_colliders := WorldConfig.list_at(w, raw, "colliders", problems)
			for j in raw_colliders.size():
				var cw := "%s.colliders[%d]" % [w, j]
				problems.append_array(WorldConfig.schema_problems(cw, raw_colliders[j], COLLIDER_KEYS))
				var c: Dictionary = raw_colliders[j] if raw_colliders[j] is Dictionary else {}
				colliders.append({"center": WorldConfig.pair_at(cw, c, "center", problems), "radius": WorldConfig.number_at(cw, c, "radius", problems)})
			entry["colliders"] = colliders
	return entry


## The bands with at least one piece that is not a marker, ascending.
func bands() -> PackedInt32Array:
	var seen := {}
	for a in _entries:
		if a.kind != "marker" and int(a.band) >= 0 and int(a.band) <= MAX_KIT_BAND:
			seen[int(a.band)] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## The footprint class of a slot radius in bu: "" when it lies outside every class.
func class_of(r_bu: float) -> String:
	var names := _class_names()
	for i in names.size():
		var span: Array = classes[names[i]]
		if r_bu >= float(span[0]) and (r_bu < float(span[1]) or (i == names.size() - 1 and r_bu <= float(span[1]))):
			return names[i]
	return ""


## The pickable shells of `band` whose scale range covers r_bu / footprint_radius_m, sorted by id.
func fitting(r_bu: float, band: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _sorted_ids():
		var a: Dictionary = assets[id]
		if a.kind == "shell" and a.band == band and a.pickable and _covers(a, r_bu):
			out.append(id)
	return out


## The landmark models of `band` in `group`, sorted by id.
func landmarks(band: int, group: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _sorted_ids():
		var a: Dictionary = assets[id]
		if a.kind == "landmark" and a.band == band and a.group == group:
			out.append(id)
	return out


## The rare set piece of `band` for `rare_kind`, or "" when the kit has none.
func rare_asset(band: int, rare_kind: String) -> String:
	for id in _sorted_ids():
		var a: Dictionary = assets[id]
		if a.kind == "rare" and a.band == band and a.rare_kind == rare_kind:
			return id
	return ""


## Problems with the kit itself; empty when the world can place it. Reading problems come back
## alone, since the rules cannot be judged on entries that did not read.
func validate() -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	var w := FILE_NAME
	# Rule 2: exactly the S1 classes. The fit and coverage rules lean on them, so they wait for it.
	var classes_ok := classes.size() == CLASSES.size()
	for name in CLASSES:
		classes_ok = classes_ok and classes.has(name) and classes[name] == CLASSES[name]
	if not classes_ok:
		errors.append("%s.footprint_classes: must be exactly %s" % [w, JSON.stringify(CLASSES, "", true)])

	var records_on_hand := DirAccess.dir_exists_absolute(RECORDS_DIR)
	var seen := {}
	var rare_kinds := {}
	var group_counts := {}
	var groups_ok := true
	for a in _entries:
		var aw: String = a.where
		# Rule 1: the id, the kind and the band. An entry whose identity is wrong is not checked further.
		if seen.has(a.id):
			errors.append("%s.id: '%s' is repeated" % [aw, a.id])
			continue
		seen[a.id] = true
		if not _matches(a.id, ID_PATTERN):
			errors.append("%s.id: '%s' does not match %s" % [aw, a.id, ID_PATTERN])
			continue
		if (a.kind == "marker") != (a.band == -1) or (a.kind != "marker" and (a.band < 0 or a.band > MAX_KIT_BAND)):
			errors.append("%s.band: %d; content is band 0 to %d and only markers (any band) are -1" % [aw, a.band, MAX_KIT_BAND])
			continue
		# Rule 3: the scale range.
		var lo: float = a.scale[0]
		var hi: float = a.scale[1]
		if not (MIN_SCALE <= lo and lo <= hi and hi <= MAX_SCALE and hi <= lo * MAX_SCALE_SPAN):
			errors.append("%s.scale: [%s, %s] needs %s <= lo <= hi <= %s and hi / lo <= %s" % [aw, lo, hi, MIN_SCALE, MAX_SCALE, MAX_SCALE_SPAN])
		elif a.kind == "landmark" and (lo < LANDMARK_SCALE[0] or hi > LANDMARK_SCALE[1]):
			errors.append("%s.scale: a landmark's scale lies within %s" % [aw, LANDMARK_SCALE])
		elif (a.kind == "rare" or a.kind == "marker") and not (lo == 1.0 and hi == 1.0):
			errors.append("%s.scale: a %s's scale is [1, 1]" % [aw, a.kind])
		# Rule 7: the yaw rule its kind allows.
		if not YAW_RULES[a.kind].has(a.yaw_rule):
			errors.append("%s.yaw_rule: '%s' is not one of %s for a %s" % [aw, a.yaw_rule, YAW_RULES[a.kind], a.kind])
		# Rule 8: the dressings (a shell has at least one; the hash picks among them).
		var dressing_ids := {}
		for j in a.dressings.size():
			var d: Dictionary = a.dressings[j]
			var dw := "%s.dressings[%d]" % [aw, j]
			if dressing_ids.has(d.id) or str(d.id).is_empty():
				errors.append("%s.id: '%s' is empty or repeated" % [dw, d.id])
			dressing_ids[d.id] = true
			if not _matches(d.tint, TINT_PATTERN):
				errors.append("%s.tint: '%s' does not match %s" % [dw, d.tint, TINT_PATTERN])
			if not (str(d.growth).is_empty() or _matches(d.growth, GROWTH_PATTERN)):
				errors.append("%s.growth: '%s' is neither \"\" nor a node name Growth_<Name>" % [dw, d.growth])
		if a.kind == "shell" and a.dressings.is_empty():
			errors.append("%s.dressings: a shell needs at least one" % aw)
		match a.kind:
			"shell":
				# Rule 4: a positive footprint, and the asset covers its own class.
				if not (float(a.footprint_radius_m) > 0.0):
					errors.append("%s.footprint_radius_m: must be above 0" % aw)
				elif not CLASSES.has(a.footprint_class):
					errors.append("%s.footprint_class: '%s' is not one of %s" % [aw, a.footprint_class, ", ".join(PackedStringArray(CLASSES.keys()))])
				elif classes_ok:
					var span: Array = classes[a.footprint_class]
					if not (_covers(a, float(span[0])) and _covers(a, float(span[1]))):
						errors.append("%s: footprint %s at scale %s does not cover its class %s %s" % [aw, a.footprint_radius_m, a.scale, a.footprint_class, span])
			"landmark":
				# Rule 5: the fixed collider, the group and three dressings within the scale range.
				if float(a.footprint_radius_m) != collide_radius_bu:
					errors.append("%s.footprint_radius_m: %s must equal landmark.collide_radius_bu %s" % [aw, a.footprint_radius_m, collide_radius_bu])
				if a.group < 0 or a.group >= GROUPS:
					errors.append("%s.group: %d is not in [0, %d)" % [aw, a.group, GROUPS])
					groups_ok = false
				else:
					var key := Vector2i(a.band, a.group)
					group_counts[key] = int(group_counts.get(key, 0)) + 1
				if a.dressings.size() != LANDMARK_DRESSINGS:
					errors.append("%s.dressings: a landmark has exactly %d (%d)" % [aw, LANDMARK_DRESSINGS, a.dressings.size()])
				for j in a.dressings.size():
					var s: float = a.dressings[j].scale
					if s < lo or s > hi:
						errors.append("%s.dressings[%d].scale: %s is outside the asset's scale %s" % [aw, j, s, a.scale])
			"rare":
				# Rule 6: one piece per rare kind, colliders a chunk arena takes.
				var rare_key := "%d/%s" % [a.band, a.rare_kind]
				if rare_kinds.has(rare_key) or str(a.rare_kind).is_empty():
					errors.append("%s.rare_kind: '%s' is empty or repeated in band %d" % [aw, a.rare_kind, a.band])
				rare_kinds[rare_key] = true
				if a.colliders.is_empty():
					errors.append("%s.colliders: a set piece needs at least one" % aw)
				for j in a.colliders.size():
					var r: float = a.colliders[j].radius
					if r < MIN_COLLIDER_R or r > ChunkArena.MAX_COLLIDER_R:
						errors.append("%s.colliders[%d].radius: %s is outside [%s, %s]" % [aw, j, r, MIN_COLLIDER_R, ChunkArena.MAX_COLLIDER_R])
		# Rule 9: the GLB and the record exist and agree; rule 10: the placeholder and approval flags.
		if not ResourceLoader.exists(a.glb):
			errors.append("%s.glb: '%s' does not exist" % [aw, a.glb])
		if records_on_hand:
			_check_record(a, aw, errors)
		elif a.approved and a.placeholder:
			errors.append("%s.approved: a placeholder is never approved" % aw)

	# Rule 5: each band's landmark groups hold the models landmark.groups lists for it, and the list
	# names only bands the kit has pieces for.
	var kit_bands := bands()
	if groups_ok:
		var group_bands := {}
		for b in kit_bands:
			group_bands[b] = true
		for b in landmark_groups_by_band:
			group_bands[b] = true
		for b in WorldConfig._sorted(group_bands.keys()):
			var counts: Array[int] = []
			for g in GROUPS:
				counts.append(int(group_counts.get(Vector2i(b, g), 0)))
			var want: Array = landmark_groups_by_band.get(b, [])
			if want.size() != GROUPS or counts != want:
				errors.append("%s.landmark.groups: band %d's landmarks per group are %s, not %s" % [w, b, counts, want])
	# Rule 11: coverage in each band, and the two markers.
	if classes_ok:
		for b in kit_bands:
			for name in _class_names():
				var span: Array = classes[name]
				var covering := 0
				for id in assets:
					var a: Dictionary = assets[id]
					if a.kind == "shell" and a.band == b and a.pickable and _covers(a, float(span[0])) and _covers(a, float(span[1])):
						covering += 1
				if covering < MIN_PICKABLE_PER_CLASS:
					errors.append("%s.assets: %d pickable band-%d shells cover all of %s %s; it needs %d" % [w, covering, b, name, span, MIN_PICKABLE_PER_CLASS])
	for id in MARKERS:
		if not (assets.has(id) and assets[id].kind == "marker"):
			errors.append("%s.assets: the marker '%s' is missing" % [w, id])
	# Rule 12: the M1 rocks, for the home block's fixed rocks only.
	for id in M1_ROCKS:
		var a: Dictionary = assets.get(id, {})
		if a.is_empty() or a.kind != "shell" or a.pickable or float(a.footprint_radius_m) != 1.0 or a.scale != M1_ROCK_SCALE:
			errors.append("%s.assets: '%s' must be a shell with pickable false, footprint_radius_m 1.0 and scale %s" % [w, id, M1_ROCK_SCALE])
	return errors


## Rules 9 and 10 against the asset's record.
func _check_record(a: Dictionary, aw: String, errors: PackedStringArray) -> void:
	var record: Variant = WorldConfig.read_json(a.record)
	if not record is Dictionary:
		errors.append("%s.record: '%s' does not exist or is not a JSON object" % [aw, a.record])
		return
	var mismatches := PackedStringArray()
	if record.get("id") != a.id:
		mismatches.append("id '%s'" % record.get("id"))
	if ResourceLoader.exists(a.glb) and str(record.get("export_path", "")) != str(a.glb).trim_prefix("res://"):
		mismatches.append("export_path '%s'" % record.get("export_path"))
	if a.has("footprint_radius_m") and record.get("footprint_radius_m") != a.footprint_radius_m:
		mismatches.append("footprint_radius_m %s" % record.get("footprint_radius_m"))
	if not mismatches.is_empty():
		errors.append("%s.record: '%s' disagrees: %s" % [aw, a.record, ", ".join(mismatches)])
	var blockout := str(record.get("review_state", "")).begins_with(PLACEHOLDER_STATE)
	if a.placeholder != blockout:
		errors.append("%s.placeholder: %s, but the record's review_state is '%s'" % [aw, a.placeholder, record.get("review_state", "")])
	elif a.approved and (a.placeholder or record.get("status") != "APPROVED"):
		errors.append("%s.approved: needs a finished piece whose record status is APPROVED" % aw)


## True when the shell's scale range covers r_bu / footprint_radius_m (within FIT_EPSILON).
static func _covers(a: Dictionary, r_bu: float) -> bool:
	var fr: float = a.footprint_radius_m
	if not (fr > 0.0):
		return false
	var s := r_bu / fr
	return s >= float(a.scale[0]) - FIT_EPSILON and s <= float(a.scale[1]) + FIT_EPSILON


## Class names in ascending order of their lower bound.
func _class_names() -> PackedStringArray:
	var names := classes.keys()
	names.sort_custom(func(x, y): return float(classes[x][0]) < float(classes[y][0]) or (float(classes[x][0]) == float(classes[y][0]) and str(x) < str(y)))
	return PackedStringArray(names)


func _sorted_ids() -> Array:
	return WorldConfig._sorted(assets.keys())


static func _matches(text: Variant, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return text is String and re.search(text) != null
