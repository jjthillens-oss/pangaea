# Skeptic review of the two research briefs

**Status:** PROPOSED research review, not approved design. **Date:** 2026-10-22.
**Reviewed:** `docs/research/community-wants.md` and `docs/research/open-source-scout.md`.

## How this was checked

Each claim was checked by loading the cited page on 2026-10-22 with an automated fetch-and-summarise tool and
asking for the exact wording or number. That tool can itself make mistakes, so "confirmed" means "the page,
as summarised, says this". Pages were not read by a human. Nothing was installed or run.

Verdicts: **confirmed** (source says it), **corrected** (source exists but the brief overstated or misattributed;
edited), **unverified** (could not confirm in this pass; left as is), **removed** (fabricated; none found).

## Part 1: community-wants.md (20 citations checked)

| Ref | Claim checked | Verdict |
|---|---|---|
| 19 Engadget/Joystiq poll | Editors 4.37/5; 68.6% creature editor favourite; building editor least liked 67.75%; Tribal 2.26/5 and 37% least favourite; Space 36% favourite; no sample size | Confirmed numbers (Tribal 37.23%, Space 36.27%). **Corrected** theme 2 table: 4.37 is the average for all editors, not the creature editor. |
| 2 Soren Johnson | "perpetual compromise"; "could have worked either as a cute game or as a scientific one"; cute/science teams; parts with fixed ("canned") stats | Confirmed |
| 4 Axios, Wright | "much more of a toy than a game"; "didn't hang together as a game"; several linked games; hardcore fans found levels too light | Confirmed |
| 10 Steam, Spore | 92% positive of about 38,000 English reviews | Confirmed (38,456) |
| 9 Steam, Thrive | 92% of 1,695; Early Access Nov 2021; about 120 months; only microbe stage complete | Confirmed |
| 41 EA News | 100 million uploads by 4 May 2009; about 307,000 a day | Confirmed. "Under a year" holds (Creature Creator launched June 2008). |
| 45 Thrive review tally | 28% science, 32% potential, 21% Spore, 17% depth/replayability | Confirmed. It is one forum member's informal tally of "100+" reviews; the brief already says so. |
| 31 Wikipedia, Spore | Shallow first four stages; *Science* fails for evolution; DRM one-star reviews; most torrented game of 2008 | Confirmed facts. **Corrected** wording: the brief said the DRM "made it the most torrented game"; Wikipedia does not claim that cause. Added the Amazon figure (2,016 of 2,216 one-star). |
| 1 Steam wish-list (2022) | "effectively a sequence of minigames"; "actual evolution mechanics"; "divine intervention"; "tacked-on"; microtransactions; dodging, third person | Confirmed, all six |
| 8 PC Gamer, Eternal Cylinder | mutations "surprisingly dull" | Confirmed (review score 70) |
| 39 Wikipedia, Eternal Cylinder | Metacritic 79 to 82 | Confirmed (PC 79, PS4 80, Xbox One 82) |
| 33 SteamSpy, Species: ALRE | 74% user score | Confirmed, but SteamSpy labels it "Old userscore"; it may be stale. |
| 36 Steam stage ranking | Tribal worst in 4 of 6 clear rankings; "a slower and more boring version of Civilization" | Confirmed (4 worst-to-best plus 2 best-to-worst lists; 4 name Tribal worst) |
| 44 Spore Wiki, removed features | Aquatic stage cut after the 2005 demo for navigation and animation problems; eggs, baby care, carrying food, underwater cities | Confirmed. Note: the "most hyped and requested" quote is from ref 47, not ref 44. |
| 47 Elysian Eclipse devlog | "one of the most hyped and requested"; undo/redo fixed "a huge issue"; built aquatic stage "because fans asked" | Quotes confirmed. **Corrected** "because fans asked": the post does not say that. Date "late 2022" is inferred from neighbouring posts (between Oct 2022 and Feb 2023); acceptable. |
| 3 bit-tech | "Five mini-games" only partly fair; oversimplification the bigger mistake; Space stage praised; nostalgia | First three confirmed. **Corrected** the Limits section: bit-tech raises nostalgia only as one possible explanation and says the answer is "more complex"; it does not make a childhood point. |
| 17 You Should Play | "an astonishing technical feat"; Civilization "plays reasonably well" but too simple | Confirmed |
| 7 Steam eco-disaster thread (2017) | Players wrote mods to remove eco-disasters and raids | Confirmed (a "NoDisastersPirateFix" package is shared in the thread) |
| 42 Wikipedia, Galactic Adventures | Adventure Creator "complex yet easy to use" | Confirmed, but it is Wikipedia's unattributed summary of reviews, not a named critic. |
| 20 Carl Zimmer (23 Oct 2008) | Biologists gave failing grades for mutation and selection | Confirmed in substance (clones, no consequence for dying). The letter grades themselves are in ref 31. |
| 34 Reddit r/Spore, "Killing Grox" (Jul 2024) | Hostile empire "nearly impossible to defeat or befriend" | **Corrected.** The post describes a strategy that is "working very well". Now marked as dissent in theme 4. |

