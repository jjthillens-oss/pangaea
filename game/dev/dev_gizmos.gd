extends Node3D
## Debug builds only (M1 step 2): lines over the pool drawn from the rules' own numbers, so what
## the player sees can be checked against what the resolver uses. Zone rings, the body circle,
## the feeding reach circle and each mouth's facing arc (green for plankton, orange for carrion).
## The debug panel toggles it. Lines ignore depth, so the rim and art's decor never hide them.
##
## M1 step 3 adds the creatures' AI (plan section 16), from the brain's own memory and helpers:
## each sight cone (range and field of view, coloured by state) and near-sense circle; the leash
## disc the sim clamps the body to (CreatureBrain.leash_disc), plus a rammer's territory and,
## dashed, the ring past which a target cancels its puff; the lair or home with a heading tick; a
## line to where it remembers its target (belief, not truth), dashed once that memory is older
## than TARGET_STALE_S; the strike lane from tell entry until recovery; the checkpoint's
## respawn_clear_m and spawn_safe_m circles; and the zoom-max camera view around the cell
## (ViewFootprint).
##
## S1 adds the endless sea's chunk layer (show_chunks, the debug panel's Chunk gizmo button; docs/
## s1/s1-content.md 6.14), lower than the rest: the loaded chunks' squares (grey), the view set's
## (white), the tile edges (cream), rings round the cell at the stream's wake, sleep, food, load and
## unload distances, each awake creature's reach disc and a cross at each sleeper (chunk_layer()).
## The AI layer draws the awake creatures only. Everything is drawn from sim-local positions every
## frame, so a rebase needs nothing.
##
## S2 (docs/s2/s2-view.md 9) adds, to the AI layer, a cross at each post of a creature with two
## posts (B.7; the leash disc drawn is already their union, D-82) and, for each remnant, a grey
## cross and a line along the way it flees, straight away from the cell (growth_layer()).
##
## S3 (docs/s3/s3-view.md 12) adds, to the AI layer, a hazard's thread capsule and, dashed, its drift
## path, and the lane a channel lurker strikes down from its lair (habit_layer()).

const LIFT_M := 0.06
const SEGMENTS := 48
const ZONE_COLOR := Color(0.55, 0.95, 0.55)
const BODY_COLOR := Color(0.75, 0.9, 1.0)
const REACH_COLOR := Color(1.0, 1.0, 1.0)
const MOUTH_COLORS := {"plant": Color(0.55, 0.95, 0.55), "meat": Color(1.0, 0.6, 0.35)}
## Sight cones by brain state; a state not listed draws white.
const STATE_COLORS := {
	CreatureBrain.REST: Color(0.6, 0.6, 0.6), CreatureBrain.WANDER: Color(0.4, 0.6, 1.0),
	CreatureBrain.FORAGE: Color(0.45, 0.9, 0.45), CreatureBrain.NOTICE: Color(1.0, 0.9, 0.3),
	CreatureBrain.CHASE: Color(1.0, 0.6, 0.2), CreatureBrain.ATTACK: Color(1.0, 0.25, 0.25),
	CreatureBrain.FLEE: Color(0.75, 0.45, 1.0),
}
const NEAR_ALPHA := 0.55            ## the near-sense circle is the cone's colour, fainter
const LEASH_COLOR := Color(1.0, 0.4, 0.7)
const TERRITORY_COLOR := Color(0.95, 0.8, 0.4)
const HOME_COLOR := Color(1.0, 1.0, 1.0)
const HOME_MARK_M := 0.3            ## half the lair cross
const HOME_TICK_M := 0.9            ## the heading tick's length
const TARGET_COLOR := Color(1.0, 0.95, 0.75)
const TARGET_STALE_S := 0.2         ## older memories draw dashed
const DASH_M := 0.25
const LANE_COLOR := Color(1.0, 0.2, 0.2)
const CHECKPOINT_COLORS := {"respawn_clear_m": Color(0.62, 0.98, 1.0), "spawn_safe_m": Color(0.35, 0.7, 0.8)}
const FOOTPRINT_COLOR := Color(1.0, 1.0, 0.6, 0.7)
const CHUNK_LIFT_M := 0.02
const CHUNK_COLOR := Color(0.6, 0.6, 0.6)
const VIEW_SET_COLOR := Color(1.0, 1.0, 1.0)
const TILE_COLOR := Color(0.96, 0.92, 0.82, 0.55)
## The stream's rings round the cell (WorldStream.rings, tm), each in its own colour.
const RING_COLORS := {
	"wake": Color(0.45, 0.9, 0.45), "sleep": Color(0.4, 0.6, 1.0), "food": Color(0.81, 0.91, 0.42),
	"load": Color(1.0, 0.75, 0.35), "unload": Color(1.0, 0.4, 0.4),
}
const SITE_REACH_COLOR := Color(0.95, 0.55, 0.9, 0.7)
const SLEEPER_COLOR := Color(0.7, 0.75, 1.0)
const SLEEPER_MARK_M := 0.4
const POST_MARK_M := 0.3            ## half a post's cross, as the lair's
const REMNANT_COLOR := Color(0.6, 0.6, 0.6)
const REMNANT_MARK_M := 0.4
const REMNANT_FLEE_M := 1.5         ## the flee line's length
const CAPSULE_COLOR := Color(1.0, 0.45, 0.6)
const DRIFT_COLOR := Color(0.8, 0.7, 1.0)
const CHANNEL_COLOR := Color(0.55, 0.85, 1.0)
const DRIFT_POINTS := 48            ## points along a drift path, over its longer period
const CHANNEL_PREY_RADIUS := 0.5    ## the prey radius the channel lane is drawn for

