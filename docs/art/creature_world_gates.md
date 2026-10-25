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
