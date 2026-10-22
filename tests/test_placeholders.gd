extends TestCase
## Bible 15: production visuals come from Blender, never from engine primitives. Every primitive
## or code-built mesh in game/ must be listed in the placeholder inventory, as functional
## (particles, UI, debug drawing) or as a placeholder with the milestone that removes it. So must
## any binary resource or model file kept in game/, since its text cannot be scanned. A
## placeholder whose asset now has a record must be removed from the code and the inventory.

const INVENTORY_PATH := "res://assets/records/placeholders/inventory.json"
const RECORDS_DIR := "res://assets/records"
const SCAN_ROOT := "res://game"
const SCAN_EXTENSIONS := ["gd", "tscn", "tres"]
## Files whose contents the text scan cannot read. Each one in game/ is a hit of its own: a saved
## mesh or scene, or a model that belongs in assets/export with a record.
const FILE_HIT_TYPES := {
	"res": "binary resource", "mesh": "binary resource", "scn": "binary resource",
	"obj": "model file", "glb": "model file", "gltf": "model file", "fbx": "model file",
	"blend": "model file", "dae": "model file",
}
## Engine primitives: meshes and CSG shapes that are not authored in Blender.
const PRIMITIVE_TYPES := [
	"BoxMesh", "CapsuleMesh", "CylinderMesh", "PlaneMesh", "PointMesh", "PrismMesh", "QuadMesh",
	"RibbonTrailMesh", "SphereMesh", "TextMesh", "TorusMesh", "TubeTrailMesh", "PrimitiveMesh",
	"CSGBox3D", "CSGCylinder3D", "CSGMesh3D", "CSGPolygon3D", "CSGSphere3D", "CSGTorus3D",
]
## Holds instances of another mesh and no geometry of its own.
const NOT_GEOMETRY := ["MultiMesh"]
const AUDIO_CUES := ["sfx_eat_plant", "sfx_eat_meat", "sfx_refuse", "sfx_starve_pulse", "amb_pool_loop"]

var _primitive_re := RegEx.create_from_string("\\b(%s)\\b" % "|".join(PackedStringArray(PRIMITIVE_TYPES)))
## Meshes built in code (ArrayMesh, ImmediateMesh, any *Mesh) and SurfaceTool.
var _built_re := RegEx.create_from_string("\\b(\\w*Mesh|SurfaceTool)\\.new\\(")
## Meshes in a scene or resource file: embedded, saved as a resource of their own, or referenced.
var _embedded_re := RegEx.create_from_string("\\[(?:gd_resource|sub_resource|ext_resource) type=\"(\\w*Mesh)\"")


func _inventory() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	return data if data is Dictionary else {}


