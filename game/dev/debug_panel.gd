extends CanvasLayer
## Debug builds only (M1 step 2): a panel on the right with the run's identity, the sim, rendering
## and performance, the actor, its derived stats, the last feeding results and the ecology, plus
## dev commands. F3 shows and hides it (dev_keys.gd); it refreshes at 4 Hz while shown. Every
## sim command goes through a PoolSim debug_* method, which logs a "debug" event.
##
## Main loads it by path from its guarded dev loader (no class_name, so nothing outside game/dev
## can depend on it). `fields` keeps the latest shown values by name, for checks.

const REFRESH_S := 0.25
const FRAME_WINDOW := 60            ## frames the longest-frame figure looks back over
const VSYNC_NAMES := {
	DisplayServer.VSYNC_DISABLED: "off", DisplayServer.VSYNC_ENABLED: "on",
	DisplayServer.VSYNC_ADAPTIVE: "adaptive", DisplayServer.VSYNC_MAILBOX: "mailbox",
}

var main: Node
## The latest shown values by name: build_id, genome_id, lineage_id, world_seed, slot, tick,
## fps, longest_frame_ms, draw_calls, adapter, driver, vsync, energy, position, and so on.
var fields := {}

var _refresh_t := 0.0
## Wall-clock frame times in ms, as in perf_tour.gd (the process delta caps a stall near 150 ms).
var _frame_ms := PackedFloat32Array()
var _last_frame_usec := -1
var _zone_rows := {}                 ## zone id -> {"bar": ProgressBar, "text": Label}
var _zones_sim: PoolSim              ## the sim the zone rows were built for

@onready var _identity: Label = %Identity
@onready var _sim: Label = %Sim
@onready var _render: Label = %Render
@onready var _actor: Label = %Actor
@onready var _stats: Label = %Stats
@onready var _feeding: Label = %Feeding
@onready var _zones: GridContainer = %Zones
@onready var _carrion: Label = %Carrion
@onready var _buttons := {
	"fill": %Fill, "drain": %Drain, "empty_zone": %EmptyZone, "spawn_carrion": %SpawnCarrion,
	"teleport": %Teleport, "gizmos": %Gizmos, "vsync": %VSync, "copy": %Copy,
}


func _ready() -> void:
	visible = false
	for command: String in _buttons:
		var button: Button = _buttons[command]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(run.bind(command))


func attach(p_main: Node) -> void:
	main = p_main
	main.screen_changed.connect(func(_screen: Node): refresh())


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


## Runs a dev command by name: fill, drain, empty_zone, spawn_carrion, teleport (to the layout
## spawn), gizmos, vsync or copy. Returns whether it applied.
func run(command: String) -> bool:
	var sim := _current_sim()
	var applied := false
	match command:
		"fill":
			applied = sim != null and sim.debug_set_energy(sim.state.energy_capacity)
		"drain":
			applied = sim != null and sim.debug_set_energy(0.0)
		"empty_zone":
			applied = sim != null and sim.debug_empty_zone(sim.nearest_zone_id())
		"spawn_carrion":
			applied = sim != null and sim.debug_spawn_carrion_ahead()
		"teleport":
			applied = sim != null and sim.debug_teleport(sim.layout.spawn, sim.layout.spawn_heading)
		"gizmos":
			var gizmos: Node3D = main.dev_layer.get_node_or_null("DevGizmos")
			if gizmos != null:
				gizmos.visible = not gizmos.visible
				applied = true
		"vsync":
			if DisplayServer.get_name() != "headless":
				var on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if on else DisplayServer.VSYNC_ENABLED)
				applied = true
		"copy":
			applied = _copy()
	refresh()
	return applied


## Brings every section up to date now.
func refresh() -> void:
	if main == null:
		return
	var sim := _current_sim()
	_identity.text = "\n".join(_identity_lines(sim))
	_render.text = "\n".join(_render_lines())
	if sim == null:
		fields.erase("tick")
		_sim.text = "No run."
		_actor.text = "No run."
		_stats.text = "No run."
		_feeding.text = "No run."
		_carrion.text = ""
		_build_zone_rows(null)
		return
	_sim.text = "\n".join(_sim_lines(sim))
	_actor.text = "\n".join(_actor_lines(sim))
	_stats.text = "\n".join(_stat_lines(sim))
	_feeding.text = "\n".join(_feeding_lines(sim))
	_update_ecology(sim)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec >= 0:
		_frame_ms.append((now - _last_frame_usec) / 1000.0)
		if _frame_ms.size() > FRAME_WINDOW:
			_frame_ms.remove_at(0)
	_last_frame_usec = now
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_S
		refresh()


