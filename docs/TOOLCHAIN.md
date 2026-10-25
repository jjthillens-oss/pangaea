# Toolchain

Pinned in `tools/toolchain.env`. Inspected and verified on 2026-10-22.

| Tool | Version | Why this one |
| --- | --- | --- |
| Godot | 4.7.2-stable (official, standard GDScript build) | Latest stable release at inspection (released 2026-08-18). |
| Godot export templates | 4.7.2-stable, Windows x86_64 only | Matches the editor exactly. |
| Blender | 5.2.2 LTS | Latest LTS. Used through the `bpy` 5.2.2 Python module in CI-style environments and the regular Blender app on the owner's PC. |

## Verified in this repository

- `godot --headless --import` imports every GLB in `assets/export/` with no errors.
- `tools/check.sh` passes (2026-10-22, commit 1ebbe75): 480 tests, the M0 boot check, the launch run, the play smoke's found and continue phases (178 and 31 checks), the UI smoke (44), the death smoke's two processes (22 and 10), with no errors in the smoke logs, and the release pack (10 checks).
- A rendered frame of the M0 boot scene (OpenGL under Xvfb) is in `docs/evidence/`.
- `tools/export_windows.sh` produces `builds/windows/Pangaea.exe` and `builds/windows/Pangaea-dev.exe` (single files, embedded pack).

**Windows gate status.**
- M0: passed (launch check). On 2026-10-22 the owner launched the exported `Pangaea.exe` (built from commit 678ce8b plus the M0 working tree) on his Windows PC and saw the sample cell rotating with four PASS lines. Hardware was not recorded.
- M1 step 2: open. On 2026-10-22 the owner ran the preview build (commit a927b0f) on his PC. The formal checklist, the adapter and the FPS are not recorded yet; see `docs/milestones/M1.md`. Later commits are exported but not Windows-verified.
- M1 step 3: open. Exported but not Windows-verified; the owner checklist is in `docs/milestones/M1.md`.

## What `tools/check.sh` runs

