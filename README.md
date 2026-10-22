# Pangaea

An original evolution game inspired by the stage-based design of classic "god games": start as a single cell, evolve a body in an editor, and carry your species from the tide pool to the stars.

Everything here (code, art, names) is made from scratch. Nothing is taken from any existing commercial game.

## Play

Open `index.html` in any modern browser. No build step, no dependencies.

- **Swim:** WASD or arrow keys, or hold the mouse / a finger toward where you want to go.
- **Evolve:** `E` or the Evolve button opens the cell editor.
- **Pause:** `P` or `Esc`.

Progress saves in the browser's local storage.

## Cell stage (playable now)

- Pick a starting diet: plant eater (filter mouth) or meat eater (jaw).
- Eat plankton or meat chunks to earn DNA and grow through five sizes.
- Other species roam the pool: grazers flee, hunters chase anything smaller. Bigger hunters glow red.
- Combat is positional: spikes hurt whatever they ram, jaws bite what's in front of them, toxin glands leave a damaging trail.
- Murky water limits sight; eye spots push it back.

### Cell editor

Spend DNA on parts and attach them anywhere around the membrane. Placement matters, because the mouth side faces the way you swim.

| Part | Unlocks at | Effect |
| --- | --- | --- |
| Filter mouth | Size 1 | Eat plants |
| Jaw | Size 1 | Bite cells, eat meat |
| Flagellum | Size 1 | Top speed |
| Cilia | Size 2 | Turning and acceleration |
| Spike | Size 2 | Ramming damage |
| Eye spot | Size 2 | Sight radius |
| Shell plate | Size 3 | Health (slightly slower) |
| Toxin gland | Size 4 | Poison cloud trail |

Each size adds two part slots. Removing a part refunds its DNA in full.

## Roadmap

1. **Cell** – done (this prototype).
2. **Creature** – walk onto land; 3D body editor with spine, limbs and mouths; befriend or hunt other species.
3. **Tribe** – small RTS with a village, tools, food gathering and rival tribes.
4. **Civilization** – cities, vehicles, trade, conquest or diplomacy across the planet.
5. **Space** – a spaceship editor, star map, terraforming and alien empires.

Each stage carries traits from the one before it (diet, aggression, social style), so how you play early shapes later options.

## Development

`tools/smoke-test.js` drives the game in headless Chromium with Playwright and fails on any page error.
