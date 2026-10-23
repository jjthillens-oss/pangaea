class_name ZoneLights
extends Node3D
## The sunlit patches (micro-world plan C7; docs/DECISIONS.md, "Microscopic world look"): soft
## shafts of cream light falling round each plankton zone, the starving tip's "sunlit patches" to
## find and the rammer's ground made visible. One disc per layout zone, 2.5 m under the swim plane,
## blended over the fluid in the Sun's colour and never in food's glow, with no fog, no depth and
## under every cue (zone_light.gdshader). The light lies round the zone's edge and leaves its feeding
## middle clear, so the cell and the food there keep their contrast. It reads the layout's zones and
## never the sim. The pool's WorldSpace shifts it across a rebase (S1), so the discs are placed in
## its frame (WorldSpace.to_frame).
##
## A growth (S2, s2-view 4.5, the growth-container contract): apply_growth re-expresses every disc in
## place (its x and z span shrink with it); set_depth_k holds the discs at DEPTH_M x k through the beat,
## so they keep their old depth on screen at frame 0. Discs of the tick's unloaded chunks retire, kept
## by zone id and adopted back when the tick loads the same zone again; a new one fades in over
## PREBLUR_S; after the settle the leftovers fade over RETIRE_S (lights do not sink) and end_growth
## frees them.
##
## Each disc wears its own copy of the material, holding where it was laid and its span then
## (anchor, laid_span): the shader lays the shafts in that frame, so neither a rebase nor a growth
## slides them across the disc (the hatch probe showed the growth's frame 0 shifting them, and a
## rebase did too); as laid they fall exactly where the world-space shafts did.

const SHADER := preload("res://game/scenes/pool/zone_light.gdshader")
## The disc spans this many zone radii across; the shader's light reaches 1.3 zone radii out, so
## neighbouring zones (22 m apart, radius 6 m) stay separate patches.
const SPAN_PER_ZONE_RADIUS := 2.6
## Height under the swim plane (m): clear of the plane's cues, above the midground decor.
const DEPTH_M := -2.5
## The patches' alpha where their light is fullest, by renderer (PROPOSED). Forward+ blends in
## linear light before the tonemap and Compatibility in sRGB after it, so one alpha lifts the navy
## fluid about three times as much in Forward+ (at 0.1, 20.9 L* against 6.4); each renderer gets
## the alpha that lifts its brightest shaft about 9 L* (look probe: 9.2 | 9.6), which an ambush
## hunter over it still clears by 15 dL* (17.1 | 16.8).
const STRENGTH := 0.035
const STRENGTH_COMPATIBILITY := 0.15
## The Sun's light colour (pool.tscn), never the food glow #CFE86A.
const TINT := Color(0.957, 0.918, 0.824)
## The way the Sun's light runs across the plane (x, z): pool.tscn's Sun points along (0.41, -0.82,
## 0.41), so the shafts lie from north-west to south-east.
const SUN_WAY := Vector2(0.7071068, 0.7071068)
## Under every other world transparent; the strike lane draws at CreatureView.LANE_PRIORITY (8).
const RENDER_PRIORITY := -2

## One unit disc for every zone, scaled to each. The start fade's warm-up draws it too (pool.gd).
var mesh: PlaneMesh

var _discs := {}   ## key -> Array[MeshInstance3D]: the pool's under POOL_KEY, the endless sea's by chunk
## A growth: retiring discs by zone id, fresh discs (disc -> the beat time it came), whether a beat is
## open, the beat time of the settle (-1 before), the beat time now and the depth factor.
var _retiring := {}
var _fresh := {}
var _beat := false
var _settled_t := -1.0
var _beat_t := 0.0
var _depth_k := 1.0


func _init() -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	material.set_shader_parameter("tint", TINT)
	material.set_shader_parameter("strength", strength_for(RenderingServer.get_current_rendering_method()))
	material.set_shader_parameter("span_per_radius", SPAN_PER_ZONE_RADIUS)
	material.set_shader_parameter("sun_way", SUN_WAY)
	mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE
	mesh.material = material


## The patches' alpha for a renderer, by its RenderingServer.get_current_rendering_method() name.
static func strength_for(method: String) -> float:
	return STRENGTH_COMPATIBILITY if method == PoolLook.COMPATIBILITY_METHOD else STRENGTH


