class_name PlayerCellView
extends Node3D
## The player's cell in the pool (M1 step 2): the sample cell body with the genome's parts placed
## by PartPlacement, drawn between sim ticks and animated in code (no rig until step 5).
## It only draws: position, heading and every reaction come from the sim and its events.
##
## The root carries the exact interpolated position and yaw. Bank, gulp, head-shake and the death
## pose go on Pivot, so they never move the point the camera and tests read.

const PART_SCENES := {
	"mouth_filter": preload("res://assets/export/part_mouth_filter.glb"),
	"mouth_jaw": preload("res://assets/export/part_mouth_jaw.glb"),
	"flagellum": preload("res://assets/export/part_flagellum.glb"),
	"eye_spot": preload("res://assets/export/part_eye_spot.glb"),
}
## Baked parts of the sample cell that the genome's parts replace (GLB contract names that
## test_assets checks). Its eyes and pupils stay.
const HIDDEN_MODEL_NODES: Array[NodePath] = [^"Body/Mouth", ^"Body/Flagellum"]

const WAG_DEG := 15.0
const WAG_HZ_REST := 2.0
const WAG_HZ_TOP := 6.0
const WAG_REST_SHARE := 0.35       ## wag amplitude at rest, as a share of the full wag
const STARVING_WAG_SHARE := 0.5    ## starving cells wag slower
const BANK_DEG := 8.0
const BANK_HALF_LIFE_S := 0.08
const GULP_S := 0.2
const GULP_SCALE := 1.08
const SHAKE_S := 0.3
const SHAKE_DEG := 6.0
const GHOST_S := 0.15
const GHOST_END_SCALE := 0.35
const TINT_FADE_S := 0.4
const STARVING_TINT := Color(0.42, 0.44, 0.47, 0.55)
const DEAD_ROLL_DEG := 160.0
const DEAD_SINK_M := 0.2
const DEAD_POSE_S := 1.2
const FX_LIFT_M := 0.15          ## the burst starts a little above the mouth, so the body never hides it
const FX_COLORS := {"plant": Color(0.62, 0.95, 0.55), "meat": Color(0.85, 0.42, 0.33)}
const WARM_UP_DEPTH_M := 5.0     ## the shader warm-up plays this far under the floor, out of sight

var _top_speed := 1.0
var _turn_rate := 1.0
var _mouths: Array[Dictionary] = []   ## Phenotype.mouths: {"type", "angle", "arc", "diet"}
var _wag_nodes: Array[Node3D] = []
var _wag_phase := 0.0
var _speed := 0.0
var _turn := 0.0
var _bank := 0.0
var _gulp_t := -1.0
var _shake_t := -1.0
var _starving := false
var _tint := 0.0
var _dead := false
var _dead_t := 0.0
var _overlay := StandardMaterial3D.new()

@onready var _pivot: Node3D = %Pivot


## Builds the parts of a genome. Each part becomes a child of Parts with metadata "part_id",
## "part_type", "part_angle" and "part_scale". A type with no model yet (cilia and spikes come in
## step 4) gets an empty marker, so the children still match the genome one to one.
func build(genome: Genome, phenotype: Phenotype) -> void:
	_top_speed = maxf(phenotype.speed, 0.01)
	_turn_rate = maxf(phenotype.turn_rate, 0.01)
	_mouths = phenotype.mouths.duplicate()
	var model: Node3D = %Model
	for path in HIDDEN_MODEL_NODES:
		var baked := model.get_node_or_null(path) as Node3D
		if baked != null:
			baked.visible = false
	var parts: Node3D = %Parts
	for child in parts.get_children():
		parts.remove_child(child)
		child.queue_free()
	_wag_nodes.clear()
	for part in genome.parts:
		var type := str(part.get("type", ""))
		var angle := float(part.get("angle", 0.0))
		var scale := float(part.get("scale", 1.0))
		var holder := Node3D.new()
		holder.name = str(part.get("id", "part"))
		holder.transform = PartPlacement.transform_for(angle, type, scale)
		holder.set_meta("part_id", str(part.get("id", "")))
		holder.set_meta("part_type", type)
		holder.set_meta("part_angle", angle)
		holder.set_meta("part_scale", scale)
		var packed: PackedScene = PART_SCENES.get(type)
		if packed != null:
			var model_node: Node3D = packed.instantiate()
			holder.add_child(model_node)
			if type == "flagellum":
				_wag_nodes.append(model_node)
		parts.add_child(holder)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(STARVING_TINT, 0.0)
	_apply_overlay(null)


## The part nodes, in genome order.
func part_nodes() -> Array[Node]:
	return (%Parts as Node3D).get_children()


## Moves the view to the sim's motion, `fraction` of the way from the previous tick to the
## current one (fraction 1 is exactly the current tick).
func show_motion(motion: Locomotion.MotionState, fraction: float) -> void:
	var p := motion.prev_position.lerp(motion.position, fraction)
	var heading := lerp_angle(motion.prev_heading, motion.heading, fraction)
	position = PlaneSpace.to_world(p)
	rotation = Vector3(0.0, PlaneSpace.yaw_for_heading(heading), 0.0)
	_speed = motion.position.distance_to(motion.prev_position) / PoolSim.DT
	_turn = angle_difference(motion.prev_heading, motion.heading) / PoolSim.DT


