class_name MeterRing
extends Control
## The growth meter (S2, s2-view 7.2): a ring that fills clockwise from the top as the meter fills,
## with the cell's size in its middle. The HUD sets what it shows each frame through show_ring();
## this node only draws and animates.
##
##   track    a dark ring (the keyline at 0.6) under the fill; a cream outline round it when the
##            state is "blocked" or "ready", so the waiting ring has a shape cue, not a colour alone
##   fill     cream, from the top clockwise, by share
##   growing  the whole ring pulses 1.0 to 1.06 at 1.5 Hz (held still under reduce flashing)
##   flash()  its glow brightens for FLASH_S (a meter lump, a discovery)
##   sweep()  after a payout at the top, the fill runs from full to empty over SWEEP_S

const RADIUS := 19.0
const WIDTH := 5.0
const OUTLINE_W := 1.5
const FONT_SIZE := 18
const CREAM := Color("#F4EAD2")
const TRACK_ALPHA := 0.6
const PULSE_HZ := 1.5
const PULSE_GROW := 0.06
const FLASH_S := 0.6
const FLASH_W := 11.0
const FLASH_ALPHA := 0.45
const SWEEP_S := 0.6
const SEGMENTS := 48
const OUTLINED: PackedStringArray = ["blocked", "ready"]

var share := 0.0
var size_n := 1
var state := "filling"
## Reduce flashing (settings): no pulse.
var reduce_flashing := false

var _pulse_t := 0.0
var _flash_t := 0.0
var _sweep_t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(44.0, 44.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## What to draw: the meter's share, the size shown and GrowthHud's state.
func show_ring(p_share: float, n: int, p_state: String) -> void:
	if is_equal_approx(p_share, share) and n == size_n and p_state == state:
		return
	share = clampf(p_share, 0.0, 1.0)
	size_n = n
	state = p_state
	if state != "growing":
		_pulse_t = 0.0
	queue_redraw()


func flash() -> void:
	_flash_t = FLASH_S
	queue_redraw()


func sweep() -> void:
	_sweep_t = SWEEP_S
	queue_redraw()


## The fill drawn now: the sweep's share while it runs, else the meter's.
func shown_share() -> float:
	return _sweep_t / SWEEP_S if _sweep_t > 0.0 else share


## The glow flash left now, 1 at a flash down to 0.
func glow() -> float:
	return _flash_t / FLASH_S


## The pulse's scale now (1.0 unless the ring is growing).
func pulse_scale() -> float:
	if state != "growing" or reduce_flashing:
		return 1.0
	return 1.0 + PULSE_GROW * (0.5 - 0.5 * cos(_pulse_t * PULSE_HZ * TAU))


## True while the outline shows (the waiting states).
func outlined() -> bool:
	return state in OUTLINED


func _process(delta: float) -> void:
	var redraw := _flash_t > 0.0 or _sweep_t > 0.0
	_flash_t = maxf(_flash_t - delta, 0.0)
	_sweep_t = maxf(_sweep_t - delta, 0.0)
	if state == "growing":
		_pulse_t = fmod(_pulse_t + delta, 1.0 / PULSE_HZ)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * pulse_scale()
	if redraw:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if _flash_t > 0.0:
		draw_arc(c, RADIUS, 0.0, TAU, SEGMENTS, Color(CREAM, FLASH_ALPHA * _flash_t / FLASH_S), FLASH_W, true)
	draw_arc(c, RADIUS, 0.0, TAU, SEGMENTS, Color(UiPalette.KEYLINE, TRACK_ALPHA), WIDTH, true)
	if outlined():
		for r in [RADIUS - WIDTH * 0.5 - OUTLINE_W * 0.5, RADIUS + WIDTH * 0.5 + OUTLINE_W * 0.5]:
			draw_arc(c, r, 0.0, TAU, SEGMENTS, CREAM, OUTLINE_W, true)
	var fill := shown_share()
	if fill > 0.0:
		var start := -PI * 0.5
		draw_arc(c, RADIUS, start, start + TAU * fill, maxi(2, ceili(SEGMENTS * fill)), CREAM, WIDTH, true)
	var font := get_theme_font(&"font", &"Label")
	var text := str(size_n)
	var ascent := font.get_ascent(FONT_SIZE)
	var height := font.get_height(FONT_SIZE)
	draw_string(font, Vector2(0.0, c.y + ascent - height * 0.5), text, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		FONT_SIZE, get_theme_color(&"font_color", &"Label"))
