# Terrain chunk prototype — PROPOSED

This is a standalone Godot 4.7.2 research prototype for a possible terrestrial era. It is **PROPOSED** tuning, not a game system or a commitment to a land-stage map. `prototypes/.gdignore` keeps it out of the main game's import. The [terrestrial era proposal](../../docs/proposals/terrestrial-era.md) calls for readable wet-shore, cover, dry-route and refuge choices; these six prototype biomes explore that spatial vocabulary without setting the era's scope.

## Run — PROPOSED

From the repository root:

```text
godot --headless --path prototypes/terrain --script res://tests/run_tests.gd
godot --headless --path prototypes/terrain --script res://run.gd -- --seed=1 --radius=2
```

The runner generates `(2R+1)^2` chunks, prints milliseconds and min/max height for each chunk, prints a biome histogram, and writes an ASCII PPM greyscale preview to ignored `builds/terrain/preview_<seed>.ppm`. `R` is limited to 0–16 so a mistaken argument does not create an unbounded preview. No game scene loads this project.

## Generation — PROPOSED

`TerrainChunk.generate(seed, cx, cz, size=32)` returns `(size+1)^2` float32 height samples, `size^2` byte biome ids, and stored-sample min/max heights. Height uses four octaves of original smooth value noise; moisture uses three independent octaves. Both noise fields use integer lattice hashing and a different fixed seed salt derived from **world seed only**. Each octave doubles frequency and halves weight. Height is in the proposed `[-10, 10]` range. The six id names are sea, shore, grass, forest, rock and snow. Sea and shore are low elevation, snow and rock are high elevation, and moisture chooses forest or grass in the middle. Those bands and scales are prototype tuning only.

All samples are evaluated at integer **world** coordinates `cx * size + local_x`, `cz * size + local_z`. A chunk index never changes the noise seed. Neighbours therefore ask for the same world positions on their shared edge, giving bit-identical float32 values without copying an edge or relying on generation order. The tests check all four directions across a 3×3 block. A cell biome uses the mean of its four corners and moisture at the cell origin. `TerrainMesh.build` builds one indexed triangle surface with up-facing normals and one UV set for later inspection; it is not used by the game.

For seed 1 and radius 2, the 160×160 preview has a low sea basin, shore bands, grass and forest patches, rocky high areas and a small snowy crest. The run counted sea 5,528, shore 5,158, grass 8,356, forest 5,186, rock 1,337 and snow 35 cells. A 32-cell chunk measured about 6–8 ms on local headless Linux; the CI acceptance test checks a median under 20 ms. This is generation time, not a rendered frame time.

## Open questions — PROPOSED

- How much elevation should a first land-stage slice expose, and which slopes are passable for each supported body plan?
- Should wet-shore and water biomes preserve a playable aquatic route through every generated region?
- Which cover and threat rules should forest and rock imply before any terrain is wired into gameplay?
- What is the approved streaming radius and memory budget on a lower-spec PC? This prototype only times chunk generation.
