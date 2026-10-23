extends CanvasLayer
## Debug builds only (M1 step 2): a panel on the right with the run's identity, the sim, rendering
## and performance, the actor, its derived stats, the last feeding results and the ecology, plus
## dev commands. F3 shows and hides it (dev_keys.gd); it refreshes at 4 Hz while shown. Every
## sim command goes through a PoolSim debug_* method, which logs a "debug" event.
##
## M1 step 3 adds the AI section (ai_lines(): two lines per creature with its state and phase
## timer, what it remembers of its target, its give-up timer and the token; then the niches, the
## respawn queue and the token; then the cell's shelter, streak, last death and checkpoint) and the
## threat commands: F9 spawns a threat ahead (the species alternate), F10 kills the nearest
## creature, and buttons freeze every brain, hide the cell from them and hurt the cell.
##
## The render section shows the GPU frame time (micro-world plan C1): showing the panel turns on the
## renderer's timing of the root viewport (RenderingServer.viewport_set_measure_render_time), and
## it stays on. A renderer that times nothing (headless) shows "n/a".
##
## The endless sea (S1, docs/s1/s1-content.md 6.14) adds the world line to the sim section
## (world_line(): the origin, the tile and its region, chunks, awake and asleep creatures and food
## against their caps, and the stream's backstop counters) and three buttons that show only there:
## a teleport 100 km east, a rebase now and the chunk gizmo. Teleport goes home there, to the
## generation start's absolute place, since the layout's spawn is a pool point that a rebase moves.
## The ecology rows list the ZONE_ROWS loaded zones nearest the cell, checked at 2 Hz, and the AI
## section lists the awake creatures and counts the sleepers.
##
## Main loads it by path from its guarded dev loader (no class_name, so nothing outside game/dev
## can depend on it). `fields` keeps the latest shown values by name, for checks.

const REFRESH_S := 0.25
const FRAME_WINDOW := 60            ## frames the longest-frame and GPU figures look back over
## Health the Hurt button takes from the cell (plan section 16).
const HURT_SELF_HP := 10.0
## The endless sea's teleports (absolute am) and their heading: home is the generation start (build
## plan 17.12), far is 100 km east of it.
const HOME_AM := Vector2(0.0, 9.0)
const FAR_AM := Vector2(100000.0, 9.0)
const TELEPORT_HEADING := -1.5708
const REBASE_BY := Vector2i(1, 0)   ## the Rebase button's dev rebase, in chunks
const ZONE_ROWS := 8                ## the endless sea's ecology rows: the loaded zones nearest the cell
## The buttons that show only in the endless sea.
const WORLD_BUTTONS: PackedStringArray = ["teleport_far", "rebase", "chunks"]
const VSYNC_NAMES := {
	DisplayServer.VSYNC_DISABLED: "off", DisplayServer.VSYNC_ENABLED: "on",
	DisplayServer.VSYNC_ADAPTIVE: "adaptive", DisplayServer.VSYNC_MAILBOX: "mailbox",
}

var main: Node
## The latest shown values by name: build_id, genome_id, lineage_id, world_seed, slot, tick,
## fps, longest_frame_ms, gpu_ms (the average GPU time, 0 for none), gpu_longest_ms, draw_calls,
## adapter, driver, vsync, energy, position, and so on. The AI section adds ai_creatures (the ids
## it lists, in order), ai_summary (the niche, queue and token line) and ai_player (the cell's
## line); spawn_threat adds last_threat (the species spawned).
var fields := {}

var _refresh_t := 0.0
## Wall-clock frame times in ms, as in perf_tour.gd (the process delta caps a stall near 150 ms).
var _frame_ms := PackedFloat32Array()
var _last_frame_usec := -1
## The renderer's GPU times of the last FRAME_WINDOW frames it timed, in ms.
var _gpu_ms := PackedFloat32Array()
var _zone_rows := {}                 ## zone id -> {"bar": ProgressBar, "text": Label}
var _zones_sim: PoolSim              ## the sim the zone rows were built for
var _zone_ids := PackedStringArray() ## the zones the rows show, in order (zone_row_ids)
var _zone_check := false             ## the endless rows are checked every other refresh (2 Hz)
var _threat_turn := 0                ## which species the next spawn_threat places

