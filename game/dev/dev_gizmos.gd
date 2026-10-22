extends Node3D
## Debug builds only (M1 step 2): lines over the pool drawn from the rules' own numbers, so what
## the player sees can be checked against what the resolver uses. Zone rings, the body circle,
## the feeding reach circle and each mouth's facing arc (green for plankton, orange for carrion).
## The debug panel toggles it. Lines ignore depth, so the floor never hides them.

const LIFT_M := 0.06
const SEGMENTS := 48
const ZONE_COLOR := Color(0.55, 0.95, 0.55)
const BODY_COLOR := Color(0.75, 0.9, 1.0)
const REACH_COLOR := Color(1.0, 1.0, 1.0)
const MOUTH_COLORS := {"plant": Color(0.55, 0.95, 0.55), "meat": Color(1.0, 0.6, 0.35)}

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
	_mesh.surface_end()


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(a, LIFT_M))
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(PlaneSpace.to_world(b, LIFT_M))


func _arc(center: Vector2, radius: float, from: float, to: float, color: Color) -> void:
	var steps := maxi(4, ceili(SEGMENTS * absf(to - from) / TAU))
	for i in steps:
		var a := lerpf(from, to, float(i) / steps)
		var b := lerpf(from, to, float(i + 1) / steps)
		_line(center + Vector2.from_angle(a) * radius, center + Vector2.from_angle(b) * radius, color)
