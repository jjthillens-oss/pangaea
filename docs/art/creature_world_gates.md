# Creature world art: gate verdicts (PROPOSED art)

The finish gates every 3D asset passes (the finish-hunyuan-assets gates): Gate 1 shape (neutral grey front, side and
three-quarter renders), Gate 2 materials with identity (close-up), Gate 3 neutral lighting, Gate 4 export and Godot verification at gameplay distance. Each verdict is
pass, needs revision or unverified, with the observation it rests on. Blender sheets come from
`tools/blender/render_world_review.py` (one sheet per asset, such as
`docs/art/renders/production/creature_field_ground_gates.jpg`); in-game frames from
`tools/godot/creature_world_gameplay_shots.gd` in the real `game/scenes/creature/creature_world.tscn` (seed 4242, the
`s1_quadruped` starter, HUD hidden), Forward+ on lavapipe and Compatibility on llvmpipe. Every render named here was
opened and looked at. The assets the job has not revised yet keep their baseline observations in
`docs/art/creature_world_dressing.md` ("Baseline frames").

## creature_field_ground, rev 2 (field rev 2a, 2026-10-25)

15 488 triangles (budget 16 000): `CreatureField` 12 800, `CreatureFieldHills` 2 688. One material,
`M_CreatureField` (external ShaderMaterial `assets/export/M_CreatureField.tres`); textures: turf albedo and normal at
1024 px, earth albedo and normal and the patch mask at 512 px. GLB 351 KB.

| Gate | Verdict | Observation |
| --- | --- | --- |
| 1 Shape | pass | `docs/art/renders/production/creature_field_ground_gates.jpg` (grey front, side, three-quarter, top; grazing key): a flat square centre, a low berm step at the walls, and a ring of hills that rises unevenly round it, its rim broken into rises and saddles rather than a level wall. The 0.12 m relief inside the walls does not show at this scale, as intended (the contract test reads it from the mesh). |
| 2 Materials | pass (in Godot) | The Blender material is a flat stand-in (the beauty, close-up and unlit panels of the sheet show only that); the shipped material is the Godot shader, so Gate 2 is judged in engine. `docs/evidence/credit-creature-world-art/env_close_ground_fplus.jpg` (right) at 1 to 3 m: individual grass blades, dark gaps, clump light and dark, and a bare earth patch with sunk pebbles and a ragged edge; no puddle-like round blotches (rev 1's failure). |
| 3 Neutral lighting | pass | The tiles carry no baked light: the turf albedo's mean is L 46, C 28, h 147 and the earth's L 45, C 20, h 70 (`tests/test_creature_world_art.gd` prints them); light and shade come from the scene. The same field reads as land under both renderers' light and under main's light (`env_*.jpg`, left halves), so the look does not depend on one light rig. |
| 4 Export and Godot | pass (Forward+); Compatibility reads as land but overexposed | Forward+ (`env_world_spawn_fplus.jpg`, `env_world_low_fplus.jpg`, right halves): a sunlit meadow with earth patches, low hills past the walls and a far ridge fading into haze; the skyline is land (horizon dE 17), turf on screen L 57 to 61, C 21 to 26, h 144 to 150. Compatibility (`env_world_roam_compat.jpg`, `env_world_low_compat.jpg`): the same land read and skyline (dE 35 to 38), turf h 152 to 154, but the shadowed sun's additive sRGB pass lifts the lit turf and hill faces to a pale mint (L 67 to 74); that is the renderer (docs/TOOLCHAIN.md). The import maps `M_CreatureField` and switches the hills' shadow off (`PATH:CreatureFieldHills`); the contract test checks both. One extra draw call and 2.7k primitives against rev 1. |

Not covered yet: the field's scatter (grass tufts, ferns, flowers, pebbles inside the walls; boulders and trees on
the berm), which comes with the kit assets, and the Gate 4 roam frame in Forward+ (a 240-frame walk on lavapipe takes
about two hours; the roam frame was judged in Compatibility).

## The flora and rock kit, rev 1 (2026-10-25)

