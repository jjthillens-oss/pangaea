class_name CreatureView
extends Node3D
## One creature in the pool (M1 step 3): its species' body blockout scaled by body_size, carrying
## the species' parts, which PartPlacement puts on it from the player's part GLBs (D22: tuning parts
## or size in data never needs a Blender run). It only draws. Position and heading come from the
## sim's motion, between ticks like PlayerCellView; the pose comes from the brain's state, phase and
## phase tick, the same counter that times the strike, so a coil on screen and the damage window
## cannot disagree.
##
## The root carries the interpolated position. Pivot turns to the heading (and wobbles); Model takes
## body_size times the pose's scale. Lane lies on the swim plane in world space while a tell targets
## the player; Marker pops up a "!" when the creature notices the player, while the creature is on
## screen (off screen the HUD's edge arrow shows the "!" instead).
##
## Growth (S2, s2-view 5): a creature is drawn at its q, its size at the cell's size over its size
## at its entry size (view_q; radius and top speed scale with it). Its threat colour, the "ink" of
## the M_Threat, M_SpikeShaft and M_SpikeTip surfaces, the "!" and the lane, shows only while it
## can attack the cell; below that it fades to a neutral grey. A body the cell can eat now (prey or
## a morsel, for a cell with a jaw) gets a green rim, an inverted hull round its body mesh. At a
## growth it may become a remnant (it goes limp: M_RemnantLimp fades in), a morsel (M_Morsel, drawn
## where its carrion item lies) or haze (it fades out). "Now food" can show over it for a moment.

## Body blockouts by species body_asset (creatures_m1.json).
const BODY_SCENES := {
	"creature_ambush_body": preload("res://assets/export/creature_ambush_body.glb"),
	"creature_rammer_body": preload("res://assets/export/creature_rammer_body.glb"),
	"creature_lurker_body": preload("res://assets/export/creature_lurker_body.glb"),
	"creature_elder_rammer_body": preload("res://assets/export/creature_elder_rammer_body.glb"),
}
## Pose nodes, as their records name them (assets/records/creature_*_body.json and part_mouth_jaw.json).
const EYE_PATHS: Array[NodePath] = [^"Body/Eye_L", ^"Body/Eye_R"]
const BROW_PATH := ^"Body/Brow"
const HOOD_PATH := ^"Body/Hood"
const MANDIBLE_PATHS: Array[NodePath] = [^"JawBase/Mandible_L", ^"JawBase/Mandible_R"]
## The emission strength M_AmbushEye was authored at (its record's eye_emission_rest): the glTF
## export folds it into the colour, so a strength g is an energy multiplier of g / this.
const EYE_EMISSION_REST := 0.4

## Pose amplitudes (plan section 14). PROPOSED and view-only: no sim timing depends on them.
const COIL_LENGTH := 0.82        ## ambush tell: the body squashes along its length...
const COIL_WIDTH := 1.08         ## ...and widens as it coils
const STRIKE_LENGTH := 1.15      ## ambush strike and glide: stretched along the lunge
const PUFF_SCALE := 1.25         ## rammer tell: the whole body puffs up...
const PUFF_HELD := 1.2           ## ...and stays nearly that big through the charge
const RELAX_SHARE := 0.4         ## recover: back to rest over this share of the phase
const SPIKE_RAISE_DEG := 25.0    ## spikes tilt up this far at full raise (about the holder's local +X)
const HOOD_RAISE := 0.7          ## the rammer's crest grows this share taller at full hood
const JAW_OPEN_DEG := 30.0       ## each mandible swings out this far at full jaw
const BROW_DROP_M := 0.03        ## the ambush brow lowers this far (at size 1) over the eyes in the coil
const EYE_GLOW_IDLE := 0.2       ## ambush eye emission strength: lurking, wandering or foraging...
const EYE_GLOW_ALERT := 0.4      ## ...noticing, watching or chasing something...
const EYE_GLOW_TELL := 1.0       ## ...and at the end of the coil and through the lunge
const WOBBLE_S := 0.3            ## a rammer blocked by a rock wobbles, dazed, this long...
const WOBBLE_DEG := 9.0          ## ...this far either way...
const WOBBLE_HZ := 5.0           ## ...this often
## Phases (CreatureBrain labels, "state/phase") in which an ambush hunter's eyes show attention.
const ALERT_PHASES: PackedStringArray = ["notice", "rest/watch", "chase/pursue", "chase/aim", "attack/recover"]

