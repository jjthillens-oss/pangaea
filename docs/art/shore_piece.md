# Shore piece: asset brief and gate report

Asset id `shore_piece`. It replaces the `shore_light` placeholder (`game/scenes/pool/shore_view.gd`, two engine
cylinders) with a Blender-authored sand landing, and its entry in `assets/records/placeholders/inventory.json` goes.

Since main's "One continuous game" (`docs/DECISIONS.md`, 2026-10-25, #199) the pool's shore is the **sea edge**: the
cell swims out of the pool into the open sea (microscopic to aquatic), and the land comes later, from the sea. The
owner's sand bank still stands; it now reads as the sandbar at the pool's mouth that the cell swims over on its way
out. That reading is PROPOSED and needs the owner's look review. The before frames below were shot on base main
2ffc1218, when the offer still read "Crawl onto land?".
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

- The shore is the pool's sea edge, the first of `ShoreLink`'s links (microscopic to aquatic;
  `game/domain/shore_link.gd`, read-only for this job). It rises once, on the first paid ring at the build's top size
  (4), `RISE_AHEAD_TM` 20 tm north (`RISE_DIRECTION` (0, -1), Godot -Z) of the cell, on a point
  `GameSession.raise_shore` finds clear for about two cell radii.
- Within `REACH_TM` (4 tm at the current size) of the shore point, "Swim out to sea?" opens ("Swim out to sea" or
  "Stay in the pool"). Past `REACH_TM * REOPEN_SHARE` (6 tm) and back, it opens again.
- The toast says "The open sea lies up ahead. Swim into its light to leave the pool." (`Main.SHORE_RISEN_TEXT`), and
  the arrow reads "Open sea N m", so the piece keeps a **light shaft** (lead decision) and lays its light on the sand.
- The shore has **no collider**. The sim knows it only as a `world_changes` entry. So nothing solid may enter the
  swim band: the ambience contract keeps -1.5 m to +0.5 m free of decor (`tests/test_ambience.gd` `PLANE_BAND`),
  and the cradle ring and lair mouth sit at -1.6 m. The landing is **submerged**, its top at about -1.6 m (lead
  decision). A dry crest the cell climbs would need a sim collider in code this job may not edit.
- `ShoreView`'s API stays: `ShoreView.new()`, `place(local: Vector2)`, `pulse(delta: float)`, node name `Shore`,
  hidden until placed. It gains `rise()`, which the pool calls when the shore rises during play (its `shore_risen`):
  the piece then comes up out of the deep over `RISE_S` 3 s instead of appearing under the cell at once. The pool places it every frame from the save, in the plane's local frame (tm at the current
  size, 1 tm = 1 Godot unit).

## Camera and scale

- The camera is the same at every size (`game/scenes/pool/pool_camera.gd`, `game/data/pool_m1.json` "camera"):
  pitch 55°, fov 45°, distance 14 (zoom 10 to 20). At 14 the swim plane shows from about 10 tm north to 5.5 tm south
  of the cell, about 21 tm wide at the centre, about 93 px per tm at 1080p.
- The cell is always about 1 tm across, because growth re-expresses the world, not the cell. So the piece is
  authored at size 4 with **1 m = 1 tm at the size shown**, and the view never rescales it.
- Points below the plane draw toward the camera (south): about 1 tm on screen at 1.6 m deep and about 2.8 tm at 6 m.
- When the shore rises it is 20 tm off screen and only its arrow shows; the bank's long south skirt reaches under the
  cell, so `ShoreView.rise()` brings the piece up from 16 m down (in the fog) over 3 s rather than popping it in
  (Gate 4, frames 01 to 01d). The lit shelf, the ring and the foot of the shaft enter at the top
  edge when the cell is about 10 to 12 tm south of the shore point.

## Look direction

A sunlit sand bank rising out of the deep blue toward the pool's mouth (north), where the open sea begins. From the
size-4 camera it must read clearly as a landform rising into the shallows, not as a decal or a disc:

