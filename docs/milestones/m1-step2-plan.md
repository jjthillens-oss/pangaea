> **Final pre-build plan for M1 step 2 (2026-10-22), kept for history.** It is copied here unchanged.
> The build differs from it in places, and some numbers here are out of date. The step 2 section of
> `docs/milestones/M1.md` lists where the build differs; the code and `game/data/` hold the current values.

# M1 step 2 "Swim and eat": final implementation plan

**Status:** PROPOSED. Every number is PROPOSED tuning and lives in `game/data/` or in constants at the top of a `game/domain` file.

**Base:** `m1-core-rules` at `65b4489` (90 tests pass). This commit landed while the review was running; it only tightened save and genome loading, and no API this plan uses changed.

**Verification:** every claim below was checked in a scratch copy of the repository with the pinned `Godot_v4.7.2-stable`. The repository was not modified.

**Winner: sim-first.** All gameplay runs in a deterministic `PoolSim` in `game/systems`, built on custom planar kinematics in `game/domain`. Scenes only draw.

**Grafted from godot-native:**
- the plane mapping (it matches the web prototype and `Input.get_vector`);
- `main.tscn` becomes the main scene, and the M0 boot runs by path;
- the placeholder inventory goes in a subfolder of `assets/records`;
- a two-process save/quit/continue smoke;
- pointer math as a pure function;
- placeholder audio synthesized at runtime;
- a spawn-validity check on continue.

**Grafted from player-first:**
- physical keycodes and key labels that are safe headless;
- refusal hints only when the food touches the cell;
- pause releases held input, and losing focus pauses;
- starving cues and an assist arrow to food;
- lateral damping in the swim model;
- a separate dev exe, so the release exe never contains the debug panel;
- a project-settings test;
- a camera on-screen check;
- flood-fill reachability for the layout.

## 0. Facts verified on the pinned engine

- **Starting bodies** (from `Phenotype.derive`):

  | Body | Speed (m/s) | Accel | Upkeep (/s) | Sight | Mass |
  |---|---|---|---|---|---|
  | Grazer | 2.91 | 3.08 | 0.90 | 9 | 1.17 |
  | Hunter | 3.26 | 3.05 | 1.15 | 6 | 1.30 |
  | Omnivore | 2.72 | 2.88 | 0.95 | 6 | 1.25 |

  - All bodies turn at 2.5 rad/s.
  - Starting energy is 60. It lasts about 51 / 40 / 49 s while cruising (grazer / hunter / omnivore).
  - A starving cell dies after 20 s (30 health ÷ 1.5 per s).
- **Sample cell import:**
  - `Body` is a MeshInstance3D with scale (0.92, 0.78, 1.0). Its children are `Mouth`, `Flagellum`, `Eye_L/R`, `Pupil_L/R`, `Nucleus` and the sockets.
  - Socket world positions: `socket_mouth` (0,0,−0.5), `socket_tail` (0,0,0.5), `socket_side_L` (−0.46,0,0), `socket_side_R` (0.46,0,0), `socket_top` (0,0.39,0).
  - The body mesh is 0.90 × 0.78 × 0.98 m, so `Phenotype.radius` 0.5 fits the body without the flagellum.
- **Command-line and runner behavior:**
  - `--fixed-fps 60` runs 600 physics frames in about 3 ms headless; without it they take about 10 s.
  - `--quit-after N` works.
  - `godot --headless --path . res://game/scenes/boot.tscn -- --smoke` runs the M0 checks when the main scene is something else.
  - `await call(name)` inside `SceneTree._initialize` works for both plain and coroutine methods.
  - Autoloads are instanced under `--script`, so this plan uses none.
- **Headless display:**
  - `DisplayServer.keyboard_get_label_from_physical` prints `ERROR: Not supported by this display server`.
  - `InputEventKey.as_text()` returns "W - Physical" for physical keys; `as_text_physical_keycode()` returns "W".
  - `root.size` is 64×64, but `get_visible_rect()` and `Camera3D.unproject_position` use 1920×1080.
  - A `Camera3D` added in `_initialize` must enter the tree (await one frame) before `look_at`.
- **Rendering resources headless:**
  - `MultiMesh.buffer` and `visible_instance_count` can be set, but per-instance transforms are not readable back under the dummy renderer.
  - `JSON.stringify(x, "", true, true)` keeps full float precision.
  - `AudioStreamWAV` plays on the dummy audio driver.
- **Plane mapping:** world = (x, 0, y), with yaw = −heading − π/2. Rotating the sample's −Z by that yaw gives the heading direction.
  - A part at +π/2 lands on `socket_side_R` (+X).
  - `InteractionResolver.relative_angle` of a point at the cell's world right is +π/2.
  - `rotate_toward` wraps correctly.
- **Domain sources:**
  - `part_catalog.gd` uses `FileAccess`.
  - `ecology_region.gd` calls `rng.randf()`.
  - `assets/records/` has a `.gdignore`, and `_records()` reads only the top-level `*.json`.

## 1. Corrections applied to the winning plan

1. **Coordinate convention.**
   - Plane `Vector2(x, y)` maps to world `(x, 0, y)`. Plane +y is world +Z, which is screen-down with the north-up camera.
   - Positive part angles are on the cell's right (clockwise seen from above). This matches the web prototype (canvas y-down) and `Input.get_vector("move_left","move_right","move_up","move_down")`.
2. **Purity scan.** It matches only bare global RNG calls (`(?<![\w.])(randf|randi|randomize|randf_range|randi_range)\(`). It allow-lists `part_catalog.gd` (an existing read-only data load) for `FileAccess`/`JSON`.
3. **PoolLayout checks.**
   - At runtime, PoolLayout checks only the data itself.
   - Every check against `assets/records` (asset exists, footprint matches) runs in tests only, because records are not exported.
4. **Regrowth test thresholds** come from the actual formula. The fixture zone (capacity 24, unit 8, growth 0.10) gets its first item back after about 22.5 s, so the bound is ≤ 30 s. All items are back at about 56 s, so the bound is ≤ 90 s.
5. **Soft wall.**
   - Push-only acceleration oscillated between 36 and 39 m under constant thrust, and never drifted back when released.
   - Replacement (section 6): outward swimming fades with depth into the band, plus a gentle return current. Simulated result: the cell settles at 38.6–38.7 m, never passes 39.0 m, and is back inside 36.5 m about 6.3 s after release.
6. **Full-stomach refusal.**
   - A refusal only at energy ≥ capacity still lets a full cell eat about one item per second.
   - The rule becomes: refuse when free room is less than half the food's energy (section 7).
7. **Points.**
   - All points go through `Lineage.earn`.
   - The existing step 1 survival rule (`Lineage.survival_points`, one point per 30 s alive) is wired in. All three plans missed it.
8. **Debug panel.** It exists only in debug builds (editor runs, CI headless and a CI-exported `Pangaea-dev.exe`). The release export excludes `game/dev/*`.
9. **M0 boot untouched.** `main.tscn` becomes the main scene. `boot.tscn`/`boot.gd` are not modified and still run by path.
10. **Test bot location.** ForageBot moves out of `game/systems` to `game/dev/` (dev-only, loaded by path).
11. **Audio** is synthesized at runtime. There are no committed WAV files and no generator script.
12. **Key labels** never come from `as_text()` (section 11).

## 2. Layering

| Layer | Owns in step 2 | Must not |
|---|---|---|
| `game/domain` (pure) | **Existing:** Phenotype, ActorState, InteractionResolver, EcologyRegion, Lineage. **New:** PlaneSpace (mapping), Locomotion (steering from stats), PoolArena (soft wall, rocks, hard edge, clear-point tests). **Small additions:** `InteractionResolver.feed(..., room)` "not hungry", `Lineage.starting_body_of`. | Node, Input, OS, Time, files, global RNG |
| `game/systems` (services) | PoolSim (fixed 60 Hz tick, tick order, feeding transaction, events), PlanktonField, CarrionField (with the interim source), PoolLayout (load + validate data), GameSession (new, continue, save, respawn), RunFlags, SimIntent. Existing PersistenceService and SaveMigrations. | Read input, build nodes, per-frame animation |
| `game/scenes`, `game/ui` (presentation) | Views built from layout data, interpolation, camera, input → `SimIntent`, HUD, menus, start screen, effects and audio driven by sim events | Change ActorState, EcologyRegion, items or points; compute stats or eligibility |
| `game/dev` (debug builds only) | Debug panel, dev gizmos, dev keys, ForageBot, perf tour | Anything the release build needs |

Scenes call one thing: `sim.step(intent)` once per physics tick. Everything they show comes from `sim` state or the events it emits. Bible 20 applies: effects and sound follow confirmed events.

## 3. Coordinates: `game/domain/plane_space.gd` (`class_name PlaneSpace`)