## Lays one disc under each of `zones` (PoolLayout.zones), replacing any from before.
func build(zones: Array[Dictionary]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_discs.clear()
	_retiring.clear()
	_fresh.clear()
	_beat = false
	_settled_t = -1.0
	add_chunk(RockField.POOL_KEY, zones)


## Lays one disc under each of `zones` ({id, center, radius}: layout zones or chunk_loaded zones)
## under `key`. In the endless sea the pool passes only the zones of sunlit and home tiles.
## During a growth beat a disc retired with the same zone id is adopted back, and a new one fades in.
func add_chunk(key: Variant, zones: Array) -> void:
	var discs: Array = _discs.get(key, [])
	for zone in zones:
		var id := String(zone.id)
		var disc: MeshInstance3D = _retiring.get(id) if _beat else null
		if disc != null:
			_retiring.erase(id)
			disc.transparency = 0.0
		else:
			disc = MeshInstance3D.new()
			disc.name = id
			disc.mesh = mesh
			disc.material_override = mesh.material.duplicate()
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(disc)
			if _beat and _settled_t < 0.0:
				_fresh[disc] = _beat_t
				disc.transparency = 1.0
		var span := float(zone.radius) * SPAN_PER_ZONE_RADIUS
		var adopted := disc.has_meta(&"laid")
		disc.position = WorldSpace.to_frame(self, zone.center, DEPTH_M * _depth_k)
		disc.scale = Vector3(span, 1.0, span)
		if not adopted:
			var laid := position + disc.position
			(disc.material_override as ShaderMaterial).set_shader_parameter("anchor", Vector2(laid.x, laid.z))
			(disc.material_override as ShaderMaterial).set_shader_parameter("laid_span", span)
			disc.set_meta(&"laid", true)
		discs.append(disc)
	_discs[key] = discs


## Frees the discs laid under `key`; an unknown key changes nothing.
func remove_chunk(key: Variant) -> void:
	for disc: MeshInstance3D in _discs.get(key, []):
		_fresh.erase(disc)
		remove_child(disc)
		disc.queue_free()
	_discs.erase(key)


## Moves every disc by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for child in get_children():
		(child as Node3D).position += position
	position = Vector3.ZERO


## A growth (the container contract): every disc re-expressed in place round `center_old` by
## 1 / `factor` (its span too), this node back at the origin; a beat opens.
func apply_growth(center_old: Vector2, factor: float) -> void:
	var shift := position
	position = Vector3.ZERO
	for child in get_children():
		var disc := child as Node3D
		disc.position = WorldSpace.reexpress_point(disc.position + shift, center_old, factor)
		disc.scale = Vector3(disc.scale.x / factor, disc.scale.y, disc.scale.z / factor)
	_beat = true
	_settled_t = -1.0
	_beat_t = 0.0


## Every disc at DEPTH_M x k (1 when no beat runs).
func set_depth_k(k: float) -> void:
	_depth_k = k
	for child in get_children():
		(child as Node3D).position.y = DEPTH_M * k


## chunk_unloaded {reason: "growth"}: the chunk's discs keep drawing, retiring, by zone id.
func retire_chunk(key: Variant) -> void:
	for disc: MeshInstance3D in _discs.get(key, []):
		_fresh.erase(disc)
		_retiring[String(disc.name)] = disc
	_discs.erase(key)


func settle_growth() -> void:
	if _beat:
		_settled_t = _beat_t


## Each beat frame: the fresh discs come in, the leftovers fade (no sink: they are light).
func beat_frame(t: float, _k: float) -> void:
	_beat_t = t
	var s := GrowthBeat.retire_share(t, _settled_t) if _beat else 1.0
	for id in _retiring:
		(_retiring[id] as GeometryInstance3D).transparency = s
	for disc: MeshInstance3D in _fresh.keys():
		var p := GrowthBeat.fresh_share(t - float(_fresh[disc]))
		disc.transparency = 1.0 - p
		if p >= 1.0:
			_fresh.erase(disc)


func end_growth() -> void:
	if not _beat:
		return
	for id in _retiring:
		var disc: Node = _retiring[id]
		remove_child(disc)
		disc.queue_free()
	_retiring.clear()
	_beat = false
	_settled_t = -1.0


## The retiring discs by zone id (tests).
func retiring() -> Dictionary:
	return _retiring.duplicate()


## The disc of zone `id` drawn now, live or retiring, or null (tests).
func disc_of(id: String) -> MeshInstance3D:
	return get_node_or_null(NodePath(id)) as MeshInstance3D
