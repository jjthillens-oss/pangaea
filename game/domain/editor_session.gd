class_name EditorSession
extends RefCounted
## One visit to the body editor (Bible section 12). Edits apply to a working copy with undo and
## redo; preview() shows the stats and cost the commit would produce; commit() validates, derives,
## checks the cost and only then returns the new genome. A refused edit or commit changes nothing.
##
## Cost = what was added this session - refund_rate x what was removed, where a part's worth is its
## cost plus its upgrades (PartCatalog.value_of): a new part, an upgrade to a kept part, a removed
## part. It can be negative (a refund). Moving, scaling or recoloring parts is free.

var catalog: PartCatalog
var original: Genome
var working: Genome
var available_points: int = 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func _init(p_genome: Genome, p_catalog: PartCatalog, p_points: int) -> void:
	catalog = p_catalog
	original = p_genome
	working = Genome.from_dict(p_genome.to_dict())
	available_points = p_points


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var r := {"ok": true, "reason": ""}
	r.merge(extra)
	return r


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _checkpoint() -> void:
	_undo.append(working.to_dict())
	_redo.clear()


func _scale_ok(scale: float) -> bool:
	return is_finite(scale) and scale >= catalog.min_scale and scale <= catalog.max_scale


func _find(part_id: String) -> Dictionary:
	for part in working.parts:
		if part.id == part_id:
			return part
	return {}


func add_part(type_id: String, angle: float, scale: float = 1.0, level: int = 1) -> Dictionary:
	if not catalog.in_editor(type_id):
		return _no("%s is not available yet" % type_id)
	if working.count_of(type_id) >= catalog.max_count_of(type_id):
		return _no("limit of %d reached" % catalog.max_count_of(type_id))
	if working.parts.size() >= catalog.max_parts:
		return _no("no free part slots")
	if not _scale_ok(scale):
		return _no("size out of range")
	if not is_finite(angle):
		return _no("bad position")
	if level < 1 or level > catalog.max_level or (level > 1 and not catalog.can_level(type_id)):
		return _no("no such level")
	_checkpoint()
	var part_id := working.add_part(type_id, wrapf(angle, -PI, PI), scale, level)
	return _ok({"part_id": part_id})


func remove_part(part_id: String) -> Dictionary:
	if _find(part_id).is_empty():
		return _no("no such part")
	_checkpoint()
	working.remove_part(part_id)
	return _ok()


func move_part(part_id: String, angle: float) -> Dictionary:
	var part := _find(part_id)
	if part.is_empty():
		return _no("no such part")
	if not is_finite(angle):
		return _no("bad position")
	_checkpoint()
	part.angle = wrapf(angle, -PI, PI)
	return _ok()


func scale_part(part_id: String, scale: float) -> Dictionary:
	if _find(part_id).is_empty():
		return _no("no such part")
	if not _scale_ok(scale):
		return _no("size out of range")
	_checkpoint()
	_find(part_id).scale = scale
	return _ok()


## Adds a copy of the part on the opposite side (angle mirrored across the front-back line).
func mirror_part(part_id: String) -> Dictionary:
	var part := _find(part_id)
	if part.is_empty():
		return _no("no such part")
	if absf(sin(float(part.angle))) < 0.05:
		return _no("part sits on the center line")
	return add_part(part.type, -float(part.angle), float(part.scale), Genome.level_of(part))


## Raises a part one level (S4.5): stronger, a little heavier and dearer to run.
func upgrade_part(part_id: String) -> Dictionary:
	var part := _find(part_id)
	if part.is_empty():
		return _no("no such part")
	if not catalog.can_level(part.type):
		return _no("this part does not level up")
	var level := Genome.level_of(part)
	if level >= catalog.max_level:
		return _no("already at level %d" % level)
	_checkpoint()
	part["level"] = level + 1
	return _ok({"cost": catalog.upgrade_cost(part.type, level)})


func set_appearance(key: String, value: Variant) -> Dictionary:
	_checkpoint()
	working.appearance[key] = value
	return _ok()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(working.to_dict())
	working = Genome.from_dict(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(working.to_dict())
	working = Genome.from_dict(_redo.pop_back())
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func cost() -> int:
	var before := _values(original)
	var after := _values(working)
	var added := 0
	var removed := 0
	for id in after:
		var change: int = after[id] - before.get(id, 0)
		if change > 0:
			added += change
		else:
			removed -= change
	for id in before:
		if not after.has(id):
			removed += before[id]
	return added - floori(removed * catalog.refund_rate)


## part id -> what the part has cost (its type's cost and its upgrades).
func _values(genome: Genome) -> Dictionary:
	var out := {}
	for part in genome.parts:
		out[part.id] = catalog.value_of(part.type, Genome.level_of(part))
	return out


## What committing now would produce, without committing.
func preview() -> Dictionary:
	var c := cost()
	return {
		"phenotype": Phenotype.derive(working, catalog),
		"current": Phenotype.derive(original, catalog),
		"cost": c,
		"affordable": c <= available_points,
		"errors": working.validate(catalog),
	}


## Returns {"ok", "errors", "genome": Genome (the offspring), "points_left": int}.
## On failure the original genome and points are untouched.
func commit() -> Dictionary:
	var errors := working.validate(catalog)
	var c := cost()
	if c > available_points:
		errors.append("Needs %d adaptation points, you have %d." % [c, available_points])
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "genome": null, "points_left": available_points}
	var child := Genome.from_dict(working.to_dict())
	child.genome_id = StableId.generate("genome")
	child.parent_genome_id = original.genome_id
	child.generation = original.generation + 1
	return {"ok": true, "errors": PackedStringArray(), "genome": child, "points_left": available_points - c}
