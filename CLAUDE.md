# Pangaea (codename GENESIS)

An original seven-era evolution game in Godot 4 with Blender-authored art. The design authority is
`docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf`. Read it before starting a task, along with
`docs/DECISIONS.md` and the tests your change touches.

## Rules that are easy to miss

- Label specs as CONFIRMED (owner requirement), PROPOSED (unapproved design) or IMPLEMENTED (built and verified). Era names, numbers and stage scopes are PROPOSED until `docs/DECISIONS.md` says otherwise.
- Do not change the era count, art pipeline, save schema, or milestone scope without the owner's approval. Record approved changes in `docs/DECISIONS.md`.
- Every production 3D asset needs an editable `.blend` source in `assets/source/blender/`, a GLB in `assets/export/` and a record in `assets/records/`. `tests/test_assets.gd` enforces this. Never replace production meshes with engine primitives.
- Blender front is +Y and up is +Z; in Godot the asset faces -Z with +Y up. 1 m = 1 Godot unit.
- Domain rules (`game/domain/`) have no scene, UI or file access. Services (`game/systems/`) own files and transactions. Scenes only present.
- No new dependencies, paid services, runtime AI or network calls without approval. Nothing is copied from Spore or other games (Thrive's GPL code included).
- Do not claim a Windows build works unless it was launched on Windows. Say "exported but not Windows-verified" otherwise.

## Commands

```bash
tools/setup_toolchain.sh --templates   # pinned Godot + Windows export templates into .toolchain/
tools/check.sh                         # import, run tests/run_tests.gd, boot smoke check
tools/export_windows.sh                # builds/windows/Pangaea.exe
python tools/blender/make_sample_cell.py   # with `pip install bpy==5.2.2` (Python 3.13), or blender --background --python
```

Versions are pinned in `tools/toolchain.env` and explained in `docs/TOOLCHAIN.md`.

## Layout

`game/domain` rules · `game/systems` services · `game/scenes` presentation · `game/ui` · `game/data` tuning data ·
`assets/source/blender` sources · `assets/export` GLB · `assets/records` asset records · `tests` · `tools` · `docs` ·
`prototypes/web-cell` the original HTML prototype, kept as a tuning sandbox (not production).
