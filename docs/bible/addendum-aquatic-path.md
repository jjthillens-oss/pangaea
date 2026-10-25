# GENESIS Bible addendum: the aquatic path

**Status: PROPOSED. Not binding until the owner approves it and `docs/DECISIONS.md` records the approval.**
This addendum extends GENESIS Master Developer Bible v0.1 so that a lineage may stay in the water through every
era. It changes no CONFIRMED requirement, no era count or order, and no milestone before M5. It is the "bounded
content plan" that Bible §4 requires before an alternative path is built. Where this addendum and the Bible
disagree, the Bible wins until the owner says otherwise.

- **Date:** 2026-10-25
- **Source of the demand:** `docs/research/aquatic-path-wishes.md` (ranked wishes A1 to A21) and
  `docs/research/community-wants.md` themes 6 and 12.
- **Owner's intent (2026-10-25):** "an aquatic underground, like underwater world with cities and civilization ...
  make sure that the aquatic stage is building that out."
- **Change control (Bible §28):** on approval, record date, decision, reason, impacted sections (§4, §6 to §11, §23,
  §26) and migration implications (none to the save schema until a settlement slice is specified).

## A. Principle (adds to §4)

A lineage that evolves in the sea may remain a sea lineage. The land route and the sea route are both supported
paths to the Interstellar era. Each era specification gains an **aquatic variant** that satisfies the same
transition contract: demonstrated capability, a survivable destination, a player choice, a save before transition,
one earlier activity still playable, one earlier adaptation that still matters, one historical relationship that
persists. A sea lineage is never forced ashore by a timer, and a land lineage is never forced back to sea.

**Bounded, not doubled.** The aquatic path shares every system with the land path (genome, phenotype, interaction
resolver, ecology regions, construction modules, research, persistence). What it adds is content: one habitat
family per era, one rig family or body-plan set, one settlement module set from era 5, and the tuning that makes
water different. Seven eras do not authorise two full campaigns; they authorise one campaign with two habitats.

**Tone (design position for the owner).** GENESIS is stylised and original (§1, §15). The addendum treats an
advanced sea people as achievable through understandable tradeoffs rather than as impossible: heat from vents, not
fire; power from currents and living electric organs; light as a managed resource; metal scarce and precious;
living material shaped by breeding in place of much early machinery. This is a game-design stance, not a claim
about real-world feasibility, and it is open to owner review.

## B. Era 2 Aquatic (adds to §6)

Already specified in `docs/stages/aquatic-plan.md`; its first slice is IMPLEMENTED, and its section 7a (on the
Aquatic stage thread's branch at the time of writing) builds the shore exit: the shore is never forced, a fish
whose body meets the crawl rule is offered "Crawl onto land?", declining writes the lineage history event
`stayed_in_the_sea` once, going ashore writes `came_ashore`, and later eras read which path the lineage took.

PROPOSED addition, on top of that: a **deep route** offer as a second choice beside the shore. It has its own
demonstrated capability (depth holding or senses in the dark), its own survivable destination (a lit reef shelf or
vent field) and its own history event (proposed name `went_deep`, in the same family as the two above). Taking it
leads into the era-3 aquatic variant in section C; declining either offer keeps all current content playable with
no penalty. Nothing in this paragraph is built, and the Aquatic stage thread will not build it before the owner
approves this addendum.

## C. Era 3 Terrestrial, aquatic variant (adds to §7)

The land era's sea twin is **the open reef**: a larger connected habitat than era 2 with currents, kelp forests,
caves and a first vent field. Its loop is the Bible's: explore, locate shelter and food, manage stamina (against
current), establish a nest, adapt to pressure (a season of cold current or a bloom that chokes a zone).

- **Body plans:** one supported set with fins and tail retained, plus one amphibious set (lobe fins or limbs) that
  forages on the tideline. Limb placement affects crawling, bracing against current and reach, with the same
  diminishing returns and attachment rules as land limbs (§12).
- **Water remains useful** for the land lineage (already in §7); **land remains reachable** for the sea lineage: the
  tideline is a shared zone, and an amphibious body plan can forage it.
- **Acceptance:** an era-2 adaptation remains useful; an edited body crosses a current field differently; a nest
  persists; a predator investigates, pursues, disengages and recovers in three dimensions without getting stuck.

## D. Era 4 Social, aquatic variant (adds to §8)

Shoals, pods and reef groups. Communication uses signals that read underwater: sound, light patterns, posture and
touch, each with an accessible substitute (§8, §19). Group orders are the Bible's five (follow, wait, investigate,
retreat, assist). The aquatic variant adds one companion task that needs a swimmer and a wader together, so the
shore gradient stays meaningful. Relationships, roles and memory carry the land era's rules unchanged.

## E. Era 5 Tribal, aquatic variant: the reef settlement (adds to §9)

This is the heart of the owner's request and the first new content the addendum proposes to build.

- **Settlement:** functional modules placed on and in a reef: shelters stacked from shell and stone or grown from
  living coral; a hearth that is a tended vent or warm seep; food pens and kelp or shellfish beds; a lookout; a
  nursery. Placement previews, collision checks, access validation and explicit costs follow §9. Modules occupy
  volume, not footprint: height matters, and workers path in three dimensions.
- **Tools as anatomy:** a sea people's tools are shell, bone, stone and living things. Manipulation ability comes
  from any approved grasping part (tentacle, claw, lobe fin, prehensile tail); the Bible already forbids
  prohibiting advancement for creatures without hands.
