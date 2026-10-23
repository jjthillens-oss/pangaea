# Creature creator analysis

Status: PROPOSED research, 2026-10-23. Labels are defined in `LEGAL_RESEARCH_BOUNDARIES.md`. Source IDs (S1–S11)
refer to `SPORE_RESEARCH.md` §3. Everything about Spore here comes from published developer papers or from
observation; nothing comes from game files.

## 1. How Spore's creature editor is built (published)

### 1.1 Body structure

- CONFIRMED (S1 §1.2): a creature is a set of **bodies** (spine segments, limb segments and parts) linked in a
  directed acyclic graph, with a serial chain of spine bodies at the root. Early prototypes allowed general graphs,
  including loops, but "testing revealed the interface complexity of a general graph was actually a hindrance to
  player creativity" (S1, footnote 1).
- CONFIRMED (S1): each body carries **capabilities** ("caps") such as grasper, foot, mouth, spine, root. Caps are
  the link between what a part looks like and what the code can do with it. Gameplay AI and inventory code query
  bodies by cap and position, the same way animators do (S1 §3.1.2).
- CONFIRMED (S1 §4.2): a **leg** is a path through the graph from a foot body to a spine body (the hip). So "how
  many legs" is computed from the graph, not stored.
- CONFIRMED (S1 §1.2): bodies of the same type respond to standard **deform curves** (mouth open/close, hand
  open/close, eyes blink, ears droop, toes bend). The animation system treats them as opaque scalars.

### 1.2 Parts: rigblocks

- CONFIRMED (S3): each part is an artist-made model (Maya) plus a set of deform animations, each parameterized over
  the unit interval rather than over time. The player drags a **handle** shown near the feature; the handle scrubs
  that animation from 0 to 1.
- CONFIRMED (S3): several deforms on one part compose **additively** (translation, rotation and scale deltas summed
  per bone, then turned into a matrix), so applying one does not undo another and the order does not matter.
  Morph targets are supported but avoided for memory and runtime cost.
- CONFIRMED (S3): when the player finishes, the model is **baked**: deform data is removed and a static model is
  kept for in-game rendering.
- CONFIRMED (S3): subranges of a handle can produce completely different styles of part, not just bigger or smaller.

### 1.3 Skin (the torso surface)

- CONFIRMED by developer statement (S7, read via a search summary because the site was down on 2026-10-23;
  re-verify): the torso skin is a "blobby implicit surface" made of **spherical metaballs only**, distributed along
  spine and limbs, rebuilt in real time while the player edits. Ellipsoids were rejected as too slow to evaluate.
- HYPOTHESIS: the surface is polygonized each edit (marching cubes or similar), and skin weights are derived from
  the nearest spine and limb bodies. Not stated in the sources we have; do not treat as fact.

### 1.4 Paint

- CONFIRMED (S4): the creature has a main body mesh plus attached detail parts. Particle-driven **brushes** (run by
  the effects system, "Swarm") move over the mesh and paint directly into diffuse, specular and bump textures.
  Custom components run paint "up and down a creature's spine and limbs" and cover the skin with oriented strokes.
- CONFIRMED (S4): the player picks one **base**, one **coat** and one **detail** paint script, plus colours; themes
  are one-click presets of these.
- CONFIRMED (S4): body UVs are generated quickly by **cubemap partitioning**. Lighting in the editor and game uses
  spherical harmonics blending diffuse and glossy terms.
- CONFIRMED (S4, vehicles/buildings): procedural UVs (planar, cylindrical, box projection) are applied in the
  vertex shader so deformed parts do not stretch textures; a final texture page is splatted together and an
  ambient-occlusion map is baked.

### 1.5 Live animation in the editor

- CONFIRMED (S1 §5): "The in-game editor begins playing animations on the character as soon as the player adds
  feet, mouths, or graspers." That instant feedback is the "comes to life" moment.
- OBSERVED (S11): parts carry gameplay ability levels; the editor shows the sum.

## 2. Observations still to record

These need our own recordings (`MEASUREMENT_PLAN.md`, session R2). Values go in `GAMEPLAY_MEASUREMENTS.csv`.

- Spine segment count limits, and how thickness and length are set (drag versus scroll).
- Symmetry behaviour: when parts mirror, and whether asymmetric placement is allowed.
- Part count and complexity limits (the complexity meter): what fills it.
- Size range from smallest to largest legal body (in the editor, measured against the grid or a reference part).
- Latency from adding a leg to the first walk cycle in the editor (frames).
- What the test drive shows: which animations play on an unusual body (no legs, many legs, legs of different
  lengths).

## 3. What GENESIS takes, and what it does not

