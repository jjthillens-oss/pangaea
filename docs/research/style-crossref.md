# Style cross-reference: does Pangaea feel like Spore, twenty years later?

Status: research brief, PROPOSED. Written 2026-10-25 for the owner's direction of that day:

> "Cross-reference our styles in game, which look very Spore-like right now. Make sure that this entire
> Pangaea feels like Spore. A modern-day version, twenty years later, better graphics and whatnot, but not
> much better. We want that nostalgia, the core nostalgic feeling that you're playing your childhood dream."

The brief answers three questions per stage: what already carries the feeling (keep), where the build has
drifted from it (drift), and what to do about each drift (fix). Section 6 turns the fixes into checkable
rules for `docs/director/rubrics/visual.md`, so every art and UI review tests for the feeling and not only
for finish.

Legal line (`docs/research/spore/LEGAL_RESEARCH_BOUNDARIES.md`): Spore is a mood reference. This brief
describes a feeling in words and compares our own frames against those words. No Spore shape, palette,
icon, name, font, sound or UI layout is copied, and none of the fixes ask for one.

## 1. Method

Evidence on our side: the shared screenshot folders (`/mnt/project-files/pangaea/screenshots/`:
`micro-world`, `m1-production-art`, `aquatic`, `creature-stage`, `creature-world`, `creature-parts`,
`endless-world`, `menus-modern`, `menus-ui`), `docs/art/ART_DIRECTION.md` (the CONFIRMED look "Soft life
hardens" with its palette, shape language and camera), the audio records in `assets/records/audio/` and
DECISIONS entries on the soundtrack, and the stages as they run in the current builds.

Evidence on Spore's side: the Steam store page (its tags are *Colorful*, *Cartoony* and *Cute*, its
promise is "from single cell to galactic god" and "survival of the funnest"), the playthrough notes in
`docs/research/spore/PLAYTHROUGH_VIDEO_NOTES.md`, and the community and mod research in
`community-wants.md` and `mod-wishes.md` (what players remember and what they asked for more of).

Each stage is scored on nine style axes. The axes are the coordinator's list: shapes, palette, saturation,
lighting, materials, UI, camera, animation charm and audio mood. "Keep" means the current build already
carries the feeling on that axis. "Drift" means it does not, with the frame that shows it. "Fix" is the
smallest change that would bring it back, labelled by who owns it.

## 2. What the Spore feeling is made of (mood words only)

This is the target, written so it can be checked without ever looking at a Spore asset again.

| Ingredient | In words |
| --- | --- |
| **Toy-like forms** | Everything is rounded, chunky and a little squashy. Creatures look like they could be picked up. Hard edges are rare and mean something (teeth, spikes, tools). |
| **Big eyes, readable faces** | The face is the first thing you see. Eyes are large, lidded and pointed at something. Mood reads at gameplay distance. |
| **Colourful but soft** | The world is saturated and cheerful, but never neon. Habitats are coloured, not grey. Creatures are a notch more saturated than the ground they stand on. Food and danger are the only things allowed to glow. |
| **Painted, not photographic** | Surfaces look painted or moulded. No photo noise, no grey PBR realism. Detail comes from pattern and shape, not from texture grain. |
| **Warm, friendly light** | Days are sunny with blue-tinted shadows; nights stay readable. The light flatters the creature. |
| **A playful, chunky UI** | Buttons and cards are rounded and a little oversized. One progress bar per stage, one currency. The editor is the reward: parts on the left, the creature on a plinth, a test-drive button. |
| **A camera that shows scale** | Each stage is a visible jump in scale. The camera sits close enough to see the face and far enough to see the world. |
| **Charm in motion** | Idle wobble, squash on landing, a wiggle when eating, a dance that is a little silly. Animation sells personality more than detail does. |
| **Gentle, curious music** | Ambient, melodic, slightly wondrous. Danger adds urgency without dropping the warmth. Sound effects are wet, soft and funny. |

