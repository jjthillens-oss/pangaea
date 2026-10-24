class_name CreatureLayer
extends Node3D
## The pool's creatures on screen (M1 step 3): one CreatureView per live creature in the sim's
## CreatureField, built when the pool attaches (the starting population, shown at once) and on each
## creature_spawned (faded in over the species data's fade_in_s), and let go on creature_died (it
## shrinks and frees itself) or creature_removed. Each frame sync() draws every view between the
## sim's last two ticks and poses it from its brain. It only draws; PoolScene routes the events.
##
## A pool without species (the step 2 pool) has no CreatureField, and the layer stays empty.
##
## Across a rebase (S1) the live views need nothing, since sync() places them from the sim each
## frame; the two things that keep a place of their own are registered with the pool's WorldSpace:
## each view's strike lane (top_level, set in local coordinates when shown) and each dying view,
## which is no longer synced. A sleeper (Creature.asleep, at least 44 tm out) is not drawn: its view
## hides on creature_slept and shows on creature_woke, placed where it woke with no slide.
##
## Growth (S2, s2-view 5): every view is drawn at its species' q at the cell's size, inked while it
## can attack the cell and rimmed while the cell can eat it (apply_relations). At a growth a view
## converts with its creature: a remnant (drawn from sim.remnants each frame, limp from
## LIMP_DELAY_S), a morsel (drawn where its carrion item lies, fading out when it is eaten or rots)
## or haze (it fades out). A creature removed by the growth or a remnant that swims off fades out
## where it was; one removed for any other reason goes at once.
##
## Morsel sites (S3, s3-view 9.1, V3-13): their carrion items ("morsel_site") are drawn here, not by
## the FoodView: one baked body per species (body and parts in M_Morsel), one MultiMesh per species
## under MorselSites, and a rim MultiMesh beside it while the cell can eat meat. A new item grows in
## over MORSEL_IN_S; one that goes without being eaten (rot, trim, unload) shrinks out over
## MORSEL_OUT_S; an eaten one goes at once, since the swallow ghost carries it (morsel_mesh_for).

## The moment after a growth's start when relations change and remnants go limp (GrowthBeat's
## RELATIONS_S) and how long the limp look takes to fade in.
const LIMP_DELAY_S := 2.0
const LIMP_FADE_S := 1.0
## A view leaving with its creature at a growth (removed, haze, a morsel eaten) fades this long.
const LEAVE_S := 0.6
## creature_removed reasons whose view fades out instead of going at once.
const FADING_REMOVALS: PackedStringArray = ["growth", "remnant_left"]

const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")
const MORSEL_SOURCE := "morsel_site"
const MORSEL_IN_S := 0.6
const MORSEL_OUT_S := 0.6
const MORSEL_MATERIAL := preload("res://assets/export/M_Morsel.tres")
const MORSEL_RIM_SHADER := preload("res://game/scenes/pool/morsel_rim.gdshader")

var sim: PoolSim
var catalog: PartCatalog
## The pool's WorldSpace, or null (a layer outside a pool: nothing shifts).
var world_space: WorldSpace

var _views := {}   ## creature id -> CreatureView, live creatures only
var _remnant_views := {}   ## remnant id -> CreatureView (S2)
var _morsel_views := {}    ## carrion item id -> CreatureView (S2)
## Morsel-site items drawn now (S3): food id -> {species, position, radius, yaw, first_seen, gone_at
## (-1 while the item is in the sim)}.
var _sites := {}
var _sites_root: Node3D
var _morsel_meshes := {}   ## species id -> the baked body
var _morsel_radii := {}    ## species id -> its phenotype's radius (a morsel's q is its radius over it)


## Starts drawing `p_sim`'s creatures: a view for each one alive now, placed at its current tick.
## `p_world_space` shifts the lanes and dying views across a rebase.
func attach(p_sim: PoolSim, p_world_space: WorldSpace = null) -> void:
	clear()
	sim = p_sim
	world_space = p_world_space
	catalog = sim.catalog
	if sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if not c.asleep:
			_add_view(c)


## Frees every view, dying ones included.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_views.clear()
	_remnant_views.clear()
	_morsel_views.clear()
	_sites.clear()
	_sites_root = null


