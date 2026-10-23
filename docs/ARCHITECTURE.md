# Architecture map

This map describes the code on `main` at `97b929b` (2026-10-23). It is an
orientation guide, not a new design decision. The game uses Godot 4; Blender
sources remain the editable origin of production meshes.

## Where work lives

| Path | Responsibility and dependency direction |
| --- | --- |
| `game/domain/` | Pure rules and value objects: genomes, derived phenotypes, movement, senses, brains, interactions, lineages and save data. These must not read scenes, UI or files. |
| `game/systems/` | Orchestration and file owning services. `PoolSim` advances domain rules, while `GameSession` coordinates runs and `PersistenceService` handles save transactions. Systems may use domain types. |
| `game/scenes/` | The root, boot check, pool presentation and audio. Scenes create systems, submit input and display snapshots and events; gameplay rules belong below this layer. |
| `game/ui/` | Title, HUD, menus, notices and shared UI helpers. The root scene wires these to the current session and pool. |
| `game/dev/` | Debug build tools and bots. Only `game/scenes/main.gd` loads them in game code, by path and only in debug builds. |
| `game/data/` | JSON tuning and content inputs for parts, species and the pool. |
| `assets/source/blender/`, `assets/export/`, `assets/records/` | Editable Blender sources, Godot importable exports and provenance records. `assets/audio/` holds audio media. The asset tests enforce the source/export/record contract. |
| `tests/` | Headless `test_*.gd` suites plus scene smokes. `tests/test_case.gd` supplies assertions; `tests/run_tests.gd` discovers suites. |
| `tools/` | Pinned toolchain setup, build/export scripts, smokes and asset generation helpers. |
| `prototypes/` | Independent experiments, including the separate `creature-lab` Godot project and the older `web-cell` tuning sandbox. They are not production gameplay dependencies. |

Dependencies flow from scenes and UI toward systems and domain rules. The
domain layer must remain independent of presentation and persistence. JSON and
assets feed the relevant loaders and views; they are not a second source of
gameplay rules.

## Start, play and save

`game/scenes/main.tscn` is the project main scene. Its `Main` script creates a
`GameSession`, reads `RunFlags`, applies `SettingsService`, and shows a start
screen or `game/scenes/pool/pool.tscn`. The pool scene's `PoolScene` takes the
session's `PoolSim`. Every physics tick it gets a `SimIntent` from `SwimInput`
(or a dev bot), calls `PoolSim.step()`, then renders the state between ticks.
The HUD and feedback receive pool events. `game/scenes/boot.tscn` is a separate
M0 toolchain check: its `boot.gd` loads the sample asset and checks data, build
identity and a save round trip; it is not the gameplay entry point.

```text
Main / menus / HUD
  -> GameSession -> PoolSim (60 deterministic ticks/s)
       -> PoolLayout, PlanktonField, CarrionField, CreatureField
       -> Genome -> Phenotype -> ActorState / Locomotion
       -> CreatureSenses -> percepts -> CreatureBrain -> drive
       -> InteractionResolver, Lineage, PoolArena
  -> PoolScene -> views, feedback, CellAudio
  -> GameSession -> PersistenceService -> SaveGame
                                  -> SaveMigrations / SaveSlots
```

`PoolSim` owns the running pool state and fixed tick order. `PoolLayout` and the
food fields load and advance the environment; `CreatureField` manages species
instances. `Genome` stores inherited parts, `Phenotype` derives body behavior,
and `Locomotion` updates planar swimming. `CreatureSenses` supplies percepts
to `CreatureBrain`; the brain does not inspect the world directly. The sim
resolves movement, feeding and combat through domain rules, then emits events.
`PoolScene` converts those events into visuals, UI signals and `CellAudio`
cues. `game/scenes/audio/soundtrack.gd` and `ui_sounds.gd` handle music and UI
audio at the scene layer; `audio_synth.gd` supports the generated cell audio.

`SaveGame` defines and validates the versioned save data. `GameSession` asks
`PersistenceService` to write or load a slot. The service validates a temporary
write before replacing a primary file, keeps a backup, and consults
`SaveMigrations` while loading older versions. `SaveSlots` maps the numbered
slots used by the menus. A save stores lineage and checkpoint information;
the live food and creatures are reconstructed when a run continues.
The implemented on-disk schema, migrations and slot rules are indexed in [the save format reference](saves/SAVE_FORMAT.md).

## Checks and builds

The pinned versions are in `tools/toolchain.env`; `tools/setup_toolchain.sh`
downloads the Linux Godot editor and, with `--templates`, Windows export
templates. On Windows, use the matching Godot version as described in
`docs/TOOLCHAIN.md`. A direct unit run is:

```text
godot --headless --path . --script res://tests/run_tests.gd
```

`tools/check.sh` imports assets, runs that full suite, checks the M0 boot
scene, runs launch/play/UI/death/menu smokes, rejects engine or script errors
in smoke logs, and checks the release pack. `tests/run_tests.gd` supports
`--only` and `--skip-slow` for local investigation; CI uses neither. Smoke
outputs go under `builds/smoke/`.

`.github/workflows/ci.yml` runs the check and Windows export on Ubuntu, then
launches the exported builds in a Windows job. `.github/workflows/nightly.yml`
calls CI. `tools/export_windows.sh` builds release and dev executables under
`builds/windows/`; the release excludes `game/dev/` and tests, while the dev
build includes the debug tools. An export alone does not establish that the
game launched successfully on Windows: the CI Windows launch job is the
separate check.
