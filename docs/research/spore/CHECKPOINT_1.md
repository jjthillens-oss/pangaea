# Research checkpoint 1: creature creator and locomotion

Status: PROPOSED research checkpoint, 2026-10-23, written for the owner's brief of the same day ("Act as the research
lead..."). The research stops here and waits for the owner's approval before any prototype is built. Labels as in
`LEGAL_RESEARCH_BOUNDARIES.md`.

## 1. What was done

- **Workspace.** Repository `jjthillens-oss/pangaea` (the only Pangaea/GENESIS repository in scope; Orbit untouched).
  Branch `claude/project-thread-uqwkit`, PR #12. Docs only; no production code, data or assets changed. Read: CLAUDE.md,
  the Bible, DECISIONS.md, the existing research notes, M1 domain code (read-only).
- **Owner's install, read-only.** Legitimate Steam copy (app 17390, build 16095569), base game only, `SporeApp.exe`
  1.3.0.29, SHA-256 recorded in `SPORE_RESEARCH.md` §2.1a. Nothing launched, written or opened in game data. Ghidra,
  Java and REA are not installed; Godot 4.7.2 and Blender 5.2 are.
- **Parallel workstreams** (run as separate research agents with separate output files, then reviewed):
  - A, community tools: `workstreams/community_tools.md`
  - B, creature editor: `workstreams/creature_editor.md`
  - C, locomotion: `workstreams/locomotion.md`
  - D, independent evidence review: `workstreams/evidence_review.md` (34 claims checked: 26 verified, 5 partly,
    1 not supported and since corrected, 2 not checkable). Its fixes were applied.
- **Static analysis of Spore: not done.** The brief allows it only "where permitted by applicable terms and law". EA's
  User Agreement §2 does not permit it, so this pass stopped at public sources and observation, as the brief says to.

## 2. Evidence index

| Group | IDs | Where listed | Strength |
| --- | --- | --- | --- |
| Maxis developer papers and sketches | S1 (SIGGRAPH 2008 animation paper, read in full), S3–S6 (SIGGRAPH 2007 sketches and slides) | `SPORE_RESEARCH.md` §3 | Primary, strongest |
| Maxis developer talks and essays | S2 (GDC 2007, not read: site down), S7 (Hecker liner notes, not read: site down), S14 (Soren Johnson essay), S16, S18 (Willmott talk slides, not read yet) | `SPORE_RESEARCH.md` §3, `workstreams/community_tools.md` §4 | Primary when read; S2, S7, S18 still to read |
| EA patents | S15 (US7789758B2, US7867093B2) | `SPORE_RESEARCH.md` §3, `LEGAL_RESEARCH_BOUNDARIES.md` §3 | Primary for what EA filed |
| Press and interviews | S10, S12, S13, S17, S21, S22 | `SPORE_RESEARCH.md` §3, `workstreams/community_tools.md` §4 | Secondary (OBSERVED) |
| Community modding projects | C1 Spore-ModAPI (commit `69b27b5`, GPL-3.0 headers), C2 SporeModder-FX (commit `a482c51`, GPL-3.0), C3 its wiki | `workstreams/community_tools.md` §2 | Modders' reverse-engineered view, not EA's design; reference only |
| Public locomotion science and talks | L1–L17 (Alexander, Heglund and Taylor, Hildebrand, Karim et al., Johansen, Overgrowth and Rain World GDC talks, Raibert...) | `workstreams/locomotion.md` §1.2 | Facts about animals and robots, not Spore |
| Our own probes (scratch, not in repo) | X1 gait maths, X2 solver timing, skin pipeline and size probes, Godot ClassDB checks | `workstreams/locomotion.md` §1.3, `workstreams/creature_editor.md` §5 | OBSERVED on the cloud test machine |
| Gameplay recordings | R2xx, R3xx rows | `GAMEPLAY_MEASUREMENTS.csv`, `MEASUREMENT_PLAN.md` | **None recorded yet** |

## 3. System map

