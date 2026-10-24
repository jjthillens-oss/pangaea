# Aquatic stage plan — PROPOSED

Status: **PROPOSED**. This is a design plan, not authorization to change the game or its save schema. It follows the seven-era order in the [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf), especially §§3–7, 12–14 and 18–19. The [playthrough observations](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) establish the familiar eat, mate, editor, grow rhythm; all implementation and presentation here must be original. The earlier [aquatic era proposal](../proposals/aquatic-era.md) supplies candidate tradeoffs, not approved tuning.

## Position and entry

The intended order is Microscopic → **Aquatic** → Terrestrial → Social → Tribal. A microscopic lineage enters an expanded connected water habitat when it can survive a chosen route and the player elects to transition. Entry keeps lineage and ancestor IDs, genome history, world seed, discoveries, relationships, diet and existing habitat state. Show the proposed body and its inherited capabilities before committing. Write a recoverable checkpoint and preserve the last known good save; do not infer a new schema from this plan.

The first aquatic route begins in a shallow refuge with visible food and a safe return path. A deeper feeding area and a connecting current make the new depth dimension meaningful. Earlier cell ecology remains present and recognizable; a former microscopic predator or food source should have a legible relationship to the new body. The exact trait conversion is an open design decision, and a prototype must demonstrate it without silently replacing a player's anatomy.

## Play loop

1. **Observe and choose.** Read prey motion, current, shelter and rival cues; choose a depth and feeding route.
2. **Eat or interact.** Filter, graze, pursue, evade or approach another organism. Feeding changes energy and growth; cooperation and conflict create remembered relationships.
3. **Return and mate.** Reach a recognizable spawning site. A mate encounter opens the editor as a meaningful reward, using the existing adaptation economy where the production design permits it.
4. **Edit and test.** Preview the offspring in a short swim course at two depths, with turning, feeding reach and energy shown together. Commit a legal body and return to a changed world.
5. **Grow and discover.** New routes and organisms become reachable; the world records the discovered place or relationship rather than a generic distance score.

The small first slice contains one safe refuge, one deep food site, one rival or predator and one spawning return. A successful loop requires two genuinely different anatomy choices to produce different viable routes. Timing, costs and content counts remain PROPOSED until measured in playtests.

## Controls and readable feedback

- Use player-relative forward/turn plus ascend/descend with remappable actions; offer an alternate camera-relative control mode if testing shows it is needed. A controller needs the same actions without simultaneous precision button chords.
- Keep a stable behind-and-above camera for navigation, a clear horizon/depth cue and a return marker for the spawning site. Do not depend on hue alone to distinguish food, rivals or hazards: shape, motion, labels and audio must reinforce them.
- Show only actionable energy, health, depth and route information during play. A change in current or predator intent needs a sustained cue rather than flashing. Text size and captions must meet §19 review before implementation.
- Swimming should visibly express the body: thrust, drag, turn radius and buoyancy. Depth is optional tactical space, not an invisible oxygen timer. Oxygen or pressure enters only if a prototype proves it creates understandable decisions.

## Editor and anatomy

| Candidate part or trait | Play effect to test | Cost or tradeoff to show |
|---|---|---|
| Tail shape and muscle | Burst acceleration and sustained thrust | Energy draw and turning cost |
| Paired fins | Slow-speed steering and depth trim | Drag and exposed area |
| Buoyancy tissue | Holding a depth against a current | Slower descent or lost burst control |
| Feeding organ | Filter reach, grazing or pursuit | Diet specialization and body cost |
| Sensory surface | Detecting motion or food in obscured water | Energy and vulnerable surface |
| Protective surface | Surviving contact or a predator strike | Mass and reduced agility |

All numbers, part availability, and inheritance mappings are PROPOSED. The preview must use the same physics and part constraints as play, show before/after values and reject clipping or unsupported anatomy. Recognize inherited microscopic choices instead of granting a free unrelated redesign. The editor should preserve lineage identity while making the new scale apparent.

## Ecology, threats and continuity

Depth and current change food, shelter and encounters rather than just background color. A predator telegraphs investigation, pursuit and disengagement; a rival can compete for a route and remain identifiable across visits and reloads. Distant population counts may be aggregate, but entering a local area must not duplicate individuals or resources. A kill, alliance or depleted feeding site has a visible consequence on revisiting. The player can still choose an earlier aquatic route once a deeper route opens.

## Exit to land

Reaching a sheltered shoreline, surviving the route and acquiring a body that can support a short crawl creates a **choice** to begin the Terrestrial era. The shoreline encounter should test the actual body and offer a readable explanation when it is not viable. On acceptance, save a checkpoint, show the same lineage crossing the boundary, then open the creature editor to adapt to weight support and air exposure. Preserve access to water and do not skip this aquatic stage in production progression. The standalone land transition prototype can test this handoff without defining the production trigger or save migration.

## Acceptance evidence before implementation

- Two distinct bodies complete the first loop by different routes; a poor body receives clear feedback and a recoverable path.
- An inherited microscopic trait affects aquatic play and survives save/reload with the same lineage identity.
- The mating/editor handoff grants no duplicate resources; cancel, commit and interrupted save paths are tested.
- Keyboard and controller traversal, color-blind cues, readable text, motion and flashing are checked with actual rendered builds. Headless tests alone cannot establish these.
- Shoreline entry and return preserve the seven-era order and a last known good save.

## Decisions still needed

The owner must approve trait conversion, the first playable body/part set, whether a rival or cooperative species enters the first slice, the land-entry capability threshold, and any oxygen or pressure rule. This plan does not change the M1 scope, create production assets, or approve a new save format.