var main: Node
## The endless sea's chunk layer (the debug panel's Chunk gizmo button).
var show_chunks := false
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func attach(p_main: Node) -> void:
	main = p_main
	visible = false
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 10
	var lines := MeshInstance3D.new()
	lines.name = "Lines"
	lines.mesh = _mesh
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	var pool: PoolScene = main.pool if main != null else null
	if not visible or pool == null or pool.sim == null:
		return
	var sim := pool.sim
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for z in sim.region.zones:
		_arc(z.center, z.radius, 0.0, TAU, ZONE_COLOR)
	var p := sim.motion.position
	var reach := sim.phenotype.radius + InteractionResolver.FEED_REACH
	_arc(p, sim.phenotype.radius, 0.0, TAU, BODY_COLOR)
	_arc(p, reach, 0.0, TAU, REACH_COLOR)
	# A mouth reaches food whose center is within reach plus the food's radius, inside its arc.
	var arc_r := reach + PoolSim.MAX_FOOD_RADIUS
	for mouth in sim.phenotype.mouths:
		var color: Color = MOUTH_COLORS.get(mouth.diet, Color.WHITE)
		var from: float = sim.motion.heading + mouth.angle - mouth.arc * 0.5
		var to: float = sim.motion.heading + mouth.angle + mouth.arc * 0.5
		_line(p, p + Vector2.from_angle(from) * arc_r, color)
		_line(p, p + Vector2.from_angle(to) * arc_r, color)
		_arc(p, arc_r, from, to, color)
	if sim.creatures != null:
		_draw_ai(sim)
	if show_chunks and sim.world != null:
		_draw_chunks(sim)
	_mesh.surface_end()