const BLEND_S := 0.12            ## a phase change that would jump the pose blends over this long
const HURT_S := 0.15             ## a hit on it: a white-red flash this long...
const HURT_SQUASH_S := 0.1       ## ...and a squash this long...
const HURT_SQUASH := 0.12        ## ...this deep
const HURT_COLOR := Color(1.0, 0.62, 0.58, 0.7)
const DIE_S := 0.4               ## death: shrink, sink and fade over this long, then free the view
const DIE_SINK_M := 0.3
const SPAWN_SCALE := 0.6         ## a new creature grows from this share of its size while it fades in
const MARKER_S := 0.6            ## the "!" shows this long on noticing the player...
const MARKER_POP_S := 0.12       ## ...popping in over this long...
const MARKER_FADE_S := 0.15      ## ...and fading over the last of it
const MARKER_Y := 1.25           ## m above the swim plane...
const MARKER_NORTH := 1.0        ## ...and this many body radii north, so it clears the body on screen
const MARKER_COLOR := Color(0.851, 0.275, 0.42)    ## threat #D9466B (docs/art/ART_DIRECTION.md)
## The "!"'s outline: cream highlight #F4EAD2. The teal-era deep shadow #1D3557 measured 1.5:1
## against the fluid behind it (WCAG contrast; look probe, tell scene), so the "!" lost its edge on
## the navy; cream measures 7.8:1 there and 3:1 against the pink inside it (micro-world plan C8).
const MARKER_OUTLINE := Color(0.957, 0.918, 0.824)
const LANE_Y := -0.02            ## the lane lies just under the swim plane, where the bodies swim
const LANE_FADE_S := 0.3         ## the lane fades out over this long when the strike ends
const LANE_COLOR := Color(0.851, 0.275, 0.42)
const LANE_SHADER := preload("res://game/scenes/pool/threat_lane.gdshader")
## The lane draws over every other world transparent (the sunlit patches and art's ambience stay
## below it, so pale decor never covers its outline) and under the dev gizmos at 10 (micro-world
## plan section 3).
const LANE_PRIORITY := 8
const WAG_DEG := 15.0            ## flagellum wag, as on the player's cell
const WAG_HZ_REST := 1.5
const WAG_HZ_TOP := 5.0
## Ink (S2, D-52): the surfaces that carry the threat colour, by material name as imported from the
## GLBs, and the neutral each fades to on a creature that can no longer attack the cell. The "!"
## and the lane fade to the crest's neutral.
const NEUTRAL_CREST := Color("#9AA0B4")
const NEUTRAL_TIP := Color("#6E7487")
const INK_SURFACES := {"M_Threat": NEUTRAL_CREST, "M_SpikeShaft": NEUTRAL_CREST, "M_SpikeTip": NEUTRAL_TIP}
## The rim on a body the cell can eat now: food's green, this wide in the world at any body size.
const RIM_COLOR := Color("#CFE86A")
const RIM_GROW_TM := 0.06
## A relation that fades (at a growth) brings the rim in this fast; the ink takes its fade_s (V-8).
const RIM_FADE_S := 0.3
const RIM_SHADER := preload("res://game/scenes/pool/rim_hull.gdshader")
## The body mesh the rim goes round (Model/Body/Body: the body GLB's root holds it).
const BODY_MESH_PATH := ^"Body"
const LIMP_MATERIAL := preload("res://assets/export/M_RemnantLimp.tres")
const MORSEL_MATERIAL := preload("res://assets/export/M_Morsel.tres")
## "Now food" over a body the cell can now eat, just after a growth.
const NOW_FOOD_TEXT := "Now food"
const NOW_FOOD_FONT := 56
const NOW_FOOD_PIXEL := 0.005
const NOW_FOOD_OUTLINE := 12
const NOW_FOOD_Y := 1.0          ## tm above the swim plane...
const NOW_FOOD_NORTH := 1.6      ## ...and this many body radii north
const NOW_FOOD_IN_S := 0.2
const NOW_FOOD_OUT_S := 0.4

var creature_id := ""
var species_id := ""
var behavior := ""
var body_size := 1.0
var radius := 0.5   ## the body's plane radius in metres (its phenotype's, times view_q)
## Growth (S2): the shown size (q), how much threat colour shows (ink, 0 neutral to 1) and how much
## rim (0..1), for tests; a remnant or a morsel is drawn as one from its conversion on.
var view_q := 1.0
var ink := 1.0
var rim := 0.0
var remnant := false
var morsel_id := ""
## The pose drawn last (pose() keys), for tests and blends.
var shown_pose := {}
var dying := false

var _top_speed := 1.0
var _speed := 0.0
var _label := ""
var _blend_from := {}
var _blend_t := BLEND_S
var _eye_material: StandardMaterial3D
var _mandibles: Array[Node3D] = []
var _spikes: Array[Node3D] = []
var _spike_rest: Array[Transform3D] = []
var _hood: Node3D
var _brow: Node3D
var _brow_rest := Vector3.ZERO
var _recover_from := {}   ## the pose a recover from a tell that never struck starts from
var _sim_at := Vector3.ZERO   ## the sim's position (not the drawn one), for the marker's on-screen test
var _wag_nodes: Array[Node3D] = []
var _wag_phase := 0.0
var _hurt_t := -1.0
var _hurt_overlay := StandardMaterial3D.new()
var _die_t := 0.0
var _fade_s := 0.0
var _fade_t := 0.0
var _marker_t := -1.0
var _lane_material := ShaderMaterial.new()
var _lane_on := false
var _lane_strength := 0.0
var _lane_fade := 0.0
var _overlay_on := false
var _transparency := 0.0
var _pivot: Node3D
var _model: Node3D
var _lane: MeshInstance3D
var _marker: Label3D
var _base_radius := 0.5
var _base_speed := 1.0
var _ink_slots: Array[Dictionary] = []   ## {"material", "ink" (its own colour), "neutral"}
var _ink_target := 1.0
var _ink_rate := 0.0                     ## per second; 0 sets at once
var _rim_target := 0.0
var _rim_rate := 0.0
var _body_mesh: MeshInstance3D
var _rim_material := ShaderMaterial.new()
var _body_hurt := StandardMaterial3D.new()   ## the hurt flash on the body mesh, chained to the rim
var _overlay_key := ""
var _limp_delay := -1.0                  ## seconds until the limp look starts fading in
var _limp_s := 0.0
var _limp_t := -1.0
var _limp_overlay: StandardMaterial3D
var _out_s := 0.0                        ## fade_out(): its length, 0 when not leaving
var _out_t := 0.0
var _now_food: Label3D
var _now_s := 0.0
var _now_t := -1.0


