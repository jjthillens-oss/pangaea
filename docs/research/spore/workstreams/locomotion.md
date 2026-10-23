# Workstream C: locomotion, anatomy-driven movement and procedural animation

Status: PROPOSED research, 2026-10-23. Nothing here is approved for the game, changes `game/`, or starts a
prototype. Labels (CONFIRMED, OBSERVED, HYPOTHESIS, PROPOSED) are defined in `../LEGAL_RESEARCH_BOUNDARIES.md`; source IDs
S1–S16 are defined in `../SPORE_RESEARCH.md` §3. New, non-Spore sources get IDs L1–L17 in §1.2 so they cannot collide with
S-numbers that other workstreams add.

This file builds on `../PROCEDURAL_ANIMATION_SPEC.md`, the animation spec. It does not replace that spec. Where the two
differ, this file says so and explains why. It is input for the owner's review. An implementation agent would receive only
the reviewed specification parts (§3–§6 "Spec", "Interfaces", "Tests") and the public sources in §1.

## 0. Question, method and limits

**Question.** How do limb length, number of legs and body proportion affect movement? How do foot placement, gait timing,
turning, slopes and animation transitions work in Spore, and which parts are documented, inferred or unknown? How does
anatomy feed abilities and stats? What original GENESIS designs follow?

**Method.**

1. Read S1 (Hecker et al. 2008) in full from a text copy of the author's PDF, and cross-checked it against the
   project's earlier summary.
2. Re-read the project's research files, `game/domain/locomotion.gd` and `game/domain/phenotype.gd`. Both were read
   only and not modified.
3. Searched public biomechanics and game-animation literature (§1.2).
4. Ran two scratch probes in GDScript on the pinned Godot 4.7.2 headless build. They live in the session scratchpad, not
   the repository, and are reported as OBSERVED:
   - the gait arithmetic of §2;
   - a solver micro-benchmark for §6.
5. Checked every Godot class and property named here against the pinned binary with `ClassDB` (§7.4).

**Limits.**

- No Spore files, mods, modder format documents or recordings were used. No owner recordings exist yet, so every
  statement about Spore's *visible* behaviour is either from a published source or a planned measurement.
- S2 (GDC 2007 talk page) and S7 were still unreachable on 2026-10-23 ("The site is temporarily down"). Several
  academic sources were read only as abstracts or secondary summaries. §1.2 says which ones.
- I am one workstream. I did not spawn further agents, and I edited only this file.

## 1. Evidence index

### 1.1 Spore sources used (IDs from `SPORE_RESEARCH.md`)

| ID | Kind | What it establishes for locomotion | Read |
| --- | --- | --- | --- |
| S1 | Developer paper (primary) | §4.2 Gaits, §4.3 Particle IK, §4.4 Jiggles, §3.2.2 movement modes (LimbLength, ground-relative), §3.1.2 game code uses the same semantic queries, §5 tests, cost and limitations | In full |
| S2 | Developer talk page | Earlier version of S1, including failures | Site down; not read |
| S11 | Community wiki (secondary) | Speed and abilities come from leg and other parts in levels | Via existing project notes only |
| S13 | Journalist quoting developers (secondary) | "Walking ratio" from leg count, length and symmetry; footfall rhythm uses torso and head size; legless creatures slither | Via existing project notes |
| S14 | Spore designer essay (secondary, first-hand) | Creature-stage part stats did not depend on limb length or placement | Via existing project notes |

### 1.2 Public locomotion literature and talks (not Spore; general knowledge, reimplemented in our own words)

