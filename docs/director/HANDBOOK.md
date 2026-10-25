# Director's handbook

Status: CONFIRMED as the operating reference (owner approval 2026-10-25). Each rule cites its source. Where this file
and the Bible disagree, the Bible wins and the conflict goes to the owner. Owner decisions override both.

Before any task, an agent must be able to answer the Bible's five questions (section 28): what player behaviour am I
delivering, which approved requirement authorizes it, which inherited system must stay intact, which source assets
are required, and what evidence will prove it works.

## Part 1. Non-negotiables

1. **"Spore but better."** Keep Spore's nostalgic gameplay, rebuild it better and add every Bible idea on top.
   (Owner, 2026-10-24 07:39.)
2. **The Bible is gospel.** `docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf` is binding; work that conflicts
   with it follows the Bible or goes to the owner first. (Owner, 2026-10-24 00:09.)
3. **Seven eras that build on each other**: Microscopic, Aquatic, Terrestrial, Social, Tribal, Civilization,
   Interstellar (working names). Nothing silently resets between them. (Bible §1, §2 "continuity across scales".)
4. **Anatomy changes play.** Every body change brings a capability and a cost; no single expensive part solves every
   problem. Parts are never stat stickers. (Bible §1, §2.)
5. **Original work only.** No Spore or EA assets, code, names, UI layouts or audio; no GPL code (Thrive is reference
   only); no reading data from Spore's files. (Bible §2; DECISIONS 2026-10-22.)
6. **Blender is mandatory** for every production 3D asset, with a Blender source, a GLB and a record. CC0 resources are
   fine, logged in the record. (Bible §15, §16; CLAUDE.md.)
7. **Playable means played.** A build is playable only when the player flow ran outside the editor; a Windows build
   counts only after a launch on Windows. (Bible §21, §22.)
8. **Honest labels.** CONFIRMED, PROPOSED, IMPLEMENTED, exactly as the Bible defines them. Never invent approval.
9. **No runtime AI, network, multiplayer, live service or paid marketplace** without owner approval. (Bible §2.)
10. **Push after every commit.** Containers restart. (Owner, 2026-10-22.)

## Part 2. The Spore pillars, stage by stage

Start each stage from Spore's loop for it (`docs/research/spore/PLAYTHROUGH_VIDEO_NOTES.md`), then layer the
Bible's systems. Dropping a pillar is Tier 3.

| Pillar | Every stage that has it must |
| --- | --- |
| Mating opens the editor | Find a mate of your own kind at a safe moment, a short mating beat, then the editor |
| The editor | Part grid on the left, the subject on a round plinth or dish on the right, a test drive, previews of what each change costs |
| Friend or foe | Choose a stance before an interaction; both paths stay viable |
| Dancing and socializing | Sing, dance, charm or pose to befriend; allies follow and help |
| Distinct stages | A scale and camera jump at each era change, a new goal and new controls |
| Small HUD | Goals top left, abilities bottom centre, one progress bar; nothing else unless it earns its place |
| The editor is the reward | An editor visit every few minutes of play |
| One persistent creature | The lineage you built shows up in every later era |

Where Pangaea does better than Spore (the improvement layer): anatomy that matters in play, a genome and lineage
that carry through every era (Bible §18), rivals that evolve by visible rules (DECISIONS 2026-10-22), creatures
readable at night, and later eras with fewer, deeper systems instead of more screen time.

## Part 3. Case law

The owner's past calls, as precedents. When a new question resembles one, follow the precedent and cite it.

### Look

- **Deep blue, never teal, for the microscopic world.** It must read as a microscopic world: a blue fluid volume,
  depth layers with huge blurry organisms behind, translucent diatom and radiolarian discs, drifting particles,
  swarms of tiny cells, a lit editor dish. (2026-10-22 19:49, 22:02.)
- **The polish bar is the minimum.** At least the polish of Spore's Steam store images; match the polish, never the
  designs. (2026-10-22.)
- **"Soft life hardens."** Pebble, petal and bead shape language from `docs/art/ART_DIRECTION.md`; the cell ladder
  is the approved look. (2026-10-22 09:12, "Incredible. I approve".)
- **Scale honesty.** No skeletons, bones or carcasses at cell or bacteria scale unless they belong to a later stage.
  (2026-10-23 05:45.)
- **Cut triangles** on every finished model without losing quality, and record before and after. (2026-10-22.)
- **Decor never uses food green or threat red** (#D9466B), and stays clear of the play plane. (Art contract.)
- **The owner judges the look**, but a look check is review at merge, not a gate. (2026-10-23 05:45.)
- **Visual work uses the finish-hunyuan-assets gates.** (2026-10-24 23:41.)
- **Generated creature skins are approved**: Spore-like full-body building with runtime geometry, auto-rigging and
  anatomy-driven animation. Code stays original. (2026-10-23 01:10, reversing IB-15.)

### Feel and pacing

- **Faster progression.** Progress comes from eating plus mating, not twenty minutes of grazing; a new part every
  few minutes. (2026-10-24 02:42.)
- **Size and strength are tradeoffs.** Bigger is slower and turns slower but has more health and bite; strengths
  level up step by step. (2026-10-24 02:42.)
- **Every size stays tense.** Size 3 must feel as tense as size 1; the elder ambush hunter exists for that.
  (2026-10-24, S3.)
- **The world is endless and grows with you**, like Spore: no world edge. (2026-10-23 00:27, 03:27.)
- **Doing earns adaptation points**; stats come from anatomy only, never flat bonuses. (2026-10-24 07:01.)
- **Mating at the nest calls a mate before the editor; singing befriends and allies follow.** (2026-10-24.)
- **Death:** respawn at the last generation checkpoint, keep the lineage, lose a quarter of unspent points; the
  death is saved at once. (M1 brief; OD1.)
- **One forgiving difficulty preset for now.** (M1 brief.)
- **Menus like Spore, but in Pangaea's style; a live title world.** (2026-10-23.)
- **Music must be lush, beautiful and cosmic, like Spore's.** Thin synth is rejected. (2026-10-23.)

### Continuity and saves

- **Continue rebuilds the world from its seed**; no full sim snapshot. Saves hold seed, lineage, genome,
  discoveries, relationships, location and persistent world changes. (2026-10-24 00:07; Bible §18.)
- **Every save schema version is the owner's call** (v3, v5 approved). (Tier 3.)
- **An era change is a transaction** with a pre-transition checkpoint and a player choice. (Bible §4, §18.)

### How the studio works

- **Never sit idle.** If the owner has not answered in about 10 minutes, go on with the recommended option; he
  reviews at merge. (2026-10-23 05:45.)
- **Merge green and ship.** Send builds as soon as the gates pass; deeper reviews run alongside. (2026-10-23.)
- **Recommend, don't just ask.** The director starts parallel work itself instead of offering it. (2026-10-23 07:31.)
- **Budget**: 10% a day, Tuesday ultracode day. (2026-10-25; see `docs/director/README.md`.)
- **Godfrey** works from `godfrey-task` issues and never merges; we review and merge his green PRs. (2026-10-23.)
- **Paused until the owner says go**: the Steam store prep and the daily build scout. (2026-10-23.)

## Part 4. Adding case law

When the owner makes a call, add one line here in the same turn: the rule, then the date and source in brackets.
Superseded lines get struck through, not deleted (Bible §28).
