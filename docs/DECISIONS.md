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

## 2026-10-22 · Interim carrion cap raised to 15 (PROPOSED)
The interim carrion supply in `game/data/pool_m1.json` may keep 15 items live instead of 12. Arrivals (every 10 ± 3 s) and rotting (after 120 s) are unchanged. Reason: with a cap of 12, the three initial items and the arrivals fill the cap at about 90 s, the supply skips arrivals until the initial items rot at 120 s, and for minutes afterwards only 9.5 to 11 items are live. Carrion lands in zones in proportion to their capacity, so the rim between the two smallest outer zones, at about (-17, 31), gets the fewest drops. A hunter that started starving there late in a run died before reaching carrion in 7.5-11.5% of runs (125-300 s, seeds 1001-1200), against 3.5-5.3% for the rim as a whole. With 15, about 12 items stay live; over seeds 1001-1200 that point drops to 6.0%, 4.0% and 4.5% at 125, 200 and 300 s, and the whole rim to 2.4-3.0%. Arrivals still come slower than the cap allows, so items keep mixed ages and do not rot together. Impact: more carrion for hunters and omnivores while the interim supply lasts; step 3 still turns it off. The late-run case in `tests/test_pool_sim.gd` checks it. Approval: tuning value, owner review pending.

## 2026-10-22 · Spore files are not used (CONFIRMED)
The owner offered to buy Spore and extract its files for formats. Declined: we do not need EA's formats, and reading data out of their files would risk Pangaea being treated as derived from them. Playing the game for design notes written in our own words is fine.

## 2026-10-22 · Studio operating model (CONFIRMED)
The owner set how the studio works:
- The lead agent runs the project as a studio. Engineering, research and design, and art run as parallel threads.
- Every commit is pushed right away (`git push -u origin HEAD`).
- Research runs as a daily digest.
- Changes to the vision or the scope still need the owner's approval.

## 2026-10-22 · Minimum visual quality bar (CONFIRMED)
The Steam store page of Spore (2008) is the minimum visual quality bar. Pangaea must reach at least that polish, but it never copies Spore's designs: no creature, part or interface design. Impact: the M1 step 2 blockouts are below this bar; they stay blockouts until the step 5 art pass.

## 2026-10-22 · CC0 resources by default (CONFIRMED)
Art may use CC0 resources by default, from sources such as Poly Haven and ambientCG. Each one used is logged in the record of the asset that uses it. Reason: CC0 puts no terms on the game.

## 2026-10-22 · M1 step 2 decisions (PROPOSED)
These came with the final step 2 plan (`docs/milestones/m1-step2-plan.md`, section 20) or were made during the build. They are built and tested, but the owner has not approved them yet. None changes the approved M1 goal. Numbers live in `game/data/pool_m1.json` and the constants at the top of each file.

