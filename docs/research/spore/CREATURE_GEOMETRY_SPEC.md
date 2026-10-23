# Creature geometry, skeleton and automatic rigging spec (GENESIS)

Status: PROPOSED specification, 2026-10-23. The direction is CONFIRMED (owner, DECISIONS.md 2026-10-23 "Generated
creature skins"): players build a whole creature freely and GENESIS generates the skin, skeleton and skin weights.
Every number, limit and algorithm choice below is PROPOSED until a prototype measures it and the owner approves.
Nothing here changes `game/` yet. Labels as in `LEGAL_RESEARCH_BOUNDARIES.md`; source IDs as in
`SPORE_RESEARCH.md` §3.

This is an original design. It uses textbook techniques (implicit surfaces, polygonization, skinning) that have
decades of public literature, and it cites where Spore's developers published a similar idea.

## 1. What Spore did (published), and where GENESIS goes further

| Topic | Spore (source) | GENESIS |
| --- | --- | --- |
| Base shape | A 3D "bean" with pullable points that work like vertebrae, the creature's "deep structure" (S12 Gingold) | Same idea: a spine of vertebrae is the editable core |
| Symmetry | Required: "all living things are symmetrical" (S12) | Symmetric by default; off-centre limbs and parts are mirrored automatically |
| Topology | Tree only; looped spines were removed because they broke animation (S1 footnote 1, S13) | Tree only |
| Skin | One implicit surface of spherical metaballs along spine and limbs, rebuilt live while editing; ellipsoids rejected as slow; no blend groups (S7, via secondary summaries; re-verify) | Implicit surface of tapered **capsule** primitives with blend rules (§4), rebuilt live |
| Tessellation | Developer says he avoided marching cubes because its patent was live during development and used an ear-clipping method instead; the patent expired before ship (S7, via secondary summary; re-verify) | Marching cubes' patent (US 4,710,876) expired in 2005; we use Surface Nets (§5), which is public and unpatented as far as we know |
| Parts | Artist-made "rigblocks" with handle-driven deform animations, baked after editing (S3) | Blender-authored parts with shape-key handles (the approved IB-15 mechanism still applies to parts) |
| Data size | Creature stored as instructions: "approximately 2-5 Kbytes" (patent US7867093B2), "4k" (S12) | Same goal: a compact body description, everything else rebuilt from it |
| Shape and gameplay | "The player's creativity in designing the creature's shape has no impact on actual gameplay"; part stats were fixed regardless of placement or limb length (S14, Soren Johnson) | **This is where GENESIS differs**: limb length, leg count, stance width, body mass and part placement change speed, turning, stability and reach (`PROCEDURAL_ANIMATION_SPEC.md` §4) |

The last row matters most. Spore's own team says shape did not affect play in the Creature stage. A modern successor
can make the body the gameplay.

## 2. Pipeline

```
BodyDescription  ->  Skeleton  ->  Primitives  ->  Field  ->  Surface Nets mesh  ->  Smooth + normals  ->  Weights  ->  Skinned mesh
(compact data)       (bones,       (capsules       (grid,      (quads -> tris)       (gradient normals)    (from field     + attached
                      caps)         per bone)       bounded)                                                 contributions)  Blender parts
```

Domain part (`BodyDescription`, validation, skeleton layout, stats) is pure and testable. The mesh build is a
service that produces arrays; scenes only display the result (CLAUDE.md layering).

## 3. BodyDescription (the creature's "genome body")

Compact, versioned data. In the prototype it lives in the prototype folder; moving it into saves is a **save
schema change**, which needs the owner's approval when that time comes.

- **Spine:** 3–24 vertebrae (PROPOSED). Each has a position (the spine is a polyline the player drags, kept as
  points) and a radius. Vertebra 0 is the head end.
- **Limbs:** 0–12 limbs (PROPOSED; each mirrored pair counts as two). Each has an attach vertebra, side (left,
  right or centre), and 2–6 joints with position and radius.
- **Parts:** 0–24 (PROPOSED). Each is a Blender-authored part id, attached to a vertebra or to a limb's last joint,
  with an offset on the skin, an orientation, a uniform scale and its shape-key handle values (0..1).
- **Symmetry flag** per limb and part (default on).
- **Paint:** base, coat, detail pattern ids and up to three colours (§8).
- Target size: under 4 KB as JSON for a large creature (comparable with Spore's published figure).

Validation (domain, pure): ranges, counts, connectedness (every limb attaches to an existing vertebra), minimum
radius, no NaN, symmetry consistency. Invalid edits are refused with a reason the editor can show (IB-02 style).

## 4. Skeleton and primitives

- **Bones.** One bone per vertebra, a chain from a root at the vertebra nearest the centre of mass (so the body
  pivots naturally) out to the head and to the tail. One bone per limb joint, parented to its attach vertebra. One
  socket bone per part. Names are deterministic: `spine_07`, `limb_L2_j1`, `part_04`. Rest pose = the edited pose.
- **Capabilities** come from parts (mouth, grasper, foot, eye, fin, etc.) and are written onto the bone that holds
  the part, plus `spine` on vertebrae and `limb` on limb joints. A leg = path from a `foot` bone to its first
  `spine` ancestor (S1 §4.2).
- **Primitives.** Each consecutive pair of joints along the spine and along each limb makes a tapered capsule
  (segment with radius interpolated between the two joints). Capsules follow limbs better than chains of spheres
  and need fewer primitives; Spore used spheres, citing speed (S7), and our feasibility number below suggests
  capsules are affordable.
- **Field.** Each primitive contributes a compact-support falloff of the distance to its segment, normalised by its
  radius, using the classic "soft object" polynomial (Wyvill, McPheeters and Wyvill 1986): f = (1 − d²/R²)³ for
  d < R, else 0. The surface is where the summed field equals an iso value. Compact support means each primitive only
  touches nearby grid cells.
- **Blend rules** (GENESIS addition; Spore had one big blob): a limb's primitives blend with their own attach
  vertebrae and each other, but are combined with other limbs by a smooth-union with a small blend radius, so two
  legs side by side do not melt into one. PROPOSED; the prototype compares plain sum versus this.

## 5. Polygonization

- **Grid.** An axis-aligned box around the primitives, with cells sized from the creature length:
  edit preview about length/48, final bake about length/96 (PROPOSED). Only cells inside some primitive's support are
  visited (sparse by bounding boxes).
- **Surface Nets** (Gibson 1998, "Constrained elastic surface nets"; the common "naive surface nets" variant): one
  vertex per cell that the surface crosses, placed at the mean of the edge crossings; quads between neighbours; split
  into triangles. Fewer, better-shaped triangles than marching cubes and simpler to write.
- **Smoothing.** Two or three Taubin smoothing passes, then each vertex projected back toward the iso surface along
  the field gradient. Normals from the analytic field gradient (smooth, no faceting).
- **Incremental rebuild while dragging.** Recompute only the region around the edited primitive (dirty box), at the
  preview resolution; full bake when the player releases the handle or leaves the editor.
- **Triangle budget.** Skin at gameplay LOD under 8 000 triangles for a large creature (PROPOSED, fits the existing
  triangle-reduction rule in DECISIONS.md 2026-10-22 "Triangle reduction"). Reduction by coarser grid for distant LODs.

Feasibility probe (OBSERVED, scratch test, not in the repo): splatting 40 compact-support blobs into a 48³ grid in
GDScript took about 13 ms on the cloud test machine (Intel Xeon 2.1 GHz, Godot 4.7.2 headless), plus about 4 ms to
scan for surface crossings. HYPOTHESIS: a full preview rebuild in GDScript lands at 30–80 ms, fine on handle release
and borderline for live dragging. Fallbacks if too slow, in order: dirty-region rebuild; lower preview grid;
a compute shader (works on Forward+ and Mobile, not on the Compatibility renderer); a C++ GDExtension (needs owner
approval: new toolchain and the MIT `godot-cpp` dependency).

## 6. Automatic rigging (skin weights)

Because GENESIS builds the skin from primitives that belong to bones, weights come for free:

1. For each vertex, compute each primitive's field contribution at that vertex.
2. A capsule between joints A and B gives its contribution to bones A and B, split by the vertex's projection
   parameter t along the segment ((1 − t) to A, t to B), so elbows and knees bend smoothly.
3. Keep the 4 largest bone weights (Godot default; 8 is available via `Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS`,
   CONFIRMED present in 4.7.2), normalise to sum 1.
4. One or two passes of weight smoothing across mesh neighbours to remove creases where limbs meet the torso.
5. Parts are rigid: each Blender part is parented to its socket bone (`BoneAttachment3D`) or merged into the creature
   mesh with weight 1 on that bone. Part bases sink into the skin by a set depth so no gap shows.

HYPOTHESIS: Spore weighted its skin in a similar way, since its skin is also built from primitives along bones. Not
stated in any source we have; recorded so nobody presents it as fact.

Godot side: build an `ArrayMesh` with `ARRAY_BONES` and `ARRAY_WEIGHTS`, a `Skin` resource with one bind per bone,
and a `Skeleton3D` from §4. All of these exist in 4.7.2 (CONFIRMED by a ClassDB probe of the pinned binary,
2026-10-23).

## 7. Collision and gameplay numbers

- Collision: one capsule per bone from the same primitive radii; parts add their own Blender-authored proxies.
  Refit is exact by construction, which removes the "collision proxies drift from shape" risk noted in IB-15.
- Mass and inertia: from primitive volumes (capsule volume formula), used by locomotion (`PROCEDURAL_ANIMATION_SPEC.md`
  §3.1).
- Silhouette metrics for gameplay and readability: length, height at the hips, stance width, number of feet,
  support polygon area, centre of mass height.

## 8. Surface colour without hand-made UVs

- Each skin vertex stores extra channels (Godot `CUSTOM0`): position along the spine (0 at head, 1 at tail), angle
  around the body (0 on the back, 0.5 on the belly), limb id and distance along the limb.
- The creature shader builds patterns from those channels: a base colour, a coat that follows the back and fades
  to the belly, details such as stripes across the spine coordinate or spots seeded per creature. Fine detail textures
  (CC0 or our own) are applied triplanar so stretched shapes do not smear.
- This follows the player-facing idea Spore published (base, coat, detail, colours, themes; S4) with different
  machinery: S4 painted pixels with particle brushes over generated UVs.
- Optional bake to a texture at editor close if shader cost is too high on the minimum spec (later decision).

## 9. Blender's role

The Bible's rule that production 3D assets are authored and finished in Blender stays true for everything the
artists make:

- All parts (mouths, eyes, hands, feet, fins, spikes, horns and so on) with shape keys, sockets, collision proxies,
  records and GLBs, through the existing pipeline and tests.
- Pattern and detail textures, materials, and the shader's look development.
- A Blender script that rebuilds any `BodyDescription` as a `.blend` (same algorithm, Python) for art review, hero
  renders and marketing; it is also the reference implementation the Godot output is tested against.
- The generator itself gets an asset record (settings, budgets, version) under `assets/records/`, and
  `tests/test_placeholders.gd` gets a rule that recognises it as production when it moves into `game/`. Both are
  changes for the build phase, not now.

## 10. Acceptance tests for the prototype

1. **Determinism:** the same description gives a byte-identical mesh (hash) across runs.
2. **Watertight and single piece:** every edge shared by exactly two triangles; one connected component per creature
   (parts excluded).
3. **Weights:** every vertex has at least one weight; weights sum to 1 ± 1e-4; no vertex on a limb has more than
   10% weight on a bone of a different limb.
4. **Budgets:** preview rebuild under 33 ms and final bake under 250 ms for the large test body on the baseline PC
   (RTX 5070 machine; CPU is a Ryzen 7 9800X3D); skin under 8 000 triangles at gameplay LOD.
5. **Extremes:** the test matrix (thin long snake, 12 limbs, one huge limb, tiny body, maximum vertebrae, all
   vertebrae at minimum radius) builds without errors and passes 2 and 3.
6. **Deformation:** posing the skeleton through a scripted range (spine bend ±60°, limbs ±90°) shows no vertex
   farther than 5% of body length from where linear blend skinning predicts, and no visible tearing at the joints
   in the review contact sheet.
7. **Size:** the large test body's description is under 4 KB as JSON.
8. **Blender parity:** the Blender script and the Godot generator give meshes whose surfaces are within one preview
   cell of each other.

## 11. Open questions

- Smooth-union blend rules versus plain sum: decided by the prototype's contact sheets.
- Whether the editor drags vertebrae directly (Spore-like) or uses a spine curve with handles; the measurement plan
  records how Spore feels (R2xx rows) as a comparison.
- Minimum-spec performance once the owner sets a minimum PC (DECISIONS.md, M1 brief item 7).
