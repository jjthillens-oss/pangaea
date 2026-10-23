# Workstream D: evidence review

Status: PROPOSED review, written 2026-10-23 by workstream D (independent reviewer). This file checks claims; it adds
no new research about Spore. Labels and source IDs follow `../LEGAL_RESEARCH_BOUNDARIES.md` and `../SPORE_RESEARCH.md`
§3. No other file was edited.

Scope: the eight files in `docs/research/spore/`, the three workstream files (`community_tools.md`,
`creature_editor.md`, `locomotion.md`) and the 2026-10-23 entry at the end of `docs/DECISIONS.md`.

Method: text copies of the primary PDFs (S1 Hecker et al. 2008; the four SIGGRAPH 2007 sketches, plus the Rigblocks
slides) were searched for each claim. The EA User Agreement, both EA patents, the marching-cubes patent, S12, S13,
S14 and S17 were fetched on 2026-10-23. Godot class claims were re-run against the pinned 4.7.2 binary with a scratch
`ClassDB` script (outside the repo). S7 (chrishecker.com) was still down ("The site is temporarily down"), and
StrategyWiki returned HTTP 403, so claims resting only on those could not be checked. GitHub API access to the
community repos was not available; only the commit hashes in the existing scratch clones were compared, by reading
`.git` refs as files (no git commands).

## 1. Summary verdict

**The research is mostly accurate and unusually careful about where it came from.** Of 34 claims checked, 26 are
verified, 5 are partly supported, 1 is not supported and 2 could not be checked. Almost every number taken from S1,
the sketches, the patents and the press articles matches its source word for word. No copied code, struct layouts,
addresses or data tables were found.

The problems are of four kinds:

1. **Labels are looser than the folder's own rule.** `LEGAL_RESEARCH_BOUNDARIES.md` reserves CONFIRMED for
   primary sources, but CONFIRMED is also applied to Wikipedia (S10), journalist reports (S12, S13, S17) and a
   search-engine summary of a page nobody could open (S7). `creature_editor.md` widens the definition to
   "developer-quoted" sources on its own authority. The CSV marks single-source rows "independently verified".
2. **One S3 claim is overstated.** "Order does not matter" for rigblock deforms is not what S3 says. S3 says that
   summing Euler angles, as Maya does, would make the result order-independent. Spore's engine instead
   concatenates quaternions, which in general is not order-independent.
3. **Documents written at different times contradict each other.** This covers the creature size target
   (2–5 KB, 4 KB and 8 KB are all cited, while the probe measured 4.6 KB), the Stage 1 acceptance criteria (they
   include a 33 ms preview that the probe already shows GDScript cannot meet), the limb hierarchy depth, gait-table
   authoring, three competing "first prototype" proposals, two overlapping domain classes
   (`BodyDescriptor` vs `BodyMechanics`), and an animation performance budget that no estimate meets.
4. **Hygiene risk sits mainly in `community_tools.md` and the scratchpad.** That file names reverse-engineered
   ModAPI header files and EA data concepts. Full clones of Spore-ModAPI (including its Ghidra scripts and the
   "reconstructed Spore source" pages) are still sitting in the session scratchpad, where any later agent in this
   session can read them.

The legal notes cite every case correctly. A few sentences read as legal conclusions and should be softened (§6).

**Does it reduce implementation work?** Yes, for architecture and for avoiding dead ends; no, for the hard
engineering and tuning. Details in §8.

## 2. Checked claims

Verdicts: **V** verified, **P** partly, **N** not supported, **?** could not check.