## The pose of a creature with `behavior` ("ambush" or "territorial") in brain phase `phase` (the
## brain's "state/phase" label), `progress` (0..1) of the way through it. `outcome` is the attack's
## (CreatureBrain.Memory.outcome) during recover, and `phase_s` the phase's length in seconds (it
## times the blocked wobble). A recover starts from `from` when it is given (the pose shown when a
## tell was cancelled, so the puff deflates from where it got to), else from the full tell or the
## lunge. Pure. Returns {"scale" (Vector3, times body_size), "jaw_open", "hood", "spike_raise",
## "brow", "eye_glow" (emission strength), "stretch", "wobble" (radians of roll)}; every amount but
## eye_glow and wobble is 0..1.
static func pose(p_behavior: String, phase: String, progress: float, outcome := "", phase_s := 0.0, from := {}) -> Dictionary:
	var k := clampf(progress, 0.0, 1.0)
	var out := _neutral(p_behavior, phase)
	if p_behavior == CreatureBrain.AMBUSH:
		match phase:
			"attack/tell":
				var e := _tell_curve(k)
				out.scale = Vector3(lerpf(1.0, COIL_WIDTH, e), 1.0, lerpf(1.0, COIL_LENGTH, e))
				out.jaw_open = e
				out.brow = e
				out.eye_glow = lerpf(EYE_GLOW_ALERT, EYE_GLOW_TELL, e)
			"attack/strike", "attack/glide":
				out.scale = Vector3(1.0, 1.0, STRIKE_LENGTH)
				out.jaw_open = 1.0
				out.brow = 1.0
				out.eye_glow = EYE_GLOW_TELL
				out.stretch = 1.0
			"attack/recover":
				# From the coil when the tell never struck, else from the lunge's stretch.
				var from_phase := "attack/tell" if outcome == "cancelled" or outcome == "interrupted" else "attack/glide"
				var start := from.duplicate() if not from.is_empty() else pose(p_behavior, from_phase, 1.0)
				start.stretch = 0.0
				return blend(start, out, smoothstep(0.0, RELAX_SHARE, k))
	elif p_behavior == CreatureBrain.TERRITORIAL:
		match phase:
			"attack/tell":
				var e := _tell_curve(k)
				out.scale = Vector3.ONE * lerpf(1.0, PUFF_SCALE, e)
				out.hood = e
				out.spike_raise = e
			"attack/strike", "attack/glide":
				out.scale = Vector3.ONE * PUFF_HELD
				out.hood = 1.0
				out.spike_raise = 1.0
			"attack/recover":
				var from_phase := "attack/tell" if outcome == "cancelled" or outcome == "interrupted" else "attack/glide"
				# A cancelled puff deflates over its whole (short) recover; the others over its first part.
				var span := 1.0 if outcome == "cancelled" else RELAX_SHARE
				var start := from if not from.is_empty() else pose(p_behavior, from_phase, 1.0)
				var deflated := blend(start, out, smoothstep(0.0, span, k))
				if outcome == "blocked":
					var t := k * phase_s
					if t < WOBBLE_S:
						deflated.wobble = deg_to_rad(WOBBLE_DEG) * sin(t * TAU * WOBBLE_HZ) * (1.0 - t / WOBBLE_S)
				return deflated
	return out


## `a` blended toward `b` by `t` (0..1), key by key.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in b:
		out[key] = lerp(a.get(key, b[key]), b[key], t)
	return out


## The phase's length in ticks: the tell, burst, glide and recover of an attack, and the notice;
## 0 for phases with no timer of their own.
static func phase_ticks(mem: CreatureBrain.Memory) -> int:
	var attack: Dictionary = mem.cfg.get("attack", {})
	if mem.state == CreatureBrain.NOTICE:
		return int(mem.cfg.get("notice_ticks", 0))
	if mem.state != CreatureBrain.ATTACK:
		return 0
	match mem.phase:
		CreatureBrain.TELL:
			return int(attack.get("tell_ticks", 0))
		CreatureBrain.STRIKE:
			return int(attack.get("burst_ticks", 0))
		CreatureBrain.GLIDE:
			return int(attack.get("glide_ticks", 0))
		CreatureBrain.RECOVER:
			return mem.recover_ticks
	return 0


## How far through its phase a brain is at the drawn moment, 0..1. The sim's tick has already
## advanced past the last step, so the drawn moment is tick - 1 + `fraction` (PoolScene._draw_time),
## and a phase entered on that step is at 0 when fraction is 0. 0 for phases with no timer.
static func phase_progress(mem: CreatureBrain.Memory, tick: int, fraction: float) -> float:
	var length := phase_ticks(mem)
	if length <= 0:
		return 0.0
	return clampf((float(tick - 1 - mem.phase_tick) + fraction) / length, 0.0, 1.0)


