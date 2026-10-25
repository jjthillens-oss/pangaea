# Aquatic stage plan

Status: **PROPOSED** unless a line says otherwise. The slice in section 8 is **IMPLEMENTED** (2026-10-25, tests and smoke below); its tuning stays PROPOSED. The owner approved building the Aquatic stage and its first
playable slice on 2026-10-25 (CONFIRMED: "Go for it"); every number, name and part list below is still PROPOSED
until playtested and recorded in [DECISIONS.md](../DECISIONS.md). The [GENESIS Bible](../bible/GENESIS_Master_Developer_Bible_v0.1.pdf)
is binding: §4 (era table and transition contract), §6 (Aquatic), §7 (shore link to Terrestrial), §12 (anatomy),
§13 (ecology), §14 (interaction), §18 (persistence) and §23 (M4 First continuity). The loop starts from Spore's
fundamentals in the [playthrough notes](../research/spore/PLAYTHROUGH_VIDEO_NOTES.md) and is rebuilt original: no
Spore code, art, sound or text. The earlier [aquatic era proposal](../proposals/aquatic-era.md) supplies the
tradeoffs this plan builds on.

## 1. Where the stage sits

Seven eras, in order (Bible §4, PROPOSED names): Microscopic, **Aquatic**, Terrestrial, Social, Tribal,
Civilization, Interstellar. Spore goes from the cell stage straight onto land; Aquatic is one of the two stages
Pangaea adds (the other is Social). It is where a cell lineage first has a body with a spine, fins and a tail, and
where "how you move" becomes the thing you evolve.

| Bible §4 column | Aquatic |
|---|---|
| Primary play | Explore depth zones and hunt or forage |
| New layer | Multicellular locomotion and richer senses |
| Retained from Microscopic | Diet, body tradeoffs, species relations |

Transition contract (Bible §4, binding): entering needs demonstrated capability, a survivable destination and a
player choice; the game saves before the transition and keeps the prior save as a recoverable checkpoint; the same
lineage and world records continue. No timer forces the player out of the water.

## 2. Spore's loop, kept

What Spore's cell and creature stages do (playthrough notes, sections 2 and 3), and what Aquatic keeps:

| Spore fundamental | Aquatic version |
|---|---|
| Eat to grow; food types follow your mouth | Plankton clouds, reef algae, shoal fish and vent food; the inherited mouth decides which you can eat |
| Mating call opens the editor, every few minutes | Return to your spawning nest with enough energy and meet your kin: the fin and tail editor opens |
| Editor: part grid left, subject on a plinth right, test button | Same layout: Tail, Fins, Body, Senses tabs on the left; your fish turning on a reef-stone plinth on the right; before/after swim stats |
| Friend or foe (socialize or attack) | Signal to another species to befriend it, or bite it; either is remembered |
| Nests as home | The spawning nest is your landmark, your editor return point and your respawn |
| Bigger fish to fear | A deep predator that investigates, pursues and gives up; a huge drifter that is scenery until you swim into its path |
| The stage ends by walking onto land | The shore at the near end; going ashore is your choice once your body can crawl |

