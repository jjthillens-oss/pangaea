# Aquatic stage assets: finish gates (aquatic-r2)

The two Blender assets aquatic-r2 adds to the Aquatic stage, taken through the finish gates in
`/home/user/tools/ASSET_GATES.md` (gate 1 shape, gate 2 materials with identity, gate 3 neutral lighting, gate 4
export and Godot). Both are PROPOSED looks, awaiting the owner's review (their records say so).

| Asset | Record | What it is |
|---|---|---|
| `aquatic_nest` | `assets/records/aquatic_nest.json` | The spawning nest, the stage's home landmark (replaces the creature stage's `creature_nest_ring` in the Aquatic world). |
| `aquatic_plinth` | `assets/records/aquatic_plinth.json` | The fin and tail editor's reef-stone plinth (replaces the creature editor's `creature_editor_room` pad in the Aquatic editor; brief option O2). |

How the evidence was made:

- **Built** by `python3 tools/blender/make_aquatic_world.py --only aquatic_nest,aquatic_plinth` (bpy 5.2.2):
  procedural meshes, procedural shaders baked to one 1024 px albedo, ORM and normal set per asset, a Blender
  source file, a GLB and a record each.
- **Gates 1 to 3** were judged on renders of the **exported GLB** (not the Blender scene), by
  `python3 tools/blender/render_aquatic_review.py <id> --out=DIR`: neutral grey (clay) and material views from the
  front (yaw 0, the asset's +Y front), side (90), three-quarter (35) and top, plus close-ups, in Cycles under
  `lookdev.review_lighting`'s three-light rig moved out and strengthened with the asset's size, over a blue-grey
  ground disc at the pivot. Its teal rim light tints shadowed sand slightly green in these renders; that is the
  light, not the asset (the baked albedo has no green, checked on the texture itself).
- **Gate 4** was judged in Godot 4.7.2, gl_compatibility under Xvfb at 1920x1080, by `tools/godot/aquatic_shots.gd`
  (views `nest_start`, `nest_far`, `nest_side`, `nest_beacon`, `nest_clutch`, `nest_rest`, `editor`), and by the
  tests below. Compatibility overexposes a shadowed sun (`docs/TOOLCHAIN.md`), so the shallows' sand and the stones
  read paler there than authored; colour was judged against the Cycles renders and the textures.
- Every render listed was opened and looked at. The JPGs beside this file are the final revision's.

## aquatic_nest

### Reference contract

There is no image reference; the contract is the job brief's (step 8) and the Bible's §6 ("nests or spawning sites
create recognizable locations"), with the art direction's "the aquatic era adds cartilage and scale".

| Requirement | Implementation | Pass criterion | Result |
|---|---|---|---|
| A scooped bowl on the sea floor | A raised mound of shell gravel, its dish 0.27 m over the pivot, a bank cresting 0.5 m at r 3.5, the foot meeting the floor at r 4.5 | The dish reads as a hollow inside a ring; the floor never shows through it | Pass (renders; `test_the_nest_sits_on_the_sea_floor`) |
| A rim of rounded reef stones crusted with coral knobs | 16 flattened boulders along the rim (long along the ring), 2 to 3 lilac polyps each | A closed-looking ring of stones, not scattered pebbles; stones at most 0.9 m, at r >= 3.6 | Pass (the stones top out at 0.79 m and their polyps at 0.84 m; the stones' inner edges are at r 3.2; a 13-stone first pass read as scattered pebbles and was rebuilt) |
| Cartilage egg capsules | Six clutches (`Clutch_1`..`Clutch_6`, separate nodes), each three "mermaid's purse" capsules 0.45 x 0.27 m with four curled amber horns, at r 1.0 to 2.2 | Read as egg cases, cream with amber, distinct from the dish | Pass (close-ups); small at gameplay distance (see the differences below) |
| One landmark beacon, at most 6 m, front-left on the rim | A pillar of seven weathered reef-stone slabs with nine amber ribbon fronds bending with the current, its own node `Beacon` (pivot at its foot) with a child `BeaconDetail` (polyps and fronds); top 5.45 m over the pivot, at Blender (-2.15, +3.07) | In the spawn camera's first frame, and reads from about 25 m | Pass (`nest_start`, `nest_far`) |
| Footprint, skirt, pivot, axes | Footprint 4.6 m; a 0.55 m skirt under the pivot; pivot at the dish centre on the floor; Blender +Y front | Checked in the generator and in Godot | Pass (`test_the_nest_fits_its_site_and_leaves_the_spawn_clear`) |
| Palette | Stone #5B544A to #A99F8B (saturation under 20%), gravel and dish greys and browns, coral lilac #7E6A9A to #CDBEDC, eggs #EFE3C6 with #DDB57A streaks, horns and fronds amber | No glowing yellow-green (food), no threat pink #D9466B; 25 degrees of LAB hue from both | Pass (the nearest hues: eggs 92 and amber 73 to 79 against food's 114; coral 308 against threat's 11) |
| Budget | 11,666 triangles of a 12,000 budget (the budget of the stage-sized "rare" set pieces); one 1024 px texture set | Within budget | Pass |

### Gate 1: shape (pass)

Clay front, side, three-quarter and top (`aquatic_nest_gate1_clay.jpg`):

- The silhouette reads as a nest from every side: a low mound, a closed ring of boulders, and one tall pillar that
  breaks the ring's outline on the front-left. The top view shows the six clutches spaced round the dish and the
  beacon on the rim.
- The beacon reads as stacked slabs, each set off its neighbour, narrowing up the pillar, with the fronds bending
  over one way (along the rim, so they stay over the footprint). A first pass of round equal stones read as a
  snowman cairn and was rebuilt as flatter, rougher slabs.
- The stones are decimated within 7 mm (the polyps within 1.5 mm, as their own piece). Their outlines show some
  facets at 2 m (the `close_rim` view); at the gameplay camera (4 to 8 m) they read round. A first pass decimated
  the polyps with the stones (12 mm) and turned them into hexagonal crystals; they are now their own piece and
  stay round.
- No visible intersections except where intended (stones sunk into the bank, slabs overlapping in the stack,
  capsules sunk a third of their thickness into the dish).

### Gate 2: materials with identity (pass, with the texel limit noted)

Material views and close-ups (`aquatic_nest_gate2_materials.jpg`, `aquatic_nest_gate2_close.jpg`):

- Five identities read apart under neutral light: shell gravel on the bank (pebbles of two sizes, each its own
  shade, pale shell fragments, shallow gaps), damp darker sand in the dish, grey pitted reef stone with a pale crust
  on the tops, lilac coral polyps, cream egg capsules streaked with amber and their amber horns, and amber kelp-like
  fronds with darker spots.
- The dish was darkened after the first Godot frames, so the cream eggs stand out from it.
- Roughness differs by surface (gravel 0.92, stone 0.78 to 0.9, polyps 0.55, eggs 0.35, fronds 0.55); nothing is
  metallic.
- Baked occlusion: the clutches bake away from the mound (`_bake_pieces(isolate=...)`), because the game hides the
  clutches of generations not yet born; the first bake left dark egg-shaped shadows on the dish under hidden
  clutches, seen on the albedo texture, and was fixed.
- Gutters: the generator fills the empty texture between UV islands with the islands' own colours
  (`_fill_gutters`), so the mipmaps of small islands (polyps, horns) keep their colour; build c4d, without it,
  showed some polyps as dark dots in the Godot spawn frame.
- Limit: one 1024 px set covers a 9.2 m nest, so the gravel is about 2 cm a texel and looks soft in a close-up at
  2 m; it reads as gravel at the gameplay camera. The texel weights give the mound more of the texture.

### Gate 3: neutral lighting (pass)

The review rig is the project's neutral three-light setup scaled to the asset (key 260 W, fill 70 W and rim 180 W
times (size / 3 m) squared, at the same angles), with a world fill; no bloom or depth of field. Highlights are not
clipped; the beacon's shadow side keeps detail. The green cast in shadowed sand is the teal rim light (above).

### Gate 4: export and Godot (pass)

- Export: GLB with nodes `NestMound`, `NestRim`, `NestPolyps`, `Beacon` (with its child `BeaconDetail`) and
  `Clutch_1`..`Clutch_6`; one material `M_AquaticNest` with albedo, ORM and normal textures (extracted by the
  import, as every asset is); 9.2 x 9.2 x 6.0 m (`test_every_record_with_dimensions_matches_its_export`).
- Placement (`game/scenes/aquatic/aquatic_world.gd`): at `rules.world.nest` on the floor profile, tilted to the
  0.2 m/m slope, sunk 0.1 m, the beacon stood upright on its foot. `tests/test_aquatic_assets.gd` loads the nest and
  the drawn sea floor and checks: the footprint within 4.65 m; nothing within 0.8 m of the fish's spawn or its
  kin; the beacon 4 to 6.2 m over the floor; the foot meeting the drawn floor all round within 0.2 m; the skirt at
  least 0.25 m under it; the dish at least 3 cm over it; every egg above it; the beacon upright with its base under
  the mound round its foot; the tilt equal to the slope.
- Frames (`aquatic_nest_gate4_godot.jpg`): the spawn frame (`nest_start`) has the beacon and its fronds on the left
  and the rim stones below the fish; from about 24 m (`nest_far`) the ring and the pillar read where PR #192's nest
  ring was a faint outline (`nest_far_before.jpg`); side-on across the slope (`nest_side`) the mound follows the
  floor with no gap or buried edge; `nest_clutch` shows three clutches after two generations.

### The three largest remaining differences

1. The clutches are small at the gameplay camera, and in Compatibility's overexposed shallows the cream eggs on
   the dish are only a little darker than the light around them. They read clearly within about 5 m.
2. The gravel's texel density (above) softens the bank in close views.
3. The stones' outlines are faceted at close range (decimation within 7 mm, kept for the budget).

## aquatic_plinth

### Reference contract

| Requirement | Implementation | Pass criterion | Result |
|---|---|---|---|
| A reef-stone plinth for the fin editor (plan section 2; brief O2) | A unit-radius slab of layered reef rock, 0.35 m deep, its flat top at the pivot | Reads as stone, not as the creature editor's metal pad | Pass |
| The editor's contract | Pivot at the centre of the top face; radius 1.0 (0.99 after the bitten edge); the editor scales it uniformly by 1.6 at y = -0.01 | `test_the_editor_stands_on_the_aquatic_reef_stone_plinth` | Pass |
| Detail where the camera looks | Polyp colonies and two amber sponges mostly on the far rim (Blender +Y), which the editor camera sees against the water under the fish | Visible, and lower than the fish | Pass (the tallest sponge is 0.11 m, 0.18 m at the editor's scale) |
| Budget | 3,874 triangles of 4,000; one 1024 px set | Within budget | Pass |

### Gate 1: shape (pass)

Clay views (`aquatic_plinth_gates.jpg`, top row): a flat top with a stepped edge (two ledges of layered rock)
bitten in by noise at two scales, never past r 1.0; the polyps and sponges stand on the rim. The bitten edge reads
soft rather than sharp-broken, which suits a water-worn reef stone. No intersections.

### Gate 2: materials with identity (pass)

Material views and close-up (bottom row): a weathered grey-brown stone top with darker patches, shallow pocks and
pale sand settled in pools; a darker edge with layer lines; lilac coral crust in patches on the edge; round lilac
polyps; amber sponges with a dark opening. A first pass had a pale beige top that read as concrete and, in the
editor, competed with the fish; it was darkened.

### Gate 3: neutral lighting (pass)

The same scaled review rig; no clipping, the shadowed edge keeps its layer lines.

### Gate 4: export and Godot (pass)

`assets/export/aquatic_plinth.glb` (one node `AquaticPlinth`, one material `M_AquaticPlinth` with its three textures, 1.96 x 1.96
x 0.45 m) in the editor (`editor_plinth_after.jpg` against `editor_before.jpg`): the fish turns over a reef-stone
slab with polyps and sponges along its far rim, where the creature stage's dark-blue metal pad was. The aquatic
smoke checks the editor's plinth is this asset.

### The three largest remaining differences

1. The bitten edge is soft; a broken, chipped edge would read more like rock at close range.
2. The top's texture is soft at the editor's 1.6 scale (1024 px over 3.2 m).
3. The polyps are one lilac with paler mouths; a second coral colour would add variety.

## Revisions

| Build | Change | Why (seen in) |
|---|---|---|
| Preview 1 (procedural, not exported) | 13 rim stones, round beacon stones, small eggs | Rejected: the rim read as scattered pebbles, the beacon as a snowman cairn, the eggs as specks (`close_far`, `clay_threequarter`) |
| Preview 2 (procedural) | 20 larger stones, flatter slabs, eggs 1.25 times larger; the plinth's first pass | The rim closed up; the plinth read as a soft cushion, so its edge was stepped and bitten |
| c4b (first export) | First GLBs, Godot frames | Polyps decimated into crystals; dark egg shadows baked on the dish under hidden clutches; the eggs too close to the dish in tone; the plinth top pale |
| c4c | Polyps and fronds as their own pieces; clutches baked in isolation; darker dish and plinth top | Round polyps, clean dish, eggs stand out |
| c4d | Texel weights: the mound 1.8, the polyps 0.5 | The gravel was the softest surface; but the polyps' islands became too small and went dark in the mipmaps (`nest_start` in Godot) |
| c4e (final) | The UV gutter fill; texel weights the mound 1.6, the polyps 1.2 | Lilac polyps at every distance, the gravel still sharper than c4c |
