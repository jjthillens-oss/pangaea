# Social stage plan

Status: **PROPOSED** unless a line says otherwise. Section 14a stays empty until the slice is built and verified;
only then does it become IMPLEMENTED, and its tuning stays PROPOSED.

CONFIRMED (owner):

- 2026-10-24, "We are making Spore but better": keep Spore's fundamentals rebuilt better, with the Bible's ideas on
  top. For this stage that means dancing and social befriending as the friend path, the friend-or-foe stance before
  an interaction, mating that opens the editor and a small HUD
  ([playthrough notes](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md), "Owner direction").
- 2026-10-25, the request for this plan: "write docs/stages/social-plan.md for the Bible's Social era (between
  creature and tribal), starting from Spore's late-creature and tribal social loop and layering the Bible's systems.
  Then build a small standalone playable slice in new folders (game/\*/social/), opened by a title Preview button,
  with its own smoke test."

Everything else here (the signal design, the numbers, the roles, the slice layout, the handoffs) is PROPOSED until
the owner approves it. The [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf) is binding: §4 (era
table and transition contract), §8 (Social), §12 (communication organs), §13 (AI states, disengagement, timeouts,
fidelity), §14 (one interaction resolver, no universal rhythm minigame), §18 (persistence), §19 (accessibility),
§23 (M5 Social foundation) and §24 (no mock buttons). Spore's loop comes from the playthrough notes and is rebuilt
original: no Spore code, art, sound, names, icons or UI layout. The earlier [Social era proposal](../proposals/social-era.md)
and the [Tribal plan](tribal-plan.md) are the neighbours this plan has to agree with. The design of Godfrey's PR #174
social prototype (needs, intentions, fading memories, refusals that cost nothing) was read as ideas only; none of its
code is used.

## 1. Where the stage sits

Seven eras in order (Bible §4; the names are working names, DECISIONS 2026-10-22 item 6): Microscopic, Aquatic,
Terrestrial, **Social**, Tribal, Civilization, Interstellar. Spore goes from the creature stage straight to the tribe;
Social is one of the two stages Pangaea adds (the other is Aquatic). Spore's late creature stage already had the seed
of it (befriend a species, allies follow, a pack of three); Pangaea makes that its own era, with individuals instead
of a species-wide card.

| Bible §4 column | Social |
|---|---|
| Primary play | Coordinate groups and build relationships |
| New layer | Group roles, communication, learned behaviour |
| Retained from Terrestrial | Individual anatomy, ecology, ancestry |

