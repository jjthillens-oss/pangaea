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

The production rules apply too: a Blender source in `assets/source/blender/`, a GLB in `assets/export/`, a record in
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

As built by `tools/blender/make_shore_piece.py` (chunk 2, PROPOSED). The plan before the build was a 24 by 20 m piece
with the skirt at -20 m by r 11 to 12 m; the Gate 1 grays showed that as a gumdrop (a flat top on a mound with steep
walls all round), so the slopes now run straight and long and the skirt eases into the fog over a wider footprint.

| Part | Size | Notes |
| --- | --- | --- |
| Shelf (the landing) | inside the brink: about 12.5 m E-W by 12 m N-S (x -5.4 to 7.2, y -5.8 to 6.3), centred at (0.25, 0.9) | Flat at -1.6 m north of y 1.8 (the crest), falling 0.085 m per m to the south brink (about -2.25 m), with broad 3.1 m swells of 7 cm. A lobed outline, not a disc: a spit curls south-east (the brink 9.2 m from the centre), a notch cuts the west. The brink stays at least 4.7 m from the pivot (a build check), clear of the reach ring's 4.3 m edge. A 9 cm berm lip runs along the brink, capped at -1.6 m. |
| South ramp | straight at about 26°, from the brink down 8 m (to about -10 m, about 16 m out) | The rounded brink (0.3 m) is the shelf's edge as seen from the approach. Flanks (east, west) at about 36° for 6 m of fall; the north face behind the crest at about 48° for 4 m, with a sharp crest edge (0.15 m rounding). |
| Skirt | easing from the end of each slope to -20 m: outer radius about 28 m south, 19 to 20 m east and west, 14 m north | In 50 to 80% fog. The outer rings are depth contours, so the skirt's UV strip splits cleanly by depth. |
| Grains | 28, 0.3 to 1.0 m, plus 2 broken glass valves (r 0.85 and 0.6 m) | Half sunk along the south brink, spilling down the ramp, a few by the spit and by the west notch; none within 1.3 m of the pivot. The highest solid vertex is a grain at -1.577 m (`sand_top_m` in the record is that measured top); the bank surface itself stays at or under -1.6 m. |
| Light shaft (`Shaft`) | open cone, top r 1.8 m, bottom r 2.8 m, from -1.6 m to +4.5 m | 24 segments, UV v from bottom (0) to top (1). |
| Reach ring (`Reach`) | flat annulus, r 3.7 to 4.3 m around `REACH_TM` 4.0, at y -0.05 | On the swim plane, not on the sand: sand at -1.6 m draws about 1 tm south on screen and would mislead the player about where the offer opens. 64 segments, UV v from inner (0) to outer (1). |

Total footprint 42.9 by 41.7 m (most of it fogged skirt); Z from -20 m to +4.5 m with the shaft.

Rig family: none. A static piece, no animation; the pulse is a shader uniform.

## Material family

- **Sand (bank and grains): one baked material, `M_ShorePiece`**, with `T_ShorePiece_Albedo`, `ORM` and `Normal` at
  **1024 px** (lead decision). Procedural in Blender, then baked:
  - wet-to-dry ramp by height: darker and glossier with depth (roughness 0.6), palest and matte on the crest (0.9);
  - ripple marks, wavelength 0.72 m, sharp crests and broad troughs, about 0.035 m deep, plus 2.6 m swells. They run
    east-west (parallel to the shore in the north) and bend to follow the brink on the south half; they fade below
    about -3 m and on faces steeper than about 30° (normal and a little albedo);
  - heavy-mineral flecks gathered in the ripple troughs, and a few amber feldspar flecks;
  - grains frosted-smooth (roughness 0.42; 0.3 read as wet beads in the Gate 2 close-up), in quartz cream, amber
    feldspar and umber, distinct from the sand;
  - the glass valves: a pale grey-green silica (roughness 0.16) with radial ribs and rings of pores.
  The shader reads three helper attributes (`Ripple`, `Mask`, `Local`) that the build removes after the bake.
