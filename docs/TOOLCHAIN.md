# Toolchain

Pinned in `tools/toolchain.env`. Inspected and verified on 2026-10-22.

| Tool | Version | Why this one |
| --- | --- | --- |
| Godot | 4.7.2-stable (official, standard GDScript build) | Latest stable release at inspection (released 2026-08-18). |
| Godot export templates | 4.7.2-stable, Windows x86_64 only | Matches the editor exactly. |
| Blender | 5.2.2 LTS | Latest LTS. Used through the `bpy` 5.2.2 Python module in CI-style environments and the regular Blender app on the owner's PC. |

## Verified in this repository

- `godot --headless --import` imports every GLB in `assets/export/` with no errors.
- `tools/check.sh` passes (2026-10-22, commit a53fc70): 252 tests, the M0 boot check, the launch run and both phases of the play smoke (96 and 23 checks), with no errors in the smoke logs.
- A rendered frame of the M0 boot scene (OpenGL under Xvfb) is in `docs/evidence/`.
- `tools/export_windows.sh` produces `builds/windows/Pangaea.exe` and `builds/windows/Pangaea-dev.exe` (single files, embedded pack).

**Windows gate status.**
- M0: passed (launch check). On 2026-10-22 the owner launched the exported `Pangaea.exe` (built from commit 678ce8b plus the M0 working tree) on his Windows PC and saw the sample cell rotating with four PASS lines. Hardware was not recorded.
- M1 step 2: open. On 2026-10-22 the owner ran the preview build (commit a927b0f) on his PC. The formal checklist, the adapter and the FPS are not recorded yet; see `docs/milestones/M1.md`. Later commits are exported but not Windows-verified.

## What `tools/check.sh` runs

In this order; any failure stops it. It takes about 40 s in the Linux container.

1. `--import`.
2. `tests/run_tests.gd`: the whole test suite.
3. The M0 checks: `game/scenes/boot.tscn` by path, with `-- --smoke`.
4. Launch run: the main scene for 300 frames (`--fixed-fps 60 --quit-after 300`). It must open with no engine or script errors.
5. Play smoke, found phase (`tests/smoke/play_smoke.gd -- --phase=found --seed=4242`): a grazer lineage is started from the start screen, eats, starves and recovers, dies and continues, then saves and quits to the title. Hunter and omnivore lineages eat too.
6. Play smoke, continue phase, in a new process: Continue brings back the same lineage, body, parts, points and place.
7. UI smoke (`tests/smoke/ui_smoke.gd`): with a saved lineage, pressing Enter through New lineage, the body card, Start and the replace-lineage confirm keeps the lineage, because the confirm opens on Cancel. Then, for every starting body, the starving banner and a real "Not saved yet" message stay clear of the HUD's status and points panels, compared by their global rects.
8. Error-log gate: fails if any `builds/smoke/*.log` has `SCRIPT ERROR` or a line starting `ERROR:`.

Steps 4 to 7 write `builds/smoke/launch.log`, `found.log`, `continue.log` and `ui.log`. Smoke saves go to `user://smoke/`, never to the player's slot. Run `tools/write_build_info.sh` first if the build id should name the commit; otherwise it says `dev`. To keep a check run away from your own Godot user data, set `XDG_DATA_HOME` to a scratch folder.

## Windows builds

`tools/export_windows.sh` writes the build info, imports, then exports two files:

| File | Preset | Contents |
| --- | --- | --- |
| `builds/windows/Pangaea.exe` | `Windows Desktop` (release) | The game. `game/dev/` and `tests/` are left out. |
| `builds/windows/Pangaea-dev.exe` | `Windows Desktop Dev` (debug) | The game plus the dev tools in `game/dev/`: the debug panel (F3), dev keys (F5 to F8), gizmos, the forage bot and the perf tour. `tests/` is left out. |

There is no console wrapper (`Pangaea-dev.console.exe`) yet, because `tools/setup_toolchain.sh` installs only the release and debug templates. CI runs `check.sh`, then the export, and uploads both exes as one artifact.

## Launch flags

Pass them after `--`, for example `Pangaea.exe -- --seed=4242`. `tools/check.sh` uses the same flags with the Godot binary.

| Flag | Effect |
| --- | --- |
| `--seed=N` | World seed for a new lineage, a whole number from 0 to 4294967295. |
| `--slot=PATH` | Save slot instead of `user://saves/slot_1.json` (`%APPDATA%\Pangaea\saves\slot_1.json` on Windows). It must name a file under `user://` or at an absolute path. |
| `--perf-tour` | Dev exe only. The forage bot swims for 90 s after a 2 s warm-up, then the game writes `user://reports/perf_<build>.json` and quits. |

A flag that cannot be used is logged as a warning and ignored, so a refused `--slot` falls back to the default slot.

## Screenshots on Linux (Xvfb)

The container has no GPU or display. Renders use Xvfb and the Compatibility renderer:

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . \
  --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
  --script path/to/shot.gd
```

- `shot.gd` is a small `SceneTree` script that sets up the scene, waits for the frames it needs, then saves `root.get_viewport().get_texture().get_image()` with `save_png`. No such script is in the repository yet.
- Wait at least 24 frames after the pool opens, so its 0.3 s fade-in is gone.
- Set the pool's `pause_on_focus_loss` to false, or Xvfb focus changes can pause it.
- These renders show the Compatibility renderer only. The game uses Forward+ on Windows, which looks different.

## Owner setup on Windows

1. Install Godot 4.7.2-stable (standard, not .NET) from godotengine.org.
2. Install Blender 5.2.2 LTS from blender.org.
3. Open `project.godot` in Godot. The main scene is `game/scenes/main.tscn`: the start screen, then the tide pool. The M0 checks still live in `game/scenes/boot.tscn`; open it and run it as the current scene.
4. To try a build without Godot, download the `pangaea-windows-<commit>` artifact from the latest CI run. Run `Pangaea.exe` to play, or `Pangaea-dev.exe` for the debug panel and the perf tour.

## Conventions

- 1 Blender meter = 1 Godot unit. No scale fix-ups on import.
- Blender: front +Y, up +Z. Godot after glTF import: front -Z, up +Y. `tests/test_assets.gd` checks this on every export.
- `.blend` import inside Godot is disabled (`filesystem/import/blender/enabled=false`). Assets enter the engine only as reviewed GLB exports.
- `.blend` files are stored in plain git for now (the sample is 130 KB). Switch to Git LFS before large sources land; see `docs/DECISIONS.md`.
- Commit in small steps and push after every commit (`git push -u origin HEAD`).