## Builds the species' body and parts (creatures_m1.json): its body_asset, scaled by body_size, and
## one holder per genome part, placed by PartPlacement like the player's parts. `q` is its size at
## the cell's size (S2; SpeciesCatalog.q_of), 1 at its entry size.
func build(species: SpeciesCatalog, p_species_id: String, catalog: PartCatalog, id := "", q := 1.0) -> void:
	creature_id = id
	species_id = p_species_id
	var data: Dictionary = species.species.get(p_species_id, {})
	behavior = str(data.get("behavior", ""))
	body_size = float(data.get("body_size", 1.0))
	var phenotype := species.phenotype(p_species_id, catalog)
	_base_speed = maxf(phenotype.speed, 0.01)
	_base_radius = phenotype.radius
	view_q = q
	_top_speed = maxf(phenotype.speed * q, 0.01)
	radius = phenotype.radius * q
	_pivot = %Pivot
	_model = %Model
	_lane = %Lane
	_marker = %Marker
	var model := _model
	var old := model.get_node_or_null(^"Body")
	if old != null:
		model.remove_child(old)
		old.free()
	var packed: PackedScene = BODY_SCENES.get(str(data.get("body_asset", "")))
	if packed != null:
		var body: Node3D = packed.instantiate()
		body.name = "Body"
		model.add_child(body)
		model.move_child(body, 0)
		_find_pose_nodes(body)
	var parts: Node3D = %Parts
	for child in parts.get_children():
		parts.remove_child(child)
		child.free()
	_mandibles.clear()
	_spikes.clear()
	_spike_rest.clear()
	_wag_nodes.clear()
	for part in species.genome(p_species_id).parts:
		var type := str(part.get("type", ""))
		var holder := Node3D.new()
		holder.name = str(part.get("id", "part"))
		holder.transform = PartPlacement.transform_for(float(part.get("angle", 0.0)), type, float(part.get("scale", 1.0)))
		holder.set_meta("part_type", type)
		var scene: PackedScene = PlayerCellView.PART_SCENES.get(type)
		if scene != null:
			var node: Node3D = scene.instantiate()
			holder.add_child(node)
			for path in MANDIBLE_PATHS:
				var mandible := node.get_node_or_null(path) as Node3D
				if mandible != null:
					_mandibles.append(mandible)
			if type == "flagellum":
				_wag_nodes.append(node)
		if type == "spike":
			_spikes.append(holder)
			_spike_rest.append(holder.transform)
		parts.add_child(holder)
	# Parts cast no shadow (plan section 20). The bodies keep theirs, all but the rammer's crest
	# (_find_pose_nodes), though the micro look's sun casts none, so nothing shows one today.
	for node in parts.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hurt_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hurt_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lane_material.shader = LANE_SHADER
	_lane_material.render_priority = LANE_PRIORITY
	_lane_material.set_shader_parameter("color", LANE_COLOR)
	_lane_material.set_shader_parameter("key", UiPalette.KEYLINE)
	_lane_material.set_shader_parameter("strength", 0.0)
	_lane.material_override = _lane_material
	_lane.visible = false
	_marker.modulate = MARKER_COLOR
	_marker.outline_modulate = MARKER_OUTLINE
	_marker.position = Vector3(0.0, MARKER_Y, -MARKER_NORTH * radius)   # north is -z
	_marker.visible = false
	_overlay_on = false
	_transparency = -1.0
	_overlay_key = ""
	_label = ""
	_build_ink()
	_build_rim()
	ink = 1.0
	_ink_target = 1.0
	rim = 0.0
	_rim_target = 0.0
	remnant = false
	morsel_id = ""
	_limp_delay = -1.0
	_limp_t = -1.0
	_apply_ink()
	shown_pose = pose(behavior, "", 0.0)
	_apply_pose(shown_pose)


