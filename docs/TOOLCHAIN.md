# Toolchain

Pinned in `tools/toolchain.env`. Inspected and verified on 2026-10-22.

| Tool | Version | Why this one |
| --- | --- | --- |
| Godot | 4.7.2-stable (official, standard GDScript build) | Latest stable release at inspection (released 2026-08-18). |
| Godot export templates | 4.7.2-stable, Windows x86_64 only | Matches the editor exactly. |
| Blender | 5.2.2 LTS | Latest LTS. Used through the `bpy` 5.2.2 Python module in CI-style environments and the regular Blender app on the owner's PC. |

## Verified in this repository

- `godot --headless --import` imports `assets/export/sample_cell.glb` with no errors.
- `tests/run_tests.gd`: 23 tests pass (genome validation, save safety and migration, asset admission).
- Boot smoke check passes headless; a rendered frame (OpenGL under Xvfb) is in `docs/evidence/`.
- `--export-release "Windows Desktop"` produces `builds/windows/Pangaea.exe` (single file, embedded pack).

**Windows gate status: passed (launch check).** On 2026-10-22 the owner launched the exported `Pangaea.exe` (built from commit 678ce8b plus the M0 working tree) on his Windows PC and saw the sample cell rotating with four PASS lines. Hardware was not recorded; record it once a baseline PC is named for the performance gate.

## Owner setup on Windows

1. Install Godot 4.7.2-stable (standard, not .NET) from godotengine.org.
2. Install Blender 5.2.2 LTS from blender.org.
3. Open `project.godot` in Godot. The main scene is `game/scenes/boot.tscn`, which runs the M0 checks on launch.
4. To try a build without Godot, download the `pangaea-windows-<commit>` artifact from the latest CI run and run `Pangaea.exe`.

## Conventions

- 1 Blender meter = 1 Godot unit. No scale fix-ups on import.
- Blender: front +Y, up +Z. Godot after glTF import: front -Z, up +Y. `tests/test_assets.gd` checks this on every export.
- `.blend` import inside Godot is disabled (`filesystem/import/blender/enabled=false`). Assets enter the engine only as reviewed GLB exports.
- `.blend` files are stored in plain git for now (the sample is 130 KB). Switch to Git LFS before large sources land; see `docs/DECISIONS.md`.
