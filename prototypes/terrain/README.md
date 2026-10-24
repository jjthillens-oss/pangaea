# Terrain chunk prototype — PROPOSED

This is a standalone Godot 4.7.2 research prototype for a possible terrestrial era. It is **PROPOSED** tuning, not a game system or a commitment to a land-stage map. `prototypes/.gdignore` keeps it out of the main game's import. The [terrestrial era proposal](../../docs/proposals/terrestrial-era.md) calls for readable wet-shore, cover, dry-route and refuge choices; these six prototype biomes explore that spatial vocabulary without setting the era's scope.

## Run — PROPOSED

From the repository root:

```text
godot --headless --path prototypes/terrain --script res://tests/run_tests.gd
godot --headless --path prototypes/terrain --script res://run.gd -- --seed=1 --radius=2
```

The runner generates `(2R+1)^2` chunks, prints milliseconds and min/max height for each chunk, prints a biome histogram and river/lake counts, and writes two ASCII PPM (`P3`) images to ignored `builds/terrain/`: `preview_<seed>.ppm` is greyscale height and `preview_<seed>_biomes.ppm` uses biome colours with blue river cells. `R` is limited to 0-16 so a mistaken argument does not create an unbounded preview. No game scene loads this project.

## Generation — PROPOSED

`TerrainChunk.generate(seed, cx, cz, size=32)` returns `(size+1)^2` float32 height samples, `size^2` byte biome ids, and stored-sample min/max heights. Height uses four octaves of original smooth value noise; moisture uses three independent octaves. Both noise fields use integer lattice hashing and a different fixed seed salt derived from **world seed only**. Each octave doubles frequency and halves weight. Height is in the proposed `[-10, 10]` range. The six id names are sea, shore, grass, forest, rock and snow. Sea and shore are low elevation, snow and rock are high elevation, and moisture chooses forest or grass in the middle. Those bands and scales are prototype tuning only.

All samples are evaluated at integer **world** coordinates `cx * size + local_x`, `cz * size + local_z`. A chunk index never changes the noise seed. Neighbours therefore ask for the same world positions on their shared edge, giving bit-identical float32 values without copying an edge or relying on generation order. The tests check all four directions across a 3×3 block. A cell biome uses the mean of its four corners and moisture at the cell origin. `TerrainMesh.build` builds one indexed triangle surface with up-facing normals and one UV set for later inspection; it is not used by the game.

The v1 seed-1 radius-2 160×160 preview had a low sea basin, shore bands, grass and forest patches, rocky high areas and a small snowy crest. That run counted sea 5,528, shore 5,158, grass 8,356, forest 5,186, rock 1,337 and snow 35 cells. A v1 32-cell chunk measured about 6–8 ms on local headless Linux; the CI acceptance test checks a median under 20 ms. This is generation time, not a rendered frame time.

## Rivers, erosion and coarse meshes — PROPOSED

The v2 height starts with the same four-octave world-coordinate value noise. One bounded thermal pass compares each sample with its four axial neighbours. For a height difference above the proposed `0.12 m` talus, it transfers `0.08 × (difference − 0.12 m)` from the higher sample toward the lower. The receiver and donor both calculate that transfer from the **same unmodified heights**, so material is deposited at a foot rather than repeatedly moved in place. A one-sample halo provides neighbour values. The result remains in `[-10, 10] m`.

For drainage, each sample chooses its steepest lower neighbour among eight directions, with a fixed direction order for ties. One rain unit starts at every world sample in a six-step halo; each unit follows at most six downhill edges, increasing the local flow accumulation. Samples above sea level with accumulation at least `10` are channels and are carved `0.14 m`. A channel points only to a **lower** channel or sea sample; where none exists it terminates in a proposed local lake. The `river_flow` direction array uses `-1` for those lake endpoints. The bounded footprint is intentionally a prototype approximation of a full watershed; its short headwater channels and single-sample lake endpoints need a later world-scale hydrology pass before gameplay.

The halo is centred on **world coordinates**, so two chunks compute the same thermal transfer, accumulation, carve and river flag on a shared border regardless of which is requested first. Tests compare both heights and channels on every border of a 3×3 block, check downhill flow, and require a channel crossing. River sites appear blue in the colour preview. In the seed-1 radius-2 preview, 1,589 of 25,600 cells show channels and 95 are proposed local lake endpoints; wet shores, grassy/forested middle slopes and rock/snow uplands remain distinguishable. The biome colours are diagram colours, not approved terrain art.

`TerrainMesh.build(chunk, step)` accepts `1`, `2` or `4`. Interior coarse cells use large triangles. Each cell touching the outer boundary retains **every** height sample along that edge and triangulates its perimeter as a fan. This stitches to a full-detail neighbour with coincident boundary vertices, including the corners, without adding skirts below the surface. The LOD test requires every boundary vertex to be referenced and match the full mesh within `1e-6 m`.

On this development host's Windows headless Godot 4.7.2 run, four 32-cell v2 chunks took 13.5–13.9 ms each (sorted middle readings 13.5 and 13.7 ms). The CI check uses a median below 40 ms. These are generation times, not rendered frame times or a cross-platform performance claim.

## Open questions — PROPOSED

- How much elevation should a first land-stage slice expose, and which slopes are passable for each supported body plan?
- Should wet-shore and water biomes preserve a playable aquatic route through every generated region?
- Which cover and threat rules should forest and rock imply before any terrain is wired into gameplay?
- What is the approved streaming radius and memory budget on a lower-spec PC? This prototype only times chunk generation.
