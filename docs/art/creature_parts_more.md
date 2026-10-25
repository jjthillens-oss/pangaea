# More creature parts (more-parts)

Twenty new creature parts, so players can build many more animal types. All of it is PROPOSED art and data, and it
waits for the owner's look review. Each part ships as an editable Blender source in `assets/source/blender/`, a GLB in
`assets/export/` and a `cpart_` record with a role in `assets/records/`. It reaches the editor through data only: `python3 tools/make_part_rules.py` copies each record's
`part_rules` into `game/data/creature/part_rules.json`, and the editor's palette and tabs read that file.

Owner request (CONFIRMED, verbatim): "20 more creature parts so players can build many animal types (beaks, trunks,
antlers, shells, tails of several kinds, webbed and padded feet, more eyes and mouths, manes, crests). Each part gets
a cpart_ record with a role, then regenerate part_rules.json with tools/make_part_rules.py."

## Tools

| File | What it does |
| --- | --- |
| `tools/blender/make_more_creature_parts.py` | Builds the 20 parts. It imports the helpers of `tools/blender/make_creature_parts.py` and never edits that file; the helpers defined there twice (`_smooth`, `_pad_material`, `_fur_material`) are copied here with an `_mp` prefix. Run: `python3 tools/blender/make_more_creature_parts.py [--only cpart_<id>[,...]]`, then `godot --headless --path . --import` and `python3 tools/make_part_rules.py`. |
| `tools/blender/render_more_parts_gates.py` | Gate 1-3 renders of one exported GLB: gray front, side, back, three-quarter and top views and one per handle under a neutral white rig with a grazing light; material three-quarter, side and close-up under the same rig; the art look under `lookdev.review_lighting`; and a labelled contact sheet. Run: `python3 tools/blender/render_more_parts_gates.py cpart_<id> <out_dir>`. |
| `tools/godot/more_parts_shots.gd` | Gate 4 frames in the real creature editor: `--mode=palette` saves one frame per palette tab; `--mode=creatures` opens presets (or a `--showcase` JSON of presets plus parts, with an optional `swap` of part types done in memory only) and saves, with the HUD and handles hidden, the world camera's distance and pitch from behind (`_game`) and the front (`_front`), a head close-up (`_close`) and a level head profile (`_side`). |

The handle views set each `H<n>_` key on every mesh of the part at once, as the runtime does (a part such as the
hooked beak keeps its lower mandible in a child mesh with the same key names). Gate notes live in the generator's
`REVIEW` table; `python3 tools/blender/make_more_creature_parts.py --notes-only --only <ids>` copies them into the
records without rebuilding the meshes.

## The twenty parts and their roles

The role decides what a part does in play today (IMPLEMENTED in `game/domain/creature/creature_stats.gd` and
`game/ui/creature_editor_hud.gd`; the values below are PROPOSED for these parts). Each part takes the existing role
whose gameplay effect best fits its anatomy, following the Bible's section 12 table (Anatomy and evolution model).
No defensive, swimming or grasping role exists yet, so shells, the paddle tail and the curling tail take `detail`
and the per-kind effects are proposed in a GitHub issue (linked below).

| Id | Animal feature | Role | Bible section 12 row | Effect today (from the role) | Palette tab |
| --- | --- | --- | --- | --- | --- |
| beak_hooked | raptor's hooked beak | mouth | Mouth and feeding apparatus | bite +5 x scale, reach | Mouths |
| beak_long | long probing bill (ibis, kiwi) | mouth | Mouth and feeding apparatus | bite, reach | Mouths |
| trunk | elephant trunk; capability `grasper` | mouth | Mouth and feeding apparatus (reach); Grasping structures | bite, reach | Mouths |
| trunk_short | tapir's short mobile snout | mouth | Mouth and feeding apparatus | bite, reach | Mouths |
| mouth_sucker | lamprey or leech sucker disc | mouth | Mouth and feeding apparatus | bite, reach | Mouths |
| mouth_fangs | fanged snake or sabre jaw | mouth | Mouth and feeding apparatus | bite, reach | Mouths |
| eye_turret | chameleon turret eye | eye | Eyes and sensory organs | sight +3 m | Senses |
| eye_lashed | big lashed mammal eye | eye | Eyes and sensory organs | sight +3 m | Senses |
| foot_otter | webbed and padded foot | foot | Legs and feet | none yet | Limbs |
| foot_pillar | padded pillar foot (elephant) | foot | Legs and feet | none yet | Limbs |
| antler_branched | deer antler | weapon | Armor and spines (deterrence) | attack +2 x scale with a mouth | Weapons |
| antler_palmate | moose antler | weapon | Armor and spines (deterrence) | attack | Weapons |
| tail_stinger | scorpion stinger tail | weapon | Armor and spines | attack | Weapons |
| tail_feather | display tail fan | detail | Communication organs (display) | charm +0.5 | Details |
| tail_paddle | beaver paddle tail | detail | Fins and tails (no swim role yet) | charm | Details |
| tail_curl | prehensile curling tail; capability `grasper` | detail | Grasping structures (no grasp effect yet) | charm | Details |
| shell_dome | tortoise carapace | detail | Armor and spines (no defensive role yet; weapon would add attack) | charm | Details |
| shell_spiral | snail coil shell | detail | Armor and spines (no defensive role yet) | charm | Details |
| mane_ridge | upright neck mane (horse, zebra) | detail | Communication organs (display) | charm | Details |
| crest_feather | feather head plume | detail | Communication organs (display) | charm | Details |

