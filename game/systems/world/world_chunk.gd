class_name WorldChunk
extends RefCounted
## One chunk of the endless world (S1): every tile object whose centre lies in the 32 x 32 tm square
## `key` at size `size`, as WorldGen.chunk makes it. Plain data; the streaming block loads it into
## the arena, the ecology region and the site table, and the scene draws it from its events.
##
## All x, y below are ABSOLUTE tm at `size`, float64. Lists are in canonical order: tile (ty, tx),
## then list index (docs/s1/s1-interfaces.md, section 3.6).

var key := Vector2i.ZERO
var size := 1
## {id, x, y, r, kind: "shell"|"landmark"|"set_piece", asset, yaw_deg, scale, tint}
var shells: Array[Dictionary] = []
## {id, x, y, radius, capacity, growth_rate, tile: Vector2i, region}
var zones: Array[Dictionary] = []
## {id, species, x, y, heading, territory: {} or {x, y, radius}, reach: {x, y, radius},
##  chunks: Array[Vector2i], sizes: Array[int], tile: Vector2i}
var sites: Array[Dictionary] = []
## {id, x, y, model, dressing, tile}: the visual; its collider is a "landmark" shell
var anchors: Array[Dictionary] = []
## {id, kind, x, y, tile}: rare set pieces; their colliders are "set_piece" shells
var places: Array[Dictionary] = []


## SHA-256 of the chunk's JSON (sorted keys, full precision): equal digests, equal chunks.
func digest() -> String:
	return JSON.stringify(to_dict(), "", true, true).sha256_text()


## {key: [cx, cy], size, shells, zones, sites, anchors, places}, every Vector2i as [x, y].
func to_dict() -> Dictionary:
	return {"key": [key.x, key.y], "size": size, "shells": _plain(shells), "zones": _plain(zones),
		"sites": _plain(sites), "anchors": _plain(anchors), "places": _plain(places)}


## A JSON-ready copy: Vector2i becomes [x, y], containers are copied, other values kept.
static func _plain(value: Variant) -> Variant:
	if value is Vector2i:
		return [value.x, value.y]
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _plain(value[k])
		return out
	if value is Array:
		var out := []
		for v in value:
			out.append(_plain(v))
		return out
	return value