Built better (the Bible's ideas on top):

- **Body matters** (§6, §12): fins, tail, body shape and a swim bladder change thrust, top speed, turn radius,
  depth holding and the depth you can stand. Two bodies on the same route swim differently, not just faster.
- **Depth warns first** (§6): every depth hazard has a readable warning phase before any harm, and harm is never
  instant or irreversible.
- **Niches, not spawns** (§6, §13): every species has a home zone and home sites; animals live there and are found
  there again. Nothing spawns around the player.
- **Places you revisit** (§6): shelters (reef arches), feeding grounds and the nest are fixed landmarks of the seed.
- **Big creatures as scenery threats** (§6): the abyssal drifter follows a fixed migration path and only becomes a
  threat when you cross it.
- **Continuity** (§4, §6, §18): lineage, genome, generation, diet, species records and friendships come from the cell
  stage and carry on.

## 3. Habitat zones

The world is one connected route from a sunlit shore down a reef slope into deep water. Depth is introduced
gradually: the slope gets steeper with distance, so a new player meets the deep only by choosing to go there.

| Zone | Depth | What lives there | Food | Danger |
|---|---|---|---|---|
| Sunlit shallows | 0 to 12 m | Your nest and kin, the shore | Plankton clouds (scaled-up microscopic life) | None |
| Reef | 12 to 30 m | Reef grazers (can be befriended), shelters | Algae patches | Low |
| Twilight drop | 30 to 60 m | Silver shoal (prey), the lancer predator | Shoal fish (meat) | The lancer |
| Deep | 60 m and below | The abyssal drifter's path, vents | Vent grazing (rich) | Pressure, the drifter |

The cell stage stays in history and in the water: plankton clouds are drawn with the cell stage's plankton and
algae art at the new scale, and the species the lineage met as a cell are named on the entry card.

## 4. Movement and anatomy

Controls: player-relative forward and turn, plus rise and dive, with burst on a held button. Keyboard (W/S thrust,
A/D turn, Space rise, Shift or C dive, E bite, Q signal) and controller use the same actions; no chords. Camera:
behind and above, steady; a depth gauge and a nest marker are always shown.

Swim rules (one rule set for play, the editor preview and the bots; Bible §12):

| Part | What it changes | What it costs |
|---|---|---|
| Tail (fluke, ribbon, lunate, paddle or whip, size 1 to 3) | Thrust, top speed, burst | Energy per second at thrust; a big tail widens the turn; each kind trades these differently (below) |
| Pectoral fins (size 0 to 3) | Turn rate at low speed, depth trim (rise and dive control), hovering | Drag (lower top speed) |
| Dorsal fin (size 0 to 2) | Stability: less drift in currents, steadier turns | Drag |
| Body (length and girth) | Long: top speed, cruise efficiency. Deep: hit points, rated depth | Long: turn radius. Deep: drag and mass |
| Swim bladder (0 to 3) | Holds depth with no effort; neutral bodies hover | Above 0 it rises when idle in the shallows and slows dives |
| Senses (eyes, barbels or lure) | Sight range; barbels sense prey in dark water; a lure draws prey in the deep | Energy upkeep |
| Mouth (inherited) | Diet: filter (plankton and algae), jaw (meat), or both | Fixed by lineage in the slice |

Tail kinds (aquatic-r2; the tuning is PROPOSED, the rules and their test are IMPLEMENTED). Each kind reads its own
row of thrust, turn penalty, drag, burst share and swim cost in `game/data/aquatic/aquatic_rules.json`, and
`tests/test_aquatic_sim.gd` checks that on the darter, the hoverer and a middle body, at every tail size, no kind is
at least as good as another on top speed, a one-second burst dash swum in the sim, yaw at 4 m/s and swim cost, and
better on one (Bible §2: a single part must not solve every problem). They are drawn with recorded creature parts and
their handles (no fish-only part yet). Measured in Godot on the darter (tail size 3) and the hoverer (size 1):

| Tail | Role | Darter: top / burst / turn radius / swim cost | Hoverer: top / burst / turn radius / swim cost |
|---|---|---|---|
| Fluke | All-rounder | 8.7 m/s / 15.7 / 10.2 m / 1.65 per s | 3.2 / 5.8 / 1.0 / 0.55 |
| Ribbon | Strong at small sizes, nimble, costly | 7.4 / 12.1 / 7.0 / 2.06 | 4.3 / 7.0 / 1.4 / 0.69 |
| Lunate | Cruiser: the top speed at strength 2 and 3, cheap, slow to start, wide turns | 10.8 / 13.7 / 19.9 / 1.32 | 3.7 / 4.6 / 1.3 / 0.44 |
| Paddle | Sprinter: the best burst and tight turns, draggy and costly | 7.9 / 21.3 / 7.1 / 2.23 | 3.8 / 10.3 / 1.2 / 0.74 |
| Whip | Thrifty: cheapest and tightest turns, slow | 5.9 / 8.0 / 4.5 / 0.91 | 3.0 / 4.0 / 0.9 / 0.30 |

The ribbon was retuned (thrust 6.4 + 1.3 per size, was 7.0 + 2.2) because it out-thrust the fluke at every size for
the same cost; that moves the hoverer from 5.2 to 4.3 m/s and its turn from 1.7 to 1.4 m (PROPOSED).

Rated depth: each body has a depth it can stand (body girth and bladder raise it). Below it, the pressure hazard
runs: a 4-second warning (creaking sound, the depth gauge turns striped amber, "Pressure: rise" text) and only then a
slow health drain, which stops the moment you rise. Death returns you to the nest (Bible §5: fair lineage
checkpoint, no lost run).

Inherited from the cell (PROPOSED trait conversion, owner decision 1 below): flagella become tail size; cilia become
pectoral fin size; eye spots become eyes; a jaw mouth gives the jaw, a filter mouth gives the filter, both give both;
spikes become dorsal spines (bite deterrence); shell plates become a deeper body (more health, slower). The cell's
colour becomes the fish's skin colour. The entry card shows each conversion so nothing changes silently.

## 5. Ecology, friends and foes

- **Reef grazers** live around their two reef shelters, feed on algae, scatter from the lancer and never leave the
  reef. Signal (Q) near one three times, a second apart, and the group befriends you: they swim with you on the reef
  and flash a warning when the lancer investigates. Bite one and the group remembers you as a foe and flees.
- **Silver shoal**: prey for jaw mouths in the twilight drop, schooling around its home ledge.
- **Lancer** (predator): patrols the twilight ledge; when it notices you it **investigates** (slows, turns its body
  side-on, a "?" tell and a low pulse sound for 2 seconds), then **pursues** for at most 6 seconds, strikes if it
  reaches you, and **disengages** when you hide in a shelter, leave its zone or outlast the chase. It returns home and
  can be met again.
- **Abyssal drifter**: a huge animal on a fixed slow loop through the deep. It is scenery unless you are in its path;
  then a shadow and a deep tone warn you 3 seconds before its sweep, which hurts a lot but does not kill a healthy
  fish outright.
- Food regrows on each site's own timer (Bible §13: no endless free food, no empty world).

## 6. Mating and the editor

Spore's rhythm: eat, return, mate, edit, every few minutes. Eating, discovering a zone for the first time and making
a friend earn adaptation points (the same economy as the creature levels rework, PR #135: actions earn points spent
in the editor; stats come from anatomy only). With energy above the mating mark, swim to the nest and press E by your
kin: the editor opens.

The editor (bounded, Bible §5): Tail, Fins, Body and Senses on the left, each option with its point cost; the fish
turns on a plinth on the right; a stats panel shows top speed, burst, turn, depth hold, rated depth, sight and upkeep
as before and after bars. Done commits the new generation (generation + 1, the parent recorded) and spends the
points; Cancel keeps the parent. The world keeps everything else: the friends, the fed sites, the drifter's place.

## 7. Exit to land (Bible §7)

The shore at the near end of the shallows is the transition point. Going ashore needs a body that can crawl (limbs,
which the Aquatic editor offers later as lobe fins) and is always a choice: the shore explains what is missing until
the body qualifies. Accepting saves a checkpoint, keeps the water reachable from the land, and opens the creature
stage with the same lineage. The land transition itself belongs to the cell-to-creature work in the "Spore-style
evolution game" thread; Aquatic hands it the lineage, it does not build its own land.

## 8. First playable slice (step 2)

Scope (PROPOSED, built in `game/**/aquatic/**`):

1. One reef-to-deep route: shallows with the nest and shore, the reef with two shelters, the twilight ledge, the deep
   with vents and the drifter's path. Built from the seed; the same seed gives the same world.
2. Two starting body variants from the cell lineage: a **darter** (from flagella: long body, big tail, small fins)
   and a **hoverer** (from cilia: short deep body, big fins, swim bladder). On the same route the darter is faster in
   a straight line and the hoverer turns tighter, holds depth and goes deeper. Tests measure both on the same course.
3. Depth hazards that warn first: pressure below the rated depth, the lancer's investigate tell, the drifter's
   shadow.
4. Species in their own niches: grazers on the reef, the shoal on the ledge, the lancer on its patrol, the drifter
   on its loop. None spawn around the player.
5. Mating at the nest opens the fin and tail editor; committing makes the next generation.
6. Lineage carried over from the cell stage: lineage id, generation, genome-derived body, diet, colour, species
   records and friendships are read from the lineage save; the entry card shows them.
7. Reachable from the title in debug builds and with `--aquatic`, like the creature stage preview.

Out of scope for the slice: the land crossing, currents, a dance
mini-game, art beyond the existing Blender-authored props and the generated creature skin, and audio beyond the
existing synth hooks.

Architecture (CLAUDE.md layout):

| Layer | Files | Owns |
|---|---|---|
| Domain | `game/domain/aquatic/` | Body to swim stats, cell genome to aquatic body, depth zones and hazards, the editor's costs and validation, the species brains. No scene, UI or files. |
| Systems | `game/systems/aquatic/` | The deterministic world sim (60 ticks a second, seeded streams, sorted by id), reading the lineage save and the tuning data. |
| Data | `game/data/aquatic/` | All tuning numbers. |
| Scenes | `game/scenes/aquatic/` | The stage root, the 3D world view, the editor's plinth. Presentation only. |
| UI | `game/ui/aquatic_*` | The HUD (energy, health, depth gauge, nest marker, warnings) and the editor panels. |

The fish's body is drawn with the creature stage's generated skin (`SpineRig`, owner-approved runtime skins) and
its Blender-authored parts (tail fluke, fins, eyes, mouth). Props reuse recorded Blender assets (rocks, the arch,
the nest ring, plankton, algae).

File boundaries: the cell stage (`game/scenes/pool`, `game/systems/pool_sim.gd`) and the creature stage
(`game/**/creature/**`, the creature editor) are read, never edited, here. `game/scenes/main.gd` and the start screen get only
the entry hook. The cpart art belongs to the art thread; the slice uses parts already recorded.

## 8a. What the slice delivers (IMPLEMENTED)

| Piece | Where | Checked by |
|---|---|---|
| Swim stats from the body, the cell conversion, edit costs | `game/domain/aquatic/aquatic_body.gd`, `game/data/aquatic/aquatic_rules.json` | `tests/test_aquatic_sim.gd` |
| The route, niches, hazards, friend or foe, mating, generations | `game/systems/aquatic/aquatic_sim.gd` | `tests/test_aquatic_sim.gd`, `tests/test_sim_purity.gd` |
| Reading the cell lineage (read-only) | `game/systems/aquatic/aquatic_lineage.gd` | `tests/smoke/aquatic_smoke.gd` |
| World view, HUD, editor, stage root | `game/scenes/aquatic/`, `game/ui/aquatic_hud.gd`, `game/ui/aquatic_editor.gd` | `tests/smoke/aquatic_smoke.gd` (in `tools/check.sh`) |
| Sea floor (Blender, record, baked tiles) | `tools/blender/make_aquatic_world.py`, `assets/records/aquatic_seafloor.json` | `tests/test_assets.gd` |

Measured on the shared rules: the darter tops 8.7 m/s and turns on a 10 m radius at speed, stands 36 m; the hoverer
tops 4.3 m/s (5.2 before the aquatic-r2 ribbon retune), turns on 1.4 m, holds its depth and stands 76 m. The lancer pursues at 6.4 m/s, so the darter outruns
it and the hoverer must hide in an arch or burst.

## 9. Acceptance (Bible §6 and §23 M4)

- Two body variants on the same route show different movement outcomes (automated: the same course, both bodies,
  different times, turn radii and depth reached).
- Every depth hazard warns before harm (automated: no damage tick before the warning has run).
- Species stay in their niches over a long run (automated soak).
- Mating opens the editor and a commit makes generation + 1 with the parent recorded; cancel changes nothing.
- The cell lineage's id, generation, diet and colour arrive in the aquatic body (automated).
- Discovery and relationships survive a reload: the slot keeps the aquatic block (save v5) and the smoke opens the
  stage again to the same fish, generation, finds, points and place (IMPLEMENTED).
- Windows build exported; not Windows-verified until launched there.

## 10. Decisions for the owner

1. Trait conversion from the cell (section 4): approve, or choose a different mapping.
2. Saving the aquatic stage: CONFIRMED by Joshua 2026-10-25 02:48 ("Yes, add aquatic saves (v5)"). Save schema v5
   adds an `aquatic` block (body, generation, history, finds, relations, meals, place, energy and health; points
   stay in `adaptation_points`); v4 -> v5 adds it empty. The stage saves on a new generation, a find, a relation
   change, a death and on leaving. The era field is not changed (decision 3). IMPLEMENTED; see docs/DECISIONS.md.
3. When the cell stage offers "go to the sea" (the cell-to-Aquatic transition): proposed at cell size 4 at the
   pool's edge, as a choice.
4. Whether oxygen is ever added (Bible §6 makes it conditional; the slice uses pressure only).
