# Pale fillet cluster (PROPOSED)

This isolated Godfrey art review asset is **not integrated into production**.

## Purpose and contract

A small, readable food pickup or village provision. Three overlapping, blunt-to-tapered soft pieces make it visually distinct from a single red cut. The source photo informs broad shape only; the model, material colors and composition are original. No photo pixels become a game texture.

| Inspected CC0 photo observation | Original implementation choice | Review criterion |
| --- | --- | --- |
| Three adjacent, partly overlapping tapered pieces, left piece largest | Three individually modeled organic lobes, with the left lobe widest and forward | A three-piece silhouette reads in gray front and three-quarter views at pickup scale |
| Broad blunt top ends and narrow lower tips | Width profile grows to a broad shoulder then narrows unevenly | No uniformly oval or identical repeated pieces |
| Pale narrow inter-piece ridges and soft pink masses | Overlapping boundaries between three restrained rose-clay tones, with cream-rose underside edges | Each boundary remains visible without a graphic seam |
| Smooth wet highlights in studio light | Opaque nonmetal Principled materials with moderate roughness | Soft material identity survives GLB and neutral Godot light; no photo shine baked into color |
| Photo on a white plate, uncertain underside | Prop rests directly on terrain; underside inferred as a cream-rose soft base | Ground origin at z=0 and no floating geometry in Godot |

Assumptions: static prop with no rig, collision or attachment. Blender +Z up; origin at ground contact. Actual GLB bounds are 0.8646 × 0.9987 × 0.1819 m in Blender width × length × height, with 1,296 triangles, four opaque glTF-compatible materials and zero textures. The proposed review budget was 700–1,500 triangles and at most four materials; this is not production approval. Export only asset meshes; cameras and lights remain review-only. Gameplay review includes a 14 m, 55°-pitch view and a closer three-quarter view. Distinguish this from the darker red-meat variant through three smaller tapered pieces and their overlap, never through hue alone.

## Planned gates

1. Build neutral-gray version in Blender and **inspect saved front, side, and three-quarter images** before assigning color. Reject identical lobes, fused intersections, or a swollen single-blob silhouette.
2. Save editable `.blend`; assign export-compatible opaque PBR materials and inspect neutral-light and gameplay-distance views. Avoid subsurface/transmission Blender nodes that glTF drops.
3. Export `meat-pale.glb`, inspect scale/origin/triangles/materials and make a matched reference/result sheet plus close crops.
4. Import GLB in an isolated Godot review setup and inspect a real rendered image. A headless load alone cannot pass this visual gate.
5. Record actual counts, checks, three remaining differences, and all pending gates in `GATES.md`; then open one PR on `godfrey/asset-meat-pale`.

Run the builder in two deliberate passes: `blender --background --python build.py -- --phase=gray`, inspect and revise its three gray views, then `blender --background --python build.py -- --phase=final`. For import and rendered screenshots, copy the GLB into `review_project/` and run its `project.godot` and `review.gd` with Godot Compatibility/OpenGL 3. The nested review project avoids Godot scanning the editable `.blend`. `make_sheet.ps1` uses the final Blender and Godot PNGs. The parent owns the shared render window.

`.gdignore` keeps this review-only package out of the production game's Godot import scan. The standalone nested review project imports a copy of the GLB on demand; its generated copy, cache and screenshots are intentionally not committed because inspected captures live beside this README.

Current state: final Blender and GLB package reviewed in an isolated Godot setup. This has not been placed in the game's production scene or accepted under its actual habitat lighting.
