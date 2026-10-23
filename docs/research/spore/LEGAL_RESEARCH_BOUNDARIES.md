# Legal research boundaries

Status: PROPOSED research rules, written 2026-10-23. This is a research note, not legal advice. Nobody on the
project is a lawyer, and nothing here clears binary analysis. Where it says "needs clearance", that means a written
opinion from a qualified lawyer in the owner's country, then an owner decision recorded in `docs/DECISIONS.md`.

Labels used in every file in this folder:

- **CONFIRMED**: stated by a primary source (the license text, a statute, a court ruling, or a paper by Spore's own
  developers), with a citation. For a project rule, it means the owner approved it.
- **OBSERVED**: seen in our own gameplay recordings or in a cited secondary source (wiki, review, interview).
- **HYPOTHESIS**: our inference about how something might work. Never present it as Spore's implementation.
- **PROPOSED**: a GENESIS design or process suggestion that the owner has not approved.

## 1. What already binds us

- CONFIRMED (owner, 2026-10-22, `docs/DECISIONS.md` "Spore files are not used"): we do not open, extract or read
  data or formats out of Spore's files. Playing the game and writing design notes in our own words is fine.
- CONFIRMED (owner, 2026-10-22, project guardrail): no decompiling, disassembling or extracting from Spore. Ghidra or
  REA analysis of Spore is **not cleared**.
- CONFIRMED (owner, 2026-10-22, "Minimum visual quality bar"): Spore's Steam page is a polish bar only. No creature,
  part or interface design is copied.
- CONFIRMED (owner, 2026-10-22): Thrive is GPL-3.0 and reference-only. No Thrive code is copied.

The protocol of 2026-10-23 keeps all of these: it asks for clearance before any binary analysis and forbids
extraction outright.

## 2. EA's license terms

Source: Electronic Arts User Agreement, last updated 14 May 2026, read on 2026-10-23 at
<https://tos.ea.com/legalapp/WEBTERMS/US/en/PC/>. CONFIRMED for the US English PC version; the version that binds
the owner depends on where he lives and where he bought the game.

| Clause | What it says (short quotes) | What it means for us |
| --- | --- | --- |
| §2 License | "You may not reverse engineer or attempt to extract or otherwise use source code or other data from EA Services", with an exception where EA authorizes it or the law permits it | Decompiling or disassembling Spore is a breach of contract unless a law gives a right that overrides the contract. Reading data out of game files is covered too. |
| §2 License | "You may not access, copy, modify or distribute any EA Service, Content or Entitlements" (except as the agreement allows) | No copying or redistributing game data, binaries or assets. |
| §7.A Technical and Content Protection Measures | "Attempting to circumvent, disable or tamper with these measures shall terminate this license." | Never touch DRM or launcher checks. This is also a separate legal risk under anti-circumvention law (section 3). |
| §7.C Monitoring and Anti-Cheat | Defines "Unauthorized Third-Party Program" as one that "intercepts, 'mines', or otherwise collects information from or through the game" | Memory readers, hooks and data-mining tools attached to a running Spore are out, even for "just measuring". Screen recording is not covered by that definition. |
| §6 Rules of Conduct | "Do not engage or assist in cheating ... or using exploits." | Irrelevant to single-player observation, but no exploit-based measurement tricks. |
| §13(B) Governing law | For residents of the EEA, UK, Switzerland, Brazil, Hong Kong, Mexico or Russia, "the laws of your country of residence govern this Agreement" | Which statutory exceptions apply depends on the owner's country. We need to know it. |

Owner's answers (2026-10-23): **bought on Steam, lives in the United States.** So:

- US law applies (section 3, US items). §13(B)'s country-of-residence rule for the EEA and others does not apply.
- Two agreements bind the copy: the Steam Subscriber Agreement (Valve) and EA's terms for the game. Open task: if the
  game shows an EULA at first launch or links one on its store page, quote that version here. We do not open files
  in the install folder to find it.
- In the US, *Davidson v. Jung* (section 3) makes a game EULA's reverse-engineering ban likely enforceable, so binary
  analysis stays off the plan. The owner confirmed on 2026-10-23: no unauthorized binary analysis or DRM
  circumvention.

