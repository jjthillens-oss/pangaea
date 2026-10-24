# Tideleaf marine flora — reference and shape contract

Status: asset production in progress. This prop is a standalone visual study; it is not integrated into a scene or gameplay.

## Reference provenance

| Field | Evidence |
| --- | --- |
| Photo | [Seagrass Laver (*Smithora naiadum*)](https://commons.wikimedia.org/wiki/File:Smithora_naiadum_1.jpg) |
| Photographer | Al Kordesch; 28 June 2017, San Mateo coast |
| Source | [iNaturalist observation 6839717](https://www.inaturalist.org/observations/6839717) |
| License | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/); the Commons file page explicitly marks the photo CC0 and records its license review |
| Reference copy | `reference-smithora-naiadum.jpg`; SHA-256 `A6BD4CCCA0FBEB8205503E43153391302190901E1FE4BEA89B779A572EE15065` |

The photo is used as a morphology and palette reference. No photo pixels, texture patches, traced silhouette, or mesh are used in the exported asset. The photographed organism is a red alga, so the original prop is described as marine flora rather than a vascular seagrass species.

## Observable contract

| Reference observation | Original design criterion | Check |
| --- | --- | --- |
| Thin reddish sheets overlap in a loose cluster | At least eight individually curved, scalloped fronds with clearly varied lengths and angles | Front, side and top gray renders |
| Frond outlines have lobed edges rather than straight strap sides | Rounded, irregular margins; no repeated rectangular cards | Silhouette views at asset and gameplay scale |
| Red-brown color changes across sheet folds | Three muted burgundy/rose PBR materials, broad color blocks; no photo texture | Neutral beauty views and GLB material inspection |
| Low, anchored cluster amid coastal growth | Holdfast attached at the origin, widest fronds spread above it | Side view and Godot import |

Design limits: target height about 1.4 m, footprint under 1.3 m, 100–2000 triangles, opaque export-compatible Principled BSDF materials, no external textures or procedural nodes, and 1 Blender metre = 1 Godot unit. These are proposed prop budgets from the Bible's art guidance; final measured counts belong in `GATES.md` after export.

The shape language follows `docs/art/ART_DIRECTION.md` (soft organic form, readable silhouette and cool habitat palette), and the source/export workflow follows Bible §§15–16. The Spore playthrough notes informed only the need for a legible aquatic/cell-stage prop; the asset uses no Spore design or media.
