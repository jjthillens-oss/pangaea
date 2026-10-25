param(
    [Parameter(Mandatory = $true)]
    [string]$ReviewDirectory
)

# Creates an isolated Godot project for visual review. Run only after the GLB
# exists. The caller then launches the pinned Godot editor/import and review.
$ErrorActionPreference = 'Stop'
$assetDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$model = Join-Path $assetDirectory 'bush-2.glb'
if (-not (Test-Path -LiteralPath $model)) { throw "No GLB to review: $model" }
if (Test-Path -LiteralPath $ReviewDirectory) { throw "Use a new review directory: $ReviewDirectory" }
$destination = (New-Item -ItemType Directory -Path $ReviewDirectory).FullName
Copy-Item -LiteralPath $model -Destination (Join-Path $destination 'bush-2.glb')

@'
config_version=5

[application]
config/name="Pangaea bush 2 isolated review"

[display]
window/size/viewport_width=1024
window/size/viewport_height=768

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $destination 'project.godot') -Encoding utf8

@'
extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://bush-2.glb") as PackedScene
	if packed == null:
		push_error("Bush GLB did not import")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(packed.instantiate())
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(2.6, 2.2, -3.3)
	camera.look_at(Vector3(0.0, 0.82, 0.0))
	camera.current = true
	var environment := WorldEnvironment.new()
	stage.add_child(environment)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.56, 0.60)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.73, 0.76, 0.78)
	env.ambient_light_energy = 0.78
	environment.environment = env
	var key := OmniLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-2.8, 3.6, -3.4)
	key.light_energy = 2.0
	key.omni_range = 12.0
	var fill := OmniLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(3.0, 2.0, 1.8)
	fill.light_energy = 0.75
	fill.omni_range = 9.0
	for _frame in 10:
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("No rendered Godot image; visual gate remains pending")
		quit(2)
		return
	var error := image.save_png("res://godot-review.png")
	if error != OK:
		push_error("Review capture failed: %s" % error_string(error))
		quit(3)
		return
	print("Bush review image: %dx%d" % [image.get_width(), image.get_height()])
	quit()
'@ | Set-Content -LiteralPath (Join-Path $destination 'review.gd') -Encoding utf8

Write-Output $destination
