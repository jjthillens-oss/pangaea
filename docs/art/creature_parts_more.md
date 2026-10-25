# More creature parts (more-parts)

Twenty new creature parts, so players can build many more animal types. All of it is PROPOSED art and data, and it
waits for the owner's look review. Each part ships as an editable `.blend`, a GLB and an `assets/records/cpart_<id>.json`
record with a role. It reaches the editor through data only: `python3 tools/make_part_rules.py` copies each record's
`part_rules` into `game/data/creature/part_rules.json`, and the editor's palette and tabs read that file.

Owner request (CONFIRMED, verbatim): "20 more creature parts so players can build many animal types (beaks, trunks,
antlers, shells, tails of several kinds, webbed and padded feet, more eyes and mouths, manes, crests). Each part gets
a cpart_ record with a role, then regenerate part_rules.json with tools/make_part_rules.py."

## Tools

| File | What it does |
| --- | --- |
| `tools/blender/make_more_creature_parts.py` | Builds the 20 parts. It imports the helpers of `tools/blender/make_creature_parts.py` and never edits that file; the helpers defined there twice (`_smooth`, `_pad_material`, `_fur_material`) are copied here with an `_mp` prefix. Run: `python3 tools/blender/make_more_creature_parts.py [--only cpart_<id>[,...]]`, then `godot --headless --path . --import` and `python3 tools/make_part_rules.py`. |
| `tools/blender/render_more_parts_gates.py` | Gate 1-3 renders of one exported GLB: gray front, side, back, three-quarter and top views and one per handle under a neutral white rig with a grazing light; material three-quarter, side and close-up under the same rig; the art look under `lookdev.review_lighting`; and a labelled contact sheet. Run: `python3 tools/blender/render_more_parts_gates.py cpart_<id> <out_dir>`. |
| `tools/godot/more_parts_shots.gd` | Gate 4 frames in the real creature editor: `--mode=palette` saves one frame per palette tab; `--mode=creatures` opens presets (or a `--showcase` JSON of presets plus parts) and saves, with the HUD and handles hidden, the world camera's distance and pitch from behind (`_game`) and the front (`_front`), a head close-up (`_close`) and a level head profile (`_side`). |

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

## Issues

(Links added when the issues are opened.)
