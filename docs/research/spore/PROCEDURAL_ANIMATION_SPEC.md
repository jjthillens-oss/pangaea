# Procedural animation spec (GENESIS)

Status: PROPOSED specification, 2026-10-23. Nothing here is approved for the game. Building any of it starts as an
isolated prototype under `prototypes/` after the owner approves that spike (`GENESIS_IMPLEMENTATION_ROADMAP.md`).
Labels are defined in `LEGAL_RESEARCH_BOUNDARIES.md`; source IDs refer to `SPORE_RESEARCH.md` §3.

This is an **original** design. Where it follows a technique published by Spore's developers (S1), it says so, so the
provenance is visible. It uses no Spore code, data or animation. General techniques (IK, gait phase offsets, duty
factor, spring bones) are standard animation knowledge with decades of public literature.

## 1. Goal

Any body the player can build in a GENESIS editor moves believably the moment it is built, and its anatomy changes
how it moves and what it can do. The Bible requires "Creature anatomy must meaningfully influence gameplay." (CONFIRMED) and
"limb placement influences support, reach, gait, and turning" (Bible §7, PROPOSED era text). This spec is the
animation half; the gameplay half lives in `game/domain/locomotion.gd` and its successors.

Non-goals: physically simulated locomotion; arbitrary graphs with loops. Spore dropped loops for two stated
reasons: a general graph's interface complexity hindered player creativity (S1 footnote 1), and looped spines broke
animation (S13, OBSERVED). Bodies come from `CREATURE_GEOMETRY_SPEC.md`: a generated skin and skeleton plus Blender-authored parts.

## 2. What Spore published (summary of S1)

CONFIRMED from S1 unless marked:

1. **Semantic selection.** Animators never name bones. A channel selects bodies by capability (grasper, mouth, foot,
   spine) narrowed by spatial filters (front/back, left/right, top/bottom, relative to the whole body or to the set of
   matching parts) and extent filters (front-most, etc.), plus a "walk up to the spine" modifier for shoulders.
