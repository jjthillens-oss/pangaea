# GENESIS creature engineering roadmap

Status: PROPOSED, rewritten 2026-10-23 after the owner set the priority: procedural creature geometry, automatic
rigging, anatomy-driven animation and locomotion first; later stages (civilization, space) are not studied yet.
Nothing here modifies existing GENESIS systems. Each step marked **gate** needs the owner's approval, recorded in
`docs/DECISIONS.md`. Labels as in `LEGAL_RESEARCH_BOUNDARIES.md`.

The goal (owner, 2026-10-23): "independently build an original, technically comparable creature-generation system
in Godot 4 using Blender for production assets."

## 1. Where the research stands

| Area | Research status | Spec |
| --- | --- | --- |
| Generated skin (implicit surface) | Published facts gathered (S7, S12, S13); details of Spore's tessellation and weighting not published | `CREATURE_GEOMETRY_SPEC.md` §3–5 |
| Procedural skeleton | Published (S1, S12) | `CREATURE_GEOMETRY_SPEC.md` §4 |
| Automatic rigging | Not published by Maxis; our method stated, Spore's left as HYPOTHESIS | `CREATURE_GEOMETRY_SPEC.md` §6 |
| Anatomy-driven animation | Published in depth (S1, S2, S13) | `PROCEDURAL_ANIMATION_SPEC.md` |
| Locomotion feel | Needs recordings (R2xx, R3xx) | `MEASUREMENT_PLAN.md` |
| Parts and handles | Published (S3) | `CREATURE_CREATOR_ANALYSIS.md` §1.2, §3 |
| Paint | Published (S4) | `CREATURE_GEOMETRY_SPEC.md` §8 |
| Legal and patents | EA license reviewed; US law applies; first patent search done | `LEGAL_RESEARCH_BOUNDARIES.md` |

Open research tasks, which run alongside the prototypes: owner recordings R2 and R3; re-read Hecker's liner notes
and GDC 2007 slides when chrishecker.com is back (S2, S7); fuller patent search on skin generation, rigging and gait.

## 2. Engineering plan

All prototype work lives in `prototypes/creature-lab/`. It does not use code from `game/`, and Stage 1's first step
makes sure the main project's import, tests and Windows export skip that folder (checked by a test). Each stage has its own tests, run headless the same way `tools/check.sh` runs tests.
Commit and push after every step.

### Stage 1: Body and skin (first prototype, **gate: awaiting approval**)

What: `BodyDescription` + validation, skeleton layout, capsule primitives, field, Surface Nets mesh, smoothing,
normals, automatic weights, a `Skeleton3D` + `Skin` + `ArrayMesh` in a viewer scene. Ten fixed test bodies from data
files (snake, biped, quadruped, hexapod, 12-limb, giant limb, tiny, max vertebrae, thin, asymmetric). A viewer scene
orbits each body and poses its skeleton through a scripted range. No editor UI yet, no parts yet (sockets only), no
animation beyond the posing sweep.

Acceptance: `CREATURE_GEOMETRY_SPEC.md` §10 items 1–7 (Blender parity, item 8, comes in stage 4). Contact sheet of
all ten bodies at rest and posed, in both renderers.

Size: about 2–4 working sessions. Output: the prototype, its tests, contact sheets, measured rebuild times, and a short
report on whether GDScript is fast enough.

### Stage 2: Live editing (**gate**)

What: drag vertebrae, add or remove vertebrae, pull limbs out of the body, add joints, mirror symmetry, thickness
handles, undo; dirty-region rebuild while dragging. Placeholder sphere "parts" attach to sockets.

Acceptance: preview rebuild under 33 ms on the baseline PC for the large test body; edits refused with a reason when
invalid; description round-trips through JSON unchanged; R207 comparison (Spore's lag) recorded.

### Stage 3: Anatomy-driven locomotion (**gate**)

What: `PROCEDURAL_ANIMATION_SPEC.md` §3.1–3.4 on generated bodies: body descriptor numbers, gait planner, foot
targets, Godot's `TwoBoneIK3D`/`FABRIK3D` per leg, spine bend, `LookAtModifier3D`, `SpringBoneSimulator3D` on tails;
crawl and float fallbacks. Walk the ten test bodies around a flat test field under keyboard control.

Acceptance: `PROCEDURAL_ANIMATION_SPEC.md` §6 items 1–5 and 8; R307–R311 comparison table against Spore recordings;
a side-by-side clip of two bodies with different leg lengths showing different speed and turning.

### Stage 4: Parts, paint and Blender parity (**gate**, with the art thread)

What: three Blender-authored test parts (a mouth, a foot, a grasper) with shape-key handles, sockets and records,
attached to generated bodies; the spine/angle vertex channels and a first creature shader (base, coat, detail);
the Blender script that rebuilds a description as a `.blend` for review.

Acceptance: `CREATURE_GEOMETRY_SPEC.md` §10 item 8; part bases sit in the skin with no gaps on all ten bodies; art
thread review against the visual bar.

### Stage 5: Motion clips and interactions (**gate**)

What: the semantic clip format (`PROCEDURAL_ANIMATION_SPEC.md` §3.3): eat, grab, look, call, attack, with capability
requirements and fallbacks (mouth as hand); the clip pass grid on all test bodies.

Acceptance: §6 item 7 (90% pass grid) and a clip preview scene showing one clip on the grid of bodies.

### Promotion into the game (**gate**, owner decision)

Only after the stages above pass: a plan to move the generator and animation into `game/` for the era that first
needs them, including the save schema change for `BodyDescription`, the `tests/test_placeholders.gd` rule for
generated production meshes, an asset record for the generator, and the effect on milestone scope. That is a
separate decision; nothing in this roadmap commits to it.

## 3. Decisions needed from the owner

1. **Approve Stage 1** as an isolated prototype in `prototypes/creature-lab/` (recommended). Nothing in `game/`
   changes.
2. Record sessions R2 and R3 when convenient (about 1.5 hours together).
3. Later, at Stage 2: if GDScript is too slow, choose between a compute shader (no new dependency, not available on the
   Compatibility renderer) and a C++ GDExtension (new toolchain and the MIT `godot-cpp` dependency).

## 4. Out of scope for now

- Tribal, civilization and space stage research (owner's priority).
- Binary analysis of Spore (not cleared; `LEGAL_RESEARCH_BOUNDARIES.md` §5).
- Online sharing of creatures (IB-29; patent review needed first, `LEGAL_RESEARCH_BOUNDARIES.md` §3).
- REA or Ghidra setup.