| System | Spore: documented | Spore: inferred or unknown | GENESIS spec |
| --- | --- | --- | --- |
| Body and spine | Tree, spine at the root, no loops; base "bean" with vertebra-like points; edit pose becomes rest pose (S1, S12) | Vertebra limits, thickness model (recordings R201, R211) | `CREATURE_GEOMETRY_SPEC.md` §3–4; `workstreams/creature_editor.md` §2 |
| Surface (skin) | Skin "generated via metaballs" over the player's skeleton (S3 slides) | Field function, tessellation, weights, LODs (not public) | Capsule implicit field + Surface Nets; alternatives in `creature_editor.md` §2.4 |
| Parts, symmetry, placement | Rigblocks with handle deforms, baked after editing (S3); symmetry as a principle (S12) | Snap and slide rules, what moves when the body changes (R204, R212–R224) | `creature_editor.md` §3: parts stored relative to their host, mirror flag |
| Saved description | Compact recipe, 2–8 KB depending on source; animation rebuilt from it (S12, S15, S17) | Exact contents (not needed; we will not use EA's format) | `creature_editor.md` §4: canonical compact JSON; save schema change needs owner approval |
| Automatic rigging | Not published | Everything | Weights from field contributions, `CREATURE_GEOMETRY_SPEC.md` §6 |
| Animation retargeting | Semantic channels, movement modes, variants, mirroring (S1, confirmed by C3 from another angle) | — | `PROCEDURAL_ANIMATION_SPEC.md` §3.3 |
| Gait and feet | Leg groups with rational frequency ratios, duty factor, step offset, speed-interpolated parameters, crawl or float fallback (S1) | Turning, slopes, stops, water edge, transitions (R304, R312–R317) | `workstreams/locomotion.md` §3–4: dimensionless gait table + reach envelope |
| IK and secondary motion | Two-phase particle constraint solver, spine splines, anti-buckling, passive "jiggles"; what failed (S1) | — | Godot 4.7.2 built-in IK first (classes verified), own solver only after a measured failure |
| Anatomy and stats | Part stats fixed regardless of shape or placement (S14) | Whether leg length changes speed at all (R307) | Speed, turning, stability, energy derived from the body (`locomotion.md` §5) |

## 4. Prioritised unknowns

1. **Is Godot's built-in IK good enough on odd bodies, at an acceptable cost?** Decides whether we must write our own
   solver (biggest cost swing). Answered by prototype 0a.
2. **How fast can the skin rebuild natively?** GDScript measured 203–578 ms against a 33 ms live-drag target, so live
   editing needs a compute shader or a C++ extension. Answered by prototype 0b.
3. **Does leg length change speed in Spore?** If not, as a Spore designer wrote (S14), it is the clearest place for
   GENESIS to be better. Answered by recording R307.
4. Junction quality where limbs meet the torso (blend rule choice), and whether limbs merge in Spore (R210).
5. Turning, slope, stop and water-edge behaviour in Spore (R304, R312–R316): all unknown until recorded.
6. Whether the analytic stats feel good in play (only a prototype can tell).

## 5. Proposed first experiment (recording, one variable)

**R307, leg length versus speed.** In the Creature Creator test drive or the Creature stage, build one creature, record
it walking and sprinting straight five times, then change only the leg length (same feet, same parts, same speed
level) and record again. Measure top speed in body lengths per second and in screen pixels per second at a fixed zoom.

Competing explanations to separate: the speed stat is unchanged and only the stride animation changes; the real speed
changes; the camera zoom changes with body size. Instructions are in `MEASUREMENT_PLAN.md` (session R3). About 20
minutes.

## 6. Smallest original prototype (recommended, awaiting approval)

**0a "Gait Lab"**: two quadrupeds identical except for leg length (0.5 m and 1.0 m) plus a hexapod, stepping with
Godot's `TwoBoneIK3D` on a flat plane under keyboard control, in `prototypes/creature-lab/gait/`, outside `game/`.

Pass criteria: foot slip under 2% of leg length; long/short speed ratio √2 ± 5%; turn time within 10% of the
predicted limit; identical foot logs across runs; no NaN or knee flips in 60 s; cost for 50 creatures reported.
About 1–2 working sessions. Full scope in `workstreams/locomotion.md` §9.

Why this one first: it is the smallest build that tests GENESIS's main advantage over Spore (the body sets how it moves)
and answers the biggest cost unknown (built-in IK or our own solver). It needs no generated skin and no new dependency.
The second prototype, 0b (spine skin and codec), follows with its own approval (`GENESIS_IMPLEMENTATION_ROADMAP.md`
§2).

## 7. What we learned, what remains uncertain, and whether this reduces work

**Learned.**
- Maxis published the architecture of the animation stack in detail, including what failed. We will not repeat those
  experiments (Wiggles feeding IK, monolithic and CCD/Jacobian solvers, looped spines).
- Spore's skin is metaball-generated around the player's skeleton (S3 slides), which matches the owner's chosen
  direction.
- Spore's creature shape did not change its stats. GENESIS can make anatomy the gameplay.
- A gait table in units of each leg's own size gives speed and cadence from leg length and makes "no foot slip" a
  simple check (our own idea, from public biomechanics).
- Two early probes changed the plan before any build: GDScript is too slow for live skin editing, and Godot's default
  JSON loses precision for saved bodies.

**Uncertain.**
- Every Spore behaviour that needs a recording (turning, slopes, stops, limits, R307).
- Godot's built-in IK on generated rest poses; native skin speed; junction quality; how the stats feel.
- S2, S7 and S18 are unread primary sources.

**Does the research reduce implementation work?** Yes, by a useful but bounded amount: it settles the architecture,
skips known dead ends and gives testable acceptance criteria, which is roughly a design head start. It does not
solve the hard engineering (fast native contouring, junctions, IK on odd bodies) or the feel numbers. Those come from
prototypes and tuning. The independent review reached the same conclusion.

## 8. Handoff rule for implementation

An implementation agent receives only: the GENESIS specs (`CREATURE_GEOMETRY_SPEC.md`,
`PROCEDURAL_ANIMATION_SPEC.md`), the spec, options and test sections of `workstreams/creature_editor.md` and
`workstreams/locomotion.md`, and public licensed references. It does not receive `workstreams/community_tools.md`,
modders' material, or S1's solver constants. This is an engineering safeguard, not a certified clean-room process.

## 9. Decisions for the owner

1. Approve prototype **0a Gait Lab** (recommended), then 0b.
2. Record **R307** (about 20 minutes), then sessions R2 and R3 when convenient.
3. Bible §7 says "support a small approved set of body plans first"; confirm whether free-form bodies replace that line.
4. Confirm that reading the public ModAPI and SporeModder-FX docs as reference is acceptable as done
   (`workstreams/community_tools.md`). Running them on your install stays out.
