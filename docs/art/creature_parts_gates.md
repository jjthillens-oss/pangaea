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
  (gray_ and mat_ front, side, threequarter, top; `--shape` poses a handle).
- Godot part views: `tools/godot/capture_part.gd -- <glb> <out dir> [--handles=Key:permille] [--fit] [--mirror]
  [--views=front,side]` (neutral sky colour, one sun, a ground plane at the pivot).
- On a real body: `tools/godot/part_on_body_shot.gd -- --preset=<name> --focus=<part type>` builds the preset in the
  creature editor scene (`game/scenes/creature/creature_editor.tscn`, driven through `setup()`), with the preset's
  colour, pattern and covering. Views: `editor` (the editor's own camera and HUD), `gameplay` (the creature world's
  camera distance, 2.4 x the body length, 2.6 to 12 m, fov 50, from the front three-quarter), `close` and `side` (on
  the part).
- The round ear's head-sphere shots: `tools/ear_round_shots.gd`. The fur fixture: `tools/covering_shots.gd --only=fur`.
- All Godot frames are the Compatibility renderer under Xvfb (it overexposes a shadowed sun, `docs/TOOLCHAIN.md`).
- Evidence (before and after pairs) is in `docs/evidence/credit-creature-parts/`.

## Before (main at 2ffc1218): what the frames show

| Part | Open review item | Seen in the before frames |
| --- | --- | --- |
| cpart_foot_frog (rev 5) | ankle and heel | Gray front and three-quarter: the ankle is a straight tube with a flat top and a crease ring where it enters the sole; the heel is a separate lump behind it. On the hopper in the editor the frog feet sit under the floor pad (placement, not the part); `--no-floor` shows them. |
| cpart_hand_frog (rev 2) | (finish) | Gray: faceted round toe discs, a flat-ended wrist stub. |
| cpart_eye_bulge (rev 4) | cream band | Godot close: a faceted iris ball and a thin dark line at the lid lip; no cream band shows under the neutral capture light, so the band needs the body frames in the editor's light to confirm. |
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

## Known issues

- `cpart_foot_frog` H2_Long at 1000 reaches about 0.119 m against the recorded footprint of 0.098 m (scout's
  measure; other `_foot_handles` feet may do the same). Left as is: the footprint semantics in `part_rules` do not
  change in this job.
- The frog feet of the hopper preset sit under the editor's floor pad (the anchor resolver and the editor's rig
  offset, not the part); in the world the walker plants them.
- A bare face (fur thinning near the head) is acceptable (PROPOSED).
