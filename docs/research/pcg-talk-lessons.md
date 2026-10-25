# Lessons from "Practical Procedural Generation for Everyone"

Source: GDC talk by Kate Compton, who built Spore's planets and made Tracery
(https://www.youtube.com/watch?v=WumyfLEa6bU). Joshua sent the transcript on 2026-10-25. It is in the
"Spore-style evolution game" thread.

Status: PROPOSED notes. Nothing here is a decision until `docs/DECISIONS.md` records it, and anything
that adds scope needs Joshua's go.

## What the talk says

1. **Be specific.** A generator for a narrow thing ("trashy urban fantasy romance") beats one for a
   broad thing ("a novel"), because you can write down its rules.
2. **Artist in a box.** Spore's creature creator came from hours of interviews with a Disney
   animator about how he designs a creature. The designers kept asking "why" until it was rules: the
   body ("bean") shape sets the character, and the mouth hung on it sets where the creature looks.
   She credits this for how good the creator was.
3. **A catalogue of methods**: tiles, grammars, distribution, parametric (sliders as an
   n-dimensional cube), interpretive (turn simple input into rich output), and simulations
   (particles, agents). Each is simple in its base case.
4. **Random placement looks bad.** Real things cluster, nest and keep their spacing. Three
   Spore-team terms:
   - **Barnacling**: a big object gets medium objects around it, and those get small ones.
   - **Footing**: where two things meet, show it (dirt piled round a tree, a gasket where a wall meets
     a floor).
   - **Greebling**: small detail glued onto surfaces.
5. **Spore's creature pipeline was interpretive.** It took the player's skeleton, turned it into
   metaballs, built the mesh, made the UVs, animated it and painted it.
6. **Subtractive methods.** Spore's planets were not all good and there was no time to fix the
   generator, so she saved the seeds of the good ones. Generate-and-test should rank its results
   rather than throw them away forever, because a strict test can loop and never accept anything.
   Don't write your own constraint solver.
7. **10,000 bowls of oatmeal.** Mathematically unique is not perceived as unique. Background things
   only need to look like they are not clones. Regions need to feel different from each other.
   Heroes need character, and the test is "would you write fan fiction about it?"
8. **Ownership is huge.** Let players find interesting things, name them, claim them and show them
   off. Spore promoted players' creations heavily.
9. **Keep generators as data.** Tracery grammars are JSON, so strangers' generators could be run
   safely, tested and visualised.
10. **Leave time to iterate.** Spore got its generators working and had to ship them with no time
    to tune. Players notice the design around a generator more than its depth.

## Where Pangaea already matches

- **Tiles**: the endless cell world is built from authored tiles with a seam ring (S1, PlacementKit).
- **Interpretive creatures**: `docs/research/spore/CREATURE_GEOMETRY_SPEC.md` has a spine of
  vertebrae as the editable core, an implicit-surface skin and automatic rigging. That is the same
  idea, in our own original design.
- **Seeds**: worlds are seeded and deterministic (hash identity tests), so keeping good seeds works.
- **Data**: saves, the world config, the species catalog and creature bodies are plain JSON data.

## Proposed actions

| # | Lesson | Proposal | Who | Adds scope? |
|---|---|---|---|---|
| 1 | Artist in a box | Write the creature editor's auto-shaping rules as an artist's steps: silhouette first, the mouth sets the facing, then limbs balance the mass. If Joshua hires an artist, interview them the Spore way. | Creature stage, Art | No |
| 2 | Barnacling, footing | Cell-world landmarks and shells get a ring of smaller debris and a settle mark where they meet the floor. The shore (now a primitive light shaft) gets sand drift round its base when art makes the piece. | Art | Small (art) |
| 3 | Distribution | Check that food, plankton and debris clump and keep their spacing instead of spreading evenly. WorldGen already uses hashed jitter on tiles. | Engineering | No |
| 4 | Seed whitelist | Rank candidate world seeds for new lineages (a good first minute) and start new games on the best. | Balance lab | Yes (the lab is paused) |
| 5 | Oatmeal tiers | Spend the uniqueness budget on species, rivals and the player's own lineage, not on background plankton. | Design | No |
| 6 | Ownership | Name your species, a card for each species you met, and sharing a creature as a short code. A creature is plain data, so a shared one cannot run code. The Bible's discoveries are already in the save. | Design, then engineering | Yes |
| 7 | Rank, don't reject | A "random creature" button or preset generator makes several candidates and keeps the best by a score, so it can never hang. | Creature stage | Small |

Items 4 and 6 need Joshua's go before anyone starts. The rest fit work already planned.