## The cell's size now (the world's; 1 in the pool).
func size() -> int:
	return sim.world.size if sim != null and sim.world != null else 1


## A remnant's view (S2), or null.
func remnant_view(id: String) -> CreatureView:
	return _remnant_views.get(id)


## A morsel's view by its carrion item id (S2), or null.
func morsel_view(food_id: String) -> CreatureView:
	return _morsel_views.get(food_id)


## What a creature of `species_id` drawn at `q` is to the cell of size n: {"can_attack", "rimmed"}.
## It can attack only at its entry size (Relationships.can_attack_player); the cell can eat it when
## it is prey or a morsel at this size and the cell has a jaw (D-52). A remnant or a morsel never
## attacks.
static func relation_of(species: SpeciesCatalog, species_id: String, q: float, radius: float, n: int,
		cell: Phenotype, converted := false) -> Dictionary:
	var role := Relationships.ladder_role(species.entry_size(species_id), n, radius)
	return {"can_attack": Relationships.can_attack_player(q) and not converted,
		"rimmed": role in ["prey", "morsel"] and cell.can_eat("meat")}


## A growth re-expressed the world round `center_old` by 1 / `factor` (growth_began): every view
## is drawn factor times smaller where it was, so a view the tick removes or converts leaves from
## the right place; the live ones are placed from the sim again on the next sync.
func apply_growth(center_old: Vector2, factor: float) -> void:
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if is_instance_valid(view):
				view.set_q(view.view_q / factor)
				view.position = WorldSpace.reexpress_point(view.position, center_old, factor)


## Sets every view's ink and rim for the cell at size n, fading over `fade_s` (0: at once).
func apply_relations(n: int, fade_s: float) -> void:
	if sim == null or sim.species == null:
		return
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if is_instance_valid(view) and not view.leaving():
				_relate(view, n, fade_s)


## A view's relation at size n, from its species' q at n (so it holds before the view is redrawn at
## that size); a morsel's from the radius its carrion item has.
func _relate(view: CreatureView, n: int, fade_s: float) -> void:
	var morsel := view.morsel_id != ""
	var q := view.view_q if morsel else sim.species.q_of(view.species_id, n)
	var r := relation_of(sim.species, view.species_id, q, view.radius if morsel else view.radius_at(q), n,
		sim.phenotype, view.remnant or morsel)
	view.set_relation(r.can_attack, r.rimmed, fade_s)


## The rimmed views (live, remnants and morsels) whose centres lie on a `screen`-sized view of
## `camera`, nearest the cell first, at most `max_count`.
func rimmed_in_view(camera: Camera3D, screen: Vector2, max_count: int) -> Array[CreatureView]:
	var found: Array[CreatureView] = []
	for view in views_in_view(camera, screen):
		if view.rimmed():
			found.append(view)
	var cell := PlaneSpace.to_world(sim.motion.position) if sim != null else Vector3.ZERO
	found.sort_custom(func(a: CreatureView, b: CreatureView) -> bool:
		return a.position.distance_squared_to(cell) < b.position.distance_squared_to(cell))
	return found.slice(0, max_count)


## Every drawn view (live, remnants and morsels, none leaving) whose centre lies on a `screen`-sized
## view of `camera`.
func views_in_view(camera: Camera3D, screen: Vector2) -> Array[CreatureView]:
	var out: Array[CreatureView] = []
	var eye := camera.global_transform if camera.is_inside_tree() else camera.transform
	var to_view := eye.affine_inverse()
	var project := Projection.create_perspective(camera.fov, screen.aspect(), camera.near, camera.far)
	for group in [_views, _remnant_views, _morsel_views]:
		for key in group:
			var view: CreatureView = group[key]
			if not is_instance_valid(view) or not view.visible or view.leaving() or view.dying:
				continue
			var v := to_view * view.position
			if v.z >= 0.0:
				continue
			var clip := project * Vector4(v.x, v.y, v.z, 1.0)
			var ndc := Vector2(clip.x, clip.y) / clip.w
			if absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0:
				out.append(view)
	return out


## The live creature's view, or null.
func view_of(id: String) -> CreatureView:
	return _views.get(id)


