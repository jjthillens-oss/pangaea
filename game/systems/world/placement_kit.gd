class_name PlacementKit
extends RefCounted
## The kit of Blender pieces the world places (game/data/placement_kit.json, S1): shells by
## footprint class, landmarks by group, rare set pieces and the two markers.
##
## T1.1 skeleton: the pinned API, empty; loading and the kit rules land with T1.3.

const DEFAULT_PATH := "res://game/data/placement_kit.json"

var load_problems := PackedStringArray()
## "fp_s" -> [lo, hi] bu (half-open; the last closed)
var classes := {}
var anchor_radius_bu := 3.0
var collide_radius_bu := 2.0
## id -> record dict
var assets := {}


static func load_from(_path: String = DEFAULT_PATH) -> PlacementKit:
	return PlacementKit.new()


func class_of(_r_bu: float) -> String:
	return ""


func fitting(_r_bu: float, _band: int) -> PackedStringArray:
	return PackedStringArray()


func landmarks(_band: int, _group: int) -> PackedStringArray:
	return PackedStringArray()


func rare_asset(_band: int, _rare_kind: String) -> String:
	return ""


func validate() -> PackedStringArray:
	return PackedStringArray(load_problems)