The one-line test for a reviewer: *would an adult who played the original at ten look at this frame and
smile before they analyse it?* If the answer needs explanation, the frame is drifting.

## 3. Cross-stage verdict

Overall the build sits on the right side of the line. The microscopic stage, the title and the editors
already carry the feeling. The two 3D world stages (aquatic slice and creature field) carry the palette but
not yet the warmth, density or charm; they currently read as clean engineering test beds rather than a
toybox world. Nothing points in the wrong direction (no grey realism, no neon, no photo noise), so the fixes
are additive: dressing, light, motion and a little saturation, not a restyle.

| Stage | Shapes | Palette | Saturation | Lighting | Materials | UI | Camera | Animation | Audio | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Title and menus | keep | keep | keep | keep | n/a | keep | n/a | drift (static) | keep | keep |
| Microscopic (cell) | keep | keep | keep | keep | keep | keep | keep | keep | keep | **keep** |
| Aquatic (sea) | drift | keep | drift (low) | drift (flat) | drift | keep | keep | drift | keep | **drift** |
| Terrestrial (creature) | keep (bodies) / drift (world) | drift | drift (washed) | drift (flat) | drift (ground) | keep | keep | drift | n/a yet | **drift** |
| Editors | keep | keep | keep | keep | keep | keep | keep | drift (no idle) | keep | keep |
| HUD | keep | keep | keep | n/a | n/a | keep (modern glass) | n/a | n/a | n/a | keep, watch |

## 4. Per-stage keep, drift, fix

### 4.1 Title and menus (`menus-modern/title_after.png`, `menus-ui/menus_sheet.jpg`)

