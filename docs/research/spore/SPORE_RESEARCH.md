# Spore research: Phase 1

Status: PROPOSED research, started 2026-10-23. Labels (CONFIRMED, OBSERVED, HYPOTHESIS, PROPOSED) are defined in
`LEGAL_RESEARCH_BOUNDARIES.md`. Read that file first; it says which methods are allowed.

Purpose: understand the engineering ideas and the gameplay behind Spore (2008) so GENESIS can build **original**
systems that reach the same or better feel. Not a clone. No Spore data, code or art enters GENESIS.

Files in this folder:

| File | What it holds |
| --- | --- |
| `LEGAL_RESEARCH_BOUNDARIES.md` | EA license review, law summary, allowed and forbidden techniques, clearance steps |
| `SPORE_RESEARCH.md` | This file: tool check, source survey, systems map, open questions, workflow |
| `CREATURE_CREATOR_ANALYSIS.md` | How Spore's creature editor is built (from published papers) and what GENESIS takes from it |
| `PROCEDURAL_ANIMATION_SPEC.md` | Original GENESIS spec for animating player-built bodies in Godot 4 |
| `GAMEPLAY_MEASUREMENTS.csv` | Measurement schema; public-source rows filled, recording rows waiting for clips |
| `MEASUREMENT_PLAN.md` | How the owner records clips and how each number is extracted |
| `GENESIS_IMPLEMENTATION_ROADMAP.md` | Research phases mapped to GENESIS milestones, with approval gates |

## 1. Summary of Phase 1

1. **Tools.** The tool check is for the owner's PC, which this session cannot see. A read-only checklist is in §2.
   Nothing was installed. REA is identified (§2.2) but not installed; Ghidra is not configured for Spore.
2. **Legal.** EA's User Agreement §2 forbids reverse engineering and extracting data, §7.A forbids touching
   protection measures, and §7.C forbids programs that "mine" data from the game. Recommendation: no binary
   analysis at all; gameplay observation and published research cover what we need. Details and the clearance
   steps, if the owner wants them anyway, are in `LEGAL_RESEARCH_BOUNDARIES.md` §5.
3. **Sources.** Maxis published unusually detailed technical work on Spore: one SIGGRAPH 2008 journal paper on the
   animation system, four SIGGRAPH 2007 sketches (rigblocks, procedural texturing, spherical planets, object
   distribution), GDC talks on animation and procedural music, and developer notes on the creature skin. §3 lists
   them with what each one establishes.
4. **Biggest finding for GENESIS.** Spore's creatures come alive because of a layered runtime stack: semantic body
   tags, animation stored relative to those tags, a procedural gait generator, a two-phase constraint IK solver and
   passive secondary motion. GENESIS can build its own version of that stack in Godot 4 within the approved art
   boundary (Blender-authored parts, shape keys and bone scale only). The spec is in `PROCEDURAL_ANIMATION_SPEC.md`.
5. **One conflict to note.** Spore generates its creature skin at runtime as an implicit surface around the spine
   and limbs. GENESIS's approved boundary (DECISIONS.md, 2026-10-22, IB-15 option B) does **not** allow
   runtime-generated body skins. This research does not reopen that decision; `CREATURE_CREATOR_ANALYSIS.md` §4
   describes how to get comparable variety inside the boundary.

## 2. Research environment

### 2.1 Tool checklist for the owner's PC (read-only)

This session runs in the cloud and cannot see the owner's PC, so these checks are for the owner to run. They only
read; they install and change nothing. Paste the output into the thread and we record it here.

Run in **PowerShell** (not as administrator):

```powershell
# Spore install: look in the usual places. Prints True/False only; opens nothing.
"Steam:  " + (Test-Path "C:\Program Files (x86)\Steam\steamapps\common\Spore")
"EA app: " + (Test-Path "C:\Program Files\EA Games\SPORE")
"Origin: " + (Test-Path "C:\Program Files (x86)\Origin Games\SPORE")
"GOG:    " + (Test-Path "C:\GOG Games\Spore")

# Godot and Blender
Get-Command godot*, blender* -ErrorAction SilentlyContinue | Select-Object Name, Source
Test-Path "C:\Program Files\Blender Foundation"

# Claude Code, Node (REA would need Node 22+), Java (Ghidra needs a JDK)
claude --version
node --version
java -version

# Ghidra has no installer; look for its launcher in common places
Get-ChildItem -Path "$env:USERPROFILE","C:\Tools","C:\Program Files" -Filter ghidraRun.bat -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object FullName

# REA (npm package rea-agents)
npm ls -g rea-agents
```

