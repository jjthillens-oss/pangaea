class_name AudioSynth
extends RefCounted
## The sound design of the cell stage as code: small signal blocks (oscillators, noise, filters,
## envelopes, bubbles, bells, plucks, voices) and the recipe of every sound effect. The offline
## generator (tools/audio/make_cell_audio.gd) renders these recipes, and the music and ambience
## recipes it adds, into the files in assets/audio/. At runtime CellAudio uses it only to remake
## a threat tell whose length in the data differs from the rendered file, so a growl or hiss still
## ends as the strike starts.
##
## Everything is mono PackedFloat32Array at `rate` Hz unless named stereo (two arrays, L and R).
## Every random draw comes from `rng`, seeded by the caller, so a render is repeatable.

const SFX_RATE := 44100

var rate: int
var rng := RandomNumberGenerator.new()


func _init(p_rate: int = SFX_RATE, seed_value: int = 1) -> void:
	rate = p_rate
	rng.seed = seed_value


# --- Buffers ---------------------------------------------------------------------------------

func silence(length_s: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, int(length_s * rate)))
	out.fill(0.0)
	return out


## Adds `sound` into `into` from `at_s`, scaled by `gain`. Samples past the end are dropped,
## or wrap to the start when `wrap` is set (a seamless loop keeps every tail).
func mix(into: PackedFloat32Array, sound: PackedFloat32Array, at_s: float, gain: float = 1.0, wrap: bool = false) -> void:
	var n := into.size()
	var start := int(at_s * rate)
	if wrap:
		for i in sound.size():
			var j := (start + i) % n
			into[j] += sound[i] * gain
		return
	for i in mini(sound.size(), n - start):
		if start + i >= 0:
			into[start + i] += sound[i] * gain