```gdscript
const SWIM_Y := 0.0
static func to_world(p: Vector2, y := SWIM_Y) -> Vector3: return Vector3(p.x, y, p.y)
static func to_plane(w: Vector3) -> Vector2: return Vector2(w.x, w.z)
static func yaw_for_heading(h: float) -> float: return -h - PI / 2.0      # model faces -Z
static func part_local_dir(a: float) -> Vector3: return Vector3(sin(a), 0.0, -cos(a))  # +a = right (+X)
static func to_save(p: Vector2) -> Array: return [p.x, SWIM_Y, p.y]
static func from_save(a: Array) -> Vector2: return Vector2(float(a[0]), float(a[2]))
static func ray_to_plane(origin: Vector3, dir: Vector3) -> Variant  # Vector2 or null (pure)
```

Heading 0 faces +X (east), as in InteractionResolver. Screen-up is north (−Z, plane −y).

`tests/test_plane_space.gd` checks:
- for headings {0, 0.7, −2, π}, `Basis(UP, yaw_for_heading(h)) * (0,0,−1)` equals `to_world(Vector2.from_angle(h))`;
- round trips are exact;
- with a cell heading east, `InteractionResolver.relative_angle` of a food at world +Z is +π/2;
- `part_local_dir(π/2)` points at `socket_side_R`.

## 4. Files

### New

| Path | Purpose |
|---|---|
| `game/domain/plane_space.gd` | Section 3 |
| `game/domain/locomotion.gd` | `Locomotion` and inner `MotionState`. Section 6 |
| `game/domain/pool_arena.gd` | `PoolArena`: boundary, rock circles, `move()`, `is_clear()`. Section 6 |
| `game/systems/sim_intent.gd` | `SimIntent { move: Vector2 }`; its length (0..1) is the throttle |
| `game/systems/pool_layout.gd` | `PoolLayout.load_from(path := "res://game/data/pool_m1.json")`, `from_dict()`, `validate() -> PackedStringArray` (data-only rules), `build_arena()`, `build_region(seed)` |
| `game/systems/plankton_field.gd` | Plankton items as a view of zone stock. Section 7 |
| `game/systems/carrion_field.gd` | Carrion items, expiry, the `spawn()` contract, the interim source. Section 7 |
| `game/systems/pool_sim.gd` | Section 5 |
| `game/systems/game_session.gd` | Section 15 (RefCounted, owned by Main; no autoload) |
| `game/systems/run_flags.gd` | Parses `--seed=N`, `--slot=PATH`, `--perf-tour` from `OS.get_cmdline_user_args()` |
| `game/data/pool_m1.json` | Layout and food tuning. Section 8 |
| `game/scenes/main.tscn`, `main.gd` | New main scene, root router. Section 9 |
| `game/scenes/pool/pool.tscn`, `pool.gd`, `pool_environment.tres` | World view and the step loop |
| `game/scenes/pool/player_cell_view.tscn`, `.gd` | Sample cell, genome parts, procedural motion |
| `game/scenes/pool/part_placement.gd` | Pure math: transform for a part angle on the body ellipse |
| `game/scenes/pool/food_view.gd` | One MultiMesh view, used for both plankton and carrion |
| `game/scenes/pool/rock_field.gd` | Instances rock GLBs from the layout |
| `game/scenes/pool/pool_camera.gd` | Section 10 |
| `game/scenes/pool/swim_input.gd` | Input → `SimIntent`, plus pure `pointer_move()`. Section 11 |
| `game/scenes/pool/feedback_fx.gd` | Eat burst, pooled Label3D "+8", "Regrowing" labels |
| `game/scenes/audio/placeholder_audio.gd` | `AudioStreamWAV` cues built in code |
| `game/ui/start_screen.tscn/.gd` | Section 12 |
| `game/ui/body_card.tscn/.gd`, `cell_preview.tscn/.gd` | Body cards and a SubViewport preview |
| `game/ui/hud.tscn/.gd`, `pause_menu.tscn/.gd`, `notice_dialog.tscn/.gd` | Section 12 |
| `game/ui/key_label.gd`, `game/ui/theme/pangaea_theme.tres` | Key labels and theme |
| `game/dev/debug_panel.tscn/.gd`, `dev_gizmos.gd`, `dev_keys.gd`, `forage_bot.gd`, `perf_tour.gd` | Debug builds only. No `class_name`; loaded by path |
| `tools/blender/blockout_common.py`, `tools/blender/make_m1_blockouts.py` | Section 14 |
| `assets/source/blender/<id>.blend`, `assets/export/<id>.glb` (+ committed `.import`), `assets/records/<id>.json` | 10 blockout assets |
| `assets/records/placeholders/inventory.json` | Placeholder and functional-primitive inventory. In a subfolder, so `_records()` skips it unchanged |
| `tests/test_plane_space.gd`, `test_locomotion.gd`, `test_pool_arena.gd`, `test_pool_layout.gd` | Section 16 |
| `tests/test_plankton_field.gd`, `test_carrion_field.gd`, `test_pool_sim.gd`, `test_game_session.gd` | Section 16 |
| `tests/test_part_placement.gd`, `test_swim_input.gd`, `test_placeholders.gd`, `test_sim_purity.gd`, `test_project_settings.gd` | Section 16 |
| `tests/fixtures/pool_test_small.json` | Tiny fixture pool |
| `tests/smoke/play_smoke.gd` | Two-process scene smoke |

### Changed

| Path | Change |
|---|---|
| `game/domain/interaction_resolver.gd` | `feed(actor, food, now, room := INF)`. After the facing check and before the cooldown: if `room < float(food.energy) * FEED_MIN_ROOM_SHARE`, return `"not hungry"`. `FEED_MIN_ROOM_SHARE := 0.5` (PROPOSED; 0 disables it). Existing callers and tests are unaffected |
| `game/domain/lineage.gd` | `static func starting_body_of(genome, catalog) -> String`: returns `"grazer"`, `"hunter"`, `"omnivore"` when part types, angles (±0.01 rad) and scales match a starting body, otherwise `""` |
| `project.godot` | `run/main_scene="res://game/scenes/main.tscn"`; `[input]` actions (section 11); `rendering/anti_aliasing/quality/msaa_3d=2` (4x). No autoloads. The window stays 1280×720 windowed |
| `export_presets.cfg` | Release preset `exclude_filter="tests/*,game/dev/*"`. New preset `Windows Desktop Dev` (same options, `exclude_filter="tests/*"`, `export_path="builds/windows/Pangaea-dev.exe"`) |
| `tools/export_windows.sh` | Also runs `--export-debug "Windows Desktop Dev" builds/windows/Pangaea-dev.exe`. The CI upload of `builds/windows/` picks it up, so `ci.yml` does not change |
| `tools/check.sh` | Section 16 |
| `tests/test_interactions.gd`, `tests/test_lineage.gd`, `tests/test_assets.gd` | New cases (section 16) |
| `docs/milestones/M1.md`, `docs/DECISIONS.md`, `docs/TOOLCHAIN.md`, `README.md` | Step 2 section, PROPOSED decisions, main scene, launch flags, the dev exe |

### Untouched

`game/scenes/boot.*`, `make_sample_cell.py`, the sample assets, the save schema, PersistenceService, SaveMigrations and `.github/workflows/ci.yml`.

## 5. The simulation: `game/systems/pool_sim.gd`

```gdscript
class_name PoolSim extends RefCounted
const DT := 1.0 / 60.0
var tick := 0
var save: SaveGame; var catalog: PartCatalog; var layout: PoolLayout
var phenotype: Phenotype; var state: ActorState; var motion: Locomotion.MotionState
var actor: InteractionResolver.Actor          # persistent: cooldowns survive between ticks
var region: EcologyRegion; var arena: PoolArena
var plankton: PlanktonField; var carrion: CarrionField
var alive_s := 0.0                            # since spawn/respawn/continue; drives survival points
var dead := false
var stats := {"plankton_eaten": 0, "carrion_eaten": 0, "plant_taken": 0.0, "energy_supplied": 0.0,
              "energy_absorbed": 0.0, "points_food": 0, "points_survival": 0, "distance_m": 0.0}
static func create(save: SaveGame, catalog: PartCatalog, layout: PoolLayout) -> PoolSim
func now() -> float                 # tick * DT; the only clock (cooldowns, carrion age)
func step(intent: SimIntent) -> void
func drain_events() -> Array[Dictionary]
func snapshot() -> Dictionary       # full state for the debug panel and hashing
func state_hash() -> int            # hash(JSON.stringify(snapshot(), "", true, true))
func nearest_edible() -> Dictionary # {} or {"id","kind","position"}; for the starving arrow
func respawn_player() -> void       # layout spawn, ActorState.fresh, cooldowns cleared, alive_s = 0
func write_position_to_save() -> void
func display_velocity() -> Vector2  # (position - prev_position) / DT, for camera look-ahead
# Dev commands (dev tools only; each emits a "debug" event):
func debug_set_energy(v: float) -> void
func debug_empty_zone(zone_id: String) -> void
func debug_spawn_carrion_ahead() -> void
func debug_teleport(p: Vector2) -> void
```

### `create()`

1. `phenotype = Phenotype.derive(save.genome, catalog)` and `state = ActorState.fresh(phenotype)`.
2. Set `actor = InteractionResolver.Actor.new("player", pos, heading, phenotype)`.
3. Choose the position:
   - `PlaneSpace.from_save(save.player.position)` if it is inside `soft_start − radius` and `arena.is_clear(p, radius)`;
   - otherwise `layout.spawn`.