| # | File | Claim | Source checked | Verdict | Note |
| --- | --- | --- | --- | --- | --- |
| 1 | SPORE_RESEARCH §2/LEGAL §2 | EA UA §2 forbids reverse engineering / extracting source code or data, "unless expressly authorized by EA or permitted by law"; "You may not access, copy, modify or distribute any EA Service, Content or Entitlements" | tos.ea.com, "Last Updated: May 14, 2026" | V | Wording and date match. |
| 2 | LEGAL §2 | §7.A "Attempting to circumvent, disable or tamper with these measures shall terminate this license"; §7.C defines Unauthorized Third-Party Program incl. "intercepts, 'mines', or otherwise collects information" | same | V | Section headings also match (7.A, 7.C). |
| 3 | LEGAL §2 | §6 "Do not engage or assist in cheating ... or using exploits"; §13(B) country-of-residence list (EEA, UK, Switzerland, Brazil, Hong Kong, Mexico, Russia) | same | V | §13(B) has a separate US/Canada/Japan clause; the file does not quote it. Quote it, because it is the clause that applies to the owner. |
| 4 | CREATURE_CREATOR §1.1, SPORE_RESEARCH §4 | Bodies form a DAG with a serial spine chain at the root; general graphs/loops dropped because "the interface complexity of a general graph was actually a hindrance to player creativity" | S1 §1.2 + footnote 1 | V | Exact quote. |
| 5 | creature_editor §2.1 | "Characters usually contain between 20 and 80 bodies"; root chosen by heuristic on incident leg limbs and position; rest pose = creation pose | S1 §1.2 | V | |
| 6 | PROC_ANIM §2.3 | Three-valued branch predicates UprightSpine, HasGraspers, HasFeet; variants per grasper; game picks nearest grasper | S1 §4.1 | V | |
| 7 | PROC_ANIM §2.4, locomotion §3.1, CSV P005 | Legs clustered into groups "of roughly equal length", ratios approximated by "small rational numbers"; authored params for 1 ≤ nfeet ≤ 6, generated for ≥ 7; float/crawl heuristic; pseudo-feet with inch-worm gait | S1 §4.2 | V | |
| 8 | locomotion §3.1 | Gait separate from retargeting "for historical reasons"; "two short legs could be running while four long legs are trotting" | S1 §4.2 | V | |
| 9 | PROC_ANIM §2.5, locomotion §6.1 | Particle IK: per-end "mass" as tuning, nonlinear length correction after Jakobsen, C1 piecewise soft constraints, two phases, quintic Hermite needed where cubic failed, anti-buckling, CCD/Jacobian/constrained dynamics tried and rejected | S1 §4.3 | V | |
| 10 | locomotion §6.1 | S1 constants: 5 outer iterations, 10% limb compression, 10%/120% shrink/stretch | S1 §4.3.2 | V | Correctly marked "not adopted". See hygiene H4. |
| 11 | PROC_ANIM §2.7, CSV P006–P008 | ~0.2 ms per frame for a 25-body creature on a 1.7 GHz Pentium-M; ~35% in IK; ~90% pass rate; "several hundred creatures and a thousand animations" | S1 §5 | V | Numbers exact. CSV `result_type` "independently verified" is wrong (single source); see L5. |
| 12 | CREATURE_CREATOR §1.5, locomotion §3.1 | "The in-game editor begins playing animations on the character as soon as the player adds feet, mouths, or graspers." | S1 §5 | V | Exact quote. |
| 13 | locomotion §4.1, §6.1 | S1 future work: "believable locomotion with anticipation in the face of discontinuous player and code inputs"; limitations: no volume ("hug", "rub chin"), no intra-character collision, anti-buckling heavy-handed, singularities | S1 §5 | V | |
| 14 | CREATURE_CREATOR §1.1 | Deform curves "mouth open/close, hand open/close, eyes blink, ears droop, toes bend" | S1 §1.2 | P | S1 says "opening and closing hands, mouths, or eyes, ears drooping, toes bending". "Blink" is a paraphrase; fine in substance. |
| 15 | CREATURE_CREATOR §1.2 | S3: deforms parameterized over the unit interval, driven by handles; morph targets supported but avoided for memory/runtime cost; subranges give different styles; baked at the end | S3 abstract | V | |
| 16 | CREATURE_CREATOR §1.2 | S3: deforms compose additively "so applying one does not undo another **and the order does not matter**" | S3 abstract §3 | **N** (second half) | S3: Maya sums Euler angles, which makes the result order-independent; "we concat quaternions". So in Spore's engine, rotation composition is in general **not** order-independent. Additivity and "does not undo" are supported. |
| 17 | creature_editor §2.1, §4.1 | S3 slides: "Base block is a special block: body mesh"; "Adjust spline, glue limbs"; "Mesh generated via metaballs"; "Single texture page, single material"; "Generate LODs"; low-bone-count runtime versions of animated blocks | Rigblocks slides | V | Strongest primary evidence for the metaball skin; it should replace S7 as the main citation (fix F3). |
| 18 | SPORE_RESEARCH S4, CREATURE_CREATOR §1.4 | Swarm particle brushes paint diffuse, specular and bump; base/coat/detail scripts; themes; cubemap-partition UVs; SH lighting | S4 sketch | V | |
| 19 | SPORE_RESEARCH S4 | Player picks scripts "and **two** colours" | S4 sketch | P | For creatures S4 says "parameterized by player-selectable colour" (no count). "Two palette colours" belongs to the building/vehicle texturing text. |
| 20 | CSV P009, P010 | Planet maps "stored as six face grids"; Halton bases 2, 3 (and 5 for 3D), incremental version | S5 §2, S6 §2 | V | |
| 21 | SPORE_RESEARCH S15, creature_editor §4.1 | Patent: store "only the instructions (or the 'recipe')"; "approximately 2-5 Kbytes"; "might be compressed"; "Creature animation is also recreated from procedural data" | US7789758B2 and US7867093B2 (Google Patents) | V | Both patents carry the same text, in a creature context. |
| 22 | LEGAL §3 | US7789758B2 active, est. expiry 2028-10-25; US7867093B2 est. 2027-12-31; inventor Will Wright; priority 2006-03-10; independent claims about server-based download/upload of instructions and an in-game browser | Google Patents | V | US7867093B2 is listed "Active – Reinstated" (it lapsed once). Worth stating. |
| 23 | LEGAL §3 | US6141019A (Roseborough, Kostolansky, del Palacio; priority 1995-10-13) expired | Google Patents | V | "Expired – Fee Related", anticipated expiry 2016-10-11. |
| 24 | CREATURE_GEOMETRY §1 | Marching cubes patent US 4,710,876 expired in 2005 | Google Patents | V | Anticipated expiration 2005-06-05. |
| 25 | CREATURE_GEOMETRY §1, §5 | Surface Nets is "public and unpatented as far as we know" | Search: US 6,084,593 "Surface net smoothing for surface representation from binary sampled data" (MERL/Gibson, filed 1998) | P | There **was** a surface-nets patent. It was filed in 1998, so it has almost certainly expired (20-year term). Expiry not confirmed from the register. Say "patented (US 6,084,593), expired" once confirmed. |
| 26 | CREATURE_GEOMETRY §1, SPORE_RESEARCH S7 | Hecker avoided marching cubes because of the live patent, used ear-clipping; spheres only; ellipsoids too slow | S7 (site down) | ? | Only "search summary" evidence. Workstream B's own summary of S7 mentions neither ear-clipping nor the patent. Treat as unverified until S7 is read. |
| 27 | SPORE_RESEARCH S12, CREATURE_GEOMETRY §1 | Gingold: "3D bean", vertebra-like points, "deep structure", "all living things are symmetrical", 20k picture vs 4k creature, legs hardest, "fuzzy interpretation", "small enough to send over networks" | Game Developer, N. Evan, 2008-06-26 | V | |
| 28 | SPORE_RESEARCH S13, PROC_ANIM §2.8–9 | IEEE Spectrum (Kushner, 2008-09-01): looped spines removed; "walking ratio"; "twice as many legs on one side ... one to two"; torso and head dimensions; mouth as a hand; "inchwormlike slither"; 20 artists and 7 programmers; > 1 million creatures in 8 days | IEEE Spectrum | V | |
| 29 | creature_editor §2.1 | S13: "Legs and limbs can be stretched and curled like clay" | IEEE Spectrum | P | S13 says creature *features* "can be stretched and curled like clay". It does not single out legs. |
| 30 | SPORE_RESEARCH §1.6, S14 | Johnson: "the player's creativity in designing the creature's shape has no impact on actual gameplay"; foot stats fixed "regardless of the position of the foot, the length of the attached limb, or the shape of the body"; procedural animation finished late | Game Developer, 2013-10-02 | V | |
| 31 | community_tools S17 | Bradshaw: creature file "about 8 K"; abilities come from parts; limb manipulation depends on facing; symmetry | MIT Technology Review, Naone, 2008-06-17 | V | |
| 32 | PROC_ANIM §1 | Bible requires "anatomy must affect gameplay" | Bible text (scratch copy) | P | The Bible says "Creature anatomy must meaningfully influence gameplay." The spec's quotation marks around a paraphrase should go. The quoted §7 line "Limb placement influences support, reach, gait, and turning" is exact. |
| 33 | locomotion §7.4, CREATURE_GEOMETRY §6 | Godot 4.7.2 has `IKModifier3D` → `ChainIK3D` → `IterateIK3D` → `FABRIK3D`/`CCDIK3D`/`JacobianIK3D`; `TwoBoneIK3D`, `SplineIK3D`, `LookAtModifier3D`, `SpringBoneSimulator3D`, `JointLimitationCone3D`; `IterateIK3D.deterministic`; `IKModifier3D.mutable_bone_axes`; `Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS`; `Skeleton3D.modifier_callback_mode_process` | Pinned binary, ClassDB re-run | V | All exist with the stated parents. |
| 34 | CSV P002–P004, SPORE_RESEARCH §4B | Four social and four combat abilities, five levels each (named in CSV notes) | S11 (fandom 402, StrategyWiki 403 today) | ? | `creature_editor.md` §0 reports both wikis unreachable on 2026-10-23. The CSV says "Read community wiki" on that date, so where these values came from is unclear. |