Also, by hand:

| Check | Why |
| --- | --- |
| Where was Spore bought (Steam, EA app, GOG, disc)? Which expansions (Galactic Adventures, Creepy & Cute, Bot Parts)? | Decides the EULA version and which features exist in recordings |
| Which country do you live in? | EA §13(B) governing law; which legal exceptions apply |
| Does Spore launch and reach the Cell stage and the Creature editor? | Needed for the recording plan |
| What screen recorder do you have (Xbox Game Bar, OBS)? Can it record at 60 fps? | Measurement precision depends on frame rate |
| Godot version on the PC | Must match `tools/toolchain.env` (4.7.2-stable) for any prototype review |

### 2.2 Tool identities (verified from public pages, 2026-10-23)

- **Claude Code**: the agent running this research. Present in this cloud session. Owner PC: unknown.
- **Godot 4**: pinned at 4.7.2-stable (`docs/TOOLCHAIN.md`). Present in the cloud toolchain.
- **Blender**: pinned at 5.2.2 LTS; in the cloud, used headless through `pip install bpy==5.2.2`. Owner PC: unknown.
- **Ghidra**: NSA's open-source reverse-engineering suite, Apache-2.0,
  <https://github.com/NationalSecurityAgency/ghidra>. CONFIRMED legitimate. Not installed or configured here, and not
  to be used on Spore (`LEGAL_RESEARCH_BOUNDARIES.md` §4).