4. Choose the heading: the layout spawn heading on a new lineage; on continue, toward the nearest zone center.
5. Seed the world:
   - `region = layout.build_region(save.world_seed * 1000003 + 1)`;
   - carrion RNG seed `save.world_seed * 1000003 + 2` (separate world and encounter seeds, Bible 13).
6. Fill plankton from full zones and place the initial carrion.

### Tick order (fixed; tests depend on it)

1. If `dead`: skip steps 2–4 and 7. The world keeps living behind the death notice.
2. `Locomotion.steer(motion, intent.move, phenotype, state.speed_multiplier(), DT)`.
3. `d = arena.move(motion, phenotype.radius, DT)`, which returns the actual displacement.
4. Metabolism:
   - call `state.tick(phenotype, DT, d)`;
   - emit `starving_started` or `starving_ended` when that changes;
   - if `not state.is_alive()`: set `dead = true` and emit `died {cause: "starved"}` once;
   - otherwise: `alive_s += DT` and `Lineage.earn(save, Lineage.survival_points(alive_s - DT, alive_s))`, emitting `earned {points, reason: "survival"}` when that is above 0.
5. Ecology:
   - `region.tick(DT)`;
   - `plankton.tick(region, arena)`;
   - `carrion.tick(DT, now(), region, arena)`.
6. Sync `actor.position` and `actor.heading` from `motion`.
7. Feeding (section 7).
8. `tick += 1`.

### Determinism

- Only `step()` advances time. Scenes never pass `delta` to the sim.
- Only the region's and the carrion field's seeded RNGs exist. The carrion field computes its own in-zone points, so it never draws from the region RNG.
- Items are kept in insertion-ordered Arrays. Candidates sort by (distance, id).
- Ids come from per-field counters: `pk_17`, `cr_4`.

### Events

| Event | When |
|---|---|
| `ate {kind, food_id, zone, supplied, absorbed, points, position}` | A meal is committed |
| `refused {kind, food_id, reason, touching, contact_s}` | At most one per tick; only when the (food, reason) pair changes or every 0.5 s. Never emitted for "out of reach" or "still swallowing" |
| `earned {points, reason}` | Survival points |
| `starving_started`, `starving_ended` | Starvation state changes |
| `zone_empty {zone}` | A zone's items hit 0 and its amount is below one unit. Latched until it is back to half capacity |
| `zone_regrown {zone}` | The zone's items are back to their maximum |
| `carrion_spawned {source}`, `carrion_expired` | Carrion enters or leaves the world |
| `died {cause}`, `respawned`, `debug {command}` | Death, respawn, dev commands |

## 6. Movement and collisions (custom kinematics, no physics bodies)

**Why custom kinematics:**
- Motion is locked to the plane by construction.
- It is deterministic and runs headless with no physics server.
- The distance charged to `ActorState.tick` is measured exactly.
- Step 3 AI reuses the same code.

No `CharacterBody3D`, `RigidBody3D` or collision shapes are used.

### `game/domain/locomotion.gd`

```gdscript
const INPUT_DEADZONE := 0.05
const ALIGN_POWER := 2.0       # thrust share = max(0, cos(heading error))^2: turn first, then swim
const BRAKE_FACTOR := 1.5      # slowing toward a lower target: 1.5x acceleration
const COAST_FACTOR := 0.9      # no input: forward speed decays at 0.9x acceleration
const LATERAL_DAMPING := 6.0   # 1/s: sideways velocity decays, so the cell carves instead of drifting
class MotionState:
    var position := Vector2.ZERO
    var velocity := Vector2.ZERO
    var heading := 0.0
    var prev_position := Vector2.ZERO
    var prev_heading := 0.0
static func steer(m: MotionState, move: Vector2, p: Phenotype, speed_mul: float, dt: float) -> void:
    m.prev_heading = m.heading
    var throttle := minf(move.length(), 1.0)
    var target := 0.0
    var slow := p.acceleration * COAST_FACTOR
    if throttle > INPUT_DEADZONE:
        var want := move.angle()
        m.heading = wrapf(rotate_toward(m.heading, want, p.turn_rate * dt), -PI, PI)
        target = p.speed * speed_mul * throttle * pow(maxf(0.0, cos(angle_difference(m.heading, want))), ALIGN_POWER)
        slow = p.acceleration * BRAKE_FACTOR
    var fwd := Vector2.from_angle(m.heading)
    var side := fwd.orthogonal()
    var u := m.velocity.dot(fwd)
    var w := m.velocity.dot(side) * exp(-LATERAL_DAMPING * dt)
    u = minf(target, u + p.acceleration * dt) if u < target else maxf(target, u - slow * dt)
    m.velocity = fwd * u + side * w
```

How the Phenotype stats drive motion:
- `speed` is the top speed. `ActorState.speed_multiplier()` halves it while starving.
- `acceleration` is the literal m/s² rate.
- `turn_rate` caps the heading change per tick.

Reference values (simulated with these formulas):

| Body | Time to 90% speed | Coast stop | 180° reversal to 90% speed |
|---|---|---|---|
| Grazer | 0.85 s | 1.5 m | ≈ 1.6 s |
| Hunter | 0.97 s | 1.9 m | ≈ 1.75 s |
| Omnivore | 0.85 s | 1.4 m | ≈ 1.6 s |

### `game/domain/pool_arena.gd`

Constants: `radius = 40`, `soft_start = 36`, `hard_radius = 39.5`, `RETURN_SPEED := 1.0` m/s.

`move(m, body_r, dt) -> float`:

1. Set `prev_position`, then `step = velocity * dt`.
2. **Soft wall.** If r > soft_start:
   - `depth = clamp((r − 36) / 3.5, 0, 1)`;
   - reduce the outward part of the step by `depth` (`step -= n * max(0, step·n) * depth`);
   - add a return current `−n * RETURN_SPEED * depth * dt`.

   This is not a hit: under full outward thrust the cell settles at about 38.6 m and drifts back in when released. Self-velocity is not changed, so turning along the edge stays smooth.
3. **Rocks.** Two passes over the rock circles. If `dist < rock.radius + body_r`, push out along the normal. Remove only the inward velocity component, so the cell slides.
4. **Hard failsafe.** Clamp to `hard_radius − body_r` (39.0 for the cell centre) and remove outward velocity.
5. Return `position.distance_to(prev_position)`. That value feeds metabolism, and the sim's `display_velocity()` feeds the camera.

**Tunneling:** the speed cap is 6 m/s, which is 0.1 m per tick, below the smallest rock radius of 0.8 m.

**Collision radius:** `phenotype.radius` (0.5).

## 7. Food, feeding and points

### Plankton (`PlanktonField`, a view of `EcologyRegion` stock)

- Each layout zone becomes `region.add_zone(id, center, radius, capacity, growth_rate)`. `zone.amount` is the only authority on how much plankton exists.
- **Items per zone:** the target count is `min(max_items_per_zone, floor(amount / unit + 1e-6))`, with `unit = 8`.
  - Each tick, a zone below target spawns one item at `region.random_point_in(zone)`.
  - Up to 8 tries are made while `arena.is_clear(p, item_radius + drift_amplitude)` fails; otherwise it retries next tick.
  - A zone above target (only possible later, when AI eats too) removes its newest item.
- **Item record:** a resolver-shaped dict, `{"id","zone","kind":"plant","position","radius":0.18,"energy":8.0,"points":1,"anchor","phase","born_tick"}`.
- **Drift is simulated, because reach depends on position.**
  - Position = `anchor + 0.35 * Vector2(sin(t*w1 + phase.x), cos(t*w2 + phase.y))`, with periods of 7–13 s.
  - Phases come from the item number by golden angle, so no RNG is drawn.
  - The vertical bob is visual only.
- **Regrowth** follows EcologyRegion's logistic rule plus its floor. For the center zone (capacity 48, growth 0.10), the first item returns about 15 s after the zone is emptied and all 6 are back after about 56 s.

### Carrion (`CarrionField`) and the interim source

- `spawn(position: Vector2, source: String, energy := 24.0, points := 3) -> Dictionary` is the only way carrion enters the world. Step 3 kills call `spawn(victim_pos, "kill", victim_energy)`.
- **Item record:** `{"id","kind":"meat","position","radius":0.3,"energy","points","age","lifetime":90.0,"source"}`. Carrion is static (it sinks and does not drift). It expires at 90 s, and the view shrinks it over its last 10 s.
- **Interim source.** The data block `carrion.interim_supply` holds `{"enabled": true, "interim": true, "interval_s": 9.0, "jitter_s": 3.0, "max_live": 6, "placement": "in_zone"}`.
  - Every 9 ± 3 s (carrion RNG), if fewer than 6 carrion items exist, it calls `spawn(p, "interim")`.
  - `p` is a clear random point inside a zone chosen by the carrion RNG, weighted by capacity.
  - It never takes the player's position as input; the API has no player argument.
  - Three initial items sit at fixed points. One is 5.2 m from spawn, so a hunter eats within seconds and a grazer meets "Needs a jaw" early.
  - The UI never states where carrion comes from.
