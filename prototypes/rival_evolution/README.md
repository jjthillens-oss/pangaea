# Rival evolution prototype v3

**Status: PROPOSED research tuning.** This isolated Godot project is not loaded by the game. Its traits mirror the six parts and limits in the read-only game/data/part_catalog.json; initial Hunter and Rammer parts mirror game/data/creatures_m1.json. These rules do not change game balance or saves.

Run with pinned Godot 4.7.2 from the repository root:

~~~sh
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1 --generations=20 --species=5
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1 --generations=500 --species=5 --summary
godot --headless --path prototypes/rival_evolution --script res://run.gd -- --seed=1 --generations=20 --species=5 --csv
godot --headless --path prototypes/rival_evolution --script res://tests/run_tests.gd
~~~

The generations option is a positive integer, species is 3 to 5, and summary prints one end-state table instead of the journal. CSV retains the v2 trait history. The same seed and options produce byte-identical output.

## PROPOSED costs, interactions and bounds

Each carried part contributes to a recurring burden, with each extra copy costing 35% more than the previous copy. Flagella carry a weight of 1.6, spikes 1.3 and other parts 1.0; scale contributes 1.5 times scale. Food need is ceil(population times (scale + 0.07 times burden) / 4). Every generation, points change by 3 + min(3, food taken) - ceil(1.5 times ceil(0.65 times burden)), clamped to 0-100. Thus larger bodies and more parts are paid for repeatedly. Spikes reduce movement speed by 0.18, then an additional 0.08 per copy, while flagella raise speed but also raise food need. Eye spots modestly improve predator defence. These coefficients are PROPOSED tuning values.

The shared pool holds at most 48 food units and regrows 38 per generation. Foragers compete in stable ability/id order; hunters select smaller or slower prey, with speed, size, spikes and eye spots affecting the encounter. Population stays in 0-24, scale in 0.5-2.0, and every body requires a mouth and respects catalog part counts and the eight-part cap.

Predation can lead to spikes, speed or eye spots, chosen deterministically by generation and species ID from the observed attack; when those choices are exhausted, a smaller body can hide. Scarcity can lead to a filter mouth, cilia, smaller size or shedding a costly optional part. Abundant food can support growth only while upkeep is modest. At most one change occurs per species per generation and changes have a three-generation cooldown. Journal entries name the predation, shortfall, feeding or re-founding cause.

If a species drops below three members after its cooldown, it can re-found from the nearest surviving relative, measured by role, scale and part counts with stable ID ties. It returns with eight members, 15 points, a body 0.2 smaller and one optional part shed where possible; at least one mouth remains. This is a prototype recovery rule, not a claim about real speciation.

The test runner checks catalog alignment, output determinism, all trait/population bounds and cooldowns over 500 generations x 20 seeds, causal journal lines, distinct predation adaptations and an integrated scarcity-triggered re-founding path. In the ordinary 20-seed run, 20/20 seeds finish with at least four species alive and 20/20 avoid a streak above 50 generations at 100 points (both required: at least 16/20). All five species survive the first 20 generations in 20/20 seeds (v2 requirement: at least 18/20). The ordinary 500-generation set triggers no re-founding; the scarcity test uses lower food regrowth to exercise that path. These headless results do not establish rendered gameplay balance.

## PROPOSED sample 20-generation journal

Exact output of seed 1, 20 generations, three species, excluding Godot's startup banner:

~~~text
Generation 1 (shared food 48)
  Grazers became larger after eating 7 food units (population 20).
  Hunters grew a filter mouth after prey supplied 7 fewer food units than needed (population 16).
  Runners became larger after eating 6 food units (population 21).
Generation 2 (shared food 48)
  Grazers kept their parts after taking 8 food units, losing 1 to predators, and lacking 0 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 19).
  Runners kept their parts after taking 7 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 3 (shared food 48)
  Grazers kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 22).
  Runners kept their parts after taking 8 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 4 (shared food 48)
  Grazers grew a flagellum after Hunters took 2 of them (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners became larger after eating 8 food units (population 24).
Generation 5 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 6 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 7 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 8 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 9 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 10 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 11 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 12 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 13 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 14 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 15 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 16 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 17 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 14 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 2 to predators, and lacking 0 food units (population 24).
Generation 18 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 19 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 20 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
~~~

## PROPOSED seed-1 500-generation summary

Exact summary table, excluding the startup banner:

~~~text
species | population | parts | points
Grazers | 24 | mouth_filter, flagellum, eye_spot | 5
Hunters | 24 | mouth_jaw, flagellum, flagellum, mouth_filter | 0
Runners | 24 | mouth_filter, flagellum, flagellum | 0
Shoalers | 24 | mouth_filter, cilia, eye_spot, flagellum, eye_spot | 0
Rammers | 10 | mouth_filter, spike, spike, spike, flagellum | 0
~~~