| Spore idea | Take it? | GENESIS version (PROPOSED unless marked) |
| --- | --- | --- |
| Capabilities on parts as the single bridge between art and code | **Yes** | Each part type in `game/data/part_catalog.json` already has effects; add a `capabilities` list (mouth, grasper, foot, fin, sensor, spine) used by animation, AI and gameplay queries. Named `capabilities` because `caps` already means stat ceilings in that file. |
| Body as a tree with a spine chain at the root | **Yes** | Matches Godot `Skeleton3D` naturally. Trees only, no loops (Spore's own finding). |
| Legs computed from the graph | **Yes** | A leg is a path from a `foot` cap to a `spine` bone. Computed, never stored in saves. |
| Parts deformed by handles scrubbing 0..1 | **Yes, within the approved boundary** | Handles drive Blender-authored shape keys and bone scale (CONFIRMED boundary, DECISIONS.md 2026-10-22, IB-15 option B). Limits per part are tuning data. |
| Additive composition of deforms | **Yes** | Shape keys are additive in Godot already; bone-scale deltas are summed, then applied. Test: order independence. |
| Baking the finished creature | **Yes** | After the editor closes, merge static parts into fewer meshes for draw calls; keep the skeleton. Measured against the M2 performance budget. |
| Implicit-surface (metaball) skin rebuilt at runtime | **Yes (changed 2026-10-23)** | The owner chose generated skins (DECISIONS.md 2026-10-23). GENESIS design: `CREATURE_GEOMETRY_SPEC.md`. §4 below is kept as a fallback only. |
| Particle brushes painting textures at runtime | **Not now** | Generating texture pixels at runtime is not a mesh, so the boundary does not forbid it, but it is a scope expansion that needs approval. §5 proposes a shader-based alternative. |
| Instant animation in the editor as parts are added | **Yes** | Core acceptance criterion in `PROCEDURAL_ANIMATION_SPEC.md` §6. |
| Ability levels summed from parts | **Already ours** | M1 part catalog does this with diminishing returns. Keep GENESIS names and numbers. |

## 4. Fallback: body variety without generated skins (superseded 2026-10-23)

Kept only as a fallback if generated skins fail their prototype tests. The owner's chosen direction is
`CREATURE_GEOMETRY_SPEC.md`.

Without a generated surface, a wide range of bodies is still possible:

1. **Segmented torso from Blender-authored segments.** The torso is a chain of 3–N Blender-authored segment meshes
   (head, neck, chest, belly, hip, tail), each skinned to its own spine bone with overlap zones weighted to both
   neighbours. Shape keys per segment: thickness, length, belly, hump, flatten. Bone scale for length.
2. **Seam handling.** Neighbouring segments are authored to share an identical ring of vertices at their joint for
   each shape-key extreme, so any mix of keys keeps the seam closed. A Blender test script checks ring match at
   every key combination corner (the extremes), in the spirit of the existing asset tests.
3. **Spine curve.** The editor bends the spine by rotating spine bones (rest pose edit), not by moving vertices.
4. **Collision.** Proxies (capsules per segment) refit from bone lengths and key values; tested at extremes, as the
   boundary decision requires.

Risk: a segmented body can look modular next to Spore's smooth skin. Mitigation to test in a spike: wide overlap
zones plus a shared material and a subtle normal-map seam blend. If the owner wants a truly continuous skin later,
that is a change to the IB-15 decision and his call.

## 5. Colouring (PROPOSED; the generated-skin version is in `CREATURE_GEOMETRY_SPEC.md` §8)

Spore paints pixels with particles. A cheaper approach that fits GENESIS's glTF-safe materials:

- Each part and segment is authored in Blender with **mask channels** (vertex colours or a mask texture): base
  region, back/coat region, detail region (stripes, spots), and a "spine distance" gradient.
- One creature shader combines three player choices (base, coat, detail pattern) and up to three palette colours,
  using those masks. Patterns are CC0 or our own tileable textures, projected with triplanar mapping so stretched
  parts do not smear.
- The result can be baked to a texture at editor close (a viewport render to texture), which stays a runtime
  texture, not a mesh. Whether that bake step is in scope is a question for the M2/M3 plan.

This follows S4's player-facing idea (base, coat, detail, colours, themes) while using different machinery.

## 6. Hypotheses we will not test by binary analysis

Recorded so nobody "fills the gap" by guessing:

- How Spore weights its skin to bones (HYPOTHESIS §1.3).
- How the complexity meter is computed. OBSERVED behaviour only, from recordings.
- How ability levels map to speed or damage numbers internally. Only externally measured values will be recorded.
