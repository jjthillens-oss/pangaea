# Pale fillet cluster (PROPOSED)

This isolated Godfrey art review asset is **not integrated into production**.

## Purpose and contract

A small, readable food pickup or village provision. Three overlapping, blunt-to-tapered soft pieces make it visually distinct from a single red cut. The source photo informs broad shape only; the model, material colors and composition are original. No photo pixels become a game texture.

| Inspected CC0 photo observation | Original implementation choice | Review criterion |
| --- | --- | --- |
| Three adjacent, partly overlapping tapered pieces, left piece largest | Three individually modeled organic lobes, with the left lobe widest and forward | A three-piece silhouette reads in gray front and three-quarter views at pickup scale |
| Broad blunt top ends and narrow lower tips | Width profile grows to a broad shoulder then narrows unevenly | No uniformly oval or identical repeated pieces |
| Pale narrow inter-piece ridges and soft pink masses | A thin ivory folded rim between two lobes; three restrained rose-clay tones | Pale boundary remains visible without resembling a slash or gory seam |
| Smooth wet highlights in studio light | Opaque nonmetal Principled materials with moderate roughness | Soft material identity survives GLB and neutral Godot light; no photo shine baked into color |
| Photo on a white plate, uncertain underside | Prop rests directly on terrain; underside inferred as a cream-rose soft base | Ground origin at z=0 and no floating geometry in Godot |

Assumptions: static prop with no rig, collision or attachment. Blender +Z up; origin at ground center. Approximate target size 1.15 × 1.02 × 0.23 m, 700–1,500 triangles, at most four opaque glTF-compatible materials, zero textures. These are proposed review budgets, not production approval. Export only asset meshes; cameras and lights remain review-only. Gameplay review should include a 55°-pitch view and a closer three-quarter view. Distinguish this from the darker red-meat variant through three smaller tapered pieces and an ivory fold, never through hue alone.

## Planned gates

1. Build neutral-gray version in Blender and **inspect saved front, side, and three-quarter images** before assigning color. Reject identical lobes, fused intersections, or a swollen single-blob silhouette.
2. Save editable `.blend`; assign export-compatible opaque PBR materials and inspect neutral-light and gameplay-distance views. Avoid subsurface/transmission Blender nodes that glTF drops.
3. Export `meat-pale.glb`, inspect scale/origin/triangles/materials and make a matched reference/result sheet plus close crops.
4. Import GLB in an isolated Godot review setup and inspect a real rendered image. A headless load alone cannot pass this visual gate.
5. Record actual counts, checks, three remaining differences, and all pending gates in `GATES.md`; then open one PR on `godfrey/asset-meat-pale`.

Run the builder in two deliberate passes: `blender --background --python build.py -- --phase=gray`, inspect and revise its three gray views, then `blender --background --python build.py -- --phase=final`. After GLB import, use the isolated `project.godot` and `review.gd` for a screenshot. `make_sheet.py` requires the final Blender and Godot PNGs. The parent owns the shared render window; these commands are only prepared here.

Current state: **preparation only**. No render, `.blend`, GLB, engine import or visual gate is claimed yet.