In this order; any failure stops it. It takes about 6 minutes in the shared 4-CPU Linux container (5 min 44 s at T0.8 on 2026-10-23: 586 tests), most of it in the unit suite. Every Godot run has a time limit (the import and the release pack's export 600 s, the unit suite 1200 s, every other run 300 s), so a hang fails the check with exit code 124 instead of running until CI cancels the job. The unit suite's 1200 s (900 s until S1) and CI's 40-minute `test-and-export` timeout (30 until S1) hold the S1 budgets (S1 build plan B-13): the fast tier may grow by 48 s over the S1 base and the slow tier by 150 s, in per-track shares, and each PR records its measured slow time. T0's slow tests take about 11 s of its 20 s share at T0.10: the saturated case's three runs; the overdriven #28E, P99.9, sleeper and rebase cases wait on T2.8 and will add to it. The limits come from `tools/bounded.sh`, which keeps each run in the script's process group, so Ctrl-C stops the check at once and no Godot outlives it; `tools/test_bounded.sh` checks that before the import (about 12 s). The test runner prints each test's name as it starts and `ok` or `FAIL` as it ends, so a stopped suite still shows the results so far and names the test that hung; the failures are listed again above the totals.

1. `--import`.
2. `tests/run_tests.gd`: the whole test suite, slow gates included.
3. The M0 checks: `game/scenes/boot.tscn` by path, with `-- --smoke`.
4. Launch run: the main scene for 300 frames (`--fixed-fps 60 --quit-after 300`). It must open with no engine or script errors.
5. Play smoke, found phase (`tests/smoke/play_smoke.gd -- --phase=found --seed=4242`): a grazer lineage is started from the start screen, eats, starves and recovers, dies and continues. Then the threats: the creatures are drawn and listed in the debug panel, F9 and F10 work, an ambush hunter catches the cell (tell, hit, death notice, death saved), the cell continues sheltered, is caught again soon after with a longer shelter, and an edge arrow shows a hunter below the screen. Then it saves and quits to the title. Hunter and omnivore lineages eat too.
6. Play smoke, continue phase, in a new process: Continue brings back the same lineage, body, parts, points, deaths and place, with the creatures back at their sites and the cell sheltered.
7. UI smoke (`tests/smoke/ui_smoke.gd`): with a saved lineage, pressing Enter through New lineage, the body card, Start and the replace-lineage confirm keeps the lineage, because the confirm opens on Cancel. Then, for every starting body, the starving banner and a real "Not saved yet" message stay clear of the HUD's status and points panels, compared by their global rects.
8. Death smoke, in two more processes: `--phase=die_and_quit --slot=user://smoke/death.json --seed=4243` starts an omnivore, eats dev carrion, is caught, and closes the window at the death notice, which quits with no dialog because the death is already saved; `--phase=after_death` continues that slot and finds the points the death left, the cell at its checkpoint and sheltered, and the death last in its history.
9. Creature smoke (`tests/smoke/creature_smoke.gd`), in two more processes on its own lineage slot: `--phase=build --creature --slot=user://smoke/creature.json --seed=4242` opens the creature stage into the editor, grows a pair of neck limbs, adds a maw, eyes and feet, picks a swatch and enters the world on Done; the player eats the nearest fruit, bites a rival, walks back to the nest and evolves, then Escape goes from the world to the editor and from the editor to the title, and Quit ends the game; `--phase=reload` opens the stage from that slot and finds the same body SHA-256, points and generation.
10. Error-log gate: fails if any `builds/smoke/*.log` has `SCRIPT ERROR` or a line starting `ERROR:`.
11. Release gate (`tools/check_release.sh`): exports the release pack (no `game/dev/`, no tests) and starts it from an empty folder, then `tools/release_probe.gd` checks the start screen is up, there is no dev layer, `--perf-tour` is ignored and the pack holds nothing from `game/dev/` or `tests/`. Logs go to `builds/release/`.

Steps 4 to 9 write `builds/smoke/launch.log`, `found.log`, `continue.log`, `ui.log`, `die_and_quit.log`, `after_death.log`, `creature_build.log` and `creature_reload.log`. Smoke saves go to `user://smoke/`, never to the player's slot. Run `tools/write_build_info.sh` first if the build id should name the commit; otherwise it says `dev`. To keep a check run away from your own Godot user data, set `XDG_DATA_HOME` to a scratch folder, as an absolute path (Godot ignores a relative one).

The test runner (`tests/run_tests.gd`) takes these flags after `--`. `check.sh` passes none, so it runs every fast and slow test and no soak test.

| Flag | Effect |
| --- | --- |
| `--skip-slow` | Skips the `test_slow_*` gates, for quick local loops. |
| `--only=test_creature_brain,test_threats_sim` | Runs only those files, named without `.gd`. |
| `--skip=test_endless_gates,test_endless_cost` | Runs every file but those. A file named in both lists is skipped. |
| `--soak` | Runs only the `test_soak_*` methods (the soak tier, below), still honouring `--only` and `--skip`. Without it no soak test runs, and the totals note how many were skipped. |

A name in `--only` or `--skip` that matches no file fails the run, and so does a run in which no test ran, so a typo cannot pass unnoticed.

## The soak tier: `tools/check_soak.sh`

The long S1 gates are `test_soak_*` methods: the golden M1 hashes at 18,000 ticks and, as the endless world lands, the long swims, the seams and the samples. `tools/check.sh` never runs them. `tools/check_soak.sh [path-to-godot] [--only=a,b | --skip=a,b]` runs `tools/test_bounded.sh`, the import (600 s limit), then `tests/run_tests.gd -- --soak` with any runner flags passed on, under a 3600 s limit. The flags may come without the Godot path.

CI runs it in three jobs, in parallel with `test-and-export` and with each other, each with a 75-minute timeout (S1 build plan B-14; `soak-c` since S3):

| Job | Command | Holds |
| --- | --- | --- |
| `soak-a` | `tools/check_soak.sh --only=test_endless_gates,test_endless_cost` | The endless gates (straight swims, the corner circle, #32, #33, hunter viability, F9, the 10 km hash) and the cost soak cases. |
| `soak-b` | `tools/check_soak.sh --skip=test_endless_gates,test_endless_cost,test_threat_fuzz` | Every other soak file, so a new one lands here without a list edit: the 18,000-tick goldens, and later the seams, the content passes, `sample_sites` and the home ring. |
| `soak-c` | `tools/check_soak.sh --only=test_threat_fuzz` | The threat fuzz soaks: S3G13's pairs at sizes 2 to 4 (80 runs of 5 minutes) and D-117's four-seed pool and sunbeam well runs. In `soak-b` they ran past its hour on PR #164. |

`tests/test_m1_goldens.gd` checks the jobs' commands and timeouts, and that between them they take every test file exactly once. S1 sign-off needs both green on the final commit. If either job measures over 60 minutes, the diagonal seam placements and any sample beyond 1,000 move to a nightly workflow, `ci-nightly.yml`.

Measured on 2026-10-23 at T0.8, in the shared 4-CPU container: `soak-b`'s command took 86 s (the 18,000-tick goldens, after `test_bounded.sh` and the import), and `soak-a`'s 18 s, because its gates still wait on T2.8 and print what they wait on. At T0.9 the 10 km hash (G13), which reads no invariant, runs on T1's fixture world: 33 s a run overdriven (100,000 ticks) and 45 s a run for the racer as it is (136,218 ticks), so its two pairs take about 160 s. At T0.10 B-7's saturated cost gate (`test_soak_a_saturated_world_costs_at_most_10_yardsticks_a_tick`, about 13 s) runs in `soak-a` and fails: the dense case reads about 21 yardsticks a median tick against 10, and B-7's own remedy does not close it (`docs/DECISIONS.md`, the S1 build plan entry), so `soak-a` stays red until the cost or the budget changes. In a trial merge of T2's tree with its FuzzInvariants (every gate running, on the fixture world), `test_endless_gates`' soak took 739 s and the cost soak cases about 17 s, so `soak-a` comes to about 13 minutes before the real tiles. The S1 planning estimates are about 28 minutes for `soak-a` and 35 for `soak-b` once every gate runs; each PR records its measured times.

## Windows builds

`tools/export_windows.sh` writes the build info, imports, then exports two files:

| File | Preset | Contents |
| --- | --- | --- |
| `builds/windows/Pangaea.exe` | `Windows Desktop` (release) | The game. `game/dev/` and `tests/` are left out. |
| `builds/windows/Pangaea-dev.exe` | `Windows Desktop Dev` (debug) | The game plus the dev tools in `game/dev/`: the debug panel (F3), dev keys (F5 to F10), gizmos, the bots and the perf tour. `tests/` is left out. |

There is no console wrapper (`Pangaea-dev.console.exe`) yet, because `tools/setup_toolchain.sh` installs only the release and debug templates. CI's `test-and-export` job (40-minute timeout) runs `check.sh`, then the export, and uploads both exes as one artifact; the soak jobs run beside it.

## Launch flags

Pass them after `--`, for example `Pangaea.exe -- --seed=4242`. `tools/check.sh` uses the same flags with the Godot binary.

| Flag | Effect |
| --- | --- |
| `--seed=N` | World seed for a new lineage, a whole number from 0 to 4294967295. |
| `--slot=PATH` | Save slot instead of `user://saves/slot_1.json` (`%APPDATA%\Pangaea\saves\slot_1.json` on Windows). It must name a file under `user://` or at an absolute path. |
| `--perf-tour` | Dev exe only. The forage bot swims for 90 s after a 2 s warm-up, then the game writes `user://reports/perf_<build>.json` (frame times and the GPU time of each frame; see "Look probe") and quits. |

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
- These renders show the Compatibility renderer. The pool's look takes one set of values in both renderers: the sun casts no shadow (Compatibility draws a shadowed light as a separate additive pass in sRGB) and nothing multiplies into stored sRGB any more, so the look probe measures Compatibility 0.1 CIE76 from the game on Windows (Forward+) on the fluid and 0.6 on the cell, and `PoolLook.COMPATIBILITY` in `game/scenes/pool/pool_look.gd` is empty, kept as an escape hatch. Transparent layers still differ: Compatibility tonemaps each transparent object before blending, so with the same alpha a mixed layer lifts the navy fluid about a third as much there and an additive layer about a fifth. Tune those on Forward+ (lavapipe, below) and check both with the look probe; the sunlit patches take one alpha per renderer for this reason (`ZoneLights.strength_for()`).

To judge the look, render with Forward+ on Mesa's software Vulkan driver (lavapipe). It takes about 30 s a frame at 1080p on 4 CPUs. Unpack the driver package that matches the installed Mesa and point the Vulkan loader at it:

```bash
apt-get download mesa-vulkan-drivers && dpkg-deb -x mesa-vulkan-drivers_*.deb /tmp/lvp
echo '{"file_format_version": "1.0.1", "ICD": {"library_path": "/tmp/lvp/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so", "api_version": "1.4.318"}}' > /tmp/lvp/lvp_icd.json
VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . \
  --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 60 --script path/to/shot.gd
```

## Look probe

`tools/godot/look_probe.gd` (micro-world plan C1) measures what the player sees. It starts a grazer lineage on seed 4242 in the real pool, stages nine fixed moments (`lineup`: both threats, plankton, carrion and the cell; `tell`: an ambush hunter 0.8 s into its tell; `puff`: a rammer's puff before a charge; `rim_north` and `rim_south`; `starving`; `hud`: the starving banner, the food arrow, a rammer near and the hurt vignette at its peak; `sunlit`: the cell in the middle of zone z_s with the AI frozen, the frame again without the zone lights, and an ambush hunter set on the patch's brightest shaft; `shelter`: the cell sheltered by the start grace at (−5.5, 21.45), its rim at mid pulse with z_s's brightest shaft behind it), then pauses the pool, stops time and centres the camera on the cell. For each moment it saves the frame the player sees and the same moment with every body, food item, rock and the 2D layer hidden (what lies behind them), writes CIELAB readings at named points (per-channel sRGB medians, D65, CIE76: the judge's maths) to `look_probe.json`, and checks a gate set. The script's header lists every frame and reading.

It runs windowed under Xvfb at 1920×1080 with `--fixed-fps 60`, from the repository root; it refuses to run headless or without a fixed frame rate. Use the lavapipe setup above for Forward+.

```bash
# Compatibility: about half a minute on 4 CPUs.
xvfb-run -a -s "-screen 0 1920x1080x24" .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . --audio-driver Dummy \
  --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
  --script res://tools/godot/look_probe.gd -- --out=/abs/probe_compat --look=micro
# Forward+ on lavapipe: about 5 minutes. --parity compares its frames with the Compatibility run's.
VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . \
  --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 60 \
  --script res://tools/godot/look_probe.gd -- --out=/abs/probe_fwd --look=micro --parity=/abs/probe_compat
```

| Flag | Effect |
| --- | --- |
| `--out=DIR` | Where the frames and `look_probe.json` go (default `user://look_probe/out`). Use an absolute path. |
| `--look=micro` or `--look=baseline` | The gate set: the micro-world look (plan section 6; the default) or today's look. |
| `--scenes=lineup,tell` | Only these moments. |
| `--parity=DIR` | Another renderer's run of the same moments: adds the median CIE76 between the two runs (whole frame, fluid frame, cell) and the parity gates. |
| `--zoom=M` | The camera distance (default the layout's 14 m). |

The exit code is 0 when every gate passes, 1 when one fails or a moment could not be staged, and 2 when the probe cannot run. It prints one PASS, FAIL or SKIP line per gate. Its save goes to `user://look_probe/`, never the player's slot; set `XDG_DATA_HOME` as for `check.sh`. Runs are repeatable: two runs in one renderer give the same readings, and their frames differ only in the HUD's random lineage id. It is not part of `check.sh`: run it at C4, C5 and C9 of the plan and whenever the look changes. Its colour maths and gate logic are unit-tested in `tests/test_look_probe.gd`.

**The micro look** (`m1-micro` after C9, 2026-10-23, and again, value for value, after the round 4 contract fixes; llvmpipe and lavapipe, 1920×1080, zoom 14). `--look=micro` with `--parity` passes 28 of its 29 gates in Forward+, and 26 in Compatibility, where the two parity gates skip (they run in the second renderer). `plankton_clip` fails in both: the highest channel is 255, the green of each diatom's sunlit, emissive core; the items' median colours top out at 249, the judge's measure. It is an asset question for art, or a gate to sign off by name (plan section 5's merge gate).

| Reading | Compatibility | Forward+ (lavapipe) | Micro gate |
| --- | --- | --- | --- |
| Cell, lineup (inner 55% of its disc) | `#C0674C`, L\* 53.4, h 43.1 | `#C0674D`, L\* 53.4, h 42.6 | h 30 to 50 |
| Fluid near the cell (centre third, fluid frame) | `#1F5487`: L\* 34.8, C\* 33.5, h 272.2 | `#1F5387`: L\* 34.5, C\* 34.0, h 273.3 | L\* 26 to 36, h 268 to 288, C\* ≥ 25; ≥ 90 degrees of hue from the threat pink (98.9 \| 97.8) |
| Cell against it, \|dL\*\| | 18.6 | 18.9 | ≥ 15 |
| Darkest corner L\*; centre minus corners' mean, dL\* | 16.3; 17.8 | 16.4; 17.5 | ≥ 15; ≥ 5 |
| Lane outline over the fluid, tell and puff (least of 6 points, \|dL\*\|) | 19.5 and 18.0 | 17.2 and 20.3 | ≥ 15 |
| Lane outline over the pale decor stand-in, tell and puff | 25.6 and 24.2 | 23.8 and 23.4 | ≥ 15 |
| The tell's lane over a sunlit patch (lift under its edge, dL\*) | 4.8 | 4.6 | ≥ 2 |
| "!" marker outline against the fluid, tell and puff (WCAG) | 7.75 and 8.56 | 7.69 and 8.39 | ≥ 3 |
| Plankton hue span; highest channel | h 117.9 to 138.1; 255 | h 117.7 to 137.2; 255 | 110 to 145; ≤ 254 |
| Carrion: least hue gap from the threat pink | 18.6 | 18.6 | ≥ 15 |
| Hurt vignette, outer band (corners) | `#743334`, h 24.8 | `#753334`, h 24.9 | h 15 to 45 |
| Starving cell against the fluid, \|dL\*\| | 20.6 | 23.3 | ≥ 10 |
| Ambush hunter in the lineup, against what lies behind it, \|dL\*\| | 24.7 | 24.3 | ≥ 15 |
| Sunlit patch: brightest lift, dL\*; least lift over the most at that radius | 9.6; 0.0 | 9.2; 0.0 | ≥ 5; ≤ 0.5 |
| Sunlit patch: ambush hunter over its brightest shaft; the cell in its middle, \|dL\*\| | 16.8; 18.9 | 17.1; 18.9 | ≥ 15; ≥ 15 |
| Shelter rim at mid pulse over a patch: lift of the edge's brightest tenth (mean), dL\* | 8.7 (2.9) | 21.7 (8.9) | ≥ 5 |
| Rim north, largest L\* step down the wall | 3.2 | 2.6 | ≤ 6 |
| Draw calls; primitives, lineup | 60; 19.8k (no shadow pass) | 47; 19.8k (no shadow pass) | |

Renderer parity, Forward+ against Compatibility (median CIE76), across the nine moments: whole frame 0.1 to 0.5, fluid frame 0.0 to 0.1, the fed cell 0.6 (1.4 in `shelter`, under the rim) and the starving cell 4.7 (its grey is a transparent overlay). Opaque content meets the plan's ≤ 2: the gates read 0.0 (fluid) and 0.6 (cell) in the lineup. Transparent layers differ as described under "Screenshots on Linux": the plan expected them up to about 6 L\* lighter in Forward+, and the shelter rim is the largest case, 2.5 times the lift (21.7 against 8.7). The lanes stay within 2.3 L\* of each other and the vignette's band keeps its hue. The sunlit patches lift the fluid alike (9.6 \| 9.2) because each renderer gets its own alpha (0.15 Compatibility, 0.035 Forward+).

**Before the micro look** (m1-threats at ecb1eee). `--look=baseline` passes its 18 gates in both renderers; `--look=micro` then failed 16 of its 21 in Compatibility and 14 in Forward+, as it should before C4. Those readings:

| Reading | Compatibility | Forward+ (lavapipe) | Micro gate |
| --- | --- | --- | --- |
| Cell, lineup (inner 55% of its disc) | `#A2543E`, h 42.1 | `#B26550`, h 41.3 | h 30 to 50 |
| Floor near the cell (centre third, fluid frame) | `#246E74`: L\* 42.4, C\* 22.6, h 206.3 | `#2A7B86`: L\* 47.5, C\* 24.3, h 212.8 | L\* 26 to 36, h 268 to 288, C\* ≥ 25; ≥ 90 degrees of hue from the threat pink (164.8 \| 158.3) |
| Cell against it, \|dL\*\| | 2.4 | 3.6 | ≥ 15 |
| Darkest corner L\*; centre minus corners' mean, dL\* | 48.4; −7.7 | 55.2; −9.2 | ≥ 15; ≥ 5 |
| Lane outline, tell and puff (least of 6 points, \|dL\*\|) | 8.0 and 6.4 | 3.0 and 2.8 (pink: CIE76 about 14) | ≥ 15 |
| Plankton hue span; highest channel | h 108.6 to 138.2; 255 | h 117.8 to 136.6; 255 | 110 to 145; ≤ 254 |
| Carrion: least hue gap from the threat pink | 18.6 | 15.1 | ≥ 15 |
| Hurt vignette, outer band (corners) | `#52585F`, h 261.2 | `#5B646C`, h 254.2 | h 15 to 45 |
| Starving cell (`#785A55` / `#9D8485`) against the floor, \|dL\*\| | 5.8 | 3.7 | ≥ 10 |
| Rim north, largest L\* step down the wall | 6.8 | 3.5 | ≤ 6 |
| Threat bodies in the lineup, hunter and rammer, \|dL\*\| (CIE76) | 2.8 (24.9) and 18.0 (32.3) | 0.4 (25.0) and 15.2 (36.6) | none (plan risk 5) |
| Draw calls; primitives, lineup | 140; 57.3k (shadow pass: 21.0k primitives, no draw calls counted) | 46; 57.3k (shadow pass: 72 draw calls, 21.0k primitives) | |

Renderer parity then, Forward+ against Compatibility (median CIE76): whole frame 4.6 to 6.9 across the seven moments, fluid frame 5.3 to 7.1, the fed cell 6.9 to 7.3 and the starving cell 17.1; in the lineup 6.5, 6.7 and 7.0 (micro gate: ≤ 2 for opaque content). The decor stand-in (a pale camera-facing plane at y −3 m, linear luminance 0.81 × alpha 0.147 = 0.12, the ambience contract's cap) lies under today's opaque floor, so the outline over it reads the same as over the floor until C4 takes the floor away. Today's skirt reading samples the floor's caustics, since there is no skirt yet.

**GPU time.** The perf tour's report (`--perf-tour`, dev exe) has `gpu_frames`, `gpu_avg_ms`, `gpu_slow_1pct_ms` and `gpu_max_ms` beside the frame times, from the renderer's own timing of the root viewport (`RenderingServer.viewport_set_measure_render_time`). The F3 panel's render section shows the GPU time's average and longest over the last 60 timed frames. A headless run times nothing and reports zeros. On llvmpipe or lavapipe the "GPU" is the CPU rasterising (a Compatibility perf tour at 1280×720 averaged 355.6 ms over 241 timed frames), so GPU budgets are measured on the owner's PC (plan section 9).

## Owner setup on Windows

1. Install Godot 4.7.2-stable (standard, not .NET) from godotengine.org.
2. Install Blender 5.2.2 LTS from blender.org.
3. Open `project.godot` in Godot. The main scene is `game/scenes/main.tscn`: the start screen, then the tide pool. The M0 checks still live in `game/scenes/boot.tscn`; open it and run it as the current scene.
4. To try a build without Godot, download the `pangaea-windows-<commit>` artifact from the latest CI run. Run `Pangaea.exe` to play, or `Pangaea-dev.exe` for the debug panel and the perf tour.

## Blender scripts

Each script builds its assets from code and writes the `.blend`, the GLB and the record; run it from the repository root, then `godot --headless --path . --import`. With the `bpy` module (`pip install bpy==5.2.2`, Python 3.13) run it with `python`; with the Blender app, `blender --background --python <script> -- <flags>`.

| Script | Assets |
| --- | --- |
| `tools/blender/make_sample_cell.py` | The M0 sample cell. |
| `tools/blender/make_m1_blockouts.py [--only id[,id...]]` | The step 2 blockouts: pool floor, rocks, plankton, carrion and four parts. |
| `tools/blender/make_m1_threats.py [--only id[,id...]]` | The step 3 blockouts: `creature_ambush_body`, `creature_rammer_body` and `part_spike`. GLBs and records come out byte-identical on every run. |
| `tools/blender/make_m1_micro_rim.py` | `pool_rim`, the microscopic world's placeholder dish wall, which takes the floor's place at the pool's edge. It reads the old floor's rim height field from `make_m1_blockouts.py`. GLB and record come out byte-identical on every run. |
| `tools/blender/make_s1_kit.py [--only id[,id...]]` | The endless world's band-0 placement kit (S1): five shells, six landmarks, the two rare set pieces and the two markers. It checks each piece against the kit's art contract before export, then writes `game/data/placement_kit.json` from the records, the home rocks `rock_a` to `rock_c` included; `tests/test_kit_assets.gd` checks the same contract. See `docs/art/endless_s1_kit.md`. |
| `tools/blender/make_s1_production.py [--only id[,id...]]` | The finished versions of the same kit pieces: `make_s1_kit.py`'s builders, so the same geometry, ids and colliders, surfaced and baked to one texture set each. It rewrites `game/data/placement_kit.json` too. |

The threat bodies and the pool rim are vertex-coloured. Godot's glTF import ignores `COLOR_0`, so each `.glb.import` maps the surface material to an external `.tres` (`M_PoolRim`, `M_AmbushBody`, `M_RammerBody`) through `_subresources`; keep that mapping when an import file is rewritten.

## Conventions

- 1 Blender meter = 1 Godot unit. No scale fix-ups on import.
- Blender: front +Y, up +Z. Godot after glTF import: front -Z, up +Y. `tests/test_assets.gd` checks this on every export.
- `.blend` import inside Godot is disabled (`filesystem/import/blender/enabled=false`). Assets enter the engine only as reviewed GLB exports.
- `.blend` files are stored in plain git for now (the sample is 130 KB). Switch to Git LFS before large sources land; see `docs/DECISIONS.md`.
- Commit in small steps and push after every commit (`git push -u origin HEAD`).
