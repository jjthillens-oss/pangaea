# GENESIS implementation roadmap (from the Spore research)

Status: PROPOSED, 2026-10-23. This roadmap does not change the Bible's milestones, the seven eras, the art
pipeline, the save schema or any milestone scope. Each step marked **gate** needs the owner's approval before it
starts, and the approval is recorded in `docs/DECISIONS.md`. Labels as in `LEGAL_RESEARCH_BOUNDARIES.md`.

## 1. Research phases

| Phase | Work | Output | Gate |
| --- | --- | --- | --- |
| 1 (done in this PR) | Legal boundaries, tool identities, published-source survey, creature creator analysis, animation spec, measurement schema and recording plan | This folder | Owner reviews the PR |
| 2 | Owner answers the tool checklist (`SPORE_RESEARCH.md` §2.1); owner records sessions R1 and R2; we extract values; re-read S2 and S7 when chrishecker.com is back; patent search | Filled CSV rows R101–R107, R201–R206; updated analysis | None for research. Recording time is the owner's. |
| 3 | Sessions R3–R5; behaviour notes for NPCs as HYPOTHESIS only | Filled rows R301–R504 | None |
| 4 | Compare each GENESIS prototype against the same rows (`subject=genesis`) | Comparison table per prototype | Follows the prototype gates below |

Binary analysis of Spore is **not** on this roadmap. See `LEGAL_RESEARCH_BOUNDARIES.md` §5.

## 2. Mapping to GENESIS milestones

Milestone names are from Bible §23 (PROPOSED there). Innovation backlog IDs are in
`docs/research/innovation-backlog.md`.

| Milestone | What this research feeds | Research inputs | Status |
| --- | --- | --- | --- |
| M1 First life (in progress) | Nothing new is added to M1. Optional: measured cell-stage feel (R1) as a comparison for tuning speed, growth and camera scaling in the endless pool work. | R101–R107 | Comparison only; tuning stays PROPOSED and playtest-led |
| M1 step 4 editor | Plain-language before/after deltas (IB-04) and instant feedback in the editor; part `capabilities` field (small schema addition to the part catalog, not the save schema). | `CREATURE_CREATOR_ANALYSIS.md` §3 | **Gate**: catalog field is a data change; confirm it fits step 4's plan |
| M2 Visual benchmark | Body variety inside the IB-15 boundary: segmented torso with matching seam rings, shape keys and bone scale (`CREATURE_CREATOR_ANALYSIS.md` §4); mask-based colouring shader (§5). Look-at and spring bones (IB-16). | S3, S4, S7 | **Gate**: spike approval; colouring bake step is a scope question |
| M3 Anatomy depth | The procedural animation stack (`PROCEDURAL_ANIMATION_SPEC.md`): BodyDescriptor, gait planner, motion clips, Godot IK stack, secondary motion; anatomy-derived speed, turn and stability (IB-14, IB-18). Exit evidence "same-scenario comparisons with meaningful tradeoffs" maps to spec §6. | S1, R2xx, R3xx | **Gate**: prototype spike approval, then production approval |
| M4 First continuity | Shore gradient between swimming oscillators and legged gait (IB-08). | S1 crawl/float rule, R206 | Later |
| M5 Social foundation onward | Target-relative clips (reach, give, carry; IB-27), grasper or mouth fallbacks so no body plan is locked out (Bible §9). | S1 §3.2 | Later |
| M7–M8 | Possible later use of cube-sphere planet ideas (S5) and Halton scatter (S6). | S5, S6 | Later; not scheduled |

## 3. Proposed prototype spikes

Each spike lives in `prototypes/` (not `game/`), has its own tests, and is thrown away or promoted only after review.
None starts without its gate.

### Spike A: Halton scatter (small, any time)

- What: deterministic, well-spaced placement of food and decoration from a seed with a density map, using an
  incremental Halton sequence (standard mathematics; the idea is published in S6, the code is ours).
- Why now: fits the endless cell-world work (repeatable, memoryless placement per region).
- Acceptance: same seed gives identical points; minimum spacing statistics beat uniform random; 10 000 points in
  under 1 ms in GDScript on the baseline PC.
- Gate: an engineering choice inside current scope (tuning and tools are the lead's call per the studio model), but it
  touches the endless-world thread's work, so it is offered to that thread rather than started here.

### Spike B: body descriptor and gait planner (domain only)

- What: `BodyDescriptor` and the gait planner from `PROCEDURAL_ANIMATION_SPEC.md` §3.1–3.2 as pure GDScript with unit
  tests, no scenes.
- Acceptance: spec §6 items 4 and 5 on the 12-body test matrix.
- Gate: owner approves starting M3 groundwork early.

### Spike C: animated test bodies

- What: Spike B plus Godot's IK modifiers on placeholder test bodies in a prototype scene, with the clip pass grid and
  a contact sheet.
- Acceptance: spec §6 items 1–3, 7 and 8.
- Gate: after Spike B, owner approval. Test bodies in `prototypes/` may be built from engine primitives because
  they are throwaway test rigs outside `game/`; anything promoted into `game/` uses Blender-authored parts with
  records, as the asset rules require.

### Spike D: segmented torso in Blender

- What: one torso of five segments authored in Blender with shape keys and matching seam rings, exported to GLB,
  driven by bone scale in Godot; collision capsules refit at the extremes.
- Acceptance: seam test passes at every key-extreme combination; no visible gap at 1080p in review lighting.
- Gate: owner approval as an M2 art spike (art thread).

## 4. Workflow per spike (PROPOSED)

1. Spec section cited, acceptance criteria copied into the spike's README.
2. Build in `prototypes/<spike>/` with tests; commit and push after every step.
3. Measure the same rows as Spore where they apply (`subject=genesis`).
4. Independent review (Codex or a separate reviewer session) of code and test results.
5. Owner decides: promote (with a DECISIONS.md entry), change, or drop.

## 5. Decisions needed from the owner

1. Purchase channel and country (for the license version and the law that applies).
2. Whether to keep binary analysis off the plan permanently (recommended), or start the clearance steps.
3. Whether REA should be evaluated as a dev tool for non-Spore uses. Recommended: no, not needed now.
4. Which spike, if any, to start first. Recommended order: A (if the endless-world thread wants it), then B.
