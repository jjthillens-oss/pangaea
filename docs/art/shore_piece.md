# Shore piece: asset brief and gate report

Asset id `shore_piece`. It replaces the `shore_light` placeholder (`game/scenes/pool/shore_view.gd`, two engine
cylinders) with a Blender-authored sand landing, and its entry in `assets/records/placeholders/inventory.json` goes.
This page is the Bible section 16 step 1 brief (gameplay function, dimensions, camera distance, silhouette, rig family,
material family, budget, acceptance criteria) and, further down, the gate report.

Status labels: **CONFIRMED** is the owner's requirement, **PROPOSED** is unapproved design, **IMPLEMENTED** is built
and verified. Unless a line says otherwise, everything below is PROPOSED.

## What the owner asked for (CONFIRMED)

> shore: replace the shore_light placeholder (game/scenes/pool/shore_view.gd, asset_id shore_piece) with a sand bank
> or landing seen from above at cell size 4, and remove its placeholder inventory entry.

The production rules apply too: a `.blend` in `assets/source/blender/`, a GLB in `assets/export/`, a record in
`assets/records/`, and no engine primitives left in game code (`tests/test_assets.gd`, `tests/test_placeholders.gd`).

## Gameplay function

- The shore is where the cell-to-creature link ends (`game/domain/shore_link.gd`, read-only for this job). It rises
  once, on the first paid ring at the build's top size (4), `RISE_AHEAD_TM` 20 tm north (`RISE_DIRECTION` (0, -1),
  Godot -Z) of the cell, on a point `GameSession.raise_shore` finds clear for about two cell radii.
- Within `REACH_TM` (4 tm at the current size) of the shore point, "Crawl onto land?" opens. Past
  `REACH_TM * REOPEN_SHARE` (6 tm) and back, it opens again.
- The toast says "A shore has risen up ahead. Swim into its light to crawl onto land." (`Main.SHORE_RISEN_TEXT`), so
  the piece keeps a **light shaft** (lead decision).
- The shore has **no collider**. The sim knows it only as a `world_changes` entry. So nothing solid may enter the
  swim band: the ambience contract keeps -1.5 m to +0.5 m free of decor (`tests/test_ambience.gd` `PLANE_BAND`),
  and the cradle ring and lair mouth sit at -1.6 m. The landing is **submerged**, its top at about -1.6 m (lead
  decision). A dry crest the cell climbs would need a sim collider in code this job may not edit.
- `ShoreView`'s API stays: `ShoreView.new()`, `place(local: Vector2)`, `pulse(delta: float)`, node name `Shore`,
  hidden until placed. The pool places it every frame from the save, in the plane's local frame (tm at the current
  size, 1 tm = 1 Godot unit).

## Camera and scale

- The camera is the same at every size (`game/scenes/pool/pool_camera.gd`, `game/data/pool_m1.json` "camera"):
  pitch 55°, fov 45°, distance 14 (zoom 10 to 20). At 14 the swim plane shows from about 10 tm north to 5.5 tm south
  of the cell, about 21 tm wide at the centre, about 93 px per tm at 1080p.
- The cell is always about 1 tm across, because growth re-expresses the world, not the cell. So the piece is
  authored at size 4 with **1 m = 1 tm at the size shown**, and the view never rescales it.
- Points below the plane draw toward the camera (south): about 1 tm on screen at 1.6 m deep and about 2.8 tm at 6 m.
- When the shore rises it is 20 tm off screen and only its arrow shows. The bank enters at the top edge when the cell
  is about 12 tm south of it.

## Look direction

A sunlit sand bank rising out of the deep blue toward the shore (north). From the size-4 camera it must read clearly
as a landform rising toward land, not as a decal or a disc:

