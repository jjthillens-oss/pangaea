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
## {id, x, y, r, kind: "shell"|"landmark"|"set_piece", asset, yaw_deg, scale, tint}; scale is the
## mesh's at this size (x bu_to_tm(size), BP-16)
var shells: Array[Dictionary] = []
## {id, x, y, radius, capacity, growth_rate, tile: Vector2i, region}; capacity is the size's (a
## "thin" zone's x second_size.zone_thin_share at a band's second size)
var zones: Array[Dictionary] = []
## {id, species, x, y, heading, territory: {} or {x, y, radius}, reach: {x, y, radius},
##  chunks: Array[Vector2i], sizes: Array[int], tile: Vector2i}; a two-post site (S2) also has
##  posts: [{x, y, heading, territory}] x 2 (the first is the home), its reach their union disc, and a
##  one-post site has no posts key, so its digest is S1's
var sites: Array[Dictionary] = []
## {id, x, y, model, dressing, tile}: the visual; its collider is a "landmark" shell
var anchors: Array[Dictionary] = []
## {id, kind, x, y, tile}: rare set pieces; their colliders are "set_piece" shells
var places: Array[Dictionary] = []
## S3 (spine 5.6): {id "m_...", key "<tile id>/<site id>", species, x, y, tile, radius (tm), energy}:
## the morsel sites live at `size`, food rather than creatures; absent from to_dict() when empty, so
## a chunk without any keeps its S1 and S2 digest
var morsel_sites: Array[Dictionary] = []


## SHA-256 of the chunk's JSON (sorted keys, full precision): equal digests, equal chunks.
func digest() -> String:
	return JSON.stringify(to_dict(), "", true, true).sha256_text()


## {key: [cx, cy], size, shells, zones, sites, anchors, places, morsel_sites?}, every Vector2i as [x, y].
func to_dict() -> Dictionary:
	var out := {"key": [key.x, key.y], "size": size, "shells": _plain(shells), "zones": _plain(zones),
		"sites": _plain(sites), "anchors": _plain(anchors), "places": _plain(places)}
	if not morsel_sites.is_empty():
		out["morsel_sites"] = _plain(morsel_sites)
	return out


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