**Quotes.** No quote over about 15 words was found, and no quote looked invented: every quote checked was found
on its page. **Fabricated citations:** none found.

**Frequency counts.** No case of one article syndicated under several refs was found. Cautions:

- Ref 14 (Vaporlens) is a machine summary of Steam reviews and is counted in four themes (4, 8, 13, 14). It is
  not an independent voice; if it were dropped, each of those counts falls by one. Ranking would not change.
- Refs 31, 39 and 42 are Wikipedia summaries of press reviews, so one ref stands for many critics, and the
  critics are not counted separately. This under-counts press views rather than inflating them.
- Some counted refs are dissent (ref 3 in theme 1, ref 4 in theme 9, ref 34 in theme 4, ref 37 in theme 10).
  The counts measure "sources that discuss the theme", not "sources that agree". That is fine, but the table
  header "Freq." could be read as agreement.
- Refs 1, 21, 26 and similar fan threads each count once, which is the stated rule and was followed.

## Part 2: open-source-scout.md (20 rows checked)

| Row | Claim checked | Verdict |
|---|---|---|
| Godot IK framework | IKModifier3D, TwoBoneIK3D, FABRIK3D, CCDIK3D, JacobianIK3D, SplineIK3D in 4.6; article 16 Dec 2025 | Confirmed (article also lists ChainIK3D and IterateIK3D). **Corrected** the risk note: the 4.6 page says "Documentation is in the works", not "still in progress". |
| LimitAngularVelocityModifier3D, BoneTwistDisperser3D | In the 4.6 IK article | Confirmed |
| Jolt module | MIT, Jolt 5.6.0; default for new 3D projects since 4.6 | Confirmed ("make Jolt the default physics engine for all new 3D projects"; existing projects keep their setting). `project.godot` sets no engine; which engine an unset setting picks on 4.7.2 is **unverified** and should be checked in the editor. |
| Godot Jolt extension | MIT; maintenance mode | Confirmed |
| Godot LOD / meshoptimizer 1.2 | MIT; LOD shape preservation improved in 4.6 | Confirmed (thirdparty README lists meshoptimizer 1.2, MIT). The 4.6 page does not name the library. |
| AccessKit | MIT, 0.22.3 | Confirmed |
| LimboAI | MIT-style code; CC-BY-4.0 demo art and logo; 4.6+ GDExtension, 4.7 module; v1.8.1, 2026-08-20 | Confirmed. The CC-BY demo-art trap is already flagged. |
| Terrain3D | MIT | Confirmed. Version/date (v1.0.2, 19 May) and the 4.4 to 4.6 range **unverified** (repo page showed no release data). |
| ProtonScatter | MIT; Godot 4; Codeberg mirror | Confirmed. **Corrected:** added an asset trap the scout missed. The README says most bundled textures are from Textures.com and may not be redistributed on their own. |
| Phantom Camera | MIT; 4.4+ | Confirmed. Release v0.11.0.3 and date **unverified**. |
| Dialogue Manager | MIT; v4 needs Godot 4.6+ | Confirmed. v4.1.0 date **unverified**. |
| Beehave | MIT; table says 2.10+ for 4.5+ | Confirmed table. The scout's note that the table and release list disagree stands. |
| Debug Draw 3D | MIT (addon LICENSE) | Confirmed. Ships a native binary built with godot-cpp (MIT); keep it out of release exports, as noted. |
| glTF-Validator | Apache-2.0 | Confirmed. It is written in Dart; the release tag and "prebuilt packages attached" are **unverified**. Using it in CI means pulling a binary or an npm package, which is a new tool dependency (the scout already says approval is needed). |
| meshoptimizer / gltfpack | MIT; v1.2 | Confirmed license; v1.2 appears current. gltfpack flag behaviour not rechecked. |
| Thrive | GPL-3.0-or-later with a mod-linking exception; 1.6.0 on 30 Aug (2026, inferred); asset license not stated | Confirmed, including the inferred year. Reference-only is correct. |
| Poly Haven | CC0; logos, renders, site text excluded; no scraping | Confirmed |
| ambientCG | CC0, no exceptions listed | Confirmed |
| Kenney | CC0; logo reserved | Confirmed |
| Freesound | Per sound: CC0, CC-BY 4.0, CC-BY-NC 4.0, legacy Sampling+ | Confirmed. CC-BY sounds need credit (title, user, URL, license); the brief's "record credit" covers this. |

**Copyleft mislabelled permissive:** none found. MPL-2.0 is correctly described as weak copyleft; GPL, LGPL,
CC-BY-SA and NC are correctly reference-only. **Not checked:** GUT, gdUnit4, Spatial Gardener, Godot Input
Helper, Many Bone IK, GodotIK, godot_voxel, godot-marching-cubes, glTF-Blender-IO, OpenGameArt, and the
research-paper table (the scout already marks several of those citations UNVERIFIED).

