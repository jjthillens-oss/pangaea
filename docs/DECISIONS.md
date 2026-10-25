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
`docs/art/ART_DIRECTION.md` sets the look ("soft life hardens"; pebble, petal and bead shape language; palette; glTF-safe material families; scale classes; review lighting). `docs/art/quality_ladder.md` takes one cell through four rungs (blockout, form, surfaced, rigged target) as separate `cell_ladder_*` assets. The owner approved the look on 2026-10-22 after reviewing the ladder renders ("Incredible. I approve"), so production art may now follow it and replace gameplay placeholders. Palette values, budgets and material settings stay PROPOSED tuning, and each production asset still goes through the ladder and the M2 benchmark. The owner set the polish bar: at least Spore's Steam store page (match its polish, never its designs), with free CC0 resources (Poly Haven, ambientCG) used by default, finished in Blender and logged in asset records. Those hosts are blocked in the current cloud environment (reachable again from 2026-10-22 09:15).

## 2026-10-22 · Triangle reduction for every production asset (CONFIRMED)
The owner asked that once a model looks right, its triangles are cut as far as possible without losing quality. Production generators decimate each mesh while its surface stays within a set distance of the full-detail model (about one screen pixel where the asset is seen most closely) and bake the full-detail shading into the normal map. Records list the tolerance and the counts before and after. The tolerances are PROPOSED tuning (`tools/blender/make_m1_production.py`).

## 2026-10-22 · CC0 scans as detail sources (PROPOSED)
CC0 photo scans (Poly Haven, ambientCG) may feed surface detail (grain, height, value variation) through a procedural shader that recolours them to the palette, and the result is baked; a scan is never shown raw. Each scan is kept in `assets/source/textures/cc0/` and listed with its URL, authors and license in the asset record. This narrows the art direction's earlier "no photo textures" line to fit the owner's CC0 rule.

## 2026-10-22 · The cell stage reads as a microscopic world (CONFIRMED)
The owner asked that the cell stage look like a microscopic world ("like a cell reproduction stage"), not just underwater. That means tiny cells, spores and bacteria swimming around, with other microorganisms to encounter. He shared Spore cell-stage screenshots for mood, scale and density only; no designs are copied. He approved the mood frame `docs/art/renders/concept/micro_mood_pool.jpg` (from `tools/blender/render_micro_mood.py`) on 2026-10-22 at 22:01 ("yes", "i look the new look way better").

The approved look is a deep-blue fluid in place of the approved pool teal. Its depth layers are:
- huge, out-of-focus organisms far below the swim plane;
- glassy radiolarian and diatom shells in place of the rocks;
- bubbles and specks drifting between the swim plane and the camera;
- muted swarms of bacteria, spirilla and spores.

Decor never uses the food green (`#CFE86A` family) or the threat pink (`#D9466B`), and never looks solid on the swim plane. The work is split as in `/mnt/project-files/pangaea/docs/ambience-handoff.md`. Art builds the decorative ambience scene and the shell swap, which are presentation only. Engineering owns the camera, floor depth, fog and lighting, and any microbe that affects play. Colours, depths and densities stay PROPOSED tuning. Microbes that compete for food or can be eaten are a separate owner decision.

## 2026-10-22 · M1 step 3 decisions (PROPOSED)
These came with the final step 3 plan (`docs/milestones/m1-step3-plan.md`, section 23) and were built in step 3. They are built and tested, but the owner has not approved them yet. None changes the approved M1 goal; the three that could are the owner decisions below. Numbers live in `game/data/creatures_m1.json`, `game/data/pool_m1.json` and the constants at the top of each file. Where the build differs from the plan, `docs/milestones/M1.md` (step 3, "As built") says how and why.