## 3. Law that sits next to the contract

These are summaries of public law for orientation. They are CONFIRMED as to what the cited texts say, not as to how
they apply to us.

- **US copyright, fair use for interoperability.** *Sega v. Accolade*, 977 F.2d 1510 (9th Cir. 1992) and *Sony v.
  Connectix*, 203 F.3d 596 (9th Cir. 2000) held that intermediate copying during disassembly can be fair use when it
  is the only way to reach unprotected functional elements for interoperability. Our goal is not interoperability, so
  these cases are a weak fit.
- **US contracts can still forbid it.** *Bowers v. Baystate*, 320 F.3d 1317 (Fed. Cir. 2003) and *Davidson &
  Associates v. Jung*, 422 F.3d 630 (8th Cir. 2005) enforced license terms that banned reverse engineering. *Davidson*
  is about a game (Blizzard's Battle.net) and also found a DMCA anti-circumvention violation. So in the US, the EA
  clause above is likely enforceable even where fair use might have applied.
- **US anti-circumvention.** 17 U.S.C. §1201 forbids circumventing access controls; §1201(f) has a narrow
  interoperability exception that does not cover "learning how a game works to make our own".
- **EU.** Directive 2009/24/EC Art. 5(3) lets a lawful user "observe, study or test the functioning of the program in
  order to determine the ideas and principles which underlie any element of the program" while loading, displaying
  or running it, and Art. 8 makes contract terms against this void. This supports our gameplay observation. Art. 6
  allows decompilation only for interoperability of an independently created program, under strict conditions; that
  does not describe our purpose either. The UK has equivalents (CDPA 1988 ss. 50A–50C, 296ZA ff.).
- **Ideas are free, expression is not.** Game mechanics and general techniques are not protected by copyright;
  code, art, animation data, audio and text are. Patents are a separate question that copyright law does not answer.
  First search (2026-10-23, Google Patents; not a legal clearance):
  - US7789758B2 and US7867093B2, "Video game with simulated evolution", EA, inventor Will Wright, priority
    2006-03-10. Google Patents lists them as active with estimated expiry 2028-10-25 and 2027-12-31 (Google marks
    status as an assumption). Their independent claims are about **sharing player-made content through a game
    server**: uploading or automatically downloading instructions that recreate content (including procedural
    animation data), selected by heuristics, and an in-game browser of server content. Read with
    `docs/research/innovation-backlog.md`: IB-29 (online gallery) would need a patent review before any work; IB-09
    (offline file sharing, no server) looks outside these claims, but that is our reading, not an opinion.
  - US6141019A, "Creature animation and simulation technique", EA, predates Spore (1990s filing); expired.
  - No patent naming Chris Hecker as inventor on the Spore animation system was found in a first search.
  Remaining task: a fuller search on creature skin generation, automatic rigging and procedural gait before any
  GENESIS system following those ideas ships. The SIGGRAPH papers are public, but publication does not rule out a
  patent.

Conclusion (PROPOSED): in every jurisdiction above, **gameplay observation of a lawfully owned copy is the safe
ground**, and decompiling Spore to learn its design is not covered by any exception we found. The legal cost of
binary analysis is high and the research gain is low, because Maxis published the key techniques (see
`SPORE_RESEARCH.md`).

## 4. Technique-by-technique risk table

| Technique | Status | Notes |
| --- | --- | --- |
| Playing Spore (owned copy) and taking notes in our own words | Allowed | Matches owner rule and EU Art. 5(3). |
| Screen recording our own play, frame-by-frame analysis, stopwatch timing | Allowed | Keep clips private in project storage, never published or committed to the repo (they contain EA's art). |
| On-screen measuring aids outside the game (a ruler overlay in the video player, a grid printed on paper) | Allowed | Nothing attaches to the game process. |
| Reading published papers, talks, slides, interviews, patents, reviews, wikis | Allowed | Cite each. Quote briefly; paraphrase the rest. |
| Spore's own in-game editors used as intended (building a test creature, using the test drive) | Allowed | Normal play. The creatures we build are test rigs only; none enters GENESIS. |
| Spore's built-in cheat console (e.g. `addDNA`, `moreMoney`) to reach a stage quickly | Flag: low risk | It is a shipped game feature, not a third-party program, but it is a cheat under §6 if read broadly. Single-player only; record its use in the measurement row. |
| Sporepedia/creature PNG cards, the Spore API, community modding tools (SporeModder, Spore ModAPI) | **Not allowed** | These read or write EA formats or hook the game. Covered by the owner's "Spore files are not used" rule. |
| Memory readers, trainers, Cheat Engine, frame-time hooks, overlays that inject into the game | **Not allowed** | §7.C "Unauthorized Third-Party Program". |
| Opening, unpacking or browsing `.package` or other files in the install folder | **Not allowed** | Owner rule. Exception: reading the EULA text if the installer shows it on screen. |
| Ghidra / REA / IDA / Hopper on Spore's executable or DLLs | **Not allowed; needs clearance** | See section 5. |
| Bypassing SecuROM, launcher, Origin/EA app or Steam checks; cracked or "no-CD" executables | **Never** | §7.A and anti-circumvention law. Not clearable. |
| Copying Spore models, textures, animations, sounds, text or UI into GENESIS | **Never** | Not clearable. |
| Studying Thrive's code | Reference-only | GPL-3.0. Read for ideas, write our own, no line-by-line translation. |

## 5. Clearance requirements before any binary analysis

Recommendation (PROPOSED): **do not seek clearance.** Keep binary analysis of Spore off the plan. The published
papers already describe the creature skin, part deformation, paint system, planets and the whole animation stack in
more detail than we need, and the remaining unknowns are gameplay numbers that recordings answer better than
disassembly would.

If the owner still wants to pursue it, all of these must be true first, in this order:

1. The owner's country and purchase channel are known, and the exact EULA that ships with that copy is cited here.
2. A qualified lawyer in that country gives a written opinion that names the specific technique, the specific files
   and the purpose, and says it is lawful despite the EULA. A general "reverse engineering is legal" is not enough.
3. The owner records the approval in `docs/DECISIONS.md`, replacing or narrowing the "Spore files are not used"
   entry, and states the scope.
4. A clean-room process is in place: the person who reads the binary writes a functional description only, and a
   different person (or agent session with no access to that material) writes GENESIS code from the description.
   No pseudocode, constants tables or data layouts cross over.
5. No DRM is touched, ever. If analysis would require it, the analysis stops.

## 6. Clean separation between research and implementation (PROPOSED process)

- Everything about Spore lives in `docs/research/spore/`. GENESIS code never imports, loads or links to it.
- Research notes describe **behaviour and published techniques in our own words**. No Spore screenshots, frames or
  clips go into the repo; recordings stay in the owner's private storage and are referenced by file name and
  timestamp only.
- GENESIS specs cite research by section, then specify our own design with our own numbers. Where a spec follows a
  published technique (for example, a particle-and-length-constraint IK), the spec says so and cites the paper, so
  provenance is auditable. Copyright does not protect a published algorithm; the patent search in section 3 covers
  the remaining risk.
- Measured Spore numbers are **comparison targets for feel**, never constants pasted into tuning data. GENESIS
  tuning values are set by GENESIS playtests and recorded as PROPOSED in `docs/DECISIONS.md` like all tuning.
- Nothing from Spore's designs (creature shapes, part shapes, UI layouts, iconography, names of parts or abilities)
  is copied. GENESIS names its own abilities.

## 7. Tool notes

- **Ghidra** is a legitimate open-source tool from the NSA, Apache-2.0, <https://github.com/NationalSecurityAgency/ghidra>.
  CONFIRMED: owning it is lawful. It is not to be pointed at Spore. We do not install or configure it for Spore.
- **REA** ("Reverse Engineer Anything"), see `SPORE_RESEARCH.md` §2 for what we verified. Not installed. Its setup
  edits agent configuration files and can install third-party tools, so it would need the owner's approval as a new
  dev tool even for non-Spore use (CLAUDE.md: no new dependencies without approval).