- **Pale sand**, paler and drier toward the crest, darker and wetter down the slope where the fluid's fog takes it.
- **Ripple marks** running along the contours, parallel to the "shoreline", so the bank's direction reads.
- A **crest edge**: the shelf breaks to a steeper face on the north (seaward) side, so the eye reads "the top".
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
-Y) toward the camera and the approaching cell, the crest is to the north, toward the open sea (Godot -Z, Blender
+Y, the front).

As built by `tools/blender/make_shore_piece.py` (chunk 2, PROPOSED). The plan before the build was a 24 by 20 m piece
with the skirt at -20 m by r 11 to 12 m; the Gate 1 grays showed that as a gumdrop (a flat top on a mound with steep
walls all round), so the slopes now run straight and long and the skirt eases into the fog over a wider footprint.

| Part | Size | Notes |
| --- | --- | --- |
| Shelf (the landing) | inside the brink: about 12.5 m E-W by 12 m N-S (x -5.4 to 7.2, y -5.8 to 6.3), centred at (0.25, 0.9) | Flat at -1.6 m north of y 1.8 (the crest), falling 0.085 m per m to the south brink (about -2.25 m), with broad 3.1 m swells of 7 cm. A lobed outline, not a disc: a spit curls south-east (the brink 9.2 m from the centre), a notch cuts the west. The brink stays at least 4.7 m from the pivot (a build check), clear of the reach ring's 4.3 m edge. A 9 cm berm lip runs along the brink, capped at -1.6 m. |
| South ramp | straight at about 26°, from the brink down 8 m (to about -10 m, about 16 m out) | The rounded brink (0.3 m) is the shelf's edge as seen from the approach. Flanks (east, west) at about 36° for 6 m of fall; the north face behind the crest at about 48° for 4 m, with a sharp crest edge (0.15 m rounding). |
| Skirt | easing from the end of each slope to -20 m: outer radius about 28 m south, 19 to 20 m east and west, 14 m north | In 50 to 80% fog. The outer rings are depth contours, so the skirt's UV strip splits cleanly by depth. |
| Grains | 28, 0.3 to 1.0 m, plus 2 broken glass valves (r 0.85 and 0.6 m) | Half sunk along the south brink, spilling down the ramp, a few by the spit and by the west notch; none within 1.3 m of the pivot. The highest solid vertex is a grain at -1.577 m (`sand_top_m` in the record is that measured top); the bank surface itself stays at or under -1.6 m. |
| Light shaft (`Shaft`) | open cone, top r 1.8 m, bottom r 2.8 m, from -1.6 m to +4.5 m | 24 segments, UV v from bottom (0) to top (1) in Blender. glTF flips v; `M_ShoreLight` flips it back. |
| Reach ring (`Reach`) | flat annulus, r 3.7 to 4.3 m around `REACH_TM` 4.0, at y -0.05 | On the swim plane, not on the sand: sand at -1.6 m draws about 1 tm south on screen and would mislead the player about where the offer opens. 64 segments, UV v from inner (0) to outer (1). |

Total footprint 42.9 by 41.7 m (most of it fogged skirt); Z from -20 m to +4.5 m with the shaft.

Rig family: none. A static piece, no animation; the pulse is a shader uniform.

## Material family

- **Sand (bank and grains): one baked material, `M_ShorePiece`**, with `T_ShorePiece_Albedo`, `ORM` and `Normal` at
  **1024 px** (lead decision). Procedural in Blender, then baked. The whole base colour is scaled once by
  `ALBEDO_GAIN` 0.27 before the bake (Gate 4 round 1: the pool's sun and ambient light the sand at about 1.9 times its
  albedo on screen, so the unscaled shelf read L* 77 behind the cell, brighter than the coral cell; scaled, it reads
  L* 43 to 47):
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
  part's strength (shaft 0.45, ring 1.0), green 0 for the shaft and 1 for the ring (a soft band across UV v). The
  builder writes that material file (tint #FFD486) with the light's Forward+ look as uniforms, tuned in Gate 4:
  `shaft_gain` 0.85 and `ring_gain` 0.35; the shaft fades from the sand up from `shaft_fade` 0.4 of its height to its
  top and toward its silhouette as facing^`shaft_edge` 1.5; and its wall toward the camera fades out from the sand up
  to `near_top` 0.6 of its height, because that wall stands between the camera and a cell in the light (it lifted the
  cell 4 to 10 L*), so the far wall carries the column. `ShoreView` sets `renderer_gain` (x the shaft, y the ring) to
  (1.0, 0.9) in Compatibility, where the ring reads about 3 L* brighter, and pulses a duplicate's `strength` (0.75 to
  1.25 at 0.5 Hz), never the shared material file.
