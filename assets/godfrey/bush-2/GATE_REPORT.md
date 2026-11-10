# Bush 2 final-revision gate report

Status: **PROPOSED, ready for studio art review; not admitted into production**. Source of record is `bush-2.blend`; the shape-only checkpoint is `bush-2-shape.blend`. Export is `bush-2.glb`. All files and captures remain under `assets/godfrey/bush-2/`.

## Source and intent

The [CC0 reference and license record](provenance.md) describe a dense dark bronze-green ti shrub. The 500 px reference was actually viewed; the final [comparison sheet](comparison-sheet.png) was generated and opened for inspection. The model is original Blender geometry, not a traced or generated mesh. It differs from the separate airy flowering sage variant through a compact, upright, staggered broadleaf crown and absence of flowers.

## Final counts and technical gates

| Gate | Result | Evidence |
| --- | --- | --- |
| Editable source and gray checkpoint | **Pass** | `bush-2.blend`, `bush-2-shape.blend`; Blender 5.2.2 LTS generated both after deterministic geometry construction. |
| Shape before material | **Pass with stylization difference** | `views/gray-front.png`, `gray-side.png`, `gray-three-quarter.png`, `gray-game-distance.png` inspected. The first attempt's separated palm-like whorls failed; continuous golden-angle leaf placement and a shared basal fan fixed that shape. The final still has sharper low-poly leaf tips than the photograph. |
| PBR identity | **Pass** | Three opaque Principled materials: rough nonmetal wood, dark bronze-purple upper leaves, olive lower leaves. No unsupported procedural nodes, alpha cards, emission, or texture dependency. `views/material-*.png` inspected under neutral broad key/fill. |
| Export structure/budget | **Pass** | `validate_glb.py`: GLB 2.0, 134,476 bytes, 1,744 triangles (budget ≤2,000), 3 materials (budget ≤4), 0 images (texture budget 0), one mesh, normals and indexed triangles. `geometry-report.json` bounds: approximately 1.54 × 1.03 × 1.61 m; ground origin. |
| Godot import and visual transfer | **Pass in isolated review** | Godot 4.7.2 imported GLB in a separate project with no errors. On Windows RTX 5070, Compatibility/OpenGL 3 non-headless review produced `godot-review.png` at 1024×768, opened and inspected. Brown wood, bronze/olive foliage, upright orientation and overlapping silhouette remain visible. A headless run used the dummy renderer and could not capture pixels; it was not treated as visual proof. |
| Paired reference/result sheet | **Pass** | `comparison-sheet.png` inspected at final version, with reference, clay, Blender PBR, Godot import and upper-crown crops in comparable framing. |
| Production scene appearance and performance | **Unverified** | No production scene was edited or asset admitted. Habitat lighting, placement density, collision, GPU overdraw and final art benchmark still require studio review. |

## Visible differences and open review points

1. The reference has smoother, curled leaf edges; this low-poly interpretation has sharper tapered tips. Its overlapping crown and color grouping remain clear at the proposed prop budget.
2. The photograph has more fine branches and small color shifts than three constant PBR materials reproduce. The exported asset deliberately uses broad color groups to retain readability at game distance.
3. The reference's exact hidden-side crown and material roughness cannot be recovered from one photo. We made a coherent all-around stem fan and used rough nonmetal surfaces; studio review may adjust the palette in the target habitat.

This is a review-ready prop, not a claim of production visual acceptance, 60 fps performance, or integration. No cpart asset or `game/ui` file changed.
