class_name LadderStrip
extends VBoxContainer
## The ladder strip (S2, s2-view 7.4): at the bottom right, above the bottom arrows' band, the
## species near the cell now and the ghosts of the sizes to come, at most MAX_ENTRIES, each an icon
## tinted by what it is to the cell at the size shown, with its plural under it so colour is never
## the only cue; and a line on what the next growth changes, or at the build's top what a later
## build brings. Hidden in the pool, which has no growth (D-46), and with nothing to show.
##
##   entries   the species of the creature views on screen (live, remnants), nearest the cell first,
##             then the ghost layer's near species; each once
##   role      Relationships' ladder role at the shown size n (the catalog's at_size for a species it
##             has, the ghost ladder's radius for one still to come), "ghost" above n; next_role the
##             same at n + 1
##   icon      its haze sprite (ghost_ladder.json haze), tinted: threat ink, prey or morsel the rim's
##             green when the cell can eat meat, else neutral; a ghost shows its ghost sprite faint
##   preview   "UI_AFTER_YOUR_NEXT_GROWTH_904015" and the first MAX_PHRASES phrases by PHRASE_ORDER, then
##             entry order; at the top "UI_COMING_IN_A_LATER_BUILD_10974C" and the ladder's preview
##
## Refreshed every REFRESH_S and at the growth beat's chord (the HUD calls refresh()). Each icon sits
## in a SLOT_W column with its caption wrapped under it, and the line wraps in the icons' width, so
## at the largest text size the panel stays clear of the bottom center's hints (test_ui_text).

const MAX_ENTRIES := 6
const MAX_PHRASES := 2
const REFRESH_S := 0.5
const ICON_PX := 40.0
const CAPTION_SIZE := 12
const GHOST_ALPHA := 0.5
## Each icon's column (its caption wraps in it, two lines at most for the shipped plurals) and the
## gap between columns; the preview line wraps in the width of six.
const SLOT_W := 68.0
const SLOT_GAP := 8
const PREVIEW_W := MAX_ENTRIES * SLOT_W + (MAX_ENTRIES - 1) * SLOT_GAP
## The most lines the longest preview the shipped ladder gives takes at the largest text size.
const PREVIEW_MAX_LINES := 3
## Clear of the bottom arrows' band by this much (s2-view 7.1).
const BAND_GAP_PX := 8.0
const INK := CreatureView.MARKER_COLOR
const RIM := CreatureView.RIM_COLOR
const NEUTRAL := CreatureView.NEUTRAL_CREST
## The phrases' order in the preview line (keys of phrase_key); ties keep entry order.
const PHRASE_ORDER: PackedStringArray = ["flee", "appear", "ignore", "morsels", "haze"]
const PHRASES := {"flee": "UI_S_FLEE_FROM_YOU_DD999A", "appear": "UI_S_APPEAR_BB549D", "ignore": "UI_S_IGNORE_YOU_9738D8",
	"morsels": "UI_S_BECOME_MORSELS_CB975E", "haze": "UI_S_FADE_TO_HAZE_194027"}
const PREVIEW_PREFIX := "UI_AFTER_YOUR_NEXT_GROWTH_904015"
const TOP_PREFIX := "UI_COMING_IN_A_LATER_BUILD_10974C"

var pool: PoolScene

var _t := 0.0
var _entries: Array[Dictionary] = []
var _panel: PanelContainer
var _icons: HBoxContainer
var _preview: Label
var _gap: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 0)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"HudPanel"
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_panel.add_child(box)
	_icons = HBoxContainer.new()
	_icons.name = "Icons"
	_icons.alignment = BoxContainer.ALIGNMENT_END
	_icons.add_theme_constant_override(&"separation", SLOT_GAP)
	box.add_child(_icons)
	_preview = Label.new()
	_preview.name = "Preview"
	_preview.theme_type_variation = &"SmallLabel"
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(PREVIEW_W, 0.0)
	box.add_child(_preview)
	_gap = Control.new()
	_gap.name = "Gap"
	add_child(_gap)
	_place_gap()
	for node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Starts showing `p_pool`'s strip.
