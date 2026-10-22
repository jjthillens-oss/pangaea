> **Final pre-build plan for M1 step 3 (2026-10-22). Status: PROPOSED.** It is copied here unchanged
> from the step 3 planning round: three competing plans (sim-first, player-first and risk-first),
> judged and merged into this one, written against step 2 at `a53fc70` (252 tests). The build starts
> from `a3fe55b` (262 tests) and differs from this plan where the code's facts disagree; the step 3
> section of `docs/milestones/M1.md` will list those deviations, and the code and `game/data/` hold
> the current values. Paths under `scratchpad/` and `wt/` name the planning copies, which are not in
> the repository.

# M1 step 3 "Threats": final implementation plan

**Status:** PROPOSED. Every number is PROPOSED tuning. Each one lives in `game/data/creatures_m1.json`, in `game/data/pool_m1.json`, or in a constant at the top of a `game/domain` file, and its reason is written next to it.

**Base:** step 2 at `a53fc70` ("Merge fix1-assets"), as checked out in `wt/plan3`, with 252 tests.
- A second review of the step 2 screens, dev layer and plumbing is still running. This plan does not plan around its outcome.
- It touches `hud.gd`, `main.gd`, `debug_panel.gd`, `dev_keys.gd` and `play_smoke.gd` only additively. Agents rebase onto whatever lands first and change nothing around it.

**Verification:**
- Every claim marked *verified* was run in a private copy (`scratchpad/p3-synth`) with the pinned `Godot_v4.7.2-stable` and an absolute `XDG_DATA_HOME` (`scratchpad/p3-synth-xdg`).
- Geometry was computed in Python (`scratchpad/p3-synth-py/`) from the real `pool_m1.json`.
- The repository and `wt/plan3` were not modified.

**Winner: sim-first** (3 of 4 judges). All threat gameplay runs inside the deterministic 60 Hz `PoolSim`: senses, brains, movement, strikes, damage, deaths, carcasses, spawns, checkpoints and fairness.
- The brain is a pure `game/domain` function of explicit percepts, so "it cannot see your coordinates" holds by construction and is tested.
- Scenes only draw the sim state and play cues from sim events.
- A tell on screen and the damage window in the sim come from the same tick counter, so they cannot disagree.

**Grafted from player-first:**
- **The locked strike line.** The heading locks at the tell start and the strike is a burst plus a glide along it, with no homing. Unlike the player plan, the line aims at a *capped lead point* taken at the tell start, because a purely locked lunge misses prey grazing at 30% even with no reaction. `CreatureBrain.strike_lane()` is one pure function used by the view, the tests and the gizmos.
- **EvadeBot.** It reacts only to sim events, 24 ticks after a tell starts, on the shorter-turn side. It drives a pinned grid of distances × 12 headings × still or grazing × fed or starving × 3 bodies, with a clearance margin.
- **The F1–F7 fairness contract** at the top, each promise naming its enforcing test.
- **The puff cancels** when the intruder leaves the territory. A `dodged` event fires when a strike that targeted the player ends without a hit.
- **Species genomes** are built with `Genome.new()` and fixed ids, and validated directly against the catalog.
- **The world-start carrion moves** out of the rammer territories.
- **An escape-speed data rule,** plus an S6 escape test for fed and starving bodies.
- **Off-screen threat indicators**, never cut.
- **The ambush "watch" phase:** a sated hunter turns to track you but does not engage.
- **The `save_v2_step2.json` fixture.**
- **Grace on a new lineage start** as well as on continue.
- The GDScript typed-value and absolute `XDG_DATA_HOME` notes.

**Grafted from risk-first:**
- the engagement token (at most 1 creature engaged with the player);
- the hard leash clamp;
- per-tick fuzz invariants with KiterBot;
- the T5 invariance test (and T10, T12, T14, T15);
- the mutation table and non-vacuity asserts;
- the flake policy and the stated determinism scope;
- the `ViewFootprint` spawn rule;
- the two-process smoke `die_and_quit` → `after_death`;
- the rule that every sort breaks ties by id.

**Rejected** (section 28 says why):
- from risk: "no saving while hunted" and `session.step()`;
- from player: layout schema 2, float-second timers, composite species GLBs, "respawn remains", and a starving-speed approach cap.

**What the player gets in step 3:**
- **Ambush hunters.** Three large, flat, dark cells with amber eyes wait at the south-east and south-west rims and in the north-west rock gap.
  - When one notices you, it turns to watch.
  - If you come within 3 m in front of it, it stops and *coils* for 1.2 s (it squashes, its jaw opens, its eyes brighten and a lane appears on the floor), then lunges along a fixed line.
- **Territorial rammers.** Four pale, banded, spiked cells patrol the rich north zones.
  - An intruder gets noticed, approached to about 4 m, then the rammer *puffs up* for 1.2 s and charges along a fixed line.
  - If you leave its patch during the puff, it deflates and stays home.
- **One at a time.** At most one creature chases or attacks you at once.
- **Fighting back.** A jaw bites and spikes ram, automatically on contact. Every kill drops meat chunks. Carrion now comes from kills, not from the step 2 trickle.
- **Death.** Getting caught or starving shows a short reason and a tip, saves the death at once (owner decision OD1), and returns you to the generation start.
  - You are sheltered there for 5 s, or 8 s or 10 s after a quick repeat death.
  - No threat can reach that spot.
  - The lineage is never erased.

---

## The fairness contract (what the player can rely on)

| # | Promise | How it is enforced |
|---|---|---|
| F1 | **You always see it coming.** Every attack has a tell of at least 1.2 s, shown by pose, sound, a "!" marker, a floor lane, and an edge arrow when the creature is off-screen. The strike line locks when the tell starts and never tracks you afterwards. | SpeciesCatalog rules 4 and 13; test_creature_brain #3; threats_sim #6 (exact ticks); fuzz invariants 4–5 |
| F2 | **A 0.4 s reaction is enough.** Swimming out of the line on the side you are facing (a turn of at most 90°), 24 ticks after the tell starts, avoids the strike. The only budgeted exceptions are swimming head-on into it while starving. The other side is not promised: turning all the way round takes longer than the 1.2 s tell. Measured every 5°, a dodge to the side behind the cell is never hit below a 120° turn while the cell faces away from the creature, but facing it (150–210°) the lunge hits from a turn of about 100° (98° fed, 96° starving). (Worded by the step 3 review fixes: the first wording, "sideways", did not say which side.) | threats_sim #2–4 (the S5 grid: EvadeBot on the side the cell faces, clearance margins); slow gates: the same side every 5° through the head-on sector, and the side behind the cell as measured |
| F3 | **A fed cell can always outswim a chase, and every chase ends.** Pursuit speed is at most 0.9 × the slowest fed starting body. Every chase ends by timer, lost sight, leash, territory or unreachable. A starving cell that swims straight away is never hit, and the threat gives up. | SpeciesCatalog rule 3; test_creature_brain #4; threats_sim #5 (S6), #18–19; fuzz invariant 6 |
| F4 | **One at a time.** At most 1 creature is engaged (chase or attack) with you. | Token; threats_sim #21 (T6); fuzz invariant 8 |
| F5 | **Hits land only when they look like hits.** Damage happens only inside a strike that followed a full tell, at most once per strike. No single hit takes 50% of a starting body's health. | SpeciesCatalog rule 5; threats_sim #6; fuzz invariants 4–5 |
| F6 | **No surprise spawns.** Creatures appear only at their own sites, at least 20 m from you and outside the view at maximum zoom. They fade in and ignore everything for 3 s. | test_creature_field #2, #7; test_view_footprint |
| F7 | **Death is short, fair and never erases the lineage.** You get a reason and a tip; the death is saved at once (OD1). You return to a checkpoint that no threat's leash reaches, with shelter 5/8/10 s and energy 0.6/0.8/1.0. Your killer ignores you for 30 s. You lose only a quarter of unspent points. | test_checkpoints #1–8; SpeciesCatalog rule 8; fuzz invariant 3 |

The respawn mechanics behind F7 are listed as rules C1–C7 in section 13.

---

## 0. Facts verified (pinned engine, my copy, and Python)

### Engine and code facts

| Fact | How it was checked | Consequence |
|---|---|---|
| `Genome.create("species:ambush_hunter")` draws `genome_id` from `StableId.generate` (Crypto). `validate` then reports "Genome has an invalid lineage id 'species:ambush_hunter'." `Genome.new()` + `add_part` also fails `validate` on its ids. | engine probe (`probes/facts.gd`) | Species genomes use `Genome.new()` with fixed ids. Their parts are validated directly against `PartCatalog`, never through `Genome.validate` (rule 1) |
| `JSON.stringify` writes a `Vector2` as `"(0.1, 0.333333)"` (about 6 digits), even with `full_precision` | engine probe | Every vector in `snapshot()` goes through `PoolSim._pair()`; `Memory.to_dict()` holds only arrays |
| `Array.sort_custom` is **not stable** on ties (200 items, 3 keys) | engine probe | Every sort the plan adds breaks ties by id or number |
| Restoring `RandomNumberGenerator.state` repeats the next draw | engine probe | RNG states go into the snapshot and the hash |
| `roundi(s × 60)`: 1.0 s → 60, 1.2 s → 72, 0.35 s → 21, 0.4 s → 24. Adding 1/60 repeatedly first reaches 0.5 s on tick 31, not 30 | engine probe | Every timer is an integer tick count, converted once at load |
| `var x := dict[key]` is a parse error: "Cannot infer the type of "x" variable because the value doesn't have a set type." | engine probe | Agents write `var x: float = dict[key]` |
| A relative `XDG_DATA_HOME` is ignored: `OS.get_user_data_dir()` falls back to `/root/.local/share/Pangaea`. An absolute one is used | engine probe | Probes, tests and `check.sh` runs before the PR use an absolute path |
| `Phenotype.derive(genome, catalog)`: part benefits diminish by rank, costs (upkeep, mass) are paid in full, `speed = (base + Σ) / mass`, radius = base 0.5. `to_dict()` leaves out `radius`, `mouths` and `spikes` | code read | The size-1 identity test compares those three as well |
| `Locomotion.steer`: `ALIGN_POWER` 2, `BRAKE` 1.5, `COAST` 0.9, `LATERAL_DAMPING` 6. The target speed is capped at `sqrt(top² − w²)` (a step 2 deviation) | code read | A burst cannot go through `steer`. `Locomotion.burst`/`glide` are added, bounded by rule 3 |
| `InteractionResolver`: `BITE_REACH` 0.3, `RAM_REACH` 0.35, `FEED_REACH` 0.25, `BITE_SIZE_LIMIT` 1.6, cooldowns 0.6 s (bite) and 0.5 s (ram), keys `"bite:<id>"`/`"ram:<id>"`, jaw arc 60°, spike arc 40°, spike stacking 0.6, ram impact `clamp(closing / attacker.speed, 0.25, 1.5)`. Bite refusal order: needs a jaw → itself → too big → out of reach → jaw not facing → recovering. Ram order: needs a spike → not moving toward it → out of reach → no spike points at it → recovering | code read | No resolver change is needed |
| `ActorState`: `STARVING_SPEED` 0.5, `STARVATION_DAMAGE` 1.5/s, regeneration 2%/s above half energy | code read | Creature metabolism scales all three (D4) |
| `PoolSim`: tick order player steer → move → metabolism → `region.tick` → `plankton.tick` → `carrion.tick` → field events → sync → feed → `tick++`. Seeds `world_seed × 1000003 + 1` (region) and `+ 2` (carrion). `create()` uses the saved position unless it equals the spawn. `respawn_player()` places the cell at `layout.spawn`. Dev commands return bool. The death event is `died {cause: "starved"}` | code read | Creature steps are inserted only when species data is given (T14) |
| `GameSession.respawn_after_death()` hard-codes `"starved"`. `_write()` stores `sim.motion.position`, which is the corpse while dead. `_is_dirty()` = `sim.dead or points/history changed or moved > 1 m from _saved_position`. `save_now()` is refused while dead | code read | `resolve_death()`, `position_for_save()` and a checkpoint-aware dirty check (section 13) |
| `Main.death_title(cause)` returns "Out of energy" for `starved`, else "Your cell died". `death_text(cause, lost)`. `request_quit()` shows "Save first?" when dirty, plus "Saving is off…" while dead | code read | The new arguments get defaults, so the step 2 callers and tests keep working |
| `CarrionField.spawn(position, source, p_energy := NAN, p_points := -1)`; points follow the data rate (24 energy → 3 points) | code read | Kill carcasses reuse it |
| `Lineage.apply_death(save, cause)` takes any cause string, removes `floor(25%)` and appends `{event: "died", cause, points_lost}` | code read | Causes `killed:<species>` need no schema change |
| `test_sim_purity._code_only` strips comments **and string contents** | code read | The `"player"` scan needs a new helper that keeps strings |
| `tests/run_tests.gd` has no `--skip-slow` or `--only` flags | code read | Added (section 18) |
| `PoolLayout.MAX_SPEED` = 6.0; catalog caps speed 6, spike `max_count` 4, `max_parts` 8, scale 0.5–2.0 | code read | Rule 3; the rammer genome fits |
| `PlayerCellView.PART_SCENES` has no `spike` entry, so a spike part draws nothing today | code read | `part_spike.glb` is added |
| `blockout_common.export(asset_id, budget, fields)` reads the module constants `REVIEW_STATE` and `GENERATOR` | code read | Keyword arguments are added; the defaults are unchanged |
| `export_presets.cfg`: the release preset excludes `tests/*,game/dev/*`; the dev preset excludes `tests/*` | code read | All bots live in `game/dev` (no `class_name`) |
| Test fixtures `pool_test_small.json` and `pool_test_rocks.json` are layout schema 1 | code read | `pool_m1.json` stays at schema 1 |

### Supply off, with the moved carrion

`carrion.interim_supply.enabled = false` and initial carrion `[[1.5, 4], [−10.5, −4.5], [10.5, −4.5]]`, run on the full suite (*verified*): 252 tests, exactly 4 fail, in 30 s.
- `test_pool_sim::test_a_hunter_starving_late_in_a_run_still_finds_carrion` (all cases starve) is replaced (section 18).
- These 3 test the supply itself and keep running with the supply switched on in the test:
  - `test_carrion_field::test_the_interim_supply_is_deterministic_per_seed`;
  - `test_carrion_field::test_the_supply_never_exceeds_max_live`;
  - `test_plankton_field::test_carrion_spawns_never_draw_from_the_region_rng`.
- `test_pool_sim::test_a_starving_hunter_recovers_from_the_worst_point_in_the_pool` **still passes** with the moved pieces.

### Bodies

These come from `Phenotype.derive`, and from the size rule (section 6) ported to GDScript in `probes/sized.gd` and run on the pinned engine.

**Size-1 identity** (*verified*): at size 1 the port matches `derive` for the 3 starting bodies and 8 single-part genomes (11 genomes), including `radius`, `mouths` and `spikes`.

| Body | Speed (starving) | Accel | Turn | Health | Upkeep | Sight | Mass | Radius | Weapon |
|---|---|---|---|---|---|---|---|---|---|
| Grazer | 2.906 (1.453) | 3.077 | 2.5 | 30 | 0.90 | 9 | 1.17 | 0.5 | — |
| Hunter | 3.262 (1.631) | 3.046 | 2.5 | 30 | 1.15 | 6 | 1.30 | 0.5 | bite 8 |
| Omnivore | 2.720 (1.360) | 2.880 | 2.5 | 30 | 0.95 | 6 | 1.25 | 0.5 | bite 8 |
| **Ambush hunter** (hunter genome, size 1.5) | 2.749 | 2.277 | 2.5 | 45 | 1.725 | 6 | 1.95 | 0.75 | bite 12 |
| **Rammer** (filter 0; spikes ±0.3 and ±1.9 at scale 0.8; flagellum π; size 1.25) | 1.840 | 1.840 | 2.5 | 37.5 | 1.20 | 6 | 2.038 | 0.625 | 4 spikes × 6.0; front stack 9.6, × 1.5 = 14.4 |

**Alternatives probed:**

| Body | Radius | Speed | Other | Verdict |
|---|---|---|---|---|
| Ambush, size 1.4 | 0.70 | 2.822 | bite 11.2 | — |
| Ambush, size 1.6 | 0.80 | 2.685 | bite 12.8 | Rejected: the radius equals the 0.5 × 1.6 bite limit exactly, so fighting back would hinge on a float comparison |
| Rammer, size 1.0, spikes 1.0 | 0.5 | 1.943 | front 14.4 | Rejected: the same radius as the player, so danger reads from spikes alone |
| Rammer, size 1.2, spikes 0.8 | 0.6 | 1.881 | front 13.82 | — |
| Rammer, size 1.2, spikes 1.0 | — | — | front 17.28 | Rejected: breaks the two-hit rule |

**Corrected claim.** The ambush hunter at 2.749 m/s is **not** slower than every starting body: the omnivore swims 2.720, and every starving body 1.36–1.63. The escape guarantee therefore comes from a validated pursuit-speed rule (F3), not from body size.

**Who can bite whom.**
- The ambush hunter (0.75) can bite a 0.5 cell, since 0.5 ≤ 0.75 × 1.6.
- A 0.5 cell with a jaw can bite the ambush hunter (0.75 ≤ 0.8) and the rammer (0.625 ≤ 0.8).
- **The two-hit rule holds.** The worst single hits are 12 (bite) and 14.4 (charge at the impact cap), both below 15 = 0.5 × 30.

### The strike probe (`probes/tell_probe.gd`, real `Locomotion`, `PoolArena` and `InteractionResolver`)

**Setup:**
- The creature starts at rest at the origin, facing the prey at center distance d.
- The prey has heading h: 12 headings, where 0° faces away from the creature and 180° faces it head-on. It is still, grazing (30% throttle) or cruising (80%), fed or starving (× 0.5).
- **At the tell start** the lane locks toward `prey + clamp(velocity × lead_s, lead_cap_m)`. During the tell the creature brakes and turns to the lock at full rate.
- **Strike:** a burst sets `velocity = lane × burst_speed`, then a glide multiplies the velocity by `exp(−drag·dt)`. `bite`/`ram` are tried every strike and glide tick.
- **EvadeBot:** 24 ticks after the tell starts, the prey swims perpendicular to the lane on the side with the shorter turn from its heading (tie: the side of the lane it is already on), and holds it.
- **Clearance** = the distance from the prey's center to the resolver's allowed sector (reach × arc), minimised over the strike.

**Final configuration:**
- **Lunge:** size 1.5; tell 1.2 s (72 ticks); burst 4.5 m/s × 0.35 s (21 ticks); glide 0.25 s (15 ticks) with drag 6; travel 2.16 m; lead 1.2 s capped at 1.0 m.
- **Charge:** size 1.25; spikes 0.8; puff 1.2 s; burst 4.0 m/s × 0.9 s (54 ticks); glide 0.3 s (18 ticks) with drag 5; travel 4.22 m; lead 1.6 s capped at 1.2 m.
- Both stay within `MAX_SPEED` 6.

**Lunge results** (*verified*). d ∈ {2.5, 2.75, 3.0} × 12 headings = 36 cases per body; columns are grazer / hunter / omnivore.

