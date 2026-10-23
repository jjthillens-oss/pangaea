extends SceneTree
## Hip swing shot: renders a Stage 1 body with every limb root swung by a fixed angle and saves a PNG, to look at the
## skin where a limb leaves the trunk (the hip volume the skin-volume test measures). Needs a window:
## xvfb-run godot --path prototypes/creature-lab --rendering-method forward_plus --rendering-driver vulkan \
##   --script res://tools/hip_swing_shot.gd -- --body=s1_quadruped --angle=90 --out=user://hip_90.png
## The skin is the GDScript build, so the picture shows BodyField's weights as the tests measure them.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const SpineRig := preload("res://rig/spine_rig.gd")

var body_name := "s1_quadruped"
var angle := 90.0
var out_path := "user://hip_swing.png"
var divisions := 48


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_name = kv[1]
			"angle": angle = float(kv[1])
			"out": out_path = kv[1]
			"divisions": divisions = int(kv[1])
	var desc = Lab.body(body_name)
	var arrays: Dictionary = SkinCpu.build(desc, divisions)
	var rig = SpineRig.new()
	root.add_child(rig)
	rig.setup(desc, arrays, Color(0.35, 0.55, 0.85))
	var skel: Skeleton3D = rig.skeleton
	for first in rig.limb_roots:
		skel.set_bone_pose_rotation(first, Quaternion(Vector3.RIGHT, deg_to_rad(angle)))
	_build_world(desc)
	# Two frames so the skeleton pose and the shadow map are in before the capture.
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("hip_swing_shot %s %.0f deg -> %s (%s)" % [body_name, angle, ProjectSettings.globalize_path(out_path),
			error_string(err)])
	quit(0 if err == OK else 1)


func _build_world(desc: RefCounted) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.85, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var box: AABB = desc.bounds_m()
	var camera := Camera3D.new()
	camera.fov = 40.0
	root.add_child(camera)
	# Side view from a little above, close in, so the hips fill the frame.
	var centre := box.get_center()
	var d: float = 1.25 * box.get_longest_axis_size()
	# Not inside the tree yet during _init, so set the view in one call.
	camera.look_at_from_position(centre + Vector3(1.0, 0.3, 0.25).normalized() * d, centre, Vector3.UP)
