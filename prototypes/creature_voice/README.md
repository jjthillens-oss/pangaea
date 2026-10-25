# Creature voice prototype

**PROPOSED** research prototype. This standalone Godot 4.7.2 project synthesizes creature calls from body traits. It is not wired into the game, and its sound design has not been approved by listening review. All synthesis here is original code; it imports no game audio code, recorded samples, or assets.

The GENESIS Bible §12 treats communication organs as affecting signal modality and range with balancing costs, and §20 calls for original vocal families linked to size, mood and intent. This prototype covers only the sound of a call. It has no communication organ, range or cost model; future critical cues must have a visual equivalent under Bible §19–20.

## Run

```text
godot --headless --path prototypes/creature_voice --script res://tests/run_tests.gd
godot --headless --path prototypes/creature_voice --script res://run.gd -- --seed=42 --traits=mass_kg:40,neck_length_m:0.3,mouth:jaw,diet:carnivore,mood:threat --out=call.wav
godot --headless --path prototypes/creature_voice --script res://run.gd -- --seed=1 --matrix
```

`--matrix` writes 60 WAVs (3 masses × 4 mouths × 5 moods) under the repo's ignored `builds/creature_voice/` directory. Pass `--out=DIR` to put the matrix elsewhere. The matrix is for Joshua to listen to; passing signal tests does not establish that it sounds good. No WAV is committed.

## PROPOSED derivation

The call is 44,100 samples/s, mono, signed 16-bit PCM. Each render uses exactly one `RandomNumberGenerator` with `rng.seed = seed`; every noisy sample consumes that stream. Identical traits and seed yield identical WAV bytes. The five trait keys are required and validated: `mass_kg` 1–10,000; `neck_length_m` 0–10; mouth `beak|jaw|proboscis|none`; diet `herbivore|carnivore|omnivore`; mood `idle|alert|threat|pain|call`.

- Fundamental frequency: `clamp(240 × (mass_kg / 10)^(-0.25), 65, 360)` Hz. The power curve makes a larger body lower without claiming a measured biological law.
- Two spectral emphasis bands: `850 × diet_brightness / (1 + 0.45 × neck_length_m)` and `1800 × diet_brightness / (1 + 0.45 × neck_length_m)` Hz. Diet brightness is 0.92 herbivore, 1.00 omnivore, 1.08 carnivore. Nine voiced harmonics are weighted by Gaussian distance to those bands. A longer neck narrows and lowers their spacing. Diet also changes jaw noise amount.
- Mouth excitation: jaw adds a small noise floor to voiced harmonics; beak adds short differential-noise clicks on the pitch period; proboscis adds a strong second harmonic; no mouth combines low voiced energy with smoothed breath noise. These are sound-design models, not an anatomical simulation.
- Mood: idle lasts 0.35 s at steady pitch; alert lasts 0.48 s and rises from 1.05 to 1.25 times base pitch; threat lasts 0.75 s at 0.82 times base pitch with roughness modulation; pain lasts 0.56 s and descends from 1.35 to 0.68 times base pitch; call lasts 0.93 s in three pulsed syllables with a pitch contour. All durations are within the requested 0.2–1.5 s.

The rendered buffer has its mean removed, a 5 ms linear fade applied at each end, then is normalized below −1 dBFS. The test runner measures pitch from autocorrelation and mouth brightness from a short-window spectral centroid, along with WAV header, finite samples, DC, duration and deterministic bytes.

## Integration questions — PROPOSED

A later creature-stage audio service could select a cue from a `CellAudio`-style event table, request a call for the visible creature's current body and mood, and cache the deterministic WAV by `(seed, traits)`. The prototype does not choose when a creature calls, spatialize sound, mix with music, measure perceived loudness, or handle many simultaneous voices. Formant and mouth rules are intentionally simple; Joshua should judge the 60-file matrix before any game integration or tuning approval.
