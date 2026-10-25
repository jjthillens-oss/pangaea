# Creature stage world dressing (PROPOSED)

Status: PROPOSED art, 2026-10-23, built for the Creature stage thread's first playable slice
(`docs/milestones/creature-stage-plan.md` section 5) to replace the placeholders its world scene builds in code.
The owner judges the look at merge; nothing here changes the stage's rules.

| Asset | Replaces | Triangles (budget) | Materials | Notes |
| --- | --- | --- | --- | --- |
| `creature_field_ground` | the field plane | 15 488 (16 000) | `M_CreatureField` (external, `assets/export/M_CreatureField.tres`) | rev 2: the 172 x 172 m walkable grid (`CreatureField`, 12 800 triangles), relief under 0.12 m inside the walls at ±80 m, a 2.5 m berm past them, the centre flat for 7.5 m round the nest; plus `CreatureFieldHills` (2 688 triangles), a coarse square ring of hills from 84 m (under the berm) out to 200 m: low rolling hills 1.5 to 4 m over the berm's crest, then from about 120 m an uneven far ridge 2 to 14 m higher (top 16.2 m); it casts no shadow (an import option) |
| `creature_nest_ring` | the nest torus | 3 000 (4 000) | `M_NestEarth`, `M_NestTwig`, `M_NestStone` (baked) | mound of earth and straw round the sim's 6 m nest: inner 5.35 m, crown 5.85 m, outer 6.45 m, 0.44 m high (0.52 m with its heaps); the inside is clear and flat to 5.3 m |
| `creature_fruit_bush` | the fruit sphere | 1 100 (1 200) | `M_BushLeaf`, `M_BushCards`, `M_BushFruit` (external, instance tint) | two root meshes: `Bush` (an 80-triangle core and 480 triangles of leaf cards, two surfaces of one mesh) and `Fruit` (nine fruit, 540); ripe draws both, bare draws `Bush` only; 1.06 x 1.06 x 0.79 m, every vertex within 0.56 m of the pivot horizontally (the top card tips are 0.81 m from it) |
| `creature_meat_chunk` | the meat box | 604 (1 200) | `M_MeatFlesh` (external, instance tint), `M_MeatBone` (baked) | a torn haunch with a bone end, 0.58 m long, lying on the ground |
| `creature_editor_room` | the editor's floor cylinder (`creature_editor_floor`) | 1 152 (1 200) | `M_EditorPad`, `M_EditorRim`, `M_EditorGroove` (baked; the grooves emit a faint flat #5FB3FF at 0.15) | a unit-radius pedestal pad, 3.5 cm thick under the face: dark blue face (#14305C, roughness about 0.5, concentric brushing), a steel-blue rim (#5A7FA8) 12 mm high with a quarter-round edge, V grooves at r 0.33 and 0.60 and at the rim's foot (0.86), revolved at 48 segments. The pivot is the centre of the top face, so the editor's y = -0.01 placement and (s, 1, s) scaling keep working; the rings are geometry and scale with the pad |

Every asset keeps the stage's contract: 1 m = 1 unit, the pivot on the ground (Godot y = 0; the editor pad's is the
centre of its top face), Blender +Y forward (Godot -Z), no node names read by game code. Sources are in
`assets/source/blender/`, exports in `assets/export/`, records in `assets/records/`, all written by
`tools/blender/make_creature_world.py`.

## The field material

`assets/export/shaders/creature_field.gdshader`, carried by `M_CreatureField.tres` and mapped onto the imported
`M_CreatureField` in `creature_field_ground.glb.import`. It samples two seamless 2.5 m tiles in world space (so the
mesh can be scaled or re-gridded freely), each at two scales (`detail_scale` 0.37, offset) and averaged, so no
repeat shows at 1 to 2 m or across the field: meadow turf (`T_CreatureField_Turf_*`, 1024 px) and bare earth
(`T_CreatureField_Earth_*`, 512 px, sparse pebbles half sunk in dust), blended by a 37 m patch mask
(`T_CreatureField_Patch`, earth where the mask passes `patch_low` to `patch_high`, so about a fifth of the field) and
a bare clearing round the nest (`clearing_r`, 7.5 m). The hills use the same material.

