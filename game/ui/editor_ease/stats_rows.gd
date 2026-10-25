extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): the creature editor's stat lines as rows, and each row's change
## since the visit began. The editor sends text lines (CreatureEditor._refresh_hud: "Length  1.31 m",
## "Legs  4   ·   limbs  4", "Selected  part p3"); a line holds one or more "name  value" segments. Pure text work:
## no scene, no editor access. An issue asks the editor for the numbers themselves; until then the panel reads
## the text it already gets. No class_name: preload it.

## Between two stats on one line, as the editor writes them.
const SEGMENT := "   ·   "
## Between a stat's name and its value.
const NAME_GAP := "  "
## The line that names the selection, not a stat.
const SELECTED_KEY := "selected"
## Whether a higher value is better (+1). Any other stat (length, mass, legs, limbs, parts, bones) is a plain change,
## neither better nor worse: a longer or heavier body is a choice, not an upgrade. PROPOSED.
const SENSE := {"speed": 1, "health": 1, "bite": 1, "sight": 1}
const UP := "▲"
const DOWN := "▼"

static var _number_re: RegEx


## {rows: [{key, name, text, number, unit, decimals}], selected: String}. A segment with no "name  number" shape
## becomes a raw row {key: "", name: the whole segment, text: "", raw: true}, so nothing the editor sends is lost.
static func parse(lines: PackedStringArray) -> Dictionary:
	var rows: Array = []
	var selected := ""
	for line in lines:
		for segment in line.split(SEGMENT, false):
			var seg := segment.strip_edges()
			var at := seg.find(NAME_GAP)
			var name := seg.substr(0, at).strip_edges() if at > 0 else seg
			var text := seg.substr(at).strip_edges() if at > 0 else ""
			if name.to_lower() == SELECTED_KEY:
				selected = text
				continue
			var number := _leading_number(text)
			if at <= 0 or number.is_empty():
				rows.append({"key": "", "name": seg, "text": "", "raw": true})
				continue
			rows.append({
				"key": name.to_lower(), "name": name.left(1).to_upper() + name.substr(1), "text": text,
				"number": number.to_float(), "unit": text.substr(number.length()).strip_edges(),
				"decimals": number.length() - number.find(".") - 1 if number.contains(".") else 0,
			})
	return {"rows": rows, "selected": selected}


## `now`'s rows, each with {delta, sense, change}: the difference from the row of the same key in `baseline`, the
## stat's SENSE, and its change text ("▲ +0.4 m/s", "▼ -3", "+0.12 m" for a plain change, "" when the shown value is
## the same). A row the baseline lacks shows no change.
static func compare(now: Array, baseline: Array) -> Array:
	var before := {}
	for row: Dictionary in baseline:
		if row["key"] != "":
			before[row["key"]] = row
	var out: Array = []
	for row: Dictionary in now:
		var r := row.duplicate()
		r["delta"] = 0.0
		r["sense"] = int(SENSE.get(r["key"], 0))
		r["change"] = ""
		if r["key"] != "" and before.has(r["key"]) and before[r["key"]]["text"] != r["text"]:
			r["delta"] = snappedf(float(r["number"]) - float(before[r["key"]]["number"]), pow(10.0, -int(r["decimals"])))
			r["change"] = change_text(r)
		out.append(r)
	return out


## "▲ +0.4 m/s" (better), "▼ -3" (worse) or "+0.12 m" (a plain change); "" for no change.
static func change_text(row: Dictionary) -> String:
	var delta := float(row.get("delta", 0.0))
	if is_zero_approx(delta):
		return ""
	var digits := int(row.get("decimals", 0))
	var number := ("%+." + str(digits) + "f") % delta
	var unit := String(row.get("unit", ""))
	var text := number if unit.is_empty() else "%s %s" % [number, unit]
	var sense := int(row.get("sense", 0))
	if sense == 0:
		return text
	return "%s %s" % [UP if delta * sense > 0.0 else DOWN, text]


## Whether a compared row got better (true), worse (false) or is a plain change or unchanged (null).
static func better(row: Dictionary) -> Variant:
	var delta := float(row.get("delta", 0.0))
	if is_zero_approx(delta) or int(row.get("sense", 0)) == 0:
		return null
	return delta * int(row["sense"]) > 0.0


## The number at the start of `text` ("1.31" of "1.31 m", "-2" of "-2"), or "".
static func _leading_number(text: String) -> String:
	if _number_re == null:
		_number_re = RegEx.create_from_string("^-?[0-9]+(\\.[0-9]+)?")
	var m := _number_re.search(text)
	return m.get_string() if m != null else ""
