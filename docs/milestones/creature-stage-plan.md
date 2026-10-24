# Creature stage, first playable slice (PROPOSED)

Status: PROPOSED plan, 2026-10-23. Built under the owner's standing rules (keep shipping, review at merge). The owner's
direction of 2026-10-23 (`docs/DECISIONS.md`, "Generated creature skins, Spore-style full-body building") is CONFIRMED;
everything else here is PROPOSED until `docs/DECISIONS.md` says otherwise.

The goal of this slice: a player can open the creature stage from the title, build a creature in a Spore-style
editor (spine, limbs, art parts, live generated skin), walk it around a test field, eat and bite to earn points
and come back to the editor to spend them. The creature's anatomy drives its play: leg length sets speed and
cadence (the gait planner), mouths set bite power, eyes set sight, mass sets health.

## 1. What exists and what moves

The creature lab (`prototypes/creature-lab/`) is a separate Godot project with everything the stage needs, all
tested: body description and codec, capsule field, Surface Nets skin (GDScript and compute shader), generated
`Skeleton3D` rig with the art parts on anchors, the gait planner with `TwoBoneIK3D` legs, and the editor core
(`creature_editor_session.gd`, `editor_picking.gd`) with the same contract as `game/domain/editor_session.gd`.

The game cannot load a prototype (it is outside the export and the import), so this slice **ports** the lab into
`game/`. The lab stays as it is, as a tuning sandbox, like `prototypes/web-cell`. Godfrey's open PRs #70 (slither)
and #71 (skin volume) change only `prototypes/creature-lab/**`; nothing here touches that folder, and their results
are re-ported into `game/` when they merge (a follow-up, noted in the lab README by the port).

Port rules:
- Copy the lab code with as few changes as possible (paths, a `res://` loader in place of the lab's `../../assets`
  reads), so a later re-port is a diff, not a rewrite. No `class_name` on the ported files; they load each other
  by `preload` path, as in the lab.
- Domain files keep the lab's purity: no scene, file, OS, clock, input or global random access.
  `tests/test_sim_purity.gd` now scans `game/domain/` recursively, so `game/domain/creature/` is checked.
- The art team's parts stay theirs: `assets/export/cpart_*.glb`, their records and the skin shader are read, never
  edited. The part palette is built from the records' `part_rules`, as in the lab.

Ported into `game/` (2026-10-23, commits 64876e0 to 1f4f93e): the lab's `domain/*.gd` as `game/domain/creature/`,
`skin/` as `game/systems/creature/` with the new `creature_data.gd` loader, `rig/spine_rig.gd`, `walker_rig.gd` and
`part_library.gd` as `game/scenes/creature/`, the data files as `game/data/creature/` (`stage1_bodies.json` as
`starter_bodies.json`), the test-only bodies, drives and mesh checks under `tests/`, and the lab's four runners as
`tests/test_creature_{body,skin,anchors,editor,gait}.gd`. The purity scan now walks `game/domain/` recursively and
the generated skin is listed in the placeholder inventory.

Built since (2026-10-23, three parallel tracks merged at `5ad28f1`): the world's `creature_stats.gd`,
`creature_world_rules.gd`, `creature_rival_brain.gd`, `creature_world_sim.gd`, `creature_world.tscn/.gd` and
`creature_world_hud` (`0c35b8b`, `e00ba1a`, `2afafd6`); the editor scene and its HUD (`366d0b9`); the stage root and
`creature_store.gd` with the hooks in `main.gd`, `start_screen.gd` and `run_flags.gd` (`e5d0125`, `2a4e6a6`); the
two-process smoke (`1227b47`). The review after the merge (`703004f` to `298f641`) made a quit from the world keep
the sim's points, moved the part rules into `game/data/creature/part_rules.json` so the release pack carries them
(`tools/make_part_rules.py`, checked by `tests/test_assets.gd`) and added the stage to `tools/check_release.sh`.

## 2. Layout (new files)