Prices: `game/data/creature/editor_costs.json` is not changed by this job, so every new part costs the default
`part_default` (10 points). Per-kind prices and effects are proposed in the issue.

## Before frames and the mouth and eye orientation check

Frames from `tools/godot/more_parts_shots.gd --set=before` on main 2ffc1218, in `docs/evidence/credit-more-parts/`:
`before_palette_<tab>.jpg` (the six palette tabs on the quadruped starter) and `before_<preset>.jpg` (each preset
at the world camera's distance from behind, top left; from the front, top right; nearer, bottom left; and a level
profile of the head, bottom right).

Finding (observed in the frames; the cause read in the code): **mouths and eyes on a `forward_cone` placement point
up, not forward.** This was already true on main before this job.
- `before_tortoise.jpg`, `before_longneck.jpg` and `before_strider.jpg` (head profile): the beak rises from the snout tip
  at roughly 50 to 70 degrees above the look direction and reads as a nose horn, not a beak.
- `before_raptor.jpg`: the jaw stands straight up from the snout tip like a post.
- `before_tortoise.jpg` and `before_angler.jpg`: the generic eye's lid opening and pupil face the sky.
- Cause: `AnchorResolver._cone_frame` (`game/domain/creature/anchor_resolver.gd`) returns a basis whose local -Z is the
  look direction and local +Y is body up. The mouth and eye models are authored with their outward axis on Blender +Z,
  which is Godot +Y, so that axis is mapped to body up.

What this job does about it: the new mouths and eyes are authored in the same convention as the existing ones (outward
axis on Blender +Z, upper side on +Y), so a single later fix to the frame by the creature-code owners corrects every
mouth and eye together. Mixing conventions would leave half the parts wrong whichever way the fix went. The problem
is reported in a GitHub issue (linked under Issues). This job does not edit creature code.

## Gate report

One row per part, filled in as each part is built and reviewed (pass, needs revision or unverified, with the
observation behind it). The same notes are in each record's `review_notes`.