func _current_sim() -> PoolSim:
	var pool: PoolScene = main.pool if main != null else null
	return pool.sim if pool != null else null


func _identity_lines(sim: PoolSim) -> PackedStringArray:
	var session: GameSession = main.session
	fields.build_id = BuildInfo.build_id()
	fields.slot = session.slot
	var lines := PackedStringArray(["Build %s" % fields.build_id,
		"Slot %s" % session.slot, "File %s" % ProjectSettings.globalize_path(session.slot)])
	if sim == null:
		return lines
	var save := sim.save
	fields.lineage_id = save.lineage_id
	fields.genome_id = save.genome.genome_id
	fields.world_seed = save.world_seed
	fields.region_seed = save.world_seed * PoolSim.SEED_STRIDE + PoolSim.REGION_SEED_OFFSET
	fields.carrion_seed = save.world_seed * PoolSim.SEED_STRIDE + PoolSim.CARRION_SEED_OFFSET
	var body := Lineage.starting_body_of(save.genome, sim.catalog)
	var last: Dictionary = session.last_save
	var last_text := "none yet" if last.is_empty() else ("ok" if last.ok else str(last.error))
	if last.is_empty() and session.load_source == "new":
		last_text = "the founding save, %s" % ("ok" if main.last_run.get("saved", false) else "failed")
	lines.append_array([
		"Lineage %s (%s)" % [save.lineage_id, GameSession.lineage_tag(save.lineage_id)],
		"Genome %s" % save.genome.genome_id,
		"Generation %d · body %s" % [save.genome.generation, body if not body.is_empty() else "evolved"],
		"World seed %d" % save.world_seed,
		"Region seed %d · carrion seed %d" % [fields.region_seed, fields.carrion_seed],
		"Loaded from %s · last save %s" % [session.load_source, last_text],
	])
	return lines


func _sim_lines(sim: PoolSim) -> PackedStringArray:
	var cost: Dictionary = main.pool.step_cost_usec()
	fields.tick = sim.tick
	fields.step_cost_avg_us = cost.avg
	return PackedStringArray([
		"Tick %d · sim time %.2f s%s" % [sim.tick, sim.now(), " · paused" if main.pool.paused else ""],
		"Step cost %.0f µs average, %d µs max (last %d ticks)" % [cost.avg, cost.max, PoolScene.STEP_COST_WINDOW],
	])


func _render_lines() -> PackedStringArray:
	var worst := 0.0
	for ms in _frame_ms:
		worst = maxf(worst, ms)
	var fps := Engine.get_frames_per_second()
	fields.fps = fps
	fields.longest_frame_ms = worst
	fields.draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	fields.adapter = "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]
	fields.driver = "%s, %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()]
	var headless := DisplayServer.get_name() == "headless"
	fields.vsync = "n/a" if headless else str(VSYNC_NAMES.get(DisplayServer.window_get_vsync_mode(), "?"))
	var window := Vector2i.ZERO if headless else DisplayServer.window_get_size()
	return PackedStringArray([
		"FPS %.0f · frame %.1f ms · longest %.1f ms (last %d frames)" % [fps, 1000.0 / maxf(fps, 1.0), worst, _frame_ms.size()],
		"Draw calls %d" % fields.draw_calls,
		"Adapter %s" % fields.adapter,
		"Driver %s" % fields.driver,
		"VSync %s · window %d×%d" % [fields.vsync, window.x, window.y],
	])


