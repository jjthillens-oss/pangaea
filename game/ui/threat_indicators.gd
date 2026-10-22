class_name ThreatIndicators
extends Control
## Off-screen threat arrows (M1 step 3, plan section 15; never cut). The pool camera shows only
## about 5.5 m south of the cell at the default zoom, while a creature senses 6 m or more, so a
## creature can notice, watch or strike from below the screen edge. Each creature whose brain is
## on the cell (noticing it, watching it, chasing it or attacking it) and whose body is off screen
## gets an arrow on the screen edge, along the line from the screen center toward it: a badge with
## its species glyph (HudIcon "jaw" for an ambush hunter, "star" for a rammer) and a pointer. During
## a tell the arrow pulses at PULSE_HZ and shows "!", so shape, motion and text carry it, and the
## tell's own sound is positional.
##
## It only reads the sim and the pool camera, at REFRESH_HZ. The HUD binds it to the pool.

const REFRESH_HZ := 30.0
## px: arrows sit this far inside the screen edge (the badge and its pointer fit).
const MARGIN_PX := 70.0
const BADGE_RADIUS_PX := 30.0
const POINTER_PX := 18.0            ## the pointer reaches this far past the badge
const POINTER_HALF_W_PX := 12.0
const GLYPH_PX := 36.0
const PULSE_HZ := 3.0
const PULSE_GROW := 0.25            ## a telling arrow grows this much at the top of each pulse
const BADGE_COLOR := Color(0.03, 0.11, 0.13, 0.9)
const THREAT_COLOR := Color(0.851, 0.275, 0.42)       ## threat #D9466B (docs/art/ART_DIRECTION.md)
const GLYPH_COLOR := Color(0.957, 0.918, 0.824)       ## cream highlight #F4EAD2
## The tell's "!": a bar over a dot, MARK_PX tall, MARK_GAP_PX beyond the badge on the side away
## from the screen edge, upright wherever the arrow is. Drawn as shapes, so no font can shrink it.
const MARK_PX := 34.0
const MARK_BAR_SHARE := 0.26        ## the bar's (and the dot's) width, as a share of the mark's height
const MARK_GAP_PX := 8.0
const MARK_OUTLINE_PX := 3.0
## The glyph for each behavior; anything else gets the jaw.
const GLYPHS := {"ambush": "jaw", "territorial": "star"}

var pool: PoolScene
## The arrows drawn now, in creature order: {"id", "species", "glyph", "position" (the badge's
## center on screen), "direction" (unit, from the screen center toward the creature), "telling"}.
var indicators: Array[Dictionary] = []
## What _draw drew for those arrows, for checks: one {"id", "badge" (Rect2 around the badge and its
## pointer), "mark" (Rect2 around the "!", empty without one)} per arrow on screen. Each refresh
## empties it, so a hidden layer, which draws nothing, leaves it empty.
var drawn: Array[Dictionary] = []

var _refresh_t := 0.0
var _pulse_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(p_pool: PoolScene) -> void:
	pool = p_pool
	refresh()


## Brings the arrows up to date now (they otherwise refresh at REFRESH_HZ).
func refresh() -> void:
	indicators.clear()
	drawn.clear()
	if pool == null or pool.sim == null or pool.sim.creatures == null or pool.camera == null:
		queue_redraw()
		return
	var sim := pool.sim
	var camera := pool.camera
	var rect := get_viewport_rect()
	for c in sim.creatures.creatures:
		if c.brain == null or not watches_player(c.brain):
			continue
		var at := PlaneSpace.to_world(c.motion.position)
		if on_screen(camera, rect, at):
			continue
		var edge := edge_point(rect, camera.unproject_position(at), camera.is_position_behind(at), MARGIN_PX)
		indicators.append(indicator_for(c.id, c.species_id, c.brain, edge, edge - rect.get_center()))
	queue_redraw()


## True when the world point `at` is in front of `camera` and projects inside the screen `rect`: a
## creature there is drawn on screen and gets no arrow.
static func on_screen(camera: Camera3D, rect: Rect2, at: Vector3) -> bool:
	return not camera.is_position_behind(at) and rect.has_point(camera.unproject_position(at))


## The arrow row for creature `id` of `species` with brain `mem`, at `edge` on screen, pointing
## along `direction` (from the screen center toward the creature; any length).
static func indicator_for(id: String, species: String, mem: CreatureBrain.Memory, edge: Vector2, direction: Vector2) -> Dictionary:
	return {"id": id, "species": species, "glyph": GLYPHS.get(mem.behavior, "jaw"), "position": edge,
		"direction": direction.normalized() if direction.length() > 1e-6 else Vector2.DOWN,
		"telling": is_telling(mem)}


## True when the brain's attention is on the cell: noticing it, watching it (an ambush hunter at
## rest), or engaged with it (chase or attack).
static func watches_player(mem: CreatureBrain.Memory) -> bool:
	if mem.target != CreatureField.PLAYER_ID:
		return false
	if mem.state in [CreatureBrain.NOTICE, CreatureBrain.CHASE, CreatureBrain.ATTACK]:
		return true
	return mem.state == CreatureBrain.REST and mem.phase == CreatureBrain.WATCH