- **Light (shaft and ring): one engine material, `assets/export/M_ShoreLight.tres`**, mapped in the
  GLB's import file like `assets/export/M_CheckpointColumn.tres`: unshaded, `blend_add`, `cull_disabled`, `depth_draw_never`,
  `fog_disabled`, `shadows_disabled`. `test_assets` allows one `engine_material` per record, so the two parts share
  it and a per-vertex weight (`COLOR_0` from a `LightWeight` attribute, raw values) tells them apart: red is the
  part's strength (shaft 0.45, ring 1.0), green 0 for the shaft (it fades at both ends and toward its silhouette) and
  1 for the ring (a soft band across UV v). The pulse sets a duplicate's `strength`, never the shared material file.
  The builder writes that material file (tint #FFD486); its strengths are first guesses for Gate 4 to tune.
- **Palette (sand albedo):** LAB hue 70 to 85°, chroma 15 to 30, linear luminance at most 0.40 everywhere (the
  below-plane rule, `tests/test_s2_assets.gd`: pieces wholly below the plane keep albedo luminance at or under 0.40).

  As built (the sand ramp's stops, wet to dry):

  | Role | Colour | L* | C | h | linear luminance |
  | --- | --- | --- | --- | --- | --- |
  | wet deep slope | #5C4A36 | 32.8 | 15.5 | 73.3° | 0.074 |
  | lower ramp | #7A6549 | 44.1 | 19.5 | 77.7° | 0.139 |
  | upper ramp | #937A57 | 52.7 | 23.2 | 78.6° | 0.208 |
  | shelf | #A88F6B | 60.8 | 23.0 | 79.8° | 0.290 |
  | dry crest (top stop) | #B39A76 | 65.0 | 22.7 | 80.1° | 0.340 |
  | amber feldspar grain | #A27D51 | 55.0 | 30.7 | 73.5° | 0.229 |
  | quartz grain | #A89A80 | 64.2 | 15.6 | 86.8° (27.6° from food) | 0.330 |
  | glass valve (highlight) | #9DA8A5 | 67.9 | 4.5 | 177.4° | 0.379 |
  | light tint | #FFD486 | 87.0 | 44.4 | 82.9° | (additive) |

  Baked albedo audit (`tools/blender/render_shore_piece.py --audit`, final bake): linear luminance max 0.339, median 0.12 over the
  used texels, about 0.28 on the shelf; chroma-12+ texels at hue 73.6 to 80.6° (p5 to p95); 0.01% of texels within
  25° of the food hue and 0.00% of the threat hue (limit 2% each).

  Reserved hues: food #CFE86A (h 114.4°) and threat #D9466B (h 11.1°), with a 25° gap rule. The sand (h 70 to 85°)
  keeps at least 29° from food and 59° from threat; the light tint (82.9°) keeps 31.5° from food. The coral player
  cell is #E9744F (L* 62.0, h 44.0°).
- No outside sources by default. If a CC0 scan is used (Poly Haven or ambientCG), it lives in its own folder under
  `assets/source/textures/cc0/` and is logged in the record's `dependencies`.

## Budget

- Triangles at most 6000 (landmark class), target 4500 to 5500. As built: 5158 (bank 2408 on a 56-segment polar
  grid, grains about 1870 with wholly buried faces dropped, valves 432, shaft 192, ring 256).
- Textures: three at 1024 px (albedo sRGB; ORM and normal non-colour). 2048 only if the Gate 4 close-ups blur.
- Draw calls: two surfaces (sand, light).
- UVs: no whole-piece smart project (it would give most texels to the fogged skirt). As built: a planar top-down UV
  for the shelf and the slopes down to about -6.7 m (83% of the atlas, 33.5 px per m), the skirt below on a strip by
  angle and depth (bottom right), and the grains and valves in their own square tiles (bottom left; a grain maps by
  an equal-area projection about its top, so its buried underside lands on the tile's rim).

## Build and pipeline

- Builder: `tools/blender/make_shore_piece.py`, its own script (lead decision), patterned on
  `tools/blender/make_endless_extras.py` and using the shared helpers (`blockout_common`, `surfacing`, `lookdev`)
  without editing them. It writes the Blender source, the GLB, the record and the light material; `--import` maps the light
  material in `assets/export/shore_piece.glb.import` after a Godot import. `--rough` saves the unbaked build to a
  scratch Blender file for shape review; `--root=DIR` writes every output under DIR instead of the repository (the chunk 2
  bakes went to `/home/user/xdg/shore/scratch/build`, so no record sat in the repo before the atomic commit).
  Build-time checks: no bank, grain or valve vertex above -1.55 m; the shelf under every point of the r 4 circle
  between -1.6 and -2.6 m; the brink at least 4.7 m from the pivot; the ring flat at -0.05 with mid radius 4.0; at
  most 6000 triangles.
- Gate renders: `tools/blender/render_shore_piece.py` into `/home/user/xdg/shore/scratch/gates` (outside Git); `--blend`
  picks the build, `--audit` writes the baked albedo and prints its luminance and hue numbers.
- In-game frames: `tools/godot/shore_shots.gd` (size 4, seed 4248, open sea or `--home`).
- The record, the `game/scenes/pool/shore_view.gd` swap and the inventory entry removal land in **one commit**, because
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
| 1 Shape (neutral gray front, side, three-quarter, game camera, grazing light) | pass (Blender, final bake) | [gate1_gray_sheet.jpg](../evidence/credit-shore/gate1_gray_sheet.jpg): front, side, three-quarter, south, plan, game camera at the shore point and 10 m south, grazing. The side view shows the long straight south ramp, the flat shelf and the steeper north face behind the crest. The plan shows a lobed outline with the south-east spit and the west notch, not a disc. At the game camera the shelf, the brink curve on the west and the north crest edge against the deep all read. Grains sit half sunk, none floating. The first three shape passes were a gumdrop (a flat top on a rounded mound, walls all round) and were revised. Remaining: in the side views the deep skirt below about -10 m is still a broad rounded mound. In game it lies in 50 to 80% fog; Gate 4 must check it does not read as a wall in the 02 frame. |
| 2 Materials with identity (close-up) | pass (Blender, final bake) | [gate2_material_closeup.jpg](../evidence/credit-shore/gate2_material_closeup.jpg) (crest, grains and valve, game camera). Matte sand with sharp-crested east-west ripple marks and sparse flecks; frosted grains in quartz cream, amber feldspar and umber, distinct from the sand; the glass valve reads as a broken porous glass plate; the ramp darkens and turns glossier with depth. The first bake had a dark occlusion disc under the shaft and closed ripple loops on the crest. Both were fixed (the light parts are added after the bake; the north half's ripples stay east-west). Albedo audit as in the palette section: max luminance 0.339, no reserved hues. The base colour carries only `bake_set`'s 30% AO darkening, no directional light. |
| 3 Neutral lighting | pass (Blender, final bake) | [gate3_neutral_sheet.jpg](../evidence/credit-shore/gate3_neutral_sheet.jpg): the shared review rig (`lookdev.review_lighting`: warm key, cool fill, teal rim, fixed AgX exposure). The sand is not clipped and the dark slopes stay readable. The deep skirt turns olive under the teal rim and cool fill; that is the rig, since its albedo is brown (h 73°). In the grazing view a 9° sun over the gray with the baked normal map shows ripples parallel to the crest, with no noise and no loops. The light shaft and ring show here only as a Blender preview; their engine look is Gate 4's. |
| 4 Export and Godot at gameplay distance (the real pool at size 4, approaching and at the shore) | unverified | not built yet |

## Before frames (the placeholder)

Rendered with `tools/godot/shore_shots.gd` on the placeholder, base main 2ffc1218 (the HUD before the hud job's
restyle), `gl_compatibility`, 1920x1080, zoom 14 unless named, seed 4248, grazer. The shore rose at (600.0, 518.1) am
in open sea (the cell moved to (600, 600) am first); with `--home` it rose at (0.0, -72.9) am, by the cradle.
L* is CIE L* of a box median from the script's readings.

| Frame | What it shows | Readings |
| --- | --- | --- |
| 01 risen | The toast "A shore has risen up ahead..." and the warm arrow "Shore 20 m" at the top edge; the shore is off screen. | fluid around the cell L* 36 |
| 02 approach, 10 tm south ([jpg](../evidence/credit-shore/before_02_approach.jpg)) | The shaft's top is already on screen at the top edge as a white blob behind the message panel. No bank. | fluid L* 30 to 36 |
| 03 reach edge, 4.6 tm ([jpg](../evidence/credit-shore/before_03_reach_edge.jpg)) | A pale translucent cylinder with a disc; the disc's edge runs just north of the cell. Reads as a glass column, not ground. | north of the cell L* 89 |
| 04 offer, 3 tm ([jpg](../evidence/credit-shore/before_04_offer.jpg)) | "Crawl onto land?" over the dimmed pool; legible. | dimmed |
| 05 at the shore point ([jpg](../evidence/credit-shore/before_05_on_shelf.jpg)) | The additive shaft clips to pure white around the cell, which washes to L* 76.5 (53.4 elsewhere). Nothing reads as sand. | behind the cell, cell hidden, L* 100 (clipped) |
| 06 east, 6 tm | The cylinder and disc side-on: a large translucent pale shape. | |
| 07 zoom 10 | The shaft clips white across the top half. | north of the cell L* 98.7 |
| 08 zoom 20 | A glowing cylinder above a disc. | north of the cell L* 100 |

What the placeholder gets wrong, and what the piece must fix: no ground or landform at all; the shaft's additive
walls clip to white in this renderer and wash out the cell; the disc reads as glass, not sand. The `--home` run
shows the cradle ring filling the south of the frame at 10 tm, so the landing's skirt must be checked against the
cradle's rim in Gate 4.