| Base | Fed or starving | No reaction: hits | Perpendicular crossings hit (of 6) | Hits at 24 ticks | Min clearance | Cases under 0.15 m |
|---|---|---|---|---|---|---|
| still | fed | 36 / 36 / 36 | 6 / 6 / 6 | **0 / 0 / 0** | 0.27 / 0.26 / 0.22 | 0 |
| still | starving | 36 / 36 / 36 | 6 / 6 / 6 | **0 / 0 / 0** | 0.07 / 0.13 / 0.04 | 2 / 1 / 2, all head-on |
| graze 30% | fed | 23 / 21 / 23 | 6 / 6 / 6 | **0 / 0 / 0** | 0.06 / 0.03 / 0.04 | 1 / 2 / 2, all head-on |
| graze 30% | starving | 33 / 33 / 35 | 6 / 6 / 6 | **0 / 0 / 1** (head-on, 2.5 m, 180°) | 0.02 / 0.04 / 0.04 | 2 / 2 / 6 (head-on 2 / 2 / 5; others ≥ 0.149) |
| cruise 80% | fed | 1 / 0 / 2 | **0 / 0 / 0** | 0 / 0 / 1 (head-on) | 0.10 / 0.28 / 0.12 | — |
| cruise 80% | starving | 15 / 9 / 19 | 0 / 0 / 4 | 2 / 2 / 5, all at 150–210° | 0.02 / 0.04 / 0.02 | — |

**Charge results** (*verified*). d ∈ {3.0, 4.0, 5.0}:

| Base | Fed or starving | No reaction: hits | Perpendicular hit (of 6) | Hits at 24 ticks | Min clearance |
|---|---|---|---|---|---|
| still | fed | 36 / 36 / 36 | 6 / 6 / 6 | **0** | 0.58 / 0.57 / 0.52 |
| still | starving | 36 / 36 / 36 | 6 / 6 / 6 | **0** | 0.22 / 0.30 / 0.15 |
| graze 30% | fed | 28 / 24 / 28 | 6 / 4 / 6 | **0** | 0.33 / 0.29 / 0.29 |
| graze 30% | starving | 33 / 31 / 33 | 6 / 6 / 6 | **0** | 0.14 / 0.21 / 0.09 |
| cruise 80% | fed | 3 / 2 / 3 | **0 / 0 / 0** | 1 / 0 / 1 (head-on) | 0.44 / 0.12 / 0.43 |
| cruise 80% | starving | 19 / 11 / 20 | 2 / 0 / 2 | 1 / 0 / 5 | — |

**Other runs that set the numbers** (*verified*, same harness):
- **Reaction time, lunge.** At 15 ticks every case clears by ≥ 0.17 m. At 30 ticks, 2 head-on grazing cases are hit.
- **Escape direction.** Swimming **straight away** at 24 ticks is hit 5–9 times per body. **So every tip says "out of its line on the side you face"**, which is what the tests prove. (The first tips said "sideways, out of its line". The review fixes measured the other side: the side behind a cell needs a turn of 90–180°, facing the creature it is hit from a turn of about 100°, and a still cell that must turn round is hit, so the tips name the side; see F2 and `docs/DECISIONS.md`.)
- **A 1.0 s lunge tell** gives 2–3 hits per body for fed reacting prey, all head-on, so 1.2 s is chosen.
- **A lunge from 2.0 m:** still head-on clearance falls to 0.01–0.05 m, and one omnivore is hit grazing head-on. So `start_min_m` is 2.5.
- **A 1.0 s puff** passes at 4–5 m (starving grazing clearance ≥ 0.16 m) but degrades at 3–3.5 m, so 1.2 s is chosen.
- **A charge from 2.0–2.5 m** hits starving grazers, mostly approaching ones. So `start_min_m` is 3.0.
- **Judge probes on the base plan's tracking lunge:** a 0.4 s sideways reaction was hit 81/81. That is why the line locks and homing does not exist.

What these tables mean for the design:
- The S5 bounds in section 18 are these numbers.
- The only cases that fail are **head-on approaches (150–210°)**: either swimming into a strike or starving and moving toward the threat. They are the documented hard case, covered by the notice cue, the lane and the tip (D6).
- **Not yet verified:** the harness starts the creature at rest. The real brain therefore must stop before its tell (`chase/aim`, section 8), and S5 runs in the real sim to confirm this.

### Layout geometry (Python on the real `pool_m1.json`)

- Spawn (0, 9). Soft wall 36 m, hard limit 39.5 m.
- Zone centers from spawn:

  | Zone | Distance (m) |
  |---|---|
  | z_center | 9 |
  | z_s | 13 |
  | z_se, z_sw | 19.2 |
  | z_ne, z_nw | 27.7 |
  | z_n | 31 |
- **Rammer territories** are zone radius 6 + 2 = 8 m, with a leash of 3 m (11 m from the center). Every rock is at least 0.72 m outside that 11 m circle.

  | Zone | Center from spawn | Territory edge | Leash edge + body |
  |---|---|---|---|
  | z_n | 31.0 | 23.0 | 19.38 |
  | z_nw, z_ne | 27.66 | 19.66 | 16.03 |

- **Base-plan lairs fail a pinch check.**
  - lair_se (25.8, 14.9): rock_14 reaches into its 9 m leash disc and sits 1.16 m from the soft wall.
  - lair_sw (−25.8, 14.9): rock_16 does the same, 1.04 m from the wall.
  - Both gaps are below 2 × 0.75 + 0.5 = 2.0 m, a passage an ambush hunter can wedge in.
  - lair_gap (−9.6, −16.6) has rock_12 cutting its leash circle, so the hard clamp would push into the rock.
- **Final sites** (all checks pass):

  | Site | Home | Heading | From spawn | Leash disc + body to checkpoint | Rock clearance | Rock gap to leash circle (need) | Note |
  |---|---|---|---|---|---|---|---|
  | lair_se | (26.4, 12.6) | −2.9258 (faces z_se) | 26.64 | 16.89 | 10.00 | 1.75 (0.85) | 1.47 m from the z_se edge |
  | lair_sw | (−24.1, 16.6) | −0.8419 (faces z_sw) | 25.27 | 15.52 | 9.93 | 1.68 (0.85) | 1.51 m from the z_sw edge |
  | lair_gap | (−9.4, −16.3) | 1.0472 (faces the pool center) | 26.99 | 17.24 | 4.71 | 1.00 (0.85) | rock_06 inside, 10.06 m gaps; 2.99 / 3.05 m outside the z_n / z_nw territories |
  | terr_n_a / terr_n_b | (∓2.5, −22) | 1.5708 | 31.10 | 19.38 | ≥ 10.27 | 0.90 (0.72) | share z_n |
  | terr_nw | (−19.1, −11) | 0.5226 | 27.66 | 16.03 | 11.17 | 0.79 (0.72) | z_nw |
  | terr_ne | (19.1, −11) | 2.6190 | 27.66 | 16.03 | 11.27 | 0.89 (0.72) | z_ne |

  So **no creature's reachable area comes within 15.5 m of the checkpoint** (the rule requires 12).
- **Initial carrion.**
  - The old pieces (−14, −6) and (12, −14) lie 7.14 m and 7.71 m from the z_nw and z_ne centers, which is inside the 8 m territories.
  - The new (±10.5, −4.5) are 10.78 m from those centers: outside the territories, inside their 11 m leash disc. They are 11.85 m from lair_gap, outside its 9 m leash.
  - The worst point (−35.5, 0) is 25.4 m from the west piece.

### Camera footprint

North-up camera, pitch 55°, vertical FOV 45°, plane trapezoid relative to the look target:

| Zoom (distance) | Ahead (north) | Behind (south) | Corner distance, 16:9 | Corner distance, 2.4:1 |
|---|---|---|---|---|
| 10 | 7.12 | 3.92 | — | — |
| 14 (default) | 9.97 | 5.49 | 17.61 | 21.99 |
| 20 (maximum) | 14.24 | 7.84 | 25.16 | 31.42 |

- Only about 5.5 m south of the cell is visible at the default zoom, while sight is 6 m. **So off-screen indicators are required.**
- At maximum zoom on an ultrawide screen a corner lies 31 m away, beyond the 20 m spawn rule. **So the `ViewFootprint` rule exists.**
- All seven sites lie outside the zoom-max 2.4:1 footprint from the spawn, with the 2.5 m look-ahead + 1 m + body margin, so a new game fills every niche.

### From the base plan (judge-confirmed or measured there, not re-measured here)

| Measurement | Value |
|---|---|
| `test_a_tick_costs_well_under_a_millisecond` | 171.9 µs per tick |
| `PoolArena.move`, one body, 18 rocks | 17.8 µs |
| `Locomotion.steer` | 1.9 µs |
| One segment-vs-18-rocks line-of-sight test | 7.6 µs |

---

## 1. Corrections applied to the winning plan (every must_fix)

| # | Must fix (judges) | Fix in this plan |
|---|---|---|
| 1 | Tells were not human-dodgeable (0.7 s tracking lunge, homing strikes) | A line locked at the tell start, aimed at a capped lead point; **no homing field exists** (rule 13 rejects unknown keys). Tells are 1.2 s for both species, and the validated floor `min_tell_s` is 1.2 s, the probe value (sections 0 and 5) |
| 2 | Fairness tests reacted on the tell tick | S5: EvadeBot reacts 24 ticks after `creature_tell`, on a pinned grid, with clearance margins and per-cell bounds from the probe (section 18). Head-on is the documented hard case (D6) |
| 3 | #1 (grazing is hit) and #3 (crossing at 80% is not) must both hold | Pinned together in threats_sim #1: still 36/36, perpendicular grazing ≥ 5/6 (lunge) and ≥ 4/6 (charge), perpendicular crossing at 80% fed ≤ 1/6 |
| 4 | SpeciesCatalog rule 1 used `Genome.create` + `Genome.validate` | `Genome.new()`, fixed ids, part checks against the catalog (rule 1) |
| 5 | Leash overshoot (a tell always completes) | A tell may not start if its lane end leaves the leash. A hard `clamp_to_disc` runs after every move, and flee slides along it. Invariant: leash + 1e-3 |
| 6 | False speed claim; no escape analysis for starving bodies | Text corrected. Rule 3: pursue speed ≤ 0.9 × the slowest fed body (2.448): ambush 2.34, rammer 1.84. S6 covers fed (never loses ground) and starving bodies (never hit; the threat gives up by give-up + one cycle) |
| 7 | Initial carrion inside the territories | Moved to (±10.5, −4.5). Verified: only the 4 interim tests fail. Noted in the M1.md acceptance row |
| 8 | No off-screen indicators | `ThreatIndicators`: a pure `edge_point()` plus HUD arrows. **Never cut** |
| 9 | No engagement limit | Token with `max_engaged_on_player` 1, assigned on the sim side through the percept flag `engageable` |
| 10 | Keep D8 (death save) as an owner decision; no "no saving while hunted" | OD1, with a recommendation; the fallback stays compilable and tested; "no saving while hunted" rejected |
| 11 | Death tips must match the tested dodge | Tips say "out of its line on the side you face" (first "sideways, out of its line"; reworded by the review fixes, F2). The puff tip adds "or leave its patch" (the cancel is tested) |
| 12 | Smoke second death reused lair_se (killer ignore) | The second quick death uses lair_sw |
| 13 | The static `"player"` scan cannot use `_code_only` | A new `_code_keep_strings` helper scans raw code with strings kept. Identifier scans cover `PoolSim`, `sim.`, `CreatureField` and `roster` |
| 14 | The symmetry test needs a harness | A scripted brainless decoy `"lineage"` creature with the player's phenotype and the same hit and knockback path. T5 invariance is the primary proof |
| 15 | Hunter gate: seeds, miss budget, knobs, owner trigger | Seeds 201–206 fixed now; pass in ≥ 5 of 6. Five data knobs in order with bounds. OD2 trigger text written (sections 10 and 24) |
| 16 | `dirty` while dead compared the corpse | `_is_dirty()` and `_mark_saved()` use `position_for_save()`. A dead cell is dirty only while its death is unsaved |
| 17 | Integer timers; exact-timing test | All durations are ticks at load; threats_sim #6 |
| 18 | Burst bypasses phenotype speed; knockback can exceed 6 m/s | Rule 3: `burst_speed ≤ PoolLayout.MAX_SPEED`. After any knockback, speed is clamped to 6.0 (T10) |
| 19 | Body snapshot built once per tick before any creature moves; id tie-breaks | Section 12, tick order step 1; determinism rules |
| 20 | Hash coverage of brain memory, RNGs, queue | threats_sim #25 (hash coverage): `seen`, `ignore`, `landed_on`, `lock_heading`, phase ticks, field and brain RNG states, the queue, token holders, grace and streak |
| 21 | Fairness tests used only the grazer | threats_sim #1–5 and #23 run all 3 bodies, fed and starving |
| 22 | Readability floor below the probe value | `min_tell_s` 1.2, `min_notice_s` 0.5 |
| 23 | Flee not bounded by the leash | The hard clamp. Fuzz invariant 2 covers flee |
| 24 | The lair geometry must keep the checkpoint safe; check leash discs, not centers | Rule 8 checks disc + body radius ≥ 12 m. New rules 9 (leash band) and 10 (pinch) moved lair_se, lair_sw and lair_gap (section 0) |
| 25 | Keep verified facts; add `sort_custom` instability | Section 0 |

---

## 2. Rules this plan keeps

1. **`game/domain` stays pure:** no Node, scene, files, clock, `Input` or global RNG.
   - New domain files: `CreatureSenses`, `CreatureBrain`, `RespawnRules`, `ViewFootprint`.
   - `test_sim_purity` scans them automatically. `SIM_FILES` gains `creature_field.gd` and `species_catalog.gd` (its file read is allowed like `part_catalog.gd`).
2. **Only `PoolSim.step()` advances time.**
   - All RNGs are seeded from the world seed.
   - Every creature, grace and tell timer is an integer tick count, converted once at load with `roundi(s × 60)`.
3. **The brain sees only percepts.** `CreatureBrain` never receives `PoolSim`, the player's `MotionState` or any id-keyed world table. Proofs: T5 invariance, the decoy symmetry test and a static scan (section 18).
4. **Combat goes only through `InteractionResolver.bite` and `ram`.** There is no second damage path and no resolver change.
5. **Every pursuit has disengagement and every navigation task has a timeout and recovery** (Bible). Each give-up reason has its own test.
6. **Save safety.** No schema change: v2 and its 15-key guard stay. The death save uses the existing temp, verify and backup path. Nothing is rewritten on load (`save_v2_step2.json` proves it).
7. **`game/dev` stays debug-only.** That covers EvadeBot, HuntBot, KiterBot, the panel additions, the gizmos and F9/F10. Nothing there has a `class_name`, and the release preset excludes it.
8. **Placeholders** only with an inventory entry. **No new dependencies, network calls or runtime AI.** Nothing is copied from Spore, EA or Thrive, and no GPL code is used. Species carry role names ("ambush hunter", "territorial rammer").
9. **Each step is one PR** with a Windows build from CI. **Agents push after every commit.**

## 3. Layering

| Layer | Owns in step 3 | Must not |
|---|---|---|
| `game/domain` (pure) | **New:** CreatureSenses, CreatureBrain (states, phases, timers, give-up, drive, `strike_lane`), RespawnRules (streaks, grace, relocation list, cause strings), ViewFootprint. **Changed:** `Phenotype.derive(..., body_size)`; `Locomotion.burst`/`glide`; `PoolArena` (`settle`, `segment_clear`, `route_point`, `separate`, `rock_contact`, `clamp_to_disc`). **Unchanged:** InteractionResolver, ActorState, EcologyRegion, Lineage, SaveGame, Genome | Node, Input, OS, Time, files, global RNG; any reference to `PoolSim` |
| `game/systems` | **New:** SpeciesCatalog (load and validate `creatures_m1.json`), CreatureField (creature records, sites, spawn queue, token, encounter RNG). **Changed:** PoolSim (bodies, tick order, combat, deaths, carcasses, grace, snapshot); GameSession (`resolve_death`, checkpoint-aware save and dirty) | Read input, build nodes, animate |
| `game/scenes`, `game/ui` | CreatureView (pose from the sim phase, lane), CreatureLayer, player hurt and shelter visuals, spike part, "!" marker, threat audio, HUD shelter chip, hurt vignette, off-screen indicators, death notice reason and tip | Decide hits, timings, targets or spawns |
| `game/dev` (debug builds only) | Panel AI section, AI gizmos, F9/F10 and buttons, EvadeBot, HuntBot, KiterBot, ForageBot `avoid_threats` | Anything the release build needs |

## 4. Files

### New

| File | Role |
|---|---|
| `game/domain/creature_senses.gd` | `class_name CreatureSenses`. Pure perception (section 7) |
| `game/domain/creature_brain.gd` | `class_name CreatureBrain`. `Memory`, `think`, `drive`, hooks, `strike_lane` (section 8) |
| `game/domain/respawn_rules.gd` | `class_name RespawnRules`. Fairness math (section 13) |
| `game/domain/view_footprint.gd` | `class_name ViewFootprint`. The camera's plane trapezoid and `contains()` (section 11) |
| `game/systems/species_catalog.gd` | `class_name SpeciesCatalog`. Loads and validates species, sites and fairness data |
| `game/systems/creature_field.gd` | `class_name CreatureField`. Creatures, spawning, respawn queue, token |
| `game/data/creatures_m1.json` | Species, niches, sites, AI, combat and fairness numbers (section 5) |
| `game/scenes/pool/creature_view.gd` + `.tscn` | One creature: Pivot → Model (scale = body_size) → Body GLB and Parts, plus a Lane quad. `static func pose()` |
| `game/scenes/pool/creature_layer.gd` | Builds and frees views from sim events; interpolates them |
| `game/ui/threat_indicators.gd` | Off-screen edge arrows. `static func edge_point()` |
| `game/dev/evade_bot.gd`, `hunt_bot.gd`, `kiter_bot.gd` | Event-driven dodger, hunter driver, fuzz driver (no `class_name`) |
| `tools/blender/make_m1_threats.py` | Blockouts `creature_ambush_body`, `creature_rammer_body`, `part_spike` |
| `assets/source/blender/{creature_ambush_body,creature_rammer_body,part_spike}.blend`, `assets/export/*.glb`, `assets/records/*.json` | Generated by the script |
| `tests/test_creature_senses.gd`, `test_creature_brain.gd`, `test_respawn_rules.gd`, `test_species_catalog.gd`, `test_creature_field.gd`, `test_view_footprint.gd`, `test_threats_sim.gd`, `test_threat_fuzz.gd`, `test_checkpoints.gd`, `test_threat_indicators.gd` | Section 18 |
| `tests/fixtures/pool_test_threats.json` | Open arena (soft wall 36), zone `z_a` at (0, 0) r 6, spawn (0, 25), a wall of 5 rocks (r 1.0) at y = 8, x = −4…4, 2 m apart, overlapping so there is no gap |
| `tests/fixtures/creatures_test.json` | The real species with `"sites": []`, so tests place creatures exactly |
| `tests/fixtures/save_v2_step2.json` | A slot written by the step 2 build (generation 1, mid-run position, points and history) |

### Changed

