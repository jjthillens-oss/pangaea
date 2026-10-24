extends TestCase
## S3's creature views (docs/s3/s3-view.md 8; S3G32 F part): the four band-1 bodies, their eyes and
## their ink at sizes 3 and 4.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const VIEW_SCENE := preload("res://game/scenes/pool/creature_view.tscn")
const SETTINGS_PATH := "user://test_creature_views/settings.cfg"
const THREAT_INK := Color("#D9466B")
const DT := 1.0 / 60.0
## Species, the body family whose pose nodes it carries, and its body material (C3V-13).
const S3_BODIES := {
	"veil": ["ambush", "res://assets/export/M_VeilBody.tres"],
	"warden": ["territorial", "res://assets/export/M_WardenBody.tres"],
	"deep_lurker": ["ambush", "res://assets/export/M_DeepLurkerBody.tres"],
	"elder_warden": ["territorial", "res://assets/export/M_ElderWardenBody.tres"],
}

var _species: SpeciesCatalog
var _catalog: PartCatalog


func before_each() -> void:
	if _species == null:
		_species = SpeciesCatalog.load_from()
		_catalog = PartCatalog.load_from()
	SettingsService.set_shared(SettingsService.new(SETTINGS_PATH))


func after_each() -> void:
	SettingsService.set_shared(null)


func test_four_bodies_and_their_contracts() -> void:
	for id in S3_BODIES:
		var asset := str(_species.species[id].body_asset)
		check(CreatureView.BODY_SCENES.has(asset), "%s: %s is a body the view can draw" % [id, asset])
		var view := _view(id, 1.0)
		var body := view._model.get_node_or_null(^"Body")
		check(body != null, "%s: the body is built" % id)
		if body == null:
			view.free()
			continue
		var family: String = S3_BODIES[id][0]
		if family == "territorial":
			check(view._hood != null, "%s: the hood a territorial puff raises" % id)
			check(view._brow == null, "%s: no ambush brow" % id)
		else:
			check(view._brow != null, "%s: the brow an ambush coil lowers" % id)
			check(view._hood == null, "%s: no rammer hood" % id)
		var mesh := body.get_node_or_null(CreatureView.BODY_MESH_PATH) as MeshInstance3D
		check(mesh != null, "%s: the body mesh" % id)
		if mesh != null:
			var material := mesh.get_active_material(0)
			check_eq(material.resource_path if material != null else "", S3_BODIES[id][1], "%s: its own body material" % id)
		view.free()


func test_eye_rest_per_body() -> void:
	var deep := _view("deep_lurker", 1.0)
	check(deep._eye_material != null, "the Deep lurker's eyes glow")
	check_near(deep._eye_material.emission_energy_multiplier, CreatureView.EYE_GLOW_IDLE / 0.7, 1e-6,
		"the Deep lurker idles at 0.2 over its rest 0.7")
	deep.free()
	var ambush := _view("ambush_hunter", 1.0)
	check_near(ambush._eye_material.emission_energy_multiplier, CreatureView.EYE_GLOW_IDLE / 0.4, 1e-6,
		"the ambush hunter keeps M1's rest 0.4")
	ambush.free()
	var veil := _view("veil", 1.0)
	check(veil._eye_material == null, "the veil's eyes are not emissive, so nothing drives them")
	veil._apply_pose(CreatureView.pose(CreatureBrain.AMBUSH, "attack/tell", 1.0))
	veil.free()


func test_ink_at_sizes_3_and_4() -> void:
	var cell := _cell("omnivore")
	var want := {
		"warden": {3: true, 4: false},
		"elder_warden": {4: true},
		"deep_lurker": {4: true},
		"lurker": {3: false, 4: false},
		"elder_rammer": {3: false, 4: false},
	}
	for id in want:
		for n: int in want[id]:
			check(_species.live_at(id, n), "%s lives at size %d" % [id, n])
			var q := _species.q_of(id, n)
			var view := _view(id, 1.0)
			view.set_q(q)
			var r := CreatureLayer.relation_of(_species, id, q, view.radius, n, cell)
			view.set_relation(r.can_attack, r.rimmed, 1.0)
			_run(view, 1.05)
			var attacks: bool = want[id][n]
			var tag := "%s at size %d" % [id, n]
			check_eq(r.can_attack, attacks, "%s: attacks" % tag)
			check_near(view.ink, 1.0 if attacks else 0.0, 1e-9, "%s: ink after the 1 s fade" % tag)
			var crest := _crest(view)
			if crest != null:
				var colour := THREAT_INK if attacks else CreatureView.NEUTRAL_CREST
				check(crest.albedo_color.is_equal_approx(colour), "%s: M_Threat %s, want %s" % [
					tag, crest.albedo_color.to_html(), colour.to_html()])
			elif id in ["warden", "elder_warden"]:
				check(false, "%s: the Warden's crest is M_Threat" % tag)
			view.free()


## A view of `id` at `q`, outside the tree, built as the layer builds one.
func _view(id: String, q: float) -> CreatureView:
	var view: CreatureView = VIEW_SCENE.instantiate()
	FakeEvents.ready_tree(view)
	view.build(_species, id, _catalog, "c_" + id, q)
	return view


## Runs the view's own animation for `seconds` at 60 fps.
func _run(view: CreatureView, seconds: float) -> void:
	for i in roundi(seconds / DT):
		view._process(DT)


func _cell(body: String) -> Phenotype:
	var founded := Lineage.found(7, "test", _catalog, body)
	return Phenotype.derive(founded.save.genome, _catalog)


## The view's own M_Threat material, or null.
static func _crest(view: CreatureView) -> BaseMaterial3D:
	for slot in view._ink_slots:
		if (slot.material as BaseMaterial3D).resource_name == "M_Threat":
			return slot.material
	return null
