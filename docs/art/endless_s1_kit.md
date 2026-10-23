# Endless world S1 art kit (PROPOSED)

This is the band-0 art for the endless cell world, from step S1 in section I of
`/mnt/project-files/pangaea/docs/endless-cell-plan.md`.

The concept sheet is `docs/art/renders/concept/landmarks_sheet.jpg`
(`tools/blender/render_landmark_concepts.py`). Joshua judges the look.

The rough versions come from `tools/blender/make_s1_world_kit.py`. Their review state is
`rough - endless world S1, not visually approved`. They are flat-coloured blockouts at final size,
so engineering can wire the world in early. Each will be replaced by a finished piece with the same
id, node name and footprint.

Ids, footprint classes and record fields will change to match engineering's S1 build plan once it
pins them.

| Id | Kind | Node | Footprint or anchor | Rough triangles |
|---|---|---|---|---|
| `landmark_great_shell`, `landmark_arch`, `landmark_giant_carcass`, `landmark_spire`, `landmark_ring`, `landmark_fan` | Landmark | `Landmark` | Fits the 3 m anchor at the top of `scale_range` (0.9 to 1.06), within ±0.5 m of the plane | ≤ 9,000 |
| `setpiece_giant_bones`, `setpiece_shell_cathedral` | Rare set piece | `Landmark` | Whole-tile dressing, about 9 to 11 m across | ≤ 14,000 |
| `shell_small_lens`, `shell_small_pill` | Shell, small class | `Rock` | 0.6 m, rock outline contract (0.85 to 1.15 × footprint in the swim band) | 1,280 |
| `shell_large_tower`, `shell_large_bell` | Shell, large class | `Rock` | 1.5 m, same contract | 1,280 |
| `rock_a`, `rock_b`, `rock_c` (PR #10) | Shell, medium class | `Rock` | 1.0 m | 464 to 534 |
| `marker_light_column` | Marker: "where you come back" | `LightColumn` | Open tube, radius 0.9 to 1.15, from −6 to +12 m; UV v runs bottom to top for the engine's fade | 384 |
| `marker_origin_arrow` | Marker: "where you began" | `OriginArrow` | Flat chevron, 1 m long, points Godot −Z | 24 |

Each landmark has three dressings recorded: plain, frosted and amber bloom. A dressing is a tint
and a scale. Attached growth nodes come with the finished pieces.

Colours stay clear of the food green and the threat pink: silica blues, lavender, cream and amber.
The giant bones keep no soft tissue and no food rim.

Previews: `docs/art/renders/rough/s1_landmarks_rough.jpg` and `s1_shells_markers_rough.jpg`.