Also checked and consistent with the reviewer's own knowledge (not fetched): the bibliographic details of L2, L3,
L4, L5, L7, L8, L10, L15, L17 in `locomotion.md`, and the arithmetic in `locomotion.md` §2 (the inequality
β·λ·c ≤ 2·√(1 − c²) and the trial walk ratio of 1.02 imply Fr ≈ 0.25 under L3, which is plausible). The probe
arithmetic in `creature_editor.md` §5 ("6–18× too slow": 203/33 and 578/33) and `locomotion.md` §6.4
(0.2–0.3 ms × 50 = 10–15 ms) is correct. Commit hashes for C1–C3 match the scratch clones' refs. Not checked: REA
star counts and the ceos3c post (§2.2), S8, S16, S21, S22, and the owner quotes in DECISIONS (thread not visible
to this reviewer).

## 3. Label problems

| ID | File, place | Problem |
| --- | --- | --- |
| L1 | SPORE_RESEARCH §4A "Procedural body geometry" | "CONFIRMED (S7, secondary)" contradicts itself under the folder's definition (CONFIRMED = primary). S7 was never read, only a search summary. The fact is still CONFIRMED, but through the S3 slides ("Mesh generated via metaballs"), not S7. "Spherical only", "ellipsoids too slow" and "rebuilt live" stay unverified. |
| L2 | SPORE_RESEARCH §4C "Later eras" | "CONFIRMED (S10)": Wikipedia is secondary, so this should be OBSERVED (the CSV row P001 already says OBSERVED). |
| L3 | community_tools §3.1, §3.2, §3.4 | "CONFIRMED (E3)" for S12, S13 and S17, which are journalist reports of talks or interviews. Under the folder's definition these are OBSERVED (secondary). S1 inside the same bullet is fine. |
| L4 | creature_editor §2.2, §3.2, §4.2 | "Documented (CONFIRMED by a primary **or developer-quoted** source)" changes the definition locally. It puts S12, S13 and S15 next to S1. Inconsistent with `locomotion.md`, which labels S13/S14 OBSERVED. Pick one rule for all files. Reviewer suggestion: CONFIRMED for S1, S3–S6, S15 and S14 (first-hand developer essay); OBSERVED for S12, S13, S17, S10, S11. |
| L5 | GAMEPLAY_MEASUREMENTS.csv P005–P010 | `result_type = independently verified`, but MEASUREMENT_PLAN §4 defines that as "two methods or two sources agree". Each row has one source. Use a value such as `documented` (new) or `observed`. P001 is genuinely two sources. |
| L6 | SPORE_RESEARCH §4A "Automatic rigging" | "CONFIRMED (S1, S3): ... the skin follows the spine and limb bodies." Neither source describes skinning. S1 shows mesh and bodies side by side (Fig. 2); S3 does not cover the creature skin at all. Downgrade that clause to HYPOTHESIS (it already is in CREATURE_CREATOR §1.3). |
| L7 | CREATURE_GEOMETRY §1 table, "Tessellation" row | A secondary-summary claim (patent avoidance, ear-clipping) sits in the "Spore (source)" column with only "re-verify". It should be labelled unverified/HYPOTHESIS until S7 is read, and nothing should depend on it. |
| L8 | CREATURE_CREATOR §1.2 | "CONFIRMED (S3) ... the order does not matter" overstates S3 (claim 16). |
| L9 | GENESIS_IMPLEMENTATION_ROADMAP §1 | "Anatomy-driven animation: Published in depth (S1, S2, S13)". S2 has never been read (site down). |
| L10 | community_tools §1 item 1, §3.1–3.3 | Header file names (E2) are used as evidence "how modders model the game". That is correctly labelled OBSERVED (community RE) and never presented as EA's design. Good. One slip: §3.2 "HYPOTHESIS (E4): the skin mesh is rebuilt from the rigblocks while editing, as S7 says". S7 is unverified (see L1). |