func _draw_ai(sim: PoolSim) -> void:
	var fairness: Dictionary = sim.species.fairness
	var checkpoint: Vector2 = sim.checkpoint().position
	for key: String in CHECKPOINT_COLORS:
		_arc(checkpoint, float(fairness.get(key, 0.0)), 0.0, TAU, CHECKPOINT_COLORS[key])
	var view := ViewFootprint.corners(sim.motion.position, sim.layout.camera, float(sim.layout.camera.zoom_max),
		float(fairness.get("spawn_view_aspect", 16.0 / 9.0)))
	for i in view.size():
		_line(view[i], view[(i + 1) % view.size()], FOOTPRINT_COLOR)
	for c in sim.creatures.awake():
		var mem := c.brain
		if mem == null:
			continue
		var at := c.motion.position
		var viewer := sim.creatures.viewer_of(c)
		var color: Color = STATE_COLORS.get(mem.state, Color.WHITE)
		var half := float(viewer.fov) * 0.5
		var sight := float(viewer.sight)
		if half >= PI - 1e-3:
			_arc(at, sight, 0.0, TAU, color)
		else:
			_line(at, at + Vector2.from_angle(c.motion.heading - half) * sight, color)
			_line(at, at + Vector2.from_angle(c.motion.heading + half) * sight, color)
			_arc(at, sight, c.motion.heading - half, c.motion.heading + half, color)
		_arc(at, float(viewer.near), 0.0, TAU, Color(color, NEAR_ALPHA))
		var leash := CreatureBrain.leash_disc(mem)
		_arc(leash.center, leash.radius, 0.0, TAU, LEASH_COLOR)
		if mem.behavior == CreatureBrain.TERRITORIAL:
			_arc(mem.territory_center, mem.territory_r, 0.0, TAU, TERRITORY_COLOR)
			_dashed_arc(mem.territory_center, mem.territory_r + float(mem.cfg.territory_exit_m), TERRITORY_COLOR)
		_line(mem.home - Vector2(HOME_MARK_M, HOME_MARK_M), mem.home + Vector2(HOME_MARK_M, HOME_MARK_M), HOME_COLOR)
		_line(mem.home - Vector2(HOME_MARK_M, -HOME_MARK_M), mem.home + Vector2(HOME_MARK_M, -HOME_MARK_M), HOME_COLOR)
		_line(mem.home, mem.home + Vector2.from_angle(mem.home_heading) * HOME_TICK_M, HOME_COLOR)
		if not mem.target.is_empty() and mem.seen.has(mem.target):
			var seen: Dictionary = mem.seen[mem.target]
			var age_s := (sim.tick - int(seen.tick)) / float(CreatureBrain.TICKS_PER_SECOND)
			if age_s > TARGET_STALE_S:
				_dashed(at, seen.position, TARGET_COLOR)
			else:
				_line(at, seen.position, TARGET_COLOR)
		if not mem.lane.is_empty():
			_lane(mem.lane, LANE_COLOR)
	var habits := habit_layer(sim)
	for capsule: Dictionary in habits.capsules:
		_capsule(capsule.a, capsule.b, float(capsule.r), CAPSULE_COLOR)
	for path: PackedVector2Array in habits.drift_paths:
		for i in range(0, path.size(), 2):
			_line(path[i], path[(i + 1) % path.size()], DRIFT_COLOR)
	for lane: Dictionary in habits.channels:
		_lane(lane, CHANNEL_COLOR)
	var layer := growth_layer(sim)
	for at: Vector2 in layer.posts:
		_cross(at, POST_MARK_M, LEASH_COLOR)
	for r: Dictionary in layer.remnants:
		_cross(r.at, REMNANT_MARK_M, REMNANT_COLOR)
		_line(r.at, r.at + r.flee * REMNANT_FLEE_M, REMNANT_COLOR)


## What the growth marks draw, in sim-local coordinates: {"posts" (each post of each awake creature
## with two posts, in creature order), "remnants" ({at, flee}: each remnant's place and the unit way
## it flees, straight away from the cell as RemnantField.tick steers it)}. Empty lists without them.
static func growth_layer(sim: PoolSim) -> Dictionary:
	var out := {"posts": [], "remnants": []}
	if sim.creatures != null:
		for c in sim.creatures.awake():
			if c.brain != null:
				for post: Dictionary in c.brain.posts:
					out.posts.append(post.home)
	if sim.remnants != null:
		for r in sim.remnants.items:
			var away := r.motion.position - sim.motion.position
			var flee := away.normalized() if away.length() > 1e-6 else Vector2.from_angle(r.motion.heading)
			out.remnants.append({"at": r.motion.position, "flee": flee})
	return out