- **Palette (sand albedo):** LAB hue 70 to 85°, chroma 15 to 30, linear luminance at most 0.40 everywhere (the
  below-plane rule, `tests/test_s2_assets.gd`: pieces wholly below the plane keep albedo luminance at or under 0.40).

  As built (the sand ramp's stops, wet to dry, as authored and as baked after `ALBEDO_GAIN`; L*, C, h and luminance
  are the baked colour's):

  | Role | Authored | Baked | L* | C | h | linear luminance |
  | --- | --- | --- | --- | --- | --- | --- |
  | wet deep slope | #5C4A36 | #2F2519 | 15.5 | 10.0 | 73.3° | 0.020 |
  | lower ramp | #7A6549 | #413524 | 22.9 | 12.6 | 77.7° | 0.038 |
  | upper ramp | #937A57 | #4F412D | 28.4 | 15.0 | 78.6° | 0.056 |
  | shelf | #A88F6B | #5B4D38 | 33.6 | 14.9 | 79.8° | 0.078 |
  | dry crest (top stop) | #B39A76 | #62533E | 36.3 | 14.7 | 80.1° | 0.092 |
  | amber feldspar grain | #A27D51 | #584329 | 29.9 | 19.8 | 73.5° | 0.062 |
  | quartz grain | #A89A80 | #5B5344 | 35.8 | 10.1 | 86.8° (27.6° from food) | 0.089 |
  | glass valve (highlight) | #9DA8A5 | #555B5A | 38.3 | 2.9 | 177.4° | 0.102 |
  | light tint | #FFD486 | (engine) | 87.0 | 44.4 | 82.9° | (additive) |

  Baked albedo audit (`tools/blender/render_shore_piece.py --audit`, final bake): linear luminance max 0.093, p99
  0.084, median 0.019 over the whole atlas (unused texels included); chroma-12+ texels (32% of all) at hue 76.1 to
  80.8° (p5 to p95); 0.00% of texels within 25° of the food hue and 0.00% of the threat hue (limit 2% each).
  `tests/test_shore_piece.gd` checks the median luminance and the hue shares on the imported texture.

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
  material in `assets/export/shore_piece.glb.import` after a Godot import; `--light` rewrites only the light material
  (light tuning without a bake). `--rough` saves the unbaked build to a
  scratch Blender file for shape review; `--root=DIR` writes every output under DIR instead of the repository (the chunk 2
  bakes went to a scratch folder outside Git, so no record sat in the repo before the atomic commit). `--rough`
  defaults to `builds/shore_piece/`, which Git ignores.
  Build-time checks: no bank, grain or valve vertex above -1.55 m; the shelf under every point of the r 4 circle
  between -1.6 and -2.6 m; the brink at least 4.7 m from the pivot; the ring flat at -0.05 with mid radius 4.0; at
  most 6000 triangles.
- Gate renders: `tools/blender/render_shore_piece.py` into `builds/shore_piece/gates` by default (Git ignores
  `builds/`), or any scratch folder outside Git with `--out`; `--blend`
  picks the build, `--audit` writes the baked albedo and prints its luminance and hue numbers.
- In-game frames: `tools/godot/shore_shots.gd` (size 4, seed 4248, open sea or `--home`); each shot's notes give the
  light's pulse strength.
- Regenerating: `python3 tools/blender/make_shore_piece.py`, `godot --headless --import`, `make_shore_piece.py
  --import`, `godot --headless --import` (the mapping then survives every later re-import, checked in chunk 3).
- In game (IMPLEMENTED): `game/scenes/pool/shore_view.gd` instantiates the GLB as `Model` under `Shore`, turns
  shadows off on every part, gives `Shaft` and `Reach` one duplicate of `M_ShoreLight` (with the renderer's gains) as
  their override, and scales `Reach` by `ShoreLink.REACH_TM / 4.0` (1 today). `place()` and `pulse()` keep their API;
  no primitive is left in the file. `game/scenes/pool/pool.gd` adds `ShoreView.warm_up_meshes()` to the start fade's
  warm-up in endless mode only. `tests/test_shore_piece.gd` covers the record, the swim band, the ring, the light, the
  view and the warm-up.
- The record, the `game/scenes/pool/shore_view.gd` swap and the inventory entry removal land in **one commit**, because
  `test_placeholders` fails on a placeholder whose asset has a record and on an unlisted primitive.

## Acceptance criteria

In game, `gl_compatibility` at 1920x1080, zoom 14, size 4 (`tools/godot/shore_shots.gd` readings):

1. From 10 tm south (02) the bank reads as a landform rising toward the north, emerging from the fog at the top.
2. Sand median L* behind the cell (05, cell hidden) is 36 to 48: at least 8 above the fluid around it and at least 15
   below the coral cell (L* about 62), so the cell stays the brightest thing in its neighbourhood.
3. The reach ring reads in front of the cell at the reach edge (03) and peaks at L* 80 or less.
4. The light shaft reads as light, not as a solid, the sand inside its foot reads lit (not as a dark disc), and the
   "Swim out to sea?" dialog (04) stays legible over the bank.
5. Nothing solid in the swim band: every bank and grain vertex at or below -1.55 m (build-time assert and a unit test).
6. No food or threat hues: at most 2% of albedo texels with chroma 12 or more within 25° of either.
7. No clipping or ugly overlap side-on (06) or near home with the cradle ring (`--home`); partly buried kit pieces
   are acceptable if they read as natural.
8. Both zoom extremes (07, 08) read.

### Results on the final export (Gate 4, IMPLEMENTED unless marked)

Compatibility readings from the final run of `tools/godot/shore_shots.gd` (open sea; the light's pulse at each shot
in brackets), Forward+ (lavapipe) for 02, 03 and 05:

1. **Met, with a note.** In 02 the cell is already over the long south ramp (the ramp runs about 16 m out from the
   brink, then the skirt), so the bank does not "emerge from the fog at the top"; it reads as a rippled slope rising
   to the lit crest and the ring at the top edge. Sand ahead of the cell L* 40.2 (Forward+ 40.6).
2. **Partly met.** Sand under the cell with the cell hidden (05): L* 47.0 (Forward+ 47.3), in the 36 to 48 window,
   and 14 to 24 above the fluid (L* 23 to 33). The sand 1.8 tm north of the cell lies in the shaft's lit foot: L*
   65.8 (Forward+ 68.0). **Not met:** the cell is only 6.4 L* above the sand under it, not 15: the coral cell reads
   L* 53.4 in Compatibility (54.0 to 54.5 in Forward+), not the 62 the criterion assumed, and the sand cannot sit 15 below
   that and 8 above the fluid. The cell stays the clearest thing in its neighbourhood by hue and chroma: CIE76 35.1
   between the cell (C 45, h 43°) and the sand under it (C 14, h 79°), 37.3 against the plain sand in 06. For the
   owner's look review.
3. **Met.** The ring reads in front of the cell in 03. At the pulse's top (1.25) it peaks at L* 75.4 on the shore
   point (05) in Compatibility and 75.4 in Forward+; the swept peaks were 71.4 to 75.4 (Compatibility, with its 0.9
   factor) and 73.2 to 75.4 (Forward+).
4. **Met.** The shaft reads as a column of light rising from the landing (03, 07, 08), not as a solid; the "Crawl onto
   land?" dialog (04) is legible over the dimmed bank. The cell in the light is not lit by it (cell L* 53.4 in every
   shot, 05 included).
5. **Met.** Build check and `test_nothing_solid_enters_the_swim_band`: the highest solid vertex is -1.577 m.
6. **Met.** 0.00% of chroma-12+ texels near food or threat (audit and `test_the_sand_keeps_dim_and_clear_of_reserved_hues`).
7. **Met (PROPOSED judgement).** No clipping side-on (06). With `--home` the shore rises 18 tm north of the home
   spawn: the cradle ring lies half-buried at the foot of the south ramp (the sand runs through its bowl), which reads
   as a drift; the home beacon stands on the shelf west of the ring, so the ring's west reading there (L* 74 to 82, h
   259 to 269°) is the beacon's blue, not the ring. Kit pieces (diatom columns, a shell) stand on the bank where the
   world placed them.
