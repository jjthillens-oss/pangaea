# Creature stage world dressing (PROPOSED)

Status: PROPOSED art, 2026-10-23, built for the Creature stage thread's first playable slice
(`docs/milestones/creature-stage-plan.md` section 5) to replace the placeholders its world scene builds in code.
The owner judges the look at merge; nothing here changes the stage's rules.

| Asset | Replaces | Triangles (budget) | Materials | Notes |
| --- | --- | --- | --- | --- |
| `creature_field_ground` | the field plane | 12 800 (16 000) | `M_CreatureField` (external, `assets/export/M_CreatureField.tres`) | 172 x 172 m grid, relief under 0.12 m inside the walls at ±80 m, a 2.5 m berm past them; the centre is flat for 7.5 m round the nest |
| `creature_nest_ring` | the nest torus | 3 055 (4 000) | `M_NestEarth`, `M_NestTwig`, `M_NestStone` (baked) | mound of earth and straw, inner 5.2 m, crown 5.8 m, outer 6.55 m, up to 0.5 m high; the inside is clear and flat |
| `creature_fruit_bush` | the fruit sphere | 914 (1 200) | `M_BushLeaf`, `M_BushFruit` (external, instance tint) | two root meshes: `Bush` and `Fruit` (nine fruit); ripe draws both, bare draws `Bush` only |
| `creature_meat_chunk` | the meat box | 604 (1 200) | `M_MeatFlesh` (external, instance tint), `M_MeatBone` (baked) | a torn haunch with a bone end, 0.58 m long, lying on the ground |
| `creature_editor_room` | the editor's floor cylinder (`creature_editor_floor`) | 1 152 (1 200) | `M_EditorPad`, `M_EditorRim`, `M_EditorGroove` (baked; the grooves emit a faint flat #5FB3FF at 0.15) | a unit-radius pedestal pad, 3.5 cm thick under the face: dark blue face (#14305C, roughness about 0.5, concentric brushing), a steel-blue rim (#5A7FA8) 12 mm high with a quarter-round edge, V grooves at r 0.33 and 0.60 and at the rim's foot (0.86), revolved at 48 segments. The pivot is the centre of the top face, so the editor's y = -0.01 placement and (s, 1, s) scaling keep working; the rings are geometry and scale with the pad |

Every asset keeps the stage's contract: 1 m = 1 unit, the pivot on the ground (Godot y = 0; the editor pad's is the
centre of its top face), Blender +Y forward (Godot -Z), no node names read by game code. Sources are in
`assets/source/blender/`, exports in `assets/export/`, records in `assets/records/`, all written by
`tools/blender/make_creature_world.py`.

## The field material

`assets/export/shaders/creature_field.gdshader`, carried by `M_CreatureField.tres` and mapped onto the imported
`M_CreatureField` in `creature_field_ground.glb.import`. It samples two seamless 2 m tiles in world space (so the
mesh can be scaled or re-gridded freely): blue-green turf (`T_CreatureField_Turf_*`) and bare earth
(`T_CreatureField_Earth_*`), blended by a 37 m patch mask (`T_CreatureField_Patch`) and a bare clearing round the
nest (`clearing_r`, 7.5 m). The tiles are numpy sums of periodic sines and wrapped Voronoi
(`make_membranes.py`'s helpers), 512 px, in `assets/export/creature_field/`. The turf keeps 25 degrees of LAB hue
from the food green (114) and the threat pink (11), so it is blue-green, not grass green.

Uniforms worth touching: `tile_m`, `patch_m`, `patch_low`/`patch_high` (how much of the field is earth),
`clearing_r`/`clearing_soft`, `turf_tint`/`earth_tint`, `edge_break` (how ragged the blend edge is).

## Instance tints

The fruit and meat draw as `MultiMesh` instances with a colour each. `M_BushLeaf.tres`, `M_BushFruit.tres` and
`M_MeatFlesh.tres` are `StandardMaterial3D` files with the baked detail textures, the asset's flat colour, and
`vertex_color_use_as_albedo` with `vertex_color_is_srgb`, so an instance colour multiplies the baked look the way
`albedo_color` would: white draws the asset as baked, a pale desaturated tint such as (0.62, 0.74, 0.58) reads as
a bare bush. The bone (`M_MeatBone`), the nest and the editor pad keep their baked materials.

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

Leaf cards or a shape-keyed canopy for the bush (the single clump reads as a rock up close), straw tufts and a
worn path for the nest, two or three bush and meat variants, and walls or a backdrop for the editor room beyond its pad.
