# Creature art contract: part assets and skin shader (PROPOSED)

The procedural creature has two owners. This doc is art's half of the contract.

| Owner | Owns |
|---|---|
| Spore research protocol thread | Runtime geometry, spine skin, rig, Gait Lab, body save format |
| Art thread | Part meshes, skin materials and shaders, look review |

It builds on these PROPOSED specs in PR #12:
- `docs/research/spore/workstreams/creature_editor.md` §3.3–3.6 (anchors and `PartRules`);
- `docs/research/spore/CREATURE_GEOMETRY_SPEC.md` §4 (bones), §8 (skin channels and paint) and §9 (Blender's role).

Nothing in this doc moves into `game/` until Joshua approves the save-schema step. The cell stage stays microscopic, so its parts have no bones, teeth or skeletons; those belong to later stages. Nothing here is copied from Spore.

## 1. Part assets

Every part follows the usual pipeline:
- a `.blend` in `assets/source/blender/part_<type>[_<variant>].blend`;
- a GLB in `assets/export/`;
- a record in `assets/records/`.

`tests/test_assets.gd` checks all three, as it does today.

### 1.1 Axes, pivot and scale

| Rule | Godot | Blender |
|---|---|---|
| Up = the skin normal at the anchor | +Y | +Z |
| Forward = toward the head, along the spine tangent projected on the skin | −Z | +Y |
| Right | +X | +X |

- **Pivot.** The pivot is the point where the part meets the skin, on the skin surface. Geometry below the pivot, down to `sink_depth`, is the part's root, so it never shows a gap when the skin bulges.
- **Scale.** Author at the part's nominal size at scale 1000‰, in metres (1 m = 1 Godot unit). The runtime applies per-mille scale uniformly about the pivot, so nothing may depend on world size.
- **Chirality.** Chiral parts ship one side only: the **right** side (+X in Godot). The runtime mirrors them at bake. Records carry `"chiral": true`. A test bakes the mirror and checks that its normals face outward.
- **Breaking change.** M1's cell parts (`part_spike`, `part_flagellum`, `part_mouth_jaw`, `part_mouth_filter`, `part_eye_spot`) use the older convention: outward is Blender +Y. When the creature runtime lands, art re-exports them in this convention as a new revision, and the records' `attachment` block changes to match. Until then they stay as they are, because M1 code reads them.

### 1.2 Nodes, shape keys and sockets

- **Root.** The root node is one mesh named after the part type in PascalCase, for example `Spike`. Extra meshes are children of the root.
- **Handles.** Up to 4 shape keys, named `H1_<what>` to `H4_<what>`, for example `H1_Length` or `H2_Curl`. Each handle runs from 0 to 1000‰. 0‰ is the basis shape. Every handle must stay inside the footprint at 1000‰.
- **Sockets.** A part that can host other parts gets empties named `socket_<n>` (Blender +Z = the hosted part's up). They export as `Node3D`s. The runtime turns each socket into a `part_NN` socket bone.
- **No bones.** Parts have no armature. The runtime rig places each part under a `BoneAttachment3D` on its socket bone. Moving parts, such as a jaw opening or a flagellum beating, animate by shape key or by a shader driven by `ANIM_PHASE` (§2.4), never by bones inside the part.
- **Collision.** A collision proxy is optional. If present, it is a child named `Collider` that is hidden in renders.

### 1.3 Record fields

The `part_*` record fields stay. These are added under `"part_rules"`, with values the runtime copies into `PartRules`:

```json
"part_rules": {
  "type": "spike",
  "footprint_radius_m": 0.06,
  "sink_depth_m": 0.03,
  "chiral": false,
  "orientation": "normal",
  "turn_limit_deg": 45,
  "tilt_limit_deg": 30,
  "centerline": "allowed",
  "hosts": ["spine", "limb", "limb_end"],
  "role": "weapon",
  "handles": [{"key": "H1_Length", "meaning": "shaft length", "default_permille": 0}]
}
```

- `role` (added 2026-10-24) says what the part is for: `eye`, `mouth`, `hand` (graspers), `foot`, `weapon` or `detail`. The editor can group its palette by it, and the stats can count eyes and mouths from it instead of a list of types. Variants of a kind are their own types (`eye`, `eye_slit`, `eye_round`), so each keeps its own mesh and rules.

- `orientation` takes one of three values:
  - `normal`: up follows the skin;
  - `ground`: feet, up follows world +Y at rest;
  - `forward_cone`: mouths and eyes, forward is clamped to a cone around the head direction.
- `footprint_radius_m` is measured at scale 1000‰ in the skin's tangent plane.
- The record's `triangle_budget` holds for the part at all handle values.

### 1.4 Budgets (PROPOSED)

| Part class | Triangles | Textures |
|---|---|---|
| Small (eye, pore, bristle) | 400 | 256 px |
| Medium (mouth, spike, fin, flagellum) | 1,200 | 512 px |
| Large (limb end, crest, shell plate) | 2,500 | 512 px |

The whole body target is set by the runtime thread. Parts are drawn as separate meshes, so a creature with 24 parts stays within about 30k part triangles.

### 1.5 Materials

Each part has the same baked set as M1's finished parts:
- a greyscale albedo detail texture times each material's base colour;
- an ORM texture;
- a normal map.

Every part material also exposes `paint_mix` (0 to 1). This is how much of the creature's paint (§2.2) replaces the part's own base colour. Horn, chitin and eyes stay near 0. Fleshy parts such as fins follow the skin near 1, so they read as one animal.

## 2. Skin shader parameters

There is one `ShaderMaterial` for the generated skin: `assets/export/shaders/creature_skin.gdshader` plus `M_CreatureSkin.tres`. Art authors and owns it. It reads only what the runtime writes.

### 2.1 Vertex inputs (written by the runtime)

| Channel | Meaning | Range |
|---|---|---|
| `CUSTOM0.x` | `spine_u`: position along the spine, 0 at the head, 1 at the tail | 0–1 |
| `CUSTOM0.y` | `ring_v`: angle around the spine in turns: 0 dorsal, 0.25 right (+X), 0.5 belly, 0.75 left; wraps on the dorsal midline | 0–1 |
| `CUSTOM0.z` | `limb_id`: 0 on the trunk, 1 and up for each limb | integer as float |
| `CUSTOM0.w` | `limb_t`: distance along the limb, 0 at the attach point, 1 at the tip | 0–1 |
| `CUSTOM1.xyz` | `rest_pos`: the vertex's rest-pose body-space position in metres (the mesh's own vertex array before skinning). Spots, cells and scales are computed here with x folded, so they don't stretch with the spine coordinates, streak at the end caps or slide when the body bends | metres |
| `COLOR.r` | `crease`: optional ambient-occlusion hint at blend seams (0 if not provided) | 0–1 |

### 2.2 Paint uniforms (from the body save, set per creature)

| Uniform | Type | Meaning |
|---|---|---|
| `base_pattern` | int | Base layer id (§2.3) |
| `coat_pattern` | int | Coat layer id: covers the back and fades toward the belly |
| `detail_pattern` | int | Detail layer id: stripes, spots, rings |
| `color_base`, `color_coat`, `color_detail` | vec3, sRGB | The 3 paint colours |
| `pattern_seed` | int | Seeds spots and noise per creature (deterministic) |
| `coat_reach` | float 0–1 | How far the coat reaches down the flanks |
| `detail_scale` | float | Pattern features per body length |
| `body_length_m` | float | The body's length; rest-space patterns are scaled by it, so a pattern keeps its count as the body grows |

### 2.3 Pattern ids (first set, IMPLEMENTED in the shader, look PROPOSED)

| Layer | Ids |
|---|---|
| Base | 0 plain, 1 mottled, 2 cellular, 3 fine scales |
| Coat | 0 none, 1 saddle, 2 dorsal stripe, 3 countershade |
| Detail | 0 none, 1 cross bands, 2 spots, 3 rings on limbs (`limb_t`), 4 eye spots |

Coats and cross bands follow `spine_u` and the folded ring value. Spots, cells and scales live in rest space (`CUSTOM1`). Fine surface detail is triplanar in object space, using CC0 or in-house greyscale textures under `assets/export/creature_skin/`. The pattern layers come from the vertex channels, so stretched bodies don't smear.

### 2.4 Global and animation uniforms

| Uniform | Meaning |
|---|---|
| `stage_look` | Int: 0 = cell (translucent membrane, rim light), 1 = creature (opaque). Later stages add their own |
| `ANIM_PHASE` | Float, set by the gait runtime per frame. Parts and skin may use it for ripple, beat or breathing |
| `damage`, `ripeness` | Floats 0–1 that reuse the M1 cell's meanings, so the same game feedback reads the same way |

### 2.5 Colour rules

- Paint colours are free for players.
- The default creature palettes art ships keep 25° LAB hue clear of food green (114) and the threat pink (11), as every other asset does.
- The threat outline and food glow stay engine overlays, never baked into the skin.

## 2.6 First look check

`assets/export/shaders/creature_skin.gdshader` has the full parameter set. It was run on the creature lab's real skins (branch `claude/project-thread-uqwkit`, commit 9fbf9e3, `spine_lab.tscn --body=all --anim=swim`). The check used a throwaway scene that sets the material override and copies the vertex array into `CUSTOM1`. Frames:
- `docs/art/renders/concept/creature_skin_v1_all.jpg`
- `..._fish.jpg`
- `..._bean.jpg`

Rendered with gl_compatibility under Xvfb.

## 2.7 First parts (PROPOSED, built)

`tools/blender/make_creature_parts.py` builds thirty-seven parts in this convention. Review sheets are `docs/art/renders/production/cpart_<type>_sheet.jpg`.

| Id | Type | Triangles | Handles | Notes |
|---|---|---|---|---|
| `cpart_beak` | beak, `forward_cone`, centreline required | 286 | H1_Length, H2_Open, H3_Hook | Keeled horn bill on a fleshy gape; the keel is on +X before the runtime's frame turns it |
| `cpart_eye` | eye, `forward_cone` | 700 | H1_Blink (on `Lid`), H2_Bulge (on `Eye`) | Glossy ball, amber iris, rolled lid; paint_mix 0 on the ball |
| `cpart_fin` | fin, `normal` | 506 | H1_Height, H2_Sweep, H3_Ripple | Ray-stiffened membrane swept to the tail; paint_mix 0.9 |
| `cpart_foot` | foot, `ground`, limb_end | 622 | H1_Spread, H2_Long | Three padded toes with horn nails; the sole on the pivot, the ankle top at z 0.09 |
| `cpart_horn` | horn, `normal`, chiral | 214 | H1_Length, H2_Curl | Right-hand side only; centreline forbidden |
| `cpart_claw` | claw, `normal`, chiral, limb_end or limb | 188 | H1_Length, H2_Hook | Dark sickle on a padded sheath; curls toward -X on the right-hand piece; paint_mix 0 on the horn |
| `cpart_hand` | hand, `normal`, limb_end, grasper | 871 | H1_Grip, H2_Spread | Three knuckled fingers and an opposed thumb with rounded pads |
| `cpart_crest` | crest, `normal`, spine, centreline required | 526 | H1_Raise, H2_Fold | Five spines with a scalloped web; sinks 0.02 m |
| `cpart_tail_fluke` | tail_fluke, `normal`, spine, centreline required | 424 | H1_Span, H2_Beat | Notched crescent for the tail cap (spine_u = 1); the blade spreads across x |
| `cpart_wing` | wing, `normal`, chiral, spine or limb | 1542 | H1_Fold, H2_Flap | Arm bone and three finger struts with a scalloped membrane; cups toward -X on the right-hand piece |
| `cpart_antenna` | antenna, `normal`, chiral | 656 | H1_Length, H2_Droop | Beaded feeler with a pitted sensory club; arcs forward and out to +X |
| `cpart_tail_spikes` | tail_spikes, `normal`, spine, centreline required | 468 | H1_Length, H2_Splay | Two pairs of bony spikes on a horny pad for the tail cap |
| `cpart_mandibles` | mandibles, `forward_cone`, centreline required | 596 | H1_Open, H2_Length | Two toothed horn jaws on a fleshy collar, meeting across x |
| `cpart_eye_stalk` | eye_stalk, `normal` | 422 | H1_Length, H2_Droop (on `EyeStalk` and `Eye`) | Eyeball on a soft stalk that bows forward, in a fleshy socket; the pupil looks forward |
| `cpart_compound_eye` | compound_eye, `forward_cone` | 489 | H1_Bulge, H2_Wide (on `CompoundEye` and `Rim`) | Dark violet faceted dome in a fleshy rim; paint_mix 0 on the lens |
| `cpart_maw` | maw, `forward_cone`, centreline required | 540 | H1_Gape (on `Maw` and `Teeth`), H2_Fangs (on `Teeth`) | Rolled lips round a dark throat, ringed with fourteen inward-raking teeth |
| `cpart_quills` | quills, `normal`, spine | 530 | H1_Raise, H2_Length | Eleven banded quills raked toward the tail from a bristled pad |
| `cpart_frill` | frill, `normal`, spine, centreline required | 1635 | H1_Fold, H2_Span (on `Frill` and `FrillWeb`) | Seven knobbed horn ribs with a scalloped fleshy web, leaning back toward the tail |
| `cpart_proboscis` | proboscis, `forward_cone`, centreline required | 928 | H1_Length, H2_Curl (on `Proboscis` and `ProboscisTip`) | Ringed trunk-like snout curving forward and down to a flared sucker pad |
| `cpart_tusk` | tusk, `forward_cone`, chiral | 720 | H1_Length, H2_Curve | Grooved ivory tusk sweeping forward and out to +X from a rolled gum; paint_mix 0 on the ivory |
| `cpart_gill_fan` | gill_fan, `normal`, chiral, spine | 786 | H1_Spread, H2_Length (on `GillFan` and `GillPlumes`) | Five feathery gill plumes on a fleshy ridge, leaning out to +X; meant for the neck sides |
| `cpart_flipper` | flipper, `normal`, limb_end | 238 | H1_Length, H2_Width | Flattened swimming paddle out along +Z, broad across x, thin fore-aft; ridges in the normal map |
| `cpart_hoof` | hoof, `ground`, limb_end | 268 | H1_Wide, H2_Tall | Cloven horn hoof on a short skin pastern; the sole on the pivot, the pastern top at z 0.075 |
| `cpart_club_tail` | club_tail, `normal`, spine, centreline required | 1053 | H1_Length, H2_Size | Knobbed bony club on a thick fleshy stalk for the tail cap |
| `cpart_lure` | lure, `normal` | 602 | H1_Length, H2_Droop | Slender stalk arching forward over the head to a glowing pale-cyan bulb (flat emission); paint_mix 0 on the bulb |
| `cpart_barbels` | barbels, `forward_cone`, centreline required | 476 | H1_Length, H2_Lift | Two long and two short whisker barbels on a fleshy chin pad |
| `cpart_eye_slit` | eye_slit, `forward_cone` | 870 | H1_Blink (on `Lid`), H2_Bulge (on `EyeSlit`) | Reptile eye: a gold iris with a slit pupil (narrow across y) in an almond of scaly lids; the iris is a second material on the ball's own ring, so its edge stays round |
| `cpart_eye_round` | eye_round, `forward_cone` | 990 | H1_Blink (on `Lid`), H2_Bulge (on `EyeRound`) | Big round eye standing proud of the skin: white ball, wide blue iris, large pupil, thin rolled lid |
| `cpart_eye_cluster` | eye_cluster, `forward_cone` | 1004 | H1_Bulge, H2_Spread (on `Eyes`) | Four glossy black eyes, two big and two small, in a low fleshy pad |
| `cpart_jaw` | jaw, `forward_cone`, centreline required | 492 | H1_Open, H2_Length (on `Jaw` and `Teeth`) | Long toothy snout: scaly upper (+Y) and lower jaws with rows of pointed teeth and pink gums, on a collar |
| `cpart_bill` | bill, `forward_cone`, centreline required | 912 | H1_Open, H2_Width | Broad flat spoon-tipped bill with nostril dents, a closing seam and a dark nail, on a fleshy gape |
| `cpart_foot_webbed` | foot_webbed, `ground`, limb_end | 629 | H1_Spread, H2_Long (on `FootWebbed`, `Web` and `Nails`) | Three long slender toes fanned wide with a thin scalloped web between them and small claws; the sole on the pivot, the ankle top at z 0.09 |
| `cpart_foot_paw` | foot_paw, `ground`, limb_end | 760 | H1_Spread, H2_Long (on `FootPaw` and `Claws`) | Round padded paw, four plump toes in an arc toward the head with short dark claws; the ankle top at z 0.095 |
| `cpart_foot_talon` | foot_talon, `ground`, limb_end | 580 | H1_Spread, H2_Long (on `FootTalon` and `Talons`) | A bird's scaly foot: a thin shank, three knuckled toes forward and one back, each with a hooked talon; the shank top at z 0.1 |
| `cpart_hand_paw` | hand_paw, `normal`, limb_end, grasper | 998 | H1_Grip, H2_Spread (on `HandPaw` and `Nails`) | Soft mitten paw: four short fat fingers side by side and a stubby thumb, with small nails |
| `cpart_hand_pincer` | hand_pincer, `normal`, limb_end, grasper | 602 | H1_Open, H2_Size | Crab pincer: a pitted shell palm, a fixed finger on -Y and a hinged one on +Y with knobbly teeth and dark tips; symmetric across x, so not chiral |
| `cpart_hand_tentacle` | hand_tentacle, `normal`, limb_end, grasper | 622 | H1_Curl, H2_Spread | Three tentacle fingers reaching out and curling back in to cup a grip, with sucker rows, from a fleshy palm |

Curved tubes (claw, fingers) use the generator's `_tube`, which carries its ring frame by parallel transport; the M1 `_sweep` flips its frame when the path turns past about 25 degrees from +Z and leaves a kink.

Every handle rests at 0. Blender adds shape keys at 1, so the generator zeroes them, or the GLB would carry them as default weights. `tests/test_assets.gd` measures meshes with blend shapes at their rest shape, because Godot's mesh AABB grows to cover every blend shape.

## 3. Blender side

Art writes `tools/blender/creature_reference.py`. It rebuilds a `BodyDescription` JSON as a `.blend` using the runtime thread's Python port of the skin algorithm. It places the parts by the same anchor rules and applies `creature_skin` look-dev as a Blender material. It is used for:
- the look review and hero renders;
- a reference that the Godot output is compared against.

## 4. Settled with the runtime thread (2026-10-23)

1. **`ring_v` wrap.** It wraps on the dorsal midline. Symmetric patterns use the folded value `f = 2·min(v, 1−v)` (0 on the back, 1 on the belly), or `sin/cos(2πv)`, so the wrap never shows.
2. **Limb-end pivots.** The pivot is where the limb axis leaves the tip cap, on the skin, with +Y outward along the limb axis. `ground` parts (feet) are the exception: +Y is body up at rest, −Z is body forward, and the sole sits on the pivot.
3. **Handles.** They are Godot blend shapes. The H1–H4 shape keys export in the GLB and are set per instance. A later bake may flatten them for the far LOD.

---
Status: PROPOSED by the art thread, 2026-10-23. Edit freely; the runtime thread's edits win on anything they own.