func _find_pose_nodes(body: Node3D) -> void:
	_eye_material = null
	for path in EYE_PATHS:
		var eye := body.get_node_or_null(path) as MeshInstance3D
		if eye == null:
			continue
		var material := eye.get_active_material(0) as StandardMaterial3D
		if material != null and material.emission_enabled:
			# One copy per view, shared by both eyes, so each creature's glow is its own.
			if _eye_material == null:
				_eye_material = material.duplicate() as StandardMaterial3D
			eye.set_surface_override_material(0, _eye_material)
	_hood = body.get_node_or_null(HOOD_PATH) as Node3D
	# The crest is a thin blade: its shadow on the back reads as a dark hole, not as its shape.
	if _hood is GeometryInstance3D:
		(_hood as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brow = body.get_node_or_null(BROW_PATH) as Node3D
	_brow_rest = _brow.position if _brow != null else Vector3.ZERO


## Each threat-coloured surface of the body and parts gets a copy of its material of its own, so
## its ink can fade without touching other creatures.
func _build_ink() -> void:
	_ink_slots.clear()
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(i) as BaseMaterial3D
			if material == null or not INK_SURFACES.has(material.resource_name):
				continue
			var own := material.duplicate() as BaseMaterial3D
			mesh_node.set_surface_override_material(i, own)
			_ink_slots.append({"material": own, "ink": material.albedo_color,
				"neutral": INK_SURFACES[material.resource_name]})


func _build_rim() -> void:
	_body_mesh = null
	var body := _model.get_node_or_null(^"Body")
	if body != null:
		_body_mesh = body.get_node_or_null(BODY_MESH_PATH) as MeshInstance3D
	_rim_material.shader = RIM_SHADER
	_rim_material.set_shader_parameter("color", RIM_COLOR)
	_rim_material.set_shader_parameter("rim", 0.0)
	_body_hurt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_hurt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_apply_rim_grow()


## Shows the creature at another size (a growth re-expresses every view by 1 / factor, D-30).
func set_q(q: float) -> void:
	view_q = q
	radius = _base_radius * q
	_top_speed = maxf(_base_speed * q, 0.01)
	_marker.position = Vector3(0.0, MARKER_Y, -MARKER_NORTH * radius)
	_apply_rim_grow()
	_apply_pose(shown_pose)


## The body's plane radius at q (its phenotype's times q).
func radius_at(q: float) -> float:
	return _base_radius * q


## What the creature is to the cell now: whether it can attack it (its ink) and whether the cell can
## eat it (its rim). The ink fades to its new value over `fade_s` and the rim over RIM_FADE_S; with
## `fade_s` 0 both are set at once.
func set_relation(can_attack: bool, rimmed: bool, fade_s: float) -> void:
	_ink_target = 1.0 if can_attack and not remnant and morsel_id == "" else 0.0
	_rim_target = 1.0 if rimmed else 0.0
	_ink_rate = 1.0 / fade_s if fade_s > 0.0 else 0.0
	_rim_rate = 1.0 / RIM_FADE_S if fade_s > 0.0 else 0.0
	if fade_s <= 0.0:
		ink = _ink_target
		rim = _rim_target
	_apply_ink()
	_apply_rim()


## The rim the next relation fades to (1 when the cell can eat it).
func rimmed() -> bool:
	return _rim_target > 0.0


## A remnant (S2, D-28): after `delay_s` it goes limp, the M_RemnantLimp look fading in over
## `limp_fade_s` (an overlay for that long, then the material). It never attacks again, so every
## relation set from now on has no ink; the ink it has fades with the next one (at a growth, at
## RELATIONS_S), so frame 0 still draws it as it was.
func set_remnant(limp_fade_s: float, delay_s: float) -> void:
	remnant = true
	_limp_s = maxf(limp_fade_s, 0.0)
	_limp_delay = maxf(delay_s, 0.0)
	_limp_t = -1.0
	hide_lane()
	_marker_t = -1.0
	_apply_marker()


## A morsel (S2, D-50): drawn with M_Morsel at `p_radius`, where the carrion item `food_id` lies
## (CreatureLayer places it there each frame).
func set_morsel(food_id: String, p_radius: float) -> void:
	morsel_id = food_id
	ink = 0.0
	_ink_target = 0.0
	_apply_ink()
	hide_lane()
	_marker_t = -1.0
	_apply_marker()
	set_q(p_radius / maxf(_base_radius, 1e-6))
	for node in _model.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).material_override = MORSEL_MATERIAL


## Leaves: fades to nothing over `seconds` where it is, with no sink, then frees itself.
func fade_out(seconds: float) -> void:
	if _out_s > 0.0 or dying:
		return
	_out_s = maxf(seconds, 1e-3)
	_out_t = 0.0
	hide_lane()
	_marker_t = -1.0
	_apply_marker()


## True while fade_out runs.
func leaving() -> bool:
	return _out_s > 0.0


## "Now food" over the body for `seconds` (fading in and out within them).
func show_now_food(seconds: float) -> void:
	if _now_food == null:
		_now_food = Label3D.new()
		_now_food.name = "NowFood"
		_now_food.text = NOW_FOOD_TEXT
		_now_food.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_now_food.font_size = NOW_FOOD_FONT
		_now_food.pixel_size = NOW_FOOD_PIXEL
		_now_food.modulate = RIM_COLOR
		_now_food.outline_modulate = UiPalette.KEYLINE
		_now_food.outline_size = NOW_FOOD_OUTLINE
		_now_food.fixed_size = false
		_now_food.render_priority = LANE_PRIORITY + 1
		_now_food.outline_render_priority = LANE_PRIORITY
		_now_food.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_now_food)
	_now_food.position = Vector3(0.0, NOW_FOOD_Y, -NOW_FOOD_NORTH * radius)
	_now_s = maxf(seconds, NOW_FOOD_IN_S + NOW_FOOD_OUT_S)
	_now_t = 0.0
	_apply_now_food()


## The "Now food" label while it shows, else null.
func now_food_label() -> Label3D:
	return _now_food if _now_food != null and _now_food.visible else null


## The rim's width in the world: its grow over the model's scale, times that scale.
func rim_grow_world() -> float:
	return float(_rim_material.get_shader_parameter("grow")) * _model.scale.x


## Moves the view to the sim's motion, `fraction` of the way from the previous tick to this one.
func show_motion(motion: Locomotion.MotionState, fraction: float) -> void:
	position = PlaneSpace.to_world(motion.prev_position.lerp(motion.position, fraction))
	_pivot.rotation.y = PlaneSpace.yaw_for_heading(lerp_angle(motion.prev_heading, motion.heading, fraction))
	_speed = motion.position.distance_to(motion.prev_position) / PoolSim.DT
	_sim_at = PlaneSpace.to_world(motion.position)


