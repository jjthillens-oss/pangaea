param(
    [Parameter(Mandatory = $true)]
    [string]$ReviewDirectory
)

$ErrorActionPreference = 'Stop'
$assetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$glb = Join-Path $assetDir 'nest-straw.glb'
if (-not (Test-Path -LiteralPath $glb)) { throw "Export is missing: $glb" }
if (Test-Path -LiteralPath $ReviewDirectory) { throw "Review directory must be new: $ReviewDirectory" }

$reviewRoot = (New-Item -ItemType Directory -Path $ReviewDirectory).FullName
Copy-Item -LiteralPath $glb -Destination (Join-Path $reviewRoot 'nest-straw.glb')

@'
config_version=5

[application]
config/name="Pangaea Nest Straw Isolated Review"
run/main_scene="res://review.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=840

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $reviewRoot 'project.godot') -Encoding utf8

@'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://review.gd" id="1"]

[node name="NestReview" type="Node3D"]
script = ExtResource("1")
'@ | Set-Content -LiteralPath (Join-Path $reviewRoot 'review.tscn') -Encoding utf8

@'
extends Node3D


func _ready() -> void:
	var packed := load("res://nest-straw.glb") as PackedScene
	assert(packed != null, "Nest GLB failed to import")
	var model := packed.instantiate()
	add_child(model)
	var bounds := _model_bounds(model)
	print("REVIEW_BOUNDS=", bounds)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(2.5, 2.5)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.71, 0.72, 0.69)
	floor_material.roughness = 1.0
	floor_mesh.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.008
	add_child(floor_node)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.71, 0.73, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.87, 0.88)
	env.ambient_light_energy = 0.85
	environment.environment = env
	add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -30, 0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-45, 140, 0)
	fill.light_energy = 0.35
	add_child(fill)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.75
	camera.position = Vector3(1.05, 0.85, 1.65)
	add_child(camera)
	camera.look_at(Vector3(0, 0.13, 0), Vector3.UP)
	camera.make_current()

	if OS.has_environment("PANGAEA_CAPTURE"):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename := OS.get_environment("PANGAEA_CAPTURE")
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(filename)
		print("REVIEW_CAPTURE=", filename, " ERROR=", error)
		get_tree().quit(0 if error == OK else 1)


func _model_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_child := child as MeshInstance3D
		var box := mesh_child.get_aabb()
		if not found:
			bounds = box
			found = true
		else:
			bounds = bounds.merge(box)
	assert(found, "Imported scene has no mesh")
	return bounds
'@ | Set-Content -LiteralPath (Join-Path $reviewRoot 'review.gd') -Encoding utf8

Write-Output $reviewRoot
