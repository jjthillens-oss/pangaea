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
| Nostalgia (the childhood-dream test) | Reads as a tech demo, a survival game or a lab scene | A player of the original would recognise the kind of game at a glance | They smile before they analyse it |

## Nostalgia checklist

From the style cross-reference (`docs/research/style-crossref.md` section 6, PR #202; PROPOSED thresholds). The owner's
aim: "twenty years later, better graphics but not much better". Each rule is pass or fail; two fails on a frame send it
back, whatever the axis scores.

1. **Toy forms.** Rounded, chunky silhouettes; hard edges only on spikes, teeth and tools.
2. **Face first.** Eyes 18 to 25% of body width, lidded, pointed at something; mood readable at the gameplay camera.
3. **Coloured world.** No habitat surface below about 25% saturation except rock and sand; caps about 55% habitat,
   75% creatures, food and threat above. Nothing reads grey or chalky.
4. **Creature over world.** The player creature is at least one saturation notch and 15 L* away from its ground.
5. **Painted, not photo.** No photo grain or tiling noise at the gameplay camera; detail is pattern and shape.
6. **Warm light, blue shadow.** Warm key, blue-tinted shadows, never black; night and fog keep rule 4.
7. **Dressed frame.** At least three layers (ground cover, mid dressing, a landmark or horizon); play plane clear.
8. **Charm in motion.** Every rigged body breathes and blinks; landing, eating and part placement squash or wobble.
9. **One bar, one currency** per stage, plus at most two small status readouts.
10. **Editor as reward.** Palette, plinth, test drive; the creature idles on the plinth; a placed part sounds and wobbles.
11. **Pickup language.** Shape, bob and a soft ground glow; never a vertical light beam or a floating icon.
12. **Ceiling check.** No effect whose only argument is realism; a frame that could pass as another genre fails.
13. **Audio match.** Calm melodic bed, a danger layer that keeps the warmth, wet soft effects; silence in an editor or
    a new stage fails.

## Reference frames

Good (scores 4 to 5): `docs/art/renders/cell_ladder_3_target_godot_game.jpg`,
`docs/art/renders/cell_ladder_3_target_sheet.jpg`, `docs/art/renders/material_sheet.jpg`, the deep-blue micro-world
frames in the project files (micro-world folder of the shared screenshots), and the creature part sheets in
`docs/art/renders/production/`. From the shared screenshots: `micro-world/micro_ingame_preview.jpg`,
`creature-parts/cpart_lineup.jpg`, `menus-modern/title_after.png`, `menus-modern/editor_after.png`.

Bad (scores 1 to 2): `docs/art/renders/cell_ladder_0_blockout_sheet.jpg` as a finished asset (it is a blockout), the
pre-2026-10-22 teal pool, any primitive standing in for a production mesh outside
`assets/records/placeholders/inventory.json`.

Needs work (shared screenshots): `creature-world/forwardplus_field.png` (checklist 3, 7), `aquatic/7_shore_offer.png`
(4, 7), `creature-stage/world_pickup_near.png` (11), `m1-production-art/pool_hunter_godot.jpg` (7, without ambience).

When the owner disagrees with a score in the Sunday review, add that frame here with his verdict. That keeps the
reviewer calibrated to his eye.
