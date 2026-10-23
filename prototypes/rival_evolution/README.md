# Rival evolution prototype

**Status: PROPOSED research tuning.** This is a separate Godot project. Nothing in the game loads it.

Run from the repository root with the pinned Godot 4.7.2 executable:

```sh
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1
godot --headless --path prototypes/rival_evolution --script res://tests/run_tests.gd
```

The runner prints 20 generations for four species. Each generation draws food and predation pressure for every species from a single RNG stream seeded by `--seed`. Species are processed in ascending numeric ID order, which also breaks every output tie. A run is an abstract pool model, not a population or gameplay simulation. Traits are retained between generations; populations are not modeled.

| Trait | Bounds | Adaptation rule |
| --- | --- | --- |
| Size | 1–5 | Abundant food grows it; starvation may shrink it. |
| Speed | 1–5 | Repeated heavy predation increases it after spikes reach their cap. |
| Mouth | filter, graze, bite | Starvation shifts it toward filtering; abundant food can strengthen it after size reaches its cap. |
| Spikes | 0–3 | Heavy predation grows them first. |

At most one trait changes for a species in a generation. Predation takes priority over feeding. A trait at its bound stays there; other eligible changes may apply as described above. The numbers and rules are proposals for testing the owner-approved direction that rivals evolve by visible, bounded rules. They do not amend the game's design or save schema.

Example journal lines for `--seed=1`:

```text
Generation 1
  Drifters grew spikes after heavy predation (food 2, losses 2).
  Grazers grew spikes after heavy predation (food 1, losses 2).
```

The tests check byte-identical output for a repeated seed, different output for different seeds, all four trait bounds over 200 generations for 20 seeds, and the default 20-generation output length.
