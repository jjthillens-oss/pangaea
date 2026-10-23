# Endless world S1 art kit (PROPOSED)

This is the band-0 art for the endless cell world, task T4.1 of the S1 build plan. It is built to
sections 4.4 and 5 of `/mnt/project-files/pangaea/docs/s1/s1-interfaces.md`.

The pieces come from `tools/blender/make_s1_kit.py`, which also writes `game/data/placement_kit.json`.
`tests/test_kit_assets.gd` checks the kit file against the placement rules and every GLB against the
art contract (bounds, swim-band outline, heights, triangle budgets, node names, growth children,
colours clear of the food and threat hues).

The finished pieces come from `tools/blender/make_s1_production.py`. It runs the kit's own
builders, so the geometry and contract are unchanged. It then turns each flat material into
greyscale procedural detail and bakes one texture set per piece: albedo detail with ambient
occlusion, ORM and a normal map. The detail is silica ribs, pore rings and striae on the glass,
membrane cells on the casings, glowing granules on the amber and fibres on the stalks. Each
material keeps its name and flat colour, and the engine draws the baked detail times that colour.
Textures are 512 px for shells, 1024 px for landmarks and rare pieces, and 256 px for markers.
The review state is `production rev 1 - M1, awaiting owner look review`, so the kit marks no piece
as a placeholder. Joshua judges the look. Review sheets are in
`docs/art/renders/production/<id>_sheet.jpg` (`tools/blender/render_production.py <id>`).

The concept sheet is `docs/art/renders/concept/landmarks_sheet.jpg`
(`tools/blender/render_landmark_concepts.py`).

| Id | Kind | Footprint or anchor | Scale | Notes |
|---|---|---|---|---|
| `shell_diatom_disc`, `shell_radiolarian_lens` | Shell, `fp_s` | 0.75 m | 0.8 to 1.2 | Pickable |
| `shell_girdle_drum` | Shell, `fp_m` | 1.05 m | 0.85 to 1.15 | Pickable |
| `rock_a`, `rock_b`, `rock_c` | Shell, `fp_m` | 1.0 m | 0.8 to 1.5 | The home rocks from PR #10, not pickable (rule 12) |
| `shell_fluted_tower` | Shell, `fp_l` | 1.2 m | 0.75 to 1.25 | Pickable |
| `shell_bell` | Shell, `fp_l` | 1.35 m | 0.88 to 1.12 | Pickable |
| `landmark_great_shell`, `landmark_ring` | Landmark, group 0 | collide 2.0, anchor 3.0 | 0.92 to 1.06 | |
| `landmark_spire`, `landmark_fan` | Landmark, group 1 | same | same | |
| `landmark_arch` | Landmark, group 2 | same | same | |
| `landmark_shed_husk` | Landmark, group 3 | same | same | A big empty vase-shaped casing split along a seam |
| `rare_giant_husk` | Rare, `giant_husk` | four colliders | 1 | The cracked-open glass husk of a dead giant microbe, picked clean, no food rim |
| `rare_shell_cathedral` | Rare | eight colliders | 1 | A ring of glass drums with lattice spires |
| `marker_checkpoint_column` | Marker | 0.5 m wide tube | 1 | "Where you come back"; unlit cream, UV v runs bottom to top for the fade |
| `marker_origin_arrow` | Marker | flat, 1.2 m long | 1 | "Where you began"; points Godot -Z |

Every landmark has three dressings: plain, frosted (shows `Growth_Needles`) and amber
(shows `Growth_Beads`). Growth nodes are hidden children of the root mesh.

Triangles: shells 960 to 1,216 (budget 1,300), landmarks 4,224 to 5,672 (6,000), giant husk 2,908
and cathedral 8,640 (12,000), column 336 and arrow 24 (800).

Colours stay clear of the food green and the threat pink: silica blues, lavender, a warm cream and
amber. The cell stage is microscopic, so nothing has bones or skeletons.