- **REA** ("Reverse Engineer Anything"). OBSERVED identity:
  - The workflow the owner refers to is most likely Stefan's post on ceos3c.com, "Reverse Engineer Anything: REA +
    Ghidra on a Game DLL" (<https://www.ceos3c.com/ai/reverse-engineer-anything/>, dated 2026-10-18). It points at the
    repository `github.com/morluto/rea`. HYPOTHESIS that this is the "Stefan 3D AI" workflow; the owner should
    confirm the video or post he meant.
  - Repository <https://github.com/morluto/rea>: an MCP server and CLI that connects coding agents (Claude Code,
    Codex, Cursor and others) to Ghidra, IDA or Hopper and to analyzers for .NET, JavaScript/Electron, Android,
    websites and firmware. MIT license for its own code. Requires Node.js 22.19+ or 24.11+. Install is
    `npx rea-agents setup`, which edits agent configuration files (with backups) and can optionally install Hopper.
    Official sources per its README: the morluto/rea repository, rea.tools, and the `rea-agents` npm package.
  - Red flag: the GitHub page as fetched showed about 366k stars and 92k forks, which is implausible for a project
    of this kind and age. That could be a scraping error or inflated metrics. **Unverified; do not install** until the
    owner looks at the page himself and an approval for a new dev tool is recorded.
  - Independent review: Korben (<https://korben.info/en/rea-ai-agent-reverse-engineering-test.html>) found REA no
    better on average than asking Claude to drive Ghidra directly.
  - Conclusion: REA is not needed for any permitted research. It stays off the plan unless the owner approves it as a
    dev tool for non-Spore uses (for example, inspecting our own builds).

## 3. Published sources on Spore's engineering

All are public papers or talks by Spore's developers unless marked. CONFIRMED means the source says it.

| ID | Source | What it establishes |
| --- | --- | --- |
| S1 | Hecker, Raabe, Enslow, DeWeese, Maynard, van Prooijen, "Real-time Motion Retargeting to Highly Varied User-Created Morphologies", ACM Trans. Graph. 27(3), Article 27, SIGGRAPH 2008. DOI 10.1145/1360612.1360626. PDF: <https://www.chrishecker.com/images/c/cb/Sporeanim-siggraph08.pdf> | The whole creature animation stack: semantic body capabilities, the Spasm authoring tool, generalized/specialized pose spaces, movement modes, branching and variants, the gait system, the two-phase Particle IK solver, "Jiggles" secondary motion, testing and performance. Primary source for `PROCEDURAL_ANIMATION_SPEC.md`. |
| S2 | Hecker, "How To Animate a Character You've Never Seen Before", GDC 2007 lecture. <https://chrishecker.com/How_To_Animate_a_Character_You%27ve_Never_Seen_Before> | Earlier version of S1, including approaches that did not work. Slides and audio linked from the page (site was down on 2026-10-23; re-check). |
| S3 | Choy, Ingram, Quigley, Sharp, Willmott, "Rigblocks: Player-deformable Objects", SIGGRAPH 2007 sketch. <https://www.cs.cmu.edu/~ajw/s2007/> | Parts are artist-made models with deform animations parameterized over 0..1 and driven by player handles; deforms compose additively; the finished model is baked. |
| S4 | DeBry, Goffin, Hecker, Quigley, Shodhan, Willmott, "Player-Driven Procedural Texturing", SIGGRAPH 2007 sketch. Same page. | Creature paint: particle-driven brushes run over the body mesh and paint diffuse, specular and bump maps; player picks base, coat and detail scripts and two colours; UVs from cubemap partitioning; spherical-harmonics lighting. |
| S5 | Compton, Grieve, Goldman, Quigley, Stratton, Todd, Willmott, "Creating Spherical Worlds", SIGGRAPH 2007 sketch. Same page. | Planets: cube-map charts with perspective projection; heightfields made by particle-driven brushes; terrain texture blended from height, slope and curvature. Relevant to GENESIS M7+ only. |
| S6 | Willmott, "Fast Object Distribution", SIGGRAPH 2007 sketch. Same page. | Incremental Halton sequence for well-spaced, repeatable object placement with density maps. Directly useful now (food and scatter placement). |
| S7 | Hecker, "My Liner Notes for Spore" (blog). <https://chrishecker.com/My_Liner_Notes_for_Spore> | Developer account: creature skin is a "blobby implicit surface" using only spherical metaballs along spine and limbs, rebuilt in real time while editing; ellipsoids rejected as too slow; rigblocks are Maya models with deformation handles. Read through a search summary on 2026-10-23 because the site was down; re-read and quote directly in Phase 2. |
| S8 | Jolly and McLeran, "Procedural Music in Spore", GDC 2008. Recording: <https://archive.org/details/GDC2008Jolly> | Music generated in real time with EAPd, a customised Pure Data; most prominent in editors. Relevant to GENESIS audio later, out of scope now. |
| S9 | Will Wright, "The Future of Content", GDC 2005 (cited as [Wright 2005] in S1) | Design intent: player-made content and procedural generation as the core of Spore. Design context, not engineering detail. |
| S10 | "Development of Spore", Wikipedia. <https://en.wikipedia.org/wiki/Development_of_Spore> | Secondary. Timeline and staff; the 2005 demo versus the shipped game. |
| S11 | Spore Wiki (fandom) and StrategyWiki "Spore/Creature Stage". <https://strategywiki.org/wiki/Spore/Creature_Stage> | Secondary, community-written. Ability categories and part-to-ability rules (OBSERVED by players). Used only as a cross-check for our own recordings. |

Not used, on purpose: Sporepedia files, the Spore API, PNG creature cards, SporeModder, Spore ModAPI and any file-format
documentation written by modders. They describe EA's formats, which the owner's rule excludes.

## 4. Systems map

For each area in the protocol: what is known, from where, and how we will close the gap. "Recording" means the owner
records clips under `MEASUREMENT_PLAN.md`.

### A. Creature creator

| Topic | Known (label, source) | Gap, and method |
| --- | --- | --- |
| Procedural body geometry | CONFIRMED (S7): implicit-surface skin of spherical metaballs along spine and limbs, rebuilt live | Not adopted (approved boundary). See `CREATURE_CREATOR_ANALYSIS.md` §4. |
| Spine manipulation | CONFIRMED (S1): a serial chain of spine bodies at the root; editor uses a tree, general graphs were tried and dropped as confusing. OBSERVED: player drags vertebrae, adds or removes them, scales each. | Recording: max and min spine segments, how thickness is set. |
| Limb placement | CONFIRMED (S1): bodies form a directed acyclic graph; capabilities tag parts (grasper, foot, mouth, spine). | Recording: attach rules, symmetry mode, limits. |
| Body scaling | CONFIRMED (S1): animations scale with character bounds (CreatureSize) or limb length (LimbLength). | Recording: size range in the editor and in the world. |
| Procedural skeleton | CONFIRMED (S1): skeleton is the body graph itself; legs are paths from a foot to a spine body (the hip). | Enough for GENESIS spec. |
| Automatic rigging | CONFIRMED (S1, S3): parts carry their own deform animations; the skin follows the spine and limb bodies. HYPOTHESIS: skin weights come from distance to bodies. | Not needed: GENESIS parts are rigged in Blender. |
| Animation adaptation | CONFIRMED (S1): full stack, see `PROCEDURAL_ANIMATION_SPEC.md` §2. | Enough for GENESIS spec. |
| Coloration and texturing | CONFIRMED (S4): base, coat and detail paint scripts plus colours; brushes run along spine and limbs. | GENESIS approach in `CREATURE_CREATOR_ANALYSIS.md` §5. |

### B. Creature gameplay

| Topic | Known | Gap, and method |
| --- | --- | --- |
| Movement speed | OBSERVED (S11): speed comes from leg parts in levels. | Recording: top speed per speed level, in body lengths per second. |
| Acceleration and deceleration | Unknown | Recording: frames from start to top speed and back. |
| Turning radius | Unknown | Recording: circle a fixed landmark; measure path radius. |
| Camera tracking | Unknown | Recording: lag behind a sudden stop, zoom range, auto-rotation. |
| Combat and social | OBSERVED (S11): four combat and four social abilities, each rated on a five-level scale from parts. | Recording: cooldowns, ranges, damage per level. |
| Abilities | OBSERVED (S11): movement abilities (sprint, sneak, jump, glide) from parts. | Recording: durations and cooldowns. |
| NPC behaviour | Unknown in engine terms | Recording: aggro radius, chase give-up distance, pack size. HYPOTHESIS only from video; never presented as Spore's code. |

### C. Evolution

| Topic | Known | Gap, and method |
| --- | --- | --- |
| Cell-stage progression | OBSERVED (S10, S11): eat to earn DNA points; the cell grows; a progress bar leads to the editor and to the next stage. | Recording: time to finish, points per food, growth steps. |
| Creature-stage progression | OBSERVED (S11): DNA points from befriending or hunting; brain upgrades raise pack size and health. | Recording: points per interaction, number of brain upgrades. |
| Anatomy-based abilities | CONFIRMED in engine terms (S1): capabilities on parts drive animation and gameplay queries. OBSERVED: abilities sum from parts. | Enough for GENESIS design direction. |
| Species generation | OBSERVED: NPC species are pre-made or downloaded player creations placed by the game. HYPOTHESIS: chosen to fit diet and stage. | Out of scope for measurement; GENESIS uses its own approved IB-05 rules. |
| Later eras | CONFIRMED (S10): five stages, Cell, Creature, Tribal, Civilization, Space. GENESIS has seven eras of its own; Spore's stage scopes are not a template. | Not measured in Phase 1. |

## 5. Open questions for Phase 2

1. Owner answers to the §2.1 checklist (purchase channel, country, recorder, Spore runs).
2. Re-read S2 and S7 when chrishecker.com is back; quote S7 directly.
3. Patent search on procedural creature animation and editing (`LEGAL_RESEARCH_BOUNDARIES.md` §3).
4. First recording session (`MEASUREMENT_PLAN.md` sessions R1 and R2).

## 6. Research and development workflow (PROPOSED)

1. **Observe.** Owner plays and records under `MEASUREMENT_PLAN.md`. No tools attach to the game.
2. **Measure.** Each clip becomes rows in `GAMEPLAY_MEASUREMENTS.csv`, with method, frames, confidence and label.
3. **Study.** Published sources in §3, cited by ID.
4. **Hypothesize.** Engineering guesses go in the analysis files, labelled HYPOTHESIS, with what would disprove them.
5. **Specify.** An original GENESIS spec with its own numbers, acceptance criteria and tests.
6. **Prototype, after approval.** An isolated Godot prototype under `prototypes/` (not `game/`), only when the owner
   approves that spike.
7. **Compare.** Measure the prototype the same way as Spore (same CSV columns, `subject=genesis`). Where a GENESIS
   number differs on purpose, say why.
8. **Refine** until the spec's acceptance criteria pass, with automated tests in `tests/` for anything that moves
   into the game.