| ID | Source | Kind | What it establishes for us | Read |
| --- | --- | --- | --- | --- |
| L1 | R. McN. Alexander, *Principles of Animal Locomotion*, Princeton UP, 2003 (cited by S1 for duty factor) | Textbook | Duty factor definition; gait vocabulary | Not read; cited through S1 |
| L2 | Alexander & Jayes, "A dynamic similarity hypothesis for the gaits of quadrupedal mammals", *J. Zool.* 201:135–152, 1983 | Paper | Animals of different size move alike at equal Froude number Fr = v²/(g·h) (h = hip height). Holds better for cursorial than non-cursorial mammals. | Secondary summaries (search results: <https://www.sfu.ca/locomotionlab/assets/dynsimwalk1997.pdf>, <https://cob.silverchair.com/jeb/article-pdf/203/16/2405/2607282/jexbio_203_16_2405.pdf>) |
| L3 | Alexander, "Estimates of speeds of dinosaurs", *Nature* 261:129–130, 1976 | Paper | Empirical fit: relative stride (stride / hip height) ≈ 2.3·Fr^0.3 | Secondary only (<https://www.sjsu.edu/faculty/watkins/alexander.htm>, which writes the relation the other way round; volume and pages unverified). Use as a plausibility curve only. |
| L4 | Heglund & Taylor, "Speed, stride frequency and energy cost per stride: how do they change with body size and gait?", *J. Exp. Biol.* 138:301–318, 1988 | Paper | Across 16 species (30 g to 200 kg), equivalent speeds scale about M^0.2 and stride frequency about M^−0.15. Mass-specific cost per stride is about constant, so cost tracks stride frequency. | Abstract (<https://cob.silverchair.com/jeb/article-split/138/1/301/5532/Speed-Stride-Frequency-and-Energy-Cost-Per-Stride>) |
| L5 | Hoyt & Taylor, "Gait and the energetics of locomotion in horses", *Nature* 292:239–240, 1981, DOI 10.1038/292239a0 | Paper | Gait changes near the speed where the energy curves cross | Abstract and later citations |
| L6 | Farley & Taylor 1991 ("force trigger" for trot–gallop) | Paper | Competing explanation for L5: gait change tracks musculoskeletal force | Cited in L5 search results only |
| L7 | Hildebrand, "Symmetrical gaits of horses", *Science* 150:701–708, 1965, DOI 10.1126/science.150.3697.701 (DOI from reference lists) | Paper | Gaits described by duty factor and the phase of fore versus hind footfall; the standard gait diagram | Citation only |
| L8 | Wilson, "Insect walking", *Annu. Rev. Entomol.* 11:103–122, 1966 | Paper | Metachronal gait: on each side, steps pass back to front; tripod at speed | Citation only |
| L9 | Cartmill, Lemelin & Schmitt, "Support polygons and symmetrical gaits in mammals", 2002 (<https://www.originalwisdom.com/wp-content/uploads/bsk-pdf-manager/2019/10/Cartmill-et-al_2002_Support-polygons-and-symmetrical-gaits-in-mammals.pdf>) | Paper | Static stability analysed through support polygons over the gait cycle | Title and listing only |
| L10 | Karim, Gaudin, Meyer, Buendia, Bouakaz, "Procedural locomotion of multilegged characters in dynamic environments", *Comput. Animat. Virtual Worlds* 24(1):3–15, DOI 10.1002/cav.1467 (<https://hal.archives-ouvertes.fr/hal-01352977>) | Paper | Fully procedural n-legged locomotion built from four modules: controller, gait/tempo manager, 3D path, footprint planner. Level of detail allows dozens of creatures. | Abstract (sources give 2012 or 2013) |
| L11 | R. S. Johansen, "Automated semi-procedural animation for character locomotion", MSc thesis, Aarhus, 2009 (<https://runevision.com/thesis/>) | Thesis | Adapting example cycles to speed, turning and terrain with IK; the "footbase" heel+toe constraint; ground height for weight | Summary page |
| L12 | D. Rosen, "An Indie Approach to Procedural Animation", GDC 2014 Animation Bootcamp (<https://gamedeveloper.com/design/video-an-indie-approach-to-procedural-animation>) | Talk | Very few keyframes plus procedural layering for fluid, interactive motion (Overgrowth) | Description only |
| L13 | J. Jakobsson and J. Therrien, "Rain World Animation Process", GDC 2016 Animation Bootcamp; designer account in Game Developer (<https://gamedeveloper.com/design/crafting-the-complex-chaotic-ecosystem-of-i-rain-world-i->) | Talk / interview | Bodies are points held at set distances, skinned with part sprites. The bodies are soft and adapt to any terrain. | Interview summary |
| L14 | T. Jakobsen, "Advanced Character Physics", GDC 2001 (cited by S1 as the basis of its length correction) | Talk / paper | Verlet particles with iterative length-constraint relaxation | Not re-read in this pass |
| L15 | Aristidou & Lasenby, FABRIK, *Graphical Models* 73(5), 2011 | Paper | The algorithm behind Godot's `FABRIK3D` | Already in `../../open-source-scout.md` |
| L16 | "IK-driven procedural spider locomotion in Godot 4.5", 80.lv, 2025-12-17 (<https://80.lv/articles/ik-driven-procedural-spider-locomotion-in-godot-4-5>) | Tutorial | Reactive stepping: raycast foot spots, step when drift passes a threshold, arc the foot, alternate pairs, body height from the feet. The code's license is not stated, so we take the idea only. | Already in scout |
| L17 | M. Raibert, *Legged Robots That Balance*, MIT Press, 1986 | Book | Neutral-point foot placement: a foot placed half a stance length ahead of the hip balances the body at steady speed | Citation from general knowledge; not re-verified online in this pass |

Status of these sources: academic results are facts about animals and robots, not about Spore. Public availability
does not license code, and none of these sources is code. We use only ideas and published equations.

### 1.3 Scratch probes (OBSERVED, not in the repository)

| ID | Probe | Result |
| --- | --- | --- |
| X1 | `gaitmath.gd`: Froude-scaled gait table on legs of 0.25, 0.5, 1 and 2 m | Stance sweep / reach ratio is identical for every leg length (1.02 walk, 1.07 trot, 0.94 run with the trial numbers). Speed scales as √L. See §2. |
| X2 | `pbd_bench.gd`: length-constraint relaxation in GDScript, 60 constraints × 8 iterations | 75 µs per creature-frame for the inner loop only, on an Intel Xeon 2.1 GHz, Godot 4.7.2 headless. See §6. |
| X3 | `probe*.gd`: ClassDB checks | See §7.4 |

## 2. Cross-cutting finding: one dimensionless gait table can serve every leg length

This is a GENESIS design result (PROPOSED). It comes from L2/L3 and our arithmetic, not from Spore.

The numbers are taken in units of the leg's own size:

- Froude number Fr = v²/(g·h), where h is hip height;
- relative stride λ = stride/h;
- duty factor β.

A gait table written in these units gives every body the same *shape* of motion. Only the scale changes. X1 shows three
consequences:

1. **Foot slip becomes a single inequality per speed band, independent of size.** A stance foot sweeps β·λ·h behind the
   hip. The leg can sweep at most 2·√(L² − h²) at hip height h = c·L. So no-slip is feasible exactly when
   β·λ·c ≤ 2·√(1 − c²). This holds for all leg lengths at once.
   - With the trial values (c = 0.9, β = 0.65/0.45/0.30, λ from L3), the ratio came out at 1.02, 1.07 and 0.94, so walk
     and trot slightly over-reach.
   - The table therefore needs a lower stance height at speed (crouch, c ≈ 0.85) or smaller β·λ. This is a tuning fact
     we found before building anything.
2. **Speed scales as √(leg length).**
   - At equal Fr, a 2 m leg moves √2 ≈ 1.41× faster in metres per second than a 1 m leg.
   - In *body lengths per second* it moves 1/√2 ≈ 0.71× as fast. For example, at the trial walk: 0.25 m legs gave
     2.97 L/s and 2 m legs gave 1.05 L/s.
   - Long legs are faster over the ground, and small creatures look quicker. Gameplay must decide which unit the player
     feels (§5).
3. **Cadence scales as 1/√(leg length).** In X1, walk cadence went from 2.18 Hz at 0.25 m to 0.77 Hz at 2 m. This
   matches the direction of L4: small animals take more strides per second.

Gameplay can tune the overall feel with one constant, an effective gravity g_eff, without breaking any of the
relations above.

## 3. System 1: gait and foot placement

### 3.1 Observed behaviour and evidence

- CONFIRMED (S1 §4.2):
  - A leg is a path from a foot body (leaf) to a spine body (the "hip").
  - Legs are "clustered into one or more groups of roughly equal length". The groups' length ratios are approximated
    by "small rational numbers", which set relative cycle frequencies.
  - Feet on each hip are ordered. Each foot gets a duty factor (citing L1) and a step trigger, which is a phase offset.
  - "Hips are translated and rotated as the feet are moved."
  - The swing path is authored in a normalised space and scaled by leg length.
  - Animators authored speed→parameter mappings for groups of 1–6 feet; groups of 7 or more feet are generated
    procedurally.
  - Several gait styles can be layered at once (limp, lumbering), and different groups can use different styles at the
    same time ("two short legs could be running while four long legs are trotting").
  - The gait system exists so that "feet not slip".
  - Footless characters float or crawl, chosen by a heuristic. Crawlers turn spine bodies into pseudo-feet with an
    inchworm gait.
  - The gait system is separate from the retargeting system "for historical reasons".
- CONFIRMED (S1 §5): the editor starts animating as soon as feet, mouths or graspers are added.
- OBSERVED (S13, secondary):
  - a "walking ratio" from leg count, length and symmetry ("twice as many legs on one side gives one to two");
  - footfall rhythm takes torso and head size into account;
  - legless creatures slither.
- OBSERVED (S11, secondary): movement speed comes from leg parts in levels.

### 3.2 Documented, inferred, unknown

| Documented (S1) | Inferred (HYPOTHESIS, not Spore fact) | Unknown (needs recording or stays unknown) |
| --- | --- | --- |
| Leg = foot-to-hip path; length clustering; rational frequency ratios; duty factor and step trigger per foot; speed-interpolated parameters for 1–6 feet, generated for 7+; normalised swing arc scaled by leg length; float/crawl fallback | Rational ratios are probably used so the combined pattern repeats with a short period. Matching *length* ratios to frequency is what a shared body speed needs when stance sweep is proportional to leg length (§3.3 rule 3). We do not know that this was Spore's reason. | Clustering tolerance; ratio set; the generation rule for 7+ feet; how foot targets are chosen (prediction versus reaction); whether Spore's stride follows leg length (R302); foot order (R308); visible slip (R309); group step ratio as seen (R310); what S13's "torso and head dimensions" changes |

### 3.3 Specification (plain language, implementation-independent; PROPOSED)

1. **Legs and groups.** A leg is a chain from a foot-capable end to its first spine joint. Legs whose effective reach
   differs by less than a tolerance form a group. Every group has one cycle clock.
2. **Scaled table.** Gait parameters are stored per speed band in leg-relative units: Fr range, duty factor, relative
   stride, swing lift as a share of leg length, and phase pattern. The same table serves every size (§2).
3. **Shared body speed.**
   - All groups move one body, so at a given speed each group's cycle period is set by its own reach. Short legs cycle
     proportionally faster.
   - The period ratio between groups snaps to a ratio of small integers (≤ 4) so the pattern repeats.
   - The rounding error is absorbed by adjusting that group's duty factor, within limits.
4. **Phase pattern.** Phases are generated, not hand-tabled per leg count:
   - left and right partners are half a cycle apart at walk and trot;
   - along each side, steps travel back to front (L8), spaced evenly;
   - at walk, the planner checks that the body's ground projection stays inside the stance-foot polygon with a margin
     over the whole cycle (L9), and raises duty factor if it does not.
   - One- and two-legged bodies are exempt from the static check and use a dynamic-balance rule (lean into the step).
5. **Foot target.** When a foot lifts, its landing spot is predicted, not reacted to:
   - first, predict the body pose at the middle of the foot's next stance from the current velocity and turn rate;
   - then place the foot under its hip's rest spot in that predicted pose (the L17 neutral-point idea);
   - then project the spot onto the ground.
6. **Safety trigger.** A stance foot also lifts early if it is stretched past its reach, or if its spot becomes invalid
   (ground lost, blocked). A foot never stays planted beyond reach. It steps, and the step is counted (test 3.7.3).
7. **Swing.** The foot follows a normalised arc scaled by leg length and lifted to clear the highest ground between take-off
   and landing. Landing lasts at least one tick at zero foot velocity.
8. **Stance.** A planted foot does not move in world space. The body moves over it.
9. **No feet.**
   - Floaters use the swim or hover oscillator (the M1 approach).
   - Crawlers assign pseudo-feet along the spine at even spacing and run a travelling wave. The wave speed comes from the
     same table, with spine segment length as "leg length".
10. **Speed is set by anatomy.** Locomotion never asks for a speed that needs a cadence above the table's top band. This
    is the link to §5.

### 3.4 Implementation options

| | A. Phase-clock planner (domain) + Godot IK modifiers (scene) | B. Reactive stepper (L16 pattern) + Godot IK | C. Hybrid: A's clocks, B's safety trigger and re-plan |
| --- | --- | --- | --- |
| How | Pure deterministic planner computes phases and predicted landing spots each fixed tick; scene writes IK targets | Each foot steps when it drifts past a threshold from its rest spot under the hip; pairs alternate by a lock flag | A, plus rules 3.3.6 and re-planning a landing spot mid-swing when ground changes |
| Foot slip | None by construction while the command is inside the speed and turn envelope (§5.3) | None while planted; feet can lag far behind in fast turns, then several step at once | None, with a bounded catch-up |
| Rhythm and style | Clear, tunable gaits (walk vs trot visibly differ); matches dimensionless table | Emergent, often "skittery"; no gait identity; cadence depends on the threshold, not the table | Same as A |
| Odd bodies (3 legs, mixed lengths, 10 legs) | Needs the group and ratio logic and the static-stability check; generated phases cover any count | Handles any count trivially, but may lift too many feet at once and drop the body | Robust |
| Determinism | Fully deterministic (domain test) | Deterministic if run in the domain at a fixed tick; order effects possible | Deterministic |
| Cost | O(feet) per tick; tiny | O(feet); tiny | O(feet) plus occasional re-plan |
| Tuning effort | Medium: one table plus a few constants | Low at first, high to make it look intentional | Medium |
| Recommendation | | | **Use C**, built as A first. B's trigger becomes the safety rule. |

### 3.5 Interfaces and data (see §7 for the consolidated list)

- `GaitTable` and `GaitPlanner` (domain), with data in `game/data/gaits.json`. That file was already named by the animation
  spec; this design redefines it in Fr units, which is a change from the animation spec §3.2 "per speed band".
- `FootState`: phase, in_stance, plant, target, swing_t, lift.
- Ground access is injected as a `Callable` sampler, so the domain never touches the scene.

### 3.6 Performance risks

- The planner is cheap.
- The cost lies in ground queries: one ray per landing prediction, about 1–3 per foot per second. That is small.
- Re-planning on moving ground (rafts, other creatures) is out of scope for the first prototype.

### 3.7 Acceptance tests (PROPOSED numbers)

1. Slip: the animation spec §6 item 2 (< 2% of leg length per stance), measured in the scene.
2. Domain:
   - planned stance sweep ≤ reach for every foot, band and test body;
   - for every phase sample, the projection of the centre of mass lies inside the stance polygon with margin ≥ 5% of hip
     height at walk, for bodies with ≥ 4 legs.
3. Safety-trigger steps are counted. Fewer than 1 per 10 s in straight walking; any count allowed during 180° reversals.
4. Determinism: two runs with the same body, command script and seed give byte-identical foot logs.
5. Scaling:
   - for two bodies identical except for leg length ×2, planned top walk speed differs by √2 ± 3% and cadence by
     1/√2 ± 3%;
   - this follows from §2 and is checked in the domain.
6. Contact sheet of the test-body matrix (animation spec §6 item 1) walking at each band.

### 3.8 Unsupported configurations (first version)

- Legs attached to other legs (branching legs). S1 supports them; we postpone.
- Feet above the hip (legs pointing up).
- Legs whose rest pose already exceeds reach on flat ground.
- A body whose centre of mass lies outside every possible support polygon: it is flagged in the editor and gets a
  "drag/crawl" fallback.
- More than 12 feet. Allowed by the geometry spec limits only if the static check passes.

## 4. System 2: turning, slopes and transitions

### 4.1 Observed behaviour and evidence

- CONFIRMED (S1 §4.2): the characters walk "across uneven terrain and along curved paths with discontinuous input
  velocities". Gait parameters are interpolated by movement speed. Hips translate and rotate with the feet.
- CONFIRMED (S1 §5, future work): "The gait system's biggest challenge is how to provide believable locomotion with
  anticipation in the face of discontinuous player and code inputs." Starts, stops and sudden turns were the
  developers' own open problem.
- CONFIRMED (S1 §3.2.2): a ground-relative movement mode keeps authored ground contact on any body height. This is for
  clips such as pounding the ground, not for gait.
- S1 says nothing about slopes beyond "uneven terrain", nothing about turn radius and nothing about swimming or
  swim-to-walk transitions.
- Biology (L5, L6): gait changes happen around particular speeds, for energy or force reasons. Animals of different size
  change gait at similar Fr (L2). Exact thresholds were found only in secondary summaries, so they are tuning starting
  points, not facts.

### 4.2 Documented, inferred, unknown

| Documented | Inferred (HYPOTHESIS) | Unknown |
| --- | --- | --- |
| Curved paths, uneven terrain and discontinuous input are handled; speed-interpolated parameters; anticipation was an unsolved issue | Hip rotation "as the feet are moved" suggests the body pose follows the feet, not only the reverse. Speed-interpolated parameters suggest no discrete walk/run state machine for gait. | Turn radius (R304); turning in place; start and stop timing (R303); slope effects on speed and pose; behaviour at water edges and in water for the Creature stage; whether stops plant all feet; idle foot shuffles |

### 4.3 Specification (PROPOSED)

**Turning**

1. The body's command is a pair (forward velocity, yaw rate), clamped to the anatomy's *reach envelope* (§5.3) before it
   reaches the planner. The planner never receives a command its feet cannot follow.
2. Landing spots come from the predicted pose (§3.3 rule 5), so on a curve the inner feet take shorter steps and the outer
   feet longer ones.
3. Turning in place is a valid command (zero forward speed). Feet step around the pivot, and the pivot is the centre of
   mass.
4. Turn rate limit:
   - each foot at horizontal distance r from the pivot sweeps r·ω·(stance time) during stance;
   - so the safe yaw rate is the smallest sweep_max/(r·β·T) over all feet.
   - Long bodies with far-out feet turn slower. This is a geometric result, not an arbitrary penalty, and it agrees with
     the animation spec §4 "wide stance turns slower" while explaining *why*.

**Slopes and uneven ground**

5. Each landing spot is projected onto the ground (ray along gravity from above the predicted spot).
6. Body height is the mean stance-foot height plus stance height. Pitch and roll come from a plane fitted to the
   stance feet. Both are rate-limited per tick.
7. The swing arc lifts to clear the highest sampled point between take-off and landing, plus clearance.
8. Gameplay effect (PROPOSED design, §5):
   - uphill top speed drops with slope;
   - downhill top speed is capped for stability;
   - beyond the body's static tipping angle (§5.3) the creature cannot stand still on the slope and slides or refuses
     that heading.

**Transitions**

9. *One clock, no resets.* Each group's phase runs continuously. Walk, trot and run are regions of one Fr axis.
   Parameters (duty factor, stride, lift) are interpolated by Fr.
10. *Pattern changes at foot boundaries.* Phase patterns (offsets) differ between bands. Interpolating offsets can pass
    through ugly patterns. A foot therefore adopts the new offset only at its next lift-off, and band changes use
    hysteresis (PROPOSED ±10% in Fr) so a creature at a boundary speed does not flicker.
11. *Start.*
    - The foot under most strain lifts first.
    - The body leans in the travel direction by a small angle that grows with acceleration. This is our answer to S1's
      "anticipation" gap.
    - Acceleration is limited by anatomy (§5).
12. *Stop.*
    - Swings in progress finish.
    - Then each foot further than a threshold from its rest spot takes one settling step, in phase order, at most one
      step per foot.
    - Then idle.
13. *Idle.* Feet stay planted. Small body weight shifts and breathing come from the clip layer and mood (IB-17), never
    from moving feet.
14. *Swim–walk gradient (IB-08).* Submersion s = clamp((water level − ground height) / hip height, 0, 1).
    - Gait output is weighted by (1 − s) and the swim oscillator (M1 style) by s.
    - Effective load per foot is reduced by buoyancy, so duty factor may drop ("punting").
    - Speed limit blends between walk and swim limits by s.
    - There is no mode switch, so the shoreline is a gradient as IB-08 proposes.

### 4.4 Implementation options

| | A. Continuous parametric blend (one planner, Fr axis, rules above) | B. Explicit state machine with authored transition clips (start, stop, turn-in-place, enter-water) | C. Motion matching or learned controller |
| --- | --- | --- | --- |
| Fit for player-built bodies | Works on any body by construction | Clips need retargeting per body (semantic clips, animation spec §3.3); many combinations to test | Needs data per morphology; impossible for unbounded bodies; also "runtime AI" needs approval |
| Responsiveness | Immediate; anticipation only through lean | Clip lengths add latency | Good where data exists |
| Visual quality | Plain but robust; style from table and lean | Richer starts and stops | Best, where trained |
| Determinism and tests | Deterministic; testable in domain | Deterministic; test grid per clip | Hard |
| Cost | Tiny | Small | High |
| Recommendation | **A as the base**, with B used only for expressive overlays (a stumble, a startled hop) layered on top | Overlay only | Reject for now |

Godot's `AnimationTree` / `AnimationNodeStateMachine` / `AnimationNodeBlendSpace1D` exist in 4.7.2 (verified). They drive
named-bone animations, so they do not fit generated skeletons without retargeting. They are not used for gait.

### 4.5 Performance risks

- Terrain sampling for swing clearance costs a few rays per swing. A heightfield lookup would be cheaper than physics rays
  once terrain exists.
- Plane fitting is O(feet).

### 4.6 Acceptance tests

1. 180° reversal at top speed: the turn finishes with no foot past its reach. Turn time is within 10% of the predicted
   envelope value.
2. Turning in place for 720° on a quadruped and a hexapod: no slip above the 2% threshold, and the pivot drifts less than
   10% of body length.
3. Stop from top speed: every foot is planted within 2 cycle periods, and at most one settling step per foot.
4. Speed ramp from 0 to top and back: no band flicker. Pattern switches equal the number of band crossings × feet.
5. Slope 0–30° in 5° steps (scene test): pitch error versus the true slope stays under 3° at rest. Feet stay on the
   surface within 1% of leg length. Speed follows the §5 slope rule within 5%.
6. Shoreline walk-in: weights change continuously, with no single-tick jumps of foot target above 5% of leg length.

### 4.7 Unsupported (first version)

- Moving or tilting platforms.
- Steps taller than 40% of hip height. The creature refuses, and climbing is a later ability.
- Ceilings and overhangs.
- Lateral (crab) gaits beyond what the envelope allows: they are allowed but not tuned.
- Jumping, which belongs to the ability layer.

## 5. System 3: anatomy → stats and abilities

### 5.1 Observed behaviour and evidence

- OBSERVED (S14): in Spore's Creature stage, part stats were fixed regardless of placement or limb length. Shape had no
  gameplay effect.
- OBSERVED (S11; rows P002–P004): four combat and four social abilities, each rated on five levels summed from parts.
  Speed comes from leg parts in levels.
- CONFIRMED (S1 §3.1.2): game code builds the same semantic context queries as animators, "for use in gameplay AI
  reasoning, inventory, etc." Capabilities are a gameplay interface as well as an animation one.
- CONFIRMED (S1 §4.1.1): branching on HasGraspers, HasFeet and UprightSpine, with a mouth fallback when there is no
  grasper (also S13).
- Biology:
  - L2/L3: speed scales with leg length through Fr.
  - L4: stride frequency falls with size, and energy per stride per kg is about constant, so a short-legged animal
    pays more to hold a given speed.
  - L9: support polygons describe static stability.
- Current GENESIS M1 (read only): `Phenotype` sums part effects into speed, acceleration and turn_rate. Mass divides
  speed and acceleration, and stats are capped. Placement matters only for facing (mouth, spike). `Locomotion.steer`
  uses independent speed and turn_rate caps.

### 5.2 Documented, inferred, unknown

| Documented | Inferred (HYPOTHESIS) | Unknown |
| --- | --- | --- |
| Part-level stats, five levels, fixed regardless of placement (S14, S11); capability queries used by gameplay (S1) | Spore's walking speed in the world may still have varied with leg length through animation (stride) even if the *stat* did not. R307 separates the two by measuring absolute and body-relative speed. | Whether leg length changes Spore's real speed; whether leg count matters; per-level speed values (R301); acceleration (R303); turn radius (R304) |

### 5.3 Specification (PROPOSED; original GENESIS rules)

Movement stats come from geometry first, then from parts, so the creature moves the way it looks. All numbers are tuning
in `game/data/body_mechanics.json`.

1. **Top speed per band:**
   - v = √(Fr_band · g_eff · h_eff), where h_eff is the stance height of the slowest-cycling group;
   - multiplied by a part factor (feet types, muscles) bounded to [0.7, 1.3], so parts tune the result but do not
     override the body;
   - mass and load reduce it as in rule 5.
2. **Reach envelope.**
   - For each stance foot i at horizontal offset r_i from the pivot, the foot's sweep velocity is v + ω × r_i. It must
     satisfy |v + ω × r_i|·β·T ≤ sweep_max_i.
   - The allowed (forward speed, yaw rate) pairs are the intersection of these constraints. Steering clamps every command
     to this set.
   - This single object replaces separate speed and turn-rate caps for legged bodies, and it guarantees no slip.
3. **Acceleration:**
   - limited to the speed gained in one cycle period at the starting band;
   - multiplied by a muscle factor and reduced by mass;
   - so long, slow-cycling legs accelerate more slowly than short legs, even with a higher top speed.
4. **Stability:**
   - static margin m = minimum distance from the centre-of-mass projection to the stance polygon edge, over the walk
     cycle;
   - tipping angle θ_tip = atan(m / h_com);
   - θ_tip sets the steepest standable slope and knock-back resistance.
   - Wide, low bodies win here. Tall long-legged bodies are fast but tip easily.
5. **Load.**
   - Weight per stance foot = m·g / (mean feet in stance).
   - Each leg's load capacity grows with its limb cross-section (capsule radius², from `../CREATURE_GEOMETRY_SPEC.md` §7).
   - Overloaded legs raise duty factor and cap the band.
   - Many thin legs and few thick legs carry the same load differently.
6. **Energy:**
   - movement energy per second ∝ mass × stride frequency (the L4 relation, simplified);
   - at equal ground speed, short legs cost more, which is a real trade-off against their turning and acceleration.
7. **Swimming and the shoreline:** fin area and placement set swim thrust and turning, as in IB-18. Blending by
   submersion (§4.3 rule 14) mixes the two sets of stats.
8. **Abilities** come from capabilities plus a geometric check, never capabilities alone. Examples:
   - "carry" needs a grasper or mouth that can reach the ground, which means its limb reach is at least its rest height
     (the same test as S1's ground-relative idea, our own rule);
   - "feed from trees" needs mouth or grasper reach at least the plant height;
   - "sprint" is the top band, available only if the envelope allows it;
   - "climb" (later) needs graspers or claws plus θ_tip above a threshold.
   - Fallbacks such as mouth-carry are capability rules, not animation hacks.
9. **Explain every number (IB-04).** Each stat records its derivation ("speed 2.1 m/s: legs 0.8 m, trot band;
   −12% load"). The editor shows deltas in plain language.

### 5.4 Implementation options

| | A. Analytic derivation (formulas above, domain) | B. Simulated measurement: run the gait planner headless on the body for a few seconds and record achieved speed, turn time and stability | C. Spore-like part points (sums and levels, as M1 does now) |
| --- | --- | --- | --- |
| Explainable to the player | Yes, every term is visible | Partly (numbers, not reasons) | Yes, but shape does not matter |
| Matches what the animation can do | By construction, if the planner uses the same envelope | Exactly, since it is measured | No; slip or "moonwalking" risk |
| Determinism | Yes | Yes (fixed tick) | Yes |
| Editor cost | Microseconds | ~10–50 ms per edit (HYPOTHESIS; planner only, no IK) | Microseconds |
| Exploit risk | Edge cases in formulas (zero-width stance, one giant leg) need caps | Strange bodies that "cheat" the planner show up honestly | Low |
| Recommendation | **A for gameplay**, plus B as an *automated test* that checks A against the planner on the body matrix (they must agree within 5%) | Test oracle | Keep for M1 cells, where the body is not legged |

M1 is not affected. `Phenotype` and `Locomotion` keep working for the microscopic era. A future `BodyMechanics` feeds the
legged eras, and the domain chooses by body plan. The save schema is unchanged, because mechanics are derived and not
stored.

### 5.5 Risks and unsupported

- Formulas can make one archetype dominant (tall runners). Balance comes from the trade-offs in rules 3, 4 and 6, and
  must be checked with a comparison table of the test bodies before any approval.
- One-legged hoppers and bodies with zero static margin need a dynamic-balance rule, which is not yet specified.
- Players need to see the derivation (IB-04), or the maths feels hidden (the IB-18 risk).

### 5.6 Acceptance tests

1. Same parts, longer legs: higher top speed (√ rule), lower cadence, lower θ_tip, slower acceleration (domain test).
2. Same parts, wider stance: higher θ_tip, lower turn rate (domain test).
3. Analytic top speed and planner-measured top speed agree within 5% on every test body.
4. Every stat has a non-empty derivation list.
5. Order independence: listing the same parts in a different order gives identical stats.

## 6. System 4: IK solve and secondary motion

### 6.1 Observed behaviour and evidence (S1 §4.3–4.4, CONFIRMED unless marked)

- **Goals.** There are far fewer goals than degrees of freedom, so extra freedom serves secondary aims. 6-DOF goals are
  turned into 3-DOF position goals at joints. Some goals are delegated to the parent: for example, a spine-mounted mouth
  moves its spine segment, so the spine bends instead of the mouth pivoting.
- **Particles and constraints.** Joints are particles with length constraints. Each end of a constraint has its own
  "mass" used only as a tuning weight. Corrections are nonlinear (following L14), with a C1 piecewise response that
  allows soft stretch and compression. The root is driven by forward kinematics.
- **Two phases.** In the spine phase, particles sit only at spine branch points, each limb is reduced to one chord
  constraint to the spine, and the spine is fitted with splines (quintic Hermite was needed; cubic failed). An
  anti-buckling rule blends toward the rest pose when neighbouring spine constraints fold. Then the limb phase runs with
  the spine fixed, using an "aim preconditioner": the limb is rotated and scaled toward the goal first, then relaxed.
  Cross-constraints keep sibling goals together. Orientations are rebuilt with minimal-twist rotations.
- **Design aims.** The solver is path independent on purpose, which is a known cause of singularities. Classic CCD,
  Jacobian and constrained-dynamics solvers were tried and found slower and harder to tune.
- **Jiggles.** Sub-trees with no goals get passive, damped secondary motion that never feeds back. The earlier "Wiggles"
  fed IK goals and hurt quality.
- **Cost.** About 0.2 ms per 25-body creature on a 1.7 GHz Pentium M, with about 35% in IK. Testing used a pass/fail grid
  with about 90% passing.
- **Limitations stated by S1:**
  - no self-collision;
  - anti-buckling can look heavy-handed;
  - singularities;
  - no notion of volume (motions such as "hug" or "rub chin" cannot be expressed).
- The specific numbers S1 publishes (5 outer iterations, 10% limb compression, 10%/120% shrink/stretch) are documented
  facts about Spore. GENESIS does **not** adopt them as constants. Ours come from our own tuning (`LEGAL_RESEARCH_BOUNDARIES.md` §6).
- Practitioner sources:
  - L13 (Rain World) used points at fixed distances for soft, terrain-adaptive bodies, the same family of technique;
  - L11 and L16 show IK foot placement on top of cycles or reactive steps;
  - L12 argues for few keys plus procedural layers.

### 6.2 Documented, inferred, unknown

| Documented | Inferred (HYPOTHESIS) | Unknown |
| --- | --- | --- |
| All of 6.1 | Leg IK targets in Spore came from the gait system as position goals for feet ("composed with any synthesized locomotion", S1 §4) | Joint limits (S1 does not mention angular limits); how knees choose a bend direction; the soft-constraint response curve; how the shipped game differed from the 2008 paper |

### 6.3 Specification (PROPOSED)

1. **Inputs.** Body transform from gameplay; foot targets from the planner; reach and look goals from clips; nothing else.
2. **Order.** Body pose (root, height, tilt) → spine bend → limbs → head and eyes → passive secondary. Later stages never
   change earlier ones.
3. **Limbs.** Each foot reaches its target if the target is in reach. Otherwise the limb points at it fully extended and
   never stretches beyond a set tolerance. Knees and elbows bend toward a hint taken from the rest pose, and the hint is
   kept stable frame to frame so joints do not flip.
4. **Spine.** The spine bends as a smooth curve between the hips and shoulders that carry limbs. If the curve would fold
   back on itself, it eases back toward rest.
5. **Secondary motion.** Tails, antennae and frills with no goals get passive spring motion. It never feeds back into
   goals (the S1 lesson).
6. **Look.** Head and eyes aim at targets from perception (IB-16), within soft limits that fade out behind the head.
7. **Determinism.** The solve depends only on current inputs and rest pose (path independent, as S1 chose). That costs
   some singularity risk, which tests must catch.

### 6.4 Implementation options

| | A. Godot built-in modifier stack | B. Own particle/length-constraint solver as a `SkeletonModifier3D` subclass | C. Physics-driven active ragdoll |
| --- | --- | --- | --- |
| Classes | `TwoBoneIK3D` (2-segment legs; `setting_count` lets one node hold many legs), `FABRIK3D`/`CCDIK3D` (subclasses of `IterateIK3D`, with `max_iterations`, `min_distance`, `angular_delta_limit`, `deterministic`, per-joint `JointLimitationCone3D`), `SplineIK3D` driven by a `Path3D` the planner writes, `LookAtModifier3D` (angle limits with damp thresholds, time-based interpolation), `SpringBoneSimulator3D` | Override `_process_modification_with_delta(delta)`; particles = joints, length constraints, per-end weights, spine spline fit, aim-then-relax; published technique (S1, L14), our code | `PhysicalBoneSimulator3D` + `PhysicalBone3D`; PD torques applied with `apply_impulse` each physics tick toward the planned pose |
| Cost | Native C++; HYPOTHESIS: well under 0.05 ms per leg | X2: 75 µs per creature-frame for the inner loop alone in GDScript; with reconstruction, about 0.2–0.3 ms (HYPOTHESIS). 50 creatures ≈ 10–15 ms, which is too slow without LOD or a GDExtension (needs approval). | Physics tick for every bone of every creature; highest |
| Foot slip | None if targets are reachable (targets are world-fixed) | None; soft constraints can trade tiny stretch for smoothness | Feet slide and stumble unless heavily tuned |
| Odd bodies | Per-chain solvers do not know about the whole body: no spine-plus-limb compromise, no delegated goals. Knee flips are possible without good pole hints. | Designed for whole-body compromises; handles branching limbs and spine-mounted mouths | Handles anything physically, but often falls over |
| Determinism | `IterateIK3D.deterministic` exists (semantics not verified); `Skeleton3D` has a MANUAL callback mode and `advance()`, so tests can step it | Fully ours, deterministic | Weak; depends on physics engine and tick |
| Tuning effort | Low to start; limited knobs | High at first, then good local control (S1's argument) | Very high |
| Recommendation | **Start here** (also the animation spec §3.4 and IB-14) | **Fallback** only after a measured failure of A on the test matrix, and approval | **Reject for locomotion**. Keep in mind for hit reactions and death ragdolls later. |

`PhysicalBone3D`'s static property list in 4.7.2 shows no joint-motor or pose-target properties, only joint type,
offsets, mass, damping and velocities. So option C would need hand-written PD control. This is OBSERVED from ClassDB,
which cannot see properties that `joint_type` adds dynamically, so it is not final.

### 6.5 Risks

- Built-in solvers on generated rest poses with unusual bone axes. The `mutable_bone_axes` property exists on
  `IKModifier3D`, and its behaviour must be tested.
- The order of the modifier stack. HYPOTHESIS: modifiers run in child order under `Skeleton3D`, which must be confirmed
  in the prototype.
- Singularities at full extension.
- Spring bones jittering at low frame rates.
- No self-collision, as in Spore.

### 6.6 Acceptance tests

The animation spec §6 items 2, 3, 4 and 8. In addition:

1. Over a 60 s scripted run on the test matrix, no knee or elbow flips its bend side unless the goal crosses the limb's
   plane.
2. Unreachable goals: the limb is fully extended toward the goal, stretched at most 2%, with no oscillation.
3. Secondary chains: zero effect on any IK-driven bone, tested by running with and without spring bones and comparing the
   driven bones' poses (difference = 0).

## 7. Proposed Godot interfaces (consolidated)

During prototyping all of this lives in `prototypes/creature-lab/` (roadmap §2), uses no `class_name` (to avoid global
class clashes with `game/`), and is loaded by path. Layering below is for an eventual move into `game/`, which is a
separate owner decision.

### 7.1 Domain (`game/domain/`, pure; no scene, UI or file access)

```text
BodyMechanics (RefCounted)
  static from_body(body: Dictionary, tuning: Dictionary) -> BodyMechanics
  legs: Array          # per leg: hip index, foot index, length, stance height, sweep_max, rest foot offset
  groups: Array        # leg indices, period ratio (p, q)
  mass, com, h_com, stance_polygon
  top_speed(band) -> float
  clamp_command(v: Vector2, omega: float) -> Vector3   # (v.x, v.y, omega) inside the reach envelope
  static_margin() -> float ; tip_angle() -> float
  energy_rate(speed: float) -> float
  derivation() -> Array[String]                         # IB-04 explanations

GaitTable (RefCounted)
  static from_dict(d: Dictionary) -> GaitTable          # bands in Fr units
  params_at(fr: float, band_hint: int) -> Dictionary    # duty, rel_stride, lift, pattern id; hysteresis via band_hint

GaitPlanner (RefCounted)
  _init(mech: BodyMechanics, table: GaitTable, ground: Callable)  # ground(xz: Vector2) -> {height, normal, ok}
  tick(dt: float, body: Transform3D, cmd: Vector3, submersion: float) -> void
  feet() -> Array      # FootState dictionaries: phase, in_stance, plant, target, swing_t, lift
  body_offset() -> Transform3D   # height, pitch, roll and lean for the scene
```

Fixed tick at the physics rate. There is no randomness, so no seed is needed. If idle variation is added later, it takes
an explicit `RandomNumberGenerator` seed, per the M1 pattern.

### 7.2 Systems (`game/systems/`)

- A loader for `game/data/gaits.json` and `game/data/body_mechanics.json` that uses `FileAccess` + `JSON` and validates
  ranges. The domain receives Dictionaries.
- No save data. Mechanics are derived from the body description, so the save schema is unchanged.

### 7.3 Scenes (`game/scenes/`, presentation only)

- `CreatureLocomotionRig` (Node3D):
  - owns the generated `Skeleton3D`;
  - creates one `Marker3D` target per foot plus pole markers;
  - builds the modifier stack as `Skeleton3D` children, in order: a small custom `SkeletonModifier3D` for body
    offset → `SplineIK3D` (with a `Path3D` whose `Curve3D` the rig rewrites) → `TwoBoneIK3D` / `FABRIK3D` per limb →
    `LookAtModifier3D` → `SpringBoneSimulator3D`;
  - sets `Skeleton3D.modifier_callback_mode_process` to physics in play, and to MANUAL with `advance()` in tests;
  - samples ground with `PhysicsDirectSpaceState3D.intersect_ray` and `PhysicsRayQueryParameters3D`, wrapped as the
    planner's `Callable`.
- Option B solver: `ParticleBodySolver extends SkeletonModifier3D`, overriding `_process_modification_with_delta`.

### 7.4 Verified against the pinned binary (Godot 4.7.2.stable.official.ed1daf0bf, `ClassDB`, 2026-10-23)

These classes exist, with these parents:

| Class | Parent |
| --- | --- |
| `SkeletonModifier3D` | Node3D |
| `IKModifier3D` | SkeletonModifier3D |
| `ChainIK3D` | IKModifier3D |
| `IterateIK3D` | ChainIK3D |
| `TwoBoneIK3D` | IKModifier3D |
| `FABRIK3D`, `CCDIK3D`, `JacobianIK3D` | IterateIK3D |
| `SplineIK3D` | ChainIK3D |
| `LookAtModifier3D`, `SpringBoneSimulator3D`, `BoneConstraint3D`, `LimitAngularVelocityModifier3D`, `BoneTwistDisperser3D`, `RetargetModifier3D`, `ModifierBoneTarget3D`, `PhysicalBoneSimulator3D` | SkeletonModifier3D |
| `AimModifier3D`, `CopyTransformModifier3D` | BoneConstraint3D |
| `JointLimitationCone3D` | JointLimitation3D (Resource) |

Also present: `Skeleton3D`, `BoneAttachment3D`, `PhysicalBone3D`, `Path3D`, `Curve3D`, `Marker3D`, `RayCast3D`,
`ShapeCast3D`, `PhysicsRayQueryParameters3D`, `PhysicsDirectSpaceState3D`, `CharacterBody3D`, `AnimationTree`,
`AnimationNodeStateMachine`, `AnimationNodeBlendSpace1D`, `RandomNumberGenerator`, `JSON`, `FileAccess`.
`SkeletonIK3D` still exists but is deprecated (scout).

Members verified:

| Class | Members |
| --- | --- |
| `SkeletonModifier3D` | `active`, `influence`, virtual `_process_modification_with_delta`, signal `modification_processed` |
| `IKModifier3D` | `mutable_bone_axes`, `set_setting_count` |
| `TwoBoneIK3D` | `set_target_node`, `set_pole_node`, `set_root_bone`, `set_middle_bone`, `set_end_bone`, `set_pole_direction`, `setting_count` |
| `IterateIK3D` | `max_iterations`, `min_distance`, `angular_delta_limit`, `deterministic`, `set_joint_limitation` |
| `SplineIK3D` | `set_path_3d`, `set_tilt_enabled` |
| `LookAtModifier3D` | `target_node`, `use_angle_limitation`, `primary_limit_angle`, `primary_damp_threshold`, `duration`, `transition_type` |
| `SpringBoneSimulator3D` | `set_stiffness`, `set_drag`, `set_gravity`, `set_radius`, `external_force` |
| `Skeleton3D` | `modifier_callback_mode_process` (PHYSICS/IDLE/MANUAL), `advance`, `set_bone_pose_rotation`, `get_bone_global_pose` |
| `PhysicsDirectSpaceState3D` | `intersect_ray` |
| `Path3D` | `set_curve` |

Not verified (behaviour, not existence):

- what `deterministic` guarantees;
- the order in which modifiers run;
- how `TwoBoneIK3D` handles many settings per node;
- `SplineIK3D` on generated spines;
- whether `IterateIK3D` honours limits on generated rest axes.

These are the first things the prototype measures.

## 8. Remaining experiments (one variable each)

Spore rows are the owner's recordings (`../MEASUREMENT_PLAN.md`); none are filled yet. "G" rows measure a GENESIS
prototype the same way (`subject=genesis`). New row IDs are **proposals** for `../GAMEPLAY_MEASUREMENTS.csv`; this
workstream did not edit that file.

| Row | Variable changed (only this) | Held fixed | Measure | Competing explanations to separate |
| --- | --- | --- | --- | --- |
| R307 (exists) | Leg length (short vs long), same feet and level | Body, parts, terrain, zoom | Top speed in body lengths/s **and** screen px/s | Stat unchanged but stride changed (animation only) vs real speed change vs camera zoom effect |
| R302 (exists) | None (baseline), 2 creatures of different leg length | | Stride / leg length | Constant ratio (scaled table) vs fixed stride |
| R310 (exists) | Long:short leg length ratio (1:1, 1:2, 2:3 builds) | Leg count, parts | Steps per group in 10 s | Ratio snaps to rationals (S1) vs continuous ratio vs one shared clock |
| R308 (exists) | Leg count 2, 4, 6, 8 | Leg length, body | Foot lift order at walk and run | Generated metachronal pattern vs pairwise alternation |
| R309 (exists) | Speed level | Body | Foot drift in stance | Planted feet vs blended cycle |
| R304 (exists) | None at first; then stance width only | Body length, legs | Turn radius at top speed | Envelope-like limit vs fixed turn rate |
| R311 (exists) | Legless body | | Motion description | Pseudo-foot wave vs float |
| **R312** (new) | Ground slope (flat, then the steepest walkable hill found) | Creature, speed key | Uphill and downhill speed, body tilt | Speed changes with slope vs constant speed with tilt only |
| **R313** (new) | Input: release key at top speed | Creature, flat | Frames to stop; number of extra steps; whether all feet plant | Settling steps vs instant freeze vs slide |
| **R314** (new) | Turn command with no forward input | Creature, flat | Does it turn in place; foot pattern while turning; time for 180° | Stepping pivot vs body rotating over planted feet (slip) |
| **R315** (new) | Leg count 4 → 6, same leg length | Body, parts | Top speed, cadence | Leg count affects speed vs only animation |
| **R316** (new) | Water depth at the shore (walk from dry land into deeper water) | Creature, speed key | Speed and animation along the path; where the change happens | Gradient vs mode switch at a depth |
| **R317** (new) | Speed (slow walk to sprint ramp) | Creature | Speed where foot pattern visibly changes, in body lengths/s, for two leg lengths | Change at equal Fr (scaled) vs equal absolute speed vs none |
| **G301** | Leg length ×1 vs ×2 in the prototype | Everything else | Speed, cadence, slip | Checks §2 and test 3.7.5 |
| **G302** | Stance width ×1 vs ×1.5 | Everything else | θ_tip, turn time | Checks §5.6 test 2 |
| **G303** | IK option A vs B on the same body matrix | Planner, bodies | Slip, flips, ms per frame | Decides whether to build B |

Confidence today: every Spore behaviour row is empty, so every Spore column in §3.2, §4.2 and §5.2 marked "Unknown"
stays unknown until the owner records R2 and R3.

## 9. Recommended smallest prototype (awaiting approval; nothing built)

**"Gait Lab": an adaptive four-legged gait whose speed comes from leg length, with no foot slip.**

**Why this one.** It validates the most important locomotion finding: one dimensionless gait table plus a reach envelope
gives anatomy-driven speed and turning with no foot slip (§2, §5.3). It also tests whether Godot's built-in IK (option A)
is good enough, which decides the biggest cost question (whether we must write our own solver). It needs no generated skin,
so it can run before or beside Stage 1.

**Scope.**

- In `prototypes/creature-lab/gait/`, which is excluded from the main project's import, tests and export, the same
  safeguard as roadmap Stage 1.
- Pure domain scripts: `BodyMechanics` (legs, groups, envelope, top speed), `GaitTable` (three bands in Fr units, from a
  JSON file in the prototype), `GaitPlanner`.
- Three test bodies built in code as `Skeleton3D` bone chains with debug line or capsule display. These are prototype-only
  placeholders, never production assets.
  - quadruped with 0.5 m legs;
  - the same quadruped with 1.0 m legs;
  - hexapod with 0.5 m legs.
- Two-bone legs with `TwoBoneIK3D`.
- A flat plane, keyboard drive and a fixed physics tick.
- No spine IK, slopes, water, clips or editor.
- Headless domain tests plus one scene test stepped in MANUAL mode.

**Pass criteria** (all measured, reported in a short note with a contact sheet and a 10 s clip per body):

1. Foot slip < 2% of leg length per stance, at walk and trot, for all three bodies.
2. Top speed ratio long/short quadruped = √2 ± 5% in m/s. Cadence ratio = 1/√2 ± 5%.
3. A 180° reversal and a 720° turn in place show no foot past reach. Turn time is within 10% of the envelope prediction.
4. Byte-identical foot logs across two runs (determinism).
5. A 60 s scripted run shows no NaN and no knee flips.
6. Cost for 50 quadrupeds driven together, reported in ms per frame. This is informational. It sets the budget for
   option B if needed.

**Size.** About 1–2 working sessions.

**Not covered.** Skin deformation, spine, odd bodies (3 legs, mixed lengths) and slopes. Those go to the next step only if
this passes.

**Ordering note.** The roadmap puts locomotion at Stage 3, after skin and editing. Running Gait Lab earlier changes the
order, though not the scope, so the owner should choose. It does not touch `game/`.

## 10. What we learned, what is uncertain, and whether this reduces work

**Learned.**

1. S1 documents the *architecture* clearly:
   - leg groups with rational frequency ratios;
   - duty factor and step trigger;
   - speed-interpolated parameters;
   - normalised swing scaled by leg length;
   - a two-phase constraint IK with spine splines and anti-buckling;
   - passive secondary motion that never feeds back.
2. S1 also documents what failed: Wiggles feeding IK, monolithic solvers, CCD/Jacobian being hard to tune, looped
   spines. That saves us from repeating those experiments.
3. Biomechanics gives a better-founded scaling rule than anything Spore published. Writing the gait in Froude units
   makes slip-freedom a size-independent check, and it makes speed, cadence, acceleration, turning, stability and
   energy follow from the body (X1).
4. Godot 4.7.2 ships every built-in we planned to use, with the expected members.
5. A pure-GDScript whole-body solver is affordable for a handful of creatures but not for 50 without LOD (X2).

**Uncertain.**

- Everything about Spore's *visible* turning, slopes, stops, water edges and stat effects, until R2 and R3 are recorded.
- The academic constants (L3 regression, gait transition Fr) were read through secondary summaries.
- How Godot's built-in IK behaves on generated rest poses.
- Whether the analytic stats feel good in play.

**Does the research reduce implementation work?**

- Yes, for architecture and risk. We know which layers to build, in which order, which solver families to skip and which
  failure modes to test for (singularities, buckling, knee flips).
- The dimensionless table cuts tuning from per-body to per-band.
- No, for numbers and feel. No Spore constant is adopted, and those numbers would not transfer anyway. Tuning remains
  real work, measured in the prototype.
- The largest remaining unknown that changes cost is whether option A is enough. Gait Lab answers that first.
