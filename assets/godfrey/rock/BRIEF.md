# Sandstone boulder brief and reference contract

Status: PROPOSED, isolated asset study. Stable study ID: `godfrey_rock_01`. No production scene integration.

## Use and budget

An original stylized terrestrial scenery rock. It must read at a roughly 4–8 m gameplay camera distance and remain recognizable from multiple angles. Proposed Blender extent: about 2.0 m wide, 1.65 m high, 1.55 m deep, with the ground contact at Blender Z = 0 and a ground-centered origin. Blender front is +Y/up +Z; Godot import must verify the conversion. Proposed small-prop budget: 100–2,000 triangles and no more than three material slots. These are review targets, not approved global budgets.

The editable `.blend`, GLB, gray-shape images, neutral-material images, paired comparison sheet, and final gate report will live in this directory. Reference lights/cameras belong in a separate collection excluded from export. No collision or gameplay behavior is proposed.

## Reference contract

| CC0 photo observation | Original Blender choice | Visible pass criterion |
| --- | --- | --- |
| Upper mass is broad and squat, not a tall shard | Asymmetric rounded volume with a lower right shoulder | Gray front and three-quarter views read wider than tall |
| Crown has a shallow, uneven layered top | Two broad stepped cap regions in geometry | Layer break remains visible at gameplay size without becoming stripes |
| Left-center recess is wide and dark | Real inset cavity bounded by irregular faceted lips | Grazing-light gray view shows depth and self-shadow, not a painted oval |
| Right half is fuller and smoother | Larger right lobe with fewer large chips | Right outline differs from left in front and three-quarter views |
| Lower contact is narrower than the bulk | Undercut lower profile and stable, flat ground patch | Silhouette has a broad overhang yet no implausible floating gap |
| Surface is warm rust-red with darker fissures | Two or three opaque stone PBR material regions; metallic 0 and high roughness | Neutral-lit render has broad warm grouping without photoreal noise |
| Small eroded edge irregularities | Limited silhouette chips and planar facets | No pillow-like uniform bevels or noisy all-over microgeometry |

The photo does not determine hidden faces, true roughness, or exact dimensions. Those will be inferred coherently and checked from alternate views. No shape or texture is copied from a 3D source.

## Gate status before authoring

- Shape-gray front/side/three-quarter: **pending**.
- Material identity and export-compatible nodes: **pending**. Plan uses Principled BSDF constants, so unsupported procedural nodes should require no bake.
- Neutral-light render and actual image inspection: **pending**.
- GLB scale/orientation/material/triangle inspection: **pending**.
- Godot isolated import and rendered gameplay-distance review: **pending**.
- Paired reference/result sheet and final three-difference review: **pending**.

The reference image and its CC0 proof are in [REFERENCE.md](REFERENCE.md).
