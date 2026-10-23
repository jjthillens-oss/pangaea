# Pangaea

An original evolution game (codename GENESIS): shape a lineage from microscopic life through seven eras into a civilization that reaches the stars. Inspired by the creativity and colorful style of Spore (2008), with every design, asset and line of code made from scratch.

Built with **Godot 4.7.2** and **Blender 5.2.2 LTS**. The design authority is the [GENESIS Master Developer Bible](docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf).

## Status

| Milestone | State |
| --- | --- |
| M0 Foundations: separate project, pinned toolchain, save schema, Blender export pipeline | Implemented; Windows launch verified by owner |
| M1 First life: microscopic feeding, threats, reproduction, bounded editor | In progress: step 1 (rules), step 2 (swim and eat) and step 3 (threats) implemented; the owner played a step 2 preview build on Windows; step 3 is exported but not Windows-verified, and its owner decisions are open. See `docs/milestones/M1.md` |

Running the project starts the game (`game/scenes/main.tscn`): a start screen, then a tide pool where a single cell swims, eats plankton or carrion, and dodges, fights or flees two kinds of threat: ambush hunters at the rims and territorial rammers in the rich north. A death returns the cell to the generation start, sheltered for a few seconds. Fighting is automatic on contact, so step 3 adds no player keys. The M0 check scene, `game/scenes/boot.tscn`, still runs by path.

## Quick start

```bash
tools/setup_toolchain.sh --templates   # Linux: pinned Godot + Windows templates
tools/check.sh                         # import, tests, M0 boot check, launch run, play and death smokes, error-log gate, release pack
tools/export_windows.sh                # builds/windows/Pangaea.exe and Pangaea-dev.exe
tools/check_release.sh                 # start the release pack, without game/dev (check.sh runs it too)
```

On Windows, open `project.godot` in Godot 4.7.2. CI builds the Windows executables for every pull request and every push to `main`; download them from the run's artifacts. `Pangaea.exe` is the game; `Pangaea-dev.exe` adds the debug panel (F3), dev keys (F5 to F10) and the perf tour.

Launch flags go after `--`: `--seed=N`, `--slot=PATH` and, in the dev exe, `--perf-tour`. See `docs/TOOLCHAIN.md`.

## Repository layout

| Path | Contents |
| --- | --- |
| `game/domain/` | Rules with no scene or file access: genome, part catalog, phenotype, energy, interactions, ecology, lineage, swimming, save schema, creature senses and brains, respawn rules |
| `game/systems/` | Services: the pool simulation, food fields, layout, species data, the creature field, game session, launch flags, persistence (safe writes, backups, migrations), build info |
| `game/scenes/` | Presentation. `main.tscn` is the main scene; `pool/` draws the tide pool; `boot.tscn` is the M0 check scene |
| `game/ui/` | Start screen, HUD, pause menu, dialogs |
| `game/dev/` | Debug-build tools (debug panel, dev keys, gizmos, perf tour, and the forage, evade, hunt and kiter bots that tests drive); left out of `Pangaea.exe` |
| `game/data/` | Tuning data (JSON) |
| `assets/source/blender/` | Blender sources of record |
| `assets/export/` | GLB exports loaded by Godot |
| `assets/records/` | One record per asset: dimensions, triangles, sockets, provenance. `placeholders/inventory.json` lists the allowed placeholders |
| `tests/` | `run_tests.gd` plus test suites (`-- --skip-slow` skips the slow gates, `-- --only=test_a,test_b` runs chosen files); `smoke/play_smoke.gd` is the multi-process scene smoke and `smoke/ui_smoke.gd` checks the HUD layout and the replace-lineage confirm |
| `tools/` | Toolchain setup, checks, export, Blender scripts |
| `docs/` | Bible, toolchain, decisions, milestone handoffs |
| `prototypes/web-cell/` | The first HTML prototype, kept as a tuning sandbox |

See `CLAUDE.md` for working rules.
