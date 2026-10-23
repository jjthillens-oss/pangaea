# Stage 1 report: limbs on the spine

Status: PROTOTYPE results, 2026-10-23. Built under the owner's standing rule to keep building (relayed by the
coordinator, 08:08). The code is in `prototypes/creature-lab/`, next to Gait Lab and Spine Lab. Nothing in `game/`
changed. The numbers come from the cloud test machine (4 vCPU Xeon, no GPU; the compute shader ran on lavapipe,
Mesa's software Vulkan). Not Windows-verified.

Inputs: the GENESIS specs (`CREATURE_GEOMETRY_SPEC.md` §10, `GENESIS_IMPLEMENTATION_ROADMAP.md` Stage 1) and the
art contract (`docs/art/creature_art_contract.md`). No Spore material.

## 1. Result

Creatures now have limbs. A limb is a chain of 2–5 joints that starts on a vertebra. A mirrored limb also makes its
copy on the other side, so a pair stays symmetric while it is edited. The skin, skeleton and weights cover limbs in
both builders, and the GPU path still gives the same mesh and bones as GDScript.

All ten bodies in the spec's test matrix are valid, closed and one piece, with no hand fixes:

- snake;
- quadruped;
- biped;
- hexapod;
- twelve limbs;
- one giant limb;
- tiny;
- maximum vertebrae;
- thin (every radius at the grid minimum);
- asymmetric.

| Spec §10 test | Result |
| --- | --- |
| 1 Determinism | Same SHA-256 across builds (twelve-limb body) |
| 2 Watertight, one piece | All ten bodies, both builders |
| 3 Weights | Sum to 1 on real bones. Limb vertices put **0%** on another limb's bones: a vertex on a limb takes weights only from its own limb and the spine |
| 4 Budgets | Preview on the GPU: 8–45 ms on software Vulkan (the tiny, fat body is the slowest). Gameplay skin within 8 000 triangles for all ten; the tiny body drops to a coarser grid (/34) automatically |
| 5 Extremes | All ten build and pass 2 and 3 |
| 6 Deformation | **Partly.** Spine ±60° with limbs ±30° stays within 5% of body length on 9 of 10 bodies. At the spec's full ±90° limb swing, 7 of 10 miss (§3) |
| 7 Size | The test bodies encode in at most 1 492 bytes. The largest body the limits allow is 4 591 bytes, over the 4 KB target (§4) |

Checks: `tests/run_stage1_tests.gd`, 55 passing and one reported as KNOWN (the tiny body, §3). The spine tests still
pass, so version 1 bodies load unchanged.

## 2. What changed

- **Body description version 2.** Each limb has an id, the vertebra it attaches to, a mirror flag and its joints.
  Each joint has its own id and the same integer position and radius as a vertebra. New validation rules:
  - joint 0 must touch its vertebra;
  - 2–5 joints per limb, at most 12 limbs and 128 bones;
  - the same thickness, fold and grid rules as the spine;
  - a mirrored limb may not reach its own copy across the middle.
- **Skin.** Limb capsules join the spine's capsules in the same p-norm blend, so a limb meets the trunk with a small
  rounded fillet. Paint coordinates follow the art contract: `limb_id` 1 and up, and `limb_t` from 0 at the shoulder
  to 1 at the tip. On a limb, `spine_u` is the spine position of its vertebra.
- **Skeleton.** One bone per joint. Joint 0 hangs from its vertebra.
- **Gameplay level of detail.** If a body's gameplay skin is over budget, it is rebuilt on a coarser grid. Round,
  bulky bodies carry more surface per grid cell.
- **Viewer.** `spine_lab.tscn -- --body=stage1 --anim=pose` shows the ten bodies through the posing sweep.

## 3. Deformation (spec test 6)

Method: pose the generated skeleton, skin the rest mesh with linear blend skinning (what the engine does), then
measure how far each vertex lands from the surface the generator would build around the posed bones. Full matrix in
`results/pose_error.json` (`tools/pose_matrix.gd`), as maximum error over body length:

| Body | Bend 60° | Swing 30° | Swing 45° | Swing 90° | Bend 60° + swing 30° | Bend 60° + swing 90° |
| --- | --- | --- | --- | --- | --- | --- |
| snake | 0.4% | 0.4% | 0.4% | 0.4% | 0.4% | 0.4% |
| quadruped | 1.2% | 2.7% | 6.5% | 43.5% | 3.8% | 69.9% |
| biped | 1.2% | 2.0% | 4.1% | 21.3% | 2.1% | 66.0% |
| hexapod | 1.5% | 0.7% | 0.8% | 2.4% | 1.5% | 3.0% |
| twelve limbs | 2.0% | 1.2% | 4.4% | 16.2% | 3.3% | 18.0% |
| giant limb | 2.7% | 1.3% | 2.5% | 12.8% | 2.0% | 13.7% |
| tiny | 12.8% | 3.9% | 10.6% | 42.7% | 16.2% | 133.1% |
| max vertebrae | 0.9% | 0.9% | 0.9% | 1.9% | 0.9% | 2.1% |
| thin | 2.0% | 1.1% | 0.9% | 1.9% | 2.0% | 10.2% |
| asymmetric | 1.9% | 1.5% | 2.8% | 12.8% | 1.8% | 12.2% |

What it means:

- At gait-like angles (a trot swings a hip about 30°), skinning holds on everything except the tiny body.
- A 90° swing puts a leg inside the belly or the next leg. The regenerated reference surface then merges them, and
  a skinned mesh cannot. Part of the large numbers is that merge, not a visible fault. The pose clip shows no
  tearing at the joints.
- The tiny body has three fat vertebrae, so a 60° bend is 30° per joint. The inner side collapses, which is the
  known weakness of linear blend skinning.

Ways to close the gap, for a later step:

- dual-quaternion skinning (Godot has no built-in option; it would be a custom skinning shader);
- a helper bone at each shoulder and hip that takes half the swing;
- re-running the generator for strongly posed bodies, since the GPU path is fast enough to rebuild every few frames.

## 4. Description size

The spec's 4 KB target (§3) was set before limbs. The test bodies stay under 1.5 KB. The worst case the limits allow
is 24 vertebrae plus 12 limbs of 5 joints, every number at its widest, and it is 4.6 KB. Two options, for the owner:

- raise the target to 6 KB;
- shorten the keys (for example `p` and `r` already are; ids could drop their prefix).

Either way, parts will add more later, so the budget should be set when parts arrive.

## 5. GPU parity and timing

`tools/skin_bench.gd` now covers the ten bodies (`results/skin_bench.json`). The GPU and GDScript builders give the
same triangles and the same bones on every body at /48 and /96.

Paint coordinates differ on a few seam vertices (most in the biped at /96), where two capsules contribute almost
equally and float rounding picks a different one. Positions and weights are unaffected.

GPU preview at /48 takes 8–45 ms on software Vulkan; GDScript takes 0.1–0.75 s.

## 6. Next (PROPOSED)

1. Parts on the skin (mouths, eyes, feet), using the art team's part meshes and limb-end pivots
   (`creature_art_contract.md`).
2. Put Gait Lab's legs on a Stage 1 body, so a generated creature walks with its own skin.
3. One of the deformation fixes in §3.
4. An editor scene to drag vertebrae and joints, using the GPU rebuild.
