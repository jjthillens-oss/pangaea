# Red meat food prop — preparation

Status: PROPOSED asset for review. It is not admitted into production scenes.

## Reference and license

The inspected [Steak and Herbs photograph](https://commons.wikimedia.org/wiki/File:Steak_and_Herbs_(Unsplash).jpg) is by Jez Timms, published 30 November 2015. Its Wikimedia Commons page explicitly records that this pre-5 June 2017 Unsplash image was published under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The stored 960 px reference thumbnail is from Wikimedia Commons, SHA-256 `02c3bae557103884439d91863b0a5b0700b6453d0561fd52c2452f2c404cbe1f`. The photograph is used only as a shape/material reference; no pixels or 3D geometry are copied into the prop. The rosemary and cutting board are excluded. Verified by reading the Commons license text and opening the downloaded image on 2026-10-25.

## Asset brief

- **Function:** readable food pickup for a terrestrial or social stage prototype; no current game integration.
- **Scale and orientation:** approximately 0.72 m wide, 0.60 m long, 0.17 m high; origin at ground contact; Blender +Z up and front +Y, Godot +Y up and front -Z.
- **Viewing distance:** 1.5–6 m, including an elevated gameplay camera. Distinguishable by outline and pale fat edge before close-up detail.
- **Triangle budget:** target under 1,200 triangles (small-prop provisional budget from Bible §16); two or three opaque PBR materials, no baked light, no required texture. Actual count remains pending Blender export.
- **Materials:** broad muted berry-red muscle, a little deeper burgundy variation, and warm ivory fat. Nonmetallic, rough, no wet/shiny or graphic detail.
- **Source of record:** final editable `meat-red.blend` and export `meat-red.glb` under this package after validation. The script is a reproducible construction aid, not a substitute for the `.blend`.

## Reference contract before materials

| Visible reference observation | Original stylized choice | Pass criterion |
| --- | --- | --- |
| Main steak is a broad, irregular lobe wider than it is thick, with a shallow inward notch at upper left | Asymmetric hand-defined radial outline and uneven top ridges | Gray front, side and three-quarter views show a slab, not a cube or oval disk; notch remains visible at pickup scale |
| Lower contour is scalloped, not a straight edge | Several deliberately varied perimeter lobes | Gray top and three-quarter views retain two distinct lower lobes |
| Broad dark crimson area is interrupted by restrained pale seams | Two matte red regions and a few shallow, branching ivory seams as separate exportable geometry | At gameplay distance the broad red reads first; the pale veins add identity without a graphic cut surface |
| Pale fat borders portions of the lower and left edge, with uneven thickness | Curved ivory rim on selected perimeter spans, absent elsewhere | Rim is visibly partial and irregular, not a uniform white outline |
| Top has curved muscle direction and low relief, rather than a smooth inflated pillow | Radial rings with controlled height changes and nonuniform tangential wedges | Grazing gray light shows shallow broad ridges; no noisy bumps or melted borders |
| Photograph has strong specular wet highlights, probably affected by lighting | Reject the wet highlight; use matte stylized food material | Neutral render has separated matte red/ivory materials, no metallic or reflective gloss |

Reference only determines the photographed face. Back and underside are invented as simple, coherent closed geometry. This is a game-food prop, not an anatomical reconstruction. There is no bone, blood, organ detail, or photoreal texture.

## Gate plan

1. Run `build_meat_red.py` in the existing Blender 5.2.2 installation only when the art render window is released. It creates an editable `.blend`, gray shape renders, neutral material renders, and a GLB of export objects only.
2. Open and inspect all gray views before accepting materials. Revise outline/height if the pickup reads as a primitive disk or the notch/lobes vanish.
3. Inspect neutral material views, validate GLB/material/triangle/dimension counts, and import/render in an isolated Godot 4.7.2 review setup. A headless parse alone is insufficient visual acceptance.
4. Make paired reference/result and region crops; open the final sheet and record the three largest remaining differences and gate states in `GATES.md`.

Prep state: reference and script only. Shape, materials, export, engine transfer, and visual fidelity are **unverified** until the final version is rendered and inspected.