| Id | Gate 1 shape | Gate 2 materials | Gate 3 neutral light | Gate 4 Godot, on a body | Triangles / budget |
| --- | --- | --- | --- | --- | --- |
| beak_hooked | pass: deep keeled upper mandible arcing into a pointed hook over a shorter lower one; cere a clean raised band | pass: slate horn darkening to a near-black hook, saturated yellow cere with a nostril each side | pass: no clipping, hook underside readable | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 1152 / 1200 |
| beak_long | pass: slender decurved bill, rounded probe tip, gape bulge; upper overhangs lower by about 1 cm | pass: orange streaked horn with seam and nostril-groove lines, pink gape | pass: highlight along the culmen, lines stay visible | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 342 / 1200 |
| trunk | pass: tapering S-curve hanging and turning forward, flatter underneath, two-fingered grip pad | pass: cool grey ring-wrinkled crackled skin against a warm-brown pebbled pad with two nostrils | pass: grazing light shows the rings, pad readable | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 2303 / 2500 |
| trunk_short | pass: broad snout tapering and drooping over a tucked lower lip; domed oval nose pad with two flared nostril lobes | pass: fine grey folded skin against a near-black glossy nose pad with dark nostrils | pass: folds and gloss read, mouth crease shadowed | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 964 / 1200 |
| mouth_sucker | pass: trumpet funnel flaring to a fleshy bead lip in ten soft scallops; a dished disc with three distinct rings of small teeth (16, 12, 8) hooking in toward a round throat | pass: wet sea-green lip with ring wrinkles and papillae, low-chroma plum disc darkening down the throat, amber teeth; clean lip-to-disc line | pass: bead highlight, teeth bright on the dark disc, throat dark but not crushed | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 1126 / 1200 |
| mouth_fangs | pass: wide low lipped snout resting a little open; face-on a lens of a mouth with two long fangs in front of the chin, curving back, and a forked tongue between the lips | pass: teal domed snake scales (slightly larger, paler plates along the mouth line, faint in the gap's shade), ivory fangs, dark plum mouth and tongue | pass: scale domes catch soft highlights, fangs bright without clipping | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 909 / 1200 |
| eye_turret | pass: smooth slightly convex cone 8.4 cm across, round aperture at the tip with the ball just inside; blink puckers it shut, reach stretches it | pass: turquoise granular tubercles in concentric ring bands; a gold iris ring round a black pupil inside the aperture | pass: ring bands read by grazing light, gold ring visible in the shadowed aperture | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 668 / 1200 |
| eye_lashed | pass: big ball set in the skin, seen through an almond opening in one smooth lid ring (heavy rolled upper lid, thin lower lid); seven bold flat lashes reach forward off the upper margin and flick up | pass: glossy white sclera, chestnut iris with fibres and a big black pupil, soft warm lid skin, near-black glossy lashes | pass: highlight on the iris, lid roll reads, lashes dark without crushing | needs revision: points up (shared forward_cone frame); reads right with the fix previewed | 987 / 1200 |

Gate 4 (beaks and trunks): `tools/godot/more_parts_shots.gd --mode=creatures --showcase=<json>` with each new
mouth swapped in memory for a preset's mouth (tortoise beak to beak_hooked, strider beak to beak_long, longneck beak
to trunk, boar maw to trunk_short). The `after_<preset>_<part>.jpg` frames in `docs/evidence/credit-more-parts/` (top
left: world camera distance from behind; top right: from the front; bottom left: nearer; bottom right: level head
profile) show all four load, seat on the snout tip without floating or deep clipping, keep their materials and sit in
scale with the head, but point up out of the snout like every existing mouth: the forward_cone frame finding above.
The `conefix_<preset>_<part>.jpg` frames add `--cone-fix-preview`, a review-only turn of each forward_cone part on the
rig (no game code changes) to the frame the orientation issue proposes: there the hooked beak points forward with its
hook down, the long bill reaches forward and curves down, the trunk comes forward and hangs, and the tapir snout juts
forward and droops, each reading as its animal feature at the world camera's distance. The eyes on those heads turn
to face forward too. The Gates 1-3 contact sheets are `gates_<part>.jpg` there as well.

Iterations that the sheets caught (Gate 1 needs revision, then fixed): the first hooked beak splayed its mandibles
apart with a V gap and read as a horn, with a sawtooth cere edge and a second nostril pair mirrored onto the lower
jaw; the first long bill's nostril groove did not survive decimation and was not visible; the first tapir snout's lip
floated free of the snout and its round nose pad stuck out of the oval tube in a ragged crown.

Gate 4 (mouths and eyes): the same tool with a `--showcase` JSON whose swaps are done in memory only: the angler's maw to mouth_sucker, the stalker's mandibles to mouth_fangs and its eye stalks to
eye_turret (at the preset's scale 1400), the prowler's slit eyes to eye_lashed. The `after_<preset>_<part>.jpg` frames
show all four load, seat on the body without floating or deep clipping, keep their materials and sit in scale, but
face up like every existing mouth and eye (the forward_cone finding above). With `--cone-fix-preview`
(`conefix_<preset>_<part>.jpg`) the lamprey funnel juts forward with its toothed disc facing ahead, the snake mouth's
fangs hang in front of the chin with the forked tongue out, the chameleon turrets point forward with gold-ringed
pupils, and the lashed eye looks forward under its heavy lid with the dark lash fringe on top. At the world camera's
distance the lashed eye and the turrets still read; the fangs on the spider-like stalker are only a few pixels and
partly behind its forelegs, and read in the close view.

Iterations that the sheets caught for the mouths and eyes (Gate 1 or 2 needs revision, then fixed): the first
lamprey disc had a sharp zigzag crown of a rim on a thin cup wall, then a single mesh whose lip-to-disc material
border decimated into a sawtooth (the disc is now its own mesh tucked under the bead); the first snake jaws were
icosphere ellipsoids at 1518 triangles (now lathed domes with rings crowded at the lip edge) and its first scale
shader read as cracked mud; the first chameleon turret read as a beehive dome whose geometric ridges decimated into
irregular terraces round a hexagonal aperture (the ridges are now in the normal map and the cone is decimated at a
tighter 0.3 mm tolerance); the first lashed eye wrapped two thin lid shells round the whole ball, read as a cracked
eggshell with spidery lashes and was 1588 triangles, and the second still creased where its two lids met and curled
its lashes back over the lid like claws (it is now one lid ring round an almond opening, sunk into the skin behind,
with bold lashes that reach forward and flick up).

## Issues

(Links added when the issues are opened.)
