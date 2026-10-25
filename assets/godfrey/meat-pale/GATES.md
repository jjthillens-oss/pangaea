# Asset review gates

| Gate | State | Evidence needed |
| --- | --- | --- |
| CC0 provenance and actual image inspection | PASS | `PROVENANCE.md` and retained reference thumbnail; source/author/license reviewed on Commons |
| Shape-gray front, side and three-quarter | PASS | Opened all three PNGs. First pass had cap tears and a detached tube-like fold; both were removed. Third pass has three distinct overlapping soft lobes, left largest. |
| Defining three-piece silhouette at gameplay distance | PASS in isolated view | Inspected `godot_gameplay.png` at 14 m, 55° pitch, 45° FOV, 960×720. Three lobes still read at about 60 px; actual habitat clutter may change this. |
| PBR materials and neutral-light response | PASS in isolated view | Three nonmetal rose-clay tops plus a cream-rose underside edge use Principled base color/roughness only. Viewed final Blender material and actual Godot close screenshot; no procedural nodes or textures to lose. |
| GLB content, scale, origin and budget | PASS | `validate_glb.py` parses final binary: 1,296 triangles, three meshes, four materials, zero textures/images, 31,948 bytes, dimensions 0.8646 × 0.1819 × 0.9987 m in glTF X/Y/Z; Y-up ground min exactly 0 after correction. Import succeeded in pinned Godot 4.7.2. |
| Paired reference/result and close crops | PASS | Opened final `reference_result_sheet.png`: source, gray, material, source center crop, Godot close and 14 m view correspond to the corrected GLB. |
| Godot visual review | PASS in isolated view | Pinned Godot 4.7.2 Compatibility/OpenGL3 on NVIDIA RTX 5070 rendered `godot_review.png` and `godot_gameplay.png` at 960×720, exit 0. Both were opened and inspected. Headless import separately passed but was not treated as visual proof. |
| Production habitat and game integration | UNVERIFIED | No scene integration, collision, animation or actual in-game lighting review was requested or performed. |

Three largest remaining differences: (1) the photo has natural fine surface contours and glossy highlights, deliberately simplified to smooth, moderately rough surfaces; (2) the central pale ridge reads only as overlapping masses at 14 m, with no separately raised stripe; (3) the underside is inferred and the photographed plate is excluded. These are visible tradeoffs for a restrained, non-graphic pickup. A real habitat and production lighting review remain open before admission to game assets.

The first isolated Godot project location accidentally scanned `.blend` files and logged a Blender-path warning despite exit 0. It was replaced with nested `review_project/`; that final project imported only the GLB and produced the saved render without the warning. A `--headless` review script produced no pixels (dummy renderer); the final visual evidence is from a hidden Compatibility/OpenGL3 GPU process, while headless import was used only for structure.
