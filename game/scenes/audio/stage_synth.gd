class_name StageSynth
extends AudioSynth
## The sound effects of the creature stage (cr_) and the Aquatic stage (aq_) as code, built from
## AudioSynth's signal blocks. tools/audio/make_cell_audio.gd renders them into assets/audio/sfx/
## and StageAudio plays them. Nothing is recorded or sampled, so every sound is original.

## Every effect: how many variants, what it is for and what the player sees with it (Bible 20).
const SFX := {
	# The creature stage.
	"cr_step_paw": {"variants": 3, "purpose": "A padded foot (paw, primate foot) steps on grass: a soft thud and a rustle. Positional.", "visual": "The foot plants and the grass bends"},
	"cr_step_hoof": {"variants": 3, "purpose": "A hoof steps: a hollow knock and a click. Positional.", "visual": "The hoof plants with a puff of dust"},
	"cr_step_claw": {"variants": 3, "purpose": "A clawed foot steps: a thud and the scratch of claws. Positional.", "visual": "The claws dig in as the foot plants"},
	"cr_step_webbed": {"variants": 3, "purpose": "A webbed foot steps: a wet slap. Positional.", "visual": "The webbed foot spreads as it plants"},
	"cr_bite": {"variants": 3, "purpose": "A creature bites: a jaw snap and a crunch. Positional.", "visual": "The bite lunge and the hit number"},
	"cr_hurt": {"variants": 2, "purpose": "Your creature is bitten: a thump and a yelp.", "visual": "Hurt flash and the health bar dropping"},
	"cr_die": {"variants": 1, "purpose": "Your creature dies: a falling groan, a thud and a soft minor chord.", "visual": "The death notice"},
	"cr_eat_fruit": {"variants": 2, "purpose": "Your creature eats fruit: a crisp crunch and a juicy squish.", "visual": "The fruit disappears and the points flash"},
	"cr_eat_meat": {"variants": 2, "purpose": "Your creature eats meat: two heavy chomps.", "visual": "The meat chunk disappears and the points flash"},
	"cr_sing": {"variants": 3, "purpose": "Your creature sings at another: a short three-note call. Positional.", "visual": "The sing and dance pose and the friendship meter"},
	"cr_befriend": {"variants": 1, "purpose": "A creature joins your pack: its answering call and a warm chord.", "visual": "\"Befriended\" notice and the ally marker"},
	"cr_snub": {"variants": 1, "purpose": "A hostile creature snubs your song: a grumpy falling grunt. Positional.", "visual": "\"Snubbed\" notice"},
	"cr_mate": {"variants": 1, "purpose": "Mating at the nest: two voices rising together and a bright arpeggio.", "visual": "The mate call and the editor opening"},
	"cr_part_pickup": {"variants": 1, "purpose": "A new part is found: a rising sparkle and a soft bloom.", "visual": "The part card and its icon"},
	"cr_earn": {"variants": 1, "purpose": "Adaptation points earned for a deed: a small two-note chime.", "visual": "The points flash"},
	"cr_refuse": {"variants": 1, "purpose": "An action is refused: a muffled wooden bonk falling a third.", "visual": "The refusal notice"},
	# The Aquatic stage.
	"aq_burst": {"variants": 2, "purpose": "A burst of speed: a fast water whoosh and a stream of bubbles.", "visual": "The burst trail behind the fish"},
	"aq_pressure_warn": {"variants": 1, "purpose": "Too deep for the body: a deep hull groan and two slow sonar pings, repeated while it lasts.", "visual": "The pressure warning and the darkening edge"},
	"aq_pressure_clear": {"variants": 1, "purpose": "Back within the safe depth: a rising bubble release and a soft bell.", "visual": "The pressure warning clears"},
	"aq_lancer_notice": {"variants": 1, "purpose": "The lancer investigates: echolocation clicks speeding up and a low hum. Positional.", "visual": "The lancer turns toward you"},
	"aq_lancer_pursue": {"variants": 1, "purpose": "The lancer gives chase: a rising rush and a growl. Positional.", "visual": "The lancer's charge and the danger marker"},
	"aq_lancer_gave_up": {"variants": 1, "purpose": "The lancer gives up: a falling whoosh going away. Positional.", "visual": "The lancer turns away"},
	"aq_drifter_warn": {"variants": 1, "purpose": "A drifter is about to sweep: an eerie glassy swell. Positional.", "visual": "The drifter's tendrils glow"},
	"aq_bite": {"variants": 2, "purpose": "Your fish bites: a snap and a muffled crunch underwater. Positional.", "visual": "The bite lunge and the hit number"},
	"aq_hurt": {"variants": 2, "purpose": "Your fish is struck or stung: a muffled thump and a sting.", "visual": "Hurt flash and the health bar dropping"},
	"aq_die": {"variants": 1, "purpose": "Your fish dies: a sinking groan and a fizz of bubbles.", "visual": "The death notice"},
	"aq_eat": {"variants": 2, "purpose": "Your fish eats: a gulp and a burst of bubbles.", "visual": "The food disappears and the points flash"},
	"aq_signal": {"variants": 2, "purpose": "Your fish signals another: a sweeping whale-like call.", "visual": "The signal rings around the fish"},
	"aq_signal_answered": {"variants": 1, "purpose": "A fish answers your signal: a call back and a glassy chime.", "visual": "The rapport meter and the friend notice"},
	"aq_mate": {"variants": 1, "purpose": "Mating: two calls weaving upward and a bright arpeggio.", "visual": "The mate notice and the editor opening"},
	"aq_found": {"variants": 1, "purpose": "A new zone or site is found: a slow, wide three-note sting.", "visual": "The discovery toast"},
	"aq_refuse": {"variants": 1, "purpose": "An action is refused or a signal goes unheard: a muffled glass bonk.", "visual": "The refusal notice"},
}