@onready var _identity: Label = %Identity
@onready var _sim: Label = %Sim
@onready var _render: Label = %Render
@onready var _actor: Label = %Actor
@onready var _stats: Label = %Stats
@onready var _feeding: Label = %Feeding
@onready var _zones: GridContainer = %Zones
@onready var _carrion: Label = %Carrion
@onready var _ai: Label = %AI
@onready var _buttons := {
	"fill": %Fill, "drain": %Drain, "empty_zone": %EmptyZone, "spawn_carrion": %SpawnCarrion,
	"teleport": %Teleport, "gizmos": %Gizmos, "vsync": %VSync, "copy": %Copy,
	"spawn_threat": %SpawnThreat, "kill_nearest": %KillNearest, "freeze_ai": %FreezeAI,
	"hide_from_ai": %HideFromAI, "hurt_self": %HurtSelf, "teleport_far": %TeleportFar, "rebase": %Rebase,
	"chunks": %Chunks,
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
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		refresh()


## Runs a dev command by name: fill, drain, empty_zone, spawn_carrion, teleport (to the layout
## spawn; in the endless sea home, to HOME_AM), gizmos, vsync, copy, spawn_threat (a creature
## DEBUG_THREAT_AHEAD_M ahead, facing the cell; each one that lands is the next species in id
## order), kill_nearest, freeze_ai and hide_from_ai (toggles) or hurt_self (HURT_SELF_HP); in the
## endless sea also teleport_far (to FAR_AM), rebase (REBASE_BY chunks now) and chunks (the chunk
## gizmo, on or off). Returns whether it applied.
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
			if sim != null and sim.is_endless():
				applied = sim.debug_teleport_abs(HOME_AM.x, HOME_AM.y, TELEPORT_HEADING)
			else:
				applied = sim != null and sim.debug_teleport(sim.layout.spawn, sim.layout.spawn_heading)
		"teleport_far":
			applied = sim != null and sim.debug_teleport_abs(FAR_AM.x, FAR_AM.y, TELEPORT_HEADING)
		"rebase":
			applied = sim != null and sim.debug_rebase(REBASE_BY)
		"chunks":
			var gizmos: Node3D = main.dev_layer.get_node_or_null("DevGizmos") if main != null else null
			if gizmos != null:
				gizmos.show_chunks = not gizmos.show_chunks
				if gizmos.show_chunks:
					gizmos.visible = true
				applied = true
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
		"spawn_threat":
			applied = sim != null and _spawn_threat(sim)
		"kill_nearest":
			applied = sim != null and sim.debug_kill_nearest_creature()
		"freeze_ai":
			applied = sim != null and sim.debug_set_ai_frozen(not sim.dev_ai_frozen)
		"hide_from_ai":
			applied = sim != null and sim.debug_set_hidden(not sim.dev_hidden)
		"hurt_self":
			applied = sim != null and sim.debug_hurt_player(HURT_SELF_HP)
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
		_ai.text = "No run."
		_build_zone_rows(null)
		_update_toggles(null)
		_update_world_buttons(null)
		return
	_sim.text = "\n".join(_sim_lines(sim))
	_actor.text = "\n".join(_actor_lines(sim))
	_stats.text = "\n".join(_stat_lines(sim))
	_feeding.text = "\n".join(_feeding_lines(sim))
	_update_ecology(sim)
	_update_ai(sim)
	_update_toggles(sim)
	_update_world_buttons(sim)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec >= 0:
		_frame_ms.append((now - _last_frame_usec) / 1000.0)
		if _frame_ms.size() > FRAME_WINDOW:
			_frame_ms.remove_at(0)
	_last_frame_usec = now
	take_gpu_sample(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_S
		refresh()


## Keeps one frame's GPU time in ms for the render section; 0 or less (not timed) is skipped.
func take_gpu_sample(ms: float) -> void:
	if ms <= 0.0:
		return
	_gpu_ms.append(ms)
	if _gpu_ms.size() > FRAME_WINDOW:
		_gpu_ms.remove_at(0)


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
	var lines := PackedStringArray([
		"Tick %d · sim time %.2f s%s" % [sim.tick, sim.now(), " · paused" if main.pool.paused else ""],
		"Step cost %.0f µs average, %d µs max (last %d ticks)" % [cost.avg, cost.max, PoolScene.STEP_COST_WINDOW],
	])
	if sim.is_endless():
		fields.world_line = world_line(sim)
		lines.append(fields.world_line)
	return lines


## The endless sea's line: the origin (km), the tile under the cell and its region (or rare kind),
## the loaded chunks, awake and asleep creatures and food items against their caps, then the
## stream's backstop counters (spine 3.10).
static func world_line(sim: PoolSim) -> String:
	var w := sim.world
	var tile := w.tile_of_local(sim.motion.position)
	var info := w.gen.tile_info(WorldConfig.band_of(w.size), tile.x, tile.y)
	var region := str(info.rare) if not str(info.rare).is_empty() else str(info.region)
	var awake := sim.creatures.awake().size() if sim.creatures != null else 0
	return ("origin %.1f, %.1f km · tile %d,%d %s · chunks %d/%d · awake %d/%d · asleep %d/%d · food %d/%d"
		+ " · overflow %d · waits %d · trimmed %d · evicted %d") % [
		w.origin_x_am / 1000.0, w.origin_y_am / 1000.0, tile.x, tile.y, region,
		w.loaded_keys().size(), int(w.caps.chunks), awake, int(w.caps.awake), w.sleeping_ids().size(), int(w.caps.sleepers),
		sim.plankton.items.size(), int(w.caps.food_items), int(w.counters.awake_overflow), int(w.counters.chunk_waits),
		int(w.counters.food_trimmed), int(w.counters.evictions)]


func _render_lines() -> PackedStringArray:
	var worst := 0.0
	for ms in _frame_ms:
		worst = maxf(worst, ms)
	var fps := Engine.get_frames_per_second()
	fields.fps = fps
	fields.longest_frame_ms = worst
	var gpu := gpu_spread(_gpu_ms)
	fields.gpu_ms = gpu.avg
	fields.gpu_longest_ms = gpu.longest
	fields.draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	fields.adapter = "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()]
	fields.driver = "%s, %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()]
	var headless := DisplayServer.get_name() == "headless"
	fields.vsync = "n/a" if headless else str(VSYNC_NAMES.get(DisplayServer.window_get_vsync_mode(), "?"))
	var window := Vector2i.ZERO if headless else DisplayServer.window_get_size()
	return PackedStringArray([
		"FPS %.0f · frame %.1f ms · longest %.1f ms (last %d frames)" % [fps, 1000.0 / maxf(fps, 1.0), worst, _frame_ms.size()],
		gpu_line(_gpu_ms),
		"Draw calls %d" % fields.draw_calls,
		"Adapter %s" % fields.adapter,
		"Driver %s" % fields.driver,
		"VSync %s · window %d×%d" % [fields.vsync, window.x, window.y],
	])


## {"avg", "longest"} of GPU times in ms; zeros for none.
static func gpu_spread(gpu_ms: PackedFloat32Array) -> Dictionary:
	var total := 0.0
	var longest := 0.0
	for ms in gpu_ms:
		total += ms
		longest = maxf(longest, ms)
	return {"avg": total / gpu_ms.size() if not gpu_ms.is_empty() else 0.0, "longest": longest}


## The render section's GPU line: the average and longest GPU time over the frames the renderer timed.
static func gpu_line(gpu_ms: PackedFloat32Array) -> String:
	if gpu_ms.is_empty():
		return "GPU n/a (the renderer has timed no frame)"
	var gpu := gpu_spread(gpu_ms)
	return "GPU %.2f ms · longest %.2f ms (last %d frames)" % [gpu.avg, gpu.longest, gpu_ms.size()]


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
	_zone_check = not _zone_check
	if sim != _zones_sim or not sim.is_endless() or _zone_check:
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


## Builds a row per zone_row_ids(sim) zone, for a new sim or when that set of zones changed.
func _build_zone_rows(sim: PoolSim) -> void:
	var ids := zone_row_ids(sim) if sim != null else PackedStringArray()
	if sim == _zones_sim and _same_ids(ids, _zone_ids):
		return
	_zones_sim = sim
	_zone_ids = ids
	fields.zone_rows = Array(ids)
	for child in _zones.get_children():
		_zones.remove_child(child)
		child.queue_free()
	_zone_rows.clear()
	if sim == null:
		return
	for id in ids:
		var z := sim.region.zone(id)
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


## The zones the ecology rows show: every zone of the pool, in order; in the endless sea the
## ZONE_ROWS loaded zones nearest the cell, nearest first (ties by id).
static func zone_row_ids(sim: PoolSim) -> PackedStringArray:
	var out := PackedStringArray()
	var zones: Array = sim.region.zones.duplicate()
	if sim.is_endless():
		var p := sim.motion.position
		zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := p.distance_to(a.center)
			var db := p.distance_to(b.center)
			return da < db or (da == db and str(a.id) < str(b.id)))
		zones = zones.slice(0, ZONE_ROWS)
	for z: Dictionary in zones:
		out.append(z.id)
	return out


## Whether two id lists hold the same ids, in any order.
static func _same_ids(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() != b.size():
		return false
	var sa := a.duplicate()
	var sb := b.duplicate()
	sa.sort()
	sb.sort()
	return sa == sb


func _update_ai(sim: PoolSim) -> void:
	var lines := ai_lines(sim)
	_ai.text = "\n".join(lines)
	var ids := []
	if sim.creatures != null:
		for c in sim.creatures.awake():
			ids.append(c.id)
	fields.ai_creatures = ids
	fields.ai_summary = summary_line(sim) if sim.creatures != null else ""
	fields.ai_player = player_line(sim)


## The endless sea's buttons show only there, and Teleport says where it goes.
func _update_world_buttons(sim: PoolSim) -> void:
	var endless := sim != null and sim.is_endless()
	for command in WORLD_BUTTONS:
		(_buttons[command] as Button).visible = endless
	(_buttons.teleport as Button).text = "Teleport home" if endless else "Teleport to spawn"


## The toggle buttons name the switch's state.
func _update_toggles(sim: PoolSim) -> void:
	var frozen := sim != null and sim.dev_ai_frozen
	var hidden := sim != null and sim.dev_hidden
	(_buttons.freeze_ai as Button).text = "Freeze AI: %s" % ("on" if frozen else "off")
	(_buttons.hide_from_ai as Button).text = "Hide from AI: %s" % ("on" if hidden else "off")


## Spawns the next threat species ahead of the cell; the turn moves on only when one lands.
func _spawn_threat(sim: PoolSim) -> bool:
	if sim.species == null or sim.creatures == null:
		return false
	var ids := sim.species.species_ids()
	if ids.is_empty():
		return false
	var species_id := ids[_threat_turn % ids.size()]
	if not sim.debug_spawn_threat_ahead(species_id):
		return false
	_threat_turn += 1
	fields.last_threat = species_id
	return true


## The AI section: two lines per creature in number order (creature_lines), then the niche, queue
## and token line, then the cell's line. A pool without creatures says so. In the endless sea only
## the awake creatures get lines, and "asleep: n" counts the sleepers after them.
static func ai_lines(sim: PoolSim) -> PackedStringArray:
	if sim.creatures == null:
		return PackedStringArray(["No creatures in this pool.", player_line(sim)])
	var lines := PackedStringArray()
	for c in sim.creatures.awake():
		lines.append_array(creature_lines(sim, c))
	if sim.is_endless():
		lines.append("asleep: %d" % sim.world.sleeping_ids().size())
	lines.append(summary_line(sim))
	lines.append(player_line(sim))
	return lines


## One creature: id, species and site; state/phase with the time in the phase over its length;
## its target as it remembers it (how it last sensed it and how long ago) or its goal; the give-up
## timer while engaged; [token] while it holds the player's token. Then health, energy, distance
## from home and whom it ignores, for how much longer.
static func creature_lines(sim: PoolSim, c: CreatureField.Creature) -> PackedStringArray:
	var site := c.site_id if not c.site_id.is_empty() else ("dev" if c.debug else "-")
	var head := "%s %s @%s" % [c.id, c.species_id, site]
	var body := "    hp %s/%s  en %d%%" % [String.num(c.state.health, 1), String.num(c.state.max_health, 1),
		roundi(100.0 * c.state.energy / maxf(c.state.energy_capacity, 1e-6))]
	var mem := c.brain
	if mem == null:
		return PackedStringArray([head + "  scripted", body])
	var state := mem.state if mem.phase.is_empty() else "%s/%s" % [mem.state, mem.phase]
	head += "  " + state
	var length := CreatureView.phase_ticks(mem)
	if length > 0:
		head += " %.2f/%.2f s" % [_seconds(sim.tick - mem.phase_tick), _seconds(length)]
	if not mem.target.is_empty():
		var seen: Dictionary = mem.seen.get(mem.target, {})
		var how := "not remembered" if seen.is_empty() else "%s, %.1f s ago" % [seen.by, _seconds(sim.tick - int(seen.tick))]
		head += "  → %s (%s)" % [mem.target, how]
	elif mem.goal.is_finite():
		head += "  goal (%.1f, %.1f)" % [mem.goal.x, mem.goal.y]
	if mem.state in [CreatureBrain.NOTICE, CreatureBrain.CHASE, CreatureBrain.ATTACK] and mem.engaged_tick >= 0:
		head += "  give-up %.1f/%.1f s" % [_seconds(sim.tick - mem.engaged_tick), _seconds(int(mem.cfg.give_up_ticks))]
	if c.id in sim.creatures.engaged_on_player:
		head += "  [token]"
	if mem.stuck:
		head += "  [stuck]"
	var ignores := PackedStringArray()
	if mem.ignore_all_until > sim.tick:
		ignores.append("all %.1f s (settling)" % _seconds(mem.ignore_all_until - sim.tick))
	var ignored: Array = mem.ignore.keys()
	ignored.sort()
	for id: String in ignored:
		if int(mem.ignore[id]) > sim.tick:
			ignores.append("%s %.1f s" % [id, _seconds(int(mem.ignore[id]) - sim.tick)])
	body += "  home %.1f m  ignore: %s" % [c.motion.position.distance_to(mem.home), ", ".join(ignores) if not ignores.is_empty() else "-"]
	return PackedStringArray([head, body])


## Each niche's count over its cap (roles in name order), the respawn queue (soonest first, ties by
## site) and the creatures holding the player's token.
static func summary_line(sim: PoolSim) -> String:
	var niches := PackedStringArray()
	var roles: Array = sim.region.niches.keys()
	roles.sort()
	for role: String in roles:
		niches.append("%s %d/%d" % [role, int(sim.region.niches[role].count), int(sim.region.niches[role].cap)])
	var queue := sim.creatures.queue.duplicate()
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.at_tick < b.at_tick or (a.at_tick == b.at_tick and str(a.site) < str(b.site)))
	var waiting := PackedStringArray()
	for q: Dictionary in queue:
		waiting.append("%s in %.1f s" % [q.site, _seconds(maxi(int(q.at_tick) - sim.tick, 0))])
	var token := sim.creatures.engaged_on_player
	return "niches: %s   queue: %s   token: %s" % [" ".join(niches) if not niches.is_empty() else "-",
		", ".join(waiting) if not waiting.is_empty() else "-", ", ".join(token) if not token.is_empty() else "-"]


## The cell: its shelter, death streak, last death, checkpoint and the dev switches that are on.
static func player_line(sim: PoolSim) -> String:
	var shelter := "sheltered %.1f s" % _seconds(sim.grace_until - sim.tick) if sim.is_sheltered() else "not sheltered"
	var last := "-"
	for i in range(sim.save.lineage_history.size() - 1, -1, -1):
		var entry: Dictionary = sim.save.lineage_history[i]
		if entry.get("event") == "died":
			last = str(entry.get("cause", "?"))
			break
	var at: Vector2 = sim.checkpoint().position
	var line := "player: %s  streak %d  last death %s  checkpoint (%.1f, %.1f)" % [shelter, sim.death_streak, last, at.x, at.y]
	if sim.dead:
		line += "  dead"
	if sim.dev_ai_frozen:
		line += "  AI frozen"
	if sim.dev_hidden:
		line += "  hidden from AI"
	return line


static func _seconds(ticks: int) -> float:
	return ticks / float(CreatureBrain.TICKS_PER_SECOND)


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
