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

Each carried part contributes to a recurring burden, with each extra copy costing 35% more than the previous copy. Flagella carry a weight of 1.6, spikes 1.3 and other parts 1.0; scale contributes 1.5 times scale. Food need is ceil(population times (scale + 0.07 times burden) / 4). Every generation, points change by 4 + min(4, food taken) - upkeep - bank tax, clamped to 0-100; upkeep is ceil(0.65 times burden), and bank tax is max(0, floor((current points - 50) / 12)). A lean fed body earns points, but a maximum-burden body loses points even when fed. The bank tax limits passive point hoarding without freezing adaptation. Spikes reduce movement speed by 0.18, then an additional 0.08 per copy, while flagella raise speed but also raise food need. Eye spots modestly improve predator defence. These coefficients are PROPOSED tuning values.

The shared pool holds at most 48 food units and regrows 38 per generation. Foragers compete in stable ability/id order; hunters select smaller or slower prey, with speed, size, spikes and eye spots affecting the encounter. Population stays in 0-24, scale in 0.5-2.0, and every body requires a mouth and respects catalog part counts and the eight-part cap.

The response to predation uses the actual attack: a faster predator favors flagella and concealment, while a larger predator favors spikes and concealment, with stable ID ties. Scarcity can lead to a filter mouth, cilia, smaller size or shedding a costly optional part. A one-unit shortfall can also trigger a response once the species has 40 points. Abundant food can support growth, an eye spot or cilia, or shedding costly parts when upkeep is high. At most one change occurs per species per generation and changes have a three-generation cooldown. Journal entries name the predation, shortfall, feeding or re-founding cause.

If a species drops below three members after its cooldown, it can re-found from the nearest surviving relative, measured by role, scale and part counts with stable ID ties. It returns with eight members, 15 points, a body 0.2 smaller and one optional part shed where possible; at least one mouth remains. This is a prototype recovery rule, not a claim about real speciation.

The test runner checks catalog alignment, byte-identical output, all trait/population bounds and cooldowns over 500 generations x 20 seeds, causal journal lines, attack-specific adaptations, and an integrated scarcity-triggered re-founding path. In the ordinary 20-seed run, 20/20 seeds finish with at least four species alive, 20/20 avoid a 100-point streak over 50 generations, 20/20 have a non-re-founding adaptation after generation 100, and 20/20 earn at least 40 points before adaptation. All 20 seeds have distinct final tables. All five species survive the first 20 generations in 20/20 seeds. Re-founding occurs 80 times in the ordinary 500-generation x 20-seed set; the lower-food stress case exercises it separately. These headless results do not establish rendered gameplay balance.

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
  Hunters became larger after eating 14 food units (population 24).
  Runners became larger after eating 8 food units (population 24).
Generation 5 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 1 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 6 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 24).
  Runners kept their parts after taking 9 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 7 (shared food 48)
  Grazers became larger after eating 10 food units (population 24).
  Hunters became larger after eating 14 food units (population 24).
  Runners grew a spike after Hunters took 2 of them (population 24).
Generation 8 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 1 to predators, and lacking 1 food units (population 23).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 9 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 4 food units (population 23).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 0 food units (population 24).
Generation 10 (shared food 48)
  Grazers grew a spike after Hunters took 2 of them (population 22).
  Hunters became larger after eating 14 food units (population 24).
  Runners became larger after eating 10 food units (population 24).
Generation 11 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 10 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 12 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 12 food units, losing 0 to predators, and lacking 2 food units (population 24).
  Runners kept their parts after taking 10 food units, losing 1 to predators, and lacking 0 food units (population 24).
Generation 13 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters grew cilia to forage after shared food ran short by 4 (population 23).
  Runners became larger after eating 10 food units (population 24).
Generation 14 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 4 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 15 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 16 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 17 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 18 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 19 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
Generation 20 (shared food 48)
  Grazers kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 22).
  Hunters kept their parts after taking 10 food units, losing 0 to predators, and lacking 3 food units (population 22).
  Runners kept their parts after taking 10 food units, losing 0 to predators, and lacking 1 food units (population 24).
~~~

## PROPOSED seed-1 500-generation summary

Exact summary table, excluding the startup banner:

~~~text
species | population | parts | points
Grazers | 22 | mouth_filter, eye_spot, cilia, cilia, cilia, flagellum, spike | 25
Hunters | 9 | mouth_jaw, flagellum, mouth_filter, cilia, cilia, cilia | 0
Runners | 20 | mouth_filter, flagellum, flagellum, cilia, spike, cilia, cilia | 19
Shoalers | 21 | mouth_filter, cilia, eye_spot, flagellum, cilia, cilia, spike | 18
Rammers | 24 | mouth_filter, cilia, eye_spot, cilia, cilia, flagellum, spike | 36
~~~
