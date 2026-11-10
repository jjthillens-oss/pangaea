extends RefCounted
## Editor-ease (docs/proposals/editor-ease.md): the cell editor's symmetry rules, pure and static. A part's twin is
## the part of the same type, size and level at its mirrored angle (the copy EditorSession.mirror_part makes);
## nothing links the two, so a pair is found from where the parts sit. A part on the middle line has no twin, by the
## same rule as EditorSession.mirror_part. A drag round the rim snaps onto the middle line or opposite a part of
## its type (snap()). UI only: EditorSession is not edited. No class_name; preload it.

## |sin(angle)| under this is on the middle line (EditorSession.mirror_part refuses to mirror such a part).
const CENTRE_SIN := 0.05
## How far a twin may sit from the exact mirrored angle, in radians.
const MIRROR_EPS := 0.02
## A part of a pair keeps this far off the middle line (radians), so the two never meet on it; sin(0.06) > 0.05.
const PAIR_EDGE := 0.06
## A drag snaps within this of the middle line or of a twin's spot (PROPOSED, radians; about 4 degrees).
const SNAP_RAD := 0.07


static func is_central(angle: float) -> bool:
	return absf(sin(angle)) < CENTRE_SIN


## The angle across the front-back line, in -PI..PI.
static func mirrored(angle: float) -> float:
	return wrapf(-angle, -PI, PI)


## `part`'s twin among `parts`: the same type, size and level at its mirrored angle, the nearest to that angle
## (ties by id). {} for none, and always {} for a part on the middle line.
static func twin_of(parts: Array, part: Dictionary) -> Dictionary:
	if part.is_empty() or is_central(float(part.angle)):
		return {}
	var target := mirrored(float(part.angle))
	var best := {}
	var best_d := MIRROR_EPS
	for p: Dictionary in parts:
		if str(p.id) == str(part.id) or str(p.type) != str(part.type):
			continue
		if not is_equal_approx(float(p.scale), float(part.scale)) or Genome.level_of(p) != Genome.level_of(part):
			continue
		var d := absf(angle_difference(float(p.angle), target))
		if d < best_d or (d == best_d and not best.is_empty() and str(p.id) < str(best.id)):
			best_d = d
			best = p
	return best


## `angle`, or when it is on the middle line (within PAIR_EDGE of it), the nearest spot just off the line on the
## side `from_angle` is on: a part of a pair never sits on the line, where it and its twin would meet. A move that
## crosses the line puts the part on the other side, and its twin on this one.
static func off_line(angle: float, from_angle: float) -> float:
	var a := wrapf(angle, -PI, PI)
	if absf(sin(a)) >= sin(PAIR_EDGE):
		return a
	var side := 1.0 if sin(from_angle) >= 0.0 else -1.0
	return side * (PAIR_EDGE if cos(a) > 0.0 else PI - PAIR_EDGE)


## A snap target this close to another part's angle is taken (radians): snapping there would put the dragged dot
## on top of that part's dot, where a click picks the other part. The rim passes its own dot size instead.
const CLEAR_RAD := 0.1


## A dragged part's angle, snapped: onto the middle line (front or back) or opposite another part of its type (where
## its mirror would be), when within SNAP_RAD; the nearest wins, the middle line on a tie, then the lower id. A target
## within `clear` of a part other than the moving one (and the ids in `keep`, its twin) is taken and skipped, so a
## drag never snaps one dot onto another (the mouth at the front and the tail at the back hold the middle line).
## Returns {"angle", "kind": "centre" | "twin" | "taken" | "", "of": the part it is opposite, for "twin"}; "taken"
## when the only target in reach was taken (the angle is then the pointer's own).
static func snap(angle: float, parts: Array, moving_id: String, keep: Array = [], clear := CLEAR_RAD) -> Dictionary:
	var a := wrapf(angle, -PI, PI)
	var best := {"angle": a, "kind": "", "of": ""}
	var best_d := SNAP_RAD
	var taken := false
	var skip: Array = keep.map(func(id: Variant) -> String: return str(id))
	skip.append(moving_id)
	for line: float in [0.0, PI]:
		var d := absf(angle_difference(a, line))
		if d >= best_d:
			continue
		if is_taken(line, parts, skip, clear):
			taken = true
			continue
		best_d = d
		best = {"angle": line, "kind": "centre", "of": ""}
	var moving := {}
	for p: Dictionary in parts:
		if str(p.id) == moving_id:
			moving = p
	if not moving.is_empty():
		var others := parts.filter(func(p: Dictionary) -> bool:
			return not str(p.id) in skip and str(p.type) == str(moving.type) and not is_central(float(p.angle)))
		others.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x.id) < str(y.id))
		for p: Dictionary in others:
			var target := mirrored(float(p.angle))
			var d := absf(angle_difference(a, target))
			if d >= best_d:
				continue
			if is_taken(target, parts, skip, clear):
				taken = true
				continue
			best_d = d
			best = {"angle": target, "kind": "twin", "of": str(p.id)}
	if taken and str(best.kind) == "":
		best["kind"] = "taken"
	return best


## Whether a part whose id is not in `skip` sits within `clear` of `angle`.
static func is_taken(angle: float, parts: Array, skip: Array, clear: float) -> bool:
	for p: Dictionary in parts:
		if not str(p.id) in skip and absf(angle_difference(float(p.angle), angle)) < clear:
			return true
	return false
