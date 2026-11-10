# Red meat food prop

Status: PROPOSED asset for review. Built and visually inspected in an isolated Godot setup; not admitted into production scenes.

## Reference and license

The inspected [Steak and Herbs photograph](https://commons.wikimedia.org/wiki/File:Steak_and_Herbs_(Unsplash).jpg) is by Jez Timms, published 30 November 2015. Its Wikimedia Commons page explicitly records that this pre-5 June 2017 Unsplash image was published under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The stored 960 px reference thumbnail is from Wikimedia Commons, SHA-256 `02c3bae557103884439d91863b0a5b0700b6453d0561fd52c2452f2c404cbe1f`. The photograph is used only as a shape/material reference; no pixels or 3D geometry are copied into the prop. The rosemary and cutting board are excluded. Verified by reading the Commons license text and opening the downloaded image on 2026-10-25.

## Asset brief

- **Function:** readable food pickup for a terrestrial or social stage prototype; no current game integration.
- **Scale and orientation:** measured GLB bounds approximately 0.80 m wide, 0.62 m long, 0.16 m high; origin at ground contact; Blender +Z up and front +Y, Godot +Y up and front -Z.
- **Viewing distance:** 1.5–6 m, including an elevated gameplay camera. Distinguishable by outline and pale fat edge before close-up detail.
- **Triangle budget:** target under 1,200 triangles (small-prop provisional budget from Bible §16); final export 1,104 triangles, two opaque PBR materials, no texture, no baked light.
- **Materials:** broad muted berry-red muscle, a little deeper burgundy variation, and warm ivory fat. Nonmetallic, rough, no wet/shiny or graphic detail.
- **Source of record:** editable `meat-red.blend` and export `meat-red.glb` under this package. The script is a reproducible construction aid, not a substitute for the `.blend`.

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

## Review process

1. Run `build_meat_red.py` in Blender 5.2.2. It creates the editable `.blend`, gray shape renders, neutral material renders, and selected-object GLB.
2. Inspect `renders/gray-front.png`, `gray-side.png`, and `gray-three-quarter.png` before materials. The first version's pink body, hard seam bends, and 1,272-triangle export were revised. `validate_glb.py` now passes the 1,200-triangle budget.
3. Copy only `project.godot`, `review_godot.gd`, and `meat-red.glb` into a separate temporary Godot review project with a `renders/` directory. Run pinned Godot 4.7.2 `--headless --editor --path <review> --import`, then `--path <review> --script res://review_godot.gd` with the actual Windows OpenGL renderer. Copy its PNG to `renders/godot-gameplay.png`. Keeping `.blend` out of that project avoids requiring editor Blender-path configuration for unrelated blend import.
4. Run `make_comparison_sheet.ps1`, open `comparison.png`, and inspect all final views. See `GATES.md` for results and limitations.

The source photograph is a reference, not a texture. No production scene imports this GLB yet.