## Poses the view from its brain at the drawn moment (`tick` is the sim's tick, `fraction` the draw
## fraction), and fills the lane with the tell's progress.
func show_brain(mem: CreatureBrain.Memory, tick: int, fraction: float) -> void:
	if mem == null or dying:
		return
	var label := mem.state if mem.phase.is_empty() else "%s/%s" % [mem.state, mem.phase]
	var progress := phase_progress(mem, tick, fraction)
	if label != _label:
		# The tell starts from rest and the strike snaps out of the coil; other changes blend.
		if not _label.is_empty() and label != "attack/tell" and label != "attack/strike":
			_blend_from = shown_pose.duplicate()
			_blend_t = 0.0
		else:
			_blend_t = BLEND_S
		# A tell that never struck deflates from the pose it had reached, not from the full coil or
		# puff, so a withdrawn threat never swells first; it starts there, so it needs no blend.
		_recover_from = {}
		if label == "attack/recover" and (mem.outcome == "cancelled" or mem.outcome == "interrupted"):
			_recover_from = shown_pose.duplicate()
			_blend_t = BLEND_S
		_label = label
	var target := pose(behavior, label, progress, mem.outcome, phase_ticks(mem) * PoolSim.DT, _recover_from)
	shown_pose = blend(_blend_from, target, _blend_t / BLEND_S) if _blend_t < BLEND_S else target
	if label == "attack/tell":
		_lane_material.set_shader_parameter("fill", progress)
	elif label == "attack/strike" or label == "attack/glide":
		_lane_material.set_shader_parameter("fill", 1.0)


## Shows the strike lane of a tell on the player (a creature_tell event's "lane").
func show_lane(lane: Dictionary) -> void:
	var length := float(lane.length)
	var width := 2.0 * float(lane.half_width)
	var heading := float(lane.heading)
	var center: Vector2 = Vector2(lane.origin) + Vector2.from_angle(heading) * (length * 0.5)
	var basis := Basis(Vector3.UP, PlaneSpace.yaw_for_heading(heading)).scaled_local(Vector3(width, 1.0, length))
	_lane.transform = Transform3D(basis, PlaneSpace.to_world(center, LANE_Y))   # top_level: in world space
	_lane_material.set_shader_parameter("size_m", Vector2(width, length))
	_lane_material.set_shader_parameter("fill", 0.0)
	_lane_on = true
	_lane_strength = 1.0
	_lane_fade = 0.0
	_apply_lane()


## The strike lane: top_level, so the pool's WorldSpace shifts it across a rebase (S1).
func lane() -> MeshInstance3D:
	return _lane


## A lane quad with a lane material of its own, for the start fade's shader warm-up (pool.gd): a
## lane first shows at a tell, in play, where its first compile would show as a hitch.
static func warm_up_lane_mesh() -> Mesh:
	var material := ShaderMaterial.new()
	material.shader = LANE_SHADER
	material.render_priority = LANE_PRIORITY
	material.set_shader_parameter("color", LANE_COLOR)
	material.set_shader_parameter("strength", 1.0)
	var quad := QuadMesh.new()
	quad.orientation = QuadMesh.FACE_Y
	quad.material = material
	return quad


## Takes the lane down: at once for a cancelled tell, or fading over `fade_s`.
func hide_lane(fade_s := 0.0) -> void:
	if not _lane_on:
		return
	if fade_s <= 0.0:
		_lane_on = false
		_lane_strength = 0.0
	else:
		_lane_fade = 1.0 / fade_s
	_apply_lane()


## The lane is on screen: shown, and drawn at a strength (its shader's alpha scale) above 0. Its
## pixels themselves (the alpha math, its depth against what lies behind it) show only in rendered
## frames.
func lane_visible() -> bool:
	return _lane.visible and float(_lane_material.get_shader_parameter("strength")) > 0.0


## The "!" over a creature that noticed the player.
func show_marker() -> void:
	_marker_t = 0.0
	_apply_marker()


## True when the creature's sim position is on the pool camera's screen, by the HUD's edge arrow
## test (ThreatIndicators.on_screen), so the "!" over its body and its edge arrow's "!" take turns
## at the screen's edge instead of one drawing through the other. True outside a tree or without a
## camera.
func on_screen() -> bool:
	if not is_inside_tree():
		return true
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	return ThreatIndicators.on_screen(camera, get_viewport().get_visible_rect(), _sim_at)


## A hit on it: a short white-red flash and squash.
func hurt() -> void:
	_hurt_t = 0.0


## Fades the body in over `seconds` (a creature that spawned while the pool was drawn).
func fade_in(seconds: float) -> void:
	_fade_s = maxf(seconds, 0.0)
	_fade_t = 0.0
	_apply_pose(shown_pose)


## Death: the body shrinks, sinks and fades over DIE_S, then the view frees itself. The carcass
## chunks come from the carrion field's own events.
func die() -> void:
	if dying:
		return
	dying = true
	_die_t = 0.0
	hide_lane()
	_marker_t = -1.0
	_apply_marker()