- **Step 3** sets `enabled: false` so that carrion comes only from kills, as approved. Keeping a trickle after step 3 would change the approved goal and needs owner approval.

### Feeding transaction (in `PoolSim`; `InteractionResolver.feed` is the only authority)

```gdscript
const MAX_FOOD_RADIUS := 0.3
func _try_feed() -> void:
    var reach := phenotype.radius + InteractionResolver.FEED_REACH + MAX_FOOD_RADIUS
    var candidates := plankton.items_near(motion.position, reach) + carrion.items_near(motion.position, reach)
    candidates.sort_custom(_closer_then_id)
    var room := state.energy_capacity - state.energy
    for food in candidates:
        var r := InteractionResolver.feed(actor, food, now(), room)
        if r.allowed:
            _commit_feed(food, r.effect)
            return
        if r.reason == "still swallowing":
            return
        _note_refusal(food, r.reason)   # emits refused{..., touching, contact_s} per the event rule

func _commit_feed(food: Dictionary, effect: Dictionary) -> void:
    var supplied := float(effect.energy)
    if food.kind == "plant":
        supplied = region.take(food.zone, supplied)      # stock first
        plankton.consume(food.id)
    else:
        carrion.consume(food.id)
    if supplied <= 0.0:
        return                                           # stale item removed; nothing granted
    var absorbed := state.eat(supplied)
    var points := int(effect.points) if supplied >= float(effect.energy) - 1e-6 else 0
    Lineage.earn(save, points)
    # Update stats, emit "ate".
```

`touching` means `dist ≤ phenotype.radius + food.radius + 0.05`.

**Invariants (Bible 22: feeding cannot duplicate resources or charge failed actions):**
- A refused feed leaves the zone, the item, energy, points and cooldowns unchanged.
- `plant_taken` equals the sum of plankton energy supplied.
- Zone amount stays between 0 and capacity.
- The item count never exceeds `floor(amount / unit)`.

**Full-stomach rule (PROPOSED).** A cell eats only when it can absorb at least half the food's energy.
- From 60 energy, a grazer eats 5 plankton (to 100) and then waits about 3.5 s of swimming per further item.
- Emptying the center zone stays easy (about 10 s).
- A full cell no longer strips zones or farms points.

**Points:**
- plankton: 1 point per 8 energy;
- carrion: 3 points per 24 energy (the same rate);
- survival: 1 point per 30 s alive (`Lineage.SURVIVAL_INTERVAL`).

## 8. Layout data: `game/data/pool_m1.json`

```json
{
  "schema_version": 1, "status": "PROPOSED",
  "pool": {"radius": 40.0, "soft_start": 36.0, "hard_radius": 39.5, "return_speed": 1.0},
  "spawn": {"position": [0.0, 9.0], "heading": -1.5708},
  "plankton": {"unit_energy": 8.0, "points": 1, "item_radius": 0.18, "max_items_per_zone": 12,
               "drift_amplitude": 0.35, "drift_period_s": [7.0, 13.0]},
  "zones": [
    {"id": "z_center", "center": [0, 0],       "radius": 5, "capacity": 48, "growth_rate": 0.10},
    {"id": "z_n",      "center": [0, -22],     "radius": 6, "capacity": 96, "growth_rate": 0.08},
    {"id": "z_ne",     "center": [19.1, -11],  "radius": 6, "capacity": 56, "growth_rate": 0.12},
    {"id": "z_se",     "center": [19.1, 11],   "radius": 6, "capacity": 80, "growth_rate": 0.08},
    {"id": "z_s",      "center": [0, 22],      "radius": 6, "capacity": 64, "growth_rate": 0.10},
    {"id": "z_sw",     "center": [-19.1, 11],  "radius": 6, "capacity": 48, "growth_rate": 0.12},
    {"id": "z_nw",     "center": [-19.1, -11], "radius": 6, "capacity": 96, "growth_rate": 0.08}
  ],
  "carrion": {"energy": 24.0, "points": 3, "item_radius": 0.3, "lifetime_s": 90.0,
              "initial": [[1.5, 4.0], [-14.0, -6.0], [12.0, -14.0]],
              "interim_supply": {"enabled": true, "interim": true, "interval_s": 9.0, "jitter_s": 3.0,
                                 "max_live": 6, "placement": "in_zone"}},
  "rocks": [
    {"id": "rock_01", "asset": "rock_a", "center": [12.0, 0.0],    "yaw_deg": 20,  "scale": 1.2},
    {"id": "rock_02", "asset": "rock_b", "center": [6.0, 10.4],    "yaw_deg": 75,  "scale": 1.0},
    {"id": "rock_03", "asset": "rock_c", "center": [-6.0, 10.4],   "yaw_deg": 140, "scale": 1.0},
    {"id": "rock_04", "asset": "rock_a", "center": [-12.0, 0.0],   "yaw_deg": 200, "scale": 1.3},
    {"id": "rock_05", "asset": "rock_b", "center": [6.0, -10.4],   "yaw_deg": 310, "scale": 1.1},
    {"id": "rock_06", "asset": "rock_c", "center": [-6.2, -10.8],  "yaw_deg": 35,  "scale": 0.9},
    {"id": "rock_07", "asset": "rock_b", "center": [30.0, 0.0],    "yaw_deg": 90,  "scale": 1.5},
    {"id": "rock_08", "asset": "rock_a", "center": [15.0, 26.0],   "yaw_deg": 160, "scale": 1.2},
    {"id": "rock_09", "asset": "rock_c", "center": [-15.0, 26.0],  "yaw_deg": 250, "scale": 1.4},
    {"id": "rock_10", "asset": "rock_a", "center": [-30.0, 0.0],   "yaw_deg": 10,  "scale": 1.5},
    {"id": "rock_11", "asset": "rock_c", "center": [15.0, -26.0],  "yaw_deg": 120, "scale": 1.3},
    {"id": "rock_12", "asset": "rock_b", "center": [-15.0, -26.0], "yaw_deg": 300, "scale": 1.2},
    {"id": "rock_13", "asset": "rock_a", "center": [32.8, -8.8],   "yaw_deg": 45,  "scale": 1.0},
    {"id": "rock_14", "asset": "rock_c", "center": [24.0, 24.0],   "yaw_deg": 215, "scale": 0.9},
    {"id": "rock_15", "asset": "rock_b", "center": [-6.0, 34.0],   "yaw_deg": 5,   "scale": 1.1},
    {"id": "rock_16", "asset": "rock_c", "center": [-32.8, 8.8],   "yaw_deg": 95,  "scale": 1.0},
    {"id": "rock_17", "asset": "rock_a", "center": [8.8, -32.8],   "yaw_deg": 275, "scale": 0.8},
    {"id": "rock_18", "asset": "rock_b", "center": [-26.4, -22.2], "yaw_deg": 180, "scale": 1.0}
  ],
  "rock_footprint_radius_m": 1.0,
  "camera": {"pitch_deg": 55.0, "fov_deg": 45.0, "distance": 14.0, "zoom_min": 10.0, "zoom_max": 20.0, "zoom_step": 2.0,
             "follow_half_life_s": 0.12, "look_ahead_s": 0.35, "look_ahead_max": 2.5},
  "assists": {"starving_food_arrow": true}
}
```

Rock collision radius = `rock_footprint_radius_m × scale`.

Checked with a script for this review:
- every rock is at least 1 m clear of every zone edge;
- the spawn is at least 3 m from rocks and 4 m from the center zone edge;
- the spawn → center segment is clear;
- every open point is reachable;
- the worst flood-fill path from an open point to a zone edge is 15.0 m, against the 16.3 m starvation budget.

Total capacity is 488, which is at most 61 plankton items.

**Runtime `validate()` (data only):**
- unique ids;
- zones inside `soft_start − 1`;
- rocks inside the pool;
- spawn and initial carrion clear;
- `min_rock_radius > 2 × 6 m/s × DT`.

**Test-only rules (`test_pool_layout.gd`, which may read `assets/records`):**
- every `asset` has a record whose `footprint_radius_m` matches `rock_footprint_radius_m` within 15%;
- the **starvation reachability rule**: on a 0.5 m grid inside `soft_start`, clear of rocks, flood fill from spawn reaches every open point, and the path distance to the nearest zone edge is at most D_max. D_max is the minimum over starting bodies of `speed × STARVING_SPEED × (max_health / STARVATION_DAMAGE) × 0.6` (16.3 m today, set by the omnivore). If it fails, move or resize zones; never weaken the test.

## 9. Scene trees and the loop