8. **Met.** Zoom 10 (07): the grains read as large pebbles, ring and lit foot in frame. Zoom 20 (08): the whole
   landing with the column of light rising over the crest.

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
| 1 Shape (neutral gray front, side, three-quarter, game camera, grazing light) | pass (Blender, final export) | [gate1_gray_sheet.jpg](../evidence/credit-shore/gate1_gray_sheet.jpg), re-rendered from the committed `assets/source/blender/shore_piece.blend`: front, side, three-quarter, south, plan, game camera at the shore point and 10 m south, grazing. The side view shows the long straight south ramp, the flat shelf and the steeper north face behind the crest. The plan shows a lobed outline with the south-east spit and the west notch, not a disc. At the game camera the shelf, the brink curve on the west and the north crest edge against the deep all read. Grains sit half sunk, none floating. The first three shape passes were a gumdrop (a flat top on a rounded mound, walls all round) and were revised. In the side views the deep skirt below about -10 m is still a broad rounded mound; in game it lies in the fog and reads as a dim slope, not a wall (Gate 4 frames 01 and 02). |
| 2 Materials with identity (close-up) | pass (Blender, final export) | [gate2_material_closeup.jpg](../evidence/credit-shore/gate2_material_closeup.jpg) (crest, grains and valve, game camera), re-rendered from the final bake. Matte sand with sharp-crested east-west ripple marks and sparse flecks; frosted grains in quartz, feldspar and umber tones, distinct from the sand; the glass valve reads as a broken porous glass plate; the ramp darkens with depth. Since Gate 4 round 1 the whole albedo carries `ALBEDO_GAIN` 0.27, so under the review rig the sand reads olive-khaki and the grains read as glossy pebbles rather than pale beads; the chunk 2 (unscaled) sheets are in Git history at 38341dad. Albedo audit as in the palette section: max luminance 0.093, no reserved hues. The base colour carries only `bake_set`'s 30% AO darkening, no directional light. |
| 3 Neutral lighting | pass, with a noted difference (Blender, final export) | [gate3_neutral_sheet.jpg](../evidence/credit-shore/gate3_neutral_sheet.jpg): the shared review rig (`lookdev.review_lighting`: warm key, cool fill, teal rim, fixed AgX exposure), final bake. Nothing clips; the shelf and ramp keep their ripples and the grains their highlights. The difference: with the exposure-matched albedo the deep skirt goes near-black-green in the three-quarter view under the rig's teal rim and cool fill, so the review rig no longer shows the slope's tone well. That is the rig's exposure, set for a 1 m creature; in the pool's own light (Gate 4) the skirt reads as a dim fogged slope. In the grazing view a 9° sun over the gray with the baked normal map shows ripples parallel to the crest, with no noise and no loops. The light shaft and ring show here only as a Blender preview; their engine look is Gate 4's. |
| 4 Export and Godot at gameplay distance (the real pool at size 4, approaching and at the shore) | pass, with acceptance criterion 2's L* gap open (above) | Export: 5158 triangles (budget 6000), two surfaces (`M_ShorePiece` with three 1024 px textures; `M_ShoreLight` engine material), 42.9 x 41.7 x 24.5 m, pivot on the shore point, faces -Z. Imported: `Shaft` and `Reach` draw with `res://assets/export/M_ShoreLight.tres` (the `.glb.import` mapping survived four re-imports), `COLOR_0` arrives raw (0.447 and 1.0), the bank's top is -1.577 m, the ring lies at y -0.05 from r 3.7 to 4.3. Frames: [after_02_approach.jpg](../evidence/credit-shore/after_02_approach.jpg), [after_03_reach_edge.jpg](../evidence/credit-shore/after_03_reach_edge.jpg), [after_04_offer.jpg](../evidence/credit-shore/after_04_offer.jpg), [after_05_on_shelf.jpg](../evidence/credit-shore/after_05_on_shelf.jpg), [after_08_zoom20.jpg](../evidence/credit-shore/after_08_zoom20.jpg), [after_home_02_approach.jpg](../evidence/credit-shore/after_home_02_approach.jpg), [gate4_godot_game.jpg](../evidence/credit-shore/gate4_godot_game.jpg) (`tools/godot/capture_asset.gd`, the game camera over the pool's fluid). Round 1 (the export as chunk 2 baked it) read the sand at L* 65 to 78 and the ring at 95 to 99, with no visible shaft (its fade ran upside down after glTF's v flip); rounds 1 and 2 fixed the albedo exposure, the shader's v and the light's gains (commits 63f2188e, 66121703). Readings: the results above. The three largest remaining differences: (1) the sand reads khaki-tan, paler than the fluid and palest on the crest, but not "pale sand" in absolute terms, the price of keeping it under the cell; (2) the shaft is a hollow tube: the sand inside its foot, seen through the open top, stays darker than the lit walls around it, a soft disc most visible at the capture tool's low close-up; (3) the grains read as glossy pebbles and show polygon facets at zoom 10 and closer. |

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