func _process(delta: float) -> void:
	_blend_t = minf(_blend_t + delta, BLEND_S)
	if _hurt_t >= 0.0:
		_hurt_t += delta
		if _hurt_t >= maxf(HURT_S, HURT_SQUASH_S):
			_hurt_t = -1.0
	if _fade_t < _fade_s:
		_fade_t = minf(_fade_t + delta, _fade_s)
	if _marker_t >= 0.0:
		_marker_t += delta
		if _marker_t >= MARKER_S:
			_marker_t = -1.0
		_apply_marker()
	if _lane_fade > 0.0:
		_lane_strength = maxf(_lane_strength - _lane_fade * delta, 0.0)
		if _lane_strength <= 0.0:
			_lane_on = false
			_lane_fade = 0.0
		_apply_lane()
	var speed_share := clampf(_speed / _top_speed, 0.0, 1.0)
	if not dying:
		_wag_phase = fmod(_wag_phase + TAU * lerpf(WAG_HZ_REST, WAG_HZ_TOP, speed_share) * delta, TAU)
	var wag := deg_to_rad(WAG_DEG) * lerpf(0.35, 1.0, speed_share) * sin(_wag_phase)
	for i in _wag_nodes.size():
		_wag_nodes[i].rotation.y = wag * (1.0 if i % 2 == 0 else -1.0)
	if dying:
		_die_t += delta
		if _die_t >= DIE_S:
			queue_free()
	_step_relation(delta)
	if _now_t >= 0.0:
		_now_t += delta
		if _now_t >= _now_s:
			_now_t = -1.0
		_apply_now_food()
	if _out_s > 0.0:
		_out_t += delta
		if _out_t >= _out_s:
			queue_free()
	_apply_pose(shown_pose)


## Draws a pose with the hurt, spawn and death effects on top.
func _apply_pose(p: Dictionary) -> void:
	if _model == null:
		return
	var model := _model
	var pivot := _pivot
	var size := body_size * view_q
	var sink := 0.0
	var transparency := 0.0
	if _fade_s > 0.0 and _fade_t < _fade_s:
		var f := smoothstep(0.0, 1.0, _fade_t / _fade_s)
		size *= lerpf(SPAWN_SCALE, 1.0, f)
		transparency = 1.0 - f
	if dying:
		var d := smoothstep(0.0, 1.0, clampf(_die_t / DIE_S, 0.0, 1.0))
		size *= 1.0 - d
		sink = DIE_SINK_M * d
		transparency = d
	if _out_s > 0.0:
		transparency = maxf(transparency, clampf(_out_t / _out_s, 0.0, 1.0))
	var squash := 1.0
	if _hurt_t >= 0.0 and _hurt_t < HURT_SQUASH_S:
		squash = 1.0 - HURT_SQUASH * sin(PI * _hurt_t / HURT_SQUASH_S)
	var s: Vector3 = p.get("scale", Vector3.ONE)
	model.scale = Vector3(s.x / sqrt(squash), s.y * squash, s.z / sqrt(squash)) * maxf(size, 1e-3)
	model.position = Vector3(0.0, -sink, 0.0)
	pivot.rotation.z = float(p.get("wobble", 0.0))
	var jaw := deg_to_rad(JAW_OPEN_DEG) * float(p.get("jaw_open", 0.0))
	for i in _mandibles.size():
		_mandibles[i].rotation.y = jaw if i % 2 == 0 else -jaw   # Mandible_L swings left, Mandible_R right
	var raise := deg_to_rad(SPIKE_RAISE_DEG) * float(p.get("spike_raise", 0.0))
	for i in _spikes.size():
		_spikes[i].transform = _spike_rest[i]
		_spikes[i].rotate_object_local(Vector3.RIGHT, raise)
	if _hood != null:
		_hood.scale = Vector3(1.0, 1.0 + HOOD_RAISE * float(p.get("hood", 0.0)), 1.0)
	if _brow != null:
		_brow.position = _brow_rest + Vector3.DOWN * BROW_DROP_M * float(p.get("brow", 0.0))
	if _eye_material != null:
		_eye_material.emission_energy_multiplier = float(p.get("eye_glow", EYE_GLOW_IDLE)) / EYE_EMISSION_REST
	var flash := PlayerCellView.hit_flash(_hurt_t, HURT_S, SettingsService.shared().reduce_flashing())
	_hurt_overlay.albedo_color = Color(HURT_COLOR, HURT_COLOR.a * flash)
	_body_hurt.albedo_color = _hurt_overlay.albedo_color
	var limp := _limp_share()
	if _limp_overlay != null:
		_limp_overlay.albedo_color.a = limp
	# Overlays and transparency change only now and then; set them on the meshes only when they do.
	# The body mesh chains its overlays: the hurt flash or the limp look fading in, then the rim.
	var key := "%s/%s/%s" % [flash > 0.0, rim > 0.0, limp > 0.0 and limp < 1.0]
	if key != _overlay_key or transparency != _transparency:
		_overlay_key = key
		_overlay_on = flash > 0.0
		_transparency = transparency
		var fading_limp := limp > 0.0 and limp < 1.0
		var shared: Material = _hurt_overlay if _overlay_on else (_limp_overlay if fading_limp else null)
		for node in model.find_children("*", "GeometryInstance3D", true, false):
			var g := node as GeometryInstance3D
			g.material_overlay = _body_overlay(fading_limp) if g == _body_mesh else shared
			g.transparency = transparency


