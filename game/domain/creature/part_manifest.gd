extends RefCounted
## The part list a shared creature carries, and which of its parts this build does not have (IB-31 "Graceful
## sharing", PROPOSED; Bible section 18). A part whose type has no rules here is a placeholder: it stays in the
## body exactly as written (type, anchor and handles), is not drawn as the real part, and is named in a warning.
## Nothing here is saved; it is all derived from the body and the part rules at load.
## Pure rules: no scene or file access.


## The part type ids the body uses, each once, sorted.
static func needed(desc: RefCounted) -> PackedStringArray:
	var seen := {}
	for p in desc.parts:
		seen[String(p["type"])] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## The needed type ids with no entry in `part_rules` (type -> rules), sorted.
static func missing(desc: RefCounted, part_rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for type in needed(desc):
		if not part_rules.has(type):
			out.append(type)
	return out


## Whether one part entry of a body is a placeholder under `part_rules`.
static func is_placeholder(part: Dictionary, part_rules: Dictionary) -> bool:
	return not part_rules.has(String(part.get("type", "")))


## The ids of the body's placeholder parts, in body order.
static func placeholder_ids(desc: RefCounted, part_rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for p in desc.parts:
		if is_placeholder(p, part_rules):
			out.append(String(p["id"]))
	return out


## {"needed": [...], "missing": [...], "placeholders": [part ids]}: what an export lists and a loader reports.
static func report(desc: RefCounted, part_rules: Dictionary) -> Dictionary:
	return {"needed": needed(desc), "missing": missing(desc, part_rules),
			"placeholders": placeholder_ids(desc, part_rules)}


## One readable line for each placeholder part, in body order; empty when every part is known.
static func warnings(desc: RefCounted, part_rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for p in desc.parts:
		if is_placeholder(p, part_rules):
			out.append("part %s needs the missing part type %s; it is kept as a placeholder" % [String(p["id"]),
					String(p["type"])])
	return out


## The most type names notice() lists before "and N more".
const NOTICE_NAMES_MAX := 3


## The plain-words notice the player sees when a body opens with `missing_types` (missing()'s list): how many part
## types this version does not have, the first `cap` names, and what happens to them. Empty when nothing is missing.
static func notice(missing_types: PackedStringArray, cap: int = NOTICE_NAMES_MAX) -> String:
	var n := missing_types.size()
	if n == 0:
		return ""
	var shown := Array(missing_types.slice(0, maxi(1, cap)))
	var names := ", ".join(PackedStringArray(shown))
	if n > shown.size():
		names += " and %d more" % (n - shown.size())
	if n == 1:
		return "This creature uses 1 part this version does not have (%s). It is kept in the save and left out for now." % names
	return "This creature uses %d parts this version does not have (%s). They are kept in the save and left out for now." % [n, names]


## notice() for a body.
static func notice_for(desc: RefCounted, part_rules: Dictionary, cap: int = NOTICE_NAMES_MAX) -> String:
	return notice(missing(desc, part_rules), cap)


## What a part is called in a list or a selection line: its type, or "Missing part: <type>" for a placeholder.
static func part_label(part: Dictionary, part_rules: Dictionary) -> String:
	var type := String(part.get("type", ""))
	return "Missing part: %s" % type if is_placeholder(part, part_rules) else type
