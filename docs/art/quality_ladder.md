# Quality ladder demo: one cell from blockout to target

**Status: PROPOSED look-development, awaiting Joshua's review.** These four assets are not
gameplay assets. The sample cell and the M1 blockouts stay in the game until the look is
approved (Bible section 15).

Every rung is a real asset with a Blender source, a GLB and a record, built headless by
`tools/blender/cell_ladder.py` and rendered by `tools/blender/render_ladder.py`. Godot checks
live in `tests/test_art_ladder.gd`.

| Rung | Art role | What changed | Triangles | Review images (`docs/art/renders/`) |
| --- | --- | --- | --- | --- |
| `cell_ladder_0_blockout` | Modeler | Primitives in clay: body, eyes, mouth, tail. Proportions and silhouette only. | 254 | `cell_ladder_0_blockout_sheet.jpg`, `_silhouette.png` |
| `cell_ladder_1_form` | Modeler | One sculpted quad-sphere body: low pebble weight, eye sockets, brow petals, cheeks, mouth recess, dorsal ridge, slight lean. Lidded eyes, lips, tapered flagellum with a collar bead, three organelle beads on the back. | 10,228 | `cell_ladder_1_form_sheet.jpg`, `_silhouette.png` |
| `cell_ladder_2_surfaced` | Surfacing | Body and tail joined and unwrapped; procedural membrane (belly-to-back gradient, mottling, back spots, darker mouth, pale tail tip) baked to a 512 px albedo and ORM; glTF-safe part materials from the palette. | 10,228 | `cell_ladder_2_surfaced_sheet.jpg` (clay and beauty rows) |
| `cell_ladder_3_target` | Rigging and animation, technical artist | `cell_single_body` rig (root, body, mouth, five tail bones, eyes, four lids); clips `idle` (2 s loop, breathing, glance, blink), `swim` (1 s loop, travelling tail wave, body counter-yaw, focused lids), `eat` (0.83 s, mouth opens and chomps, lunge, happy squint). Loop modes set in the Godot import file. | 10,228 | `cell_ladder_3_target_sheet.jpg`, `_godot_game.jpg`, `_godot_close.jpg`, `_swim.gif` |

## What the technical artist checks (all passing)

- Every rung loads in Godot 4.7.2 and keeps the sample cell's five sockets, with the mouth at
  Godot forward (-Z) and the top socket up.
- Triangles stay under the Bible's 15,000 ordinary-creature proposal, and the count Godot sees
  matches the record. Textures stay at 512 px (microscopic budget).
- The surfaced rungs arrive with a textured `M_CellMembrane` (albedo and roughness maps).
- The target has a `Skeleton3D` with the named bones and one `AnimationPlayer` with `idle`,
  `swim` (looping) and `eat` (one-shot) at the recorded lengths.
- Gameplay readability: at the M1 camera (55 degree pitch, 45 degree FOV, 14 m) the cell is
  about 100 px tall at 1080p, and the coral body reads clearly against the teal pool
  (`cell_ladder_3_target_godot_game.jpg`, rendered in Godot's Compatibility renderer).

## Known gaps before this could become production art

- In-engine frames come from the Compatibility renderer under a virtual display. The game uses
  Forward+; a Forward+ frame on Joshua's RTX 5070 is still needed.
- No normal map yet: surface detail is all in the silhouette and albedo. A baked detail normal
  map (and CC0 detail textures once the network allows Poly Haven and ambientCG) is the next
  surfacing step.
- Godot generates LODs on import; their silhouette has not been reviewed yet.
- Deformation at extreme supported proportions (Bible section 16 step 5) needs the procedural
  creature body, which does not exist yet.

## Rebuild

```bash
python3.13 -m venv /root/tools/bpyenv && /root/tools/bpyenv/bin/pip install bpy==5.2.2
/root/tools/bpyenv/bin/python tools/blender/cell_ladder.py          # all rungs (or: 0 1 2 3)
/root/tools/bpyenv/bin/python tools/blender/render_ladder.py        # turntables, silhouettes, sheets
/root/tools/bpyenv/bin/python tools/blender/render_material_sheet.py
xvfb-run -a .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-method gl_compatibility \
  --script res://tools/godot/capture_asset.gd -- res://assets/export/cell_ladder_3_target.glb docs/art/renders/cell_ladder_3_target_godot swim
```
