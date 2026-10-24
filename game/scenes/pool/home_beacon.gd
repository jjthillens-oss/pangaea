class_name HomeBeacon
extends Node3D
## The home beacon (S3, docs/s3/s3-view.md 6.5, V3-8; D-112): art's tall glass marker under home,
## the absolute origin, in endless mode at every size. It is a WorldSpace leaf (no apply_growth), so
## S2's rule divides its position and scale by f at each growth, and its top stays at
## TOP_BU / 1.6^(n - 1) tm with no code of its own. Its materials are dimmed like the cradle ring's.

const SCENE := "res://assets/export/home_beacon.glb"
const TOP_BU := -12.71                      ## assets/records/home_beacon.json top_bu
const DIM := 0.5                            ## linear albedo factor (V3-6, V3-8)

var _model: Node3D


func _init() -> void:
	name = "HomeBeacon"


## The beacon's top (tm) at size `n`.
static func top_tm(n: int) -> float:
	return TOP_BU / WorldConfig.tm_to_am(n)


## Puts the beacon at home in `world`'s frame now, at size `n`'s scale; loads the model the first time.
func place(world: WorldStream, n: int) -> void:
	if _model == null and ResourceLoader.exists(SCENE):
		_model = (load(SCENE) as PackedScene).instantiate() as Node3D
		_model.name = "Model"
		CradleView.dim_materials(_model, DIM)
		for g: Node in _model.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_model)
	position = PlaneSpace.to_world(world.local_of_abs(0.0, 0.0), 0.0)
	scale = Vector3.ONE / WorldConfig.tm_to_am(n)


## The model's merged AABB in this node's frame (tests).
func model_aabb() -> AABB:
	return CradleView.aabb_under(self)
