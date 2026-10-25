# Innovation backlog

**Status: PROPOSED.** Nothing in this backlog is approved design or changes the Bible, the era count, the save
schema, the art pipeline or any milestone scope. Every item is a proposal for Joshua's review; items marked as scope
changes need his approval and a `docs/DECISIONS.md` entry before any production work starts.

- **Date:** 2026-10-22
- **Author:** design analyst, Pangaea research team
- **Inputs:** `docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf` (v0.1, read as text), `docs/DECISIONS.md`,
  `docs/milestones/M0.md`, `docs/milestones/M1.md`, `docs/research/community-wants.md` (cited as "theme N"),
  `docs/research/open-source-scout.md` (cited as "OSS") and, from 2026-10-25, `docs/research/mod-wishes.md`
  (cited as "mod wishes N"; items IB-30 to IB-33). Both briefs were being corrected by a skeptic at the
  time of writing; theme numbers and names below match the versions read on 2026-10-22.

## How items were derived

The aim is to treat the Bible as the goal rather than a literal script, and to ask where GENESIS can answer what
Spore fans asked for in an original way. Each item started from one or more ranked themes in `community-wants.md`
(theme 1 "every stage needs real depth" is the strongest, theme 17 "physical, readable combat" the weakest). It was
then checked against the Bible section that governs it, and against the OSS brief for anything we can build with
what we already have (mainly Godot 4.7.2's built-in IK and SkeletonModifier3D stack, and Blender shape keys). Spore
features are named only to explain a complaint; no item reuses a Spore system, name or layout, and Thrive ideas are
described from their public behaviour only, never from their GPL code.

Items are original takes, not ports. Where a fan request is itself a Spore feature (online sharing, for example), the
item proposes a different shape that fits the Bible's exclusions, and says so.

## Scoring method

- **Value (H/M/L):** H when the item answers a top-7 theme with high strength *and* serves a Bible pillar (§2) or a
  CONFIRMED requirement (§1). M when it answers a mid-ranked theme or strengthens a pillar indirectly. L otherwise.
- **Cost (H/M/L):** rough engineering plus Blender art effort. L is days of work inside existing services; M is a
  focused feature of one or two weeks with a few assets; H is multi-week, touches several services or needs new rig
  or content families.
- **Risk:** the main way the item could go wrong (scope creep, feel, performance, approval).
- **Type:**
  - *Within current scope*: already required or allowed by the Bible and approved decisions; still PROPOSED design
    until built.
  - *Refinement of a proposal*: sharpens something the Bible proposes but has not approved (era mechanics, §26 open
    items) without adding scope.
  - *Scope change needing approval*: adds a system, a boundary, or a route the Bible does not yet cover.
  - *Conflicts with Bible exclusion*: touches the §2 exclusions (multiplayer, live service, user scripting). Network calls are barred separately
    by the project rules in `CLAUDE.md` unless approved.
- **Milestone** is the Bible §23 milestone where the item would first be built or decided, followed by the governing
  section (§N).

## Backlog

| ID | Idea | Community theme(s) | Milestone, § | Type | Value | Cost | Risk | Depends on |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| IB-01 | Trait ledger: every inherited trait records what it did, and each era transition checks that some still matter | 7 Body design, 9 Continuity, 1 Depth | M4, §4 transition contract, §12 | Refinement of a proposal | H | M | Becomes a cosmetic checklist | M1 lineage history; IB-18 |
| IB-02 | "Why did that happen" recap after a death, failed feed or failed ram, built from resolver refusal reasons | 7 Body design, 11 Challenge, 17 Combat | M1 step 3, §2, §14 | Within current scope | H | L | Too much text for a cell game | M1 interaction resolver |
| IB-03 | Editor test space: a small calm basin to try the edited body against a dummy food and threat before committing | 2 Editors, 7 Body design | M1 step 4 or M3, §12 | Within current scope | H | M | Scene work grows past M1 caps | M1 editor session |
| IB-04 | Before and after comparison in the editor with plain-language deltas ("turns 12% slower, bites twice as hard") | 2 Editors, 7 Body design | M1 step 4, §12, §19 | Within current scope | H | L | Numbers feel like a spreadsheet | M1 phenotype |
| IB-05 | Rival species evolve between generations by bounded rules, shown in the journal | 5 Living ecosystem, 11 Challenge | M3 spike, §13 | Scope change, approved 2026-10-22 (see DECISIONS.md) | H | H | Runaway rivals; hard to test | M1 ecology region; Thrive auto-evo idea (reimplemented) |
| IB-06 | Offspring variation: a reproduction offers the designed child plus two small inherited variants to choose from | 5 Living ecosystem, 3 Science vs fun | M3, §3, §12 | Scope change needing approval | M | M | Dilutes the designer fantasy | M1 lineage; IB-04 |
| IB-07 | Staying aquatic is a viable route past the terrestrial era, within a bounded content plan | 6 Aquatic, 12 Freedom of path | M4 decision, §4, §26 | Scope change needing approval | H | H | Doubles content per era | IB-08 |
| IB-08 | The shore is a gradient: amphibious bodies trade swim and walk efficiency rather than switching modes | 6 Aquatic, 9 Continuity, 12 Freedom | M4, §7 | Refinement of a proposal | H | M | Locomotion edge cases | IB-14, IB-18 |
| IB-09 | Offline creature sharing: export a body to a small data file, import a friend's file, both validated like saves | 8 Sharing, 2 Editors | M3 or later, §2, §18 | Scope change needing approval | H | M | Malformed files; seen as a step to online | M0 genome validation |
| IB-10 | Imported creatures can be released into your world as a wild species that lives under your ecology rules | 8 Sharing, 5 Living ecosystem | M5 or later, §13 | Scope change needing approval | M | M | Balance breaks from outside designs | IB-09, IB-05 |
| IB-11 | Interstellar consequences come from the player's own actions (overharvest, introduced species) with a forecast, not random disasters | 4 Space stage | M8, §2, §11, §13 | Refinement of a proposal | H | M | Too passive, nothing happens | IB-21 regional ecology |
| IB-12 | Rival civilizations have readable goals and memory, and every one can be negotiated with or outlasted | 4 Space stage, 16 Social | M8, §11, §14 | Refinement of a proposal | H | M | Diplomacy UI cost | IB-19 relationship model |
| IB-13 | Homeworld needs arrive as a queue the player answers when they choose, not interruptions | 4 Space stage, 13 Length | M8, §11 | Refinement of a proposal | M | L | Needs ignored with no cost | IB-11 |
| IB-14 | Procedural gait and reach from Godot's built-in IKModifier3D, driven by our own gait-template service | 2 Editors, 17 Combat | M3, §12, §25 | Within current scope | H | H | Foot sliding on odd bodies | OSS: IK framework (built-in), Hecker 2008 idea |
| IB-15 | Body variety from Blender shape keys and bone scale on Blender-authored parts, inside an approved deformation boundary | 2 Editors, 7 Body design | M2 decision, M3 build, §12, §15 | Scope change, approved 2026-10-22 (see DECISIONS.md) | H | M | Collision proxies drift from shape | OSS: shape keys path 1 and 2 |
| IB-16 | Eyes and head follow what the creature actually perceives, using LookAtModifier3D and spring bones | 17 Combat and behaviour, 2 Editors | M2, §2, §13, §15 | Within current scope | M | L | Twitchy look-at | OSS: SkeletonModifier3D stack |
| IB-17 | Mood shown through pose and motion (fear, effort, satisfaction), with a text label for accessibility, no floating icons | 17 Combat and behaviour, 16 Social | M3, §19, §20 | Within current scope | M | M | Unreadable at camera distance | IB-14, IB-16 |
| IB-18 | Where a part sits changes what it does in every era (fin position sets turning, leg spread sets stability) | 7 Body design | M3, §12 | Refinement of a proposal | H | M | Hidden maths players cannot read | M1 facing arcs; IB-04 |
| IB-19 | Learned behaviours (a route, a hunting trick) recorded in the lineage and passed to offspring in the Social era | 9 Continuity, 16 Social | M5, §8, §12 | Refinement of a proposal | M | M | Feels like a skill tree | IB-01 |
| IB-20 | Tribal tools and buildings grow out of the species' own anatomy (diggers burrow, filter feeders farm, grippers craft) | 10 Tribal, 7 Body design | M6, §9 | Refinement of a proposal | H | H | Content per body plan | IB-01, IB-18 |
| IB-21 | Civilization runs on species you co-evolved with: former prey become herds, former rivals keep their history | 10 Civilization, 9 Continuity | M7, §10, §13 | Refinement of a proposal | M | H | Record bloat across eras | IB-01, IB-05 |
| IB-22 | Eras are open-ended: the player chooses when to move on, and an era keeps offering goals while they stay | 13 Length, 12 Freedom | M4 decision, §4, §26 | Refinement of a proposal | M | M | Players stall without direction | §4 transition contract |
| IB-23 | A harder preset where the ecosystem pushes back on a dominant player (rivals adapt, food shifts) rather than enemies hitting harder | 11 Challenge | M3, §3, §26 | Refinement of a proposal | M | M | Feels punitive | IB-05 |
| IB-24 | Field notes: an optional biology explanation for each discovery in the journal, without changing the art style | 3 Science vs fun | M1 step 6 or M3, §19 | Within current scope | M | L | Inaccurate science | none |
| IB-25 | Lineage album: every generation's body side by side, with what changed and why it survived | 9 Continuity, 2 Editors | M1 step 4 or M3, §2, §12 | Within current scope | M | L | Needs thumbnails per generation | M1 lineage history |
| IB-26 | Peaceful parity: a grazer or filter-feeder line has a viable non-violent path in every era | 12 Freedom of path, 16 Social | M3 onward, §8, §27 | Refinement of a proposal | H | M | Peaceful path becomes the easy path | IB-18 |
| IB-27 | Carry and drag: food and prey can be moved by mouth or grasping parts, so anatomy sets what can be hauled | 6 Cut features, 17 Combat | M3, §12, §14 | Refinement of a proposal | M | M | Physics jitter | IB-14 |
| IB-28 | Every exported GLB checked by glTF-Validator in `tools/check.sh` and CI (dev-only tool) | none directly; protects 2 Editors | M2, §16, §22 | Within current scope (tool approval needed) | M | L | Pre-release validator versions | OSS: glTF-Validator |
| IB-30 | Supported body scale range: a lineage can grow toward giant or shrink toward tiny over generations, with real consequences for feeding, speed, threat and what it can carry | 7 Body design, 12 Freedom; mod wishes 7 | M3, §7, §12 | Refinement of a proposal | H | M | Rig families must deform at both extremes | IB-14, IB-15, approved reshaping boundary |
| IB-31 | Sharing that degrades gracefully: an exported creature carries its part list and opens with visible placeholders when a part is missing, never a refusal | 8 Sharing; mod wishes 11 | After M3 with IB-09, §18 | Refinement of a proposal | M | L | Placeholder bodies look broken | IB-09 (needs the D4 decision) |
| IB-32 | Authored terrain variety: each habitat is built from a small set of Blender landforms (river, canyon, island, plateau) composed per seed, so worlds feel different to walk on | 15 Richer worlds; mod wishes 12 | M2 habitat, M3, §7, §15, §16 | Within current scope (needs the §15 procedural boundary) | M | M | Boundary for runtime placement not yet approved | OSS: ProtonScatter candidate; art team |
| IB-33 | Colour and material freedom: exact colour entry, per-region palettes and pattern layers in the editor, within the biome saturation discipline of §15 | 2 Editors; mod wishes 3 | M2 benchmark, M3 editor, §15 | Within current scope | M | L | Breaks art cohesion if unbounded | M2 material family |
| IB-29 | Online gallery of creatures (a Sporepedia-like service) | 8 Sharing | Not scheduled, §2 exclusions | Conflicts with Bible exclusion | H | H | Live service, moderation, network | Separate owner approval |

## Item notes

**IB-01 Trait ledger.** The player sees, at each era transition, a short page: "Your spiked hide kept ambush hunters
away 41 times; in the next era it becomes thick plating that slows you on slopes." Spore's parts stopped mattering
after the cell stage; here each trait has a recorded history and a defined meaning in the next era, and the
transition fails its own acceptance check if no trait carries forward with a gameplay effect. Smallest slice: in M1,
count events per part (bites, deterrences) into lineage history and show the totals on reproduction; test that a
save round trip keeps them. It needs no schema change if it lives in the existing lineage history field; if it does
need new fields, that is a save schema change for approval.

**IB-02 Why did that happen.** After death the player sees two or three lines: "The rammer hit you from behind; your
spike faces forward. You were at 8% energy, so you moved at half speed." Spore never explained losses, and Thrive is
called confusing; this turns the resolver's existing refusal reasons into teaching. Smallest slice: in M1 step 3,
keep the last five resolver results and energy states, and show them on the respawn screen.

**IB-03 Editor test space.** The player swims the edited body in a small, safe basin with one food and one slow
threat before paying. The Bible already requires a test space (§12); the Elysian Eclipse developers added undo and redo to fix accidental edits,
and the test space goes further by letting the player feel the change. Smallest slice: reuse the tide pool scene
with a fixed seed, no saving, and a "commit" or "back to editor" choice.

**IB-04 Before and after.** The editor shows the current and edited body's numbers in plain words, with icons and
text rather than colour alone. It beats a hidden stat change because the cost is visible before points are spent.
Smallest slice: a function that turns two phenotypes into sorted sentences, unit-tested in `game/domain`.

**IB-05 Rival species evolve.** Between the player's generations, each rival species may change one part, chosen by
how it fared (starved, eaten, thrived), and the journal reports it: "Rammers grew a second spike." Spore's rivals
never changed; Thrive's forum notes its rivals fell behind. We would reimplement the idea, never Thrive's code.
Smallest slice: a pure domain function that takes a species body, its survival tallies and a seed, and returns at
most one catalog-legal edit; tests check determinism and that it never exceeds the part caps.

**IB-06 Offspring variation.** On reproduction the player sees their designed child and two siblings with one small
inherited difference each, and picks which one to play. It sits between the designer fantasy (themes 2, 7) and the
selection camp (theme 5) without taking control away. Smallest slice: generate the two variants from a seed, show
their before and after (IB-04), and test that the points charged are the same for all three.

**IB-07 Staying aquatic.** A lineage that never leaves the water can still reach later eras through water-adapted
social and settlement play, with a clearly explained gate where land becomes necessary. The Bible already says never
to force a land build (§4); fans list the cut aquatic stage among the most wanted features. Smallest slice: a
written content plan for one aquatic alternative per later era, costed, before any build.

**IB-08 Shore gradient.** In shallows the player's speed and stamina blend between swim and walk values based on
fins and legs, so an amphibian is good at both and great at neither. This replaces a hard "land stage" switch.
Smallest slice: a phenotype function for blended locomotion by water depth, with a scenario test of two bodies on
the same shore route (the §6 acceptance form).

**IB-09 Offline sharing.** The player exports "My Creature.pangaea-creature" to a folder and a friend imports it.
The file is plain data (genome plus name), validated exactly like a save, and never contains code. It answers
theme 8 without a network call, service or account, so it avoids the §2 multiplayer and live-service exclusions and the `CLAUDE.md` no-network rule; it still
adds a new player-facing file format, so it needs approval. Smallest slice: export and import of a genome through the
existing validator, with tests for malformed, oversized and newer-build files.

**IB-10 Imported wildlife.** An imported creature can be released into the world as a wild species with its own
niche. It gives sharing a gameplay purpose that Spore's gallery did not have. Smallest slice: spawn one imported body
under the normal niche caps and check the ecology still recovers.

**IB-11 No random disasters.** Ecological trouble on colonies comes from things the player did (overharvesting,
introducing a species), with a forecast several minutes ahead and a choice of responses. Fans wrote mods to remove
Spore's frequent eco-disasters; the Bible already prefers observable consequences over hidden random punishment
(§2). Smallest slice: a regional model where harvest above regrowth lowers a visible health value and a forecast
appears before any loss.

**IB-12 Negotiable rivals.** Each rival civilization states what it wants and remembers what the player did, and
there is always a path to peace, trade or outlasting it. Some fans describe Spore's dominant empire as unbeatable and
unbefriendable, though others share strategies that beat it. Smallest slice: a rival with one goal, one memory list and three responses, tested for "a single
accident does not cause permanent war" (§8 rule).

**IB-13 Homeworld queue.** Requests from home wait in a list with deadlines measured in actions, not seconds, and
show what happens if ignored. Smallest slice: a queue with one request type and a visible, mild consequence.

**IB-14 Procedural gait.** Legs, fins and mouths reach their targets with Godot's built-in IK solvers, driven by our
own gait-template service written from the public Hecker 2008 idea and the common leg-stepping pattern. No add-on is
needed. Smallest slice: an M3 spike on Godot 4.7.2 with one Blender rig family, four legs, a slope, and a test of the
pure step-planning maths.

**IB-15 Shape-key boundary.** The editor stretches, thickens or lengthens parts by driving shape keys and bone scale
authored in Blender; nothing is generated at runtime. This keeps the Blender-source rule intact while giving the
variety fans loved. Smallest slice: one body segment with four shape keys, collision proxy refitted and tested at the
extreme values (§12, §16 step 5).

**IB-16 Attention.** A creature looks at what its perception system reports, and stops looking when it loses sight.
It shows intent before an attack, which supports readable combat (§14), and it uses perception rather than the
player's position (§13). Smallest slice: one eye spot bone on the M1 cell with a look-at target fed by the AI state.

**IB-17 Mood in motion.** Fear, effort and satisfaction show as pose and speed changes, with a short text label in
the accessibility settings. Smallest slice: three blended poses on one rig, captured at gameplay camera distance.

**IB-18 Placement matters.** Fins placed at the tail turn better; fins at the sides hold position; legs spread wide
stand steady but turn slowly. M1 already makes mouth and spike facing matter, and this extends the rule. Smallest
slice: one placement-sensitive stat (turning from fin position) in `phenotype.gd`, with tests that the same parts in
different places give different results.

**IB-19 Learned behaviour.** A companion that found a safe route teaches it to offspring, recorded in lineage
history. Smallest slice: one learned behaviour that survives a reload and a generation.

**IB-20 Anatomy-led tribe.** Settlement actions depend on the body: a digger builds burrows, a grasper builds huts,
a filter feeder tends plankton beds. The Bible asks for equivalent viable paths without hands (§9). Smallest slice:
one structure buildable by two different body types in different ways.

**IB-21 Co-evolved civilization.** Regional resources include the species the player lived alongside, with their
history. Smallest slice: one former prey species appears as a herd resource with its original id and record.

**IB-22 Open-ended eras.** The transition is always offered, never forced; staying gives new goals and harder
conditions. Fans say Spore reached space too quickly. Smallest slice: in M4, a "stay" choice at the transition
screen, and one follow-up goal.

**IB-23 Pushback preset.** On the harder preset, a dominant player sees rivals adapt and food shift away, which
rewards learning rather than reflexes (Thrive developers' point). Smallest slice: depends on IB-05; one rule that
raises rival adaptation rate when the player's niche share passes a threshold.

**IB-24 Field notes.** Each discovery has an optional, short real-biology note. It speaks to the science camp
without changing the CONFIRMED stylised look. Smallest slice: notes for the six M1 parts, written in our own words.

**IB-25 Lineage album.** A page of every generation's body, with the change made and how long it survived. Smallest
slice: a list view from existing lineage history; thumbnails later.

**IB-26 Peaceful parity.** A filter-feeder line can reach every era without killing, through grazing, avoidance,
alliances and trade. Smallest slice: a scenario test where a grazer completes the M1 two-generation loop without a
bite or ram.

**IB-27 Carry and drag.** Prey and food can be dragged to a safe spot, with mouth or grasping parts setting what can
be carried. Smallest slice: in M3, one carry interaction in the resolver with a size limit.

**IB-28 GLB validation.** Every exported asset is checked by Khronos glTF-Validator before Godot import. Smallest
slice: one CI step on the sample cell GLB. Needs approval as a dev-only tool.

**IB-30 Body scale range.** The most-made "play as something else" mods let players be a giant, half a giant, or
tiny, and pick up smaller creatures (`mod-wishes.md` wish 7). GENESIS can answer that originally: a lineage's size
is a trait with costs (energy, turning, exposure) and payoffs (reach, intimidation, carrying). Smallest slice: in M3,
two size tiers for one rig family with the phenotype service scaling speed, bite reach and energy use.

**IB-31 Graceful sharing.** Three independent mod sources warn that custom parts broke sharing with vanilla players,
and creators advertise "vanilla compatible" as a feature (wish 11). Whatever shape IB-09 takes, a shared creature
file should list the parts it needs and open with marked placeholders when one is missing. Smallest slice: a save
fixture with an unknown part id that loads with a placeholder and a warning, not an error.

**IB-32 Authored terrain variety.** "25 New Planets" and the adventure packs exist because players found Spore's
terrain samey (wish 12). GENESIS habitats can be composed from a small set of Blender-authored landforms placed per
seed, inside the procedural-placement boundary §15 asks us to define. Smallest slice: the M2 habitat built from four
landform pieces, two seeds compared side by side.

**IB-33 Colour and material freedom.** Nine colour, paint and texture mods (wish 3) say players wanted exact colour
control and more pattern options. Within the §15 saturation discipline, the editor can offer hex entry, three colour
regions and a pattern layer. Smallest slice: hex entry plus two regions on the M2 benchmark creature's material
family.

**IB-29 Online gallery.** Listed so the demand is recorded. It is a live service (excluded by §2) and needs network
calls (barred by `CLAUDE.md` without approval), accounts and moderation. Not recommended for the initial production scope; IB-09 is the offline alternative.

## Recommended for Joshua's decision now

These four are vision-level or scope choices that shape M2 and M3 work. Each is phrased for a decision card. All
options are PROPOSED until Joshua chooses.

### D1. How should evolution work beyond the player's own edits? (IB-05, IB-06, IB-23)

Context: fans' fifth-ranked theme asks for real selection and rivals that evolve; their second and seventh themes
love designing the body directly. The Bible makes the player the designer (§3, §12) and gives the ecology aggregate
populations (§13), but says nothing about rivals evolving.

- **A. Player designs; rivals stay as hand-tuned species.** Simplest; matches the Bible today; the world feels static
  across generations.
- **B. Player designs; rival species evolve between generations by bounded, visible rules.** Adds a domain service
  and journal entries; rivals keep up with the player.
- **C. B plus offspring variation:** each reproduction offers the designed child and two small inherited variants.
  More "evolution" feel, more UI.
- **D. Selection-led:** the population evolves and the player only nudges. Changes the core fantasy; not recommended.

**Recommendation: B**, built first as an M3 spike with tests, with C trialled later as an optional setting. It answers
the living-ecosystem complaint without taking the editor away.

### D2. Should a lineage be able to stay aquatic past the terrestrial era? (IB-07, IB-08, IB-22)

Context: the cut aquatic stage is among the most requested missing features (theme 6), and fans want freedom of path
(theme 12). The Bible forbids forcing a land build and requires bounded content plans for alternative paths (§4,
§26). This needs deciding before the M4 transition slice is briefed, and it affects M3 rig families.

- **A. Land is required for era 3 on; water stays useful through the shore gradient.** Lowest cost.
- **B. Aquatic play stays viable through the Social era, with an explained gate before Tribal.** One extra content
  variant for era 4 only.
- **C. A full aquatic route to the Interstellar era.** Highest appeal and roughly doubles later-era content.

**Recommendation: B**, with the shore gradient (IB-08) either way. It honours the "never force" rule and the fan
demand while keeping later eras to one main content path.

### D3. May the editor reshape Blender-authored parts at runtime, and how far? (IB-15, IB-14)

Context: the Bible allows runtime deformation only on Blender-authored meshes inside an approved boundary (§12, §15),
and the OSS brief found no permissive creature-mesh library, so this boundary decides how varied bodies can look in
M3. It should be decided before the M2 benchmark creature is rigged.

- **A. Fixed parts only:** move, rotate, mirror and uniform scale. Safest; least variety.
- **B. Shape keys and bone scale authored in Blender, driven at runtime within set limits.** Spore-like variety with
  every mesh Blender-sourced; collision proxies refit and tested at the extremes.
- **C. B plus a runtime "blob" body skin generated in our own code.** Closest to Spore's look; furthest from the
  pipeline; research spike only.

**Recommendation: B.** It needs no new dependency, keeps the Blender rule, and gives the editor real expressiveness.

### D4. Should players be able to share creatures, and how? (IB-09, IB-10, IB-29)

Context: sharing is theme 8 (high strength) and was central to Spore's success. The Bible excludes multiplayer and live
service from initial scope (§2), and `CLAUDE.md` bars network calls without approval. File-based sharing avoids the network but adds a new file format.

- **A. No sharing in the initial production scope.**
- **B. Offline export and import of creature files, validated like saves, no network.** Answers most of the demand at
  low cost; can start after M3.
- **C. B, plus imported creatures can live in your world as wild species.** Gives sharing a gameplay purpose; later
  milestone.
- **D. An online gallery.** Conflicts with the §2 exclusions; needs separate approval and a service.

**Recommendation: B now, with C considered at M5.** It gives players a way to show off creations without accounts,
servers or the risks fans associate with EA's online features.

### Decisions to schedule later

- **Era length (IB-22):** whether eras are open-ended. Decide with the M4 brief (§26).
- **Pushback difficulty (IB-23):** depends on D1. Decide with the difficulty presets already open in `DECISIONS.md`.
- **Interstellar rules (IB-11, IB-12, IB-13):** decide before the M8 brief.

## No approval needed

These items are engineering or tuning inside approved scope (Bible requirements, the approved M1 brief, or built-in
engine features). They are still PROPOSED design until built and verified, and they must stay inside the M1 scope
caps where they land in M1.

| ID | Why no approval is needed | Earliest point |
| --- | --- | --- |
| IB-02 | Uses the resolver's existing refusal reasons (§14 requires failed actions to explain themselves). | M1 step 3 |
| IB-03 | The Bible requires an editor test space (§12); only its timing is a choice. | M1 step 4 or M3 |
| IB-04 | Cost and stat preview are required (§5, §12); plain-language tooltips are required (§19). | M1 step 4 |
| IB-14 | Rig families and gait templates are required (§12); the IK solvers are built into the pinned Godot. | M3 spike |
| IB-16 | Built-in modifiers; §2 and §15 ask for eyes and pose that show attention. | M2 |
| IB-17 | §20 asks animation to show attention, fear, effort and satisfaction. | M3 |
| IB-24 | The discovery journal is required (§19); notes are text. | M1 step 6 or M3 |
| IB-25 | Lineage history already exists; this is a view of it. | M1 step 4 or M3 |
| IB-28 | Dev-only check that fits §16 and §22. The tool itself still needs a yes as a dependency (CLAUDE.md). | M2 |
| IB-32 | Habitat art is M2 work already; this only asks that landforms be modular. The runtime placement boundary still needs the §15 approval. | M2 |
| IB-33 | Editor colour controls are inside the editor scope; §15 bounds them. | M2 benchmark, M3 editor |

Items IB-01, IB-08, IB-18, IB-26 and IB-27 refine proposed era mechanics. They need no scope approval, but they
belong in the relevant milestone brief so Joshua approves them along with that brief. IB-01 may also need a save
schema change, which would need approval on its own.
