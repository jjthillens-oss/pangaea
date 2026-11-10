# Interstellar stage plan - PROPOSED

Status: **PROPOSED throughout**. This plan refines the working seventh era in the [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf), especially sections 11-14 and 18-19. The [playthrough observations](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) show a scale change to navigation, contact and visits between worlds; they do not authorize copying presentation, assets or mechanics. The [interstellar proposal](../proposals/interstellar-era.md) supplies candidates rather than approvals. No new save schema or production milestone is established here.

## Position and entry

Civilization -> **Interstellar** is the intended final era transition. The first departure is a player choice after a viable expedition has an explicit destination, supplies and return capacity. A recoverable pre-departure checkpoint is required. The homeworld remains a playable place instead of becoming a menu background.

A proposed entry record retains the same `lineage_id`, `genome` with stable part IDs, `lineage_history`, named founder and descendants, inherited diet and habitat tolerances, the home settlement IDs and stocks, a prior shipment or route obligation, a named diplomatic ally or rival, `discoveries`, `relationships`, `world_changes`, `world_seed`, and culture/knowledge records once their representation is approved. Culture and interworld records are not defined by today's v4 format; this is a required continuity test for future design, not a claim that it can currently load.

## Play loop and smallest first slice

**Plan -> provision -> travel -> survey -> decide -> establish a viable outpost -> return -> observe a consequence.** The player compares a destination's conditions with the lineage's actual biological needs, reserves supplies, inspects ship constraints, makes a recoverable journey, surveys a bounded habitat and commits only to an outpost that can sustain its residents. Exchange of a useful resource or discovery then changes a homeworld decision. Direct creature play on both worlds supports habitat observation, local contact and a return to earlier relationships.

The smallest playable first slice has the homeworld and one reachable second world in a small authored star region. It includes one approved modular ship configuration, one survey site, one habitat-support requirement, one outpost choice, an outbound leg and a return leg. An unavailable destination and one interrupted journey have recoverable outcomes. The slice deliberately excludes unlimited procedural content, a galaxy economy and seamless planetary flight.

## Editor role and anatomy

A bounded ship editor previews range, carried mass, reserve capacity, habitat support and a safe-return margin from approved modules. An outpost placement preview shows local food, atmosphere or shelter suitability against the lineage's documented needs. Neither preview grants free resources; failure must explain the missing requirement before commitment. A creature editor return continues to validate the same inherited body and adaptation costs where an approved checkpoint allows it. Ship modules are functional equipment, not replacements for anatomy.

An inherited feeding organ changes what provisions an outpost needs; respiratory or thermal tolerance changes shelter demand; locomotion changes which survey ground the creature can traverse. A supported body plan must have an alternate viable strategy instead of being silently barred from the era. Individual energy, inherited adaptation potential and civilization knowledge have distinct sources and uses.

## Threats, relationships and local consequences

Supply depletion, unsuitable habitat, blocked destinations, failed contact and a broken home route should be forecast with actionable reasons. First contact has readable intentions and memory of encounters; a named homeworld ally or rival still affects offers and trust after the voyage. Distant ecosystems can be summarized, but revisiting either world must conserve named residents, outpost inventory, discoveries and significant ecological changes. A failed expedition should have a bounded recovery path rather than corrupting or deleting the lineage. Visual symbols and text reinforce all critical color and audio cues.

## Save and continuity

The [v4 audit](../saves/SAVE_FORMAT_BIBLE_AUDIT.md) establishes current durable keys such as `era`, `lineage_id`, `genome`, `lineage_history`, `discoveries`, `relationships`, `settlements`, `world_changes` and `pending_transactions`. It also records that cross-era checkpoints and interworld travel transactions are not yet specified or tested. An implementation would require separate owner approval for any new record or migration, last-known-good recovery, stable world/outpost IDs and an explicit rollback rule before departure can be called safe.

The [confirmed Continue decision](../DECISIONS.md) rebuilds the cell world from its seed; it does not promise exact-tick restoration of a voyage. A future travel slice must say whether a save lands before departure, after arrival, or in a separately approved recoverable journey state. This plan does not assume a live ship position or remote ecosystem tick can be resumed with current v4 data. On return, the same lineage, culture, discovery and relationship records must be demonstrably available at home.

## Headless prototype evidence

A deterministic two-world model could test that a viable ship and outpost pass the same preview and commit rules, while insufficient capacity or habitat support charges nothing. Seeded destination selection and all tie breaks should be stable. Fixtures should assert the exact lineage ID, genome part ID, home settlement ID, neighbor relationship, discovery and ecological change before departure, after outpost establishment, and after return. Interrupted travel and unavailable destinations should restore the agreed safe boundary without duplicating supplies or residents. Rendered review must separately assess navigation clarity, contact communication and useful embodied play.

## Relationship to the Bible

This narrows Bible section 11's first demonstration to a complete two-world round trip with one outpost. The Bible permits a small authored region and seeded destinations; the proposed ship and outpost previews make functional limits inspectable. Infinite content, arbitrary ship forms, seamless travel and a new persistence protocol remain undecided. The same lineage, homeworld relevance and return requirement are retained.

## Open questions for owner review

1. What is the first destination's one meaningful biological difference, and what alternate strategy keeps every supported body viable?
2. Which exact checkpoint boundary should an interrupted outward or return leg use under seeded restart?
3. Which culture, route and contact records require a new approved save representation before the first transition?
4. What homeworld activity should be consequential on return, and which ship modules are approved for the first editor?