## Snaps the view to the sim with no motion to animate between ticks (spawn, respawn, teleport).
func place(motion: Locomotion.MotionState) -> void:
	show_motion(motion, 1.0)
	_speed = 0.0
	_turn = 0.0
	_bank = 0.0


func set_starving(starving: bool) -> void:
	_starving = starving


func set_dead(dead: bool) -> void:
	_dead = dead
	if not dead:
		_dead_t = 0.0


## A meal: the cell gulps.
func gulp() -> void:
	_gulp_t = 0.0


## A diet refusal: a small shake of the head.
func head_shake() -> void:
	_shake_t = 0.0


## World position of the mouth that eats `kind` ("plant" or "meat"), or the front of the cell.
func mouth_position(kind: String) -> Vector3:
	var local := PartPlacement.surface_point(0.0)
	for mouth in _mouths:
		if mouth.diet == kind:
			local = PartPlacement.transform_for(mouth.angle, mouth.type).origin
			break
	return _pivot.to_global(local)


## A ghost of the eaten item flies from where it was into the mouth, and the eat burst plays.
func swallow(from: Vector3, kind: String, mesh: Mesh) -> void:
	if not is_inside_tree():
		return
	var mouth := mouth_position(kind)
	_burst(mouth + Vector3.UP * FX_LIFT_M, FX_COLORS.get(kind, Color.WHITE))
	if mesh != null:
		_ghost(mesh, from, mouth)


## Plays the eat burst and draws each mesh once, out of sight under the floor, so their shaders
## are ready before the first real meal. A real meal restarts the burst at the mouth.
func warm_up(meshes: Array[Mesh]) -> void:
	if not is_inside_tree():
		return
	var hidden := global_position + Vector3.DOWN * WARM_UP_DEPTH_M
	_burst(hidden, Color.WHITE)
	for mesh in meshes:
		if mesh != null:
			_ghost(mesh, hidden, hidden)


func _burst(at: Vector3, color: Color) -> void:
	var fx: CPUParticles3D = %EatFx
	fx.global_position = at
	fx.color = color
	fx.restart()
	fx.emitting = true


func _ghost(mesh: Mesh, from: Vector3, to: Vector3) -> void:
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(ghost)
	ghost.global_position = from
	var tween := ghost.create_tween().set_parallel()
	tween.tween_property(ghost, "global_position", to, GHOST_S).set_ease(Tween.EASE_IN)
	tween.tween_property(ghost, "scale", Vector3.ONE * GHOST_END_SCALE, GHOST_S)
	tween.chain().tween_callback(ghost.queue_free)


func _process(delta: float) -> void:
	var speed_share := clampf(_speed / _top_speed, 0.0, 1.0)
	# Flagellum wag: faster and wider with speed, slower while starving, still once dead.
	var hz := lerpf(WAG_HZ_REST, WAG_HZ_TOP, speed_share) * (STARVING_WAG_SHARE if _starving else 1.0)
	if not _dead:
		_wag_phase = fmod(_wag_phase + TAU * hz * delta, TAU)
	var wag := deg_to_rad(WAG_DEG) * lerpf(WAG_REST_SHARE, 1.0, speed_share) * sin(_wag_phase)
	for i in _wag_nodes.size():
		_wag_nodes[i].rotation.y = wag * (1.0 if i % 2 == 0 else -1.0)
	# Bank into turns, smoothed so tick-to-tick steps do not jitter.
	var want_bank := -clampf(_turn / _turn_rate, -1.0, 1.0) * deg_to_rad(BANK_DEG) * speed_share
	_bank = lerpf(want_bank, _bank, pow(0.5, delta / BANK_HALF_LIFE_S))
	var shake := 0.0
	if _shake_t >= 0.0:
		_shake_t += delta
		var k := _shake_t / SHAKE_S
		shake = deg_to_rad(SHAKE_DEG) * sin(k * TAU * 1.5) * (1.0 - k) if k < 1.0 else 0.0
		if k >= 1.0:
			_shake_t = -1.0
	var gulp_scale := 1.0
	if _gulp_t >= 0.0:
		_gulp_t += delta
		var g := _gulp_t / GULP_S
		gulp_scale = 1.0 + (GULP_SCALE - 1.0) * sin(clampf(g, 0.0, 1.0) * PI)
		if g >= 1.0:
			_gulp_t = -1.0
	if _dead:
		_dead_t = minf(_dead_t + delta / DEAD_POSE_S, 1.0)
	var pose := smoothstep(0.0, 1.0, _dead_t)
	_pivot.rotation = Vector3(0.0, shake, _bank + deg_to_rad(DEAD_ROLL_DEG) * pose)
	_pivot.position = Vector3(0.0, -DEAD_SINK_M * pose, 0.0)
	_pivot.scale = Vector3.ONE * gulp_scale
	_update_tint(delta)


## Greys the cell while it starves (or is dead) with one shared overlay material.
func _update_tint(delta: float) -> void:
	var want := 1.0 if _starving or _dead else 0.0
	if is_equal_approx(_tint, want):
		return
	_tint = move_toward(_tint, want, delta / TINT_FADE_S)
	_overlay.albedo_color = Color(STARVING_TINT, STARVING_TINT.a * _tint)
	_apply_overlay(_overlay if _tint > 0.0 else null)


func _apply_overlay(material: Material) -> void:
	for root: Node in [%Model, %Parts]:
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).material_overlay = material
