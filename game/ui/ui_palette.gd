class_name UiPalette
extends RefCounted
## Colours that the HUD and the pool's drawn cues share (micro-world plan C8), tuned against the
## deep-blue fluid of the microscopic look (docs/DECISIONS.md, "Microscopic world look").

## The keyline: deep navy for the outlines of world labels, the target ring and the starving arrow,
## the edge arrows' badges and the strike lane's edge, so each cue keeps value contrast on the
## fluid and on pale decor. Blue, never black (docs/art/ART_DIRECTION.md).
const KEYLINE := Color("#091229")
