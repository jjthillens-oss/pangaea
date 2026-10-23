# Workstream B: creature editor (body, attachment, saved description)

Status: PROPOSED research, written 2026-10-23 by research workstream B. Labels (CONFIRMED, OBSERVED, HYPOTHESIS,
PROPOSED) and source IDs S1–S16 are defined in `../LEGAL_RESEARCH_BOUNDARIES.md` and `../SPORE_RESEARCH.md` §3.
Nothing here changes `game/`, the save schema or any decision. Every number for GENESIS is PROPOSED tuning.

Question: for the creature creator, what do we know (documented, inferred, unknown) about (1) body/spine
representation, segment scaling and surface generation, (2) part attachment, symmetry, orientation and placement
constraints, and (3) how a creature's editable description is saved and rebuilt? What original GENESIS designs
follow?

## 0. Method and sources

Allowed methods only (`LEGAL_RESEARCH_BOUNDARIES.md` §4): published developer papers, slides, patents and press
reports. No Spore files, no community tools, no file-format documentation, no recordings yet (those are planned
rows; nothing was recorded for this file).

What was read for this file, on 2026-10-23:

| ID | What was read | Notes |
| --- | --- | --- |
| S1 | Full text of the SIGGRAPH 2008 paper (§1.2, §3, §4.1–4.3, §5) | Primary. The PDF link in `SPORE_RESEARCH.md` was down; read from an earlier download of the same paper. |
| S3 | The Rigblocks abstract **and its slides** (`https://www.cs.cmu.edu/~ajw/s2007/0248-Rigblocks.pdf`, `.../0248-Rigblocks-slides.pdf`) | Primary. The slides add creature-specific lines not recorded in our notes before; see §1.1 and §2.1. |
| S4 | Procedural texturing abstract (`.../0311-PaintingModels.pdf`) | Primary. Only the "main body mesh plus detail parts" line matters here. |
| S7 | Hecker's liner notes | Site still down ("temporarily down"); web.archive.org is blocked from this environment. Only a search-engine summary was available again: "I chose a blobby implicit surface (sometimes called metaballs) to represent the skin", started October 2003, chosen for topological robustness over local control. Still to be quoted directly. |
| S12 | Game Developer report of Gingold's talk | Re-read; quotes below are from the article. |
| S13 | IEEE Spectrum, "Engineering Spore" | Re-read; quotes below are from the article. |
| S15 | Patent US7867093B2 description (Google Patents, both halves of the page) | Primary for what EA disclosed about stored creature data. |
| S10b | Wikipedia, "Spore Creature Creator", <https://en.wikipedia.org/wiki/Spore_Creature_Creator> | Secondary. New in this file: released 17 June 2008 (NA); has a test environment; creatures shared through the Sporepedia. Nothing on symmetry or limits. |

Tried and not available: the Spore fandom wiki (HTTP 402), StrategyWiki's creature-editor page (HTTP 403), and a
retailer-hosted Creature Creator PDF (HTTP 404). Those community pages would only be secondary cross-checks for our
own recordings anyway.

## 1. Where GENESIS starts (M1 code, read-only)

The M1 cell editor already sets several conventions the creature editor should keep:

- `Genome` (`game/domain/genome.gd`, schema 1) holds `parts: [{id, type, angle, scale}]`, `appearance`, stable
  `part_N` ids and `next_part_number`. Placement is a single angle around a round cell, 0 = front, positive = the
  cell's right (`PlaneSpace.part_local_dir`: `(sin a, 0, -cos a)`, models face -Z).
- `Genome.from_dict` never drops a part; bad entries are kept and reported by `validate()` (Bible §18).
- `EditorSession` keeps a working copy, undo/redo as whole `to_dict()` snapshots, a refusal reason for every
  refused edit, and a transactional `commit()` (Bible §12).
- Mirroring today is `mirror_part`: it adds a second, independent part at `-angle`, and refuses parts within
  `|sin a| < 0.05` of the centre line. The mirror is not linked to the original.
- `Phenotype.derive` is the one stat calculation, with diminishing returns ranked by size so part order never
  matters.
- Saves are written with `JSON.stringify(dict, "\t")` (`persistence_service.gd`), which does **not** keep full
  float precision (see §4.4, probe P5).

There is no spine, limb, skin, skeleton or 3D placement yet. The 2026-10-23 decision makes the skin, skeleton and
weights generated; detail parts stay Blender-authored.

---

## 2. System 1: body, spine, segment scaling and surface

### 2.1 Observed behaviour and evidence

- The player shapes "a malleable clay-like torso containing the spine" and attaches limbs and parts (S1 §1.2).
- The torso and limbs are a set of **bodies** (transform, bounding box, parent) in a directed acyclic graph "with a
  serial chain of spine bodies at the root of the tree"; characters "usually contain between 20 and 80 bodies"
  (S1 §1.2). Early prototypes allowed general graphs with loops; "the interface complexity of a general graph was
  actually a hindrance to player creativity" (S1 footnote 1). S13 adds that looped spines broke animation:
  "bye-bye, doughnuts."
- The base shape was "a 3D bean" whose pullable points "looked like vertebrae, which also helped the animation
  system"; Gingold calls this "the deep structure of the creatures" (S12).
- S3 slides, "Note: Creatures": "Base block is a special block: body mesh"; "Allow player control over a basic
  skeleton – Adjust spline, glue limbs"; "Mesh generated via metaballs"; "Rigblocks attached to body". This is the
  only primary Maxis source we have that names the skin method, and it agrees with S7.
- S7 (summary only): blobby implicit surface, spherical metaballs, rebuilt live; chosen for topological robustness
  rather than local control.
- The pose the player builds in is the **rest pose**: "The position and orientation of the bodies at the time the
  player creates the character is called the rest pose ... We simply assume the player created the character in a
  'reasonable' rest configuration" (S1 §1.2). Players "sometimes adjust the rest pose after seeing their character
  animate" (S1 footnote 2).
- The animation root is "a unique spine body chosen by a heuristic based on the maximum number of incident leg limbs
  and the position of the body" (S1 §1.2).