func bind(p_pool: PoolScene) -> void:
	pool = p_pool
	_t = 0.0
	refresh()


func _process(delta: float) -> void:
	if pool == null or pool.paused:
		return
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH_S
		refresh()


## Rebuilds the entries and the preview line from the pool now.
func refresh() -> void:
	var growth := pool.growth() if pool != null and pool.sim != null else null
	if growth == null:
		_entries.clear()
		visible = false
		return
	var n := pool.shown_size()
	var ladder := pool.ghosts.ladder() if pool.ghosts != null else {}
	_entries = entries_for(live_species(pool), pool.ghosts.near_species(n) if pool.ghosts != null else PackedStringArray(),
		n, pool.sim.species, ladder)
	var at_top: bool = growth.at_top(n, pool.max_size())
	_show(_entries, pool.sim.phenotype.can_eat("meat"), preview_line(_entries, at_top, n, ladder))


## The species of the creature views on screen, nearest the cell first, each once.
static func live_species(p_pool: PoolScene) -> PackedStringArray:
	if p_pool.camera == null:
		return PackedStringArray()
	var views := p_pool.creature_layer.views_in_view(p_pool.camera, p_pool.view_size())
	var cell := p_pool.cell_view.position
	views.sort_custom(func(a: CreatureView, b: CreatureView) -> bool:
		return a.position.distance_squared_to(cell) < b.position.distance_squared_to(cell))
	var out := PackedStringArray()
	for view in views:
		if view.species_id != "" and not out.has(view.species_id):
			out.append(view.species_id)
	return out