| File | Change |
|---|---|
| `game/domain/phenotype.gd` | `derive(genome, catalog, body_size := 1.0)`. Size 1 gives identical results |
| `game/domain/locomotion.gd` | `static func burst(m, heading, speed)` and `static func glide(m, drag, dt)`. `steer` is unchanged |
| `game/domain/pool_arena.gd` | `settle` (extracted from `move`), `segment_clear`, `route_point` (moved from ForageBot), `separate`, `rock_contact`, `clamp_to_disc` |
| `game/systems/pool_sim.gd` | Optional `species` argument (null = exactly step 2). Section 12 |
| `game/systems/game_session.gd` | Loads species; `resolve_death()`; idempotent `respawn_after_death()`; `SAVE_ON_DEATH`; checkpoint-aware save and dirty |
| `game/data/pool_m1.json` | `carrion.interim_supply.enabled: false`; `carrion.initial` → `[[1.5, 4.0], [−10.5, −4.5], [10.5, −4.5]]`. Nothing else; still schema 1 |
| `game/scenes/pool/pool.gd` | Owns CreatureLayer; routes the new events; `died` carries the reason |
| `game/scenes/pool/player_cell_view.gd` | `PART_SCENES["spike"]`, hurt flinch, shelter shimmer |
| `game/scenes/audio/placeholder_audio.gd` | 9 synthesized cues; tell cue lengths read from species data |
| `game/scenes/main.gd` | `_on_died` calls `session.resolve_death()`; `death_title(cause, reason := "")`; `death_text(cause, lost, tip := "", saved := true)`; quit text after a failed death save |
| `game/ui/hud.gd`, `hud.tscn` | Shelter chip, hurt vignette, health bar whenever hurt, ThreatIndicators layer, "Dodged!" label |
| `game/ui/hud_icon.gd` | Shapes `jaw` (ambush) and `star` (rammer) for the edge arrows; `ring` for the shelter chip |
| `game/ui/refusal_hints.gd` | Attack refusal hints |
| `game/dev/debug_panel.gd`, `dev_gizmos.gd`, `dev_keys.gd`, `forage_bot.gd` | Section 16 |
| `project.godot` | Actions `dev_spawn_threat` (F9) and `dev_kill_nearest` (F10) |
| `tools/blender/blockout_common.py` | `export(..., review_state=REVIEW_STATE, generator=GENERATOR)`; defaults unchanged |
| `tools/check.sh` | Smoke phases `die_and_quit` and `after_death` |
| `assets/records/placeholders/inventory.json` | 9 audio entries; functional entries for the "!" marker, lane, vignette, edge arrows and "Dodged!" |
| `tests/run_tests.gd` | `-- --skip-slow` skips `test_slow_*` methods; `-- --only=a,b` filters files. CI runs everything |
| Existing tests | Section 18, "Changed tests" |
| `docs/milestones/M1.md`, `docs/DECISIONS.md`, `README.md` | Step 3 section; D1–D22; the acceptance-row note on the carrion change |

### Untouched

- `interaction_resolver.gd`, `actor_state.gd`, `ecology_region.gd`, `lineage.gd`, `save_game.gd`, `genome.gd`, `stable_id.gd`.
- Persistence and migrations; `boot.*`.
- The camera, swim input and plankton field.
- The CI workflow and export presets.
- `wt/plan3`.

---

## 5. Data: `game/data/creatures_m1.json`

This file is separate from `pool_m1.json`, so `PoolLayout` and its schema do not change (D15). Seconds become ticks at load, and the brain only sees ticks.

```json
{
  "schema_version": 1,
  "status": "PROPOSED",
  "note": "M1 step 3 threats. Every number is PROPOSED tuning; reasons are in docs/milestones/M1.md step 3.",
  "ai": {
    "think_hz": 10, "engaged_think_hz": 20, "dead_reckon_cap_s": 0.5,
    "unreachable_window_s": 2.0, "unreachable_min_m": 0.5, "return_fail_limit": 3,
    "settle_s": 3.0, "tell_start_max_speed": 0.3
  },
  "combat": { "player_bite_knockback": 0.8, "player_ram_knockback": 1.5, "max_speed_after_hit": 6.0 },
  "fairness": {
    "min_tell_s": 1.2, "min_notice_s": 0.5, "min_recover_s": 0.5,
    "max_pursue_share_of_slowest_fed": 0.9, "max_single_hit_share": 0.5,
    "max_engaged_on_player": 1,
    "spawn_safe_m": 20.0, "spawn_view_aspect": 2.4, "spawn_view_margin_m": 1.0,
    "respawn_clear_m": 12.0, "leash_band_margin_m": 0.1, "pinch_margin_m": 0.5,
    "grace_s": [5.0, 8.0, 10.0], "respawn_energy_share": [0.6, 0.8, 1.0],
    "streak_window_s": 90.0, "killer_ignore_s": 30.0, "start_grace_s": 5.0
  },
  "spawning": { "retry_s": 1.0, "min_gap_m": 2.0, "fade_in_s": 1.0 },
  "species": {
    "ambush_hunter": {
      "name": "ambush hunter",
      "death_reason": "Caught by an ambush hunter",
      "death_tip": "Ambush hunters wait at the rims. When one coils, swim out of its line on the side you face; turning round takes too long.",
      "behavior": "ambush", "body_asset": "creature_ambush_body", "body_size": 1.5,
      "parts": [{"type": "mouth_jaw", "angle": 0.0}, {"type": "flagellum", "angle": 2.8}, {"type": "flagellum", "angle": -2.8}],
      "niche": {"role": "ambush", "cap": 3, "respawn_s": 60.0, "respawn_jitter_s": 10.0},
      "metabolism_share": 0.1, "start_energy_share": 0.9, "hungry_below": 0.6, "full_above": 0.85,
      "senses": {"fov_deg": 200.0, "near_m": 1.0, "memory_s": 2.0},
      "speeds": {"wander": 0.5, "forage": 0.6, "pursue": 0.85, "flee": 1.0},
      "prey_max_radius_share": 1.6,
      "notice_s": 0.5, "give_up_s": 5.0, "leash_m": 9.0,
      "forage_radius_m": 18.0, "forage_timeout_s": 30.0, "forage_retry_s": 20.0,
      "refractory_s": 6.0, "nav_timeout_s": 20.0,
      "attack": {"kind": "bite", "tell": "lunge", "start_min_m": 2.5, "start_max_m": 3.0, "standoff_m": 2.75, "aim_deg": 20.0,
                 "lead_s": 1.2, "lead_cap_m": 1.0, "tell_s": 1.2,
                 "burst_speed": 4.5, "burst_s": 0.35, "glide_s": 0.25, "glide_drag": 6.0,
                 "recover_s": 1.0, "blocked_recover_s": 1.0, "knockback": 1.5},
      "flee": {"below_health_share": 0.35, "for_s": 4.0},
      "carcass": {"chunks": 4, "energy": 24.0, "on_starve": false}
    },
    "rammer": {
      "name": "territorial rammer",
      "death_reason": "Rammed by a territorial rammer",
      "death_tip": "Rammers guard the richest patches. When one puffs up, swim out of its line on the side you face, or leave its patch.",
      "behavior": "territorial", "body_asset": "creature_rammer_body", "body_size": 1.25,
      "parts": [{"type": "mouth_filter", "angle": 0.0},
                {"type": "spike", "angle": 0.3, "scale": 0.8}, {"type": "spike", "angle": -0.3, "scale": 0.8},
                {"type": "spike", "angle": 1.9, "scale": 0.8}, {"type": "spike", "angle": -1.9, "scale": 0.8},
                {"type": "flagellum", "angle": 3.14159}],
      "niche": {"role": "territorial", "cap": 4, "respawn_s": 30.0, "respawn_jitter_s": 6.0},
      "metabolism_share": 0.25, "start_energy_share": 0.6, "hungry_below": 0.7, "full_above": 0.9,
      "senses": {"fov_deg": 270.0, "near_m": 0.8, "memory_s": 3.0},
      "speeds": {"wander": 0.45, "forage": 0.5, "pursue": 1.0, "flee": 1.0},
      "intruder_min_radius": 0.3,
      "notice_s": 0.5, "give_up_s": 8.0, "territory_margin_m": 2.0, "territory_exit_m": 1.0, "leash_m": 3.0,
      "rest_s": [4.0, 8.0], "refractory_s": 3.0, "nav_timeout_s": 8.0,
      "attack": {"kind": "ram", "tell": "puff", "start_min_m": 3.0, "start_max_m": 5.0, "standoff_m": 4.0, "aim_deg": 15.0,
                 "lead_s": 1.6, "lead_cap_m": 1.2, "tell_s": 1.2,
                 "burst_speed": 4.0, "burst_s": 0.9, "glide_s": 0.3, "glide_drag": 5.0,
                 "recover_s": 1.2, "blocked_recover_s": 2.0, "knockback": 2.5},
      "flee": {"below_health_share": 0.4, "for_s": 5.0},
      "carcass": {"chunks": 3, "energy": 24.0, "on_starve": false}
    }
  },
  "sites": [
    {"id": "lair_se",  "species": "ambush_hunter", "home": [26.4, 12.6],  "heading": -2.9258},
    {"id": "lair_sw",  "species": "ambush_hunter", "home": [-24.1, 16.6], "heading": -0.8419},
    {"id": "lair_gap", "species": "ambush_hunter", "home": [-9.4, -16.3], "heading": 1.0472},
    {"id": "terr_n_a", "species": "rammer", "home": [-2.5, -22.0], "heading": 1.5708, "territory_zone": "z_n"},
    {"id": "terr_n_b", "species": "rammer", "home": [2.5, -22.0],  "heading": 1.5708, "territory_zone": "z_n"},
    {"id": "terr_nw",  "species": "rammer", "home": [-19.1, -11.0], "heading": 0.5226, "territory_zone": "z_nw"},
    {"id": "terr_ne",  "species": "rammer", "home": [19.1, -11.0],  "heading": 2.6190, "territory_zone": "z_ne"}
  ]
}
```

### Why these numbers

**Ambush hunter**
- **Size 1.5.** It is visibly the biggest thing in the pool and can still be bitten back (0.75 < 0.8).
- **Pursuit 0.85 × 2.749 = 2.34 m/s.** This is below the 2.448 m/s escape bound, so every fed starting body outswims it (F3).
- **Lunge.**
  - Tell 1.2 s; start window 2.5–3.0 m (center to center); aim ≤ 20°.
  - Lead 1.2 s, capped at 1.0 m.
  - Burst 4.5 m/s for 0.35 s, then glide 0.25 s (drag 6): 2.16 m of travel.
  - These are the probed values (section 0). A shorter tell or a closer start failed the probe.
- **Notice 0.5 s, then watch.** A sated hunter only watches you and strikes when you come within 3 m in front of it. A hungry one (below 60%) pursues within its 9 m leash.
- **Metabolism 10%.** Hunger takes about 174 s (0.9 → 0.6 at 0.17/s), so the rim hunters are rarely hungry and mostly watch. Starving to death takes over 13 minutes.
- **Give-up 5 s** without landing a hit. It ends the chase about one attack cycle (2.8 s) after the timer, at most.

**Rammer**
- **Size 1.25, spike scale 0.8.** It is bigger than the player (0.625 against 0.5), so it reads by size as well as spikes. The front stack stays at 14.4, which keeps the two-hit rule.
- **Puff 1.2 s.** Charge window 3.0–5.0 m, aim ≤ 15°, stand-off 4 m. Burst 4.0 m/s for 0.9 s, then glide 0.3 s (drag 5): 4.22 m. These are probed.
- **Pursuit 1.84 m/s.**
- **Territory** = zone radius + 2 m, so grazing at the zone edge already counts as intruding. Exit hysteresis 1 m (the puff cancels beyond 9 m).
- **Leash 3 m.**
- **Rest 4–8 s** varies the patrol.

**Both**
- **The two-hit rule** (12 and 14.4, against 15) is validated at load (rule 5).
- **Carcasses of 24-energy chunks** (the step 2 unit, 3 points each): 4 for an ambush hunter, 3 for a rammer. A rammer kill feeds a hunter player for about 63 s (72 / 1.15).
- **Respawns:** rammers 30 ± 6 s, because they are the hunter's prey; ambush hunters 60 ± 10 s.

### `SpeciesCatalog.validate(layout, part_catalog) -> PackedStringArray`

Each violation is reported as a named error, and each rule has a mutated-data test case.

1. **Genomes.**
   - Each species genome is built with `Genome.new()`. It gets `genome_id = "species:<id>"`, `lineage_id = "species"` and part ids `p1…pN` (deterministic and never checked by `StableId`), then `add_part`.
   - Its parts are checked against `PartCatalog`: known type, count ≤ `max_count`, total ≤ `max_parts`, scale within [`min_scale`, `max_scale`], a finite angle in [−π, π], and a required mouth.
   - `body_size` is within [1.0, 2.0]. `Genome.validate` is **not** called.
2. **Weapon.** `ambush` needs a jaw and `attack.kind == "bite"`; `territorial` needs a spike and `"ram"`.
3. **Speed.**
   - `burst_speed ≤ PoolLayout.MAX_SPEED` (the tunnelling bound).
   - Non-strike speed shares are ≤ 1.0.
   - **Escape rule:** `speeds.pursue × phenotype.speed ≤ max_pursue_share_of_slowest_fed × min(fed speed of every starting body)`, computed from the catalog at load.
4. **Readability.** `tell_s ≥ min_tell_s` (1.2), `notice_s ≥ min_notice_s` (0.5), `recover_s ≥ min_recover_s` (0.5). Every duration is ≥ 1 tick.
5. **Forgiving.** The worst single hit on a defense-0 target is `< max_single_hit_share ×` the smallest starting `max_health`. A bite counts `bite_damage`; a ram counts the front-spike stack × 1.5.
6. **Strike window.** `start_min_m ≤ standoff_m ≤ start_max_m`. The strike lane length (`strike_lane`, section 8) is ≤ the leash (ambush) or ≤ territory radius + leash (rammer).
7. **Sites.**
   - The species exists, and its cap is ≤ its number of sites.
   - The home is inside `soft_start − radius − 1` and `arena.is_clear(home, radius)`.
   - Sites are ≥ `min_gap_m` apart.
   - `territory_zone` exists.
8. **Checkpoint safety** (against `layout.spawn`, the step 3 checkpoint).
   - Every reachable disc plus body radius stays ≥ `respawn_clear_m`. The disc is (home, leash) for an ambush site and (territory center, territory radius + leash) for a rammer.
   - Every home is ≥ `spawn_safe_m` away.
9. **Leash band.** No rock surface lies within `radius + leash_band_margin_m` of a leash circle, so the hard clamp never pushes a body into a rock.
10. **Pinch.** Every rock that reaches into a disc (plus body radius) leaves ≥ `2 × radius + pinch_margin_m` to the soft wall and to every other rock.
11. **New-game fill.** Every home lies outside `ViewFootprint` of the checkpoint at `zoom_max`, at `spawn_view_aspect`, with margin `look_ahead_max + spawn_view_margin_m + radius`.
12. **Fairness arrays** have equal length ≥ 1 and do not decrease.
13. **No unknown keys** in species or attack blocks. A `homing_deg_s` or `tell_turn_share` cannot come back silently.

**`pool_m1.json`:**
- `carrion.interim_supply.enabled` is `false` (D1). The block stays, so the OD2 fallback is a data change.
- `carrion.initial` moves out of the territories (D19). This changes the step 2 data that its acceptance row describes ("three world-start carcasses"), so M1.md notes it.

---

## 6. The creature model

### Size rule: `Phenotype.derive(genome, catalog, body_size := 1.0)` (D3)

```gdscript
const MIN_BODY_SIZE := 0.5
const MAX_BODY_SIZE := 2.0
# s = clampf(body_size, MIN_BODY_SIZE, MAX_BODY_SIZE)
# Every part: benefit share × s; costs (upkeep, mass) × s; spike damage × part scale × s.
# Base mass, base upkeep and base max_health × s; radius = base radius × s.
# Base speed, acceleration, turn, sight and energy capacity are NOT scaled.
# speed = (base speed + Σ speed) / mass_s, and the same for acceleration, so bigger means slower.
```

- The brief says the ambush hunter is "built from the same parts at a larger size". One rule gives tougher, harder-hitting, hungrier and slower bodies, and step 4 can expose it.
- At s = 1 the result is identical (*verified* for 11 genomes). The test compares `to_dict()` plus `radius`, `mouths` and `spikes`.
- The player is always size 1 in M1.

### Condition and metabolism (D4)

- Creatures use `ActorState` unchanged: `fresh(phenotype)`, then `energy = capacity × start_energy_share`.
- Metabolism is `state.tick(phenotype, DT × metabolism_share, moved × metabolism_share)`. This scales upkeep, movement cost, starvation damage and regeneration together.
- A creature that starves to death leaves no carcass, because carrion comes from kills.

### Movement

| Situation | Motion |
|---|---|
| Not striking | `Locomotion.steer(m, drive.move, p, drive.speed_mul × state.speed_multiplier(), DT)`, unchanged (turn-first) |
| Tell | `steer` with zero move (it brakes), then `heading = rotate_toward(heading, lock_heading, turn_rate × DT)` |
| Strike, burst ticks | `Locomotion.burst(m, lock_heading, burst_speed)`: heading = lock, velocity = from_angle(lock) × burst_speed |
| Strike, glide ticks | `Locomotion.glide(m, glide_drag, DT)`: velocity × exp(−drag × DT), heading unchanged |

- Neither burst nor glide goes through `steer`, so `burst_speed` is bounded by rule 3, not by phenotype speed.
- **`PoolArena` additions** (all pure; the existing 10,000-step fuzz guards `move`):
  - `settle(m, body_r)`: rock push-out (2 passes) and the hard-limit clamp, extracted from `move`, which now calls it.
  - `segment_clear(a, b, shrink := 0.9) -> bool`: false when the segment passes within `rock.radius × shrink` of a rock center. Grazing a rock's edge still counts as visible.
  - `route_point(from, to, body_r, clearance := 0.1, margin := 0.6) -> Vector2`: ForageBot's `_route` detour, moved here and used by ForageBot, the bots and brains.
  - `static separate(a, ra, ma, b, rb, mb) -> bool`: overlapping bodies are pushed apart along the line between centers, split by inverse mass. It changes **positions only**, so ram closing speed comes from real swim velocities (D13).
  - `rock_contact(p, r, slack := 0.05) -> String`: the id of a rock within `r + slack`, or "".
  - `static clamp_to_disc(m, center, radius) -> bool`: outside the disc, the body is projected onto the circle and only the outward velocity is removed, like the pool's hard limit. So flee and every other state slide along the leash (D20).
- **Knockback** (in PoolSim): on a hit, `target.velocity += dir × knockback`, then speed is clamped to `max_speed_after_hit` (6.0, the tunnelling bound) for both bodies (D14).

### Creature record (`CreatureField.Creature`, inner class)

`id` ("c_N"), `number`, `species_id`, `site_id`, `debug` (bool), `phenotype`, `state` (ActorState), `motion` (MotionState), `actor` (`InteractionResolver.Actor`; its cooldowns persist), `brain` (`CreatureBrain.Memory`), `drive` (the last drive dictionary), `last_hit_by` (id), `strike_hit` (bool, reset at each strike start), `born_tick`.

## 7. Senses: `game/domain/creature_senses.gd`

```gdscript
class_name CreatureSenses extends RefCounted
## viewer: {id, species, position, heading, radius, sight, fov, near}
## bodies: [{id, species, position, velocity, radius, alive, concealed, engageable, bite, spikes}]
##   built ONCE per tick, before any creature moves (start-of-tick snapshot)
static func perceive(viewer: Dictionary, bodies: Array, arena: PoolArena) -> Array[Dictionary]
static func perceive_food(viewer: Dictionary, items: Array, kinds: PackedStringArray) -> Array[Dictionary]
static func bearing(viewer: Dictionary, p: Vector2) -> float     # -PI..PI relative to its heading
```

