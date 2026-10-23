# GDScript lint baseline

Status: IMPLEMENTED as an advisory CI job; existing source formatting is unchanged.

## Method

On Windows, from `main` at `97b929b`, I ran `gdtoolkit==4.5.0` with its default rules against the same paths used by the new CI job:

```text
gdlint game tests tools
gdformat --check game tests tools
```

The scope contains 143 `.gd` files. The tools exit with status 1 because the current tree has findings. The new `gdscript-lint` job uses `continue-on-error: true`; it still runs the formatting step when lint fails, and it does not gate `test-and-export` or `windows-launch`. Prototype projects are outside this job because each has its own Godot project and conventions.

## Current findings

| Lint rule | Findings |
| --- | ---: |
| `max-line-length` | 2,226 |
| `class-definitions-order` | 35 |
| `max-public-methods` | 10 |
| `max-file-lines` | 6 |
| `max-returns` | 3 |
| `class-variable-name` | 2 |
| `unused-argument` | 1 |
| `function-argument-name` | 1 |
| `function-variable-name` | 1 |
| `comparison-with-itself` | 1 |
| **Total** | **2,286** |

The 2,286 lint findings occur in 119 files. `gdformat --check` would reformat 128 files and leave 15 unchanged. No existing file was reformatted for this task.

| File | Lint findings |
| --- | ---: |
| `tests/test_threats_sim.gd` | 209 |
| `tests/smoke/play_smoke.gd` | 154 |
| `tests/test_pool_view.gd` | 109 |
| `tools/godot/look_probe.gd` | 109 |
| `tests/test_species_catalog.gd` | 80 |
| `tests/test_creature_brain.gd` | 76 |
| `tests/test_ui_text.gd` | 74 |
| `game/systems/species_catalog.gd` | 66 |
| `tests/test_assets.gd` | 66 |
| `tests/test_ambience_contract.gd` | 62 |

## Rule recommendation

I would turn off `max-line-length` in a later, reviewed configuration change. It accounts for 97% of findings, and the existing test fixtures and assertions often use long literal values that are clearer together. Keeping it on now obscures more specific findings such as `comparison-with-itself` in `tests/test_pool_view.gd:864`. I would keep the other rules enabled, including the six size/complexity warnings, until their individual findings have been reviewed. I have not added a `gdlintrc` here, so this report reflects the toolkit defaults and CI reports the full baseline.

Version source: [gdtoolkit 4.5.0 on PyPI](https://pypi.org/project/gdtoolkit/4.5.0/), the stable Godot 4 series used by the CI job.