## After frames (the shore piece)

The same tool, seed, offsets and renderer on the final export (tuning round 2, base main 71c61fe5), Compatibility
unless named; the light's pulse strength at each shot in brackets.

| Frame | What it shows | Readings (L*) |
| --- | --- | --- |
| 01 risen (1.09) | The toast and the "Shore 20 m" arrow; the bank's south skirt already lies under the cell, dim in the fog. | fluid 25.3, ahead of the cell 32.5 |
| 02 approach, 10 tm south (1.10) ([jpg](../evidence/credit-shore/after_02_approach.jpg)) | The cell over the rippled south ramp, which rises to the paler crest; the ring and the shaft's foot at the top edge, partly behind the message panel. | sand ahead 40.2, ring 66.1; Forward+ sand 40.6, ring 69.2, cell 54.5 |
| 03 reach edge, 4.6 tm (0.77) ([jpg](../evidence/credit-shore/after_03_reach_edge.jpg)) | The ring just ahead of the cell; the column of light rising from the landing behind it. | ring 61.2, sand 1.8 tm ahead (the shaft's foot) 59.6; Forward+ ring 66.1, 63.6 |
| 04 offer, 3 tm (0.77) ([jpg](../evidence/credit-shore/after_04_offer.jpg)) | "Crawl onto land?" over the dimmed bank; legible. | dimmed |
| 05 on the shore point (1.25) ([jpg](../evidence/credit-shore/after_05_on_shelf.jpg)) | The cell inside the ring, standing in the shaft's lit foot without being lit by it. | cell 53.4, sand under it (hidden) 47.0, sand 1.8 tm north 65.8, ring 75.4; Forward+ cell 54.0, under 47.3, north 68.0, ring 75.4 |
| 06 east, 6 tm (0.83) | The bank's flank and the ring side-on; no clipping. | plain sand 43.3, ring 65.6 |
| 07 zoom 10 (0.99) | Large grains, the ring and the lit foot. | ring 71.9 |
| 08 zoom 20 (1.19) ([jpg](../evidence/credit-shore/after_08_zoom20.jpg)) | The whole landing, the ring, and the column of light over the crest. | ring 60.3 |
| home 02 ([jpg](../evidence/credit-shore/after_home_02_approach.jpg)) | `--home`: the cradle ring half-buried at the foot of the ramp, the bank running through its bowl. | |