## Live views of awake creatures in creature order (dying views and sleepers are not counted).
func views() -> Array[CreatureView]:
	var out: Array[CreatureView] = []
	if sim == null or sim.creatures == null:
		return out
	for c in sim.creatures.creatures:
		if _views.has(c.id) and not c.asleep:
			out.append(_views[c.id])
	return out


## Reacts to one sim event (PoolScene._route calls it for every event).
func on_event(event: Dictionary) -> void:
	if sim == null or sim.creatures == null:
		return
	var id := str(event.get("id", ""))
	match str(event.get("type", "")):
		"creature_spawned":
			var c := sim.creatures.find(id)
			if c != null and not c.asleep and not _views.has(id):   # a sleeper is drawn when it wakes
				var view := _add_view(c)
				view.fade_in(sim.species.fade_in_ticks * PoolSim.DT)
		"creature_died":
			# A remnant dies with its creature's id (D-28), so its view dies the same way.
			var view: CreatureView = _views.get(id, _remnant_views.get(id))
			if view != null:
				_views.erase(id)
				_remnant_views.erase(id)
				view.die()
				if world_space != null:
					world_space.register(view)   # no longer synced; it leaves when it frees itself
		"creature_slept":
			var view: CreatureView = _views.get(id)
			if view != null:
				view.hide_lane()
				view.visible = false
		"creature_woke":
			var c := sim.creatures.find(id)
			if c != null:
				var view: CreatureView = _views.get(id)
				if view == null:
					view = _add_view(c)
				view.visible = true
				view.show_motion(c.motion, 1.0)   # where it woke, at once: no slide from where it slept
				view.show_brain(c.brain, sim.tick, 1.0)
		"creature_removed":
			# A death has already let its view go; this is a stuck creature taken out of sight, or
			# (S2) a sleeper or remnant leaving at a growth, which fades where it was.
			var view: CreatureView = _views.get(id, _remnant_views.get(id))
			if view != null:
				_views.erase(id)
				_remnant_views.erase(id)
				if str(event.get("reason", "")) in FADING_REMOVALS and view.visible:
					_let_go(view)
				else:
					remove_child(view)
					view.queue_free()
		"creature_converted":
			var view: CreatureView = _views.get(id)
			if view == null:
				return
			_views.erase(id)
			match str(event.get("to", "")):
				"remnant":
					_remnant_views[id] = view
					view.set_remnant(LIMP_FADE_S, LIMP_DELAY_S)
				"morsel":
					var food_id := str(event.get("food_id", ""))
					_morsel_views[food_id] = view
					view.set_morsel(food_id, float(event.get("radius", view.radius)))
				_:
					_let_go(view)
		"ate", "carrion_expired":
			var morsel: CreatureView = _morsel_views.get(str(event.get("food_id", "")))
			if morsel != null:
				_morsel_views.erase(morsel.morsel_id)
				_let_go(morsel)
			if str(event.type) == "ate":
				_sites.erase(str(event.get("food_id", "")))   # the swallow ghost carries it
		"creature_noticed":
			if event.get("target") == CreatureField.PLAYER_ID and _views.has(id):
				_views[id].show_marker()
		"creature_tell":
			if event.get("target") == CreatureField.PLAYER_ID and _views.has(id):
				_views[id].show_lane(event.lane)
		"tell_cancelled":
			if _views.has(id):
				_views[id].hide_lane()
		"creature_recovered":
			if _views.has(id):
				_views[id].hide_lane(CreatureView.LANE_FADE_S)
		"hit":
			var target_id := str(event.get("target", ""))
			var target: CreatureView = _views.get(target_id, _remnant_views.get(target_id))
			if target != null:
				target.hurt()
			if str(event.get("kind", "")) == "sting":
				var veil := view_of(str(event.get("attacker", "")))
				if veil != null and veil.threads != null:
					veil.threads.flash()


## Draws every live creature `fraction` of the way from the sim's previous tick to its current one
## (PoolScene's draw fraction), posed from its brain. A creature without a view (its spawn event
## was taken before the layer attached) gets one at once.
func sync(fraction: float) -> void:
	if sim == null or sim.creatures == null:
		return
	for c in sim.creatures.creatures:
		if c.asleep:
			continue
		var view: CreatureView = _views.get(c.id)
		if view == null:
			view = _add_view(c)
		view.show_motion(c.motion, fraction)
		view.show_brain(c.brain, sim.tick, fraction)
	_sync_converted(fraction)
	_sync_morsel_sites(sim.now() - (1.0 - fraction) * PoolSim.DT)


