# Nest-straw prop brief and reference contract

Status: PROPOSED standalone art candidate. No production scene integration or approved visual benchmark is implied.

## Intended use and limits

An empty, stylized creature nest that reads as a safe return/mating place at a third-person terrestrial camera. This candidate is about 0.95 m wide, 0.85 m deep and 0.27 m tall. Blender up is +Z and front is +Y; the origin rests at the bottom center. The Godot import must keep that physical size and upright orientation. The prop is static, with no rig or animation. Collision is left to later production integration.

Target budget for this one prop: at most 2,000 triangles and three opaque, nonmetallic Principled materials. No texture is required unless visual inspection shows a specific lost material feature; if a procedural node is added it must be baked before GLB export. The candidate will not enter the production asset registry without benchmark approval.

## Observable reference contract

| CC0 photo observation | Original implementation choice | Visible pass criterion |
| --- | --- | --- |
| A broad, low cup tapers to a smaller footprint; the top opening is elliptical in perspective. | Interlaced tapered reed strips form a shallow ring above a concave lower web. | At a three-quarter gameplay view, the top opening and supporting sidewall read separately; the profile stays low. |
| The inner well is dark and visibly recessed below an uneven upper rim. | The center sinks below the rim and uses a dark fiber material with restrained ambient shadow. | Gray material views show geometric depth; the cavity does not depend on painted black alone. |
| Several stout pale ribbons overlap horizontally around the near rim. | Broad curved strips cross and stack with small height offsets. | At ~120 px display width, several crossing bands remain visible rather than becoming noise. |
| A handful of wiry stalks project above and beyond the cup. | Sparse tapered three-sided stems extend at irregular angles. | Front and side silhouettes show 4–8 distinct fine outward strokes, without a uniform circular fringe. |
| Strands vary from fine dark twigs to wider pale fibers. | Three rough nonmetal materials: golden reed, pale dry fiber, dark twig. | Under neutral light the material groups stay distinct at gameplay distance. |
| The photograph is monochrome; its actual colors, underside and back are uncertain. | Infer a coherent warm mineral/straw palette and construct unseen surfaces consistently. | Do not claim a color match; inspect the entire prop from alternate views and disclose the inference. |

The photo includes a human hand and background. Those are context and are not modeled. The nest shape is an observation, not geometry or texture to copy.

## Planned gates

1. **Gray shape:** Save a blockout source and inspect top, side and matched three-quarter images. Revise if the opening collapses, the cavity reads flat or the rim is mechanically regular.
2. **Material:** Save the final editable source. Inspect constant-color PBR materials under neutral broad/fill/grazing lights, including a gameplay-distance crop; no bloom or dramatic depth of field.
3. **Export:** Export only the mesh to GLB, verify origin, orientation, dimensions, UVs, normals, triangle/material counts, and no review lights or cameras.
4. **Engine:** Import in an isolated Godot review project and inspect an actual rendered gameplay-distance view against the paired CC0 image. Headless import alone is insufficient.
5. **Comparison:** Save paired reference/result sheet and the actual viewed images. Mark gates as pass, needs revision or unverified, with remaining differences.

These gates are pending until Blender and Godot work run.
