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

var main: Node
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
	for c in sim.creatures.creatures:
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
			_lane(mem.lane)


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(a, LIFT_M))
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(b, LIFT_M))


## A strike lane's rectangle (CreatureBrain.strike_lane): from its origin forward to its length,
## its half-width either side.
func _lane(lane: Dictionary) -> void:
	var forward := Vector2.from_angle(float(lane.heading))
	var side := forward.orthogonal() * float(lane.half_width)
	var a: Vector2 = lane.origin + side
	var b: Vector2 = lane.origin - side
	var far := forward * float(lane.length)
	_line(a, b, LANE_COLOR)
	_line(a, a + far, LANE_COLOR)
	_line(b, b + far, LANE_COLOR)
	_line(a + far, b + far, LANE_COLOR)


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


func _arc(center: Vector2, radius: float, from: float, to: float, color: Color) -> void:
	var steps := maxi(4, ceili(SEGMENTS * absf(to - from) / TAU))
	for i in steps:
		var a := lerpf(from, to, float(i) / steps)
		var b := lerpf(from, to, float(i + 1) / steps)
		_line(center + Vector2.from_angle(a) * radius, center + Vector2.from_angle(b) * radius, color)
