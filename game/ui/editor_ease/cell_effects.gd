extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): what adding a part does to the cell, for the palette's part card. The
## numbers come from the game's own rules: the part goes onto a copy of the working body where add() would put it
## (with its twin when Symmetry is on), and Phenotype.derive runs on the body before and after, so diminishing
## copies, caps, levels, energy use and mass all count as they will (Bible 12 one stats rule; Bible 14 previews use
## the rules of the result). Pure: reads the session, never changes it. No class_name; preload it.


## The stat rows that change when `type_id` is added at each of `angles`: [label, before, after, better] in
## CellEditor.stat_rows' order and format, the Eats row included; rows whose shown numbers stay the same are left
## out.
static func rows(working: Genome, catalog: PartCatalog, type_id: String, angles: Array) -> Array:
	var copy := Genome.from_dict(working.to_dict())
	for a: float in angles:
		copy.add_part(type_id, wrapf(a, -PI, PI))
	var all := CellEditor.stat_rows(Phenotype.derive(working, catalog), Phenotype.derive(copy, catalog))
	return all.filter(func(r: Array) -> bool: return r[1] != r[2])


## The card for adding `type_id` at `angles` (one angle, or a part's and its twin's), `role` saying what it is for:
## {"title", "lines"} in the part card's line format (part_card.gd show_lines).
static func card(session: EditorSession, type_id: String, angles: Array, role: String) -> Dictionary:
	var catalog := session.catalog
	var working := session.working
	var price := catalog.cost_of(type_id)
	var count := working.count_of(type_id)
	var limit := catalog.max_count_of(type_id)
	var room := mini(limit - count, catalog.max_parts - working.parts.size())
	var fits := clampi(room, 0, angles.size())
	var part_name := type_id.capitalize()
	var title := "%s · %d points" % [part_name, price] if fits < 2 else "%s pair · %d points" % [part_name, 2 * price]
	var lines := []
	if not role.is_empty():
		lines.append([role.substr(0, 1).to_upper() + role.substr(1), ""])
	if fits == 0:
		if count >= limit:
			lines.append(["Limit reached: %d of %d on the body" % [count, limit], "worse"])
		else:
			lines.append(["No free part slots: %d of %d used" % [working.parts.size(), catalog.max_parts], "worse"])
		return {"title": title, "lines": lines}
	if fits < angles.size():
		lines.append(["Only one fits: its twin would pass the limit", "note"])
	elif fits == 2:
		lines.append(["Adds it with a mirrored twin (Symmetry is on)", "note"])
	var placed := angles.slice(0, fits)
	for r: Array in rows(working, catalog, type_id, placed):
		lines.append(["stat", r[0], r[1], r[2], r[3]])
	if count > 0 and catalog.diminishing_factor < 1.0:
		lines.append(["Copies add less: each extra one gives %d%% of the one before; energy use and mass in full"
			% roundi(100.0 * catalog.diminishing_factor), "note"])
	lines.append(["%d of %d on the body now" % [count, limit], "note"])
	var left := session.available_points - session.cost() - price * fits
	if left < 0:
		lines.append(["Needs %d more points than you have" % -left, "worse"])
	else:
		lines.append(["Leaves %d of your %d points" % [left, session.available_points], "note"])
	lines.append([placement(float(placed[0]), fits == 2), "note"])
	return {"title": title, "lines": lines}


## Where add() puts it, in words: the front, the back, or a side (with its twin opposite).
static func placement(angle: float, pair: bool) -> String:
	var where := "Goes at the side, in the widest gap"
	if absf(angle_difference(angle, 0.0)) < 0.05:
		where = "Goes at the front"
	elif absf(angle_difference(angle, PI)) < 0.05:
		where = "Goes at the back"
	elif pair:
		where += ", its twin opposite"
	return where + ". Drag its dot round the rim to move it."
