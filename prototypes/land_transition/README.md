# Shoreline handoff — PROPOSED standalone prototype

This original, isolated Godot 4 sketch tests a cell **lineage** crawling from an aquatic shoreline into a creature editor. It deliberately retains the Bible's intervening Aquatic era; it is not a direct Microscopic → Terrestrial production transition. No production scene, save, art or editor is imported. Shapes are diagnostic placeholders, not production assets.

Run: `godot --path prototypes/land_transition`. Move with left/right, rest with down, and press Enter at dry ground to open and commit the simple support editor. R resets. Run tests: `godot --headless --path prototypes/land_transition --script res://tests/run_tests.gd`.

The model bounds crawl distance by stamina and support, records shoreline contact, gates the editor, and preserves lineage/feeding ancestry. Its quantities and entry gate are PROPOSED. It does not model a real swimming habitat, serialize state, provide a production creature editor, or verify visuals/accessibility. The [Bible](../../docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf) §§4, 6–7, 18 and [playthrough observations](../../docs/research/spore/PLAYTHROUGH_VIDEO_NOTES.md) informed the loop; no observed code or assets were copied. A production handoff needs approved trait mapping, save checkpoint and migration, anatomy validation, rendered movement checks, and an accessible input review.