Behaviour treated as proof of an internal algorithm: none found in the specs. The files consistently mark
inferences as HYPOTHESIS and refuse to guess skin weights or the complexity formula. The closest case is
`creature_editor.md` §2.2 inferred item 4 ("cross-sections are round, because spheres alone cannot make an
elliptical section"). It is correctly labelled HYPOTHESIS, but its reasoning is weak: overlapping spheres can make
flattened sections. R220 is the right test.

## 4. Contradictions between files

| ID | Topic | Where | Contradiction | Suggested resolution |
| --- | --- | --- | --- | --- |
| C1 | Creature description size | S12 "4k"; S15 "2–5 Kbytes"; S17 "about 8 K"; CREATURE_GEOMETRY §3 and §10.7 "under 4 KB ... comparable with Spore's published figure"; creature_editor §4.3.7, §4.6, P5 (4.6 KB quantized for an over-maximal body; worst case 6.5 KB with long keys) | The geometry spec cites "the" published figure as if there were one, and ignores 8 KB. Its own limits (24 vertebrae, 12 limbs × 6 joints, 24 parts) produce a body that workstream B measured above 4 KB. | State that three sources give 2–8 KB, so the number is a loose target, not a parity requirement. Make the 4 KB test apply to "the largest body reachable under the complexity limit" (B's wording) everywhere, or raise it to 8 KB. |
| C2 | Skin rebuild timing | CREATURE_GEOMETRY §5 (updated: GDScript cannot meet 33 ms); creature_editor §2.8/§6 ("lead should decide whether to update" the spec); ROADMAP Stage 1 acceptance = §10 items 1–7 (includes item 4: preview < 33 ms) and output "report on whether GDScript is fast enough"; ROADMAP §3.3 defers the native choice "Later, at Stage 2" | The spec has been updated, but B's note is now stale. The roadmap still makes Stage 1 pass a criterion that the probe says GDScript fails, and still treats GDScript speed as an open question. | Roadmap: Stage 1 acceptance = items 1–3, 5–7 plus *measured* rebuild times; move the 33 ms target to Stage 2 (where it is already listed); bring the native-path decision forward into Stage 1, as B recommends. Delete B's stale sentence. |
| C3 | Bake budget vs probe | CREATURE_GEOMETRY §10.4 "final bake under 250 ms"; probe P2: 1.28–3.03 s at the bake grid in GDScript | Not contradictory in principle (native is assumed), but nothing says the 250 ms bake also needs native code. | Say so explicitly. |
| C4 | Limb hierarchy depth | CREATURE_GEOMETRY §3 (each limb has an attach **vertebra**); creature_editor §2.3.2 (limbs may branch from a limb joint, one level deep); locomotion §3.8 (branching legs unsupported) | Three different rules. | Pick one for Stage 1. Reviewer suggestion: vertebra-only in Stage 1, branch-on-limb as a later option. |
| C5 | Gait table authoring | PROC_ANIM §3.2 (table authored per speed band for 1–6 legs per group, generated for more); locomotion §3.3.4 ("Phases are generated, not hand-tabled per leg count", table in Fr units) | Locomotion flags the unit change (§3.5) but not that it also drops per-leg-count tables. | Update PROC_ANIM §3.2 to point at locomotion §3.3, or note both options. |
| C6 | Domain class for derived locomotion numbers | PROC_ANIM §3.1 `BodyDescriptor` (legs, groups, stride, cadence, top speed, turn rate, stability); locomotion §7.1 `BodyMechanics` (legs, groups, top speed, envelope, stability); geometry/B `BodyDescription` (the editable data) | Two classes with the same job, plus a third whose name differs by one word from the first. | Merge into `BodyMechanics`; retire the name `BodyDescriptor` to avoid confusion with `BodyDescription`. |
| C7 | Animation performance budget | PROC_ANIM §6.8: 50 creatures × 25 bones < 1.5 ms total (30 µs each); locomotion §6.4: option B ≈ 0.2–0.3 ms each (10–15 ms for 50); option A "well under 0.05 ms per leg" (HYPOTHESIS), i.e. up to ~0.2 ms for a quadruped | No estimate meets the 1.5 ms budget. S1's own figure (0.2 ms per creature, 2008 hardware) is ~7× the per-creature budget. | Mark §6.8 as provisional, add LOD and update-rate tiers to the spec, and let Gait Lab measure option A before the number is kept. |
| C8 | First prototype | ROADMAP Stage 1 (ten bodies, full skin pipeline, no editor); creature_editor §8 (spine-only body, no limbs, "inside Stage 1"); locomotion §9 (Gait Lab, before Stage 3) | Three different "smallest prototype" proposals for the owner, two of which reorder or shrink the roadmap. | Lead should give the owner one sequenced choice: e.g. (a) spine-only skin + codec, (b) Gait Lab in parallel, (c) full Stage 1. |
| C9 | Test body matrix | ROADMAP / CREATURE_GEOMETRY / B: "ten fixed test bodies"; PROC_ANIM §6.1: "at least 12" with a different list | Two overlapping matrices. | One shared matrix file in the prototype; animation adds its extra bodies to it. |
| C10 | Loop removal reason | CREATURE_GEOMETRY §1 "looped spines were removed because they broke animation (S1 footnote 1, S13)"; PROC_ANIM §1 "Spore removed loops for the same reason, S13" | S1 footnote 1 gives a different reason (interface complexity hindered creativity); S13 gives the animation reason. | Cite both reasons separately. |
| C11 | Community-tools tension | community_tools §5 says SPORE_RESEARCH §3 calls modder tools "not used, on purpose" and asks the lead to reconcile | SPORE_RESEARCH §3 has already been updated with a reconciling paragraph. | Delete the stale risk note, or point to the new paragraph. Open question 6 (owner approval of the reading) stays. |
| C12 | Bible scope vs the 2026-10-23 decision | Bible §7: "Support a small approved set of body plans first"; DECISIONS 2026-10-23: build "their full creature just like Spore" | The decision entry does not say whether it supersedes this Bible line. | Owner to state it in the DECISIONS entry (a prototype can still start with a small approved set of test bodies). |
| C13 | DECISIONS placement | The 2026-10-23 entry sits after the "Open decisions" lists instead of with the dated entries. | Cosmetic, but readers scanning dated entries miss it. | Move it up when DECISIONS.md is next edited (owner-approved edit). |

## 5. Clean-room hygiene

| ID | Where | Issue | Severity | Action |
| --- | --- | --- | --- | --- |
| H1 | Session scratchpad `wsA/Spore-ModAPI`, `wsA/SporeModder-FX`, `wsA/wiki-SporeModder-FX` | Full git object stores of the GPL repos remain, including ModAPI's Ghidra scripts (`SDKtoGhidra` branch ref present) and the "reconstructed Spore source code" pages that `community_tools.md` says must never reach implementation agents. Any later agent in this session can read them. | **High** | Delete the clones from the scratchpad once the commit hashes are recorded (they are). |
| H2 | community_tools §3.1–3.4 | Names reverse-engineered ModAPI header paths and EA-internal concepts (`EditorModel.h`, `cEditorResource.h`, `cCreatureDataResource.h` "four-letter type codes", `EditorRigblock.h`, `Anim/anim_csd.h`, `IAnimWorld.h`, `Simulator/` classes). No layouts or code, so not a copyright problem, but it is E2 material. | Medium | Keep `community_tools.md` out of every implementation packet. Optionally replace file names with "a ModAPI header" in a redacted copy. |
| H3 | CSV P002 and P004 notes; community_tools §3.4 | Spore ability names ("Sing, dance, charm, pose", "Bite, charge, strike, spit") and capability tag lists from the wiki. Fine as research notes, but LEGAL §6 forbids reusing ability names. | Low | Mark these notes "research only, never GENESIS names". |
| H4 | locomotion §6.1 | S1's solver constants (5 iterations, 10%, 10%/120%) are inside a section locomotion says implementation agents may receive ("§3–§6"). They are marked not adopted, but an agent may still copy them. | Low–medium | Narrow the hand-off to the "Specification", "Implementation options" and "Acceptance tests" subsections (§x.3, §x.4, §x.6/7), not whole §6. |
| H5 | Spore-specific vocabulary in GENESIS specs | `grasper` (capability name, a distinctive Spore/S1 term) in CREATURE_CREATOR §3, PROC_ANIM, B §3.5; PROC_ANIM §3.3 frame modes closely mirror S1's mode set (rest-relative, CreatureSize, LimbLength, ground-relative, target-relative, look-at), renamed. | Low | Published paper ideas are fair to use, with provenance shown, as done. Consider a GENESIS word for `grasper` (e.g. `hand` or `manipulator`) so no Spore vocabulary ships in data files. |
| H6 | Quotes over ~25 words | creature_editor §2.1 S1 rest-pose quote (about 32 words with an ellipsis); LEGAL §3 Art. 5(3) (statute, fine) | Low | Shorten the S1 quote or paraphrase. Everything else is under 25 words. |
| H7 | MEASUREMENT_PLAN / LEGAL | Clips stay out of the repo; the plan says so. Good. The owner's executable SHA-256 and build ID in SPORE_RESEARCH §2.1a are inventory, not EA content. Fine. | None | |

No code, struct layouts, addresses, constants tables or Spore data files were found in any research file. The
JSON example in `creature_editor.md` §4.3 is an original GENESIS format with invented values.

## 6. Legal notes

Case and statute citations: all correct.

| Citation | Check |
| --- | --- |
| *Sega Enterprises v. Accolade*, 977 F.2d 1510 (9th Cir. 1992) | Correct. The holding is broader than "only for interoperability": disassembly can be fair use where it is the only way to reach unprotected ideas and functional elements and there is a legitimate reason (Accolade's reason was compatibility). The file's conclusion ("weak fit for us") still holds. |
| *Sony Computer Entertainment v. Connectix*, 203 F.3d 596 (9th Cir. 2000) | Correct. |
| *Bowers v. Baystate Technologies*, 320 F.3d 1317 (Fed. Cir. 2003) | Correct. Note it applied First Circuit law and drew a strong dissent on preemption. |
| *Davidson & Associates v. Jung*, 422 F.3d 630 (8th Cir. 2005) | Correct. It concerned the bnetd emulator of Blizzard's Battle.net. The court enforced the EULA/TOU reverse-engineering ban, found a §1201 violation and rejected the §1201(f) defence. |
| 17 U.S.C. §1201(f) | Correctly described as a narrow interoperability exception for an independently created program. |
| Directive 2009/24/EC Art. 5(3), 6, 8 | Correct. The Art. 5(3) quote matches. Art. 8 (second paragraph) voids contract terms contrary to Art. 6 or Art. 5(2)–(3). |
| UK CDPA ss. 50A–50C, 296ZA ff. | Correct range. Cite s. 50BA (observe, study, test) and s. 296A (contract terms void) by number. |

Statements to soften (none is dangerous; they read as legal conclusions in a document that says it is not legal
advice):

1. LEGAL §2 and §5: "*Davidson v. Jung* makes [EA's] term likely enforceable" in the US. *Davidson* binds only the
   Eighth Circuit; circuits differ on preemption (compare *Vault Corp. v. Quaid Software*, 847 F.2d 255, 5th Cir.
   1988, which held a state law validating reverse-engineering bans preempted). Suggested wording: "US courts have
   enforced such terms (*Bowers*, *Davidson*), so we assume EA's term is enforceable." The practical conclusion
   (no binary analysis) does not change.
2. LEGAL §2 table: "Screen recording is not covered by that definition." That is our reading. Add "in our reading".
3. LEGAL §4: "Matches owner rule and EU Art. 5(3)". The owner is in the US, so EU law is background only. Say so,
   or drop the EU reference from the US-facing table.
4. LEGAL §3 patents: good caveats already. Add that US7867093B2 is "Active – Reinstated", and that the S1/S3
   techniques GENESIS follows have had only a "first search", so the "fuller search" item should block
   *shipping*, not prototyping (which the roadmap implies but does not say).
5. CREATURE_GEOMETRY §1: Surface Nets "unpatented as far as we know" is wrong. US 6,084,593 exists (1998 filing,
   almost certainly expired). Replace with the patent number and its status once confirmed on the register.
6. DECISIONS 2026-10-23 says `LEGAL_RESEARCH_BOUNDARIES.md` "applies US law". That is accurate for orientation
   only; keep the file's "not legal advice" status visible wherever it is cited.

## 7. Prioritised fix list

| # | Priority | File | Exact problem | Suggested fix |
| --- | --- | --- | --- | --- |
| F1 | P0 | Session scratchpad `wsA/` | GPL clones, including the Ghidra scripts and "reconstructed Spore source" pages, are readable by later agents | Delete the three clone folders; keep the recorded hashes in `community_tools.md` |
| F2 | P0 | GENESIS_IMPLEMENTATION_ROADMAP §2 Stage 1, §3.3 | Stage 1 acceptance includes the 33 ms preview (spec §10.4), which the probe shows GDScript fails; the native decision is deferred to Stage 2 | Stage 1 acceptance: §10 items 1–3, 5–7 plus measured times; schedule one native-path measurement in Stage 1; keep 33 ms in Stage 2 |
| F3 | P1 | SPORE_RESEARCH §4A, CREATURE_CREATOR §1.3, CREATURE_GEOMETRY §1 | Metaball skin cited as CONFIRMED via S7 (unread); tessellation/patent story unverified | Cite the S3 slides ("Mesh generated via metaballs") as the primary source; label the S7 details (spheres only, ellipsoids, ear-clipping, patent avoidance) unverified until S7 is read |
| F4 | P1 | CREATURE_CREATOR §1.2 and §3 row "Additive composition" | "order does not matter" not supported by S3 (Spore concatenates quaternions) | Change to "add up so one does not undo another; S3 notes that Euler summation would be order-independent, while the engine concatenates quaternions". The GENESIS order-independence test stays, as our own requirement |
| F5 | P1 | LEGAL label definitions vs SPORE_RESEARCH §4, community_tools §3, creature_editor §2.2/3.2/4.2 | CONFIRMED applied to secondary sources; local redefinition in B | Adopt one rule (suggested in L4) and relabel S10, S12, S13 and S17 claims as OBSERVED |
| F6 | P1 | CREATURE_GEOMETRY §3 and §10.7; creature_editor §4.3.7 | 4 KB target vs 2–5/4/8 KB sources and the 4.6 KB probe | Cite all three figures; define the test body as "largest reachable under the complexity limit"; mark 4 KB as GENESIS's own target |
| F7 | P1 | PROC_ANIM §6.8 | 1.5 ms for 50 creatures has no supporting estimate | Mark provisional; add LOD/update-rate tiers; re-set after Gait Lab measures option A |
| F8 | P2 | GAMEPLAY_MEASUREMENTS.csv P005–P010 | `independently verified` on single-source rows | Change `result_type` (e.g. `documented`), or add a second source |
| F9 | P2 | GAMEPLAY_MEASUREMENTS.csv P002–P004 | Values cited to S11 on a day both wikis were unreachable | Record how they were obtained (search summary?) and lower confidence to `low` until R4 |
| F10 | P2 | CREATURE_GEOMETRY §1, §5 | Surface Nets called unpatented | Name US 6,084,593 and its (expired) status after checking the register |
| F11 | P2 | PROC_ANIM §3.1 vs locomotion §7.1 | `BodyDescriptor` and `BodyMechanics` overlap; `BodyDescriptor` ≈ `BodyDescription` | Merge into `BodyMechanics`; update PROC_ANIM |
| F12 | P2 | PROC_ANIM §3.2 | Gait table "per leg count" vs locomotion's generated phases in Fr units | Point to locomotion §3.3 as the current proposal |
| F13 | P2 | CREATURE_GEOMETRY §3, creature_editor §2.3, locomotion §3.8 | Limb attach depth differs | One Stage 1 rule (vertebra only) |
| F14 | P2 | Roadmap, B §8, locomotion §9 | Three first-prototype proposals | One sequenced owner choice in the roadmap |
| F15 | P2 | LEGAL §2, §3, §5 | *Davidson* stated as making the term "likely enforceable"; screen recording "not covered" stated as fact; UK sections imprecise | Soften as in §6 items 1–3; cite CDPA s. 50BA and s. 296A |
| F16 | P2 | locomotion header ("§3–§6" hand-off) | Hand-off includes S1 constants in §6.1 | Hand off only the spec/options/tests subsections |
| F17 | P3 | SPORE_RESEARCH §3 S4 entry | "two colours" | "player-selectable colour(s)" |
| F18 | P3 | creature_editor §2.1 | "Legs and limbs can be stretched and curled like clay (S13)" | "features" (S13's word) |
| F19 | P3 | PROC_ANIM §1 | Paraphrase of the Bible inside quotation marks | Quote "Creature anatomy must meaningfully influence gameplay" |
| F20 | P3 | CREATURE_GEOMETRY §1, PROC_ANIM §1 | Loop-removal reason attributed to S1 footnote 1 | S1: interface complexity; S13: animation exceptions |
| F21 | P3 | community_tools §5 "Tension" note; creature_editor §6 note on the 30–80 ms estimate | Stale: both already resolved in the lead files | Delete or mark resolved |
| F22 | P3 | ROADMAP §1 | S2 cited as published evidence though never read | Drop S2 or mark "not read" |
| F23 | P3 | locomotion §2 item 2 | "In body lengths per second it moves 0.71×" silently assumes body length scales with leg length (isometric); R307 (same body, longer legs) is not isometric | State the assumption; give the non-isometric case too |
| F24 | P3 | creature_editor §2.1 | S1 rest-pose quote ~32 words | Shorten |
| F25 | P3 | LEGAL §2 | §13(B) US clause not quoted | Quote the US/Canada/Japan clause that actually applies |

## 8. Does the research reduce implementation work?

Honest view: **yes, by a useful but bounded amount.** It is roughly a design head start, not a shortcut through the
engineering.

What it saves:

- **Architecture decisions that would otherwise need throwaway prototypes.** These are well sourced: tree-only
  bodies, legs computed from the graph, capability tags as the single bridge to animation and gameplay, edit pose
  = rest pose, recipe-not-mesh saves, a metaball-family skin, a two-phase solve order, passive secondary motion
  that never feeds back. S1 also documents what failed (Wiggles, monolithic and CCD/Jacobian solvers, loops), which
  saves real experiments.
- **Concrete, testable acceptance criteria and interfaces.** Most of the specs could be handed to an implementer
  today, after the contradictions in §4 are resolved.
- **Two early measurements that changed the plan.** The GDScript skin probe (200–580 ms against a 33 ms target)
  and the size probe found real problems before any build. The `ClassDB` checks remove guesswork about Godot 4.7.2.
- **The dimensionless gait table** in `locomotion.md` §2 is the most valuable original idea. It turns per-body
  tuning into per-band tuning and makes no-slip a checkable inequality. It is GENESIS's own design, from public
  biomechanics, not from Spore.

What it does not save:

- The hard engineering: fast native contouring, junction quality, anchor robustness, and making Godot's built-in IK
  behave on generated rest poses. No public source describes these, as the workstreams themselves say.
- All feel numbers. No Spore recording exists yet, so every "Unknown" column is still unknown, and by policy no
  Spore number becomes a GENESIS constant anyway.
- About a fifth of the material (`community_tools.md`, much of the tool and REA discussion) adds little to
  implementation; its main value is confirming S1 from another angle and mapping legal risk.

Risk to the saving: the contradictions in §4 (especially C2, C6, C7, C8) would cost an implementer time, or lead
to building the wrong Stage 1, if they are not fixed before hand-off. Fix F1–F7 before any prototype starts.
