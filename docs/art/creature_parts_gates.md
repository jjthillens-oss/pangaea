# Creature part finish gates: the six reworked parts and the fur

Gate report for the creature-parts job: the frog foot, frog hand, bulge eye,
round ear, primate muzzle and dragon wing (`cpart_foot_frog`, `cpart_hand_frog`, `cpart_eye_bulge`,
`cpart_ear_round`, `cpart_muzzle_primate`, `cpart_wing_dragon`) and the fur covering of
`assets/export/shaders/creature_skin.gdshader`. All of this art is PROPOSED. Part ids, handle keys, sockets, pivots and
scale stay as they are (CONFIRMED, owner). Each gate is recorded as pass, needs revision or unverified with what was
seen; a part's record carries the same notes under `review_notes` (written by
`tools/blender/make_creature_parts.py`, since the export rewrites the whole record).

The gates are the finish-hunyuan-assets gates: 1 shape in neutral grey (front, side, three-quarter), 2 materials with
identity (close-up), 3 neutral lighting, 4 export and Godot verification at gameplay distance.

## How the frames are made

- Blender gate 1 and 2 views: `python3 tools/blender/render_part_review.py [--shape=H1_Fold:1000] <glb> <out dir>`
  (gray_ and mat_ front, side, threequarter, top; `--shape` poses a handle). `--views=` picks views (also `low34`, a
  three-quarter from below, and `back`), `--dist=` sets the camera distance in bounding-box diagonals (default 2.2;
  1.1 to 1.3 frame a small part closely), `--size=` the frame size, and `--stand` stands a face part up as it sits on a
  head (its face toward the front camera, its brow up), so the side view shows a muzzle's profile.
- Godot part views: `tools/godot/capture_part.gd -- <glb> <out dir> [--handles=Key:permille] [--fit] [--mirror]
  [--views=front,side]` (neutral sky colour, one sun, a ground plane at the pivot).
- On a real body: `tools/godot/part_on_body_shot.gd -- --preset=<name> --focus=<part type>` builds the preset in the
  creature editor scene (`game/scenes/creature/creature_editor.tscn`, driven through `setup()`), with the preset's
  colour, pattern and covering. Views: `editor` (the editor's own camera and HUD), `gameplay` (the creature world's
  camera distance, 2.4 x the body length, 2.6 to 12 m, fov 50, from the front three-quarter), `close` and `side` (on
  the part). `--mark=<part type>:<material>:<#colour>` (diagnostic) paints one material flat and unlit, to find which
  faces make a band or a highlight.
- The round ear's head-sphere shots: `tools/ear_round_shots.gd`. The fur fixture: `tools/covering_shots.gd --only=fur`.
- All Godot frames are the Compatibility renderer under Xvfb (it overexposes a shadowed sun, `docs/TOOLCHAIN.md`).
- Evidence (before and after pairs) is in `docs/evidence/credit-creature-parts/`.

## Before (main at 2ffc1218): what the frames show

| Part | Open review item | Seen in the before frames |
| --- | --- | --- |
| cpart_foot_frog (rev 5) | ankle and heel | Gray front and three-quarter: the ankle is a straight tube with a flat top and a crease ring where it enters the sole; the heel is a separate lump behind it. On the hopper in the editor the frog feet sit under the floor pad (placement, not the part); `--no-floor` shows them. |
| cpart_hand_frog (rev 2) | (finish) | Gray: faceted round toe discs, a flat-ended wrist stub. |
| cpart_eye_bulge (rev 4) | cream band | Godot close: a faceted iris ball and a thin dark line at the lid lip; no cream band shows under the neutral capture light. On the hopper in the editor's light: a pale cream-green flat ledge round each ball, which is the lid band (confirmed with `--mark`, see the revision 5 section). |
| cpart_ear_round (rev 4) | rim facets and crease | Head-sphere front and three-quarter: straight segments along the outline and a crease line inside the rolled rim. |
| cpart_muzzle_primate (rev 3) | side profile | Gray side: a flat slab with a box-shaped muzzle table and a brow of the same height, a slot between them. On the monkey it sits small under the eyes. |
| cpart_wing_dragon (rev 1) | fold lift-off (found by the scout) | Godot front and side at H1_Fold 500 and 1000: the root leaves the ground plane; at 1000 the folded bundle hovers above it with membrane shreds below. On the dragon preset the folded wings float above the back. |
| fur (covering 1) | close-up flakes, leg strand direction | Fixture close: separate pale disc slices along the silhouette; fixture side: bristles standing off the legs. On the monkey, boar and prowler in the editor: an even fine fringe. |

