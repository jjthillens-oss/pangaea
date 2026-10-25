# Bush 1 asset gate report

Final candidate: `bush-1.glb`, generated from the editable `bush-1.blend` with Blender 5.2.2 LTS. `bush-1-shape.blend` preserves the gray silhouette review state. All work is confined to this asset folder.

| Gate | Evidence | Result |
| --- | --- | --- |
| Reference contract | [CC0 sage photograph and provenance](provenance.md); [paired comparison sheet](sheets/reference-result.png) | Pass for an original stylized interpretation. The photograph is only a reference. |
| Gray shape first | [Front](views/gray-front.png), [side](views/gray-side.png), [three-quarter](views/gray-three_quarter.png) | Pass after a revision that thinned the woody stems and spread leaf pairs along the branches. Airy asymmetric fan and open gaps are visible in all three views. |
| PBR material | [Material front](views/material-front.png), [side](views/material-side.png), [three-quarter](views/material-three_quarter.png) | Pass: opaque rough nonmetal wood, sage leaves, and blue-violet blooms. All three are constant Principled materials, so no baked texture is required. |
| Export budget | `geometry-report.json`; independent inspection of GLB JSON chunk | Pass: **1,584 triangles**, **3 materials**, **3 primitives**, **0 textures**, **0 images**, 115,412-byte GLB. Bounds approximately **1.92 × 1.08 × 1.30 m**; bottom vertex is 0.071 m above origin. |
| Godot import and render | Separate temporary Godot 4.7.2 project, [800 × 800 OpenGL Compatibility screenshot](views/godot-review.png), included `review/` script | Pass for isolated import and visible render. The screenshot was inspected, not inferred from a headless load. The original `--headless` capture used Godot's dummy renderer and could not provide pixels; the non-headless Compatibility run rendered with the local NVIDIA device. |
| Gameplay readability | Same [Godot screenshot](views/godot-review.png) at a roughly 3–4 m camera distance | Partial: broad fan and muted leaves are clear; violet flower accents remain deliberately small and can disappear at greater distance. This is a sparse flowering sage, intentionally distinct from the later dense broadleaf bush. Final placement/lighting in a production scene is untested. |

The first gray review looked like bare twigs. We increased secondary leaf groups and added paired foliage lower on each primary stem, then inspected new front, side and three-quarter gray views before accepting the material pass. The final muted flowers were enlarged once for visibility. No production scene, `cpart_*` asset, or UI file was changed.

The isolated Godot editor import emitted a safe-save warning while using the sandboxed settings directory, but generated the imported `.scn`; the subsequent 800 × 800 rendered capture completed successfully. This is visual evidence for the standalone GLB only, not whole-game visual approval.