- For IK, Spore fits a spline through spine joint positions between branch points; cubic splines "did not fit
  adequately in many common cases" because player spines have many inflection points, while quintic Hermite
  splines were sufficient (S1 §4.3.2). Interior spine bodies are stored as a parameter t plus an offset and
  orientation relative to a frame transported along the spline.
- Legs and limbs "can be stretched and curled like clay" (S13).

### 2.2 Documented, inferred, unknown

Documented (CONFIRMED by a primary or developer-quoted source):

1. The body is a tree of bodies with a serial spine chain at the root; no loops (S1, S13).
2. The skin is generated from metaballs around a player-controlled skeleton (S3 slides; S7).
3. The player's edit pose is the rest pose for animation (S1).
4. The skeleton editing is "adjust spline, glue limbs" (S3 slides).
5. Typical size: 20–80 bodies including parts (S1).
6. Player spines have many inflection points (S1 §4.3.2), so any GENESIS spine curve must handle wiggly input.

Inferred (HYPOTHESIS, not to be presented as Spore's implementation):

1. Each vertebra has its own thickness, and the metaball radii follow it (consistent with "pullable points" and
   with spheres along the spine, not stated).
2. The spine "spline" in S3 is the same vertebra chain the player drags, interpolated for display.
3. The skin is polygonized each edit by some contouring method; the method is unpublished apart from S7's summary.
4. Cross-sections are round, because spheres alone cannot make an elliptical section (would need many spheres).

Unknown (needs recordings or stays unknown):

1. Vertebra count limits and how vertebrae are added or removed (R201, R214).
2. Thickness range per vertebra and whether width and height can differ (R211, R220).
3. Whether the spine can leave the sagittal plane (R212).
4. Skin update lag while dragging (R207) and visible tessellation density (R222).
5. How two close limbs blend (R210).
6. Skin weights and polygonizer (we will not try to find out; `CREATURE_CREATOR_ANALYSIS.md` §6).

### 2.3 Specification (implementation-independent, PROPOSED)

1. A creature body is one **spine**: an ordered chain of 3 or more vertebrae from head end to tail end. Each
   vertebra has a position in body space and a thickness. The spine is a tree root; nothing loops.
2. **Limbs** branch from a vertebra (or, at most one level deep, from a limb joint). A limb is a chain of 2 or more
   joints, each with a position and a thickness.
3. Thickness varies smoothly between neighbouring vertebrae and joints. Optionally a vertebra has separate width and
   height (elliptical section); round is the default.
4. The skin is one closed, smooth, single-piece surface around the spine and all limbs. It has no holes, no
   self-intersections visible from outside and no seams. Limbs that touch blend; limbs that only come close stay
   visibly separate.
5. Editing any vertebra, joint or thickness updates the skin while the player drags (preview quality) and at full
   quality when the player releases.
6. The edit pose is the rest pose. The editor refuses or corrects poses that cannot animate (folded spine, limb
   inside the torso), with a reason.
7. The same body always gives the same skin on the same machine; across machines the skin may differ only within a
   small tolerance.
8. Skin, skeleton, collision and mass are derived; none of them is saved as authority (§4).

### 2.4 Implementation options

**Spine representation**

| | S-A: vertebra chain (points the player drags) | S-B: spline with few handles, vertebrae resampled |
| --- | --- | --- |
| Feel | Direct, Spore-like "pull a vertebra" (S12) | Smoother curves, fewer handles, less fiddly |
| Data | 3–24 points × (pos, radius) | 2–8 handles + segment count; vertebrae derived |
| Skeleton | Bone per vertebra, stable ids natural | Bone count can change when the curve changes length, so ids are less stable |
| Animation | Wiggly spines need a robust curve for IK (S1 found cubics insufficient); interpolate with centripetal Catmull–Rom for display and a rotation-minimizing frame for orientation | Already a curve |
| Risk | Kinks between points if the player zig-zags | Feels less "clay"; inserting local detail needs more handles |

Recommendation: S-A for data and skeleton, with an editor helper that smooths neighbours when one vertebra is
dragged (falloff over 1–2 neighbours, PROPOSED). Store points, not curves.

**Segment scaling**

| | Round thickness per vertebra | Width + height per vertebra (elliptical) |
| --- | --- | --- |
| Look | Tubes and beans; flat bodies (rays, turtles) only by many limbs | Flat fish, broad beetles, deep-chested runners |
| Field cost | Distance to segment | Distance in a scaled local frame; about 1.5–2× per sample (HYPOTHESIS, to time) |
| Weights, collision | Capsules, exact | Capsules approximate; collision needs boxes or convex hulls |

Recommendation: round first (prototype Stage 1), elliptical as a measured Stage 2 add-on. It is a clear way to go
beyond what spheres allow.

**Surface generation** (the core choice)

| | F-1: tapered-capsule implicit field + Surface Nets (current spec) | F-2: swept generalized cylinders + subdivision cage | F-3: SDF raymarch preview, mesh at release |
| --- | --- | --- | --- |
| How | Sum compact-support falloffs of distance to each spine/limb segment; contour the iso surface on a grid; smooth; normals from the field gradient | Rings of vertices around each spine/limb segment form a coarse quad cage; branch junctions are stitched; Catmull–Clark subdivision smooths it | Editor draws the body with a fragment shader that raymarches the same field (no mesh); a mesh is built (F-1) when the handle is released |
| Quality | Organic blobs, automatic blending at junctions; small grid-scale lumps; no natural UVs | Clean quad topology, natural UVs (u along spine, v around), great deformation; junctions are the hard part (3+ way branches, limbs close together) | Perfectly smooth preview at any resolution; final look still F-1 |
| Robustness | Topology changes handled for free (S7's reason); thin features below about 1.5 cells can tear (probe P1 found 2 non-manifold edges) | Fragile at junctions, near-touching limbs and folded spines; needs many special cases | Preview never fails; final mesh has F-1's limits |
| Cost | Grid cost; probe P1–P3 shows GDScript is far too slow for live drag; native code needed | Cheap: ring count × sides, then 1–2 subdivision levels; fast in GDScript | GPU per pixel × primitives; not in the Compatibility renderer; editor only |
| Determinism | Good on one machine; float differences across CPUs or compilers can move vertices (hash tests per platform) | Very good (fewer ops) | Preview not part of determinism |
| Weights | From field contributions, exact by construction (`CREATURE_GEOMETRY_SPEC.md` §6) | From ring ownership, trivial and very clean | Same as F-1 |
| Blender interplay | Need our own Python port of field + nets for parity; Blender metaball objects use a different field and must not be the reference | Blender's Skin modifier + Subdivision is the same idea, good for art review; its source is GPL so it is a reference only, never ported | Same as F-1 |

Recommendation: **F-1 stays the production path** (it is the only one that copes with arbitrary player topology,
which is Spore's own reason in S7), built natively (see §5). F-3 is a strong candidate for the drag preview if F-1
native still misses 33 ms. F-2 is the fallback if F-1's lumps or cost fail review, and is worth a one-day spike on
the torso alone because it gives UVs and topology F-1 cannot.

### 2.5 Godot 4.7.2 interfaces (PROPOSED; names avoid clashes with existing classes)

Domain (`game/domain/`, pure, no scene or file access):

- `BodyDescription` (RefCounted): the editable body. Fields in §4.3. `to_dict() -> Dictionary`,
  `static from_dict(d) -> BodyDescription` (keeps bad entries, fills `load_problems`), `validate(rules: BodyRules)
  -> PackedStringArray`, `duplicate_body() -> BodyDescription`.
- `BodyRules` (RefCounted, loaded from `game/data/body_rules.json` by a service): vertebra, limb, joint, part limits
  and thickness ranges. All tuning data.
- `SpineCurve` (RefCounted): built from vertebrae. `point(u: float) -> Vector3`, `frame(u: float) -> Basis`
  (rotation-minimizing, +Y up seeded from body up), `radius(u: float) -> float`, `length() -> float`,
  `u_of_vertebra(i: int) -> float`.
- `BodyField` (RefCounted): primitives from a description. `sample(p: Vector3) -> float`, `gradient(p) -> Vector3`,
  `contributions(p) -> PackedFloat32Array` (per bone, for weights), `bounds() -> AABB`, `primitives_in(box: AABB)
  -> PackedInt32Array`.
- `BodySkeletonLayout` (RefCounted): `static build(desc) -> BodySkeletonLayout` with `bones: Array[Dictionary]`
  (`{name, parent, rest: Transform3D, capabilities: PackedStringArray}`), `root_bone`, `legs()` (computed paths from
  foot to first spine bone, S1 §4.2; never stored).

Services (`game/systems/`):

- `SkinBuilder` (Object or RefCounted): `request(desc: BodyDescription, quality: int, dirty: AABB = AABB()) -> int`
  (request id); runs on `WorkerThreadPool`; signal `skin_ready(request_id: int, arrays: Array, stats: Dictionary)`;
  `cancel(request_id)`; stale results are dropped. Output is plain `Mesh.ARRAY_*` arrays (vertices, normals,
  `ARRAY_CUSTOM0` spine/around channels, `ARRAY_BONES`, `ARRAY_WEIGHTS`, indices) so the service never creates
  nodes. `build_sync(desc, quality) -> Array` for tests.

Scenes (`game/scenes/creature/`):

- `CreatureRig` (Node3D): `apply(layout: BodySkeletonLayout, arrays: Array, parts: Array)`; creates
  `Skeleton3D`, `Skin`, `MeshInstance3D`, and part instances under `BoneAttachment3D` (§3.5).
- `CreatureEditorView` (Control + SubViewport): input, handles, gizmos only; calls the edit session (§3.5).

### 2.6 Data requirements

| Field | Range (PROPOSED) | Unit / storage |
| --- | --- | --- |
| Vertebra count | 3–24 | — |
| Vertebra position | body box ±1500 in each axis | integer, 1 unit = 1/1000 of `reference_length` |
| Vertebra radius | 20–400 | same units; neighbour ratio at most 3:1 |
| Optional width/height ratio | 0.5–2.0 | integer per mille |
| Limb count | 0–12 counted after mirroring | — |
| Joints per limb | 2–6 | — |
| Joint radius | 15–250 | same units; must be at least 1.5 preview cells at the creature's size |
| `reference_length` | per era, e.g. 0.3–4 m | float metres, the creature's size; one scalar so growth does not rewrite every point |

### 2.7 Acceptance tests (automatable, headless)

1. `test_body_description_validates_ranges`: each limit in `BodyRules` refused with a reason; boundary values
   accepted.
2. `test_spine_is_a_tree`: limbs attach only to existing vertebrae or limb joints; no cycles; depth ≤ 2.
3. `test_skin_watertight`: for each of the ten fixed test bodies (`GENESIS_IMPLEMENTATION_ROADMAP.md` Stage 1),
   every edge is shared by exactly two triangles and the skin is one connected piece.
4. `test_skin_deterministic_same_machine`: two builds give the same SHA-256 of vertex, index and weight bytes.
5. `test_skin_cross_platform_tolerance` (CI on Linux and Windows): every vertex of one build lies within 0.1
   preview cell of the other build's surface. Bit-for-bit across machines is not assumed (Bible §13).
6. `test_thin_feature_refused`: a joint radius under the minimum is refused before the build, not torn after.
7. `test_rest_pose_sane`: a folded spine (angle between neighbouring segments under 30°, PROPOSED) or a limb whose
   joints lie inside the torso is refused with a reason.
8. `test_preview_budget` and `test_bake_budget` (dev exe on the baseline PC, not CI): preview under 33 ms, bake
   under 250 ms for the large body.
9. `test_triangle_budget`: gameplay LOD under 8 000 triangles (current spec) for the large body.

### 2.8 Performance risks, unsupported configurations, remaining experiments

Risks:

- **GDScript is too slow for the live preview** (probe P1–P3, §5): 200 ms for a small body and 580 ms for a large
  one at the coarse preview grid, against a 33 ms target. The earlier spec's 30–80 ms guess was too optimistic.
- **Triangle count:** the coarse preview grid already gives 7 800–12 100 triangles; the fine grid 31 000–48 600.
  Production needs decimation (the existing triangle-reduction rule) or adaptive grids.
- **Weights** cost as much as contouring in GDScript; they must be native or culled per primitive.
- Every creature skin is a unique mesh: many species on screen means many draw calls and skinned meshes. Budget it
  in the M2 benchmark.
- Load time: rebuilding every NPC species at area load. A cache (§4.4 option D-3) mitigates it.

Unsupported (refused with a reason, PROPOSED):

- Loops, disconnected limbs, limbs on limbs deeper than one level.
- Features thinner than 1.5 preview cells at the creature's size (probe P1 shows tears below that).
- Spines folded back on themselves or crossing themselves (the field merges them into one lump).
- Spine leaving the sagittal plane (first version; see R212).
- Limbs whose joints sit inside the torso.

Remaining experiments (one variable at a time): R201, R207, R210, R211, R222 (existing); new R212, R214, R220
(§7). GENESIS-side: same-body build at three grid sizes (only grid changes) to set the preview cell size; plain sum
versus smooth-union for two legs at five spacings (only spacing changes).

---

## 3. System 2: part attachment, symmetry, orientation and placement

### 3.1 Observed behaviour and evidence

- Parts are rigblocks: artist models plus deform animations over 0..1 driven by player handles, composed additively,
  baked when finished (S3 abstract).
- S3 slides, general rule for all of Spore's editors: "Let player use supplied parts to build model – Allow
  stacking, pinning, sliding". For creatures: "Rigblocks attached to body".
- Every body carries **capabilities** (grasper, mouth, foot, spine, root...); gameplay and animation query bodies by
  capability (S1 §1.2, §3). Parts of the same type share standard deform curves (open/close mouth, blink) (S1 §1.2).
- A leg is a path from a foot body to the first spine body (S1 §4.2); legs come from the graph.
- Symmetry: "the creatures would have symmetry" (S12). Yet S1 Figure 5 shows "an asymmetric character", and S13
  describes a gait rule "if one side has twice as many legs as the other", so asymmetric bodies were possible in
  some form.
- Animations are mirrored across the **sagittal plane** automatically for variants (S1 §4.1.2), which assumes a
  well-defined body midplane.
- Mouths attached to the spine pass their IK goals to the spine body they sit on (S1 §4.3), so where a part sits
  changes how the body moves.
- Placement had no gameplay effect in Spore's Creature stage: part stats were fixed "regardless of placement or limb
  length" (S14).
- Eyes were "dropped onto the beast's shoulders" in a demo (S13), i.e. parts can sit anywhere on the skin.

### 3.2 Documented, inferred, unknown

Documented:

1. Parts are artist-made, deformed by handle-driven 0..1 animations that add up, then baked (S3).
2. Parts attach to the body; the editors allow stacking, pinning and sliding (S3 slides).
3. Capabilities on bodies link parts to animation and gameplay (S1).
4. A sagittal midplane exists and animations mirror across it (S1).
5. Symmetry is a design principle (S12); some asymmetric configurations existed (S1 Fig. 5, S13).
6. Placement did not change part stats in the Creature stage (S14).

Inferred (HYPOTHESIS):

1. "Sliding" means a placed part moves along the skin as the player drags it, staying on the surface.
2. Parts follow the body when the spine or a limb is edited (they ride with the vertebra they sit on).
3. Symmetric placement creates a linked twin rather than an independent copy.
4. Part orientation defaults to the surface normal.

Unknown:

1. Whether parts follow the body after spine edits, or stay fixed in space (R215).
2. Whether parts can stack on parts (R216), and how deep.
3. Rotation freedom per part type and its limits (R217).
4. Centre-line snap behaviour for symmetric parts (R204, R218).
5. Part scale range relative to the body (R223) and what happens when the skin shrinks under a part (R224).
6. What fills the complexity meter (R205, R209); behaviour only, never the formula.

### 3.3 Specification (PROPOSED)

1. Every part has one **host**: a spine segment, a limb segment, a limb end (feet, hands), or another part's socket.
2. A part's place is stored **relative to its host**, so it rides along when the body is edited. After any edit the
   part sits on the skin again (no floating, no sinking past its sink depth).
3. Orientation: the part's up axis follows the skin normal at its place; its forward axis follows the spine
   direction toward the head (projected onto the skin); the player adds bounded turn, tilt and roll per part type.
   Some types have a fixed rule (feet face the ground at rest; mouths face forward within a cone).
4. Symmetry is on by default. The body's midplane is fixed (body x = 0). A part placed off the midplane has a
   **linked twin**; editing one edits both. A part dropped within a small band of the midplane snaps onto it and has
   no twin. The player can break a link; the twin then becomes an independent part with its own id.
5. Chiral parts (a claw that curls one way) use a mirrored version on the twin side, so both curl inward.
6. Placement rules refuse, with a reason: unknown host, a host that cannot take that part type, two parts
   overlapping more than a set share of their footprints, exceeding per-type counts (existing `max_count`), and a
   body without a required category (existing `required_categories`).
7. Capabilities come from part types (catalog data) and are attached to the part's bone; legs, graspers and mouths
   are found by querying capabilities and the graph, never stored.
8. **GENESIS difference** (from S14): placement and anatomy feed `Phenotype` (reach of a mouth on a long neck,
   forward arc of eyes, leg length) through the one stat calculation.

### 3.4 Implementation options

| | A-1: parametric anchor (host, u, θ, h) | A-2: free transform in host-bone space from a surface raycast | A-3: A-2 plus re-snap along stored normal |
| --- | --- | --- | --- |
| Stored | host id, u along host (0..1), angle θ around the host axis (0 = top/dorsal, +π/2 = right), height offset h, turn/tilt/roll, scale | host bone id, local position + rotation | as A-2 plus a re-snap direction |
| After a body edit | Recomputed: point on host curve at u, march along direction θ to the skin, frame from normal + spine tangent. Rides along and stays on the skin by construction | Stays fixed relative to bone: floats or sinks when thickness changes | Projects back to the skin along the stored direction; fine for small edits, odd for large ones |
| Mirror | θ → −θ, roll and turn negate; exact | Mirror the transform across x = 0; exact | Same as A-2 |
| Coverage | Any tube-like host; awkward on junction blobs (two hosts overlap) and on the very ends of the spine (u near 0/1 needs a cap mode, θ as a polar angle) | Anywhere the ray hits | Anywhere |
| Data | ~8 numbers | ~7 numbers | ~10 numbers |
| Determinism | Good; depends on field march (bisection, fixed iterations) | Exact | Good |
| Cost | One field march per part per rebuild: probe P4 measured 0.3–1.2 ms per query in GDScript with no culling; with `primitives_in` culling expected well under 0.1 ms (HYPOTHESIS) | Free | One march per part |
| Fit with M1 | Generalizes M1's single `angle` (same sign convention) | New convention | New convention |

Recommendation: **A-1 stored, with raycasting only as UI input** (the editor converts a mouse hit on the skin to
host, u and θ). It keeps M1's angle convention (positive = right), makes symmetry exact, and makes "rides along"
true by construction. End caps use a polar mode (u pinned at 0 or 1, θ around the axis, plus an elevation angle).

Symmetry options:

| | Y-1: mirror flag on one stored item | Y-2: two stored items with a shared `pair_id` |
| --- | --- | --- |
| Data | Half | Full |
| Editing | One item; twin always exact | Must keep both in step on every edit (bugs if not) |
| Breaking symmetry | Materialize the twin as a new item with a new id | Clear `pair_id` |
| Stats | `Phenotype` expands mirrored items before ranking (same diminishing returns) | Direct |

Recommendation: Y-1, with a `materialize_twin` edit. It also fits the existing M1 rule that parts on the centre line
have no mirror.

Chiral parts: either the Blender asset ships explicit left and right variants (art cost, exact shading), or the
runtime mirrors the mesh once at bake (flip x, reverse winding, flip tangent sign). Avoid negative scale on bones;
skinning and physics do not handle it well. Recommendation: runtime mirror at bake, with an asset-record flag
`chiral: true` and a test that the mirrored mesh has outward normals.

### 3.5 Godot interfaces (PROPOSED)

Domain:

- `PartAnchor` (RefCounted, value object): `host_id: String`, `u: int`, `theta: int`, `height: int`,
  `turn: int`, `tilt: int`, `roll: int`, `mirror: bool` (quantized ints, §4.3). `mirrored() -> PartAnchor`.
- `AnchorResolver` (RefCounted): `resolve(desc: BodyDescription, field: BodyField, anchor: PartAnchor) ->
  Transform3D` (body space); `from_surface_hit(desc, field, point: Vector3, normal: Vector3) -> PartAnchor`.
- `PartRules` read from `part_catalog.json` additions: `hosts: ["spine","limb","limb_end","part"]`,
  `capabilities: [...]`, `orientation: "normal"|"ground"|"forward_cone"`, `turn_limit_deg`, `tilt_limit_deg`,
  `footprint_radius`, `sink_depth`, `chiral: bool`, `centerline: "allowed"|"required"|"forbidden"`.
  (`caps` already names stat ceilings in that file, so the list is `capabilities`, as `CREATURE_CREATOR_ANALYSIS.md`
  §3 says.)
- `BodyEditSession` (RefCounted), modelled on `EditorSession`: `move_vertebra(id, pos)`, `insert_vertebra(after_id)`,
  `remove_vertebra(id)`, `set_radius(id, r)`, `add_limb(host_id, side)`, `add_joint(limb_id)`, `place_part(type,
  anchor)`, `move_part(id, anchor)`, `orient_part(id, turn, tilt, roll)`, `scale_part(id, s)`, `set_handle(id, k,
  v)`, `set_mirror(id, on)`, `materialize_twin(id)`, `undo()`, `redo()`, `preview()`, `commit()`. Each edit returns
  `{ok, reason}` and changes nothing when refused. Signal `body_changed(dirty: AABB, kind: StringName)` so the view
  asks `SkinBuilder` for a dirty-region rebuild.

Scenes: `CreatureRig` places each part under a `BoneAttachment3D` on the host's socket bone and applies Blender
shape keys for handles (the approved IB-15 mechanism for parts still applies).

### 3.6 Data requirements

Part entry: `id` (`part_N`, existing scheme), `type`, `anchor` (8 ints + bool), `scale` (per mille, range from
`PartRules`, M1 uses 0.5–2.0), `handles` (0–4 values, per mille), `mirror`. Budget: about 24 parts × ~120 bytes
JSON ≈ 2.9 KB before quantization (probe P5 measured the whole large body).

### 3.7 Acceptance tests

1. `test_anchor_rides_along`: move, thicken and lengthen the host; every part stays within 1 mm × size of the skin
   and keeps its u and θ.
2. `test_mirror_exact`: for each part with `mirror`, the twin's transform equals the original reflected across
   x = 0 (within 1e-4).
3. `test_centerline_snap`: θ within the snap band (PROPOSED ±4°) becomes 0 or π with no twin; outside it, a twin.
4. `test_materialize_twin`: gives a new stable id; both parts then edit independently; undo restores the link.
5. `test_placement_refusals`: overlap, wrong host, count limit, missing mouth, each with a reason, nothing changed.
6. `test_orientation_rules`: feet face down within the limit at rest; mouths within their forward cone.
7. `test_legs_computed`: legs equal foot-to-spine paths for the ten bodies; never read from saves.
8. `test_stats_order_independent`: shuffled part order and mirror flag versus explicit twins give the same
   `Phenotype` (extends the M1 property).
9. `test_chiral_mirror_normals`: a mirrored chiral part has outward normals and correct winding.

### 3.8 Risks, unsupported configurations, remaining experiments

Risks: the anchor march near junction blobs can pick the wrong lobe (test the ten bodies at their junctions);
dense parts on a thin limb overlap; many `BoneAttachment3D` nodes per creature cost little but each part is a draw
call until baked (S3 baked into a single material and texture page; GENESIS needs a similar merge step).

Unsupported (PROPOSED): parts not touching the skin; parts on parts deeper than one level; asymmetric linked twins
(a twin is always exact); parts inside the torso.

Remaining experiments: R204, R205, R209 (existing); new R215–R218, R223, R224 (§7). GENESIS-side: snap band
width (only the band changes) in a usability test.

---

## 4. System 3: the editable description, saved and rebuilt

### 4.1 Observed behaviour and evidence

- EA's patent: procedural content stores "only the instructions (or the 'recipe') for recreating the content
  rather than storing the content itself"; "the size can be reduced to approximately 2-5 Kbytes of data"; content
  "might be compressed" for servers; "Creature animation is also recreated from procedural data" (S15).
- "The picture is 20k. The creature is 4k" (S12); creatures "had to be small enough to send over networks" (S12).
- Baking: deform data is removed and a new base mesh is produced; "Single texture page, single material"; "Generate
  LODs"; parts that animate at runtime (mouths) are replaced with "low-bone-count versions" and their animations are
  retargeted to the new skeleton (S3 slides).
- The rest pose is whatever the player built (S1), so the saved description must keep the full edit pose.

### 4.2 Documented, inferred, unknown

Documented:

1. The saved creature is a recipe, about 2–5 KB, not a mesh (S15, S12).
2. Animation is regenerated from the body's structure (S15, S1).
3. The playable model is baked from the recipe: one material, one texture page, LODs, simplified rigs for animated
   parts (S3 slides).
4. The edit pose is the rest pose (S1).

Inferred (HYPOTHESIS):

1. The recipe holds spine points and thickness, limb chains, part ids with placement and handle values, and paint
   choices; everything else is rebuilt.
2. Rebuilding on another machine gives a visually equal, not bit-equal, mesh.
3. Part ids must stay valid across expansions, so ids are stable names rather than indices.

Unknown (and deliberately not investigated: reading Spore's saved creatures or their format is excluded by the
owner's 2026-10-22 rule):

1. The actual fields, precision, versioning and compression of Spore's recipe.
2. Whether a baked mesh is cached locally.
3. Whether reopening a saved creature restores the editor state exactly (R221 checks this by observation only).

### 4.3 Specification (PROPOSED)

1. The **body description** is the only authority for a creature's body. Skeleton, skin, weights, collision, mass,
   legs, stats and animation parameters are derived from it, deterministically.
2. It is versioned (`body_version`), and every older version has a tested migration.
3. It uses stable ids for vertebrae (`v_N`), limbs (`l_N`), joints (`j_N`) and parts (`part_N`), each with a
   next-number counter like `Genome.next_part_number`, so ids are never reused (Bible §12, stable ids independent of
   scene paths).
4. Numbers are stored as integers on fixed grids (positions and radii in 1/1000 of `reference_length`, angles in
   1/10 000 of a turn, handles and scales in per mille). Encode → decode → encode gives identical text.
5. Loading never drops a part or limb. Unknown part types are kept, reported by `validate()`, and drawn as a
   marked stand-in in the editor (Bible §18).
6. The description records the generator version that last baked it. A newer generator may rebuild a slightly
   different skin; it never changes the description.
7. Size: the largest legal body under 4 KB as compact JSON (target; probe P5 measured 4.6 KB for a deliberately
   over-maximal body, see §5).
8. Each generation's description is kept in lineage history (it is the genome), so ancestors can be rebuilt.

Proposed shape (one example, values invented):

```json
{"body_version": 1, "plan": "spine", "reference_length_mm": 1200, "generator": "skin-1",
 "vertebrae": [{"id": "v_1", "p": [0, 820, -480], "r": 140}, {"id": "v_2", "p": [0, 860, -300], "r": 210}],
 "limbs": [{"id": "l_1", "host": "v_2", "mirror": true,
            "joints": [{"id": "j_1", "p": [250, 700, -280], "r": 80}, {"id": "j_2", "p": [300, 40, -260], "r": 50}]}],
 "parts": [{"id": "part_1", "type": "mouth_a", "anchor": {"host": "v_1", "u": 0, "theta": 0, "h": 0,
            "turn": 0, "tilt": 0, "roll": 0}, "mirror": false, "scale": 1000, "handles": [500]}],
 "next": {"v": 3, "l": 2, "j": 3, "part": 2}, "paint": {"base": "p_a", "coat": "p_b", "detail": "p_c",
 "colors": ["#E9744F", "#F4EAD2", "#1D3557"]}}
```

### 4.4 Implementation options

| | D-1: canonical compact JSON inside the save | D-2: packed binary (bit-packed, base64 in the save) | D-3: D-1 plus a non-authoritative baked-mesh cache |
| --- | --- | --- | --- |
| Size, large body | Probe P5: 4.6 KB quantized, 0.64 KB deflated | Estimate about 1 KB raw (HYPOTHESIS, not built) | D-1 + about 0.5–2 MB per cached creature on disk |
| Readability, diffs | Human-readable; works with `JsonValues` and existing migration tests | Opaque; needs its own tools | As D-1 |
| Migration | Field-by-field, like `SaveMigrations.v1_to_v2` | Version byte + hand-written decoders; brittle | As D-1; cache invalidated by key |
| Robustness | Unknown fields are visible and kept | One wrong bit corrupts the rest | Cache miss = rebuild, never a failure |
| Load time | Rebuild each creature (bake 250 ms target each) | Same | Fast: load cached arrays when key matches |
| Sharing (IB-09 offline files) | Fine; small enough | Smaller | Share D-1 only |

Recommendation: **D-1**, plus D-3 when the number of species per area makes rebuild time visible. The cache key is
SHA-256 of the canonical description text + generator version + platform tag; the cache lives under `user://` and
is never part of a save. D-2 only if a later sharing feature needs it (and sharing through a server has the patent
issue in `LEGAL_RESEARCH_BOUNDARIES.md` §3).

Precision note (OBSERVED, probe P5): Godot's `JSON.stringify` without `full_precision` writes about 15 significant
digits, so `0.1 + 0.2` does not round-trip; and `JSON.parse_string` turns integers into floats, so the first
re-encode turns `120` into `120.0` (stable after that). The save currently uses the default. Storing integers on
fixed grids avoids both problems for body data; the canonical encoder must also write integers without `.0`.

### 4.5 Godot interfaces (PROPOSED)

Domain: `BodyDescription.to_dict()` / `from_dict()`; `BodyCodec` (static): `encode(desc) -> String` (canonical:
fixed key order, integers, no whitespace), `decode(text) -> BodyDescription`, `hash(desc) -> String`;
`BodyMigrations` (static): `migrate(d: Dictionary) -> Dictionary` per `body_version`.

Genome: a later `Genome` schema 2 would add `body: Dictionary` (absent for cell-era genomes, which keep
`parts`/`angle`). `Phenotype.derive` would read the body when present.

Systems: `PersistenceService` keeps writing JSON; `SkinCache` (new service): `get(key) -> Array`, `put(key,
arrays)`, `prune(max_bytes)`.

**Save schema impact:** this is a save schema change (save v3 / genome schema 2) and needs the owner's approval
before anything moves into `game/` (CLAUDE.md; `GENESIS_IMPLEMENTATION_ROADMAP.md` "Promotion into the game").
Until then the description lives only in the prototype.

### 4.6 Data requirements and size budget

| Item | Max count | JSON bytes each (quantized, approx.) | Total |
| --- | --- | --- | --- |
| Header, paint, counters | 1 | 300 | 0.3 KB |
| Vertebrae | 24 | 45 | 1.1 KB |
| Limbs (stored once when mirrored) | 6–12 | 60 + 45 per joint | up to 2.0 KB at 6 limbs × 6 joints |
| Parts | 24 | 130 | 3.1 KB |

The worst case adds up to about 6.5 KB with long keys, so meeting 4 KB needs short keys, mirrored items stored
once, and realistic maxima (fewer joints when limbs are many). Deflate brings any of these under 1.1 KB (probe P5).
PROPOSED budget: 4 KB uncompressed for the largest body players can actually reach under the complexity limit.

### 4.7 Acceptance tests

1. `test_body_codec_round_trip`: encode → decode → encode is byte-identical for the ten bodies and 1 000 random
   valid bodies (seeded).
2. `test_body_codec_after_save_json`: a body written through `PersistenceService` and read back encodes to the same
   canonical text (catches the int-to-float and precision issues).
3. `test_body_never_drops_parts`: unknown part types, bad hosts and wrong-typed fields are kept and reported.
4. `test_body_migrations`: a fixture per `body_version` migrates and validates.
5. `test_body_size_budget`: the largest reachable body encodes under 4 KB.
6. `test_rebuild_from_description_only`: delete the cache, rebuild, compare the mesh hash with the cached build on
   the same machine.
7. `test_cache_key_changes_with_generator_version`.
8. `test_ids_never_reused`: remove and add vertebrae, limbs and parts; no id repeats; counters only grow.

### 4.8 Risks, unsupported cases, remaining experiments

Risks: generator changes alter old creatures' look (mitigated by versioned generator and review fixtures); float
drift across platforms (tolerance tests, not hash tests, across machines); lineage history growing by about 4 KB per
generation (100 generations ≈ 0.4 MB, fine; PROPOSED cap or diffs later).

Unsupported: storing meshes or skin weights in saves; executable content in descriptions (Bible §18); loading a
description from a newer `body_version` than the game knows (refuse with a message, keep the file).

Remaining experiments: R221 (new). GENESIS-side: re-encode the ten bodies through a full save/load cycle.

---

## 5. Feasibility probe (OBSERVED, scratch only)

Script: `/tmp/claude-0/-home-user-pangaea/c6c69f40-fc53-5266-b764-95b77bc0f127/scratchpad/wsB/probe.gd` (not in
the repo, original code, invented test bodies, no Spore data). Machine: cloud container, Intel Xeon @ 2.10 GHz,
4 cores, 15 GB RAM, Godot 4.7.2-stable official, headless, single-threaded GDScript. Unoptimized naive code:
the numbers bound the problem; they are not a design target. Field: tapered capsules, falloff (1 − d²/R²)³ with
R = 1.6 r; naive Surface Nets on a dense grid with per-capsule box splats; top-4 weights from capsule contributions.

| Probe | Small body (10 vertebrae, 2 limb pairs × 3 joints, 21 capsules) | Large body (24 vertebrae, 6 limb pairs × 6 joints, 95 capsules) |
| --- | --- | --- |
| P1 grid at length/48 | 29×38×64; splat 65 ms, nets 88 ms, weights 50 ms = **203 ms**; 7 800 tris; watertight | 31×37×62; 211 + 98 + 269 = **578 ms**; 12 096 tris; watertight |
| P2 grid at length/96 | 55×72×124; 474 + 592 + 213 = **1.28 s**; 31 328 tris; watertight | 58×71×120; 1 102 + 665 + 1 267 = **3.03 s**; 48 592 tris; **2 non-manifold edges** |
| P3 determinism (same process, two builds) | identical SHA-256 | identical SHA-256 |
| P4 anchor query (u, θ) by 24-step bisection on the field, no culling | 0.29 ms | 1.25 ms |
| P5 description size (24 parts) | JSON 4 019 B; quantized 3 290 B; deflate 493 B | JSON 6 690 B; quantized 4 593 B; deflate 641 B |

What it tells us:

1. GDScript is 6–18× too slow for a 33 ms live preview even at the coarse grid. The native route (compute shader:
   no new dependency, not on the Compatibility renderer; or a C++ GDExtension: needs owner approval) is not
   optional for live dragging. HYPOTHESIS: native C++ is 20–50× faster on these loops, which would put the large
   body near 12–30 ms; to be measured, not assumed.
2. Without native code, the editor can still work with a release-to-rebuild flow, F-3 raymarch preview, or F-2
   generalized cylinders (cheap enough for GDScript).
3. The fine grid can tear thin limbs (P2, large body): the minimum joint radius must be set in grid cells, and the
   watertight test must run on every test body at every quality.
4. Triangle counts at the coarse grid already exceed the 8 000 gameplay budget for the large body; decimation or
   an adaptive grid is part of the bake, not optional.
5. Quantized JSON alone does not meet 4 KB for an over-maximal body; short keys plus realistic limits do (§4.6).

## 6. What this research changes for GENESIS

- New primary evidence (S3 slides) agrees with S7 that Spore's skin was metaballs over a player-edited skeleton
  ("Adjust spline, glue limbs"). F-1 stays the right family.
- Evidence that asymmetric creatures existed (S1 Fig. 5, S13) means "symmetry required" (S12) was a default, not an
  absolute. GENESIS keeps symmetry on by default with an explicit "break link" edit.
- The rest pose is the edit pose (S1), so GENESIS must validate rest poses and offer a "settle" helper rather than
  assume a standard pose.
- The earlier GDScript estimate in `CREATURE_GEOMETRY_SPEC.md` §5 (30–80 ms) is contradicted by this probe
  (200–580 ms). The Stage 1 prototype should measure a native path early. (This file does not edit that spec; the
  lead should decide whether to update it.)
- Does the research reduce work? Yes, moderately: it settles the topology (tree, no loops), the surface family, the
  edit-pose-as-rest-pose rule and the recipe-not-mesh save model, all of which would otherwise need prototypes to
  discover. It does not reduce the hard engineering (fast contouring, junction quality, anchor robustness), which
  no public source describes.

## 7. New measurement rows proposed (R212–R224)

Each changes one variable. Recording only, under `MEASUREMENT_PLAN.md`. These are proposals for the CSV; this file
does not edit it.

| Row | Quantity | Method (one variable) |
| --- | --- | --- |
| R212 | Can a vertebra be dragged off the midplane? | Plain body; drag one middle vertebra sideways only; record whether it moves and whether its neighbours follow |
| R214 | Where an inserted vertebra appears and whether parts on neighbours move | Plain body with one eye on vertebra 3; insert one vertebra next to it; nothing else |
| R215 | Do parts follow spine edits? | Body with one part; drag its vertebra up 1 body width; compare part position before and after |
| R216 | Can parts stack on parts, and how deep? | Place one part on another, then a third on the second |
| R217 | Rotation freedom per part type | One mouth, one eye, one foot; try each rotation control; record limits by screen angle |
| R218 | Centre-line snap band | Drag a symmetric part slowly toward the midline; note the screen angle where the twin disappears; 5 takes |
| R220 | Cross-section shape | Front view of a plain body before and after the thickness control; compare width and height on screen |
| R221 | Save and reopen fidelity | Save a test creature, reopen it in the editor with the same camera; compare screenshots side by side; behaviour only, no file inspection |
| R222 | Visible tessellation at closest zoom | Count silhouette facets on a plain body at max zoom; then at min zoom |
| R223 | Part scale range relative to the body | One part; scale to min and max; measure against body length |
| R224 | Part behaviour when the skin shrinks under it | Part on a vertebra; reduce only that vertebra's thickness to minimum |

(R213 and R219 are left free: rest-pose persistence is already CONFIRMED by S1, and branching legs appear in S1
Fig. 6.)

## 8. Prioritized unknowns and the smallest prototype

Unknowns, highest impact first:

1. Native contouring speed for the large body (decides live drag versus release-to-rebuild). GENESIS-side, measurable
   now.
2. Junction quality: sum versus smooth-union where limbs meet the torso and each other (R210 for Spore's look).
3. Anchor robustness near junctions and spine ends.
4. Whether parts ride along in Spore (R215) — a feel target only; GENESIS chooses "ride along" either way.
5. Description size at realistic maxima.

Smallest original prototype that validates the key finding (inside the already proposed Stage 1 gate, awaiting
owner approval): a **variable-length spine body** in `prototypes/creature-lab/`: 3–24 vertebrae with round
thickness, no limbs, no parts; F-1 skin at two grid sizes; the canonical encoder; tests 2.7 (1, 3, 4, 6, 9) and 4.7
(1, 2, 5). It answers unknown 1 (time it in GDScript and with one native path) and fixes the description format
before limbs and parts add complexity. Nothing is built until the owner approves it.

## Sources

- S1 Hecker et al., SIGGRAPH 2008: <https://www.chrishecker.com/images/c/cb/Sporeanim-siggraph08.pdf>
- S3 Choy et al., Rigblocks abstract and slides: <https://www.cs.cmu.edu/~ajw/s2007/0248-Rigblocks.pdf>,
  <https://www.cs.cmu.edu/~ajw/s2007/0248-Rigblocks-slides.pdf>
- S4 DeBry et al., Player-Driven Procedural Texturing: <https://www.cs.cmu.edu/~ajw/s2007/0311-PaintingModels.pdf>
- S7 Hecker, liner notes (down; search summary only): <https://www.chrishecker.com/My_Liner_Notes_for_Spore>
- S10b Wikipedia, Spore Creature Creator: <https://en.wikipedia.org/wiki/Spore_Creature_Creator>
- S12 Game Developer on Gingold: <https://gamedeveloper.com/game-platforms/gingold-talks-i-spore-i-s-magic-crayon-approach>
- S13 IEEE Spectrum, Engineering Spore: <https://spectrum.ieee.org/engineering-spore>
- S14 Johnson, My View of the Elephant: <https://www.gamedeveloper.com/design/spore-my-view-of-the-elephant>
- S15 US7867093B2: <https://patents.google.com/patent/US7867093B2/en>
- Techniques (public literature, not Spore): Wyvill, McPheeters and Wyvill 1986 (soft objects); Gibson 1998
  (surface nets); Catmull and Clark 1978 (subdivision); Hart 1996 (sphere tracing, for F-3).