## cpart_wing_dragon, revision 2 (IMPLEMENTED)

Change: H1_Fold keeps the root on the skin. The fold fades out over the 6 cm above the root, only the fingers draw
in toward the wrist (the arm and the inner panel's body edge stay), and the last finger's polar angle is taken in
0..360 like the folded points'. Before, it was -172 degrees, so finger 4 and the panel between fingers 3 and 4 turned
past their fold targets, and every point more than 6 cm from the wrist, the root included, was drawn 38% toward it:
the root rose 6.2 to 6.5 cm at scale 1000 (16 cm on the dragon preset at 2600). Rest shape, H2_Flap, materials,
bake, sockets (none), pivot, triangles (2334 of 2500) and dimensions (0.068 x 0.345 x 0.444 m) are unchanged.

| Gate | Status | Observation |
| --- | --- | --- |
| 1 shape | pass | Gray side and three-quarter at H1_Fold 0, 500 and 1000 (Blender) and Godot front and side on a ground plane: the arm stands on the ground at every fold; the fingers bundle back down along the forearm with the membrane pleated between them; no tear and no finger through the membrane. At 1000 the inner panel's body edge stays along the skin as a narrow sliver, as a bat's flank membrane does (PROPOSED). Folded GLB y min: bones -0.0238, membrane -0.0186 (rest values); the sunk root vertices stay at or below -0.012. |
| 2 materials | pass (unchanged) | Membrane red-brown with fine raised veins, scaly green bone and cream claw read apart in the Blender material view and in Godot. |
| 3 lighting | pass | Neutral Blender review light and the neutral Godot capture; no bloom. |
| 4 Godot | pass | Imported; the dragon preset in the editor scene at the world's gameplay distance (7.55 m) and close, open and folded: the folded wings sit rooted on the back. `test_every_handle_at_full_keeps_the_part_on_the_skin` passes for it. |

Guard test: `tests/test_creature_parts.gd` `test_every_handle_at_full_keeps_the_part_on_the_skin` sets every handle of
every cpart_ to 1000 (imported blend shapes hold absolute positions) and checks that the part still reaches below
the skin, that the vertices sunk deeper than half the sink depth stay under it, and that a ground part still reaches
its sole.

## cpart_ear_round, revision 5 (IMPLEMENTED)

Change: the rim crease and the rim facets. The front of the flap now eases into the helix with zero slope at both ends
(from rho 0.72 out to the rim; it was a squared ramp from 0.82), a shallow scapha groove (0.6 mm under the fat helix)
keeps the helix reading as a rolled ridge, and the roll is a cubic Hermite per meridian that leaves the front rim and
meets the back rim along their own slopes. Before, the roll was a semicircle that started flat, so it met the front
at a 50 to 70 degree bend all the way round, which shaded as a line inside the rim. The largest turn between
neighbouring rows near the rim is now 26 degrees, the same as the bowl's and antihelix's own turns. For the facets,
`_bake` takes an optional `accept` per object (passed to `surfacing.reduce`). The ear's test keeps the three outermost
roll rows within 0.13 mm and the rest of the rim within 0.26 mm of the high mesh; the interior keeps 0.3 mm. At 0.3 mm
everywhere the outline was a 28-gon with sides up to 14 mm. Triangles 1070 of 1200 (was 770). Dimensions
(0.056 x 0.034 x 0.065 m), pivot, sink, footprint, handles (H1_Perk, H2_Size), sockets (none) and materials are
unchanged.

| Gate | Status | Observation |
| --- | --- | --- |
| 1 shape | pass | Blender gray front, side and three-quarter and the head-sphere front, three-quarter and side (`tools/ear_round_shots.gd`): a smooth oval outline with no straight runs or lumps and no dark line inside the rim; the rolled helix, scapha, antihelix round the bowl, tragus and notch read. Before: a lumpy outline, a kink at the top of the notch side and a crease line along the inside of the top rim. |
| 2 materials | pass (unchanged) | Pink pored skin on the front and the front half of the roll, brown grained fur behind, split at the roll's apex (Blender material views and Godot). |
| 3 lighting | pass | Neutral Blender review light, the neutral Godot capture and the head-sphere light; no bloom. |
| 4 Godot | pass | Imported; on the monkey preset in the editor scene at the world's gameplay distance it reads as a round ear on the side of the head; close up the outline stays smooth at rest and with H1_Perk and H2_Size at 1000. |

Evidence: `ear_round_head_before_after.jpg` (head sphere, top before, bottom after), `ear_round_gray_before_after.jpg`
and `ear_round_monkey_before_after_perk.jpg` (monkey close: before, after, after with both handles at 1000).

## cpart_eye_bulge, revision 5 (IMPLEMENTED)

Cause of the cream band, confirmed before rebuilding: on the hopper preset close up in the editor scene,
`tools/godot/part_on_body_shot.gd --mark=eye_bulge:M_EyeBulgeLid:#ff2020,eye_bulge:M_EyeBulgeMound:#2040ff` paints the
lid band red and the mound blue. The pale ring is exactly the red lid band: the eight rows from `low` up to the lip
make a wide, near-flat ledge round the ball in a lighter tint (#79A458) at a flat 0.8 grey, so in the editor's key
light it reads as a pale cream-green ring between the iris and the mound. The back of the lip, which the scout
suspected (seen through a 1.6 mm gap), shows in Blender as a dark ring, not as the band. The same frames showed the
skirt below the skin as a straight cylinder, so on the hopper's rounded head the mound stood off as a wall with a hard
corner, and the 24-segment ball outline was visibly faceted.

Change: the lid takes the mound's tint (#6E9A4E) at a flat 0.72 grey, a little darker than the mound's mottle, so it
reads as skin folding round the ball. Six lid rows hug the ball up to a rounded lip at 1.08 ball radii, and one last
row tucks the lip's edge inside the ball (0.972 radii), so there is no gap and no back face to see. The skirt below
the skin tucks in under the widest ring at the skin line, so the mound's edge curves into a rounded head. There are 32
segments round (was 24) and six iris rows (was four). H1_Blink closes the same round dome; H2_Bulge now stretches only
the ball above the lip (the top still rises a third of a radius), so it never pulls away from the lid. Triangles: 1152
of 1200 (was 960). Dimensions (0.13 x 0.13 x 0.11 m), footprint, sink, pivot, handle keys, sockets (none) and material
names are unchanged; `game/data/creature/part_rules.json` is unchanged. `_eye_ball` and `_wet_skin_material` gained optional parameters
whose defaults keep every other part's output.

| Gate | Status | Observation |
| --- | --- | --- |
| 1 shape | pass | Blender gray front, side and three-quarter: the ball sits in one rounded mound, the lid hugs it to a rounded lip with no gap (before: a black ring between ball and lip), and the skirt tapers under the skin. Godot captures: H1_Blink 500 rolls a clean green lid over the lower ball; 1000 closes a round dome with no pinhole; H2_Bulge 1000 shows no gap at the lid. Remaining: the ball's top outline still shows mild facets close up (rows 19 degrees apart, was 29); one more row would go over the budget. |
| 2 materials | pass | Glossy bronze iris with the slit pupil; the lid an even green band in the mound's colour (no pale ring); the mound mottled wet skin (Blender material views, the baked albedo, Godot). |
| 3 lighting | pass | Neutral Blender review light and the neutral Godot capture; no bloom. |
| 4 Godot | pass | Imported; on the hopper preset in the editor view, at the world's gameplay distance and close, the pale ledge is gone and the mound's edge curves into the head in shadow; blinked shut, it is a round green dome. |

Still open, outside this part: the mound stands off the hopper's narrow head as a rounded collar (scale 1300 on a
strongly curved head), and parts keep their baked colours, so the mound is a lighter green than the hopper's body.
`paint_mix` is not read by game code, so matching the body colour would be a `creature_look` change, which other
agents own.

Evidence: `eye_bulge_band_cause_marked.jpg` (the hopper close up, plain and with the lid red and the mound blue),
`eye_bulge_hopper_before_after.jpg` (close and side, before left, after right),
`eye_bulge_editor_gameplay_before_after.jpg`, `eye_bulge_gray_before_after.jpg` (gray front and side, material
three-quarter) and `eye_bulge_blink_bulge_after.jpg` (Godot at rest, H1_Blink 500 and 1000, H2_Bulge 1000).

## cpart_muzzle_primate, revision 4 (IMPLEMENTED)

Cause: revision 3's snout was a superellipse plateau, a flat top 19 mm high from y -23 to -8 mm with steep steps at
both ends, and the brow ridge stood just as high (18.8 mm). Seen from the side (Blender gray, the plate stood up as on
a head) it read as two slabs with a slot between them, with the nose pad a flattened blob on the flat top.

Change: the snout follows a side profile (`MZ_PROFILE` in the generator, a clamped cubic spline over the face plane,
printed and checked before the build). At x = 0 it rises from the nose bridge between the eyes (y +2 mm, 7.8 mm high)
to a rounded nose tip (y -14 mm, 20 mm), rolls over the upper lip (y -20 mm, 18.7 mm) to a 1 mm crease at the mouth
line (y -25.5 mm, 15 mm), then a small rolled lower lip, a shallow groove and a chin pad, and recedes into the face
(y -36 mm, 8.8 mm). Across x it is a narrow 7 mm bridge widening to the squared 21.5 mm half width at the nose and
lips, with steep sides, so the front outline stays square. The brow is lower (10 mm, was 13.5 mm) and sits under the
nose tip. The nose pad is a leather oval laid over the nose tip along the snout's curve (0.9 mm proud, rim tucked
under) in the leather pad material (roughness 0.4); the old helper-name collision had given it the glossy frog-disc
material. Two tilted dark nostrils sit on it and the mouth line follows the crease. The eye hollows, nostrils and mouth
line now face out of the face; they were wound inward and showed only because the materials are double-sided.