1. **Plane convention.** Plane point (x, y) is world (x, 0, y), so plane +y is world +Z, which is screen-down with the north-up camera. Heading 0 faces +X. Positive part angles are on the cell's right. `PlaneSpace` is the only mapping; the step 4 editor and mirroring must match it.
2. **Full-stomach rule.** A cell refuses food ("not hungry", shown as "Full") when it has room for less than half the food's energy (`InteractionResolver.FEED_MIN_ROOM_SHARE` 0.5; 0 turns it off). Reason: refusing only at full capacity still let a full cell eat about one item a second, strip zones and farm points.
3. **Survival points are live.** The step 1 rule (one point per 30 s alive, `Lineage.SURVIVAL_INTERVAL`) now pays in play. The timer restarts on respawn and on Continue. All points go through `Lineage.earn`.
4. **Interim carrion.** Until step 3, carrion also appears by itself: three pieces at fixed points at the start, then one every 10 ± 3 s inside a zone (picked at random, weighted by plankton capacity) while fewer than 15 are live (12 until the cap entry above). Each piece rots after 120 s. `CarrionField.spawn()` is the only way carrion enters the world; step 3 kills call `spawn(victim_pos, "kill", victim_energy)`. Step 3 sets `interim_supply.enabled` to false so carrion comes only from kills; keeping a trickle after step 3 needs owner approval. Reason for 120 s / 15 / 10 ± 3 s (the plan had 90 s / 6 / 9 ± 3 s): a hunter starving from the rim right after the first carrion rotted missed food in a third of runs. With a cap of 12 the worst rim point still starved 9 to 11.5% of runs, so the cap went to 15 (see "Interim carrion cap raised to 15"); the worst point is now 4 to 6%. Impact: about 12 pieces are live when nobody eats (peak 15), above the readability guide of about 8. This lasts only until step 3, which turns the interim supply off. A "spread" placement is proposed in `docs/milestones/M1.md`, not built.
5. **Interim death handling.** On death, `Lineage.apply_death` takes a quarter of the unspent points and records the death; then the cell respawns at the layout spawn (the generation 1 start) with fresh energy and health. The world is kept. This applies the approved death rule at the only checkpoint step 2 has, until step 3 checkpoints. Quitting without saving after a death skips the penalty until step 4 autosave.
6. **Energy, health and heading are not saved.** Continue gives 60% energy and full health, faces the nearest zone and restarts the world from its seed; the HUD says the cell rested. The save schema stays v2. Saving them would be schema v3, decided in step 4.
7. **Dev tools only in a dev exe.** The debug panel, dev keys, gizmos, forage bot and perf tour live in `game/dev/` and load only when `OS.is_debug_build()` is true. The release export leaves out `game/dev/*`; CI also exports `Pangaea-dev.exe`. Reason: the Bible and the brief keep debug tools to development builds.
8. **Main scene is `game/scenes/main.tscn`.** The M0 checks still run from `game/scenes/boot.tscn` by path (`tools/check.sh` does this).
9. **Starving arrow.** While starving, an arrow points to the nearest food this body can eat. It is an assist for the forgiving preset, switched by `assists.starving_food_arrow` in the layout data.
10. **Camera.** Pitch 55 degrees, vertical field of view 45 degrees, distance 14 m, zoom 10 to 20 m in 2 m steps, yaw fixed north-up, no shake or roll. This follows the approved brief (about 55 degrees, following the cell).
11. **Pool floor is one vertex-coloured material.** `pool_floor` uses one material, `M_PoolFloor`, coloured per vertex so sand, silt and rim stone fade into each other. It replaces three materials assigned per face, whose silt patches had stair-step edges. The floor now reaches r 66 m (was 58), because the widest view from the wall reaches about r 64.9. Impact: the floor is one mesh surface with one material. Godot's glTF import leaves the vertex colours out of the material, so `pool_floor.glb.import` points the material at `assets/export/M_PoolFloor.tres`. The colours are stored sRGB-encoded, so other glTF viewers show the floor lighter than the game does.

## 2026-10-22 · Rival species evolve by visible rules (CONFIRMED direction)
The owner chose option B on the research decision card: the player still designs their own creature, and between the player's generations rival species adapt under bounded rules that the journal shows. This is innovation backlog item IB-05 (`docs/research/innovation-backlog.md`). It is planned as an M3 spike with tests. The rules, rates and caps are PROPOSED tuning, and nothing is built yet. Offspring variants (option C) and a selection-led population (option D) were not chosen.

## 2026-10-22 · Runtime reshaping boundary for creature parts (CONFIRMED)
The owner chose option B on the research decision card. The editor may reshape creature parts in-game only through shape keys and bone scaling that are authored in Blender, and only within set limits. Every mesh still comes from a Blender source, and collision proxies are refit and tested at the extreme supported values. Runtime-generated body skins (option C) are not approved. This is the approved boundary that Bible section 12 requires for runtime deformation, and it is innovation backlog item IB-15. The limits per part are PROPOSED tuning data.

## 2026-10-22 · Art direction and quality ladder approved (CONFIRMED)
`docs/art/ART_DIRECTION.md` sets the look ("soft life hardens"; pebble, petal and bead shape language; palette; glTF-safe material families; scale classes; review lighting). `docs/art/quality_ladder.md` takes one cell through four rungs (blockout, form, surfaced, rigged target) as separate `cell_ladder_*` assets. The owner approved the look on 2026-10-22 after reviewing the ladder renders ("Incredible. I approve"), so production art may now follow it and replace gameplay placeholders. Palette values, budgets and material settings stay PROPOSED tuning, and each production asset still goes through the ladder and the M2 benchmark. The owner set the polish bar: at least Spore's Steam store page (match its polish, never its designs), with free CC0 resources (Poly Haven, ambientCG) used by default, finished in Blender and logged in asset records. Those hosts are blocked in the current cloud environment.

