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

## 2026-10-22 · Art direction draft and quality ladder (PROPOSED, owner review pending)
`docs/art/ART_DIRECTION.md` proposes the look ("soft life hardens"; pebble, petal and bead shape language; palette; glTF-safe material families; scale classes; review lighting). `docs/art/quality_ladder.md` takes one cell through four rungs (blockout, form, surfaced, rigged target) as separate `cell_ladder_*` assets. Nothing replaces gameplay placeholders until the owner approves the look. The owner set the polish bar: at least Spore's Steam store page (match its polish, never its designs), with free CC0 resources (Poly Haven, ambientCG) used by default, finished in Blender and logged in asset records. Those hosts are blocked in the current cloud environment.

## Open decisions (from Bible section 26)
- Visual reference package and benchmark scene (M2).
- Minimum supported PC spec (below the owner's high-end baseline).
- Difficulty presets beyond M1's single forgiving preset.
- Final era names and boundaries (working names approved for now).
- Git LFS for large `.blend` sources.