func _record_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(RECORDS_DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


## Every file under `dir` with one of `extensions`, recursively.
func _game_files(dir: String, extensions: Array, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in extensions:
			out.append(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		_game_files(dir + "/" + sub, extensions, out)


## Binary resources and model files among `files`, as hits like _scan_text's (line 0: the whole file).
func _file_hits(files: PackedStringArray) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for file in files:
		var type: String = FILE_HIT_TYPES.get(file.get_extension().to_lower(), "")
		if type != "":
			hits.append({"file": file, "type": type, "line": 0})
	return hits


## Mesh types named in one file's text, as [{"file", "type", "line"}], first mention of each type.
## Whole-line comments are skipped; anything else that names a primitive counts.
func _scan_text(file: String, text: String) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var seen := {}
	var lines := text.split("\n")
	for i in lines.size():
		var trimmed := lines[i].strip_edges()
		if trimmed.begins_with("#") or trimmed.begins_with(";"):
			continue
		var types := PackedStringArray()
		for m in _primitive_re.search_all(trimmed):
			types.append(m.get_string(1))
		for re: RegEx in [_built_re, _embedded_re]:
			for m in re.search_all(trimmed):
				if not m.get_string(1) in NOT_GEOMETRY:
					types.append(m.get_string(1))
		for type in types:
			if not seen.has(type):
				seen[type] = true
				hits.append({"file": file, "type": type, "line": i + 1})
	return hits


## Hits that no inventory entry (functional or placeholder) lists by both type and file.
func _unlisted(hits: Array[Dictionary], inventory: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for hit in hits:
		var listed := false
		for group in ["functional", "placeholders"]:
			for entry: Dictionary in inventory.get(group, []):
				if hit.type in entry.get("types", []) and hit.file in entry.get("files", []):
					listed = true
		if not listed:
			out.append("%s:%d %s" % [hit.file, hit.line, hit.type] if hit.line > 0 else "%s %s" % [hit.file, hit.type])
	return out


## Placeholders whose asset now has a record, so the stand-in must go.
func _replaced_placeholders(inventory: Dictionary, record_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in inventory.get("placeholders", []):
		if String(entry.get("asset_id", "")) in record_ids:
			out.append("%s (asset %s has a record)" % [entry.get("id"), entry.get("asset_id")])
	return out


func test_the_scanner_finds_primitive_and_code_built_meshes_but_not_multimeshes() -> void:
	var text := "\n".join([
		"var box := BoxMesh.new()",
		"[sub_resource type=\"QuadMesh\" id=\"QuadMesh_1\"]",
		"\tlines = ImmediateMesh.new()",
		"var shape := CSGSphere3D.new()",
		"var st := SurfaceTool.new()",
		"[sub_resource type=\"ArrayMesh\" id=\"ArrayMesh_2\"]",
		"var many := MultiMesh.new()",
		"[sub_resource type=\"MultiMesh\" id=\"MultiMesh_3\"]",
		"## A whole-line comment about a SphereMesh is not a use.",
		"var again := BoxMesh.new()",
	])
	var types := PackedStringArray()
	for hit in _scan_text("game/x.gd", text):
		types.append(hit.type)
	types.sort()
	check_eq(types, PackedStringArray(["ArrayMesh", "BoxMesh", "CSGSphere3D", "ImmediateMesh", "QuadMesh", "SurfaceTool"]), "types found")
	var first: Dictionary = _scan_text("game/x.gd", text)[0]
	check_eq(first, {"file": "game/x.gd", "type": "BoxMesh", "line": 1}, "a hit names its file and first line")


func test_the_scanner_finds_a_mesh_saved_as_its_own_resource_or_referenced_by_a_scene() -> void:
	# A mesh baked to an ArrayMesh and saved from the editor, and a scene that references it.
	var saved := _scan_text("game/rock_standin.tres", "[gd_resource type=\"ArrayMesh\" format=4]\n\n[resource]")
	check_eq(saved.size(), 1, "a saved ArrayMesh resource is a hit")
	if saved.size() == 1:
		check_eq(saved[0], {"file": "game/rock_standin.tres", "type": "ArrayMesh", "line": 1}, "saved mesh hit")
	var scene := "\n".join([
		"[gd_scene load_steps=3 format=3]",
		"[ext_resource type=\"ArrayMesh\" path=\"res://game/rock_standin.tres\" id=\"1_a\"]",
		"[ext_resource type=\"Mesh\" path=\"res://game/ball.res\" id=\"2_b\"]",
		"[ext_resource type=\"MultiMesh\" path=\"res://game/many.tres\" id=\"3_c\"]",
		"[ext_resource type=\"Script\" path=\"res://game/x.gd\" id=\"4_d\"]",
	])
	var types := PackedStringArray()
	for hit in _scan_text("game/standin.tscn", scene):
		types.append(hit.type)
	types.sort()
	check_eq(types, PackedStringArray(["ArrayMesh", "Mesh"]), "meshes a scene references, but not a MultiMesh")


func test_binary_resources_and_model_files_in_game_are_hits_of_their_own() -> void:
	var files := PackedStringArray([
		"game/scenes/pool/ball.res", "game/scenes/pool/rock.mesh", "game/scenes/pool/saved.scn",
		"game/scenes/pool/blob.obj", "game/scenes/pool/stand_in.glb", "game/scenes/pool/stand_in.GLTF",
		"game/scenes/pool/rig.fbx", "game/scenes/pool/source.blend",
		"game/scenes/pool/pool.gd", "game/scenes/pool/pool.tscn", "game/scenes/pool/pool_environment.tres",
		"game/scenes/pool/stand_in.glb.import", "game/data/pool_m1.json",
	])
	var found := PackedStringArray()
	for hit in _file_hits(files):
		found.append("%s %s" % [hit.file.get_file(), hit.type])
	check_eq(found, PackedStringArray([
		"ball.res binary resource", "rock.mesh binary resource", "saved.scn binary resource",
		"blob.obj model file", "stand_in.glb model file", "stand_in.GLTF model file",
		"rig.fbx model file", "source.blend model file",
	]), "file hits")
	var inventory := {"functional": [{"id": "x", "types": ["model file"], "files": ["game/scenes/pool/blob.obj"]}]}
	check_eq(_unlisted(_file_hits(PackedStringArray(["game/scenes/pool/blob.obj", "game/scenes/pool/ball.res"])), inventory),
		PackedStringArray(["game/scenes/pool/ball.res binary resource"]), "a listed file passes and an unlisted one is reported")


func test_an_unlisted_mesh_is_reported_and_a_listed_one_is_not() -> void:
	var inventory := {
		"functional": [{"id": "fx", "types": ["QuadMesh"], "files": ["game/fx.tscn"]}],
		"placeholders": [{"id": "rock", "asset_id": "rock_z", "types": ["SphereMesh"], "files": ["game/rocks.gd"], "remove_by": "M9"}],
	}
	var hits: Array[Dictionary] = [
		{"file": "game/fx.tscn", "type": "QuadMesh", "line": 3},
		{"file": "game/rocks.gd", "type": "SphereMesh", "line": 7},
		{"file": "game/other.gd", "type": "QuadMesh", "line": 9},
		{"file": "game/fx.tscn", "type": "BoxMesh", "line": 4},
	]
	check_eq(_unlisted(hits, inventory), PackedStringArray(["game/other.gd:9 QuadMesh", "game/fx.tscn:4 BoxMesh"]), "unlisted hits")


func test_a_placeholder_whose_asset_now_has_a_record_is_reported() -> void:
	var inventory := {"placeholders": [
		{"id": "old_cell", "asset_id": "sample_cell"},
		{"id": "beep", "asset_id": "sfx_not_recorded"},
	]}
	check_eq(_replaced_placeholders(inventory, _record_ids()), PackedStringArray(["old_cell (asset sample_cell has a record)"]), "replaced")


func test_the_inventory_lists_the_synthesized_audio_and_the_functional_primitives() -> void:
	var inventory := _inventory()
	check(inventory.get("placeholders") is Array and inventory.get("functional") is Array, "inventory has placeholders and functional lists")
	var ids := {}
	for group in ["functional", "placeholders"]:
		for entry: Dictionary in inventory.get(group, []):
			var id := String(entry.get("id", ""))
			check(id != "" and not ids.has(id), "entry id '%s' is set and unique" % id)
			ids[id] = true
			check(entry.get("types") is Array and not entry.types.is_empty(), "%s lists its types" % id)
			check(entry.get("files") is Array and not entry.files.is_empty(), "%s lists its files" % id)
			for file in entry.get("files", []):
				check(String(file).begins_with("game/"), "%s file %s is a game/ path" % [id, file])
			if group == "placeholders":
				check(String(entry.get("asset_id", "")) != "", "%s names the asset it stands in for" % id)
				check(String(entry.get("remove_by", "")) != "", "%s names the milestone that removes it" % id)
	for cue in AUDIO_CUES:
		var found := false
		for entry: Dictionary in inventory.get("placeholders", []):
			if entry.get("asset_id") == cue:
				found = true
				check_eq(entry.get("remove_by"), "M1 step 5", "%s removed by" % cue)
		check(found, "audio cue %s is listed as a placeholder" % cue)
	for type in ["QuadMesh", "Label3D", "ImmediateMesh"]:
		var found := false
		for entry: Dictionary in inventory.get("functional", []):
			found = found or type in entry.get("types", [])
		check(found, "%s is listed as functional" % type)


func test_every_mesh_in_game_code_is_listed_and_no_placeholder_outlived_its_asset() -> void:
	var inventory := _inventory()
	var files := PackedStringArray()
	_game_files(SCAN_ROOT, SCAN_EXTENSIONS, files)
	check(files.size() > 0, "found game files to scan")
	var hits: Array[Dictionary] = []
	for path in files:
		hits.append_array(_scan_text(path.trim_prefix("res://"), FileAccess.get_file_as_string(path)))
	var opaque := PackedStringArray()
	_game_files(SCAN_ROOT, FILE_HIT_TYPES.keys(), opaque)
	for i in opaque.size():
		opaque[i] = opaque[i].trim_prefix("res://")
	hits.append_array(_file_hits(opaque))
	var unlisted := _unlisted(hits, inventory)
	check(unlisted.is_empty(), "meshes not in %s: %s" % [INVENTORY_PATH, unlisted])
	var replaced := _replaced_placeholders(inventory, _record_ids())
	check(replaced.is_empty(), "placeholders to remove: %s" % replaced)