## Pauses or resumes every view's own animation (flashes, fades, the wag).
func set_paused(paused: bool) -> void:
	for child in get_children():
		child.set_process(not paused)


func _add_view(c: CreatureField.Creature) -> CreatureView:
	var view: CreatureView = VIEW_SCENE.instantiate()
	view.name = c.id
	view.build(sim.species, c.species_id, catalog, c.id, float(sim.creatures.record_of(c.species_id).get("q", 1.0)))
	add_child(view)
	if world_space != null:
		world_space.register(view.lane())
	view.show_motion(c.motion, 1.0)
	view.show_brain(c.brain, sim.tick, 1.0)
	_views[c.id] = view
	_relate(view, size(), 0.0)
	return view


## Draws the remnants from the sim (S2: they swim off, brainless, in a still pose) and the morsels
## where their carrion items lie.
func _sync_converted(fraction: float) -> void:
	var remnants: Variant = sim.get(&"remnants")
	if remnants != null:
		for r in remnants.items:
			var view: CreatureView = _remnant_views.get(r.id)
			if view != null:
				view.show_motion(r.motion, fraction)
	for food_id in _morsel_views.keys():
		var item := sim.carrion.find(food_id) if sim.carrion != null else {}
		var view: CreatureView = _morsel_views[food_id]
		if item.is_empty():
			# Taken some way the layer heard no event for (a creature ate it): it goes all the same.
			_morsel_views.erase(food_id)
			_let_go(view)
		else:
			view.position = PlaneSpace.to_world(item.position)


## The morsel-site items drawn now (their food ids, shrinking ones included).
func morsel_site_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _sites:
		out.append(id)
	return out


## How morsel-site item `food_id` was drawn last (its instance transform), or the identity.
func morsel_site_transform(food_id: String) -> Transform3D:
	return _sites.get(food_id, {}).get("drawn", Transform3D.IDENTITY)


## The baked morsel body of `species_id` (cached): body and parts in one surface, in M_Morsel.
func morsel_mesh(species_id: String) -> Mesh:
	if not _morsel_meshes.has(species_id):
		_morsel_meshes[species_id] = bake_morsel(sim.species, species_id, catalog)
		_morsel_radii[species_id] = sim.species.phenotype(species_id, catalog).radius
	return _morsel_meshes[species_id]


## The swallow ghost's mesh for carrion item `food_id`: its baked body when it is a morsel-site item
## drawn here, else null (the FoodView's mesh).
func morsel_mesh_for(food_id: String) -> Mesh:
	var site: Dictionary = _sites.get(food_id, {})
	return null if site.is_empty() else morsel_mesh(str(site.species))


## A creature view of `species_id` built at q 1, its Model's meshes merged into one surface placed
## as the view draws them (vertex colour kept, white where a mesh has none, for M_Morsel), and
## the view freed.
static func bake_morsel(species: SpeciesCatalog, species_id: String, p_catalog: PartCatalog) -> ArrayMesh:
	var view: CreatureView = VIEW_SCENE.instantiate()
	view.build(species, species_id, p_catalog, "", 1.0)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for node in view.get_node(^"Pivot/Model").find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != view:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var nb := t.basis.inverse().transposed()
		for surface in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mi.mesh.surface_get_arrays(surface)
			var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var sn: Variant = arrays[Mesh.ARRAY_NORMAL]
			var sc: Variant = arrays[Mesh.ARRAY_COLOR]
			var su: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var si: Variant = arrays[Mesh.ARRAY_INDEX]
			var base := vertices.size()
			for i in sv.size():
				vertices.append(t * sv[i])
				normals.append((nb * (sn as PackedVector3Array)[i]).normalized() if sn != null else Vector3.UP)
				colors.append((sc as PackedColorArray)[i] if sc != null else Color.WHITE)
				uvs.append((su as PackedVector2Array)[i] if su != null else Vector2.ZERO)
			if si != null:
				for i in (si as PackedInt32Array):
					indices.append(base + i)
			else:
				for i in sv.size():
					indices.append(base + i)
	view.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Draws the morsel-site items at sim time `now`: every item in the sim, and the ones that went