## Renders one effect variant (0-based), repeatably.
static func render(id: String, variant: int) -> PackedFloat32Array:
	var s := StageSynth.new(SFX_RATE, hash("%s/%d" % [id, variant]))
	var out := s._stage_sfx(id, variant)
	return s.normalized(s.faded(out, 0.0005, 0.004), SFX_PEAK)


func _stage_sfx(id: String, v: int) -> PackedFloat32Array:
	match id:
		"cr_step_paw":
			var out := silence(0.3)
			mix(out, _thump(0.14, [95.0, 85.0, 105.0][v], 55.0), 0.0, 0.9)
			mix(out, shaped(svf(white(0.16), 2600.0, 1800.0, 0.9), 0.004, 0.05), 0.0, 0.35)
			return lowpass(out, 5000.0)
		"cr_step_hoof":
			var out := silence(0.3)
			mix(out, shaped(pluck(0.2, [240.0, 280.0, 210.0][v], 0.985, 0.8), 0.0005, 0.04), 0.0, 0.8)
			mix(out, shaped(highpass(white(0.01), 3000.0), 0.0002, 0.003), 0.0, 0.6)
			mix(out, _thump(0.12, 120.0, 70.0), 0.0, 0.6)
			mix(out, shaped(lowpass(white(0.15), 1200.0), 0.01, 0.05), 0.01, 0.15)
			return out
		"cr_step_claw":
			var out := silence(0.3)
			mix(out, _thump(0.13, [110.0, 100.0, 120.0][v], 60.0), 0.0, 0.8)
			for k in 3:
				var scratch := shaped(svf(white(0.03), 5500.0, 3500.0, 3.0), 0.001, 0.01)
				mix(out, scratch, 0.012 + 0.022 * k + rng.randf_range(0.0, 0.01), 0.35)
			return out
		"cr_step_webbed":
			var out := silence(0.32)
			mix(out, shaped(svf(white(0.12), 1100.0, 380.0, 2.2), 0.001, 0.035), 0.0, 1.0)
			mix(out, _thump(0.1, 90.0, 60.0), 0.0, 0.5)
			mix(out, bubble([700.0, 820.0, 640.0][v], 0.4), 0.04)
			return out
		"cr_bite":
			var out := silence(0.4)
			mix(out, shaped(highpass(white(0.025), 2200.0), 0.0004, 0.006), 0.0, 1.0)
			mix(out, shaped(sweep(0.08, [1500.0, 1300.0, 1700.0][v], 500.0, 0.4), 0.001, 0.02), 0.0, 0.6)
			for k in 4:
				mix(out, shaped(svf(white(0.04), 2400.0, 1200.0, 1.5), 0.001, 0.012), 0.03 + 0.03 * k, 0.5 - 0.08 * k)
			mix(out, _thump(0.16, 140.0, 70.0), 0.0, 0.7)
			return out
		"cr_hurt":
			var out := silence(0.5)
			mix(out, _thump(0.25, 120.0, 55.0), 0.0)
			var yelp := voiced(buzz(0.28, [480.0, 540.0][v], [300.0, 330.0][v], 12, 1.1, 0.05), 900.0, 600.0, 2300.0, 1700.0, 5.0)
			mix(out, swelled(shaped(yelp, 0.008, 0.12), 1.0, 1.0, 0.01), 0.03, 0.6)
			return out
		"cr_die":
			var out := silence(2.6)
			var groan := voiced(buzz(1.4, 180.0, 70.0, 16, 1.0, 0.05), 700.0, 350.0, 1400.0, 900.0, 4.0)
			mix(out, shaped(groan, 0.05, 0.6), 0.0, 0.6)
			mix(out, _thump(0.4, 80.0, 40.0), 0.9, 0.9)
			for k in 3:
				var f: float = [220.0, 261.63, 329.63][k]
				mix(out, shaped(lowpass(sweep(1.8, f, f * 0.97, 0.3), 1300.0), 0.25, 0.8), 1.0 + 0.06 * k, 0.2)
			return out
		"cr_eat_fruit":
			var out := silence(0.45)
			for k in 3:
				mix(out, shaped(svf(white(0.05), 3200.0, 1800.0, 1.2), 0.001, 0.015), 0.04 * k, 0.6 - 0.12 * k)
			mix(out, shaped(svf(white(0.2), 900.0, 500.0, 3.0), 0.01, 0.06), 0.1, 0.6)
			mix(out, bubble([1100.0, 950.0][v], 0.4), 0.16)
			return out
		"cr_eat_meat":
			var out := silence(0.55)
			mix(out, _chomp(1.0, [80.0, 72.0][v]), 0.0)
			mix(out, _chomp(0.75, [70.0, 64.0][v]), [0.18, 0.21][v], 0.8)
			return out
		"cr_sing":
			# A pentatonic phrase, sung on an "ah" opening to "oo", with vibrato.
			var phrases := [[392.0, 440.0, 587.33], [523.25, 440.0, 392.0], [329.63, 392.0, 523.25]]
			return _call(phrases[v], 0.24, 900.0, 1300.0)
		"cr_befriend":
			var out := silence(2.0)
			mix(out, _call([440.0, 523.25, 659.25], 0.2, 950.0, 1400.0), 0.0, 0.8)
			for k in 3:
				mix(out, bell(1.4, [880.0, 1108.73, 1318.51][k], 0.5, 1.0, 0.7), 0.55 + 0.08 * k, 0.3)
			return out
		"cr_snub":
			var out := silence(0.7)
			var grunt := voiced(buzz(0.45, 160.0, 95.0, 18, 0.9, 0.08), 600.0, 400.0, 1100.0, 800.0, 3.0)
			mix(out, saturated(shaped(grunt, 0.02, 0.2), 1.6), 0.0, 0.8)
			return out
		"cr_mate":
			var out := silence(2.6)
			mix(out, _call([392.0, 493.88, 587.33], 0.28, 900.0, 1300.0), 0.0, 0.6)
			mix(out, _call([493.88, 587.33, 739.99], 0.28, 1000.0, 1500.0), 0.12, 0.5)
			var notes := [783.99, 987.77, 1174.66, 1567.98]
			for k in notes.size():
				mix(out, bell(1.2, notes[k], 0.4, 2.0, 1.0), 1.0 + 0.1 * k, 0.3)
			return out
		"cr_part_pickup":
			var out := silence(2.0)
			var notes := [659.25, 830.61, 987.77, 1318.51, 1661.22]
			for k in notes.size():
				mix(out, bell(1.3, notes[k], 0.45, 2.0, 1.1), 0.07 * k, 0.32)
			var shimmer := svf(white(1.2), 3000.0, 7000.0, 5.0)
			mix(out, shaped(shimmer, 0.3, 0.4), 0.1, 0.15)
			for f in [329.63, 415.3, 493.88]:
				mix(out, shaped(lowpass(sweep(1.6, f, f, 0.3), 2000.0), 0.2, 0.6), 0.2, 0.15)
			return out
		"cr_earn":
			var out := silence(0.9)
			mix(out, bell(0.7, 1174.66, 0.2, 2.0, 1.0), 0.0, 0.5)
			mix(out, bell(0.8, 1567.98, 0.25, 2.0, 1.0), 0.09, 0.45)
			return out
		"cr_refuse":
			var out := silence(0.4)
			mix(out, shaped(pluck(0.3, 330.0, 0.97, 0.4), 0.001, 0.08), 0.0, 0.8)
			mix(out, shaped(pluck(0.3, 262.0, 0.97, 0.4), 0.001, 0.09), 0.11, 0.7)
			return lowpass(out, 2500.0)
		"aq_burst":
			var out := silence(0.7)
			var rush := svf(white(0.5), [300.0, 260.0][v], [2400.0, 2000.0][v], 2.0)
			mix(out, swelled(rush, 0.1, 0.5, 0.01), 0.0, 0.9)
			mix(out, bubbles(0.5, 22, 600.0, 2800.0, 0.6), 0.05, 0.5)
			return lowpass(out, 4500.0)
		"aq_pressure_warn":
			var out := silence(1.8)
			var groan := saturated(voiced(buzz(1.4, 42.0, 36.0, 24, 0.8, 0.06), 180.0, 140.0, 420.0, 320.0, 4.0), 1.5)
			mix(out, swelled(groan, 0.2, 1.0, 0.2), 0.0, 0.8)
			mix(out, shaped(lowpass(bell(0.9, 392.0, 0.35, 1.0, 0.6), 1200.0), 0.002, 0.3), 0.2, 0.5)
			mix(out, shaped(lowpass(bell(0.9, 370.0, 0.35, 1.0, 0.6), 1200.0), 0.002, 0.3), 0.85, 0.45)
			return faded(out, 0.0, 0.3)
		"aq_pressure_clear":
			var out := silence(1.4)
			mix(out, bubbles(0.8, 26, 700.0, 3000.0, 0.5), 0.0, 0.5)
			mix(out, bell(1.2, 783.99, 0.4, 1.0, 0.8), 0.15, 0.35)
			mix(out, bell(1.2, 1174.66, 0.4, 1.0, 0.8), 0.3, 0.3)
			return lowpass(out, 4000.0)
		"aq_lancer_notice":
			var out := silence(1.4)
			var at := 0.0
			var gap := 0.16
			while at < 1.1:
				mix(out, shaped(svf(white(0.01), 3500.0, 3500.0, 6.0), 0.0003, 0.003), at, 0.5)
				at += gap
				gap = maxf(0.025, gap * 0.82)
			mix(out, shaped(lowpass(sweep(1.3, 70.0, 85.0, 0.4), 400.0), 0.2, 0.5), 0.0, 0.5)
			return out
		"aq_lancer_pursue":
			var out := silence(1.2)
			mix(out, swelled(svf(white(1.0), 250.0, 1800.0, 2.5), 0.05, 1.5, 0.1), 0.0, 0.8)
			var growl := saturated(voiced(buzz(1.0, 70.0, 120.0, 20, 0.9, 0.05), 300.0, 600.0, 800.0, 1300.0, 4.0), 1.8)
			mix(out, swelled(growl, 0.1, 1.4, 0.1), 0.0, 0.5)
			return faded(lowpass(out, 3500.0), 0.0, 0.08)
		"aq_lancer_gave_up":
			var out := silence(1.4)
			mix(out, shaped(svf(white(1.2), 1600.0, 250.0, 2.0), 0.02, 0.45), 0.0, 0.7)
			mix(out, shaped(lowpass(sweep(1.0, 140.0, 70.0, 0.3), 500.0), 0.02, 0.4), 0.0, 0.3)
			return out
		"aq_drifter_warn":
			var out := silence(1.6)
			for f in [987.77, 1046.5, 1479.98]:
				mix(out, swelled(lowpass(sweep(1.4, f, f * 1.01, 0.1), 3000.0), 0.0, 1.2, 0.3), 0.0, 0.18)
			mix(out, swelled(svf(white(1.4), 2000.0, 4500.0, 6.0), 0.0, 1.5, 0.3), 0.0, 0.2)
			return faded(out, 0.0, 0.15)
		"aq_bite":
			var out := silence(0.35)
			mix(out, shaped(lowpass(white(0.02), 3000.0), 0.0004, 0.006), 0.0, 1.0)
			mix(out, shaped(svf(white(0.15), 1300.0, 450.0, 2.5), 0.004, 0.05), 0.015, 0.7)
			mix(out, _thump(0.14, [150.0, 135.0][v], 80.0), 0.0, 0.6)
			mix(out, bubbles(0.15, 6, 600.0, 1800.0, 2.0), 0.03, 0.3)
			return lowpass(out, 3500.0)
		"aq_hurt":
			var out := silence(0.45)
			mix(out, _thump(0.25, 110.0, 50.0), 0.0)
			mix(out, shaped(bell(0.12, [2200.0, 2400.0][v], 0.03, 1.41, 3.0), 0.001, 0.04), 0.0, 0.4)
			mix(out, bubbles(0.25, 10, 500.0, 2000.0, 2.0), 0.0, 0.4)
			return lowpass(out, 4000.0)
		"aq_die":
			var out := silence(2.6)
			var groan := voiced(buzz(1.6, 140.0, 55.0, 16, 1.0, 0.05), 500.0, 250.0, 1000.0, 600.0, 4.0)
			mix(out, shaped(lowpass(groan, 1200.0), 0.05, 0.7), 0.0, 0.6)
			mix(out, bubbles(2.0, 40, 250.0, 1600.0, 1.4), 0.1, 0.5)
			for k in 3:
				var f: float = [196.0, 233.08, 293.66][k]
				mix(out, shaped(lowpass(sweep(1.8, f, f * 0.96, 0.3), 1000.0), 0.3, 0.8), 0.6 + 0.06 * k, 0.18)
			return out
		"aq_eat":
			var out := silence(0.5)
			mix(out, shaped(svf(white(0.12), 400.0, 1200.0, 2.0), 0.005, 0.05), 0.0, 0.8)
			mix(out, _thump(0.12, [120.0, 105.0][v], 70.0), 0.03, 0.6)
			mix(out, bubbles(0.3, 12, 800.0, 2600.0, 1.5), 0.06, 0.5)
			return lowpass(out, 4000.0)
		"aq_signal":
			var out := silence(1.4)
			var f0: float = [330.0, 392.0][v]
			var call := voiced(buzz(1.0, f0, f0 * 1.5, 10, 1.3, 0.02), 700.0, 1200.0, 1600.0, 2200.0, 4.0)
			for i in call.size():
				call[i] *= 1.0 + 0.25 * sin(TAU * 5.5 * float(i) / rate)
			mix(out, shaped(swelled(call, 0.2, 0.6, 0.08), 0.05, 0.6), 0.0, 0.7)
			return lowpass(out, 3000.0)
		"aq_signal_answered":
			var out := silence(1.8)
			var call := voiced(buzz(0.8, 440.0, 587.33, 10, 1.3, 0.02), 800.0, 1300.0, 1700.0, 2300.0, 4.0)
			mix(out, shaped(swelled(call, 0.2, 0.6, 0.08), 0.05, 0.5), 0.0, 0.6)
			mix(out, bell(1.2, 1174.66, 0.4, 2.0, 0.9), 0.7, 0.3)
			mix(out, bell(1.2, 1760.0, 0.45, 2.0, 0.9), 0.82, 0.25)
			return lowpass(out, 4500.0)
		"aq_mate":
			var out := silence(2.6)
			mix(out, shaped(voiced(buzz(1.0, 330.0, 494.0, 10, 1.3, 0.02), 700.0, 1200.0, 1600.0, 2200.0, 4.0), 0.08, 0.5), 0.0, 0.5)
			mix(out, shaped(voiced(buzz(1.0, 415.0, 659.0, 10, 1.3, 0.02), 800.0, 1300.0, 1700.0, 2300.0, 4.0), 0.08, 0.5), 0.15, 0.45)
			var notes := [659.25, 830.61, 987.77, 1318.51]
			for k in notes.size():
				mix(out, bell(1.2, notes[k], 0.4, 2.0, 1.0), 1.0 + 0.1 * k, 0.3)
			return lowpass(out, 5000.0)
		"aq_found":
			var out := silence(2.8)
			var notes := [587.33, 880.0, 783.99]
			for k in notes.size():
				mix(out, bell(2.2, notes[k], 0.8, 1.0, 0.7), 0.25 * k, 0.35)
			for f in [146.83, 220.0, 293.66]:
				mix(out, swelled(lowpass(sweep(2.4, f, f, 0.3), 1200.0), 0.0, 0.6, 0.6), 0.0, 0.15)
			return faded(lowpass(out, 4000.0), 0.0, 0.6)
		"aq_refuse":
			var out := silence(0.4)
			mix(out, lowpass(bell(0.3, 587.33, 0.09, 1.0, 1.2), 1500.0), 0.0)
			mix(out, lowpass(bell(0.32, 466.16, 0.11, 1.0, 1.2), 1300.0), 0.11, 0.9)
			return out
	push_error("StageSynth: unknown sound '%s'" % id)
	return silence(0.1)