- **Resources (sources and sinks):** food that cannot be stored dry, so pens and beds matter; light, scarcer with
  depth, which decides where crafts can be done; warmth from the vent, which decides what can be shaped; shell,
  stone and kelp fibre as materials. No metal in this era.
- **Diplomacy:** cooperation, exchange, territorial disagreement and conflict with neighbouring groups, some of them
  land or shore groups met at the tideline. Culture emerges from repeated actions (§9).
- **Acceptance:** establish a small functioning reef settlement, resolve a resource shortage (a dimmed season or a
  cooled vent), interact with a neighbouring group, and show that individual lineage and body traits still matter.
- **Embodied play retained:** swimming, feeding, observation and local interaction from eras 2 to 4.

## F. Era 6 Civilization, aquatic variant: connected reefs (adds to §10)

- **Region:** a bounded sea region with several reef and tideline settlements joined by current routes. Transport
  follows routes and actual delivery state (§10); a current that shifts has a visible consequence.
- **Production and research:** current-driven works, tended vent forges for the few low-melting metals, bred and
  tamed sea life as labour, lighting and sensing; metal otherwise arrives as a scarce good from shore or trade, so
  it is precious and its routes matter. Research needs prerequisites and practical inputs, and the aquatic tree
  shares the land tree's shape with different inputs rather than being a separate tree.
- **Sea and shore peoples:** a land or tideline culture on the same world is a diplomatic partner, rival or trading
  counterpart. Treaties change behaviour; conflict targets and consequences are readable.
- **Vehicles:** an approved module set for underwater craft before arbitrary forms (§11's ship rule applied early).
- **Presentation (from city-builder players' complaints, research finding 5):** a settlement reads as a living reef,
  not a refinery: homes, pens and workshops mix; sea life passes through; light and life are visible from inside;
  routes curve with the current rather than running as straight pipes.
- **Acceptance:** two settlements exchange goods along a current route, a disrupted route has a visible
  consequence, one agreement with a shore people changes behaviour, and a local swim remains playable.

## G. Era 7 Interstellar, aquatic variant (adds to §11)

A sea people's spacecraft is a water-filled habitat with the Bible's functional constraints (range, capacity,
habitat support). Colonisation scores worlds by ocean suitability as well as land. The homeworld's reefs stay
relevant through culture, resources, relationships and return activities. First contact with an outpost of a land
people, or vice versa, uses the §11 rules.

## H. Milestones (adds to §23)

No change to M0 to M4. Aquatic variants attach to later milestones and one spike precedes them:

| Milestone | Addition | Exit evidence |
| --- | --- | --- |
| M4 First continuity | The Aquatic stage's deep-route offer sits beside the shore offer | Both offers tested; declining either keeps play going |
| **M4.5 Reef spike** (new, small) | One reef settlement with three modules, one vent hearth, one food pen, three workers pathing in 3D, one camera | Owner-reviewed capture; a shortage resolved; no stuck worker in a 10-minute soak |
| M5 Social foundation | Underwater signal set and the swimmer-and-wader companion task | Scenario test with reload |
| M6 Settlement slice | The era-5 reef settlement as a variant of the land settlement, sharing modules code | Resource, construction, diplomacy and embodied loop, underwater |
| M7 Regional slice | Current routes between two reef or tideline settlements; one shore-people agreement | Regional consequence scenario |
| M8 Space slice | Water-filled ship module set; ocean suitability in survey | Cross-world persistence with a sea lineage |

The reef spike is deliberately before M5 because 3D settlement navigation and camera were the reasons Spore's team
cut the content (research finding 6). It is a risk reduction, not a feature.

## I. Risks (adds to §25)

| Risk | Early warning | Response |
| --- | --- | --- |
| Two campaigns' worth of content | Separate module sets or research trees for sea and land | Shared systems and module code; content, not systems, differ |
| 3D settlement navigation and camera | Workers stuck, players losing "up" | Reef spike before M5; movement plane constraints where they help |
| Sea path becomes the easy or the hard path | Playtest completion rates diverge | Tune shared difficulty presets, not separate rules |
| Realism arguments stall design | Debate about metallurgy in reviews | Owner-confirmed tone position in section A |

## J. Decisions for the owner (adds to §26)

1. **Approve the aquatic path as a supported route** to the Interstellar era (this addendum), or limit it to era 4
   with an explained gate before Tribal (backlog decision D2 option B), or keep the current plan where era 3 onward
   is land only.
2. **Confirm the tone position** in section A (vents, living machines and scarce metal as understandable tradeoffs).
3. **Approve the M4.5 reef spike** as the next new content after M4, and its placement before M5.
4. **Decide the tideline rule:** whether a sea lineage may hold shore quarters in era 5 and 6 (recommended: yes,
   with the amphibious body plan) or must trade for everything on land.
5. **Name the aquatic settlement modules** for era 5 (seven proposed: shelter, hearth vent, pen, bed, lookout,
   nursery, workshop) or cut the set.

## K. Recommendation

Approve 1 as a supported route with sections B to H as the bounded plan, confirm 2 and 3, answer 4 as "yes, with
the amphibious plan," and accept the seven modules in 5 as PROPOSED tuning data. Record the approval in
`docs/DECISIONS.md`, add this file to the Bible folder's index, and raise the Bible to v0.2 at the next revision.