Triangles: at the default 0.8 mm decimation the first build cut the nose pad to 8 triangles, so the pad and the dark
decals are authored at their final density and not decimated, and the snout is held within 0.45 mm by a fit test
(`_points_fit`, the same kind of test the round ear's rim uses). A no-export diagnostic gave the face 981 triangles at
0.3 mm, 401 at 0.45 mm and 299 at 0.6 mm (the same as no test); 0.45 mm fits the budget. The fur ruff is resampled
(41 points and 6 sides, was 49 and 7). 1095 of 1200 triangles (was 1151). Dimensions 0.09 x 0.103 x 0.029 m (was 0.089
x 0.102 x 0.03); the footprint is 0.056 m (was 0.055, from the resampled ruff; no game code reads it). Sink, pivot, the
eye sockets (x +-15.5 mm, y +9 mm, same depth), handle keys (H1_Snout now moves the whole snout with its own mask,
H2_Brow is unchanged), sockets (none) and material names are unchanged.

| Gate | Status | Observation |
| --- | --- | --- |
| 1 shape | pass | Blender gray front, side, three-quarter and low three-quarter, stood up (`tools/blender/render_part_review.py --stand`): the side outline runs from the brow ridge into a dip at the bridge, out along the snout to a rounded nose tip, over the upper lip into the mouth crease and back past a small lower lip and chin (before: a flat-topped block with a vertical front, as high as the brow). Front: a squared muzzle, an oval nose pad, a curved mouth line. H1_Snout 1000 pushes the whole snout out keeping its profile; H2_Brow 1000 makes the brow heavier. Remaining: a few flat facets on the snout's lower sides in grazing light. |
| 2 materials | pass | Blender material views: a dark leather nose pad with two darker nostrils, pale pored skin, the dark mouth line and eye hollows, the brown fur ruff; the same pieces read apart in Godot. |
| 3 lighting | pass | Neutral Blender review light and the neutral Godot capture; no bloom. |
| 4 Godot | pass | Imported; captured front and side. On the monkey preset in the editor scene it reads at gameplay distance as the grey snout under the eyes; close up the rounded snout and oval nose pad replace the box and nose block. The preset places the plate low on the head facing forward and down, so the editor shows the profile mostly from below (placement, not the part). |

Evidence: `muzzle_primate_gray_before_after.jpg` (gray front, side, three-quarter and material three-quarter, before
on top), `muzzle_primate_side_before_after.jpg` (side, before gray, after gray, after material),
`muzzle_primate_handles_after.jpg` (rest, H1_Snout 1000, H2_Brow 1000 material, H1_Snout 1000 side) and
`muzzle_primate_monkey_before_after.jpg` (the monkey preset close and side, before left).

## Known issues

- `cpart_foot_frog` H2_Long at 1000 reaches about 0.119 m against the recorded footprint of 0.098 m (scout's
  measure; other `_foot_handles` feet may do the same). Left as is: the footprint semantics in `part_rules` do not
  change in this job.
- The frog feet of the hopper preset sit under the editor's floor pad (the anchor resolver and the editor's rig
  offset, not the part); in the world the walker plants them.
- A bare face (fur thinning near the head) is acceptable (PROPOSED).
- On the monkey preset the muzzle plate sits low on the head facing forward and down, so its side profile is seen
  mostly from below in the editor (the preset and the anchor resolver, which other agents own).