## The strip's entries: `live` then `ghosts`, each species once, at most MAX_ENTRIES, as
## {id, role, next_role, plural, texture} at size n (texture a res:// path, "" when there is none).
static func entries_for(live: PackedStringArray, ghosts: PackedStringArray, n: int, species: SpeciesCatalog, ladder: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for id in live + ghosts:
		if seen.has(id) or out.size() >= MAX_ENTRIES:
			continue
		seen[id] = true
		var role := role_at(id, n, species, ladder)
		out.append({"id": id, "role": role, "next_role": role_at(id, n + 1, species, ladder),
			"plural": plural_of(id, ladder), "texture": texture_of(id, role, ladder)})
	return out


## What species `id` is to a cell of size n: "ghost" below its entry size, else the catalog's
## ladder role at n (its at_size), or for a species only the ghost ladder names, Relationships'
## role for the ladder's radius at n; "haze" for one neither knows.
static func role_at(id: String, n: int, species: SpeciesCatalog, ladder: Dictionary) -> String:
	var known := species != null and species.has_species(id)
	var in_ladder: bool = ladder.get("species", {}).has(id)
	var entry := species.entry_size(id) if known else (int(ladder.species[id].entry_size) if in_ladder else 1)
	if entry > n:
		return "ghost"
	if known:
		return str(species.at_size(id, n).get("ladder_role", "haze"))
	if in_ladder:
		return Relationships.ladder_role(entry, n, GhostLayer.true_radius(ladder, id, n))
	return "haze"


## The ladder's plural for a species ("Lurkers", "rammers"); its id in words with an "s" otherwise.
static func plural_of(id: String, ladder: Dictionary) -> String:
	for group in ["species", "names"]:
		if ladder.get(group, {}).has(id):
			return str(ladder[group][id].plural)
	return id.replace("_", " ") + "s"


## A ghost's sprite for a species still to come, else its haze sprite; "" when the ladder has none.
static func texture_of(id: String, role: String, ladder: Dictionary) -> String:
	if role == "ghost" and ladder.get("species", {}).has(id):
		return str(ladder.species[id].texture)
	return str(GhostLayer.haze_paths(ladder).get(id, ""))


## The icon's tint: ink for a threat, the rim's green for prey or a morsel when the cell can eat
## meat, a faint white over a ghost's own sprite, neutral otherwise.
static func tint_of(role: String, has_jaw: bool) -> Color:
	match role:
		"threat":
			return INK
		"ghost":
			return Color(1.0, 1.0, 1.0, GHOST_ALPHA)
		"prey", "morsel":
			return RIM if has_jaw else NEUTRAL
	return NEUTRAL


## Which phrase a change of role from `from` to `to` takes (PHRASES' keys), "" for none: no change,
## or a change the table does not word.
static func phrase_key(from: String, to: String) -> String:
	if from == to:
		return ""
	match to:
		"prey":
			return "flee"
		"morsel":
			return "morsels"
		"haze":
			return "haze"
		"rival":
			return "ignore" if from == "threat" else ""
		"threat":
			return "appear" if from == "ghost" else ""
	return ""


## The phrase for `plural` going from `from` to `to` ("rammers flee from you"), "" for none.
static func phrase(plural: String, from: String, to: String) -> String:
	var key := phrase_key(from, to)
	return TranslationServer.translate(PHRASES[key]) % plural if key != "" else ""


## The preview line: at the build's top the ladder's preview for size n; else the first MAX_PHRASES
## phrases of `entries` by PHRASE_ORDER, then entry order; "" with none.
static func preview_line(entries: Array[Dictionary], at_top: bool, n: int, ladder: Dictionary) -> String:
	if at_top:
		var preview := str(ladder.get("preview_at_top", {}).get(str(n), ""))
		return TranslationServer.translate(TOP_PREFIX) + " " + preview if preview != "" else ""
	var keyed := []
	for i in entries.size():
		var e := entries[i]
		var key := phrase_key(str(e.role), str(e.next_role))
		if key != "":
			keyed.append([PHRASE_ORDER.find(key), i, TranslationServer.translate(PHRASES[key]) % str(e.plural)])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var phrases := PackedStringArray()
	for k in keyed.slice(0, MAX_PHRASES):
		phrases.append(k[2])
	return TranslationServer.translate(PREVIEW_PREFIX) + " " + "; ".join(phrases) if not phrases.is_empty() else ""


## The entries drawn now (for checks).
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## The icons drawn now (for checks): [{texture (res:// path), tint, caption}].
func icons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in _icons.get_children():
		if not (slot as Control).visible:
			continue
		var icon := slot.get_child(0) as TextureRect
		out.append({"texture": icon.texture.resource_path if icon.texture != null else "", "tint": icon.self_modulate,
			"caption": (slot.get_child(1) as Label).text})
	return out


## The preview line drawn now, "" when hidden.
func preview_text() -> String:
	return _preview.text if _preview.visible else ""


func _show(entries: Array[Dictionary], has_jaw: bool, preview: String) -> void:
	while _icons.get_child_count() < entries.size():
		_icons.add_child(_icon_slot())
	for i in _icons.get_child_count():
		var slot := _icons.get_child(i) as VBoxContainer
		slot.visible = i < entries.size()
		if not slot.visible:
			continue
		var e := entries[i]
		var icon := slot.get_child(0) as TextureRect
		var path := str(e.texture)
		icon.texture = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		icon.self_modulate = tint_of(str(e.role), has_jaw)
		(slot.get_child(1) as Label).text = str(e.plural)
	_preview.text = preview
	_preview.visible = preview != ""
	visible = not entries.is_empty()


func _icon_slot() -> VBoxContainer:
	var slot := VBoxContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(SLOT_W, 0.0)
	slot.add_theme_constant_override(&"separation", 2)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	var caption := Label.new()
	caption.add_theme_font_size_override(&"font_size", CAPTION_SIZE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size = Vector2(SLOT_W, 0.0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(caption)
	return slot


## The gap under the panel: from the frame's bottom margin up to BAND_GAP_PX over the arrows' band.
func _place_gap() -> void:
	var margin := 0.0
	var frame := get_parent() as MarginContainer
	if frame != null:
		margin = float(frame.get_theme_constant(&"margin_bottom"))
	_gap.custom_minimum_size = Vector2(0.0, maxf(ThreatIndicators.band_px() + BAND_GAP_PX - margin, 0.0))
