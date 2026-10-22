# Decisions log

Each entry: date, decision, reason, impact, approval. Status labels follow the Bible: CONFIRMED, PROPOSED, IMPLEMENTED.

## 2026-10-22 · Engine stays Godot 4 (CONFIRMED)
Owner approved starting M0 in Godot 4 rather than switching to three.js. Reason: Windows builds, animation, physics and simulation come with the engine. The HTML prototype moves to `prototypes/web-cell/` as a tuning sandbox.

## 2026-10-22 · Toolchain pinned (IMPLEMENTED, owner review pending)
Godot 4.7.2-stable and Blender 5.2.2 LTS. See `docs/TOOLCHAIN.md`.

## 2026-10-22 · Product name (open)
The repository and window title use **Pangaea**; the Bible calls the project **GENESIS**. Treated as codename for now. Owner to confirm the player-facing name.

## 2026-10-22 · Thrive code not reused (owner aware)
Thrive is GPL-3.0. Reusing its code would require releasing Pangaea under the GPL. It may be studied as a design reference only, unless the owner decides otherwise.

## 2026-10-22 · M1 "First life" brief approved (CONFIRMED)
The owner set all seven decisions in the M1 brief (https://claude.ai/artifact/DjB7DT9NR2WL2SMALMyheT) to Approved:
1. **Scope caps** as written: one tide pool about 80 m across, one single-body cell rig, 6 editor parts (filter mouth, jaw, flagellum, cilia, spike, eye spot), 2 foods (plankton, carrion), 2 threats (ambush hunter, territorial rammer), 1 reproduction interaction, energy and adaptation points only, 1 save slot with backup and autosave per generation, placeholder audio.
2. **Starting bodies:** grazer, hunter and omnivore, picked when a lineage starts. Part layouts are tuning data in `game/data/part_catalog.json` (PROPOSED values).
3. **Camera and movement:** movement locked to one horizontal plane; camera tilted about 55 degrees and following the cell.
4. **Death rule:** respawn at the last generation checkpoint, keeping the lineage; unspent adaptation points drop by a quarter (`Lineage.DEATH_POINT_LOSS`).
5. **Difficulty:** one forgiving preset for M1; more presets later.
6. **Era names:** the seven names from Bible section 4 stay as working names.
7. **Baseline Windows PC:** the owner's own PC: AMD Ryzen 7 9800X3D, NVIDIA GeForce RTX 5070 (12 GB), 32 GB RAM, Windows 64-bit. It also has AMD integrated graphics; performance checks must run on the RTX 5070. This is a high-end machine, so a lower minimum spec should be chosen later (around the M2 visual benchmark).

## 2026-10-22 · Save schema v2 (IMPLEMENTED)
Adds `adaptation_points` (unspent, never negative). `SaveMigrations.v1_to_v2` upgrades M0 saves in memory with 0 points; `tests/fixtures/save_v1.json` covers it. Approved as part of the M1 brief (the brief lists adaptation points as a saved resource).

## 2026-10-22 · M1 tuning numbers (PROPOSED)
Part costs, effects, diminishing returns (each further copy gives 60% of the previous one; spikes hitting together stack the same way, strongest first), caps, starvation, regeneration, survival points (one per 30 s alive), interaction reach and cooldowns are first-pass values. They live in `game/data/part_catalog.json` and the constants at the top of each `game/domain` file, and will be tuned in play from M1 step 2 on.

## 2026-10-22 · Spore files are not used (CONFIRMED)
The owner offered to buy Spore and extract its files for formats. Declined: we do not need EA's formats, and reading data out of their files would risk Pangaea being treated as derived from them. Playing the game for design notes written in our own words is fine.

## 2026-10-22 · Studio operating model (CONFIRMED)
The owner set how the studio works:
- Claude is the studio lead. Engineering, research and design, and art run as parallel threads.
- Every commit is pushed right away (`git push -u origin HEAD`).
- A daily research digest goes to the owner.
- Changes to the vision or the scope still need the owner's approval.

## 2026-10-22 · Minimum visual quality bar (CONFIRMED)
The Steam store page of Spore (2008) is the minimum visual quality bar. Pangaea matches its polish, never its designs: no creature, part or interface design is copied. Impact: the M1 step 2 blockouts are below this bar; they are placeholders until the step 5 art pass.

## 2026-10-22 · CC0 resources by default (CONFIRMED)
Art may use CC0 resources by default, from sources such as Poly Haven and ambientCG. Each one used is logged in the record of the asset that uses it. Reason: CC0 puts no terms on the game.

## 2026-10-22 · M1 step 2 decisions (PROPOSED)
These came with the approved step 2 plan (`docs/milestones/m1-step2-plan.md`, section 20) or were made during the build. They are built and tested, but the owner has not approved them yet. None changes the approved M1 goal. Numbers live in `game/data/pool_m1.json` and the constants at the top of each file.

1. **Plane convention.** Plane point (x, y) is world (x, 0, y), so plane +y is world +Z, which is screen-down with the north-up camera. Heading 0 faces +X. Positive part angles are on the cell's right. `PlaneSpace` is the only mapping; the step 4 editor and mirroring must match it.
2. **Full-stomach rule.** A cell refuses food ("not hungry", shown as "Full") when it has room for less than half the food's energy (`InteractionResolver.FEED_MIN_ROOM_SHARE` 0.5; 0 turns it off). Reason: refusing only at full capacity still let a full cell eat about one item a second, strip zones and farm points.
3. **Survival points are live.** The step 1 rule (one point per 30 s alive, `Lineage.SURVIVAL_INTERVAL`) now pays in play. The timer restarts on respawn and on Continue. All points go through `Lineage.earn`.
4. **Interim carrion.** Until step 3, carrion also appears by itself: three pieces at fixed points at the start, then one every 10 ± 3 s inside a zone (picked at random, weighted by plankton capacity) while fewer than 12 are live. Each piece rots after 120 s. `CarrionField.spawn()` is the only way carrion enters the world; step 3 kills call `spawn(victim_pos, "kill", victim_energy)`. Step 3 sets `interim_supply.enabled` to false so carrion comes only from kills; keeping a trickle after step 3 needs owner approval. Reason for 120 s / 12 / 10 ± 3 s (the plan had 90 s / 6 / 9 ± 3 s): a hunter starving from the rim right after the first carrion rotted missed food in a third of runs; now the worst measured rate is 5%. Impact: about 11 pieces are live when nobody eats, above the readability guide of about 8. A "spread" placement is proposed in `docs/milestones/M1.md`, not built.
5. **Interim death handling.** On death, `Lineage.apply_death` takes a quarter of the unspent points and records the death; then the cell respawns at the layout spawn (the generation 1 start) with fresh energy and health. The world is kept. This applies the approved death rule at the only checkpoint step 2 has, until step 3 checkpoints. Quitting without saving after a death skips the penalty until step 4 autosave.
6. **Energy, health and heading are not saved.** Continue gives 60% energy and full health, faces the nearest zone and restarts the world from its seed; the HUD says the cell rested. The save schema stays v2. Saving them would be schema v3, decided in step 4.
7. **Dev tools only in a dev exe.** The debug panel, dev keys, gizmos, forage bot and perf tour live in `game/dev/` and load only when `OS.is_debug_build()` is true. The release export leaves out `game/dev/*`; CI also exports `Pangaea-dev.exe`. Reason: the Bible and the brief keep debug tools to development builds.
8. **Main scene is `game/scenes/main.tscn`.** The M0 checks still run from `game/scenes/boot.tscn` by path (`tools/check.sh` does this).
9. **Starving arrow.** While starving, an arrow points to the nearest food this body can eat. It is an assist for the forgiving preset, switched by `assists.starving_food_arrow` in the layout data.
10. **Camera.** Pitch 55 degrees, vertical field of view 45 degrees, distance 14 m, zoom 10 to 20 m in 2 m steps, yaw fixed north-up, no shake or roll. This follows the approved brief (about 55 degrees, following the cell).
11. **Pool floor is one vertex-coloured material.** `pool_floor` uses one material, `M_PoolFloor`, coloured per vertex so sand, silt and rim stone fade into each other. It replaces three materials assigned per face, whose silt patches had stair-step edges. The floor now reaches r 66 m (was 58), because the widest view from the wall reaches about r 64.9. Impact: one draw call for the floor. Godot's glTF import leaves the vertex colours out of the material, so `pool_floor.glb.import` points the material at `assets/export/M_PoolFloor.tres`. The colours are stored sRGB-encoded, so other glTF viewers show the floor lighter than the game does.

## Open decisions (from Bible section 26)
- Visual reference package and benchmark scene (M2).
- Minimum supported PC spec (below the owner's high-end baseline).
- Difficulty presets beyond M1's single forgiving preset.
- Final era names and boundaries (working names approved for now).
- Git LFS for large `.blend` sources.

## Open decisions (from M1 step 2)
- Interim carrion density: keep about 11 live pieces, or add the "spread" placement now.
- Whether energy and health are saved (schema v3), in step 4.
- A rule for eye spots above about scale 1.2, which reach into the sample cell's baked eyes, before the step 4 editor.
- A console wrapper for `Pangaea-dev.exe` (needs the console templates in the toolchain setup and CI).
