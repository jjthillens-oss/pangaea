# Creature stage world dressing (PROPOSED)

Status: PROPOSED art, 2026-10-23, built for the Creature stage thread's first playable slice
(`docs/milestones/creature-stage-plan.md` section 5) to replace the placeholders its world scene builds in code.
The owner judges the look at merge; nothing here changes the stage's rules.

| Asset | Replaces | Triangles (budget) | Materials | Notes |
| --- | --- | --- | --- | --- |
| `creature_field_ground` | the field plane | 12 800 (16 000) | `M_CreatureField` (external, `assets/export/M_CreatureField.tres`) | 172 x 172 m grid, relief under 0.12 m inside the walls at ±80 m, a 2.5 m berm past them; the centre is flat for 7.5 m round the nest |
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
repeat shows at 1 to 2 m or across the field: sage turf (`T_CreatureField_Turf_*`, tuft crowns over mottled ground
with blade streaks) and bare earth (`T_CreatureField_Earth_*`, sparse pebbles half sunk in dust), blended by a
37 m patch mask (`T_CreatureField_Patch`, earth where the mask passes `patch_low` to `patch_high`, so about a
fifth of the field) and a bare clearing round the nest (`clearing_r`, 7.5 m). A second, offset read of the patch
mask dries the turf (`turf_dry_tint`, a lighter yellower multiplier, `dry_amount`) in broad swathes, so the
meadow varies at the scale a camera 10 to 60 m up sees. The tiles are numpy sums of periodic sines and wrapped
Voronoi (`make_membranes.py`'s helpers), 512 px, in `assets/export/creature_field/`.

Colour: the turf is authored at LAB hue 145 to 146, chroma 18 to 20, L 36 to 54 (`#425B44` to `#6A896D`), and the
dry multiplier keeps it at 139 or more, the 25 degrees of LAB hue from the food green (114) every asset keeps
(`docs/art/production_m1.md`). The stage's blue sky ambient and sky-coloured fog push whatever is authored about
25 to 30 degrees toward cyan on screen (the first, minty palette rendered at hue 170; this one at 172 to 179 but
with the chroma halved, 11 to 13, and L 60), so the field reads as muted land rather than sea; a grass green on
screen would need either a warmer ambient and fog in `creature_world.tscn` (the Creature stage thread's) or
relaxing the food-hue gap for creature-stage ground, which is the owner's call.

Uniforms worth touching: `tile_m`, `detail_scale`, `patch_m`, `patch_low`/`patch_high` (how much of the field is
earth), `clearing_r`/`clearing_soft`, `turf_tint`/`earth_tint`, `turf_dry_tint`/`dry_amount`, `macro_strength`,
`edge_break` (how ragged the blend edge is), the roughness and specular pairs (the turf has no sheen).

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
```

In-engine screenshots: `tools/godot/world_dressing_shot.gd` under Xvfb (recipe in its header), and
`tools/godot/editor_room_shot.gd` for the editor pad in the editor scene's own sky and lights, from the editor camera's
pose. The Compatibility renderer overexposes a shadowed sun (docs/TOOLCHAIN.md), so judge colour on Forward+
(lavapipe) or with `--no-shadow`.

## Next

Straw tufts and a worn path for the nest, two or three bush and meat variants (a second leaf atlas or card
layout would do for the bush), and walls or a backdrop for the editor room beyond its pad.
