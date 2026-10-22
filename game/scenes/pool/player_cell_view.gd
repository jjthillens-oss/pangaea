class_name PlayerCellView
extends Node3D
## The player's cell in the pool (M1 step 2): the sample cell body with the genome's parts placed
## by PartPlacement, drawn between sim ticks and animated in code (no rig until step 5).
## It only draws: position, heading and every reaction come from the sim and its events.
##
## The root carries the exact interpolated position and yaw. Bank, gulp, head-shake, the hurt
## flinch and the death pose go on Pivot, so they never move the point the camera and tests read.
## One overlay (cell_overlay.gdshader) greys the cell while it starves or is dead, flashes it red
## when it is hurt and draws the soft rim of shelter (M1 step 3).

const PART_SCENES := {
	"mouth_filter": preload("res://assets/export/part_mouth_filter.glb"),
	"mouth_jaw": preload("res://assets/export/part_mouth_jaw.glb"),
	"flagellum": preload("res://assets/export/part_flagellum.glb"),
	"eye_spot": preload("res://assets/export/part_eye_spot.glb"),
	"spike": preload("res://assets/export/part_spike.glb"),
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
## A hit on the cell (M1 step 3): a red flash fading over HURT_S and a flinch, a quick squash and
## recoil of the body, over FLINCH_S. PROPOSED, view only.
const HURT_S := 0.15
const HURT_TINT := Color(0.93, 0.2, 0.2, 0.75)   ## below about 0.6 alpha the cyan cell turns grey, not red
const FLINCH_S := 0.15
const FLINCH_SQUASH := 0.15
const FLINCH_BACK_M := 0.08
## Shelter (M1 step 3): a soft rim pulsing once a second, never above alpha 0.25, so it never flashes.
const SHELTER_RIM := Color(0.62, 0.98, 1.0)
const SHELTER_ALPHA_MAX := 0.25
const SHELTER_ALPHA_MIN := 0.1
const SHELTER_HZ := 1.0
const SHELTER_FADE_S := 0.3
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
var _hurt_t := -1.0
var _sheltered := false
var _shelter := 0.0
var _shelter_phase := 0.0
var _overlay := ShaderMaterial.new()
var _overlay_on := false
var _warm_overlay := 0   ## frames left to draw the overlay unseen, so its shader is ready before play

@onready var _pivot: Node3D = %Pivot


## Builds the parts of a genome. Each part becomes a child of Parts with metadata "part_id",
## "part_type", "part_angle" and "part_scale". A type with no model yet (cilia come in step 4) gets
## an empty marker, so the children still match the genome one to one.
func build(genome: Genome, phenotype: Phenotype) -> void:
	_top_speed = maxf(phenotype.speed, 0.01)
	_turn_rate = maxf(phenotype.turn_rate, 0.01)
	_mouths = phenotype.mouths.duplicate()
	_pivot = %Pivot   # also set here, so a view built outside the tree (in tests) can animate
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
	_overlay.shader = preload("res://game/scenes/pool/cell_overlay.gdshader")
	_overlay_on = false
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


## A hit on the cell: a red flash and a flinch.
func hurt() -> void:
	_hurt_t = 0.0


## Shelter after a respawn or a start (the sim's grace): a soft pulsing rim while it lasts.
func set_sheltered(sheltered: bool) -> void:
	_sheltered = sheltered


## The overlay's current colours, for tests: {"tint": Color, "rim": Color}.
func overlay_colors() -> Dictionary:
	var none := Color(0.0, 0.0, 0.0, 0.0)
	var tint = _overlay.get_shader_parameter("tint")
	var rim = _overlay.get_shader_parameter("rim")
	return {"tint": tint if tint is Color else none, "rim": rim if rim is Color else none}


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
	_warm_overlay = 2
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
	var flinch := 0.0
	if _hurt_t >= 0.0:
		_hurt_t += delta
		flinch = sin(PI * clampf(_hurt_t / FLINCH_S, 0.0, 1.0))
		if _hurt_t >= maxf(HURT_S, FLINCH_S):
			_hurt_t = -1.0
	var pose := smoothstep(0.0, 1.0, _dead_t)
	_pivot.rotation = Vector3(0.0, shake, _bank + deg_to_rad(DEAD_ROLL_DEG) * pose)
	_pivot.position = Vector3(0.0, -DEAD_SINK_M * pose, FLINCH_BACK_M * flinch)
	var squash := 1.0 - FLINCH_SQUASH * flinch
	_pivot.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash)) * gulp_scale
	_update_overlay(delta)


## Greys the cell while it starves (or is dead), flashes it red when hurt and rims it while
## sheltered, with one overlay material on every mesh; no overlay at all when none applies.
func _update_overlay(delta: float) -> void:
	var want := 1.0 if _starving or _dead else 0.0
	_tint = move_toward(_tint, want, delta / TINT_FADE_S)
	_shelter = move_toward(_shelter, 1.0 if _sheltered and not _dead else 0.0, delta / SHELTER_FADE_S)
	_shelter_phase = fmod(_shelter_phase + TAU * SHELTER_HZ * delta, TAU) if _shelter > 0.0 else 0.0
	# Eased out (1 - k^2), so the first frames after a hit show it at nearly full red.
	var flash := 1.0 - pow(_hurt_t / HURT_S, 2.0) if _hurt_t >= 0.0 and _hurt_t < HURT_S else 0.0
	var tint := Color(STARVING_TINT, STARVING_TINT.a * _tint)
	if flash > 0.0:
		tint = Color(tint.lerp(HURT_TINT, flash), maxf(tint.a, HURT_TINT.a * flash))
	var pulse := lerpf(SHELTER_ALPHA_MIN, SHELTER_ALPHA_MAX, 0.5 - 0.5 * cos(_shelter_phase))
	var rim := Color(SHELTER_RIM, pulse * _shelter)
	_overlay.set_shader_parameter("tint", tint)
	_overlay.set_shader_parameter("rim", rim)
	var on := tint.a > 0.0 or rim.a > 0.0 or _warm_overlay > 0
	_warm_overlay = maxi(_warm_overlay - 1, 0)
	if on != _overlay_on:
		_overlay_on = on
		_apply_overlay(_overlay if on else null)


func _apply_overlay(material: Material) -> void:
	for root: Node in [%Model, %Parts]:
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).material_overlay = material
