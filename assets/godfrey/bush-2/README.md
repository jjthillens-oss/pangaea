# Bush 2 — dense bronzeleaf crown

Status: **PROPOSED asset in preparation**. This is an isolated review package, not a production scene integration. Render, export, and engine gates remain pending.

This variant is deliberately distinct from bush 1's wide, airy, blue-flowered sage fan. Bush 2 is a compact, upright cluster of dark broadleaf rosettes with a taller central crown, two offset shorter crowns, and small lower offshoots. It has no flowers. A top-down angled camera should see overlapping leaf layers and some gaps; the side must still read as a shrub, not a flat cutout.

## Reference contract

| Reference observation | Original implementation choice | Visible pass criterion |
| --- | --- | --- |
| Taller middle mass with shorter side crowns | One central upright stem, two offset stems and two low shoots | Gray front and three-quarter views show a stepped crown, not a sphere or perfect cone |
| Dense pointed, recurved broad leaves | Individually bent double-sided lance leaves in staggered whorls | Distinct leaf tips and layered clusters read at gameplay distance; no square card canopy |
| Narrow dark holes between leaf groups | Leave small stem/air pockets while overlapping many leaves | Gray side view has depth and a few deliberate negative spaces |
| Deep bronze-purple upper foliage, olive lower foliage | Three constant opaque nonmetal Principled materials: bronze, olive, woody stem | Large color groups match the observation under neutral light; no baked highlights or generic noise |
| Natural asymmetric offshoots | Unequal side branches and a restrained lean | Silhouette is not mirrored; all crowns remain planted and balanced |

## Proposed gameplay specification

- Function: stationary edible-plant habitat prop for later art review only. It has no collision, gameplay logic, animation or production placement in this PR.
- Size: roughly 1.5 m wide and 1.7 m tall, origin at ground center, Blender +Z up. In Godot 1 m = 1 unit; review front orientation +Y Blender / -Z Godot. These are review assumptions, not adopted production tuning.
- Camera: compare at the repository's 55° / 14 m gameplay camera and at a closer neutral turntable angle. Preserve the main mass at both sizes.
- Budget: at most 2,000 triangles, four opaque PBR material slots or fewer, no texture required. Actual counts and GLB transfer must be reported after rendering/export.
- Do not flatten organic form with hard-surface cleanup. Geometry carries the broad leaves and silhouette; simple PBR constants carry color and restrained roughness. Review lights and cameras are excluded from export.

## Required gates before PR

1. Build editable `.blend` without altering reference source; capture and inspect gray front/side/three-quarter views before using materials.
2. Inspect neutral material close-up and gameplay-distance views. Revise visible geometry/material defects.
3. Export GLB and inspect scale, triangle count, slots, facing, normals and absence of unsupported procedural nodes. Record counts in a gate report.
4. Import into an isolated Godot review setup, capture and **inspect** an actual Godot render. Headless import alone does not clear this gate.
5. Save a paired reference/result comparison sheet from the final revision and report each gate as pass, needs revision, or unverified, plus three remaining differences.

No screenshot, GLB or report currently claims a passed gate. The builder in this folder is source preparation pending the shared Blender window.