**Transition in from Terrestrial (PROPOSED).** Bible §4: demonstrated capability, a survivable destination and a
player choice; save before the transition and keep the prior save as a recoverable checkpoint; the same lineage and
world records continue. The proposed gate is "two allies and an established nest": a creature that has befriended
two creatures and returned to its nest is offered the move ("Your kin and allies gather at the nest: start living as
a band?"). Refusing keeps the creature stage running. No timer forces it.

**Transition out to Tribal (PROPOSED).** Section 13.

**The three continuity items (Bible §4, "a transition fails acceptance if any of these is replaced by a cosmetic
badge alone"):**

| Bible §4 requirement | In Social |
|---|---|
| A local activity from the earlier era that remains playable | Walking on the same gait planner, eating fruit at bushes and biting carry over from the creature stage; its Sing becomes one of four signals |
| One earlier adaptation that still matters | The creature's anatomy, through the same `CreatureStats` numbers: eyes set sight (who you can see, who sees your display), legs set speed, mouths and hands set what you can carry, display organs strengthen the dance, a throat sac carries a song further, ears hear further |
| One historical relationship that persists | Creatures befriended in the creature stage become the first band (PROPOSED; needs a save field and an owner decision, section 12). In the slice the band is met fresh at its den |

## 2. Spore's social loop, kept

What Spore does (playthrough notes, Creature 0:10 to 0:50 and Tribal 0:51 to 1:31), and the Pangaea version.

**Late creature stage:**

| Spore fundamental | Pangaea Social version |
|---|---|
| A stance before any interaction: one button to make friends, one to make dinner | Approaching an individual shows its tag and the two answers with their bindings: **Friend** (a signal, R / pad B) or **Foe** (a bite, F / pad X). The stance is chosen per press, so nothing is left armed (Bible §19) |
| Sing, dance, charm and pose in front of another species to impress it | Four signals: **Sing**, **Display** (the dance), **Share** (a gift) and **Calm** (the pose). The player reads the individual first and picks the one that fits (section 4). No rhythm game |
| A goal card: "Impress 3 to ally" | A goal card: "Befriend the band 1 / 3", then "Feed the nest 2 / 6" |
| Allies follow and join a pack of at most three | Companions join a band of at most three (PROPOSED cap), follow by default and take orders (section 7). A full band says so: "Band full: dismiss one first" |
| Pack hunts | Assist sends the band's fighters at your foe; together they drive off the hunter (section 8). Hunting prey as a band is in the full stage, not the slice |
| Your nest, and other species' nests you walk to | Your nest (home, retreat point, faint respawn) and the band's den (where its members live before they join and go back to when dismissed) |
| Mating at the nest opens the editor | Kept: mating at the nest opens the same creature editor, now with a reach and cost preview for signals (section 9). Not in the slice |
| A small HUD: goals top left, abilities bottom centre | Goal card top left, band cards top right, the signal and order dock bottom centre, one caption line (section 11) |

**Tribal stage (what Social prepares):**

| Spore fundamental | Where it lands |
|---|---|
| Gifts to a rival village | Share is already a gift in Social; Tribal widens it to exact offers shown before commitment (Bible §14) |
| Instruments (the social path) against weapons (the combat path) | Social has the body's own signals and bite; Tribal adds instruments as tools that extend a signal's range or reach a whole group (Bible §9: tools extend anatomy) |
| Rival coloured villages | The full Social stage has neighbouring bands and loners, each group with its own reputation (the slice has one band and one loner); Tribal turns them into the rival tribe with a befriend path and a raid path ([Tribal plan](tribal-plan.md)). Rivals are told apart by name, shape and label, never colour alone |

## 3. Built better: the Bible's systems on top

- **Individuals, not a species card (§8).** Every creature has a stable id, a name, a disposition (warm, curious or
  wary), needs (hunger, fear), a bounded memory of significant encounters and a role. Two members of one species can
  answer the same signal differently.
- **Readable signals (§8, §12, §14).** Recognition (what the individual shows) → signal (one choice) → response (a
  word and a movement) → consequence (memory, trust, joining). Anatomy changes range and strength; Calm works for
  every body, so no body is locked out of the basic set.
- **Orders that answer (§8).** Follow, wait, investigate, retreat and assist, plus dismiss. Every order is either
  acknowledged or refused with a reason, reports progress or inability, can be cancelled by a new order, and times out.
- **Relationships that forgive (§8).** Trust combines recent memories, which fade, with a slow persistent reputation.
  One accidental bump never makes an individual or a band hostile; repeated harm makes an individual hostile for a
  while, then it listens again. This replaces the creature stage's "a bitten creature stops listening for the rest
  of its life" for Social (section 5).
- **Roles from anatomy (§8, §12).** Scout, defender and forager come from the body, each with a visible cost.
- **Percepts-only AI (§13).** Companions and the hunter decide from what they perceive (directions, distances,
  orders, their own needs), never from the player's coordinates or the sim. Every pursuit disengages; every order
  times out; near actors think more often than far ones.
- **One resolver (§14).** The dock's enabled state and tooltip, and the action itself, ask the same rule. A refused
  signal or order explains what is missing and spends nothing, not even the cooldown.
- **Accessible (§19).** Bindings come from the input map, every response is a word as well as a movement, nothing
  needs colour, hearing or rapid presses, and opening the orders menu pauses the sim so no action is left held.

## 4. The friend path: read and answer

Spore's call-and-response minigame copied a rhythm. Bible §14 rules out a universal rhythm minigame unless it is
separately approved, and players found Spore's version shallow ([community wants](../research/community-wants.md),
theme 16). Pangaea's friend path is **read and answer** (PROPOSED; the dance and the pose stay, as Display and Calm):
success comes from choosing what fits the individual's visible mood and needs. The outcome never depends on when the
button was pressed, how fast, or in what rhythm; a test pins this (section 15).

1. **Recognition.** The tag over the targeted individual shows its name, role and mood in words: *hungry*, *wary*,
   *curious*, *warm*, *scared*, *hostile* or *at ease*, plus what it is doing (grazing, watching you, fleeing). Its
   movement backs the word up: a wary one keeps its distance and turns side-on, a hungry one heads for bushes, a
   curious one turns to face you.
2. **Signal.** The player picks one of four signals (wheel or LB / RB cycles, or click the dock) and presses Friend.
3. **Response.** One of five, shown as a caption and a movement:

   | Response | When | Movement | Memory |
   |---|---|---|---|
   | *welcomes you* | the signal fits | turns to you and steps closer | a strong friendly memory, scaled by the signal's strength |
   | *listens* | it does not fit but is not unwelcome | stops and faces you | a small friendly memory |
   | *is unsure* | as *listens*, but its trust is still below zero | stops, keeps its distance | the same small friendly memory |
   | *backs away* | a loud signal (Sing, Display) to a wary or frightened individual | steps back | a short-lived bad memory |
   | *is busy* | it is fleeing or in a fight | keeps doing it | none |

4. **Consequence.** The memory changes its trust; at the join mark (6, PROPOSED) a band member asks to join and
   follows. A loner or a member of another band can be befriended but stays where it lives (in the slice).

**The four signals (PROPOSED numbers; the tuning lives in game/data/social/):**

| Signal | Spore root | Channel | Range and anatomy | Needs | Fits |
|---|---|---|---|---|---|
| **Sing** | sing | sound, any direction | 6 m; a throat sac adds 4 m; a target with ears hears it 1.5 times as far | nothing | an individual whose species has a voice organ or nothing showier; the default |
| **Display** | dance | sight | the target's own sight range, capped at 12 m; strength 1, plus 0.5 for the first display organ and 60% of the step before for each next one, at most 4 organs (diminishing returns, Bible §12) | the target can see you: you are within 70 degrees of where it faces | a display-rich species (two or more display organs) |
| **Share** | charm, gift | touch | 2.5 m | a fruit you carry; carrying needs a mouth or a hand (two fruit with a hand) | a hungry individual |
| **Calm** | pose | sight or touch | 3 m | nothing: every body can do it | a wary or frightened individual |

Display organs are the detail-role parts in the part rules that are not listed as voice or hearing organs (crest,
frill, mane, wing, tail fluke, lure and so on). Voice organs: the throat sac. Hearing organs: round and pointed ears.
Part types the tuning does not name count for nothing, so a new part never changes a signal by accident.

**Which signal fits** is one fixed rule, applied in order, from what the tag and movement already show:

1. hungry (hunger at 0.6 or more) → Share;
2. wary (a wary disposition while its trust is below 2) or frightened (fear at 0.4 or more) → Calm;
3. its species is display-rich → Display;
4. otherwise → Sing.

So a wary monkey wants Calm first, and once calmed (trust 2) it listens to a song; the boar is hungry at the start and
wants a gift; the crested strider answers a display. Needs change over time (hunger rises, fear fades), so the
fitting answer changes too, and the tag shows it.

**Failures cost nothing.** A refused signal names the missing requirement and spends neither the cooldown nor the
fruit: *Too far: come within 6 m*, *It can't see you: get in front of it*, *Nothing to share: carry a fruit first*,
*Your body can't carry: it needs a mouth or a hand*, *Wait a moment*, *It won't listen: you hurt it (40 s)*.

**No body is locked out.** Calm has no anatomy requirement and never startles. A body that cannot do the fitting
signal still earns *listens* with any other: slower, never impossible. Two body plans suit different strategies: a
crested strider befriends display-loving individuals in fewer signals, a hopper's throat sac sings from 10 m.

## 5. Individuals, needs, memory and reputation

- **Identity.** A stable id (`b1`, `b2`, ...) sorted for every loop, a name from an original syllable list drawn
  from the world seed's name stream, a preset body, a disposition and a home site.
- **Needs.** Hunger rises from its start value to full over 180 s and drops when the individual eats at a bush.
  Fear rises with a threat's closeness and fades over 6 s. Needs drive the mood word and the fitting signal.
- **Memory.** At most 8 entries `{kind, tick, scale}`. Each kind has a weight and a lifetime; an entry's weight fades
  linearly to nothing over its lifetime and then drops out. When full, the weakest entry goes first, then the oldest
  (ties broken by kind). Proposed kinds: *kind* (a fitting Sing or Display), *gift*, *calm*, *listened*, *startled*,
  *bitten*, *bumped*, *helped* (the band fed the nest or drove off the hunter together), *parted* (dismissed).
- **Trust** = disposition base (warm 1, curious 0, wary -1) + the faded memory weights + half the group's
  reputation, clamped to -10 .. 10.
- **Reputation** is per group (the band, the loner). Each event moves it by a quarter of the memory weight, and no
  single event moves it more than 0.5. It does not fade: it is the persistent half of the relationship (Bible §8). A
  group refuses everything only at -5, which takes at least ten capped bad events.
- **No single-collision war.** A bump is a -0.5 memory that lasts 10 s and moves reputation by 0.125. A bite is a -4
  memory for 90 s. Three bites within 60 s make that individual hostile for 120 s ("It won't listen: you hurt it",
  with the seconds left); then it listens again, and its memories fade on their own. Nothing is "for life".

## 6. Roles from anatomy

Roles are bounded behaviours, not classes. Each individual's role is the highest of three scores from its body
(`CreatureStats` numbers; weights in the tuning), ties broken in the fixed order forager, scout, defender.

| Role | Score from | Advantage | Visible cost |
|---|---|---|---|
| Scout | sight and speed | Sees the hunter first (it spots it 6 m further than its eyes alone, so before the hunter notices it) and warns the band ("Name warns: hunter!"); the band then senses the hunter through it | The hunter notices a scout from 3 m further: it draws attention |
| Defender | weapons and mass | Fights beside you on Assist and makes the hunter lose its nerve | Follows slower (0.85 times speed) and gets hungry 1.25 times faster |
| Forager | hands and mouths | Carries more (two fruit with a hand) and gathers on Assist | Will not fight: refuses an Assist in a fight ("no fighter") and flees earlier |

## 7. Orders

The orders menu opens on E / pad Y and pauses the sim; ui_left / ui_right pick, ui_accept gives, ui_cancel closes. The
dock also gives orders with the mouse. An order goes to the whole band; each companion answers for itself.

| Order | Target | Acknowledgement | Progress and end | Refusal |
|---|---|---|---|---|
| Follow | you | *follows you* | keeps within 4 m, spaced 2 m apart; if separated by more than 30 m it says *lost you* and goes home | hostile |
| Wait | where it stands | *waits here* | holds until another order; flees a threat, then comes back | hostile |
| Investigate | the spot 12 m ahead of you | *goes to look* | *found: fruit / the hunter's lair / nothing*, then follows you again; no progress for 4 s or 20 s in all → *can't reach that spot*, and it comes back | hostile; frightened (fear 0.5 or more) with trust below 8 when the spot is within 14 m of the hunter |
| Retreat | your nest | *heads home* | runs to the nest and waits there | hostile |
| Assist | your foe, or the group task | fighters: *with you*; foragers: *gathers food* | fighters attack your foe; foragers (and everyone when there is no fight) gather fruit for the nest | foragers in a fight: *no fighter, I'll gather*; hostile |
| Dismiss | one companion | *goes back to the den* | leaves the band, keeps its memories (a mild *parted*) | none |

A new order cancels the old one and releases its reservations. A frozen companion is a bug: every order has a
timeout or an end state. The **group-intention view** is the band cards (top right): name, role, current order or
state, and trust in words (*trusting*, *friendly*, *unsure*).

## 8. Group task, threat and nest

- **Feed the nest.** A grove of 8 fruit bushes regrows each bush 25 s after it is picked. Carriers reserve a ripe
  bush before walking to it, so no bush is picked twice; a cancelled or failed trip releases it. Delivering 6 fruit
  to the nest completes the task (*helped* for each companion that took part).
- **The hunter (a prowler)** follows Bible §7 and §13: patrol between its lair and the grove → **investigate** (a
  2.5 s readable tell: it stops, turns side-on, its tag reads *watching*) → **pursue** for at most 6 s, only while it
  still sees its target and fewer than 3 of the group stand within 6 m of that target → **strike** with a 1.2 s cooldown →
  **disengage** after the pursuit time, when its nerve (3) runs out under bites, or when its target is inside the
  nest → **rest** at its lair for 12 s → patrol. It never steps inside the nest. A strike takes a quarter of the
  player's health; an individual it strikes is frightened (fear 1) and flees, but no individual is hurt in the slice. Meat at its lair says "a predator
  lives here" before it is ever seen.
- **Pack defence.** Assist sends fighters at the hunter; each bite costs it nerve. A band that stands together
  deters it without a fight.
- **Leader loss (Bible §8).** When the player's health reaches 0 the player faints, the band keeps every member and
  memory, companions retreat to the nest and wait, and after 3 s the player recovers at the nest. A dismissed or
  separated companion goes home and waits; nothing is erased.

## 9. Learned behaviour and the editor return

- **A learned route (IB-19, PROPOSED).** A companion that delivers fruit learns the grove route: later trips skip its
  1.5 s search. In the full stage a learned route passes to offspring by one explicit rule: a parent that used it at
  least 3 times passes it on; an inherited route not used for one generation is forgotten. The slice records
  learning and tests the rule; it has no generations.
- **The editor return (not in the slice).** Mating at the nest opens the same creature editor (part grid left,
  creature on a plinth right, test drive), with a preview row for signal reach and strength (song range, display
  strength, carry) next to the movement numbers, and their costs. It edits the player's genome only: a companion's
  role is never rewritten by the editor (proposal "group-role panel").

## 10. Fidelity tiers (Bible §13)

Near actors (within 30 m of the player) run their brain every 6 ticks (10 Hz) and move every tick with full gait and
IK. Far actors run brain and movement every 30 ticks with the body transform placed directly. Moving between tiers
keeps the same id, name, memory and reservations, and emits a tier event; nothing is duplicated or dropped.

## 11. Controls and HUD

Existing input actions only (no new InputMap entries): move_up / down / left / right (WASD, arrows, left stick,
d-pad) walk, camera-relative; **creature_social** (R / pad B) is Friend: perform the selected signal at the target;
**zoom_in / zoom_out** (wheel / LB, RB) cycle the selected signal; **creature_bite** (F / pad X) is Foe;
**creature_evolve** (E / pad Y) opens the orders menu; **pause** (Esc / P / pad Menu) asks to leave. ui_cancel never
leaves the stage, because pad B is also Sing. Prompts name the bound keys from the input map (Bible §19).

The HUD is small and Spore-like on the glass theme: goal card top left; band cards top right with a Dismiss button
each; the dock bottom centre (Sing, Display, Share, Calm | Follow, Wait, Investigate, Retreat, Assist), whose enabled
state and tooltip come from the same rule as the action; one caption line for responses, acknowledgements and
refusals; one hint line. Tags over individuals give name, role and mood, and a ▸ marker on the target: the individual
within 15 m that the player faces most squarely (distance times (2 - cos angle) squared, lowest wins). Nothing relies
on colour alone.

## 12. Persistence

The slice writes nothing: it reads the lineage slot (read-only) to take the player's creature, and never saves.
A later Social save block (the band with ids and names, memories, reputation, learned routes and the nest) is a save
schema change and needs the owner's approval (Bible §18; it would follow the Aquatic v5 block proposed in PR #192). Until then the slice
has a test-only record (`social_slice_record_v0`) that tests round-trip to prove identities and significant
relationships survive; it is not the save and is never written to disk.

## 13. Social to Tribal (PROPOSED)

- **The choice.** After the band has completed several group tasks from the same den (proposed: three), the den
  offers a settlement choice: "Settle here as a tribe?", showing the reachable food and shelter and what changes
  (Bible §4 and the Tribal plan). The game saves first; refusing keeps Social running. No automatic transition.
- **The handoff** carries the band (ids, names, roles, bodies), relationships (memories and reputation), the rival
  groups' reputation, learned routes and the den as the campsite. The Tribal plan already begins "with a
  recognizable Social-era group at a small campsite" with befriend and raid paths and no single-collision war; this
  plan matches it.
- **Instruments.** Tribal introduces instruments as tools that extend Sing and Display (more range, a whole group at
  once), the counterpart of Spore's instruments-versus-weapons choice.

## 14. First playable slice

**Scope (PROPOSED).** One 80 m field on the creature stage's ground; the player's nest at the centre; the band's den;
a grove of 8 bushes; the hunter's lair with meat. A band of three (a curious strider, a warm boar, a wary monkey), one
wary loner (a hopper) and one hunter (a prowler), all built from the presets. The player's creature comes from the
lineage slot read-only if it holds a legged creature, otherwise a starter body. Goals: befriend the band (3), then
feed the nest (6). All four signals, all five orders and dismiss, the hunter's full cycle, a faint and recovery.

**Entry.** A "Social stage" button in the title's Preview list (shown like the existing Creature stage button,
release builds too) and the `--social` launch flag. The stage opens with an entry card ("Preview · Social stage.
Watch how each one behaves, then answer. Nothing here is saved."). Pause asks "Leave the Social preview? Nothing here
is saved." and returns to the title. Bible §24: the button opens a real playable slice, not a mock.

**Architecture (PROPOSED file layout, all new; nothing in the creature code is edited).**

| Layer | Folder | What it holds |
|---|---|---|
| Tuning | game/data/social/ | the slice's numbers (social_slice.json), seconds converted to whole ticks once at load |
| Domain rules (pure, no files, no scene) | game/domain/social/ | social traits from anatomy, memory and reputation, the one interaction resolver (signals and orders), the companion and hunter brains (percepts only) |
| Services | game/systems/social/ | the data loader and the sim: 60 ticks a second, seeded streams, id order, plain-data snapshots and events |
| Presentation | game/scenes/social/ | the stage root (entry, input, leave) and the code-built world view |
| UI | game/ui/social/ | the HUD (goal card, band cards, dock, caption, hint, entry card) and the tags |
| Tests | tests/ | test_social_* unit tests (fast, no skins) and a social smoke |

The sim reuses the creature stage's anatomy and movement code read-only (`CreatureStats`, the gait planner, body
mechanics and the field rules in `game/domain/creature/creature_world_rules.gd`) through preloads, and follows the
creature world sim's determinism rules: whole-tick durations, every sort tied by id, every random draw from a stream
seeded by the world seed.

