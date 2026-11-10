# Creature Lab: Gait Lab (0a), Spine Lab (0b) and Stage 1 limbs

Status: PROTOTYPE, approved by the owner on 2026-10-23 ("Build Gait Lab"). Not production code. Nothing here is loaded
by the game, and nothing in `game/` was changed. This folder is its own Godot project, so the main project's import,
tests and export skip it. The research plan put it in a planned `gait/` subfolder; it sits one level up so that later
prototypes (0b spine skin) can share the project. Results are in
`docs/research/spore/GAIT_LAB_REPORT.md`.

Built only from the GENESIS specs (`docs/research/spore/workstreams/locomotion.md` §2–§5 and §9,
`PROCEDURAL_ANIMATION_SPEC.md`) and public biomechanics. No Spore code, data or community-tool material was used.

## What it does

Three test bodies (quadruped with 0.5 m legs, the same quadruped with 1.0 m legs, hexapod with 0.5 m legs) walk, trot and
run on a flat plane. Speeds come from leg length through one table in Froude units, so the long-legged quadruped is √2
times faster with a 1/√2 slower cadence, and its turn limit comes from its own reach. Legs are generated `Skeleton3D`
chains solved by Godot's built-in `TwoBoneIK3D`. Visuals are capsules and cylinders, which the asset rules allow in
prototypes only.

## Run it

Open `prototypes/creature-lab/project.godot` in Godot 4.7.2 and press Play.

- Hold **W** to move, **S** to back up, **A**/**D** to turn.
- **1**, **2**, **3** set the pace: walk, trot, run.
- **Tab** changes the body (short legs, long legs, hexapod, all three). **R** resets.

Command line (after `--`): `--body=quad_short|quad_long|hexapod|all`, `--drive=keyboard|demo|walk|trot|run|turn_in_place|reversal|random`,
`--duration=SECONDS`, `--hud=0`.

```bash
G=.toolchain/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path prototypes/creature-lab --script res://tests/run_tests.gd   # domain tests
$G --headless --path prototypes/creature-lab --script res://tools/measure.gd     # rig measurements -> results/measurements.json
prototypes/creature-lab/tools/render_clips.sh OUT_DIR                             # 10 s clips and contact sheets (Xvfb)
```

## Layout

| Path | Role |
| --- | --- |
| `data/gait_table.json` | Gait bands in Froude units, duty factors, reach margin, swing limits (PROPOSED tuning) |
| `data/test_bodies.json` | The three test bodies |
| `domain/gait_table.gd`, `domain/body_mechanics.gd`, `domain/gait_planner.gd` | Pure rules: no scene, UI or file access |
| `rig/creature_rig.gd` | Generated skeleton, `TwoBoneIK3D`, primitive visuals, rig measurements |
| `gait_lab.gd`, `gait_lab.tscn` | The scene: keyboard or scripted drive, footprints, HUD |
| `lab_data.gd`, `lab_drives.gd` | Data loading and scripted inputs |
| `tests/run_tests.gd` | Headless domain tests |
| `tools/measure.gd`, `tools/render_clips.sh` | Rig measurements and clips |

Scripts have no `class_name` and load each other by path, so nothing leaks into a global class list.

## Spine Lab (0b) and Stage 1 limbs

Generated creature bodies: a spine of 3–24 vertebrae with limbs of 2–5 joints, skinned by Surface Nets in GDScript
(`skin/skin_cpu.gd`) and in a compute shader (`skin/skin_gpu.gd`, `skin/surface_nets.glsl`) that gives the same mesh.
Results: `docs/research/spore/SPINE_LAB_REPORT.md` and `STAGE1_LIMBS_REPORT.md`.

```bash
$G --path prototypes/creature-lab spine_lab.tscn -- --body=stage1 --anim=pose     # the ten Stage 1 bodies posing
$G --headless --path prototypes/creature-lab --script res://tests/run_spine_tests.gd
$G --headless --path prototypes/creature-lab --script res://tests/run_stage1_tests.gd
$G --headless --path prototypes/creature-lab --script res://tests/run_legless_tests.gd
$G --headless --path prototypes/creature-lab --script res://tests/run_swim_tests.gd
$G --headless --path prototypes/creature-lab --script res://tests/run_skin_volume_tests.gd
$G --headless --path prototypes/creature-lab --script res://tests/run_editor_tests.gd
$G --headless --path prototypes/creature-lab --script res://tools/pose_matrix.gd  # -> results/pose_error.json
$G --path prototypes/creature-lab walker_lab.tscn -- --body=s1_quadruped --drive=demo   # a generated creature walking
$G --headless --path prototypes/creature-lab --script res://tools/walker_measure.gd  # -> results/walker_measurements.json
xvfb-run $G --path prototypes/creature-lab --rendering-method forward_plus --rendering-driver vulkan --script res://tools/skin_bench.gd
```

| Path | Role |
| --- | --- |
| `data/body_rules.json`, `data/spine_bodies.json`, `data/stage1_bodies.json` | Limits and test bodies (PROPOSED) |
| `domain/body_description.gd`, `domain/body_codec.gd`, `domain/body_field.gd` | Body description, canonical save text, capsule field |
| `skin/` | Grid, GDScript and GPU builders, mesh checks |
| `rig/spine_rig.gd` | Generated skeleton (vertebrae and limb joints), skinned mesh with CUSTOM0/CUSTOM1 |
| `spine_lab.gd`, `spine_lab.tscn` | Viewer |
| `domain/gait_body.gd`, `rig/walker_rig.gd`, `walker_lab.gd`, `walker_lab.tscn` | Generated bodies walking on the gait planner |
| `domain/anchor_resolver.gd`, `rig/part_library.gd` | Part anchors on the skin; the art team's part GLBs and skin shader, loaded from the main project |
| `tools/make_stage1_bodies.py` | Writes `data/stage1_bodies.json` |

## Flat-ground legless and stub-leg modes

`walker_lab.tscn` also accepts `--body=s1_snake` for a spine-only travelling-wave slither and
`--body=s1_tiny` for an alternating-pair stub-leg shuffle. Both use the existing generated skin
and a new deterministic ground-drive controller. Slither speed is bounded and increases with body
length and vertebra count; shuffle speed and turning are limited by the short feet. The headless
ground-drive checks run both modes for 60 seconds of deterministic random input and measure
contact slip, finite state, and level-root stability. The combined `tests/run_tests.gd` runner
includes these checks. Measurements and limits are in
`docs/research/spore/LEGLESS_LAB_REPORT.md`.

## PROPOSED aquatic swim mode

`walker_lab.tscn` accepts `--body=swim_tail|swim_fins` and `--medium=water`.
Mode selection reads the body description before the existing legged and ground-drive
routes: a fin, flipper or tail fluke selects water when no limb reaches the ground;
`--medium=water` explicitly overrides anatomy. It never creates a `GroundDrive` for
a swimmer. `swim_tail` drives a head-to-tail wave and paired fin strokes;
`swim_fins` has paired flippers without a tail paddle and uses fin strokes alone.
Both are PROPOSED lab descriptions, not game assets or production locomotion.
The controller's pitch/roll, forward-cycle progress and curvature gates run in
`tests/run_swim_tests.gd`. Two side-view screenshots and measured limits are in
`docs/research/spore/SWIM_LAB_REPORT.md`.
