# Workstream A: community tools and public developer sources

Status: PROPOSED research note, written 2026-10-23 by workstream A. Labels (CONFIRMED, OBSERVED, HYPOTHESIS,
PROPOSED) and source IDs S1 to S16 are defined in `LEGAL_RESEARCH_BOUNDARIES.md` and `SPORE_RESEARCH.md`. New sources
in this file use IDs C1 to C3 (community tools) and S17 to S22 (developer and press sources).

Evidence types used below:

- **E1** community tool source or documentation statement (what the modders' tools do or say).
- **E2** reverse-engineered declaration of EA internals (headers and names that modders wrote from disassembly).
  These show how modders model the game, not how EA designed it. Always labelled OBSERVED (community RE).
- **E3** developer description (Maxis staff talks, papers, interviews). The label follows
  `LEGAL_RESEARCH_BOUNDARIES.md`: CONFIRMED only when we read the developers' own paper, slides, patent or essay
  (S1, S3, S14, S15); OBSERVED when a journalist or press item reports it (S12, S13, S17, S21, S22).
- **E4** our inference. Always labelled HYPOTHESIS.

Method and limits. Both repositories were cloned into the session scratchpad, outside the repo, without checking out
code. We read the READMEs, the license files and license headers, the folder and file names, one-line doc comments
of the creature-related headers, and the SporeModder FX wiki pages on parts and animation. We did **not** read
function bodies, struct layouts, offsets, addresses, or the pages of "reconstructed Spore source code" (see risk
notes). No code, tables or layouts from these projects appear here. Spore itself was not touched. Subagents: this
file is one workstream; no further subagents were used.

## 1. Summary

1. OBSERVED (E2, medium confidence): the modding community models Spore's editor as a **creation made of
   "rigblocks"** (every part, spines included) that hold transform, symmetry, scale and handle-driven deform values.
   A separate saved resource holds the creation, and the editor converts in both directions. This agrees with the
   developer papers (S3, S1), which is the stronger evidence.
2. OBSERVED (E1, medium-high): a part is defined by a **property list** (name, cost, scale limits, ability
   levels, behaviour tags, symmetric variants, sounds), a **model with built-in deform animations and morph handles**,
   and three **paint textures** that control where the generated skin paint shows. When a creation is saved, the
   part textures are baked into one texture.
3. OBSERVED (E1, high, matches S1): the community animation exporter selects animated "bodies" by **capability
   tags plus filters** (side, extent, nearest spine). It can scale motion by creature size, make it relative to
   rest pose or the ground, and aim it at a second body. That is S1's semantic, body-independent animation, seen from
   the tool side.
4. OBSERVED (E1, medium): **gameplay abilities come from integer levels declared on parts**, plus behaviour-only
   tags (foot, mouth, spine and so on). This matches S14 (stats fixed per part, independent of shape) and S11.
   Locomotion internals are barely modelled by the community: only a generic "locomotive object" class name.
5. CONFIRMED licenses: SporeModder FX is GPL-3.0 (LICENSE.md). Spore ModAPI has **no top-level license file**.
   Its own source files carry GPL-3.0-or-later headers, and it bundles third-party code under other licenses,
   including Microsoft Detours under a non-commercial research license. None of it may enter GENESIS (owner rules);
   these projects are reference only, and for us only their public docs.

## 2. Source table

| ID | Source | Version / commit (checked 2026-10-23) | License | Evidence type | What it establishes |
| --- | --- | --- | --- | --- | --- |
| C1 | Spore ModAPI SDK, <https://github.com/Spore-Community/Spore-ModAPI>; docs at <https://modapi-docs.sporecommunity.com/> | Default branch `master`, HEAD `69b27b5b407a2c76e1e701ba27630a77a9ce5d01`, 2026-10-16. Latest release `v2.5.579` (2026-10-16, marked Latest on GitHub) | No root LICENSE file. Per-file headers: GPL-3.0-or-later ("Copyright (C) 2019 Eric Mor"). Bundles EASTL (EA, BSD-3-Clause style) and Microsoft Detours 3.0 Express (Microsoft Research Shared Source License, non-commercial) | E1 (README, tutorials) and E2 (headers declaring EA classes) | A C++ SDK for DLL mods that are **injected into the running game** by a launcher. Exposes, by name, editor, rigblock, skin, animation, skin-paint, simulator and creature-ability subsystems. Ships Ghidra import scripts. |
| C2 | SporeModder FX, <https://github.com/Spore-Community/SporeModder-FX>; site <https://smfx.sporecommunity.com> | Default branch `master`, HEAD `a482c51d8d37fc8cf416acecc3c00a5b0723f2e5`, 2026-10-07. Latest release `v2.2.27` (tag date 2026-03-13) | GPL-3.0 (LICENSE.md is the GNU GPL v3 text) | E1 (tool features), E2 (format readers named after EA formats) | A Java desktop tool that **unpacks, converts and repacks Spore's data packages** into editable text, and has model, texture, UI, effect and animation editors. |
| C3 | SporeModder FX wiki, <https://github.com/Spore-Community/SporeModder-FX/wiki> | Wiki HEAD `6b8cf56f12de3ba12bae026fa9ce8d72e7922cd9`, 2026-10-16 | No license stated on the wiki | E1, with E2 mixed in (format conventions learned from EA files) | Tutorials on custom creature parts, saving with custom parts, part capabilities and part animations, using and exporting creature animations, and importing creations into Blender. Most useful public description of the **part and animation model**. |

Maintainers and contributors (from git history; OBSERVED): both projects were started by **emd4600 / Eric Mor**
(largest contributor to both). Other frequent contributors: Allison Ghost, 0KepOnline, Rosalie Wanders (Rosalie241,
also author of SporeModLoader), Kade and Splitwirez. Both repos sit under the **Spore-Community** GitHub
organization. The SporeModder FX v2.2.26 release note says "update for new owner", so ownership moved recently;
we did not identify the new owner.

New developer and press sources (not in S1 to S16): see section 4.

## 3. Findings by subsystem

### 3.1 Creature description: how it is saved and reconstructed

- OBSERVED (E2, medium): ModAPI declares an **editor model** that keeps track of a creation's parts and paints and
  converts to and from a **saved creation resource**. Creature, building and vehicle files are all this resource
  type, each with its own file extension. Header doc comments in `Editors/EditorModel.h` and
  `Editors/cEditorResource.h` (C1) say this.
- OBSERVED (E2, medium): ModAPI also names a **creature data resource** that groups per-part capability entries and
  morph (deform) values, with parts tagged by short four-letter type codes. Names only, from
  `Editors/cCreatureDataResource.h` (C1). HYPOTHESIS (E4): this is the derived gameplay and animation summary of a
  creature, separate from the editable description.
- OBSERVED (E1, high): a creation that uses a part not on the editor's **allowed-parts manifest** is not saved
  unless the manifest is extended (C3, "Saving with custom parts"). So the save holds **references to part
  definitions**, not geometry. This agrees with S12 and S15 (the creature is a small recipe).
- OBSERVED (E1, medium): on save, the parts' paint textures are **baked into one fixed-size texture** (C3,
  "Creating Custom Part Rigblocks"). ModAPI names a bake manager (C1). This agrees with S3 ("the finished model is
  baked").
- OBSERVED (E1/E2): Sporepedia selection and creation import and export exist as named subsystems (C1 "Sporepedia",
  "Thumbnail import/export" headers). We do not study the PNG-card format; owner rule.
- Size of the recipe. CONFIRMED (E3, S15 patent): about 2 to 5 KB. OBSERVED (E3, press reports): S12 about 4 KB;
  new S17 (Lucy Bradshaw, 2008) about 8 KB. The numbers differ; any of them supports the conclusion that **the description is parameters plus part
  references, rebuilt at load**.
- Plain summary (HYPOTHESIS, E4): the editable description is a list of parts. Each entry has a part definition
  reference, a transform, a parent link, symmetry, scale and handle (deform) values, plus paint choices and colours.
  Skin, skeleton, textures and animation are all regenerated from it. **GENESIS implication (PROPOSED):** our save
  schema should store only the authoring parameters and a part-catalogue ID per part, and treat meshes, rigs and
  baked textures as caches. Any schema change still needs owner approval (CLAUDE.md).

### 3.2 Editor model and parts

- OBSERVED (E2, medium): every interactive object in the editor, **spines included**, is a "rigblock" (doc comment
  in `Editors/EditorRigblock.h`, C1). The rigblock carries a base orientation combined with a player-set
  orientation. It has named attach and snap points on its model and a surface "pinning" behaviour, with variants
  modders describe as physics-based and geometry-based.
- OBSERVED (E2, medium): editor **handles** are separate objects with idle, hover, selected and dragging states
  (`Editors/EditorBaseHandle.h`, C1). That fits S3: handles drive deform animations parameterized over 0 to 1.
- OBSERVED (E2, low-medium): names only. The editor has **limits/budgets** (`EditorLimits.h`), **content
  validation** (`ContentValidation.h`), **spine tuning** (`TuningSpine.h`), an **editor skin and skin mesh**
  (`cEditorSkin.h`, `cEditorSkinMesh.h`) and a **play (test-drive) mode** with its own animations. HYPOTHESIS (E4):
  the skin mesh is rebuilt from the rigblocks while editing. The S3 slides confirm a metaball-generated body mesh;
  "rebuilt live" rests only on an S7 search summary, which is unverified until S7 is read.
- OBSERVED (E1, medium-high): a creature part definition holds a template parent (part category such as mouth or
  grasper), a model and paint textures, a display name, **ability levels**, behaviour tags, **minimum and maximum
  scale** with a default scale, model transform offsets, attached effects, mouth and foot sound types, cost,
  complexity, a runtime bone count and unlock data (C3).
- OBSERVED (E1, high): **symmetry by variant files**. A part can name separate left, right and centre definitions.
  The right one is usually a mirrored model, and centre variants are used mainly for eyes (C3). HYPOTHESIS (E4): the
  editor picks the variant from which side of the body the part lands on.
- OBSERVED (E1, medium): parts carry their own **named deform animations** per category (open and close for
  mouths, graspers and eyes; flap and bend for feet and wings; expressions for eyes; and so on), authored on a fixed
  0-to-end timeline (C3, "List of Part Animations"). That is S1's "rigblock animations" and S3's deforms, seen from
  the tool side.
- OBSERVED (E3, press reports, medium-high): S12 says symmetry is required and legs were the hardest part of the editor. S13 says looped spines
  were removed. S17 says the interface adjusts limb manipulation to the creature's orientation and mirrors limbs
  placed on one side.

### 3.3 Skeleton and animation

- OBSERVED (E1, high): a creature is made of **bodies** (parts, limb segments, spine segments), and a body is the
  smallest unit that can be animated. A shipped in-game cheat named in C3 shows these bodies. Matches S1.
- OBSERVED (E2, medium): ModAPI names a creature **block** with a parent index, so the body set is a **tree**
  (`Anim/CreatureBlock.h`). It also names creature skinning data (`Anim/anim_csd.h`) and an animation world that
  loads a blocks description (`Anim/IAnimWorld.h`). Matches S1 (body graph; the editor uses a tree).
- OBSERVED (E1, high): **animations are authored against channels, not bones.** A channel picks bodies by
  capability (grasper, foot, mouth, eye, root spine, whole creature), then filters by side, by extent (for example
  the top-most) or by nearest spine. Motion can be **scaled by creature size**, made **relative** to rest pose,
  **ground-relative** on the vertical axis, or **aimed at a secondary body**. Parts' own deform animations can be
  keyed too (C3, "Exporting creature animations from Blender"). This is the strongest public cross-check of S1's
  semantic retargeting.
- OBSERVED (E1, medium): an **animation list** gives each animation an ID and options: play once, loop or hold
  the last frame; whether walking is allowed during it; whether it becomes the new idle; blend-in time; priority;
  and **several weighted choices** re-rolled per loop or not (C3, "How to: use Spore animations"; ModAPI's
  animated-creature doc comments, C1). This matches S1's variants and branching.
- CONFIRMED (E3): S1 remains the primary source for the solver: particle IK and the gait system. (S2, the
  earlier GDC talk, has not been read; site down.)
  Workstream A found nothing in C1 to C3 that adds to them on the solver side.

### 3.4 Locomotion and abilities

- OBSERVED (E1, medium-high): part capabilities split into **ability levels** (combat, social, movement skills such
  as sprint, sneak, jump and glide, plus speed and health) and **behaviour tags** (spine, mouth, eye, foot, limb,
  grasper, wing, fin and so on). Some tags are needed just for the part to animate (C3, "List of Part
  Capabilities"). HYPOTHESIS (E4): creature stats are sums or maxima of part levels. S11 and S14 support a fixed
  per-part model.
- OBSERVED (E2, low): ModAPI names a **locomotive object** base class, a creature base class with ability play and
  jump calls, and a creature ability class with animation IDs and UI icons (C1 `Simulator/` headers). These say
  nothing about gait. The community has **not** publicly modelled gait timing, foot placement or turning.
- Developer-side locomotion facts are still only S1 (gait system and IK) and S14 (shape has no stat effect), both
  CONFIRMED (E3), plus S13, OBSERVED (E3, press report: walking ratio from leg count, length and symmetry; footfall
  rhythm from torso and head size; legless creatures slither; mouth as a hand).
- Conclusion (E4): community tools **do not reduce** our locomotion unknowns. Gameplay recordings
  (`MEASUREMENT_PLAN.md`) and S1 stay the sources for gait.

## 4. New developer and press sources

| ID | Source | Opened? | Evidence type | What it establishes |
| --- | --- | --- | --- | --- |
| S17 | E. Naone, "Creating Creatures", MIT Technology Review, 2008-06-17. <https://www.technologyreview.com/2008/06/17/127401/creating-creatures/> | Yes (via fetch summary) | E3, secondary (interview with exec producer Lucy Bradshaw) | Animation and behaviour generated from attached parts. Parts set abilities. Limb editing adapts to body orientation. Symmetry mirrors limbs. A creature file is a recipe of about 8 KB. |
| S18 | A. Willmott, "Content Creation in Spore", Stanford CS448 "Virtual Worlds" guest talk, 2007. <https://www.andrewwillmott.com/talks/content-creation-in-spore> (slides PDF, about 93 MB, linked there) | Page yes; slides **not read** | E3 | Overview of the tech behind player-made content. Likely covers rigblocks, skin and paint. Read the slides in Phase 2. |
| S19 | A. Willmott, "Maxis sketches" page. <https://www.andrewwillmott.com/maxis-sketches> | Search result only | E3 | Alternate home of the SIGGRAPH 2007 sketches (S3 to S6), with slides. |
| S20 | A. Willmott and S. Shodhan, "Stylized Rendering in Spore", GPU Pro (2010), book chapter | **Unverified** (named in search results only) | E3 | Rendering and post-process filters. Low relevance to creatures. |
| S21 | K. Compton, "Practical Procedural Generation for Everyone", GDC 2017. Video <https://youtu.be/WumyfLEa6bU> (title confirmed via YouTube oEmbed); write-up <https://gamedeveloper.com/design/practical-procedural-generation-for-everyone-> | Write-up yes; video **not watched** | E3 (Compton worked on Spore planets) | Spore used as an example. The write-up says creatures were made with parametric controls, trading uniqueness against player control, and that good planet seeds were whitelisted by brute force. Secondary report; low confidence on creature detail. |
| S22 | "Spore Experts Share Animation Techniques at SIGGRAPH", Computer Graphics World press item, 2008-08-12. <https://www.cgw.com/Press-Center/Siggraph/2008/Spore-Experts-Share-Animation-Techniques-at-SIGG.aspx> | Yes | E3, press release | Confirms S1 was presented as a SIGGRAPH 2008 technical paper. Motion is stored in a body-independent form and applied through IK at runtime. Adds nothing beyond S1. |

Also found, lower value: a Shacknews post-release interview with Maxis
(<https://www.shacknews.com/article/54609/a-post-release-spore-interview>; not opened; reported to say procedural
animation started as a research project). Maxis's 2009 public Spore API (Shacknews, 2009-02-27,
<https://www.shacknews.com/article/57447/maxis-releases-spore-api>) exposed creation data and statistics as web
services. We do not use it (owner rule; `LEGAL_RESEARCH_BOUNDARIES.md` §4).

Searched with nothing found: talks by Dan Moskowitz or Ocean Quigley on creature tech, and any GDC Vault page for
S16. Kate Compton is a co-author of S5 (planets), not of creature papers.

## 5. Risk notes

- **Not allowed for us** (owner rule "Spore files are not used"; EA User Agreement §2, §7.C):
  - Using SporeModder FX to open, unpack, convert or browse the owner's `.package` files, models, textures,
    animations or property lists. That is its core function.
  - Installing ModAPI, the ModAPI Launcher Kit or SporeModLoader, or injecting any DLL mod. That includes the
    `GmdlExport` mod (exports creations to Blender) and `EditorPlayModeNoBounds`.
  - The SporeModder Blender add-ons' import of Spore models or animations, and the "import creations into Blender"
    workflow (C3). These read EA formats.
  - ModAPI's `SDKtoGhidra` folder: Ghidra import scripts and symbol files for Spore's executable. Using it is binary
    analysis, which is not cleared.
- **Do not read further:** ModAPI `Documentation/SourceCodeSimulator.md`, `SourceCodeSkinner.md` and
  `SourceCodeTerrain.md` describe themselves as **reconstructed Spore source code**. They are decompilation-derived
  EA code. We opened the first lines of one page only to classify it, and stopped there. Nothing from them is used
  here. Implementation agents must never be given these files.
- **Headers are EA's internals as modders understand them.** Class names, struct layouts, property IDs and hashes
  in C1 are reverse-engineered. We used file names and one-line descriptions only, to cross-check developer papers.
  Nothing from them is a spec input.
- **EA material inside the repos:** SporeModder FX ships font files with EA- and Maxis-style names under
  `UI Editor/`, plus Spore-branded fonts and images under `docs/style/`. The wiki's capability and animation lists
  are EA's data names. Do not copy any of them, and do not reuse EA's part, ability or animation names in GENESIS
  (`LEGAL_RESEARCH_BOUNDARIES.md` §6).
- **License:** GPL-3.0 for C2, and GPL-3.0-or-later per-file for C1 (no root license file). Any code use would
  impose GPL terms on GENESIS, and the owner forbids copying anyway. Detours in C1 is non-commercial only.
- **Tension with an earlier note (resolved):** `SPORE_RESEARCH.md` §3 now has a paragraph ("Community projects")
  that reconciles its "not used, on purpose" list with the owner's 2026-10-23 brief: study at concept level only
  (public READMEs, wiki prose and file names, no format layouts). Owner approval of that reading is still open
  question 6.
- **In-game cheat:** C3 mentions a shipped console cheat that shows creature bodies. It is a game feature, not a
  third-party tool, so under `LEGAL_RESEARCH_BOUNDARIES.md` §4 it is "Flag: low risk". Use it only with owner
  approval, and log it.

## 6. Open questions

1. Does the editor pick the left, right or centre variant from where the part lands? What happens on the body's
   midline? (Recording; OBSERVED target.)
2. How are pinning or surface attachment and part orientation decided when a part is dragged across the skin? S3
   and S7 do not say. Recording: drag a part slowly across a curved body and note the snap and rotation behaviour.
3. Are creature stats a sum, a maximum or the best part per category? S11 suggests levels; C3 only shows per-part
   levels. Recording: add two parts with the same ability and read the stat bar.
4. What do the editor's limits cover (part count, complexity, cost)? Names exist in C1, values unknown.
   Recording: fill the complexity meter.
5. Read S18 (Willmott's Stanford slides) and S2 when available; check S21's video for creature detail.
6. Owner question: is reading C1 and C3 public prose and file names (as done here) acceptable under "Spore files are
   not used"? If not, this file should be cut back to section 4 only.
7. Owner question (optional): may we use the shipped bodies-display cheat during recordings?