```
main.tscn
Main (Node, main.gd)            owns GameSession and RunFlags; one screen child at a time;
                                close-request prompt (auto_accept_quit = false);
                                in debug builds: load("res://game/dev/...") and add DevLayer
└─ <screen>                     StartScreen (game/ui/start_screen.tscn) or Pool (game/scenes/pool/pool.tscn)

pool.tscn
Pool (Node3D, pool.gd)          setup(session: GameSession, intent_provider: Object = null)
├─ WorldEnvironment             pool_environment.tres
├─ Sun (DirectionalLight3D)     rot (-60, 30, 0), shadows, 2 splits, max distance 40 m
├─ Floor                        instance of assets/export/pool_floor.glb (cast_shadow off)
├─ Rocks (Node3D, rock_field.gd)        rock_a/b/c.glb at layout position, yaw, uniform scale
├─ Plankton (MultiMeshInstance3D, food_view.gd, kind=plant)   mesh taken from plankton.glb, shadows off
├─ Carrion  (MultiMeshInstance3D, food_view.gd, kind=meat)    mesh taken from carrion.glb, shadows off
├─ %PlayerCell (instance player_cell_view.tscn)
│  ├─ Model                     sample_cell.glb; Body/Mouth and Body/Flagellum hidden; eyes and pupils kept
│  ├─ Parts (Node3D)            part_*.glb placed by PartPlacement (sibling of Model, so Body's
│  │                            non-uniform scale never squashes parts)
│  └─ EatFx (CPUParticles3D)    ≤ 12 particles
├─ %Feedback (Node3D, feedback_fx.gd)   pooled Label3D: "+8 energy · +1", "Regrowing" over emptied zones
├─ %Camera (Camera3D, pool_camera.gd)
├─ %SwimInput (Node, swim_input.gd)
├─ %Audio (Node, placeholder_audio.gd)
└─ UI (CanvasLayer 10)          Hud, PauseMenu, Notice, TargetRing (2D ring at the cursor's plane point),
                                StarvingArrow (screen-edge arrow)
```

Wiring:
- Nodes are wired with `%UniqueName` and typed `@export`, not path strings.
- The only name lookups are the GLB contract names (`Body/Mouth`, `Body/Flagellum`, `socket_*`), which a test asserts.

### `pool.gd`

```gdscript
func _physics_process(_d: float) -> void:              # 60 Hz; delta unused
    if paused: return
    var t0 := Time.get_ticks_usec()
    sim.step(intent_provider.next_intent(sim))         # SwimInput or ForageBot: same method
    perf.record(Time.get_ticks_usec() - t0)
    for e in sim.drain_events(): _route(e)             # HUD, feedback, audio, notice

func _process(delta: float) -> void:
    var f := Engine.get_physics_interpolation_fraction()
    cell_view.show_motion(sim.motion, f)               # lerp prev→current, lerp_angle, then yaw_for_heading
    camera.follow(cell_view.position, sim.display_velocity(), delta)
    plankton_view.sync(sim.plankton.items, sim.tick)   # writes MultiMesh.buffer once; visible_instance_count
    carrion_view.sync(sim.carrion.items, sim.tick)
```

- Interpolation is manual; `physics/common/physics_interpolation` stays off.
- Pause uses the scene's own `paused` flag, so the UI keeps processing.

### `player_cell_view.gd`

- **Part placement.** `PartPlacement.transform_for(angle, type)` puts each part on the body ellipse, with `rx = 0.46` and `rz = 0.5` taken from the sockets.
  - Position is `(rx·sin a, 0, −rz·cos a)`.
  - The part's −Z axis follows the outward normal `(sin a / rx, 0, −cos a / rz)`.
  - The eye spot sits at y = 0.18, with horizontal semi-axes scaled by √(1 − (0.18/0.39)²).
- **Procedural motion** (no rig until step 5):
  - flagellum yaw wag ±15° at 2–6 Hz, scaled by speed;
  - bank up to 8° from turn rate;
  - a gulp pulse (scale 1.0 → 1.08 → 1.0 over 0.2 s) on `ate`;
  - a small head-shake (±6°, 0.3 s) on a diet refusal hint;
  - grey tint and slower wag while starving.
- **Feedback on eating.** On `ate`, a ghost of the item flies to the mouth in 0.15 s.

## 10. Camera (`pool_camera.gd`, not parented to the cell)

- **Fixed view.** Yaw is fixed north-up and never rotates. Pitch is −55°, vertical FOV 45°, near 0.1, far 200.
- **Distance.** Default 14 m; the wheel zooms between 10 and 20 m in 2 m steps, smoothed over 0.25 s. At 14 m the view at the cell is about 20.6 m wide, from 5.5 m behind to 10 m ahead. At 1080p the cell is about 86 px wide.
- **Target.** The interpolated cell position plus look-ahead `display_velocity × 0.35 s`, capped at 2.5 m.
- **Follow.** `pos = target.lerp(pos, pow(0.5, delta / 0.12))` in `_process`.
- **No effects.** No shake, roll or FOV kick, so there is nothing to disable for reduced motion.
- **No void at the rim.** The floor mesh runs to r = 58.

## 11. Input (keyboard and mouse; fixed defaults)

| Action (`project.godot` `[input]`, physical keycodes) | Default | Behavior |
|---|---|---|
| `move_up` / `move_down` / `move_left` / `move_right` | W/S/A/D and arrow keys | `Input.get_vector("move_left","move_right","move_up","move_down")` is already a plane vector, relative to the screen (which is the world, since yaw is fixed). AZERTY players get ZQSD in the same physical place |
| `swim_to_cursor` | Left mouse, hold | Swim toward the cursor's point on the plane (see below) |
| `zoom_in` / `zoom_out` | Mouse wheel | Camera zoom |
| `pause` | Esc, P | Pause menu |
| `toggle_fullscreen` | F11 | Borderless fullscreen, for the 1080p check |
| `toggle_debug`, `dev_fill`, `dev_drain`, `dev_empty_zone`, `dev_spawn_carrion` | F3, F5, F6, F7, F8 | Handled only by `game/dev/dev_keys.gd` (debug builds) |

**Swim to cursor:**
- The point comes from `PlaneSpace.ray_to_plane(camera.project_ray_origin(m), camera.project_ray_normal(m))`.
- The intent comes from pure `SwimInput.pointer_move(cell_pos, target_pos)`: zero inside 0.3 m, ramping to full at 2.5 m.

**Rules:**
- Any held swim key wins over the mouse.
- Mouse-held state starts only on a press in `_unhandled_input`, so GUI clicks never start a swim. It is cleared on release.
- Opening pause or a dialog, and window focus loss, clear all held state; focus loss also auto-pauses. After resuming, the mouse must be pressed again (Bible 19).
- Eating is automatic on contact, and the resolver decides. There is no eat key; Space and right mouse stay unbound for step 3.

**Key labels (`game/ui/key_label.gd`).** For each action, the first `InputEventKey` gives its physical keycode.
- In a window: `OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(code))`.
- When `DisplayServer.get_name() == "headless"`: `event.as_text_physical_keycode()`. This guard avoids the verified headless engine ERROR.
- Never `as_text()`, which returns "W - Physical".

Remapping and controllers stay out of scope. Using actions keeps both cheap to add later.

## 12. Start screen, HUD, pause and the interim death notice

### Start screen (`game/ui/start_screen.tscn`, keyboard-navigable, first button focused)

- **Header.** Title "Pangaea"; `BuildInfo.build_id()` at the bottom right. No mock buttons for later eras.
- **Continue** is enabled when `session.peek_slot().ok`. Its card shows:
  - body name (`Lineage.starting_body_of`, or "Evolved cell");
  - lineage tag (the first 8 hex digits of `lineage_id`, as `3F9A-C21B`);
  - generation, adaptation points and the local saved time;
  - a `CellPreview` of the saved genome.

  If the save loaded from the backup: "Your last save could not be read; continuing from the backup." If neither file loads, Continue is disabled and the dialog lists the PersistenceService errors. Nothing is deleted.
- **New lineage** opens a picker with three `BodyCard`s.
  - Each card shows a one-line role description and diet ("Eats plankton" / "Eats carrion" / "Eats both").
  - Stats come from `Phenotype.derive`: speed (m/s), turning (°/s), upkeep (energy/s), sight (m) and energy capacity.
  - One shared `CellPreview` (SubViewport with its own World3D) shows the focused body.
  - If a save exists, confirm first: "This replaces your current lineage. The previous save is kept as a backup until your next save." This matches `save_to`, which moves the old file to `.bak`.
  - **Start** calls `main.start_new(body)`. This is the same method the smoke test calls.
- **Quit.**

### HUD (`game/ui/hud.tscn`, mouse_filter IGNORE)

Labels refresh at 10 Hz or on change; bars every frame.

- **Top left:**
  - energy bar with "Energy 62 / 100" and a state chip: Fed, Hungry (< 25%) or Starving;
  - health bar, shown only while health is below max or the cell is starving;
  - "Grazer lineage 3F9A-C21B · Generation 1".
- **Top right:** "◆ 7 adaptation points". It flashes +N on `ate` and `earned`.
- **Starving.** Banner (icon and text, not colour alone): "Starving: you are slow and losing health. Find food." It pulses at 1 Hz. Health appears, the cell greys, and the StarvingArrow points to `sim.nearest_edible()` (data assist flag, PROPOSED).
- **Meal toasts:** "+8 energy · +1 point". Survival: "+1 point · survived 30 s".
- **Refusal hints** (bottom center) follow the `refused` event rules:

  | Reason | Shown when | Text |
  |---|---|---|
  | Diet ("needs a jaw" / "needs a filter mouth") | Immediately while touching; same reason at most once per 4 s | "Needs a jaw: your filter mouth only eats plankton" |
  | "mouth is not facing it" | After `contact_s ≥ 0.5` | "Turn your mouth toward it" |
  | "not hungry" | At most once per 5 s | "Full" |
  | Unknown reason | As given | As given |
