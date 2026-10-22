# M1 production art

**Status: PROPOSED, awaiting Joshua's look review.** The approved art direction
(`ART_DIRECTION.md`, owner approval 2026-10-22) applied to the M1 gameplay assets. Each asset keeps
its blockout's id, node names, origin, scale and gameplay contract, so the game picks it up with no
code change; `tests/test_assets.gd` and `tests/test_part_placement.gd` check the contract.

Built by `tools/blender/make_m1_production.py` (shaders and baking in `tools/blender/surfacing.py`),
review sheets by `tools/blender/render_production.py`, in-game frames by
`tools/godot/capture_pool.gd`. The pool lighting is engineering's (`game/scenes/pool/pool_look.gd`,
DECISIONS "Pool lighting pass"); the floor's production pass keeps its geometry contract, vertex
colours and lighting passes and adds detail on top.

## What each asset became

| Asset | Look |
| --- | --- |
| `sample_cell` | The ladder cell on the gameplay body: coral pebble body with a rust back, cream belly and amber spots, three amber organelle beads, big lidded eyes (tops under the eye spot's 0.30 m), lips and a flagellum (hidden in the pool, where genome parts replace them). |
| `part_mouth_filter` | Eight-petal coral funnel with cream rims, a throat that darkens toward the gullet and a fringe of soft cilia with bead tips (soft, because a sharp point means danger in this era). |
| `part_mouth_jaw` | Two serrated chitin mandibles on hinges (`Mandible_L`/`_R`, ready for a bite animation), threat pink at the gum and worn amber at the tips, on a coral collar. |
| `part_flagellum` | A spiral-fluted whip, rust at the collar bead fading to a cream tip. |
| `part_eye_spot` | A glossy amber eye with a dark lens in a coral cup on a short stalk, under a rust petal lid (`EyeSpotLid`, ready for a blink). |
| `plankton` | A centric diatom: radial ribs, rings of pores, a food-glow core (emission map), girdle band. |
| `carrion` | A torn, marbled flesh chunk with muscle fibres, a pale sinew band and fat beads. |
| `creature_ambush_body` | Engineering's step 3 ambusher (flat dark mottled pebble, amber eyes, heavy brow) with a warty, pebbled hide, wet glowing eyes with fine grain and a wrinkled brow. Vertex-colour pattern, nodes, frame and M_AmbushEye unchanged. |
| `creature_rammer_body` | Engineering's step 3 rammer (pale banded dome, crest, frowning lids) with leathery plates and pores, a veined crest membrane and keratin-streaked threat points. Bands, Hood pivot and frame unchanged. |
| `part_spike` | The thorn with growth rings on its threat-coloured shaft, a knurled bone collar and a glossy dark point. Same length, attachment and reach. |
| `pool_floor` | Engineering's bowl, sand, silt patches and grey stone rim lip (vertex colours, unchanged), with sand ripples from a CC0 normal map on `M_PoolFloor.tres` (tiled every 5 m), so the caustics catch on them. Reduced only where the silt still fades softly. |
| `rock_a`, `rock_b`, `rock_c` | Glassy shells of dead microorganisms for the micro world (rev 4): a radiolarian lattice with an amber core, a ribbed diatom drum and a cream coccolith-plated drum. Same ids, footprint and swim-band outline contract. |

## Triangles and textures

Triangle reduction (CONFIRMED owner requirement, ART_DIRECTION section 9): each mesh is decimated
while its surface stays within the tolerance of the full-detail model, and the full-detail shading
is baked into the normal map.

| Asset | Full detail | Shipped | Budget | Tolerance | Textures (px) |
| --- | --- | --- | --- | --- | --- |
| `sample_cell` | 9,412 | 5,607 | 8000 | 1.5 mm | Albedo 1024, ORM 1024, Normal 1024 |
| `part_mouth_filter` | 1,344 | 1,260 | 1500 | 0.6 mm | Albedo 512, ORM 512, Normal 512 |
| `part_mouth_jaw` | 1,096 | 728 | 1500 | 0.6 mm | Albedo 512, ORM 512, Normal 512 |
| `part_flagellum` | 1,056 | 558 | 1500 | 0.6 mm | Albedo 512, ORM 512, Normal 512 |
| `part_eye_spot` | 1,256 | 1,006 | 1500 | 0.6 mm | Albedo 512, ORM 512, Normal 512 |
| `plankton` | 384 | 284 | 400 | 1.5 mm | Albedo 256, ORM 256, Normal 256, Emission 256 |
| `carrion` | 320 | 300 | 400 | 1.5 mm | Albedo 256, ORM 256, Normal 256 |
| `creature_ambush_body` | 3,264 (normals from a 6,000-triangle body) | 2,922 | 4000 | 1.5 mm body, 0.6 mm eyes and brow | Detail 1024, ORM 1024, Normal 1024 |
| `creature_rammer_body` | 3,800 (normals from a 5,000-triangle body) | 3,428 | 4000 | 1.5 mm body, 0.6 mm eyes, lids and crest | Detail 1024, ORM 1024, Normal 1024 |
| `part_spike` | 1,056 | 282 | 600 | 0.6 mm | Detail 512, ORM 512, Normal 512 |
| `pool_floor` | 17,536 | 13,802 | 20000 | 5 mm | Normal 1024 (engine material, tiled) |
| `rock_a` | 2,400 | 524 | 1300 | 10 mm | Albedo 512, ORM 512, Normal 512 |
| `rock_b` | 2,400 | 534 | 1300 | 10 mm | Albedo 512, ORM 512, Normal 512 |
| `rock_c` | 2,400 | 464 | 1300 | 10 mm | Albedo 512, ORM 512, Normal 512 |

The threat bodies keep engineering's vertex colours (the tests read their tone and bands), so
reduction also keeps every original vertex's colour within 0.04 per channel, and the rammer keeps
its three bands along the midline. Their materials keep their names and flat colours and gain a
shared greyscale detail albedo (`surfacing.bake_set(tints=...)`); the bodies' `.tres` multiply the
vertex colours by it. In-game frames: `renders/production/threat_*_godot.jpg`.

The old sample cell had 13,056 triangles and the blockout rocks 1,280 each. The filter mouth's
cilia are already thin, so it reduces least.

## Outside sources

| Source | License | Used for |
| --- | --- | --- |
| [Poly Haven, Aerial Beach 01](https://polyhaven.com/a/aerial_beach_01) (Rob Tuytel), 1k OpenGL normal map, kept in `assets/source/textures/cc0/polyhaven_aerial_beach_01/` | CC0 1.0 | Pool floor sand ripples (`assets/export/T_PoolFloor_Normal.png`) |
| [Poly Haven, Rock Boulder Dry](https://polyhaven.com/a/rock_boulder_dry) (Dimitrios Savva, Rico Cilliers), 1k diffuse and displacement, kept in `assets/source/textures/cc0/polyhaven_rock_boulder_dry/` | CC0 1.0 | Rock grain and height under the palette recolour (rocks rev 3; unused since the rev 4 shells, kept for the record) |

## Known gaps

- Judged in Blender's Cycles and in Godot's Compatibility renderer under a virtual display. A
  Forward+ frame on Joshua's RTX 5070 is still needed.
- The cell's rig (idle, swim, eat, hurt, die) comes in M1 step 5; the M1 cell is animated in code.
- Textures come from Cycles bakes, so rebuilding can change a few noise values in them; geometry
  and contract values are deterministic.

## Rebuild

```bash
/root/tools/bpyenv/bin/python tools/blender/make_m1_production.py [--only id,...]
/root/tools/bpyenv/bin/python tools/blender/render_production.py [id ...]
xvfb-run -a .toolchain/Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-method gl_compatibility \
  --fixed-fps 60 --script res://tools/godot/capture_pool.gd -- --out=docs/art/renders/production/pool --body=hunter --zoom=-2
```

## Micro-world ambience (PROPOSED tuning; the look is CONFIRMED in DECISIONS)

`game/scenes/pool/ambience/ambience.tscn` is decor only. The pool mounts it as its one `Ambience`
child when the file exists (engineering's micro-world plan, C6), so art adds files and never edits
`pool.tscn`. It reads the pool's camera and cell view, never the sim, and draws from its own
random numbers. `tests/test_ambience.gd` checks this and the contract in plan section 7.

- **Drifting layers** (`drift.gdshader`): four MultiMeshes of camera-facing quads, 1,540 in all.
  The shader wraps them in a 48 x 40 m box around the camera's focus, so the CPU never moves them.
  - 40 faint foreground specks and bubbles, 0.6 to 2.8 m above the plane.
  - 900 specks, 3 to 30 m below.
  - 120 rising bubbles, 3 to 10 m below.
  - 480 microbes in 18 swarms, 3 to 7 m below: rods, spirilla and spores. They part around the
    cell as it swims over them.
  - Shapes are drawn in the shader. Specks and bubbles grow softer away from the plane, standing
    in for depth of field.
- **Backdrops**: ten flat quads 12 to 22 m below the plane, recycled around the camera. Each
  carries a pre-blurred organism from `tools/blender/make_ambience_backdrops.py`: a giant ciliate,
  a bead colony, a diatom, a coiled filament or a radiolarian. The source is
  `assets/source/blender/ambience_backdrops.blend`, and the textures are in `assets/export/ambience/`.
- **Fading with depth**: everything is `blend_mix` with the engine's height fog on, so decor
  fades into the fluid with stock fog. There is no custom fog code and no depth of field.
- **Readability caps** (plan section 7):
  - nothing within 1.5 m below or 0.5 m above the swim plane;
  - every colour at least 25 degrees of LAB hue from food and threat, so no mauve;
  - linear luminance times opacity at most 0.12;
  - linear luminance at most 0.40 below the plane;
  - render priority under the strike lane's.
  
  Decor is therefore subtle by design: it gives depth and motion behind the cues and never
  competes with them.
- **Colours**: dusty blue, lavender and amber; the backdrops are blue-lavender, peach, pale silica
  and lavender.
- **Previews** until engineering's fluid lands: `capture_pool.gd -- --floor-y=-40 --micro-look`.
  This applies the plan's proposed fluid values and mounts the ambience.
