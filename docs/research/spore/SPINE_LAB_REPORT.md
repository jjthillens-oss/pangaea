# Spine Lab report (prototype 0b)

Status: PROTOTYPE results, 2026-10-23. Built on the owner's go ahead to start the next creature prototype. The code is in
`prototypes/creature-lab/` next to Gait Lab. Nothing in `game/` changed. The numbers come from the cloud test machine
(4 vCPU Xeon, **no GPU**: the compute shader ran on lavapipe, Mesa's software Vulkan on the CPU, Godot 4.7.2). A real
graphics card will be much faster on the GPU path. Nothing here is Windows-verified.

Inputs: only the GENESIS specs (`CREATURE_GEOMETRY_SPEC.md`, `workstreams/creature_editor.md` §8) and public
techniques (soft-object falloff, Wyvill et al. 1986; Surface Nets, Gibson 1998). No Spore material.

## 1. Result

The question 0b had to answer was whether live editing can rebuild the skin fast enough, and in which path. **The
compute shader path does it without C++.** Even on a software GPU, the preview grid rebuilds in 6–30 ms, inside the
33 ms live-drag target. GDScript alone takes 80–475 ms, so it is a fallback and the reference that the GPU result is
checked against, not the live path.

| Body (vertebrae) | Triangles at /48 | GDScript /48 | GPU /48 | GDScript /96 (bake) | GPU /96 (bake) |
| --- | --- | --- | --- | --- | --- |
| bean (3) | 10 908 | 189 ms | 30 ms | 1 200 ms | 146 ms |
| worm (16) | 2 688 | 82 ms | 6 ms | 434 ms | 25 ms |
| fish (10) | 6 204 | 175 ms | 18 ms | 978 ms | 76 ms |
| snake (24) | 1 948 | 116 ms | 9 ms | 692 ms | 28 ms |
| tadpole (6) | 7 696 | 175 ms | 25 ms | 877 ms | 115 ms |
| arch (12) | 4 236 | 128 ms | 9 ms | 461 ms | 45 ms |
| large (24) | 8 156 | 475 ms | 24 ms | 2 504 ms | 119 ms |

GPU times are the median of repeat builds. The first GPU build in a session pays about 1.3 s of pipeline set-up once.
Source: `prototypes/creature-lab/results/skin_bench.json` (`tools/skin_bench.gd`).

Checks (`tests/run_spine_tests.gd`, 46 checks, all passing):

- The GPU mesh is the same as the GDScript mesh: same vertex and triangle order, positions within 0.00005 of a cell.
  Repeat GPU builds are identical.
- Every skin is closed, one piece and wound the right way, for the 7 test bodies and 25 random valid spines.
- Two builds of a body give the same SHA-256.
- Every vertex has four bone weights that sum to 1.
- The large body has 5 656 triangles at the gameplay grid (length/40), under the 8 000 budget.

## 2. Body description and save format (PROPOSED)

- A spine body is 3–24 vertebrae. Positions and radii are whole numbers in thousandths of the body's reference length,
  so a save never holds a float and the same body always writes the same text.
- Each vertebra has a stable id (`v_N`). Ids are never reused, so a later part or limb can point at a vertebra safely.
- The encoder writes keys in a fixed order with no spaces. Encode, decode, encode is byte-identical for the 7 test
  bodies and 1 000 random ones, including after a round trip through Godot's own JSON.
- Unknown fields are kept and written back, so an older build does not destroy a newer body. A newer version number is
  refused with a reason. Bad values are reported, not silently changed.
- The largest spine body is 1 177 bytes, against a 4 096-byte budget.
- Validation refuses bodies that cannot skin well and says why: too few or too many vertebrae, out of bounds,
  too thin for the grid, neighbours too different in size, a fold sharper than 30°, or a spine touching itself.

This is a prototype format. It does not change the game's save schema, which needs the owner's approval.

## 3. How the skin is built

1. Each pair of neighbouring vertebrae makes a tapered capsule with a soft falloff. Capsules are blended with a
   p-norm (P = 3). A plain sum bulged at the joints and a plain max left creases; P = 3 does neither.
2. The field is sampled on a grid sized from the body (preview length/48, gameplay length/40, bake length/96).
3. Surface Nets puts one vertex in each grid cell the surface crosses and joins them into quads.
4. Tight bends can leave ambiguous cells that would make the skin non-manifold. A fix pass finds them with a 256-entry
   table and nudges one corner. Both builders run it the same way, so the meshes still match. It fired on 1 of 14
   bench builds and on 4 of 25 random spines.
5. Normals come from the field gradient. Bone weights are the four strongest capsule contributions.
6. **Paint coordinates** go into the mesh as CUSTOM0 for the art team's skin shader: position along the spine (0 head,
   1 tail), angle around the body (0 back, 0.25 right side, 0.5 belly), limb id and distance along the limb. The art
   contract (`docs/art/creature_art_contract.md` §4) uses this layout. CUSTOM1 holds each vertex's rest-pose position,
   so spots and cells painted in rest space stay round and fixed to the body when it bends; `spine_rig.gd
   body_length_m()` gives the matching shader uniform.

## 4. Not covered yet

- Limbs, parts and junctions between them (Stage 1).
- Mesh smoothing, and an editor to drag vertebrae (the viewer only loads fixed bodies and swims them).
- Timing on a real GPU and on the baseline PC.

## 5. Recommendation

1. Use the compute shader as the live path for Stage 1. A C++ GDExtension is not needed for the skin (roadmap
   decision 4 can close as "no").
2. Measure on the owner's PC when convenient: one command, `tools/skin_bench.gd`, under the Forward+ renderer.
3. Start Stage 1 (limbs on the spine, ten test bodies) after the owner approves it.