- **Controls hint** (bottom left), built from `key_label`. Shown until the first meal or for 30 s; it is also in the pause menu. The first-meal hint depends on diet.

### Pause menu

- **Buttons:** Resume, Save (toast "Saved 14:02" or the error text), Save and quit to title, Quit to desktop.
- **Quit to desktop** asks "Save first?" when `dirty`. The window-close request uses the same dialog.
- **Footer:** "Seed 4242 · build 0.0.2-m1+abc123".

### Death notice (interim, until step 3 checkpoints)

1. On `died`, the notice reads: "Your cell starved. The lineage continues. You lose a quarter of your unspent adaptation points (−N)."
2. The world keeps drifting and saving is disabled.
3. **Continue** calls `session.respawn_after_death()`, which runs `Lineage.apply_death(save, "starved")` and then `sim.respawn_player()`. The cell returns to the layout spawn, which is the generation 1 start, with fresh ActorState and cleared cooldowns. The world is kept.

This is the approved death rule, applied at the only checkpoint step 2 has.

## 13. Debug panel and the dev build

**Existence.** It exists only when `OS.is_debug_build()`: editor runs, headless CI and `Pangaea-dev.exe`.
- `main.gd` loads `res://game/dev/*` by path under that check.
- The release preset excludes `game/dev/*`, so the release exe does not contain it.
- F3 toggles it. CanvasLayer 20, right side, refreshed at 4 Hz.

**Fields:**
- **Identity:** build id, `genome_id`, `lineage_id`, generation, starting body, `world_seed`, the derived region and carrion seeds, slot path, last save result and load source. Copy button for seed, build, genome id and position (clipboard guarded headless).
- **Sim:** tick and sim time; step cost (average and max over 120 ticks, µs).
- **Rendering and performance:** FPS, frame ms, draw calls (`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`), adapter (`RenderingServer.get_video_adapter_name()`), rendering driver and vsync. The adapter line shows whether the RTX 5070 or the AMD iGPU is in use.
- **Actor:** energy/capacity, health/max, starving flag, speed multiplier, alive time and next survival point, position, heading (°), speed, soft-wall depth.
- **Derived stats:** `Phenotype.to_dict()`, plus radius, mouths (type, angle°, arc°) and the effective top speed now.
- **Feeding:** the last 6 resolver results with reasons.
- **Ecology:** per zone, amount/capacity bar, items and empty/regrowing state; carrion count and next interim arrival.
- **Commands** (buttons, plus F5–F8), all through `PoolSim.debug_*`, which log `debug` events: Fill energy, Drain energy, Empty nearest zone, Spawn carrion 4 m ahead, Teleport to spawn, toggle DevGizmos (zone rings, resolver mouth arcs, reach circle with ImmediateMesh lines), VSync on/off.
- **No AI line** until step 3.

`game/dev/perf_tour.gd` (cut first if late): `Pangaea-dev.exe -- --perf-tour` runs ForageBot for 90 s at the current resolution and writes `user://reports/perf_<build>.json`. Contents: average FPS, 1% low, max frame ms, adapter, driver, resolution and vsync.

## 14. Art and audio: Blender blockouts now, no mesh placeholders

`tools/blender/make_m1_blockouts.py [--only <id>]` uses shared helpers in `blockout_common.py` (materials, sockets, bounds, triangle count, record writer, glTF export with the same settings as `make_sample_cell.py`).
- Run with `~/tools/bpyenv/bin/python` or `blender --background --python`.
- It is deterministic (fixed formulas and `mathutils.noise` offsets).
- Each asset writes `assets/source/blender/<id>.blend`, `assets/export/<id>.glb` and `assets/records/<id>.json`, with `status: PROPOSED`, `review_state: "blockout - M1 step 2, not visually approved"` and procedural provenance.

| Asset id | Blockout spec | Budget |
|---|---|---|
| `pool_floor` | Radial grid to r = 58. Height −1.6 at the center, −1.0 at r = 30, −0.6 at r = 36, −0.45 at r = 39 (so the 0.78 m tall cell never clips inside the hard limit). Rim lip rises to +1.2 at r = 42 with a pale stone band; shelf at about +1.0 to r = 58. Gentle undulation. Materials `M_PoolSand`, `M_PoolSilt`, `M_PoolRimStone`, assigned per face | ≤ 20k tris |
| `rock_a`, `rock_b`, `rock_c` | Displaced, flattened icospheres. Pivot at the swim plane; mesh from y −2.0 to +0.6 at scale 1 (top ≤ 0.96 m at scale 1.6). Record key `footprint_radius_m: 1.0`. Warm grey-brown | ≈ 1.3k each |
| `plankton` | Green diatom glob about 0.36 m across, slight emission. One MeshInstance3D (for the MultiMesh) | ≤ 400 |
| `carrion` | Irregular dull red-brown chunk with a pale streak, about 0.6 m. Static, no drift, so it reads by shape and motion, not colour alone. One MeshInstance3D | ≤ 400 |
| `part_mouth_filter`, `part_mouth_jaw`, `part_flagellum`, `part_eye_spot` | Origin at the attachment point; extends along Blender +Y (Godot −Z). Fringed funnel 0.32 m; twin dark mandibles 0.3 m; tapered S-curve 0.75 m; orange pigment dome 0.12 m | ≤ 1.5k each |

- Cilia and spike meshes wait for step 4, when the editor can add them.
- The sample cell's baked `Mouth` and `Flagellum` are hidden, so only genome parts show. A test asserts the node names.

**Placeholders.** `assets/records/placeholders/inventory.json` has the form `{"placeholders": [...], "functional": [...]}`.
- **Placeholders:** the expected entries are only the runtime-synthesized audio cues, each with `remove_by: "M1 step 5"`.
- **Functional:** CPUParticles3D quads (EatFx), Label3D, and dev-only ImmediateMesh gizmos. Bible 15 counts particles, UI and debug as functional.
- **If a blockout slips:** an engine primitive may stand in only with an entry in `placeholders` that names the asset id, file, node and `remove_by`.

**Audio.** `placeholder_audio.gd` builds `AudioStreamWAV` buffers at startup, with no files:
- `eat_plant` (rising blip), `eat_meat` (two low chomps), `refuse` (dull two-tone), `starve_pulse` (≤ 1 Hz), and a 4 s filtered-noise ambience loop;
- level −14 dB, with repeats of the same sound limited to one per 60 ms;
- every cue has a visual equivalent.

## 15. Save and continue (no new save fields)

**`GameSession`** (`game/systems/game_session.gd`, RefCounted, owned by Main):

```gdscript
const DEFAULT_SLOT := "user://saves/slot_1.json"   # %APPDATA%\Pangaea\saves\slot_1.json on Windows
func _init(slot := DEFAULT_SLOT, layout_path := PoolLayout.DEFAULT_PATH)
func peek_slot() -> Dictionary        # {"exists","ok","source","summary","errors"}; never writes
func start_new(body: String, seed := -1) -> Dictionary   # -1: randomize() then randi() (non-negative)
func continue_run() -> Dictionary     # {"ok","source","errors"}
func save_now() -> Dictionary         # {"ok","error"}; refused while sim.dead
func respawn_after_death() -> int     # Lineage.apply_death + sim.respawn_player; returns points lost
var dirty: bool                       # points changed, moved > 1 m or died since the last save
```

**New lineage:**
1. `Lineage.found(seed, BuildInfo.build_id(), catalog, body)`.
2. `save.player.position = PlaneSpace.to_save(layout.spawn)`.
3. `PersistenceService.save_to(slot, save)`. This explicit start makes Continue reliable; it is not autosave.
4. Build the sim.

**Save points:** pause → Save; Save and quit to title; the quit/close dialog. Each runs `sim.write_position_to_save()` and then `save_to`. There is no timed autosave; per-generation autosave is step 4.

**Continue:**
1. `load_from(slot)`, falling back to the backup and reporting it.
2. `PoolSim.create(save, ...)`.

**What carries over:**

| Restored (saved fields) | Not restored (no schema field) |
|---|---|
| Lineage id | Energy and health (the cell restarts at `ActorState.fresh`: 60% energy, full health; the toast says "Your cell rested: Energy 60%, Health full") |
| Genome (same parts, so the same look) | Heading (faces the nearest zone) |
| Generation and lineage history | Zone stock, plankton and carrion (the world restarts from the seed) |
| Adaptation points | Alive timer |
| World seed | |
| Player position (validated; layout spawn otherwise) | |

Persisting actor state would be schema v3 with a migration and a fixture: a step 4 decision.

**Isolation:**
- `--slot=` overrides the path.
- Smoke runs use `user://smoke/…` and tests use `user://test_saves/<pid>/…`, so CI never touches the owner's save.
- Known interim limitation: quitting without saving after a death skips the death penalty until step 4 autosave.