## True during a tell (the coil or the puff).
static func is_telling(mem: CreatureBrain.Memory) -> bool:
	return mem.state == CreatureBrain.ATTACK and mem.phase == CreatureBrain.TELL


## Where an arrow for a point projected at `p_screen` goes. A point inside `rect` shrunk by
## `margin` is returned as it is (it is on screen). Any other point goes onto the edge of that inset
## rect, along the ray from the rect's center toward it. A point behind the camera projects
## mirrored through the center, so it is mirrored back first and always goes to the edge. Never NaN.
static func edge_point(rect: Rect2, p_screen: Vector2, behind_camera: bool, margin: float) -> Vector2:
	var center := rect.get_center()
	if not p_screen.is_finite():
		return center
	var half := (rect.size * 0.5 - Vector2(margin, margin)).max(Vector2.ZERO)
	var d := p_screen - center
	if behind_camera:
		d = -d
	elif absf(d.x) <= half.x and absf(d.y) <= half.y:
		return p_screen
	if d.length() < 1e-9:
		d = Vector2.DOWN   # straight behind the camera: below the screen
	var t := INF
	if absf(d.x) > 1e-9:
		t = minf(t, half.x / absf(d.x))
	if absf(d.y) > 1e-9:
		t = minf(t, half.y / absf(d.y))
	return center + d * t


func _process(delta: float) -> void:
	if pool == null or pool.paused:
		return
	_pulse_t = fmod(_pulse_t + delta, 1.0 / PULSE_HZ)
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 1.0 / REFRESH_HZ
		refresh()


## How the arrow `ind` (an indicators row) is drawn on the screen `rect`, `pulse` (0..1) of the way to
## the top of its pulse (only a telling arrow pulses). Pure; _draw and the layout checks share it.
## Returns {"center", "radius", "pointer" (the triangle: tip and two base corners), "glyph" (Rect2),
## "mark_at" (the "!"'s center), "mark_h" (its height, 0 without one), "badge" (Rect2 around the
## badge and its pointer), "mark" (Rect2 around the "!", empty without one)}.
static func arrow_shape(ind: Dictionary, pulse: float, rect: Rect2) -> Dictionary:
	var c: Vector2 = ind.position
	var dir: Vector2 = ind.direction
	var grow := 1.0 + (PULSE_GROW * clampf(pulse, 0.0, 1.0) if ind.telling else 0.0)
	var r := BADGE_RADIUS_PX * grow
	# The pointer: a triangle from the badge's rim outward, toward the creature.
	var side := dir.orthogonal() * POINTER_HALF_W_PX * grow
	var base := c + dir * (r * 0.6)
	var pointer := PackedVector2Array([c + dir * (r + POINTER_PX * grow), base + side, base - side])
	var badge := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	for p in pointer:
		badge = badge.expand(p)
	var g := GLYPH_PX * grow
	var out := {"center": c, "radius": r, "pointer": pointer, "glyph": Rect2(c - Vector2(g, g) * 0.5, Vector2(g, g)),
		"mark_at": c, "mark_h": 0.0, "badge": badge, "mark": Rect2()}
	if not ind.telling:
		return out
	var h := MARK_PX * grow
	var half := Vector2(h * MARK_BAR_SHARE * 0.5 + MARK_OUTLINE_PX, h * 0.5 + MARK_OUTLINE_PX)
	# The mark's center sits far enough along -dir that its upright box clears the badge.
	var at := c - dir * (r + MARK_GAP_PX + absf(dir.x) * h * 0.3 + absf(dir.y) * h * 0.5)
	out.mark_at = at
	out.mark_h = h
	out.mark = Rect2(at - half, half * 2.0)
	return out


func _draw() -> void:
	var pulse := 0.5 - 0.5 * cos(_pulse_t * PULSE_HZ * TAU)
	var rect := get_viewport_rect()
	drawn.clear()
	for ind in indicators:
		var shape := arrow_shape(ind, pulse, rect)
		draw_colored_polygon(shape.pointer, THREAT_COLOR)
		draw_circle(shape.center, shape.radius, BADGE_COLOR)
		draw_arc(shape.center, shape.radius, 0.0, TAU, 40, THREAT_COLOR, 4.0 if ind.telling else 3.0, true)
		HudIcon.draw_shape(self, ind.glyph, shape.glyph, GLYPH_COLOR, BADGE_COLOR)
		if shape.mark_h > 0.0:
			_draw_mark(shape.mark_at, shape.mark_h)
		drawn.append({"id": ind.id, "badge": shape.badge, "mark": shape.mark})


## An upright "!" of height `h` centered on `at`: a bar, a gap and a dot, outlined in the badge's colour.
func _draw_mark(at: Vector2, h: float) -> void:
	var w := h * MARK_BAR_SHARE
	var top := at.y - h * 0.5
	var bar := Rect2(at.x - w * 0.5, top, w, h - w * 1.7)
	var dot := Vector2(at.x, at.y + h * 0.5 - w * 0.5)
	var o := MARK_OUTLINE_PX
	draw_rect(bar.grow(o), BADGE_COLOR)
	draw_circle(dot, w * 0.5 + o, BADGE_COLOR)
	draw_rect(bar, THREAT_COLOR)
	draw_circle(dot, w * 0.5, THREAT_COLOR)