## 2026-10-22 · Pool lighting pass (PROPOSED)
The pool now reads as lit water: the floor turns teal and darker with depth, while the cell and the food on the swim plane keep their own colours and read first. All values are PROPOSED tuning; they live in `game/scenes/pool/pool_environment.tres`, the `Sun` node in `game/scenes/pool/pool.tscn`, `assets/export/M_PoolCaustics.tres` and `assets/export/M_PoolWater.tres`. Art direction rules applied (`docs/art/ART_DIRECTION.md` section 3):
- "Shadows go blue, never black." Ambient light is deep shadow `#1D3557` at energy 2.2 (was a pale blue at 0.3); it is all the light a shadow gets.
- "Pool teal `#2A7F86`: water tint, far habitat." It is the fog colour and the background: depth fog 0.006 per m (was 0.02, which also hazed the cell), height fog below y −0.25 at 0.5 per m, so the floor fades with depth and the swim plane stays clear.
- "Lit habitat surfaces" lean "shallow turquoise `#49B3A6`". A water pass multiplies the floor by exp(−absorb × depth) under a surface at y 0.8, absorb (0.95, 0.27, 0.14) per m: red goes first, so lit sand reads teal-turquoise and its shadows keep their contrast, which a fog mix would wash out. The rim lip and shelf stay dry.
- "Habitat colors stay below about 55% saturation." The lit floor's median is about `#3A9096` (was khaki `#8A8A76`), HSL saturation 0.44 (90th percentile 0.54); its CIELAB chroma, 26, matches pool teal's 25.
- "Living things and anything interactive are warmer and more saturated." Only the floor goes through the water. The key light is cream highlight `#F4EAD2` ("never pure white"), energy 1.3 (was 0.5), from the top left (pitch −55°, yaw −135°; was from the bottom right), so a cell gets a lit top-left, a blue underside and a shadow below-right that shows how high it swims.
- Food glow `#CFE86A` stays the only glowing yellow-green and threat `#D9466B` stays out of the habitat: neither is used in the light or the floor.
- Caustics: a procedural pass (`pool_caustics.gdshader`, no texture) in cream, strength 0.13, cells about 3 m, drifting slowly; the sun's shadows mask it and it fades with the fog. A first try at 0.28 competed with the plankton.
- Glow is off (was on, threshold 1.1, which nothing reached in Forward+). The Compatibility renderer stores a glowing frame at a quarter of its brightness, which turns the water pass almost black.
- The shadow's first split reaches 24 m (`directional_shadow_split_1` 0.6, was 0.1 = 4 m, where nothing is), so the cell's shadow stays smooth at every zoom.
- Budget: still one directional light with 2 splits to 40 m and no SSR, SSAO, SSIL, SDFGI or volumetric fog (`tests/test_pool_look.gd`). The floor is drawn three times (base, caustics, water), the plan's "3 materials". The caustic pass, two 3 × 3 cell lookups per floor pixel, is the only real cost; it is not yet measured on Windows hardware.

Evidence, Forward+ at 1920×1080 and gameplay zoom (CIE76 colour difference between each item's core and the floor ring around it, before → after): plankton 48 → 53 to 58; carrion 15 → 44 to 48; the starving cell 12 → 24. The fed cell's colour difference stays about 29 to 30 and its luminance contrast rises from 1.9 to 2.5. Mean frame luminance stays within 5% (grazer 126 → 122, hunter 129 → 123); shadows are lighter (darkest 3%: L* 26 → 35) and the cell and plankton brighter (L* 67 → 76 and 82 → 90). Renders: `screenshots/m1-step2-look/` in the project files.
Impact: the mint sample cell is now close in hue to the water and reads by value and by its shadow, most weakly over the pale shallows near the rim; the art direction's coral default membrane (`#E9744F`) would restore a hue difference. The rim lip's pale stone renders almost white in full sun. The Compatibility renderer (cloud screenshots, and machines without Vulkan) adds a shadowed light to the rest in sRGB, so its frames come out brighter, cyan and with near-white rocks and plankton; the look was judged in Forward+ (`docs/TOOLCHAIN.md` has the recipe for Forward+ renders in the container).

## Open decisions (from Bible section 26)
- Visual reference package and benchmark scene (M2).
- Minimum supported PC spec (below the owner's high-end baseline).
- Difficulty presets beyond M1's single forgiving preset.
- Final era names and boundaries (working names approved for now).
- Git LFS for large `.blend` sources.

## Open decisions (from M1 step 2)
- Interim carrion density: about 12 live pieces (peak 15) until step 3 turns the interim supply off. Keep that, or add the "spread" placement now.
- Whether energy and health are saved (schema v3), in step 4.
- A rule for eye spots above about scale 1.2, which reach into the sample cell's baked eyes, before the step 4 editor.
- A console wrapper for `Pangaea-dev.exe` (needs the console templates in the toolchain setup and CI).