1. **D1 Interim carrion off.** `carrion.interim_supply.enabled` is false in `pool_m1.json`, so carrion comes from kills plus the three world-start pieces. The block stays, so turning a trickle back on (OD2) is a data change. This is what step 2's decision 4 said step 3 would do.
2. **D2 Hunter viability is a slow CI gate.** `tests/test_threat_gates.gd` (`test_slow_a_hunter_lineage_lives_on_its_kills_in_five_of_six_seeds`): HuntBot drives a hunter for 240 s on seeds 201 to 206, fixed before any run. A seed passes with no starvation death, at most one death to a threat and at least 3 pieces of carrion eaten; at least 5 of 6 must pass. If it fails, five data knobs are tuned in order within their bounds (rammer respawn 30 → ≥ 15 s, rammer chunks 3 → ≤ 4, ambush chunks 4 → ≤ 5, carrion lifetime 120 → ≤ 240 s, rammer flee share 0.4 → ≥ 0.25), never the gate. The shipped data passes 6 of 6 with no tuning, so OD2 was not raised.
3. **D3 One body size rule.** `Phenotype.derive(genome, catalog, body_size = 1.0)` scales part benefits and costs, spike damage, base mass, upkeep, health and radius by the size (0.5 to 2.0); base speed, acceleration, turn, sight and energy capacity are not scaled, so bigger is tougher, hungrier, harder-hitting and slower. Size 1 gives exactly the step 2 result. The ambush hunter is the hunter body at size 1.5; the rammer is a filter mouth, four spikes at scale 0.8 and a flagellum at size 1.25. The player is always size 1 in M1.
4. **D4 Creature metabolism.** Creatures use `ActorState` unchanged at a share of the player's rates: ambush hunters 10%, rammers 25% (upkeep, movement cost, starvation damage and regeneration together). A creature that starves leaves no carcass.
5. **D5 Combat on contact.** A jaw bites and spikes ram automatically whenever `InteractionResolver` allows it; there is no attack key, and Space and the right mouse button stay unbound. This is owner decision OD3.
6. **D6 Tells are locked lines.** A creature starts its tell nearly still (at most 0.3 m/s), locks its heading at the target's position plus its velocity × the lead time (capped at 1.0 m for the lunge, 1.2 m for the charge), and strikes along that line as a burst then a glide, with no homing. Both tells last 1.2 s (72 ticks), and the data refuses anything shorter. A cell that swims out of the line on the side it faces 0.4 s after the tell starts is not hit (worded by the review fixes: fair, below); the hard case is swimming head-on into a strike while starving, which the notice cue, the floor lane and the tip cover.
7. **D7 Forgiving two-hit rule.** No single hit may reach half of the smallest starting body's health (15 of 30), checked at load: the ambush bite deals 12 and a full charge 14.4.
8. **D8 The checkpoint is the generation start.** `PoolSim.checkpoint()` derives it from the layout spawn (generation 1 is the only generation until step 4). Nothing new is saved: the save schema stays v2 with its 15 keys. Step 4 adds the per-generation spawning spot and changes only `checkpoint()`.
9. **D9 Fairness numbers.** Creatures spawn at least 20 m from the cell and outside the camera's view at full zoom-out on a 2.4:1 screen (with the 2.5 m look-ahead, 1 m and the body radius as margin). No creature's reach comes within 12 m of the checkpoint. Shelter after a death is 5, 8 or 10 s and respawn energy 60, 80 or 100% for the first, second and third quick death in a row (each within 90 s of the last respawn). The killer ignores the cell for 30 s. A new lineage and Continue start with 5 s of shelter.
10. **D10 Where the threats live.** Rammers guard the rich north zones (two in z_n, one each in z_nw and z_ne). Ambush hunters wait at the south-east rim (26.4, 12.6), the south-west rim (−24.1, 16.6) and the north-west rock gap (−9.4, −16.3), moved from the first sites so no rock pinches a leash. z_center, z_s, z_se and z_sw are unguarded, and the spawn is beyond every leash. (After the step 3 review the north-west hunter moved to the south rim as lair_s, (5.0, 31.0), watching z_s; see "M1 step 3 review fixes: pressure".)
11. **D11 AI rates and senses.** Brains decide at 10 Hz, staggered by creature number, and at 20 Hz while engaged; every timed phase advances on its exact tick, and between decisions a creature acts on what it last sensed. Senses are sight (a field of view up to 6 m, blocked by rocks), touch, pain and a memory of 2 or 3 s. There is no level-of-detail scheduling in M1.
12. **D12 The player's death leaves no carrion.** No corpse runs, and a dead cell never feeds an ambush hunter.
13. **D13 Body separation is positional.** Overlapping bodies are pushed apart along the line between their centres, split by inverse mass; velocities are not changed, so a ram's closing speed comes from real swimming.
14. **D14 Knockback.** A landed hit pushes the target (ambush bite 1.5 m/s, rammer charge 2.5, the player's bite 0.8 and ram 1.5, from the data), and both bodies' speed is then capped at 6 m/s, the tunnelling bound.
15. **D15 Species have their own data file.** `game/data/creatures_m1.json` holds species, niches, sites, AI, combat and fairness numbers; `pool_m1.json` keeps layout schema 1.
16. **D16 Creatures, streaks and shelter are not saved.** Continue repopulates the sites from the world seed and gives 5 s of shelter.
17. **D17 Dev spawns and stuck creatures.** Creatures placed by dev tools bypass the niche caps, are not counted and never respawn. A creature that fails to get home three times is marked stuck, and is removed and requeued at its site only while the cell is at least 20 m away and cannot see it.
18. **D18 Death causes in the history.** `"starved"` or `"killed:<species id>"` (for example `killed:ambush_hunter`); a dev kill of the cell records plain `"killed"`.
19. **D19 World-start carrion moved.** The two pieces that lay inside the z_nw and z_ne territories moved from (−14, −6) and (12, −14) to (−10.5, −4.5) and (10.5, −4.5); (1.5, 4) stays. This changes step 2 data; the step 2 acceptance row says so.
20. **D20 Escape and leash rules.** Pursuit is at most 0.9 × the slowest fed starting body (the omnivore's 2.72 m/s, so 2.448 m/s), checked at load: ambush hunters pursue at 2.34 m/s, rammers at 1.84. After every move the sim clamps each creature to its leash disc, and no tell starts whose strike would leave it. Load-time rules keep every reachable disc 12 m from the checkpoint, keep rocks off every leash circle and leave room to pass every rock inside a disc.
21. **D21 One creature at a time.** At most one creature chases or attacks the cell (`max_engaged_on_player` 1, the forgiving preset); the others watch or wait until their give-up timers end it.
22. **D22 Body-only blockouts.** `tools/blender/make_m1_threats.py` builds the ambush and rammer bodies without parts; the view places the species' part GLBs at runtime through `PartPlacement`, so tuning `parts` or `body_size` never needs a Blender run. There are no composite species GLBs. Body vertex colours reach Godot through external materials (`M_AmbushBody.tres`, `M_RammerBody.tres`) mapped in each `.glb.import`, the same pattern as the pool floor, because Godot's glTF import ignores `COLOR_0`; a regeneration that rewrites the `.import` file must keep that mapping.

## 2026-10-22 · M1 step 3 owner decisions (OD1 CONFIRMED; OD3 open; the recommended option of each is built)
Each changes what the approved brief says, or could. The build ships with the recommended option, and the other is one constant or one data change, already wired and tested.

- **OD1. Save the death at once.** CONFIRMED by the owner on 2026-10-22: option A. (A, built) `GameSession.SAVE_ON_DEATH = true`: when the cell dies the game writes the slot (the same temp, verify and backup path) with the death applied and the cell at its checkpoint, so quitting at the death notice cannot skip the death. That is a write trigger beyond the brief's "autosave on each generation". (B) `SAVE_ON_DEATH = false`: step 2's rule, nothing is written until the player saves, and quitting without saving discards the death. Both paths are tested in `tests/test_checkpoints.gd`.
- **OD2. Hunter fallback, only if the viability gate fails after tuning.** Not raised: the gate passes 6 of 6 seeds with the shipped data and no tuning. If a later change fails it after the five knobs reach their bounds, the owner chooses: (A, recommended) a slow interim carrion trickle again (`interim_supply.enabled` true, every 30 ± 5 s, at most 4 live, in zones; data only), or (B) accept that hunter lineages are harder in M1, turn the gate into a printed report, and add "Hunters must hunt to eat." to the hunter's start card.
- **OD3. Combat on contact, with no attack key.** (A, recommended and built) Keep it: it uses the step 1 resolver unchanged, and step 4's editor makes part placement the skill. (B) Add an attack key in step 4 through the same resolver path. Recorded as D5.

## 2026-10-22 · Pool lighting pass (PROPOSED)
The pool now reads as lit water: the floor turns teal and darker with depth, while the cell and the food on the swim plane keep their own colours and read first. All values are PROPOSED tuning; they live in `game/scenes/pool/pool_environment.tres`, the `Sun` node in `game/scenes/pool/pool.tscn`, `assets/export/M_PoolCaustics.tres` and `assets/export/M_PoolWater.tres`. Art direction rules applied (`docs/art/ART_DIRECTION.md` section 3):
- "Shadows go blue, never black." Ambient light is deep shadow `#1D3557` at energy 2.2 (was a pale blue at 0.3); it is all the light a shadow gets.
- "Pool teal `#2A7F86`: water tint, far habitat." It is the fog colour and the background: depth fog 0.006 per m (was 0.02, which also hazed the cell), height fog below y −0.25 at 0.5 per m, so the floor fades with depth and the swim plane stays clear.
- "Lit habitat surfaces" lean "shallow turquoise `#49B3A6`". A water pass multiplies the floor by exp(−absorb × depth) under a surface at y 0.8, absorb (0.95, 0.27, 0.14) per m: red goes first, so lit sand reads teal-turquoise and its shadows keep their contrast, which a fog mix would wash out. The rim lip and shelf stay dry: the caustics fade out over the last 0.2 m of floor below the surface, and the lip is weathered grey stone, linear `(0.36, 0.35, 0.33)`, darker than the sand (it was pale `(0.70, 0.68, 0.62)`, which rendered at L* 92 to 95 in full sun, the brightest thing on screen and lighter than the plankton's glow at L* 87; it now renders at L* 78). `tests/test_pool_look.gd` keeps the lip's vertex luminance at 0.40 or less (PROPOSED).
- "Habitat colors stay below about 55% saturation." The lit floor's median is about `#3A9096` (was khaki `#8A8A76`), HSL saturation 0.44 (90th percentile 0.54); its CIELAB chroma, 26, matches pool teal's 25.
- "Living things and anything interactive are warmer and more saturated." Only the floor goes through the water. The key light is cream highlight `#F4EAD2` ("never pure white"), energy 1.3 (was 0.5), from the top left (pitch −55°, yaw −135°; was from the bottom right), so a cell gets a lit top-left, a blue underside and a shadow below-right that shows how high it swims.
- Food glow `#CFE86A` stays the only glowing yellow-green and threat `#D9466B` stays out of the habitat: neither is used in the light or the floor.
- Caustics: a procedural pass (`pool_caustics.gdshader`, no texture) in cream, strength 0.13, cells about 3 m, drifting slowly; the sun's shadows mask it and it fades with the fog. A first try at 0.28 competed with the plankton.
- Glow is off (was on, threshold 1.1, which nothing reached in Forward+). The Compatibility renderer stores a glowing frame at a quarter of its brightness, which turns the water pass almost black.
- The shadow's first split reaches 24 m (`directional_shadow_split_1` 0.6, was 0.1 = 4 m, where nothing is), so the cell's shadow stays smooth at every zoom.
- Budget: still one directional light with 2 splits to 40 m and no SSR, SSAO, SSIL, SDFGI or volumetric fog (`tests/test_pool_look.gd`). The floor is drawn three times (base, caustics, water), the plan's "3 materials". The caustic pass, two 3 × 3 cell lookups per floor pixel, is the only real cost; it is not yet measured on Windows hardware.

Evidence, Forward+ at 1920×1080 and gameplay zoom (CIE76 colour difference between each item's core and the floor ring around it, before → after): plankton 48 → 53 to 58; carrion 15 → 44 to 48; the starving cell 12 → 24. The fed cell's colour difference stays about 29 to 30 and its luminance contrast rises from 1.9 to 2.5. Mean frame luminance stays within 5% (grazer 126 → 122, hunter 129 → 123); shadows are lighter (darkest 3%: L* 26 → 35) and the cell and plankton brighter (L* 67 → 76 and 82 → 90). Renders: `screenshots/m1-step2-look/` in the project files.
Compatibility renderer: the values above are tuned for Forward+, the Windows build's renderer. Compatibility (OpenGL: cloud screenshots, and PCs that fall back from Vulkan) tonemaps each pass on its own and adds the shadowed sun to the rest in sRGB, so with the same values its lit floor turned swimming-pool cyan (`#16A9D2`, saturation 0.81) and plankton, rocks and the rim clipped to white. `game/scenes/pool/pool_look.gd` now gives it its own values when `RenderingServer.get_current_rendering_method()` is `gl_compatibility` (Forward+ and Mobile keep the authored ones), on copies of the pool's environment and floor passes, so the shared `.tres` files keep the Forward+ values. The values (PROPOSED, with the reason for each in that file): sun 1.5 (0.9 after exposure, Forward+ 1.3: brighter clips the plankton's sunlit tops to white), exposure 0.6 with white point 2, ambient 3.0, distance fog 0.0015 per m, height fog 1.25 per m, caustics 2.0 with a soft ceiling of 0.2 (`max_light`, a new caustic uniform that is off in Forward+, so the brightest lines in the shallows cannot clip), water absorb (0.31, 0.077, 0.012) per m.

Evidence, both renderers at 1920×1080 and gameplay zoom, four shots (grazer, hunter, starving, rim; renders in `screenshots/m1-step2-look/`): the two renderers' floor medians are 6.2 to 7.5 CIE76 apart (grazer: Compatibility `#2F7C80`, Forward+ `#398F96`); floor saturation is at most 0.46 in both; plankton cores stay yellow-green (hue 110 to 119 in Compatibility, 115 to 123 in Forward+); the 97th-percentile L* is at most 72 in Compatibility and 81 in Forward+ (the rim shot was 94 in Forward+ and 100 in Compatibility). Near-white plankton pixels (L* 92 or more, chroma under 15) are 10 to 15% in Compatibility (27 to 36% with the Forward+ values, under 1% in Forward+). Against the `m1-swim-eat` shots in the same renderer, the luminance contrast of the cell, plankton and carrion against the floor is higher in every shot, and so is their colour difference, except the cell's at the rim (Compatibility 27 → 21, Forward+ 27 → 10) and the fed cell's in Forward+ (30 to 31 → 28).
Impact: the mint sample cell is now close in hue to the water and reads by value and by its shadow, most weakly over the shallows near the rim; the art direction's coral default membrane (`#E9744F`) would restore a hue difference. Compatibility frames stay a little darker and greener than Forward+, with paler plankton tops and stronger caustics in the shallows by the rim, so the look is still judged in Forward+ (`docs/TOOLCHAIN.md` has the recipe for Forward+ renders in the container).

## Open decisions (from Bible section 26)
- Visual reference package and benchmark scene (M2).
- Minimum supported PC spec (below the owner's high-end baseline).
- Difficulty presets beyond M1's single forgiving preset.
- Final era names and boundaries (working names approved for now).
- Git LFS for large `.blend` sources.

## Open decisions (from M1 step 2)
- ~~Interim carrion density: about 12 live pieces (peak 15) until step 3 turns the interim supply off.~~ Settled by step 3, which turned the interim supply off (D1).
- Whether energy and health are saved (schema v3), in step 4.
- A rule for eye spots above about scale 1.2, which reach into the sample cell's baked eyes, before the step 4 editor.
- A console wrapper for `Pangaea-dev.exe` (needs the console templates in the toolchain setup and CI).

## 2026-10-23 · Generated creature skins, Spore-style full-body building (CONFIRMED direction)
The owner changed the runtime reshaping boundary (entry of 2026-10-22, IB-15 option B) to option C: the creature
editor generates the body skin at runtime around a player-built spine and limbs, so players can build a whole
creature freely, as in Spore. In his words (2026-10-23): "It should be generated skins. They should be able to build
their full creature just like Spore." He also set the research priority: procedural creature geometry, automatic
rigging and anatomy-driven animation come before any study of later stages. Impact:
- Supersedes the "runtime-generated body skins not approved" part of the IB-15 entry. Detail parts (mouths, eyes,
  hands, feet, fins and so on) stay Blender-authored with records; the torso and limb skin, skeleton and skin
  weights are generated by GENESIS code. Bible §12 asks for an approved boundary for runtime deformation; this entry
  is that approval, and the boundary details (limits, budgets, tests) are PROPOSED in
  `docs/research/spore/CREATURE_GEOMETRY_SPEC.md`.
- `tests/test_placeholders.gd` treats meshes built in code inside `game/` as placeholders. When the generator moves
  into `game/`, that test needs a rule for generated production meshes; that change is part of the build, not done yet.
- Scope of "like Spore": in a follow-up message the same day the owner set the objective as "to independently build
  an original, technically comparable creature-generation system in Godot 4 using Blender for production assets",
  from public research and gameplay measurement, with no unauthorized binary analysis or DRM circumvention. So
  GENESIS matches Spore's functions and feel (free-form building, generated skin, automatic rigging, procedural
  animation) with its own code and designs. Spore's part shapes, art, animation data, UI and code are not copied
  (2026-10-22 entries "Spore files are not used" and "Minimum visual quality bar" stand).
- Existing GENESIS systems are not modified yet. A first isolated prototype starts only after the owner approves it.
- The owner bought Spore on Steam and lives in the United States; `docs/research/spore/LEGAL_RESEARCH_BOUNDARIES.md`
  applies US law. Binary analysis of Spore stays off the plan.
Approval: owner, project thread "Spore research protocol", 2026-10-23.

## Open decisions (from M1 step 3)
- OD3 (combat on contact): the owner's answer only adds a key in step 4; the recommended option is built. OD1 (save the death at once) is CONFIRMED as built.
- OD2 (hunter fallback) is raised only if the hunter viability gate fails after data tuning; it passes now.
- Threat pressure: sated ambush hunters mostly watch, and HuntBot's hunter took no hits in 240 s on any gate seed. How much pressure the threats bring is for the owner's play test (never shorter tells). For a cell by the spawn the levers are z_center's and z_s's regrowth and lair_s's place ("M1 step 3 review fixes: pressure", below); hunger, metabolism, `start_max_m` and `max_engaged_on_player` act only where a creature already reaches. The ambush hunters' `metabolism_share` (0.1), `start_energy_share` (0.9) and `hungry_below` (0.6) also set how long lair_s's hunter lasts with no prey (about 12.5 to 13 minutes) and, with no prey, when it starts to chase (about 4 minutes after it spawns). The rim zones z_se and z_sw share z_s's F6 hole: every point of each is within 20 m of its lair's home, so lair_se and lair_sw never spawn while the cell stays there. After a Continue in either zone, a greedy camper at 60% met nothing in 600 s in 8 of 8 runs (seeds 1 and 2, both bodies) and never ran dry, since those zones top out at 1.92 and 1.73 energy a second. The levers there are those zones' regrowth or an F6 or D16 rule; this was already true before the review and is left to the owner's play test.

## 2026-10-22 · M1 step 3 review fixes: ai (PROPOSED)
Fixes to the creature AI and its tests after the step 3 review. Built and tested, not yet approved by the owner. No data file changes; the numbers below are constants in the code or the tests.

1. **The token is decided at each think (D21, F4).** Before every think, CreatureField sets the player's `engageable` flag on the brain's remembered entry as well as on a fresh percept, so a brain that last saw the cell while the token was free no longer chases on that old flag after another creature took it. The review's race (two hungry hunters 10 m apart, the cell swimming east between them at 0.6 throttle) put two creatures on the token at tick 35; it now never has more than one, and no second creature even enters a chase. The cleaner variant (the token as a think input) was not taken: it would change the senses' percept format that the brain tests build on, for the same result.
2. **The token list has a hard cap.** `CreatureField.update_token(c, tick)` never grows `engaged_on_player` past `max_engaged_on_player` (1). A brain that engaged while the token was full is refused: it forgets the player (`CreatureBrain.forget`, no ignore time), so it drops the chase or calls off its tell, and the refusal is logged with `push_error`. The log line is not limited to debug builds, because sim code may not read `OS` (`test_sim_purity`); in a release build it only reaches the log file. With decision 1 in place it fires only in its own unit test (`test_creature_field`, which forces a second engagement on purpose), never in the sim tests, the fuzz or the gates.
3. **A sated ambush hunter swims home before noticing prey.** In `wander/return`, an ambush hunter that is not hungry skips prey it would not chase (anything but its attacker or prey it has bitten) until it is home (0.3 m), then notices it once and watches. Before, a sated hunter pushed more than 1 m off its home (a missed lunge, a shove) looped notice, watch, return about every 0.7 s (a "!" and a chirp each time) for as long as the prey stayed in view: 22 notices in 15 s in the brain test, which now gets home with at most one. A side effect: the hunter viability gate went from 6 of 6 seeds to 5 of 6 (5 needed). In seed 202 the lair hunter no longer re-notices the cell right after its missed lunge, which moved the cell's next kill and its carcass by 0.03 m; HuntBot then starved waiting beside a piece it could not turn its mouth onto. That is the bot's weakness, so no data was tuned; making HuntBot back off and re-approach such a piece is left to whoever owns it. On the merged branch, with the pressure fix's lair_s move, the gate passes 6 of 6 again (6 or 7 kills, 0 hits taken); the bot's weakness is noted in M1.md's known issues.
4. **A rammer lets an intruder go rather than puff at it past its territory exit.** Where it would start a tell at a target seen beyond `territory_r + territory_exit_m` (9 m from the zone's center), it gives up (`left_territory`, refractory 3 s) instead: that puff would be cancelled on the next think, 3 ticks later, after its lane, hiss and "!" had already shown. The chase and the leash still reach 11 m, and puffs inside 9 m are unchanged. The plan's rammer `chase/aim` row says so.
5. **How far a strike may start from its tell's lane.** The view draws the lane where the tell started; a body leaning on the creature through its tell can still move it. The threat fuzz allows a strike to start up to 0.5 m from its lane's origin (the four seeds' worst is 0.446 m: the z_n rammer c_4 pushed by its neighbour c_5 through a puff, seed 402; the rest are under 0.03 m), and a hit on the cell must lie in the lane grown only by that strike's own drift. The heading is exact (1e-6 rad). Re-anchoring the drawn lane on a pushed body is left to the view.
6. **Fuzz invariant 9 checks every tick.** Any change to a brain's memory of the cell, on any tick and in any state, must be what `CreatureSenses` gives from where the creature looked before the step (same sense, position and velocity) or the pain of the cell's hit on that tick; the token's flag is left out of the comparison. At least 2000 such changes must be checked over the four seeds (3333 today).

## 2026-10-22 · M1 step 3 review fixes: fair (PROPOSED)
An independent review of step 3 found that the dodge promise did not say which side, and that a hunter's starving tip sent it to plankton. Both are fixed in words and tests; no physics or tuning number changed, and no state hash moved.

1. **F2 and D6 promise the side the cell faces.** F2 said that swimming "sideways, out of the line" 0.4 s after the tell starts avoids the strike, and both death tips said "swim sideways". The S5 grid only ever dodged on the side with the shorter turn (`EvadeBot.side`). The other side needs a turn of 90 to 180 degrees, and a cell turns first and swims after (`Locomotion.steer`: 2.5 rad/s, thrust `max(0, cos(error))²`, none past 90 degrees), so a full turn round (about 1.26 s) takes longer than the 1.2 s tell. Both reviewers advised keeping the physics: a faster turn or a back-swim is a step 2 locomotion change with its own retuning, and doubling the turn rate past 90 degrees still left the turn-round case hit. So the promise now reads: a 0.4 s reaction, swimming out of the line on the side you are facing (a turn of at most 90 degrees), avoids the strike. The other side is not promised, and F2 and D6 say what was measured on it. (A first rewording promised "turning less than about 120 degrees". The check of these fixes found that it held only on the S5 grid's 30-degree headings: facing the creature, a fed cell dodging to the side behind it is hit from a 98 degree turn. So the gates below sample every 5 degrees where that turn is under 120.) Measured with `EvadeBot.far_side` (24-tick reaction, distances × headings × still or grazing at 30% × fed or starving × 3 bodies) on the S5 headings first:

   | Hits of 36 per cell | Lunge: still fed | still starving | grazing fed | grazing starving | Charge: still fed | still starving | grazing fed | grazing starving |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   | Grazer | 20 | 26 | 6 | 16 | 6 | 10 | 0 | 2 |
   | Hunter | 20 | 24 | 10 | 14 | 6 | 8 | 0 | 2 |
   | Omnivore | 20 | 28 | 8 | 21 | 6 | 14 | 0 | 2 |

   - On the S5 headings the side behind is hit in 213 of 432 lunge runs and 56 of 432 charge runs. On the side the cell faces, the same lunge grid is hit once (the budgeted starving omnivore grazing head-on) and the charge grid never.
   - Lunge hits by heading (0 faces away from the creature, then every 30 degrees): 0, 3, 16, 26, 35, 26, 1, 26, 35, 26, 16, 3; charge: 0, 0, 3, 13, 10, 2, 0, 2, 10, 13, 3, 0.
   - Every 5 degrees where the turn to the side behind is under 120 degrees (headings 335 to 25, facing away from the creature, and 155 to 205, facing it), added to the S5 headings: 1,152 runs per species, of which the lunge hits 329 and the charge 60 (`test_slow_a_dodge_on_the_side_behind_the_cell_is_hit_only_past_120_degrees_of_turn_outside_head_on`).
     - Facing away, no dodge that turns less than 120 degrees is hit (396 such runs per species). Exactly 120 is the edge: a still starving cell facing 30 or 330 degrees is hit by the lunge.
     - Facing the creature (the head-on sector, 150 to 210 degrees), the lunge hits a fed cell from a 98.3 degree turn (the hunter grazing at 175 or 185 degrees) and a starving one from about 96 (and at 90 exactly head-on, where both sides are the same turn). The charge hits only starving cells there, from 110 degrees. Hits of 36 per heading from 150 to 210 degrees, lunge: 26, 23, 14, 11, 7, 3, 1, 3, 7, 11, 14, 23, 26; charge: 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2.
   - The side the cell faces, every 5 degrees from 150 to 210 (468 runs per species; `test_slow_a_dodge_on_the_side_the_cell_faces_holds_every_5_degrees_through_the_head_on_sector`): the lunge hits once, the same starving omnivore at 180 degrees, and the charge never. The checker's probe ran this side every 5 degrees round the whole circle and found only that hit.
   - The slow tests gate all of it. On the side the cell faces: no fed hit, and at most one starving hit per cell, through the head-on sector. On the side behind: no hit under 120 degrees outside the head-on sector, a fed lunge hit under 105 degrees inside it, and a still cell turning round hit. A change that makes the other side safer fails one of the last two and says F2, D6 and the tips can promise more. The S5 tests in the fast suite keep checking that every dodge on the promised side turns at most 90 degrees. The two slow tests run 3,240 strikes, about a minute of CPU here; the fast suite no longer runs the 864 other-side strikes of the first version (`test_threats_sim` with `--skip-slow` takes 63 s of CPU, down from 79).
   - The tips now read "Ambush hunters wait at the rims. When one coils, swim out of its line on the side you face; turning round takes too long." and "Rammers guard the richest patches. When one puffs up, swim out of its line on the side you face, or leave its patch." "Out of its line" stays in, because a cell facing about 30 degrees off the lane would otherwise read the tip as straight ahead, which is close to swimming straight away (hit 5 to 9 times per body, plan section 0).
   - Not built: a safe-side cue on the floor lane (a scene change, offered by a reviewer), and a back-swim or quicker reversal. Whether dodging feels fair is an owner play-test question (M1.md).
2. **The starving tip names only food the body can eat.** Plan section 15 gave one starving tip, "Plankton regrows in the sunlit patches; slow down when energy runs low.", for every body, and a hunter's jaw cannot eat plankton. `GameSession.starved_tip(phenotype)` keeps that line for a body that eats plankton (grazer, omnivore), gives one that eats only carrion (the hunter) "More carrion comes only from kills: bite a rammer from behind, jaw first, and keep biting until it dies, then eat what it drops. Slow down when energy runs low.", and a body with no mouth, or none given, "Slow down when energy runs low." It is worded as the tests hunt (threats_sim #9 and #22 and HuntBot bite a rammer from behind and keep biting: five bites of 8 kill its 37.5 health) and names no other prey, since an ambush hunter may be too big to bite. It says "More carrion" because the three world-start pieces rot only at 120 s and a hunter left idle starves sooner, so they may still lie in the pool when the tip shows (the first wording, "Carrion comes only from kills: swim into a rammer from behind, jaw first, then eat what it drops.", claimed otherwise and read as one bite). `resolve_death` and `Main.death_text`'s fallback both use it.
3. **A hunter is told it must hunt before it starves.** The hunter card reads "Two tails for speed and a jaw for carrion. Hunters must hunt to eat." (OD2-B's sentence; "that tears carrion" became "for carrion" so the role keeps to the card's three lines), and its first-meal hint reads "Eat by touching carrion (still brown chunks) with your jaw; more comes only from kills." ("more": the hint shows at the start, beside the world-start pieces.) Both fit their panels at 1920 × 1080, which the 1280 × 720 window shows scaled: the role is 3 lines in its 116 px, the hint 3 lines (114 px, as the grazer's and omnivore's), and the hunter's starving notice 424 px tall (463 px if the save fails) (`test_ui_text`; the same heights were read from the laid-out screens).
4. **Unchanged on purpose.** The carrion supply stays off (D1; OD2 is not raised). The starving arrow still points only at food: pointing it at a rammer patch when no carrion exists, as one reviewer suggested, would steer a slow, weak cell into a threat and blur food and danger.

## 2026-10-22 · M1 step 3 review fixes: visual (PROPOSED)
Fixes from the independent review of step 3's threat visuals. Every number here is PROPOSED view tuning; none changes the sim or a state hash.
- **The lane's outline goes above the quarter-alpha cap.** `threat_lane.gdshader` keeps `MAX_ALPHA` 0.25 for the inside (base 0.06, fill 0.14, chevrons 0.11, so the floor shows through the strip) and draws only the thin outline (the 0.14 m dark spike-tip crimson border and the 0.06 m threat-colour line inside it, about 0.2 m of a strip 1.5 to 3 m wide) at `LINE_ALPHA` 0.7. At 0.25 no red survives over the lit teal floor of the step 3 lighting: the frame read as a grey selection box. This changes plan section 14's "alpha ≤ 0.25" for the outline only and needs the owner's approval. `tests/test_pool_view.gd` keeps the inside under 0.25, the outline at most 0.75 and at most 0.25 m wide. Measured as the mean of the outline pixels the change alters, 1.0 s into a tell at zoom 14 (grazer, seed 4242), with "pink" meaning hue 300 to 10 and saturation over 0.15: the ambush hunter at lair_se in Compatibility, before `#5C7B7F` (hue 187, 0% pink), after `#775061` (hue 334, 86% pink), over a floor of `#4C9390`; in Forward+ (lavapipe), before `#829395` (hue 185, 0%), after `#A77583` (hue 343, 91%), floor `#5CA19E`; the rammer terr_n_a in Compatibility, before `#4C666D` (hue 193, 0%), after `#714759` (hue 334, 89%), floor `#357879`; in Forward+, before `#797A84` (hue 233, 15%), after `#A6667A` (hue 342, 95%), floor `#3F8288`. The frames are in the project's shared files, not the repository: `pangaea/screenshots/m1-step3-fixes/` (`lane_*`, `crest_*` and `hud_*`, before and after).
- **The bottom hint sits above the edge arrows' band.** The south screen edge is the nearest to the cell (about 5.5 m at zoom 14 against an ambush sight of 6 m), so the bottom edge arrow is the most common one, and its badge and its tell "!" were drawn over the refusal hint at the bottom center ("Turn your mouth toward it" lost a letter or two for up to 3.2 s). The arrows stay on top of the HUD and keep to a band along their edge: on the top and bottom edges the "!" is drawn beside the badge, toward the screen's middle (on the side edges it stays inward), so a bottom arrow reaches at most `ThreatIndicators.band_px()` = 70 + 30 × 1.25 = 107.5 px above the screen's bottom at the top of its pulse (it reached about 161 px with the "!" above the badge). `hud.tscn` raises the hint by its gap under it, 40 → 96 px, so the hint panel ends at y 952 of 1080, 20.5 px above that band (the canvas is 1920 × 1080 at every window size). The smoke checks every refusal hint against the drawn arrows and against an arrow at every place on every edge, telling at the top of its pulse, in 1280 × 720 and 1920 × 1080 windows. The on-screen test stays the body's center (plan section 15), so a half-visible creature still gets an arrow.
- **One "!" per notice: over the body on screen, on the edge arrow off screen.** The 3D "!" sits 1.25 m up and one body radius north of its creature, so a creature that notices the cell from just below the bottom edge (the common case: dy of about 5.5 to 6.6 m at zoom 14) drew its "!" through the edge arrow's badge and pointer, and the two read as one pin. `CreatureView` now shows its marker only while the creature's sim position is on screen, by the arrows' own test (`ThreatIndicators.on_screen`), and the edge arrow draws its upright "!" while the creature is in its notice phase (not a rammer's wait for its turn), without the pulse, which stays the tell's. So a notice from off screen still shows a "!", which plan section 15 gave only to a tell's arrow; the plan, M1.md and the smoke record it.
- **The rammer's crest casts no shadow.** Seen from the 55 degree camera the thin crest blade threw a hard dark shape on the pale back in Compatibility and a dithered smudge in Forward+, which read as a hole in the body. `CreatureView` turns off the Hood mesh's cast shadow (only the rammer has one); every body still casts its own, against plan section 20's "bodies cast shadows". The crest's points still render dark navy, since the side the camera sees faces away from the key light: the production threat bodies are to give `M_Threat` a faint emission (`#D9466B`, energy about 0.6, PROPOSED), which is an art source change, not made here.
- **A cancelled tell deflates from where it got to.** The recover after a cancelled puff blended from the full puff, so a rammer cancelled early swelled for about 0.1 s (scale 1.03 → 1.18 for a cancel 5 ticks in) before deflating. It now starts from the pose shown at the cancel and only deflates, over the same 24-tick recover; a recover after a strike is unchanged.

## 2026-10-22 · M1 step 3 review fixes: pressure (PROPOSED)
The step 3 review found that a cell feeding by the spawn never had to meet a threat. z_center and z_s each fed a grazer or an omnivore for ever, and both lay outside every creature's reach: the nearest reach disc (leash or territory plus leash, plus the body) ended 4.1 m from z_center and 8.9 m from z_s. Hunger, metabolism, the lunge window and the token act only inside a reach, so none of them could change that. Three data changes close the gap (the third, z_s's regrowth, came from the second review round); how much pressure the pool should have stays the owner's call after he plays. Tells stay 1.2 s, and D20, D21 and every SpeciesCatalog and layout rule are unchanged.

1. **lair_gap moves to the south rim as lair_s** (`creatures_m1.json`): home (5.0, 31.0), heading −2.0779 (facing z_s's centre), was (−9.4, −16.3) in the north-west rock gap. Its reach (9 m leash plus its 0.75 m body) enters z_s by 5.45 m, and from home its hunter sees z_s's edge 4.30 m away (sight 6 m). Its reach keeps 12.81 m from the checkpoint (rule 8 needs 12; every other site keeps 15.5 m or more), its home is 22.56 m away and outside the widest view, and it passes rules 9 and 10 with rock_15 and rock_08 outside its disc. Why this site:
   - A lair north of z_center must sit at least 7.75 m from it (rule 8), beyond the hunters' 6 m sight. A probe lair at (0, −13) noticed the omnivore twice in twelve five-minute runs, six of them dodging.
   - West of z_s, rock_15 leaves 0.38 m to the soft wall (rule 10).
   - A rammer's territory can never touch z_center: rule 8 keeps its edge 1.6 m short.
   - Moving lair_sw or lair_se would free z_sw or z_se. In a probe with lair_sw moved, a grazer then lived in z_sw for 5 minutes and met nothing.
   - lair_gap guarded no zone. The north keeps its four rammers, and all three ambush hunters now wait at rims, as their death tip says.
2. **z_center regrows at 0.08 a second, was 0.10** (`pool_m1.json`; z_n, z_se and z_nw already use 0.08). Its most sustained yield, r × K × (1/4 + 0.05), falls from 1.44 to 1.15 energy a second. That is below what a foraging cell eats, about 1.4 a second (53 meals of 8 in 5 minutes for both bodies). So z_center alone no longer feeds a cell, and a forager by the spawn also feeds where threats live. No reach can make z_center itself dangerous: rule 8 keeps every reach short of all but its far 2 m, beyond any lair's sight. An emptied z_center now shows its first item after 19.1 s and all 6 after 70.5 s (was 15.3 s and 56.4 s). Every zone is still full at world start.
3. **z_s regrows at 0.06 a second, was 0.10** (`pool_m1.json`; second review round). lair_s alone left z_s safe for a cell that stays in it:
   - F6 spawns a creature only when the cell is at least 20 m from its site and out of view. Every point of z_s is 4.3 to 16.3 m from lair_s's home, and any lair whose reach enters z_s must be that close. So while the cell is anywhere in z_s, lair_s cannot spawn or respawn.
   - After a title Continue from a save made in z_s (D16: fresh energy, no creatures saved), lair_s never spawned in 300 s. In a 20-minute z_s camp from the spawn, lair_s's hunter starved with no prey at 741 to 791 s and never came back; meetings per 5 minutes were [8, 13, 2, 0], [8, 7, 3, 0], [4, 5, 1, 0] and [13, 6, 5, 0] (seeds 1 and 2, both bodies).
   - At 0.10 z_s fed such a camper for ever: its top sustained yield, 1.92 energy a second, is above the 1.45 to 1.52 a camper that eats every item it has room for draws (eating with half an item's room wastes the rest), and the camper never fell below 0.88 energy.
   - At 0.06, growth × capacity is 3.84, the same as z_center's at 0.08, so both zones by the spawn top out at 1.15 a second. A camper that eats what it can, as the cell does whenever it touches an item with room for half of it, eats z_s down and then runs dry on what an eaten-down zone regrows (0.52 to 0.60 a second). It has to leave, or it starves and continues at the spawn, 22.6 m from lair_s's home; either way lair_s spawns and is there when it comes back.
   - Not closed, and left to the owner: only a cell that tops up whenever it touches food is pushed out of z_center and z_s. A cell that rests and eats in bursts when it drops to about 75 to 85% lives in either zone for ever with no threat: in a checker's probe it met nothing in 900 s in 6 of 8 runs from the spawn into z_center and in 4 of 4 runs started at a zone's centre (seeds 1 and 2, both bodies), and never fell below 0.72 energy. That is an ordinary way to play, not min-maxing. The same holds for a camper that eats an item only when it has room for all of it: it wastes nothing and draws only its burn, 0.97 to 1.03 a second, under the 1.15 top yield. From full it stayed at 0.89 energy or more for 900 s in z_s and in z_center (seed 1, both bodies). Closing that too needs a top yield under that burn. With z_center at 0.0625 and z_s at 0.047 (top yield 0.90) it ran dry after 348 to 498 s; with 0.05 and 0.0375 (0.72) after 246 to 309 s, and the greedy forager from the spawn then met more threats (seeds 1 to 6: omnivore 2.63 a minute and 1.50 deaths per 5 minutes without dodging, 7.27 a minute dodging; grazer 5.00 and 9.23; no starvation, no deaths when dodging). An emptied z_center would then take 90 s or 113 s to show all 6 items (70.5 s now) and z_s 120 s or 150 s (94 s now). How sparse the food by the spawn may be is for the owner's play test, so it stays at 0.08 and 0.06.
   - No lair can cover this instead: F6 is the fairness contract, and a lair 20 m from every point of z_s reaches none of it.
   - An emptied z_s now shows its first item after 21.5 s and all 8 after 94 s (was 12.9 s and 56.4 s).
4. **Gates** (`tests/test_threat_gates.gd`, slow):
   - #32, pressure: the forager is ForageBot (nearest food, minds no creature) under EvadeBot's dodge, 0.4 s after each tell (F2). It runs from the spawn for 300 s on seeds 501 to 503, fixed before any run, for the grazer and the omnivore. Notices of the cell plus tells at it must come at least 1.0 a minute for each body (pressure exists), and at least once in every seed (second round: an average let a seed that met nothing pass). The cell may die at most 0.5 times per 5 minutes over the six runs (a careful player is not worn down), and it must never starve.
   - #33, no larder for a greedy camper (second round): a camper starts full at the centre of z_s and of z_center, as a Continue from a save made there would put it (a Continue gives 60%; full is the harder case), eats only that zone's food, dodges tells, and must run dry within 7 minutes, for the grazer and the omnivore (seed 331, fixed before any run).
   - A fast test (`test_species_catalog`, `test_an_ambush_lair_reaches_into_z_s_and_sees_it_from_home`) keeps a lair reaching at least 2 m into z_s and seeing its edge from home.

Measured: a greedy forager from the real spawn, 300 s, probe seeds 1 to 6. Meetings are notices of the cell plus tells at it. Each cell gives the runs that met a threat, meetings a minute, then deaths per 5 minutes.

| Forager | Before | lair_s only | First round (lair_s, z_center 0.08) | Built (also z_s 0.06) |
| --- | --- | --- | --- | --- |
| Grazer, no dodging | 4 of 6; 1.73; 1.00 | 6 of 6; 1.83; 0.83 | 6 of 6; 4.03; 2.50 | 6 of 6; 3.93; 2.50 |
| Omnivore, no dodging | 0 of 6; 0; 0 | 0 of 6; 0; 0 | 6 of 6; 2.10; 1.00 | 6 of 6; 2.17; 1.00 |
| Grazer, dodging each tell | 4 of 6; 4.30; 0 | 6 of 6; 4.80; 0 | 6 of 6; 8.37; 0 | 6 of 6; 8.33; 0 |
| Omnivore, dodging each tell | 0 of 6; 0; 0 | 0 of 6; 0; 0 | 6 of 6; 4.50; 0 | 6 of 6; 4.50; 0 |

Measured: a z_s camper (eats only z_s's food, dodges tells) started at z_s's centre, 900 s, seeds 1 and 2, both bodies. Each cell gives when it first ran dry, from 60% energy (a Continue) and from full, then when lair_s first spawned (60%; full).

| z_s growth (top yield) | Ran dry, 60% | Ran dry, full | lair_s spawned |
| --- | --- | --- | --- |
| 0.10 (1.92), before | never | never | never |
| 0.07 (1.34) | 279 to 407 s | 546 to 663 s | 316 to 461 s; 590 to 709 s |
| 0.06 (1.15), built | 212 to 239 s | 292 to 321 s | 249 to 277 s; 329 to 359 s |
| 0.05 (0.96) | 186 to 206 s | 247 to 268 s | 216 to 244 s; 275 to 306 s |

0.06 was chosen over 0.07 because a camper that arrives full lasted up to 11 minutes at 0.07, and over 0.05 because 0.06 matches z_center's top yield, which a camper already cannot live on. Built, the Continue camper met lair_s 11 to 13 times in 15 minutes (before: never). In the 20-minute camp from the spawn, lair_s's hunter still starved at 748 to 793 s, but it was back at 829 to 992 s, once the camper had starved and continued at the spawn (this camper never leaves on its own); meetings per 5 minutes were [6, 5, 1, 2], [4, 3, 0, 3], [4, 5, 0, 0] and [5, 2, 0, 6], and the camper starved to death 6 or 7 times. A z_center camper (same probe) ran dry at 230 to 279 s from 60% and 315 to 338 s from full; at z_center's old 0.10 the full one never did.

- Before, the omnivore stayed in z_center 99% of the time, and two of the six grazers lived in z_s. Built, those two grazers spend 52% and 81% of the run in z_s and meet lair_s there 7 and 5 times (their first meetings with any threat at 28 and 80 s). The omnivore leaves z_center when it runs short and meets the rammers, lair_se or lair_s (first at 104 to 207 s).
- Gate #32, built: grazer 9.00 meetings a minute and omnivore 5.73, each met in 3 of 3 seeds; 0 deaths; 0 starved (first round: 8.80 and 5.73). With the data before the fix: grazer 3.60 (met in 2 of 3) and omnivore 0.00, so the gate fails. With lair_s alone: grazer 4.27 and omnivore 0.00, so it fails too. With lair_s moved back and z_s at 0.10, the grazer's 11.07 a minute passes the average but seed 501 meets nothing, so the every-seed rule fails it; with z_s at 0.06 that grazer leaves z_s and meets lair_se, so only the fast z_s lair test guards lair_s.
- Gate #33, built: z_s ran dry after 331 s (grazer) and 310 s (omnivore), z_center after 350 and 339 s, each camper in its zone 100% of the time. With z_s at 0.10 its campers never ran dry in 420 s; with z_center at 0.10, neither did its campers.
- The other gates, built: hunter viability 6 of 6 seeds (6 or 7 kills, 20 to 22 meat, 0 hits taken; D2 needs 5); predation balance 0 predation deaths and no niche empty in seeds 1 to 4; threat fuzz seeds 401 to 404: 16 tells, 17 give-ups, 5 hits on the cell and 2 flees, against floors of 10, 3, 1 and 1 (z_s's change left all four the same).
- A probe with z_center at 0.09 (lair_sw moved instead of lair_gap) met the dodging omnivore in only 3 of 6 runs (1.23 a minute).

Impact: a first-time player who forages by the spawn, eating what it touches, now meets a tell within a few minutes. One who never reacts to a tell dies 1 to 2.5 times per 5 minutes; one who dodges each tell does not die. Neither zone by the spawn feeds a cell that stays in it and eats what it touches, so a player who saves in z_s and continues there runs short within about 5 minutes and meets lair_s when coming back. A player who rests by the spawn and eats in bursts when hungry, or only with room for a whole item, can still live in either zone and never meet a threat (item 3); how much to push that player out is the owner's call. Gate #32 takes about 90 s on its own here (4 shared CPUs at load 10) and #33 about 45 s (load 6). Approval: tuning values, owner review pending.

## 2026-10-22 · M1 step 3 review fixes: tests (PROPOSED)
1. **Cost gate flake policy.** A wall-clock gate cannot both pass under steady load and fail on a step that got twice as costly: on the shared 4-CPU container, pinning the run beside one busy loop doubles every reading, exactly like a 2× regression. So the two step 3 cost gates now check two things, and only sim.step and a yardstick are timed:
   - **Microseconds, with room for load.** The same ticks are timed three times, the bot's run and two replays of its recorded intents, and the replays must end in the bot's run's state hash. #28 (7 creatures, `tests/test_threats_sim.gd`) counts the fastest whole run against **1500 µs** (was 1000); #29 (24 creatures, `tests/test_threat_gates.gd`) keeps each 5 s window at its fastest of the three and counts against **4400 µs** (the plan's 2500). Each limit is about 2.5× a quiet reading here (about 550 to 600 and 1700 µs; CI's runners read 247.9 and 810.2 at 815ba10, 364.2 and 1183.7 in run 39859308458 of this branch, 311.3 and 979.2 in run 39873075887), in line with the plan's "fail only at 3–5× the expected cost". Pinned beside a busy loop they read 1188 and 3908 µs and pass; the old limits failed there.
   - **Yardsticks, for a regression.** Right after each timed step the gate times `tests/cost_yardstick.gd`, a fixed piece of plain GDScript work that allocates nothing (vector math over every pair of 24 points, three times over, into a packed array; 99 to 106 µs in every condition below). Time-slicing by other processes lands on the step and the yardstick in proportion to their length, so a run's step time over its yardstick time holds where the microseconds do not. The median of the three runs must stay under **8** (#28) and **22** (#29). Median readings here at load 2 to 7 (other agents' suites), and pinned to one core beside a busy loop or a cache-thrashing process (each doubling the microseconds): #28 4.71 to 5.37, #29 15.1 to 16.9; on CI's runner (run 39873075887, at 3657b4b) 4.64 and 14.59, each run within 0.07 of the others. Steps made twice as costly in a copy (a busy wait as long as the step itself, the creatures' body snapshot rebuilt 20 extra times, or a loop of 8500 or 22000 sines) read 9.5 to 10.2 and 28.2 to 33.3 in the same conditions and fail, while their microseconds (1047 to 1148 and 3005 to 3602 µs on the quietest runs) pass. Each limit is about 1.5 and 1.3 times the highest reading here (1.7 and 1.5 times CI's), and a doubled step reads at least 1.2 and 1.3 times over it.
   - **Why the yardstick changed.** The review's first yardstick built a dictionary each time, and the gates took the lowest of the three runs. Its time grew with the heap and with the cost of the step before it: the three counts often fell run after run (14.75, 13.89, 13.27 in one `check.sh`), and the stress yardstick's median rose from about 102 µs to 120 to 141 µs behind the busy wait or the sine loop. So a doubled stress step read only 1.4 to 1.6 times the yardsticks: at load 5.5 to 6, 23.3 for both against 14.6; at load 2.4 to 2.8 the review-round gate passed the sine loop (20.85 yardsticks, 3110 µs) and failed the busy wait by 0.09, and the reviewer saw the busy wait pass at load 6 to 7 (21.55 and 21.96). The new yardstick and the median run read 28.7 and 33.3 for those two at load 2.7 to 3.3.
   - **Heavy load.** Load still moves the count a little. The highest medians above, about 10 % over the quiet readings, came in the final `check.sh` at load 4 to 7 (5.37 and 16.45) and beside the cache-thrashing process (5.05 and 16.9; single runs up to 5.66 and 17.18 in all), since load pushes the step's data out of the caches more than the yardstick's. No heavier load came this round; the reviewer saw the first yardstick's runs range from 6.84 to 20.70 at load 19. So a failure under heavy load is rerun on a quiet machine before it is blamed on the step, and a pass under heavy load does not by itself rule a regression out; a pass on a quiet machine (load under about 4 here) or on CI does. At load above about 15 (several agents' suites at once) expect the microsecond checks to fail (2883 and 6017 µs at load 18 to 28, both passing when rerun at load 9 to 10) and the unit suite to come near its 900 s limit (769 s in that run).
   - If a gate fails, rerun its file alone (`-- --only=`) and note `uptime`. A yardstick failure is the step until a quiet rerun passes. A microsecond failure with the yardstick count in range is usually load, but under heavy load a costlier step can read in range too (a stress step five times as costly read 13.80 with the first yardstick at load 13 to 18), so it is load only once a quiet rerun passes. A stop at the suite's 900 s limit names the test it stopped in on the last `run` line: rerun that file alone, and if it finishes, the stop was load, not a hang. CI's runners differ (two runs read 248 and 364 µs for #28); if one reads near a yardstick limit, the limit is revisited with the readings, never by loosening it until a doubled step passes.
2. **No run can hang CI.** `tools/check.sh` and `tools/check_release.sh` run each Godot call under `timeout` (the import and the release pack's export 600 s, the unit suite 900 s, the boot check, the launch run, each smoke and each release start 300 s; about three times their usual length here), so a hang fails with exit code 124 and the output so far. The helper, `tools/bounded.sh`, runs `timeout --foreground`: plain `timeout` moves Godot into a process group of its own, so a Ctrl-C at the terminal no longer stopped the import or the suite (check.sh carried on to its next run), and an outer `timeout` or a stopped CI job left Godot running for up to its limit. The cost is that a process Godot starts would not be stopped with it; no run here starts one. `tools/test_bounded.sh`, which `check.sh` runs first (about 12 s), checks the stop, the kill 10 s later, and that an interrupt or a terminate sent to the script's process group ends the script and leaves nothing running. `tests/run_tests.gd` prints `run` as each test starts and `ok` or `FAIL` as it ends, then the failures again above the totals, so a stopped suite names the test that hung. CI's export step gets a 10-minute limit; the job's 30 minutes stay as the backstop, since one stopped run ends `check.sh` within about 17 minutes.
3. **Respawn edges are tested at the sim level.** `test_checkpoints` #7 sends home a creature 11.5 m from the checkpoint (its home 20 m out) next to the 14 m one that stays, and checks a dev kill's respawn gives no brain an ignore on the cell; #6 checks every brain but the killer's keeps the ignore entry it had. `RespawnRules.to_relocate` still measures centre distance while rule 8, fuzz invariant 3 and test #1 measure the body's edge, so a dev creature centred at 12.3 m is neither sent home nor counted as clear; natural creatures cannot get there (rule 8), so this is left as is.

## 2026-10-22 · Microscopic world look (PROPOSED)
The owner approved a new look for the M1 cell stage: a microscopic world, a deep-blue fluid with depth layers, instead of a shallow pool with a floor. The sim, collision and camera do not change. The engineering plan is `docs/micro-world-plan.md` in the project files; it puts the fluid's opaque backdrop at y −40 m. Its values are PROPOSED tuning, recorded here as each part lands.

- **Measure first: the look probe and GPU time (C1).** `tools/godot/look_probe.gd` stages seven fixed moments on seed 4242 and checks the plan's section 6 gates in either renderer; `docs/TOOLCHAIN.md` ("Look probe") has its commands and all of today's readings. Where the plan names a gate but no method, the probe's choice is PROPOSED:
  - the lane outline is the largest |dL\*| against the same pixels with the lane hidden, scanned across the lane's edge at 30, 50 and 70% of its length on both sides; the gate takes the least of the places no body covers, and needs at least 3;
  - the pale decor stand-in is a camera-facing plane at y −3 m (the top of the midground band) under the lane's middle, colour (0.85, 0.92, 1.0) at alpha 0.147: linear luminance 0.81 × alpha = 0.12, the ambience contract's cap;
  - "no visible hard lower edge" on the skirt is no L\* step above 6 between samples 0.5 m apart down the north wall (radius 38.75 m, y −1 to −30 m) below the cell, with art's decor hidden (since the final audit, below);
  - the depth glow check (plan risk 1) wants the fluid's centre third at least 5 L\* lighter than the mean of its four corners;
  - "fluid near the cell" is the centre third of the frame with every body, food item, rock and the 2D layer hidden; the cell and starving gates compare the cell's inner 55% with it;
  - parity is the median CIE76 between the two renderers' frames, over the fluid frame and over the cell; the hurt vignette's outer band is the four corner boxes with the vignette alone over the 3D frame.
  The lineup's threats are dev-spawned (D17), since the sim keeps a site's creature on its leash (D20), and are shot once their 1 s fade-in ends. `--look=baseline` holds today's look in both renderers with margins, so the probe can be checked on today's build: it passes there, and the micro gates fail as expected. Today, Compatibility / Forward+ (lavapipe): cell h 42.1 / 41.3; the teal floor near the cell L\* 42.4 / 47.5 at h 206 / 213 and C\* 23 / 24; the cell against it dL\* 2.4 / 3.6; lane outline 8.0 / 3.0 (tell) and 6.4 / 2.8 (puff); starving cell dL\* 5.8 / 3.7; hurt vignette band h 261 / 254, blue-grey; carrion 18.6 / 15.1 degrees from the threat pink; the renderers 6.7 apart on the floor and 7.0 on the cell. The perf tour's report gains `gpu_frames`, `gpu_avg_ms`, `gpu_slow_1pct_ms` and `gpu_max_ms`, and the F3 panel a GPU line (average and longest over the last 60 timed frames), from the renderer's own timing of the root viewport. Impact: no change to the game or its look. The probe lives in `tools/` (outside both exes) and the GPU timing in `game/dev/` (dev exe only); on lavapipe and llvmpipe the GPU time is CPU rasterising, so the plan's GPU budgets are measured on the owner's PC.
- **Shader warm-up without the floor.** Under the 0.3 s start fade, the eat burst and both food meshes draw once, so their shaders are compiled before the first meal (`pool.gd` `_fade_in`, `PlayerCellView.warm_up(meshes, at)`). They used to draw 5 m under the cell, hidden only by the floor; without the floor they would show through the fluid after the fade, about 30% fogged. They now draw on the camera's view axis at `PoolScene.WARM_UP_Y` −45 m (PROPOSED), 5 m behind the backdrop: in the frustum at every zoom (65 to 75 m from the camera, far plane 200 m) and behind opaque ground in both looks. `tests/test_warm_up.gd` pins this at every zoom from 10 to 20 m, looking at the spawn and past the wall to the north and south, for 16:9, 16:10, 4:3 and 21:9 windows; the old point 5 m under the cell fails it. No visible change: in Compatibility, frames 2 to 34 of a fresh start match the previous build pixel for pixel, apart from the random lineage id, while a control with the point above the swim plane shows the burst on the cell. Impact: occlusion culling is off (`project.godot` does not set it). Turning it on would cull the hidden draw, so nothing would compile and the point would have to move.
- **The rim asset, an engineering placeholder.** Without the floor, the pool's edge needs a mesh of its own. `tools/blender/make_m1_micro_rim.py` builds `pool_rim` (`assets/export/pool_rim.glb`, record `assets/records/pool_rim.json`, review state "blockout - M1 micro world, not visually approved"): 3,840 triangles against a budget of 4,000 (the plan's "about 4k"). The pool scene does not use it yet; the fluid look swaps it in for the floor. It is one surface of revolution with 128 segments. A skirt wall faces the pool at r 38.62 to 38.70 (a 6 cm wobble) from 30 m down to a rounded top edge at −0.56 m. From r 39 out it takes the floor's own rim height field: the lip at +1.2 m at r 42, then the shelf at +1.0 m out to r 66, past the widest view from the wall. The surface crosses the swim plane at r 40.04 all round. That is half a metre outside the hard radius (39.5) where the collision stops the cell's side, so the wall the player sees is where the cell stops. Inside r 39 the surface stays at or below −0.46 m, under the cell. `tests/test_assets.gd` checks the shape from the triangles alone, never the material, against the plan's bands: the inner face in r 38.5 to 38.8 at every azimuth down to at least 5 m, and the crossing between the hard radius and 1 m outside it. Art can swap the look the owner picks (stone, membrane or brighter water) by pointing `pool_rim.glb.import` at another material. A mutation that did exactly that failed only the look test. Generator, export and record are byte-identical between runs.
- **Skirt depth: 30 m.** The plan's sketch stopped at −6.4 m (38% fog), with −20 m (82%) as the fallback if the lower edge showed. A probe rendered the plan's look (its section 3 values) with the rim in place of the floor, in Compatibility at 1920×1080 and zoom 14. With the cell pressed against the north wall, a −20 m skirt still left a faint step of 2.7 L* where it ends, across the lower screen. At −30 m (93% fog) no step shows. At zoom 14 the skirt's end stays below the frame. At zoom 20 it is in frame, and the screen-centre column changes by at most 0.8 L* per 15 px. The deeper skirt costs no triangles.
- **Placeholder palette.** The colours are linear RGB in vertex colours, drawn by `assets/export/M_PoolRim.tres`.
  - The lip and shelf are dark, cool stone, (0.030, 0.034, 0.045), about sRGB (0.19, 0.20, 0.23). This is the plan's darkened stone, (0.20, 0.19, 0.18), turned toward blue.
  - From 1 m down, the wall's inner face takes a lighter navy, (0.07, 0.13, 0.19). On the north side the sun (from the north-west, 55° up) never reaches that face, and in the lip's stone it rendered near black (L* 6), against "shadows go blue, never black".
  - Every colour keeps blue ≥ green ≥ red, so nothing leans toward food's yellow-green or the threat's pink. The lip's luminance is 0.04 against the 0.40 cap. Tests pin the cap, the cool rule and a floor of 0.08 on the wall's luminance.
  - Probe readings, Compatibility: the sunlit lip and shelf render grey at L* 34 to 38 (chroma 5), a little lighter than the fluid beside them (L* 24 to 32). The north wall renders navy at L* 18 by the cell and L* 24 with depth (hue 280 to 289). A thin crease at the wall's top edge renders at L* 12. The coral cell is L* 54 or more.
  - Forward+ (lavapipe), same shot: the rim is within 1 L* of those readings (shelf L* 36.6 against 35.8, the wall the same, the crease 13.3 against 12.2), and the lineup's fluid matches.
  - Impact: from the wall, the edge reads as a grey stone band above the cell and a navy wall falling away below it. If the owner keeps stone, art may darken the shelf about 0.7 times to sit at the fluid's value; the final material sets that.
- **The fluid look (C4).** The floor is gone, and with it the caustic and water passes and the Compatibility profile. The fluid is built from four parts that render the same in both renderers:
  - height fog from 1 m under the swim plane (`fog_height` −1.0, `fog_height_density` 0.09: 30% at 5 m, 56% at 10 m, 93% at 30 m, 97% at 40 m), colour (0.0, 0.085, 0.20);
  - `%Backdrop`, an opaque, unshaded 400 × 400 m plane at y −40 (`game/scenes/pool/backdrop.gdshader`, `#0B2E6B`) that keeps the engine's fog, so every pixel of it shows the fog colour at that depth and any decor art adds fades into exactly the colour behind it. It covers r 162.8 m around the farthest focus, the widest view at zoom 20 in a 21:9 window (r 146.5 at 16:9), and its farthest visible point is 140.7 m from the camera, inside the 200 m far plane;
  - `%DepthGlow`, a second directional light that lights nothing (`light_cull_mask` 0, no shadow, sky mode light only), colour `#4C9BE0`, energy 1, pointed along the camera's view axis, so the fog's sun scatter (0.05) draws a lighter field around the view centre like a microscope's lit field;
  - no distance fog (`fog_density` 0), so everything on the swim plane keeps its colour at every zoom.
  The ambient is `#2F6FB8` at energy 0.8 (luminance × energy 0.32, blue). The Sun keeps its colour and direction (55° up, yaw −135°), goes from energy 1.3 to 1.5 and casts no shadow. The start fade is `#194A7C`, the fluid's mid-tone, not the old teal. Tonemap Filmic, white 1, exposure 1, unchanged. `%Rim` is the C3 placeholder `pool_rim.glb`; `pool.gd` names it `rim_node` and no longer turns its shadows off (nothing casts one). Deleted: `pool_floor` (GLB, import, record, `.blend`), `M_PoolFloor.tres`, `T_PoolFloor_Normal.png`, `M_PoolCaustics.tres` and `pool_caustics.gdshader`, `M_PoolWater.tres` and `pool_water.gdshader`, and the floor's entry in `make_m1_production.py` (`make_m1_blockouts.py` stays as history, and the rim generator still reads its height field). The CC0 sand scan in `assets/source/textures/cc0/polyhaven_aerial_beach_01/` is kept, though nothing uses it now. `PoolLook.COMPATIBILITY` is `{}`; `apply(profile, sun, world)` still works on copies, as an escape hatch should a renderer drift again. The Backdrop's `PlaneMesh` is listed in the placeholder inventory as functional (kind "environment"): the fog hides it to 97% and it shows no shape of its own. Impact: draw calls in the probe's lineup fall from 140 to 57 (Compatibility) and from 46 to 45 (Forward+), primitives from 57.3k to 19.7k, and the shadow pass is gone.
- **Why one set of values now works (renderer findings).** Compatibility draws a shadowed directional light as a separate additive pass in sRGB, tonemapped on its own, and multiplied the water pass into stored sRGB; that is why the old look needed its own Compatibility values. With the sun's shadow off and the floor's passes gone, the probe (`tools/godot/look_probe.gd`, 1920×1080, zoom 14) measures the two renderers 0.0 CIE76 apart on the fluid and 0.6 on the cell (the old look: 6.7 and 7.0). The DepthGlow relies on the fog's sun scatter ignoring the light's cull mask, which both renderers do in 4.7.2 (GLES3 and Forward+ `fog_process`); the engine does not document it, so the probe's depth glow gate (centre field at least 5 L* lighter than the corners) catches it after an engine upgrade. Aerial perspective is compiled out of Compatibility and is off.
- **Distance fog turns the coral toward the threat pink (fog-pink finding).** Measured in the probe's lineup, Compatibility, with the values above: `fog_density` 0.004 moves the cell from h 43.1, C* 45.3 to h 39.9, C* 42.3, toward the threat's h 11, and the carrion from 18.6 to 16.4 degrees of hue from the threat pink. With plan A's brighter fog colour it reached h 0 to 9 (plan section 2). Hence 0; `tests/test_pool_look.gd` pins it.
- **The look probe on the fluid look, Compatibility | Forward+ (lavapipe).** Cell `#C0674C` L* 53.4, h 43.1 | 42.6; fluid near the cell `#1E5286` L* 34.0, C* 34.1, h 273.5 in both (mood frame L* 27 to 30, h 278); top band L* 25.5, bottom 27.1, corners 16.3 to 17.9 at h 282 to 285; the cell against the fluid dL* 19.4 in both; centre field 17.2 | 17.1 L* above the corners; starving cell dL* 20.6 | 23.3; ambush body L* 55.2 | 54.8 at h 88 (dL* 24.7), rammer L* 69 | 70; carrion 18.6 degrees from the threat pink; plankton h 117.9 to 138.1; rim north skirt's largest step 3.2 | 2.6 L*. Gates: 14 of 20 pass in Compatibility and in Forward+ with parity (both parity gates pass). The six that fail:
  - the four lane outline gates (over the fluid 2.8 | 10.5 dL* on the tell, 3.1 | 10.7 on the puff; over the pale decor stand-in 2.4 to 3.1): the keyline, fill lift and `LANE_PRIORITY` are C5, which waits for the lane fix round;
  - the hurt vignette's outer band, h 316 | 316 (blue-violet over the navy, as the plan foresaw): its warmer tint is C8;
  - plankton clipping: the highest channel is 255 in both renderers. It is the green channel in the sunlit, emissive core of each diatom, 86 to 177 pixels of each item; the items' median colours top out at 249 (`#E1F99C`), the judge's measure (250). It clipped in the old look too. The sun alone does not settle it: at energy 1.0 the core still clips while the cell falls to dL* 11.6 (gate 15), and with no sun the core peaks at 226. Engineering keeps the plan's light; the fix is the plankton's albedo or emission core (art) or a decision that the gate reads the item's median, as the judge did.
  Frames: `screenshots/micro-world/engineering/c4_compatibility_<scene>.png` and `c4_forward_plus_<scene>.png` in the project files, for the scenes lineup, tell, puff, rim_north, rim_south, starving and hud.
- **The look's tests, old to new.** `tests/test_pool_look.gd` is rewritten; each removed pin has a successor. The floor's pass chain and its water's absorption become "the fluid fades with depth" (height fog bands at 0, 10, 30 and 40 m). The caustics' own fog copy becomes "every additive pool shader takes no fog" (all `.gdshader` files under `game/scenes/pool/`, art's `ambience/` included: additive plus engine fog paints a bright hard quad). "Glow stays off" and "one shadowed key light and no costly screen effects" become "one warm key light without shadows and nothing costly" (glow, SSR, SSAO, SSIL, SDFGI, volumetric fog, aerial perspective, sky affect and camera attributes). "Shadows go blue" stays. Its HSL saturation cap of 0.55 becomes "the fluid keeps to its value and hue rule": the owner-approved fluid is about 0.93 saturated, so the stored fog colour plus the glow's scatter has luminance at most 0.12 (now 0.10), and a LAB hue in the fluid's band 268 to 288 (now 281.8). The band carries the plan's hue gap for the stored colours: anywhere in it the fluid is more than 150 degrees from food and at least 83 from the threat pink. The plan's 90 from the pink would fail its own fog by a degree (89.3), so the look probe holds the 90 on screen instead, in a gate added to section 6's, `fluid_threat_gap` (the fluid renders at h 273.5, 98 degrees away; a first version of the test also checked the stored colours against 83, which the band already guarantees, so it could never fail and was dropped). The same test pins the tonemap, white and exposure, which the fluid's dark stored colours depend on. The three Compatibility profile tests become "both renderers take one set of values and the escape hatch works on copies". The rim lip test moves to `pool_rim` and the scene's `%Rim`. New: distance fog is off; the Backdrop covers every view inside the far plane; the DepthGlow lights only the fog along the view axis; the start fade is the fluid's mid-tone (its L* 30.8 within the fluid's 26 to 36). In `tests/test_assets.gd` the floor's three tests go; the corner-reach maths moves to a shared helper, `tests/view_reach.gd`, used by the rim's shelf check and the Backdrop's coverage check (its own test moves to `test_pool_look.gd`); the rock test now asks for a base at least 1.5 m under the plane, where the height fog starts to take it, instead of "down to the floor". `tests/test_warm_up.gd` reads the Backdrop's height from the scene. Sixteen mutations of the look (distance fog on, thinner fog, a shallow or small Backdrop, a fog-disabled Backdrop, the glow turned up or lighting the world, a shadowed sun, B's first brighter fog, a violet fog, a dimmer ambient, a tonemap white of 2, an additive ambience shader with fog, a Compatibility profile, the teal fade, and a Backdrop below the warm-up point) each fail the test meant for it.
- **Left as it was.** `game/systems/carrion_field.gd` still says carrion lies "on the pool floor" in its doc comment: this work leaves `game/systems` untouched; the wording pass (C8) can take it. Rocks keep their buried bases and now hang as cut pillars whose bases fade into the fog (about 5% fogged at 1.6 m down); the merge gate on art's shell swap stands.
- **The ambience mount (C6).** `pool.gd` `_mount_ambience()` instances `res://game/scenes/pool/ambience/ambience.tscn` (`PoolScene.AMBIENCE_SCENE`), when it exists, as the pool's single child "Ambience". It runs in the pool's `_ready` once `camera` and `cell_view` are set; art's scene reads them through `get_parent()` and writes nothing back. Art's PR therefore adds files only and edits neither `pool.tscn` nor `pool.gd`: a small amendment to the handoff's "one added child node". Its layers are in view from the first frame, so their shaders compile under the start fade and need no warm-up draw. `tests/test_ambience_contract.gd` checks the plan's section 7 on the scene as the pool mounts it. Until the scene exists only the mount check runs (no Ambience child); the rest return without looking.
  - What it reads: every `GeometryInstance3D` under Ambience, every material it draws with (overrides, surface materials, particle passes and next passes) and each MultiMesh. A material's colours are its Color uniforms and its texture uniforms, times a `brightness` uniform when it has one; a standard material's are its albedo, emission and albedo texture, and a particle process material's its colour and colour ramps. For hue, a flat colour and every stop of a gradient or colour ramp count one by one, however many stops there are; an image texture (a painting) first counted by its alpha-weighted mean, so a few stray texels did not fail it, and now counts by coverage (the contract fixes below). Since round 4 it also reads sprites (texture × modulate), shader defaults, vertex colours a shader draws through COLOR and a CPU emitter's colours (below). Its opacity is the colour's alpha × an `opacity` (or `alpha`) uniform × the instances' custom w. Luminance is linear, `Color.srgb_to_linear().get_luminance()`: luminance × opacity at most 0.12 for any transparent decor, and luminance alone at most 0.40 for anything under the plane.
  - Headless finding: the test runner's dummy renderer keeps no MultiMesh buffer, so instance transforms read as identity and custom data as (0, 0, 0, 1). The contract therefore takes two conventions: an instanced layer whose shader places its own quads names its band of world heights in a vec2 `height_range` uniform (art's drift shader already does), and its custom w counts as up to 1, so the layer's top opacity belongs in an `opacity` uniform with custom w scaling under it.
  - The rest as the plan says: one Ambience, no reference to `res://game/systems` or any class declared there (`PoolSim` among them) and no global random calls; no shadows and every material under `LANE_PRIORITY` (`CreatureView.LANE_PRIORITY`, 8, since C5); additive materials fog-disabled and the rest fogged; no environment, camera, light, fog volume, probe or GI node, and no camera attributes, depth of field, volumetric fog or aerial perspective in its sources; nothing in −1.5 to +0.5 m; nothing above +3 m, the top of the plan's foreground band (the highest instance, the top of a mesh's box or of a `height_range`; the camera is only 8.2 m over the plane at zoom 10, so an item at +3 m already draws about 1.6 times its size at the plane). The ceiling alone does not keep a faint sheet off the frame: a 12 m quad at +2 m passed it and lifted the fluid near the cell from L\* 34.4 to 42.8 in the independent check of round 2. Since the contract fixes below (rounds 3 and 4), no single item above the plane, whatever draws it (a mesh, a sprite, one instance of a MultiMesh or one particle), may be 2 m or more in any direction, so the ceiling, the size cap and the count together keep the foreground to sparse small items; at most 40 items above the plane, counting each MultiMesh instance and each particle, and a mesh once; at most 2,000 instances or particles, 12 billboards of 2 m or more, and 3 transparent billboards over one point (1 m grid); no colour within 25 degrees of LAB hue of food or threat (greys under C* 5 skipped). Twenty-six mutations, of the mount (twice, misnamed, wrong path) and of art's scene (each rule broken once), each fail the test meant for it. Five of them came from the independent check of C6, which found two gaps in the first version: it had no ceiling over the foreground (a decor band raised to +8 m, or one backdrop quad lifted there, passed), and it judged a material with more than 8 colours by their mean, so a 9-stop ramp with one threat-pink stop passed (it still passes the first version's test). The others: a particle colour ramp with a food stop, and 50 particles above the plane (the first version counted an emitter once). Controls pass: a band ending at exactly 3 m, a 9-stop blue ramp, a blue particle ramp, and one small quad above the plane with the Foreground cut to 39 (it sits at the cap of 40).
- **Art's ambience PR (#10) against the contract.** Merged as a tree only (`git merge-tree`), never into `m1-micro`, and written into a scratch copy of C6: the one conflict, the placeholder inventory, keeps both entries. Nine of the ten contract tests pass, and art's own seven; the same after the contract gained its 3 m ceiling and its stop-by-stop ramp check (art's Foreground layer spans 0.6 to 2.8 m, and its colours are flat tints and painted backdrops). The tenth fails on the four drift layers (Foreground, Specks, Bubbles, Microbes): their per-instance opacity cannot be read headless, so their tints count at full opacity (luminance 0.37 to 0.55). Their real tops, tint × the layer's top alpha, are 0.066 to 0.119, inside the cap (Microbes with 0.001 to spare). Art's fix is two lines: a `uniform float opacity` in `drift.gdshader` multiplied into ALPHA and set to the layer's top alpha, with custom w stored as alpha / top alpha. With it, all ten pass, and the whole fast suite on that copy passes (525 tests). The look probe on that copy, Compatibility: the fluid near the cell reads L* 34.4 (34.0 without decor), the cell 19.0 dL* against it, the glow 17.5; the same lane, vignette and plankton gates fail as without it; one more gate fails, the skirt's largest step down the north wall, 6.5 dL* against 6 (3.2 without decor), because decor crosses the sampled column; draw calls rise by 8 to 12 per scene. Frames: `screenshots/micro-world/engineering/c6_art_pr10_compatibility_<scene>.png`.
- **Sunlit patches (C7, owner question 2 taken as "yes").** `game/scenes/pool/zone_lights.gd` (`%ZoneLights`, which `pool.gd` `_build` lays from the layout's zones) puts one disc of the Sun's cream, (0.957, 0.918, 0.824), under each of the seven plankton zones, 2.5 m under the swim plane. `zone_light.gdshader` draws it additive, unshaded, `fog_disabled`, `depth_draw_never`, with no shadow, at render priority −2: full light out to 35% of the disc's radius, smoothly gone at its rim. All discs share one unit PlaneMesh scaled per zone, and the start fade's warm-up draws that mesh at the C2 point with the food meshes (`PoolScene.warm_up_meshes()`). The starving tip stays as it is. `tests/test_zone_lights.gd` checks one disc per zone, centred under it at y −2.5 and spanning 2.6 zone radii, also after a rebuild; the Sun's colour, 52 CIE76 from food's glow (at least 30); the render modes, priority −2 and under `LANE_PRIORITY`; a strength above 0 and at most 0.007; and the warm-up drawing the shared mesh. Twelve mutations each fail the test meant for them; the fogged one also fails `test_pool_look.gd`'s additive check.
  - Size: "2.6 × zone radius" is the disc's span across, as plan B's prototype built it (a PlaneMesh 2.6 r on a side, also in the judge render). Its light is half at 0.88 r, about the zone's edge, and gone at 1.3 r (7.8 m; 6.5 m for the centre zone). Read as a radius (15.6 m), discs 22 m apart would overlap by 9.2 m and the point between two zones would get 86% of a centre's light: one wash over the pool, not patches.
  - Strength 0.006 (PROPOSED), not the plan's 0.05 to 0.08. That range was judged in Compatibility only, and the judge render's "fluid near the cell" was read from a band beside the cell, outside the patch. The look probe's lineup has the cell in the centre zone, inside it. Fluid near the cell L* and the cell's dL* against it, by strength: Compatibility 0 → 34.0 / 19.4, 0.05 → 36.8 / 16.6, 0.06 → 38.0 / 15.4, 0.08 → 40.4 / 13.0 (gates: L* at most 36, dL* at least 15); Forward+ 0.006 → 35.7 / 17.7, 0.01 → 36.9 / 16.5, 0.05 → 45.7 / 7.7 with the fluid's chroma down to 23.4 (gate 25).
  - Renderer finding: the same additive disc adds about five times as much light in Forward+ as in Compatibility, which tonemaps each transparent object before blending. At 0.006 Compatibility shows no change at all (the lineup's fluid frame is identical to C4's, pixel for pixel), and Forward+ lifts the middle of a zone 1.7 L*, fading to nothing at 1.3 r.
  - Impact: within the gates the patches are at the edge of seeing in Forward+ and absent in Compatibility, so the starving tip's "sunlit patches" still rest on owner question 2. Either the owner accepts a lighter fluid and a weaker cell in the zones (the gate would move; 0.01 already fails it in Forward+), another patch design lights the zones without lifting the fluid where the cell feeds, or the "no" branch rewords the tip (in `game/systems/game_session.gd`, so it needs the owner's go-ahead to touch `game/systems`). It is part of the merge gate below. The strength is one constant. The cost is about 2 draw calls in view (the lineup: 47 against 45 in Forward+, 60 against 57 in Compatibility) and the overdraw of seven discs.
  - The independent check of C7 measured the same against the C4 frames: Compatibility draws the lineup's fluid pixel for pixel as without patches, and Forward+ lifts the centre third by 1.5 L* on average (3.6 at most). The class comment no longer claims the patches can be found.
  - Another design, measured for owner question 2 and not built: a soft ring of the same light at each zone's edge, rising from 0.52 zone radii to a peak at 0.88 and gone at 1.3, leaving the feeding middle dark. In the lineup the cell's zone ring stays outside the probe's centre third, so it can be far stronger than the disc within the gates. L* lift over the C4 frames, at most, Forward+ | Compatibility: at 0.025, 11.6 | 0 (Compatibility drops additive light this faint); at 0.05, 19.8 | 3.4. At 0.05 the fluid near the cell reads L* 35.2 | 34.4 and the cell 18.2 | 19.0 dL* above it, and every gate that passes with the disc still passes. Costs: in Forward+ at 0.05 the ring behind the ambush hunter cuts its contrast from 23.9 to 15.6 dL* (19.7 at 0.025), and the tell's lane outline over the fluid from 10.0 to 5.7 dL* where the ring lies under it (C5's keyline is meant to carry the lane); the bright ring also reads somewhat like a target marker. Frames: `screenshots/micro-world/engineering/r2_ring_forward_plus_0.05_lineup.png`, `r2_ring_forward_plus_0.05_tell.png`, `r2_ring_forward_plus_0.025_lineup.png` and `r2_ring_compatibility_0.05_lineup.png`.
  - The final look probe, Compatibility | Forward+ (lavapipe), with parity: 15 of 21 gates pass in each, the 21st being `fluid_threat_gap` (97.6 | 98.3 degrees; see "The look's tests"); the same six fail as after C4: the four lane gates (C5; over the fluid 2.8 | 10.0 on the tell, 3.1 | 9.8 on the puff, a little under C4's Forward+ readings where a patch lies under the lane), the vignette (C8; h 316 | 318) and plankton clipping (255). Parity: fluid 0.1, cell 0.6. Frames: `screenshots/micro-world/engineering/c7_compatibility_<scene>.png` and `c7_forward_plus_<scene>.png`.
- **Merge gate for `m1-micro`.** The plan names one gate, art's rock-to-shell swap (until it lands, the rocks hang as cut pillars). Three more join it, so `m1-micro` merges to `main` only when all four are in:
  - art's shell swap (plan section 3);
  - C5, the lane on the fluid (keyline, fill lift and `LANE_PRIORITY`), which waits for the lane fix round. Until then the strike lane is weaker in Compatibility than in the old look: its outline reads 2.8 dL* over the fluid on the tell and 3.1 on the puff, against 8.0 and 6.4 before (Forward+ 10.0 and 9.8, against 3.0 and 2.8), and 2.4 to 3.1 over the pale decor stand-in; the four lane gates fail;
  - C8, the small cues: the hurt vignette's outer band reads purple (h 316 | 318, gate 15 to 45), and the outlines and badges keep their teal-era colours;
  - owner question 2, the sunlit patches (above).
  The look probe then passes in both renderers, or each gate still failing is signed off by name. Plankton clipping (255) is an asset question for art, or a decision that the gate reads each item's median (249), as the judge did.
  - Status after the finishing round (2026-10-23): C5, C8 and the visible sunlit patches are in (bullets below), and the look probe passes every gate in both renderers but plankton clipping. The shell swap is on art's PR #10 branch (`claude/micro-ambience`, "Rocks become glassy microorganism shells") and not yet merged, so it alone holds the merge. The plan's sections 3 and 5 now name the same four parts.
- **The lane on the fluid (C5).** `threat_lane.gdshader` keeps fix3-visual's outline (`LINE_ALPHA` 0.7, the dark spike-tip border 0.14 m and the bright threat line 0.06 m inside it) and adds the plan's two changes: a deep-navy keyline `#091229` (0.035, 0.071, 0.161), `KEY_M` 0.08 m wide, at the lane's edge outside the border (blue, never black; at 0.05 m it drew about 1 px in Forward+ at zoom 14), and `FILL_LIFT` 0.85, which moves the filled inside from the dark shade toward `#D9466B` so the fill reads over navy. The alpha is `max(min(inside, MAX_ALPHA), LINE_ALPHA * max(max(border, accent), keyline))`: the inside stays under 0.25 and only the outline's 0.28 m reaches 0.7. `CreatureView.LANE_PRIORITY` 8 is set on the lane's material, so the zone lights (−2), art's ambience (tested below 8) and every other world transparent draw under it, and the dev gizmos (10) over it. The start fade's warm-up draws a lane quad with the lane's material at the C2 point (`CreatureView.warm_up_lane_mesh()` in `PoolScene.warm_up_meshes()`), so a first tell does not compile it in play; the placeholder inventory's lane entry names `creature_view.gd` for that quad. `tests/test_pool_view.gd` checks the priority (above 0, under the gizmos' read from `dev_gizmos.gd`, and on the lane's material), the warm-up's lane mesh and its priority, the keyline's width (at most 0.1 m, with the coloured outline still at most 0.25 m), the fill lift and the alpha line; the lane's y test stays in (−0.1, 0). The zone-light and ambience tests now read `CreatureView.LANE_PRIORITY` itself. Look probe, Compatibility | Forward+ (lavapipe), the least |dL\*| of the six places across the outline: over the fluid 19.5 | 19.4 on the tell and 18.0 | 19.0 on the puff, over the pale decor stand-in 25.2 | 23.4 and 24.1 | 23.7 (gate 15; before C5, 2.8 | 10.0, 3.1 | 9.8 and 2.4 to 3.1); the four lane gates pass in both renderers, and the 15 others that passed still pass with the same readings (parity fluid 0.1, cell 0.6). Impact: the lane reads as a pink-lined strip with a navy edge on the fluid; its filled part reads lilac in Compatibility and pink in Forward+, which blends in linear light.
- **Small cues on the fluid (C8).**
  - Hurt vignette (`game/ui/hurt_vignette.gdshader`): the tint goes from (0.55, 0.04, 0.10) to a warm red (0.96, 0.25, 0.04), so r ≥ 3 × b with room to spare, and an outer band adds up to `band` 0.35 more of it from `band_from` 1.0 (the middle of each edge) to `outer` 1.35. The middle of each edge keeps its alpha (0.19 at `VIGNETTE_PEAK` 0.35) and the middle of the screen stays clear; the corners rise from 0.35 to about 0.47. Over the navy fluid a warmer tint alone at 0.35 still blends to a mauve, so the corners need the extra alpha to read red. That puts the outermost band above step 3's "alpha up to 0.35" (`m1-step3-plan.md`, hurt vignette): PROPOSED, for the owner's sign-off; it is still one pulse per hit, with no flash or shake. Look probe, outer band, Compatibility | Forward+: `#733333` | `#753433`, L* 30.0 | 30.6, C* 31.3 | 31.9, h 25.8 | 26.8 (gate 15 to 45; before, 316.0 | 317.9, purple). `tests/test_ui_text.gd` reads the shader's defaults and checks r ≥ 3 × b, a clear middle (`inner` at least 0.5), a band, and `VIGNETTE_PEAK` × (1 + band) at most 0.5.
  - One keyline: `UiPalette.KEYLINE` `#091229` (new `game/ui/ui_palette.gd`) is the outline of the world labels (`feedback_fx.gd`, alpha 0.9), the target ring (0.8), the starving arrow (0.85), the edge arrows' badge and its glyph's outline (`threat_indicators.gd` `BADGE_COLOR`, 0.9), and the strike lane's `key` uniform, which `CreatureView` sets from it. The `HudIcon` outline in the HUD's own panels keeps its teal: it sits on the panels, not on the fluid. `tests/test_pool_view.gd` checks the five share the constant.
  - The badge and the HUD panels, re-checked at 1920 × 1080: the edge arrows ride a track 70 px inside the screen's edges with a badge radius of 37.5 px at the top of its pulse, so a badge can still cover a panel's edge where the track crosses it: 11.2% of the track's length overlaps the status panel, 15.8% the controls panel, 8.2% the points panel and 2.5% the state chip. Unchanged: fix3 draws the arrows over the HUD on purpose (an arrow must not hide behind a panel). It stays an open issue for the HUD layout.
  - The "!" marker's outline: `MARKER_OUTLINE` `#1D3557` measured 1.49:1 (WCAG) against the fluid behind the tell and 1.28:1 behind the puff (plan: lighten under 3:1). It is now the cream highlight `#F4EAD2`: 7.75 | 7.69 on the tell and 9.89 | 9.43 on the puff, Compatibility | Forward+, with the pink glyph 3.05 | 3.03 against its outline (the glyph alone reads 2.5 to 3.2 against the fluid, so the outline carries it). The probe measures it in a new step of the tell and puff scenes (`<scene>_marker.png`: the marker shown and popped, decor hidden, the pixels that change sorted into outline and glyph) and gates `marker_outline` at 3.0 on the tell.
  - Wording: "floor" goes from the comments and test names and messages that described the old floor (`creature_view.gd`, including the "Bodies cast shadows" comment, `test_pool_view.gd`, `play_smoke.gd`, `dev_gizmos.gd`, the lane shader's header); `player_cell_view.gd` had none left after C4. Left as is: `game/systems/carrion_field.gd`'s doc and `creature_brain.gd`'s "floor lane" (the sim and domain are out of this branch's reach) and the history in `pool_look.gd` and one test comment, which name the floor that was removed.
  - Look probe after C8, Compatibility | Forward+ (lavapipe): every gate passes in both but `plankton_clip` (255); the parity gates, which run in the second renderer, read fluid 0.1 and cell 0.6. Lanes over the fluid 19.5 | 19.4 (tell) and 18.0 | 19.0 (puff), over decor 25.5 | 23.4 and 24.2 | 23.7; the starving cell 20.6 | 23.3 dL* against the fluid.
- **Visible sunlit patches (owner question 2, the "yes" version).** The owner's promise is "light shafts over rich food". C7's additive disc could not keep it inside the gates: it was full at the zone's middle, where the lineup's cell feeds, and Compatibility drops faint added light. `zone_light.gdshader` now draws soft shafts of the Sun's cream round each zone instead, on the same disc, mesh, depth (−2.5 m), span (2.6 zone radii) and priority (−2):
  - Shape: a band from 0.45 zone radii out (no light inside it, so the cell and the food in the middle keep their contrast), full at 0.95 (about the zone's edge) and gone at 1.3, the disc's rim, so it shows no edge. Within the band the light falls in soft parallel shafts along the Sun's way across the plane (`ZoneLights.SUN_WAY`, north-west to south-east, from `pool.tscn`'s Sun), spaced by two waves of 2.9 m and 1.7 m so they fall unevenly, a little brighter on the side the Sun shines from, at a phase of each zone's own. Static, so nothing flickers. A ring was measured in round 2 and read somewhat like a target marker; broken into shafts, the band's brightest radius has a lift of 0 between shafts and 9 on them.
  - Blend: `blend_mix` of the cream at an alpha, not added (Compatibility tonemaps each transparent before blending and lost an added 0.025 altogether), still unshaded, `fog_disabled` (it lies just under the plane, and the fog would tint it toward the fluid it lights), `depth_draw_never`, no shadow. Forward+ blends in linear light before the tonemap and Compatibility in sRGB after it, so one alpha lifts the navy about three times as much in Forward+ (0.1: 20.9 L* against 6.4). `ZoneLights.strength_for()` gives each renderer its own (PROPOSED): 0.035 in Forward+ and any other renderer, 0.15 in Compatibility (`PoolLook.COMPATIBILITY_METHOD`), so the brightest shaft lifts the fluid 9.2 | 9.6 L*.
  - Why that strength: it is the most that keeps an ambush hunter 15 dL* clear of a shaft behind it. Measured by strength, the brightest lift and the hunter over it: Compatibility 0.2 → 12.9 and 13.9 dL\*, 0.165 → 10.7 and 15.9, 0.15 → 9.6 and 16.8; Forward+ 0.06 → 14.2 (the tell's lane outline over the fluid also fell to 16.9), 0.045 → 11.4 and 15.0, 0.035 → 9.2 and 17.1.
  - The look probe gains a `sunlit` scene (the cell in the middle of zone z_s, AI frozen) and these gates (PROPOSED). `patch_visible`: the brightest lift, sampled at 0 to 1.3 zone radii along 16 directions on the patches' plane, against the same frame with the zone lights hidden, at least 5 dL\* (9.6 | 9.2). `patch_shafts`: the least lift over the most at the brightest radius, at most 0.5 (0.0 | 0.0; an even ring reads 1). `patch_ambush`: an ambush hunter let in between the camera and the brightest point, at least 15 dL\* against what lies behind it (16.8 | 17.1; body L\* 55.5 | 55.2 over fluid 38.7 | 38.1). `sunlit_cell`: the cell in the patch's middle, at least 15 (18.9 | 18.9). `ambush_contrast`: the lineup's hunter on the centre zone's band, at least 15 (24.7 | 24.3). `lane_on_patch`: the tell's lane lies over z_se's patch, which lifts the fluid under its edge by at least 2 (4.8 | 4.6), so its lane gates are read over a patch: they pass at 19.5 | 17.2 over the fluid and 25.6 | 23.8 over decor.
  - Full look probe, Compatibility | Forward+ (lavapipe), with parity: every one of the 28 gates passes but `plankton_clip` (255). Fluid near the cell L\* 34.8 | 34.5 (C7's disc had lifted Forward+ to 35.7), the cell 18.6 | 18.9 dL\* against it, parity fluid 0.0 to 0.1 and cell 0.6. Draw calls in the lineup 60 | 47, as with C7's disc.
  - The starving tip ("Plankton regrows in the sunlit patches") stays as it is. `tests/test_zone_lights.gd` checks the blend and render modes, each renderer's alpha (Forward+ at most 0.045, Compatibility at most 0.17 and 3 to 5 times Forward+'s), the band (no light within 0.4 zone radii, gone by the disc's rim), the span uniform and `SUN_WAY` against the Sun in `pool.tscn`.
- **Ambience contract, round 3 fixes.** The independent check of round 2 found five mutations of art's scene that passed `tests/test_ambience_contract.gd`. Each now fails the test meant for it:
  - Size (x02, a 12 × 12 m unshaded quad at +2 m, luminance × alpha 0.09, with the Foreground cut to 39). New `test_foreground_meshes_are_small`: a mesh above the swim plane (its top at +0.5 m or higher; instanced layers and particles are items, counted by the 40 cap) must span under `LARGE_M`, 2 m, across. Art's Foreground is a MultiMesh of 2 to 6 cm quads and its backdrops lie 8 m and more under the plane, so art passes. The C6 bullet's reason for the 3 m ceiling now says what the ceiling does and leaves the faint sheet to the size cap.
  - Paintings (x03, a 64 px painting, one blue organism beside one threat-pink one: its mean hue was 44.6 degrees from the pink). An image texture now counts by coverage: it fails when more than 2% (`PAINTING_SHARE`) of its alpha-weighted texels with C\* 12 or more (`PAINTING_CHROMA`, after `brightness`) lie within 25 degrees of a reserved hue. x03 reads 48.4%, x04 (pink only) 100%; art's five paintings 0.000 to 0.018% (colony; measured on the 64 px grid). Control: the blue organism with a 3 × 3 texel pink speck (1.4%) passes.
  - Colours outside the uniforms. A shader's literal colour written to ALBEDO or EMISSION now counts as one of its colours, whether written directly (x05) or through a constant or a local variable (x05b), read as the sRGB colour it draws (a shader's numbers are linear); x05's pink fails the hue test (12 degrees from the threat colour) and the luminance caps (0.404, counted at full opacity since no `opacity` uniform names its alpha). A standard material with `vertex_color_use_as_albedo` counts its albedo times each vertex colour of its mesh, read from the surface arrays, which the headless runner keeps (x08, x08b: pink vertices under a white or grey albedo). Controls pass: a literal navy ALBEDO and blue vertex colours under grey.
  - Particle extents (x07, an emitter at +1 m whose box reaches ±10 m). A particle emitter's heights are now its emission shape's extents (box, sphere or ring, with the shape's offset and scale) merged with its `visibility_aabb`, not its origin: x07 reaches +11 m and fails the ceiling and the plane band. Control: an emitter at +1.5 m with a 0.4 m box and a tight `visibility_aabb` passes.
  - Run on art PR #10 (branch `claude/micro-ambience` at `c77c18c`, which already carries the opacity uniform of `docs/handoff/art-pr10-opacity-uniform.diff`), merged as a tree only into a scratch copy: all 11 contract tests pass, art's own 7 pass, and so does the whole fast suite. The mutations x00 to x09 (the checker's, run again), x05b and the five controls give the expected result each. The conventions are in the contract test's header and in the ambience handoff (project files, `docs/ambience-handoff.md`, "Technical rules"). Art needs to change nothing.
- **The shelter rim in the look probe (round 2's finding: plan section 4 promised it, no frame had it).** New `shelter` scene: the cell sheltered by the sim's grace, as after a start, at (−5.5, 21.45), which puts z_s's brightest shaft behind its edge (the patch lifts the fluid there 6.2 | 5.1 L\*, Compatibility | Forward+), its rim held at mid pulse (alpha 0.175, half way between 0.1 and 0.25), then the same moment with the rim off. Read over the cell's own edge pixels (0.6 to 1.3 of its radius on screen, where the frame differs from the fluid frame): the rim lifts them 2.9 | 8.9 L\* on average and 8.7 | 21.6 at the 90th percentile, the silhouette where the fresnel rim sits; the rimmed edge reads 18.1 | 23.6 L\* above the lit fluid just outside the cell. Gate `shelter_rim` (PROPOSED): the 90th-percentile lift at least 5. The rim is unchanged (cyan, alpha 0.1 to 0.25, never a flash). It adds its light, so Forward+, which blends in linear light, shows it about 2.5 times as strongly as Compatibility; at a frozen mid pulse it is faint in Compatibility, as round 2's check found, and the gate guards that it never vanishes over a lit patch. Also from round 2: `ZoneLights.RENDER_PRIORITY`'s comment now says the lane draws at `CreatureView.LANE_PRIORITY` (8), which C5 made true, and the plan's merge gate (sections 3 and 5) names the four parts above.
- **Palette, docs and acceptance (C9).**
  - Start screen (`game/ui/start_screen.tscn`): the backdrop runs from Fluid light `#4C9BE0` at the top to Fluid deep `#0B2E6B` at the bottom, in place of the teal water. The light end goes on top, as the old gradient did, because the build label sits at the bottom right: its grey text reads 7.9:1 (WCAG) over the deep end and would read about 1.9:1 over the light one. The title reads 3.9 to 4.5:1 (140 px, large text, over 3:1) and the tagline 5.0:1. The menu buttons and the save card keep the theme's dark teal panels; they read, but a blue theme is a UI pass, not this plan.
  - Asset reviews (`tools/godot/capture_asset.gd`): over the fluid. It borrows the pool's WorldEnvironment, Sun, DepthGlow and Backdrop from `pool.tscn` with the renderer's PoolLook profile, in place of the teal background, the key and rim lights and the floor plane. Its close-up looks down about 30 degrees instead of 21, so the Backdrop's far edge (200 m out, 40 m down) stays out of frame as it does in game.
  - ART_DIRECTION (marked for art's sign-off): Fluid deep, Fluid light and Ambient join the palette; Pool teal is retired as a habitat colour and leaves the palette board (`docs/art/renders/palette.png`, re-rendered). Its hex stays in `lookdev.py` as the eye-iris tint that the cell and production scripts use; changing those irises is art's call. The habitat saturation cap no longer covers the fluid; section 3's rule takes its place, with the stored-colour band of `tests/test_pool_look.gd` (hue 268 to 288, at least 83 degrees from the pink) and the on-screen 90 degrees of the look probe.
  - TOOLCHAIN ("Look probe"): the nine moments, the run times (Compatibility about 25 s, Forward+ on lavapipe about 4.5 minutes here) and the final readings and parity. M1.md: row 9 of step 3's Windows checklist, the micro look in Forward+ on the owner's RTX 5070 with three perf tours.
  - Final look probe, Compatibility | Forward+ (lavapipe), with parity, at 70302c9: every gate passes in both renderers but `plankton_clip` (255 | 255). Forward+ passes 28 of 29 and Compatibility 26, where the two parity gates skip. Parity in the lineup: fluid 0.0, cell 0.6 (median CIE76). Across the nine moments: whole frame 0.1 to 0.5, fluid frame 0.0 to 0.1, the fed cell 0.6 (1.4 in `shelter`) and the starving cell 4.7, whose grey is a transparent overlay. The largest transparent difference is the shelter rim, 8.7 | 21.7 dL\* on the brightest tenth of the cell's edge. Frames: `screenshots/micro-world/engineering/final_compatibility_<scene>.png` and `final_forward_plus_<scene>.png` in the project files, for lineup, tell, puff, rim_north, rim_south, starving, hud, shelter, sunlit and sunlit_ambush (the hunter over the patch's brightest shaft).
- **Final audit (2026-10-23, after a container restart).** Steps 1 to 7 re-checked against the branch at `9afd690`: every line that either side of the `m1-threats` merge added since their merge base is in the merge, and `game/systems` and `game/domain` match `m1-threats`. The Compatibility probe at `9afd690` reads exactly as at `70302c9` above.
  - The ambience contract, re-run in a fresh scratch copy of the branch with art PR #10 merged as a tree only (`claude/micro-ambience` at `c77c18c`, which is `24ca885` plus `docs/handoff/art-pr10-opacity-uniform.diff` and one comment): all 11 contract tests and art's own 7 pass, and so does the fast suite (552 tests). `24ca885` with the handoff diff applied passes the same; without it, only the pale-decor test fails (the Foreground counts 0.553 against 0.12). The mutations x01 to x09 and x05b each fail the test meant for them again and the five controls pass. Art needs to change nothing for the contract.
  - The look probe with art PR #10 mounted: `skirt_edge` read 6.5 against 6 in Compatibility, as in round 1. One of art's backdrop organisms lies across the sampled column down the north wall (L\* 29.6, then 35.7 for three samples at y −22 to −23 m, then 29.2): decor in front of the wall, not a lower edge on the skirt. `rim_north` now reads the skirt from the fluid frame with the pool's `Ambience` hidden too (`rim_north_wall.png`, taken only when an ambience is mounted), so without art the probe reads as before in both renderers. With art mounted, every gate then passes in both renderers but `plankton_clip` (Compatibility | Forward+ with parity): skirt 3.2 | 2.6, fluid near the cell L\* 34.8 | 34.9, the cell 18.6 | 18.5 dL\* above it, lanes over the fluid 19.5 | 17.2 (tell) and 18.0 | 18.3 (puff), the lineup's hunter 24.4 | 22.8, parity fluid 0.1 and cell 0.6. Against the same run without art, Forward+'s puff lane loses 2.0 over the fluid and 0.7 over the decor stand-in and its hunter 1.5; every other reading moves by at most 0.4 (the vignette's hue by 1 degree). Draw calls in the lineup 71 | 58 (60 | 47 without art). So once art's PR lands, the look probe still passes everything but plankton clipping.
- **Ambience contract, round 4 fixes.** The independent check of round 3 found that `tests/test_ambience_contract.gd` judged size only for a `MeshInstance3D` and read nothing of a sprite. A `Sprite3D` veil 12 m across at +2 m with modulate alpha 0.15 (y01, x02's sheet drawn as a sprite) passed all 11 tests, and in the Compatibility probe it lifted the fluid near the cell to L\* 43.2 (gate 36) and cut the cell to 15.2 dL\*; so did a threat-pink `Sprite3D` 10 m across at −15 m (y02), and a 12 m quad, or forty 3 m quads, in a MultiMesh at +2 m (y03, y03b). Each now fails the test meant for it:
  - Size: `test_foreground_meshes_are_small` becomes `test_foreground_items_are_small`, over every geometry instance above the swim plane (its top at +0.5 m or higher, or instances the runner cannot place). An item's size is its largest extent in any direction, scaled as its node is: a mesh's box; a sprite's rectangle (`get_item_rect()` × `pixel_size`, laid on its axis as `SpriteBase3D` lays it, and a billboard by the engine's cube round it); one instance's mesh for a MultiMesh; one particle's draw meshes × its emitter's largest scale (`scale_max` × the scale curve's top). Each stays under 2 m. Convention (headless, the instance transforms cannot be read): an instanced layer's shader draws each item at its mesh's size or smaller, as art's `drift.gdshader` draws its 1 m quad at 2 to 6 cm in the Foreground. The large-billboard budget now counts the same items (each instance or particle of 2 m or more once), and the stacking check takes sprites.
  - Sprites: a sprite is read as the material the engine builds for it, a standard material with its texture times its modulate (the modulate's alpha is its opacity), see-through unless it is opaque or cut out, at its own render priority, with fog; an animated sprite gives one per frame. The hue, luminance, priority and fog checks therefore see it. A standard material's albedo texture is now judged times its albedo, as it draws, and the albedo alone only when there is no texture.
  - Readable nodes: decor draws with meshes, MultiMeshes, particles or sprites. Anything else under the ambience (a `Label3D`, a CSG shape) fails `test_nothing_costly_or_banned`, and so do a `Decal` (it would project onto the cell), a fixed-size sprite (no size in the world) and a sprite without the depth test (it would draw over the cell).
  - The check's two colour and reach lows: a shader that reads `COLOR` now counts its mesh's vertex colours (y04, threat-pink vertex colours drawn by `ALBEDO = COLOR.rgb` at alpha 0.1); a MultiMesh's instance colours, which the headless runner reads as black, fail with a note to carry decor colour in uniforms. A `CPUParticles3D` now reaches as far as its fastest particle travels in its lifetime (`initial_velocity` × lifetime + ½ × its strongest linear, radial or tangential acceleration × lifetime²), plus its gravity's fall; in 4.7.2 it also has a `visibility_aabb`, merged when set. Its own colour and ramps count as a process material's.
  - Found on the way: the headless renderer gives no shader defaults (`RenderingServer.shader_get_parameter_default` returns null for every uniform), so a colour uniform the material leaves at its declared default was never read: a quad whose shader draws `uniform vec4 tint : source_color` declared threat pink, never set, passed (y15). A default is now read from the shader's code (a number or a vecN of numbers), and a uniform declared without one is zero, as in GLSL.
  - Run on art PR #10 (`claude/micro-ambience` at `c77c18c`) merged as a tree only into a scratch copy: the contract 11 of 11, art's own `test_ambience` 7 of 7 and the fast suite 552 tests, 0 failed. 37 mutations and controls of art's scene, each on a fresh copy: the checker's y01 to y05 and the earlier rounds' x00 to x09, x05b, c01 to c05, v0 and v1; and mine, y06 (a CPU emitter at +1 m whose 3 m/s particles reach +4 m), y07 (a `Label3D`), y08 (pink instance colours), y09 (a sprite without the depth test), y10 (a white sprite modulated threat pink), y11 (a 3 m billboard sprite at +2 m), y12 (a pink CPU emitter), y13 and y14 (GPU particles drawing 3 m quads, or 1 m quads at scale 4, at +1.5 m) and y15. Each mutation fails the test meant for it, the seven controls pass (c06, a 1 m sprite at +2 m with the Foreground cut to 39; c07, a slow CPU emitter at +1.5 m), `24ca885` fails without the handoff's opacity diff and passes with it, and no run has a SCRIPT ERROR. Art needs to change nothing. The conventions are in the test's header and in the ambience handoff (project files, `docs/ambience-handoff.md`, "Technical rules").
- **The round 3 check's other lows.**
  - Hurt vignette test: `tests/test_ui_text.gd` checked r ≥ 3 × b, which the plan asked for, and it passed the old tint (0.55, 0.04, 0.10), the one that read purple over the navy fluid, and a purple (0.6, 0.05, 0.19). The test now also blends the tint at the corners' alpha (`VIGNETTE_PEAK` × (1 + band), 0.47) over the fluid in the corners as the look probe reads it in its hud scene (`#072A55`; `#082A55` in Forward+), in sRGB as both renderers blend the 2D layer, and asks for LAB h 15 to 45, the probe's `vignette_hue` gate. Today's tint lands at `#773432`, h 28.6 (the probe reads h 24.8 | 24.9 on screen, over a whole corner); the old tint at h 338.8 and the purple at 333.2, and both mutations now fail.
  - Art's production log (`docs/art/production_m1.md`) still listed `pool_floor` in its asset and budget tables and credited the CC0 sand scan to the deleted `assets/export/T_PoolFloor_Normal.png`. An engineering note above the tables now says the micro look retired the floor (C4), that the `pool_floor` rows are history, not budget, and that the Aerial Beach credit covers only the kept source scan in `assets/source/textures/cc0/polyhaven_aerial_beach_01/`. The rows themselves stay as written: art PR #10 edits the rock rows next to each of them, and a change there would conflict with it (checked with `git merge-tree`); art can drop them in its next pass.
- **Final gates after round 4 (2026-10-23).** Nothing that draws changed in round 4 (the contract, a unit test and the docs), and the look probe at `14d6337` reads value for value as at `d014a20` in both renderers: every gate passes but `plankton_clip` (255, art's), 26 of 29 in Compatibility (the parity gates skip there) and 28 of 29 in Forward+ with parity (fluid 0.0, cell 0.6). The `final_` frames in `screenshots/micro-world/engineering/` were re-shot from these runs; against the earlier set only the HUD's random lineage id differs.

## 2026-10-23 · Steam store prep drafts (PROPOSED)
Drafts for a Steam presence live in `docs/store/`: store copy and tags, capsule concepts, a trailer plan and the
Steamworks steps only the owner's account can do. Nothing is published. Store material never names other games and
describes only what the build contains. The capsule concepts are crops of a Blender key art render of the approved
mood scene (`tools/blender/render_store_keyart.py`); `tools/store/make_capsules.py` uses Pillow as marketing tooling
only, never as a game dependency. Open for the owner: the player-facing name (see "Product name"; existing Steam games
called *Pangea* argue for a distinctive subtitle), the release model, individual or company, and the AI-content
disclosure wording.

## 2026-10-23 · Menus and UI pass: settings, save slots, controller, title (scope CONFIRMED by owner direction; details PROPOSED)

The owner asked the studio to run a Menus and UI department (2026-10-23 07:31, approving the coordinator's list: "title screen, settings, save slots and controller support"). That widens M1's "1 save slot" cap (scope caps above) to three slots; the save schema is unchanged.

- **Settings are account settings, apart from run state** (Bible 18): `user://settings.cfg`, written by `SettingsService` (temp file and rename), checked by `GameSettings` against a spec (a bad or missing value falls back to its default and is logged as a warning). IMPLEMENTED.
- **What the settings cover** (Bible 19): display mode, vsync, frame cap, 3D resolution, MSAA; master, music, effects and ambience volumes (by bus name, a missing bus skipped; the sound thread adds the layout) and mute in the background; zoom speed, invert zoom, stick deadzone; every rebindable action per device (keyboard and mouse, controller) with a swap when an input is taken; text size 100, 115 or 130% (scales every font size in the theme); reduce camera motion; reduce flashing (the hurt vignette at 40%); growth trigger (auto or press Grow, read by S2); pause on focus loss. Subtitles wait for the first spoken lines. IMPLEMENTED, values PROPOSED.
- **Save slots**: `user://saves/slot_1.json` to `slot_3.json` (`SaveSlots`). Slot 1 is the old default file, so an existing lineage appears there. The chosen slot is remembered in the settings; `--slot` still overrides it. Delete asks first with Cancel focused and removes the save and its backup, keeping any `.corrupt-*` file. IMPLEMENTED.
- **Controller**: defaults in `project.godot` (left stick and d-pad swim, RB/LB zoom in/out, Menu pauses, Y grows; `grow` also on G for S2). Menus add A (choose), B (back) and the left stick at runtime because the engine's `ui_accept`/`ui_cancel` have no controller buttons; LB/RB (Q/E on keys) change settings tabs. Hints and the pause menu's controls name the inputs of the device used last (`InputPrompts`). IMPLEMENTED; not tested with a physical controller yet.
- **Look**: the theme moves from teal to the deep-blue palette (navy panels, blue borders, amber focus and primary buttons kept). The title backdrop is a procedural shader (light shafts and drifting motes, original), slowed to 15% by Reduce camera motion. PROPOSED; the owner judges the look.

## 2026-10-23 · A live title world (direction CONFIRMED by owner; look PROPOSED)

The owner asked for menus that feel like Spore's "but Pangaea style" (2026-10-23 08:08). Nothing is copied: the feel
(a living scene behind the menu, playful motion) is the brief, and the layout, art and motion are our own.

- **The title is a live 3D scene** (`TitleWorld`): the pool's own environment, lights, backdrop and ambience, art's
  landmarks and shells in the haze, and the saved cell swimming lazy figure-of-eight loops with the game's own
  Locomotion, plus two other starting bodies in the distance. A slow camera drift (15% under Reduce camera motion).
  With no save, a grazer swims there. It only draws; it never touches a save or the sim. IMPLEMENTED.
- **The New lineage picker puts the picked body in the world** (it pops in), replacing the small preview box; the big
  Continue card becomes a translucent nameplate beside the cell. The 2D backdrop shader stays as an unused fallback.
  IMPLEMENTED.
- **Playful motion** (`MenuBounce`): title buttons are pills that swell with a little overshoot when focused or hovered
  and squash when pressed; views slide and fade in with their buttons arriving one after another. Reduce camera motion
  removes the overshoot and the slide. IMPLEMENTED; the owner judges the look.
- **The same touch everywhere** (2026-10-23, after the owner's go-ahead to continue): the pause menu, settings and save
  slots use MenuBounce too and fade in (fade only, so a dim never uncovers an edge), and under them the title's menu
  fades out so only the sea shows. A "dive" into the pool on Continue was considered and left out: the pool opens at
  once (the smokes and session code expect it) and already fades in. IMPLEMENTED.
- **Accessibility audit fixes** (`docs/accessibility-audit.md`, 2026-10-23): with Reduce flashing on, the player's and
  rivals' hit flashes swell in and out at 40% instead of jumping to full (the flinch and squash still show the hit); the
  starving arrow's label follows Text size; the settings footer reads Change, Select and Back from the input map for
  the device in use, and Q / E or LB / RB for tabs stays fixed menu navigation. IMPLEMENTED.

## 2026-10-23 · Cell-stage audio (PROPOSED)

M1 step 5's "real audio", built by the sound and music thread while engineering builds S1. Every sound is PROPOSED until Joshua listens; a listening preview (about two minutes of title, feeding, a hunt, starving, death, respawn and the endless-world stings) is in the project files at `pangaea/audio/cell_audio_preview.mp3`.
- **Sources.** The in-game effects and ambience are original: `tools/audio/make_cell_audio.gd` renders them from code (`game/scenes/audio/audio_synth.gd` holds the effect recipes and the signal blocks: bubbles after van den Doel's model, FM glass bells, Karplus-Strong plucks, formant voices, filtered noise). No samples, so nothing to license and nothing from Spore. The three UI clicks are Kenney's Interface Sounds 1.0 (CC0, `https://kenney.nl/assets/interface-sounds`), unmodified, logged in their records. No new dependency: the generator runs on the pinned Godot.
- **Files and records.** `assets/audio/{sfx,ambience,music,ui}/`, one record per file in `assets/records/audio/` (generator or third-party source, licence, bus, loop, length and, for every effect, its visual equivalent, Bible 20). Effects are mono 44.1 kHz; ambience is stereo 22.05 kHz to keep the repo small (about 41 MB in all with the music), which suits the muffled underwater sound. Godot imports them with its default QOA compression. Loops get a `.import` with a forward loop; the generator writes it only when none exists.
- **Mixer.** `default_bus_layout.tres`: Master (a −0.5 dB hard limiter), Music (a low-pass the soundtrack closes, then a wide hall), SFX (a small wet room), Ambience. All sit at 0 dB; the mix lives in the players, so the settings menu can own the bus volumes by name.
- **CellAudio** (`game/scenes/audio/cell_audio.gd`, the pool's `Audio` node) keeps the placeholder's cue API (`play`, `play_at`, `configure_tells`), so `pool.gd` changed only the node's type. New: 1 to 3 variants per effect (never the same twice running) with a little pitch jitter, the cell's death (`player_die`), a whoosh on every strike, a cancelled tell that stops that creature's growl and lets air out, a swim whir that follows the cell's speed, and a bed plus a detail layer per region (sunlit, reef, drift) crossfaded on S1's `tile_entered`, with a sting for a new region and a swell for a rare set piece. Cues for S2's growth (`grow_warn`, `grow`, `growth_ring`, `now_food`) are ready to call. Those cues come from the pool's `sim_event` signal, not new routing in `pool.gd`. Tell sounds still last exactly as long as the data's tell: a length other than the rendered file's is re-rendered at load.
- **Soundtrack** (`game/scenes/audio/soundtrack.gd`, in `main.tscn`, so the music carries from the title into the pool). Joshua heard the first, synthesized score and asked for "beautiful instrumentals" like Spore's (2026-10-23 08:09), so the music is now composed CC0 tracks by human composers from OpenGameArt, all uploaded before 2024 (so no AI-generated music to disclose), each logged in its record: title *Magic Space* (codemanu), looped; a shuffled calm playlist of *Another August* and *Aquaria* (The Cynic Project), *Drifting* (some-weirdo) and *Nautilus* (poinl), with 4 to 9 s of rest between tracks; danger *Frenzied Swimming* (ShoninyasTube), looped, faded in within about half a second when a creature notices, tells at, strikes at or hits the cell and held 6 s, with the calm track kept quietly underneath so it resumes where it was. Starving (calm −4 dB, low-pass 1.1 kHz), dead (−8 dB, 550 Hz) and the pause menu (1.8 kHz) muffle it. Nothing in it is a fixed motif yet: Bible 20's "music grows with scale and keeps its motifs" waits for a composed theme. A sampler of all 11 candidates is in the project files (`pangaea/audio/music_candidates_sampler.mp3`); swapping a track is one line in `soundtrack.gd` plus its record. `CellAudio.set_size` is kept for per-size playlists.
- **UiSounds** (`main.tscn`) hooks every button and slider that enters the tree: hover (mouse, or focus moved by keyboard or gamepad), press, and back for Back, Cancel, Resume, Close and Quit. A control can opt out with the meta `silent_ui` or pick its sound with `ui_sound`.
- **Placeholders.** `placeholder_audio.gd` and its 14 inventory entries are gone; `tests/test_placeholders.gd` now checks no audio placeholder comes back. `tests/test_audio.gd` checks records against files, the cue table against the synth, loop modes, lengths and loop seams, peaks (none above −0.9 dBFS, none near silent), repeatable renders, the bus layout, the moods and the UI sound rules.

## 2026-10-23 · Endless cell world: "Now, full" (CONFIRMED) and the S1 build decisions (PROPOSED)
The owner chose decision 1 of the endless cell plan (`docs/endless-cell-plan.md` in the project files) on 2026-10-23 at 03:27 UTC: **"Now, full (four sizes in M1)"**. CONFIRMED. The cell stage becomes an endless sea that the cell grows through; M1 ships its first four sizes. The builds are E0 (get ready), S1 "The sea goes on", S2 "First growth", S3 "Bigger and bigger", S4 the editor and generations (the old M1 step 4), S5 real art and S6 acceptance, so the editor comes in the fifth build. Every step ends in a Windows build the owner can play. The engineering plans are `docs/s1/s1-interfaces.md` (the spine) and `docs/s1/s1-core.md` in the project files.

- **The four M1 brief changes approved with it (CONFIRMED, 2026-10-23 03:27 UTC).** They amend the "M1 'First life' brief approved" entry above:
  1. Today's pool is no longer the whole world. It becomes the home block at the centre of an endless sea, unchanged inside (scope cap 1's "one tide pool about 80 m across").
  2. M1 has more than its limit of two kinds of threat (scope cap 1's "2 threats"). S2 and S3 add six creatures; five reuse the two threat bodies and their attacks.
  3. The save records the cell's size. S1 keeps schema v2, whose three-number position now means absolute micrometres (am) written in float64; S2 brings schema v3 with the size, the growth ring and the absolute checkpoint (plan section E).
  4. The world is put together only from Blender-made pieces on an approved list (`game/data/placement_kit.json`), never from shapes made up by code. A rough Blender piece stands in until its finished version lands under the same id.

  The open question about how the pool's edge should look goes away, because there is no edge.
- **Bible deviation.** The Bible's microscopic era starts "in a readable shallow environment" (section 5). The cell stage is now an endless sea with **ten sizes**, each 1.6 times the last, and today's pool is its home block. The era count, the loop (feed, evade, reproduce, edit) and the acceptance list are unchanged. Plan decisions 2 to 4 are not yet answered, so the build works toward their recommended options, which are PROPOSED until the owner answers: (2) the cell grows automatically at the first calm moment once its ring is full, with press-G built as a switch; (3) ten sizes, of which M1 ships four; (4) at the top the game offers the move to the ocean era, and the player may stay forever.
- **S1 build decisions** (PROPOSED; the spine's section 1, deviations from the plan's wording, not its rules):
  - D-1. New endless sim files go under `game/systems/world/`. `tests/test_sim_purity.gd` scans that whole directory and allows file access only to its four loaders (built in T0.4).
  - D-2. The tile catalog class is `TileCatalog`: Godot 4.7.2 refuses `class_name TileSet` ("hides a native class").
  - D-3. There is no slow CI job, so S1 adds a **soak** tier: `test_soak_*`, skipped by default, run by `tests/run_tests.gd -- --soak` through `tools/check_soak.sh` in a parallel CI job `soak` (75-minute timeout; built in T0.3). The plan's "slow job" items go there; `test_slow_*` stays inside `tools/check.sh`. S1 sign-off needs `soak` green on the final commit.
  - D-4. `game/data/world_cell.json` ships with `"mode": "endless"`. `GameSession` takes a world path (default `""` = pool), so every existing test stays in pool mode by construction. main passes the default path and the `--world=` override; the existing check.sh phases get `--world=pool`.
  - D-5. `home_b0.json` references `pool_m1.json` and `creatures_m1.json` and adds only the seam ring, so pool mode and the home block cannot drift apart.
  - D-6. The kit assets a shell slot can take are derived from the slot radius and the kit's scale ranges, not listed per slot, so adding a finished asset needs no tile edit.
  - D-7. `WorldGen` is an instance binding (world seed, generator version, content), with `chunk(n, cx, cy)` and a per-tile memo that is covered by tests (a hash of six ints costs about 14 µs here).
  - D-8. Think slots go through `CreatureField.think_due`; `creature_brain.gd` is unchanged in S1.
  - D-9. A site is in the site table while its home chunk is loaded; a sleeper's reach-disc chunks (at most 4 at S1) load before it wakes and never unload while it is awake; territory geometry is copied into the site record.
  - D-10. A teleport respawn's unload-all happens behind the camera cut and is exempt from invariant 12 (nothing appears or vanishes in view); everything after it is measured from the checkpoint.
  - D-11. Every respawn, near or teleport, fills at once the zones that touch the new view.
  - D-12. A new endless spawn blocker, "no room": the home lies beyond the wake ring and the sleepers are at their cap.
  - D-13. Endless-only snapshot keys live under one top-level key, `"world"`, and endless-only event fields appear only in endless mode, so pool snapshots and events stay byte-identical.
- **The core design's decisions** (PROPOSED; `docs/s1/s1-core.md` section 1, inside the spine's interfaces), in brief: C-1 the view set is the 3 × 3 chunks round the cell plus every chunk within 11.5 tm of the zoom-max view (measured at most 11 chunks, cap 12); C-2 `ChunkArena` keeps absolute collider centres in float64 and derives local ones by subtracting in float64; C-3 its candidate boxes fall back to the brute-force settle when a position leaves them, so grid and plain results are identical for every input; C-4 a tile site's home lies inside its reach disc, inset by its radius (a new tile rule); C-5 the endless spawn blockers run "near the player", "in view", "not clear", "occupied", "dormant", then "no room" (also when an awake spawn would pass the awake cap); C-6 scripted and siteless debug creatures never sleep; C-7 a sleeper lies still and every other brain forgets it as a target; C-8 `absolute_position_am()` returns the absolute checkpoint exactly while dead or a respawn is pending; C-9 create and a teleport respawn fill every food zone at once, a near respawn only those touching the view; C-10 a teleport respawn drops all carrion; C-11 `food_trimmed` counts transitions; C-12 a tile zone needs 75% of its 0.25 tm grid points 0.7 tm clear of shells; C-13 endless mode refuses the interim carrion supply; C-14 debug creatures take numbers from 2^30 up; C-15 the chunk-digest golden waits for the region-rule answer; C-16 every endless branch tests one flag, so pool mode never builds an endless object; C-17 `resolve_death` and `_is_dirty` are guarded while a respawn is pending; C-18 a broken world file or flag is a data problem in both modes; C-19 `ChunkArena`'s near grids keep per-cell counts, updated on add and remove (a full re-mark costs 1.36 ms a load); C-20 `full_precision` applies to the whole save; C-21 HuntBot keeps its M1 retreat and patrol zones in pool mode, and in endless mode retreats to the nearest unguarded zone and patrols the nearest territorial zones.
- **Measured facts that change the plan's numbers** (Godot 4.7.2 headless and Python, recorded by the S1 writers): the region thresholds that give each region a third are [0.395, 0.605], not [0.42, 0.58] (which gives sunlit 25%); a view set holds at most 11 chunks; Godot's JSON parse returns about 9% of doubles one ulp off even with `full_precision`, so "exact" means "within one ulp" in every save test, and the gate that tells `full_precision` on from off is a one-ulp test, not the 1 µm Continue test; the pinned drift swap leaves about 1.7% drift, which is open question 1 below.
- **E0 as built (T0; IMPLEMENTED).**
  - `WorldHash` (`game/domain/world_hash.gd`): MurmurHash3_x86_32 over little-endian int64 words, seed 0x9747B28C, and FNV-1a 32 for purpose strings, both public domain; no engine `hash()`. `tools/world_hash_ref.py --check` is an independent Python reference that checks 12 published MurmurHash3 vectors, 3 FNV-1a vectors and the 20 goldens; `tests/test_world_hash.gd` pins the same goldens (G23). The spine's note on G23's mutation is wrong: without the high word, rows 2, 6 and 7 collide, and rows 4, 5 and 8, not rows 5 and 6.
  - The golden M1 hashes (plan D.4; G1): three scenarios (the step 2 pool, threats with ForageBot, threats with KiterBot) × seeds 401, 402, 4242 and 77 × ticks 600, 3,600 and 18,000, each with `state_hash()` and the SHA-256 of the same snapshot string, in `tests/fixtures/m1_goldens.json`. Recorded at `986f668` (main) by `tools/godot/record_goldens.gd` and re-run to equality at `ac03f1e` (the plan's recording point) and `e076d3f` (the spine's base), whose sim, data and bots are identical. Seed 401 at 600 and 3,600 ticks is fast (about 4 s), the other seeds slow (about 9 s), all seeds at 18,000 soak (about 60 s). Pool mode stays bit-identical through S1: a differing golden blocks the merge, and the file is never re-recorded to make a change pass, only when an engine upgrade changes `hash()` while every SHA-256 still matches.
- **The S1 bots and gate harness as built (T0.6, T0.7; the numbers are PROPOSED).**
  - **The swim body.** No starting body reaches the 6 tm/s the plan's swims and #28E name: the hunter, the fastest, makes 3.26 tm/s. The fastest legal body, a jaw and three flagella at scale 2 ("racer"), makes 4.41. The straight swims and the cost gates swim the racer and print the speed they reached. `PoolLayout.MAX_SPEED` (6 tm/s) stays the cap the rocks and chunk timings are proven against.
  - **`game/dev/swim_bot.gd`.** A straight swimmer asks for `dir.normalized() * throttle` every tick. A camper swims to its zone's centre and asks for nothing within half the zone's radius, looking the zone up by id each tick so it follows a rebase. A greedy camper (#33) also eats food lying in its zone (the zone's plankton, or carrion inside it) once it has room for half an item.
  - **HuntBot (C-21).** Pool mode keeps `z_center` and `z_n`, `z_ne`, `z_nw`; its output is unchanged (seeds 201 to 206: the same state hashes at 3,600 and 14,400 ticks, the same kills). In endless mode it reads only sites live at the world's size, retreats to the nearest loaded zone whose centre no live reach disc covers, and patrols the 3 nearest loaded zones in a live territory, choosing again on each arrival. On the M1 pool's own data that rule picks `z_center` and `z_ne`, `z_nw`, `z_n`, in that order from the spawn, which is why the pool keeps its constants.
  - **ForageBot and KiterBot.** In endless mode they mind only the awake creatures, KiterBot drops a target that falls asleep, and ForageBot with no zone loaded waits where it is instead of heading for the M1 spawn. The golden M1 hashes prove the pool unchanged.
  - **The gate harness** (`tests/test_endless_gates.gd`). The gates run on the real content once T4.3's tiles exist, on T1's fixture world before that, and print what they wait on while a T2 surface is missing. A fast test fails once the file that marks a dependency is in the tree (`world_content.gd` T1.1, `world_stream.gd` T2.1, `rebase_shift.gd` T2.4, `fuzz_invariants.gd` T2.8) while the harness still misses its surface. With nothing missing, the same test checks that the content has no problems and runs a 120-tick swim with the invariants on.
  - **Soak gates.**
    - Eight directions: 36,000 ticks each, with at least 128 tm covered.
    - The corner circle: radius 3 tm round the first of 8 candidate chunk corners whose circle is clear, held within 8 tm of the corner.
    - #32: from home on M1's seeds 501 to 503, and from 10 points in [-2 km, 2 km]² (point seed 3202, run seeds 511 + i), with M1's thresholds for each body and each start group.
    - #33: in `z_center`, `z_s` and the first 4 tile zones found from 40 probe points (seed 3203) within 24 tm whose centres no live reach disc covers, with M1's checks.
    - Hunter viability: from home on seeds 201 to 206 (5 must pass) and from 10 points (seed 3204, run seeds 211 + i; 9 must pass).
    - F9: 30 points (seed 3209), each a grazer at zero energy, hidden, which must eat within 25 s.
    - G13: two runs of a 10 km swim at 0.25 rad, compared every 18,000 ticks and at the end.

    Together they step about 1.7 million endless ticks.
  - **Cost gates** (`tests/test_endless_cost.gd`, slow).
    - **P99.9** counts each tick at its fastest of the 3 identical runs, as #29's windows do, so a single burst from another process cannot fail it. The median run's own percentile is printed beside it. A dry run on T2's branch with its fake generator, in a scratch copy, read 16.5 yardsticks for one run's own P99.9 and 4.7 for the per-tick fastest; #28E there read 98 µs and 1.45 yardsticks.
    - **The sleeper cost** uses the world's own sleepers after a 1,200-tick swim, because debug creatures never sleep (C-6). It times them against a twin sim with them removed, tick by tick in turn, over 3 rounds of 200 ticks. It needs at least 8 sleepers, and on the fixture world it waits for the real content.
    - **The rebase tick** goes 3 chunks against the cell's side of the origin, so the timed tick holds one rebase and not two.
- **Open S1 questions** (spine section 9 and core section 17; the build follows the working answer in brackets until the owner or the integrator answers): the region rule (keep the pinned drift swap, about 1.7% drift, or a coordinate rule, 14% to 16% [recommended: the coordinate rule]); threat sites on rare tiles [yes, as tile rule 7]; arch landmarks over swimmable water [no overhang outside the 2 bu collider]; whether `--world=pool` is enough for comparing with the old pool [the flag only]; a soak run above 60 minutes [the sample and the seam pairs move to nightly first]; an awake-overflow count above 0 after density testing [lower the site density, as plan F says]; whether #33's endless camper skips the home block's guarded zones [it does]; whether a sleeper keeps its sight memory [it does].

## 2026-10-23 · S1 build plan: the corrections layer, B-1 to B-30 (PROPOSED)
`docs/s1/s1-build-plan.md` (project files) corrects the spine, `s1-core.md` and `s1-content.md`, and wins where they differ. Its ids are cited with prefixes from now on: **B-n** the build plan, **D-n** the spine, **CC-n** core's C-n and **CT-n** content's C-n (core and content both number C-1 to C-21). In the S1 entry above, "The core design's decisions" C-1 to C-21 are CC-1 to CC-21, and D-1 to D-13 are the spine's.

- **Rules it settles.**
  - **The density split** (B-17, from CT-18; G15). On the 20 straight 2 km swims: a zone edge within 9 tm at least every 30 s, and a live site's home within the view ring (33.9 tm) at least every 60 s. The plan's single 30 s gate failed by design. `sample_sites(gen, band, size, center_abs_tm, radius_tm := 40.0)` has one definition (live sites whose reach discs meet the disc, at most 10 at 40 tm); content's "homes within 55 tm" count is withdrawn. Home-ring seeds: 10 slow, 40 soak.
  - **The region rule** (B-11; core Q1, content 17.5). With `max_drift_run` m = 2, a tile whose raw region is drift is sunlit when `posmod(tx, m+1) == m` or `posmod(ty, m+1) == m`; every other tile keeps its raw region. Thresholds stay [0.395, 0.605]. Expected shares: drift about 14.8 %, sunlit 51.9 %, reef 33.3 %; no row or column holds three drift tiles in a row. G15 asserts drift in [0.12, 0.18] and each region at least 10 %. It replaces the spine's swap (about 1.7 % drift), answering open question 1 above.
  - **Home rule 3** (B-2). The seam ring holds 16 to 24 zones with 4 ≤ R ≤ 6 and capacity 8 to 24; every ring zone lies outside `seam_inner_r` (|c| − R ≥ `seam_inner_r`), with |cx| + R ≤ 63 and |cy| + R ≤ 63; ring zones are at least 1.0 bu apart; every home zone, M1's and the ring's, keeps at least 0.7 bu (`ZONE_CLEAR_MARGIN`) from every home collider, ring shells and M1 rocks alike; static #33 holds per zone. `HomeBlock.ZONE_SHELL_GAP_BU` goes from 0.5 to 0.7. G3's mutation is unchanged.
  - **The gap rule** (B-3; replaces CC-12's 75 % clear share). Every zone disc keeps |zc − cc| − zr − cr ≥ 0.7 bu from every collider of its own tile or home block: shells, the landmark anchor collider (r 2.0) and set-piece colliders. It is orientation-invariant, and with pairs across tiles at least 5 bu apart it makes `is_clear(anchor, 0.675)` hold for every plankton anchor whatever is loaded. `PoolLayout.zone_problems` reports each zone under the margin when given circles; the pool path is unchanged. It is never cut.
  - **The hold ring** (B-6). `rings_tm.hold` = 96 (the finding's 120 would break the local bound). Rule 4 adds unload < hold; rule 6 becomes `rebase_beyond + max(unload, hold) + chunk_tm·√2 < local_bound` (237.25 < 256); `WorldContent.problems` adds `rebase_beyond + hold + reach_max + chunk_tm·√2 < local_bound` (248.25 with content's reach of 11). Step 5 opens with a hold pass: an awake creature whose site's reach-disc centre (a siteless debug creature's leash-disc centre) is more than 96 tm from the cell is removed as "unloaded", out of view, and its site refills as a sleeper with no respawn delay. D-9 reads "while a creature is awake **and held**, its reach-disc chunks never unload".
- **Gate mutations that changed** (build plan section 6).
  - G6: "lattice memo keyed by (b, i) without j" (core 16.6).
  - G7: "caps computed before the unloading sites are erased" and "`spawn_site` skips `try_spawn`" (16.3).
  - G8: invariants 12, 13 and 16 with the hold ring; swims overdriven at 6.0 plus one racer run (B-12). "Sleep ring 44 → 30" cannot fail, so the mutations are "trim filter ignores in-view", "dead-state places not excluded" and "hold removal skipped" (16.14).
  - G11: `from_save_abs` truncated to float32, which the 100 km case always catches; `full_precision` false belongs to `test_a_saved_double_reads_back_within_one_ulp` (16.1).
  - G13: the two-run 10 km hash at 6.0 overdriven plus the racer pair; the mutation is "zone stream left unseeded", plus the route test (16.4).
  - G23: the note corrected (16.5): without the high word rows 2, 6 and 7 are equal, and rows 4, 5 and 8, as the E0 entry above found.
- **The rest, in one line each** (the track that applies it in brackets). B-1 rule 8 stays in `WorldConfig.validate`, no silent fallback, T4.3 deletes T1's `T4_CONTENT` allowance [T1, T4]. B-4 stream events follow the field events raised before them and no event after `rebased` carries an old-frame position [T2]. B-5 at the chunk cap a view-set key always loads [T2]. B-7 the saturated cost case [T0.10, below]. B-8 endless create reloads the view set at the placed point [T2]. B-9 an awake spawn loads its site's reach chunks first [T2]. B-10 `_create_endless` and `FakeWorldGen.endless_sim` are the test seam [T2]. B-12 `SwimBot.overdrive` [T0.9, below]. B-13 a slow-tier budget of +150 s (T0 20 s, T1 40, T2 35, T3 5, T4 40, T5 10), fast +48 s, the suite bound 1200 s and CI 40 minutes [T0.8]. B-14 the soak split into `soak-a` and `soak-b`, a nightly workflow only for a job over 60 minutes [T0.8]. B-15 places carry `yaw_deg` and `mirror` [T1, T2, T5]. B-16 `orientation_problems` and `seam_problems`' orientations [T1]. B-17 above. B-18 `docs/TOOLCHAIN.md`, CI and the runner are T0's; spine 2.1 gains T4's and T5's files [T0.8]. B-19 the release probe checks the endless content [T5]. B-20 draw calls ≤ 96 and GPU P99 ≤ the M1 baseline + 2.0 ms on the Windows tour [T5]. B-21 a creature's `seen` memory clears when it falls asleep [T2]. B-23 create-time `chunk_loaded` events stay queued and T5's build is idempotent per key [T5]. B-26 art's kit on main is T4.1 and T4 adds `test_kit_tints` [T4]. B-27 and B-28 the giant husk and the shell cathedral re-authored against the kit [T4]. B-29 a sealed pocket is legal when empty [T1]. B-30 ids and dressings follow the kit [T1, T5]. B-22, B-24 and B-25 are not assigned.
- **The open S1 questions above, answered by the plan.** Region rule: the coordinate rule (B-11). Rare tiles need a live threat site (spine Q1). The arch ships (Q2; CT-8 moot). `--world=pool` is enough (Q4). A soak job over 60 minutes moves the diagonal seams and any sample beyond 1,000 to nightly (B-14). Awake overflow: lower the site density in data first (T4.4), never widen the 40 to 44 band (Q7). The endless #33 camper skips the guarded M1 zones (core Q3). A sleeper does **not** keep its sight memory: it clears on falling asleep (B-21), the reverse of the working answer.
- **T0.9 as built (B-12).** `SwimBot.overdrive(sim)` sets `sim.phenotype.speed` to `PoolLayout.MAX_SPEED` (6.0) and refills the energy; callers apply it before each step, and only tests and soak gates call it (a fast test scans `game/` and `tests/smoke/` for it). On T2's FakeWorldGen, whose lane along y = 9 holds no collider, an overdriven straight swim averaged 6.000 tm/s over ticks 300 to 900 (the gate is ≥ 5.9) and the racer as it is 4.405. The eight straight swims, the 10 km hash and the four cost swims run overdriven, each with one racer run (the cost gates' racer runs are one soak case); an overdriven swim must average more than the racer's top speed. The harness now waits per level: SIM (an endless sim at home), WORLD (also the stream's read API, teleport, rebase and the creatures' endless fields) and ALL (also FuzzInvariants). G13 reads no invariant and runs now on T1's fixture world: 33 s a run overdriven, 45 s for the racer. With the zone stream's seed line deleted in a scratch copy, 0 of 6 overdriven and 0 of 8 racer records matched.
- **T0.10 as built (B-7, core Q3).**
  - **The saturated case.** `DenseGen` in `tests/test_endless_cost.gd` is T2's FakeWorldGen with 3 zones (the fake's radius 5 and capacity 40) and 9 rammer sites a chunk. RACER swims overdriven east along y = 16 for 1,200 ticks, then 600 timed ticks, 3 runs. At the median timed tick the awake cap is full (12, of them 8 in view), the sleeper cap full (30) and the food at 117 of 120 (the rammers eat and the zones regrow); 23 chunks and 207 site records are loaded, about 10 chunks load during the timing, and `awake_overflow` reaches about 290 over a run.
  - **Measured** (2026-10-23, load 2 to 6 in the shared 4-CPU container; the yardstick reads about 70 µs here): the median tick is **20.0 to 22.0 yardsticks** (1,400 to 1,600 µs) in the median run and the chunk-load ticks **31 to 55** at their fastest of 3, against B-7's 10 and 16. B-7's remedy, `caps.awake` 10, tried in a scratch copy, read 19.9. The case therefore fails B-7 by about twice, and the remedy does not close it.
  - **The rows for core 10.1** (the same swim, one process each, instrumented in a scratch copy): the swim with no zones and no sites 85 µs (1.3 yardsticks); with the dense zones and food at the cap (69 zones loaded, 120 items, the food trim running every tick) 460 µs (6.8), so **food at the cap costs about 5.5 yardsticks**; **30 sleepers cost 2.0 µs each** (rounds 2.0, 0.8 and 2.0), about 0.9 yardstick; the 12 awake rammers with their 207 site records and about 165 waiting spawn retries take the remaining **14 or so**. By phase, in mean µs a tick: the stream's step 470 (246 of it with no creatures), the creatures' brains 588, spawn retries 177, plankton 202, creature moves and contacts 114, combat 89.
  - **How it is gated.** Asserting B-7's limits in the slow tier would stop every `check.sh` until the cost or the budget changes. So the slow case `test_slow_a_saturated_world_fills_its_caps_and_prints_its_cost` asserts that the three runs time the same ticks, that chunks load during them and that the caps are full (awake 12 with at least 6 in view, sleepers 30, food within one zone's worth of 120), and prints the rows with its verdict; the soak case `test_soak_a_saturated_world_costs_at_most_10_yardsticks_a_tick` asserts B-7's limits and fails in `soak-a` until that is settled. The limits are not loosened. Settling it is for T2 (the stream's step and the spawn retries), T1 (the caps) or the integrator and the owner (the budget).
  - **A hang the case found in the stream (T2).** `WorldStream._sleep_and_wake`'s eviction loop never ends when a tick needs two evictions: the evicted sleeper stays in the loop's list, still asleep and still the farthest, so it is picked again, `CreatureField.remove` returns at once because it is gone, and the count never falls. In a scratch copy of this tree, two calm creatures moved past the sleep ring on the same tick with the sleepers at their cap made `step` never return (stopped after 120 s). Two awake creatures falling asleep in one tick at the sleeper cap can happen in play. Three of T0.10's mutations hung on it before the loop was guarded in their copies.
  - **The #33 camper** (core Q3). T0.6 already excludes the guarded M1 zones: the endless camper's home zones are M1's #33 zones, `z_center` and `z_s`, and a fast test pins that no M1 territory zone (`z_n`, `z_nw`, `z_ne`) is among them.
- **T0's gates on T2's latest tree** (`e8a055b`: T2.7 added `tests/fuzz_invariants.gd`, so nothing waits any more). Merged into this worktree for a trial and not kept, because its `check.sh` fails the rebase gate (below); T0 merges T2 again once that passes. On T1's fixture world, in the shared container:
  - **Soak, `test_endless_gates`** (739 s in all). The eight overdriven swims averaged 5.87 to 5.99 tm/s and the racer 4.38, with every invariant clean and `awake_overflow` and `chunk_waits` 0 (about 22 s a swim). The corner circle loaded 6 chunks and nothing late. #32: no death in 130 minutes. #33: every camper ran dry, after 175 to 332 s. Hunter viability: 6 of 6 seeds from home and 10 of 10 points. G13: 6 of 6 and 8 of 8 records equal. **F9 failed**: 6 of the 30 starving grazers died before eating, a question of the fixture world's food density, to be run again on T4.3's tiles.
  - **Cost, `test_endless_cost`.** #28E: 4.56 to 4.88 yardsticks overdriven (251 to 356 µs), 4.97 for the racer. P99.9: 14.40 to 16.06 overdriven (16.06 at load 5.6; 14.40 at load 2) and 15.57 for the racer. **The rebase gate fails**: a rebase tick costs 2.84 to 4.38 yardsticks more than the tick before it overdriven and 2.63 for the racer, at loads 1.2 to 5.6, against 2; T2.6's tree, before the hold pass, read 2.84 too. Core's estimate was 160 µs, 1.6 yardsticks of a 100 µs yardstick; the yardstick reads about 70 µs here. **The sleeper gate fails for the racer**: 8 sleepers at 6.0 µs each against 2 (the overdriven run leaves 7 sleepers, under the 8 it needs, and waits for the real content). Both are T2's to bring under their limits; the limits are not loosened.

## 2026-10-23 · S1 integration: the gate harness plays as a player would (PROPOSED)
G16's runs from points (#32 and hunter viability) failed on the real content for reasons in the harness, not the sea. The gates' thresholds are unchanged; the harness fixes leave the content untouched, and the content fix at the end of this entry changes only the band 0 tiles.
- **Arrival.** A run from a point used to teleport onto it. M1's spawn rule (`CreatureField.blocker_from`: no site spawns within `spawn_safe_m` of the cell or in its view) then kept every site round the point empty for as long as the cell stayed near, which a forager or a hunter does (seed 513 at (−1258, 162): rammer sites 5 and 12 tm off, an ambush lair 21 tm off, none ever spawned). Now `arrive()` places the cell 100 tm out (beyond the 56 tm load ring from every site in view of the point) on a bearing drawn from seed 3210 + the run seed, and it swims in, hidden and kept fed, with a new homing `SwimBot.toward(abs)` until within 2 tm; the timed run then starts with the energy the cell had. A run whose arrival ends more than 10 tm off fails. Arrivals take 31 to 38 s.
- **HuntBot roams the endless sea** (beside CC-21, which stands; pool mode is unchanged). After arrival alone the hunter still starved at 7 of 10 points: having eaten the rammers round it, it ping-ponged between the two nearest territory zones, which kept the dead rammers' sites in its view so they never respawned (4 points); with no territory loaded it held still (1 point); or it wedged in a crack between shells (2 points, below). In the endless world, with no rammer awake to hunt, it now swims for the nearest sleeping rammer (it wakes inside the 40 tm wake ring), and with no rammer alive in the loaded ground it heads home, where the arrow points, hunting what it meets. CC-21's patrol is used only while some rammer lives but none can be hunted.
- **SwimBot.Unjam.** `route_point` goes round the nearest collider on the side the line passes; where shells stand in a row closer than the body is wide, that leads into the crack beside the next one and the cell stays put (the M1 rocks have no such crack). A bot that, touching a collider, moves less than 0.3 tm in 60 ticks steps aside along the row to a point 6 tm to one side of its line (alternating sides, 6, 6, 12, 12 … tm), then heads on. HuntBot's endless travel and the homing swimmer use it.
- **Numbers** (2026-10-23, the merged `s1`, the gates' own run functions, load 1.3 to 3). #32 from points, met a threat in every run: grazer 7 of 10 before, **9 of 10** after; omnivore 6 of 10 before, **8 of 10** after; meetings a minute 4.3 and 4.6 before, 6.3 and 6.7 after; no death, no starvation. Hunter viability from points: 1 of 10 before, **10 of 10** after (arrival alone: 3 of 10; with roaming: 8; with Unjam: 10); from home 6 of 6 before and after.
- **What still fails is the content's** (T4, T1). #32 at (1635, 302) for both bodies and at (−174, −1729) for the omnivore: in 300 s the forager never comes within a threat's notice range. At (1635, 302) only ambush hunters live near (2 to 5 awake, 10 to 14 asleep), lurking 10 to 40 tm from the zones it eats in, and the rammers sleep 44 to 93 tm off; at (−174, −1729) the omnivore grazes westward between rammer territories (rammers awake 24 to 34 tm off) where the grazer, from the same point, wandered into them (31 meetings). The gate wants a meeting in every run, M1's #32, so it fails until the content or the gate's promise for the open sea changes.
- **#32's content fix** (PROPOSED, T4). Only the band 0 tiles change; the gate, the harness, the regions, the site rules and the home block do not. First, an ambush hunter notices a cell only within 6.5 tm of the lair it lurks at, and 18 lairs (in the six reef tiles, the giant husk, sunlit_a, sunlit_b and sunlit_e) stood 5.2 to 8.7 tm outside the rims of the meadows they watch (3.7 to 7.3 tm from the nearest zone of any kind), so a forager could graze a whole meadow unseen. Each lair now waits 2 tm outside its meadow's rim, facing the meadow's centre. Every site still keeps rules 8 to 10 (the least inset slack is 1.05 tm and the least anchor slack 3.94 tm, against 1.0), and the worst 40 tm disc still holds 10 sites. Second, 25 gaps between reef shells were narrower than 1.5 tm (the narrowest 0.42 tm; a cell is 1.0 tm across), and a forager that wandered into one wedged there and starved (2 of 60 runs from 30 tuning points). Moving 21 shells by 0.1 to 5.9 tm opened every one, so no two colliders in a tile now stand closer than 1.5 tm. Drift still has no sites (rule 7): a forager that starts in drift leaves it for food within a few minutes, and from 20 drift points both bodies met a threat in every run.
- **Numbers after the fix** (2026-10-23, the gates' own run functions). #32 from points: grazer 9 of 10 before, **10 of 10** after; omnivore 8 of 10 before, **10 of 10** after; meetings a minute 6.3 and 6.7 before, 6.8 and 7.6 after; the fewest meetings in a run 0 before, 13 and 7 after; no death, no starvation. From home nothing changes: 3 of 3 for both bodies, 14.3 and 3.9 meetings a minute. A hold-out of 20 fresh points (point seed 7717, run seeds 7800 + i), which is not a gate: 19 of 20 before and **20 of 20** after for both bodies, meetings a minute 4.6 and 5.2 before and 6.2 and 6.3 after, the fewest in a run 0 before and 10 and 9 after. Hunter viability (6 of 6 from home, 10 of 10 from points), #33 (every camper runs dry, with no meeting), F9, the straight swims, the corner circle and the 10 km hash still pass, and the sleeper cost gate still finds 10 natural sleepers after 1,477 and 1,973 ticks. Still thin: the omnivore from home on seed 503 meets the home block's ambush hunter only once in 300 s; in some arrangements a zone of sunlit_a lies 33 tm from any threat's reach; and in the shell cathedral about one zone in ten is more than 30 tm from one.
- **The sleeper cost gate swims on.** Its 1,200 ticks east left 6 or 7 of the world's own creatures asleep (debug creatures never sleep, CC-6), under its 8. It now swims at least that long and on east until 10 sleep, at most 4,800 ticks: 10 after 1,477 ticks overdriven and 1,973 as it is, about 145 tm out. The 2 us limit stands; the gate reads 10.9 and 12.2 us a sleeper and fails until the perf work lands. F9 on the same content: all 30 starving grazers eat, the slowest after 10.4 s of its 20.

## 2026-10-23 · S1 cost gates: rebase and sleeper ticks at their fastest of 3; B-7 carried into S2 (PROPOSED)
The G17 rebase and sleeper gates in `tests/test_endless_cost.gd` now measure the way #28E and P99.9 already do: identical deterministic runs, each timed tick counted at its fastest. One burst of load from another process no longer fails them. Only the measurement changed. Their limits (2.0 yardsticks; 2.0 µs a sleeper), what they time, the game code and the game data are as they were.
- **Rebase.** The gate timed 20 rebase ticks, each against the plain tick before it, in one run, so a burst on either tick moved the excess: single samples ran from −1.9 to +34 yardsticks, and 6 of 14 recent readings were over 2 under load, against about +1.4 to +1.6 quiet (+1.5 at the perf merge, `48d0542`). Now 3 runs time the same 20 rebases, and their end hashes and kept tries are checked equal. The rebase tick and the plain tick each count at their fastest of the 3, and the median excess over the 20 must stay at most 2.0. Beside it the gate prints the median run's own median, which is the reading the old gate gave.
- **Sleeper.** Its 3 rounds ran on in the same twin sims, so each round timed 200 later ticks, and a burst on either sim moved that round (rounds like 2.40, 4.90 and 5.60 µs under load, against 1.0 to 1.4 quiet). Now each round builds the twins afresh, so the 3 rounds time the same ticks, and both sims' end hashes are checked equal. Each tick of each sim counts at its fastest of the 3, and the difference of the two sims' median ticks, per sleeper, must stay at most 2.0 µs. Every round's own reading is printed as before.
- **Measured** (`s1-gates`, `test_endless_cost` alone, 16 runs at load 2.1 to 4.0 with six other builders in the 4-CPU container; 8 runs on `7593ec8` and 8 after merging #32's content fix, which moves neither gate). In alternating A/B probes at load 2.7, the rebase gate read 1.76 to 2.56 on the old tiles and 1.94 to 2.45 on the new.
  - Sleeper: **0.30 to 2.30 µs, over 2.0 in 1 of 16 runs** (2.30 at load 3.4). Each round's own reading, as one round of the old gate read it, ran 0.40 to 3.80 µs; the median round, the old verdict, was over 2.0 in 9 of 16.
  - Rebase: **1.75 to 2.65 yardsticks (median 2.12), over 2.0 in 11 of 16 runs**. Each run's own median, the old reading, ran 1.82 to 4.35 and was over in 40 of 48.
  - #28E read 4.05 to 4.31 yardsticks and P99.9 12.55 to 15.85; both pass.
  - The racer's soak case, once at load 2.1: sleeper 0.90 µs, rebase 2.36 yardsticks.
- **What the method cannot remove.** Every yardstick reading in the file sits 20 to 40% above the perf merge's at every load seen today, 1.1 to 4.0: #28E 4.0 to 4.3 against 3.3 to 3.5, and P99.9 12.4 to 15.9 against 8.9 to 9.6. Taking the fastest of 3 removes bursts but not a steady slowdown of the tick against the yardstick. The tick's data competes for the shared caches and the yardstick's does not (the flake policy's "heavy load" note), and in this virtual machine that competition may not show in its own load average. Most of it is the machine, and a little is the code. In alternation at load 1.3 to 1.6, the perf merge's game scripts (`48d0542`) read 2.05 to 2.39 on the new method and this branch's read 1.98 to 2.94; the end hashes were equal. A check of 20 pairs in shuffled order at load 2.6 to 5.3 read a mean of 2.15 for the perf merge's scripts and 2.37 for this branch's: 0.22 higher (standard error 0.10), and higher in 15 of the 20 pairs. Two caches added after the perf merge are dropped by every rebase: the hold pass's bound (`fed7e54`, keyed on `_site_epoch`, which `_rederive` bumps) and a forager's kept colliders (`3211e00`, keyed on `ChunkArena.epoch`, which `set_origin` bumps). The plain tick uses them, and the rebase tick does the work again. Over the gate's 20 rebases, the rebase ticks measured 51 hold centres and picked 26 routes, against 0 and 5 on the plain ticks before them. That is about 0.06 to 0.08 yardsticks for the hold centres and 0.07 to 0.13 for the routes on each rebase tick, each tick at its fastest of 3. It is a real cost of the rebase tick, and the gate is right to count it. So here the rebase gate still reads about 2.0 to 2.5, and it fails in about two runs of three, even at load 1.1 to 1.4: the final `check.sh` read 2.54, where each run's own median read 2.64 to 2.99. The check above saw the unchanged gate fail in 25 of 27 runs at load 1.9 to 5.3 (1.34 to 2.93, mean 2.39). By the flake policy that failure is rerun on CI or on a quiet machine, where the gate should read near the merge's +1.5 plus those 0.15 to 0.2, so about 1.7; this container has not been quiet enough today to show it. Five runs instead of 3 would not settle it either: on the same probes the fastest of 5 read a median of 2.0, against 2.2 for the fastest of 3.
- **Detection** (a scratch copy at load 1.7 to 2.5, 6 runs of each version in rotation, all three versions running the gates in the same minutes):
  - Rebase regression: a fixed loop of 1,240 square roots in `WorldStream.rebase`, calibrated at 0.68 to 0.70 yardsticks. The rebase gate read 2.67 to 3.14 and **failed 6 of 6**. Without the loop, in the same minutes, it read 1.79 to 2.67 (mean 2.21 against 2.92 with it, so the loop added 0.71).
  - Sleeper regression: a fixed loop of 32 square roots per sleeper in `WorldStream._wakers`, calibrated at about 1.2 µs a sleeper. The sleeper gate read 2.10 to 3.20 µs and **failed 6 of 6**. Without the loop it read 1.10 to 1.40.
- **Proposal, not done.** The sleeper limit is in microseconds, so machine speed and steady load move it in a way the other G17 gates, counted in yardsticks, cancel. It would be more faithful to G17 to time the yardstick after each sleeper-gate tick, as the other gates do, and hold the per-sleeper difference in yardsticks (2 µs is about 0.03 of this container's 70 µs yardstick). That restates the limit, so the decision is G17's owner's to make.
- **B-7's saturated soak gate: OPEN, an S1 item carried into S2.**
  - Measured on `s1`: perf rounds 1 and 2 (bit-identical outputs) read a saturated median of 10.7 to 12.2 yardsticks. The 16 runs above, at load 2 to 4, read **10.26 to 11.27** in the median run, against 10. The chunk-load ticks at their fastest of 3 had a median of **17.1 to 21.3** a run (20.0 over all 160) and a worst of **29.3 to 45.4**, against 16. The worst was the 8th load tick in every run: timed tick 564, which in one tick unloads a chunk, removes 7 creatures, spawns 7 and loads a chunk. The soak case read 11.17 and 42.23 at load 2.1.
  - B-7's fallback, `caps.awake` 10, was not taken (`world_cell.json` keeps 12).
  - The next lever is a per-tick spawn budget. It changes the output in endless mode only, with the pool identical. It is to be built on `e2` once S2's T2 lands.
  - The real-content gates pass: #28E reads about 3.3 to 3.5 yardsticks at the perf merge and 4.0 to 4.3 here, and P99.9 reads 8.9 to 9.6 and 12.6 to 15.9.

## 2026-10-23 · S1 integration: what the owner sees (PROPOSED)
Fixes to the endless sea's view layer found in the S1 owner frames, made on `s1` at integration. Pool mode is unchanged.
- **The column stands beside the checkpoint.** It stood on the checkpoint, so a new or respawned cell started inside it. It now stands `WorldMarkers.COLUMN_BESIDE_TM` (2.6 tm) due east of it: the camera always looks north, so a piece due east stands beside the cell on screen whichever way the cell faces, where one to the south would rise across it. The arrow and the pip are unchanged (the arrow points at abs (0, 0); the pip points at the column). Content 6.11's "it stands at the checkpoint" now reads "beside it". Whatever the GLB brings, the column is drawn at most `COLUMN_TOP_MAX_M` (4.5 m, the kit's soft shaft since art PR #63) above the swim plane, so an opaque or taller piece never runs out of the top of the screen from the spawn at the default camera; the kit's own shaft is drawn as made.
- **Zone labels keep off the cell.** The label that floated over the cell was a zone's "Regrowing N%" (`FeedbackFx`), standing 1.2 m over the centre of the zone the cell had just emptied, where a forager waits; a run with ForageBot at home showed it over the cell for hundreds of frames. A zone label now rises at once just clear of the cell's top on screen (1.35 cell radii, the food arrow label's clearance) and settles back smoothly when the cell leaves; when it would have to rise more than 1.2 m (the cell comes onto it from the north) it hides at once and fades back in when the cell is clear, so it never slides across the cell. This applies in the pool too. Meal labels still rise from the mouth and hit labels from the cell, as M1 has them: they are about the cell and last about a second.
- **The pip keeps off the panels.** With the column to the west the pip sat on the west edge where the controls panel (bottom left, the first 30 s of a lineage) covers it, and its words under the panel too; to the north-west it falls under the status panel, to the north-east under the points and toasts. `Hud.panel_rects()` lists the panels showing now, and `WorldOverlay.place_pip` slides the pip along the edge band (`ThreatIndicators.MARGIN_PX` in, both ways, in 4 px steps) to the nearest point where neither the pip nor its words come within 6 px of one; with no panel in the way it sits where an edge arrow would, as before. `test_world_hud` sweeps 72 bearings against hud.tscn's panels at 1920 x 1080 (the pip slides at 30 of them) and checks each pip is clear, on the band and at the nearest clear point; the endless smoke checks the real HUD's panels. The threat arrows are unchanged; they draw over the panels.
- **Landmark pieces load ahead.** The headless swim tour's long frames came with chunk loads because `LandmarkLayer` loaded each landmark or rare GLB the first time a chunk held it, inside that chunk's event: 44 to 151 ms a piece, seven pieces, 605 ms in all. Timed per frame in a scratch copy (two tours, load 2.5 to 4.3), 6 and 8 frames took over 50 ms: 10 were such loads, the rest the far respawn (three frames, outside the view's chunk work) and one sim tick. The rest of the view's chunk work is small: the shell MultiMesh rewrites took 24 ms over the whole tour (692 of them, 37 µs each, at most 1.8 ms in a frame, at the far respawn's 67), the zone discs 4 ms, the zone labels 15 ms, so per-frame batching and instance-range writes would buy nothing and are not done. Now `LandmarkLayer.setup` starts loading the kit's landmark and rare pieces on worker threads (`ResourceLoader.load_threaded_request`), each GLB once a run and kept for it; a chunk takes its piece (waiting only if the load is still running), and a layer that goes takes any load still pending, so none leaks at exit. After, two tours at load 3.8 to 4.2: no frame over 50 ms (longest 40.7 and 37.8 ms, a sim tick and frames outside the pool), a piece taken in 0.02 to 0.03 ms, 1% low 5.0 and 6.9 ms against 10.5 and 8.6 before; the headless G18 line passes. The shell pieces still load on first use (13 to 30 ms each, in the first 4 s). `test_world_scene` checks setup starts every load, that no chunk is needed for them to finish, and that no request is left with the loader.
- **Tall pieces at the top of the screen (a proposal; the camera is unchanged).** The landmarks stand 3.3 to 4.0 m above the swim plane (the shell cathedral 3.9 m, the giant husk 1.9 m) and reach 3.0 to 3.4 m below it; the shells stand 0.5 to 0.9 m above and 1.9 to 2.1 m below (the M1 rocks, 0.6 above and 1.7 below, are built the same way). At the default camera (pitch 55°, fov 45°, distance 14) the top edge of the screen meets the swim plane 10.0 m north of the cell, and a point h m above the plane stays on screen only within (6.35 − h) / 0.637 m north of it. So a landmark's top leaves the screen once the landmark is more than 3.7 to 4.5 m north of the cell, and the player sees it whole only from close by (frames 03 and 06); a shell's top leaves only past 8.6 m, but the lower bodies, which run down the screen, hang into its top edge from pieces up to 13.3 m (shells) and 15.3 m (landmarks) north, beyond the ground in view (frame 05); south of the cell they run down the screen toward it (frame 08). How far north a piece's top stays on screen, in m:

  | Camera | Ground | Top 0.9 m | Top 2.0 m | Top 3.5 m | Top 4.0 m | Cell drawn |
  | --- | --- | --- | --- | --- | --- | --- |
  | Pitch 55°, distance 14 (now) | 10.0 | 8.6 | 6.8 | 4.5 | 3.7 | 100% |
  | Pitch 55°, distance 16 | 11.4 | 10.0 | 8.3 | 5.9 | 5.1 | 88% |
  | Pitch 55°, distance 18 | 12.8 | 11.5 | 9.7 | 7.3 | 6.6 | 78% |
  | Pitch 65°, distance 14 | 7.9 | 7.0 | 5.8 | 4.1 | 3.6 | 100% |

  The options. (1) Art, recommended: landmarks stand at most about 2 m above the swim plane and carry their height below it, as the shells do; a 2 m top stays on screen to 6.8 m north, two thirds of the ground in view north of the cell, with no camera change. (2) The endless sea starts at distance 16 (the zoom stays 10 to 20, so the sim's view footprints, which use `zoom_max`, do not change); the cell is drawn 12% smaller than in the approved pool. It needs a test that pool mode's camera stays at pitch 55°, fov 45° and distance 14, and the look probe's M1 scenes unchanged. (3) A steeper pitch does not help: at 65° the ground in view north shrinks to 7.9 m and a 4 m top still leaves at 3.6 m, and the pitch is also the sim's (`ViewFootprint`, spawn fairness), so it is not the view's alone to change. (4) Fading a piece as its top nears the edge is possible in the view, but it would hide the landmark the player is swimming toward.

## 2026-10-23 · S2 "First growth": the build decisions (PROPOSED)
S2 is planned in four files in the project files: the spine `docs/s2/s2-interfaces.md`, the sim half `docs/s2/s2-sim.md` (tracks T0 to T4 and T3's code), the view half `docs/s2/s2-view.md` (T5) and the corrections layer `docs/s2/s2-build-plan.md`, which wins where they differ (then s2-sim and s2-view, then the spine). Every number not verified there is PROPOSED tuning held in data or a named constant. Standing rule (owner, 2026-10-23): never wait on Joshua, keep building, merge when green.

- **Ids in this entry.** D-14 to D-56 and C-1 to C-13 are the S2 spine's (S2 continues S1's D-1 to D-13; these C-n are not S1's CC-n or CT-n); D-57 to D-87 and X-1 to X-17 are s2-sim's; V-1 to V-26 and C-V1 to C-V18 are s2-view's; BP-1 to BP-20 are the build plan's; S2G1 to S2G41 are the gates (S2G37 to S2G41 are new in the build plan). "Adopted" means as the document words it; otherwise the line gives what replaces it.
- **The build plan, BP-1 to BP-20.**
  - BP-1 (replaces D-14's first sentence and D-15). The integration branch is `e2`, the tracks `e2-t0-gates`, `e2-t1-brain`, `e2-t2-growth`, `e2-t3-world`, `e2-t4-saves` and `e2-t5-scene`; `s2-*` names in the documents read `e2-*`, because origin still holds M1's `s2-*` branches. `e2` is S1's I-5 head with `origin/main` merged (main's side on art, `settings_service.gd`, `game/scenes/audio/**` and the menus) while S1 is closed but not on main: `e2` = `99ec158` (s1 `48d0542` + main `d29cbce`). T1.1 to T1.4 and T4.1 to T4.2 started early from `s1-t5-scene` and merge `e2`.
  - BP-2. The fuzz checker learns growth (T2.6b, gate S2G39): positions compared in absolute am with the measuring point's k; cuts are `respawned`, `debug teleport_abs` and `debug set_size`; on a growth tick, conversions, carrion spawns, growth unloads, every load and the plankton loss are exempt before `grew`, growth removals are checked from the old frame, and everything after `grew` from the new; `HIDDEN_REMOVALS` gains `growth` and `remnant_left`; invariant 13 adds remnants and posts.
  - BP-3 (replaces D-21, spine 3.14 and 4.7, s2-sim 3.11 and 4.5's settings part). The trigger is main's `gameplay/growth_trigger` (`SettingsService.shared().growth_trigger()`), sent as `SimIntent.trigger` on the first tick after the pool builds and on every change; `world_cell.json` `growth.trigger` is only the sim default for tests and bots. Reduce motion is `SettingsService.reduce_camera_motion()`. `UserSettings` is player memory on `user://player_memory.cfg` with only `hints_followed` and `giant_pass_lineages`; `user://settings.cfg` is main's and S2 code never writes it.
  - BP-4 (replaces D-31 and D-64). `WorldStream.next_size_clear_point(sim)` is a pure function of the cell's absolute point, size and radius: S1's spiral at size n + 1 in the 3 × 3 new-size chunks round the cell's new-size chunk, bounded to 4 rings, `Vector2.INF` when wedged. The new-size chunks are prefetched (`_next_chunks`, at most `growth.prefetch_per_tick` 1 a tick, once the meter passes `prefetch_share` 0.9 of the ring) into a cache that never changes a result and is never hashed; the growth tick loads from it and asserts its settle equals the point. `PoolSim.clear_point_on(arena, p, r, max_rings)` is the one spiral. A content rule (at every size, the largest shell radius ≤ `chunk_tm − 2 × wedge_tm`; T3.4b) keeps every collider the spiral can touch in the 3 × 3. S2G18 stays 40 yardsticks measured warm; S2G37 and S2G38 are new.
  - BP-5 (replaces D-51; withdraws every `max_in_build` 3 test config). `Growth.blocker_of(sim, with_wedge)` names the first failing calm condition in the order hunted, chasing, eating, wedged. The parked-grazer gate: a ForageBot grazer at size 2 in a sunlit zone with live rammer sites finds 90 calm ticks in a row within 28.5 s, on 6 seeds (slow), with at least one rammer fleeing it in view. The growth fuzz reaches its second growth through `debug_set_size(1)`.
  - BP-6. With growth off, endless size 1 is hash-identical to S1: `tests/fixtures/endless_s1_hashes.json` is recorded on the `e2` base (T0.1b) and compared by `test_hash_identity` (T0.2). `Gates.make_sim(body, seed, growth := false)` sets `switches.growth` on every call; S1 test helpers default to growth off; `world_min.json` carries `switches.growth` false; the size-1 cost runs use growth on in press mode with no press; the smokes' S1 phases run in press mode.
  - BP-7. Seams T5 needs from T2 and T3 each have an owner: `chunk_loaded` gains `sites` and place `scale` (T2.5); `debug {command: "set_size"}` (T2.6); remnants freeze under `dev_ai_frozen` (T2.4); fills on the growth tick carry the growth tick as `born_tick` (already true; T2.5 asserts it); shell, set-piece and landmark `scale` × s (T3.3); `CarrionField.find` (T2.2); remnants read through `sim.remnants.items`.
  - BP-8. S2G12 compares the stream's whole state (held keys, chunk digests, hashed arena colliders, sites, zones) after a growth at P with a `debug_set_size(2)` arrival at P and two size-2 swims to P.
  - BP-9. CellAudio is on main, so T5 calls its cues and `set_size` (V-21, C-V16, s2-view 7.6's tones and the placeholder rows are withdrawn). Step 0 is on the branch, so X-12 is void and D-73 goes in `_respawn_now` (`pool_sim.gd:445`).
  - BP-10 (replaces D-16's second sentence and s2-sim 3.3's endless part). `CreatureField.create` registers niches only for species with `entry_size` 1, in both modes; `recompute_caps` registers the roles of species with `entry_size` ≤ the size plus every role already registered, so the size-1 endless `niches` equal S1's.
  - BP-11. The swim path between a two-post site's posts (a capsule of R + `route_clearance`) clears every shell of its tile live at that size (S2G41; T3).
  - BP-12 is not assigned.
  - BP-13. The reversal is the first tick after `grew` at which a body of the old size's species, now at q < 1, flees the cell inside the default-zoom footprint; its median over 18 runs is ≤ 30 s (a run with none counts 120 s), soak, T0.5. S2G1's tiers: fast, every relationship rule off at seed 401 on the three M1 scenarios to 600 ticks and the endless identity at 600 and 3,600; slow, each rule alone on and alone off to 3,600 and the endless identity at 18,000; soak, all rules off at seeds 402, 4242 and 77 to 18,000.
  - BP-14. T5.2 ships on main's two bodies (gate S2G40 pins their node and material names, `M_Threat` on the elder rammer). If art's `BACKDROP_COUNT` 0 is not on `e2` by I-3, the integrator makes that two-line change. Until `apply_scale_view` lands, the hatch probe hides the ambience and says so.
  - BP-15. The writer conflicts are settled as: thin zones D-60 (× 0.4) over D-54; remnant overflow D-78 (to haze) over D-44; growth-tick frames D-65 over D-30; the remnant leave rule D-84 over D-45; every awake creature converts (D-87) over spine 3.10 step 2; the cell in `self_view` D-59 over D-24; post spacing D-61 over spine 3.13; containers, camera, remnant reads, T5's files, the scale view and near ghosts C-V2 to C-V5, C-V12 and C-V13 over spine 3.15, 2.1 and 2.2; the wedge point BP-4 over D-31 and D-64; settings BP-3 over D-21; D-16 in endless BP-10.
  - BP-16. Shell, set-piece and landmark `scale` × `bu_to_tm(n)` at the five places in `world_gen.gd`; places get `scale` in the event; at size 1 s is exactly 1.0, so the size-1 digest is unchanged.
  - BP-17. `WorldStream.chunk_loaded_event(ch)` is public and the only builder of the payload; `WorldSpace.chunk_loaded_event` and `fake_growth_events.gd` go through it.
  - BP-18. Save v3 is frozen when S2 ships: no key is added later (a later need is v4 with its own migration and fixture); the genome's `appearance` stays a free dictionary, so S4's `appearance.membrane` needs no change; the trigger, reduce motion, hints and the giant pass are not in the save; an S1 build refuses a v3 save.
  - BP-19. The HUD shows the bound key: `Growth.hint()` keeps "(G)" and the HUD replaces it with the `grow` binding's label (`SettingsService.first_code`).
  - BP-20. `counters.remnant_overflow` and the `world` keys `growth`, `remnants`, `carrion_radius` and `carrion_lifetime` exist only when growth exists.
- **The spine's decisions, D-14 to D-56.** D-14: BP-1. D-15: BP-1. D-16: pool half adopted, endless half replaced by BP-10. D-17 to D-20: adopted (D-19 with D-66's `carrion_lifetime` and BP-20). D-21: replaced by BP-3. D-22, D-23: adopted. D-24: replaced by D-59. D-25 to D-29: adopted (D-27 also answers spine Q8; D-28 is built as D-57; D-29's exemptions are BP-2's). D-30: replaced by D-65. D-31: replaced by BP-4. D-32: adopted (with D-81). D-33: adopted ("food" is a v3 discovery type, Q5). D-34, D-35: adopted (D-35 answers Q1: at least 80 % before the first growth). D-36 to D-40: adopted (D-39 applied everywhere by D-69). D-41: adopted, with BP-14's fallback (Q2). D-42, D-43: adopted, stored per machine in player memory (BP-3; Q6, Q9). D-44: replaced by D-78. D-45: replaced by D-84. D-46 to D-50: adopted. D-51: replaced by BP-5. D-52, D-53: adopted (D-53 answers Q4). D-54: adopted except the thin share, 0.4 by D-60. D-55, D-56: adopted.
- **s2-sim's decisions, D-57 to D-87.** All adopted, except: D-64 is replaced by BP-4 (no `_next_clear`, no `exact` argument, no 0.25 tm tolerance); D-73 goes in `_respawn_now` (BP-9); D-76's `debug_set_size` also emits `{type: "debug", command: "set_size", size}` (C-V9, BP-7). In brief: D-57 a remnant is a `CreatureField.Creature` with no brain, and combat takes remnants through `_combat_bodies()`; D-58 the step order (intent stored, events marked, `world.step`, the M1 body, remnants after the creature moves, `growth.observe` before `tick += 1`); D-59 `self_view.cell` and `cell_seen`; D-60 thin zones × 0.4; D-61 post spacing (Lurker 4 to 6 tm, elder rammer 6.0 to 10.5 tm, its `nav_timeout_s` 16); D-62 `CreatureBrain.CALM` and `is_calm`; D-63 fear in every think, after pain; D-65 old-frame positions for every event before the origin moves; D-66 morsels skip step 3's shrink and `carrion_lifetime` joins the snapshot; D-67 `_load_chunk(…, settle)` and `_unload_chunk(…, reason)`; D-68 conversions by `Relationships.ladder_role`, `min_rel` 0.45 and `morsel_min_rel` 0.25 fixed; D-69 k in every tile-frame disc; D-70 content validated at every size; D-71 food looks new at a size; D-72 kill lumps; D-74 Continue clamps the size (Q-S6); D-75 autosave after `grew`; D-77 a remnant's phenotype is `at_size(n + 1)`; D-78 overflow to haze; D-79 radius, cfg and rings from `record_of`; D-80 beat loads; D-81 the build top skips the calm window, `Growth.NEVER`; D-82 the union disc; D-83 rebase and teleport handle remnants and `RebaseShift` shifts posts; D-84 a remnant leaves only beyond `spawn_safe_m` and outside the zoom-max footprint; D-85 the brain source scan; D-86 the showcase gates the start of a calm window; D-87 every awake creature converts.
- **s2-view's decisions, V-1 to V-26.** All adopted, except V-21 (withdrawn by BP-9: CellAudio's cues and `set_size` are on main). V-15 (settings from `SettingsService`, player memory in `user://player_memory.cfg`) is applied to the spine and s2-sim too (BP-3), and T5.1 makes no DECISIONS edit of its own. In brief: V-1 the beat clock is sim draw time; V-2 one k(t) curve; V-3 `reexpress` divides the shown distance, not the asked zoom; V-4 and V-5 containers re-express their children; V-6 the settle is shown; V-7 the HUD keeps the old size until the chord at 1.9 s; V-8 relations apply at 2.0 s; V-9 remnants keep their views; V-10 old food fades from copies; V-11 ghost quads with a per-frame draw scale up to 2.0 (Q-V1); V-12 ghosts are camera-relative; V-13 the rise; V-14 the first giant pass; V-16 the pool ORs a grow press into the intent; V-17 reduce motion is a frame snapshot cross-fade (Q-V5: the `%Fade` dip on Windows if the tour shows a 50 ms frame); V-18 marker thresholds in tm, distances in am; V-19 the ghost layer also runs in pool mode; V-20 new materials warmed up; V-22 glitter; V-23 no lump toast; V-24 morsels drawn by the creature's view; V-25 lair mouths and silt trails; V-26 the `grow` perf route.
- **Contradictions found by the writers.**
  - The spine's C-1 to C-13: adopted as the spine resolves them, except C-7 (branches are `e2-*`, BP-1), C-9 (settled by BP-3, not a new settings file), C-10 (settled by BP-5; no size-3 test config) and C-11 (line numbers follow the build plan's section 1; where lines drift, the line and the function name are cited).
  - s2-sim's X-1 to X-17: adopted, except X-12, which is void (step 0 is present; BP-9).
  - s2-view's C-V1 to C-V18: adopted, except C-V1 (also applied to the spine and s2-sim, BP-3), C-V5 (minus `placeholder_audio.gd` and `inventory.json`), C-V6 (adopted, but size-2 shells would draw 1.6 times too large, not too small; BP-7, BP-16), C-V9, C-V10, C-V14 and C-V15 (their owners are BP-7's) and C-V16 (reversed by BP-9).
  - The build plan's R-1 to R-7 are settled by BP-4, BP-16, BP-10, BP-6 with BP-20, BP-17, T0.4 creating `test_endless_fuzz` if S1 had not (S1 shipped it), and BP-9 with BP-14.
- **Open questions, built toward.** Spine Q1 to Q9 as above and Q3 and Q7 as written; s2-sim Q-S1 to Q-S8 as written (D-71; D-27; D-59; D-61; `life_s` kept for the scene; D-74's clamp; D-63; no sim change for the starving tip, which T5 owns); s2-view Q-V1 to Q-V13 as written. Two remain for the owner's end review: reduce camera motion one click deep under Settings → Accessibility, as main built it (Q-V8), and an S1 build cannot read an S2 save (BP-18).
- **Early-track decisions** (PROPOSED; recorded from the early T1 and T4 builders' reports).
  - T1.2: `Relationships.q_of` multiplies by 0.625 (exactly 5/8) n − c times below the entry size and by 1.6 c − n times above it, so q is exactly 0.625, 0.390625, 0.244140625 … (`pow(1.6, -2)` is 0.39062499999999994). Its rule functions and `ladder_role` take an optional trailing tolerance (default `Relationships.TOLERANCE` 1e-6), which the brain passes as `cfg.share_tolerance`.
  - T1.3: `CreatureBrain.POST_HYSTERESIS_M` 2.0 is a named brain constant and the default of `cfg.post_hysteresis_m`, read only in `config()` like the other length defaults. `CreatureBrain.KEY_KINDS` is an explicit closed table of 71 cfg paths (`speeds.*` are shares and kept, `attack.burst_speed` is a speed and scaled); `key_kind` returns "" for anything else and the classification walk fails on it. `cfg.share_tolerance` comes from `relationships.tolerance` (default 1e-6) and also applies to rules 1 and 2 when their switches are off; no M1 body pair lies within 1e-6 above a share, so the M1 goldens are unchanged.
  - T1.4: `_answer_fear` takes the first feared percept in `CreatureSenses.perceive`'s order (nearest first, ties by id) and returns at once when rule 3 is off. `fear_of` is cleared with the attacker in `forget()` and `on_target_gone()` when it is that id, and always in `force_return()`. `creature_fled.from` may now be a feared body, not the attacker. In `test_threats_sim`, `threats_forage` and `threats_kiter` at seed 401 with every relationship rule on hash as the M1 goldens at 600 and 3,600 ticks (about 2.5 s of the fast suite).
  - T4-a: save v3 refuses unknown keys as load problems, at the top level and inside every object v3 adds or changes (v2 ignored unknown top-level keys), because a key this build does not know would otherwise be dropped by the next save. T4-b: `SaveGame.MIN_SIZE` 1 and `MAX_SIZE` 10 bound every size in the save; D-74's clamp happens at Continue. T4-c: `spawn`, when not null, is exactly `{x_am, y_am, heading}`; `player.energy` and `player.health` are null or finite and ≥ 0; a missing `spawn` key is a load problem. T4-d: sizes a file holds as whole floats are stored as ints, so a loaded save equals a running one. T4-e: `v2_to_v3` writes its own literal values, never `SaveGame`'s current defaults, and leaves a non-object `player` for the load to report. T4-f: v3 does not refuse repeated discoveries; the ledger de-duplicates. T4-g: `UserSettings` takes only a `PackedStringArray` per key, writes only `[hints] followed` and `[ambience] giant_pass_lineages`, and saves through `player_memory.cfg.tmp` renamed into place.
  - Further PROPOSED numbers that the other tracks report while they build are added here by the integrator.
- **T0's lines** (PROPOSED; the gates track's own readings).
  - T0.1b, re-recorded. `endless_s1_hashes.json` was first recorded on the `e2` base `99ec158`. s1-content's #32 tile fix (s1 `0216503`, in `e2` at `a01afaf`: 18 ambush lairs moved to the rims of their meadows, 21 reef shells moved off cell-narrow cracks) changes the endless world, so it is re-recorded on `a01afaf` with growth off. All nine hashes but swim_hunter's 600 move; swim_hunter 600 and 3,600 and swim_racer 600 and 3,600 equal T2's own growth-off readings on `a01afaf`.
  - T0.2: S2G1's fast tier runs the endless identity to 600 ticks for all three runs and to 3,600 for the racer only, because all three to 3,600 take about 4.8 s here against T0's 3 s fast share; the hunter and circle runs reach 3,600 and 18,000 in the slow tier. s2-sim's S2G1 mutation (fear share 1.19) moves no M1 hash: M1's rammers and ambush hunters never come within fear's reach of each other on seeds 401, 402, 4242 and 77 to 18,000 ticks. So a fast static test checks every M1 pair and the three starting cells against rules 1 to 4 (it fails at 1.19), and the slow control turns fear alone on at share 0.75, where a rammer fears the cell, which must move both threat scenarios.
  - T0.3, the bots. Every bot's growth keys are `EvadeBot.GrowthKeys` (one class in `evade_bot.gd`, which every bot already loads or can): `keys.trigger` (default "auto"; "" sends none) goes on the bot's first intent only, and with `keys.trigger` "press" and `keys.press` (default true) the bot holds Grow on every tick `growth.is_full(size)`; `keys.press` false is the press-mode run that never presses (S2G38, BP-6). A bot that runs another inside it (ForageBot's EvadeBot, HuntBot's EvadeBot, a greedy camper's ForageBot, ClumsyBot's ForageBot) blanks the inner bot's trigger, so an inner bot first run mid-run sends nothing. In the pool and with growth off nothing reads the keys, so the M1 goldens and the S1 identity hashes are unchanged.
  - T0.3, ClumsyBot readings. "Within sight" is the default zoom's view footprint on a 16:9 screen (HuntBot's `VIEW_ASPECT`). "Until hit or dead" is the cell's: a charge ends when `sim.stats.hits_taken` grows or the cell dies, and the creature it was charging when the hit landed is passed over from then on (otherwise "until hit" would end nothing, since the same creature would be charged again on the next tick). q == 1 is `SpeciesCatalog.q_of(species, size)` within 1e-9 (it is exactly 1.0 at the entry size). The die mode's 40 tm and the view are in the current size's tm.
  - T0.3, the size-2 runner (S2G8). At size 2 nothing at q < 1 strikes at the cell, so without help a run would never ask the rule against answering a larger body. KiterBot's `bite_visits` (off by default, so S1's runs are unchanged) swims jaw first into each creature it visits once it has arrived, until one bite lands (`sim.stats.hits_dealt` grows), then circles as before. The runner is non-vacuous only when each of the pairs (ambush_hunter, 2) and (rammer, 2) had the cell in its senses on at least 600 ticks and was bitten at least once. HuntBot reads chunk sites and territories with `world.local_of_tm` (absolute tm at the stream's size), which equals `local_of_abs` at size 1, so S1's hashes do not move.
  - T0.3 to T0.6, waiting. Each S2 gate waits on the seams it reads (`Gates.S2_NEEDS` in `test_endless_gates.gd`): `debug_set_size` (T2.5), `debug_force_growth` and `debug_fill_meter` (T2.6), FuzzInvariants' `growths` and `set_sizes` counts (T2.6b), `sim.remnants` (T2.4), `Growth.blocker_of` (T2.3), the species entering at size 2 (T1.7) and the real content's size-2 sites (T3.5). A seam may be missing only while its marker file is absent, so a gate cannot wait for ever on a seam that has landed under another name.
  - T0.4, the growth fuzz (S2G21). The fast case runs its second run without the checker, for the hash only (T0's 3 s share). Each cycle is BP-5's (set back at 600, force at 1,199). Until T3.5 it runs on the size-2 fake world (`FakeWorldGen.s2_species()`). S2G21's mutation (the snapshot omits `growth.closing` or `carrion_lifetime`) is caught by T2.7's perturbation, not by the two-run hash, which compares a run with itself.
  - T0.5, the growth gates (S2G16). The first-growth gate drives a wary ForageBot (`avoid_threats`, as #29 and #32 do) on the grazer and the omnivore, and HuntBot on the hunter, 6 seeds each. The 3 to 5 minute bound is on the median of all 18 runs, and the 6 minute bound is on each run. The reversal median is over the runs that grew. Clumsy and die run on the grazer and the omnivore over the same 6 seeds, and a run with no growth by 720 s counts 720 s. A dead cell continues after the 90-tick death notice. The parked grazer's "sunlit zone" is a zone whose chunk record has region "sunlit", and "live rammer sites" are rammer sites whose territory covers the zone's centre and that are live at the cell's size (HuntBot's `_live`).
  - T0.6, the cost gates (S2G17, S2G18, S2G38). The size-1 runs fill the ring once at the start (`debug_fill_meter`, or `Growth.add` before T2.6). The meter never drains, so it stays full, and each run checks that it ended at size 1, full and not armed. #29E's two placements are 12 dev creatures of the species a growth to 2 keeps as remnants (ladder role rival or prey at 2, D-68), on a 6 tm ring round a hidden, still cell before the forced growth, and 10 dev creatures of the size-2 species on the same ring after it. Each 5 s window's mean tick and yardstick count is taken at its fastest of 3 runs. The remnant gate times the same scene with no awake dev creatures against its twin with the remnants removed, 200 ticks a round for 3 rounds, and divides by the remnants held on average through each round (they flee and leave). It needs at least 8 on average, as the sleeper gate needs 8 sleepers. The growth tick is the tick after `debug_force_growth`, on a hidden, still omnivore at home. S2G38 first read on T2.5 (merged here at `997ea0c`): with the ring held full the overdriven swim's P99.9 is 18.4 to 22.2 yardsticks against 14.0 to 15.6 with it empty (same swim and runs, load 2.5 to 3.0), so the gate fails on T2.5 and its limit stands. A one-run profile puts the slow ticks on neither chunk loads nor prefetches.
  - T0.7, purity and the budget (S2G27, S2G30). `growth.gd`, `remnant_field.gd` and `relationships.gd` are in `MUST_SCAN` and must also exist, because they have landed. `run_tests.gd` ends every run that covers all files outside the soak tier with S2G30's report. Each track's fast time is the time of the fast methods in the test files 5.1 gives it, less the same files' time on e2's base `99ec158` (`S1_FAST_MS`, read here at load 3.5 to 3.8: 137.2 s for 954 tests), set against its share. The whole tier's share is the tracks' sum: 31 s, because the build plan's T2 share of 11 s replaces the 10 s behind s2-interfaces' "+30 s". A file a track only adds to counts whole, so its S1 time cancels against the base. It is a reading, not a gate. On this branch at load 3.7 to 4.5 it read T0 +2.5 s, T1 +6.1, T2 +1.5, T3 −0.4, T4 −2.6, T5 +0.3, and +5.1 s in all.
  - T0 fix round, the size-2 tour (S2G8; BP-2). At size 2 the home's M1 sites are in view of the spawn and never spawn there, so the runner that stayed home sensed ambush_hunter on 11 ticks and rammer on 22, against 600. `SwimBot.SiteTour` takes each cell to the nearest site live at the world's size of the first of its species groups that has one, read from `WorldGen.chunk` up to 6 chunk rings round the cell's (192 tm each way at size 2), and swims there round rocks (`Unjam`) until it is within 8 tm of the site's home. It stays while the site's creature is awake, passing a site over whose creature is not awake 300 ticks after it arrived or whose home it has not reached 3,600 ticks after it set off, and keeps to the point 3 tm in front of that creature whenever the cell is farther off or more than 90° off its heading (an M1 creature at size 2 senses the cell only within about 4 tm and turns away to flee it). Kiters tour rammer and ambush_hunter, then lurker and elder_rammer, 1,800 ticks a site; evaders tour rammers, then ambush hunters, 3,600 ticks a site; an evading cell that eats plants forages once below 0.5 of its energy until 0.9. `ForageBot.unjam` (off by default, so the M1 goldens and S1's runs do not move) frees the evaders' forager from cracks. Readings: ambush_hunter sensed on 1,468 ticks and bitten 24 times, rammer 1,001 and 55; seed 424 (evade, hunter body) died 7 times before, of hunger at its waiting point (a jaw-only body eats only meat, and endless carrion comes only from kills), and 0 times on tour, where it kills rammers by contact and eats them.
  - T0 fix round, the parked grazer (S2G16; BP-5). The zone search reads `WorldGen.chunk` ring by ring up to 8 rings round the cell's chunk (256 tm each way at size 2), and one ring past the first that finds a zone: seeds 612 and 613 have no sunlit zone in a live rammer territory among the 16 loaded chunks and find one 184 and 176 tm away. The plan's mutation for this gate (the chase rule counting fleeing bodies the cell cannot eat) survived it: a still cell never closes in on a body that flees it. So each run goes on for 600 ticks with the grazer swimming at the nearest rammer fleeing it within chase_track_tm; `blocker_of` must never say "chasing" then, and over the seeds the grazer must have closed in by more than chase_close_tm within a chase window on some tick (79 to 102 ticks a seed here; mutated, 48 to 72 chasing ticks on every seed).
  - T0 fix round, S2G18's warm path (BP-4). The growth tick's cost fails its limit on the base too, so the plan's mutation (the growth tick ignores the prefetch) is read by a second slow case on seeds 2811 and 2812, warm as the gate has it: every chunk the growth tick loads that the prefetch held is the very `WorldChunk` it held (14 of 14; mutated, 0 of 14).
  - T0 fix round, the showcase (S2G16; BP-13, D-49). The plan's mutation for the reversal (showcase off) survived it: the reversal median is 0.0 s with and without the showcase, because a remnant in view at the growth reverses at once (mutated, 1 run of 18 had none). Each first-growth run therefore checks D-49 itself: every calm count before the first growth starts once showcase_s has passed since the ring filled, or with a creature that flips at the next size in view (`Growth._flip_in_view`, read after the tick as `observe` read it). Base: 0 of 24 calm counts unshown over the 18 runs; mutated: 19, on 16 runs.
  - T0 fix round, S2G16 readings on `cb115e5` (readings, not decisions). The first-growth soak's median is 176.2 s over the 18 runs, under the 3-minute floor, so it fails on the base: wary ForageBot grazer median 187.1 s, omnivore 176.2 s, HuntBot hunter 126.4 s (its kills' meat brings it to about 2 minutes); none over 6 minutes; reversal median 0.0 s. The limits stand. Mutated, the drain cap at ring / 90 gives a median of 97.1 s and showcase off 169.5 s.
- **Balance lab targets for S2 to re-measure** (`docs/s2/s2-inputs-balance.md`, from the 2026-10-23 sweep on main `a9d0dba`; readings, not gates). S1's golden M1 hashes lock pool mode, so tuning goes into the endless world's data (tiles, size tables, the growth economy), not M1's pool data, unless a golden refresh is deliberate and logged here. `tools/balance_lab.sh` is re-run on the S1 merge and after S2 and S3 to compare with this baseline:
  1. A careful forager is never hungry (95 to 96 % mean energy, 8 of 8 survive). S2's growth economy turns surplus food into progress (T2). Target: a wary or evading forager at size 1 in the endless sea at 70 to 80 % mean energy.
  2. A wary bot meets 0.10 to 0.23 threats a minute (endless placement; S3's size tables). Target: at least 0.5 meetings a minute.
  3. EvadeBot dodges 147 of 148 tells (keep F2's fairness; S3 adds tell kinds). Target: a 0.4 s bot dodges 85 to 95 % at size 2 and up.
  4. Rammers cause most deaths (14 of 18 for a careless grazer; watched, T2). Target: a careless forager's median first death at 90 s or later.
  5. HuntBot makes about 1.7 kills a minute at 90 % energy (S3's threat variants). Target: under 1 kill a minute at size 1.
  6. A hunter that does not hunt starves in about 2 minutes (T5's starving tip for meat-only bodies, "Hunt rammers from behind for meat"). Target: the tip shows once a run when a meat-only body starves.
- **Integration, the s1 merge** (PROPOSED). s1 `309dd72` (the perf3 round: a rebase keeps the hold bound and the kept colliders, `remove_all`, one sleeper spawn a tick, the deferred frees) is merged into `e2`. Where the sides met: (1) the stream's quiet-tick work: one chunk generation a tick (`_look_ahead`), then the prefetch (BP-4) keeps S2's scheduling (every tick that loaded nothing and generated nothing ahead), and s1's site preparation (`_prepare_ahead`) takes the quiet ticks the prefetch leaves; what the unloads let go is freed as s1 has it (quiet ticks with no generation), and what the growth tick lets go stays in `_retired` until after the beat as S2 has it, its whole-chunk unload sending nothing to `_let_go`. None of the caches changes a result. (2) A site's creature made ahead (`prepare_site`) comes from the species record at the field's size (D-79) through `CreatureBrain.made`; `start` and then `set_posts` run at the spawn, so `post_since` is the spawn tick as before. (3) The growth tick forgets the chunks generated ahead and the sites prepared for them (made at size n). (4) `ChunkArena.set_origin` no longer bumps the epoch (s1), so test_growth_tick's crossing check expects it unchanged.
  - T0.1b, re-recorded again. s1's one sleeper spawn a tick (`78fcea8`) changes the endless results, so `endless_s1_hashes.json` is re-recorded on the merge with growth off (base commit `309dd72`). s1's own harness, driven the same way (the three identity runs to 600, 3,600 and 18,000 ticks), computes the same nine hashes on s1, so the merge is bit-identical to s1 with growth off.
- **The growth tick's cost (S2G18), the cuts** (PROPOSED). On the merge the warm growth tick cost 4,400 to 5,450 µs here (59 to 72 yardsticks; CI read 41 to 53 against the 40 limit). The limit stands; the tick now does less, and what it did is moved to the quiet ticks before it or the beat's ticks after it. None of this changes a result with growth off (`test_hash_identity` holds the nine S1 hashes), and the growth tick's world is the one the caches off build (test_growth_tick's identity and prepared-load checks hold).
  - **D-80 amended.** The growth tick loads its view set and no more: the beat's loads (the chunks the cell heads for) begin the tick after it (`step` skips `_load` on the tick that grew).
  - **C-V15 amended.** The growth tick fills no food zone. Every zone shown at the growth waits for its fill (`PlanktonField.pending_fill`; it does not regrow meanwhile). The tick after the growth queues the waiting zones nearest the cell first (the sort is that tick's cost) and fills `FILL_ZONES_PER_TICK` (4) of them; each tick after fills the next 4 until the queue is empty (a view set shows about 16 zones, so under a second of the 2 s beat). An item is born on the tick that fills its zone. A zone that leaves the food set before its turn regrows by the plankton's own tick instead. The view's warm-up draws the new items from their first frame, one frame after the growth's (frame 0 shows the old food's fading copy alone).
  - **The growth tick tries no site.** Every site of its view set is due at once; the growth tick's spawn pass tries none, and each tick of the beat tries `BEAT_TRIES_PER_TICK` (6) sites (`tick_spawns_at`'s `tries`; the rest stay due, in place), so the view set's creatures arrive over the beat's first ticks, each where the cell cannot see it happen (the spawn check against the cell's places at that tick). S2G9's safety check now runs over every spawn of the beat at its tick.
  - **One pass unloads the old size.** `_unload_all` leaves the state and the events that unloading each chunk in key order leaves (test_growth_tick checks the two against each other), and hands the old tables (zones, streams, the items' index, sites, roles, homes, chunks) to `_retired` whole, fresh ones in their place, so their entries are freed on quiet ticks after the beat with the old chunks, items and arena.
  - **The next size's arena holds the view set.** The quiet-tick chore (`_arena_chore`) keeps in the next arena the chunks the growth tick at the cell's point would load (`_next_view_keys`: `view_set_keys` at size n + 1 with the origin at A, expression for expression) and the 3 x 3 round the chunk the cell heads for, one chunk a tick in and one out, so the growth tick's loads find their chunks held and add none. `ChunkArena.set_origin` returns at once for an unchanged origin (every centre is already that origin's).
  - **Quiet ticks prepare the loads further.** Besides each cached chunk's streams and payload (BP-4), `_prepare_next` makes its zones' region records (what `add_zone` makes, the centre still to place; `EcologyRegion.add_zone_prepared` places it) with their absolute places, and its sites' records (`_site_record_abs`, the local places still to derive). The load takes them; a chunk whose zone `add_zone` would refuse has no zone records prepared, and its load makes them.
  - **Readings** (this container, the fastest of 3 runs a seed): 1,900 to 2,700 µs, 28 to 36.5 yardsticks on seeds 2811 to 2816 (the yardstick is about 60 to 75 µs here and about 100 µs on CI, so CI reads about three quarters of this). The cold tick (no warm-up) is printed beside it, not gated: 4,300 to 7,200 µs.
- **The drain, 190 s a ring** (PROPOSED; data). S2G16's first-growth median read 176.2 s on the base, under its 3-minute floor (the limits stand). The median follows the drain: 97.1 s with the cap at ring / 90 and 176.2 s at ring / 180, about 18 s plus 0.88 of `drain_ring_seconds`. `growth.drain_ring_seconds` goes from 180 to 190, the one number moved; the rings, the floor share and the lumps stay. The soak (deterministic, so CI reads the same) at each value tried: at 180 the first growth 176.2 s (under the floor); at 185 178.7 s (under); at 200 197.8 s and the clumsy player 203.9 s, but dying on purpose 200.1 s against foraging 202.9 s (the dying omnivore's hunts grow it sooner, so S2G16's third check fails); at 190 the first growth 186.0 s (slowest run 212.7 s), the clumsy player 203.4 s, dying 193.5 s against foraging 190.4 s: all three pass.

## 2026-10-24 · B-7, the saturated load tick: the allocator, and loads that do one thing a tick (PROPOSED)
The B-7 soak gate times every tick of a dense 600-tick swim, 3 runs, and holds every tick that loads a chunk to 16 yardsticks at its fastest of the 3. It read 16.0 to 21.2 on CI and 13.2 to 20.7 here. These changes take the worst load tick from about 2,010 µs to about 1,190 µs here (the yardstick is about 68 µs on this container, 52 on CI), and leave the pool's output unchanged. Two of them change endless output only; the other two change nothing at all.

- **The allocator, not the load (exact).** The worst tick, 564, spent 230 to 280 µs inside its first large allocation. glibc merges every small block freed since its last large request when the next large request comes, so the first large request of a load tick (a chunk's 1 KB near grid) paid for every quiet tick before it. A tick that loads nothing now asks for and drops a `HEAP_SETTLE_BYTES` (4 KB) block at its end (`WorldStream._settle_heap`), so the merge happens on a quiet tick. No state is touched, so no output changes.
- **A tick unloads or loads, never both (endless only).** `_unload` returns how many chunks went, and `_load` takes the ring only when none did. The ring is 22 tm beyond the view and a tick's swim is under 0.2 tm, so a chunk held back one tick is still loaded long before it is seen. A waker's own chunks still load on the tick that needs them, whatever else happened.
- **A tick that loads a chunk spawns nothing (endless only).** `WorldStream.loaded_now()` is true on the tick that loaded, and `PoolSim` skips its spawn pass on it; the next tick takes the queue as usual. The pool has no loads, so its output is identical.
- **Route picks carried over a chunk change (exact).** `ChunkArena` keeps the last `ROUTE_CHANGES` (64) changes as epoch → (first index, shift, chunk key). A kept route pick whose epoch is older is carried instead of thrown away: if no changed chunk's square comes within the pick's own box (`ROUTE_CARRY_MARGIN_TM` of slack over the collider reach, the keep distance and the body), its near-collider indices are shifted by the adds and removes and the pick stands. Otherwise it is picked again, as before. The identity harness and the dense end hash are the same with the carry off and on.
- **The site queue goes in one batch (exact).** `_load_chunk` collects the chunk's due sites and calls `CreatureField._enqueue_retries(due, tick)` once, which places each exactly as the per-site `_enqueue` did.

Measured here, each load tick at its fastest of 7, in µs: before, ticks 188, 244, 508 and 564 read 1,119 to 1,347, 1,583 to 1,642, 1,293 to 1,361 and 1,992 to 2,013, with a plain median tick of 738 to 756. After, the ten load ticks read 1,008 to 1,188 and the plain median 749. The gate's own reading here is a median tick of 10.76 to 10.90 yardsticks (limit 10, and CI reads about 8.8) with load ticks of 9.3 to 17.1 (limit 16). **Then the load's own parts (exact).** A chunk's colliders, its zones' plankton streams and absolute centres, its zones' local centres and its `chunk_loaded` payload are made from the generated chunk alone, so a quiet tick now makes them (`_prepare_parts`, a whole tick's `PREPARE_PER_TICK` share, before the chunk's site records), and the load takes them. The local values and the payload are used only when every part and site record was made in the frame in force at the load (`_frame()`, the origin and scale; a record made in another frame marks the chunk mixed); a site record made in that frame is not derived again. Otherwise the load makes them as before. The identity harness's hashes and the dense end hash (2949906145) are unchanged. Load ticks here, fastest of 7: **793 to 985 µs** (from 1,008 to 1,188), plain median 694 µs. The gate here read load ticks of 10.6 to 16.65 yardsticks, 1 or 2 of 10 just over 16, with a median tick of 10.7 to 11.2; CI reads its own.

**On `e2`:** the s1 merge (`e30719f`) brings these in. Two of them change the endless results (a tick unloads or loads, never both; a tick that loads a chunk takes no spawns), so `tests/fixtures/endless_s1_hashes.json` is re-recorded at base commit `3724eeb`, as its own commit. With growth off, s1's identity harness computes the same nine hashes on the merge as on s1.

## 2026-10-24 · #29E, the 30 s after a growth: exact cuts (PROPOSED)
CI read #29E (each 5 s window of the 30 s after a growth, 12 remnants and 10 awake, at its fastest of 3 runs; limit 14 yardsticks, unchanged) at 14.51 and 14.07 in windows 1 and 2 on `9386c27`, the head that brought B-7 into `e2`. It passed on `dd137d7` before it. Counted with callgrind on the gate's own scene (deterministic, so the counts do not move run to run), B-7 adds 0.3 % of the scene's instructions a tick, and the heap settle alone 0.17 %: the gate sat on its edge, and the runner decided which side. This container reads 15 to 17 in those windows both before and after B-7. So the answer is less work a tick, not a different B-7.

- **The closing history (exact).** `Growth._note_closing` tests the cell's bite reach once a tick (`_bite_reach`) instead of in `_can_hurt` for every body, and keeps each tick's distances in the field's order: only `_closing_in` reads them, which asks whether any id closed, and `snapshot` already sorts the ids. The per-tick key sort and the second dictionary are gone.
- **Discovery (exact).** WorldGen puts every place and anchor inside its chunk's square (`WorldGen._in`), so `Growth._discover` passes over a chunk of the 3 x 3 whose square lies beyond the larger find radius plus `DISCOVER_SLACK_TM` (0.5 tm, far more than the local values' float32 rounding).
- **The remnants' views (exact).** `RemnantField.tick` made the camera's view of the cell once per remnant, and `may_leave` the zoom-max view of each place once per remnant: both are made once a tick now (`ViewFootprint.quad_contains`, `RemnantField.leave_views`), with the same corners.
- **Every creature seek keeps its route (exact).** `ChunkArena.route_point_kept` kept a route's colliders only while the start crept and the goal stayed put. It now keeps them while either end moves less than `ROUTE_KEEP_TM`, and every endless creature's seek (wander, forage, chase, flee) passes its own `RouteKeep`, so a chase whose prey drifts a little reuses the colliders it gathered. The kept answer equals `route_point` on 30,000 creeping and jumping calls (`test_a_kept_route_equals_route_point_while_its_goal_creeps_too`), and the scene's end hash, the nine S1 identity hashes and the dense B-7 end hash (1933848748) are unchanged.

The scene's end hash after the 1,800 timed ticks is the same before and after (1846101512), and so are the growth, remnant and endless tests.

## 2026-10-24 · Continue rebuilds the world from its seed (CONFIRMED)

Godfrey's test review round 3 (issue #77, PR #95) asked for a test that a save → load → continue run matches an
uninterrupted run tick for tick. That cannot hold under D6 and D16 above: Continue restores the cell, its body, lineage,
adaptation points and checkpoint, and repopulates plankton, creatures and shelter from the world seed. Asked whether to
keep that contract or change the save schema to restore the exact moment, Joshua chose **keep** (2026-10-24 00:07 UTC).
The seeded-restart contract stays; exact restores are a separate, later decision if a stage needs them.

## 2026-10-23 · Creature stage preview (PROPOSED)

The first playable slice of the creature stage (`docs/milestones/creature-stage-plan.md`), built under the owner's
standing rules; the generated-skin direction of 2026-10-23 is CONFIRMED, everything below is PROPOSED until the owner
says otherwise. It opens from the title's "Creature stage" button (marked Preview, below the main menu) or with
`--creature` after `--` (it uses the session's lineage slot, so `--slot=PATH` applies; the smoke uses it), and
the stage's own Escape leaves it for the title.

- **Saves (plan section 3).** Superseded on 2026-10-24 by save schema v3 (the entry below): the creature lives in
  the lineage save. The first version kept its own file, `user://creature_stage/slot_<n>.json` (`CreatureStore`),
  which is removed; nothing shipped wrote one outside the preview build.
- **The editor (plan section 4).** PROPOSED. A Spore-style room over the ported editor core: handles to drag, a
  tool per part type in the art records (read from `game/data/creature/part_rules.json`, compiled from the records
  by `tools/make_part_rules.py` since the records folder is not exported), a limb tool, undo and redo, mirror,
  insert and delete, eight skin swatches carried in the body's `skin_color` key, a test drive on the gait planner,
  and a method twin for every input path so the smoke drives it. Escape is progressive (tool, then an unsaved-edits
  prompt, then the title); Done on a legless body asks once.
- **The world (plan section 5).** `CreatureWorldSim` runs at 60 ticks a second from the world seed like `PoolSim`
  (whole-tick durations, sorts tied by id, every draw from a seeded stream, plain-data snapshots). A flat 160 m test
  field with a nest at the centre, fruit bushes that regrow and meat from kills, six rivals built from the starter
  bodies whose brains get percepts only (wander, graze, flee a bigger creature, hunt a smaller one when hungry).
  Anatomy sets play (`CreatureStats`): leg length gives speed and cadence through the gait planner, mouth parts bite
  power, eye parts sight, body volume health; a body with no mouth eats fruit by touch at half the points. Death sends
  the creature back to the nest at full health with a 20% points loss. Camera-relative movement, bite on F / pad X,
  evolve at the nest on E / pad Y. The numbers live in `game/data/creature/creature_stage.json` (PROPOSED).
- **Save schema v3.** Approved by owner direction on 2026-10-24 and built; see the entry below. The lab's
  `user://creatures/*.json` files remain importable as the same codec text.

## 2026-10-24 · Save schema v3: the creature in the lineage save (CONFIRMED direction; IMPLEMENTED)
Joshua (2026-10-24 00:09 UTC): "Then follow the Bible. That is your gospel." Bible section 18 asks for one save per
lineage with its genome and history, versioned migrations with fixtures, a last-known-good backup, and loads that
never silently drop body parts or lineage history. The creature stage's separate file did not meet that, so:

- **Schema.** `SaveGame.SCHEMA_VERSION` is 3. A new top-level field, `creature`, is `{}` until the lineage enters the
  creature stage, then `{"name", "body", "generation", "history"}`: `body` is the body codec's dictionary (extra keys
  such as `skin_color` kept), `generation` a whole number of at least 1, `history` a list. The creature's points are
  the save's `adaptation_points`: one lineage, one pool of points. IMPLEMENTED (`game/domain/save_game.gd`).
- **Migration.** `SaveMigrations` 2 to 3 adds `creature: {}`; v1 saves go through 1 to 2 and then 2 to 3, in memory,
  and the file is rewritten only by the next save. Fixtures: `tests/fixtures/save_v1.json`, `save_v2_step2.json` and
  the new `save_v3_creature.json` (a creature at generation 3 with two history entries). IMPLEMENTED.
- **Validation.** The creature's types are checked in `SaveGame.validate`; its body is checked against the body rules
  and the part rules by `CreatureRules` (`game/systems/creature/creature_rules.gd`), which `PersistenceService` passes
  in. A bad body fails the load with the reasons and the `.bak` loads instead, as with an invalid genome; parts are
  never dropped. A write is verified by reading it back, the creature's generation and body included. IMPLEMENTED.
- **The stage.** `CreatureStage` reads and writes the session's slot through `PersistenceService` (`--slot` applies).
  A slot with no save founds a lineage (`Lineage.found`, the omnivore cell, the stage's start points); a lineage
  without a creature gets the starter quadruped and keeps its points and seed. A slot that exists but will not load
  is shown on screen with the reasons and is never written over; Escape leaves. `CreatureStore` and
  `--creature-store` are removed (the old flag is now an unknown argument). IMPLEMENTED.
- **Unchanged.** The era stays `microscopic`: moving between eras is a Bible transaction and out of scope here.
  Continue still rebuilds the cell pool from its seed (the 2026-10-24 entry above).

## 2026-10-24 · Save schema v4: S2's cell fields with the creature (PROPOSED)
S2 (on `e2`) had built its own v3 (the cell's size and growth meter, the checkpoint, `spawn`, `gen_version`, the
player's energy and health; BP-18 and T4-a to T4-g above) while main took v3 for the creature (the entry above). Both
preview builds may have written v3 files. When `e2` merged main, S2's fields became **v4**, which holds both halves:
`SaveMigrations.v3_to_v4` adds `creature: {}` to a v3 file that lacks it (the S2 preview's) and S2's exact defaults
to one that lacks `growth` (the creature preview's), so either loads and Continues. v2 files go 2 to 3 to 4. BP-18's
freeze now names v4 (a later need is v5). The S2 fixture (`save_v3_s2.json`) stays a v3 file and is pinned to load
through the step unchanged but for the empty creature; the creature fixture is pinned to gain only S2's defaults.

## 2026-10-24 · Creature editor after the owner's playtest (PROPOSED; IMPLEMENTED)
Joshua played the creature stage (2026-10-24 02:39 UTC) and asked for easier editing, scalable parts and preset
creatures that also live in the world. Built:

- **Camera.** Right-drag orbits the creature, as middle-drag and the right stick already did; the wheel zooms between
  a quarter and four times the body's framing distance. The right mouse button is still bound to no input action.
- **Part size.** `+` / `-` and the wheel over a selected part grow or shrink it by 10% a step; a vertebra or joint
  thickens as before. The body rules' part scale range widens from 0.5x..2x to 0.25x..4x. A new part is sized to the
  body: scale 1000 on a body the size of the starter quadruped, in proportion on a bigger or smaller one
  (`EditorPicking.fit_scale`).
- **Presets.** Ten preset creatures, `game/data/creature/presets.json` from `tools/make_creature_presets.py`: raptor,
  dragon, monkey, beetle, longneck, tortoise, boar, stalker, hopper and strider. Each passes the body and part rules,
  builds a closed skin within the gameplay budget and walks on two or more legs (`tests/test_creature_presets.gd`).
  The editor offers them under "Start from" on a creature's first design (generation 1, no history); picking one is
  free and keeps the points. Back asks before leaving an uncommitted preset.
- **World.** The rivals' species are the presets (they were the test starter bodies), each in its preset's colour,
  still dressed with the world's random extra parts.
- **Palette.** The parts list scrolls inside a palette panel that fits the screen. A visual palette with part
  pictures is the next step.

## 2026-10-24 · Creature editor parts palette with pictures (PROPOSED; IMPLEMENTED)
Joshua's playtest: "you can't tell, it just lists the items". The palette now shows each part tool as a picture of
the art team's mesh, three to a row, with its name and price (the full price is in the tooltip). The pictures are
rendered at runtime (`game/scenes/creature/part_icons.gd`: one small SubViewport, each part framed from a
three-quarter view), so nothing is stored and new art shows on the next launch; headless runs render none and keep
the text. The presets moved into a "Start from a preset" drop-down so the palette fits a 900-row screen.
## 2026-10-24 · Creature size follows physics (CONFIRMED direction; numbers PROPOSED; IMPLEMENTED)
Joshua (2026-10-24 02:42 UTC): "a bigger creature is obviously going to be slower than a small creature. Same thing
with strength", with a level-up system for stats to come on top. `CreatureStats` now scales two numbers by mass:

- **Top speed.** The legs' Froude top speed still grows with leg length. Above `size.ref_kg` (120 kg) it is
  multiplied by (1 - e^-x) / (1 - e^-1), x = (mass / ref_kg)^-0.6: the saturation term of the allometric speed law
  (Hirt et al. 2017, big animals run out of time to accelerate). So 300 kg runs at 0.69 of its legs' speed and
  1.2 t at 0.35. The world sim scales the throttle by the same factor, so play matches the editor's number.
- **Strength.** Bite power is multiplied by (mass / 60 kg)^(2/3), muscle cross-section, kept within 0.25x..6x.
- **Not yet.** The incremental level-up system is still to be designed and built.

## 2026-10-24 · Creature progress: doing earns adaptation points (CONFIRMED by the owner; numbers PROPOSED; IMPLEMENTED)
Joshua (02:42 UTC) asked for an incremental level-up system on top of the size physics. PR #128 first built flat
stat levels (+5% a level, saved as creature `xp`). Asked what the Bible recommends (06:46), the answer was that it has
no level system: stats derive from anatomy with costs and caps (section 12), and progress runs through energy,
adaptation potential and knowledge (section 3). Joshua picked "Doing earns adaptation points" (06:47), which replaces
the levels:

- **Deeds.** Walking (1 point per 25 m), landed bites (2), hits survived (1) and each rival first spotted in a life
  (2) add adaptation points, the same purse eating fills; the world sim reports each as an "earned" event and the
  HUD flashes it. Numbers: `game/data/creature/creature_stage.json` "deeds".
- **Stats.** They come from the body and its physics only; the points buy body changes in the editor.
- **Save.** No new field: the points already save as `adaptation_points`. `CreatureLevels` and the creature `xp` key
  are removed; a save written with `xp` still loads, and the key is dropped on the next save.

## 2026-10-24 · The twelve preset creatures read as their archetypes (PROPOSED; IMPLEMENTED)

- Joshua (23:40) asked for the default creatures to look like what they are, the dragon most of all, and still
  belong in a Spore-like world. `tools/make_creature_presets.py` redraws all twelve on parts that already exist:
  the dragon has a long neck, swept horns, big wings, a row of back spikes, a spiked tail and heavy legs; the monkey
  has a big round head with a short muzzle, long arms it knuckle-walks on (the uneven-leg tilt stands it about 20
  degrees front-up) and a curling tail; the hopper is squat, with eyes on top, webbed feet and long hind legs folded
  in a Z. The others get distinct outlines: a rhino-horned beetle, a domed tortoise, a spider-bodied stalker, a
  maned boar, a cat-like prowler, an S-necked strider.
- `--report` prints each preset's legs as the gait planner reads them and the tilt they give. Folded legs keep
  their knee-to-toe piece rigid, so their gait length is short and a frog does not tip onto its nose.
- No save, schema or part changes. Screenshots: `screenshots/creature-stage/archetypes/presets_*`.

## 2026-10-25 · Creature skin covering picker (PROPOSED; IMPLEMENTED)
Joshua (2026-10-24 23:40) asked for monkeys with fur and frogs that read as frogs. The editor's palette gains four
covering toggles under the swatches: Smooth, Fur, Scales, Wet. The choice rides in the body's extra keys as
`skin_covering` (a whole-number float 0..3, smooth when missing or out of range; `creature_look.gd`), so no save field
or schema change. It reaches the skin shader as its int `covering` uniform, which the art thread owns. Like the swatch
it is free and outside undo. Presets and rivals wear the covering their body carries; a random first design draws one.

## 2026-10-24 · Creature gait follows limb proportions: bound and knuckle-walk (PROPOSED; IMPLEMENTED)

- Joshua (23:40) asked for walking that follows leg sizes and hands, frogs more frog-like and monkeys more monkey-like.
- Bound: a four-legged body whose hind legs are at least 1.5 times as long as its front legs bounds at run speed
  instead of trotting. Each pair moves together, the front pair lands first and the hind pair pushes off last, then
  every foot is off the ground. The body dips once per cycle and pitches nose down on landing, nose up in flight.
  Tuning: `game/data/creature/gait_table.json` (bound_*, the run band's long_hind_pattern).
- A body that bounds sits on folded hind legs (hips at 0.4 of their length), about level, like a frog, instead of
  standing front-down on straight hind legs.
- Long arms: a hanging limb whose root sits no higher than 1.2 limb lengths above the ground is a front leg, so an
  ape knuckle-walks, leaning onto its arms. Short arms still hang. Legs are ordered front to back by hip position.
- Short legs set the pace: speed and stride scale with the lowest standing hip, and no hip stands above 0.82 of its
  leg, so feet stay in reach. Even legs walk, trot and run exactly as before.

## 2026-10-24 · Creature head shape dials in the editor (PROPOSED; IMPLEMENTED)
Joshua (23:40) asked for more head shape options. The creature editor's stats panel gets five sliders: snout
(1.0x to 2.0x), skull width and skull height (0.6x to 1.6x; ranges agreed with the art thread), jaw and brow ridge
(0 to 100%). They are free, and a slider drag is one undo step.

- **Storage.** A `head_shape` block in the body's extra dictionary (per mille, whole-number floats, left out when
  neutral), which the codec keeps as an unknown key: no save schema or body version change. Ranges are in
  `game/data/creature/body_rules.json` "head_shape"; `validate()` refuses values outside them.
- **Shape.** The vertebrae do not move. `BodyField` scales the head end of the first spine capsule and adds up to four
  capsules around vertebra 0 (`game/domain/creature/head_shape.gd`) on bone 0, so the skin (CPU and GPU), the part
  anchors, picking and the bounds follow. A part on the head end rides out to the snout tip.
- **Cosmetic only.** The dials cost nothing, so they change no stat: mass (and the health, bite strength and speed
  built on it, in the world sim and the editor's panel) counts only the spine and limb capsules at their plain head
  radius (`BodyField.body_volume_m3`). `tests/test_creature_head_shape.gd` pins this. Giving the head a stat effect
  would need a cost and the owner's sign-off.

## 2026-10-24 · Creature legs of different lengths tilt the body (PROPOSED; IMPLEMENTED)

- Joshua (23:40) asked for walking that follows leg sizes. Every leg now stands at the gait table's
  stance_height_ratio of its own length, instead of every hip standing at the shortest leg's height.
- A least-squares line through those heights along the body sets the hip height and a standing tilt, capped at
  30 degrees. An ape on long arms knuckle-walks front-up, and a body on long hind legs stands front-down.
- Even legs stand level as before.

## 2026-10-24 · Creature weapons add to the bite (PROPOSED; IMPLEMENTED)

- Weapon-role parts (claws, horns, spikes, tusks, tail spikes, club tails, quills) add 2 attack each at scale 1
  (times scale), before the body's strength factor, and the largest four count. Tuning is `creature_stage.json`
  "weapon".
- A creature attacks with its mouth, so a mouthless body gains nothing from weapons. The cost is the parts' editor
  price, as for every part (Bible section 2: every change has a benefit and a cost).

## 2026-10-24 · Mating at the nest calls a mate before the editor (CONFIRMED direction; presentation PROPOSED; IMPLEMENTED)
Joshua (07:39): keep Spore's breeding, where mating at the nest opens the editor. Evolving at the nest (E, pad Y) now
calls a mate of the player's own kind. It walks up beside the player, a heart rises over the pair, and then the
editor opens. The beat lasts `CreatureWorld.MATE_BEAT_S` (2.5 s) and the world holds still during it. The mate is a
twin of the player's body: an egg, a hatchling and mates of other kinds come later.

## 2026-10-24 · Creature stage friend path: sing to befriend, allies follow (CONFIRMED direction; numbers PROPOSED; IMPLEMENTED)
Joshua (07:39): keep Spore's fundamentals, including "dancing, friend/foe", built better with the Bible's ideas.
The creature world now has both paths. Bite (F, pad X) is the foe path. Sing (R, pad B) is the friend path:
- **Songs.** Each song, facing a creature up close, adds the singer's charm to its friendship. Charm is base 1, plus
  0.5 for each display organ (every detail-role part: crest, frill, lure, antenna, barbels, gill fan, wing, fin, tail fluke), counting at most four of them
  (Bible §12: communication organs give signal, with diminishing returns).
- **Allies.** A creature at friendship 5 joins the pack, which is worth 10 adaptation points. Allies follow the
  player and attack whatever it is fighting. The player and its allies never bite each other.
- **Anger.** A creature the player bites stops listening for the rest of its life. Biting an ally drives it out of
  the pack.
- **Not saved.** Respawned creatures are new individuals. Allies last only for the visit and are not saved yet
  (Bible §18 relationships come with species memory later).

Tuning lives in `creature_stage.json` "social". Spore's call-and-response minigame is not copied: the Bible §14
avoids a universal rhythm minigame unless approved.

## 2026-10-24 · Creature editor palette grouped by kind (PROPOSED; IMPLEMENTED)
Joshua (07:39): keep Spore's fundamentals, built better with the Bible's ideas; the playthrough notes
(docs/research/spore/PLAYTHROUGH_VIDEO_NOTES.md) show the editor's part grid grouped by kind on the left with the
creature on a plinth on the right. The palette gains tabs (All, Mouths, Senses, Limbs, Weapons, Details) above the
part pictures; picking a tool by key switches to its tab, and a part type art adds later lands in Details until it
is listed in `CreatureEditorHud.PART_CATEGORY`. Layout and styling stay Pangaea's own.

## 2026-10-24 · Twelve preset creatures and a Random creature button (owner ask; designs PROPOSED; IMPLEMENTED)
Joshua (07:46) asked for 12 default creatures, or a button that makes a random creature. Both are built:
- **Presets.** Two new ones, Prowler (a maned four-legged hunter) and Angler (a round lure-headed ambusher),
  bring the count to 12.
- **Random creature.** The button sits beside the preset menu, for a first design only. It picks a preset and
  dresses it with extra parts the same way the world's rivals are made, so every result passes the rules. It then
  picks a random swatch colour and coat. Like a preset, it costs nothing.
More variants of each part type (eyes, feet, hands...) need new Blender meshes from the art team; the palette and
its tabs pick them up from the records.

## 2026-10-24 · The sea's pieces load on the main thread at setup, not on worker threads (PROPOSED)

- **Why.** The Windows launch check's grow run (D3D12 on WARP, the CI runner's software renderer)
  stalled for its whole 300 s on two runner hosts out of three. The perf tour's watch thread placed
  the stall in the engine between the nodes' process steps and the draw, at route tick 15, about
  when the sea's worker-thread GLB loads (`ResourceLoader.load_threaded_request`: landmark and rare
  pieces since S1, shell pieces and the lair mouth since S2G26) finish. Every other renderer and
  run passed, and main, with no such loads, passes on the same runners.
- **What.** `LandmarkLayer.load_pieces`, `RockField.load_pieces` and `SiltTrail.load_mouth` load
  those 17 GLBs on the main thread when the sea is set up (the start of a run or a Continue), each
  once a run and kept. No growth or chunk frame loads a GLB, so S2G26 and G18 hold as before; the
  cost moves to the run's start: about 0.9 s headless on the Linux container (9 to 150 ms a piece).
- **Revisit.** A loading screen or a spread-out load at the start, if 0.9 s shows on the owner's
  PC. Worker-thread loads come back only with a Windows WARP run that passes several times.

## 2026-10-24 · S4.1 pacing: parts cost four times as much, and finds pay points (PROPOSED)

- **Why.** After his playtest the owner asked for Spore's loop: mate with a cell like yours and add
  parts, instead of grazing for 20 minutes to level up (docs/s4/s4-plan.md). Measured first (ForageBot
  grazer and omnivore, HuntBot hunter, seeds 11 and 12, growth on, 9 minutes): points are plentiful.
  The grazer had 46 points at 3 minutes and earned about 15 a minute (plants 118 of 146), the hunter
  66 and about 25 (meat 174 of 222, 19 kills). At the M1 costs (10 to 25) the first mate would buy
  three parts and the eight slots would be full in under 10 minutes.
- **What.** The editor parts cost four times as much: mouth_filter, cilia and eye_spot 40, mouth_jaw,
  flagellum and spike 60 (shell_plate 80 and toxin_gland 100, not in the editor yet). A new place
  pays 10 points and a new landmark 20 (`growth.points` in world_cell.json, at every size, as
  `earned {points, reason, id}`, toasted "+10 points · new place"), so exploring earns parts too.
  Food and survival points stay (M1's goldens hold them); kills pay through their meat.
- **Gate.** `tests/test_pacing_gates.gd` (soak): the grazer and the hunter can afford the cheapest
  part by 3 minutes, and earn a part of the mean editor cost every 1.5 to 4.5 minutes.
- **Revisit.** After the owner plays S4's mating: the costs and the find points are data.

## 2026-10-24 · S4.3 kin and mating: a cell like yours swims in when you can mate (PROPOSED)

- **What.** `Kin` (game/systems/world/kin.gd), with growth on: once the cell has 70 % of its energy
  (Lineage.REPRODUCE_ENERGY_SHARE) and the points for the cheapest editor part for 3 s, a cell drawn
  from its own genome swims in from 12 radii away and keeps 2.6 radii beside it, pulsing softly.
  Swimming into it at a calm moment (Growth's blockers: not hunted, no fight in the quiet ticks; a
  recent meal is fine) reports `mate` once; the pool scene emits `mate_requested` and, once the editor
  (S4.4) closes, `finish_mate()` sends the kin away. Not ready for 20 s, 40 radii away, a death, a
  respawn or a growth also send it away. The HUD says "A cell like you is here. Swim into it to mate."
- **Bible.** Section 5's "reproduction opens a bounded editor at a safe opportunity" and section 24's
  one reproduction interaction: the touch is the interaction and the calm moment the safe opportunity.
- **No change to the sea.** The kin is no creature: no brain sees it, it never fights, eats or
  blocks, and it takes nothing from any random stream, so a run with it hashes as one without
  (`test_kin`). It is not saved. Pool mode and S1's sea (growth off) have none.
- **Defaults for the owner** (s4-plan's open questions): the kin comes on a call rather than
  always swimming in the sea; it is harmless.

## 2026-10-24 · S4.4 the cell editor: mating builds the next generation (PROPOSED)

- **What.** `CellEditor` (game/ui/cell_editor.gd), a UI over `EditorSession`. The kin's `mate` opens
  it over the paused sea. Its parts:
  - a palette of editor parts with their costs;
  - a rim view where parts are placed, selected and dragged round the cell, with the front at the top;
  - the 3D `CellPreview`;
  - a before-and-after table: speed, turning, health, bite, ram, defense, sight, energy use and mass.
    Energy use and mass are better lower.
  - Controls: Add, Remove, Bigger and Smaller, Mirror, Undo and Redo (also keys), Back and Mate.
- **Commit.** Mate calls `Lineage.reproduce` (70 % energy, points paid). `PoolSim.apply_offspring`
  then re-derives the body where the cell is, keeping its shares of energy and health. The game
  autosaves, and the HUD says "Generation N". Back closes without a generation, and the kin leaves
  either way.
- **Placement.** A mouth goes to the front, propulsion to the back when the back is free, and
  anything else to the widest gap.
- **Bible.** Section 5's bounded editor with previews of speed, turning, feeding, defense and energy
  demand. Section 18: the genome and lineage are saved, not the sea.
- **Not yet.** The test pool to swim the new body before committing (IB-03), part levels (S4.5) and
  mass on turning (S4.2, deferred because it re-records every golden).

## 2026-10-24 · S4.5 part levels: upgrade a part in the editor (PROPOSED)

- **What.** Joshua's "level up your strengths... an incremental system" (2026-10-24 02:42), as part
  levels:
  - The editor's Upgrade raises the selected part from level 1 to at most 3. Each level multiplies
    the part's benefits by 1.4 then 1.75, and its mass and upkeep by 1.2 then 1.4. So a level 3 tail
    is fast but heavy and dear to run, and mass still slows the whole body.
  - Level 2 costs the part's price again, and level 3 costs 1.5 times it. Selling an upgraded part
    refunds the part and its upgrades.
  - A filter mouth has no benefit to raise, so it does not level.
  - All numbers are in `part_catalog.json` (`part_levels`).
- **Saved on the genome.** A part's `level` is saved only above 1. Saves made before levels load as
  level 1 and derive, cost and serialise exactly as before. Level 1 shares are 1.0, so every golden
  is unchanged.
- **The look.** An upgraded part is drawn 15 % larger for each level, and the rim view puts a pip
  outside it for each level.
- **Shell plate.** The shell plate enters the editor, as s4-plan proposed (band 1, art PR #42's
  model). It gives defense and health and is the heaviest part. The editor list test now pins seven
  parts.

## 2026-10-24 · S4.6 acceptance for the mating loop (PROPOSED)

- `tests/test_s4_acceptance.gd` runs the shipped endless sea and checks:
  - a grazer is readied, meets its kin, swims into it, and is born twice: first with a second tail,
    then with that tail at level 2;
  - an edit it cannot pay for is refused and changes nothing;
  - save and Continue bring back the same genome, points and two births;
  - two deaths keep the body and each takes a quarter of the points.
- **Open (rule 3 against edited bodies).** The pursue bound is checked against the slowest *starting*
  body. A heavy edited body (shells, spikes, no tail) can be slower than a hunter's chase. That is
  the size and strength tradeoff Joshua asked for, so the editor allows it. The proposal is that the
  editor warns "Hunters can catch this body" instead of refusing; it is not built yet.

  the size and strength tradeoff Joshua asked for, so the editor allows it. Built (S4.4): the editor
  warns "The <hunter> can catch this body: it chases at x, this body swims y." when the working body
  is no faster than `SpeciesCatalog.fastest_chase` at the cell's size, and Mate stays allowed.

## 2026-10-24 · S3 T0.1: the size 1 and 2 baseline on e3-base (PROPOSED)

- **`e3-base` is a branch, not a tag.** The proxy refuses tag pushes and ref writes here, so the
  base S3 is measured against is the branch `e3-base` at a9afd3b (main with the S4 stack).
- **Hash identity (S3G34).** `tests/fixtures/endless_s2_hashes.json` holds six runs at sizes 1 and 2
  recorded on `e3-base` with `max_in_build` 2 and `landmark_return` off; `test_hash_identity`
  replays them at 600 ticks (fast) and 18,000 (slow).
- **Cost baseline (BP3-7)**, from main's CI run 40084302551 (soak-a), each the median run:
  - size 1: #28E 4.28 yardsticks, P99.9 13.21, rebase +1.50, saturated (B-7) 9.75 of 10;
  - size 2: #28E 5.00 yardsticks.
  - `BASE_GREEN` in `tests/test_endless_cost.gd` records these rows as green. Size 2's P99.9,
    rebase and saturated rows had no case on the base; T0 measures them before I-3.
  - The size-1 #28E median is far under 7.6 yardsticks, so section 8's size-3 lever is not needed.
  - The saturated row sits at 9.75 of 10. A size-3 saturated case that blocks on it has little room;
    the relative row (size 3 at most 1.15 x size 1) is the one to watch.

## 2026-10-24 · S3 T1: the hazard rules and the four new species (PROPOSED)

- **The species catalog** (s3-sim 3.2) gains the hazard behavior and its rule 14 (D-121, D-122),
  `radius_at` (D-139) and a hazard's reach disc of leash plus a thread (D-121). The brain's cfg
  carries a hazard's drift and threads in ticks (D-124), built in T1.1 because the catalog reads the
  sting cooldown from it.
- **`creatures_m1.json`** gains the stinger veil and the Warden (entry size 3) and the Deep lurker and
  elder Warden (entry size 4), as s3-sim 4.2 gives them, none with a pool site, so the M1 and S2
  hash files replay unchanged. Two changes from 4.2:
  - The elder Warden keeps the elder rammer's 16 s `nav_timeout_s`, not the rammer's 8 s. D-147's
    12.8 s move between meadows is 0.8 x 16 s; with 8 s the post-travel rule refuses every meadow
    pair D-147 allows.
  - The Warden, Deep lurker and elder Warden tips keep 4.2's advice and add the M1 strike's dodge
    ("swim out of its line on the side you face"), which F2 requires of every species that strikes.
    The veil never strikes, so its tip names its threads instead.
- A hazard's threat-arrow glyph is "warning". The veil never engages, so it never shows.

## 2026-10-24 · S3 "Band 1": the build decisions, and T0's readings (PROPOSED)

S3 (cell sizes 3 and 4, band 1) is planned in four files in the project files: the spine
`docs/s3/s3-interfaces.md`, the sim half `docs/s3/s3-sim.md` (T0 to T3), the view half
`docs/s3/s3-view.md` (T4 and T5) and the corrections layer `docs/s3/s3-build-plan.md`, which wins
where they differ (then s3-sim for T0 to T3 and s3-view for T4 and T5, then the spine). Every number
not verified there is PROPOSED tuning held in data or a named constant. Standing rules (owner): the
GENESIS Bible is binding; never wait on Joshua; merge when green; never change a cost-gate limit.

- **Ids in this entry.** D-88 to D-118, C3-n and Q3-n are the spine's; D-119 to D-147, X3-n and
  SQ3-n are s3-sim's; V3-n, C3V-n, Q3V-n and A3V-n are s3-view's; BP3-1 to BP3-20 are the build
  plan's. Gates S3G1 to S3G42 are the spine's, lettered sub-gates s3-sim's, S3G43 s3-view's, and
  S3G5c, S3G12e, S3G14b, S3G17d, S3G24d, S3G34b, S3G39b and S3G42c the build plan's.
- **The build plan, BP3-1 to BP3-20.**
  - BP3-1. The integration branch is `e3`, the tracks `e3-t0-gates` to `e3-t5-worldview` (never
    `s3-*`, which M1 holds). `e3-base` is main with S1, S2 and S4 merged (a branch: tags are refused
    here). Precedence as above; push after every commit.
  - BP3-2. S3G34 holds by keys: `hazard_live` gates the sting and strike-hit snapshot keys, and
    `debug_set_size` resets them (a cut). The S2 identity hashes are recorded on `e3-base` with
    `max_in_build` 2 and `landmark_return` off and replayed in `test_hash_identity` (T0); S3G34b in
    `test_stings` (T2).
  - BP3-3. `_morsel_live` is replaced by `_claims`, kept exact through `_set_food` and `_drop_entry`;
    `morsel_claims()` for the checker; S3G17b's three cases and S3G17d on every fuzz tick.
  - BP3-4. A sting's `hit` carries `engaged` (sorted, at the sting); invariant 15 (c) reads it, not
    the before-snapshot (S3G14b, S3G12e).
  - BP3-5. S3G39b (T2): arrival equality at 2 to 3 and 3 to 4, and prefetch neutrality.
  - BP3-6. S3G20 (band-1 chunk cost) is T3's, measured in the same run as band 0, with absolute and
    relative rows and a data lever.
  - BP3-7. S3G21's rows: size 3 at most 1.15 x size 1 and size 4 at most 1.10 x size 2 (#28E and
    saturated medians, blocking); the absolute rows block where `BASE_GREEN` has the row green at the
    size they are held against. Replaces D-115's merge rule and settles Q3-11.
  - BP3-8. The landmark spiral is bounded (`LANDMARK_SPIRAL_RINGS` 8, 4 tm); "no_clear_point" and
    the new "unloaded" refusal; D the respawn clear radius plus the cell plus twice
    `reach_max_threat`; S3G5c, S3G42c, S3G24d; S3G26's mutation is the unbounded spiral with a
    blocked anchor.
  - BP3-9. Cross-track rows land with the track named in the build plan's 4.1.
  - BP3-10. The spine's tile and cradle examples are replaced by two schema-example fixtures; the
    tile rules read band-1 regions, rare kinds, transit and the elder-Warden posts.
  - BP3-11. File owners: `test_fuzz_invariants` is T0's; asset tables stay art's; S3G23 in
    `test_growth_gates` (T0); `test_endless_sim` is T2's.
  - BP3-12. S3G28 compares the state hash and the save dictionary; T2.8's round trip is three key
    checks; `EcologyRegion.tick(dt, tick_number)`.
  - BP3-13 to BP3-20 as the build plan's table: D-134's anchor rule at band 1 and up only; the cradle
    ring follows PR #64 (14.0625); `write_kit.py` amends D-143; hooks follow function names;
    `switches.landmark_return` and partial bands; band-0 live sets unchanged; a sting's `engaged`
    is event-only; the checker clears invariant 15's windows at a `set_size` cut.
- **The spine's D-88 to D-118 and s3-sim's D-119 to D-147.** Adopted as the build plan amends them:
  D-114's fixture sentence (BP3-2), D-115's merge rule (BP3-7), D-126's snapshot keys (BP3-2),
  D-132b's spiral (BP3-8), D-134 (BP3-13) and D-143 (BP3-15). D-121's veil `leash_m` is 4.75, not
  the spine's 7.0.
- **Contradictions and questions.** The spine's C3-n, s3-sim's X3-n and s3-view's C3V-n are adopted
  as the build plan's 4.1 and 4.2 settle them; Q3-1 to Q3-13 as its 4.3 answers them (Q3-6: the Deep
  lurker's `fov_deg` 90, 120 if S3G10 is red); SQ3-n and Q3V-n as written. C3V-16's two `check.sh`
  lines (s3-view 16.3) wait for T5's `band_up` and `band_up_continue` smoke phases, which are not on
  `e3` yet; T0 adds them in a T0.9 commit when they land.
- **T0's lines** (PROPOSED; the gates track's own readings and the ways it read the plan).
  - T0.1. `e3-base` is a branch at a9afd3b; the size 1 and 2 baseline is the entry above.
  - T0.3. Invariant 7's hazard form allows a hazard that enters DRIFT off its path (a spawn at home,
    the end of a flee, a wake) the gap at rule 14 (f)'s margin on top of D-141's 120 ticks; one that
    enters on its path keeps the 120. Invariant 4's lane origin may move past `LANE_DRIFT_M` when the
    cell itself leaned on the creature in its tell (a size-4 tour moved a telling Deep lurker 0.70
    tm). D-117 (b), the sunbeam well, runs on the shipped world, because `world_b1_min.json`'s tiles
    break the real kit's rules.
  - T0.4. The size-4 tours' creatures eat each morsel item soon after it spawns, so no item is live
    at an unload on a tour; that clause is read by `test_morsel_sites` and `test_fuzz_invariants`.
  - T0.5. The S3 gates run on the shipped world with its top at 4 (`Gates.make_sim_at`), set to the
    size by `debug_set_size`, with bots that never press Grow; foragers unjam at sizes 3 and 4, because
    band 1's cracks jam a ForageBot (seed 502's grazer stuck 100 s and starved). #32 counts a veil's
    sting as a meeting (a veil never notices or tells). The bloom gate compares a hungry camper's
    yield in an elder Warden's meadows with each meadow's plain twin over six cycles: 1.04, with the
    x2.0 bloom mutation 1.27.
  - T0.5, a balance finding put to the owner: #32 is red at size 3 (0.3 to 0.7 meetings a minute
    against 1.0). Size 1 reads about 4 a minute and size 4 about 3. A species never lives below its
    entry size, so at size 3 only the Warden and the veil are at q 1; the rammer, ambush hunter,
    lurker and elder rammer are outgrown (q 0.39 to 0.625). Veil gardens and glass reefs hold veils
    alone, a forager seldom touches a thread, and the unguarded elder-Warden mounds (capacity 18) are
    its favourite size-3 food. Probes in a scratch copy, none shipped: Wardens on the mounds and veils
    on the mounds and the food gave the grazer 0.47 from home and 0.84 from points and the omnivore
    1.27 and 1.46; a second Warden per flat and veil per reef did no better; an ambush hunter
    stand-in at entry size 3 left the grazer at 0.40 from home. Moving veils onto food also breaks
    rules 6 and 12 in most tiles. So the first card ("as tense as size 1" by moving threats) was
    withdrawn, and a second asks between a calmer size 3 (one meeting every 4 minutes, a run may meet
    none; recommended, unblocking S3) and a new size-3 hunter species (scope beyond S3, new art).
  - T0.5b. S3G23's medians pool the grazer and the omnivore (12 runs), as S2's first-growth gate
    pools its bodies: second growth 385.6 s, third 944.2 s against 960 (grazer 772, omnivore 1,137).
  - T0.6. S3G21 runs sizes 1 to 4 in one process on the top-4 world. Relative rows on a dev
    container: #28E 7.13 against 7.19 at size 3 (tight) and 7.43 against 7.76 at size 4; saturated
    green at both. That container put size 1's own P99.9, rebase and saturated rows over their limits
    too (17.1, +2.25, 13.4 in their own tests), so the absolute rows are read on CI. S3G21b reads
    0.25 to 0.29 yd after `_landmark_pass` keeps the 3 x 3 chunks' anchors between chunk changes
    (10.5 to 3.3 us a tick, the same choice); the route wakes no veil, so its sting row is the gates
    and the awake scan. S3G19: warm 31.2 (2 to 3) and 25.8 (3 to 4) at worst.
  - T0.7. S3G26 runs the 10 tests' checkpoint rules at 50 landmark checkpoints in one soak case (the
    save-side tests do not depend on the checkpoint's place; S3G33 covers the save at size 4). The S3
    save fixture is `tests/fixtures/saves/save_v4_s3.json`, not `save_v3_s3.json`: this build's writer
    stamps schema 4 (the creature save work); S3 adds no field (D-142).
- **CI.** soak-a (endless gates and cost) read 8.4 min and soak-b 26 min on main's last run. With
  T0.5 to T0.7, soak-a's 16 cases took 28.8 min on this container (4 CPUs, shared with balance probes
  the whole time, so slower than CI); S3G26 adds about 1 min to soak-b. Both stay inside each job's
  60-minute bound, so the split stays as it is; the PR's first CI run gives the real figures.
  The same run's reds: S3G22's #32 at size 3 (below), and the cost rows that fail here at size 1 too
  (saturated, the racer, S3G21's absolute rows), which CI reads (BP3-7).

## 2026-10-24 · S3: the owner's calls on cost limits and size-3 danger

Joshua answered four cards at 16:47 to 16:48 UTC.

- **soak-a's two cost limits: raised to 11 and 2.5 yardsticks** (card "Raise soak-a's two cost limits
  to cover the spread between CI runners?", option "Raise to 11 and 2.5"). `DENSE_LIMIT_YARDSTICKS`
  10 → 11 (B-7's saturated case, the median run's median tick) and `REBASE_LIMIT_YARDSTICKS` 2.0 → 2.5
  (a rebase tick's median excess). The cases are renamed to the new numbers
  (`test_soak_a_saturated_world_costs_at_most_11_yardsticks_a_tick`,
  `test_slow_a_rebase_tick_costs_at_most_2_5_yardsticks_more`). Reason: the same tree read on either
  side of the old limits on different CI runners. Every other cost limit is unchanged.
- **S3G20: band 1's chunks may cost 1.20 × band 0's** (card "Accept band 1's world-loading cost being
  15 to 20% above band 0's?", option "Accept 1.20x for band 1"). The relative rows of
  `test_slow_band_1_chunks_cost_as_band_0s` become median and p90 at most 1.20 × and max at most
  1.35 × (1.10 and 1.25 before). The absolute rows (G17's at size 3, S2G37's at size 4) are unchanged.
- **Size 3 is as tense as size 1, with a new size-3 hunter** (cards "How dangerous should size 3
  feel?", option "As tense as size 1", and "Size 3 can't match size 1's danger by moving creatures.
  Which way?", option "Add a new size-3 hunter"). T0.5c (the calmer size-3 bar) is reverted: #32 at
  size 3 needs M1's 1.0 meetings a minute and a meeting in every run again. A new species, an elder
  ambush hunter entering at size 3, joins the glass reefs and veil gardens; it is a scope addition the
  owner approved here. Its body is a stand-in until art delivers its model, ghost and haze sprite.

### The elder ambush hunter as built (S3G22)

- **Species** `elder_ambush` ("elder ambush hunter"): entry size 3, behaviour ambush, the M1 ambush
  hunter's numbers (speeds, leash 9 m, lunge, tell 1.2 s, start energy 0.9, hungry below 0.6) with two
  eye spots added, so its sight is 12 m: it sees across the mound or zone it waits beside. At size 4
  it is outgrown (q 0.625) and answers to the prey share, as the Lurker and the Deep lurker do one
  size past their entry. Art's body (`creature_elder_ambush_body`, eye_emission_rest 0.5) and near
  ghost (`T_Ghost_elder_ambush`) landed the same day; its haze is the ambush hunter's. The ladder
  strip's caption is "elder hunters" (three words do not fit 68 px at the largest text size).
- **Where it lies in wait** (all sizes [3], every tile passing rules 6 to 10 at sizes 3 and 4):
  - glass reefs: `ea` 3 to 4.5 m off the central zone; `eb` by an outer pocket of food, by the Lurker's
    corner in reefs a, c, d and f and in the east pocket of reefs b and e, which the #32 point runs
    showed held no threat at all at size 3. The Lurker leaves size 3 in reefs (rule 7's four sites;
    the outgrown ambush hunter stays as the prey rule 9 needs).
  - veil gardens: `ea` 3 to 4.5 m off the inner mound; the second veil (`vb`) leaves gardens a to e.
  - warden flats: `ea` 3 to 4.5 m off the inner mound (unguarded at size 3; the elder Warden takes it at 4);
    in flats b and e it takes the second Warden's place (rule 7). This goes one tile kind past the
    card's "reefs and veil gardens": the mounds were where the quiet #32 runs fed.
  - the cradle: one by each quadrant's inner meadow.
  Every `ea` keeps at least 2.9 m outside every zone. Placed right beside them first, the hunters
  pushed the wary forager off the richest food at size 3 (it skips food within 8 m of a creature),
  and the pacing gate's third growth went from 944 s to 1109 s.
- **Measured** (#32 at size 3, 3 home seeds and 10 points, 5 minutes each): grazer 1.53 meetings a
  minute from home and 1.84 from points, omnivore 1.40 and 1.88, a meeting in every run, no deaths.
  Before the reefs' second hunters one point run (seed 516) met nothing even at 15 m sight, and a
  hungrier start (0.7) changed nothing; with them, two eye spots are enough.
- **The size-3 growth ring is 120, down from 150 (S3G23; Joshua, 02:42: faster progression)**. With the
  hunters off the zones the pacing gate still read 1096 s. The slow runs are not held by a blocker:
  they roam far from home, where size-3 food is thin, so energy sits under the drain floor (80%) and
  the meter barely moves. A smaller ring is the one lever that touches size 3 alone (the drain floor
  would move the first growth under its 3-minute floor). Measured over the gate's 12 runs: ring 130,
  1017 s; ring 120, 932 s (grazer 753 s, omnivore 1092 s). Rings now read 90, 120, 120, 170. Open:
  two of the six wary omnivore runs (seeds 622 and 624) never reach size 4 in 22 minutes, with about
  230 meals each; the size-3 food economy for an omnivore is a balance item for the next pass.

## 2026-10-24 · S3 T4.4: the ghost ladder reaches sizes 5 and 6 (PROPOSED; IMPLEMENTED)

- **Rows**: the engulfer (entry 5, 0.85 tm) and the lancer (entry 6, 0.70 tm) join `ghost_ladder.json`
  with art's measured body rects and no haze yet (an empty haze is skipped by the file checks and
  by `haze_paths`); the band-1 foods' hazes (glass flake, bead cluster) join `food_haze`, and the
  top-of-ladder preview at 4 names the engulfer.
- **A long body is sized by its length on screen (V-11)**: near quads lie flat with the texture's
  top to the north, so a body long from north to south shows that length foreshortened by the view
  (`GhostLayer._foreshortening`, measured through the camera at the ghost). `_rule_side` divides by
  the larger of the rect's width and its height times that factor. Every ghost with a rect wider
  than tall is unchanged; the lancer now draws at least 1.4 cells along its length at sizes 1 to 4
  and zooms 10, 14 and 20 (it drew 0.98 before). `test_near_ghosts_draw_at_least_1_4_cells` measures
  each ghost's longer side on screen.

## 2026-10-24 · S3 T4.5: the haze of older sizes (V3-14; PROPOSED; IMPLEMENTED)

- **What**: `OlderHaze` (`game/scenes/pool/older_haze.gd`, `older_haze.gdshader`) as s3-view 9.3
  writes it: from size 3 one MultiMesh of the size before's plant-food haze (the algae ball at 3,
  the glass flake at 4), 24 per 32 tm chunk on a jittered 5 x 5 grid over the focus chunk and the
  eight round it (216), 2.6 to 3.4 tm under the plane, tinted #B8C4D6 at brightness 0.7 and opacity
  0.25, in the fog. Places come from `WorldHash.hash_ints(seed, size, cx, cy, i)` split three ways
  with `mix32`, since `mix32` takes two words. It rebuilds only when the cell's chunk changes.
- **Growth**: a registered growth container. It re-expresses in place, keeps the old set through
  the beat, and at `end_growth` draws the new size's set, fading in over 1.0 s. A growth to 3 brings
  its first set in at 2.0 s of the beat. The pool tells it the new size (`begin_growth`) before
  `apply_growth`. The fade runs on the drawn sim time, so it stops while paused.
- **Contract reading (test_ambience_contract)**: the contract read a shader material's textures and
  colour uniforms separately, each times `brightness`. The haze sprite's white core read 0.45 luma,
  over the 0.40 limit under the plane, though the shader draws texture x tint (0.25). A texture is
  now read times the material's `tint` uniform when it has one, as a standard material's albedo
  texture is read times its albedo. No other contract material has a `tint` uniform beside a
  texture, so no other reading changes. The tint still counts as a flat colour too, so a tint in the
  food hue still fails.
- **Note**: T4.4's commit cited V3-14 for the ghost rows; those rows are V3-13's ladder work, and
  V3-14 is this haze.

## 2026-10-24 · S3 T5.1: the old band below (V3-3 to V3-5, V3-21; S3G28, S3G29; PROPOSED; IMPLEMENTED)

- **What**: `OldBandLayer` (`game/scenes/pool/old_band_layer.gd`, node `OldBand`) as s3-view
  section 5 writes it. From band 1 it draws the band before's landmarks and rare set pieces sunk
  under the plane at their true size: absolute am = (x_bu, y_bu) x 2.56^b, scale = piece scale x
  2.56^b / 1.6^(n - 1), top at `top_target_tm(h)` (-2 tm for pieces up to 1 tm tall, -3 from 3 tm).
  It builds its own `WorldGen` from the same content and seed, and no sim file names it (S3G28: the
  sim's hashes and the save are the same with it on and off).
- **Bake**: each band-0 model (6 landmarks, 2 rare kinds) is baked once a run into one surface with
  vertex colours = the old colour of each surface's albedo (desaturated 0.65 in linear light, luma
  capped at 0.30), one material per model with the model's detail texture. Measured: every colour
  at luma 0.27 to 0.30, chroma at most 12, at least 33 degrees of LAB hue from food and 63 from
  threat. The mesh stores 8 bits a channel, so colours are rounded down to keep the cap.
- **Two sides**: a MultiMesh has no per-instance mirror flag, so a mirrored rare piece would draw
  inside out. The baked materials draw both sides; the pieces are opaque and closed, so the cost is
  small.
- **Pool wiring**: registered container and growth container (`old_band_enabled` false skips
  setup); `set_band` at the build, at `debug set_size`, and in `_begin_growth` after
  `apply_growth` (the in-band 3 to 4 growth eases each instance's y to its new target over the beat,
  V3-7); `refresh` on respawn and teleport; `tick` each frame refreshes every 0.5 s outside a beat and
  bakes one model a frame until all are baked. The band-up fade and hand-off are T5.2's.
- **Refresh cost**: the pieces of a cell or block are pure, so the layer keeps them (at most 4096)
  between refreshes. Median 0.35 ms headless over 100 refreshes moving 2.2 tm each (gate 1.0 ms).

## 2026-10-24 · S3 T5.2: the band-up beat (V3-1, V3-2, V3-16; S3G30, S3G36 F part; PROPOSED; IMPLEMENTED)

- **Profile (V3-1)**: `GrowthBeat.begin` calls `set_retire_profile` on every growth container that
  has it: `BAND_UP_SINK_TM` 3.0 and `BAND_UP_RETIRE_S` 2.0 on a band-up (`is_band_up(from, to)`:
  `band_of` differs), the S2 values otherwise, so the next in-band growth is back to S2's beat.
  RockField and SiltTrail sink their retiring chunks by the profile; ZoneLights sinks its retiring
  discs only on a band-up (its S2 beat fades them in place, which stays).
- **Hand-off (V3-2)**: after `apply_growth`, `LandmarkLayer.release_band(b)` detaches every
  `a_<b>_` and `p_<b>_` piece with its global transform, and `OldBandLayer.adopt` puts them under
  `Handoff`. Each sinks from its y to its old-band y (the drawn instance with the same id, or the
  piece's own AABB) by `ease_in_out_cubic` over `HANDOFF_SINK_S` 1.4 s, then cross-fades with the
  old band's MultiMeshes over 1.4 to 2.0 s; `end_growth` frees it. A cancelled beat fades the handed
  pieces out over `GrowthBeat.MIN_FADE_S` and shows the old band at once. No piece pops.
- **Two fixes in LandmarkLayer found by the hand-off**: a rare piece looks its asset up in its own
  band (`band_of_rare`, from `TileCatalog.RARE_KINDS_BY_BAND`), not the drawn band; and a place's
  `scale` reaches its pose (it was dropped, so a scaled landmark drew at 1).
- **Preload (V3-16)**: the endless `_build` requests a threaded load of `s3_preload_paths()` (every
  kit shell, landmark and rare of the bands this build reaches, the cradle ring, the home beacon);
  `_process` polls, and when all are in `_warm_up_late` draws each scene's meshes once at the hidden
  warm-up point. **Changed from the plan**: `use_sub_threads` is false. With sub-threads a GLB's
  loads outlive the pool and Godot 4.7.2 aborts at exit (seen in `test_warm_up`); one thread per
  scene still keeps the loads off the main thread. A pool freed mid-preload collects its requests
  first.
- **Tests**: `test_growth_view` (no pop at a band-up, the profile resets, a cancelled band-up still
  fades) and `test_warm_up` (the S3 assets are preloaded, their meshes warmed). Mutations caught:
  a cancel that frees the pieces, a profile never reset, a sink offset of 0.3 tm, old-band
  instances shown from frame 0.

## 2026-10-24 · S3 T5.3: the cradle and the home beacon (V3-6 to V3-9; S3G37, S3G32 F part; PROPOSED; IMPLEMENTED)

- **What**: `CradleView` (`game/scenes/pool/cradle_view.gd`, node `Cradle`) and `HomeBeacon`
  (`home_beacon.gd`), made once in the endless build (never in the M1 pool) and registered in
  WorldSpace: the cradle a container, the beacon a leaf. From band 1 the cradle draws art's
  `cradle_ring.glb` (materials dimmed x 0.5 in linear light, top at -2.0 tm), the M1 pool's 18 rocks
  and 8 ring shells at true size (baked like the old band, sharing its bake cache, tops at -2.5 tm),
  48 plankton-haze glitter sprites on `glitter_ring.gdshader` at -1.8 tm, and the caption "Your
  lineage began here" at the ring's north edge, faded from 35 to 40 tm from home.
- **Ring scale**: art re-exported the ring at the old pool's size (record `radius_bu` 14.0625, the
  plan's 7.0 was rev 0), so `RING_RECORD_RADIUS_BU` is 14.0625 and the scale is
  `pool_ring.radius_bu / 14.0625 x bu_to_tm(n)`: 1.0 at size 3, 0.625 at 4. A test pins the constant
  to the record.
- **Beat**: a growth re-expresses what the cradle shows; `set_size(to)` lays out the new size and
  the pieces ease to it over the beat (V3-7). A band-up lays size 3 out at once and fades it in over
  0.5 to 2.0 s. The beacon follows S2's leaf rule, so its top is -12.71 / 1.6^(n - 1) at every size.
- **Tests**: `test_world_scene` (ring at the pool radius, record constant, visible from band 1,
  caption text and range, dish at true size, beacon top per size through real growths, nodes
  grouped, ring and beacon dimmed) and `test_growth_view` (the band-up fade, the in-band ease).
  The decor rows (S3G32 F part) live in `test_ambience_contract.gd` as `test_s3_decor_rows`, next to
  T4's older-haze rows, since they use its readers. With this art an undimmed ring is still under
  `MAX_LUMA_BELOW` (Silica luma 0.38), so a direct check that every ring and beacon surface is
  dimmed guards V3-6. Mutations caught: no dimming, beacon scaled by `bu_to_tm`, cradle at band 0,
  caption always on, dish at am scale, dish and ring tops not pinned, no in-band ease, a fade from 0 s.

## 2026-10-24 · S3 T5.4: zone patches and the bloom tint (V3-10, V3-11; S3G15 view; PROPOSED; IMPLEMENTED)

- **Patches (V3-10)**: `PATCH_REGIONS` moves from the pool to `ZoneLights` and gains
  `warden_flat`; the pool passes every chunk zone and `ZoneLights.has_patch` picks: a listed region,
  no region (the M1 pool's zones), or a bloom meadow.
- **Bloom tint (V3-11)**: a bloom meadow also gets `bloom_<zone id>`, a disc laid as its patch on
  the shared `bloom_mesh` (`bloom_tint.gdshader`: `T_BloomTint` mask, tint #E8C27A, no fog, under
  every cue). Its alpha is 0.05 (Forward+) or 0.18 (Compatibility) times a per-instance strength:
  `bloom_strength` is 1 while the meadow's slot blooms and 0.25 while the other does, eased over 2 s
  after each switch, at the drawn sim tick (`update_bloom` from the pool's frame), so it switches
  with `EcologyRegion.bloom_multiplier` and never pops. The shader's alpha uniform is named
  `opacity`, as the other decor's, so the contract readers find it.
- **Tests**: `test_growth_view` (the tint follows the regrowth phase over two cycles, never both
  slots full, eases through each switch; only bloom meadows get a disc, warden flats a patch, glass
  reefs none, freed with the chunk) and `test_ambience_contract.test_bloom_disc_rows` (under the
  plane band, no fog, under the lane, 30 degrees clear of food, luminance x alpha 0.10 at the
  Compatibility alpha). Mutations caught: both slots blooming together, every zone patched,
  warden flats unlisted, the tick read undrawn, no ease, the spine's #E8D27A, a 0.4 alpha.

## 2026-10-24 · S3 T5.5: the HUD for sizes 3 and 4 (V3-15, V3-17 to V3-19; S3G27 HUD, S3G41; PROPOSED; IMPLEMENTED)

- **Names (D-116)**: `REGION_NAMES` gains band 1's regions and rare places verbatim. Home from band
  1 is the cradle: `region_toast(region, rare, band)` gives "Your lineage began here", shown once
  per `bind` (the 30 s rule still applies to every other name). The band is read from
  `pool.sim_size()` in `_on_region`, so the start tile at bind takes it too.
- **Toasts wait for the chord (V3-15, C3V-21)**: a `tile_entered` during a growth beat before
  `CHORD_S` is held (the last one wins) and shown from `on_growth_chord`.
- **Places line (V3-17, C3V-1)**: `%PlacesLine` after `%GrowthLine`, from
  `growth.places_found(pool.shown_size())` at every endless size, hidden in the M1 pool;
  `GrowthHud.places_text` is static and `Hud.set_places` owns the label.
- **Hazard phrase (V3-18)**: "stop" ("stinger veils stop stinging") sits after "ignore" in
  `PHRASE_ORDER`; ladder entries carry `behavior` from the species catalog.
- **Veil hint (V3-19)**: kept, not cut (it is first on the cut list, but S3 is not running long).
  `IdeaHints` id `veil_threads`, "Threads sting: swim around them", wanted while
  `hint_context().veil_in_view` (`inked_veils_in_view > 0`); followed `VEIL_FOLLOW_S` 10 s after it
  showed when a veil was in view since and no sting hit the cell. The sting comes from the `hit`
  event (kind "sting", target the cell) that `IdeaHints.on_event` already gets, so the context
  carries no `last_sting_s` (the spec's route); the behaviour is the same.
- **Tests**: `test_growth_hud` (`test_places_text`, `test_hazard_phrase`, `test_preview_at_four`,
  `test_veil_hint`, the context's keys) and `test_world_hud` (`test_band_one_names`,
  `test_cradle_toast_once`, `test_toast_waits_for_the_chord`). Mutations caught: the cradle on the
  30 s rule, no reset at bind, a toast at frame 0, a held toast never shown, home as the cradle at
  band 0, a misnamed region, "stop" missing from or out of `PHRASE_ORDER`, "ignore you" for the
  veil, entries without `behavior`, the line at the new size during the beat, the line in the M1
  pool, the veil hint repeating after a pass, a sting or a bite ignored or counted, no veil in view
  required, a 5 s follow, a context that never sees the veil.

## 2026-10-24 · S3 T5.6: dev tools for sizes 3 and 4 (s3-view 12, D-118; PROPOSED; IMPLEMENTED)

- **Buttons**: `%Size3` and `%Size4` join `GROWTH_BUTTONS` beside Size 1 and 2 (the spec put them
  in `WORLD_BUTTONS`; they show where the sea grows, as S2's size buttons do, and a button in both
  lists would have its visibility set twice). `%GoToCradle` is a world button: from band 1 it
  teleports to the band's cradle `view_point_bu` times `band_factor` to the band (band 1:
  (0, 46.08) am, `DebugPanel.cradle_point_am`), facing north; at band 0 it is disabled, reads "Go
  to cradle (size 3+)" and a run is refused with a reason on the refusal line.
- **Creature lines**: a hazard gets a third line with where it is on each drift sine now
  (`posmod(tick + phase, period)`, more use to a dev than the fixed phase) and its drift goal; a
  bloom brain its blooming slot, the post it guards and the seconds to the next switch.
- **Gizmos**: `DevGizmos.habit_layer` gives each hazard's thread capsule (drawn as two sides and two
  half circles) and its drift path (48 points of `drift_goal` over the longer period, every other
  segment drawn), and each channel lurker's strike lane from its lair (`_lane` takes a colour).
- **Tests**: `test_debug_panel` (`test_size_3_and_4_and_go_to_cradle`,
  `test_hazard_and_bloom_lines_and_marks`). Mutations caught: band 0's factor (18 am), the button
  never disabled, a cradle at band 0, Size 4 unrouted, the fixed drift phase, the time since the
  switch, the drift path over the x period, a 1.0 prey radius, a lane for every creature.

## 2026-10-24 · S3 T5.7: build top 4, band-up smoke and perf tour (D-89, C3V-16, C3V-21; S3G36, S3G43; PROPOSED; IMPLEMENTED)

- **Build top 4 (D-89)**: `world_cell.json` `sizes.max_in_build` is 4, so the shipped endless world
  grows to size 4. Tests written for S2's top-2 world pin it where the test is about S2 (the
  config fixture's `_base()`, the place and dev-meter tests in `test_growth`, `test_tiles`, the
  band-0 content tests via `WorldChecks.shipped_world_at(2)`), and the rest read the top from
  `world.max_size` instead of a literal 2 or 3.
- **Band-up names its tile (C3V-21)**: C3V-21 assumed a band-up fires `tile_entered`. It does not
  at home: the cell keeps tile (0, 0) across the band-up, so no toast came and the cradle toast in
  the smoke never showed. `Hud.on_growth_chord` now names the tile the cell is on when the chord
  lands on a band-up and no toast is held (`test_band_up_names_the_tile_at_the_chord`).
- **Endless smoke (S3G43)**: `band_up` and `band_up_continue` as s3-view 16.2 (23 and 11 checks).
  The two `check.sh` lines go after S2's `grow` lines (C3V-16, bound 120 s each; the phases ran in
  about 20 s together here).
- **Perf tour (S3G36)**: the swim route takes the S3 steps at 9,000, 9,600 (go to cradle), 10,800
  and 16,500 (band-up under reduce motion); the grow route runs 3,600 ticks with three growths, a
  set size 2 and the reduce-motion band-up. `PerfTour.s3_gate` reports `report.gate.s3`
  (`growth_pass`: every growth window ≤ 50 ms; `draw_pass`: max draw calls ≤
  `S3G36_MAX_DRAW_CALLS` 104) and the printed line appends " · S3G36 pass" or " · S3G36 FAIL: …".
  `test_debug_panel` checks both routes' ticks and the verdict text.
- **On CI with the top at 4 (PR #164)**: `test_world_layout_gates`' live-site swim still claimed the
  size-2 threats are met at size 2 only; at 3 and 4 the Lurker and the elder rammer live on, so it
  now checks that every species met lives at its size (`SpeciesCatalog.live_at`) and that the
  size-2 threats start at 2. S3G20 read band 1's chunks at 1.24 x band 0's (limit 1.20): band 1 has
  85% more creature sites a chunk (496 against 268 over the gate's 500 chunks), and per-site work is
  the gap. `WorldGen` now reads the disc memo before working out k, the role and turned memos no
  longer build a default dictionary or array on every call, and shell, zone and site ids join a
  per-tile prefix instead of formatting; the chunks and their digests are unchanged. Locally the
  median ratio moved from 1.19 to 1.20 to 1.15 to 1.17 (the limit stands).
  S3G21's size-3 relative row then read 5.04 yd against 1.15 x size 1's 4.37 = 5.03 (absolute 5.04
  of 8.0; size 2 reads 5.06, so size 3 costs what size 2 does). Size 3 keeps about 6 creatures awake
  where size 1 keeps 4 (the elder ambush hunter Joshua chose, and the veils). A drifting veil now
  steers from its own values (`CreatureBrain.seek_from`, as a forager's seek does) instead of
  building a self view every tick; size 3 and 4 swims hash the same at every 1,000 ticks. The 1.15
  limit is the owner's and stands until he answers the card. **Answered 2026-10-24 22:31 UTC:**
  Joshua raised the size-3 row to 1.20 x size 1 (`S3_RELATIVE[3]`); size 4's 1.10 x size 2 and every
  absolute row stand.
- **S3's soak tier on its first CI run (PR #164, soak-b)**: T0.3 ran only the one-seed slow cases, so
  `test_threat_fuzz`'s two four-seed soaks first ran on CI, and failed on the checks, not the game.
  (1) Invariant 7's hazard form held a veil to its path too soon twice. A sleeper woken 0.98 tm off
  at size 3 starts from rest while its goal moves on, so the gap grew to 1.33 tm before it gained,
  and it was 1.038 tm off at 120 ticks; `_drift_settle_ticks` now adds the ground the goal covers
  while the hazard makes a half turn and gets up to speed. And a respawn that moves a veil home
  (`_clear_checkpoint`, the event's `relocated`) is a new entry, as a site's spawn at home is.
  (2) In D-117 (a)'s pool runs a rammer chasing the cell overshot, turned back and was 0.240 m
  from where it was 150 ticks before: S1's restated stall measure (got 0.25 m away and came back)
  now holds in the pool too. (3) S3G13's pair runs met each pair on 71 to 217 ticks against 600:
  the evader foraged away, the kiter circled other creatures and starved every 25 s or so, and each
  respawn was back at home. The runner now tethers the cell within 0.6 of the pair's sight
  (`_tether`), which also brings it to the size-4 veil's threads under the evader (0 contact ticks
  on two seeds before). Unit cases in `test_fuzz_invariants` catch the respawn entry and the get-up
  time each taken out.
  With the pairs met for real, two more showed locally. (4) A size-2 rammer fleeing the cell along
  its leash edge, where the edge crosses a rock, was clamped into the rock 11 mm (invariant 1
  forgives 1 mm): the clamp runs after the settle. From size 2 `PoolSim._contacts` now takes such a
  clamp back as `move_body` takes back a wedged move (the body stays where the tick began and
  stops); the pool and size 1 are unchanged, and S1's and S2's hashes hold to 18,000 ticks. (5) At
  size 4 the tethered cell sat in a veil's path for 40 ticks and slid it 0.635 tm off (bound
  0.625): a body touching a hazard (`_in_its_way`) now holds invariant 7's hazard form off, and
  parting is a new entry. Unit cases catch each taken out.
- **A third soak job, `soak-c` (PR #164)**: on `b97dac7` soak-b's one Godot run took 55 of its 60
  minutes, 27 of them S3G13 with the pairs barely met; on `87040a9` it ran out of the hour inside
  S3G13. Met for real, S3G13's 80 runs of 5 minutes take about 23 s each in the 4-CPU container. B-14's
  remedy for an hour-long job, a nightly workflow, would take S3G13 off the pull request (and the
  nightly workflows wait on Joshua), so `test_threat_fuzz` gets its own parallel job, `soak-c`, and
  soak-b skips it; `test_m1_goldens` checks the three jobs take every file once. Invariant 13's
  check, 21% of a run, now formats a point's label only for a new farthest point and scans the
  colliders in one loop (the same farthest point and label); a run went from 28 to 23 s.

## 2026-10-24 · S3 T5.7: the look probe at sizes 3 and 4 (s3-view 15; S3G31, S3G32 M; PROPOSED; IMPLEMENTED)

- **Scenes**: `lineup_s3`, `lineup_s4` and `hatch_band_up` join `ENDLESS_SCENES` and
  `GROWTH_SCENES` (an omnivore, the AI frozen). The lineups stand at the band's cradle view point
  (`cradle_view_point_tm`: (0, 18) tm at 3, (0, 11.25) at 4), with the spec's bodies, morsel items
  and ghosts; they play `CARRION_SETTLE_FRAMES` (45), not `START_FRAMES` (30), so the morsel items
  have grown in (0.6 s). `hatch_band_up` is size 2 at (0, 28.8) tm and shoots as `hatch`, adding
  the old band's draw calls at 2.0 s.
- **Readings**: the veil's threads (frames with and without `Threads`: ink, width, median CIE76,
  neutral gap) and, at 4, each morsel item's rim (frames with and without the `__rim` MultiMeshes)
  and the strip's preview. A near ghost's `cell_multiple` is now its larger side over the cell
  (`test_ghosts`' measure): the lancer is tall and thin, 0.65 across and 1.65 high. S1's and S2's
  ghosts read as before (their width is the larger side).
- **The veil's threads ink (S3G32 M)**: the spec's outline (a 0.06 tm line, alpha 0.85 at its very
  middle) read 0.5% of the threads' pixels within 15 degrees of the threat pink, because the line
  blends with the navy at every pixel. The inked outline is now solid over its inner half and 0.08 tm
  wide (`capsule_outline.gdshader` `smoothstep(0.5 w, w, ...)`, `OUTLINE_ALPHA` (0.6, 1.0),
  `OUTLINE_W_TM` 0.08). In Forward+, the game's renderer, the spec's flat fill (alpha 0.10) then
  blended to a purple wash (CIE76 about 20, hue about 300 degrees) over more than half the capsule
  and the share fell to 26.7%. The fill is now 0.10 at the rim and fades to nothing on the axis
  (`(d / r)^3`), so the whole stinging area still reads from its edge: 46.2% at size 3 in
  Compatibility and 45.3% in Forward+, and the neutral outline at 4 stays 95 and 79 degrees off the
  pink.
- **Gates**: 21 rows, all pass in Compatibility (50 of 50 with S1's and S2's), each with its reading
  in its `what`. S1's and S2's growth scenes read as at S2. The endless set (16 of 16) moved a little
  (reef food gap 140.0, reef contrast 6.4, shed husk 164.4 and 92.3) and the arrow home's centre
  reads L* 90.6 against 99.8 (bound 75); each `what` records it.
- **Found, not fixed (look review)**: the near ghosts and giants draw no pixel above the probe's
  change threshold at sizes 3 and 4 (largest change 6 of 255), as S2's faint-ghost item; and the
  Compatibility renderer draws a band's fresh pieces and the cradle at frame 0 of the band-up
  (P99 47.7), although their `GeometryInstance3D.transparency` is 1 at that draw (read at
  `frame_post_draw`). Forward+, the game's renderer, hides them (P99 23.2: the old plankton and one
  landmark at the screen's edge).

## 2026-10-25 · Cell to creature link: the cell crawls onto land (Bible section 4; PROPOSED; IMPLEMENTED)

Joshua said "Go" (2026-10-25 01:23 UTC) to the studio's proposal: "the cell crawls onto land and the
creature editor opens, which joins the two stages into one game." This is the first era transition
in the game, built to the Bible's transition contract (section 4) and its transaction rule (section
18). Code: `ShoreLink` (`game/domain/shore_link.gd`, the rules on the save), `EraTransition`
(`game/systems/era_transition.gd`, the writes), `ShoreView` (`game/scenes/pool/shore_view.gd`),
`GameSession.raise_shore`, the pool's `shore_reached`, Main's `open_shore_offer`, `cross_to_land` and
`back_to_water`, and `CreatureRules.from_cell`.

- **Demonstrated capability**: the shore rises the first time the lineage fills its ring at the
  build's top size (the first `ring_paid` at size 4), so a lineage must reach the top and fill it
  once. The toast says "A shore has risen up ahead. Swim into its light to crawl onto land."
- **A survivable destination**: the shore stands 20 tm up the screen from where the cell was (inside
  the loaded 3 x 3 chunks), on the first clear point the rule C1 spiral finds there for twice the
  cell's radius. It is a shaft of warm light with a sand disc as wide as its 4 tm reach, and a warm
  arrow (a second `StarvingArrow`) points to it from the cell while it is out of reach. The shaft and
  disc are primitive meshes until art makes the shore piece (art follow-up).
- **A player choice**: swimming into the reach pauses the pool under "Crawl onto land?", which says
  what unlocks (legs, walking, the creature editor), what changes (a land world, its food) and what
  stays (the lineage, its history, the points, the checkpoint). "Stay in the water" plays on; the
  offer opens again only after the cell has swum out past 1.5 times the reach and back. Nothing
  forces the crossing, so aquatic play goes on as long as the player likes.
- **Saved as a transaction with a checkpoint**: "Crawl ashore" saves the slot (the cell at the
  shore), writes the same save as `<slot>.pre-terrestrial` (the checkpoint, through the usual temp,
  verify and backup path), then writes the lineage ashore: era `terrestrial`, a `came_ashore`
  lineage event (generation and genome id) and the lineage's first creature. A failed last write
  undoes the move in memory and the slot still holds the cell; the order of the writes is the safe
  equivalent of a pending transaction, so `pending_transactions` stays empty. No key is added: the
  shore is a `world_changes` entry `{"kind": "shore", "x_am", "y_am", "size"}` (an array v4 leaves
  to its readers), and the era and creature fields are v4's own. Deleting a slot, or founding a new
  lineage in it, removes the checkpoint.
- **The same lineage continues**: lineage id, genome, lineage history, adaptation points (one pool
  for both stages, as before), discoveries, world seed and the shore carry over unchanged. The first
  creature is the starter quadruped with the cell's hue as its skin (`from_cell`: the genome's
  `appearance.hue` at saturation 0.55 and value 0.8, as `"#rrggbb"` in the body's `skin_color`,
  agreed with the Creature stage thread), and the editor still offers the presets on a first visit.
  A lineage that already shaped a creature in the title's creature stage preview keeps it, with the
  cell's skin only when it has none of its own (`CreatureRules.ashore`), so no spent point is lost.
  The crawl is a 1.2 s fade to sand with "Your lineage crawls onto land", then the creature editor
  opens under it with the banner "Your lineage came ashore. Shape its first land body: every
  adaptation point it earned in the water comes with it."
- **Going back**: Continue on a lineage that is ashore opens the creature stage. The title shows
  "Back to the water" while the checkpoint is there (also when the slot no longer loads, so the cell
  is not lost with it). It asks first, Cancel focused, as what the lineage did on land is lost:
  it writes the checkpoint back as the slot (the save ashore becomes the slot's `.bak` until the next
  save) and continues the cell at the shore, which can cross again
  once it has swum out of the reach and back (a run that starts in the reach never opens the offer
  at once).
  The continue card says "On land" for a lineage ashore.
- **Open for Joshua (era boundaries need owner approval)**: the Bible puts the Aquatic era between
  Microscopic and Terrestrial. This link goes from the cell stage to the creature stage that exists
  now; when Aquatic is built it slots in between (the cell's top size would lead to the aquatic
  stage, and its shore to land). The contract's three carry-over tests are only partly met until
  then: the earlier local activity that stays playable is the cell itself, through the checkpoint;
  the adaptation that still matters is the shared point pool (the creature world has no diets, so
  the cell's diet does not carry yet); the relationship that persists waits for the creature world's
  species records.