**`perceive`**, in this order:
1. Skip the viewer itself, dead bodies and concealed bodies. Concealed means the player during shelter, or the dev "hide from AI" switch.
2. **Near:** `d ≤ viewer.radius + body.radius + near`. The body is perceived `by: "near"` regardless of FOV and line of sight. This is touch, a lateral-line sense.
3. **Sight:** `by: "sight"` when all of these hold:
   - `d ≤ sight + body.radius`;
   - `|bearing| ≤ fov / 2` (inclusive);
   - `arena.segment_clear(viewer.position, body.position)`.
4. Sort by (distance, id). `sort_custom` is unstable, so the id breaks ties.

**Percept:** `{id, species, position, velocity, radius, distance, bearing, by, engageable, bite: bool, spikes: int}`. The values are copies.

- **`engageable`** is set by CreatureField per viewer (the token, section 8). It is true for every non-player body.
- **Pain** is a third sense, `on_hurt` (section 8). The attacker is in contact, so its position is known.
- **`perceive_food`** uses range and FOV only, with no line of sight, because food does not flee and rocks are handled by `route_point`. It runs only while the creature is foraging.
- **The player's body** is passed as species `"lineage"` and id `"player"`. The brain treats it like any other species, which T5 and the decoy test prove.

## 8. The brain: `game/domain/creature_brain.gd`

### API

```gdscript
class_name CreatureBrain extends RefCounted
class Memory:
    var behavior: String              # "ambush" | "territorial"
    var cfg: Dictionary               # species block, durations already in ticks
    var state := "rest"               # rest | wander | forage | notice | chase | attack | flee
    var phase := ""                   # rest: lurk|watch; wander: patrol|return; forage: seek|eat;
                                      # chase: pursue|aim; attack: tell|strike|glide|recover
    var state_tick := 0; var phase_tick := 0
    var target := ""                  # id
    var seen := {}                    # id -> {position, velocity, tick, by, species, radius, engageable}; bounded by memory
    var engaged_tick := -1            # when notice began; reset by a landed hit
    var landed_on := {}               # id -> tick of our last hit on it
    var lock_heading := NAN; var lane := {}   # set at tell entry, cleared at recover
    var goal := Vector2.INF; var food_id := ""
    var progress := {}                # {position, tick} for the unreachable and nav checks
    var ignore := {}                  # id -> until_tick (refractory, killer ignore)
    var ignore_all_until := 0         # settle after spawn
    var attacker := ""; var rest_until := 0; var forage_after := 0
    var outcome := ""                 # hit | missed | blocked | interrupted | cancelled
    var return_fails := 0; var stuck := false
    var home: Vector2; var home_heading: float
    var territory_center := Vector2.INF; var territory_r := 0.0
    var wake := false                 # think on the next tick regardless of schedule
    var rng := RandomNumberGenerator.new()
    var events: Array[Dictionary] = []
    func to_dict() -> Dictionary      # vectors as [x, y]; seen and ignore sorted by id; rng state included
static func create(behavior, cfg, home, home_heading, territory: Dictionary, seed: int, tick: int) -> Memory
## self_view: {id, species, position, heading, velocity, speed_now, radius, speed, health_share, energy_share}
static func think(mem: Memory, self_view: Dictionary, percepts: Array, food: Array, tick: int, arena: PoolArena) -> void
## Every tick. Advances timed phases exactly. Returns {mode: "steer"|"tell"|"burst"|"glide", move: Vector2 (|move| ≤ 1),
## speed_mul, strike: bool, target: String, feed: String}
static func drive(mem: Memory, self_view: Dictionary, tick: int, arena: PoolArena) -> Dictionary
static func on_hurt(mem: Memory, attacker: Dictionary, tick: int) -> void
static func on_strike_landed(mem: Memory, tick: int) -> void
static func on_blocked(mem: Memory, tick: int) -> void
static func force_return(mem: Memory, forget_id: String, ignore_until: int) -> void
static func is_engaged_with(mem: Memory, id: String) -> bool    # state chase or attack, target == id
## The danger lane: origin, heading, length = travel + radius + reach + prey_radius, half_width = radius + reach + prey_radius.
## Used by the brain's leash check, the view's floor lane, the gizmos and the tests.
static func strike_lane(attack: Dictionary, own_radius: float, prey_radius: float, origin: Vector2, heading: float) -> Dictionary
```

### Split of work (D11)

- **`think`** makes every perception-based decision: target choice, give-up, food, flee, tell start.
  - It runs at 10 Hz (`(tick + number) % 6 == 0`), at 20 Hz while engaged (`% 3`), and on the next tick after `wake`.
  - Creature numbers stagger it.
- **`drive`** runs every tick. It advances timed phases at their exact tick and steers from **memory only**: the last percept, dead-reckoned by `min(age, 0.5 s)`.
- So a tell always lasts exactly 72 ticks, and between thinks a creature acts on what it last perceived.

### Timings in ticks (60 Hz)

| | Notice | Tell | Burst | Glide | Recover | Blocked recover | Give up | Memory | Refractory | Flee | Nav timeout | Settle |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ambush | 30 | 72 | 21 | 15 | 60 | 60 | 300 | 120 | 360 | 240 | 1200 | 180 |
| Rammer | 30 | 72 | 54 | 18 | 72 | 120 | 480 | 180 | 180 | 300 | 480 | 180 |

### Starting a tell (both behaviors; checked in `think`)

A creature in `chase/aim` starts a tell only when all of these hold:
- the target's dead-reckoned distance is in [`start_min_m`, `start_max_m`] and its bearing is ≤ `aim_deg`;
- its own speed is ≤ `tell_start_max_speed` (0.3 m/s), so the tell starts from rest, as in the probe;
- the target percept is `engageable`;
- the lane end (`position + from_angle(lock) × travel`) lies inside its leash disc. This is the leash overshoot fix.

**At entry:**
- `lock_heading` = the angle to `target + clamp(velocity × lead_s, lead_cap_m)`;
- `lane = strike_lane(...)`;
- emit `creature_tell {target, kind, ticks, lane}`.

The heading never tracks the target after this (D6). There is no homing.

### Ambush hunter (`behavior: "ambush"`)

| State / phase | Movement | Leaves when |
|---|---|---|
| `rest/lurk` | At home, turned to `home_heading`; no thrust | **Prey** perceived → `notice`. Hungry (energy < 0.6) and `tick ≥ forage_after` → `forage`. Hurt → `flee` if health < 35%, else `notice` the attacker (`wake`) |
| `notice` (30) | Turns to the target at full rate; no thrust; emits `creature_noticed` | At the end: hungry, `landed_on[target]` or hurt by it, and engageable → `chase/pursue`; otherwise → `rest/watch` |
| `rest/watch` | At home; keeps turning to face the remembered target; no thrust | In window, aimed and engageable → `chase/aim`. Hungry → `chase/pursue`. Target lost (memory) → `rest/lurk`. Not a chase and not engaged |
| `chase/pursue` | `route_point` toward the **stand-off point** `target + unit(self − target) × standoff_m` at pursue 0.85 | In window and aimed → `chase/aim`. Give-up rules |
| `chase/aim` | Brakes (zero move) and turns to the target at full rate | The tell-start conditions hold → `attack/tell`. Window lost → `chase/pursue` (hungry) or `wander/return` (sated) |
| `attack/tell` (72) | Brakes; turns to `lock_heading` | At +72 exactly → `attack/strike`. Cut short only by death or hurt below the flee share (`creature_recovered {interrupted}`) |
| `attack/strike` (21) | `burst` along the lock; `strike = true` | Hit → `recover` (hit). A rock ahead (`rock_contact`, bearing ≤ 60°) → `recover` (blocked). +21 → `attack/glide` |
| `attack/glide` (15) | `glide`; `strike = true` | Hit → `recover` (hit). +15 → `recover` (missed) |
| `attack/recover` (60) | Coasts; no turn | Target perceived, engageable, not given up, and (hungry or hurt by it) → `chase/pursue`; its next attack needs a **new tell**. Otherwise → `wander/return` |
| `forage/seek` | Nearest perceived carrion within `forage_radius` 18 m of home; without one, patrols points 6 m around home (brain RNG) at 0.6 | Touching → `forage/eat`. Energy ≥ 0.85 → `wander/return`. 30 s with no food → `wander/return` and `forage_after = tick + 20 s`. Prey → `notice` |
| `forage/eat` | `drive.feed = food_id`; the sim runs `InteractionResolver.feed` | Eaten or gone → `forage/seek` |
| `wander/return` | `route_point` toward home at 0.5 | Within 0.3 m → `rest/lurk`. Nav timeout → recovery (below) |
| `flee` (240) | Away from the attacker's last position through `route_point` at 1.0; slides along the leash | Timer → `wander/return`. Hurt again → the flee restarts |

- **Prey:** a percept of another species with `radius ≤ own radius × 1.6` (it can bite it), not ignored, and not inside `ignore_all_until`. So it hunts the player and rammers, never another ambush hunter.

### Territorial rammer (`behavior: "territorial"`)

| State / phase | Movement | Leaves when |
|---|---|---|
| `rest` | Still, facing `home_heading` or the last patrol heading, for 4–8 s (brain RNG) | Timer → `wander/patrol`. Hungry → `forage`. **Intruder** → `notice`. Hurt → retaliate (`notice` the attacker, even outside the territory but within the leash) or `flee` |
| `wander/patrol` | To a random clear point inside `territory_r − 1` at 0.45 | Arrival → `rest`. Nav timeout → a new goal. Intruder → `notice` |
| `forage/seek`, `/eat` | Nearest perceived plankton inside the territory at 0.5 | Energy ≥ 0.9 → `rest`. Intruder → `notice` |
| `notice` (30) | Turns to face; no thrust | Intruder still inside and engageable → `chase/pursue`. Not engageable → stays in `notice` until give-up. Gone → `wander/patrol` |
| `chase/pursue` | To the stand-off point (4 m) at 1.0. Too close means it swims out first: a run-up | In window and aimed → `chase/aim`. Give-up rules |
| `chase/aim` | Brakes and turns | Tell-start conditions → `attack/tell` |
| `attack/tell` **puff** (72) | Brakes; turns to `lock_heading` | At +72 → `attack/strike`. **Target perceived beyond `territory_r + territory_exit_m` (9 m)** → `tell_cancelled {reason: "left_territory"}` → `recover` (cancelled; deflates over 24 ticks) → `wander/return` |
| `attack/strike` (54) | `burst` 4.0 m/s along the lock | Hit → `recover`. Rock ahead → `on_blocked` → `recover` 120 (dazed: a readable punish window). +54 → `attack/glide` |
| `attack/glide` (18) | `glide` drag 5 | Hit → `recover`. +18 → `recover` (missed) |
| `attack/recover` (72) | Coasts | Intruder still inside and engageable → `chase/pursue` (a new tell). Else → `wander/patrol` |
| `flee` (300) | Away from the attacker; slides along the leash | → `wander/return` |

- **Intruder:** a percept of another species with `radius ≥ 0.3`, inside `territory_r` (8 m) of the territory center, not ignored.
- The ambush hunter counts, so rammers attack it, and ambush hunters prey on rammers that wander near lair_gap. Both creatures' give-up rules bound this.

### The engagement token (F4, D21)

- **Engaged with a body** = the brain is in `chase` or `attack` with that body as its target. Notice and watch are not engaged.
- **CreatureField** keeps `engaged_on_player: PackedStringArray`. Before each creature's think, in number order, it sets the player percept's `engageable = engaged_on_player.size() < max_engaged_on_player or c.id in engaged_on_player`, and updates the list right after that think. This is deterministic.
- **A creature that cannot get the token** stays in `notice` (rammer) or `rest/watch` (ambush). Its give-up and memory timers still run, so it cannot wait forever.
- Other bodies (rammers, ambush hunters, the decoy) are always engageable. The token protects only the player, in the forgiving preset.

### Give-up rules (checked in `think` during `notice`, `chase` and `attack/recover`)

| Reason | Ambush | Rammer |
|---|---|---|
| `lost`: target not perceived for the memory length | 120 ticks | 180 ticks |
| `timer`: engaged without landing a hit (a landed hit resets `engaged_tick`) | 300 | 480 |
| `leash`: at the leash (≥ leash − 0.25 m) with the target farther out | 9 m | — |
| `left_territory`: target beyond `territory_r + leash` (11 m) from the center | — | yes |
| `unreachable`: moved < 0.5 m over the last 120 ticks while in `chase/pursue` | yes | yes |
| `target_gone`: dead, concealed or removed | yes | yes |

**On give-up:**
- emit `creature_gave_up {id, target, reason}`;
- set `ignore[target] = tick + refractory`;
- go to `wander/return` (ambush) or `wander/patrol` (rammer).

An attack in progress always completes, so a tell is always honest. The give-up is checked again at `recover`.

### Recovery (navigation)

- Every navigation goal (return, patrol, forage seek) has a progress check. If the creature moves less than 0.5 m in 120 ticks, it re-plans with `route_point` around the other side of the blocking rock (the brain RNG picks the first side).
- Patrol and forage pick a new goal when `nav_timeout` runs out.
- Return counts one fail per timeout. After 3, the brain sets `stuck`.
- CreatureField removes a stuck creature only when it is ≥ `spawn_safe_m` from the player and outside the view footprint, and requeues it at its site (`creature_removed {reason: "stuck"}`, D17). Otherwise it keeps trying and the panel shows `stuck`.
- The pinch and band rules (9 and 10) make this a backstop, not a routine.

### Brain events (CreatureField drains them and adds `id`)

- `creature_noticed {target, by}`
- `creature_tell {target, kind, ticks, lane}`
- `tell_cancelled {target, reason}`
- `creature_strike {target, kind}`
- `creature_recovered {target, outcome}`
- `creature_gave_up {target, reason}`
- `creature_fled {from}`
- `creature_state {from, to}` (debug only)

---

## 9. Combat: only through `InteractionResolver.bite` and `ram`

### Creature strikes (F5)

- **When:** only while the brain phase is `attack/strike` or `attack/glide` (`drive.strike == true`), only against `drive.target`, and at most once per strike (`strike_hit`).
- **How:** each such tick, in creature order, the sim calls `bite(c.actor, target_actor, now)` or `ram(c.actor, target_actor, closing, now)`.
  - `closing = (v_attacker − v_target) · unit(target − attacker)`, using velocities after motion and before separation.
  - A concealed or dead target is skipped.
- **If allowed:**
  1. `target.state.take_damage(effect.damage)`;
  2. knockback, then the speed clamp to 6.0;
  3. the `hit` event;
  4. `on_strike_landed` (to recover);
  5. if the target is a creature, its brain's `on_hurt`.
- **If refused:** the strike continues until its ticks run out. Creatures never cause damage outside a strike window.
- **`dodged {id, species}`:** emitted by the sim (not the brain) when a strike whose target is the player ends in `recover` with outcome `missed` or `blocked`.

### Player attacks (automatic on contact; OD3, D5)

- **When:** each tick while the player is alive.
- **Targets:** creatures whose center distance is ≤ player radius + their radius + 0.35, sorted by (distance, id).
- **How:** the player takes the first allowed `bite` and the first allowed `ram` among them, at most one of each per tick. Resolver cooldowns apply.
- **If allowed:** damage, knockback (0.8 bite, 1.5 ram), speed clamp, `hit`, then the creature brain's `on_hurt`.
- **Grace:** the player's first hit ends shelter (`grace_ended {reason: "attacked"}`).
- **No new input.** Space and right mouse stay unbound. Starting bodies have no spikes, so ramming is for step 4 genomes and test genomes now.

**Attack refusals** (player only):
- `attack_refused {target, kind, reason}` is emitted for the nearest creature in contact.
- It uses the feeding throttle: the (target, reason) pair changes, or 0.5 s pass.
- **Quiet reasons:** "out of reach", "jaw is recovering", "spikes are recovering", "not moving toward it", "needs a jaw", "needs a spike".
- **Hinted by `RefusalHints`:** "jaw is not facing it" → "Turn your jaw toward it"; "no spike points at it" → "Point a spike at it"; "too big to bite" → "Too big to bite".

### Damage table (defense is 0 for every M1 body)

| Attacker → target | Per hit | Hits to kill |
|---|---|---|
| Ambush bite → player (30) | 12 | 3 |
| Ambush bite → rammer (37.5) | 12 | 4 |
| Rammer ram → player (30) | 9.6 × impact 0.25–1.5 (a charge is ≈ 14.4) | ≥ 3 |
| Rammer ram → ambush (45) | ≤ 14.4 | ≥ 4 |
| Hunter or omnivore bite → rammer (37.5) | 8 | 5 |
| Hunter or omnivore bite → ambush (45) | 8 | 6 |
| Grazer | — | it swims away |

- Health regenerates at 0.6/s above half energy (the step 1 rule), so a player who escaped two hits is whole again in about 40 s.
- **Why a hunter can farm rammers:**
  - From behind, the first bite causes pain.
  - The rammer must then turn (up to 1.26 s), open to its 3 m window (a run-up, since the hunter is close and faster), stop, and puff for 1.2 s.
  - Meanwhile bites land every 0.6 s. It flees below 15 health (after 3 bites) at 1.84 m/s, and the hunter (3.26 m/s) catches it.
  - The slow gate checks this (section 18).

## 10. Deaths, carrion and the end of the interim supply

**A creature dies** when its health reaches 0 after damage:
1. Emit `creature_died {id, species, cause: "killed", by, position, carcass: [food ids]}`.
2. **Carcass:** for `i` in `0..chunks−1`, try the angle `heading + i × TAU / chunks` at 0.45 m, then 0.9 m. Take the first point with `arena.is_clear(p, 0.3)`, else the body's center. Then call `carrion.spawn(p, "kill", 24.0)` (3 points).
   - Deterministic, with no RNG.
   - The chunks are edible on the next tick, because feeding already ran this tick.
3. `region.on_creature_removed(role)`.
4. Queue a respawn at `tick + roundi((respawn_s + rng.randf_range(−jitter, jitter)) × 60)` from the field's encounter RNG. Debug spawns are never queued.

**A starving creature** emits `creature_died {cause: "starved"}` and leaves no carcass.

**The player dies:**
- `dead = true`, `death = {cause: "killed", by, by_species, reason}`;
- emit `died {cause, by, by_species, reason, position}`;
- the player leaves **no carrion** (D12). There is no corpse-run exploit, and the player cannot feed an ambush hunter.

**Interim supply off** (D1). Carrion comes only from:
1. the 3 world-start carcasses (moved, D19);
2. the player's kills;
3. creature-on-creature kills (ambush hunters on rammers near lair_gap; rammers retaliating).

