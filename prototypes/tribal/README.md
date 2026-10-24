# Tribal village — PROPOSED standalone prototype

This original Godot 4 sketch shows a small village, two workers, food/material gathering, a shelter, and one rival tribe. It is isolated under `prototypes/`; its circles and rectangles are diagnostic placeholders rather than production assets. The [binding Bible](../../docs/bible/GENESIS_Master_Developer_Bible_v0.1.pdf) §9 and the [playthrough observations](../../docs/research/spore/PLAYTHROUGH_VIDEO_NOTES.md) informed the loop; no observed assets, code, or UI were copied.

Run: `godot --path prototypes/tribal`. Keys 1/2 assign food/material, G gathers, B builds shelter, T trades with the neighbor, W warns them, C cancels assignments and R regenerates sites. Run tests: `godot --headless --path prototypes/tribal --script res://tests/run_tests.gd`.

The model makes resource reservations exclusive, releases them on completion/cancel/depletion, conserves exchange stocks and remembers one rival relationship. All amounts and controls are PROPOSED. This is not a production economy, agent navigation, AI opponent, save format, construction preview or rendered accessibility acceptance. Those need separate approved scope and tests.