Rev 2 (field rev 2a, PROPOSED):
- The turf tile is a carpet of grass blades: strokes 1.2 to 4 cm long and about 5 mm wide, laid with a z-order so each
  pixel shows its top blade, crowding into irregular clumps with dark thatch in the gaps. Rev 1's lighter, round
  Voronoi tuft crowns read as puddles or caustics from the game camera, so the tile has no round shapes any more.
- Three world-space variations, all reads of the patch mask: `dry_color` (#778F77, CIELAB L 57, C 17, h 143) mixed in
  up to `dry_amount` 0.4 in broad swathes; `lush_tint` (a linear multiplier, 0.78 / 0.92 / 0.92) that deepens other
  swathes toward h 150; and a 6 m `clump_m` light and dark (`clump_strength` 0.14) at the scale the gameplay camera
  sees. `dry_color` and `lush_tint` are written into `assets/export/M_CreatureField.tres`, so the contract test reads them.
- `ambient_occlusion` 0.7 with `AO_LIGHT_AFFECT` 0: the sky's blue ambient falls on the ground at 70%, the sun at 100%.

Colour: the blades are authored in CIE LCh at hue 141 to 154, chroma 27 to 36; the tile's mean is L 46, C 28, h 147
(rev 1: hue 145 to 146 at chroma 18 to 20). The dry and lush variations keep the turf at hue 143 to 150 at every
mix, so the field keeps the 25 degrees of LAB hue from the food green (114) every asset keeps
(`docs/art/production_m1.md`); a straw or yellow dry tint would cross that band on its way, which is why the dry
meadow is a grey sage. `tests/test_creature_world_art.gd` checks these means. The owner may relax the gap for
creature-stage ground (open question 2), since its food is amber fruit and red meat rather than green; true grass
greens (h 120 to 138) would then be available.

Uniforms worth touching: `tile_m`, `detail_scale`, `patch_m`, `patch_low`/`patch_high` (how much of the field is
earth), `clearing_r`/`clearing_soft`, `turf_tint`/`earth_tint`, `dry_color`/`dry_amount`, `lush_tint`/`lush_amount`,
`clump_m`/`clump_strength`, `macro_strength`, `ambient_occlusion`, `edge_break` (how ragged the blend edge is), the
roughness and specular pairs (the turf has no sheen).

## Instance tints

The fruit and meat draw as `MultiMesh` instances with a colour each. `M_BushLeaf.tres`, `M_BushCards.tres`,
`M_BushFruit.tres` and `M_MeatFlesh.tres` are `StandardMaterial3D` files with the baked (or, for the cards,
authored) greyscale detail textures, the asset's flat colour, and `vertex_color_use_as_albedo` with
`vertex_color_is_srgb`, so an instance colour multiplies the baked look the way `albedo_color` would: white draws
the asset as baked, a pale desaturated tint such as (0.62, 0.74, 0.58) reads as a bare bush. One instance colour
tints the bush's core, its leaf cards and its fruit alike: the cards carry the leaf colour `#3C8A6C`, the core the
same hue darkened to `#245442` (LAB L 32 against 52), so a gap between cards reads as shade inside the shrub. The
bone (`M_MeatBone`), the nest and the editor pad keep their baked materials.

## The bush's leaf cards

`Bush` is one mesh with two surfaces, so the stage still draws it as one `MultiMesh`:

- Surface 0 is the lumpy core (`M_BushLeaf`, baked, decimated at a 6 cm tolerance to 80 triangles because the
  cards hide most of it; the reduction may not lift its flat base more than 3 cm off the ground). It is dull
  (baked roughness 0.95, `metallic_specular` 0.2 in its `.tres`), so a sunlit gap never shines pale through the
  leaves.
- Surface 1 is 120 crossed pairs of quads (`M_BushCards`, 480 triangles, not baked or decimated) over all but the
  underside of the core. Each pair is 16 to 22 cm, its base sunk 3.5 cm under the core, its axis the local normal
  leaned up (outward and upward on the sides, upright on the crown). The first quad is rolled to face out across
  the surface (give or take 0.6 rad), so it covers the core seen from outside; the second stands radially and
  breaks the silhouette. The lowest card vertex is 5.7 cm above the ground; the builder fails under 5 cm.

The cards sample `T_BushLeafCards` (`assets/export/creature_fruit_bush/`), a 512 px RGBA atlas authored in numpy:
four leaf clusters in a 2 x 2 grid (three, four, five and six overlapping leaves fanning up from the card's base),
each leaf with a mid-vein, faint side veins, shading toward its edges and a shadow band where it lies over
another. RGB is greyscale detail with a mild warm (lit) to cool (shaded) bias, A the anti-aliased cut-out, zero within 4 px of each cell's edge and faded in over the next 6 px, so a variant
never pulls in its neighbour at the near mips. Times the leaf colour the
cards stay between LAB hue 146 and 169: at least 39 degrees from the food green (114) as authored and 31 under
the bare tint, and far from the threat pink (11). Each pair samples one variant, each quad mirrored at random.

In Blender the cards are their own object with the atlas material (`blend_method` CLIP, a Round node on the
alpha, which the glTF exporter writes as `alphaMode` MASK), joined into `Bush` after the core's bake, so the
core's baked UVs and the cards' atlas UVs both survive. In the engine `M_BushCards.tres` draws the copy Godot
extracts from the GLB (`creature_fruit_bush_T_BushLeafCards.png`, which the scene importer gives mipmaps and fixed
alpha borders) with alpha scissor at 0.5, no culling and roughness 0.8. The `Fruit` mesh stays its own root, so
ripeness still toggles it. The review sheet's clay row shows the cards as plain quads, since clay ignores the
alpha; judge the leaves on the beauty row and in the engine.

## Regenerating

```bash
python tools/blender/make_creature_world.py [--only id[,id...]]   # bpy 5.2.2 venv
godot --headless --path . --import                                # writes the .import files and extracts the textures
python tools/blender/make_creature_world.py --import              # the .tres files, the .glb.import mappings, normal-map flags
godot --headless --path . --import                                # picks the mappings up
python tools/blender/render_production.py creature_nest_ring creature_fruit_bush creature_meat_chunk creature_editor_room   # review sheets
python tools/blender/render_world_review.py creature_fruit_bush [...]   # gate views: grey (grazing key), beauty, close-up, unlit base colour, card alpha
```

In-engine screenshots: `tools/godot/creature_world_gameplay_shots.gd` runs the real `game/scenes/creature/creature_world.tscn`
(and `game/scenes/creature/creature_editor.tscn` with `--editor`) and saves gameplay frames, close-ups and the editor's zoom extremes, with
draw calls, primitives and `setup_ms`. `tools/godot/world_dressing_shot.gd` stages the dressing alone, and
`tools/godot/editor_room_shot.gd` the editor pad from the editor camera's poses; both take their light out of the
real scenes (recipes in their headers). The Compatibility renderer overexposes a shadowed sun (docs/TOOLCHAIN.md), so
judge colour on Forward+ (lavapipe) or with `--no-shadow`.

## Baseline frames (2026-10-25, before the creature-world-art revision)

Frames of main at 2ffc1218 from `tools/godot/creature_world_gameplay_shots.gd` (seed 4242, the `s1_quadruped` starter, HUD
hidden), in `docs/evidence/credit-creature-world-art/before_*.jpg`. Ground band = the mean CIELAB (D65) between the
horizon and 60% of the frame's height, leaving out the middle fifth of the columns where the creature stands.

| Frame | Renderer | Band L / C / h | Ground just under the horizon L / C / h | Horizon dE |
| --- | --- | --- | --- | --- |
| close_ground | Forward+ (lavapipe) | 46.8 / 18.5 / 146 | 51.8 / 11.8 / 129 | 30.7 |
| world_roam | Compatibility, shadowed sun | 59.0 / 20.8 / 170 | 82.5 / 11.1 / 176 | 19.1 |
| world_roam | Compatibility, `--no-shadow` | 48.0 / 16.9 / 146 | 55.7 / 8.0 / 148 | 24.5 |
| close_ground | Compatibility, shadowed sun | 59.0 / 23.1 / 169 | 77.6 / 13.3 / 174 | 21.0 |

- The water read is strongest in Compatibility with the shadowed sun: its additive sRGB pass lifts the turf to a pale
  teal (h170) and the fogged far field to a pale cyan (L83), which reads as shallow sea with sandbars. Forward+, the
  shipping renderer, draws the same turf as a low-chroma grey-green (h146, C18), but the far third still fades into
  the blue-grey depth fog from 20 to 78 m and meets the sky with no land on the horizon, the turf's round blotches
  read as puddles, and nothing stands up from the ground.
- The fruit bushes do not draw in the game: `game/scenes/creature/creature_world.gd` `_multimesh()` starts every MultiMesh at
  `visible_instance_count = 0`, and `_draw_food()` raises it for the fruit and the meat but never for the bushes, so
  the fruit floats in the air with only its own shadows (`docs/evidence/credit-creature-world-art/before_close_bush_fplus.jpg`). The art tools draw the bush
  through their own MultiMesh, so earlier review frames showed it. The fix is one line in that script, which
  this art job does not own (issue #195).
- The nest mound reads as smooth tan: the straw streaks are too fine to show at gameplay distance.
- The editor pad floats in the room's sky with no walls; seen from PITCH_MAX at ZOOM_MAX it sits in a black void.
- Cost (Compatibility on llvmpipe, 1920x1080, a 4-CPU container shared with other jobs): spawn frame 239 draw calls,
  107k primitives, about 640 ms a frame (470 ms without the sun's shadow); `setup_ms.total` 1,968 ms (test budget
  3,000 ms). Forward+ on lavapipe: setup 4,112 ms, about 30 s a frame. These are software-renderer numbers for
  before/after comparison only, not a performance claim for real GPUs.

## Field rev 2a frames (art only, 2026-10-25)

The new turf, shader variations, AO and hills, with `game/scenes/creature/creature_world.tscn` untouched, in
`docs/evidence/credit-creature-world-art/art_*.jpg`. Same poses and measure as the baseline.

| Frame | Renderer | Band L / C / h | Ground just under the horizon L / C / h | Horizon dE |
| --- | --- | --- | --- | --- |
| close_ground | Forward+ (lavapipe) | 48.4 / 24.8 / 147 (was 46.8 / 18.5 / 146) | 52.9 / 14.7 / 140 (was 51.8 / 11.8 / 129) | 32.5 |
| world_roam | Compatibility, shadowed sun | 58.2 / 24.8 / 165 (was 59.0 / 20.8 / 170) | 81.7 / 13.1 / 176 | 19.5 |

- Forward+ (the shipping renderer): the turf reads as a grass meadow up close and at the gameplay camera, with blades,
  clumps and drier and lusher swathes; no puddle-like blotches.
- Compatibility with the shadowed sun is still teal (h 165): its additive sRGB sun pass lifts the blue ambient and
  fog, and the art cannot hold that back alone. (This Compatibility frame was taken with a first, paler dry tint,
  #8FA08C at 0.42; the shipped #778F77 at 0.4 is darker and greyer.)
- The hills stand beyond the 78 m fog end, so in both renderers they are fully fogged into the sky's horizon colour
  and the horizon still has no land line. The environment retune below is the fix the art cannot make.
- After these frames, two more art changes went in (commit "uneven hills and organic earth patches"): the hills became
  low near hills plus an uneven far ridge (they had read as a wall once the fog let them show), and the shader now
  reads the patch mask rotated and domain-warped (rev 1's earth patches had boxy, axis-aligned edges) and fades the
  earth patches out past 74 m, so the berm and hills are grass.
- Cost: unchanged within noise (Compatibility spawn 240 draw calls, 109.7k primitives; `setup_ms.total` 2,206 ms on
  the shared container, test budget 3,000 ms).

## The world's light (PROPOSED retune of `game/scenes/creature/creature_world.tscn`, 2026-10-25)

The lead allowed this job to change only the values of the scene's sky, environment and fog sub-resources and the
sun's energy, in one isolated commit ("land-coloured light and haze (values only)"), after the art-only fixes above.
No nodes, scripts or other properties changed; dropping that commit restores main's light.

| Value | Main | Now | Why |
| --- | --- | --- | --- |
| `Sky_material.ground_bottom_color` | (0.42, 0.54, 0.66) | (0.30, 0.32, 0.25) | the sky's lower half lights the ground's shade from below; earth, not blue |
| `Sky_material.ground_horizon_color` | (0.52, 0.64, 0.78) | (0.62, 0.68, 0.66) | a grey-green land haze under the horizon instead of the sky's blue |
| `ambient_light_color` / `ambient_light_sky_contribution` | (unset) / 1.0 | (0.60, 0.64, 0.52) / 0.6 | 40% of the ambient is a warm neutral, so the shade stops turning cyan |
| `ambient_light_energy` | 0.3 | 0.4 | the shade keeps some colour with less sky in it |
| `fog_light_color` | (0.52, 0.64, 0.78), the sky's horizon | (0.66, 0.72, 0.76) | a paler grey haze that differs from the sky, so the hills keep a skyline |
| `fog_density` | 1.0 | 0.85 | the farthest hills keep some of their green |
| `fog_aerial_perspective` | 0.5 | 0.25 | less sky colour mixed into the haze |
| `fog_depth_begin` / `fog_depth_end` | 20 / 78 m | 35 / 200 m | the whole field (to ±80 m) and the hills show; the haze starts past the gameplay camera's ground |
| Sun `light_energy` | 0.75 | 1.0 | a sunlit day: the lit side of the turf is green and the earth warm |

Before/after pairs (the same art, main's light on the left), in `docs/evidence/credit-creature-world-art/env_*.jpg`.
"Turf" is the mean CIELAB of only the turf pixels (hue 115 to 215, chroma over 6) in the ground band (between the
first sharp edge under the sky, now the hills' skyline, and 60% of the frame height, the middle fifth of the columns
left out); the share of earth in the band varies with the pose, so the turf-only reading is the fair comparison.
Horizon dE is between the sky just above that edge and the land just under it.

| Frame | Renderer | Turf L / C / h before | after | Horizon dE before | after |
| --- | --- | --- | --- | --- | --- |
| world_roam | Compatibility, shadowed sun | 56.9 / 26.2 / 164.5 | 67.2 / 31.8 / 151.8 | 12.3 (a fogged blue band) | 34.9 |
| close_ground | Compatibility, shadowed sun | 57.4 / 25.0 / 166.6 | 69.0 / 29.7 / 152.7 | | |
| world_low | Compatibility, shadowed sun | 61.3 / 26.3 / 166.1 | 73.9 / 30.5 / 153.7 | 12.9 | 37.8 |
| close_ground | Forward+ (lavapipe) | 49.7 / 24.2 / 147.8 | 57.5 / 25.8 / 143.7 | | |
| world_spawn | Forward+ (lavapipe) | 51.4 / 25.9 / 148.9 | 59.6 / 24.9 / 146.0 | | |
| world_low | Forward+ (lavapipe) | 51.9 / 24.4 / 151.6 | 61.2 / 21.2 / 149.5 | 29.3 (field edge into fog) | 17.1 (hills' skyline) |

Against the brief's PROPOSED targets (turf hue 160 or under, chroma 15 or more, a land horizon with dE 8 or more):
met in both renderers. Against main (the baseline table above, rev 1 art and main's light) the Compatibility roam turf
went from h 171.8 to 151.8 and Forward+'s close-up turf from C 19.2 to 25.8.

What the frames show:
- Forward+, the shipping renderer: a sunlit grass meadow with bare earth patches, low hills behind the walls and a
  far ridge fading into a grey-blue haze; the skyline is land. The turf reads at hue 144 to 150 on screen, still on the
  far side of the food green's band (89 to 139).
- Compatibility (these Linux frames): the same land read, but the shadowed sun's additive sRGB pass lifts the turf
  (L 67 to 74 against 57 to 61 in Forward+) and the sunlit hill faces to a pale mint. That is the renderer, not the
  values (docs/TOOLCHAIN.md); judge colour on Forward+.
- No water read remains in either renderer: no pale cyan plane at the horizon, no sky-coloured far field.
- Cost: the light change leaves every frame's counts exactly as they were (fog culls nothing, so the hills were
  drawn before too): world_spawn 240 draw calls and 109.7k primitives in both renderers, world_low 254 / 94.0k in
  Forward+ and 126 / 78.5k in Compatibility. Against main's 239 / 107k at world_spawn, the hills mesh is the one extra
  draw call and 2.7k primitives. `setup_ms.total` in these runs was 2,105 to 3,221 ms on the shared container (the
  higher ones are the Forward+ runs, whose skin build is slower; the creature skins and rigs are most of it).

The owner may also relax the 25-degree food-green gap for creature-stage ground (open question 2): true grass greens
(h 120 to 138) would read as land even more readily, and the creature stage's food is amber fruit and red meat.

## Next

Straw tufts and a worn path for the nest, two or three bush and meat variants (a second leaf atlas or card
layout would do for the bush), and walls or a backdrop for the editor room beyond its pad.