**Keep.** The deep-blue, bokeh-lit title with a single calm tagline ("Life starts small.") and the lineage
card showing the player's own creature is exactly the feeling: your creature greets you. The rounded glass
buttons, the yellow focus ring and the large, friendly type read as a toy, not as a tool. Settings tabs are
clear and never cluttered. The soundtrack (calm instrumentals chosen after the owner asked for "beautiful
instrumentals", DECISIONS 2026-10-23) fits.

**Drift.** The title creature is still. In the memory of the original, the thing on the title screen breathes.
Settings and save-slot screens are fine but slightly flat (same card, same weight everywhere).

**Fix.** Art and UI (small): give the title and slot-card creature its idle (breathe, blink, a slow turn) and
let the bokeh drift. Keep everything else.

### 4.2 Microscopic stage (`micro-world/micro_ingame_preview.jpg`, `m1-production-art/pool_*_godot.jpg`)

**Keep.** This is the stage that most earns the feeling today. The deep, saturated blue fluid, the coral
player cell with huge lidded eyes, glassy shells, drifting specks, a few glowing foods and pink-tipped threats
all sit inside section 2. The HUD is one bar and one counter. The hunter and grazer bodies are pebble-petal-
bead shapes with a clear front. Music is calm and wondrous, danger fades in and out. The camera is top-down
and close.

**Drift.** Minor only. Some in-engine frames (`pool_hunter_godot.jpg`) show a very empty mid-ground: a single
cell on a wide, uniform green-grey plane with two rocks. The ambience layers (PR #10 drift layers) fix most of
this where they are mounted; frames taken without them look like a lab dish. The green-grey floor tint in
those frames is the one place where the habitat reads grey rather than coloured.

**Fix.** Engineering and art (small): make the ambience scene part of every review capture so the empty
frame never reaches review; keep the floor tint inside the palette's shallow turquoise or moss band rather
than a desaturated grey-green. No shape or palette change.

### 4.3 Aquatic stage (`aquatic/aquatic_slice_sheet.jpg`, `aquatic/7_shore_offer.png`)

**Keep.** The cyan-to-blue water gradient, the white sand, the soft fog and the lobe-finned player with its
lidded eyes are on palette. Food is green and glowing, the nest is a readable sand ring, and the shore offer
card is friendly and well written. HUD is one bar per need plus a depth line.

**Drift.**
- *Density and warmth.* The sea is a near-empty white plane with a sand path and a few stick fragments. The
  feeling wants a reef: coloured growth, swaying things, fish in the distance, light rays. Today it reads as
  an underwater car park at noon.
- *Saturation.* The frame is about 70% white-cyan; the eye has nothing warm to rest on. Section 2 wants the
  creature a notch more saturated than the world, which fails here because the world is so bright that the
  blue creature nearly vanishes against it (`7_shore_offer.png`).
- *Lighting.* Flat ambient; no caustics or beams, so there is no "sunlit shallows" at all despite the label.
- *Shapes and motion.* Food discs are the same disc at every size; the player's swim is a glide without the
  body wave that sells "fish".

**Fix.** Art (medium, inside the M4.5 reef spike proposed in `docs/bible/addendum-aquatic-path.md`): a reef
dressing set (soft corals, fans, weed clumps, two kinds of pebble fish) in the algae-green, moss, amber and
coral palette rows; a sun shaft or caustic pass tied to depth; a sand albedo two notches darker and warmer so
the player reads against it. Engineering (small): a sinusoidal body wave on the swim cycle and a small bob on
idle. All of it stays within the addendum's "bounded, not doubled" scope.

### 4.4 Terrestrial stage (`creature-stage/world_pickup_near.png`, `creature-world/forwardplus_field.png`, `creature-parts/cpart_lineup.jpg`, `endless-world/creature_skin_v1_all.jpg`)

**Keep.** The part lineup is the strongest nostalgic hit in the whole project. Every part is rounded,
chunky and slightly comic (the hand, the hoof, the maw, the lure); the eye is big with a lid; nothing is
sharp except spikes and quills. The skin concepts carry pattern over a soft gradient, painted rather than
photographic. The creature HUD (one energy bar, adaptation-point counter, a "Fed" chip) is minimal and warm.
The camera pitch and distance show face and world together.

**Drift.**
- *Ground.* The field is a flat turquoise-and-tan blob pattern that reads as a fabric swatch
  (`forwardplus_field.png`). It has no grass height, no edge variety, no warm undertone. Saturation is low and
  value is high, so the ground reads "washed" (section 2 wants coloured, not grey or chalky).
- *Density.* A handful of bushes and one nest ring on an open plain. The feeling wants a layered world:
  ground cover, mid-size plants, a few large landmarks, a horizon with something on it.
- *Lighting.* A single sun without a warm key tint; shadows are present but the frame lacks a time of day.
  The sky is a plain gradient.
- *Materials.* Terrain is a tiled noise; it is neither painted nor moulded.
- *Motion.* Pickups are marked by a vertical light beam (`world_pickup_near.png`), which is a modern shooter
  cue, not a toybox one. The creature's idle and walk have no squash or wobble yet.

**Fix.**
- Art (medium): a ground kit in the moss, algae-green, amber and rust rows: a painted-look grass albedo with
  a warm undertone, patches that are irregular not blobby, a few flowering ground-cover meshes and two large
  landmark shapes (a leaning rock, a big round tree) so each nest has a view.
- Engineering (small): warm key light with blue fill and a sky gradient that goes warm at the horizon;
  a dusk and night profile that keeps the creature's silhouette at the rubric's contrast (the playthrough notes
  list washed-out nights as the original's weakest frames, so this is "better" without being "different").
- Design and art (small): replace the pickup light beam with a part-shaped, gently bobbing pickup and a soft
  ground ring. Add the squash on landing and the eat wiggle to the gait set (Bible §21 lids and squash).

### 4.5 Editors (`menus-modern/editor_after.png`, `aquatic/6_editor_lobe.png`)

**Keep.** Parts left, creature on a plinth, test-drive button, a glass panel over the stage: this is the
pattern the owner asked to keep (mechanics, not styling) and the styling is our own glass-and-yellow. The
editor feels like a reward room rather than a form.

**Drift.** The creature on the plinth is still; parts snap on without a sound or a wobble. The plinth room
background is the same deep blue in every era.

**Fix.** Engineering and audio (small): idle breathing on the plinth, a soft "plop" and squash when a part
lands, a happy blink when the test drive starts. Art (small, later): one plinth backdrop per era so the room
tells you where you are (jelly light, reef, meadow, campfire).

### 4.6 HUD (all stage frames)

**Keep.** One bar, one counter, a small status chip, controls hint at the bottom. Nothing you need is hidden.

**Watch.** The dark glass cards are the modern note the owner asked for ("better graphics, but not much
better"). They are fine as long as they stay rounded, warm-text and few. The aquatic HUD already has two bars
and two right-hand readouts; a third would tip it into a dashboard. The rubric rule in section 6 caps it.

### 4.7 Animation charm (cross-stage)

**Keep.** Lids before pupils and the eye-size rule are in ART_DIRECTION and the cell rig uses them.

**Drift.** Outside the cell stage there is almost no secondary motion: no idle wobble, no squash, no eat
wiggle, no dance yet. Spore's charm lived in those; a still creature in a flat field reads as a test scene.

**Fix.** Engineering (medium, one task): a shared "charm layer" of procedural secondary motion for every
rigged body (breathing scale, landing squash, eat wiggle, blink timer, a lean into turns), driven from the
sim's events. Ships once, benefits every era.

### 4.8 Audio mood (cross-stage)

**Keep.** Calm composed instrumentals with a danger layer that fades in and out, muffled under water, soft
wet effects. This is already the feeling and the owner approved the direction.

**Drift.** The creature stage has no stage-specific ambience yet (birds, wind, insects) and the editors are
silent apart from clicks. Music is the same playlist in every era, so era changes do not sound like a scale jump.

**Fix.** Audio (small, when the audio thread resumes): a land ambience bed, two or three part-snap and
test-drive sounds, and one new calm track reserved for the first creature-stage entry so the jump is heard.

### 4.9 Camera (cross-stage)

**Keep.** Top-down close in the pool, pitched three-quarter on land, a visible scale jump between them. The
rubric's gameplay camera (55 degrees, 45 degree FOV, 14 m) is a good default.

**Drift.** None that matters. One note: the aquatic camera sits low enough that the bright sand fills most of
the frame; raising the pitch a little or darkening the sand (4.3) solves the contrast problem either way.

## 5. What "better graphics, but not much better" means in practice

The owner's line sets a ceiling as well as a floor. The ceiling: no photoreal terrain, no screen-space
effects that make the frame look like a different genre, no cinematic colour grading, no hard-surface realism
on creatures. The floor: real lighting with tinted shadows, soft fog and depth, painted-quality textures,
secondary animation, a dressed world. Modern tools are spent on *more charm per frame*, not on fidelity. Two
rules follow:

1. A new effect is allowed when it makes a creature more readable or a world more alive. It is not allowed
   when its only argument is "it looks more realistic".
2. Any frame that could be mistaken for a survival or shooter game is over the ceiling, however polished.

## 6. Rules for `docs/director/rubrics/visual.md` (PROPOSED)

These are written to drop into the rubric as a new axis plus checklist. Thresholds are proposed; the owner
calibrates them in the Sunday review by adding verdicts to the reference frames.

**New axis: Nostalgia (the childhood-dream test).**

| 1 (fail) | 3 (acceptable) | 5 (benchmark) |
| --- | --- | --- |
| Reads as a tech demo, a survival game or a lab scene | A player of the original would recognise the kind of game at a glance | They would smile before they analyse it |

**Checklist (each item pass or fail; two fails on a frame send it back):**

1. **Toy forms.** Rounded, chunky silhouettes; hard edges only on spikes, teeth and tools. No bevelled
   hard-surface realism on living things.
2. **Face first.** Eyes 18 to 25% of body width, lidded, pointed at something. Mood readable at the gameplay
   camera.
3. **Coloured world.** No habitat surface below about 25% saturation except rock and sand, and none above the
   palette caps (habitat about 55%, creatures about 75%, food and threat only above that). Nothing in the
   frame reads grey or chalky.
4. **Creature over world.** The player creature is at least one saturation notch and 15 L\* away from the
   ground it stands on (the look probe's `cell_contrast` gate, applied to every stage).
5. **Painted, not photo.** No visible photo grain or tiling noise at the gameplay camera; detail is pattern
   and shape.
6. **Warm light, blue shadow.** Key light warm, shadows tinted blue, never black. Night and fog profiles keep
   rule 4.
7. **Dressed frame.** At the gameplay camera at least three layers are visible (ground cover, mid-size
   dressing, a landmark or horizon element), and the play plane stays clear.
8. **Charm in motion.** Every rigged body shows idle breathing and a blink; landing, eating and part
   placement each get a squash or wobble. A still creature in review video fails.
9. **One bar, one currency.** The HUD shows one progress bar and one currency per stage, plus at most two
   small status readouts. Cards stay rounded and few.
10. **Editor as reward.** Parts palette, plinth, test drive; the creature idles on the plinth; a part landing
    makes a sound and a wobble.
11. **Pickup language.** Interactive things are marked by shape, bob and a soft ground glow, never by a
    vertical light beam or a floating icon.
12. **Ceiling check.** No effect whose only justification is realism. If the frame could pass as a different
    genre, it fails.
13. **Audio match.** Where the review includes audio: calm melodic bed, a danger layer that keeps the warmth,
    wet and soft effects. Silence in an editor or a new stage is a fail.

**Reference frames to add to the rubric:** good, `micro-world/micro_ingame_preview.jpg`,
`creature-parts/cpart_lineup.jpg`, `menus-modern/title_after.png`, `menus-modern/editor_after.png`;
needs work, `creature-world/forwardplus_field.png` (rules 3, 7), `aquatic/7_shore_offer.png` (rules 4, 7),
`creature-stage/world_pickup_near.png` (rule 11), `m1-production-art/pool_hunter_godot.jpg` (rule 7 without
ambience).

## 7. Suggested backlog items (for `docs/director/backlog.json`, PROPOSED)

| Item | Stage | Tier | Size | From |
| --- | --- | --- | --- | --- |
| Charm layer: shared secondary motion for rigged bodies | all | agents (feel) | medium | 4.7 |
| Land ground kit and landmarks | terrestrial | looks (Sunday) | medium | 4.4 |
| Warm key, dusk and night profiles that keep contrast | terrestrial | agents | small | 4.4 |
| Pickup marker: shape, bob and ground ring | terrestrial | agents | small | 4.4 |
| Reef dressing set and caustic pass | aquatic | looks (Sunday), inside M4.5 | medium | 4.3 |
| Swim body wave and idle bob | aquatic | agents | small | 4.3 |
| Title and plinth idle, part-landing sound and wobble | menus, editors | agents | small | 4.1, 4.5 |
| Land ambience bed and editor sounds | audio | agents (when the audio thread resumes) | small | 4.8 |
| Ambience scene in every review capture | microscopic | agents | small | 4.2 |

None of these changes the era count, the art pipeline, the save schema or a milestone's scope. The reef
dressing set sits inside the M4.5 reef spike the aquatic addendum already proposes.

## 8. Known gaps

- No frames yet of the social, tribal, civilization or interstellar eras, so sections 4 and 6 cover the built
  stages only; the rules in section 6 are written to apply to later eras unchanged.
- Audio was judged from the records and the DECISIONS description, not from a listening session.
- Night and storm profiles do not exist yet; rule 6 is written for when they do.
- The verdicts are one reviewer's eye. The owner's Sunday review is the calibration.