## What S3's habit marks draw, in sim-local coordinates, for the awake creatures in creature order:
## {"capsules" (each hazard's CreatureBrain.thread_capsule {a, b, r}), "drift_paths" (each hazard's
## DRIFT_POINTS points of drift_goal over its longer period, a closed loop), "channels" (each channel
## lurker's strike lane from its lair along its home heading)}.
static func habit_layer(sim: PoolSim) -> Dictionary:
	var out := {"capsules": [], "drift_paths": [], "channels": []}
	if sim.creatures == null:
		return out
	for c in sim.creatures.awake():
		var mem := c.brain
		if mem == null:
			continue
		if mem.behavior == CreatureBrain.HAZARD:
			out.capsules.append(CreatureBrain.thread_capsule(mem, c.motion.position, c.motion.heading, c.phenotype.radius))
			var period := maxi(mem.drift_period.x, mem.drift_period.y)
			var path := PackedVector2Array()
			for i in DRIFT_POINTS:
				path.append(CreatureBrain.drift_goal(mem, roundi(float(i) * period / DRIFT_POINTS)))
			out.drift_paths.append(path)
		if bool(sim.species.habit_of(c.species_id).get("channel", false)):
			out.channels.append(CreatureBrain.strike_lane(mem.cfg.attack, c.phenotype.radius, CHANNEL_PREY_RADIUS, mem.home,
				mem.home_heading))
	return out


func _draw_chunks(sim: PoolSim) -> void:
	var layer := chunk_layer(sim)
	for pair: Array in [[layer.tiles, TILE_COLOR], [layer.loaded, CHUNK_COLOR], [layer.view, VIEW_SET_COLOR]]:
		for square: Rect2 in pair[0]:
			_square(square, pair[1])
	for ring: String in layer.rings:
		_arc(sim.motion.position, float(layer.rings[ring]), 0.0, TAU, RING_COLORS[ring], CHUNK_LIFT_M)
	for disc: Dictionary in layer.reach:
		_arc(disc.center, float(disc.radius), 0.0, TAU, SITE_REACH_COLOR, CHUNK_LIFT_M)
	for at: Vector2 in layer.sleepers:
		_cross(at, SLEEPER_MARK_M, SLEEPER_COLOR, CHUNK_LIFT_M)


## What the chunk layer draws, in sim-local coordinates: {"loaded", "view", "tiles" (Array of Rect2:
## the loaded chunks', the view set's round the cell and the tiles' under the loaded chunks),
## "rings" (ring name -> radius in tm, RING_COLORS' rings), "reach" (each awake creature's site
## reach, {center, radius}), "sleepers" (each sleeper's position)}. Empty lists in the pool.
static func chunk_layer(sim: PoolSim) -> Dictionary:
	var out := {"loaded": [], "view": [], "tiles": [], "rings": {}, "reach": [], "sleepers": []}
	var w := sim.world
	if w == null:
		return out
	var keys := w.loaded_keys()
	for key in keys:
		out.loaded.append(_tm_square(w, key, w.chunk_tm))
	for key in w.view_set_keys(sim.motion.position):
		out.view.append(_tm_square(w, key, w.chunk_tm))
	if not keys.is_empty():
		var tile_tm := w.content.config.tile_bu * WorldConfig.bu_to_tm(w.size)
		var lo := Vector2i(keys[0])
		var hi := Vector2i(keys[0])
		for key in keys:
			lo = lo.min(key)
			hi = hi.max(key)
		for ty in range(floori(lo.y * w.chunk_tm / tile_tm), floori((hi.y + 1) * w.chunk_tm / tile_tm - 1e-6) + 1):
			for tx in range(floori(lo.x * w.chunk_tm / tile_tm), floori((hi.x + 1) * w.chunk_tm / tile_tm - 1e-6) + 1):
				out.tiles.append(_tm_square(w, Vector2i(tx, ty), tile_tm))
	for ring: String in RING_COLORS:
		if w.rings.has(ring):
			out.rings[ring] = float(w.rings[ring])
	if sim.creatures != null:
		for c in sim.creatures.awake():
			var site: Dictionary = w.sites.get(c.site_id, {})
			if not site.is_empty():
				out.reach.append({"center": site.reach.center, "radius": float(site.reach.radius)})
		for c in sim.creatures.creatures:
			if c.asleep:
				out.sleepers.append(c.motion.position)
	return out