## Part 3: project rules

| Rule | community-wants.md | open-source-scout.md |
|---|---|---|
| Labelled PROPOSED | Yes | Yes |
| No Spore files | Yes; public pages only | Yes; Spore listed as design benchmark only, citing the 2026-10-22 decision |
| No GPL code reuse | Thrive used only for player opinion | Thrive, Blender and Blender add-ons reference-only |
| Blender-mandatory meshes | Not relevant | Respected: every mesh path keeps a `.blend` source; runtime meshing needs an approved boundary |
| No new dependencies without approval | Not relevant | Respected: nothing adopted; each Adopt-candidate says approval is needed |
| No scope change | Respected: online sharing flagged as out of scope, not argued for | Respected |

One soft point: the scout's top recommendation 4 builds on Hecker et al. (Spore's own animation paper).
Reimplementing a published technique is legal and the scout says to write our own code, but the owner may want
to know that a core system would follow Spore's published method closely.

## Edits made

`community-wants.md`: (1) bit-tech nostalgia point softened; (2) theme 2 table: 4.37 credited to all editors,
with the 68.6% creature-editor figure added; (3) theme 4: ref 34 marked as dissent in the table and text;
(4) theme 6: "because fans asked" replaced by the devlog's own words; (5) theme 14: DRM-to-piracy cause
removed, Amazon figure added.

`open-source-scout.md`: (1) IK row docs quote fixed; (2) ProtonScatter row: Textures.com asset warning added.

`innovation-backlog.md`: see Part 4.

No citation was removed. I committed nothing (see the note in Part 4).

## Part 4: innovation-backlog.md (added at the coordinator's request)

**Theme citations.** All 29 items cite theme numbers and names that match `community-wants.md` after the edits
above (for example 5 "living ecosystem", 6 "cut features", 10 "Tribal / Civilization"). D1's "fifth-ranked" and
"second and seventh" themes are right. Two item notes leaned on claims this review corrected:

- IB-12 said fans call the dominant empire unbeatable; **corrected** to note that some fans share winning
  strategies (ref 34).
- IB-03 said fans praised undo and redo in Elysian Eclipse; ref 47 is the developers' own devlog. **Corrected.**

**Type labels.** Checked each against the Bible text. All are honest:

- Scope changes (IB-05, 06, 07, 09, 10, 15) each add a system, file format, route or deformation boundary the
  Bible does not yet approve. IB-07 could be called a refinement (§4 already forbids forcing a land build), but
  "scope change" is the safer label because §4 also requires a bounded content plan.
- "Within current scope" items match real Bible requirements: editor test space and cost preview (§12),
  failed actions explain themselves (§14), discovery journal (§19), animation shows attention, fear, effort and
  satisfaction (§20), rig families and gait templates (§12). IB-28 correctly adds "tool approval needed".
- Refinements match Bible proposals: learned behaviour between generations (§8), carrying by grasping parts
  (§12 anatomy table), tools as extensions of anatomy without requiring hands (§9), no hidden random punishment
  (§2), "a single accidental" act not causing permanent hostility (§8).
- IB-29 is correctly "conflicts with exclusion" (live service).

**Corrected:** the backlog listed "network" as a §2 Bible exclusion in three places (scoring method, IB-09/IB-29
notes, D4). The Bible's exclusions are multiplayer, live service, blockchain, user scripting, paid marketplace,
unrestricted universe simulation and runtime language models; the no-network rule comes from `CLAUDE.md`. Wording
now names each source.

**Not changed, but worth knowing:** the stated rule for Value H ("a top-7 theme with high strength") is applied
loosely. IB-05, IB-07 and IB-08 rest on themes rated medium-high; IB-09 and IB-29 on theme 8 (ranked 8th);
IB-26 on themes 12 and 16 (medium). These are judgement calls, but the owner should not read H as strictly
evidence-backed. Also, the Bible text places the exclusions list just after the §2 heading, while
`community-wants.md` calls it "§1 Explicit exclusions"; the PDF layout makes this ambiguous, so neither was changed.

**Note on commits:** my edits to the two briefs and an early skeleton of this review were included in commit
823750b by another agent. I made no commit myself.

## Remaining risks and biases

- **Reddit is under-sampled** (two threads via mirrors), and one of the two turned out to argue against the
  claim it was cited for. YouTube, the biggest place for Spore retrospectives, is nearly absent.
- **Hardcore skew.** Steam threads, CivFanatics and the Thrive forums are long-time fans; casual and younger
  players, who may value the cartoon tone and the short stages, are barely heard.
- **The 2008 poll is self-selected** Joystiq readers with no sample size. Treat its percentages as indicative.
- **Machine summaries all the way down.** The briefs and this review both read pages through a summarising
  tool. Before any quote is used publicly, a person should open the page.
- **Version dates without years.** Several scout rows infer the year; four release versions are unverified.
  Re-check on the day any add-on is proposed for approval, and test on 4.7.2.
- **Ten scout rows and about 30 community refs were not checked** in this pass.