**Guard test.** A saved file's key set equals the 15 v2 keys and `schema_version == 2`. A field added without a migration fails CI.

## 16. Headless CI

### `tools/check.sh`

The CI workflow file does not change; it already runs `check.sh` and the export.

```bash
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://tests/run_tests.gd
"$GODOT" --headless --path . res://game/scenes/boot.tscn -- --smoke                 # M0 checks, unchanged
mkdir -p builds/smoke
"$GODOT" --headless --fixed-fps 60 --path . --quit-after 300 -- --slot=user://smoke/launch.json 2>&1 | tee builds/smoke/launch.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=found --slot=user://smoke/slot_1.json --seed=4242 2>&1 | tee builds/smoke/found.log
"$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke/play_smoke.gd -- --phase=continue --slot=user://smoke/slot_1.json 2>&1 | tee builds/smoke/continue.log
if grep -E "SCRIPT ERROR|^ERROR:" builds/smoke/*.log; then echo "engine errors in smoke logs"; exit 1; fi
```

`pipefail` (already set) keeps the Godot exit codes.

### Unit and integration tests (`run_tests.gd`, synchronous, no scene tree)

| File | Asserts |
|---|---|
| `test_plane_space` | Section 3 |
| `test_locomotion` | Reaches `speed` within 1% and never exceeds `speed × mult`. Time to 90% speed in [0.5, 1.5] s. Heading change per tick ≤ `turn_rate·dt`. Reversal to 90% opposite speed ≤ 2.0 s. Starving halves top speed. Coast stop in [0.8, 2.5] m. Adding spikes (catalog-derived) is slower. Asking straight behind gives no forward thrust until the heading passes 90° |
| `test_pool_arena` | 10,000-step seeded random-intent fuzz: rock penetration ≤ 1 mm and r ≤ hard − radius. Glancing contact (0.8 m offset) clears the rock within 3 s of first contact. Steering away from a touching rock separates within 0.5 s. No tunneling at 6 m/s through a 0.8 m rock. Full outward thrust for 20 s settles in [37.5, 39.0]. Release: r < 36.5 within 10 s. The returned distance equals the displacement |
| `test_pool_layout` | Section 8 runtime and test-only rules on the real `pool_m1.json`, including reachability |
| `test_plankton_field` | After random takes and ticks, items = min(max, floor(amount/unit)). Spawns inside the zone and clear of rocks. Same seed, same positions. Drift stays within its amplitude. Carrion spawns never draw from the region RNG |
| `test_carrion_field` | Interim supply deterministic per seed. Never above `max_live`. Expiry at lifetime. `enabled: false` means no spawns. `spawn(p, "kill", e)` works (the step 3 contract) |
| `test_interactions` (+) | "not hungry" when room < half the food's energy. Refusal order is diet → reach → facing → not hungry → cooldown. The refusal starts no cooldown. Existing cases unchanged |
| `test_lineage` (+) | `starting_body_of` names each body; an edited genome gives "" |
| `test_part_placement` | Angle 0 lands within 0.03 m of `socket_mouth`, +π/2 at `socket_side_R`, π at `socket_tail`. The part's −Z axis is the outward normal |
| `test_swim_input` | `pointer_move` is zero inside 0.3 m, full at ≥ 2.5 m, direction exact. `ray_to_plane` handles parallel rays. `key_label` returns "W" headless |
| `test_sim_purity` | Scans `game/domain/*.gd` and the sim files (`pool_sim`, `plankton_field`, `carrion_field`, `sim_intent`): no bare global RNG calls, no `Time.`, `OS.`, `Input.`, `get_tree(`, `extends Node`, `FileAccess` or `DirAccess`. `part_catalog.gd` is allow-listed for its read-only data load |
| `test_project_settings` | Main scene is `main.tscn`. No autoloads. Every action exists with physical-keycode events. Release preset excludes `game/dev/*`; the dev preset exists. No file outside `game/dev` references `res://game/dev/` except `main.gd`'s guarded loader |
| `test_placeholders` | Scans `game/**/*.gd`, `.tscn` and `.tres` for primitive mesh classes and `*Mesh.new()`. Every hit must be in the inventory. A placeholder whose asset id now has a record fails, which forces its removal |
| `test_assets` (+) | Dimension check generalized to every record with `dimensions_m` (±0.05 m). Parts: bounds max z ≤ 0.05 and center z < −0.05. Food mesh radius within 20% of `item_radius`. Rock footprint within 15% and top ≤ 0.6 m at scale 1. Floor: max height ≤ −0.45 for r ≤ 39, above +0.8 over r 41.5–43. `sample_cell` has `Body/Mouth`, `Body/Flagellum`, `Pupil_L/R`. Food GLBs have exactly one MeshInstance3D |
| `test_game_session` | See below |

`test_pool_sim` (ForageBot loaded by path from `game/dev/forage_bot.gd`):

1. **Each body founds and eats** (seed 1234, real layout): within 20 s of sim time there is an `ate` of an edible kind; energy rises on that tick; points rise by the food's points.
2. **Diet refusals change nothing:**
   - a hunter touching plankton gets "needs a filter mouth";
   - zone amount, item ids, energy, points, cooldowns and `alive_s`-independent state are unchanged.
3. **Zone empty and regrow** (fixture: one zone, capacity 24, unit 8, no rocks, interim off):
   - start energy 5; the bot empties the zone and `zone_empty` fires;
   - it parks 6 m away with zero intent;
   - the first item returns ≤ 30 s, all items ≤ 90 s, and `zone_regrown` fires;
   - every item lies within the zone; `plant_taken` equals the plankton energy supplied.
4. **Starvation is recoverable:**
   - grazer at 0 energy, 12 m from a zone: measured top speed ≤ 0.5 × speed + ε;
   - it eats before dying, then `is_starving()` is false and full speed returns;
   - repeated for the hunter from the layout's worst point over 3 fixed seeds. If one fails, tune `max_live` or the interval, not the test.
5. **Death:** with no input the cell dies; `died` fires exactly once; a dead cell does not move; `respawn_player()` restores it at spawn. Through GameSession, points drop by floor(25%) and history gains `died`.
6. **Determinism:** two sims with seed 77 and the same scripted intents over 1800 ticks have equal `state_hash()`. Seed 78 gives different plankton positions.
7. **Feeding goes through the resolver:** a valid custom genome with its filter mouth at +π/2 (right side) swims straight into plankton and gets no meal (last refusal "mouth is not facing it"). With the food on its right, it eats.
8. **Full stomach:** at full energy, touching edible food gives "not hungry" and changes nothing. At room = half the food's energy, it eats.
9. **Survival points:** 61 s alive gives +2; ticks not stepped give none; the timer resets on respawn.
10. **Step cost:** 3600 ticks on the real layout. Prints the average µs; fails only above 1000 µs.

`test_game_session`:
- `start_new("omnivore", 5150)`, 600 bot ticks, `save_now()`;
- a fresh GameSession on the same slot runs `continue_run()`: lineage id, genome JSON, points, seed and history are equal, position within 1e-3, source "primary";
- the key-set guard passes;
- a corrupted primary leads to source "backup", and `peek_slot()` reports it;
- `peek_slot()` leaves file mtimes unchanged;
- a new lineage over an existing save turns the old file into `.bak`.

### Scene smoke (`tests/smoke/play_smoke.gd`, a SceneTree script; nodes are awaited into the tree before use)

**Found phase:**
1. Clear `user://smoke/` and instance `main.tscn`.
2. The start screen shows three body cards whose stat text equals the formatted `Phenotype.derive` values.
3. Call `main.start_new("grazer")`. The pool runs with ForageBot as intent provider for up to 40 s of sim time. Check:
   - at least 2 `ate` events and points ≥ 2;
   - the HUD energy text equals the sim energy;
   - `cell_view.show_motion(motion, 1.0)` puts the view within 1 mm of `PlaneSpace.to_world(position)`;
   - camera pitch is 55° ± 0.5°;
   - the cell's `unproject_position` stays inside the central 40% of 1920×1080;
   - plankton and carrion `visible_instance_count` equal the sim counts;
   - the debug panel shows `genome_id` and the seed.
4. Drain energy through `debug_set_energy(0)`: the starving banner and arrow are visible. The bot recovers and the banner hides.
5. Pause → Save and quit to title, through the same methods the buttons use. Write `user://smoke/expect.json` (lineage id, genome id, part types and angles, points, position).
6. Brief hunter and omnivore runs on their own slots must each eat within 40 s.

**Continue phase (a new process):**
1. Continue is enabled and its card shows the lineage tag and body.
2. Continue loads the pool.
3. Lineage id, genome id, the PlayerCell part children (count, type and angle), points (and the HUD points text) and position (±1e-3) all match.

Output is PASS/FAIL lines and exit code 0 or 1.

## 17. Performance (target 60 fps at 1080p on the RTX 5070 / 9800X3D)

**Sim (CPU):** one actor, 18 rocks, 7 zones, at most 61 plankton and 6 carrion. Brute-force queries, with item dictionaries reused. Expected 30–100 µs per tick, against a 16.7 ms frame.