## The local square of grid cell `key` of side `side_tm` (absolute tm, from the origin).
static func _tm_square(w: WorldStream, key: Vector2i, side_tm: float) -> Rect2:
	return Rect2(w.local_of_tm(key.x * side_tm, key.y * side_tm), Vector2.ONE * side_tm)


func _square(r: Rect2, color: Color) -> void:
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		_line(c[i], c[(i + 1) % 4], color, CHUNK_LIFT_M)


func _cross(at: Vector2, half: float, color: Color, lift := LIFT_M) -> void:
	_line(at - Vector2(half, half), at + Vector2(half, half), color, lift)
	_line(at - Vector2(half, -half), at + Vector2(half, -half), color, lift)


func _line(a: Vector2, b: Vector2, color: Color, lift := LIFT_M) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(a, lift))
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(b, lift))


## A strike lane's rectangle (CreatureBrain.strike_lane): from its origin forward to its length,
## its half-width either side.
func _lane(lane: Dictionary, color: Color) -> void:
	var forward := Vector2.from_angle(float(lane.heading))
	var side := forward.orthogonal() * float(lane.half_width)
	var a: Vector2 = lane.origin + side
	var b: Vector2 = lane.origin - side
	var far := forward * float(lane.length)
	_line(a, b, color)
	_line(a, a + far, color)
	_line(b, b + far, color)
	_line(a + far, b + far, color)


## A capsule from `a` to `b` of radius `r`: its two sides and a half circle round each end.
func _capsule(a: Vector2, b: Vector2, r: float, color: Color) -> void:
	var d := (b - a).normalized() if a.distance_to(b) > 1e-6 else Vector2.RIGHT
	var n := d.orthogonal() * r
	_line(a + n, b + n, color)
	_line(a - n, b - n, color)
	_arc(b, r, d.angle() - PI / 2.0, d.angle() + PI / 2.0, color)
	_arc(a, r, d.angle() + PI / 2.0, d.angle() + 3.0 * PI / 2.0, color)


func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	var dashes := maxi(1, floori(length / (DASH_M * 2.0)))
	for i in dashes:
		_line(a.lerp(b, (i * 2.0) / (dashes * 2.0)), a.lerp(b, (i * 2.0 + 1.0) / (dashes * 2.0)), color)


func _dashed_arc(center: Vector2, radius: float, color: Color) -> void:
	var steps := SEGMENTS * 2
	for i in range(0, steps, 2):
		var a := TAU * i / steps
		var b := TAU * (i + 1) / steps
		_line(center + Vector2.from_angle(a) * radius, center + Vector2.from_angle(b) * radius, color)


func _arc(center: Vector2, radius: float, from: float, to: float, color: Color, lift := LIFT_M) -> void:
	var steps := maxi(4, ceili(SEGMENTS * absf(to - from) / TAU))
	for i in steps:
		var a := lerpf(from, to, float(i) / steps)
		var b := lerpf(from, to, float(i + 1) / steps)
		_line(center + Vector2.from_angle(a) * radius, center + Vector2.from_angle(b) * radius, color, lift)
