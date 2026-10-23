# Terrestrial era — PROPOSED

Status: **PROPOSED** throughout. This is a design proposal, not an implemented feature or an approved change to milestone scope. It develops GENESIS Bible v0.1 §§4–7, 12, 18–19 and the existing decisions log. “Terrestrial” is the Bible's working name for the land era; the owner has not fixed final era names or boundaries.

## Core loop — PROPOSED

The player leaves a sheltered shore to find food, traverses terrain with a body they designed, returns to a nest, and edits the next generation in response to visible pressures. Short loops across wet shore, cover and dry ground expose tradeoffs before a larger map is considered. A slope costs stamina; vegetation changes cover and access; exposure gives an early warning before a dangerous area. The nest anchors recovery and a repeatable route. Food regeneration and safe retreat must prevent one poor adaptation from ending the lineage.

Swimming remains a useful local activity. A shoreline route allows the player to use inherited aquatic movement to reach food or escape danger, while a more land-efficient body handles longer dry passages. An aquatic species or former rival remains identifiable at the water's edge, retaining a historical relationship rather than restarting the ecology.

## Anatomy and editor — PROPOSED

The first slice supports a small, explicitly approved set of body plans, rather than arbitrary limbs. Limb placement changes support polygon, reach, turning and gait selection. Mass and body length affect stamina demand and slope ability. Feet and appendage variants create costs in water, so all-terrain optimization is not free. A swimming organ stays useful in the river or shallows but may burden sustained land travel.

The editor previews a short slope, a flat route and a water crossing with comparable movement, stamina and stability values. It rejects unsupported structures with a plain explanation before spending adaptation potential. Generated torso and limb skins follow the current owner-approved direction in `docs/DECISIONS.md`; authored detail parts retain Blender source and asset records. Motion is bounded by tested rig families and proportions. The proposal does not promise physically accurate gait for every anatomy, in line with Bible §7.

## Threats — PROPOSED

A predator investigates, pursues, disengages and recovers with visible tells and bounded navigation timeouts. Terrain and cover affect whether it sees or reaches the player, but do not make an invisible instant-kill rule. Exposure and exhaustion warnings appear before the player loses a safe return route. A nearby water refuge can save a capable swimmer. The first acceptance scenario should verify the predator does not get stuck and the player can recover after entering unsuitable terrain.

## Carryover and transition — PROPOSED

The transition is offered only after the lineage demonstrates a survivable shore route; a timer never forces a fully aquatic build onto land. The player may continue aquatic play within approved scope. Before accepting, the game explains the new stamina, nest and terrain responsibilities, saves a recoverable checkpoint, and preserves the same genome identity, ancestry, discoveries, aquatic habitats and species relationships. An inherited swimming adaptation remains functional in a real water crossing. The earlier aquatic foraging route remains playable. A known rival's response at the shoreline reflects the prior relationship.

Implementation of this transaction would need a separately approved design for persistent nest and location data, plus migration and reload tests. This document proposes no save schema, does not add an era, and does not expand the current milestone.

## Departure from the Bible — PROPOSED

Bible §7 requires shore connections, terrain choices and a small set of body plans but does not define a first playable map. The wet-shore/dry-route/refuge loop narrows that broad vision to a testable slice. The editor's three comparison routes make the Bible's anatomy consequences legible before purchase. The proposed water refuge is one concrete safe recovery route; it needs playtesting to ensure it does not trivialize predators.

## Open questions for the owner — PROPOSED

1. Which body-plan families and extreme proportions should the first land slice support?
2. What minimum aquatic activity must remain directly playable after a land transition?
3. Does the first nest persist as a single location, or may the player choose among several sites? This would affect save design.
4. Which relationship from aquatic play should appear in the first shoreline encounter?