| Path | Role |
| --- | --- |
| `game/domain/creature/` | Ported pure rules: `body_description.gd`, `body_codec.gd`, `body_field.gd`, `anchor_resolver.gd`, `creature_editor_session.gd`, `editor_picking.gd`, `body_mechanics.gd`, `gait_table.gd`, `gait_planner.gd`, `gait_body.gd`, plus new `creature_stats.gd` (anatomy to play numbers) and `creature_world_rules.gd` (the world's pure rules) |
| `game/data/creature/` | `body_rules.json`, `editor_costs.json`, `gait_table.json`, `starter_bodies.json` (the lab's Stage 1 bodies), `creature_stage.json` (world tuning, PROPOSED) |
| `game/systems/creature/` | `skin_grid.gd`, `skin_cpu.gd`, `skin_gpu.gd`, `surface_nets.glsl` (the skin builders; the GPU one owns its own `RenderingDevice`), `creature_data.gd` (loads the data files and the part rules from the records), `creature_rules.gd` (the creature's starter, start points and body checks for the lineage save), `creature_world_sim.gd` (the deterministic world simulation) |
| `game/scenes/creature/` | `spine_rig.gd`, `walker_rig.gd`, `part_library.gd` (ported; parts loaded from `res://assets/export`), `creature_editor.tscn/.gd`, `creature_world.tscn/.gd`, `creature_stage.tscn/.gd` (the stage root Main hosts) |
| `game/ui/creature_*` | The editor's palette, points bar and buttons; the world HUD (health, points, hint) |
| `tests/test_creature_*.gd`, `tests/smoke/creature_smoke.gd` | Ported lab tests in the main runner, the new rules' tests, and a scripted play-through smoke |

Main gets `open_creature_stage()`; the title screen gets a "Creature stage" button (marked as a preview); `--creature`
after `--` launches straight into it on the session's lineage slot, so `--slot=PATH` applies (the smoke's two
processes share `user://smoke/creature.json` this way and clean it up; the smoke stops before playing if the path is
anywhere else). Both are small edits to files other
departments own (`main.gd`, `start_screen.gd`, `run_flags.gd`); keep them to the hook and the button.

## 3. Saves (save schema v3, IMPLEMENTED)

Owner direction of 2026-10-24 ("follow the Bible", section 18) folds the creature into the lineage save:
`SaveGame.creature` holds `{"name", "body" (the codec's dictionary), "generation", "history"}` and its points are the
save's `adaptation_points`. The migration from v2 adds an empty creature; the body is validated against the body
rules and part rules (`CreatureRules`) and a broken one fails the load with reasons, the `.bak` loading instead. The
stage reads and writes the session's slot through `PersistenceService`, founds a lineage when the slot is empty, and
never writes over a slot that will not load. The first version's separate file (`CreatureStore`) is gone. Details in
`docs/DECISIONS.md`, 2026-10-24 · Save schema v3.

## 4. The editor (scene over the ported core)

- Mouse: left-drag a handle (vertebra, joint, part) to move it; with a part tool chosen, left-click the skin to add
  one; wheel over a selected vertebra or joint thickens or thins it, elsewhere zooms; middle-drag or the right stick
  orbits. The right mouse button and Space stay unbound (`tests/test_project_settings.gd`).
- Palette: one tool per part type in the art records, with a limb tool; the cost of each tool and the points left
  are shown; a refused edit shows its reason for two seconds, like the cell editor's refusal hints.
- Undo, redo, delete, insert, symmetry: the core's ops, on keys and on buttons. Every gesture is one undo step.
- Live skin: the GPU builder on a worker thread when the renderer has compute (Forward+); the GDScript builder
  otherwise (the compatibility renderer the cloud screenshots use). Handles follow the mouse at once, the skin catches
  up.
- "Test drive" walks the working body on the gait planner's legs in place of the editor view; a body with no legs
  says so (slither comes with Godfrey's #70).
- Skin colour: eight swatches (`SKIN_COLORS`, `set_skin_color`); the choice rides in the body dictionary's extra
  `skin_color` key, so the world and the save carry it without a schema change. Paint beyond a flat colour stays out.
- "Done" commits (validates, charges the points, writes the lineage save) and enters the world; a body with no legs is
  asked about once first. Escape and "Back" are progressive: the tool and the selection clear first, unsaved edits
  are asked about once, then it leaves to the title.
- Mouse-first: the pad orbits (right stick) and leaves (B); the tools, Done, Undo and the test drive are mouse and
  keyboard in this slice.
- Every mouse and key path has a method twin (`add_part_at(screen_pos)`, `choose_tool(type)`, `drag(from, to)`, ...)
  so the smoke and the UI tests drive it without input events, as `tests/smoke/play_smoke.gd` drives the pool.

## 5. The world (a test field, deterministic sim)

`CreatureWorldSim` runs at 60 ticks a second from the world seed, like `PoolSim`: whole-tick durations, every sort
tied by id, every draw from a seeded stream, snapshots as plain data. It holds the player, food and rivals; the scene
only presents it.

- A flat field 160 m across with a nest at the centre (the editor's spot). Food: fruit bushes (regrow) and meat
  left by kills. Eating fruit or meat gives points; the world is endless in time, not in space (walls at the edge).
- Rivals: 6 creatures built from the starter bodies with parts drawn from the seed. Brains get percepts only
  (`CreatureBrain`'s rule): wander, graze, flee a bigger creature, hunt a smaller one when hungry. A bite lands when
  the attacker's mouth reach touches the target; damage is the bite power.
- Anatomy to play (`creature_stats.gd`, pure): speed and cadence from the gait planner's leg length; bite power from
  mouth parts (maw, mandibles, beak) and their scale; sight range from eye parts; health from body volume; a body
  with no mouth can still eat fruit by touch, at half the points.
- Controls: `move_*` relative to the camera, `creature_bite` (F, pad X) and `creature_evolve` (E, pad Y) at the nest.
  New actions go into `project.godot` and the tables in `tests/test_project_settings.gd`.
- Death: health at zero sends the creature back to the nest at full health with a 20% points loss, with a notice.
- The camera follows behind and above the creature; the right stick or middle-drag orbits.

## 6. Gates

1. `tests/run_tests.gd` green with the ported lab tests (body, codec, field, skin closed on every starter body at
   the gameplay grid, anchor round trip, editor session ops and refusals, picking, gait planner) and the new ones
   (stats, world rules, world sim determinism: same seed and intents, same SHA-256 of the snapshot stream; lineage save round
   trip; purity).
2. `tests/smoke/creature_smoke.gd` in `tools/check.sh`: launch into the stage, build a body through the method
   twins (grow a limb pair, add a maw, two eyes and feet), commit, enter the world, walk, eat fruit, bite a rival,
   evolve back to the editor with more points, save; then a second phase in a new process loads the lineage save and finds
   the same body and points.
3. No engine or script errors in any smoke log; the release pack starts (`tools/check_release.sh`).
4. `tests/test_placeholders.gd`: every mesh the stage builds in code is listed in
   `assets/records/placeholders/inventory.json`: the generated skin (functional, kind "generated"), the editor handles
   and gizmos (functional, kind "ui"), the field, the nest and the fruit as placeholders that the creature-stage art
   pass removes.
5. A Windows export (`tools/export_windows.sh`), zipped to the project files as
   `Pangaea-M2-creature-preview-windows.zip`. Exported but not Windows-verified until the owner launches it.
   Pending: the zip is not on the project files mount yet (`builds/` holds the M0 and M1 zips); it waits for an
   export made after the part-rules fix above, since the export before it shipped a stage without tools.

## 7. Out of this slice (next)

Slither and stub gaits (Godfrey #70), skin volume at extreme swings (#71), paint patterns beyond the flat skin
colour, full pad control of the editor, more biomes and terrain relief, social play (packs, calls), the lineage save schema v3, Blender parity exports of a
built creature, and the look pass on the field, nest and fruit.
