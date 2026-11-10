# Civilization stage plan - PROPOSED

Status: **PROPOSED throughout**. This plan refines the working sixth era in the [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf), especially sections 10, 12-14 and 18-19. The [playthrough notes](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) establish that a shift to settlements and a regional view is a recognizable stage change; their art, names, interface and rules are not source material. The earlier [civilization proposal](../proposals/civilization-era.md) is a candidate design, not approval. This plan changes neither milestone scope nor the save schema.

## Position and entry

The intended order is Tribal -> **Civilization** -> Interstellar. Entry is an explicit choice after the Tribal settlement has demonstrated stable food, usable construction and a working relationship with one neighbor. It must not create an anonymous replacement faction. A pre-transition checkpoint is required before any production handoff.

The proposed entry record names exactly what must remain observable: `lineage_id`, `genome` and its part IDs, `lineage_history`, the founding creature's diet and handling capabilities, named Social companions, the Tribal settlement's people and resource stores, the neighboring tribe's relationship, `discoveries`, and `world_changes` such as depleted habitat. Existing `world_seed`, location, and era identity continue. Current v4 saves have these top-level categories but do not define a Civilization transaction or fully validate settlement and relationship entries; this list is an acceptance contract for future approved work, not a claim that the handoff works today.

## Play loop and smallest first slice

**Inspect a need -> commit a shipment -> follow the route -> respond to disruption -> negotiate or adapt -> inspect the local result.** The player chooses an actual resource and source settlement, sees stock reserved, watches a bounded route change delivery state, and learns why a shipment failed or arrived. Production and research need practical inputs and known prerequisites. Local creature play remains available to scout a path, negotiate at the destination, or verify the food shortage in person.

The smallest playable first slice contains two named settlements in one bounded region, one food or material resource, one route, one disruption, and one limited agreement with a neighboring group. A completed delivery changes the destination's stock; an interruption visibly delays it without teleporting goods or silently refunding them. The first agreement changes a specific access or exchange rule. No planet-wide simulation, generalized economy, or combat campaign is implied.

## Editor role and anatomy

A bounded route editor previews traversal time, capacity, exposure, ecological cost and reservation state before commitment. A research view shows the prerequisite and input a proposed upgrade consumes. A diplomacy preview states the offer and exact obligation. A settlement module editor can remain available for legitimate functional additions, using the same preview/commit rule as Tribal construction. A creature editor return remains possible through an approved lineage checkpoint; it still validates anatomy and charges adaptation cost instead of granting a free redesign.

Founders' feeding anatomy determines food demand; grasping or alternate handling paths affect loading and local labor; locomotion affects which surveyed routes are traversable. These are tradeoffs, never a reason to make a supported body plan unable to progress. Keep individual energy, inherited adaptation potential and research knowledge distinct. One universal currency cannot explain all three.

## Threats, relationships and readable outcomes

Shortage, damaged routes, habitat loss and territorial disputes are pressures the player can diagnose. Economic exchange, diplomacy and force each have explicit costs and consequences; none erases a group's prior history. A former Tribal neighbor keeps a stable identity and remembered agreement or grievance when the map expands. Regional ecology may aggregate distant organisms, but returning to a place must not duplicate stock, remove a named individual, or erase a prior ecological change. Warnings use labels and symbols alongside color, and direct-control tasks remain worthwhile.

## Save and continuity

[Current v4 save state](../saves/SAVE_FORMAT_BIBLE_AUDIT.md) includes `era`, `lineage_id`, `genome`, `lineage_history`, `discoveries`, `relationships`, `settlements`, `world_changes`, and `pending_transactions`. The last four are not yet a validated Civilization ledger. A production transition would need an owner-approved transaction definition, a pre-transition checkpoint, migration/rollback fixtures and tests proving the named entry records survive load. It must not infer approval of v5 from this document.

The [2026-10-24 Continue decision](../DECISIONS.md) keeps seeded world reconstruction. Thus a reload can preserve durable route commitments and identities only after those entries are specified and implemented; it does **not** promise resumption at the same simulation tick or a shipment midway along a path. The first slice should either checkpoint at a safe delivery boundary or define an approved recoverable shipment state before calling it persistent.

## Headless prototype evidence

A small deterministic model could prove: two settlements retain stable IDs; shipment reservation neither duplicates nor loses stock on success, disruption or cancel; the route has inspectable states; an agreement changes one eligible exchange; and aggregate-to-local switching conserves named people and goods. A fixture should enter with a particular genome part ID, named companion, neighbor relationship and habitat change, then assert those same values after a proposed transition and reload. Headless checks cannot approve the strategic interface, readable conflict cues or rendered local play.

## Relationship to the Bible

This plan narrows Bible section 10's regional acceptance to one observable shipment and one agreement. It proposes a route editor as a way to make actual delivery state legible; the Bible does not require that editor. The bounded region, two-settlement exchange, disrupted-route consequence, diplomatic behavior change and embodied return are retained. This is a proposed slice, not an expansion of the approved M1 scope.

## Open questions for owner review

1. Which first resource, route hazard and agreement make the exchange testable without disguising a full economy?
2. What safe checkpoint boundary should represent an interrupted shipment under the seeded-restart Continue contract?
3. Which Tribal identities and ecological changes must persist before a Civilization transition can be enabled?
4. Which embodied activity remains useful after the region map opens, and what editor return triggers it?
