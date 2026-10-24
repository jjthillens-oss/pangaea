# Social stage plan — PROPOSED

Status: **PROPOSED**. The [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf) §§4, 8, 12–14, 18–19 is binding. The [playthrough notes](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) describe meeting other creatures, choosing friendly or hostile encounters, and returning to an editor. Those are observations of a gameplay loop, not a source for code, assets, interface layout, or a universal minigame. This plan adds the Bible's distinct Social era **between Terrestrial and Tribal**. It does not authorize production changes.

## Entry and player promise

The player remains their creature, with the same lineage, body, territory, encounters and ecological needs. A stable home range and repeated recognizable encounters unlock opportunities to form a group; an explicit transition choice introduces social goals without deleting feeding, exploration, swimming or danger. The first task is to recognize one individual, communicate an intention and cooperate on food or safety. The later settlement layer is earned through repeated coordination rather than a cut to a disconnected management game.

## Loop and first slice

**Meet → signal → read response → cooperate or contest → remember → adapt.** The player approaches an individual with a visible disposition and needs, chooses an intention, sees acknowledgement or refusal, and experiences a consequence. Gathering, defense and moving through a dangerous route remain embodied tasks. An editor return after a meaningful group milestone lets the player test body changes that support the chosen strategy. Anatomy remains relevant but social play is a viable alternative to fighting, not a compulsory replacement for survival.

The first slice has the player, one recruitable individual, one wary individual, one shared food route and one threat. It must support friendship, refusal, retreat and a peaceful recovery from a failed approach. A target may remember repeated help or harm. Avoid single-hit permanent hostility. Local actors can use detailed behavior while distant groups use conservative aggregate updates that keep significant identities.

## Control and communication

- Direct creature control continues. A compact group-intention view adds **follow, wait, investigate, retreat, assist** as commands; the camera may pull back for awareness but returns to embodied play at any time.
- Every command has a clear target, acknowledgement, progress or inability response, and cancellation. Unreachable orders time out, release reservations and provide a route or reason rather than leaving a frozen companion.
- Signals have range and modality shaped by anatomy. A quiet or poorly sighted body gets an accessible substitute; no body choice makes the basic command set unusable. Show recognition, signal, response and consequence through animation, text and sound, not color alone.
- The action preview and execution must consult the same eligibility rules for visibility, range, anatomy, cooldown and cost. A failed action explains its missing requirement without charging resources.

## Roles, anatomy and learned behavior

| Role or trait | Suggested advantage | Visible cost or limit |
|---|---|---|
| Scout with long-range sensing | Finds routes and warns companions | Energy, exposure, false alarms |
| Defender with protective anatomy | Shields a retreating group | Lower pursuit speed and food demand |
| Forager with reach or handling ability | Gathers or carries local food | Poor combat posture or slower travel |
| Strong signal organ | Communicates through obscured terrain | Body cost and predator attention |

These roles are bounded behaviors, not character classes. Individuals retain names/IDs, needs, memory of significant interactions, ancestry and body traits. Learned route or hazard knowledge can be passed between generations only through an explicit, testable rule. A companion can refuse, flee, become separated or die; leader loss must not erase the group or make the save unloadable. All tuning and unlock conditions are PROPOSED.

## From social group to tribe

Repeated successful cooperation around a site can support a settlement choice. The handoff carries group members, their relationships, local creatures, habitat state and resource obligations into Tribal play. It should expose the future settlement's reachable food and shelter constraints before commitment. Tools and buildings are introduced by the Tribal era; Social does not silently grant technology. The player can still leave the emerging site to forage or revisit earlier habitats.

## Acceptance evidence

1. Recruit and dismiss one companion, complete a shared route task, then reload with the same identities and important relationships.
2. Refusal, retreat, an unreachable order and separation across a streaming boundary all resolve with clear feedback and no duplicate actor or resource.
3. Two anatomy plans support different social strategies without blocking the basic control set.
4. A short embodied task remains useful after the strategic group view is available.
5. Rendered keyboard/controller, captions, color-blind cues and readable text are reviewed; headless tests cannot prove those qualities.

## Decisions for owner review

Approve the minimum group size and event that offers the Tribal transition, which learned behaviors can be inherited, which interactions persist as reputation, and whether a first slice needs a hostile neighbor. This plan deliberately avoids a fixed morality score, a mandatory rhythm contest and an automatic stage transition.