## A sung call: one note per frequency, `note_s` each, gliding between them, on a mouth opening
## from "ah" to "oo" (first formant a0 to a1 Hz), with a vibrato on the held notes.
func _call(notes: Array, note_s: float, a0: float, b0: float) -> PackedFloat32Array:
	var length_s := note_s * notes.size() + 0.1
	var out := silence(length_s + 0.3)
	var n := int(length_s * rate)
	var phase := 0.0
	var src := silence(length_s)
	for i in n:
		var t := float(i) / rate
		var k := mini(int(t / note_s), notes.size() - 1)
		var into := fmod(t, note_s) / note_s
		var f: float = notes[k]
		if k + 1 < notes.size() and into > 0.8:
			f = lerpf(f, float(notes[k + 1]), (into - 0.8) / 0.2)
		f *= 1.0 + 0.012 * sin(TAU * 5.5 * t) * minf(1.0, into * 3.0)
		phase = fmod(phase + TAU * f / rate, TAU * 64.0)
		var v := 0.0
		for h in 10:
			v += sin(phase * (h + 1)) / pow(h + 1.0, 1.2)
		src[i] = v
	var sung := voiced(src, a0, a0 * 0.55, b0, b0 * 0.6, 4.5)
	mix(out, swelled(shaped(sung, 0.03, length_s * 0.8), 0.7, 1.0, 0.03), 0.0)
	return out