**Reused art (recorded GLBs and generated skins, no primitives):** `assets/export/creature_field_ground.glb`,
`assets/export/creature_nest_ring.glb` (the nest and the den), `assets/export/creature_fruit_bush.glb` (its Fruit
mesh hidden while a bush is bare; a fruit-only copy shows a carried fruit), `assets/export/creature_meat_chunk.glb`
(at the lair), and the creatures' generated skins with their recorded part GLBs, built exactly as the creature world
builds them. Markers and tags are 2D Controls.

**Out of the slice.** Saving; the transitions in and out; mating and the editor return; generations and inherited
routes (the rule is tested only); prey hunting; a rival band; streaming across real world chunks (the far tier stands
in for it); new input actions; new art.

### 14a. What the slice delivers

Not built yet. This section is filled in, and marked IMPLEMENTED, only after the slice, its tests, its smoke and
rendered frames are done.

## 15. Acceptance mapped to tests (PROPOSED)

| Bible §8 / §13 / §14 acceptance | Proof |
|---|---|
| Recruit and dismiss a companion | sim test (befriend, join, dismiss) and the smoke |
| Complete a group task | sim test (feed the nest, no bush picked twice) and the smoke |
| Refusal or retreat | rules tests (every order acknowledged or refused with a reason; forager refuses a fight; frightened refuses to investigate) and the smoke |
| Reload with identities and significant relationships | sim test (the test-only record round trip; the real save waits for section 12) |
| Loss of the leader | sim test (faint keeps the band and its relationships) and the smoke |
| Unreachable orders | brain and sim tests (acknowledged, reported, released) and the smoke |
| Separation across streaming boundaries | sim test (far tier changes without duplication or identity loss) |
| One accidental collision is not permanent war | memory test (one bump) and sim test (the band stays friendly) |
| Two anatomies suit different social strategies; no body locked out | traits tests (display organs, throat sac, ears) and the rules test that Calm is eligible for every body |
| No rhythm minigame | rules test: the response depends on the choice, never on when it was pressed |
| Preview equals action | stage test: the dock's enabled state and tooltip match the resolver |
| The hunter investigates, pursues, disengages and never enters the nest | brain tests and the smoke |
| Determinism | sim test: the same seed and intents give the same snapshots over 600 ticks |
| Never writes the save | stage test and smoke: the slot's SHA-256 and folder listing are unchanged |
| Readability, input and captions | rendered frames at 1920x1080 and 1280x720, read by eye; headless tests cannot prove these |

## 16. Decisions for the owner

1. Approve **read and answer** (Sing, Display, Share, Calm chosen to fit what the individual shows) as the Social
   friend path in place of a call-and-response minigame.
2. Approve the slice reading the player's creature from the lineage slot (read-only), or start it from presets only.
3. The Preview button shows in release builds too, like the Creature stage button. Keep it, or debug builds only?
4. A Social save block (band, memories, reputation, learned routes) as a save schema change after the Aquatic v5
   block.
5. The entry gate (proposed: two allies and an established nest) and the exit to Tribal (proposed: a settlement choice
   at the den after three group tasks).
6. The numbers: band cap 3, join mark 6, memory weights and lifetimes, reputation step cap 0.5 and hostile mark -5,
   three bites in 60 s for 120 s of hostility.
7. Whether the creature stage should drop "a bitten creature stops listening for life" to match Bible §8 (that code
   belongs to the creature stage; this plan does not change it).
