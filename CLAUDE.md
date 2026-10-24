# Pangaea (codename GENESIS)

An original seven-era evolution game in Godot 4 with Blender-authored art. The design authority is
`docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf`. Read it before starting a task, along with
`docs/DECISIONS.md` and the tests your change touches.

## Rules that are easy to miss

- Label specs as CONFIRMED (owner requirement), PROPOSED (unapproved design) or IMPLEMENTED (built and verified). Era names, numbers and stage scopes are PROPOSED until `docs/DECISIONS.md` says otherwise.
- Do not change the era count, art pipeline, save schema, or milestone scope without the owner's approval. Record approved changes in `docs/DECISIONS.md`.
- Every production 3D asset needs an editable `.blend` source in `assets/source/blender/`, a GLB in `assets/export/` and a record in `assets/records/`. `tests/test_assets.gd` enforces this. Never replace production meshes with engine primitives; the only allowed exceptions are listed in `assets/records/placeholders/inventory.json` (`tests/test_placeholders.gd`).
- Blender front is +Y and up is +Z; in Godot the asset faces -Z with +Y up. 1 m = 1 Godot unit.
- Godot's glTF import ignores vertex colours, so vertex-coloured assets (the pool floor, the threat bodies) take an external `.tres` material mapped in their `.glb.import`. Keep that mapping when an export is regenerated.
- Domain rules (`game/domain/`) have no scene, UI or file access. Services (`game/systems/`) own files and transactions. Scenes only present.
- The pool simulation is deterministic at 60 ticks a second: durations are whole ticks (converted once at load), every sort breaks ties by id, and every random draw comes from a stream seeded by the world seed. Snapshot vectors are `[x, y]` pairs. Creature senses and brains get percepts only, never the sim or the cell's position; `tests/test_sim_purity.gd` checks this.
- No new dependencies, paid services, runtime AI or network calls without approval. Nothing is copied from Spore or other games (Thrive's GPL code included).
- CC0 art resources (Poly Haven, ambientCG) may be used by default; log each one in the record of the asset that uses it.
- Dev-only code lives in `game/dev/` and has no `class_name`. In game code only `main.gd` loads it, by path and only in debug builds; tests may load it too. The release exe leaves it out; `tests/test_project_settings.gd` enforces this.
- The main scene is `game/scenes/main.tscn`. The M0 checks run from `game/scenes/boot.tscn` by path.
- Do not claim a Windows build works unless it was launched on Windows. Say "exported but not Windows-verified" otherwise.
- Commit in small steps and push after every commit (`git push -u origin HEAD`).

## Commands

```bash
tools/setup_toolchain.sh --templates   # pinned Godot + Windows export templates into .toolchain/
tools/check.sh                         # import, tests, M0 boot check, launch run, play, UI and death smokes, error-log gate, release pack
tools/export_windows.sh                # builds/windows/Pangaea.exe (release) and Pangaea-dev.exe (dev tools)
python tools/check_docs.py --report     # report path-shaped Markdown references that do not exist
python tools/blender/make_sample_cell.py   # with `pip install bpy==5.2.2` (Python 3.13), or blender --background --python
python tools/blender/make_m1_blockouts.py [--only id[,id...]]   # the M1 blockouts, the same way
python tools/blender/make_m1_threats.py [--only id[,id...]]   # the step 3 threat bodies and the spike part, the same way; then --import
python tools/blender/make_creature_world.py [--only id[,id...]]   # the creature stage's field, nest, fruit bush and meat chunk; then godot --import, --import, godot --import
godot --headless --path . --script res://tools/audio/make_cell_audio.gd [-- --only=id|sfx|ambience|buses]   # the cell-stage effects and ambience; then --import
python tools/make_part_rules.py [--check]   # game/data/creature/part_rules.json from the creature part records (the pack carries no records)
# Tests only: godot --headless --path . --script res://tests/run_tests.gd [-- --skip-slow | -- --only=test_a,test_b]
```

Smoke logs go to `builds/smoke/`. Launch flags go after `--`: `--seed=N`, `--slot=PATH`, `--perf-tour` (dev exe only).
For screenshots, run under `xvfb-run` with `--rendering-method gl_compatibility --rendering-driver opengl3`; the full recipe is in `docs/TOOLCHAIN.md`.

Versions are pinned in `tools/toolchain.env` and explained in `docs/TOOLCHAIN.md`.

## Layout

`game/domain` rules · `game/systems` services · `game/scenes` presentation · `game/ui` · `game/dev` debug-build tools · `game/data` tuning data ·
`assets/source/blender` sources · `assets/export` GLB · `assets/records` asset records · `tests` · `tools` · `docs` ·
`prototypes/web-cell` the original HTML prototype, kept as a tuning sandbox (not production).