func scaled(samples: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	for i in out.size():
		out[i] *= gain
	return out


func peak(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for s in samples:
		top = maxf(top, absf(s))
	return top


func normalized(samples: PackedFloat32Array, to_peak: float) -> PackedFloat32Array:
	var top := peak(samples)
	return samples if top <= 0.0 else scaled(samples, to_peak / top)


## Short linear fades at both ends, so a cut never clicks.
func faded(samples: PackedFloat32Array, in_s: float, out_s: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	var n := out.size()
	var a := mini(n, int(in_s * rate))
	var b := mini(n, int(out_s * rate))
	for i in a:
		out[i] *= float(i) / a
	for i in b:
		out[n - 1 - i] *= float(i) / b
	return out


## A gentle tanh saturation: warmth and a soft ceiling.
func saturated(samples: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	var norm := 1.0 / tanh(drive)
	for i in out.size():
		out[i] = tanh(out[i] * drive) * norm
	return out


# --- Sources ---------------------------------------------------------------------------------

func white(length_s: float) -> PackedFloat32Array:
	var out := silence(length_s)
	for i in out.size():
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


## Sine sweeping exponentially from f0 to f1 Hz, with `h2` and `h3` of the 2nd and 3rd harmonic.
func sweep(length_s: float, f0: float, f1: float, h2: float = 0.0, h3: float = 0.0) -> PackedFloat32Array:
	var out := silence(length_s)
	var n := out.size()
	var phase := 0.0
	var ratio := f1 / f0
	for i in n:
		phase += TAU * f0 * pow(ratio, float(i) / n) / rate
		out[i] = sin(phase) + h2 * sin(2.0 * phase) + h3 * sin(3.0 * phase)
	return out


## A buzzy voice source: harmonics 1..`harmonics` falling as 1/n^tilt, pitch gliding from f0 to
## f1 with a little random jitter (`jitter` of the pitch, changing about 12 times a second).
func buzz(length_s: float, f0: float, f1: float, harmonics: int = 14, tilt: float = 1.0, jitter: float = 0.02) -> PackedFloat32Array:
	var out := silence(length_s)
	var n := out.size()
	var phase := 0.0
	var wobble := 0.0
	var target := 0.0
	var amps := PackedFloat32Array()
	for h in harmonics:
		amps.append(1.0 / pow(h + 1.0, tilt))
	for i in n:
		if i % (rate / 12) == 0:
			target = rng.randf_range(-1.0, 1.0)
		wobble += (target - wobble) * 0.002
		var f := f0 * pow(f1 / f0, float(i) / n) * (1.0 + jitter * wobble)
		phase = fmod(phase + TAU * f / rate, TAU * 64.0)
		var s := 0.0
		for h in harmonics:
			if f * (h + 1) < rate * 0.45:
				s += amps[h] * sin(phase * (h + 1))
		out[i] = s
	return out


## A struck glassy bell (two-operator FM): carrier `f`, modulator at `ratio` times it, the
## brightness index falling from `index` with the note.
func bell(length_s: float, f: float, decay_s: float, ratio: float = 3.5, index: float = 2.2) -> PackedFloat32Array:
	var out := silence(length_s)
	var mod_phase := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / rate
		mod_phase += TAU * f * ratio / rate
		phase += TAU * f / rate
		var env := minf(1.0, t / 0.002) * exp(-t / decay_s)
		out[i] = env * sin(phase + index * exp(-t / (decay_s * 0.35)) * sin(mod_phase))
	return out


## A plucked string (Karplus-Strong), soft and woody when `brightness` is low.
func pluck(length_s: float, f: float, decay: float = 0.996, brightness: float = 0.5) -> PackedFloat32Array:
	var out := silence(length_s)
	var period := maxi(2, int(rate / f))
	var ring := PackedFloat32Array()
	ring.resize(period)
	var low := 0.0
	for i in period:
		low = lerpf(low, rng.randf_range(-1.0, 1.0), brightness)
		ring[i] = low
	var at := 0
	for i in out.size():
		var nxt := (at + 1) % period
		var v := ring[at]
		ring[at] = decay * (0.5 * (v + ring[nxt]))
		out[i] = v
		at = nxt
	return faded(out, 0.0, 0.01)


## One rising bubble (after van den Doel's model): a sine at f0 Hz whose pitch climbs as it
## decays; small bubbles are high, short and bright.
func bubble(f0: float, gain: float = 1.0) -> PackedFloat32Array:
	var d := 0.043 * f0 + 0.0014 * pow(f0, 1.5)
	var length_s := minf(0.4, 5.0 / d)
	var out := silence(length_s)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / rate
		phase += TAU * f0 * (1.0 + 0.1 * d * t) / rate
		out[i] = gain * minf(1.0, t / 0.0006) * exp(-d * t) * sin(phase)
	return out


## A burst of `count` bubbles over `length_s` between `f_low` and `f_high` Hz, denser toward
## the start when `front` > 1.
func bubbles(length_s: float, count: int, f_low: float, f_high: float, front: float = 1.0) -> PackedFloat32Array:
	var out := silence(length_s + 0.4)
	for k in count:
		var at := pow(rng.randf(), front) * length_s
		var f := exp(rng.randf_range(log(f_low), log(f_high)))
		mix(out, bubble(f, rng.randf_range(0.3, 1.0)), at)
	return out


# --- Filters and shapes ----------------------------------------------------------------------

## A state-variable band-pass (or low-pass with `low`) whose centre sweeps exponentially from c0
## to c1 Hz, with resonance q (1 is soft, 8 is a sharp ring).
func svf(samples: PackedFloat32Array, c0: float, c1: float, q: float = 1.0, low: bool = false) -> PackedFloat32Array:
	var out := samples.duplicate()
	var n := out.size()
	var lp := 0.0
	var bp := 0.0
	var damp := 1.0 / q
	var ratio := c1 / c0
	for i in n:
		var c := minf(c0 * pow(ratio, float(i) / n), rate * 0.22)
		var g := 2.0 * sin(PI * c / rate)
		var hp := samples[i] - lp - damp * bp
		bp += g * hp
		lp += g * bp
		out[i] = lp if low else bp
	return out


## One-pole low-pass at `cutoff` Hz.
func lowpass(samples: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	for i in out.size():
		y += a * (samples[i] - y)
		out[i] = y
	return out


## One-pole high-pass at `cutoff` Hz.
func highpass(samples: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var low := lowpass(samples, cutoff)
	var out := samples.duplicate()
	for i in out.size():
		out[i] -= low[i]
	return out


## Multiplies by an attack-then-exponential-decay envelope that reaches zero at the end.
func shaped(samples: PackedFloat32Array, attack_s: float, decay_s: float) -> PackedFloat32Array:
	var out := samples.duplicate()
	var n := out.size()
	for i in n:
		var t := float(i) / rate
		out[i] *= minf(1.0, t / maxf(attack_s, 1e-4)) * exp(-t / decay_s) * (1.0 - float(i) / n)
	return out


## Multiplies by a swell from `start` to 1 (power `curve`), with a short attack and a 15 ms tail.
func swelled(samples: PackedFloat32Array, start: float, curve: float, attack_s: float = 0.04) -> PackedFloat32Array:
	var out := samples.duplicate()
	var n := out.size()
	var tail := int(0.015 * rate)
	for i in n:
		var k := float(i) / n
		out[i] *= minf(1.0, float(i) / (attack_s * rate)) * lerpf(start, 1.0, pow(k, curve)) * minf(1.0, float(n - i) / tail)
	return out


## Two resonant formants on a source (a creature's mouth): centres glide from a0 to a1 and from
## b0 to b1 Hz.
func voiced(source: PackedFloat32Array, a0: float, a1: float, b0: float, b1: float, q: float = 5.0) -> PackedFloat32Array:
	var one := svf(source, a0, a1, q)
	var two := svf(source, b0, b1, q)
	var out := source.duplicate()
	for i in out.size():
		out[i] = one[i] + 0.6 * two[i] + 0.05 * source[i]
	return out


# --- Effects (sound effect recipes) ----------------------------------------------------------

## The sound-effect ids and how many variants each has. CellAudio picks a variant at random
## (never the one it just played) and nudges its pitch a little.
const SFX_VARIANTS := {
	"eat_plant": 3, "eat_meat": 3, "refuse": 1, "starve_pulse": 1,
	"notice": 2, "tell_lunge": 1, "tell_puff": 1, "strike": 2, "tell_cancel": 1,
	"bite": 3, "ram": 2, "hurt": 2, "dodged": 2, "creature_die": 2, "player_die": 1, "respawn": 1,
	"region_enter": 1, "region_rare": 1, "grow_warn": 1, "grow": 1, "growth_ring": 1, "now_food": 1,
}
## Seconds a tell sound lasts when the data gives no other length (creatures_m1.json tell_s).
const DEFAULT_TELL_S := 1.2
const SFX_PEAK := 0.89            ## -1 dBFS


## Renders one effect variant (0-based). `length_s` is used by the tells only.
static func render_sfx(id: String, variant: int, length_s: float = DEFAULT_TELL_S) -> PackedFloat32Array:
	var s := AudioSynth.new(SFX_RATE, hash("%s/%d" % [id, variant]))
	var out := s._sfx(id, variant, length_s)
	return s.normalized(s.faded(out, 0.0005, 0.004), SFX_PEAK)


func _sfx(id: String, v: int, length_s: float) -> PackedFloat32Array:
	match id:
		"eat_plant":
			# A soft suck, a rising pop and a small glassy sparkle: the plankton bursts inside.
			var out := silence(0.42)
			var suck := svf(white(0.12), 600.0, 1800.0, 1.5)
			mix(out, swelled(suck, 0.2, 1.5), 0.0, 0.35)
			var pop: float = [900.0, 1050.0, 780.0][v]
			mix(out, bubble(pop, 1.0), 0.085)
			mix(out, bubble(pop * 1.6, 0.5), 0.11)
			var sparkle: float = [2349.3, 2637.0, 2093.0][v]
			mix(out, bell(0.3, sparkle, 0.08, 2.0, 0.8), 0.1, 0.25)
			mix(out, bubbles(0.18, 5, 1800.0, 4200.0, 2.0), 0.11, 0.22)
			return out
		"eat_meat":
			# Two wet chomps: a low thud with a squelch of filtered noise, then a smaller one.
			var out := silence(0.5)
			var first: float = [0.0, 0.0, 0.0][v]
			var gap: float = [0.15, 0.13, 0.17][v]
			mix(out, _chomp(1.0, 105.0 + 10.0 * v), first)
			mix(out, _chomp(0.7, 92.0 + 8.0 * v), first + gap, 0.75)
			mix(out, bubbles(0.25, 4, 300.0, 900.0, 1.5), gap + 0.05, 0.35)
			return out
		"refuse":
			# A muffled glass bonk falling a third: "no".
			var out := silence(0.4)
			var a := lowpass(bell(0.3, 659.3, 0.09, 1.0, 1.2), 1800.0)
			var b := lowpass(bell(0.32, 523.3, 0.11, 1.0, 1.2), 1600.0)
			mix(out, a, 0.0)
			mix(out, b, 0.11, 0.9)
			mix(out, shaped(lowpass(white(0.06), 900.0), 0.002, 0.02), 0.0, 0.4)
			return out
		"starve_pulse":
			# A slow, weak heartbeat: lub-dub.
			var out := silence(0.5)
			mix(out, _thump(0.2, 68.0, 44.0), 0.0)
			mix(out, _thump(0.18, 60.0, 40.0), 0.17, 0.65)
			return lowpass(out, 400.0)
		"notice":
			# A creature's startled chirp and a bright ping: something has seen you.
			var out := silence(0.45)
			var f0: float = [330.0, 370.0][v]
			var voice := voiced(buzz(0.2, f0, f0 * 1.9, 10, 1.1, 0.03), 700.0, 1400.0, 1800.0, 2600.0, 4.0)
			mix(out, swelled(shaped(voice, 0.01, 0.12), 0.6, 1.0, 0.008), 0.0, 0.8)
			mix(out, bell(0.4, [1760.0, 1975.5][v], 0.12, 2.0, 1.4), 0.04, 0.55)
			return out
		"tell_lunge":
			return _growl(length_s)
		"tell_puff":
			return _inflate(length_s)
		"tell_cancel":
			# A tell given up: air let out, a soft falling sigh.
			var out := silence(0.5)
			mix(out, shaped(svf(white(0.45), 1400.0, 300.0, 1.2), 0.01, 0.18), 0.0, 0.7)
			mix(out, shaped(sweep(0.4, 220.0, 120.0, 0.3), 0.01, 0.15), 0.0, 0.4)
			return out
		"strike":
			# The lunge or charge itself: a fast whoosh of displaced water.
			var length := 0.32
			var out := silence(length)
			var rush := svf(white(length), [500.0, 400.0][v], [2600.0, 1800.0][v], 2.0)
			mix(out, swelled(rush, 0.1, 0.6, 0.01), 0.0)
			var tail := shaped(lowpass(white(length), 500.0), 0.03, 0.08)
			mix(out, tail, 0.0, 0.6)
			return faded(out, 0.0, 0.06)
		"bite":
			# A sharp snap of a jaw with a wet tear.
			var out := silence(0.3)
			mix(out, shaped(highpass(white(0.03), 2500.0), 0.0005, 0.006), 0.0, 1.0)
			mix(out, shaped(sweep(0.08, [1900.0, 1700.0, 2100.0][v], 700.0, 0.4), 0.001, 0.02), 0.0, 0.6)
			var tear := svf(white(0.18), 1500.0, 500.0, 2.5)
			mix(out, shaped(tear, 0.005, 0.06), 0.02, 0.7)
			mix(out, _thump(0.12, 160.0, 90.0), 0.0, 0.5)
			return out
		"ram":
			# A heavy jelly body slamming: a deep thud and a wobbling ring.
			var out := silence(0.6)
			mix(out, _thump(0.4, [92.0, 80.0][v], 38.0), 0.0)
			var wobble := sweep(0.45, 210.0, 150.0, 0.3)
			for i in wobble.size():
				var t := float(i) / rate
				wobble[i] *= exp(-t / 0.12) * (0.6 + 0.4 * sin(TAU * 13.0 * t))
			mix(out, wobble, 0.01, 0.45)
			mix(out, shaped(lowpass(white(0.1), 1200.0), 0.001, 0.03), 0.0, 0.6)
			return out
		"hurt":
			# You are hit: a dull thump, a bright sting and a small hurt squeak.
			var out := silence(0.45)
			mix(out, _thump(0.25, 130.0, 60.0), 0.0)
			mix(out, shaped(bell(0.12, [2400.0, 2600.0][v], 0.03, 1.41, 3.0), 0.001, 0.04), 0.0, 0.5)
			var squeak := voiced(buzz(0.22, [520.0, 560.0][v], [380.0, 400.0][v], 10, 1.2, 0.05), 900.0, 650.0, 2200.0, 1800.0, 5.0)
			mix(out, swelled(shaped(squeak, 0.01, 0.1), 1.0, 1.0, 0.01), 0.04, 0.55)
			return out
		"dodged":
			# A clean swish past the strike and a rising sparkle: you got away.
			var out := silence(0.6)
			var swish := svf(white(0.3), 2600.0, 700.0, 2.0)
			mix(out, swelled(swish, 1.0, 1.0, 0.03), 0.0, 0.7)
			var notes: Array = [[1318.5, 1975.5], [1480.0, 2217.5]][v]
			mix(out, bell(0.35, notes[0], 0.09, 2.0, 1.0), 0.12, 0.45)
			mix(out, bell(0.4, notes[1], 0.12, 2.0, 1.0), 0.2, 0.45)
			return out
		"creature_die":
			# A membrane pops and the creature fizzes out, sinking.
			var out := silence(1.0)
			mix(out, shaped(lowpass(white(0.05), 2500.0), 0.0005, 0.012), 0.0, 0.9)
			mix(out, _thump(0.2, 180.0, 70.0), 0.0, 0.6)
			mix(out, shaped(sweep(0.7, [420.0, 380.0][v], 95.0, 0.4), 0.01, 0.25), 0.03, 0.5)
			mix(out, bubbles(0.6, 26, 500.0, 2600.0, 2.2), 0.02, 0.6)
			return out
		"player_die":
			# Your cell gives out: the heartbeat stops, a long falling dissolve and a soft minor chord.
			var out := silence(2.6)
			mix(out, _thump(0.2, 62.0, 40.0), 0.0, 0.9)
			mix(out, _thump(0.18, 55.0, 36.0), 0.2, 0.55)
			mix(out, shaped(sweep(1.6, 330.0, 80.0, 0.4, 0.15), 0.05, 0.7), 0.35, 0.45)
			for k in 3:
				var f: float = [293.66, 349.23, 440.0][k]
				mix(out, shaped(lowpass(sweep(2.2, f, f * 0.94, 0.3), 1400.0), 0.25, 0.9), 0.4 + 0.06 * k, 0.22)
			mix(out, bubbles(1.8, 30, 250.0, 1400.0, 1.6), 0.4, 0.35)
			return out
		"respawn":
			# A new life: rising glass notes and a lift of bubbles.
			var out := silence(1.5)
			var notes := [587.33, 880.0, 1174.66, 1479.98]
			for k in notes.size():
				mix(out, bell(1.0, notes[k], 0.35, 2.0, 1.2), 0.09 * k, 0.4)
			mix(out, bubbles(0.8, 14, 900.0, 3000.0, 0.7), 0.0, 0.3)
			return out
		"region_enter":
			# A quiet three-note sting when you swim into a new region.
			var out := silence(2.2)
			var notes := [880.0, 1318.5, 1174.66]
			for k in notes.size():
				mix(out, bell(1.8, notes[k], 0.6, 2.0, 0.9), 0.16 * k, 0.4)
			return lowpass(out, 5000.0)
		"region_rare":
			# Something huge and rare is near: a slow swell, a wide chord and a shimmer.
			var out := silence(4.0)
			for f in [146.83, 220.0, 277.18, 329.63, 440.0]:
				var tone := lowpass(sweep(3.6, f, f * 1.003, 0.35, 0.12), 1800.0)
				mix(out, swelled(tone, 0.0, 0.7, 0.8), 0.0, 0.18)
			for k in 6:
				mix(out, bell(1.6, [1760.0, 2217.5, 2637.0][k % 3], 0.5, 2.0, 0.8), 1.0 + 0.28 * k, 0.16)
			return faded(out, 0.0, 0.8)
		"grow_warn":
			# The cell is about to grow: a rising shimmer that builds for 1.5 s.
			var out := silence(1.6)
			var shimmer := svf(white(1.5), 800.0, 5000.0, 6.0)
			mix(out, swelled(shimmer, 0.05, 2.0, 0.2), 0.0, 0.5)
			mix(out, swelled(sweep(1.5, 220.0, 440.0, 0.2), 0.0, 1.5, 0.3), 0.0, 0.3)
			return out
		"grow":
			# Growth: a swell into a bright major chord, a deep bloom under it.
			var out := silence(3.0)
			mix(out, _thump(0.5, 70.0, 40.0), 0.0, 0.7)
			for f in [293.66, 440.0, 554.37, 739.99, 880.0]:
				mix(out, shaped(lowpass(sweep(2.8, f, f, 0.3, 0.1), 2600.0), 0.15, 1.1), 0.05, 0.2)
			for k in 4:
				mix(out, bell(1.4, [1174.66, 1479.98, 1760.0, 2349.3][k], 0.45, 2.0, 1.0), 0.1 + 0.07 * k, 0.25)
			mix(out, bubbles(1.2, 24, 600.0, 3500.0, 0.8), 0.0, 0.3)
			return out
		"growth_ring":
			# A big lump of growth: a bubbly two-note chime.
			var out := silence(1.2)
			mix(out, bell(1.0, 1174.66, 0.3, 2.0, 1.0), 0.0, 0.5)
			mix(out, bell(1.0, 1760.0, 0.35, 2.0, 1.0), 0.1, 0.45)
			mix(out, bubbles(0.5, 12, 1200.0, 3500.0, 1.5), 0.0, 0.35)
			return out
		"now_food":
			# A former threat is now small enough to eat: a bright, curious up-down.
			var out := silence(0.8)
			mix(out, bell(0.5, 987.77, 0.15, 2.0, 1.2), 0.0, 0.5)
			mix(out, bell(0.6, 1479.98, 0.2, 2.0, 1.2), 0.1, 0.5)
			mix(out, bell(0.6, 1318.5, 0.2, 2.0, 1.2), 0.22, 0.4)
			return out
	push_error("AudioSynth: unknown sound '%s'" % id)
	return silence(0.1)


## A short low thud: a sine falling from f0 to f1 with a quick attack.
func _thump(length_s: float, f0: float, f1: float) -> PackedFloat32Array:
	return shaped(sweep(length_s, f0, f1, 0.25), 0.002, length_s * 0.3)


## One wet chomp.
func _chomp(gain: float, f: float) -> PackedFloat32Array:
	var out := silence(0.22)
	mix(out, _thump(0.16, f, f * 0.55), 0.0, gain)
	var squelch := svf(white(0.16), 1300.0, 450.0, 3.0)
	for i in squelch.size():
		squelch[i] *= 0.7 + 0.3 * sin(TAU * 38.0 * float(i) / rate)
	mix(out, shaped(squelch, 0.003, 0.045), 0.004, 0.9 * gain)
	mix(out, shaped(highpass(white(0.02), 3000.0), 0.0005, 0.004), 0.0, 0.5 * gain)
	return out


## The ambush hunter's lunge tell: a low throat growl that rises and opens over `length_s` and
## is loudest at its end, which is the strike, with a gurgle under it.
func _growl(length_s: float) -> PackedFloat32Array:
	var src := buzz(length_s, 62.0, 138.0, 22, 0.9, 0.05)
	for i in src.size():
		src[i] *= 0.82 + 0.18 * sin(TAU * lerpf(7.0, 15.0, float(i) / src.size()) * float(i) / rate)
	var out := voiced(src, 320.0, 720.0, 900.0, 1500.0, 4.0)
	out = saturated(out, 1.8)
	var rumble := lowpass(white(length_s), 120.0)
	mix(out, rumble, 0.0, 2.0)
	mix(out, bubbles(length_s * 0.9, int(length_s * 14.0), 180.0, 520.0, 0.6), 0.0, 0.35)
	var shaped_out := swelled(out, 0.25, 1.6, 0.06)
	shaped_out.resize(int(length_s * rate))
	return faded(shaped_out, 0.0, 0.012)


## The rammer's puff tell: water rushing in through a narrowing throat, a rubbery creak, and the
## clicks of its spikes rising toward the end of `length_s`.
func _inflate(length_s: float) -> PackedFloat32Array:
	var n := int(length_s * rate)
	var out := silence(length_s)
	var rush := svf(white(length_s), 280.0, 2400.0, 3.0)
	mix(out, rush, 0.0, 1.0)
	var creak := sweep(length_s, 85.0, 170.0, 0.6, 0.3)
	for i in creak.size():
		var t := float(i) / rate
		creak[i] *= 0.5 + 0.5 * sin(TAU * 21.0 * t + 3.0 * sin(TAU * 2.3 * t))
	mix(out, creak, 0.0, 0.45)
	var clicks := int(length_s * 18.0)
	for k in clicks:
		var at := sqrt(rng.randf()) * length_s * 0.95
		mix(out, shaped(highpass(white(0.008), 2200.0), 0.0003, 0.002), at, rng.randf_range(0.15, 0.4))
	var shaped_out := swelled(out, 0.2, 1.3, 0.08)
	shaped_out.resize(n)
	return faded(shaped_out, 0.0, 0.012)
