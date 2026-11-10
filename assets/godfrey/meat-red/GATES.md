# Red meat asset gate report

Status: PROPOSED for studio visual review, 2026-10-25. Final revision is the `meat-red.blend` / `meat-red.glb` paired with `comparison.png` in this package. This is an isolated prop, not a production integration.

| Gate | Result | Direct observation or check |
| --- | --- | --- |
| CC0 provenance | Pass | Opened the 960 px reference image; Commons identifies Jez Timms, 30 November 2015, pre-2017 Unsplash CC0. URL and image SHA-256 are in README. No photo pixels are used in the mesh/material. |
| Gray silhouette and volume | Pass for stylized pickup | Inspected front, side, three-quarter, and elevated gray renders. A shallow single cut with asymmetrical scalloped edge and one notch reads at distance. The initial too-smooth form was retained only after the notch and partial edge stayed visible from multiple views; organic softness is intentional. |
| Materials and lighting | Pass for proposed style | Inspected neutral Blender material views. Revised overly pink first pass to darker matte red and thinned/curved pale seams. Broad red area, partial warm-ivory rim, and shallow veins remain distinct; metallic is zero. No directional highlight is baked. |
| Export budget | Pass | `validate_glb.py`: 1,104 indexed triangles, 2 exportable PBR materials, 0 textures, 6 meshes, 0 cameras/lights, 28,328 bytes. First build had 1,272 triangles and was revised rather than raising the gate. Blender 5.2.2 saved editable source. Bounds from GLB POSITION accessors are approximately 0.80 × 0.62 × 0.16 m after axis conversion. |
| Godot transfer | Pass for isolated import and visual | Godot 4.7.2 on Windows/NVIDIA GeForce RTX 5070 imported the GLB in a separate temporary review project; the actual OpenGL 3.3 Compatibility renderer produced `renders/godot-gameplay.png`. Opened the pixels: deep matte berry-red slab, ivory rim, thin seams, no missing materials, black faces, or misplaced camera/light. The 900×900 image is a representative elevated view, not an in-game placement test. |
| Paired comparison | Pass with stated fidelity level | Opened `comparison.png` after creation. It pairs cropped CC0 reference with final Godot view at approximate elevated framing and shows final Blender gray/material three-quarter views. Exact reconstruction was not the target; broad shape/material cues are retained as an original, non-graphic game-food prop. |
| Production/gameplay acceptance | Unverified | No pickup scale, collision, terrain contact, scene lighting, or multi-instance performance acceptance in the production game. No production scene integration was requested. |

## Three largest remaining differences

1. The photograph has dense real muscle grain and complex marbling; this deliberately low-detail prop uses three simple pale arcs and broad matte color to stay legible at pickup distance.
2. The photographed cut has a more complex upper boundary and additional neighboring meat outside the chosen crop; the prop is one self-contained, asymmetrical slab.
3. Blender's AgX neutral render is lighter than the Godot Compatibility render. Godot keeps the intended red/ivory separation, but studio benchmark lighting and real pickup placement remain untested.

The result is technically valid and visually reviewed in isolation. The studio still needs to decide whether this proposed food style fits the approved in-game benchmark.
