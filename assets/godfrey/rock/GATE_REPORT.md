# Godfrey rock: asset gate report

**Status:** reviewable standalone prop; owner art approval and production scene fit remain pending. No game scene or creature part was changed.

## Final version reviewed

- Original source: `rock.blend`; shape-only checkpoint: `rock_blockout.blend`; exported game file: `rock.glb`.
- Reference: `reference_cc0.jpg`, credited and licensed in `REFERENCE.md`. The photo is an observational reference only; no pixels are used in the material or geometry.
- Paired sheets: `reference_and_rock.png` and `recess_detail.png`. I opened and inspected both sheets, the gray front and three-quarter renders, the material front/gameplay renders, and `godot_review.png`.
- Construction: custom mesh with a broad upper cap, a physical inset on the image-left face, a fuller image-right shoulder, and a narrowed base. No downloaded mesh or third-party shader was imported.

## Technical gate

| Gate | Measured result | Status |
| --- | --- | --- |
| Source remains editable | Blender 5.2.2 LTS saved `rock.blend` and shape checkpoint | Pass |
| Geometry | 482 source vertices, 960 triangles; GLB 2.094 × 1.675 × 1.589 m, Y up | Pass against the proposed 100–2,000 triangle small-prop target |
| Materials | Three opaque, nonmetallic Principled PBR materials, roughness 0.81–0.94 | Pass |
| Textures and baking | Zero textures, zero procedural/unsupported material nodes; no bake needed | Pass |
| Export | 101,092-byte self-contained GLB, one mesh, 3 materials, no camera/light or external dependency; `validate_glb.py` passed | Pass |
| Godot transfer | Godot 4.7.2 imported the GLB in a separate review project; OpenGL 3 rendered a 760 × 760 screenshot that was opened and inspected | Pass for this isolated test |
| Production visual fit | No pool, terrain, target-resolution, or owner art review | Pending |

`technical_report.json` and `glb_validation.json` preserve the machine measurements. `review.gd` and `project.godot` are review aids only; in the local test I copied those two files plus `rock.glb` into an empty temporary project before importing, so the production project was never changed.

## Observed comparison and remaining differences

1. The silhouette reads as a broad boulder with a narrowed ground contact, but is deliberately more regular and rounded than the complex natural reference. The cap and angular recess preserve the strongest readable cues at game scale.
2. The model's recess is real inset geometry and stays visible in gray and Godot views. It is simpler and shallower than the photographed erosion; adding microscopic cracks would exceed the intended stylized detail scale.
3. Godot's neutral review light shows a noticeably darker, flatter red-brown than the Blender studio render. This is disclosed in the detail sheet. Material acceptance under actual Pangaea lighting and at intended on-screen size is pending.

The 100–2,000 triangle target and ~2 m footprint are proposed review budgets, not an approved engine benchmark. This is not integrated into a scene or declared final art until the studio accepts those choices.