## without being eaten until they have shrunk out.
func _sync_morsel_sites(now: float) -> void:
	if sim.carrion == null:
		return
	var seen := {}
	for item in sim.carrion.items:
		if item.get("source", "") != MORSEL_SOURCE:
			continue
		var id := str(item.id)
		seen[id] = true
		var site: Dictionary = _sites.get(id, {})
		if site.is_empty():
			site = {"species": str(item.get("species", "")), "first_seen": now, "gone_at": -1.0,
				"yaw": WorldHash.unit(WorldHash.str32(id)) * TAU}
			_sites[id] = site
		site.position = item.position
		site.radius = float(item.radius)
	for id in _sites.keys():
		var site: Dictionary = _sites[id]
		if seen.has(id):
			continue
		if float(site.gone_at) < 0.0:
			site.gone_at = now
		elif now - float(site.gone_at) >= MORSEL_OUT_S:
			_sites.erase(id)
	if _sites.is_empty() and _sites_root == null:
		return
	if _sites_root == null:
		_sites_root = Node3D.new()
		_sites_root.name = "MorselSites"
		add_child(_sites_root)
	var by_species := {}
	for id in _sites:
		var species_id := str(_sites[id].species)
		if not by_species.has(species_id):
			by_species[species_id] = PackedStringArray()
		by_species[species_id].append(id)
	var rimmed := sim.phenotype != null and sim.phenotype.can_eat("meat")
	for child in _sites_root.get_children():
		var species_id := str(child.name).trim_suffix("__rim")
		if not by_species.has(species_id) or (str(child.name).ends_with("__rim") and not rimmed):
			(child as MultiMeshInstance3D).multimesh.instance_count = 0
	for species_id: String in by_species:
		var ids: PackedStringArray = by_species[species_id]
		var body := _site_multimesh(species_id, false)
		var rim := _site_multimesh(species_id, true) if rimmed else null
		for mm in [body, rim]:
			if mm != null and mm.instance_count != ids.size():
				mm.instance_count = ids.size()
		var r := float(_morsel_radii.get(species_id, 1.0))
		for i in ids.size():
			var site: Dictionary = _sites[ids[i]]
			var shown := smoothstep(0.0, MORSEL_IN_S, now - float(site.first_seen))
			if float(site.gone_at) >= 0.0:
				shown *= 1.0 - clampf((now - float(site.gone_at)) / MORSEL_OUT_S, 0.0, 1.0)
			var s := maxf(float(site.radius) / maxf(r, 1e-6) * shown, 1e-4)
			var t := Transform3D(Basis(Vector3.UP, float(site.yaw)).scaled(Vector3.ONE * s), PlaneSpace.to_world(site.position))
			site.drawn = t
			body.set_instance_transform(i, t)
			if rim != null:
				rim.set_instance_transform(i, t)
				rim.set_instance_custom_data(i, Color(shown, 0.0, 0.0, 0.0))


## The MultiMesh drawing `species_id`'s morsel-site items (or their rim), made on first use.
func _site_multimesh(species_id: String, rim: bool) -> MultiMesh:
	var key := species_id + ("__rim" if rim else "")
	var mmi := _sites_root.get_node_or_null(NodePath(key)) as MultiMeshInstance3D
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = key
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = rim
		mm.mesh = morsel_mesh(species_id)
		mmi.multimesh = mm
		if rim:
			var material := ShaderMaterial.new()
			material.shader = MORSEL_RIM_SHADER
			material.set_shader_parameter("color", CreatureView.RIM_COLOR)
			material.set_shader_parameter("grow", CreatureView.RIM_GROW_TM)
			mmi.material_override = material
		else:
			mmi.material_override = MORSEL_MATERIAL
		_sites_root.add_child(mmi)
	return mmi.multimesh


## A view no longer drawn from the sim fades out where it is; WorldSpace moves it until it frees itself.
func _let_go(view: CreatureView) -> void:
	view.fade_out(LEAVE_S)
	if world_space != null:
		world_space.register(view)