**Rendering:**
- Forward+, MSAA 3D 4x.
- One directional light, 2 shadow splits capped at 40 m.
- Standard depth fog (no volumetric fog); glow low (plankton emission only); SSAO, SSIL, SSR and SDFGI off.
- Food, effects and floor cast no shadows. No textures and no transparent water surface.
- Expected draw calls:

  | Item | Calls |
  |---|---|
  | Floor | 3 materials |
  | Rocks | 18 (or 3 MultiMeshes if profiling says so) |
  | Food | 2 MultiMeshes |
  | Cell and parts | about 10 |
  | UI | the rest |
  | **Total** | well under 100 |

  About 70k triangles in total.

**Per frame:**
- one `MultiMesh.buffer` write per food view;
- HUD labels at 10 Hz and the debug panel at 4 Hz;
- pooled CPUParticles3D and Label3D;
- manual interpolation for high-refresh monitors;
- vsync on;
- default `max_physics_steps_per_frame` of 8, so a hitch slows the sim rather than letting it spiral.

**Shader hitches:** Godot 4.7 ubershaders, plus a 0.3 s fade-in at pool start during which one hidden eat burst emits and both food materials are on screen.

**Measuring:**
- CI records only sim and process cost.
- The owner runs `Pangaea-dev.exe` fullscreen at 1920×1080 with vsync off from the debug panel, and confirms the adapter line names the RTX 5070. Godot's `--gpu-index` or the Windows "High performance" setting are the fallbacks.
- `--perf-tour` JSON is the evidence. Note that the debug template adds a little GDScript overhead; the release-build measurement belongs to step 6.

## 18. Build order (one PR, reviewable in order) and cut list

1. **Domain:** PlaneSpace, Locomotion, PoolArena, the resolver `room` rule, `starting_body_of`, and their tests.
2. **Systems:** `pool_m1.json`, PoolLayout, PlanktonField, CarrionField, PoolSim (with survival points and `Lineage.earn`), GameSession, RunFlags, plus `game/dev/forage_bot.gd` and `test_pool_sim` / `test_game_session`. **All four acceptance items are proven in CI here, without a scene.**
3. **Blender blockouts:** records, the placeholder inventory, and the `test_assets` and `test_placeholders` changes.
4. **Pool scene:** cell view and parts, camera, input and key labels, food views, rock field, feedback, audio.
5. **UI:** start screen, body picker and preview, HUD, pause, death notice. Then the dev layer: debug panel, gizmos, dev keys.
6. **Build plumbing:** `main.tscn` as main scene, export presets, `export_windows.sh`, `check.sh`, the play smoke, `test_project_settings`.
7. **Docs:** M1.md step 2 section in the Bible handoff format, DECISIONS, TOOLCHAIN and README. CI exports both exes; label them "exported but not Windows-verified" until the owner runs the checklist.

**Cut first if late:** perf tour; CellPreview (fall back to text cards); "Regrowing" labels; part blockouts (fall back to listed placeholder primitives so the bodies stay distinguishable).

**Never cut:** feeding through the resolver, starving cues, save/continue, the dev-only debug panel, and the step 2 acceptance tests.

## 19. Acceptance mapping

| Item | Player path | Automated proof |
|---|---|---|
| Start a lineage and eat | New lineage → body → Start. Spawn is 4 m from the center zone, facing it; the hunter's carrion is 5.2 m away | `test_pool_sim` #1, smoke found phase (3 bodies) |
| Recover from starvation by finding food | Play until starving, or F6 in the dev exe. Banner, half speed, health bar and arrow appear. Every open point is ≤ 15 m (path) from a zone. Eat, and the banner clears | `test_pool_sim` #4, the reachability rule, smoke starving step |
| Eat a zone empty and watch it regrow | Center zone: 6 items, about 10 s to empty from 60% energy. First item back after about 15 s, all after about 56 s ("Regrowing" label; debug bars) | `test_pool_sim` #3, `test_plankton_field` |
| Save, quit, reload and recognize the same lineage and body | Esc → Save and quit → Quit → relaunch. The Continue card shows body, lineage tag, generation, points and a preview. Same parts, place and points | `test_game_session`, the two-process smoke |

**Owner Windows checklist** (record commit, resolution and FPS in M1.md):
1. Launch `Pangaea.exe` and see the start screen.
2. Start each body and eat.
3. Starve and recover.
4. Empty the center zone and watch it regrow.
5. Save, quit to desktop, relaunch, Continue: same body, tag and points.
6. F11 fullscreen at 1080p.
7. `Pangaea-dev.exe`: F3 shows the RTX 5070 adapter and FPS. Run `-- --perf-tour` and send the JSON.

## 20. Decisions to record in `docs/DECISIONS.md` (all PROPOSED; none changes the approved goal)

1. **Plane convention:** world (x, 0, y), north-up camera, positive part angles on the cell's right. The step 4 editor and mirroring must match.
2. **Full-stomach refusal:** `"not hungry"` when room < 50% of the food's energy (`FEED_MIN_ROOM_SHARE`).
3. **Survival points** (the existing step 1 rule) are live in play.
4. **Interim carrion source** (`interim: true`, in-zone, `spawn()` contract). Step 3 turns it off so carrion comes from kills; keeping a trickle needs owner approval.
5. **Interim death handling:** `Lineage.apply_death` plus respawn at the generation 1 start until step 3 checkpoints. Unsaved deaths can be skipped by quitting without saving until step 4 autosave.
6. **Energy, health and heading are not saved;** Continue gives 60% energy. Schema v3 is decided in step 4.
7. **Debug panel only in debug builds:** a separate `Pangaea-dev.exe` CI artifact; the release excludes `game/dev`.
8. **Main scene is `main.tscn`;** the M0 checks run via `boot.tscn` by path.
9. **Starving food arrow** assist (forgiving preset, data flag).
10. **Camera:** pitch 55°, FOV 45°, distance 14 m (zoom 10–20 m), fixed north-up yaw.

## 21. Risks

| Risk | Early warning | Response |
|---|---|---|
| Rule mouth and visual mouth disagree (sign or handedness) | "Turn your mouth toward it" while the mesh visibly faces the food | PlaneSpace is the single mapping. Socket cross-check tests. DevGizmos draws the resolver's mouth arcs |
| Turn rate plus facing arcs make food fiddly | Slow first meals; many facing refusals | Alignment throttle, touch-only and 0.5 s facing hints, food radius 0.18. Tune `ALIGN_POWER` and `LATERAL_DAMPING` before domain constants |
| Hunter cannot find enough interim carrion | `test_pool_sim` #4 fails on a seed; owner deaths | In-zone placement, initial chunk near spawn, `max_live` and interval in data, starving arrow |
| Interim rules become permanent by accident | Step 3 lands with them still on | `interim` flags, DECISIONS entries, an M1.md step 3 to-do |
| Continue refills energy to 60% (save-scumming out of starvation) | Owner notices | Honest toast; decision 6 in step 4 |
| Hiding the sample's `Mouth`/`Flagellum` by name breaks on re-import | Duplicate mouth or tail | `test_assets` asserts the names; step 5 replaces the body |
| Dev code reaches the release build | F3 works in `Pangaea.exe` | Exclude filter, `OS.is_debug_build()` guard, `test_project_settings` |
| Headless-only engine errors | Log gate fails | Key-label guard; nodes awaited into the tree before `look_at` |
| Green CI but a broken or hitching exe (no GPU, shaders or Windows in CI) | Owner reports | Error-log gate, owner checklist, dev exe adapter line and perf tour. Report "exported but not Windows-verified" until it is run |
| Determinism drift | `test_pool_sim` #6 fails | Purity scan, seeded RNGs only, (distance, id) tie-break |
| `.blend` bloat in plain git | A source above about 5 MB | Keep the procedural floor small; raise the open Git LFS decision |
| Scope creep into step 3 | Perception or chase code in ForageBot | ForageBot stays a dev and test driver; creature AI starts fresh in step 3 |

## 22. Out of scope (unchanged)

- Threats and AI, bite and ram in play, checkpoints (only the interim respawn above);
- the editor UI, reproduction and per-generation autosave;
- final art and rig, cilia and spike meshes;
- real audio;
- controller support and remapping;
- settings files;
- any save schema change;
- new dependencies, network calls or runtime AI.

The web prototype stays a tuning sandbox.

## 23. Constraint flags found in the three plans

- **godot-native:** its starvation ending ("Load last save", no `Lineage.apply_death`) departs from the approved death rule (keep the lineage, lose a quarter of unspent points). Not adopted.
- **sim-first and godot-native:** both make the debug panel reachable in the release exe with `--dev`. That conflicts with "development builds only" (Bible 24 and the brief). Replaced by the dev exe.
- **player-first:** adds unrequested product changes:
  - a maximized default window;
  - a `settings.cfg` service;
  - lineage name generation;
  - algae-patch assets;
  - CI workflow edits;
  - feel, readability and UI-layout gates.

  None contradicts a constraint, but all are outside step 2 and are not adopted.
- **No plan adds save fields,** and every plan routes feeding through InteractionResolver. All three add points to the save directly and miss survival points; fixed above.