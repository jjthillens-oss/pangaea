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
| Anatomy-driven animation | Published in depth (S1, S13); S2 (GDC 2007) not read yet |  `PROCEDURAL_ANIMATION_SPEC.md` |
| Locomotion feel | Needs recordings (R2xx, R3xx) | `MEASUREMENT_PLAN.md` |
| Parts and handles | Published (S3) | `CREATURE_CREATOR_ANALYSIS.md` §1.2, §3 |
| Paint | Published (S4) | `CREATURE_GEOMETRY_SPEC.md` §8 |
| Legal and patents | EA license reviewed; US law applies; first patent search done | `LEGAL_RESEARCH_BOUNDARIES.md` |

Open research tasks, which run alongside the prototypes: owner recordings R2 and R3; re-read Hecker's liner notes
and GDC 2007 slides when chrishecker.com is back (S2, S7); fuller patent search on skin generation, rigging and gait.

## 2. Engineering plan

All prototype work lives in `prototypes/creature-lab/`. It does not use code from `game/`, and the first prototype's
first step makes sure the main project's import, tests and Windows export skip that folder (checked by a test). Each stage has its own tests, run headless the same way `tools/check.sh` runs tests.
Commit and push after every step.

### Stage 0: two small probes before Stage 1 (updated after the checkpoint, **gate: awaiting approval**)

The checkpoint (`CHECKPOINT_1.md`) replaced "start with full Stage 1" by two smaller prototypes, in this order:

- **0a Gait Lab** (`workstreams/locomotion.md` §9): two quadrupeds identical except for leg length, plus a hexapod,
  stepping with Godot's built-in two-bone IK on a flat plane. Tests that leg length sets speed and turning with no
  foot slip, and whether Godot's IK is good enough. No skin. About 1–2 sessions. **Approved and built 2026-10-23;
  all pass criteria met, built-in IK holds for legs** (`GAIT_LAB_REPORT.md`).
- **0b Spine skin and codec** (`workstreams/creature_editor.md` §8): a 3–24 vertebra body with no limbs or parts, the
  capsule skin at two grid sizes timed in GDScript and in one native path (compute shader), and the compact
  description encoder. Decides how live editing will be made fast. About 1–2 sessions. **Built 2026-10-23: the
  compute shader rebuilds the preview skin in 6–30 ms even on a software GPU; no C++ needed for the skin**
  (`SPINE_LAB_REPORT.md`).

Each gets its own owner approval. Stage 1 below starts only after 0b, and uses its timing result.

### Stage 1: Body and skin (**gate**)

What: `BodyDescription` + validation, skeleton layout, capsule primitives, field, Surface Nets mesh, smoothing,
normals, automatic weights, a `Skeleton3D` + `Skin` + `ArrayMesh` in a viewer scene. Ten fixed test bodies from data
files (snake, biped, quadruped, hexapod, 12-limb, giant limb, tiny, max vertebrae, thin, asymmetric). A viewer scene
orbits each body and poses its skeleton through a scripted range. No editor UI yet, no parts yet (sockets only), no
animation beyond the posing sweep.

Limbs attach to vertebrae only in Stage 1 (no limbs branching from limbs; a later option).

Acceptance: `CREATURE_GEOMETRY_SPEC.md` §10 items 1–3 and 5–7, plus **measured** rebuild and bake times in the path
chosen after 0b. The 33 ms live-preview target moves to Stage 2; probe 0b already showed GDScript alone cannot meet it.
Blender parity (item 8) comes in Stage 4. Contact sheet of all ten bodies at rest and posed, in both renderers.

Size: about 2–4 working sessions. Output: the prototype, its tests, contact sheets and timings.

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

1. ~~Approve prototype 0a, Gait Lab~~ Approved and built 2026-10-23 (`GAIT_LAB_REPORT.md`).
2. ~~Then approve 0b (spine skin and codec).~~ Built 2026-10-23 on the owner's go ahead (`SPINE_LAB_REPORT.md`).
3. Record sessions R2 and R3 when convenient (about 1.5 hours together).
4. After 0b (recommendation: the compute shader path is enough, so no): if the compute shader path is not enough, choose whether to allow a C++ GDExtension (new toolchain and
   the MIT `godot-cpp` dependency).
5. Bible §7 says "Support a small approved set of body plans first"; the 2026-10-23 decision asks for full free-form
   bodies like Spore. Confirm whether free-form bodies replace that line, or whether the first playable version ships
   a small approved set of body plans built with the free-form system.

## 4. Out of scope for now

- Tribal, civilization and space stage research (owner's priority).
- Binary analysis of Spore (not cleared; `LEGAL_RESEARCH_BOUNDARIES.md` §5).
- Online sharing of creatures (IB-29; patent review needed first, `LEGAL_RESEARCH_BOUNDARIES.md` §3).
- REA or Ghidra setup.
