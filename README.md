# Pangaea

An original evolution game (codename GENESIS): shape a lineage from microscopic life through seven eras into a civilization that reaches the stars. Inspired by the creativity and colorful style of Spore (2008), with every design, asset and line of code made from scratch.

Built with **Godot 4.7.2** and **Blender 5.2.2 LTS**. The design authority is the [GENESIS Master Developer Bible](docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf).

## Status

| Milestone | State |
| --- | --- |
| M0 Foundations: separate project, pinned toolchain, save schema, Blender export pipeline | Implemented; Windows launch verified by owner |
| M1 First life: microscopic feeding, threats, reproduction, bounded editor | Not started |

Opening the project runs the M0 check scene: it loads the Blender sample creature and verifies the build, part data, asset loading and a save round trip.

## Quick start

```bash
tools/setup_toolchain.sh --templates   # Linux: pinned Godot + Windows templates
tools/check.sh                         # import, tests, boot smoke check
tools/export_windows.sh                # builds/windows/Pangaea.exe
tools/check_release.sh                 # start the release pack, without game/dev (check.sh runs it too)
```

On Windows, open `project.godot` in Godot 4.7.2. CI builds a Windows executable on every push; download it from the run's artifacts.

## Repository layout

| Path | Contents |
| --- | --- |
| `game/domain/` | Rules with no scene or file access: genome, part catalog, save schema |
| `game/systems/` | Services: persistence (safe writes, backups, migrations), build info |
| `game/scenes/` | Presentation. `boot.tscn` is the M0 check scene |
| `game/data/` | Tuning data (JSON) |
| `assets/source/blender/` | Blender sources of record |
| `assets/export/` | GLB exports loaded by Godot |
| `assets/records/` | One record per asset: dimensions, triangles, sockets, provenance |
| `tests/` | `run_tests.gd` plus test suites |
| `tools/` | Toolchain setup, checks, export, Blender scripts |
| `docs/` | Bible, toolchain, decisions, milestone handoffs |
| `prototypes/web-cell/` | The first HTML prototype, kept as a tuning sandbox |

See `CLAUDE.md` for working rules.