## The body mesh's overlay chain: the hurt flash (or the limp look while it fades in), then the rim.
func _body_overlay(fading_limp: bool) -> Material:
	var first: BaseMaterial3D = _body_hurt if _overlay_on else (_limp_body_overlay() if fading_limp else null)
	var rim_pass: Material = _rim_material if rim > 0.0 else null
	if first == null:
		return rim_pass
	first.next_pass = rim_pass
	return first


func _limp_body_overlay() -> BaseMaterial3D:
	if _limp_overlay == null:
		return null
	if not _limp_overlay.has_meta(&"body"):
		_limp_overlay.set_meta(&"body", _limp_overlay.duplicate())
	var own: BaseMaterial3D = _limp_overlay.get_meta(&"body")
	own.albedo_color = _limp_overlay.albedo_color
	return own


## The limp look's share now: 0 before it starts, 1 once it is the material.
func _limp_share() -> float:
	if _limp_t < 0.0:
		return 0.0
	return 1.0 if _limp_s <= 0.0 else clampf(_limp_t / _limp_s, 0.0, 1.0)


## Moves ink and rim toward their targets, and runs the limp look's cross-fade.
func _step_relation(delta: float) -> void:
	if ink != _ink_target:
		ink = _ink_target if _ink_rate <= 0.0 else move_toward(ink, _ink_target, _ink_rate * delta)
		_apply_ink()
	if rim != _rim_target:
		rim = _rim_target if _rim_rate <= 0.0 else move_toward(rim, _rim_target, _rim_rate * delta)
		_apply_rim()
	if _limp_delay >= 0.0:
		_limp_delay -= delta
		if _limp_delay < 0.0:
			_limp_t = 0.0
			_limp_overlay = LIMP_MATERIAL.duplicate() as StandardMaterial3D
			if _limp_overlay != null:
				_limp_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_limp_overlay.albedo_color.a = 0.0
	elif _limp_t >= 0.0 and _limp_t < _limp_s:
		_limp_t = minf(_limp_t + delta, _limp_s)
	if _limp_t >= 0.0 and _limp_share() >= 1.0 and _limp_overlay != null:
		_limp_overlay = null
		for node in _model.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).material_override = LIMP_MATERIAL
		_overlay_key = ""


func _apply_ink() -> void:
	for slot in _ink_slots:
		(slot.material as BaseMaterial3D).albedo_color = _inked(slot.neutral, slot.ink)
	if _marker != null:
		_marker.modulate = Color(_inked(NEUTRAL_CREST, MARKER_COLOR), _marker.modulate.a)
	_lane_material.set_shader_parameter("color", _inked(NEUTRAL_CREST, LANE_COLOR))


## A colour between the neutral (ink 0) and the ink colour (ink 1), each end exact.
func _inked(neutral: Color, ink_color: Color) -> Color:
	if ink >= 1.0:
		return ink_color
	if ink <= 0.0:
		return neutral
	return neutral.lerp(ink_color, ink)


func _apply_rim() -> void:
	_rim_material.set_shader_parameter("rim", rim)


## The hull's push in the mesh's own units, so the rim is RIM_GROW_TM wide in the world.
func _apply_rim_grow() -> void:
	_rim_material.set_shader_parameter("grow", RIM_GROW_TM / maxf(body_size * view_q, 1e-3))


func _apply_now_food() -> void:
	if _now_food == null:
		return
	_now_food.visible = _now_t >= 0.0
	if not _now_food.visible:
		return
	var a := minf(clampf(_now_t / NOW_FOOD_IN_S, 0.0, 1.0), clampf((_now_s - _now_t) / NOW_FOOD_OUT_S, 0.0, 1.0))
	_now_food.modulate.a = a
	_now_food.outline_modulate.a = a


func _apply_lane() -> void:
	_lane.visible = _lane_on and _lane_strength > 0.0
	_lane_material.set_shader_parameter("strength", _lane_strength)


func _apply_marker() -> void:
	_marker.visible = _marker_t >= 0.0 and on_screen()
	if not _marker.visible:
		return
	var pop := clampf(_marker_t / MARKER_POP_S, 0.0, 1.0)
	_marker.scale = Vector3.ONE * (1.0 + 0.35 * sin(PI * pop) if pop < 1.0 else 1.0) * maxf(pop, 0.2)
	_marker.modulate.a = clampf((MARKER_S - _marker_t) / MARKER_FADE_S, 0.0, 1.0)


static func _neutral(p_behavior: String, phase: String) -> Dictionary:
	var glow := 0.0
	if p_behavior == CreatureBrain.AMBUSH:
		glow = EYE_GLOW_ALERT if phase in ALERT_PHASES else EYE_GLOW_IDLE
	return {"scale": Vector3.ONE, "jaw_open": 0.0, "hood": 0.0, "spike_raise": 0.0, "brow": 0.0,
		"eye_glow": glow, "stretch": 0.0, "wobble": 0.0}


## The tell's pose curve: fast at first, so the coil or puff already shows at the 0.4 s a player
## needs to react (F2), then settling into its full depth at the strike.
static func _tell_curve(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)