func _actor_lines(sim: PoolSim) -> PackedStringArray:
	var s := sim.state
	var m := sim.motion
	fields.energy = s.energy
	fields.position = m.position
	var next_point := ceilf((sim.alive_s + 1e-6) / Lineage.SURVIVAL_INTERVAL) * Lineage.SURVIVAL_INTERVAL
	return PackedStringArray([
		"Energy %.1f / %.0f · health %.1f / %.0f" % [s.energy, s.energy_capacity, s.health, s.max_health],
		"Starving %s · speed multiplier %.2f · dead %s" % ["yes" if s.is_starving() else "no", s.speed_multiplier(), "yes" if sim.dead else "no"],
		"Alive %.1f s · next survival point at %.0f s" % [sim.alive_s, next_point],
		"Position (%.2f, %.2f) · heading %.0f°" % [m.position.x, m.position.y, rad_to_deg(m.heading)],
		"Speed %.2f m/s · soft-wall depth %.2f" % [m.velocity.length(), sim.arena.wall_depth(m.position)],
		"Points %d" % sim.save.adaptation_points,
	])


func _stat_lines(sim: PoolSim) -> PackedStringArray:
	var p := sim.phenotype
	var parts := PackedStringArray()
	var stats := p.to_dict()
	for key: String in stats:
		var value = stats[key]
		parts.append("%s %s" % [key, ", ".join(PackedStringArray(value)) if value is Array else "%.2f" % value])
	var lines := PackedStringArray([" · ".join(parts)])
	lines.append("Radius %.2f m · top speed now %.2f m/s" % [p.radius, p.speed * sim.state.speed_multiplier()])
	for mouth in p.mouths:
		lines.append("Mouth %s at %.0f°, arc %.0f° (%s)" % [mouth.type, rad_to_deg(mouth.angle), rad_to_deg(mouth.arc), mouth.diet])
	return lines


func _feeding_lines(sim: PoolSim) -> PackedStringArray:
	if sim.feed_log.is_empty():
		return PackedStringArray(["Nothing yet."])
	var lines := PackedStringArray()
	for entry in sim.feed_log:
		var outcome := "eaten" if entry.allowed else "refused: %s" % entry.reason
		lines.append("%.2f s  %s %s  %s" % [entry.tick * PoolSim.DT, entry.food_id, entry.kind, outcome])
	return lines


func _update_ecology(sim: PoolSim) -> void:
	_build_zone_rows(sim)
	for z in sim.region.zones:
		var row: Dictionary = _zone_rows.get(z.id, {})
		if row.is_empty():
			continue
		var bar: ProgressBar = row.bar
		bar.max_value = z.capacity
		bar.value = z.amount
		var state := "regrowing" if sim.plankton.is_regrowing(z.id) else ("empty" if z.amount < sim.plankton.unit_energy else "")
		(row.text as Label).text = "%.0f / %.0f · %d items%s" % [z.amount, z.capacity, sim.plankton.count_in(z.id),
			" · " + state if not state.is_empty() else ""]
	var supply := sim.carrion.supply
	var arrival := "interim supply off"
	if bool(supply.get("enabled", false)) and is_finite(sim.carrion.next_supply_at):
		arrival = "next interim arrival in %.1f s" % maxf(sim.carrion.next_supply_at - sim.now(), 0.0)
	_carrion.text = "Carrion %d live (at most %d) · %s" % [sim.carrion.items.size(), int(supply.get("max_live", 0)), arrival]


func _build_zone_rows(sim: PoolSim) -> void:
	if sim == _zones_sim:
		return
	_zones_sim = sim
	for child in _zones.get_children():
		_zones.remove_child(child)
		child.queue_free()
	_zone_rows.clear()
	if sim == null:
		return
	for z in sim.region.zones:
		var name_label := Label.new()
		name_label.text = z.id
		name_label.theme_type_variation = &"DebugLabel"
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"ZoneBar"
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var text := Label.new()
		text.theme_type_variation = &"DebugLabel"
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_zones.add_child(name_label)
		_zones.add_child(bar)
		_zones.add_child(text)
		_zone_rows[z.id] = {"bar": bar, "text": text}


## Copies the seed, build, genome id and position, where the platform has a clipboard.
func _copy() -> bool:
	var sim := _current_sim()
	var text := "build %s" % BuildInfo.build_id()
	if sim != null:
		text = "seed %d · %s · genome %s · position (%.2f, %.2f)" % [sim.save.world_seed, text,
			sim.save.genome.genome_id, sim.motion.position.x, sim.motion.position.y]
	fields.copied = text
	var button: Button = _buttons.copy
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		button.text = "Copy (no clipboard here)"
		return false
	DisplayServer.clipboard_set(text)
	button.text = "Copied"
	return true