**Hunter viability** (D2) is a fixed gate, not a hope (slow test #30).
- **Setup:** HuntBot drives a hunter on seeds **201–206**, fixed now, 240 s each.
- **Pass:** in at least **5 of 6** seeds:
  - no starvation death;
  - ≤ 1 threat death;
  - ≥ 3 carrion chunks eaten.

  The test prints kills and meals per seed.
- **If it fails, tune data in this order,** one knob at a time, stopping at the first pass and never past the bound:

  | # | Knob | From → bound |
  |---|---|---|
  | 1 | `rammer.niche.respawn_s` | 30 → ≥ 15 |
  | 2 | `rammer.carcass.chunks` | 3 → ≤ 4 |
  | 3 | `ambush_hunter.carcass.chunks` | 4 → ≤ 5 |
  | 4 | `pool_m1.carrion.lifetime_s` | 120 → ≤ 240 |
  | 5 | `rammer.flee.below_health_share` | 0.4 → ≥ 0.25 |

  HuntBot may be improved; the test thresholds may not be loosened.
- **If all five reach their bounds and it still fails,** it goes to the owner as **OD2** (section 24).

The respawn energy ladder (0.6 / 0.8 / 1.0) already breaks a starvation death loop without adding food.

## 11. Niche spawning: `game/systems/creature_field.gd`

```gdscript
class_name CreatureField extends RefCounted
var species: SpeciesCatalog
var creatures: Array = []           # Creature, in creation order (= tick order)
var next_number := 1
var rng: RandomNumberGenerator      # encounter seed: world_seed * 1000003 + 3
var queue: Array[Dictionary] = []   # {site, species, at_tick}, sorted by (at_tick, site)
var engaged_on_player := PackedStringArray()
var events: Array[Dictionary] = []
static func create(p_species, catalog: PartCatalog, layout: PoolLayout, region: EcologyRegion, seed_value: int) -> CreatureField
func populate(arena: PoolArena, player_pos: Vector2, zoom_max: float, tick: int) -> void
func tick_spawns(arena: PoolArena, player_pos: Vector2, tick: int) -> void
func spawn_at(species_id: String, p: Vector2, heading: float, site := "", tick := 0, debug := false) -> Creature  # tests and dev
func remove(c: Creature, reason: String, tick: int, requeue: bool) -> void
func find(id: String) -> Creature
func bodies(player_body: Dictionary) -> Array[Dictionary]   # the start-of-tick snapshot for senses
```

- **Niches.** At create, each species calls `region.set_niche(role, cap)`. Every spawn calls `region.try_spawn(role)` first; `remove` calls `on_creature_removed`. Debug spawns bypass the cap and are not counted (D17).
- **Sites.** Each site holds at most one creature. Sites are in data order. Creatures are placed only at their own sites, never around the player.
- **Spawn check**, at populate and at each due queue entry. While the player is dead, the checkpoint counts as the player position.
  1. The home is ≥ `spawn_safe_m` (20) from the player.
  2. The home is outside `ViewFootprint.contains(player_pos, home, camera, zoom_max, spawn_view_aspect, look_ahead_max + spawn_view_margin_m + radius)` (D9). This can be cut after the 20 m rule if late.
  3. `arena.is_clear(home, radius)`.
  4. No body within `min_gap_m` (2) of the home.

  On failure the entry is requeued `retry_s` (1 s) later.
- **`ViewFootprint`** (pure, `game/domain`):
  - It is the plane trapezoid of the north-up camera, from pitch, FOV, zoom distance and aspect (the numbers in section 0), grown by the margin.
  - A scene test checks it against `Camera3D.unproject_position` (section 18).
- **New creature:**
  - `rest` (ambush `rest/lurk`), at home and `home_heading`, with energy `start_energy_share`.
  - **Settle:** `ignore_all_until = tick + settle` (3 s), so it notices nothing.
  - The view fades it in over `fade_in_s` (1.0 s).
  - Brain seed `(world_seed × 1000003 + 3) × 31 + number`, so a creature's choices do not depend on the order of other creatures' thinks.
- **Not saved** (D16). On continue, `populate` rebuilds the population from the encounter seed, and sites that fail the spawn check wait in the queue.

## 12. PoolSim changes

```gdscript
static func create(save, catalog, layout, p_species: SpeciesCatalog = null) -> PoolSim   # null = step 2 exactly (T14)
var species: SpeciesCatalog; var creatures: CreatureField   # null without species
var death := {}                       # {cause, by, by_species, reason} while dead
var grace_until := -1                 # tick; the player is concealed and immune to strikes before it
var death_streak := 0; var last_respawn_tick := 0
var dev_ai_frozen := false; var dev_hidden := false          # dev switches (hashed)
func checkpoint() -> Dictionary       # {position, heading}: the generation start = layout.spawn in step 3
func position_for_save() -> Vector2   # checkpoint while dead, else motion.position
func respawn_player() -> void         # section 13; emits respawned {grace_s, energy, relocated, streak}
func player_body() -> Dictionary      # the player in the senses' body format
func is_sheltered() -> bool
# Dev commands (dev tools only; each emits "debug" and returns bool):
func debug_spawn_creature(species_id: String, p: Vector2, heading: float) -> bool
func debug_spawn_threat_ahead(species_id: String) -> bool   # 6 m ahead, facing the player
func debug_kill_nearest_creature() -> bool                  # cause "killed", by "debug"; leaves a carcass
func debug_set_ai_frozen(on: bool) -> bool
func debug_set_hidden(on: bool) -> bool
func debug_hurt_player(amount: float) -> bool
```

- `create` with species:
  - builds `creatures` (seed +3) and populates against the restored player position;
  - sets `grace_until = start_grace_s × 60` for a new lineage **and** on continue, so a load never drops the player into danger;
  - starts with `death_streak = 0`.
- `write_position_to_save()` writes `position_for_save()`.

### Tick order (fixed; tests depend on it)

When `species` is null, steps 1, 2, 10, 11 and 12 and every creature part of steps 4–9 are skipped. What remains (player steer, move, metabolism, ecology, sync, feed) is exactly step 2's tick (T14).

1. **Body snapshot.** The senses' body list, built **once**, before anything moves: the player, then creatures in number order.
2. **Creatures** (unless `dev_ai_frozen`), in number order, for each live creature:
   - (a) set the player percept's `engageable` (the token);
   - (b) if a think is due or `wake` is set: `perceive`, plus `perceive_food` while foraging, then `think`; update `engaged_on_player`;
   - (c) `d = drive(...)`;
   - (d) motion by `d.mode`: `steer`, tell braking and turning, `burst` or `glide`.

   A frozen creature gets zero intent and coasts.
3. **Player** (if not dead): steer, as in step 2.
4. **Move:** `arena.move` for the player, then each creature. Record the distances.
5. **Contacts:**
   - `separate` each overlapping pair (player first, then creature order), one pass;
   - `arena.settle` each body that separation moved;
   - `PoolArena.clamp_to_disc` each creature to its leash disc, **last**, so the leash invariant holds at the end of every tick;
   - a striking creature whose `rock_contact` lies ahead (bearing ≤ 60°) → `on_blocked`.
6. **Metabolism:**
   - the player exactly as in step 2 (starving events, `died {cause: "starved", ...}`, survival points);
   - creatures at `metabolism_share`; a starved creature is removed.
7. **Ecology:** `region.tick`, `plankton.tick`, `carrion.tick` (no supply), then `creatures.tick_spawns`.
8. **Sync** the player's and every creature's resolver actors.
9. **Feeding:**
   - the player (if not dead), as in step 2;
   - then each creature whose `drive.feed` names a food item, through `InteractionResolver.feed` and the shared `_take_food` (region stock, `consume`, no points). Emit `creature_ate`.
10. **Combat:**
    - (a) the player's attacks;
    - (b) creature strikes in number order;
    - (c) knockback and speed clamps;
    - (d) deaths: the player first (`died`), then creatures in number order (carcass, removal, queue).
    - A body killed in (a) cannot strike in (b). A mutual kill on one tick resolves in this fixed order (T12).
11. **Dodges:** a strike that ended this tick with no hit on the player → `dodged`.
12. **Shelter:** if `grace_until` passes this tick → `grace_ended {reason: "timeout"}`. Then `tick += 1`.

While the player is dead:
- steps 3, the player's part of 9, and 10a are skipped;
- creatures keep living, as the world did in step 2;
- the pool is paused while the death notice is open, as in step 2.

### Determinism

- **Scope:** same build, same platform. Hashes are compared between runs in one process, never against stored constants.
- **Seeded RNGs only:**

  | Stream | Seed |
  |---|---|
  | Region (existing) | +1 |
  | Carrion (existing) | +2 |
  | Encounter field | +3 |
  | One per brain | `field seed × 31 + number` |

  No system draws from another system's RNG (T15).
- **Every sort has a total order:**
  - percepts and player targets by (distance, id);
  - the spawn queue by (at_tick, site);
  - creatures by number;
  - carcass chunks by index.
- All timers are integer ticks.
- `snapshot()` includes every creature field and RNG state. Event logs are excluded.

### Events (new or changed)

| Event | When |
|---|---|
| `creature_spawned {id, species, site, position, heading}` | A creature is placed |
| `creature_noticed {id, target, by, position}` | Notice begins |
| `creature_tell {id, target, kind: lunge\|puff, ticks, lane, position}` | Tell begins; the view poses for `ticks` and draws `lane` |
| `tell_cancelled {id, target, reason}` | The puff is cancelled (`left_territory`) |
| `creature_strike {id, target, kind, position, heading}` | Strike begins |
| `creature_recovered {id, target, outcome}` | Recovery begins (`hit\|missed\|blocked\|interrupted\|cancelled`) |
| `dodged {id, species}` | A strike on the player ended with no hit |
| `creature_gave_up {id, target, reason}` | Any give-up |
| `creature_fled {id, from}`, `creature_ate {id, kind, food_id}` | Flee; a creature meal |
| `hit {attacker, target, kind: bite\|ram, damage, dealt, target_health, knockback, position}` | Every landed hit, either way |
| `attack_refused {target, kind, reason}` | The player only, throttled |
| `creature_died {id, species, cause, by, position, carcass}` | Death |
| `creature_removed {id, reason: "stuck"}` | Stuck recovery |
| `died {cause: starved\|killed, by, by_species, reason, position}` | The player dies (was `{cause}`; `cause` is kept, so step 2 handlers work) |
| `respawned {grace_s, energy, relocated: [ids], streak}` | Checkpoint respawn (was `{}`) |
| `grace_ended {reason: timeout\|attacked}` | Shelter ends |
| `carrion_spawned {source: "kill", ...}` | Unchanged event; new source |

### Snapshot additions (all vectors through `_pair`)

```text
"creatures": [{"id","number","species","site","debug","born_tick","position","velocity","heading","prev_position",
               "health","energy","cooldowns","last_hit_by","strike_hit",
               "drive":{"mode","move","speed_mul","strike","target","feed"}, "brain": mem.to_dict()}],
"creature_next", "creature_rng", "spawn_queue": [{"site","species","at_tick"}], "engaged_on_player",
"niches": region.niches, "grace_until", "death_streak", "last_respawn_tick", "death", "dev_ai_frozen", "dev_hidden",
"stats" += {"kills","hits_dealt","hits_taken","damage_dealt","damage_taken","dodges","creature_meals","creature_deaths"}
```

`state_hash()` is unchanged in form.

---

## 13. Checkpoints, death and saving

### The checkpoint in step 3 (D8)

- **What it is:** the last generation's start. Generation 1 is the only generation until step 4, so the checkpoint is `layout.spawn` and `layout.spawn_heading`.
- **Where it lives:** derived, not stored, through `PoolSim.checkpoint()`. **No schema change:** v2 and the 15-key guard stay.
- **Step 4:** adds the per-generation spawning spot in schema v3, with a migration and a fixture test. Only `checkpoint()` changes, and rules 8 and 11 then run against every spawning spot.

### The death flow (`GameSession`)

```gdscript
## Top of file. The owner's choice for OD1; the recommended value is true.
const SAVE_ON_DEATH := true
var save_on_death := SAVE_ON_DEATH    # tests set it to exercise both paths
## Applies the death once (Lineage.apply_death with RespawnRules.death_cause) and, when save_on_death,
## writes the slot with the player at the checkpoint. Idempotent.
## Returns {lost, cause, by_species, reason, tip, saved: {attempted, ok, error}}.
func resolve_death() -> Dictionary
## Resolves first if needed (so step 2 callers keep working), then sim.respawn_player(). Returns the points lost.
func respawn_after_death() -> int
```

1. The sim emits `died`. `Main._on_died` calls `session.resolve_death()`:
   - `lost = Lineage.apply_death(save, RespawnRules.death_cause(death))`. The cause is `"starved"`, `"killed:ambush_hunter"` or `"killed:rammer"` (D18).
   - With `save_on_death`: `_write()`, with `position_for_save()` = the checkpoint, through the existing temp, verify and backup path. `_mark_saved()` then stores `position_for_save()`, the points and the history.
   - If that save fails, the death still applies in memory, the session stays dirty, and the notice adds "Could not save: …".
2. The notice shows the **already applied** loss (section 15).
3. Continue → `respawn_after_death()` → `sim.respawn_player()`.

**`_is_dirty()`:**
- `(sim.dead and not _death_saved)`, or points or history differ from the last save, or `position_for_save()` moved > 1 m from `_saved_position`.
- After a saved death the cell is *not* dirty, both while the notice is open and after a respawn at the checkpoint.

**`request_quit()` while dead:**

| Situation | Behaviour |
|---|---|
| Death saved (OD1 yes) | Not dirty, so no dialog; the app quits. The notice already said "Saved." |
| Death save failed | The dialog reads "Your cell's death could not be saved. Quit anyway?" [Quit, Cancel] |
| Fallback (OD1 no) | The step 2 dialog, unchanged ("Save first?" plus "Saving is off…"). Quitting without saving discards the death, as in step 2 |

`save_now()` stays refused while dead.

**Why the death is saved at once:**
- In step 2, "Quit without saving" at the death notice skipped the death (step 2 D5). A fair checkpoint must not be skippable, and threats make deaths common.
- It writes only what the run already owns: points minus the loss, history plus `died`, and the position at the checkpoint.
- It adds a write trigger beyond the brief's "autosave on each generation", so it is **owner decision OD1**. The build uses the recommended option. The fallback is one constant, and both paths are tested (test_checkpoints #2–3 run with `save_on_death` true and false).

### `sim.respawn_player()`: checkpoint rules C1–C7 (the mechanics behind F7)

```gdscript
class_name RespawnRules extends RefCounted
static func streak_after(prev_streak: int, alive_ticks: int, window_ticks: int) -> int  # alive < window → prev + 1, else 1
static func pick(table: Array, streak: int) -> float                                   # table[clampi(streak, 1, size) - 1]
static func to_relocate(checkpoint: Vector2, clear_m: float, bodies: Array) -> PackedStringArray  # ids within clear_m, sorted
static func death_cause(death: Dictionary) -> String                                   # "starved" | "killed:<species>"
```

| Rule | What respawn does | Checked by |
|---|---|---|
| C1 | The cell is placed at `checkpoint()`, confirmed by `arena.is_clear`; otherwise at the nearest clear point on a 0.5 m spiral (unreachable for the real layout) | test_checkpoints |
| C2 | Every creature within `respawn_clear_m` (12) is placed at its home and heading with `force_return`, in the same tick as the respawn (the camera snaps then). Rule 8 and the hard clamp make this reachable only for debug creatures | Position check; fuzz invariant 3 |
| C3 | Every brain forgets the player (`seen`, `target`, `landed_on`). The killer gets `ignore["player"] = tick + 30 s`. The token is released. The player is **concealed** until `grace_until` | Brain dicts; no `creature_noticed` on the player during shelter |
| C4 | `ActorState.fresh`, then `energy = capacity × respawn_energy_share[streak]` (0.6 / 0.8 / 1.0). Full health. Cooldowns cleared | State values |
| C5 | Shelter = `grace_s[streak]` (5 / 8 / 10 s). Strikes against a concealed target are skipped and senses skip it. Shelter ends early if the player lands a hit | No `hit` on the player before `grace_until` |
| C6 | The lineage is intact: lineage id, genome JSON and generation unchanged. Points = before − `floor(25%)`. History gains exactly one `died` entry with its cause | Save compare |
| C7 | With OD1: the slot on disk matches C6, with the position at the checkpoint | Reload from the slot |

- **Streak:** `streak_after(prev, ticks alive since the last respawn, 90 s)`. It is not saved (D16), so continue resets it.
- **New lineage and continue:** `start_grace_s` (5 s) of shelter, and the spawn check with the footprint rule.

## 14. Scenes

### `creature_view.tscn`

```text
CreatureView (Node3D, script creature_view.gd)
├── Pivot (Node3D; yaw from heading, PlaneSpace)
│   └── Model (Node3D; uniform scale = body_size × pose.scale)
│       ├── Body (creature_<x>_body.glb instance: Eye_L, Eye_R, Brow | Hood)
│       └── Parts (Node3D; one holder per genome part placed by PartPlacement, the player's part GLBs)
├── Lane (MeshInstance3D quad on the floor, unshaded, alpha ≤ 0.25; visible only during a tell targeting the player)
└── Marker (Label3D "!", no depth test; shown 0.6 s on notice of the player)
```

- **`static func pose(behavior: String, phase: String, progress: float) -> Dictionary`**, pure and tested. It returns `{scale: Vector3, jaw_open, hood, spike_raise, eye_glow, stretch}`.

| Behavior / phase | Pose |
|---|---|
| Ambush `notice` / `rest/watch` | Eye glow 0.4; the body turns to track (from the sim heading) |
| Ambush `tell` | **Coil:** scale z 1.0 → 0.82, x 1.0 → 1.08; jaw 0 → 1; eye glow 0.4 → 1.0, eased in |
| Ambush `strike` / `glide` | Stretch: scale z 1.15, jaw 1 |
| Ambush `recover` | Relax back over the first 40% |
| Rammer `tell` | **Puff:** uniform 1.0 → 1.25; hood 0 → 1; spike raise 0 → 1 (part holders tilt 25° outward) |
| Rammer `strike` / `glide` | Puffed scale held at 1.2; spikes raised |
| Rammer `recover` (`blocked`, `cancelled`) | Deflate. Blocked adds a 0.3 s wobble; cancelled deflates over 0.4 s |

- **Progress** = `(sim.tick − brain.phase_tick + interpolation alpha) / phase_ticks`, read from the sim every frame. The pose and the damage window come from the same counter.
- **Lane:** placed from the event's `lane` (`strike_lane`: lunge 3.71 × 3.1 m, charge 5.70 × 2.95 m, for a 0.5 prey). It fades out at the end of the glide.
- **Creature hurt:** a 0.15 s white-red overlay flash and a 0.1 s squash.
- **Death:** a 0.4 s shrink and fade; the chunks appear from `carrion_spawned`.
- **Spawn:** fade in over 1.0 s.

### `creature_layer.gd`

- Builds one view per creature on `creature_spawned` and on attach (it reads `sim.creatures`).
- Frees views on `creature_died` and `creature_removed`.
- Interpolates `prev_position` → `position` exactly like PlayerCellView.

### `pool.gd` routing additions

| Event | Response |
|---|---|
| `creature_noticed` (target player) | View marker "!"; `notice` cue; HUD indicator if off-screen |
| `creature_tell` | `tell_lunge` or `tell_puff` cue (positional, length = tell); lane on when targeting the player; the pose is driven by the phase, not by this event |
| `tell_cancelled` | Lane off |
| `dodged` | "Dodged!" label; `dodged` cue |
| `hit` | Player target: `cell_view.hurt()` (0.15 s flinch and red overlay), HUD vignette, `hurt` cue, "−12" label. Creature target: hurt flash and a `bite`/`ram` cue |
| `creature_died` | Shrink the view; `creature_die` cue |
| `died` | As in step 2, but `died.emit(cause, reason)` |
| `respawned` | As in step 2, plus the shelter shimmer and the `respawn` cue |
| `grace_ended` | Shimmer off |

### Player view

- `PART_SCENES["spike"] = part_spike.glb`.
- `hurt()`.
- `set_sheltered(on)`: a soft cyan rim pulsing at 1 Hz with alpha ≤ 0.25, so it never flashes.

### Audio (placeholder, synthesized; one inventory entry each; `remove_by` "M1 step 5")

| Cue | Sound | Where it plays |
|---|---|---|
| `notice` | 0.15 s rising chirp | Positional |
| `tell_lunge` | Low rising growl, **length = tell_s from data** | Positional |
| `tell_puff` | Inflating hiss, length = tell_s | Positional |
| `bite` | Snap | Positional |
| `ram` | Thud | Positional |
| `hurt` | Short dull thump plus a high tick | 2D |
| `dodged` | Light ping | 2D |
| `creature_die` | Descending tone | Positional |
| `respawn` | Soft two-note chime | 2D |

- Positional cues use a pool of 6 `AudioStreamPlayer3D`, with `max_distance` 25 m. A tell cue is therefore audible even when the creature is off-screen.
- The `REPEAT_LIMIT_MS` rule is unchanged.

## 15. HUD, feedback and the death notice

Every signal uses at least two of shape, motion, text and sound. Colour is never the only carrier.

- **Off-screen indicators** (`game/ui/threat_indicators.gd`, **never cut**):
  - **Which creatures:** each one whose brain targets the player in `notice`, `rest/watch`, `chase` or `attack`, and whose projected position is outside the viewport.
  - **What is drawn:** an edge arrow with the species glyph (`HudIcon` `jaw` = ambush hunter, `star` = rammer). During a tell it pulses at 3 Hz and shows "!".
  - **Placement:** `static func edge_point(rect: Rect2, p_screen: Vector2, behind_camera: bool, margin: float) -> Vector2`, pure and tested. A position behind the camera is mirrored.
  - Updated at 30 Hz. A functional inventory entry.
- **Shelter chip:** "Sheltered 5" with the `ring` icon, counting down whole seconds and hidden at 0. Text from `Hud.grace_text(seconds)`.
- **Hurt vignette:** a `ColorRect` with a radial edge shader. One pulse per hit, alpha up to 0.35 and down over 0.4 s, at most once per 0.5 s. No full-screen flash and no camera shake (comfort).
- **Health bar:** shown whenever health < max, or while starving (the step 2 rule), so damage is always visible.
- **Hit numbers** (cuttable): a Label3D "−12" for damage dealt and taken, using the pooled `feedback_labels`.
- **"Dodged!"** (cuttable): a 0.8 s floating label on `dodged`.
- **Death notice:**

  | Cause | Title |
  |---|---|
  | `starved` | "Out of energy" |
  | `killed` | the species `death_reason`, e.g. "Caught by an ambush hunter" |
  | anything else | "Your cell died" |

  - `Main.death_title(cause, reason := "")` returns the title.
  - `Main.death_text(cause, lost, tip := "", saved := true)` returns one sentence and a tip line. For example: "The lineage continues from the start of generation 1. You lost a quarter of your unspent adaptation points (−3). Saved." plus the species `death_tip`.
  - The starvation tip names only food the body can eat (`GameSession.starved_tip`, a review fix): "Plankton regrows in the sunlit patches; slow down when energy runs low." for a body that eats plankton, "More carrion comes only from kills: bite a rammer from behind, jaw first, and keep biting until it dies, then eat what it drops. Slow down when energy runs low." for one that eats only carrion, and "Slow down when energy runs low." otherwise.
  - The step 2 phrasing "You lose" becomes "You lost", because the loss is already applied.
  - When the save failed, "Saved." becomes "Could not save: <error>". With the OD1 fallback, "Saved." is omitted.
  - Continue toast: "Back at the generation start · sheltered for 5 s."

## 16. Debug panel and dev tools (debug builds only)

**Debug panel "AI" section** (refreshes at 4 Hz like the others). Example:

```text
c_3 ambush_hunter @lair_se  attack/tell 0.32/1.20 s  → player (sight, 0.1 s ago)  give-up 2.1/5.0 s  [token]
    hp 45/45  en 78%  home 1.2 m  ignore: -
c_5 rammer @terr_n_a  wander/patrol  goal (−1.0, −24.3)  hp 37.5/37.5  en 64%
niches: ambush 3/3  territorial 4/4   queue: lair_gap in 41.2 s   token: c_3
player: sheltered 3.2 s  streak 2  last death killed:ambush_hunter  checkpoint (0.0, 9.0)
```

The `Copy` button still copies the whole snapshot, which now includes creatures.

**Gizmos** (with the panel, as in step 2):

| Gizmo | Shows |
|---|---|
| Sight cone | Range and FOV, coloured by state: rest grey, wander blue, forage green, notice yellow, chase orange, attack red, flee purple |
| Near circle | The near-sense radius |
| Territory and leash rings | Rammer territory, exit and leash; ambush leash around the lair |
| Lair marker | Home position and a heading tick |
| Target line | To the *remembered* position, dashed when older than 0.2 s. It shows belief, not truth |
| Strike lane | `strike_lane()` during tells, for every target |
| Checkpoint circles | `respawn_clear` (12 m) and `spawn_safe` (20 m) |
| View footprint | The zoom-max `ViewFootprint` outline around the player |

**Commands.** Panel buttons and keys both go through `debug_panel.run()`, as in step 2.

| Key | Command | Sim call |
|---|---|---|
| F9 | `spawn_threat` (alternates species) | `debug_spawn_threat_ahead` |
| F10 | `kill_nearest` | `debug_kill_nearest_creature` |
| (button) | `freeze_ai` toggle | `debug_set_ai_frozen` |
| (button) | `hide_from_ai` toggle | `debug_set_hidden` |
| (button) | `hurt_self` (10) | `debug_hurt_player` |

`project.godot` adds `dev_spawn_threat` (F9) and `dev_kill_nearest` (F10).

**Bots** (`game/dev/`, loaded by path, no `class_name`):
- **EvadeBot** (`evade_bot.gd`). It wraps a base intent (idle, graze in a heading, cruise, approach a point, or ForageBot) and reads **only sim events**, the way a player watches the screen.
  1. On `creature_tell` targeting the player, it waits `reaction_ticks` (24).
  2. Then it swims perpendicular to the event's lane heading. The side is the one with the shorter turn from its current heading; on a tie (difference < 1e-3 rad), the side of the lane centre line it is already on.
  3. It holds that until the matching `creature_recovered`, `dodged` or `tell_cancelled`.
  4. Then it swims straight away from the creature for 1.0 s, and returns to the base intent.
- **HuntBot** (`hunt_bot.gd`, hunter body; it may read the whole sim). Its priorities:
  1. the EvadeBot reaction;
  2. eat sensed carrion;
  3. approach the nearest rammer not in tell or strike to a point 1.2 m behind its tail, and bite while in its rear arc;
  4. retreat to z_center when health < 40%;
  5. patrol z_n → z_ne → z_nw, keeping 10 m from every lair.
- **KiterBot** (`kiter_bot.gd`). It drives toward the nearest creature and circles it at 3–6 m, crossing lairs and territories, with no evasion.
- **ForageBot** gains `avoid_threats := false`. When on, it skips food within 8 m of any creature, routes away from creatures within 6 m, and uses the EvadeBot reaction. The step 2 smoke phases turn it on.

## 17. Art: Blender blockouts (no mesh placeholders planned)

**`tools/blender/make_m1_threats.py`** runs under headless bpy at `/root/tools/bpyenv/bin/python`. It reuses `blockout_common` with `export(..., review_state="blockout - M1 step 3, not visually approved", generator="tools/blender/make_m1_threats.py")`. Each asset gets a `.blend`, a GLB and a record.

**Body-only blockouts.** Parts are placed at runtime from the existing part GLBs through `PartPlacement`. There are no composite species GLBs and no data-hash coupling, so tuning `parts` or `body_size` in data never needs a Blender re-run (D22).

| Asset | Spec | Budget |
|---|---|---|
| `creature_ambush_body` | Unit frame shared with parts (equator RX 0.46 / RZ 0.5, so `PartPlacement` attaches the same part GLBs). **Flat:** top 0.24, bottom 0.20. Dark mottled olive-brown vertex colours with a pale belly. A brow ridge (node `Brow`). Amber eyes `Eye_L`/`Eye_R` with material `M_AmbushEye` (the view drives its emission) | ≤ 4,000 tris |
| `creature_rammer_body` | Same frame; **domed:** top 0.40, bottom 0.30. Pale sand with three dark bands. A dorsal frill on node `Hood` (scaled in the puff). `Eye_L`/`Eye_R` | ≤ 4,000 tris |
| `part_spike` | 0.32 m tapered cone, bone white with a dark tip. Origin at the attachment point; outward axis Blender +Y (Godot −Z); embed 0.03 m; `part_type` "spike" | ≤ 600 tris |

**Shape language** ("tell food from danger by shape and motion alone"):
- Food is small, round and drifting, in green or red-brown.
- Threats are big and flat with glowing eyes (ambush), or domed, banded and spiked (rammer).
- Threats move with intent: they turn to face you, stop, then coil or puff.

**`test_assets` contracts:**
- node names (`Body`, `Eye_L`, `Eye_R`, and `Brow` or `Hood`);
- triangle budgets;
- the ambush footprint at body_size 1.5 is ≥ 1.4 × the sample cell's;
- the ambush height-to-width ratio is ≤ 0.35;
- a spike tip at scale 1 protrudes ≥ 0.25 m beyond the body ellipse when placed by `PartPlacement`;
- record dimensions within ±0.05 m.

**Placeholder rule:** if the Blender commit slips (cut list), bodies fall back to `CapsuleMesh`/`CylinderMesh` placeholders. Each gets an inventory entry with `remove_by` "M1 step 5", and `test_placeholders` keeps them honest.

---

## 18. Tests

### Runner and policy

- **`run_tests.gd`:**
  - `-- --skip-slow` skips methods named `test_slow_*`, for agent loops;
  - `-- --only=test_creature_brain,test_threats_sim` filters files;
  - CI's `check.sh` runs everything with no flags.
- **Expected time:** today about 30 s, plus about 30 s for the new fast tests and about 2 minutes for the slow ones. **Budget ≤ 4 minutes.**
- **Flake policy:**
  - No test compares wall-clock time except the cost gates, which print their value and fail only at 3–5× the expected cost.
  - Scenario tests use fixtures and scripted intents. Statistical gates use seeds written into the test **before** any measurement and state their miss budget. If a gate fails after a change, tune the data, never the test.
  - **Non-vacuity:** every scenario first asserts its trigger event happened (for example `creature_tell` fired once), then asserts the outcome.
  - Before the PR, `check.sh` runs 3 times in a row with an absolute private `XDG_DATA_HOME`.
- **Determinism scope:** same build, same platform, within one process. No golden hashes.

### New unit tests

| File | Asserts |
|---|---|
| `test_creature_senses` | **Range:** perceived at `sight + r − 1e-3`, not at `+ 1e-3`. **FOV:** bearings at ±fov/2 are perceived, ±(fov/2 + 0.01) are not. **LOS:** a rock between them hides the body; grazing within 0.9 × the rock radius of the edge does not. **Near sense** ignores FOV and LOS. Concealed, dead and self are skipped. **Order:** (distance, id), with an equal-distance tie that `sort_custom` alone would scramble. Percepts are copies. `engageable` passes through. `perceive_food` uses range and FOV only |
| `test_creature_brain` | Synthetic percepts only; the 14 cases below |
| `test_respawn_rules` | Streak 1 → 2 → 3 within the window, reset to 1 at ≥ 90 s. `pick` clamps beyond the table. `to_relocate` is sorted and includes exactly 12.0 m. Cause strings |
| `test_species_catalog` | The real data is valid. One mutated copy per rule (1–13) produces that rule's named error, for example: 5 spikes (rule 1); burst 6.5 m/s; pursue 0.95 (2.61 > 2.448); tell 1.1 s; a 15-damage hit; a lair 20 m from spawn with leash 9; old lair_se (pinch with rock_14); old lair_gap (band with rock_12); a cap greater than its sites; a `homing_deg_s` key. Species genomes are deterministic: same ids and `to_dict()` on every load |
| `test_creature_field` | The 7 cases below |
| `test_view_footprint` | The corners match section 0 within 0.01 m (zoom 14 and 20; 16:9 and 2.4:1). `contains` is true at the look target and false 1 cm outside each edge. The margin grows the trapezoid |
| `test_threat_indicators` | `edge_point` puts on-screen points unchanged, off-screen points on the inset rect edge along the ray from the center, and mirrors behind-camera points. Corners, NaN-free |
| `test_phenotype` (+) | Size 1 equals the default for every starting body and every single-part genome (`to_dict` + `radius`, `mouths`, `spikes`). Ambush numbers: radius 0.75, mass 1.95, speed 2.749 ± 0.001, accel 2.277 ± 0.001, health 45, upkeep 1.725, bite 12. Rammer numbers: radius 0.625, speed 1.840 ± 0.001, health 37.5, spike 6.0. Spike damage scales with part scale × s |
| `test_locomotion` (+) | `burst` sets heading and speed exactly. `glide` after n ticks equals `v0 × exp(−drag × n / 60)` within 1e-9. `steer` cases unchanged |
| `test_pool_arena` (+) | `settle` after a 10,000-step fuzz keeps the invariants. `segment_clear` cases. `route_point` (the moved ForageBot cases). `separate`: bodies end ≥ `ra + rb − 1e-4` apart, the heavier one moves less, velocities unchanged. `rock_contact`. `clamp_to_disc`: the position ends on the circle, inward velocity is kept, and outward velocity is removed |

**`test_creature_brain` cases:**
1. `rest` → `notice` when a prey percept appears. **No** notice for: the same species; a body over 1.6 × its own radius; an ignored id; anything during `settle`.
2. **Notice** lasts exactly 30 ticks. Then:
   - hungry → `chase/pursue`;
   - sated ambush → `rest/watch`;
   - not engageable → watch (ambush) or stay in `notice` (rammer);
   - watch → `chase/aim` only when in window, aimed and engageable.
3. **Phases:**
   - `aim` → `tell` only at speed ≤ 0.3 m/s, in window and aimed;
   - `tell` → `strike` at exactly +72 (set by `drive`, not by the think schedule); `strike` 21 → `glide` 15 → `recover` (missed);
   - `on_strike_landed` → `recover` at once;
   - `lock_heading` is set at tell entry and the drive heading equals it on every strike tick (no homing), however the target moves.
4. **Give-up, one test each:**
   - `lost` exactly 120/180 ticks after the last percept;
   - `timer` at 300/480 ticks with the target just outside the window;
   - `leash`;
   - `left_territory`;
   - `unreachable` with the position frozen for 120 ticks;
   - `target_gone`.

   A non-engageable target never extends a chase past these.
5. **Refractory:** the same id is ignored for 360/180 ticks after a give-up; another id is noticed at once.
6. **Pain:** `on_hurt` from behind (outside the FOV) → `notice` of the attacker on the next tick (`wake`).
7. **Flee:** below the flee share → `flee` for 240/300 ticks → `wander/return` → `rest` at home.
8. **Rammer:**
   - an intruder inside → notice; outside → ignored;
   - **puff cancel:** the target perceived at 9.01 m during the tell → `tell_cancelled {left_territory}`, no strike;
   - `on_blocked` → `recover` for 120 ticks;
   - rest durations in [240, 480] ticks.
9. **A new tell every time:** after `recover` with the target still in the window, the next attack goes through `aim` → `tell`. Never strike → strike.
10. **Drive bounds** over 10,000 random-percept ticks:
    - no NaN and `|move| ≤ 1`;
    - `speed_mul ≤ 1` outside the strike;
    - `mode` is `burst`/`glide` only in the strike;
    - the speed share in `chase` equals `speeds.pursue`.
11. **Determinism:** the same seed gives the same patrol goals. `to_dict()` holds only arrays and pairs, with no `Vector2`.
12. **Stuck:** three return timeouts set `stuck`.
13. **Tell guards:**
    - no tell when the lane end would leave the leash (an ambusher 8 m from home facing out);
    - no tell below `start_min_m`: it moves to the stand-off point instead.
14. **`strike_lane`:**
    - lunge length 3.71 and half-width 1.55, charge 5.70 and 1.475 (prey 0.5);
    - the travel equals the per-tick sum of burst and glide within 1 cm;
    - the lane contains every position where the resolver would allow the hit (sampled).

**`test_creature_field` cases:**
1. **Populate on the real layout:** 7 creatures at their sites; niche counts 3/3 and 4/4; ids c_1…c_7 in site order.
2. **Spawn-safe deferral:** with the player at lair_se, that site is queued, and it spawns at the first 1 s retry once the player is ≥ 20 m away and outside the footprint.
3. **Death:** the niche count drops; the queue entry lands in [50, 70] s (ambush) or [24, 36] s (rammer).
4. **Carcass placement:** chunks are clear of rocks, including next to a fixture rock. Count 4 or 3; source "kill"; 24 energy and 3 points each.
5. **Stuck removal** requeues only when the player is far and the site is out of view.
6. **Debug spawns** bypass the cap, are not counted and never respawn.
7. **Settle:** a new creature notices nothing for 180 ticks, then notices a prey that was in view all along.

### Integration tests: `test_threats_sim` (fixtures with `creatures_test.json`, or real data where stated)

**Tells and fairness.** These run in the real sim. Creatures are placed with `spawn_at`, and the tell starts at tick 0 through the brain's own `begin_tell` (whitebox), matching the probe geometry: at rest, facing the prey at distance d.

1. **The threats are real, and moving prey is safe** (pinned together, so tuning cannot slide to either extreme). No reaction, all 3 bodies, fed:
   - still prey is hit in 36/36 cases for both species;
   - a prey grazing perpendicular at 30% is hit in ≥ 5/6 (lunge) and ≥ 4/6 (charge);
   - a prey crossing perpendicular at 80% is hit in ≤ 1/6 for both.
2. **S5 lunge grid.** EvadeBot (24 ticks), d ∈ {2.5, 2.75, 3.0} × 12 headings × {still, graze 30%} × {fed, starving} × 3 bodies.

   | Cell | Hits | Clearance |
   |---|---|---|
   | still, fed | 0 | ≥ 0.15 m everywhere |
   | still, starving | 0 | ≥ 0.15 m outside head-on (150–210°) |
   | graze, fed | 0 | ≥ 0.15 m outside head-on |
   | graze, starving | ≤ 1 per body, head-on only | ≥ 0.10 m outside head-on |

3. **S5 charge grid.** The same grid at d ∈ {3.0, 4.0, 5.0} inside the territory.

   | Cell | Hits | Clearance |
   |---|---|---|
   | fed (still and graze) | 0 | ≥ 0.15 m everywhere |
   | starving (still and graze) | 0 | ≥ 0.05 m everywhere |

4. **S5 natural path.** No whitebox: notice → pursue → aim → tell, with all 3 bodies still or grazing at 4 headings and EvadeBot. The bounds are those of #2–3. This proves the brain reaches the probed geometry on its own.
5. **S6 escape** (F3). Each of the 3 bodies swims straight away at full throttle from a hungry ambusher and from a rammer, each starting 4 m behind it in pursuit.
   - **Fed:** after the first 1 s, the gap never shrinks over any 1 s window (tolerance 0.05 m).
   - **Starving:** never hit, and `creature_gave_up` fires by `give_up + tell + burst + glide + recover` ticks.
6. **Exact timings.**
   - For every `creature_tell`, `creature_strike` comes exactly 72 ticks later.
   - Every creature `hit` lies inside `[strike tick, strike tick + burst + glide)` of that creature's own strike, and there is at most one per strike.
   - The heading is constant over the strike.
7. **Puff cancel.** An intruder at 6 m swims out of z_a during the puff: `tell_cancelled {left_territory}`, no `creature_strike`, no `hit`; the rammer returns.
8. **Dodged.** A dodged lunge emits exactly one `dodged` for the player and none for a creature target.

**Combat both ways.**

9. **A hunter kills a rammer:** 5 bites from behind; `creature_died`; 3 `carrion_spawned {source: "kill"}`, edible next tick; eating one gives 24 energy and 3 points through `Lineage.earn`.
10. **Fighting back:** a hunter's bite on an ambush hunter deals 8. A test genome with front spikes rams a rammer for the resolver formula's damage at the measured closing speed; backing away is refused ("not moving toward it") and changes nothing.
11. **Creature on creature:** an ambush hunter kills a rammer that wanders within 3 m of its face and leaves 3 chunks. A hungry ambush hunter then eats one.
12. **T10:** charges against a player pressed to a fixture rock from 36 directions. Penetration ≤ 1 mm and speed ≤ 6.0 m/s after every tick.
13. **T12:** player and ambush hunter at 1 health each, both attacks allowed on one tick. Both die, the events come in the fixed order, and two runs give the same hash.

**Senses: "it cannot see your coordinates".**

14. **LOS and range:** a player behind the 5-rock wall is never noticed over 600 ticks; one at 6.6 m is never noticed; one behind the creature is noticed only within the near radius.
15. **Memory:** the player breaks LOS behind the wall. The creature heads for the last seen point and gives up `lost` within memory + 3 ticks. Its remembered target position never equals the hidden player's live position.
16. **T5 invariance (the primary proof):**
    - Two sims with the same seed and one ambush hunter. Sim A parks the player 16 m north of it, sim B 16 m south, both unsensed. Creature snapshots are identical every tick for 1800 ticks.
    - Variant: both players are inside sight range but behind the wall, at different points.
    - **Control:** in clear view in sim C, the snapshots differ (the test is not vacuous).
17. **Decoy symmetry and static scan.**
    - **Harness:** a brainless decoy creature (`spawn_at` with `debug_scripted = true`). It has species `"lineage"`, the player's phenotype and actor, and its velocity is scripted to the player's intent. Hits on it go through the same `take_damage`, knockback and clamp path as the player.
    - Run A uses the player at P; run B parks the player out of sense range and puts the decoy at P. The ambush hunter's drive outputs match tick by tick until the first hit, or for 300 ticks.
    - **Static scan:** a new `_code_keep_strings()` helper strips comments only. `creature_brain.gd` and `creature_senses.gd` must contain no `"player"` or `'player'` literal and no identifier `PoolSim`, `CreatureField`, `roster`, or `sim.`.

**Give-up and recovery** (an acceptance item).

18. **Unreachable:** the player stays behind the wall's middle. The ambush hunter gives up `unreachable` or `lost`, returns, and is in `rest/lurk` within 20 s.
19. **Timer, leash and territory:**
    - the player kites just outside the window → `timer`;
    - leads the ambush hunter out → `leash`, then it is home and resting within 15 s;
    - leaves the rammer's territory → `left_territory`.

    A re-approach within the refractory window gets no notice.
20. **Stuck return:** a fixture closes the only gap of a rock ring around the creature. After 3 nav timeouts it is removed `stuck`, then respawns at its site once the player is far.

**Token.**

21. **T6, one at a time:** an ambush hunter and a rammer (debug spawns) with the player inside both trigger zones. Engaged-on-player ≤ 1 every tick. The second creature stays in notice or watch, then gives up on its timer.

**Economy.**

22. **A starving hunter recovers by killing:** a hunter at energy 0, 6 m behind a resting rammer, driven by HuntBot. It kills, eats before dying (20 s at half speed), and is no longer starving.
23. **Every fed body can pass a lair:** on the real layout, each of the 3 bodies swims at full speed along z_se past lair_se and is never hit.

**Determinism and coverage.**

24. **T13:** two sims with seed 77 and recorded intents (including a chase and a kill) give equal `state_hash()` every 60 ticks over 3600 ticks. Seed 78 differs by tick 600.
25. **Hash coverage.** Perturbing each field changes `state_hash()`:
    - position.x by 1e-9;
    - velocity, heading, health and energy;
    - a cooldown;
    - `phase_tick`, `target`, `lock_heading`;
    - a `seen` position and an `ignore` entry;
    - `landed_on`;
    - the brain and field RNG states;
    - a queue `at_tick`;
    - `engaged_on_player`;
    - `grace_until` and `death_streak`.
26. **T14:** with seed 77 and the step 2 intent script, `PoolSim.create(..., null)` and `create(..., species with no sites)` give equal `snapshot()` minus the new keys over 3600 ticks, so the creature machinery without creatures changes nothing. Every step 2 test also runs unchanged against `create(..., null)`.
27. **T15:** `region.rng.state` is identical after `create` with and without species (same seed) and across a forced respawn.
28. **Step cost:** real data, 7 creatures, ForageBot, 3600 ticks. It prints the average and fails only above **1000 µs**.

**Slow tests** (`test_slow_*`):

29. **Stress:** 24 creatures (fixture sites on a 28 m ring, caps raised), 1800 ticks. Fails above **2500 µs**.
30. **Hunter viability gate** (D2): seeds 201–206, rules in section 10, pass in ≥ 5 of 6.
31. **Predation balance:** seeds 1–4, 300 s, player hidden (`dev_hidden`) at spawn. Asserts:
    - no niche sits at 0 for more than 90 s;
    - ≤ 6 predation deaths per run;
    - every creature not resting moves ≥ 1 m per 60 s.

    It prints the kill counts.

### `test_threat_fuzz` (real layout and niches; KiterBot; seeds 401–404, 60 s each; shelter ended at the start)

Checked every tick for every creature:

| # | Invariant |
|---|---|
| 1 | No rock penetration > 1 mm; inside the hard limit; no NaN in position or velocity; speed ≤ 6.0 |
| 2 | Distance to its leash disc center ≤ disc radius + 1e-3, **in every state including flee** |
| 3 | No data (non-debug) creature within 12 m of the checkpoint |
| 4 | Every `creature_strike` is preceded on the same creature by a `creature_tell` exactly 72 ticks earlier, with no other phase in between |
| 5 | Every creature `hit` happens inside its strike or glide, at most once per strike |
| 6 | Every chase lasts ≤ give-up + one attack cycle; every notice ≤ notice + give-up |
| 7 | No stall: in `chase/pursue`, `wander/*` or `forage/seek` for 150 ticks, the creature moved ≥ 0.25 m or changed phase |
| 8 | Engaged on the player ≤ 1 |
| 9 | When a creature first targets the player, `CreatureSenses.perceive` recomputed independently says the player was sensed that tick (or it was hurt by the player) |
| 10 | Health in [0, max]; energy in [0, capacity] |
| 11 | Niche counts equal live non-debug creatures |

**Non-vacuity, over all seeds:** ≥ 10 tells, ≥ 3 give-ups, ≥ 1 hit on the player, ≥ 1 flee.

### `test_checkpoints` (new): "die several times in a row and always return to a fair checkpoint"

1. **Die five times in a row.** `GameSession`, real data, grazer, seed 9090, a scripted driver.
   - **The deaths:**
     1. teleport 2.75 m in front of lair_se's ambush hunter, still → killed by it;
     2. the same at lair_sw;
     3. the same at lair_gap;
     4. park in the middle of z_n → killed by a rammer;
     5. `debug_set_energy(0)` and wait → starved.
   - **After each death:** `resolve_death()`, C7 on disk, then `respawn_after_death()`.
   - **After each respawn, C1–C6:**
     - shelter 5, 8, 10, 10, 10 s (each death within 90 s of the last respawn);
     - energy 0.6, 0.8, 1.0, 1.0, 1.0;
     - no creature within 12 m;
     - no `hit` on and no `creature_noticed` of the player before `grace_until`;
     - points drop by `floor(25%)` each time;
     - 5 new `died` entries: `killed:ambush_hunter` × 3, `killed:rammer`, `starved`;
     - the lineage id and genome JSON are unchanged.
   - **At the end:** the slot reloads with `continue_run` source "primary", the position at the checkpoint, and the 15 save keys.
2. **Quitting at the notice does not skip the death** (`save_on_death = true`). Die, `resolve_death()`, drop the session. A new `continue_run()` finds:
   - the points reduced and `died` in the history;
   - the cell at the checkpoint;
   - 5 s of shelter.

   Slot mtimes are unchanged by the load. **With `save_on_death = false`**, the reload instead finds the pre-death save, which is the step 2 behaviour.
3. **A failed death save is honest.** A file sits where the slot's folder should be.
   - `resolve_death()` returns `saved.ok == false` with an error;
   - the death is applied in memory and `dirty` is true;
   - respawn still works;
   - the quit text is "Your cell's death could not be saved. Quit anyway?"
4. **Not dirty after a saved death.** `_is_dirty()` is false while the notice is open and after the respawn; true after a failed save; true while dead with `save_on_death = false`.
5. **Streak reset:** die, survive 91 s, die → shelter is 5 s again.
6. **Killer ignore.** After the respawn, swim straight back to the killer's lair. It does not notice the player until 30 s after the respawn, and does once that has passed.
7. **Relocation (C2).** Two debug creatures within 12 m of the checkpoint are at their homes after the respawn, with no memory of the player, and `respawned.relocated` names them.
8. **A step 2 save continues** (`save_v2_step2.json`):
   - copied to a temp slot, it continues under step 3 with creatures present;
   - the file bytes and mtime are unchanged by the load;
   - the cell starts sheltered.

### Changed tests

| Test | Change |
|---|---|
| `test_pool_sim` | `test_a_hunter_starving_late_in_a_run_still_finds_carrion` is removed and replaced by threats_sim #22 and slow #30 (D2). All other step 2 tests run without species, unchanged |
| `test_carrion_field` (2 tests), `test_plankton_field` (1) | Build the field from the real config with `interim_supply.enabled = true` set in the test (a `_supply_on()` helper); assertions unchanged |
| `test_pool_layout` | Guard: the real data has `interim_supply.enabled == false` and no initial carrion inside an 8 m territory of z_n, z_nw or z_ne. If OD2 picks the trickle, the first guard changes with it |
| `test_game_session` | Respawn through `resolve_death()` + `respawn_after_death()`. History cause "starved". `dirty` follows test_checkpoints #4. The 15-key test is unchanged |
| `test_sim_purity` | `SIM_FILES += creature_field.gd, species_catalog.gd` (the latter's file read is allowed). New domain files are scanned automatically. `_code_keep_strings()` and the brain scan (#17) |
| `test_ui_text` | `death_title("starved") == "Out of energy"` kept. Adds `death_title("killed", "Caught by an ambush hunter")`; `death_text` containing "(−3)", "generation 1" and "Saved."; `grace_text(5) == "Sheltered 5"`; the attack hints; the failed-save quit text |
| `test_pool_view` | `CreatureView.pose`: neutral at tell 0; coil at tell 1 (z 0.82, jaw 1); puff at tell 1 (scale 1.25, spikes 1); no stretch outside strike. CreatureLayer creates and frees views. A view at alpha 1 is within 1 mm of `PlaneSpace.to_world`. The player view builds a `part_spike` holder. **ViewFootprint vs camera:** 200 sampled plane points; `Camera3D.unproject_position` inside the 1920×1080 viewport implies `ViewFootprint.contains` at zoom 14 and 20 |
| `test_assets` | The 3 new records and their contracts (section 17) |
| `test_placeholders` | The 9 audio entries and the functional entries. No primitives |
| `test_project_settings` | `KEY_ACTIONS += {dev_spawn_threat: [KEY_F9], dev_kill_nearest: [KEY_F10]}` |
| `test_interactions`, `test_actor_state`, `test_ecology`, `test_lineage`, `test_persistence`, `test_genome` | Unchanged; they guard the untouched rules |

### Mutation table (run once by the implementer; results recorded in the PR)

| Mutation | Must fail |
|---|---|
| The brain reads the player position from a field passed in (bypassing senses) | T5 (#16), #17 |
| Homing reintroduced (the strike turns toward the target) | brain #3, threats_sim #2 |
| Tell shortened to 1.0 s in data | `test_species_catalog` (floor), #2 |
| Tell started on the tick of the decision, skipping `aim` | brain #3, #4 natural path |
| EvadeBot reacts on the tell tick (0 latency) | a guard assert in #2 that the reaction tick = tell + 24 |
| Remove the chase timer | brain #4, #19, fuzz 6 |
| Remove the refractory ignore | brain #5, #19 |
| Remove the leash clamp | fuzz 2 or 3 |
| Remove the tell leash guard | brain #13, fuzz 2 |
| Remove the token | #21, fuzz 8 |
| Spawner draws from `region.rng` | T15 (#27) |
| Spawn without the footprint rule | test_creature_field #2 |
| Shelter not set on respawn | test_checkpoints #1 |
| Death applied at respawn instead of at death | test_checkpoints #2 |
| `_is_dirty` compares `motion.position` again | test_checkpoints #4 |
| `sort_custom` without the id tie-break in percepts | test_creature_senses (tie) |
| Burst speed 6.5 in data | `test_species_catalog` (rule 3) |
| Pursue share 0.95 in data | `test_species_catalog` (rule 3), S6 (#5) |
| Knockback without the speed clamp | T10 (#12) |
| A creature hit allowed outside the strike | fuzz 5, #6 |
| A snapshot vector written as `Vector2` | hash coverage (#25) |

---

## 19. Smoke and `check.sh`

### Found phase (grazer, seed 4242), added after the step 2 steps

1. **Frame probe:**
   - creature view count == `sim.creatures.creatures.size()` (7);
   - each view within 1 mm of its sim position at alpha 1;
   - the debug panel shows one AI line per creature, plus the niche and token line.
2. **Caught:**
   - `debug_teleport` the cell 2.75 m in front of lair_se's ambush hunter, facing away, intent zero.
   - Wait for `creature_tell`. During the tell: `Model.scale.z` < 0.95, the eye emission is > 0, and the Lane is visible.
   - Wait for a `hit`: vignette alpha > 0 and the health bar visible.
   - Keep still until `died`: the notice is open with the title "Caught by an ambush hunter" and the tip line.
   - Before Continue, the slot on disk already has the reduced points and history `killed:ambush_hunter` (OD1).
3. **Continue:** the cell is at the checkpoint, the chip reads "Sheltered 5" (then 4), and no creature is within 12 m.
4. **A second quick death, at lair_sw** (lair_se's killer ignores the player for 30 s):
   - wait for the shelter to end, then teleport in front of lair_sw's ambush hunter;
   - assert the death happens within 90 s of the last respawn;
   - Continue → the chip reads "Sheltered 8".
5. **Off-screen indicator:**
   - `debug_spawn_creature("ambush_hunter", cell + (0, 5.8), −π/2)`. That is south of the cell, below the 5.49 m screen edge, facing north and within sight.
   - The cell stays still. After the creature's 3 s settle, wait for `creature_noticed`: the HUD shows one indicator at the bottom edge with the `jaw` glyph.
   - Then `debug_kill_nearest_creature()`.
6. The existing save-and-quit step. `expect.json` gains `"died": 2`.

ForageBot uses `avoid_threats = true` in every bot-driven step.

### Continue phase

- Creature views exist for every site that passes the spawn check from the restored position.
- The player is at the saved position, and the chip reads "Sheltered 5".

### New two-process phases (proving C7 across processes)

- **`--phase=die_and_quit --slot=user://smoke/death.json --seed=4243`:**
  - start a new omnivore;
  - eat two pieces from `debug_spawn_carrion_ahead` (6 points);
  - teleport in front of lair_se's ambush hunter and die;
  - press Quit to desktop from the notice: **no dialog appears** (the death is saved), and the process exits.
- **`--phase=after_death --slot=user://smoke/death.json`:**
  - the Continue card shows 5 points;
  - Continue puts the cell at the checkpoint, history last = `died` / `killed:ambush_hunter`, and shelter is active.

**`check.sh`:**
- adds both runs after the existing smokes, logging to `builds/smoke/*.log`;
- the error-log gate is unchanged;
- the launch smoke is unchanged.

## 20. Performance budget

**Sim (CPU, per tick at 60 Hz).** These are estimates from the base plan's measured unit costs.

| Part | Estimate |
|---|---|
| Step 2 baseline | 172 µs |
| 7 extra `arena.move` | 125 µs |
| 7 `drive` + motion | 30 µs |
| Thinks: 7 creatures at 10–20 Hz, each ≈ 8 distance checks and ≤ 8 LOS tests at 7.6 µs | ≈ 40–70 µs averaged |
| Separation (28 pairs), clamps, combat, metabolism | < 25 µs |
| **Total** | **≈ 400 µs** |

- **Gates:** ≤ 1000 µs with real data (#28) and ≤ 2500 µs with 24 creatures (#29).
- **If over budget, in this order:**
  1. a rock grid for `move`/`settle`/`segment_clear` (pure, in `PoolArena`);
  2. LOS only for the nearest 4 candidates;
  3. think at 6 Hz when idle;
  4. skip `arena.move` for resting creatures with zero velocity.

**Rendering:**
- 7 creatures × (1 body + up to 6 part instances) add about 50 draw calls and about 35k triangles to step 2's under 100 calls and about 70k triangles.
- Creature bodies cast shadows; parts do not.
- Lanes, markers and labels are pooled.
- The perf tour runs with creatures live, and the owner's Windows run records FPS on the RTX 5070 as in step 2.

---

## 21. Build order and cut list

The step is one PR. Agents commit in this order and **push after every commit**. Each commit leaves `tools/check.sh` green.
- Every acceptance proof is green headless by commit 11, before any scene work.
- **OD1 is asked before commit 9.** If the owner has not answered by then, commit 9 builds the recommended option (`SAVE_ON_DEATH = true`) with the fallback compiled and tested, so the answer only flips the constant.

| # | Commit | Contents | Tests added or changed |
|---|---|---|---|
| 1 | Domain foundations | Size rule; `Locomotion.burst`/`glide`; `PoolArena` `settle`/`segment_clear`/`route_point`/`separate`/`rock_contact`/`clamp_to_disc`; ForageBot uses `route_point`; `run_tests` flags | phenotype, locomotion, pool_arena |
| 2 | Senses and footprint | `creature_senses.gd`, `view_footprint.gd` | senses, view_footprint |
| 3 | Brain | `creature_brain.gd` (both behaviors, token flag, `strike_lane`) | creature_brain |
| 4 | Respawn rules | `respawn_rules.gd` | respawn_rules |
| 5 | Species data | `creatures_m1.json`, `species_catalog.gd`, fixtures; `pool_m1.json` supply off and carrion moved; `_supply_on` tests; the late-run hunter test removed; layout guards | species_catalog, layout, carrion, plankton |
| 6 | Creature field | `creature_field.gd` (populate, queue, spawn checks, carcass helper, stuck removal, token list) | creature_field |
| 7 | PoolSim creatures | Species argument, body snapshot, think/drive/motion, move/separate/settle/clamp, creature metabolism and feeding, snapshot and hash, events | threats_sim #14–17, #24–28 |
| 8 | Combat and deaths | Strike windows, player auto-attacks, knockback and clamps, deaths, carcasses, blocked, cancel, dodged, refusals; EvadeBot | threats_sim #1–13, #18–23 |
| 9 | Checkpoints and saving | `checkpoint()`, `position_for_save()`, respawn C1–C6, shelter, concealment, streak, killer ignore, start and continue grace; `GameSession.resolve_death`, `SAVE_ON_DEATH`, dirty | test_checkpoints, game_session |
| 10 | Fuzz | KiterBot, `test_threat_fuzz` | fuzz |
| 11 | Gates | HuntBot, ForageBot `avoid_threats`, slow #29–31. **Data-only tuning commits follow until the gates pass**; the printed numbers go into M1.md | slow tests |
| 12 | Blockouts | `make_m1_threats.py`, `blockout_common` keyword args, 3 assets (`.blend`, GLB, record) | assets |
| 13 | Creature scenes | `creature_view` (pose, lane, marker), `creature_layer`, `pool.gd` routing, spike part, hurt and shelter visuals, 9 audio cues, inventory | pool_view, placeholders |
| 14 | UI | ThreatIndicators, shelter chip, vignette, health bar rule, "Dodged!", hit numbers, death notice reason, tip and save line, attack hints; `main.gd` resolve flow and quit text | ui_text, threat_indicators |
| 15 | Dev layer | AI panel section, gizmos, F9/F10 and buttons, actions | project_settings |
| 16 | Smoke | Section 19, including the two-process phases | smoke |
| 17 | Docs | M1.md step 3 (Bible handoff format, measured perf, gate prints, the mutation table, the carrion note on the step 2 acceptance row); DECISIONS D1–D22; README (no new player keys). The PR body says "exported but not Windows-verified" | — |

**Cut first if late** (in order):
1. the 24-creature stress test (keep the 7-creature cost gate);
2. the `ViewFootprint` spawn rule (keep the 20 m rule and the fade-in; keep the class for the gizmo);
3. hit-number labels and "Dodged!" (the `dodged` event and cue stay);
4. memory and target-line gizmos;
5. the rammer `Hood` animation (the puff is still a whole-body scale and spike raise);
6. the floor lane (pose, sound, "!" and the edge arrow remain);
7. creature hurt flash;
8. the predation-balance slow test (keep it as a dev print).

**Never cut:**
- locked, sim-timed tells and their S5/S6 tests;
- off-screen indicators;
- every give-up reason and nav recovery;
- the token and the hard leash clamp;
- combat only through the resolver;
- C1–C7, the die-five-times test and the death save (or its owner-chosen fallback);
- the debug AI lines;
- determinism, hash coverage, T5 and the static scan;
- the hunter viability gate;
- the Blender blockouts, or listed placeholders if they slip.

## 22. Acceptance mapping

| Item (brief) | Player path | Automated proof |
|---|---|---|
| Two threat behaviors, readable shapes, tells before attacking | South-east or south-west rim: a big flat dark cell turns to watch; swim within 3 m in front and it stops, coils for 1.2 s with a lane, then lunges along it. North zones: a spiked pale cell approaches, puffs for 1.2 s, then charges. Swimming out of the lane on the side the cell faces at the tell escapes | threats_sim #1–8, pool_view poses, smoke "caught", test_assets silhouettes |
| AI states wander, forage, notice, chase, attack, flee, rest; own senses, not your coordinates | Hide behind the north-west rock and nothing notices you. Bump one from behind and it turns | brain #1–12, senses, threats_sim #14–17 (T5, decoy, static scan), fuzz 9 |
| Every chase has a give-up time; **tests: AI give-up and recovery** | Swim away: an ambush hunter stops at its 9 m leash, a rammer at its territory edge | brain #4–5, #12; threats_sim #5, #18–20; fuzz 2, 6, 7 |
| Spawns by niche, not around the player | Kill a rammer: another appears at its patrol site about 30 s later, never in view | test_creature_field #1–3, #5–7; slow #31 |
| Damage and death both ways; carrion comes from kills | A hunter bites a rammer 5 times; 3 meat chunks drop; eat them | threats_sim #9–13, #22; layout guards; slow #30 |
| **Die several times in a row and always return to a fair checkpoint**; short reason; lineage never erased | Get caught: "Caught by an ambush hunter", a tip, −25% points, saved. Continue: sheltered 5 s at the start. A quick repeat gives 8 s | test_checkpoints #1–8; smoke caught/continue; `die_and_quit` → `after_death` |
| Tell food from danger by shape and motion alone | Food is small, round and drifting; threats are big, eyed or spiked, turn to face you and stop before striking | test_assets silhouettes; owner judgement on Windows |
| Debug panel: AI state | F3 in `Pangaea-dev.exe` | Smoke debug lines |
| Save round trips | Quit at the death notice, relaunch, Continue: back at the start with the loss applied | test_checkpoints #2, #8; two-process smoke; test_game_session |

**Owner Windows checklist** (record the commit, resolution and FPS in M1.md):
1. Start a grazer. Swim to the north zone, watch a rammer puff, and swim out of its line on the side you face. Then try leaving its patch during a puff.
2. Swim along the south-east rim and watch the ambush hunter track you. Go within 3 m in front of it, watch the coil and lane, and dodge out of its line on the side you face.
3. Get caught by each threat. Read the title and tip. Continue: "Sheltered 5". Die again quickly at the other lair: "Sheltered 8".
4. Start a hunter. Kill a rammer from behind and eat the chunks.
5. Die, quit at the notice, relaunch, Continue: at the start, points reduced.
6. Let a threat notice you from below the screen edge and check the edge arrow.
7. In `Pangaea-dev.exe`: F3 shows the AI lines and cones, and F9/F10 work. Run `-- --perf-tour` and send the JSON.
8. Answer one question: could you tell food from danger before anything attacked you?

---

## 23. Decisions to record in `docs/DECISIONS.md` (all PROPOSED)

| # | Decision | Owner needed? |
|---|---|---|
| D1 | The interim carrion supply is **off**; carrion comes from kills plus the 3 world-start carcasses. Step 2 D4 said step 3 would do this | No (planned) |
| D2 | Hunter viability is a **slow CI gate** (HuntBot, seeds 201–206, ≥ 5 of 6). Five data knobs are tuned in order within bounds first | Only if it still fails: **OD2** |
| D3 | **Size rule** `Phenotype.derive(..., body_size)`. Size 1 changes nothing; the player is always size 1 in M1 | No |
| D4 | Creature metabolism shares: ambush 10%, rammer 25%. Starved creatures leave no carcass | No |
| D5 | **Combat is automatic on contact** (jaw bites, spikes ram); no attack key | **OD3** (controls) |
| D6 | **Tells are locked lines:** heading locked at tell start toward a capped lead point, no homing, a burst plus glide, started from rest. Both tells are 1.2 s, with a validated floor of 1.2 s. A 0.4 s reaction out of the line on the side the cell faces (a turn of at most 90°) avoids the strike. The other side is not promised: turning all the way round takes longer than the tell, and facing the creature that side is hit from a turn of about 100° (review fix). The probe's head-on approaches (150–210°) are the documented hard case, covered by the notice cue, the lane and the tip | No |
| D7 | **Forgiving two-hit rule:** no single hit reaches 50% of starting health, validated at load | No |
| D8 | **The checkpoint is the generation start** (derived; **no schema change**) | No |
| D9 | Fairness numbers: spawn-safe 20 m plus the zoom-max view footprint, respawn-clear 12 m, shelter 5/8/10 s, respawn energy 0.6/0.8/1.0, streak window 90 s, killer ignore 30 s, start and continue shelter 5 s | No |
| D10 | Geography: rammers guard the rich north zones (z_n ×2, z_nw, z_ne). Ambush hunters sit on the south-east and south-west rims and in the north-west gap, at the moved, pinch-free sites. z_center, z_s, z_se and z_sw are unguarded; the spawn is unreachable by any leash | No |
| D11 | AI rates and senses: think at 10 Hz idle and 20 Hz engaged (staggered); drive every tick from memory; FOV, LOS, near sense, pain and bounded memory; no LOD in M1 | No |
| D12 | The player's death leaves no carrion | No |
| D13 | Body separation is positional only, split by inverse mass | No |
| D14 | Knockback on hits (data); speed clamped to 6 m/s after any hit | No |
| D15 | Species live in a separate `creatures_m1.json`; `PoolLayout`'s schema is unchanged | No |
| D16 | Creatures, streaks and shelter are **not saved**; continue repopulates from the encounter seed and gives 5 s of shelter | No |
| D17 | Debug spawns bypass niche caps. A stuck creature is removed and respawned out of view | No |
| D18 | History death causes are `"starved"` or `"killed:<species id>"` | No |
| D19 | The world-start carrion moves to (±10.5, −4.5), out of the rammer territories (noted on the step 2 acceptance row) | No |
| D20 | **Escape and leash rules:** pursuit ≤ 0.9 × the slowest fed body (validated); a hard leash clamp after every move; no tell whose lane leaves the leash; data rules for checkpoint discs, leash bands and pinch points | No |
| D21 | **Engagement token:** at most 1 creature in chase or attack against the player (forgiving preset, data) | No |
| D22 | Body-only blockouts with runtime part placement; no composite species GLBs | No |

## 24. Owner decisions

Each one changes what the approved brief says, or could. The plan builds and ships with the **recommended** option, and each alternative is one constant or one data change, already wired and tested.

### OD1. Save the death at once, with the player at the checkpoint

- **What changes:** the game writes the save slot when the cell dies (the same temp, verify and backup path). That is a write trigger beyond the brief's "autosave on each generation".
- **Why:** in step 2, choosing "Quit without saving" at the death notice skipped the death and its point loss (step 2 D5). With threats, deaths are common, and "always return to a fair checkpoint" should not be skippable. The write contains only what the run already owns: points minus a quarter, one history entry, and the position at the checkpoint.
- **Options:**
  - **(A, recommended) Save at death.** `SAVE_ON_DEATH = true`.
  - **(B) Keep step 2's behaviour:** nothing is written until the player saves, and quitting without saving discards the death. `SAVE_ON_DEATH = false`.
- **Effect on the build:** both paths are compiled and tested (test_checkpoints #2–4). The quit text follows the choice (section 13).
- **When:** asked before commit 9. Without an answer by then, (A) is built and the answer only flips the constant.

### OD2. Hunter fallback, raised only if the viability gate fails after data tuning

**Trigger text** (to send if it happens):

> The hunter-viability gate still fails after tuning rammer respawn, carcass sizes, carrion lifetime and rammer flee to their bounds (seeds 201–206 results attached). Choose:
> - **(A, recommended)** re-enable a slow interim carrion trickle: `interim_supply.enabled: true`, interval 30 ± 5 s, `max_live` 4, placed in zones. This is a data change with no code.
> - **(B)** accept that hunter lineages are harder in M1. The gate becomes a printed report, and the start screen hunter card adds "Hunters must hunt to eat."

**Why (A):** the brief says carrion comes from kills. A small trickle keeps that true in spirit while guaranteeing that a new hunter lineage is playable.

### OD3. Combat on contact, with no attack key

- **What it is:** a controls choice, not in the brief's text. Jaws bite and spikes ram automatically when the resolver allows it. No new key, so Space and right mouse stay unbound.
- **Options:**
  - **(A, recommended) Keep it.** It uses the step 1 resolver unchanged and the editor preview already describes it. Step 4's editor makes part placement the skill.
  - **(B)** Add an attack key in step 4 through the same resolver path.
- Recorded as D5.

---

## 25. Risks

| Risk | Early warning | Response |
|---|---|---|
| The real brain does not reproduce the probe geometry (think latency, braking before the tell) | threats_sim #4 (natural path) fails while #2–3 pass | `tell_start_max_speed`, `standoff_m` and `aim_deg` in data; tells may lengthen, never shorten (floor 1.2 s) |
| Hunters cannot live on kills | Slow #30 fails | The five knobs in order (section 10), then OD2 |
| Threats feel toothless (sated ambush hunters only watch; the token limits pressure) | Owner checklist; few deaths in play | Hunger thresholds, metabolism share, `start_max_m` (≤ 3.0 by probe) and `max_engaged_on_player` are data. Raise pressure by hunger, not by shortening tells |
| Emergent predation empties a niche, or the pool turns chaotic | Slow #31 prints; owner says "nothing to hunt" | Prey radius share, refractory and leash in data |
| A tell is readable in the sim but not on screen | Owner cannot see the coil from the camera | Pose amplitudes are view constants; the lane, eye glow, positional cue and edge arrow are redundant channels |
| Head-on approaches feel unfair | Deaths cluster on players swimming into threats | The documented hard case (D6). The notice cue and watch phase come first; the tip says to swim out of its line on the side you face. The `start_min_m` and aim data can narrow it further |
| GDScript cost grows with creatures | #28 above 600 µs | The rock grid first (section 20) |
| Determinism drift (Vector2 in snapshots, dictionary order, unstable sorts) | #24 or #25 fails | `_pair` everywhere, sorted dictionaries, id tie-breaks, per-creature seeds |
| Separation jitter against rocks with several bodies | Visible shiver in the smoke frame probe | One separation pass, then `settle`, then the clamp. The band rule keeps the clamp off rocks |
| The death save fails on a user's disk | The notice shows "Could not save" | Honest in memory and dirty; the quit prompt warns; backup rotation unchanged |
| Test runtime creeps up | CI over 4 minutes | `--skip-slow` for local loops; slow tests are capped at about 2 minutes in total |
| A conflict with the running step 2 review | Rebase conflicts in `hud.gd` or `main.gd` | Additive edits only; rebase onto whatever lands |
| Auto-combat feels passive | Owner feedback | OD3(B) in step 4 |

## 26. Out of scope

- Reproduction, the editor, spawning spots and schema v3 (step 4).
- More species, more habitats, schooling, and creature populations or creature saving.
- Final art, rigs, real audio and creature animation clips (step 5).
- LOD scheduling and a pathfinding grid (re-routing around single rocks is enough for this pool).
- Settings UI for flashing or reduced motion, controller support and remapping.
- New dependencies, network calls or runtime AI.

## 27. Constraint check

| Constraint | Status |
|---|---|
| `game/domain` purity | Kept. Four new pure domain files, scanned by `test_sim_purity` |
| Deterministic, headless-testable sim | Kept. Integer ticks, seeded streams, id tie-breaks; every acceptance proof is headless |
| Scenes only draw and send intents | Kept. Views read sim phases and events. The lane comes from `strike_lane()` |
| `game/dev` debug-only, no `class_name`, excluded from the release exe | Kept. All bots and dev tools live there |
| Save safety | No schema change (v2, 15 keys). The death save uses temp, verify and backup. No rewrite on load (test_checkpoints #2, #8) |
| Placeholders | Only synthesized audio and functional UI, each with an inventory entry. Bodies are Blender blockouts |
| Numbers | Every number is PROPOSED and lives in `creatures_m1.json`, `pool_m1.json` or top-of-file constants (`MIN_BODY_SIZE`, `SAVE_ON_DEATH`, pose amplitudes) |
| One PR with a Windows build from CI; push after every commit | Section 21 |
| Brief and vision changes | Only OD1 (a write trigger), OD2 (conditional) and OD3 (controls), each with a recommendation and a buildable default |
| Naming and sources | Generic role names; nothing from Spore, EA or Thrive; no GPL code |
| Verification status | CI exports are reported "exported but not Windows-verified" until the owner runs the checklist |
| `wt/plan3`, the repository | Not modified by this planning work; probes ran only in `scratchpad/p3-synth` with its own `XDG_DATA_HOME` |

## 28. Contradictions resolved

| # | Contradiction | Resolution and reason |
|---|---|---|
| 1 | **Tell length.** Sim 0.7/0.9 s; judges suggested about 1.0 s lunge and 1.0–1.2 s puff with a floor ≥ 0.8 s; player 1.0/1.2 s | **1.2 s for both, floor 1.2 s.** In my probe a 1.0 s lunge still hit 2–3 fed reacting cases per body; 1.2 s gave 0. A 1.0 s puff failed at 3–3.5 m |
| 2 | **Lead.** One judge wanted `lead_cap_s = 0` (purely locked); another wanted a capped lead point, because a pure lock misses grazers | **A capped lead point** (1.0 m lunge, 1.2 m charge) and **no homing.** The probe hits non-reacting perpendicular grazers 6/6 and misses all fed 24-tick reactors |
| 3 | **Escape bound.** Fed (0.9 × 2.72) or starving (0.9 × 1.36) | **Fed**, validated. A starving cap (1.22 m/s) makes threats catch only still players, which a judge flagged as toothless. Starving bodies are protected by the lane geometry, give-up and leash (S6, all 3 bodies) |
| 4 | **"Engaged".** Sim counted notice and flee; risk counted chase and attack | Chase and attack against the target. Watching is not engagement, so creatures stay present without dogpiling |
| 5 | **Spawn distance.** Sim 20 m; player and risk 12–18 m plus the view footprint | 20 m **and** the zoom-max footprint at 2.4:1 (a corner reaches 31 m). The footprint is cuttable, the 20 m rule is not |
| 6 | **Lair sites.** Sim lairs at (±25.8, 14.9) and (−9.6, −16.6) | Moved to (26.4, 12.6), (−24.1, 16.6) and (−9.4, −16.3) by new data rules 9 and 10 (rock_14 and rock_16 pinches, rock_12 cutting the lair_gap leash). Mirror-symmetric rim sites free of pinches do not exist with a 9 m leash, so the two rims differ slightly |
| 7 | **Ambush size.** One judge suggested 1.6 to be truly slower | **1.5 is kept.** At 1.6 the radius equals the bite limit for a 0.5 cell exactly; the escape guarantee comes from the validated pursuit share (0.85), not from size |
| 8 | **Rammer size.** Sim 1.0; player 1.2 | **1.25 with spike scale 0.8.** Size 1.2 with full spikes stacks 17.28, breaking the two-hit rule; 1.25 × 0.8 keeps 14.4 and reads bigger than the player |
| 9 | **Notice cue.** Sim 0.35 s; player 0.5 s | **0.5 s**, with a validated floor |
| 10 | **Lunge start.** Sim ≤ 3.6 m; player ≤ 3.0 m | **[2.5, 3.0] m from rest**, approached through a stand-off point. 2.0 m starts degraded in the probe |
| 11 | **Quit while dead after a saved death.** Risk showed a dialog saying "already saved"; others none | **No dialog.** A saved death is not dirty, and step 2 shows the dialog only when dirty. The notice says "Saved."; a failed save gets its own dialog |
| 12 | **Saving while hunted.** Risk refused `save_now` while hunted | **Rejected.** It blocks Save & Quit with no autosave behind it; the death save covers the exploit |
| 13 | **`session.step()`** (risk) | **Rejected.** The pool keeps stepping the sim as in step 2; GameSession only resolves deaths and saves |
| 14 | **Layout schema 2 for niches and homes** (player) | **Rejected.** Fixtures are schema 1 and validated by name; data lives in `creatures_m1.json` |
| 15 | **Float-second timers** (player) | **Rejected.** 1/60 accumulation reaches 0.5 s on tick 31; integer ticks everywhere |
| 16 | **Composite species GLBs** with a data hash (player) | **Rejected.** Any tuning would fail CI until Blender re-ran; body-only blockouts instead |
| 17 | **"Respawn remains"** (player) | **Rejected.** The player's death leaves no carrion (D12); the respawn energy ladder breaks starvation loops instead |
| 18 | **Ambush hunter in a rammer territory.** Player: the rammer flees from it; sim: the rammer attacks it | **Attack** (sim). Predation both ways produces carrion and is bounded by give-up rules; slow #31 watches the balance |
| 19 | **Symmetry proof.** Sim: decoy test; risk: T5 invariance; one judge: make the decoy optional | **Both**, with T5 primary. The decoy gets a specified harness so it is meaningful, not optional |
| 20 | **Supply-off test.** Sim deleted the late-run hunter test; the moved carrion must keep the worst-point test | The late-run test is replaced by #22 and the slow gate; the worst-point test stays and passes (verified) |