Built by `tools/blender/creature_flora.py` (through `tools/blender/make_creature_world.py`); see "The flora and rock kit" in
`docs/art/creature_world_dressing.md`. Blender sheets: one per asset, such as `docs/art/renders/production/creature_grass_tuft_gates.jpg`. Godot frames:
`tools/godot/world_dressing_shot.gd -- --kit` in the creature world's own light (the WorldEnvironment and Sun of
`game/scenes/creature/creature_world.tscn`), Compatibility on llvmpipe and Forward+ on lavapipe; the composite
evidence is `docs/evidence/credit-creature-world-art/kit_*.jpg`. The kit is not placed in the game yet: the field's
scatter (step 10) composes it, so Gate 4 here is the kit staged on the real field at the gameplay camera's distance.

### creature_grass_tuft, creature_fern_clump, creature_flower_clump (meadow cards)

48, 96 and 72 triangles (budgets 48, 96, 120); one material, `M_MeadowCards` (external `StandardMaterial3D`,
`assets/export/M_MeadowCards.tres`); one texture, `assets/export/creature_flora/T_MeadowCards.png` (1024 px RGBA,
shared, linked by URI from the GLBs). GLBs 4.6, 7.1 and 6.1 KB. The verdicts are the same for the three unless a row
names one.

| Gate | Verdict | Observation |
| --- | --- | --- |
| 1 Shape | pass | `docs/art/renders/production/creature_grass_tuft_gates.jpg`, `creature_fern_clump_gates.jpg`, `creature_flower_clump_gates.jpg` (grey front, side, three-quarter and top; clay keeps the cards' alpha cut): the tuft reads as a fan of blades from every side and as a three-armed splay from above; the fern as a rosette of eight arching feather fronds, two upright in the middle; the flowers as stems with bells and round heads over a leafy foot. No card shows as a quad edge-on to the review cameras. First sheets (not kept) showed every card's back side black (one sheet flipped for the back face) and then ghosted cards (Cycles skipped coincident sheets); both fixed (two sheets 1.2 mm apart, culled backs, and the review honouring the cull). |
| 2 Materials | pass | Close-up and unlit panels: blades with a lighter mid-rib, darker base and rounded edges; fern pinnae combed into lobes with gaps between them (the first atlas's pinnae merged into one leaf, fixed); lilac bells, sky-blue and cream star heads with a dark violet eye, cream umbels. No black or foreign fringe at the cut edges (the push-pull fill). Hue: 0.04% of the atlas's chromatic texels sit within 25 degrees of the food green or the threat pink (the test prints it; the builder fails any cell over 1%). |
| 3 Neutral lighting | pass | The atlas carries no light: the base darkening is occlusion; lit and shaded sides come from the scene. Both sides of every card light like the ground in Godot (normals leaned up), so a clump does not show a bright and a black half (`kit_close` frames). |
| 4 Export and Godot | pass | `docs/evidence/credit-creature-world-art/kit_close.jpg` and `kit_row.jpg` (Forward+ on lavapipe and Compatibility on llvmpipe, the stage's own light): at 1.6 m the tuft, fern and flowers read as grass, fern and wildflowers with crisp cut-outs (alpha scissor, no sorting), at the gameplay camera's 6 to 10 m as small tufts and coloured sprinkles that belong to the turf. Import: the external material is mapped, LODs off and shadows off for the card meshes (the test checks the mapping, the shadow, the two sheets and the up-leaning normals). The first Godot pass found `transparency = 1` (alpha blending) in the material; it is 2 (scissor) now and the test checks it. |

Three largest remaining differences from the target: (1) at the gameplay camera the cover is small (0.35 to 0.42 m on
a field the camera sees from 6 to 10 m), so the lush read depends on the scatter's density and on clumping pieces
together (step 10); (2) the cards cast no shadow, so a clump has no contact shade on the turf beyond the atlas's dark
base; (3) Godot builds the atlas's mips by plain averaging, so far off the alpha of thin blades falls under the 0.5
scissor and far cover thins out toward the turf rather than holding its silhouette. The frames reach about 15 m, where the tufts still read; past that
is unchecked until the scatter's frames (its planned 55 m visibility range ends the cover anyway).

### creature_pebble_cluster

157 triangles (budget 160); one material, `M_Pebble` (baked greyscale detail times #8C8070); Albedo, ORM and Normal
at 512 px. GLB 566 KB.

| Gate | Verdict | Observation |
| --- | --- | --- |
| 1 Shape | pass at gameplay distance | `docs/art/renders/production/creature_pebble_cluster_gates.jpg`: seven rounded, flattened stones of 3 to 12 cm, half sunk, in a loose patch; smooth shading, no slivers. Up close (the 135 mm panel) the outlines are polygonal (seven to nine sides): 157 triangles for seven pebbles. From the game camera they are 1 to 3 cm on screen and read round (`kit_close`, `kit_row`). |
| 2 Materials | pass | Beauty and unlit: a warm grey-tan stone (mean L 43, C 8.8, h 80), each pebble a little lighter or darker, fine speckle in the normal map; reads as smooth river stone, matching the pebbles painted into the earth tile. |
| 3 Neutral lighting | pass | The albedo is flat greyscale detail times one tint, with only the baked occlusion in it. |
| 4 Export and Godot | pass | `kit_close.jpg`, `kit_row.jpg`: on the earth patch and the turf at 1.6 m and at the gameplay distance the pebbles sit in the ground (cut off under it) and read as stones; no hovering. |

Remaining: the polygonal outline in a macro close-up (a 240-triangle budget would round it); the pebbles are only
the earth tile's stones made solid, so they add little at the gameplay camera unless the scatter lays them in
drifts along the earth patches' edges.

### creature_boulder_a, creature_boulder_b, creature_boulder_c

689, 885 and 1 182 triangles (budgets 700, 900, 1 200); one material each (`M_CreatureBoulderA`, `_B`, `_C`, baked
from the procedural shader over the CC0 Rock Boulder Dry scan, logged in each record); Albedo, ORM and Normal at 512,
1024 and 1024 px. GLBs 542 KB, 2.1 MB and 1.9 MB. Surface error after decimation 3.0 to 5.2 mm (the records'
`reduction`).

| Gate | Verdict | Observation |
| --- | --- | --- |
| 1 Shape | pass | `docs/art/renders/production/creature_boulder_a_gates.jpg`, `_b_`, `_c_` (grey front, side, three-quarter and top with the grazing key): broad, rounded boulders with a near-level top facet and soft side facets that catch the grazing light as planes with rounded edges, not eggs. The first build (not kept) was a smooth ovoid: the planes cut too little (0.8 to 0.92 of the radius, a 0.12 blend); now 0.74 to 0.88 with a 0.07 blend and a top plane. Each is fitted to its size (1.00, 1.80, 3.00 m across) and sinks 12% of its height. |
| 2 Materials | pass | Beauty, close-up and unlit: cool blue-grey stone carrying the scan's grain and veining at one tile per 1.6 m (no stretch on the steep sides: box projection), a moss cap over the top with a ragged, fine-grained edge, flecked light and dark, and a soft fuzz in the normal map. The first moss (blobs from a coarse noise, with a dark damp ring) read as paint splotches with an outline in the Compatibility frame; reworked to a cap whose edge is broken at a fine scale, with a damp grey at the stone's own lightness. |
| 3 Neutral lighting | pass | The bake is the shader's base colour without light (plus the shared 30% occlusion darkening); no highlight or directional shade is baked in. Hue: 0.00% of chromatic texels near a reserved hue, means h 164 to 168 at C 5 to 6 (the test prints both); the first warm stone's means were h 112 to 116, on the food green, so the stone went cool. |
| 4 Export and Godot | pass | `kit_boulders.jpg` (on the turf at 6 to 11 m, for review only) and `kit_berm.jpg` (on the berm past the east wall from 20 m inside), both renderers: they stand on the slope without hovering, the moss caps read from both, the facets catch the sun. Their place is outside the walls only (the record's `placement`; the test keeps anything over 0.45 m out of the walkable field). |

Remaining: (1) the moss cap is the same on all three and uniform over the top; a few flecks lower down and a
thinner cap on one of them would make a group read less stamped; (2) the stone is a different rock from the warm
pebbles and nest stones (deliberate, for the hue rule; the owner may prefer warm stone with less moss); (3) alone on
the berm at 20 m they read small: they need grouping with trees and each other (step 10).