2. **Generalized pose space.** Each channel records motion through an invertible mapping between a body's real pose
   and a body-independent pose. Movement modes define the mapping: absolute, rest-relative, scaled by creature size
   or limb length, ground-relative (0 = rest height, 1 = ground), and target-relative (0 = rest, 1 = an external or
   internal target such as a fruit or the creature's own mouth), plus look-at.
3. **Binding.** The first time a clip plays on a creature it binds: three-valued branch predicates (UprightSpine,
   HasGraspers, HasFeet) pick between alternative clips; **variants** enumerate which concrete parts can play each
   channel (one per grasper, or per grasper–mouth pair), with automatic left–right mirroring. Game code picks the
   variant (for example, the grasper nearest the fruit).
4. **Gaits.** Legs are clustered into groups of roughly equal length; the groups' length ratios are approximated by
   small rational numbers to set relative cycle frequencies. Each foot gets a duty factor (fraction of the cycle on
   the ground) and a step trigger (phase offset). Animators authored gait parameters against speed for 1–6 feet;
   7 or more are generated. Footless bodies float or crawl, with spine bodies turned into pseudo-feet.
5. **Particle IK.** Joints are 3-DOF particles linked by length constraints solved iteratively, with masses per
   constraint end used as tuning knobs and soft, stretchable constraints. Two phases: spine first (particles only at
   branch points, spine fitted as splines, anti-buckling pull toward rest), then limbs with the spine fixed. Path
   independent by design. Several classic solvers (CCD, Jacobian, constrained dynamics) were tried and rejected as
   slower and harder to tune.
6. **Jiggles.** Parts no clip selects get passive, heavily damped secondary motion that never feeds back into the
   authored motion. An earlier version that fed into IK goals hurt quality and was dropped.
7. **Testing.** Clips were tested on a database of creatures uploaded by players, with testers filling a pass/fail
   grid; pass rate about 90%. Cost: about 0.2 ms per frame for a 25-body creature on a 1.7 GHz Pentium M, about 35%
   of it in IK.

Also reported, but not in S1. Items 8 and 9 are OBSERVED (S13, a journalist quoting developers); item 10 is
CONFIRMED (S14, a first-hand developer essay):

8. A "walking ratio" comes from leg count, leg length and symmetry (twice as many legs on one side gives one to
   two); footfall rhythm and gait take the torso and head dimensions into account.
9. With no paw or claw, the mouth acts as the hand; with no legs, the creature slithers like an inchworm.
10. Spore's own designer reports that the Creature stage's part stats did not depend on limb length or placement
    (S14). Animation adapted to shape; gameplay did not. GENESIS changes that (§4).

## 3. GENESIS architecture (PROPOSED)

Five layers, each testable alone. Domain rules stay free of scenes, UI and files (CLAUDE.md).

```
BodyMechanics (domain)   ->  Gait planner (domain)  ->  Pose goals  ->  Godot SkeletonModifier3D stack  ->  Secondary
   capabilities, legs,         phases, foot targets,      clips +           IK solvers, look-at              spring bones
   leg groups, stats           speed limits               gait              (scene)                          (scene)
```

### 3.1 BodyMechanics (`game/domain/`, pure)

Renamed from `BodyDescriptor` and merged with `BodyMechanics` in `workstreams/locomotion.md` §7.1, which holds the
current interface. The old name was retired because it differed by one word from `BodyDescription` (the editable body
data, `CREATURE_GEOMETRY_SPEC.md` §3). Built from the body description, genome and part catalog when a body is
created or edited. Contains:

- Bone tree (spine chain at the root, limbs as subtrees), rest lengths in metres.
- Capabilities per part (`capabilities` list in the part catalog; see `CREATURE_CREATOR_ANALYSIS.md` §3).
- Legs: paths from a `foot` part to the first `spine` bone. Leg length = summed rest lengths.
- Leg groups: legs whose lengths are within a tolerance (PROPOSED 20%) of each other.
- Derived locomotion numbers used by gameplay, from anatomy (examples, all PROPOSED tuning):
  - stride length ≈ k_stride × leg length;
  - max cadence from leg group (shorter legs step faster, bounded);
  - top walking speed = stride × cadence, reduced by load (mass / number of supporting feet);
  - turn rate from lateral foot spread (wider stance turns slower but is more stable), fin placement for swimmers;
  - stability score from support polygon area relative to body height.

Because gameplay speed is computed from the same numbers the gait uses, feet do not slide: the animation never has
to cover more ground than the body can step. This is the key link between anatomy, animation and gameplay.

### 3.2 Gait planner (`game/domain/`, pure, deterministic)

Input: body mechanics, current velocity and turn rate, time. Output per foot: phase, stance or swing, target position on
the ground plane (before terrain correction).

- One cycle clock per leg group. Ratios between groups snap to small rationals (1:1, 1:2, 2:3) so patterns repeat.
  Same idea as §2 item 4; the numbers are ours.
- Gait table per speed band (stand, walk, trot, run) with duty factor and phase offsets. **Current proposal:**
  `workstreams/locomotion.md` §3.3, where the table is written in leg-relative (Froude) units and phases are
  generated for every leg count rather than hand-tabled per count. The earlier idea here (authored for 1–6 legs per
  group, generated for more) is superseded unless the prototype shows generated phases look worse. File:
  `game/data/gaits.json`, PROPOSED tuning.
- Step trigger rule: in stance, a foot lifts when its phase says so **or** when it is stretched beyond its reach
  radius (safety net for sudden turns).
- Swing path: a normalized arc (lift height as a share of leg length, PROPOSED 0.15–0.3) scaled per leg.
- Footless bodies: swimmers use oscillators on fins, tails and flagella (as in M1); crawlers assign pseudo-feet to
  spine bones at even intervals and run a wave along them.

### 3.3 Pose goals: GENESIS motion clips

Our own clip format (a Godot `Resource`, saved as `.tres`), not Godot's bone-name animations:

- **Channel selector:** capability + side (left/centre/right) + extent (front-most, etc.) + "to spine" modifier.
  Same concept as S1's contexts; our own field names and rules.
- **Frame mode:** rest-relative, size-scaled, limb-scaled, ground-relative, target-relative, look-at. The clip stores
  curves in that frame; at play time they map onto the actual parts.
- **Requirements:** each clip lists required capabilities (for example, `grasper`); if missing, a fallback clip is
  chosen (for example, carry in mouth). This replaces S1's predicate branching with a simpler, data-driven list.
- **Variants:** for single-part channels, the game asks the clip for candidates and picks by its own rule
  (nearest to target, free, same side). Mirroring is automatic.
- Authoring: first clips are written as data and checked in a dev-only preview scene under `game/dev/` that plays
  one clip on a grid of test bodies at once (S1 §3.4 describes the same multi-character preview idea). A Blender
  authoring path is a later question.

### 3.4 Solve: Godot's built-in stack (scene layer)

Use Godot 4.6+ built-ins first (`docs/research/open-source-scout.md`: `IKModifier3D` family, `LookAtModifier3D`,
`SpringBoneSimulator3D`, all MIT as part of Godot; to be tested on 4.7.2):

1. Root and spine: set the root from gameplay; bend the spine toward spine goals with `SplineIK3D` or a small
   custom spine pass (two-phase order as in S1: spine first, limbs second, by modifier order in the stack).
2. Legs and arms: `TwoBoneIK3D` for two-segment limbs, `FABRIK3D` for longer chains, with pole hints from rest pose.
3. Head and eyes: `LookAtModifier3D` with soft limits (IB-16).
4. Secondary: `SpringBoneSimulator3D` on chains no clip or gait drives (tails, antennae, frills), passive only.

If the built-ins fail the acceptance tests (§6) on odd bodies, write our own particle-and-length-constraint solver as
a `SkeletonModifier3D` (published technique, our code), only after a measured failure and an approved follow-up.

### 3.5 Terrain correction (scene layer)

Raycast each stance-foot target to the ground; tilt the hips and body to the average foot height and slope, limited
per frame. Not needed for the microscopic era (fixed plane).

## 4. How anatomy affects gameplay (PROPOSED examples)

| Anatomy | Animation effect | Gameplay effect |
| --- | --- | --- |
| Longer legs | Longer stride, slower cadence | Higher top speed, worse slope stability (taller) |
| More legs per group | Lower duty factor needed, smoother gait | Higher load capacity and stability, higher upkeep |
| Uneven leg groups | Rational cadence ratios (visible "shuffle") | Speed limited by the slowest group |
| Wide stance | Body sway reduced | Turn rate lower, knock-back resistance higher |
| Graspers | Reach and carry clips available | Can carry items (IB-27), use tools later (IB-20) |
| No graspers | Mouth-carry fallback clips | Carry limited to one item |
| Tail | Spring-bone sway, counter-turn | Small turn-rate bonus at speed (balance) |
| Fins at the rear vs sides | Different swim oscillators | Rear fins turn better, side fins hold position (IB-18) |

Every effect is shown to the player in the editor before they commit (IB-04 plain-language deltas).

## 5. Era fit

- **Microscopic (M1, now):** no legs. Already uses oscillators on flagella and cilia. Nothing here changes M1.
- **Aquatic:** fins, tails and body undulation. Gait planner unused; oscillators plus spring bones plus look-at.
- **Terrestrial onward:** full stack. First real use; IB-14 places the spike at M3.

## 6. Acceptance criteria and tests (PROPOSED numbers)

Automated, in `tests/` once anything moves into the game; in the prototype first:

1. **Test body matrix.** At least 12 generated test bodies: 0 legs (floater and crawler), 1, 2 upright, 2 prone,
   3 asymmetric, 4, 6, 8, 10, mixed leg lengths (2 long + 4 short), one huge, one tiny. Bodies are built from
   placeholder test parts listed in `assets/records/placeholders/inventory.json` or from production parts.
2. **No foot slip.** During stance, each foot's world position drifts less than 2% of its leg length per stance
   phase, at all speed bands, on flat ground.
3. **No impossible poses.** No NaN or infinite transforms; bone lengths within 5% of rest; no joint flipping past
   its limit, over a 60 s scripted run with sudden stops and 180° turns.
4. **Determinism.** The gait planner gives identical output for the same body mechanics, inputs and seed (domain test).
5. **Speed coupling.** The gameplay top speed from `BodyMechanics` never needs a cadence above the gait table's
   limit (domain test over every test body).
6. **Editor feedback.** After adding a foot, mouth or grasper in the editor, the body is animating with it within
   0.5 s (S1 reports immediate play; our target is a number we can test).
7. **Clip pass grid.** Every clip on every test body, rendered to a contact sheet; a reviewer marks pass/fail.
   Target ≥ 90% pass before a clip ships, and failures are fixed or the clip gets a fallback (S1 used the same kind of
   grid and reported about 90%).
8. **Performance (provisional).** On the baseline PC (RTX 5070 machine, DECISIONS.md), 50 animated creatures of 25
   bones cost under 1.5 ms per frame on the main thread together. No estimate yet meets this: S1 reports about
   0.2 ms per creature on 2008 hardware, and `workstreams/locomotion.md` §6.4 estimates 0.2–0.3 ms per creature for an
   own GDScript solver (10–15 ms for 50). So the budget assumes tiers: full solve for near creatures, a reduced
   update rate (for example every second or fourth frame) and simpler IK for mid-distance ones, and clip-only or
   frozen poses for far ones. The number is re-set after Gait Lab measures option A (built-in IK), and again once a
   lower minimum spec is chosen.
9. **Compare with Spore measurements.** Prototype values measured the same way as Spore clips
   (`GAMEPLAY_MEASUREMENTS.csv`, `subject=genesis`): stride-to-leg ratio, start and stop frames, turn radius.
   Differences are allowed, but must be explained.
