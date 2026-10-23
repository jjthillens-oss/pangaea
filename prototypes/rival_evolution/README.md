# Rival evolution prototype v2

**Status: PROPOSED research tuning.** This is an isolated Godot project. Nothing in the game loads it, and these rules do not change the game or its save schema.

Run from the repository root with pinned Godot 4.7.2:

```sh
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1 --generations=20 --species=5
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1 --generations=20 --species=5 --csv
godot --headless --path prototypes/rival_evolution --script res://tests/run_tests.gd
```

`--generations` accepts a positive integer; `--species` accepts 3, 4 or 5. The default is 20 generations and four species. `--csv` emits one trait record per species and generation, including population, food, predation, shortfall, scale, speed, mouth, spikes, points and parts. Same seed and options produce byte-identical journal and CSV output. The model is an abstract pool experiment, not the cell-stage population simulation.

## PROPOSED visible traits and budget

The six editor parts, their costs and count limits mirror `game/data/part_catalog.json`; the tests read that file without changing it and check the mirror. The initial Grazer uses the catalog's grazer body, Hunter uses `ambush_hunter`, and Rammer uses the M1 `rammer` body from `game/data/creatures_m1.json`. Runners and Shoalers are variants using the same catalog parts. Five named species are available; `--species=3` uses the first three. All bodies require a mouth, at most eight parts and scale 0.5–2.0. A rival spends accumulated adaptation points on each added part or scale change, and no part exceeds its catalog count limit.

Each generation, one shared food pool regrows by 24 units up to 36. Grazers and filter-mouth hunters compete for it in forage ability order, breaking ties by stable species ID. A filter mouth, cilia and speed can improve feeding; a larger body needs more food. Jawed Hunters also select smaller or slower living prey. Their speed and size improve attacks; prey speed, spikes and size improve defence. A successful kill feeds the hunter and reduces the prey's population. The seeded random stream only perturbs attack strength. Population stays in 0–24 and adaptation points in 0–100. These figures are PROPOSED tuning values.

Predation of at least two members can trigger a spike, then speed. A shortfall can trigger a filter mouth, cilia, then smaller size. Adequate feeding can grow size. Each species makes at most one change per generation and waits three generations before the next change, preventing an immediate reversal. The journal states the observed cause for each change or hold. These rules are PROPOSED; the prototype does not promise plausible ecology over arbitrarily long runs.

The test runner checks catalog alignment, repeatability, trait and population bounds over 500 generations for 20 seeds, cooldown, causal lines, and 20-generation survival. With five species, all species survive the first 20 generations in 20/20 tested seeds (required: at least 18/20). It does not measure rendered visuals or game balance.

## PROPOSED sample 20-generation journal

Exact output of `--seed=1 --generations=20 --species=3`, excluding Godot's startup banner:

```text
Generation 1 (shared food 36)
  Grazers grew a spike after Hunters took 2 of them (population 19).
  Hunters grew a filter mouth after prey supplied 3 fewer food units than needed (population 18).
  Runners became larger after eating 4 food units (population 21).
Generation 2 (shared food 36)
  Grazers kept their parts after taking 5 food units, losing 0 to predators, and lacking 0 food units (population 22).
  Hunters kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 21).
  Runners kept their parts after taking 5 food units, losing 1 to predators, and lacking 0 food units (population 23).
Generation 3 (shared food 36)
  Grazers kept their parts after taking 6 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 6 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 4 (shared food 36)
  Grazers became larger after eating 6 food units (population 24).
  Hunters became larger after eating 13 food units (population 24).
  Runners grew a spike after Hunters took 2 of them (population 24).
Generation 5 (shared food 36)
  Grazers kept their parts after taking 7 food units, losing 1 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 11 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 6 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 6 (shared food 36)
  Grazers kept their parts after taking 7 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 6 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 7 (shared food 36)
  Grazers became larger after eating 7 food units (population 24).
  Hunters became larger after eating 11 food units (population 24).
  Runners became larger after eating 6 food units (population 24).
Generation 8 (shared food 36)
  Grazers kept their parts after taking 8 food units, losing 1 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 6 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 9 (shared food 36)
  Grazers kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 6 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 10 (shared food 36)
  Grazers grew a spike after Hunters took 2 of them (population 24).
  Hunters became larger after eating 14 food units (population 24).
  Runners became larger after eating 6 food units (population 24).
Generation 11 (shared food 36)
  Grazers kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 7 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 12 (shared food 35)
  Grazers kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 7 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 13 (shared food 34)
  Grazers became larger after eating 8 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
  Runners became larger after eating 7 food units (population 24).
Generation 14 (shared food 33)
  Grazers kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters became larger after eating 12 food units (population 24).
  Runners kept their parts after taking 8 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 15 (shared food 31)
  Grazers kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 8 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 16 (shared food 29)
  Grazers became larger after eating 8 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners became larger after eating 8 food units (population 24).
Generation 17 (shared food 27)
  Grazers kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters became larger after eating 12 food units (population 24).
  Runners kept their parts after taking 8 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 18 (shared food 24)
  Grazers kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 5 food units, losing 1 to predators, and lacking 3 food units (population 23).
Generation 19 (shared food 24)
  Grazers became larger after eating 9 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners grew cilia to forage after shared food ran short by 3 (population 23).
Generation 20 (shared food 24)
  Grazers kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters grew cilia to forage after shared food ran short by 5 (population 23).
  Runners kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
```