- **Pale sand**, paler and drier toward the crest, darker and wetter down the slope where the fluid's fog takes it.
- **Ripple marks** running along the contours, parallel to the "shoreline", so the bank's direction reads.
- A **crest edge**: the shelf breaks to a steeper face on the north (inland) side, so the eye reads "the top".
- **Shallow-water light** over it: the shaft, and the light it implies on the sand.
- Micro scale (PROPOSED, needs the owner's look review): **giant sand grains**, rounded mineral grains 0.3 to 1.0 m
  across half sunk in the crest and spilling down the south ramp. The size-4 cell is about one grain across, which
  sells the microscopic scale ("scale the depiction of microscopic life into the aquatic ecosystem", Bible section
  6, continuity). One or two broken glass
  test fragments (diatom or foram halves) tie it to the micro world.

Original work only. No reference images from other games are used. The palette below is checked against the pool's
reserved hues.

## Dimensions (Blender metres, Z up, front +Y = north)

The pivot is the shore point on the swim plane (Godot y = 0). Yaw is fixed: the ramp faces south (Godot +Z, Blender
-Y) toward the camera and the approaching cell, the crest is inland to the north (Godot -Z, Blender +Y, the front).

| Part | Size | Notes |
| --- | --- | --- |
| Shelf (the landing) | about 13 m E-W by 10 m N-S at the -2.0 m contour | Top (`sand_top_m`) at -1.6 m, about 1.5 m north of the pivot. A rounded, slightly asymmetric lobe, not a disc: a spit curls south-east, a notch cuts the west. Its radius around the pivot is at least 5.5 m, so the reach ring (r 4) always draws over sand even though below-plane surfaces draw about 1 tm south on screen. |
| South ramp | shelf edge down to about -6 m by r 9 to 10 m | Gentle, about 25 to 30°. The north face past the crest is steeper. |
| Skirt | steepening to about -20 m at r 11 to 12 m | Fades into the fog (about 80% at 20 m), so no hard lower edge shows. |
| Grains | 24 to 36, 0.3 to 1.0 m | Every grain top at or below -1.55 m. |
| Light shaft (`Shaft`) | open cone, top r about 1.8 m, bottom r about 2.8 m, from -1.6 m to +4.5 m | 24 segments, UV v from bottom (0) to top (1). |
| Reach ring (`Reach`) | flat annulus, r 3.7 to 4.3 m around `REACH_TM` 4.0, at y -0.05 | On the swim plane, not on the sand: sand at -1.6 m draws about 1 tm south on screen and would mislead the player about where the offer opens. 64 segments, UV v from inner (0) to outer (1). |

Total footprint about 24 by 20 m; Z from about -20 m to +4.5 m with the shaft.

Rig family: none. A static piece, no animation; the pulse is a shader uniform.

## Material family

- **Sand (bank and grains): one baked material, `M_ShorePiece`**, with `T_ShorePiece_Albedo`, `ORM` and `Normal` at
  **1024 px** (lead decision). Procedural in Blender, then baked:
  - wet-to-dry ramp by height: darker and glossier with depth, palest on the crest;
  - ripple marks, wavelength 0.6 to 0.9 m, about 0.04 m deep, along the contours (normal and a little albedo);
  - fine mineral flecks;
  - grains smooth (roughness about 0.3), in quartz-cream, amber feldspar and umber, distinct from the sand.
- **Light (shaft and ring): one engine material, `assets/export/M_ShoreLight.tres`**, mapped in the
  `.glb.import` like `M_CheckpointColumn.tres`: unshaded, `blend_add`, `cull_disabled`, `depth_draw_never`,
  `fog_disabled`, `shadows_disabled`. `test_assets` allows one `engine_material` per record, so the two parts share
  it and a per-vertex weight (`COLOR_0` from a `LightWeight` attribute) sets each part's strength. The pulse sets a
  duplicate's `strength`, never the shared `.tres`.
- **Palette (sand albedo):** LAB hue 70 to 85°, chroma 15 to 30, linear luminance at most 0.40 everywhere (the
  below-plane rule, `tests/test_s2_assets.gd`: pieces wholly below the plane keep albedo luminance at or under 0.40).

  | Role | Example | L* | C | h | linear luminance |
  | --- | --- | --- | --- | --- | --- |
  | wet slope sand | #6E5B45 | 40.0 | 16.2 | 74.7° | 0.11 |
  | mid shelf sand | #8F7758 | 51.5 | 21.1 | 77.1° | 0.20 |
  | dry crest sand (upper bound) | #B49E7E | 66.3 | 20.0 | 80.9° | 0.36 |
  | light tint | #FFD486 | 87.0 | 44.4 | 82.9° | (additive) |

  Reserved hues: food #CFE86A (h 114.4°) and threat #D9466B (h 11.1°), with a 25° gap rule. The sand (h 70 to 85°)
  keeps at least 29° from food and 59° from threat; the light tint (82.9°) keeps 31.5° from food. The coral player
  cell is #E9744F (L* 62.0, h 44.0°).
- No outside sources by default. If a CC0 scan is used (Poly Haven or ambientCG), it lives under
  `assets/source/textures/cc0/<name>/` and is logged in the record's `dependencies`.

## Budget

- Triangles at most 6000 (landmark class), target 4500 to 5500.
- Textures: three at 1024 px (albedo sRGB; ORM and normal non-colour). 2048 only if the Gate 4 close-ups blur.
- Draw calls: two surfaces (sand, light).
- UVs: no whole-piece smart project (it would give most texels to the fogged skirt). A planar top-down UV for shelf
  and slope (about 85% of the atlas), a thin strip for the skirt, a reserved strip for the grains.

## Build and pipeline

- Builder: `tools/blender/make_shore_piece.py`, its own script (lead decision), patterned on
  `tools/blender/make_endless_extras.py` and using the shared helpers (`blockout_common`, `surfacing`, `lookdev`)
  without editing them. It writes the `.blend`, GLB, record and `M_ShoreLight.tres`; `--import` maps the light
  material in `assets/export/shore_piece.glb.import` after a Godot import.
- Gate renders: `tools/blender/render_shore_piece.py` into `/home/user/xdg/shore/scratch/gates` (outside Git).
- In-game frames: `tools/godot/shore_shots.gd` (size 4, seed 4248, open sea or `--home`).
- The record, the `shore_view.gd` swap and the inventory entry removal land in **one commit**, because
  `test_placeholders` fails on a placeholder whose asset has a record and on an unlisted primitive.

## Acceptance criteria

In game, `gl_compatibility` at 1920x1080, zoom 14, size 4 (`tools/godot/shore_shots.gd` readings):

1. From 10 tm south (02) the bank reads as a landform rising toward the north, emerging from the fog at the top.
2. Sand median L* behind the cell (05, cell hidden) is 36 to 48: at least 8 above the fluid around it and at least 15
   below the coral cell (L* about 62), so the cell stays the brightest thing in its neighbourhood.
3. The reach ring reads in front of the cell at the reach edge (03) and peaks at L* 80 or less.
4. The light shaft reads as light, not as a solid, and the "Crawl onto land?" dialog (04) stays legible over the bank.
5. Nothing solid in the swim band: every bank and grain vertex at or below -1.55 m (build-time assert and a unit test).
6. No food or threat hues: at most 2% of albedo texels with chroma 12 or more within 25° of either.
7. No clipping or ugly overlap side-on (06) or near home with the cradle ring (`--home`); partly buried kit pieces
   are acceptable if they read as natural.
8. Both zoom extremes (07, 08) read.

## Target contract

There is no reference image, so the contract is against this brief.

| Target | Implementation | Visible pass criterion |
| --- | --- | --- |
| A landform rising north, not a disc | Heightfield lobe with a spit, a notch, a gentle south ramp and a steeper north face | Gray top-down at the game camera shows an asymmetric bank with a readable crest |
| Sand, pale on the crest | Height-driven wet-to-dry albedo ramp | Close-up and in-game: crest visibly paler than the slope, within the L* window |
| Ripples along the contours | Contour-following ripple bands in normal and albedo | Grazing-light gray and the in-game frame show bands parallel to the crest, not noise |
| Crest edge | Break of slope at the crest line | Front and side grays show a distinct edge, not a pillow |
| Giant grains | Squashed, sunk grains with their own UV strip and finish | Close-up: grains distinct from sand; none floating, none above -1.55 m |
| Shallow-water light | Additive shaft plus the reach ring, one engine material | In game: a soft column over the landing and a ring at 4 tm on the plane |

## Gate report

Each gate is pass, needs revision or unverified, with an observable reason, after opening the renders.

| Gate | Result | Evidence and reason |
| --- | --- | --- |
| 1 Shape (neutral gray front, side, three-quarter, game camera, grazing light) | unverified | not built yet |
| 2 Materials with identity (close-up) | unverified | not built yet |
| 3 Neutral lighting | unverified | not built yet |
| 4 Export and Godot at gameplay distance (the real pool at size 4, approaching and at the shore) | unverified | not built yet |

## Before frames (the placeholder)

Rendered with `tools/godot/shore_shots.gd` on the placeholder, base main 2ffc1218 (the HUD before the hud job's
restyle), `gl_compatibility`, 1920x1080, zoom 14 unless named, seed 4248, open sea.
