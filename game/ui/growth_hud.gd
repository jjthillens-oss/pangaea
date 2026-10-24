class_name GrowthHud
extends RefCounted
## What the HUD's growth row shows (S2, s2-view 7.2), worked out from the sim's Growth with no
## state of its own. The meter ring draws a state and a share; the badge names the size; the line
## under them is Growth.hint() itself, so the HUD never words growth state (spine 3.15).
##
## `growth` is anything with Growth's read API (spine 3.7): trigger, armed, meter, calm_ticks,
## blocker, ring(n), is_full(n), at_top(n, max_in_build). Null means no growth (the M1 pool, D-46).
##
##   none     no growth: the row is hidden
##   filling  the ring is not full (or full and waiting for its showcase window): plain
##   growing  full and calm, in auto, or in press mode once G is pressed: the ring pulses
##   blocked  full, and something keeps the cell from being calm: the track gets a cream outline
##   ready    full in press mode, waiting for G: the track gets a cream outline
##   top      full at the build's top size; not reached, since the top pays out at once (D-32)

const STATES: PackedStringArray = ["none", "filling", "growing", "blocked", "ready", "top"]


static func state_of(growth: Object, n: int, max_in_build: int) -> String:
	if growth == null:
		return "none"
	if not growth.is_full(n):
		return "filling"
	if growth.at_top(n, max_in_build):
		return "top"
	if growth.blocker != "":
		return "blocked"
	if growth.calm_ticks > 0 and (growth.trigger == "auto" or growth.armed):
		return "growing"
	if growth.trigger == "press" and not growth.armed:
		return "ready"
	return "filling"


## How full the ring of size n is, 0 to 1 (0 with no growth, or at a size with no ring).
static func share_of(growth: Object, n: int) -> float:
	if growth == null:
		return 0.0
	var ring: float = growth.ring(n)
	return clampf(growth.meter / ring, 0.0, 1.0) if ring > 0.0 else 0.0


## The growth line: Growth.hint() as it is, "" with no growth. Until the sim words its hint (T2.3)
## a Growth without hint() shows no line.
static func hint_of(growth: Object) -> String:
	if growth == null or not growth.has_method(&"hint"):
		return ""
	return growth.hint()


## "Size 2 · about 32 µm", from the ladder's labels (world_cell.json ladder.labels); "Size 2" when
## the labels do not reach that size.
static func badge_text(n: int, labels: Array) -> String:
	if n >= 1 and n <= labels.size():
		return TranslationServer.translate("UI_SIZE_D_S_819246") % [n, labels[n - 1]]
	return TranslationServer.translate("UI_SIZE_D_FE2755") % n


## The toast when the ring pays out at the build's top (D-32).
static func ring_paid_text(points: int) -> String:
	return TranslationServer.translate("UI_RING_FULL_ENERGY_REFILLED_D_POINT_S_63C31A") % [points, "" if points == 1 else "s"]


## The hint with its literal "(G)" naming the key bound to grow now (BP-19): Growth.hint() keeps
## "(G)" and the player may rebind it. `key` "" leaves the line as it is.
static func with_grow_key(hint: String, key: String) -> String:
	return hint.replace("(G)", "(%s)" % key) if key != "" else hint
