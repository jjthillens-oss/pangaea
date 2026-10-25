# Visual rubric

Status: axes from Bible §15 (CONFIRMED source); thresholds and scoring guide PROPOSED.

Score in-engine frames at the gameplay camera, 1920×1080, with a clay frame next to the beauty frame where the
asset is new. Never score generated beauty images in place of in-engine evidence (Bible §22). Compare against the
reference frames below at the same camera scale.

**Pass:** every axis 3 or more and a mean of 4 or more. Any axis below 3 sends the work back with the reason.
Numbers never approve a new art style; that is the owner's M2 benchmark call (Tier 3).

| Axis | 1 (fail) | 3 (acceptable) | 5 (benchmark) |
| --- | --- | --- | --- |
| Silhouette | Reads as a primitive or a blob at gameplay distance | Recognisable kind (cell, fish, walker) | Identifiable as this species from the outline alone |
| Proportions and pose | Floating, clipping, sliding feet, T-pose | Grounded, no clipping | Pose shows weight and intent |
| Expressiveness | Dead eyes, no face direction | Eyes and facing show attention | You can tell its mood at a glance |
| Material cohesion | Photo noise, mixed polygon language, raw scans | Matches the family in `docs/art/ART_DIRECTION.md` | Indistinguishable in finish from the approved ladder |
| Palette and lighting | Hue clash; food green or threat red used as decor; washed out | Biome palette held; targets readable | Depth and mood without hiding form |
| Environment density | Empty or cluttered | Layers present, play plane clear | Layered depth that sells scale |
| Readability | Food, threat and the player blur together | Clear at 1080p | Clear at a glance, even at night or in fog |
| Polish next to the bar | Clearly below Spore's Steam store images | Close | Matches that polish with original designs |

## Reference frames

Good (scores 4 to 5): `docs/art/renders/cell_ladder_3_target_godot_game.jpg`,
`docs/art/renders/cell_ladder_3_target_sheet.jpg`, `docs/art/renders/material_sheet.jpg`, the deep-blue micro-world
frames in the project files (micro-world folder of the shared screenshots), and the creature part sheets in
`docs/art/renders/production/`.

Bad (scores 1 to 2): `docs/art/renders/cell_ladder_0_blockout_sheet.jpg` as a finished asset (it is a blockout), the
pre-2026-10-22 teal pool, any primitive standing in for a production mesh outside
`assets/records/placeholders/inventory.json`.

When the owner disagrees with a score in the Sunday review, add that frame here with his verdict. That keeps the
reviewer calibrated to his eye.
